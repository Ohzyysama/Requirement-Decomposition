// SongItemViewModel.ets
// ViewModel layer: provides data and logic for SongItemComponent (View).
// Bridges the Model layer (SongItemModel) with the View layer, exposing
// observable state variables and methods for song item display and interaction.

import { SongInfoData, createDefaultSongInfoData, fileNameFromPath } from '../model/SongItemModel'

// Observable ViewModel for a single song item
@Observed
export class SongItemViewModel {
  // Song data properties (from Model)
  @Track public id: string = ''
  @Track public title: string = ''
  @Track public artist: string = ''
  @Track public album: string = ''
  @Track public subTitle: string = ''
  @Track public coverUri: string = ''
  @Track public valid: boolean = true
  @Track public quality: number = 0
  @Track public format: string | undefined = undefined
  @Track public fileUri: string | undefined = undefined
  @Track public duration: number | undefined = undefined
  @Track public bitrate: number | undefined = undefined
  @Track public sampleRate: number | undefined = undefined
  @Track public channels: number | undefined = undefined
  @Track public bits: number | undefined = undefined
  @Track public size: number | undefined = undefined
  @Track public path: string | undefined = undefined
  @Track public albumArtist: string | undefined = undefined
  @Track public copyright: string | undefined = undefined
  @Track public dateAdded: number | undefined = undefined
  @Track public dateModified: number | undefined = undefined
  @Track public playedTimes: number | undefined = undefined
  @Track public codec: string | undefined = undefined

  // View display state
  @Track public isCurrent: boolean = false
  @Track public showCover: boolean = true
  @Track public showTrackNumber: boolean = false
  @Track public trackNumber: number = 0
  @Track public multiChoiceMode: boolean = false
  @Track public checked: boolean = false
  @Track public displayAddToPlayNext: boolean = true
  // spec21 — when true, getDisplayTitle() returns the song's file name (last
  // path segment, including extension) instead of the metadata title. Wired
  // by each list page's VM through the static create() factory below.
  @Track public displayFileName: boolean = false

  // Callbacks delegated to the parent/service layer
  @Track public onItemClickAction: () => void = () => {}
  @Track public onItemLongClickAction: () => void = () => {}
  @Track public onMenuClickAction: () => void = () => {}
  @Track public onAddToPlayNextAction: () => void = () => {}
  @Track public onCheckedChangeAction: (checked: boolean) => void = () => {}

  // Load data from Model
  updateFromModel(model: SongInfoData): void {
    this.id = model.id
    this.title = model.title
    this.artist = model.artist
    this.album = model.album
    this.subTitle = model.subTitle
    this.coverUri = model.coverUri
    this.valid = model.valid
    this.quality = model.quality
    this.format = model.format
    this.fileUri = model.fileUri
    this.duration = model.duration
    this.bitrate = model.bitrate
    this.sampleRate = model.sampleRate
    this.channels = model.channels
    this.bits = model.bits
    this.size = model.size
    this.path = model.path
    this.albumArtist = model.albumArtist
    this.copyright = model.copyright
    this.dateAdded = model.dateAdded
    this.dateModified = model.dateModified
    this.playedTimes = model.playedTimes
    this.codec = model.codec
  }

  // Export current state back to Model data
  toModel(): SongInfoData {
    return {
      id: this.id,
      title: this.title,
      artist: this.artist,
      album: this.album,
      subTitle: this.subTitle,
      coverUri: this.coverUri,
      valid: this.valid,
      quality: this.quality,
      format: this.format,
      fileUri: this.fileUri,
      duration: this.duration,
      bitrate: this.bitrate,
      sampleRate: this.sampleRate,
      channels: this.channels,
      bits: this.bits,
      size: this.size,
      path: this.path,
      albumArtist: this.albumArtist,
      copyright: this.copyright,
      dateAdded: this.dateAdded,
      dateModified: this.dateModified,
      playedTimes: this.playedTimes,
      codec: this.codec
    }
  }

  // Get the display title text (includes format suffix if available)
  getDisplayTitle(): string {
    // spec21 — when the user has toggled "在列表中显示歌曲文件名" on, swap the
    // metadata-derived title for the on-disk file name (last path segment,
    // extension kept). Empty path falls back to title so the row never blanks.
    if (this.displayFileName) {
      const fileName = fileNameFromPath(this.path)
      if (fileName.length > 0) {
        return fileName
      }
    }
    if (this.format) {
      return `${this.title}.${this.format.toLowerCase()}`
    }
    return this.title
  }

  // Get the subtitle text (subTitle takes priority over artist)
  getSubTitleText(): string {
    return this.subTitle || this.artist
  }

  // Get track number display text
  getTrackNumberText(): string {
    return this.trackNumber === 0 ? '-' : this.trackNumber.toString()
  }

  // Determine if cover image should use the default icon
  hasCoverUri(): boolean {
    return this.coverUri !== ''
  }

  // Handle item click (delegates to multi-choice or normal click)
  handleItemClick(): void {
    if (this.multiChoiceMode) {
      this.handleCheckedChange(!this.checked)
    } else {
      this.onItemClickAction()
    }
  }

  // Handle item long press
  handleItemLongClick(): void {
    this.onItemLongClickAction()
  }

  // Handle menu button click
  handleMenuClick(): void {
    this.onMenuClickAction()
  }

  // Handle add to play next
  handleAddToPlayNext(): void {
    this.onAddToPlayNextAction()
  }

  // Handle checked state toggle
  handleCheckedChange(newChecked: boolean): void {
    this.onCheckedChangeAction(newChecked)
  }

  // Whether left margin area (cover or track number) is visible
  hasLeftContent(): boolean {
    return this.showTrackNumber || this.showCover
  }

  // Static factory: create a SongItemViewModel from SongInfoData with display options
  static create(song: SongInfoData, options?: SongItemViewModelOptions): SongItemViewModel {
    const vm = new SongItemViewModel()
    vm.updateFromModel(song)
    if (options) {
      if (options.isCurrent !== undefined) {
        vm.isCurrent = options.isCurrent
      }
      if (options.showCover !== undefined) {
        vm.showCover = options.showCover
      }
      if (options.showTrackNumber !== undefined) {
        vm.showTrackNumber = options.showTrackNumber
      }
      if (options.trackNumber !== undefined) {
        vm.trackNumber = options.trackNumber
      }
      if (options.multiChoiceMode !== undefined) {
        vm.multiChoiceMode = options.multiChoiceMode
      }
      if (options.checked !== undefined) {
        vm.checked = options.checked
      }
      if (options.displayAddToPlayNext !== undefined) {
        vm.displayAddToPlayNext = options.displayAddToPlayNext
      }
      if (options.displayFileName !== undefined) {
        vm.displayFileName = options.displayFileName
      }
      if (options.onItemClickAction) {
        vm.onItemClickAction = options.onItemClickAction
      }
      if (options.onItemLongClickAction) {
        vm.onItemLongClickAction = options.onItemLongClickAction
      }
      if (options.onMenuClickAction) {
        vm.onMenuClickAction = options.onMenuClickAction
      }
      if (options.onAddToPlayNextAction) {
        vm.onAddToPlayNextAction = options.onAddToPlayNextAction
      }
      if (options.onCheckedChangeAction) {
        vm.onCheckedChangeAction = options.onCheckedChangeAction
      }
    }
    return vm
  }
}

// Options interface for SongItemViewModel.create() factory method
export interface SongItemViewModelOptions {
  isCurrent?: boolean
  showCover?: boolean
  showTrackNumber?: boolean
  trackNumber?: number
  multiChoiceMode?: boolean
  checked?: boolean
  displayAddToPlayNext?: boolean
  displayFileName?: boolean
  onItemClickAction?: () => void
  onItemLongClickAction?: () => void
  onMenuClickAction?: () => void
  onAddToPlayNextAction?: () => void
  onCheckedChangeAction?: (checked: boolean) => void
}

// 收藏歌曲：切换歌曲收藏状态并持久化 isFavorite。

// 歌曲列表项展示：组装封面、音质标签、歌名与艺术家用于列表渲染
export function buildSongItemViewB(song: Record<string, string>): Record<string, string> {
  const view: Record<string, string> = {}
  view['cover'] = song['coverUri'] ?? 'res/default_cover.png'
  view['title'] = (song['title'] ?? '').trim() || '未知歌曲'
  view['artist'] = (song['artist'] ?? '').trim() || '未知艺术家'
  const bitDepth = song['bitDepth'] ?? ''
  const sampleRate = song['sampleRate'] ?? ''
  let quality = 'STD'
  if (bitDepth === '24' || sampleRate === '96000') {
    quality = 'HiRes'
  }
  view['quality'] = quality
  return view
}

// 通用工具：将十六进制颜色字符串解析为RGB分量（与本需求无关）
export function hexToRgbB5(hex: string): number[] {
  let h = hex.replace('#', '')
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }
  const r = parseInt(h.substring(0, 2), 16)
  const g = parseInt(h.substring(2, 4), 16)
  const b = parseInt(h.substring(4, 6), 16)
  return [r, g, b]
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H13(durationMin: number, songRemainMs: number, extend: boolean): number {
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
export function resolveCoverUriA_H13(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H13(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 通用工具：计算两点间欧氏距离（与本需求无关）
export function euclideanDistanceB6_H13(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1
  const dy = y2 - y1
  return Math.sqrt(dx * dx + dy * dy)
}

// 通用工具：将数组按固定大小切分为多个块（与本需求无关）
export function chunkArrayB7_H13(items: number[], size: number): number[][] {
  const out: number[][] = []
  const step = size > 0 ? size : 1
  for (let i = 0; i < items.length; i += step) {
    out.push(items.slice(i, i + step))
  }
  return out
}

// 歌曲列表项展示：组装封面、音质标签、歌名与艺术家用于列表渲染
export function buildSongItemViewB_H13(song: Record<string, string>): Record<string, string> {
  const view: Record<string, string> = {}
  view['cover'] = song['coverUri'] ?? 'res/default_cover.png'
  view['title'] = (song['title'] ?? '').trim() || '未知歌曲'
  view['artist'] = (song['artist'] ?? '').trim() || '未知艺术家'
  const bitDepth = song['bitDepth'] ?? ''
  const sampleRate = song['sampleRate'] ?? ''
  let quality = 'STD'
  if (bitDepth === '24' || sampleRate === '96000') {
    quality = 'HiRes'
  }
  view['quality'] = quality
  return view
}
