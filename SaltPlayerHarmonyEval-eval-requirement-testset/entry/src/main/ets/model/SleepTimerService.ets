// SleepTimerService.ets
// Model layer: global singleton managing sleep timer countdown.
// Owns the setInterval tick, state machine, and AppStorage sync.
// Corresponds to Android SleepTimer.kt

import { SleepTimerConfig, SleepTimerState } from './SleepTimerModel'
import AudioPlayerService from './AudioPlayerService'
import { promptAction } from '@kit.ArkUI'

export default class SleepTimerService {
  private static instance: SleepTimerService | null = null
  private timerId: number = -1
  private state: SleepTimerState = SleepTimerState.NULL
  private remainingMs: number = 0
  private endTimeMs: number = 0
  private autoExtend: boolean = false
  private isExtendPhase: boolean = false
  private songIdAtExtendStart: string = ''

  private constructor() {
  }

  static getInstance(): SleepTimerService {
    if (!SleepTimerService.instance) {
      SleepTimerService.instance = new SleepTimerService()
    }
    return SleepTimerService.instance
  }

  start(config: SleepTimerConfig): void {
    this.cancel()
    const totalMs = config.minutes * 60 * 1000
    this.state = SleepTimerState.TICK
    this.autoExtend = config.autoExtend
    this.isExtendPhase = false
    this.endTimeMs = Date.now() + totalMs
    this.remainingMs = totalMs
    this.syncToAppStorage()
    this.timerId = setInterval(() => this.tick(), 1000)
  }

  cancel(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.state = SleepTimerState.NULL
    this.remainingMs = 0
    this.endTimeMs = 0
    this.isExtendPhase = false
    this.songIdAtExtendStart = ''
    // Unregister song completion hook
    AudioPlayerService.getInstance().onSongCompletedDuringSleepTimer = null
    this.syncToAppStorage()
  }

  getState(): SleepTimerState {
    return this.state
  }

  getRemainingMs(): number {
    return this.remainingMs
  }

  getIsExtendPhase(): boolean {
    return this.isExtendPhase
  }

  private tick(): void {
    const now = Date.now()
    this.remainingMs = Math.max(0, this.endTimeMs - now)

    // During auto-extend phase, check if user paused or changed song
    if (this.state === SleepTimerState.TICK_UNTIL_SONG_END) {
      const service = AudioPlayerService.getInstance()
      const currentSongId = (AppStorage.get('currentSongId') as string) ?? ''
      if (!service.isCurrentlyPlaying() || currentSongId !== this.songIdAtExtendStart) {
        this.handleErrorEnd()
        return
      }
    }

    this.syncToAppStorage()

    if (this.remainingMs <= 0) {
      if (this.state === SleepTimerState.TICK && this.autoExtend) {
        this.startExtendPhase()
      } else {
        this.finish()
      }
    }
  }

  private startExtendPhase(): void {
    const service = AudioPlayerService.getInstance()
    const durationMs = service.getDurationMs()
    const currentMs = service.getCurrentTimeMs()
    const speed = service.getSpeed()

    if (durationMs <= 0 || currentMs >= durationMs || !service.isCurrentlyPlaying()) {
      this.finish()
      return
    }

    const remainingSongMs = Math.round((durationMs - currentMs) / speed)
    this.state = SleepTimerState.TICK_UNTIL_SONG_END
    this.isExtendPhase = true
    this.endTimeMs = Date.now() + remainingSongMs
    this.remainingMs = remainingSongMs
    this.songIdAtExtendStart = (AppStorage.get('currentSongId') as string) ?? ''
    this.syncToAppStorage()

    // Register hook: if the song completes naturally before our timer expires,
    // stop playback and exit immediately instead of auto-skipping to next song.
    // This mirrors Android's SleepTimer.onTimerFinish() being called on song end.
    service.onSongCompletedDuringSleepTimer = () => {
      this.finish()
    }
  }

  private handleErrorEnd(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.state = SleepTimerState.ERROR_END
    this.remainingMs = 0
    this.isExtendPhase = false
    // Unregister song completion hook
    AudioPlayerService.getInstance().onSongCompletedDuringSleepTimer = null
    this.syncToAppStorage()
    try {
      promptAction.showToast({ message: '睡眠定时被取消：播放被暂停或切换了歌曲' })
    } catch (_e) {
      // toast may fail if no UI context
    }
    setTimeout(() => {
      this.state = SleepTimerState.NULL
      this.syncToAppStorage()
    }, 3000)
  }

  finish(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    this.state = SleepTimerState.NULL
    this.remainingMs = 0
    this.isExtendPhase = false
    this.syncToAppStorage()

    const service = AudioPlayerService.getInstance()
    // Unregister hook before stopping
    service.onSongCompletedDuringSleepTimer = null

    try {
      promptAction.showToast({ message: '睡眠定时结束' })
    } catch (_e) {
      // toast may fail
    }

    service.pause()
    service.saveStateBeforeExit()
    service.terminateApp()
  }

  private syncToAppStorage(): void {
    AppStorage.setOrCreate('sleepTimerState', this.state as number)
    AppStorage.setOrCreate('sleepTimerRemainingMs', this.remainingMs)
    AppStorage.setOrCreate('sleepTimerIsExtendPhase', this.isExtendPhase)
  }
}

// 睡眠定时：开启「播放完当前歌曲再停止」时，到点不立即停止，等当前曲目自然结束后再淡出暂停。

// 睡眠定时：设置 1–120 分钟定时时长，到点淡出并暂停播放。

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabA(name: string): string {
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

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H6(durationMin: number, songRemainMs: number, extend: boolean): number {
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
export function resolveCoverUriA_H6(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H6(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H6(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockA_H6(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorA_H6(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 睡眠定时：剩余毫秒格式化为 mm:ss，"播完本曲"时对齐到歌曲结束
export function formatSleepRemainX_X2(remainMs: number, finishCurrent: boolean, songRemainMs: number): string {
  let ms = remainMs > 0 ? remainMs : 0
  if (finishCurrent && songRemainMs > ms) {
    ms = songRemainMs
  }
  const sec = Math.floor(ms / 1000)
  const m = Math.floor(sec / 60)
  const s = sec % 60
  const mm = m < 10 ? '0' + m : String(m)
  const ss = s < 10 ? '0' + s : String(s)
  return mm + ':' + ss
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_X2(ratio: number, durationMs: number): number {
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

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_X2(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorA_X2(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_X2(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}
