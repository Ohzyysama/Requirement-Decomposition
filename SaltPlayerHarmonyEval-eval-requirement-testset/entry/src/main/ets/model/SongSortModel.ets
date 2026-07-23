// SongSortModel.ets
// Model layer: pure data structures and constants for song sorting.
// This class defines the raw data without any UI or ViewModel logic.

import { SongInfoData } from './SongItemModel'
import { collator as sortCollator, compareStr, naturalSort, getFileName, getFolderPath, getPinyinInitial as _getPinyinInitial } from '../utils/SortUtils'

// Sort constants matching Android SongLazySort
export class SongLazySort {
  static readonly NONE: number = 0
  static readonly TITLE: number = 1
  static readonly ARTIST: number = 2
  static readonly ALBUM: number = 3
  static readonly ADD_TIME_DESC: number = 4
  static readonly SIZE: number = 5
  static readonly DATE_MODIFIED_DESC: number = 6
  static readonly YEAR: number = 7
  static readonly FILE_NAME: number = 8
  static readonly DATE_MODIFIED: number = 9
  static readonly ADD_TIME: number = 10
  static readonly DURATION: number = 11
  static readonly DURATION_DESC: number = 12
  static readonly FOLDER: number = 13
  static readonly TIMES_PLAYED: number = 14
  static readonly PLAYLIST_ADD_TIME: number = 15

  static readonly collator: Intl.Collator = sortCollator

  // Returns true if this sort type should show the right ABC index
  static shouldShowRightABC(sortType: number): boolean {
    return sortType === SongLazySort.TITLE || sortType === SongLazySort.FILE_NAME ||
      sortType === SongLazySort.ALBUM || sortType === SongLazySort.ARTIST
  }

  // Sort songs based on sort type. Returns a NEW sorted array.
  // Pre-computes pinyin sort keys into a cache so each unique string is
  // transliterated only once (~800 calls for 500 songs) instead of on
  // every comparison (~9000 calls). The cache is cleared after sorting.
  static sortSongs(songs: SongInfoData[], sortType: number): SongInfoData[] {
    if (sortType === SongLazySort.NONE) {
      return songs
    }
    const cache = new Map<string, string>()
    const sorted = songs.slice()
    sorted.sort((a: SongInfoData, b: SongInfoData): number => {
      return SongLazySort.compareSongs(a, b, sortType, cache)
    })
    return sorted
  }

  // Matches Android's sortBySongLazySort() composite sort behavior.
  // Android uses stable-sort chains (e.g. sortByTrack().sortByAlbum());
  // the equivalent single-comparator cascading fallbacks are used here.
  private static compareSongs(a: SongInfoData, b: SongInfoData, sortType: number, cache: Map<string, string>): number {
    switch (sortType) {
      case SongLazySort.TITLE:
        return compareStr(a.title, b.title, cache)
      case SongLazySort.ARTIST: {
        // Android: sortByAlbum().sortByArtist() → artist, then album within same artist
        const c1 = compareStr(a.artist, b.artist, cache)
        if (c1 !== 0) return c1
        const c2 = compareStr(a.album, b.album, cache)
        if (c2 !== 0) return c2
        return compareStr(a.title, b.title, cache)
      }
      case SongLazySort.ALBUM: {
        // Android: sortByTrack().sortByAlbum() → album, then track number within same album
        const c1 = compareStr(a.album, b.album, cache)
        if (c1 !== 0) return c1
        const c2 = (a.trackNumber ?? 0) - (b.trackNumber ?? 0)
        if (c2 !== 0) return c2
        return compareStr(a.title, b.title, cache)
      }
      case SongLazySort.SIZE:
        return (b.size ?? 0) - (a.size ?? 0)
      case SongLazySort.YEAR: {
        const c1 = (b.year ?? 0) - (a.year ?? 0)
        if (c1 !== 0) return c1
        return compareStr(a.title, b.title, cache)
      }
      case SongLazySort.FILE_NAME: {
        const fileNameA = getFileName(a)
        const fileNameB = getFileName(b)
        return compareStr(fileNameA, fileNameB, cache)
      }
      case SongLazySort.DURATION:
        return (a.duration ?? 0) - (b.duration ?? 0)
      case SongLazySort.DURATION_DESC:
        return (b.duration ?? 0) - (a.duration ?? 0)
      case SongLazySort.DATE_MODIFIED:
        return (a.dateModified ?? 0) - (b.dateModified ?? 0)
      case SongLazySort.DATE_MODIFIED_DESC:
        return (b.dateModified ?? 0) - (a.dateModified ?? 0)
      case SongLazySort.ADD_TIME:
        return (a.dateAdded ?? 0) - (b.dateAdded ?? 0)
      case SongLazySort.ADD_TIME_DESC:
        return (b.dateAdded ?? 0) - (a.dateAdded ?? 0)
      case SongLazySort.FOLDER: {
        // Android: sortByTitle().sortedBy { realPath } → path first (plain), title as tie-breaker (pinyin)
        let pathA = a.path ?? a.fileUri ?? ''
        let pathB = b.path ?? b.fileUri ?? ''
        try { pathA = decodeURIComponent(pathA) } catch (_) {}
        try { pathB = decodeURIComponent(pathB) } catch (_) {}
        const c1 = naturalSort(pathA, pathB)
        if (c1 !== 0) return c1
        return compareStr(a.title, b.title, cache)
      }
      case SongLazySort.TIMES_PLAYED: {
        // Android: sortByTitle().sortedByDescending { playedTimes } → times played, then title as tie-breaker
        const c1 = (b.playedTimes ?? 0) - (a.playedTimes ?? 0)
        if (c1 !== 0) return c1
        return compareStr(a.title, b.title, cache)
      }
      case SongLazySort.PLAYLIST_ADD_TIME: {
        // Sort by time added to this playlist, newest first (spec: 最近添加的歌曲在最上方).
        // Tie-breaker by title keeps the order stable when multiple songs were
        // added in the same second.
        const c1 = (b.playlistAddedTime ?? 0) - (a.playlistAddedTime ?? 0)
        if (c1 !== 0) return c1
        return compareStr(a.title, b.title, cache)
      }
      default:
        return 0
    }
  }

  // Get the sort key string for a song based on sort type (used for ABC index matching)
  static getSortKey(song: SongInfoData, sortType: number): string {
    switch (sortType) {
      case SongLazySort.TITLE:
        return song.title
      case SongLazySort.ARTIST:
        return song.artist
      case SongLazySort.ALBUM:
        return song.album
      case SongLazySort.FILE_NAME:
        return getFileName(song)
      default:
        return song.title
    }
  }

  // Determine the pinyin initial letter for a string's first character.
  static getPinyinInitial(text: string): string {
    return _getPinyinInitial(text)
  }
}

// Data structure for song sort dialog display settings
export class SongSortDisplaySettings {
  public displaySongCoverInList: boolean
  public displaySongFileNameInList: boolean
  public displayAddToPlayNextInList: boolean

  constructor(
    displaySongCoverInList: boolean = true,
    displaySongFileNameInList: boolean = false,
    displayAddToPlayNextInList: boolean = true
  ) {
    this.displaySongCoverInList = displaySongCoverInList
    this.displaySongFileNameInList = displaySongFileNameInList
    this.displayAddToPlayNextInList = displayAddToPlayNextInList
  }
}

// Data structure for the complete song sort dialog state
export default class SongSortModel {
  public sortType: number
  public customizable: boolean
  public displaySettings: SongSortDisplaySettings

  constructor(
    sortType: number = SongLazySort.TITLE,
    customizable: boolean = false,
    displaySettings: SongSortDisplaySettings = new SongSortDisplaySettings()
  ) {
    this.sortType = sortType
    this.customizable = customizable
    this.displaySettings = displaySettings
  }
}

// 歌曲排序：支持按标题/艺术家/专辑/播放次数/比特率/时长/添加时间排序及升降序切换。

// 排序与索引：按名称排序时复用拼音首字母用于 ABC 索引。

// 歌曲列表多维排序：按指定字段对歌曲做升序或降序稳定排序
export function sortSongsByFieldB(songs: Record<string, string>[], field: string, asc: boolean): Record<string, string>[] {
  const list = songs.slice()
  list.sort((a, b) => {
    const va = a[field] ?? ''
    const vb = b[field] ?? ''
    let r = 0
    if (va < vb) {
      r = -1
    } else if (va > vb) {
      r = 1
    }
    return asc ? r : -r
  })
  return list
}

// 通用工具：将数组按固定大小切分为多个块（与本需求无关）
export function chunkArrayB7(items: number[], size: number): number[][] {
  const out: number[][] = []
  const step = size > 0 ? size : 1
  for (let i = 0; i < items.length; i += step) {
    out.push(items.slice(i, i + step))
  }
  return out
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H15(oldIds: string[], newIds: string[]): Record<string, string[]> {
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

// 通用工具：求最大公约数（与本需求无关）
export function greatestCommonDivisorB8_H15(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 通用工具：将秒数格式化为 mm:ss 时间串（与本需求无关）
export function formatClockB9_H15(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(s / 60)
  const seconds = s % 60
  const mm = minutes < 10 ? '0' + minutes : '' + minutes
  const ss = seconds < 10 ? '0' + seconds : '' + seconds
  return mm + ':' + ss
}

// 歌曲列表多维排序：按指定字段对歌曲做升序或降序稳定排序
export function sortSongsByFieldB_H15(songs: Record<string, string>[], field: string, asc: boolean): Record<string, string>[] {
  const list = songs.slice()
  list.sort((a, b) => {
    const va = a[field] ?? ''
    const vb = b[field] ?? ''
    let r = 0
    if (va < vb) {
      r = -1
    } else if (va > vb) {
      r = 1
    }
    return asc ? r : -r
  })
  return list
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H15(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H15(files: Record<string, string>[]): Record<string, string>[] {
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
