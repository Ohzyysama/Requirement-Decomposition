// PaletteExtractor.ets
// HarmonyOS equivalent of Android's MediaNotificationProcessor (Palette-based).
// Directly mirrors the algorithm from AOSP's
//   frameworks/base/packages/SystemUI/src/com/android/systemui/media/MediaNotificationProcessor
// which is the basis of mkaflowski/Media-Style-Palette used by Salt Player.
//
// Core API:
//   PaletteExtractor.extract(pixelMap) → { backgroundColor, primaryTextColor, isLight }
//
// Algorithm (matches Android exactly):
//   1. Downscale bitmap to ~150x150 area
//   2. Build quantized swatches from the downsampled pixels
//   3. backgroundColor = findBackgroundColorAndFilter(swatches):
//      - pick largest-population swatch (NO filter)
//      - if it's not white/black, use it
//      - otherwise, among swatches whose population >= largest/2.5 AND that are not
//        white/black, pick the most saturated one
//      - fallback: white
//   4. isLight = relativeLuminance(backgroundColor) > 0.5
//   5. primaryTextColor = selectForegroundColor(backgroundColor, swatches):
//      - candidate = selectVibrantCandidate / selectMutedCandidate
//      - if candidate has enough population (≥ 1% of dominant), use it
//      - else if dominant has enough saturation, use dominant
//      - else use fallback (BLACK for light bg, WHITE for dark bg)
//   6. ensureColors: if contrast < 4.5, findContrastColor by lightness adjustment

import { image } from '@kit.ImageKit'

// ==================== Public Result Interface ====================

export interface MediaColorResult {
  backgroundColor: string    // '#ffRRGGBB' dominant cover color
  primaryTextColor: string   // '#ffRRGGBB' high-contrast text color
  isLight: boolean           // relativeLuminance(backgroundColor) > 0.5
}

// ==================== Algorithm Constants (match AOSP MediaNotificationProcessor) ====================

const RESIZE_BITMAP_AREA: number = 150 * 150
const BLACK_MAX_LIGHTNESS: number = 0.08
const WHITE_MIN_LIGHTNESS: number = 0.90
const POPULATION_FRACTION_FOR_WHITE_OR_BLACK: number = 2.5
const POPULATION_FRACTION_FOR_DOMINANT: number = 0.01
const POPULATION_FRACTION_FOR_MORE_VIBRANT: number = 1.0
const MIN_SATURATION_WHEN_DECIDING: number = 0.19
const MIN_CONTRAST_RATIO: number = 4.5

// ==================== Internal Types ====================

interface ColorBucket {
  count: number
  rSum: number
  gSum: number
  bSum: number
}

// Swatch: mirrors androidx.palette.graphics.Palette.Swatch
class Swatch {
  r: number = 0
  g: number = 0
  b: number = 0
  h: number = 0
  s: number = 0
  l: number = 0
  population: number = 0
}

interface ColorRgb {
  r: number
  g: number
  b: number
}

interface LabColor {
  L: number
  a: number
  b: number
}

// ==================== PaletteExtractor ====================

export class PaletteExtractor {

  /**
   * Extract MediaNotificationProcessor-equivalent colors from a PixelMap.
   * Returns { backgroundColor, primaryTextColor, isLight }.
   */
  static async extract(pixelMap: image.PixelMap): Promise<MediaColorResult> {
    const DEFAULT_RESULT: MediaColorResult = {
      backgroundColor: '#ffffffff',
      primaryTextColor: '#ff000000',
      isLight: true
    }

    const info = await pixelMap.getImageInfo()
    const width = info.size.width
    const height = info.size.height
    const totalPixels = width * height
    if (totalPixels === 0) {
      return DEFAULT_RESULT
    }

    // Read all pixels (RGBA_8888 = 4 bytes/pixel)
    const bufferSize = totalPixels * 4
    const buffer = new ArrayBuffer(bufferSize)
    await pixelMap.readPixelsToBuffer(buffer)
    const pixels = new Uint8Array(buffer)
    const isBGRA = info.pixelFormat === image.PixelMapFormat.BGRA_8888

    // Downscale to ~150x150 area (Android resizeBitmapArea)
    const area = totalPixels
    const scale = area > RESIZE_BITMAP_AREA ? Math.sqrt(RESIZE_BITMAP_AREA / area) : 1
    const targetPixels = Math.max(1, Math.floor(area * scale * scale))
    const stride = Math.max(1, Math.floor(area / targetPixels))

    // Build quantized histogram (4-bit per channel = 4096 buckets)
    const buckets = new Map<number, ColorBucket>()

    for (let i = 0; i < totalPixels; i += stride) {
      const offset = i * 4
      const a = pixels[offset + 3]
      if (a < 125) continue

      let r: number, g: number, b: number
      if (isBGRA) {
        b = pixels[offset]
        g = pixels[offset + 1]
        r = pixels[offset + 2]
      } else {
        r = pixels[offset]
        g = pixels[offset + 1]
        b = pixels[offset + 2]
      }

      const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
      const existing = buckets.get(key)
      if (existing) {
        existing.count++
        existing.rSum += r
        existing.gSum += g
        existing.bSum += b
      } else {
        buckets.set(key, { count: 1, rSum: r, gSum: g, bSum: b })
      }
    }

    if (buckets.size === 0) {
      return DEFAULT_RESULT
    }

    // Convert to Swatch objects
    const swatches: Swatch[] = []
    buckets.forEach((bucket) => {
      const sw = new Swatch()
      sw.r = Math.round(bucket.rSum / bucket.count)
      sw.g = Math.round(bucket.gSum / bucket.count)
      sw.b = Math.round(bucket.bSum / bucket.count)
      const hsl = PaletteExtractor.rgbToHsl(sw.r, sw.g, sw.b)
      sw.h = hsl[0]
      sw.s = hsl[1]
      sw.l = hsl[2]
      sw.population = bucket.count
      swatches.push(sw)
    })

    // Step 1: Find backgroundColor (match AOSP findBackgroundColorAndFilter)
    const bgSwatch = PaletteExtractor.findBackgroundSwatch(swatches)
    const backgroundColor = PaletteExtractor.hexFromRgb(bgSwatch.r, bgSwatch.g, bgSwatch.b)
    const bgLum = PaletteExtractor.relativeLuminance(bgSwatch.r, bgSwatch.g, bgSwatch.b)
    const isLight = bgLum > 0.5

    // Step 2: Find dominant among non-white/non-black (for foreground selection)
    const dominantSwatch = PaletteExtractor.findDominantExcludingWhiteBlack(swatches)

    // Step 3: Select foreground color (match AOSP selectForegroundColor)
    let mainColor = PaletteExtractor.selectForegroundColor(bgSwatch, swatches, dominantSwatch)

    // Step 4: Build optimal foreground
    let primaryTextColor: string
    if (isLight) {
      const fgRgb = PaletteExtractor.parseHexColor(mainColor)
      const bgRgb: ColorRgb = { r: bgSwatch.r, g: bgSwatch.g, b: bgSwatch.b }
      const resultRgb = PaletteExtractor.buildOptimalForegroundLight(fgRgb, bgRgb, dominantSwatch, MIN_CONTRAST_RATIO)
      primaryTextColor = PaletteExtractor.hexFromRgb(resultRgb.r, resultRgb.g, resultRgb.b)
    } else {
      primaryTextColor = PaletteExtractor.ensureContrast(mainColor, backgroundColor, isLight)
    }

    return { backgroundColor, primaryTextColor, isLight }
  }

  // ==================== findBackgroundColorAndFilter ====================
  // AOSP algorithm:
  // 1. Find the most populated swatch (no filter).
  // 2. If it's not white/black, use it.
  // 3. Otherwise, among all non-white/non-black swatches whose population is at
  //    least (maxPopulation / POPULATION_FRACTION_FOR_WHITE_OR_BLACK), pick the
  //    one with the highest saturation.
  // 4. Fallback to the original dominant if nothing qualifies.
  private static findBackgroundSwatch(swatches: Swatch[]): Swatch {
    // Find overall dominant
    let dominant: Swatch = swatches[0]
    for (const sw of swatches) {
      if (sw.population > dominant.population) dominant = sw
    }

    // If dominant is not white/black, return it
    if (!PaletteExtractor.isWhiteOrBlack(dominant)) {
      return dominant
    }

    // Otherwise search for a highly saturated non-white/black color
    const maxPop = dominant.population
    const threshold = maxPop / POPULATION_FRACTION_FOR_WHITE_OR_BLACK
    let bestNonNeutral: Swatch | undefined = undefined
    let bestSaturation = -1

    for (const sw of swatches) {
      if (PaletteExtractor.isWhiteOrBlack(sw)) continue
      if (sw.population < threshold) continue
      if (sw.s > bestSaturation) {
        bestSaturation = sw.s
        bestNonNeutral = sw
      }
    }

    return bestNonNeutral ?? dominant
  }

  private static findDominantExcludingWhiteBlack(swatches: Swatch[]): Swatch {
    let dominant: Swatch | undefined = undefined
    for (const sw of swatches) {
      if (PaletteExtractor.isWhiteOrBlack(sw)) continue
      if (!dominant || sw.population > dominant.population) {
        dominant = sw
      }
    }
    if (dominant) return dominant
    // Fallback to overall dominant
    let overall: Swatch = swatches[0]
    for (const sw of swatches) {
      if (sw.population > overall.population) overall = sw
    }
    return overall
  }

  // ==================== Swatch classification ====================
  // Matches AOSP Target definitions (androidx.palette.graphics.Target)

  // Vibrant: L∈[0.30, 0.70], S∈[0.35, 1.00]
  private static isVibrant(sw: Swatch): boolean {
    return sw.l >= 0.30 && sw.l <= 0.70 && sw.s >= 0.35
  }
  // Light Vibrant: L∈[0.55, 1.00], S∈[0.35, 1.00]
  private static isLightVibrant(sw: Swatch): boolean {
    return sw.l >= 0.55 && sw.s >= 0.35
  }
  // Dark Vibrant: L∈[0.00, 0.45], S∈[0.35, 1.00]
  private static isDarkVibrant(sw: Swatch): boolean {
    return sw.l <= 0.45 && sw.s >= 0.35
  }
  // Muted: L∈[0.30, 0.70], S∈[0.00, 0.40]
  private static isMuted(sw: Swatch): boolean {
    return sw.l >= 0.30 && sw.l <= 0.70 && sw.s <= 0.40
  }
  // Light Muted
  private static isLightMuted(sw: Swatch): boolean {
    return sw.l >= 0.55 && sw.s <= 0.40
  }
  // Dark Muted
  private static isDarkMuted(sw: Swatch): boolean {
    return sw.l <= 0.45 && sw.s <= 0.40
  }

  private static isWhiteOrBlack(sw: Swatch): boolean {
    return sw.l > WHITE_MIN_LIGHTNESS || sw.l < BLACK_MAX_LIGHTNESS
  }

  private static findBestSwatchByTarget(
    swatches: Swatch[],
    predicate: (sw: Swatch) => boolean,
    targetL: number,
    targetS: number
  ): Swatch | undefined {
    let best: Swatch | undefined = undefined
    let maxPop = 0
    for (const sw of swatches) {
      if (sw.population > maxPop) maxPop = sw.population
    }
    if (maxPop === 0) return undefined

    let bestScore = -1
    for (const sw of swatches) {
      if (!predicate(sw)) continue
      const satScore = 1 - Math.abs(sw.s - targetS)
      const lumScore = 1 - Math.abs(sw.l - targetL)
      const popScore = sw.population / maxPop
      const score = satScore * 0.24 + lumScore * 0.52 + popScore * 0.24
      if (score > bestScore) {
        bestScore = score
        best = sw
      }
    }
    return best
  }

  // ==================== selectForegroundColor (AOSP match) ====================

  private static selectForegroundColor(bgSwatch: Swatch, swatches: Swatch[], dominantSwatch: Swatch): string {
    const bgLum = PaletteExtractor.relativeLuminance(bgSwatch.r, bgSwatch.g, bgSwatch.b)
    const isLight = bgLum > 0.5

    let moreVibrant: Swatch | undefined
    let vibrant: Swatch | undefined
    let moreMuted: Swatch | undefined
    let muted: Swatch | undefined
    let fallbackR: number, fallbackG: number, fallbackB: number

    if (isLight) {
      // Light bg: prefer darker colors
      moreVibrant = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isDarkVibrant, 0.26, 1.00)
      vibrant = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isVibrant, 0.50, 1.00)
      moreMuted = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isDarkMuted, 0.26, 0.30)
      muted = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isMuted, 0.50, 0.30)
      fallbackR = 0; fallbackG = 0; fallbackB = 0
    } else {
      // Dark bg: prefer lighter colors
      moreVibrant = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isLightVibrant, 0.74, 1.00)
      vibrant = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isVibrant, 0.50, 1.00)
      moreMuted = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isLightMuted, 0.74, 0.30)
      muted = PaletteExtractor.findBestSwatchByTarget(swatches, PaletteExtractor.isMuted, 0.50, 0.30)
      fallbackR = 255; fallbackG = 255; fallbackB = 255
    }

    // Select vibrant candidate: prefer moreVibrant if it has enough population relative to vibrant
    let colored = PaletteExtractor.selectCandidate(moreVibrant, vibrant)
    if (!colored) {
      colored = PaletteExtractor.selectCandidate(muted, moreMuted)
    }

    if (colored) {
      if (dominantSwatch === colored) {
        return PaletteExtractor.hexFromRgb(colored.r, colored.g, colored.b)
      }
      const ratio = dominantSwatch.population > 0
        ? colored.population / dominantSwatch.population
        : 0
      if (ratio < POPULATION_FRACTION_FOR_DOMINANT
          && dominantSwatch.s > MIN_SATURATION_WHEN_DECIDING) {
        return PaletteExtractor.hexFromRgb(dominantSwatch.r, dominantSwatch.g, dominantSwatch.b)
      }
      return PaletteExtractor.hexFromRgb(colored.r, colored.g, colored.b)
    }

    // No colored candidate — use dominant if it's meaningful
    if (PaletteExtractor.hasEnoughPopulation(dominantSwatch, swatches)) {
      return PaletteExtractor.hexFromRgb(dominantSwatch.r, dominantSwatch.g, dominantSwatch.b)
    }

    return PaletteExtractor.hexFromRgb(fallbackR, fallbackG, fallbackB)
  }

  // Choose the more vibrant one if it has enough population relative to the less vibrant
  private static selectCandidate(moreVibrant: Swatch | undefined, lessVibrant: Swatch | undefined): Swatch | undefined {
    if (moreVibrant && lessVibrant) {
      const ratio = lessVibrant.population > 0
        ? moreVibrant.population / lessVibrant.population
        : 0
      if (ratio < POPULATION_FRACTION_FOR_MORE_VIBRANT) {
        return lessVibrant
      }
      return moreVibrant
    }
    return moreVibrant ?? lessVibrant
  }

  private static hasEnoughPopulation(sw: Swatch, allSwatches: Swatch[]): boolean {
    let total = 0
    for (const s of allSwatches) total += s.population
    if (total === 0) return false
    return sw.population / total >= POPULATION_FRACTION_FOR_DOMINANT
  }

  // ==================== ensureColors (contrast adjustment) ====================
  // Iteratively adjust lightness until contrast ratio ≥ 4.5 with background.
  private static ensureContrast(fgHex: string, bgHex: string, isLightBg: boolean): string {
    const fg = PaletteExtractor.parseHexColor(fgHex)
    const bg = PaletteExtractor.parseHexColor(bgHex)

    const contrast = PaletteExtractor.contrastRatio(
      PaletteExtractor.relativeLuminance(fg.r, fg.g, fg.b),
      PaletteExtractor.relativeLuminance(bg.r, bg.g, bg.b)
    )
    if (contrast >= MIN_CONTRAST_RATIO) {
      return fgHex
    }

    return PaletteExtractor.findContrastColor(fg, bg, isLightBg, MIN_CONTRAST_RATIO)
  }

  // Binary-search LAB lightness until contrast ≥ minContrast
  // (matches NotificationColorUtil.findContrastColor / findContrastColorAgainstDark)
  private static findContrastColor(
    fg: ColorRgb,
    bg: ColorRgb,
    isLightBg: boolean,
    minContrast: number
  ): string {
    const bgLum = PaletteExtractor.relativeLuminance(bg.r, bg.g, bg.b)
    const fgLab = PaletteExtractor.rgbToLab(fg.r, fg.g, fg.b)

    // For light bg, decrease L; for dark bg, increase L
    let low: number, high: number
    if (isLightBg) {
      low = 0   // darkest possible
      high = fgLab.L
    } else {
      low = fgLab.L
      high = 100  // lightest possible
    }

    // Binary search for minimum adjustment that meets the contrast threshold
    let a = fgLab.a
    let bLab = fgLab.b
    let resultRgb: ColorRgb = fg

    for (let i = 0; i < 15; i++) {
      const mid = (low + high) / 2
      const candidate = PaletteExtractor.labToRgb(mid, a, bLab)
      const candLum = PaletteExtractor.relativeLuminance(candidate.r, candidate.g, candidate.b)
      const contrast = PaletteExtractor.contrastRatio(candLum, bgLum)

      if (contrast >= minContrast) {
        resultRgb = candidate
        if (isLightBg) {
          low = mid   // darker is fine, try lighter
        } else {
          high = mid  // lighter is fine, try darker
        }
      } else {
        if (isLightBg) {
          high = mid  // need darker
        } else {
          low = mid   // need lighter
        }
      }
    }

    return PaletteExtractor.hexFromRgb(resultRgb.r, resultRgb.g, resultRgb.b)
  }

  // ==================== Light Mode Foreground Optimizer ====================

  /**
   * Build an optimal foreground color for light-mode backgrounds.
   * Constraints:
   *   - Saturation ∈ [0.30, 0.60]  (not gray, not oversaturated)
   *   - Lightness  ∈ [0.12, 0.30]  (dark enough for contrast, not pitch-black)
   *   - Contrast ratio ≥ minContrast
   *   - Hue inherits from cover palette (keeps color association)
   */
  private static buildOptimalForegroundLight(
    baseFg: ColorRgb,
    bg: ColorRgb,
    dominant: Swatch,
    minContrast: number
  ): ColorRgb {
    const baseHsl = PaletteExtractor.rgbToHsl(baseFg.r, baseFg.g, baseFg.b)
    const bgHsl = PaletteExtractor.rgbToHsl(bg.r, bg.g, bg.b)
    const domHsl = PaletteExtractor.rgbToHsl(dominant.r, dominant.g, dominant.b)

    const MIN_L = 0.12
    const MAX_L = 0.30
    const MIN_S = 0.30
    const MAX_S = 0.60
    const DEFAULT_HUE = 225

    // 1. Hue inheritance chain
    let h: number
    if (baseHsl[1] >= 0.18) {
      h = baseHsl[0]
    } else if (domHsl[1] >= 0.15) {
      h = domHsl[0]
    } else if (bgHsl[1] >= 0.10) {
      h = bgHsl[0]
    } else {
      h = DEFAULT_HUE
    }

    // 2. Saturation with hard bounds
    let s: number
    if (baseHsl[1] >= MIN_S) {
      s = baseHsl[1]
    } else if (domHsl[1] >= MIN_S) {
      s = domHsl[1] * 0.85
    } else if (bgHsl[1] >= 0.15) {
      s = bgHsl[1] * 0.75
    } else {
      s = MIN_S
    }
    s = Math.min(Math.max(s, MIN_S), MAX_S)

    // 3. Lightness: search from MAX_L downward for the brightest value
    //    that still meets contrast. Avoids crushing to near-black.
    const bgLum = PaletteExtractor.relativeLuminance(bg.r, bg.g, bg.b)
    let bestRgb: ColorRgb = { r: 0, g: 0, b: 0 }
    let found = false

    for (let l = MAX_L; l >= MIN_L; l -= 0.015) {
      const rgb = PaletteExtractor.hslToRgb(h, s, l)
      const lum = PaletteExtractor.relativeLuminance(rgb.r, rgb.g, rgb.b)
      const c = PaletteExtractor.contrastRatio(lum, bgLum)
      if (c >= minContrast) {
        bestRgb = rgb
        found = true
        break
      }
    }

    if (!found) {
      bestRgb = PaletteExtractor.hslToRgb(h, s, MIN_L)
    }

    return bestRgb
  }

  // ==================== Color Math Helpers ====================

  static rgbToHsl(r: number, g: number, b: number): number[] {
    const rf = r / 255, gf = g / 255, bf = b / 255
    const max = Math.max(rf, gf, bf)
    const min = Math.min(rf, gf, bf)
    const l = (max + min) / 2
    let h = 0, s = 0

    if (max !== min) {
      const d = max - min
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
      if (max === rf) {
        h = ((gf - bf) / d + (gf < bf ? 6 : 0)) * 60
      } else if (max === gf) {
        h = ((bf - rf) / d + 2) * 60
      } else {
        h = ((rf - gf) / d + 4) * 60
      }
    }
    return [h, s, l]
  }

  private static hslToRgb(h: number, s: number, l: number): ColorRgb {
    const c = (1 - Math.abs(2 * l - 1)) * s
    const hh = h / 60
    const x = c * (1 - Math.abs((hh % 2) - 1))
    const m = l - c / 2

    let r = 0, g = 0, b = 0
    if (h < 60) { r = c; g = x; b = 0 }
    else if (h < 120) { r = x; g = c; b = 0 }
    else if (h < 180) { r = 0; g = c; b = x }
    else if (h < 240) { r = 0; g = x; b = c }
    else if (h < 300) { r = x; g = 0; b = c }
    else { r = c; g = 0; b = x }

    return {
      r: Math.round((r + m) * 255),
      g: Math.round((g + m) * 255),
      b: Math.round((b + m) * 255)
    }
  }

  static relativeLuminance(r: number, g: number, b: number): number {
    const toLinear = (c: number): number => {
      const s = c / 255
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b)
  }

  static contrastRatio(lum1: number, lum2: number): number {
    const lighter = Math.max(lum1, lum2)
    const darker = Math.min(lum1, lum2)
    return (lighter + 0.05) / (darker + 0.05)
  }

  static mixColors(color1: string, color2: string, ratio: number): string {
    const c1 = PaletteExtractor.parseHexColor(color1)
    const c2 = PaletteExtractor.parseHexColor(color2)
    const inv = 1 - ratio
    const r = Math.round(c1.r * inv + c2.r * ratio)
    const g = Math.round(c1.g * inv + c2.g * ratio)
    const b = Math.round(c1.b * inv + c2.b * ratio)
    return PaletteExtractor.hexFromRgb(r, g, b)
  }

  // ==================== LAB Color Space (D65) ====================

  private static rgbToLab(r: number, g: number, b: number): LabColor {
    // sRGB → linear
    const toLinear = (c: number): number => {
      const s = c / 255
      return s <= 0.04045 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
    }
    const R = toLinear(r)
    const G = toLinear(g)
    const B = toLinear(b)

    // Linear → XYZ (sRGB D65)
    let X = R * 0.4124564 + G * 0.3575761 + B * 0.1804375
    let Y = R * 0.2126729 + G * 0.7151522 + B * 0.0721750
    let Z = R * 0.0193339 + G * 0.1191920 + B * 0.9503041

    // Normalize by D65 white point
    X /= 0.95047
    Y /= 1.00000
    Z /= 1.08883

    const f = (t: number): number => t > 0.008856 ? Math.pow(t, 1 / 3) : (7.787 * t + 16 / 116)
    const fx = f(X), fy = f(Y), fz = f(Z)
    return {
      L: 116 * fy - 16,
      a: 500 * (fx - fy),
      b: 200 * (fy - fz)
    }
  }

  private static labToRgb(L: number, a: number, bVal: number): ColorRgb {
    const fy = (L + 16) / 116
    const fx = a / 500 + fy
    const fz = fy - bVal / 200

    const fInv = (t: number): number => {
      const t3 = t * t * t
      return t3 > 0.008856 ? t3 : (t - 16 / 116) / 7.787
    }

    let X = fInv(fx) * 0.95047
    let Y = fInv(fy) * 1.00000
    let Z = fInv(fz) * 1.08883

    // XYZ → linear sRGB
    let R = X *  3.2404542 + Y * -1.5371385 + Z * -0.4985314
    let G = X * -0.9692660 + Y *  1.8760108 + Z *  0.0415560
    let B = X *  0.0556434 + Y * -0.2040259 + Z *  1.0572252

    const toSrgb = (c: number): number => {
      const clamped = Math.max(0, Math.min(1, c))
      const v = clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * Math.pow(clamped, 1 / 2.4) - 0.055
      return Math.round(Math.max(0, Math.min(255, v * 255)))
    }

    return { r: toSrgb(R), g: toSrgb(G), b: toSrgb(B) }
  }

  // ==================== Hex helpers ====================

  private static parseHexColor(hex: string): ColorRgb {
    let s = hex.replace('#', '')
    if (s.length === 8) {
      s = s.substring(2)
    }
    return {
      r: parseInt(s.substring(0, 2), 16),
      g: parseInt(s.substring(2, 4), 16),
      b: parseInt(s.substring(4, 6), 16)
    }
  }

  private static hexFromRgb(r: number, g: number, b: number): string {
    const hex = (n: number): string => {
      const clamped = Math.max(0, Math.min(255, Math.round(n)))
      const h = clamped.toString(16)
      return h.length < 2 ? '0' + h : h
    }
    return '#ff' + hex(r) + hex(g) + hex(b)
  }
}

// 重排方法顺序，取色算法行为不变。

// 通知取色：从封面提取主色用于通知动态背景。
