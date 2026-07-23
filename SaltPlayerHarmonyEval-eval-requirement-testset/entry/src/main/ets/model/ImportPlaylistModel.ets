// ImportPlaylistModel.ets
// Model layer: data operations for importing a playlist from a .txt file.
// Mirrors Android PlaylistViewModel.importPlaylist + M3U.txtToPaths flow.

import { MusicDatabase, PlaylistRow, PlaylistOrderUpdate } from './MusicDatabase'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG = 'ImportPlaylistModel'

export const IMPORT_PLAYLIST_MAX_NAME_LEN: number = 100

// Pure Model-layer helper encapsulating spec15 name derivation, line parsing,
// txt detection, DB matching, and the full import-commit flow. Keeps
// MainPageViewModel thin.
export class ImportPlaylistDataSource {
  // Case-insensitive .txt extension check on the URI or filename.
  // Used by Scenario 3 to reject non-.txt inputs before any file IO.
  static isTxtFile(uriOrName: string): boolean {
    if (!uriOrName || uriOrName.length === 0) return false
    // Strip query string or fragment if present.
    let s = uriOrName
    const qIdx = s.indexOf('?')
    if (qIdx >= 0) s = s.substring(0, qIdx)
    const hIdx = s.indexOf('#')
    if (hIdx >= 0) s = s.substring(0, hIdx)
    const lower = s.toLowerCase()
    return lower.endsWith('.txt')
  }

  // Spec15 S1/S2 step 4/5 — name derivation from a URI:
  //   1. Take substring after the last '/'
  //   2. Strip a trailing '.txt' / '.TXT' (case-insensitive)
  //   3. URL-decode percent-escapes (picker returns encoded URIs like
  //      file://.../my%20list.txt)
  //   4. Trim leading + trailing whitespace
  //   5. If length > 100, cut to first 100 chars, then trim again (so a space
  //      exposed by the cut is stripped).
  static deriveName(uri: string): string {
    if (!uri || uri.length === 0) return ''
    // 1. Substring after last '/'.
    let base: string = uri
    const slash = base.lastIndexOf('/')
    if (slash >= 0) base = base.substring(slash + 1)
    // Strip query/fragment if any leaked in.
    const qIdx = base.indexOf('?')
    if (qIdx >= 0) base = base.substring(0, qIdx)
    const hIdx = base.indexOf('#')
    if (hIdx >= 0) base = base.substring(0, hIdx)
    // 2. Strip trailing .txt/.TXT case-insensitively.
    if (base.length >= 4) {
      const tail = base.substring(base.length - 4).toLowerCase()
      if (tail === '.txt') {
        base = base.substring(0, base.length - 4)
      }
    }
    // 3. URL-decode. Fall back to raw string on bad escapes.
    let decoded: string = base
    try {
      decoded = decodeURIComponent(base)
    } catch (_e) {
      decoded = base
    }
    // 4. Trim leading + trailing whitespace.
    let trimmed = decoded.trim()
    // 5. Truncate to max length, then re-trim.
    if (trimmed.length > IMPORT_PLAYLIST_MAX_NAME_LEN) {
      trimmed = trimmed.substring(0, IMPORT_PLAYLIST_MAX_NAME_LEN).trim()
    }
    return trimmed
  }

  // Spec15 S1/S2 step 6 — split file body on '\n', trim each line
  // (Windows CRLF '\r' is dropped by the trim), filter empties. Mirrors
  // M3U.txtToPaths but also drops empty lines (Android tolerates them because
  // SongRepo.getByRealPath returns null for '' — we filter early so the DB
  // lookup sees only real paths).
  //
  // The lines are returned verbatim (any percent-encoding from a legacy
  // export, or fully decoded from a new export). MusicDatabase.getTrackIdsByPaths
  // matches them against DB rows by comparing canonical (fully decoded)
  // forms on both sides, so the import works regardless of which variant
  // the file uses.
  static parsePaths(content: string): string[] {
    if (!content || content.length === 0) return []
    const raw = content.split('\n')
    const out: string[] = []
    for (let i = 0; i < raw.length; i++) {
      const line = raw[i].trim()
      if (line.length > 0) {
        out.push(line)
      }
    }
    return out
  }

  // Commit flow:
  //   1. saveIndex — normalise existing playlistOrder to 0..n-1.
  //   2. Insert Playlist row with playlistOrder = -1 so it appears first.
  //   3. Insert matched tracks into PlaylistTrack with isAscending=false so
  //      the FIRST path in the txt receives the largest addedTime and thus
  //      sits on top under PLAYLIST_ADD_TIME desc default sort. That matches
  //      Android resolved behaviour where the cover resolves to the first
  //      path of the txt (getPlaylistFirstCovers ORDER BY addedTime DESC).
  //
  // Returns the new playlist id on success, or null on DB failure.
  static async commitImportedPlaylist(name: string, matchedTrackIds: string[]): Promise<string | null> {
    const ready = await MusicDatabase.ensureReady()
    if (!ready) {
      hilog.error(0, TAG, 'commitImportedPlaylist: database not ready')
      return null
    }

    // 1. saveIndex — normalise existing rows' playlistOrder to 0..n-1 in their
    //    current sort order (already ORDER BY playlistOrder ASC).
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
      hilog.error(0, TAG, 'commitImportedPlaylist: saveIndex failed: %{public}s', (e as Error).message)
      // Keep going — even without normalisation, inserting with -1 still floats
      // the new playlist to the top.
    }

    // 2. Build and insert new row. ID uses timestamp + random suffix to avoid
    //    same-millisecond collisions.
    const now = Date.now()
    const newId = now.toString() + '-' + Math.floor(Math.random() * 1000).toString()
    const row: PlaylistRow = {
      id: newId,
      title: name,
      coverModifiedTime: 0,
      isUserEditedCover: false,
      description: '',
      createdTime: now,
      playlistOrder: -1,
      trackSort: 0,
      trackSortDescending: false
    }
    const ok = await MusicDatabase.insertPlaylist(row)
    if (!ok) {
      hilog.error(0, TAG, 'commitImportedPlaylist: insertPlaylist failed')
      return null
    }

    // 3. Insert matched tracks — isAscending=false so trackIds[0] (first path
    //    in the txt) gets the largest addedTime → sits on top → becomes cover.
    if (matchedTrackIds.length > 0) {
      try {
        await MusicDatabase.insertPlaylistTracks(newId, matchedTrackIds, now, false)
      } catch (e) {
        hilog.error(0, TAG, 'commitImportedPlaylist: insertPlaylistTracks failed: %{public}s',
          (e as Error).message)
        // Playlist row already exists; return its id so the UI still shows it.
      }
    }

    return newId
  }
}

// 歌单导入：从 .txt 文件按路径导入歌单曲目。

// 每首歌序列化为一行 标题|艺术家|路径 的文本
function serializePlaylistLinesE(songs: Array<Record<string, string>>): string {
  const lines: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const s: Record<string, string> = songs[i];
    const title: string = s.title !== undefined ? s.title : '';
    const artist: string = s.artist !== undefined ? s.artist : '';
    const path: string = s.path !== undefined ? s.path : '';
    lines.push(title + '|' + artist + '|' + path);
  }
  return lines.join('\n');
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitE(values: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const f: number = values[i] * 9 / 5 + 32;
    out.push(Math.round(f * 10) / 10);
  }
  return out;
}

// 检查括号字符串是否正确配对
function isBalancedBracketsE_H52(text: string): boolean {
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

// 计算一组数值的算术平均值
function averageOfNumbersE_H52(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum: number = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
  }
  return sum / values.length;
}

// 每首歌序列化为一行 标题|艺术家|路径 的文本
function serializePlaylistLinesE_H52(songs: Array<Record<string, string>>): string {
  const lines: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const s: Record<string, string> = songs[i];
    const title: string = s.title !== undefined ? s.title : '';
    const artist: string = s.artist !== undefined ? s.artist : '';
    const path: string = s.path !== undefined ? s.path : '';
    lines.push(title + '|' + artist + '|' + path);
  }
  return lines.join('\n');
}

组装文件夹歌曲信息详情字段：标题、格式、比特率与文件大小文案。
function buildFolderSongInfoD_H52(title: string, format: string, bitrate: number, bytes: number): Map<string, string> {
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

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_H52(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
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
function searchLibraryTracksE_H52(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
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
