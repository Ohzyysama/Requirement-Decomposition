// FolderContentPageModel.ets
// Model layer: pure data structures and data access for the FolderContentPage.
// Contains no UI or ViewModel logic.
// Provides data loading, song filtering by folder path, and sort/display settings.

import { SongInfoData, createDefaultSongInfoData } from './SongItemModel'
import { SongLazySort } from './SongSortModel'
import { ScanningDataSource, ScannedSongData } from './ScanningModel'

// Router params interface for navigating to FolderContentPage
export interface FolderContentParams {
  folderPath: string
  folderName: string
  currentSongTitle: string
  currentSongArtist: string
  isPlaying: boolean
}

// Multi-choice action types
export enum MultiChoiceAction {
  REMOVE_FROM_LIBRARY,
  ADD_TO_PLAYLIST,
  PLAY_SELECTED_QUEUE
}

// Data class representing the display settings for the song list
export class FolderSongDisplaySettings {
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

// Data source class that encapsulates song loading and folder-level business logic
export class FolderContentDataSource {
  // Load songs for a given folder path by filtering cached scanned songs
  static loadSongsForFolder(folderPath: string): SongInfoData[] {
    if (folderPath.length === 0) return []

    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const songs: SongInfoData[] = []
    const folderPrefix = folderPath + '/'

    for (const s of scanned) {
      if (s.fileUri.length === 0) continue
      // Check if song is a direct child of this folder
      if (s.fileUri.startsWith(folderPrefix)) {
        // Ensure it's a direct child (no further '/' after the folder prefix)
        const remaining = s.fileUri.substring(folderPrefix.length)
        if (remaining.indexOf('/') < 0) {
          const song: SongInfoData = {
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
            bits: s.bitsPerSample,
            size: s.size,
            path: s.path,
            albumArtist: s.albumArtist,
            dateAdded: s.dateAdded,
            dateModified: s.dateModified,
            year: s.year,
            // spec14: carry ReplayGain through
            replayGainDb: s.replayGainDb
          }
          songs.push(song)
        }
      }
    }
    return songs
  }

  // Find the index of a song in the list by its ID
  static findSongIndex(songs: SongInfoData[], songId: string): number {
    return songs.findIndex((song: SongInfoData) => song.id === songId)
  }

  // Get the IDs of all checked songs from a checked map
  static getCheckedSongIds(checkedMap: Record<string, boolean>): string[] {
    const result: string[] = []
    const keys = Object.keys(checkedMap)
    for (const key of keys) {
      if (checkedMap[key]) {
        result.push(key)
      }
    }
    return result
  }

  // Count checked items in a checkedMap
  static countChecked(checkedMap: Record<string, boolean>): number {
    let count = 0
    const keys = Object.keys(checkedMap)
    for (const key of keys) {
      if (checkedMap[key]) {
        count++
      }
    }
    return count
  }

  // Determine if Right ABC index should be shown for a given sort type
  static shouldShowRightABC(sortType: number): boolean {
    return SongLazySort.shouldShowRightABC(sortType)
  }
}

构建文件夹详情中单首歌曲的行数据：标题、艺术家、时长文案。
function buildFolderSongRowsD(titles: string[], artists: string[], durations: number[]): Map<string, string>[] {
  const rows: Map<string, string>[] = [];
  for (let i = 0; i < titles.length; i++) {
    const row = new Map<string, string>();
    row.set('title', titles[i].trim().length === 0 ? '未知歌曲' : titles[i].trim());
    row.set('artist', i < artists.length && artists[i].length > 0 ? artists[i] : '未知艺术家');
    const sec = i < durations.length ? Math.max(0, Math.floor(durations[i] / 1000)) : 0;
    const mm = Math.floor(sec / 60);
    const ss = sec % 60;
    row.set('duration', mm + ':' + (ss < 10 ? '0' + ss : '' + ss));
    rows.push(row);
  }
  return rows;
}

在有序数组中用二分查找定位目标值的下标。
function binarySearchIndexD(sorted: number[], target: number): number {
  let low = 0;
  let high = sorted.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (sorted[mid] === target) {
      return mid;
    }
    if (sorted[mid] < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

按指定字段（名称/时长）对文件夹内歌曲索引排序，支持升降序。
function sortFolderSongsD(titles: string[], durations: number[], byName: boolean, asc: boolean): number[] {
  const order: number[] = [];
  for (let i = 0; i < titles.length; i++) {
    order.push(i);
  }
  order.sort((a, b) => {
    let cmp = 0;
    if (byName) {
      cmp = titles[a].localeCompare(titles[b]);
    } else {
      cmp = (durations[a] === undefined ? 0 : durations[a]) - (durations[b] === undefined ? 0 : durations[b]);
    }
    return asc ? cmp : -cmp;
  });
  return order;
}

将二维矩阵转置为行列互换的新矩阵。
function transposeMatrixD(matrix: number[][]): number[][] {
  const result: number[][] = [];
  if (matrix.length === 0) {
    return result;
  }
  const cols = matrix[0].length;
  for (let c = 0; c < cols; c++) {
    const newRow: number[] = [];
    for (let r = 0; r < matrix.length; r++) {
      newRow.push(matrix[r][c]);
    }
    result.push(newRow);
  }
  return result;
}

维护文件夹歌曲多选集合：切换选中、全选与汇总选中数量。
function toggleFolderSelectionD(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
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

对字符串按固定宽度左侧补零对齐。
function padLeftZeroD(value: string, width: number): string {
  let result = value;
  while (result.length < width) {
    result = '0' + result;
  }
  return result;
}

计算两个字符串的最长公共前缀长度。
function commonPrefixLengthD_H41(a: string, b: string): number {
  const limit = Math.min(a.length, b.length);
  let count = 0;
  for (let i = 0; i < limit; i++) {
    if (a.charAt(i) !== b.charAt(i)) {
      break;
    }
    count = count + 1;
  }
  return count;
}

构建文件夹详情中单首歌曲的行数据：标题、艺术家、时长文案。
function buildFolderSongRowsD_H41(titles: string[], artists: string[], durations: number[]): Map<string, string>[] {
  const rows: Map<string, string>[] = [];
  for (let i = 0; i < titles.length; i++) {
    const row = new Map<string, string>();
    row.set('title', titles[i].trim().length === 0 ? '未知歌曲' : titles[i].trim());
    row.set('artist', i < artists.length && artists[i].length > 0 ? artists[i] : '未知艺术家');
    const sec = i < durations.length ? Math.max(0, Math.floor(durations[i] / 1000)) : 0;
    const mm = Math.floor(sec / 60);
    const ss = sec % 60;
    row.set('duration', mm + ':' + (ss < 10 ? '0' + ss : '' + ss));
    rows.push(row);
  }
  return rows;
}

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H41(trackArtists: string[]): Array<{ name: string; count: number }> {
  const tally = new Map<string, number>();
  for (const raw of trackArtists) {
    const name = raw.trim();
    if (name.length === 0) continue;
    tally.set(name, (tally.get(name) ?? 0) + 1);
  }
  const result: Array<{ name: string; count: number }> = [];
  tally.forEach((count, name) => result.push({ name, count }));
  result.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  return result;
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H41(name: string, cover: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const trimmed = name.trim();
  const display = trimmed.length === 0 ? '未知艺术家' : trimmed;
  const initial = display.charAt(0).toUpperCase();
  item.set('name', display);
  item.set('avatar', cover.length > 0 ? cover : initial);
  const count = songCount < 0 ? 0 : songCount;
  item.set('subtitle', count + ' 首歌曲');
  return item;
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_H41(names: string[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (let i = 0; i < names.length; i++) {
    const name = names[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    (groups.get(key) as string[]).push(name);
  }
  return groups;
}

将二维矩阵转置为行列互换的新矩阵。
function transposeMatrixD_H41(matrix: number[][]): number[][] {
  const result: number[][] = [];
  if (matrix.length === 0) {
    return result;
  }
  const cols = matrix[0].length;
  for (let c = 0; c < cols; c++) {
    const newRow: number[] = [];
    for (let r = 0; r < matrix.length; r++) {
      newRow.push(matrix[r][c]);
    }
    result.push(newRow);
  }
  return result;
}

按指定字段（名称/时长）对文件夹内歌曲索引排序，支持升降序。
function sortFolderSongsD_H42(titles: string[], durations: number[], byName: boolean, asc: boolean): number[] {
  const order: number[] = [];
  for (let i = 0; i < titles.length; i++) {
    order.push(i);
  }
  order.sort((a, b) => {
    let cmp = 0;
    if (byName) {
      cmp = titles[a].localeCompare(titles[b]);
    } else {
      cmp = (durations[a] === undefined ? 0 : durations[a]) - (durations[b] === undefined ? 0 : durations[b]);
    }
    return asc ? cmp : -cmp;
  });
  return order;
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H42(name: string, cover: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const trimmed = name.trim();
  const display = trimmed.length === 0 ? '未知艺术家' : trimmed;
  const initial = display.charAt(0).toUpperCase();
  item.set('name', display);
  item.set('avatar', cover.length > 0 ? cover : initial);
  const count = songCount < 0 ? 0 : songCount;
  item.set('subtitle', count + ' 首歌曲');
  return item;
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_H42(names: string[]): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (let i = 0; i < names.length; i++) {
    const name = names[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!groups.has(key)) {
      groups.set(key, []);
    }
    (groups.get(key) as string[]).push(name);
  }
  return groups;
}

汇总艺术家详情头部信息：名称、专辑数与歌曲数的副标题文案。
function buildArtistHeaderD_H42(name: string, albumCount: number, songCount: number): Map<string, string> {
  const header = new Map<string, string>();
  const safeName = name.trim().length === 0 ? '未知艺术家' : name.trim();
  const albums = albumCount < 0 ? 0 : albumCount;
  const songs = songCount < 0 ? 0 : songCount;
  header.set('title', safeName);
  const parts: string[] = [];
  parts.push(albums + ' 张专辑');
  parts.push(songs + ' 首歌曲');
  header.set('subtitle', parts.join(' · '));
  return header;
}

计算两个字符串的最长公共前缀长度。
function commonPrefixLengthD_H42(a: string, b: string): number {
  const limit = Math.min(a.length, b.length);
  let count = 0;
  for (let i = 0; i < limit; i++) {
    if (a.charAt(i) !== b.charAt(i)) {
      break;
    }
    count = count + 1;
  }
  return count;
}

用辗转相除法计算两个整数的最大公约数。
function greatestCommonDivisorD_H42(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    const r = x % y;
    x = y;
    y = r;
  }
  return x;
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_H45(raw: string, existing: string[]): string {
  const name: string = raw.trim();
  if (name.length === 0) {
    return 'empty';
  }
  for (let i = 0; i < existing.length; i++) {
    if (existing[i].trim() === name) {
      return 'duplicate';
    }
  }
  return 'ok';
}

将查询字符串解析为键值对映射。
function parseQueryStringD_H45(query: string): Map<string, string> {
  const params = new Map<string, string>();
  const cleaned = query.charAt(0) === '?' ? query.substring(1) : query;
  const pairs = cleaned.split('&');
  for (let i = 0; i < pairs.length; i++) {
    if (pairs[i].length === 0) {
      continue;
    }
    const kv = pairs[i].split('=');
    params.set(kv[0], kv.length > 1 ? kv[1] : '');
  }
  return params;
}

判断给定字符串是否为回文（忽略大小写）。
function isPalindromeD_H45(text: string): boolean {
  const cleaned = text.toLowerCase();
  let left = 0;
  let right = cleaned.length - 1;
  while (left < right) {
    if (cleaned.charAt(left) !== cleaned.charAt(right)) {
      return false;
    }
    left = left + 1;
    right = right - 1;
  }
  return true;
}

维护文件夹歌曲多选集合：切换选中、全选与汇总选中数量。
function toggleFolderSelectionD_H45(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
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

根据折叠状态裁剪艺术家歌曲列表，折叠时仅展示前 N 首。
function collapseArtistSongsD_H45(songs: string[], expanded: boolean, limit: number): string[] {
  if (expanded) {
    return songs.slice(0);
  }
  const max = limit <= 0 ? 5 : limit;
  if (songs.length <= max) {
    return songs.slice(0);
  }
  const visible: string[] = [];
  for (let i = 0; i < max; i++) {
    visible.push(songs[i]);
  }
  return visible;
}

汇总该艺术家的专辑区块数据，按发行年份倒序排列并去重。
function buildArtistAlbumSectionD_H45(titles: string[], years: number[]): string[] {
  const seen = new Set<string>();
  const pairs: Map<string, number> = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const title = titles[i].trim();
    if (title.length === 0 || seen.has(title)) {
      continue;
    }
    seen.add(title);
    pairs.set(title, i < years.length ? years[i] : 0);
  }
  const list = Array.from(seen);
  list.sort((a, b) => (pairs.get(b) as number) - (pairs.get(a) as number));
  return list;
}

为文件夹内歌曲建立首字母到首个出现下标的 ABC 索引映射。
function folderAbcIndexD_X15(titles: string[]): Map<string, number> {
  const index = new Map<string, number>();
  for (let i = 0; i < titles.length; i++) {
    const name = titles[i].trim();
    if (name.length === 0) {
      continue;
    }
    const head = name.charAt(0).toUpperCase();
    const key = head >= 'A' && head <= 'Z' ? head : '#';
    if (!index.has(key)) {
      index.set(key, i);
    }
  }
  return index;
}

用辗转相除法计算两个整数的最大公约数。
function greatestCommonDivisorD_X15(a: number, b: number): number {
  let x = Math.abs(a);
  let y = Math.abs(b);
  while (y !== 0) {
    const r = x % y;
    x = y;
    y = r;
  }
  return x;
}

统计字符串中每个字符出现的次数。
function countCharFrequencyD_X15(text: string): Map<string, number> {
  const freq = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    const current = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, current + 1);
  }
  return freq;
}

按指定字段（名称/时长）对文件夹内歌曲索引排序，支持升降序。
function sortFolderSongsD_X15(titles: string[], durations: number[], byName: boolean, asc: boolean): number[] {
  const order: number[] = [];
  for (let i = 0; i < titles.length; i++) {
    order.push(i);
  }
  order.sort((a, b) => {
    let cmp = 0;
    if (byName) {
      cmp = titles[a].localeCompare(titles[b]);
    } else {
      cmp = (durations[a] === undefined ? 0 : durations[a]) - (durations[b] === undefined ? 0 : durations[b]);
    }
    return asc ? cmp : -cmp;
  });
  return order;
}

// 歌曲列表多维排序：按指定字段对歌曲做升序或降序稳定排序
export function sortSongsByFieldB_X15(songs: Record<string, string>[], field: string, asc: boolean): Record<string, string>[] {
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

// 按名称或创建时间对歌单做升序/降序排序
function sortPlaylistsE_X15(lists: Array<Record<string, string | number>>, byTime: boolean, asc: boolean): Array<Record<string, string | number>> {
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

维护文件夹歌曲多选集合：切换选中、全选与汇总选中数量。
function toggleFolderSelectionD_X16(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
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

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB_X16(selected: string[], songId: string): string[] {
  const set = new Set<string>(selected)
  if (set.has(songId)) {
    set.delete(songId)
  } else {
    set.add(songId)
  }
  const out: string[] = []
  set.forEach((id: string) => {
    out.push(id)
  })
  return out
}

根据歌曲状态构建文件夹详情的更多菜单项列表（含禁用过滤）。
function buildFolderMenuItemsD_X16(hasArtist: boolean, hasAlbum: boolean): string[] {
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

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB_X16(song: Record<string, string>): string[] {
  const items: string[] = ['play_next', 'add_to_playlist', 'share', 'song_info']
  const isFavorite = (song['favorite'] ?? 'false') === 'true'
  items.push(isFavorite ? 'unfavorite' : 'favorite')
  const source = song['source'] ?? 'local'
  if (source === 'local') {
    items.push('goto_artist')
    items.push('goto_album')
    items.push('remove_from_library')
  }
  return items
}

将驼峰命名字符串转换为短横线连接的形式。
function camelToKebabD_X16(input: string): string {
  let result = '';
  for (let i = 0; i < input.length; i++) {
    const ch = input.charAt(i);
    const lower = ch.toLowerCase();
    if (ch !== lower && i > 0) {
      result = result + '-';
    }
    result = result + lower;
  }
  return result;
}

在有序数组中用二分查找定位目标值的下标。
function binarySearchIndexD_X16(sorted: number[], target: number): number {
  let low = 0;
  let high = sorted.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (sorted[mid] === target) {
      return mid;
    }
    if (sorted[mid] < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}
