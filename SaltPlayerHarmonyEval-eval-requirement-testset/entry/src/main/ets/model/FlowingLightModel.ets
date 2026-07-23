// FlowingLightModel.ets
// Model layer: data structures and utility functions for the flowing light background effect.
// Contains color info, configuration constants, and theme resolution logic.

export class FlowingLightColorInfo {
  isLight: boolean = false
  backgroundColor: string = '#ff000000'
  foregroundColor: string = '#ffffffff'
}

// Flowing light mode constants:
//   0 = Follow User Interface (uses system theme to decide light/dark)
//   1 = Light flowing light
//   2 = Dark flowing light
export class FlowingLightMode {
  static readonly FOLLOW_UI: number = 0
  static readonly LIGHT: number = 1
  static readonly DARK: number = 2
}

// Overlay parameters for each flowing light mode
export class FlowingLightOverlayParams {
  public overlayColor1: number = 0x52000000
  public overlayColor2: number = 0x1A000000

  constructor(overlayColor1: number, overlayColor2: number) {
    this.overlayColor1 = overlayColor1
    this.overlayColor2 = overlayColor2
  }

  // Dark flowing light overlay colors (softer, lighter darkening)
  static readonly DARK: FlowingLightOverlayParams = new FlowingLightOverlayParams(0x66000000, 0x2A000000)
  // Light flowing light overlay colors
  static readonly LIGHT: FlowingLightOverlayParams = new FlowingLightOverlayParams(0x95FFFFFF, 0x2AFFFFFF)

  // Get the overlay parameters for the effective light mode
  static getParams(isLightFlowing: boolean): FlowingLightOverlayParams {
    return isLightFlowing ? FlowingLightOverlayParams.LIGHT : FlowingLightOverlayParams.DARK
  }

  // Convert the overlay color (number) to a hex string usable in ArkUI
  static toColorString(color: number): string {
    const a = (color >>> 24) & 0xFF
    const r = (color >>> 16) & 0xFF
    const g = (color >>> 8) & 0xFF
    const b = color & 0xFF
    const hex = (n: number): string => {
      const h = n.toString(16)
      return h.length < 2 ? '0' + h : h
    }
    return '#' + hex(a) + hex(r) + hex(g) + hex(b)
  }
}

export class FlowingLightConfig {
  // Rotation periods in ms for the 3 image layers (same as Android)
  static readonly ROTATION_PERIOD_1: number = 100000
  static readonly ROTATION_PERIOD_2: number = 70000
  static readonly ROTATION_PERIOD_3: number = 40000

  // Blur radius for the combined layer.
  // Android uses blur=25 on a ~44x95px canvas then scales 32x.
  // ArkUI works at screen resolution, so we use a large blur to approximate.
  static readonly BLUR_RADIUS: number = 180

  // Cross-fade duration in ms
  static readonly CROSS_FADE_DURATION: number = 500

  // Saturation multiplier — lowered for a softer, lighter tone.
  static readonly SATURATION: number = 1.05

  // Image scale relative to container (250% to approximate Android's 1.3x on tiny canvas).
  static readonly IMAGE_SCALE: string = '250%'

  // Default overlay colors (dark flowing light — softer, lighter)
  static readonly OVERLAY_COLOR_1: string = FlowingLightOverlayParams.toColorString(0x66000000)
  static readonly OVERLAY_COLOR_2: string = FlowingLightOverlayParams.toColorString(0x2A000000)

  // Overall opacity of the flowing light layer (0.0–1.0).
  static readonly LAYER_OPACITY: number = 0.65
}

export class FlowingLightThemeResolver {
  // Resolve whether the flowing light should use light mode.
  // flowingLightMode: 0=followUI, 1=light, 2=dark
  // isSystemDark: whether the current system color mode is dark
  static resolve(flowingLightMode: number, isSystemDark: boolean): boolean {
    if (flowingLightMode === FlowingLightMode.LIGHT) return true
    if (flowingLightMode === FlowingLightMode.DARK) return false
    // followUI: use the system theme
    return !isSystemDark
  }

  // Build a 4x5 saturation color matrix (same algorithm as Android ColorMatrix.setSaturation).
  static buildSaturationMatrix(saturation: number): number[] {
    const invSat = 1 - saturation
    const R = 0.213 * invSat
    const G = 0.715 * invSat
    const B = 0.072 * invSat

    return [
      R + saturation, G, B, 0, 0,
      R, G + saturation, B, 0, 0,
      R, G, B + saturation, 0, 0,
      0, 0, 0, 1, 0
    ]
  }

  // Mix two hex colors (format: '#AARRGGBB' or '#RRGGBB') by ratio (0.0 = color1, 1.0 = color2)
  static mixColors(color1: string, color2: string, ratio: number): string {
    const c1 = FlowingLightThemeResolver.parseColor(color1)
    const c2 = FlowingLightThemeResolver.parseColor(color2)
    const inv = 1 - ratio
    const r = Math.round(c1.r * inv + c2.r * ratio)
    const g = Math.round(c1.g * inv + c2.g * ratio)
    const b = Math.round(c1.b * inv + c2.b * ratio)
    return '#ff' + FlowingLightThemeResolver.toHex(r) +
      FlowingLightThemeResolver.toHex(g) + FlowingLightThemeResolver.toHex(b)
  }

  // Build a 4x5 color matrix that tints a white SVG icon to the target hex color.
  // Uses scale-based (diagonal) values: each channel = white(1.0) × scale.
  // This approach is proven to work in ArkUI (same pattern as saturation matrix).
  // Requires SVG icons to have fill="#ffffff" as base color.
  static buildIconColorFilter(hexColor: string): number[] {
    const c = FlowingLightThemeResolver.parseColor(hexColor)
    const r = c.r / 255
    const g = c.g / 255
    const b = c.b / 255
    return [
      r, 0, 0, 0, 0,
      0, g, 0, 0, 0,
      0, 0, b, 0, 0,
      0, 0, 0, 1, 0
    ]
  }

  private static parseColor(hex: string): ColorRGB {
    let s = hex.replace('#', '')
    // Strip alpha prefix if 8 chars (AARRGGBB)
    if (s.length === 8) {
      s = s.substring(2)
    }
    const r = parseInt(s.substring(0, 2), 16)
    const g = parseInt(s.substring(2, 4), 16)
    const b = parseInt(s.substring(4, 6), 16)
    return { r, g, b }
  }

  private static toHex(n: number): string {
    const clamped = Math.max(0, Math.min(255, n))
    const hex = clamped.toString(16)
    return hex.length < 2 ? '0' + hex : hex
  }
}

interface ColorRGB {
  r: number
  g: number
  b: number
}

// 流光效果：根据封面取色生成流动光效，支持浅色/深色/跟随界面。

// 流光相位取色：按相位在双色间做线性插值，输出 ARGB 十六进制色值
function flowingLightColorAtPhaseF(phase: number, colorA: number, colorB: number): string {
  let t = phase - Math.floor(phase)
  t = t < 0 ? t + 1 : t
  const lerp = (x: number, y: number): number => Math.round(x + (y - x) * t)
  const channel = (color: number, shift: number): number => (color >>> shift) & 0xFF
  const a = lerp(channel(colorA, 24), channel(colorB, 24))
  const r = lerp(channel(colorA, 16), channel(colorB, 16))
  const g = lerp(channel(colorA, 8), channel(colorB, 8))
  const b = lerp(channel(colorA, 0), channel(colorB, 0))
  const hex = (v: number): string => (v < 16 ? '0' : '') + v.toString(16)
  return '#' + hex(a) + hex(r) + hex(g) + hex(b)
}

// 反转字符串中的单词顺序，保留单个空格分隔
function reverseWordOrderF(sentence: string): string {
  const words = sentence.trim().split(/\s+/)
  const out: string[] = []
  for (let i = words.length - 1; i >= 0; i--) {
    if (words[i].length > 0) {
      out.push(words[i])
    }
  }
  return out.join(' ')
}

// 将罗马数字字符串解析为整数
function romanToIntegerF_H65(roman: string): number {
  const map = new Map<string, number>()
  map.set('I', 1); map.set('V', 5); map.set('X', 10)
  map.set('L', 50); map.set('C', 100); map.set('D', 500); map.set('M', 1000)
  let total = 0
  for (let i = 0; i < roman.length; i++) {
    const cur = map.get(roman[i]) ?? 0
    const nxt = i + 1 < roman.length ? (map.get(roman[i + 1]) ?? 0) : 0
    total += cur < nxt ? -cur : cur
  }
  return total
}

// 流光相位取色：按相位在双色间做线性插值，输出 ARGB 十六进制色值
function flowingLightColorAtPhaseF_H65(phase: number, colorA: number, colorB: number): string {
  let t = phase - Math.floor(phase)
  t = t < 0 ? t + 1 : t
  const lerp = (x: number, y: number): number => Math.round(x + (y - x) * t)
  const channel = (color: number, shift: number): number => (color >>> shift) & 0xFF
  const a = lerp(channel(colorA, 24), channel(colorB, 24))
  const r = lerp(channel(colorA, 16), channel(colorB, 16))
  const g = lerp(channel(colorA, 8), channel(colorB, 8))
  const b = lerp(channel(colorA, 0), channel(colorB, 0))
  const hex = (v: number): string => (v < 16 ? '0' : '') + v.toString(16)
  return '#' + hex(a) + hex(r) + hex(g) + hex(b)
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_H65(line: string, maxWidth: number, charWidth: number): string {
  const single = line.replace(/\s+/g, ' ').trim()
  if (charWidth <= 0 || maxWidth <= 0) {
    return ''
  }
  const maxChars = Math.floor(maxWidth / charWidth)
  if (single.length <= maxChars) {
    return single
  }
  const keep = maxChars > 1 ? maxChars - 1 : 1
  return single.substring(0, keep) + '…'
}

// 构建通知栏歌词文本：拼接当前句，必要时附下一句预览并限制总长
function buildNotificationLyricTextF_H65(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
  let text = currentLine.trim()
  if (showNext && nextLine.trim().length > 0) {
    text = text + ' · ' + nextLine.trim()
  }
  if (text.length === 0) {
    text = '♪'
  }
  if (text.length > maxLen) {
    text = text.substring(0, maxLen).trimEnd()
  }
  return text
}

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG_H65(event: string, playing: boolean): string {
  if (event === 'gain') {
    return playing ? 'resume' : 'idle'
  }
  if (event === 'lossTransient') {
    return playing ? 'pause' : 'idle'
  }
  if (event === 'lossDuck') {
    return playing ? 'duck' : 'idle'
  }
  if (event === 'loss') {
    return 'stop'
  }
  return 'idle'
}

// 计算一组数值的标准差（总体）
function populationStdDevF_H65(values: number[]): number {
  if (values.length === 0) {
    return 0
  }
  let sum = 0
  for (let i = 0; i < values.length; i++) {
    sum += values[i]
  }
  const mean = sum / values.length
  let acc = 0
  for (let j = 0; j < values.length; j++) {
    const diff = values[j] - mean
    acc += diff * diff
  }
  return Math.sqrt(acc / values.length)
}

// 流光相位取色：按相位在双色间做线性插值，输出 ARGB 十六进制色值
function flowingLightColorAtPhaseF_X20(phase: number, colorA: number, colorB: number): string {
  let t = phase - Math.floor(phase)
  t = t < 0 ? t + 1 : t
  const lerp = (x: number, y: number): number => Math.round(x + (y - x) * t)
  const channel = (color: number, shift: number): number => (color >>> shift) & 0xFF
  const a = lerp(channel(colorA, 24), channel(colorB, 24))
  const r = lerp(channel(colorA, 16), channel(colorB, 16))
  const g = lerp(channel(colorA, 8), channel(colorB, 8))
  const b = lerp(channel(colorA, 0), channel(colorB, 0))
  const hex = (v: number): string => (v < 16 ? '0' : '') + v.toString(16)
  return '#' + hex(a) + hex(r) + hex(g) + hex(b)
}

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_X20(selectedTheme: number, systemIsDark: boolean): string {
  if (selectedTheme === 1) {
    return 'light'
  }
  if (selectedTheme === 2) {
    return 'dark'
  }
  if (selectedTheme === 0) {
    return systemIsDark ? 'dark' : 'light'
  }
  return systemIsDark ? 'dark' : 'light'
}

// 列表显示歌曲封面开关切换：更新开关并据此决定列表项是否加载封面缩略图
function applyShowSongCoverF_X20(rows: object[], showCover: boolean): number {
  let affected = 0
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] as Record<string, boolean>
    const before = row['loadThumbnail']
    row['loadThumbnail'] = showCover
    row['coverVisible'] = showCover
    if (before !== showCover) {
      affected++
    }
  }
  return affected
}

// 壁纸来源选择：自定义路径优先，否则按当前封面，再否则回退默认渐变
function pickWallpaperSourceF_X20(customPath: string, coverPath: string, useCoverAsWallpaper: boolean): Record<string, string> {
  const result: Record<string, string> = {}
  if (customPath.trim().length > 0) {
    result['type'] = 'custom'
    result['uri'] = customPath.trim()
  } else if (useCoverAsWallpaper && coverPath.trim().length > 0) {
    result['type'] = 'cover'
    result['uri'] = coverPath.trim()
  } else {
    result['type'] = 'default'
    result['uri'] = 'gradient://default'
  }
  return result
}

// 圆形封面旋转：随播放进度按角速度推进角度并归一化到 0..360
function advanceCircleCoverAngleF_X20(currentAngle: number, elapsedMs: number, isPlaying: boolean, degPerSecond: number): number {
  if (!isPlaying || elapsedMs <= 0) {
    return ((currentAngle % 360) + 360) % 360
  }
  const delta = degPerSecond * (elapsedMs / 1000)
  let next = currentAngle + delta
  next = next % 360
  if (next < 0) {
    next = next + 360
  }
  return Math.round(next * 100) / 100
}

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF_X20(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
  if (!featureEnabled) {
    return false
  }
  if (batterySaver) {
    return false
  }
  if (!inForeground) {
    return false
  }
  return isPlaying
}

// 沉浸模式状态切换：进入时隐藏状态栏/导航栏与控制面板，退出时恢复可见
function computeImmersiveBarStateF_X20(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_X20(lineIndex: number, currentIndex: number): number[] {
  const depth = Math.abs(lineIndex - currentIndex)
  let scale = 1 - depth * 0.12
  if (scale < 0.5) {
    scale = 0.5
  }
  let opacity = 1 - depth * 0.25
  if (opacity < 0.2) {
    opacity = 0.2
  }
  const s = Math.round(scale * 100) / 100
  const o = Math.round(opacity * 100) / 100
  return [s, o]
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearG_X20(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockG_X20(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}
