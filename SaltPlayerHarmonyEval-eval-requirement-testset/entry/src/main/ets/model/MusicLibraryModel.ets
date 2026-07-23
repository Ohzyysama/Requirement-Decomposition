// MusicLibraryModel.ets
// Model layer: pure data structures for the Music Library page.
// Contains no UI or ViewModel dependency.

import {
  MusicDatabase,
  MusicLibraryAggregate,
  TrackSizeMissing
} from './MusicDatabase'
import { ScanningDataSource } from './ScanningModel'
import { fileIo, fileShare } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

// Data model for pie chart entries
export interface PieEntryData {
  label: string
  value: number
  color: string
}

// Data model for quality statistics
export interface QualityStatData {
  label: string
  count: string
}

// Velocity sample for fling tracking (mirrors MPAndroidChart's AngularVelocitySample)
export interface VelocitySampleData {
  time: number
  angle: number
}

// Music library statistics data from the data source
export interface MusicLibraryData {
  pieEntries: PieEntryData[]
  totalSize: string
  hqCount: string
  sqCount: string
  hiResCount: string
  othersCount: string
}

// Default empty MusicLibraryData for initialization
export function createDefaultMusicLibraryData(): MusicLibraryData {
  return {
    pieEntries: [],
    totalSize: '0.00 B',
    hqCount: '0',
    sqCount: '0',
    hiResCount: '0',
    othersCount: '0'
  }
}

// Human-readable byte formatter (B/KB/MB/GB, 2 decimals). Duplicated locally
// to keep MusicLibraryModel free of UI/MainPage coupling.
function formatBytes(bytes: number): string {
  if (bytes <= 0) return '0.00 B'
  const gb = bytes / (1024 * 1024 * 1024)
  if (gb >= 1) return `${gb.toFixed(2)} GB`
  const mb = bytes / (1024 * 1024)
  if (mb >= 1) return `${mb.toFixed(2)} MB`
  const kb = bytes / 1024
  if (kb >= 1) return `${kb.toFixed(2)} KB`
  return `${bytes.toFixed(2)} B`
}

// Activate read permission for a single persisted URI. Wrapped in try/catch
// so the caller can fall through to a "treat as unreadable" branch.
async function tryActivatePermission(uri: string): Promise<boolean> {
  try {
    const policy: fileShare.PolicyInfo = {
      uri: uri,
      operationMode: fileShare.OperationMode.READ_MODE
    } as fileShare.PolicyInfo
    await fileShare.activatePermission([policy])
    return true
  } catch (_e) {
    return false
  }
}

// Stat a single audio file URI and return its size in bytes (0 on failure).
// On the first open failure we try fileShare.activatePermission and retry —
// matches the AudioPlayerService recovery path so persisted URIs that aren't
// yet activated this session still resolve to a real size instead of 0.
async function statFileSize(uri: string): Promise<number> {
  if (!uri || uri.length === 0) return 0
  let file: fileIo.File | null = null
  try {
    try {
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
    } catch (_openErr) {
      const activated = await tryActivatePermission(uri)
      if (!activated) return 0
      try {
        file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY)
      } catch (_retryErr) {
        return 0
      }
    }
    const stat = await fileIo.stat(file.fd)
    return stat.size > 0 ? stat.size : 0
  } catch (_e) {
    return 0
  } finally {
    if (file !== null) {
      try {
        await fileIo.close(file)
      } catch (_closeErr) {
        // ignore
      }
    }
  }
}

// Resolve sizes for every track URI in batches so we don't fan out an
// unbounded number of concurrent fileIo.open calls on large libraries.
// Returns an array aligned with the input — entries that failed are 0.
async function statFileSizes(uris: string[]): Promise<number[]> {
  if (uris.length === 0) return []
  const BATCH = 32
  const out: number[] = new Array(uris.length).fill(0)
  for (let i = 0; i < uris.length; i += BATCH) {
    const end = Math.min(i + BATCH, uris.length)
    const slice = uris.slice(i, end)
    const sizes: number[] = await Promise.all(
      slice.map((u: string): Promise<number> => statFileSize(u))
    )
    for (let k = 0; k < sizes.length; k++) {
      out[i + k] = sizes[k]
    }
  }
  return out
}


// Data source for the Music Library statistics page. Pulls totals + per-tier
// counts directly from a SQL aggregate over the Track table — no JS-side row
// iteration, so 0 in the UI now means "0 in the DB" rather than "we lost the
// number somewhere on the way out". When the DB still carries size = 0 for
// rows persisted by an older scan, we recover real bytes from fileIo.stat
// and write them back so the next visit takes the fast path.
export class MusicLibraryDataSource {
  static async loadMusicLibraryData(): Promise<MusicLibraryData> {
    // Reclassify any tracks whose quality column is still the schema default
    // (rows scanned before the column existed, or migrated from Preferences)
    // BEFORE we read the aggregate, so HQ/SQ/HR counts reflect every track
    // with usable metadata — not just the ones scanned after the upgrade.
    // Pull-to-refresh on the song list page invokes the same routine via
    // ScanningDataSource.refreshExistingTracks → backfillQualitiesAcrossLibrary.
    const reclassified = await ScanningDataSource.backfillQualitiesAcrossLibrary()
    if (reclassified > 0) {
      hilog.info(0, 'MusicLibraryModel',
        'quality-backfill: classified %{public}d tracks', reclassified)
    }

    const agg: MusicLibraryAggregate = await MusicDatabase.getMusicLibraryAggregate()
    if (agg.totalCount === 0) {
      return createDefaultMusicLibraryData()
    }
    let totalBytes = agg.totalSize
    hilog.info(0, 'MusicLibraryModel',
      'aggregate from DB: count=%{public}d totalSize=%{public}d',
      agg.totalCount, agg.totalSize)

    // Recover sizes for any rows where Track.size is still 0. We only stat
    // files when the DB doesn't already know — typical libraries skip this
    // entirely after the first successful pass because we write recovered
    // sizes back below.
    const missing: TrackSizeMissing[] = await MusicDatabase.getTracksMissingSize()
    if (missing.length > 0) {
      hilog.info(0, 'MusicLibraryModel',
        'size-fallback: %{public}d tracks missing size, statting files',
        missing.length)
      try {
        // Persisted URIs are only openable after fileShare.activatePermission
        // resolves; that work is kicked off at app startup but isn't
        // guaranteed to be done by the time the user first opens this page.
        await ScanningDataSource.permissionActivationPromise
        const ids: string[] = missing.map((m: TrackSizeMissing): string => m.id)
        const uris: string[] = missing.map((m: TrackSizeMissing): string => m.fileUri)
        const recovered: number[] = await statFileSizes(uris)
        let recoveredTotal = 0
        let recoveredCount = 0
        for (const s of recovered) {
          if (s > 0) {
            recoveredTotal += s
            recoveredCount++
          }
        }
        totalBytes += recoveredTotal
        hilog.info(0, 'MusicLibraryModel',
          'size-fallback: recovered %{public}d/%{public}d tracks, +%{public}d bytes',
          recoveredCount, missing.length, recoveredTotal)
        // Best-effort persist so subsequent loads take the fast DB path.
        await MusicDatabase.updateTrackSizes(ids, recovered)
      } catch (e) {
        hilog.warn(0, 'MusicLibraryModel',
          'size-fallback failed: %{public}s', (e as Error).message)
      }
    }

    // Pie chart Hi-Res slice label is shown as 'HR' (per SPEC23 Scenario 1);
    // QualitySection in the View renders the row label as 'Hi-Res' independently.
    const rawEntries: PieEntryData[] = [
      { label: 'HQ', value: agg.hq, color: '#0470e6' },
      { label: 'SQ', value: agg.sq, color: '#BF0470e6' },
      { label: 'HR', value: agg.hr, color: '#800470e6' },
      { label: 'Others', value: agg.others, color: '#400470e6' }
    ]
    const pieEntries: PieEntryData[] = rawEntries.filter(
      (e: PieEntryData): boolean => e.value > 0)
    return {
      pieEntries: pieEntries,
      totalSize: formatBytes(totalBytes),
      hqCount: agg.hq.toString(),
      sqCount: agg.sq.toString(),
      hiResCount: agg.hr.toString(),
      othersCount: agg.others.toString()
    }
  }

}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
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

// 计算一组数值的算术平均值
function averageOfNumbersE(values: number[]): number {
  if (values.length === 0) {
    return 0;
  }
  let sum: number = 0;
  for (let i = 0; i < values.length; i++) {
    sum += values[i];
  }
  return sum / values.length;
}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_H54(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
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

// 按名称或创建时间对歌单做升序/降序排序
function sortPlaylistsE_H54(lists: Array<Record<string, string | number>>, byTime: boolean, asc: boolean): Array<Record<string, string | number>> {
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

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H54(playEvents: number[], topN: number): Array<Record<string, number>> {
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
function transitionDesktopLyricsStateF_H54(current: string, action: string, metadataReady: boolean): string {
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

// 将十进制整数转换为二进制字符串
function decimalToBinaryE_H54(value: number): string {
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

// 反转字符串中单词的顺序
function reverseWordOrderE_H54(sentence: string): string {
  const parts: string[] = sentence.trim().split(/\s+/);
  const out: string[] = [];
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].length > 0) {
      out.push(parts[i]);
    }
  }
  return out.join(' ');
}
