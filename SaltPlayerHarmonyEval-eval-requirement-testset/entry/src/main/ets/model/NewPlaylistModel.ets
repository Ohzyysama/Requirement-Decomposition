// NewPlaylistModel.ets
// Model layer: data structure and data operations for creating a new playlist
// Corresponds to Android NewPlaylistDialog.kt + PlaylistViewModel.addPlaylist flow.

import PlaylistModel from './PlaylistModel'
import { MusicDatabase, PlaylistRow, PlaylistOrderUpdate } from './MusicDatabase'

// Maximum length for a playlist name (mirrors Android PlaylistViewModel check)
export const PLAYLIST_NAME_MAX_LEN: number = 100

// Result of validating a user-entered playlist name
export enum PlaylistValidation {
  OK = 0,
  EMPTY = 1,
  TOO_LONG = 2
}

// Data class representing a new playlist to be created
export class NewPlaylistData {
  public name: string = ''

  constructor(name?: string) {
    if (name) {
      this.name = name
    }
  }
}

// Data access operations for playlist creation
export class NewPlaylistDataSource {
  // Validate the trimmed playlist name. Empty → EMPTY, > 100 chars → TOO_LONG.
  // Matches PlaylistViewModel.kt (android) addPlaylist branches.
  static validate(name: string): PlaylistValidation {
    const trimmed = name.trim()
    if (trimmed.length === 0) return PlaylistValidation.EMPTY
    if (trimmed.length > PLAYLIST_NAME_MAX_LEN) return PlaylistValidation.TOO_LONG
    return PlaylistValidation.OK
  }

  // Legacy API preserved so existing call sites that only care about blank-vs-non-blank
  // continue to compile. Prefer `validate()` for new code.
  static isValidName(name: string): boolean {
    return NewPlaylistDataSource.validate(name) === PlaylistValidation.OK
  }

  // Create a new playlist row in the DB. Mirrors Android PlaylistViewModel.addPlaylist:
  //   1. Normalise existing rows' order to 0..n-1 (saveIndex).
  //   2. Insert new row with playlistOrder = -1 so it floats to the top on next read.
  // Returns the inserted PlaylistModel on success, or null on DB/validation failure.
  // Callers are responsible for triggering any UI reload after this resolves.
  static async createPlaylist(name: string): Promise<PlaylistModel | null> {
    const trimmed = name.trim()
    if (NewPlaylistDataSource.validate(trimmed) !== PlaylistValidation.OK) {
      return null
    }
    const ready = await MusicDatabase.ensureReady()
    if (!ready) {
      console.error('NewPlaylistDataSource: database not ready')
      return null
    }

    // 1. saveIndex() — normalise existing rows' playlistOrder to 0..n-1 in
    //    their current sort order (already ORDER BY playlistOrder ASC).
    try {
      const existing: PlaylistRow[] = await MusicDatabase.getAllPlaylists()
      const pairs: PlaylistOrderUpdate[] = existing.map((r: PlaylistRow, i: number): PlaylistOrderUpdate => {
        const pair: PlaylistOrderUpdate = { id: r.id, order: i }
        return pair
      })
      if (pairs.length > 0) {
        await MusicDatabase.updatePlaylistOrders(pairs)
      }
    } catch (e) {
      console.error('NewPlaylistDataSource: saveIndex failed: ' + (e as Error).message)
      // Keep going — even without normalisation, inserting with -1 still floats
      // the new playlist to the top, so Scenario 3 still holds.
    }

    // 2. Build and insert new row. ID uses timestamp + random suffix to avoid
    //    same-millisecond collisions in rapid-create scenarios.
    const now = Date.now()
    const newId = now.toString() + '-' + Math.floor(Math.random() * 1000).toString()
    const row: PlaylistRow = {
      id: newId,
      title: trimmed,
      coverModifiedTime: 0,
      isUserEditedCover: false,
      description: '',
      createdTime: now,
      playlistOrder: -1,
      trackSort: 0,
      trackSortDescending: false
    }
    const ok = await MusicDatabase.insertPlaylist(row)
    if (!ok) return null
    return new PlaylistModel(row.id, row.title, 0, '')
  }
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE(raw: string, existing: string[]): string {
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

// 将秒数格式化为 mm:ss 时间文本
function formatDurationLabelE(totalSeconds: number): string {
  const secs: number = Math.max(0, Math.floor(totalSeconds));
  const minutes: number = Math.floor(secs / 60);
  const remain: number = secs % 60;
  const mm: string = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss: string = remain < 10 ? '0' + remain : '' + remain;
  return mm + ':' + ss;
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_H48(raw: string, existing: string[]): string {
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

为文件夹内歌曲建立首字母到首个出现下标的 ABC 索引映射。
function folderAbcIndexD_H48(titles: string[]): Map<string, number> {
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

对文件夹内歌曲索引做洗牌，生成随机播放顺序。
function shuffleFolderQueueD_H48(count: number): number[] {
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
function toggleFolderSelectionD_H48(selected: Set<number>, index: number, selectAll: boolean, total: number): Set<number> {
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

// 计算购物车商品总价（含折扣）
function computeCartTotalE_H48(prices: number[], discount: number): number {
  let sum: number = 0;
  for (let i = 0; i < prices.length; i++) {
    sum += prices[i];
  }
  const rate: number = Math.min(1, Math.max(0, discount));
  return Math.round(sum * (1 - rate) * 100) / 100;
}

// 判断给定年份是否为闰年
function isLeapYearE_H48(year: number): boolean {
  if (year % 4 !== 0) {
    return false;
  }
  if (year % 100 !== 0) {
    return true;
  }
  return year % 400 === 0;
}

// 去除首尾空白后校验非空并与现有歌单名查重
function validateNewPlaylistNameE_X5(raw: string, existing: string[]): string {
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

// 新建歌单：名称去首尾空白、空名回退默认名、与既有歌单重名时追加序号
export function normalizePlaylistNameX_X5(name: string, existing: string[], fallback: string): string {
  let n = name.trim()
  if (n.length === 0) {
    n = fallback
  }
  if (existing.indexOf(n) < 0) {
    return n
  }
  let i = 2
  while (existing.indexOf(n + ' (' + i + ')') >= 0) {
    i++
  }
  return n + ' (' + i + ')'
}

// 按 id 找到目标歌单并写入去空白后的新名称
function renamePlaylistByIdE_X5(lists: Map<number, string>, id: number, newName: string): boolean {
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

// 加入时去重追加到末尾，移出时保留原有顺序
function toggleSongInPlaylistE_X5(songIds: number[], songId: number, add: boolean): number[] {
  const next: number[] = [];
  let found: boolean = false;
  for (let i = 0; i < songIds.length; i++) {
    if (songIds[i] === songId) {
      found = true;
      if (add) {
        next.push(songIds[i]);
      }
    } else {
      next.push(songIds[i]);
    }
  }
  if (add && !found) {
    next.push(songId);
  }
  return next;
}

// 判断给定年份是否为闰年
function isLeapYearE_X5(year: number): boolean {
  if (year % 4 !== 0) {
    return false;
  }
  if (year % 100 !== 0) {
    return true;
  }
  return year % 400 === 0;
}
