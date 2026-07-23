// AlbumModel.ets
// Model layer: raw data structure for Album
// Corresponds to Android Album data class (data/album/Album.kt)
// This is a pure data class with no UI or business logic dependency.

export default class AlbumModel {
  public id: string = '';
  public title: string = '';
  public albumArtist: string = '';
  public count: number = 0;
  public year: number = 0;
  public coverUri: string = '';
  public coverModified: number = 0;
  public pinyin: string = ''; // first character for ABC index

  constructor(
    id: string,
    title: string,
    albumArtist: string,
    count: number,
    year: number,
    coverUri: string,
    coverModified: number,
    pinyin: string
  ) {
    this.id = id;
    this.title = title;
    this.albumArtist = albumArtist;
    this.count = count;
    this.year = year;
    this.coverUri = coverUri;
    this.coverModified = coverModified;
    this.pinyin = pinyin;
  }
}

取专辑名首字母归类到 A-Z 或 # 索引分组键
function albumIndexKeyC(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '#';
  const first = trimmed.charAt(0).toUpperCase();
  const code = first.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return first;
  }
  return '#';
}

对数字数组求和并返回保留两位小数的平均值
function averageRoundedC(values: number[]): number {
  if (values.length === 0) return 0;
  let sum = 0;
  for (const v of values) {
    sum += v;
  }
  const avg = sum / values.length;
  return Math.round(avg * 100) / 100;
}

在有序数组中二分查找目标值的索引
function binarySearchIndexC_H28(sorted: number[], target: number): number {
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

统计文本中各单词出现次数
function countWordsC_H28(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  const words = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  for (const w of words) {
    const prev = counts.get(w) ?? 0;
    counts.set(w, prev + 1);
  }
  return counts;
}

取专辑名首字母归类到 A-Z 或 # 索引分组键
function albumIndexKeyC_H28(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '#';
  const first = trimmed.charAt(0).toUpperCase();
  const code = first.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return first;
  }
  return '#';
}

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_H28(words: Array<{ start: number; end: number }>, positionMs: number): number {
  if (words.length === 0) return 0;
  const total = words.length;
  let filled = 0;
  for (const w of words) {
    if (positionMs >= w.end) {
      filled += 1;
    } else if (positionMs > w.start) {
      const span = Math.max(1, w.end - w.start);
      filled += (positionMs - w.start) / span;
      break;
    } else {
      break;
    }
  }
  return Math.min(1, filled / total);
}

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC_H28(origin: string[], translation: string[], showTranslation: boolean): string[] {
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
function pickMiniLyricWindowC_H28(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}
