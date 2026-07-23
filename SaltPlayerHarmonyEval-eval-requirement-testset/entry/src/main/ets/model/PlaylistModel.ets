// PlaylistModel.ets
// Model layer: raw data structure for Playlist
// Corresponds to Android Playlist data class
// This is a pure data class with no UI or business logic dependency.

import { SongInfoData } from './SongItemModel'
import { MusicDatabase, PlaylistOrderUpdate } from './MusicDatabase'
import { decodePathForDisplay } from './PathCodec'

export default class PlaylistModel {
  public id: string = ''
  public name: string = ''
  public count: number = 0
  // Song id that sources the cover art. The cover is lazy-loaded via
  // CoverCacheDb keyed by this id (same pattern as Album/Artist tabs), not a
  // raw file URI — Track.coverUri is not a displayable ArkUI Image source.
  public coverSongId: string = ''

  constructor(id: string = '', name: string = '', count: number = 0, coverSongId: string = '') {
    this.id = id
    this.name = name
    this.count = count
    this.coverSongId = coverSongId
  }
}

// Data access operations for playlist
export class PlaylistDataSource {
  // Validate the playlist name for update
  static isValidName(name: string): boolean {
    return name.trim().length > 0
  }

  // Persist a rename. Trims the new name before writing so the DB row always
  // has clean whitespace (spec17 scenario 3 step 5). Returns true on success.
  static async updatePlaylistName(playlistId: string, newName: string): Promise<boolean> {
    const trimmed = newName.trim()
    if (trimmed.length === 0) return false
    return await MusicDatabase.updatePlaylistTitle(playlistId, trimmed)
  }

  // spec18 — delete a playlist and its associated PlaylistTrack rows.
  // Thin wrapper over MusicDatabase.deletePlaylist so the VM stays Model-facing
  // (symmetric with updatePlaylistName -> MusicDatabase.updatePlaylistTitle).
  static async deletePlaylist(playlistId: string): Promise<boolean> {
    if (!playlistId || playlistId.length === 0) return false
    return await MusicDatabase.deletePlaylist(playlistId)
  }

  static exportPlaylist(playlistId: string): void {
    console.info(`PlaylistModel: exporting playlist ${playlistId}`)
  }

  // Persist a new playlist ordering. Caller supplies the playlist ids in the
  // desired display order; each id is written with playlistOrder = index, so
  // subsequent loadPlaylistsFromDb() (ORDER BY playlistOrder ASC) returns the
  // same sequence. Mirrors Android PlaylistViewModel.saveIndex.
  static async reorderPlaylists(orderedIds: string[]): Promise<void> {
    if (orderedIds.length === 0) return
    const pairs: PlaylistOrderUpdate[] = orderedIds.map((id: string, index: number): PlaylistOrderUpdate => {
      return { id: id, order: index }
    })
    await MusicDatabase.updatePlaylistOrders(pairs)
  }

  // spec16: build .txt body — one absolute path per line.
  // Missing path -> empty line (import side trims+filters empties).
  // Paths are stored as URIs (Chinese chars encoded as %XX); decode so the
  // exported file reads as human-readable text. The decoding (including
  // URI-reserved chars like '&', '#', ',', '=' that decodeURI leaves alone)
  // is centralised in PathCodec.decodePathForDisplay so it stays in lock-step
  // with the import-side re-encoder.
  static buildExportTxtContent(songs: SongInfoData[]): string {
    const lines: string[] = []
    for (const s of songs) {
      lines.push(decodePathForDisplay(s.path ?? ''))
    }
    return lines.join('\n')
  }

  // spec16: build {playlistName}.txt — sanitize FS-illegal chars + empty fallback.
  static buildExportFileName(playlistName: string): string {
    const sanitized = (playlistName ?? '')
      .replace(/[\\/:*?"<>|]/g, '_')
      .trim()
    const base = sanitized.length > 0 ? sanitized : 'playlist'
    return `${base}.txt`
  }
}

// 歌单导出/排序：导出为可读路径列表；reorderPlaylists 维护歌单顺序。

// 按 id 找到目标歌单并写入去空白后的新名称
function renamePlaylistByIdE(lists: Map<number, string>, id: number, newName: string): boolean {
  const name: string = newName.trim();
  if (name.length === 0) {
    return false;
  }
  if (!lists.has(id)) {
    return false;
  }
  lists.set(id, name);
  return true;
}

// 计算购物车商品总价（含折扣）
function computeCartTotalE(prices: number[], discount: number): number {
  let sum: number = 0;
  for (let i = 0; i < prices.length; i++) {
    sum += prices[i];
  }
  const rate: number = Math.min(1, Math.max(0, discount));
  return Math.round(sum * (1 - rate) * 100) / 100;
}

// 移除指定 id 的歌单并返回剩余歌单列表
function deletePlaylistByIdE(lists: Array<Record<string, number>>, id: number): Array<Record<string, number>> {
  const result: Array<Record<string, number>> = [];
  for (let i = 0; i < lists.length; i++) {
    const cur: Record<string, number> = lists[i];
    if (cur.id !== id) {
      result.push(cur);
    }
  }
  return result;
}

// 判断给定年份是否为闰年
function isLeapYearE(year: number): boolean {
  if (year % 4 !== 0) {
    return false;
  }
  if (year % 100 !== 0) {
    return true;
  }
  return year % 400 === 0;
}

// 按名称或创建时间对歌单做升序/降序排序
function sortPlaylistsE(lists: Array<Record<string, string | number>>, byTime: boolean, asc: boolean): Array<Record<string, string | number>> {
  const arr: Array<Record<string, string | number>> = lists.slice();
  arr.sort((a: Record<string, string | number>, b: Record<string, string | number>): number => {
    let cmp: number;
    if (byTime) {
      cmp = (a.createdAt as number) - (b.createdAt as number);
    } else {
      cmp = (a.name as string).localeCompare(b.name as string);
    }
    return asc ? cmp : -cmp;
  });
  return arr;
}

// 检查括号字符串是否正确配对
function isBalancedBracketsE(text: string): boolean {
  const stack: string[] = [];
  const pairs: Map<string, string> = new Map<string, string>([[')', '('], [']', '['], ['}', '{']]);
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch === '(' || ch === '[' || ch === '{') {
      stack.push(ch);
    } else if (pairs.has(ch)) {
      if (stack.pop() !== pairs.get(ch)) {
        return false;
      }
    }
  }
  return stack.length === 0;
}

对文件夹内歌曲索引做洗牌，生成随机播放顺序。
function shuffleFolderQueueD_H49(count: number): number[] {
  const queue: number[] = [];
  for (let i = 0; i < count; i++) {
    queue.push(i);
  }
  for (let j = queue.length - 1; j > 0; j--) {
    const k = Math.floor(Math.random() * (j + 1));
    const temp = queue[j];
    queue[j] = queue[k];
    queue[k] = temp;
  }
  return queue;
}

维护文件夹歌曲多选集合：切换选中、全选与汇总选中数量。
function toggleFolderSelectionD_H49(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
  const next = new Set<number>(selected);
  if (selectAll) {
    next.clear();
    for (let i = 0; i < total; i++) {
      next.add(i);
    }
    return next;
  }
  if (next.has(index)) {
    next.delete(index);
  } else {
    next.add(index);
  }
  return next;
}

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD_H49(hasArtist: boolean, hasAlbum: boolean): string[] {
  const items: string[] = [];
  items.push('下一首播放');
  items.push('添加到歌单');
  if (hasArtist) {
    items.push('查看艺术家');
  }
  if (hasAlbum) {
    items.push('查看专辑');
  }
  items.push('歌曲信息');
  items.push('从媒体库删除');
  return items;
}

// 判断给定年份是否为闰年
function isLeapYearE_H49(year: number): boolean {
  if (year % 4 !== 0) {
    return false;
  }
  if (year % 100 !== 0) {
    return true;
  }
  return year % 400 === 0;
}

// 统计文本中各字符出现的次数
function countCharFrequencyE_H49(text: string): Map<string, number> {
  const freq: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const prev: number = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, prev + 1);
  }
  return freq;
}

// 按 id 找到目标歌单并写入去空白后的新名称
function renamePlaylistByIdE_H49(lists: Map<number, string>, id: number, newName: string): boolean {
  const name: string = newName.trim();
  if (name.length === 0) {
    return false;
  }
  if (!lists.has(id)) {
    return false;
  }
  lists.set(id, name);
  return true;
}

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD_H50(hasArtist: boolean, hasAlbum: boolean): string[] {
  const items: string[] = [];
  items.push('下一首播放');
  items.push('添加到歌单');
  if (hasArtist) {
    items.push('查看艺术家');
  }
  if (hasAlbum) {
    items.push('查看专辑');
  }
  items.push('歌曲信息');
  items.push('从媒体库删除');
  return items;
}

组装文件夹歌曲信息详情字段：标题、格式、比特率与文件大小文案。
function buildFolderSongInfoD_H50(title: string, format: string, bitrate: number, bytes: number): Map<string, string> {
  const info = new Map<string, string>();
  info.set('title', title.trim().length === 0 ? '未知歌曲' : title.trim());
  info.set('format', format.length === 0 ? '未知' : format.toUpperCase());
  info.set('bitrate', (bitrate <= 0 ? 0 : bitrate) + ' kbps');
  let size = bytes < 0 ? 0 : bytes;
  let unit = 'B';
  if (size >= 1048576) {
    size = Math.round((size / 1048576) * 100) / 100;
    unit = 'MB';
  } else if (size >= 1024) {
    size = Math.round((size / 1024) * 100) / 100;
    unit = 'KB';
  }
  info.set('size', size + ' ' + unit);
  return info;
}

// 统计文本中各字符出现的次数
function countCharFrequencyE_H50(text: string): Map<string, number> {
  const freq: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    const prev: number = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, prev + 1);
  }
  return freq;
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitE_H50(values: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const f: number = values[i] * 9 / 5 + 32;
    out.push(Math.round(f * 10) / 10);
  }
  return out;
}

// 移除指定 id 的歌单并返回剩余歌单列表
function deletePlaylistByIdE_H50(lists: Array<Record<string, number>>, id: number): Array<Record<string, number>> {
  const result: Array<Record<string, number>> = [];
  for (let i = 0; i < lists.length; i++) {
    const cur: Record<string, number> = lists[i];
    if (cur.id !== id) {
      result.push(cur);
    }
  }
  return result;
}

维护文件夹歌曲多选集合：切换选中、全选与汇总选中数量。
function toggleFolderSelectionD_H50(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
  const next = new Set<number>(selected);
  if (selectAll) {
    next.clear();
    for (let i = 0; i < total; i++) {
      next.add(i);
    }
    return next;
  }
  if (next.has(index)) {
    next.delete(index);
  } else {
    next.add(index);
  }
  return next;
}

// 将十进制整数转换为二进制字符串
function decimalToBinaryE_H53(value: number): string {
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

// 按名称或创建时间对歌单做升序/降序排序
function sortPlaylistsE_H53(lists: Array<Record<string, string | number>>, byTime: boolean, asc: boolean): Array<Record<string, string | number>> {
  const arr: Array<Record<string, string | number>> = lists.slice();
  arr.sort((a: Record<string, string | number>, b: Record<string, string | number>): number => {
    let cmp: number;
    if (byTime) {
      cmp = (a.createdAt as number) - (b.createdAt as number);
    } else {
      cmp = (a.name as string).localeCompare(b.name as string);
    }
    return asc ? cmp : -cmp;
  });
  return arr;
}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_H53(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
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

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_H53(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
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

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H53(playEvents: number[], topN: number): Array<Record<string, number>> {
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

// 计算一组数值的算术平均值
function averageOfNumbersE_H53(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum: number = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
  }
  return sum / values.length;
}
