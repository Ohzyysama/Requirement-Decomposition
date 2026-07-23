// SearchAllSongsModel.ets
// Model layer: data structure and data access for search all songs feature.
// Contains no UI dependency. Responsible for data retrieval and song search logic.

import { SongInfoData } from './SongItemModel'
import { ScanningDataSource, ScannedSongData } from './ScanningModel'

// Router params interface for SearchAllSongsPage
export interface SearchAllSongsRouterParams {
  validCount: number
  currentSongTitle: string
  currentSongArtist: string
  isPlaying: boolean
}

// Model class encapsulating search data and search logic
export class SearchAllSongsModel {
  // Perform search against all scanned songs
  // Matches keyword against title, artist, and album (case-insensitive)
  static searchSongs(keyword: string): SongInfoData[] {
    const trimmed = keyword.trim()
    if (trimmed.length === 0) {
      return []
    }
    const lower = trimmed.toLowerCase()
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const results: SongInfoData[] = []
    for (const s of scanned) {
      if (s.title.toLowerCase().includes(lower) ||
        s.artist.toLowerCase().includes(lower) ||
        s.album.toLowerCase().includes(lower)) {
        results.push({
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          subTitle: s.artist.length > 0 ? s.artist : s.displayName,
          coverUri: s.coverUri ?? '',
          valid: true,
          quality: s.quality,
          fileUri: s.fileUri,
          duration: s.duration,
          bitrate: s.bitrate,
          sampleRate: s.sampleRate,
          channels: s.channels,
          size: s.size,
          path: s.fileUri,
          year: s.year,
          dateAdded: s.dateAdded,
          dateModified: s.dateModified
        })
      }
    }
    return results
  }
}

// 全局搜索：按标题/艺术家/专辑大小写不敏感匹配，输入即时返回结果。

// 全局搜索：优化标题/艺术家/专辑的匹配顺序，命中标题优先。

// 歌曲列表搜索：按关键字匹配歌名或艺术家，忽略大小写
export function searchAllSongsB(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
  const kw = keyword.trim().toLowerCase()
  if (kw.length === 0) {
    return songs
  }
  const matched: Record<string, string>[] = []
  for (const s of songs) {
    const title = (s['title'] ?? '').toLowerCase()
    const artist = (s['artist'] ?? '').toLowerCase()
    if (title.indexOf(kw) >= 0 || artist.indexOf(kw) >= 0) {
      matched.push(s)
    }
  }
  return matched
}

// 通用工具：计算两点间欧氏距离（与本需求无关）
export function euclideanDistanceB6(x1: number, y1: number, x2: number, y2: number): number {
  const dx = x2 - x1
  const dy = y2 - y1
  return Math.sqrt(dx * dx + dy * dy)
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 将十进制整数转换为二进制字符串
function decimalToBinaryE(value: number): string {
  let n: number = Math.abs(Math.floor(value));
  if (n === 0) {
    return '0';
  }
  let bits: string = '';
  while (n > 0) {
    bits = (n % 2) + bits;
    n = Math.floor(n / 2);
  }
  return value < 0 ? '-' + bits : bits;
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H14(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H14(files: Record<string, string>[]): Record<string, string>[] {
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

// 通用工具：将数组按固定大小切分为多个块（与本需求无关）
export function chunkArrayB7_H14(items: number[], size: number): number[][] {
  const out: number[][] = []
  const step = size > 0 ? size : 1
  for (let i = 0; i < items.length; i += step) {
    out.push(items.slice(i, i + step))
  }
  return out
}

// 通用工具：求最大公约数（与本需求无关）
export function greatestCommonDivisorB8_H14(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 歌曲列表搜索：按关键字匹配歌名或艺术家，忽略大小写
export function searchAllSongsB_H14(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
  const kw = keyword.trim().toLowerCase()
  if (kw.length === 0) {
    return songs
  }
  const matched: Record<string, string>[] = []
  for (const s of songs) {
    const title = (s['title'] ?? '').toLowerCase()
    const artist = (s['artist'] ?? '').toLowerCase()
    if (title.indexOf(kw) >= 0 || artist.indexOf(kw) >= 0) {
      matched.push(s)
    }
  }
  return matched
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H14(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H55(playEvents: number[], topN: number): Array<Record<string, number>> {
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
function transitionDesktopLyricsStateF_H55(current: string, action: string, metadataReady: boolean): string {
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

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H55(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 反转字符串中单词的顺序
function reverseWordOrderE_H55(sentence: string): string {
  const parts: string[] = sentence.trim().split(/\s+/);
  const out: string[] = [];
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].length > 0) {
      out.push(parts[i]);
    }
  }
  return out.join(' ');
}

// 计算两个经纬度坐标之间的球面近似距离（米）
function haversineDistanceF_H55(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number): number => d * Math.PI / 180
  const R = 6371000
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_H55(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 通用工具：将十六进制颜色字符串解析为RGB分量（与本需求无关）
export function hexToRgbB5_X8(hex: string): number[] {
  let h = hex.replace('#', '')
  if (h.length === 3) {
    h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
  }
  const r = parseInt(h.substring(0, 2), 16)
  const g = parseInt(h.substring(2, 4), 16)
  const b = parseInt(h.substring(4, 6), 16)
  return [r, g, b]
}

// 歌曲列表搜索：按关键字匹配歌名或艺术家，忽略大小写
export function searchAllSongsB_X8(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
  const kw = keyword.trim().toLowerCase()
  if (kw.length === 0) {
    return songs
  }
  const matched: Record<string, string>[] = []
  for (const s of songs) {
    const title = (s['title'] ?? '').toLowerCase()
    const artist = (s['artist'] ?? '').toLowerCase()
    if (title.indexOf(kw) >= 0 || artist.indexOf(kw) >= 0) {
      matched.push(s)
    }
  }
  return matched
}

// 歌曲列表多维排序：按指定字段对歌曲做升序或降序稳定排序
export function sortSongsByFieldB_X8(songs: Record<string, string>[], field: string, asc: boolean): Record<string, string>[] {
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

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_X14(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 歌曲列表搜索：按关键字匹配歌名或艺术家，忽略大小写
export function searchAllSongsB_X14(songs: Record<string, string>[], keyword: string): Record<string, string>[] {
  const kw = keyword.trim().toLowerCase()
  if (kw.length === 0) {
    return songs
  }
  const matched: Record<string, string>[] = []
  for (const s of songs) {
    const title = (s['title'] ?? '').toLowerCase()
    const artist = (s['artist'] ?? '').toLowerCase()
    if (title.indexOf(kw) >= 0 || artist.indexOf(kw) >= 0) {
      matched.push(s)
    }
  }
  return matched
}

对文件夹内歌曲名做大小写不敏感的关键词过滤，空关键词返回全部。
function searchFolderSongsD_X14(songs: string[], keyword: string): string[] {
  const query = keyword.trim().toLowerCase();
  if (query.length === 0) {
    return songs.slice(0);
  }
  const matched: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const name = songs[i].toLowerCase();
    if (name.indexOf(query) >= 0) {
      matched.push(songs[i]);
    }
  }
  return matched;
}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_X14(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
  const stats: Map<string, Record<string, number>> = new Map<string, Record<string, number>>();
  for (let i = 0; i < tracks.length; i++) {
    const q: string = tracks[i].quality as string;
    const size: number = tracks[i].size as number;
    if (!stats.has(q)) {
      stats.set(q, { count: 0, bytes: 0 });
    }
    const bucket: Record<string, number> = stats.get(q) as Record<string, number>;
    bucket.count += 1;
    bucket.bytes += size;
  }
  return stats;
}

// 通用工具：将字节数格式化为可读字符串（与本需求无关）
export function formatBytesB1_X14(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let idx = 0
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024
    idx++
  }
  return Math.round(value * 100) / 100 + ' ' + units[idx]
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitE_X14(values: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const f: number = values[i] * 9 / 5 + 32;
    out.push(Math.round(f * 10) / 10);
  }
  return out;
}
