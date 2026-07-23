// FlowingLightViewModel.ets
// ViewModel layer: manages flowing light background state including cover loading,
// color extraction, cross-fade animation, and rotation angles.
//
// Android reference (FlowingLightView.kt + MainActivity.reDrawFlowingLightView):
// - Overlay colors are ALWAYS #52000000 + #1A000000 (hardcoded in init, never updated)
// - Cover brightness (isLight) only affects the UI foreground text color,
//   NOT the flowing light overlays
// - Foreground color is extracted via MediaNotificationProcessor (Palette-based)

import { image } from '@kit.ImageKit'
import { effectKit } from '@kit.ArkGraphics2D'
import { CurrentSongCoverController } from '../model/CurrentSongCoverController'
import {
  FlowingLightConfig,
  FlowingLightThemeResolver,
  FlowingLightOverlayParams
} from '../model/FlowingLightModel'
import { PaletteExtractor } from '../model/PaletteExtractor'
import type { MediaColorResult } from '../model/PaletteExtractor'

@Observed
export default class FlowingLightViewModel {
  // ==================== Cover PixelMaps ====================
  @Track public coverPixelMap: image.PixelMap | undefined = undefined
  @Track public previousCoverPixelMap: image.PixelMap | undefined = undefined

  // ==================== Rotation Angles ====================
  @Track public rotation1: number = 0
  @Track public rotation2: number = 0
  @Track public rotation3: number = 0

  // ==================== Rotation Control ====================
  @Track public isRotating: boolean = false

  // ==================== Cross-Fade ====================
  @Track public currentOpacity: number = 1
  @Track public previousOpacity: number = 1
  @Track public isCrossFading: boolean = false

  // ==================== Theme / Colors ====================
  // Overlay colors are FIXED constants matching Android FlowingLightView.init
  // (dso_color_lyrics_back=#52000000, white_alpha_10=#1A000000).
  // Android never changes these at runtime.
  @Track public overlayColor1: string = FlowingLightConfig.OVERLAY_COLOR_1
  @Track public overlayColor2: string = FlowingLightConfig.OVERLAY_COLOR_2

  // Foreground color for UI text/icons — extracted from cover brightness
  @Track public foregroundColor: string = '#ffffffff'
  @Track public accentColor: string = ''
  @Track public isLightMode: boolean = false
  @Track public colorExtracted: boolean = false

  // ==================== Saturation Matrix ====================
  @Track public saturationMatrix: number[] =
    FlowingLightThemeResolver.buildSaturationMatrix(FlowingLightConfig.SATURATION)

  // ==================== Callback ====================
  // Called after color extraction completes so parent can update reactive properties
  public onColorsExtracted: (() => void) | null = null
  // Called when a new cover is loaded and cross-fade should be animated (requires UIContext)
  public onCoverLoaded: (() => void) | null = null

  // ==================== Internal State ====================
  @Track private currentSongId: string = ''

  // Subscribe to the central cover controller — called by PlayerPageViewModel
  // during initialization. The controller delivers PixelMap changes to all
  // subscribers simultaneously, matching Android's StateFlow pattern.
  subscribeToController(): void {
    CurrentSongCoverController.getInstance().addListener(
      (songId: string, pm: image.PixelMap | undefined): void => {
        this.onControllerCoverChanged(songId, pm)
      })
  }

  // Internal handler — receives the current song cover from the controller.
  private onControllerCoverChanged(songId: string, pm: image.PixelMap | undefined): void {
    if (songId === this.currentSongId && this.coverPixelMap) {
      return // same song, already applied
    }
    this.currentSongId = songId
    this.colorExtracted = false
    this.accentColor = ''

    if (songId.length === 0) {
      this.coverPixelMap = undefined
      this.previousCoverPixelMap = undefined
      this.isCrossFading = false
      return
    }

    if (this.isCrossFading) {
      this.completeCrossFade()
    }

    if (pm) {
      this.coverPixelMap = pm
      this.currentOpacity = 1
      this.extractColors(pm)
    } else {
      this.coverPixelMap = undefined
    }
  }

  // Update cover when song changes — kept for backward compat / explicit calls.
  // Delegates to the central controller which notifies all subscribers.
  updateCover(songId: string, _coverUri: string): void {
    console.info('FlowingLightVM.updateCover called: songId=' + songId)
    if (songId.length === 0) {
      this.currentSongId = ''
      this.coverPixelMap = undefined
      this.previousCoverPixelMap = undefined
      this.isCrossFading = false
      this.colorExtracted = false
      this.accentColor = ''
      return
    }
    CurrentSongCoverController.getInstance().loadForSong(songId)
  }

  // Extract background + primary text colors from cover art using PaletteExtractor,
  // which is the HarmonyOS equivalent of Android's MediaNotificationProcessor.
  //
  // Matches Salt Player Android's reDrawFlowingLightView → magicColor() logic:
  //   val processor = MediaNotificationProcessor(ctx, compressBitmap)
  //   if (processor.isLight) playerViewModel.color.value = processor.primaryTextColor
  //   else playerViewModel.color.value = ColorKit.mix(processor.backgroundColor, rgb(40,40,40))
  //
  // This only produces the "magic color" (accentColor). The effectKit pass is kept
  // only for FOREGROUND brightness detection (isLightMode) used elsewhere.
  private extractColors(pixelMap: image.PixelMap): void {
    const extractionSongId = this.currentSongId

    // Pass 1: effectKit for brightness-based isLightMode (legacy behaviour)
    try {
      effectKit.createColorPicker(pixelMap, (err, colorPicker) => {
        if (extractionSongId !== this.currentSongId) return
        if (!err && colorPicker) {
          const mainColor = colorPicker.getMainColorSync()
          if (mainColor) {
            const r = mainColor.red
            const g = mainColor.green
            const b = mainColor.blue
            const brightness = (r * 299 + g * 587 + b * 114) / 1000
            this.isLightMode = brightness > 128
            // Legacy foregroundColor (kept for backward compat with PlayQueueComponent fallback)
            if (this.isLightMode) {
              this.foregroundColor = FlowingLightThemeResolver.mixColors(
                '#ff' + this.toHex(r) + this.toHex(g) + this.toHex(b),
                '#ff050f19', 0.7
              )
            } else {
              this.foregroundColor = FlowingLightThemeResolver.mixColors(
                '#ff' + this.toHex(r) + this.toHex(g) + this.toHex(b),
                '#ffffffff', 0.7
              )
            }
          }
        }
      })
    } catch (_e) {
      // effectKit unavailable
    }

    // Pass 2: PaletteExtractor for magic accent color (Android parity)
    PaletteExtractor.extract(pixelMap)
      .then((result: MediaColorResult) => {
        if (extractionSongId !== this.currentSongId) return

        // Salt Player Android logic (MainActivity.reDrawFlowingLightView.magicColor):
        //   if (processor.isLight) → use primaryTextColor
        //   else → mix(backgroundColor, playerThemeSummer.playerActivityMainColor)
        //   where playerThemeSummer.playerActivityMainColor = Color.rgb(40, 40, 40) = #ff282828
        //   and ColorKit.mix uses 50/50 ratio
        if (result.isLight) {
          this.accentColor = result.primaryTextColor
        } else {
          this.accentColor = PaletteExtractor.mixColors(
            result.backgroundColor,
            '#ff282828',
            0.5
          )
        }

        this.colorExtracted = true
        if (this.onColorsExtracted) this.onColorsExtracted()
      })
      .catch(() => {
        if (extractionSongId !== this.currentSongId) return
        this.accentColor = ''
        this.colorExtracted = true
        if (this.onColorsExtracted) this.onColorsExtracted()
      })
  }

  // Complete cross-fade transition (called after animation finishes)
  completeCrossFade(): void {
    this.isCrossFading = false
    this.previousCoverPixelMap = undefined
    this.currentOpacity = 1
    this.previousOpacity = 0
  }

  // Apply flowing light mode: update overlay colors based on whether light or dark flowing.
  // isLightFlowing: true = use light overlay colors, false = use dark overlay colors
  applyFlowingLightMode(isLightFlowing: boolean): void {
    const params = FlowingLightOverlayParams.getParams(isLightFlowing)
    this.overlayColor1 = FlowingLightOverlayParams.toColorString(params.overlayColor1)
    this.overlayColor2 = FlowingLightOverlayParams.toColorString(params.overlayColor2)
  }

  private toHex(n: number): string {
    const clamped = Math.max(0, Math.min(255, n))
    const hex = clamped.toString(16)
    return hex.length < 2 ? '0' + hex : hex
  }
}
