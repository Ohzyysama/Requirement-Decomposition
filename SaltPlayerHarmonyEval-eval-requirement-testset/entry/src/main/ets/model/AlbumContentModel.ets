// AlbumContentModel.ets
// Model layer: pure data structures for album content page.
// Provides data access methods (load album songs, participating artists, etc.)

import { SongInfoData } from './SongItemModel'
import ArtistModel from './ArtistModel'
import { ScanningDataSource, ScannedSongData } from './ScanningModel'
import { Guqin } from './Guqin'
import { MainPageDataSource } from './MainPageModel'
import { CoverCacheDb } from './CoverCacheDb'
import { BlockedFolderDataSource } from './BlockedFolderModel'

// Router params interface for navigating to AlbumContentPage
export interface AlbumContentRouterParams {
  albumId: string
  albumTitle: string
  albumArtist: string
  albumCount: number
  albumYear: number
  albumCoverUri: string
  albumCoverSongId: string
  albumDuration: string
  albumHz: number
  albumBits: number
  albumIsHiRes: boolean
  albumCopyright: string
}

// Song grouped by disc number
export interface DiscSongGroupData {
  disc: number
  songs: SongInfoData[]
  discDuration: string
}

// Album detail data returned by data access layer
export interface AlbumDetailData {
  songs: SongInfoData[]
  discGroups: DiscSongGroupData[]
  artists: ArtistModel[]
  totalDurationText: string
}

export function formatDurationMs(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000)
  const h = Math.floor(totalSeconds / 3600)
  const m = Math.floor((totalSeconds % 3600) / 60)
  const s = totalSeconds % 60
  if (h > 0) {
    return `${h}:${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`
  }
  return `${m}:${s.toString().padStart(2, '0')}`
}

// Data access class for album content
export default class AlbumContentModel {
  // Load album detail: songs matching albumTitle+albumArtist from scanned data
  static loadAlbumDetail(params: AlbumContentRouterParams): AlbumDetailData {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()

    const matchingSongs: SongInfoData[] = []
    const artistSet = new Set<string>()

    for (const s of scanned) {
      if (blockedPaths.length > 0 && s.fileUri.length > 0) {
        let isBlocked = false
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 && s.fileUri.indexOf(blocked) >= 0) {
            isBlocked = true
            break
          }
        }
        if (isBlocked) continue
      }
      const key = s.album + '|' + s.albumArtist
      if (key === params.albumId || (s.album === params.albumTitle && s.albumArtist === params.albumArtist)) {
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
        matchingSongs.push(song)
        if (s.artist.length > 0) {
          const splitArtists = Guqin.getArtists(s.artist)
          for (const name of splitArtists) {
            artistSet.add(name)
          }
        }
      }
    }

    // Single disc group
    let totalDuration = 0
    for (const song of matchingSongs) {
      totalDuration += song.duration ?? 0
    }
    const discGroups: DiscSongGroupData[] = []
    if (matchingSongs.length > 0) {
      discGroups.push({
        disc: 0,
        songs: matchingSongs,
        discDuration: formatDurationMs(totalDuration)
      })
    }

    // Participating artists — use global artist data for song count (consistent with artist detail page)
    const allArtists = MainPageDataSource.loadDefaultArtists()
    const artists: ArtistModel[] = []
    artistSet.forEach((name: string) => {
      const globalArtist = allArtists.find(a => a.name === name)
      const count = globalArtist?.count ?? 0
      const coverSongId = globalArtist?.coverSongId ?? ''
      artists.push(new ArtistModel(name, name, count, '', '', coverSongId))
    })

    return { songs: matchingSongs, discGroups: discGroups, artists: artists, totalDurationText: formatDurationMs(totalDuration) }
  }
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
  const copy = tracks.slice();
  copy.sort((a, b) => {
    if (a.disc !== b.disc) {
      return a.disc - b.disc;
    }
    if (a.track !== b.track) {
      return a.track - b.track;
    }
    return a.title.localeCompare(b.title);
  });
  return copy;
}

将扁平键值对按前缀分组为嵌套映射
function groupByPrefixC(keys: string[], sep: string): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (const key of keys) {
    const idx = key.indexOf(sep);
    const prefix = idx >= 0 ? key.slice(0, idx) : key;
    const bucket = groups.get(prefix) ?? [];
    bucket.push(key);
    groups.set(prefix, bucket);
  }
  return groups;
}

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC(trackArtists: string[]): Array<{ name: string; count: number }> {
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

将驼峰命名拆分为以空格分隔的词序列
function splitCamelWordsC(identifier: string): string[] {
  const words: string[] = [];
  let current = '';
  for (const ch of identifier) {
    if (ch >= 'A' && ch <= 'Z' && current.length > 0) {
      words.push(current);
      current = ch;
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    words.push(current);
  }
  return words;
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC_H31(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H31(name: string, cover: string, songCount: number): Map<string, string> {
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
function groupArtistsByLetterD_H31(names: string[]): Map<string, string[]> {
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

将驼峰命名拆分为以空格分隔的词序列
function splitCamelWordsC_H31(identifier: string): string[] {
  const words: string[] = [];
  let current = '';
  for (const ch of identifier) {
    if (ch >= 'A' && ch <= 'Z' && current.length > 0) {
      words.push(current);
      current = ch;
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    words.push(current);
  }
  return words;
}

将字节数格式化为带单位的可读字符串。
function formatByteSizeD_H31(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024;
    index = index + 1;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[index];
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H31(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
  const copy = tracks.slice();
  copy.sort((a, b) => {
    if (a.disc !== b.disc) {
      return a.disc - b.disc;
    }
    if (a.track !== b.track) {
      return a.track - b.track;
    }
    return a.title.localeCompare(b.title);
  });
  return copy;
}

按艺术家名称首字母分组生成 ABC 索引，非字母归入 # 组。
function groupArtistsByLetterD_H32(names: string[]): Map<string, string[]> {
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
function buildArtistHeaderD_H32(name: string, albumCount: number, songCount: number): Map<string, string> {
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

将字节数格式化为带单位的可读字符串。
function formatByteSizeD_H32(bytes: number): string {
  if (bytes <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value = value / 1024;
    index = index + 1;
  }
  const rounded = Math.round(value * 100) / 100;
  return rounded + ' ' + units[index];
}

计算一组数值的算术平均值，空集合返回 0。
function averageOfValuesD_H32(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum = 0;
  for (let i = 0; i < values.length; i++) {
    sum = sum + values[i];
  }
  const avg = sum / values.length;
  return Math.round(avg * 1000) / 1000;
}

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H32(trackArtists: string[]): Array<{ name: string; count: number }> {
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
function buildArtistItemD_H32(name: string, cover: string, songCount: number): Map<string, string> {
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
