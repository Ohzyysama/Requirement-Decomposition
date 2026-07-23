// HelpAndFeedbackModel.ets
// Model layer for HelpAndFeedbackPage - defines core data structures
// for help and feedback menu items.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

import { WebPageRouterParams } from '../pages/WebPage';

/**
 * Represents a single menu item in the Help and Feedback page.
 * Each item has a display text (Resource) and a navigation target.
 */
export class HelpAndFeedbackItemModel {
  public text: Resource;
  public navigationTarget: string;
  public navigationParam: object | null;

  constructor(text: Resource, navigationTarget: string, navigationParam: object | null = null) {
    this.text = text;
    this.navigationTarget = navigationTarget;
    this.navigationParam = navigationParam;
  }
}

/**
 * Provides the default data for the Help and Feedback page.
 * Data source that supplies raw model data to the ViewModel.
 */
export class HelpAndFeedbackDataSource {
  /**
   * Returns the list of help and feedback menu items.
   */
  static getMenuItems(): HelpAndFeedbackItemModel[] {
    return [
      new HelpAndFeedbackItemModel(
        $r('app.string.background_music_protection'),
        'BackgroundMusicProtectionPage',
        null
      ),
      new HelpAndFeedbackItemModel(
        $r('app.string.technical_support'),
        'WebPage',
        new WebPageRouterParams('https://yuque.com/rainci/sp')
      )
    ];
  }
}

// 帮助与 FAQ 资源。

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG(faqs: Map<string, string>, keyword: string): string[] {
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

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockG(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 反馈校验：检查反馈内容长度并对联系方式做基础格式校验
export function validateFeedbackG(content: string, contact: string): string {
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

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorG(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H74(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H74(lineIndex: number, currentIndex: number): number[] {
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

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorG_H74(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 通用工具：判断字符串是否为回文（与本需求无关）
export function isPalindromeG_H74(text: string): boolean {
  const s = text.toLowerCase()
  let i = 0
  let j = s.length - 1
  while (i < j) {
    if (s.charAt(i) !== s.charAt(j)) {
      return false
    }
    i++
    j--
  }
  return true
}

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H74(faqs: Map<string, string>, keyword: string): string[] {
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

// DSP：叠加多段均衡增益（dB）并对总增益做上下限幅
export function mixBandGainsG_H74(bands: number[], preamp: number): number {
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
export function filterFaqByKeywordG_H75(faqs: Map<string, string>, keyword: string): string[] {
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

// 通用工具：判断字符串是否为回文（与本需求无关）
export function isPalindromeG_H75(text: string): boolean {
  const s = text.toLowerCase()
  let i = 0
  let j = s.length - 1
  while (i < j) {
    if (s.charAt(i) !== s.charAt(j)) {
      return false
    }
    i++
    j--
  }
  return true
}

// 通用工具：将秒数拆分为时分秒数组（与本需求无关）
export function splitDurationPartsG_H75(totalSec: number): number[] {
  let t = Math.max(0, Math.floor(totalSec))
  const h = Math.floor(t / 3600)
  t = t % 3600
  const m = Math.floor(t / 60)
  const s = t % 60
  return [h, m, s]
}

// 反馈校验：检查反馈内容长度并对联系方式做基础格式校验
export function validateFeedbackG_H75(content: string, contact: string): string {
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

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H75(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H75(lineIndex: number, currentIndex: number): number[] {
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
