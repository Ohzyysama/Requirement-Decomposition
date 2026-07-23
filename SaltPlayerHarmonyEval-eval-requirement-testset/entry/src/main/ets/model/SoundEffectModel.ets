// SoundEffectModel.ets
// Model layer: pure data structures and data operations for sound effect settings.
// Defines speed levels, DSP effect items, and compressor configuration.
// No UI or ViewModel logic.

import AudioPlayerService from './AudioPlayerService'

// Data class representing a speed level option
export class SpeedLevelItem {
  public value: number = 1.00
  public label: string = 'x1.00'

  constructor(value: number, label: string) {
    this.value = value
    this.label = label
  }
}

// Data class representing a DSP effect item
export class DspEffectItem {
  public icon: Resource
  public title: ResourceStr
  public subtitle: string
  public iconColor: ResourceColor

  constructor(icon: Resource, title: ResourceStr, subtitle: string, iconColor: ResourceColor) {
    this.icon = icon
    this.title = title
    this.subtitle = subtitle
    this.iconColor = iconColor
  }
}

// Constants and default data for sound effect settings
export class SoundEffectConstants {
  static readonly DEFAULT_SPEED: number = 1.00

  // All available speed levels
  static getSpeedLevels(): SpeedLevelItem[] {
    return [
      new SpeedLevelItem(0.25, 'x0.25'),
      new SpeedLevelItem(0.50, 'x0.50'),
      new SpeedLevelItem(0.75, 'x0.75'),
      new SpeedLevelItem(0.80, 'x0.80'),
      new SpeedLevelItem(0.90, 'x0.90'),
      new SpeedLevelItem(0.95, 'x0.95'),
      new SpeedLevelItem(1.00, 'x1.00'),
      new SpeedLevelItem(1.05, 'x1.05'),
      new SpeedLevelItem(1.10, 'x1.10'),
      new SpeedLevelItem(1.25, 'x1.25'),
      new SpeedLevelItem(1.50, 'x1.50'),
      new SpeedLevelItem(1.75, 'x1.75'),
      new SpeedLevelItem(2.00, 'x2.00'),
      new SpeedLevelItem(2.50, 'x2.50'),
      new SpeedLevelItem(3.00, 'x3.00'),
      new SpeedLevelItem(4.00, 'x4.00')
    ]
  }
}

// Data operations for sound effect settings
export class SoundEffectDataSource {
  // Apply speed change to the player
  static applySpeed(speed: number): void {
    AudioPlayerService.getInstance().setSpeed(speed)
  }

  // Toggle compressor on/off
  static setCompressorEnabled(enabled: boolean): void {
    console.info(`SoundEffectModel: compressor enabled = ${enabled}`)
    // TODO: Implement actual compressor toggle
  }

  // Open MAX Audio concert hall atmosphere
  static openConcertHallAtmosphere(): void {
    console.info('TODO: Open concert hall atmosphere dialog')
    // TODO: Implement actual navigation or dialog
  }

  // Open SALT PLAYER AUDIOFX V4
  static openAudioFxV4(): void {
    console.info('TODO: Open SALT PLAYER AUDIOFX V4')
    // TODO: Implement actual navigation or dialog
  }
}

// 播放速度：在 0.125x–4.0x 间按档位调节，选择后即时应用到 AVPlayer。

// 速度音效：播放速度档位作为音效项之一应用。

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA(speed: number): number {
  const MIN = 0.25
  const MAX = 4.0
  const STEP = 0.05
  if (Number.isNaN(speed)) {
    return 1.0
  }
  const clamped = Math.min(MAX, Math.max(MIN, speed))
  const stepped = Math.round(clamped / STEP) * STEP
  return Math.round(stepped * 100) / 100
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeA(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// DSP：叠加多段均衡增益（dB）并对总增益做上下限幅
export function mixBandGainsG(bands: number[], preamp: number): number {
  let sum = preamp
  for (let i = 0; i < bands.length; i++) {
    sum += bands[i]
  }
  const MIN = -24
  const MAX = 24
  if (sum < MIN) {
    return MIN
  }
  if (sum > MAX) {
    return MAX
  }
  return Math.round(sum * 10) / 10
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeG(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearA_H4(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabA_H4(name: string): string {
  let out = ''
  for (let i = 0; i < name.length; i++) {
    const c = name.charAt(i)
    const lower = c.toLowerCase()
    if (c !== lower && i > 0) {
      out += '-'
    }
    out += lower
  }
  return out
}

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA_H4(speed: number): number {
  const MIN = 0.25
  const MAX = 4.0
  const STEP = 0.05
  if (Number.isNaN(speed)) {
    return 1.0
  }
  const clamped = Math.min(MAX, Math.max(MIN, speed))
  const stepped = Math.round(clamped / STEP) * STEP
  return Math.round(stepped * 100) / 100
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_H4(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H4(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H4(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabG_H71(name: string): string {
  let out = ''
  for (let i = 0; i < name.length; i++) {
    const c = name.charAt(i)
    const lower = c.toLowerCase()
    if (c !== lower && i > 0) {
      out += '-'
    }
    out += lower
  }
  return out
}

// DSP：叠加多段均衡增益（dB）并对总增益做上下限幅
export function mixBandGainsG_H71(bands: number[], preamp: number): number {
  let sum = preamp
  for (let i = 0; i < bands.length; i++) {
    sum += bands[i]
  }
  const MIN = -24
  const MAX = 24
  if (sum < MIN) {
    return MIN
  }
  if (sum > MAX) {
    return MAX
  }
  return Math.round(sum * 10) / 10
}

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H71(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H71(lineIndex: number, currentIndex: number): number[] {
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

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H71(faqs: Map<string, string>, keyword: string): string[] {
  const kw = keyword.trim().toLowerCase()
  const matched: string[] = []
  if (kw.length === 0) {
    faqs.forEach((a: string, q: string) => { matched.push(q) })
    return matched
  }
  faqs.forEach((answer: string, question: string) => {
    const hay = (question + ' ' + answer).toLowerCase()
    if (hay.indexOf(kw) >= 0) {
      matched.push(question)
    }
  })
  return matched
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearG_H71(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}
