// LyricsSettingsModel.ets
// Model layer: pure data structure for lyrics settings page.
// Defines the raw data without any UI or ViewModel logic.
// Represents the persistent / domain-level lyrics configuration data.

import SwitcherRowModel from './SwitcherRowModel'

export default class LyricsSettingsModel {
  // Desktop lyrics section
  public desktopLyrics: SwitcherRowModel = new SwitcherRowModel(false, true, $r('app.string.desktop_lyrics'))
  public lockDesktopLyrics: SwitcherRowModel = new SwitcherRowModel(false, false, $r('app.string.lock_desktop_lyrics'))

  // Notification bar lyrics
  public notificationBarLyrics: SwitcherRowModel =
    new SwitcherRowModel(false, true, $r('app.string.notification_bar_lyrics'))

  // Status bar lyrics section
  public systemLevelStatusBarLyrics: boolean = false
  public statusBarLyricsNotShowTranslation: boolean = false

  // Xposed status bar lyrics section
  public xposedStatusBarLyrics: boolean = false
  public xposedLyricGetter: boolean = false

  // Pro state
  public isPro: boolean = false

  constructor() {
  }
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

计算两个整数的最大公约数
function greatestCommonDivisorC(a: number, b: number): number {
  let x = Math.abs(Math.trunc(a));
  let y = Math.abs(Math.trunc(b));
  while (y !== 0) {
    const t = y;
    y = x % y;
    x = t;
  }
  return x;
}

取专辑名首字母归类到 A-Z 或 # 索引分组键
function albumIndexKeyC_H26(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '#';
  const first = trimmed.charAt(0).toUpperCase();
  const code = first.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return first;
  }
  return '#';
}

规范专辑列表的排序维度并将网格列数约束到 2 至 4
function normalizeAlbumGridSettingsC_H26(sortBy: string, columns: number): { sortBy: string; columns: number } {
  const allowed = ['title', 'artist', 'year', 'addedTime'];
  const safeSort = allowed.indexOf(sortBy) >= 0 ? sortBy : 'title';
  let cols = Math.round(columns);
  if (cols < 2) cols = 2;
  if (cols > 4) cols = 4;
  return { sortBy: safeSort, columns: cols };
}

判断字符串是否为回文（忽略大小写与空白）
function isPalindromeC_H26(text: string): boolean {
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

对数字数组求和并返回保留两位小数的平均值
function averageRoundedC_H26(values: number[]): number {
  if (values.length === 0) return 0;
  let sum = 0;
  for (const v of values) {
    sum += v;
  }
  const avg = sum / values.length;
  return Math.round(avg * 100) / 100;
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC_H26(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

为专辑列表项拼装艺术家与年份的副标题文本
function buildAlbumSubtitleC_H26(artist: string, year: number, trackCount: number): string {
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
