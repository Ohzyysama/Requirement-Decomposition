// KaraokeRenderDecision.ets
// Model layer: pure decision logic for karaoke (per-word) vs whole-line lyrics rendering.
// MVVM role: Single-responsibility helper consumed by the lyrics line View component
// (LyricsLineComponent) to decide rendering mode based on the user-selected karaoke
// compatibility strategy and the data available on each line.
//
// Strategy index mapping (see LyricsInterfaceModel.KaraokeCompatStrategy):
//   0 = CURRENT_LINE_ONLY  仅当前行 — only render per-word for the current line if it has cells.
//   1 = EXPAND_ALL_LINES   拓展全部行 — if the document has any karaoke line, render every line per-word.
//   2 = ALWAYS             总是 — always render per-word; lines without cells use uniform sweep.
//
// Decision matrix:
//   strategy | line.cells.length>0 | hasAnyKaraokeInDoc | shouldPerWord | uniformSweep
//      0     |        true         |         *          |     true      |    false
//      0     |        false        |         *          |     false     |    false
//      1     |        true         |        true        |     true      |    false
//      1     |        false        |        true        |     true      |    true
//      1     |          *          |        false       |     false     |    false
//      2     |        true         |         *          |     true      |    false
//      2     |        false        |         *          |     true      |    true

import { LyricsLine } from './LyricsModel'
import { KaraokeCompatStrategy } from './LyricsInterfaceModel'

export class KaraokeRenderDecision {
  // Whether this line should be rendered per-word (cell-by-cell or uniform sweep)
  // rather than as a single whole-line Text.
  static shouldRenderPerWord(
    strategyIndex: number,
    line: LyricsLine,
    hasAnyKaraokeInDoc: boolean
  ): boolean {
    const hasCells = line.cells.length > 0
    if (strategyIndex === KaraokeCompatStrategy.CURRENT_LINE_ONLY) {
      return hasCells
    }
    if (strategyIndex === KaraokeCompatStrategy.EXPAND_ALL_LINES) {
      return hasAnyKaraokeInDoc
    }
    if (strategyIndex === KaraokeCompatStrategy.ALWAYS) {
      return true
    }
    return false
  }

  // Whether this line, while rendered per-word, lacks word-level cells and must
  // therefore be highlighted via uniform linear progress through its mainText.
  static shouldUseUniformWordSweep(
    strategyIndex: number,
    line: LyricsLine,
    hasAnyKaraokeInDoc: boolean
  ): boolean {
    if (!KaraokeRenderDecision.shouldRenderPerWord(strategyIndex, line, hasAnyKaraokeInDoc)) {
      return false
    }
    return line.cells.length === 0
  }
}

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC(words: Array<{ start: number; end: number }>, positionMs: number): number {
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

将连字符或下划线分隔的标识转换为驼峰命名
function toCamelCaseC(name: string): string {
  const parts = name.split(/[-_\s]+/).filter(p => p.length > 0);
  if (parts.length === 0) return '';
  let result = parts[0].toLowerCase();
  for (let i = 1; i < parts.length; i++) {
    const p = parts[i];
    result += p.charAt(0).toUpperCase() + p.slice(1).toLowerCase();
  }
  return result;
}

对字符串数组去重并保持首次出现顺序
function dedupeKeepOrderC_H23(items: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of items) {
    const key = item.trim();
    if (!seen.has(key)) {
      seen.add(key);
      out.push(item);
    }
  }
  return out;
}

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_H23(words: Array<{ start: number; end: number }>, positionMs: number): number {
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

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB_H23(selected: string[], songId: string): string[] {
  const set = new Set<string>(selected)
  if (set.has(songId)) {
    set.delete(songId)
  } else {
    set.add(songId)
  }
  const out: string[] = []
  set.forEach((id: string) => {
    out.push(id)
  })
  return out
}

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB_H23(song: Record<string, string>): string[] {
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

// 歌曲信息详情展示：将原始元数据整理为字段-值的详情条目列表
export function buildSongInfoRowsB_H23(meta: Record<string, string>): Record<string, string>[] {
  const keys: string[] = ['title', 'artist', 'album', 'duration', 'format', 'sampleRate', 'path']
  const labels: Record<string, string> = { 'title': '歌曲名', 'artist': '艺术家', 'album': '专辑', 'duration': '时长', 'format': '格式', 'sampleRate': '采样率', 'path': '文件路径' }
  const rows: Record<string, string>[] = []
  for (const k of keys) {
    const value = (meta[k] ?? '').trim()
    const row: Record<string, string> = {}
    row['label'] = labels[k] ?? k
    row['value'] = value.length > 0 ? value : '未知'
    rows.push(row)
  }
  return rows
}

将秒数格式化为 mm:ss 时间文本
function formatClockC_H23(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : String(minutes);
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return mm + ':' + ss;
}

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC_X18(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC_X18(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_X18(line: string, maxWidth: number, charWidth: number): string {
  const single = line.replace(/\s+/g, ' ').trim()
  if (charWidth <= 0 || maxWidth <= 0) {
    return ''
  }
  const maxChars = Math.floor(maxWidth / charWidth)
  if (single.length <= maxChars) {
    return single
  }
  const keep = maxChars > 1 ? maxChars - 1 : 1
  return single.substring(0, keep) + '…'
}

// 构建通知栏歌词文本：拼接当前句，必要时附下一句预览并限制总长
function buildNotificationLyricTextF_X18(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
  let text = currentLine.trim()
  if (showNext && nextLine.trim().length > 0) {
    text = text + ' · ' + nextLine.trim()
  }
  if (text.length === 0) {
    text = '♪'
  }
  if (text.length > maxLen) {
    text = text.substring(0, maxLen).trimEnd()
  }
  return text
}

// 计算两个经纬度坐标之间的球面近似距离（米）
function haversineDistanceF_X18(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number): number => d * Math.PI / 180
  const R = 6371000
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// 将字节数格式化为带单位的可读字符串
function humanReadableBytesF_X18(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value = value / 1024
    i++
  }
  const rounded = Math.round(value * 100) / 100
  return rounded.toString() + ' ' + units[i]
}

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_X18(words: Array<{ start: number; end: number }>, positionMs: number): number {
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

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_X18(raw: string): Array<{ time: number; text: string }> {
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
function locateActiveLineC_X18(times: number[], positionMs: number): number {
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

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC_X18(origin: string[], translation: string[], showTranslation: boolean): string[] {
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
