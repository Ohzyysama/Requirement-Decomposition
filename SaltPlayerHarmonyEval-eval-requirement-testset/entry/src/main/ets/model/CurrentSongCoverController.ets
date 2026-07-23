// CurrentSongCoverController.ets
// Single source of truth for the currently playing song's cover art.
//
// Mirrors Android's MusicController.coverBitmap StateFlow pattern:
//   - ONE central PixelMap, loaded once when the current song changes
//   - ALL UI consumers (MiniPlayer, PlayerPage, FlowingLight, PlayQueue)
//     subscribe via addListener() and receive the same PixelMap reference
//   - Race conditions are handled by a monotonic requestId: late-arriving
//     async results for a stale songId are silently discarded
//
// Note: in SPH, the songId IS the file URI (see ScanningModel: song.id = uri).
// The controller therefore takes a single identifier — no separate fileUri
// parameter to guard against AppStorage-timing bugs.

import { image } from '@kit.ImageKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { CoverCacheDb } from './CoverCacheDb'
import { CoverArtExtractor } from './CoverArtExtractor'

const TAG = 'CurrentCover'

export type CurrentCoverListener = (songId: string, coverPixelMap: image.PixelMap | undefined) => void

export class CurrentSongCoverController {
  private static instance: CurrentSongCoverController | null = null

  private _coverPixelMap: image.PixelMap | undefined = undefined
  private _currentSongId: string = ''
  // Tracks whether the current songId has been fully resolved (either to a
  // real PixelMap or to a definitive "no cover" result).  Prevents the
  // same-songId skip from short-circuiting when a previous call failed early.
  private _resolved: boolean = false
  // Distinguishes "load failed due to error" from "song genuinely has no cover".
  // When true, a repeated loadForSong for the same songId will retry;
  // when false (normal no-cover result), it won't.
  private _loadFailed: boolean = false
  private requestId: number = 0
  private listeners: CurrentCoverListener[] = []

  static getInstance(): CurrentSongCoverController {
    if (!CurrentSongCoverController.instance) {
      CurrentSongCoverController.instance = new CurrentSongCoverController()
    }
    return CurrentSongCoverController.instance
  }

  get coverPixelMap(): image.PixelMap | undefined {
    return this._coverPixelMap
  }

  get currentSongId(): string {
    return this._currentSongId
  }

  // Register a listener. Called immediately with the current state so new
  // subscribers don't need a separate "initial sync" step.
  addListener(fn: CurrentCoverListener): void {
    if (!this.listeners.includes(fn)) {
      this.listeners.push(fn)
    }
    // Deliver current state so the subscriber is up-to-date immediately.
    fn(this._currentSongId, this._coverPixelMap)
  }

  removeListener(fn: CurrentCoverListener): void {
    const idx = this.listeners.indexOf(fn)
    if (idx >= 0) this.listeners.splice(idx, 1)
  }

  private notify(): void {
    const id = this._currentSongId
    const pm = this._coverPixelMap
    for (const listener of this.listeners) {
      listener(id, pm)
    }
  }

  // Called when the current playing song changes.
  // Idempotent for the same resolved song. A songId that was already resolved
  // (even to undefined — i.e. "no cover") is a no-op; only new songs reset.
  // Exception: if the previous load FAILED (error/race), we retry.
  loadForSong(songId: string): void {
    if (songId === this._currentSongId) {
      if (!this._resolved) return       // load already in progress — don't bump requestId
      if (!this._loadFailed) return      // already resolved (cover or no-cover) — skip
      // _loadFailed === true → fall through to retry
    }

    const myRequestId = ++this.requestId
    this._currentSongId = songId
    this._resolved = false
    this._loadFailed = false

    // Keep the old cover visible until the new one is ready (avoid flicker).
    // Only clear if there is no song to load.
    if (!songId || songId.length === 0) {
      this._coverPixelMap = undefined
      this._resolved = true
      this.notify()
      return
    }

    // Async: RDB → extract from audio file.
    // songId IS the fileUri in SPH (song.id = uri in ScanningModel).
    // Old cover stays visible until the new one arrives.
    CoverCacheDb.loadCover(songId)
      .then((rdbPm: image.PixelMap | undefined) => {
        if (rdbPm) return rdbPm
        return CoverArtExtractor.extractAndCache(songId, songId)
      })
      .then((pm: image.PixelMap | undefined) => {
        if (this.requestId !== myRequestId) return // stale
        this._coverPixelMap = pm ?? undefined
        this._resolved = true
        this._loadFailed = false
        this.notify()
        hilog.info(0, TAG, 'Async load %{public}s for %{public}s',
          pm ? 'hit' : 'miss', songId.substring(songId.length - 30))
      })
      .catch((e: Error) => {
        if (this.requestId !== myRequestId) return
        this._coverPixelMap = undefined
        this._resolved = true
        this._loadFailed = true // mark as failed — retry allowed
        this.notify()
        hilog.warn(0, TAG, 'Load failed: %{public}s', e.message)
      })
  }

  // Force-reload the current song's cover (e.g. after cache invalidation).
  reload(): void {
    if (this._currentSongId.length > 0) {
      const songId = this._currentSongId
      this._currentSongId = '' // force re-load
      this._resolved = false
      this._loadFailed = false
      this.loadForSong(songId)
    }
  }

  clear(): void {
    this.requestId++
    this._coverPixelMap = undefined
    this._currentSongId = ''
    this._resolved = true
    this._loadFailed = false
    this.notify()
  }
}

// 当前歌曲封面持久化：缓存当前封面供通知使用。

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockA(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H7(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H7(files: Record<string, string>[]): Record<string, string>[] {
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

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H7(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorA_H7(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 通用工具：将字节数格式化为可读字符串（与本需求无关）
export function formatBytesB1_H7(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let idx = 0
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024
    idx++
  }
  return Math.round(value * 100) / 100 + ' ' + units[idx]
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H7(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}
