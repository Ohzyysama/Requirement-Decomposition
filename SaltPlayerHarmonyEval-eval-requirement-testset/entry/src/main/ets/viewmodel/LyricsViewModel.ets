// LyricsViewModel.ets
// ViewModel layer: lyrics sync engine and state management.
// MVVM role: Bridges LyricsModel data with the lyrics UI components.
// Manages current line tracking, user scroll state, and translation toggle.

import {
  LyricsDocument,
  LyricsLine,
  LyricsPackage,
  LyricsSource,
  LyricsLoader
} from '../model/LyricsModel'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class LyricsViewModel {
  // ==================== Observable State ====================
  @Track public document: LyricsDocument = new LyricsDocument()
  @Track public currentLineIndex: number = -1
  @Track public currentTimeMs: number = 0
  @Track public source: string = LyricsSource.NOT_FOUND
  // Spec17: hydrate from persisted AppStorage so the toggle survives song
  // changes and app restart. EntryAbility.onCreate seeds the AppStorage value
  // before any VM is constructed, so the read here always sees the restored
  // setting (default true).
  @Track public openTranslation: boolean = (AppStorage.get<boolean>('lyricsOpenTranslation') ?? true)
  @Track public hasTranslation: boolean = false
  @Track public isUserScrolling: boolean = false
  @Track public isLoading: boolean = false
  @Track public lyricsVersion: number = 0

  // ==================== Internal State ====================
  private userScrollTimerId: number = -1
  private loadId: number = 0
  private seekCooldown: number = 0
  // Whether the user's finger is currently touching the lyrics list
  private isTouching: boolean = false
  // Spec17: listeners notified when openTranslation flips. The PlayerPageVM
  // subscribes here to rebuild mini-lyrics with interleaved translation lines.
  private translationListeners: Array<(open: boolean) => void> = []
  private static readonly USER_SCROLL_RESUME_DELAY: number = 1500

  // ==================== Lyrics Loading ====================

  async loadLyrics(fileUri: string, songId: string): Promise<void> {
    console.info('[LyricsViewModel] loadLyrics start, fileUri: ' + fileUri + ', songId: ' + songId)
    // Increment race guard (non-reactive, only for stale detection)
    this.loadId++
    const myLoadId = this.loadId
    // Reset state for new song — clear document immediately so updateProgress
    // won't match new song's time against the old song's lyrics during async loading
    this.currentLineIndex = -1
    this.currentTimeMs = 0
    this.document = new LyricsDocument()
    this.source = LyricsSource.NOT_FOUND
    this.hasTranslation = false
    this.isUserScrolling = false
    AppStorage.setOrCreate('lyricsIsUserScrolling', false)
    this.clearUserScrollTimer()
    this.lyricsVersion++

    if (!fileUri || fileUri.length === 0) {
      this.document = new LyricsDocument()
      this.source = LyricsSource.NOT_FOUND
      this.hasTranslation = false
      this.lyricsVersion++
      return
    }

    this.isLoading = true
    try {
      const pkg: LyricsPackage = await LyricsLoader.loadLyrics(fileUri, songId)
      // Discard stale result if a newer loadLyrics call has started
      if (myLoadId !== this.loadId) {
        console.info('[LyricsViewModel] loadLyrics discarded stale result for songId: ' + songId)
        return
      }
      this.document = pkg.document
      this.source = pkg.source
      this.hasTranslation = pkg.document.hasTranslation
      // Reset currentLineIndex so updateProgress re-evaluates on the new document
      this.currentLineIndex = -1
      // Increment AFTER document is set — ForEach key change and data change in same frame
      this.lyricsVersion++
    } catch (err) {
      console.error('[LyricsViewModel] loadLyrics failed: ' + (err as Error).message)
      if (myLoadId !== this.loadId) {
        return
      }
      this.document = new LyricsDocument()
      this.source = LyricsSource.NOT_FOUND
      this.hasTranslation = false
      this.lyricsVersion++
    } finally {
      if (myLoadId === this.loadId) {
        this.isLoading = false
      }
      console.info('[LyricsViewModel] loadLyrics done, source: ' + this.source +
        ', lines: ' + this.document.lines.length +
        ', isEmpty: ' + this.document.isEmpty)
    }
  }

  // ==================== Progress Sync ====================

  updateProgress(currentTimeMs: number): void {
    this.currentTimeMs = currentTimeMs

    if (this.document.isEmpty || !this.document.isScrollable) {
      this.currentLineIndex = -1
      return
    }

    // Skip progress updates briefly after seek to avoid race conditions
    if (this.seekCooldown > 0) {
      this.seekCooldown--
      return
    }

    const newIndex = this.findCurrentLine(currentTimeMs)
    if (newIndex !== this.currentLineIndex) {
      // Clear previous current line
      if (this.currentLineIndex >= 0 && this.currentLineIndex < this.document.lines.length) {
        this.document.lines[this.currentLineIndex].isCurrent = false
      }
      this.currentLineIndex = newIndex
      if (newIndex >= 0 && newIndex < this.document.lines.length) {
        this.document.lines[newIndex].isCurrent = true
      }
    }
  }

  // ==================== Line Seeking ====================

  seekToLine(index: number): number {
    if (index >= 0 && index < this.document.lines.length) {
      const line: LyricsLine = this.document.lines[index]
      // Only clear isCurrent on the old line (avoid O(n) traversal)
      if (this.currentLineIndex >= 0 && this.currentLineIndex < this.document.lines.length) {
        this.document.lines[this.currentLineIndex].isCurrent = false
      }
      this.currentLineIndex = index
      line.isCurrent = true
      this.currentTimeMs = line.startTime
      // Resume auto-scrolling immediately after seeking
      this.isUserScrolling = false
      this.clearUserScrollTimer()
      // Reduced cooldown for faster progress sync recovery
      this.seekCooldown = 1
      return line.startTime
    }
    return -1
  }

  // ==================== Translation Toggle ====================

  toggleTranslation(): void {
    this.openTranslation = !this.openTranslation
    // Spec17: persist to disk so the choice survives song changes and app
    // restart, and broadcast so PlayerPageVM (mini-lyrics) can refresh.
    SettingsStore.getInstance().save('lyricsOpenTranslation', this.openTranslation)
    for (const fn of this.translationListeners) {
      try {
        fn(this.openTranslation)
      } catch (_e) {
        // ignore listener failures so one bad subscriber can't block others
      }
    }
  }

  // Spec17: external observers (e.g. PlayerPageViewModel) subscribe so they
  // can rebuild derived state (mini-lyrics interleaving) on toggle.
  addTranslationChangedListener(fn: (open: boolean) => void): void {
    this.translationListeners.push(fn)
  }

  removeTranslationChangedListener(fn: (open: boolean) => void): void {
    const idx = this.translationListeners.indexOf(fn)
    if (idx >= 0) {
      this.translationListeners.splice(idx, 1)
    }
  }

  // ==================== User Scroll Handling ====================

  onUserScrollStart(): void {
    this.isUserScrolling = true
    this.isTouching = true
    this.clearUserScrollTimer()
    AppStorage.setOrCreate('lyricsIsUserScrolling', true)
  }

  onUserScrollEnd(): void {
    this.isTouching = false
    this.clearUserScrollTimer()
    this.userScrollTimerId = setTimeout(() => {
      this.resumeAutoSync()
    }, LyricsViewModel.USER_SCROLL_RESUME_DELAY)
  }

  // Force-cancel user scroll state and immediately re-sync to current playback position
  resumeAutoSync(): void {
    this.clearUserScrollTimer()
    this.isUserScrolling = false
    AppStorage.setOrCreate('lyricsIsUserScrolling', false)
    if (this.document.isScrollable) {
      const newIndex = this.findCurrentLine(this.currentTimeMs)
      if (newIndex !== this.currentLineIndex) {
        if (this.currentLineIndex >= 0 && this.currentLineIndex < this.document.lines.length) {
          this.document.lines[this.currentLineIndex].isCurrent = false
        }
        this.currentLineIndex = newIndex
        if (newIndex >= 0 && newIndex < this.document.lines.length) {
          this.document.lines[newIndex].isCurrent = true
        }
      }
    }
  }

  private clearUserScrollTimer(): void {
    if (this.userScrollTimerId !== -1) {
      clearTimeout(this.userScrollTimerId)
      this.userScrollTimerId = -1
    }
  }

  // ==================== Source Tag ====================

  getSourceTag(): string {
    switch (this.source) {
      case LyricsSource.EMBEDDED:
        return 'EMBEDDED'
      case LyricsSource.LRC_FILE:
        return 'LRC'
      case LyricsSource.NOT_FOUND:
      default:
        return 'NOT FOUND'
    }
  }

  // ==================== Binary Search for Current Line ====================

  private findCurrentLine(timeMs: number): number {
    const lines: LyricsLine[] = this.document.lines
    if (lines.length === 0) {
      return -1
    }

    // Before the first line
    if (timeMs < lines[0].startTime) {
      return -1
    }

    // Binary search: find the last line whose startTime <= timeMs
    let low = 0
    let high = lines.length - 1
    let result = 0

    while (low <= high) {
      const mid = Math.floor((low + high) / 2)
      if (lines[mid].startTime <= timeMs) {
        result = mid
        low = mid + 1
      } else {
        high = mid - 1
      }
    }

    return result
  }

  // ==================== Cleanup ====================

  destroy(): void {
    this.clearUserScrollTimer()
  }
}

// 歌词同步滚动：随播放进度高亮当前行并平滑滚动到可视区域。

// 迷你歌词：播放页迷你歌词模式下的当前行展示。

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC(times: number[], positionMs: number): number {
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

对操作进行防抖，仅在静默期后执行最后一次调用
function debounceCallC(calls: number[], gapMs: number): number[] {
  const fired: number[] = [];
  let last = -Infinity;
  for (let i = 0; i < calls.length; i++) {
    const t = calls[i];
    const isLast = i === calls.length - 1;
    const nextGap = isLast ? Infinity : calls[i + 1] - t;
    if (t - last >= gapMs || nextGap >= gapMs) {
      fired.push(t);
      last = t;
    }
  }
  return fired;
}

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC(origin: string[], translation: string[], showTranslation: boolean): string[] {
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

将秒数格式化为 mm:ss 时间文本
function formatClockC(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : String(minutes);
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return mm + ':' + ss;
}

将连字符或下划线分隔的标识转换为驼峰命名
function toCamelCaseC_H22(name: string): string {
  const parts = name.split(/[-_\s]+/).filter(p => p.length > 0);
  if (parts.length === 0) return '';
  let result = parts[0].toLowerCase();
  for (let i = 1; i < parts.length; i++) {
    const p = parts[i];
    result += p.charAt(0).toUpperCase() + p.slice(1).toLowerCase();
  }
  return result;
}

将秒数格式化为 mm:ss 时间文本
function formatClockC_H22(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : String(minutes);
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return mm + ':' + ss;
}

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC_H22(times: number[], positionMs: number): number {
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

// 歌曲随机播放全部：用洗牌算法生成全部歌曲的随机播放顺序
export function shuffleAllSongsB_H22(songIds: string[]): string[] {
  const order = songIds.slice()
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  return order
}

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB_H22(selected: string[], songId: string): string[] {
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
export function buildSongMenuItemsB_H22(song: Record<string, string>): string[] {
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

按显示开关将原文行与翻译行合并为待渲染的展示序列
function mergeTranslationLinesC_H24(origin: string[], translation: string[], showTranslation: boolean): string[] {
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

// 歌曲更多操作菜单：依据歌曲来源与收藏态动态构建可用菜单项
export function buildSongMenuItemsB_H24(song: Record<string, string>): string[] {
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
export function buildSongInfoRowsB_H24(meta: Record<string, string>): Record<string, string>[] {
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

为专辑列表项拼装艺术家与年份的副标题文本
function buildAlbumSubtitleC_H24(artist: string, year: number, trackCount: number): string {
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

对字符串数组去重并保持首次出现顺序
function dedupeKeepOrderC_H24(items: string[]): string[] {
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

计算两个整数的最大公约数
function greatestCommonDivisorC_H24(a: number, b: number): number {
  let x = Math.abs(Math.trunc(a));
  let y = Math.abs(Math.trunc(b));
  while (y !== 0) {
    const t = y;
    y = x % y;
    x = t;
  }
  return x;
}

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_X4(raw: string): Array<{ time: number; text: string }> {
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

依据每个字的起止时间计算当前毫秒下整行的高亮填充比例
function karaokeFillRatioC_X4(words: Array<{ start: number; end: number }>, positionMs: number): number {
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

将秒数格式化为 mm:ss 时间文本
function formatClockC_X4(totalSeconds: number): string {
  const safe = Math.max(0, Math.floor(totalSeconds));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : String(minutes);
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return mm + ':' + ss;
}

在已排序时间戳数组中二分定位当前播放毫秒对应的歌词行索引
function locateActiveLineC_X4(times: number[], positionMs: number): number {
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

// 歌词滚动：计算当前行垂直居中所需的滚动偏移并夹取上下边界
export function lyricScrollOffsetX_X4(lineTops: number[], active: number, viewportH: number, contentH: number): number {
  if (active < 0 || active >= lineTops.length) {
    return 0
  }
  let offset = lineTops[active] - viewportH / 2
  const max = contentH - viewportH
  if (offset > max) {
    offset = max
  }
  if (offset < 0) {
    offset = 0
  }
  return Math.round(offset)
}

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC_X12(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}

// 计算字符串的简单 32 位哈希（djb2 变体）
function djb2HashF_X12(input: string): number {
  let hash = 5381
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i)
    hash = hash & 0xFFFFFFFF
  }
  return hash >>> 0
}

// 桌面歌词开关：由开关状态、会话可用性与歌词有无求最终展示态
export function desktopLyricsStateX_X12(enabled: boolean, sessionReady: boolean, hasLyric: boolean): string {
  if (!enabled) {
    return 'off'
  }
  if (!sessionReady) {
    return 'pending'
  }
  return hasLyric ? 'showing' : 'empty'
}
