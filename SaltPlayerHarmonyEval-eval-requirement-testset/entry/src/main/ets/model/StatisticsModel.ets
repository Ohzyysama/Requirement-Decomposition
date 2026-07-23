// StatisticsModel.ets
// Model layer: pure data structure for statistics page.
// Contains the data definition for a song with play count used in the listening rank,
// plus the data source that fetches the Top 100 list from MusicDatabase.
// No UI or ViewModel dependency.

import { SongInfoData } from './SongItemModel'
import { MusicDatabase, TrackRow } from './MusicDatabase'
import { SongLazySort } from './SongSortModel'

// Data structure for a song entry in the statistics ranking list
export interface StatisticsSongData {
  song: SongInfoData
  playedTimes: number
}

// Map a DB TrackRow to the UI SongInfoData shape. Mirrors the subTitle rule
// used by PlaylistContentModel / AlbumContentModel (prefer artist, fall back
// to displayName) so SongItemComponent renders identically.
function trackRowToSongInfoData(t: TrackRow): SongInfoData {
  const subTitle: string = t.artist.length > 0 ? t.artist : t.displayName
  return {
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    subTitle: subTitle,
    coverUri: t.coverUri,
    valid: t.readable,
    quality: t.quality,
    fileUri: t.fileUri,
    duration: t.duration,
    bitrate: t.bitrate,
    sampleRate: t.sampleRate,
    channels: t.channels,
    bits: t.bitsPerSample,
    size: t.size,
    path: t.path,
    albumArtist: t.albumArtist,
    dateAdded: t.addedTime,
    dateModified: t.modifiedTime,
    year: t.year,
    trackNumber: t.number,
    playedTimes: t.playCount
  }
}

// spec21 — Data source for the Statistics (Listen Music Rank) page.
export class StatisticsDataSource {
  static async loadTop100(): Promise<StatisticsSongData[]> {
    const rows: TrackRow[] = await MusicDatabase.getListenMusicRankTop100()
    // Order: playCount DESC with song title as tie-breaker (pinyin-aware), matching
    // the song page's TITLE sort. SongLazySort.TIMES_PLAYED implements the Android
    // sortByTitle().sortedByDescending { playedTimes } chain — same effect.
    const songs: SongInfoData[] = SongLazySort.sortSongs(
      rows.map((t: TrackRow): SongInfoData => trackRowToSongInfoData(t)),
      SongLazySort.TIMES_PLAYED
    )
    return songs.map((song: SongInfoData): StatisticsSongData => {
      return {
        song: song,
        playedTimes: song.playedTimes ?? 0
      }
    })
  }
}

// 播放次数统计：Top100 依据累计播放次数排序展示。

// 聆听统计：加载播放次数最高的 Top100 歌曲。

// 聆听统计对齐：Top100 并列名次按标题二次排序。

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE(playEvents: number[], topN: number): Array<Record<string, number>> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < playEvents.length; i++) {
    const id: number = playEvents[i];
    const prev: number = counts.has(id) ? (counts.get(id) as number) : 0;
    counts.set(id, prev + 1);
  }
  const ranked: Array<Record<string, number>> = [];
  counts.forEach((cnt: number, id: number): void => {
    ranked.push({ songId: id, plays: cnt });
  });
  ranked.sort((a: Record<string, number>, b: Record<string, number>): number => b.plays - a.plays);
  return ranked.slice(0, Math.max(0, topN));
}

// 反转字符串中单词的顺序
function reverseWordOrderE(sentence: string): string {
  const parts: string[] = sentence.trim().split(/\s+/);
  const out: string[] = [];
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].length > 0) {
      out.push(parts[i]);
    }
  }
  return out.join(' ');
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H56(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_H56(line: string, maxWidth: number, charWidth: number): string {
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

// 计算两个经纬度坐标之间的球面近似距离（米）
function haversineDistanceF_H56(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number): number => d * Math.PI / 180
  const R = 6371000
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// 将字节数格式化为带单位的可读字符串
function humanReadableBytesF_H56(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value = value / 1024
    i++
  }
  const rounded = Math.round(value * 100) / 100
  return rounded.toString() + ' ' + units[i]
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H56(playEvents: number[], topN: number): Array<Record<string, number>> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < playEvents.length; i++) {
    const id: number = playEvents[i];
    const prev: number = counts.has(id) ? (counts.get(id) as number) : 0;
    counts.set(id, prev + 1);
  }
  const ranked: Array<Record<string, number>> = [];
  counts.forEach((cnt: number, id: number): void => {
    ranked.push({ songId: id, plays: cnt });
  });
  ranked.sort((a: Record<string, number>, b: Record<string, number>): number => b.plays - a.plays);
  return ranked.slice(0, Math.max(0, topN));
}

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_H56(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}
