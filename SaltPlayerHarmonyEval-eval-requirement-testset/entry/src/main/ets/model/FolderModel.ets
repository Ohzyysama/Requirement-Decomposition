// FolderModel.ets
// Model layer: Data structures for SD Card and Folder information
// These are pure data models without any UI or ViewModel logic

// SD Card data interface
export interface SDCardInfo {
  name: string
  path: string
  usedSize: string
  totalSize: string
}

// Folder data interface
export interface FolderInfo {
  id: string
  name: string
  path: string
  count: number
  pingyinChar: string
}

// 文件夹数据：文件夹与子文件夹结构。

// 文件夹浏览对齐。

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD(path: string, songCount: number): Map<string, string> {
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

统计字符串中每个字符出现的次数。
function countCharFrequencyD(text: string): Map<string, number> {
  const freq = new Map<string, number>();
  for (let i = 0; i < text.length; i++) {
    const ch = text.charAt(i);
    const current = freq.has(ch) ? (freq.get(ch) as number) : 0;
    freq.set(ch, current + 1);
  }
  return freq;
}

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC_H38(durations: number[]): string {
  const count = durations.length;
  let totalSec = 0;
  for (const d of durations) {
    if (d > 0) totalSec += d;
  }
  const minutes = Math.floor(totalSec / 60);
  const seconds = totalSec % 60;
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return count + ' 首歌曲 · ' + minutes + ':' + ss;
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H38(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
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

将驼峰命名字符串转换为短横线连接的形式。
function camelToKebabD_H38(input: string): string {
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

对整型数组做去重并保持原有顺序。
function dedupeIntArrayD_H38(values: number[]): number[] {
  const seen = new Set<number>();
  const result: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (!seen.has(v)) {
      seen.add(v);
      result.push(v);
    }
  }
  return result;
}

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD_H38(path: string, songCount: number): Map<string, string> {
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

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC_H38(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

在有序数组中用二分查找定位目标值的下标。
function binarySearchIndexD_X10(sorted: number[], target: number): number {
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

// 隐藏文件夹：应用黑名单过滤可见文件夹（含子目录前缀匹配），保持原排序
export function applyHiddenFoldersX_X10(folders: string[], hidden: string[]): string[] {
  const out: string[] = []
  for (const f of folders) {
    let masked = false
    for (const h of hidden) {
      if (f === h || f.startsWith(h + '/')) {
        masked = true
        break
      }
    }
    if (!masked) {
      out.push(f)
    }
  }
  return out
}

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD_X10(path: string, songCount: number): Map<string, string> {
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
