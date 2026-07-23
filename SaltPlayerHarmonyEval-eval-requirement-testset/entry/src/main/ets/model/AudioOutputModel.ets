// AudioOutputModel.ets
// Model layer: pure data structures for Audio Output page settings.
// Defines raw data without any UI or ViewModel logic.

// Speed level data
export class SpeedLevelModel {
  public value: number = 1.00
  public label: string = 'x1.00'

  constructor(value: number, label: string) {
    this.value = value
    this.label = label
  }
}

// Audio output mode data
export class AudioOutputModeModel {
  public title: string = ''
  public subtitle: string = ''
  public mode: string = ''

  constructor(title: string, subtitle: string, mode: string) {
    this.title = title
    this.subtitle = subtitle
    this.mode = mode
  }
}

// DSP effect item data
export class DspEffectItemModel {
  public icon: Resource = $r('app.media.ic_arrow_back')
  public title: ResourceStr = ''
  public subtitle: string = ''
  public iconColor: ResourceColor = '#000000'

  constructor(icon: Resource, title: ResourceStr, subtitle: string, iconColor: ResourceColor) {
    this.icon = icon
    this.title = title
    this.subtitle = subtitle
    this.iconColor = iconColor
  }
}

// Audio output settings data (the core model for the page)
export default class AudioOutputModel {
  // Audio output toggle states
  public audioFocusEnabled: boolean = true
  public volumeBalanceEnabled: boolean = true
  public fadeInOutEnabled: boolean = true

  // Audio output mode
  public selectedOutputMode: string = 'audiotrack'

  // Audio output sample rate
  public sampleRateMin: number = 4000
  public sampleRateMax: number = 192000
  public audioOutputFreq: number = 48000

  // Force change device freq
  public changeDeviceFreqEnabled: boolean = false

  // DSP compressor
  public compressorEnabled: boolean = false

  // Playback speed (initialized from AppStorage for cross-component sync)
  public currentSpeed: number = AppStorage.get<number>('playbackSpeed') ?? 1.00

  // Static data: speed levels
  public static readonly SPEED_LEVELS: SpeedLevelModel[] = [
    new SpeedLevelModel(0.25, 'x0.25'),
    new SpeedLevelModel(0.50, 'x0.50'),
    new SpeedLevelModel(0.75, 'x0.75'),
    new SpeedLevelModel(0.80, 'x0.80'),
    new SpeedLevelModel(0.90, 'x0.90'),
    new SpeedLevelModel(0.95, 'x0.95'),
    new SpeedLevelModel(1.00, 'x1.00'),
    new SpeedLevelModel(1.05, 'x1.05'),
    new SpeedLevelModel(1.10, 'x1.10'),
    new SpeedLevelModel(1.25, 'x1.25'),
    new SpeedLevelModel(1.50, 'x1.50'),
    new SpeedLevelModel(1.75, 'x1.75'),
    new SpeedLevelModel(2.00, 'x2.00'),
    new SpeedLevelModel(2.50, 'x2.50'),
    new SpeedLevelModel(3.00, 'x3.00'),
    new SpeedLevelModel(4.00, 'x4.00')
  ]

  // Static data: output modes
  public static readonly OUTPUT_MODES: AudioOutputModeModel[] = [
    new AudioOutputModeModel(
      'AudioTrack',
      '默认音轨输出',
      'audiotrack'
    ),
    new AudioOutputModeModel(
      'OpenSL ES',
      '原生高性能低延迟输出，稳定性高，但无法配合使用系统音效以及第三方音效软件',
      'opensl'
    ),
    new AudioOutputModeModel(
      'AAudio',
      '原生高性能低延迟输出，但无法配合使用系统音效以及第三方音效软件',
      'aaudio'
    )
  ]

  // Restore defaults
  restoreDefaults(): void {
    this.selectedOutputMode = 'audiotrack'
    this.audioOutputFreq = 48000
    this.changeDeviceFreqEnabled = false
  }
}

// 音频输出：查看当前输出设备信息并在可用设备间切换。

// 音频输出对齐：补充设备热插拔后的刷新。

// 音频输出：补充输出设备切换的设备信息展示。

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG(event: string, playing: boolean): string {
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

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorG(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}

// 音量平衡：将 -1..1 的平衡值映射为左右声道增益系数
export function computeChannelGainsG(balance: number): number[] {
  let b = balance
  if (b < -1) {
    b = -1
  } else if (b > 1) {
    b = 1
  }
  const left = b <= 0 ? 1 : 1 - b
  const right = b >= 0 ? 1 : 1 + b
  const lr = Math.round(left * 1000) / 1000
  const rr = Math.round(right * 1000) / 1000
  return [lr, rr]
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderG(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF_H68(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
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
function computeImmersiveBarStateF_H68(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderG_H68(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashG_H68(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG_H68(event: string, playing: boolean): string {
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

// 流光相位取色：按相位在双色间做线性插值，输出 ARGB 十六进制色值
function flowingLightColorAtPhaseF_H68(phase: number, colorA: number, colorB: number): string {
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

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H69(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashG_H69(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeG_H69(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// 音量平衡：将 -1..1 的平衡值映射为左右声道增益系数
export function computeChannelGainsG_H69(balance: number): number[] {
  let b = balance
  if (b < -1) {
    b = -1
  } else if (b > 1) {
    b = 1
  }
  const left = b <= 0 ? 1 : 1 - b
  const right = b >= 0 ? 1 : 1 + b
  const lr = Math.round(left * 1000) / 1000
  const rr = Math.round(right * 1000) / 1000
  return [lr, rr]
}

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF_H69(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
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
function computeImmersiveBarStateF_H69(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}
