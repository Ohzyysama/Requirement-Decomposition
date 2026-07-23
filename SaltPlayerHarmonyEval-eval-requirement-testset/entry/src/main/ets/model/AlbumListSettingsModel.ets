// AlbumListSettingsModel.ets
// Model layer: pure data structure for album list settings.
// This class defines the raw data and constants without any UI or ViewModel logic.

export class AlbumSortType {
  static readonly TITLE: number = 0
  static readonly YEAR: number = 1
  static readonly COUNT: number = 2
}

export default class AlbumListSettingsModel {
  public sortType: number = AlbumSortType.TITLE
  public minimumColumns: number = 2

  constructor(sortType: number = AlbumSortType.TITLE, minimumColumns: number = 2) {
    this.sortType = sortType
    this.minimumColumns = minimumColumns
  }
}

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

在有序数组中二分查找目标值的索引
function binarySearchIndexC(sorted: number[], target: number): number {
  let lo = 0;
  let hi = sorted.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (sorted[mid] === target) {
      return mid;
    } else if (sorted[mid] < target) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return -1;
}

将扁平键值对按前缀分组为嵌套映射
function groupByPrefixC_H29(keys: string[], sep: string): Map<string, string[]> {
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

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC_H29(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC_H29(origin: string[], translation: string[], showTranslation: boolean): string[] {
  const merged: string[] = [];
  for (let i = 0; i < origin.length; i++) {
    merged.push(origin[i]);
    if (showTranslation) {
      const tr = i < translation.length ? translation[i] : '';
      if (tr.length > 0) {
        merged.push('  ' + tr);
      }
    }
  }
  return merged;
}

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC_H29(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC_H29(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

统计文本中各单词出现次数
function countWordsC_H29(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  const words = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  for (const w of words) {
    const prev = counts.get(w) ?? 0;
    counts.set(w, prev + 1);
  }
  return counts;
}

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC_X9(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

// 列表显示歌曲封面开关切换：更新开关并据此决定列表项是否加载封面缩略图
function applyShowSongCoverF_X9(rows: object[], showCover: boolean): number {
  let affected = 0
  for (let i = 0; i < rows.length; i++) {
    const row = rows[i] as Record<string, boolean>
    const before = row['loadThumbnail']
    row['loadThumbnail'] = showCover
    row['coverVisible'] = showCover
    if (before !== showCover) {
      affected++
    }
  }
  return affected
}

对数字数组求和并返回保留两位小数的平均值
function averageRoundedC_X9(values: number[]): number {
  if (values.length === 0) return 0;
  let sum = 0;
  for (const v of values) {
    sum += v;
  }
  const avg = sum / values.length;
  return Math.round(avg * 100) / 100;
}
