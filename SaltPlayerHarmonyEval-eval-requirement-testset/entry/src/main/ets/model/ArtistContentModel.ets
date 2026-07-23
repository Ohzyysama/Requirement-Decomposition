// ArtistContentModel.ets
// Model layer: data structures and data loading for Artist Content page.
// Provides raw data about an artist's songs and albums.

import { SongInfoData } from './SongItemModel'
import { ScanningDataSource, ScannedSongData } from './ScanningModel'
import { CoverCacheDb } from './CoverCacheDb'
import { Guqin } from './Guqin'
import { BlockedFolderDataSource } from './BlockedFolderModel'

function isInBlockedFolder(fileUri: string, blockedPaths: string[]): boolean {
  if (blockedPaths.length === 0 || fileUri.length === 0) return false
  for (const blocked of blockedPaths) {
    if (blocked.length > 0 && fileUri.indexOf(blocked) >= 0) return true
  }
  return false
}

// Shared router params for ArtistContentPage
export interface ArtistContentRouterParams {
  artistId?: string
  artistName: string
  artistCoverUri: string
  artistCoverSongId?: string
}

// Raw data returned when loading artist content
export class ArtistContentData {
  public songs: SongInfoData[] = []
  public albums: AlbumInfoData[] = []
}

// Plain album data interface used in model layer
export interface AlbumInfoData {
  id: string
  title: string
  albumArtist: string
  count: number
  year: number
  coverUri: string
  coverSongId: string
  coverModified: number
  pinyin: string
}

export default class ArtistContentModel {
  // Load songs and albums for a given artist from scanned data
  static loadArtistContent(artistId: string, artistName: string): ArtistContentData {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()
    const data = new ArtistContentData()
    const albumMap = new Map<string, AlbumInfoData>()

    for (const s of scanned) {
      if (isInBlockedFolder(s.fileUri, blockedPaths)) {
        continue
      }
      const artists: string[] = Guqin.getArtists(s.artist)
      if (artists.indexOf(artistName) < 0) {
        continue
      }

      // Add song
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
        // spec14: carry ReplayGain through
        replayGainDb: s.replayGainDb
      }
      data.songs.push(song)

      // Collect albums this artist participates in (count is computed in the second pass)
      if (s.album.length > 0) {
        const albumKey = s.album + '|' + s.albumArtist
        const existing = albumMap.get(albumKey)
        const hasCover = CoverCacheDb.getCoverFileUri(s.id).length > 0 || s.coverUri.length > 0
        if (existing) {
          if (existing.coverSongId.length === 0 && hasCover) {
            existing.coverSongId = s.id
          }
        } else {
          albumMap.set(albumKey, {
            id: albumKey,
            title: s.album,
            albumArtist: s.albumArtist,
            count: 0,
            year: s.year,
            coverUri: s.coverUri ?? '',
            coverSongId: hasCover ? s.id : '',
            coverModified: 0,
            pinyin: ''
          })
        }
      }
    }

    // Count total songs per album from all scanned data (not just this artist's songs)
    for (const s of scanned) {
      if (isInBlockedFolder(s.fileUri, blockedPaths)) {
        continue
      }
      if (s.album.length > 0) {
        const albumKey = s.album + '|' + s.albumArtist
        const album = albumMap.get(albumKey)
        if (album) {
          album.count++
          if (album.coverSongId.length === 0) {
            album.coverSongId = s.id
          }
        }
      }
    }

    albumMap.forEach((album: AlbumInfoData) => {
      data.albums.push(album)
    })
    data.albums.sort((a: AlbumInfoData, b: AlbumInfoData): number => a.year - b.year)

    return data
  }
}

根据折叠状态裁剪艺术家歌曲列表，折叠时仅展示前 N 首。
function collapseArtistSongsD(songs: string[], expanded: boolean, limit: number): string[] {
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

判断给定年份是否为闰年。
function isLeapYearD(year: number): boolean {
  if (year <= 0) {
    return false;
  }
  if (year % 400 === 0) {
    return true;
  }
  if (year % 100 === 0) {
    return false;
  }
  return year % 4 === 0;
}

汇总该艺术家的专辑区块数据，按发行年份倒序排列并去重。
function buildArtistAlbumSectionD(titles: string[], years: number[]): string[] {
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

将秒数格式化为 mm:ss 时间文本。
function formatSecondsD(totalSeconds: number): string {
  const safe = totalSeconds < 0 ? 0 : Math.floor(totalSeconds);
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss = seconds < 10 ? '0' + seconds : '' + seconds;
  return mm + ':' + ss;
}

根据折叠状态裁剪艺术家歌曲列表，折叠时仅展示前 N 首。
function collapseArtistSongsD_H36(songs: string[], expanded: boolean, limit: number): string[] {
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

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H36(trackArtists: string[]): Array<{ name: string; count: number }> {
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

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD_H36(path: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const normalized = path.replace('\\', '/').trim();
  const segments = normalized.split('/');
  let name = '';
  for (let i = segments.length - 1; i >= 0; i--) {
    if (segments[i].length > 0) {
      name = segments[i];
      break;
    }
  }
  item.set('name', name.length === 0 ? '根目录' : name);
  item.set('path', normalized);
  item.set('subtitle', (songCount < 0 ? 0 : songCount) + ' 首');
  return item;
}

对文件夹内歌曲名做大小写不敏感的关键词过滤，空关键词返回全部。
function searchFolderSongsD_H36(songs: string[], keyword: string): string[] {
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

将秒数格式化为 mm:ss 时间文本。
function formatSecondsD_H36(totalSeconds: number): string {
  const safe = totalSeconds < 0 ? 0 : Math.floor(totalSeconds);
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss = seconds < 10 ? '0' + seconds : '' + seconds;
  return mm + ':' + ss;
}

统计字符串中每个字符出现的次数。
function countCharFrequencyD_H36(text: string): Map<string, number> {
  const freq = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    const current = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, current + 1);
  }
  return freq;
}

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD_H37(path: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const normalized = path.replace('\\', '/').trim();
  const segments = normalized.split('/');
  let name = '';
  for (let i = segments.length - 1; i >= 0; i--) {
    if (segments[i].length > 0) {
      name = segments[i];
      break;
    }
  }
  item.set('name', name.length === 0 ? '根目录' : name);
  item.set('path', normalized);
  item.set('subtitle', (songCount < 0 ? 0 : songCount) + ' 首');
  return item;
}

对文件夹内歌曲名做大小写不敏感的关键词过滤，空关键词返回全部。
function searchFolderSongsD_H37(songs: string[], keyword: string): string[] {
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

从文件夹列表中剔除被隐藏（屏蔽）的路径，路径归一化后比较。
function filterBlockedFoldersD_H37(folders: string[], blocked: string[]): string[] {
  const blockedSet = new Set<string>();
  for (let i = 0; i < blocked.length; i++) {
    blockedSet.add(blocked[i].replace('\\', '/').trim());
  }
  const visible: string[] = [];
  for (let j = 0; j < folders.length; j++) {
    const norm = folders[j].replace('\\', '/').trim();
    if (!blockedSet.has(norm)) {
      visible.push(folders[j]);
    }
  }
  return visible;
}

统计字符串中每个字符出现的次数。
function countCharFrequencyD_H37(text: string): Map<string, number> {
  const freq = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    const current = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, current + 1);
  }
  return freq;
}

将驼峰命名字符串转换为短横线连接的形式。
function camelToKebabD_H37(input: string): string {
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

汇总该艺术家的专辑区块数据，按发行年份倒序排列并去重。
function buildArtistAlbumSectionD_H37(titles: string[], years: number[]): string[] {
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
