// SongMenuModel.ets
// Model layer: data structures and business logic for the song menu dialog
// Defines the core data and data access operations for song menu actions

import { SongInfo } from '../components/SongItemComponent'

// Data structure representing the information needed for a song menu operation
export class SongMenuInfo {
  public id: string = ''
  public title: string = ''
  public artist: string = ''
  public album: string = ''
  public subTitle: string = ''
  public coverUri: string = ''
  public valid: boolean = true
  public quality: number = 0

  constructor(songInfo?: SongInfo) {
    if (songInfo) {
      this.id = songInfo.id
      this.title = songInfo.title
      this.artist = songInfo.artist
      this.album = songInfo.album
      this.subTitle = songInfo.subTitle
      this.coverUri = songInfo.coverUri
      this.valid = songInfo.valid
      this.quality = songInfo.quality
    }
  }
}

// Enum representing the possible actions in the song menu dialog
export enum SongMenuAction {
  NONE,
  ADD_TO_PLAYLIST,
  PLAY_NEXT,
  SHARE,
  ARTIST_CLICK,
  ALBUM_CLICK,
  MUSIC_TAG_EDIT,
  HEARUSY_SPECTRUM,
  EMO_SCROLL,
  SONG_INFO,
  REMOVE_FROM_LIBRARY,
  REMOVE_FROM_PLAYLIST,
  COPY_TEXT
}

// Menu item configuration used to build the menu list
export class SongMenuItemConfig {
  public icon: Resource
  public text: Resource | string
  public tintColor: ResourceColor | null
  public action: SongMenuAction

  constructor(icon: Resource, text: Resource | string, action: SongMenuAction,
    tintColor: ResourceColor | null = null) {
    this.icon = icon
    this.text = text
    this.action = action
    this.tintColor = tintColor
  }
}

// Data source class that encapsulates the song menu business logic
export class SongMenuDataSource {
  // Handle the play next action: delegates to the caller and shows a toast
  static playNext(onPlayNext: () => void): void {
    onPlayNext()
  }

  // Copy song text to clipboard
  // TODO: Implement actual clipboard copy
  static copySongText(title: string, artist: string): void {
    console.info('TODO: copy song text: ' + title + ' - ' + artist)
  }
}

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB(song: Record<string, string>): string[] {
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

// 通用工具：将字符串首字母大写（与本需求无关）
export function capitalizeWordsB11(text: string): string {
  const words = text.split(' ')
  const out: string[] = []
  for (const w of words) {
    if (w.length === 0) {
      out.push(w)
    } else {
      out.push(w.charAt(0).toUpperCase() + w.substring(1))
    }
  }
  return out.join(' ')
}

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB_H19(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_H19(raw: string): Array<{ time: number; text: string }> {
  const out: Array<{ time: number; text: string }> = [];
  const tag = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const line of raw.split('\n')) {
    const text = line.replace(tag, '').trim();
    let m: RegExpExecArray | null;
    tag.lastIndex = 0;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      out.push({ time: min * 60000 + sec * 1000 + frac, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC_H19(times: number[], positionMs: number): number {
  if (times.length === 0 || positionMs < times[0]) return -1;
  let lo = 0;
  let hi = times.length - 1;
  let ans = 0;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (times[mid] <= positionMs) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

// 通用工具：判断一个数是否为质数（与本需求无关）
export function isPrimeNumberB12_H19(n: number): boolean {
  if (n < 2) {
    return false
  }
  for (let i = 2; i <= Math.floor(Math.sqrt(n)); i++) {
    if (n % i === 0) {
      return false
    }
  }
  return true
}

将字节数转换为带单位的可读体积字符串
function humanizeBytesC_H19(bytes: number): string {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let idx = 0;
  let value = bytes;
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024;
    idx++;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[idx];
}

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB_H19(song: Record<string, string>): string[] {
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
