// LaboratoryModel.ets
// Model layer: pure data structure for Laboratory (experimental) settings.
// Represents the persisted configuration state without any UI or ViewModel logic.
// Corresponds to Android MMKV-persisted booleans in LaboratoryScreen.

export default class LaboratoryModel {
  public autoOpenPlaybackScreen: boolean = false
  public lyricsUIEffect3D: boolean = false
  public getAlbumArt: boolean = false
  public saltUiMaterial: boolean = false
  public liquidGlass: boolean = false
  public isPro: boolean = false

  constructor(
    autoOpenPlaybackScreen: boolean = false,
    lyricsUIEffect3D: boolean = false,
    getAlbumArt: boolean = false,
    saltUiMaterial: boolean = false,
    liquidGlass: boolean = false,
    isPro: boolean = false
  ) {
    this.autoOpenPlaybackScreen = autoOpenPlaybackScreen
    this.lyricsUIEffect3D = lyricsUIEffect3D
    this.getAlbumArt = getAlbumArt
    this.saltUiMaterial = saltUiMaterial
    this.liquidGlass = liquidGlass
    this.isPro = isPro
  }
}

// 实验室：开启后切歌自动打开播放页。

// 实验功能：3D 歌词预告与 Salt UI Material 主题。

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearG(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG(lineIndex: number, currentIndex: number): number[] {
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

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabG(name: string): string {
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

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H72(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// DSP：叠加多段均衡增益（dB）并对总增益做上下限幅
export function mixBandGainsG_H72(bands: number[], preamp: number): number {
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

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H72(faqs: Map<string, string>, keyword: string): string[] {
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

// 反馈校验：检查反馈内容长度并对联系方式做基础格式校验
export function validateFeedbackG_H72(content: string, contact: string): string {
  const text = content.trim()
  if (text.length < 5) {
    return 'contentTooShort'
  }
  if (text.length > 500) {
    return 'contentTooLong'
  }
  if (contact.length > 0) {
    const okMail = contact.indexOf('@') > 0 && contact.indexOf('.') > 0
    const okPhone = contact.length >= 6 && !Number.isNaN(Number(contact))
    if (!okMail && !okPhone) {
      return 'contactInvalid'
    }
  }
  return 'ok'
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabG_H72(name: string): string {
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

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockG_H72(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H73(faqs: Map<string, string>, keyword: string): string[] {
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

// 反馈校验：检查反馈内容长度并对联系方式做基础格式校验
export function validateFeedbackG_H73(content: string, contact: string): string {
  const text = content.trim()
  if (text.length < 5) {
    return 'contentTooShort'
  }
  if (text.length > 500) {
    return 'contentTooLong'
  }
  if (contact.length > 0) {
    const okMail = contact.indexOf('@') > 0 && contact.indexOf('.') > 0
    const okPhone = contact.length >= 6 && !Number.isNaN(Number(contact))
    if (!okMail && !okPhone) {
      return 'contactInvalid'
    }
  }
  return 'ok'
}

// 检查更新：逐段比较语义版本号判断远端是否更新
export function compareSemverG_H73(local: string, remote: string): number {
  const a = local.split('.')
  const b = remote.split('.')
  const len = Math.max(a.length, b.length)
  for (let i = 0; i < len; i++) {
    const x = i < a.length ? parseInt(a[i], 10) : 0
    const y = i < b.length ? parseInt(b[i], 10) : 0
    if (x > y) {
      return 1
    }
    if (x < y) {
      return -1
    }
  }
  return 0
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockG_H73(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorG_H73(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H73(lineIndex: number, currentIndex: number): number[] {
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
