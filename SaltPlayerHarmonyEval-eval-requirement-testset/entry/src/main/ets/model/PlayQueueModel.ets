// PlayQueueModel.ets
// Model layer: raw data structures for PlayQueue
// Pure data classes with no UI or business logic dependency.

// Represents a single song in the play queue
export class QueueSongModel {
  public id: string = ''
  public title: string = ''
  public artist: string = ''
  public album: string = ''
  public subTitle: string = ''
  public fileUri: string = ''
  public coverUri: string = ''

  constructor(id: string = '', title: string = '', artist: string = '',
    album: string = '', subTitle: string = '', fileUri: string = '', coverUri: string = '') {
    this.id = id
    this.title = title
    this.artist = artist
    this.album = album
    this.subTitle = subTitle
    this.fileUri = fileUri
    this.coverUri = coverUri
  }
}

// Play mode enumeration values
export class PlayModeConstants {
  static readonly CIRCLE: string = 'circle'
  static readonly REPEAT_ONE: string = 'repeat_one'
  static readonly RANDOM: string = 'random'
}

// 播放模式：随机播放维护独立随机队列，循环模式按正常队列顺序。

// 播放队列：维护当前播放队列的数据结构与移除/清空操作。

// 队列对齐：补充队列移除后的当前索引修正。

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashA(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H3(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeA_H3(bytes: number): string {
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
export function isLeapYearA_H3(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA_H3(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA_H3(speed: number): number {
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
export function seekPositionFromRatioA_H3(ratio: number, durationMs: number): number {
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
