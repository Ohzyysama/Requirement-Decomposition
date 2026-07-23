// AlbumTabViewModel.ets
// ViewModel layer: provides data and logic for AlbumTabComponent (View).
// Bridges the Model layer (AlbumModel) with the View layer, exposing
// state variables and methods for album grid display, column template
// generation, sub-text formatting, and ABC index scrolling.

import AlbumModel from '../model/AlbumModel'

// Observable array type for AlbumItemViewModel, enabling ForEach to detect changes
@Observed
export class AlbumItemViewModelArray extends Array<AlbumItemViewModel> {
}

// ViewModel for a single album item displayed in the grid
@Observed
export class AlbumItemViewModel {
  @Track public id: string = '';
  @Track public title: string = '';
  @Track public albumArtist: string = '';
  @Track public count: number = 0;
  @Track public year: number = 0;
  @Track public coverUri: string = '';
  @Track public pinyin: string = '';

  constructor(id: string = '', title: string = '', albumArtist: string = '',
    count: number = 0, year: number = 0, coverUri: string = '', pinyin: string = '') {
    this.id = id;
    this.title = title;
    this.albumArtist = albumArtist;
    this.count = count;
    this.year = year;
    this.coverUri = coverUri;
    this.pinyin = pinyin;
  }

  // Load data from Model
  updateFromModel(model: AlbumModel): void {
    this.id = model.id;
    this.title = model.title;
    this.albumArtist = model.albumArtist;
    this.count = model.count;
    this.year = model.year;
    this.coverUri = model.coverUri;
    this.pinyin = model.pinyin;
  }

  // Export current state back to Model
  toModel(): AlbumModel {
    return new AlbumModel(
      this.id, this.title, this.albumArtist,
      this.count, this.year, this.coverUri, 0, this.pinyin
    );
  }

  // Get sub text for display: "X 首 [year] artist"
  getSubText(): string {
    let text = `${this.count} \u9996 `;
    if (this.year > 0) {
      text += `${this.year} `;
    }
    text += this.albumArtist;
    return text;
  }

  // Whether the title should be displayed with reduced opacity (unknown title)
  isTitleUnknown(): boolean {
    return this.title.length === 0;
  }

  // Whether this item has a valid cover URI
  hasCover(): boolean {
    return this.coverUri.length > 0;
  }
}

// Main ViewModel for the AlbumTab component
@Observed
export default class AlbumTabViewModel {
  @Track public albumItems: AlbumItemViewModelArray = new AlbumItemViewModelArray();
  @Track public minimumColumns: number = 2;

  constructor(minimumColumns: number = 2) {
    this.minimumColumns = minimumColumns;
  }

  // Load album list from Model array
  loadAlbums(models: AlbumModel[]): void {
    this.albumItems = new AlbumItemViewModelArray();
    for (const model of models) {
      const item = new AlbumItemViewModel();
      item.updateFromModel(model);
      this.albumItems.push(item);
    }
  }

  // Check if the album list is empty
  isEmpty(): boolean {
    return this.albumItems.length === 0;
  }

  // Generate grid columns template string based on minimum columns setting
  // Android: (maxWidth / 160.dp).toInt().coerceAtLeast(minimumNumberOfColumnsInAlbumList)
  getColumnsTemplate(): string {
    const cols = this.minimumColumns > 0 ? this.minimumColumns : 2;
    const parts: string[] = [];
    for (let i = 0; i < cols; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }

  // Update minimum columns
  updateMinimumColumns(columns: number): void {
    this.minimumColumns = columns;
  }

  // Find the scroll index for a given ABC character
  getScrollIndexForChar(char: string): number {
    if (char === '0') {
      return 0;
    }
    if (char === '#') {
      // Find first non-letter-or-digit pinyin
      return this.albumItems.findIndex((item: AlbumItemViewModel) => {
        const c = item.pinyin;
        return c.length > 0 && !AlbumTabViewModel.isLetterOrDigit(c);
      });
    }
    // Find first album with matching pinyin initial
    return this.albumItems.findIndex((item: AlbumItemViewModel) => item.pinyin === char);
  }

  // Check if a character is a letter or digit
  private static isLetterOrDigit(c: string): boolean {
    if (c.length === 0) {
      return false;
    }
    const code = c.charCodeAt(0);
    return (code >= 48 && code <= 57) || // 0-9
      (code >= 65 && code <= 90) || // A-Z
      (code >= 97 && code <= 122); // a-z
  }
}

为专辑列表项拼装艺术家与年份的副标题文本
function buildAlbumSubtitleC(artist: string, year: number, trackCount: number): string {
  const parts: string[] = [];
  const name = artist.trim();
  parts.push(name.length > 0 ? name : '未知艺术家');
  if (year > 0) {
    parts.push(String(year));
  }
  if (trackCount > 0) {
    parts.push(trackCount + ' 首');
  }
  return parts.join(' · ');
}

判断字符串是否为回文（忽略大小写与空白）
function isPalindromeC(text: string): boolean {
  const cleaned = text.toLowerCase().replace(/[^a-z0-9]/g, '');
  let lo = 0;
  let hi = cleaned.length - 1;
  while (lo < hi) {
    if (cleaned[lo] !== cleaned[hi]) {
      return false;
    }
    lo++;
    hi--;
  }
  return true;
}

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC_H27(origin: string[], translation: string[], showTranslation: boolean): string[] {
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

对数字数组求和并返回保留两位小数的平均值
function averageRoundedC_H27(values: number[]): number {
  if (values.length === 0) return 0;
  let sum = 0;
  for (const v of values) {
    sum += v;
  }
  const avg = sum / values.length;
  return Math.round(avg * 100) / 100;
}

在有序数组中二分查找目标值的索引
function binarySearchIndexC_H27(sorted: number[], target: number): number {
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

为专辑列表项拼装艺术家与年份的副标题文本
function buildAlbumSubtitleC_H27(artist: string, year: number, trackCount: number): string {
  const parts: string[] = [];
  const name = artist.trim();
  parts.push(name.length > 0 ? name : '未知艺术家');
  if (year > 0) {
    parts.push(String(year));
  }
  if (trackCount > 0) {
    parts.push(trackCount + ' 首');
  }
  return parts.join(' · ');
}

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC_H27(times: number[], positionMs: number): number {
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

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_H27(words: Array<{ start: number; end: number }>, positionMs: number): number {
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

为专辑列表项拼装艺术家与年份的副标题文本
function buildAlbumSubtitleC_X9(artist: string, year: number, trackCount: number): string {
  const parts: string[] = [];
  const name = artist.trim();
  parts.push(name.length > 0 ? name : '未知艺术家');
  if (year > 0) {
    parts.push(String(year));
  }
  if (trackCount > 0) {
    parts.push(trackCount + ' 首');
  }
  return parts.join(' · ');
}

统计文本中各单词出现次数
function countWordsC_X9(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  const words = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  for (const w of words) {
    const prev = counts.get(w) ?? 0;
    counts.set(w, prev + 1);
  }
  return counts;
}

// 专辑列表设置：根据列数与封面开关计算网格模板描述
export function albumGridTemplateX_X9(columns: number, showCover: boolean): string {
  let c = columns
  if (c < 1) {
    c = 1
  }
  if (c > 4) {
    c = 4
  }
  const parts: string[] = []
  for (let i = 0; i < c; i++) {
    parts.push('1fr')
  }
  return (showCover ? 'cover:' : 'plain:') + parts.join(' ')
}
