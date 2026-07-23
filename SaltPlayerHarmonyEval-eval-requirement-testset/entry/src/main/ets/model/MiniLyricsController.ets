// MiniLyricsController.ets
// Singleton controller that feeds the currently playing lyric line to the
// mini player bar. Mirrors the CurrentSongCoverController listener pattern
// so the mini bar stays in sync regardless of which page is on top and
// keeps ticking when the PlayerPage overlay is closed.
//
// Responsibilities:
//   - Load lyrics on song change (via AudioPlayerService.addOnSongChangedListener)
//   - Keep a 200ms progress tick that reads AudioPlayerService.getCurrentTimeMs()
//     and advances the LyricsViewModel cursor (paused → anchor frozen → cursor
//     frozen → subtitle frozen; resume picks up automatically).
//   - Publish (songId, lyricLine, hasLyrics) to all subscribed listeners.
//
// The "has lyrics" flag is true only when the parsed LyricsDocument contains
// timestamped lines (isScrollable && lines.length > 0). Static-only lyrics
// (no timestamps) do not feed the mini bar — the artist fallback is used
// instead, matching the spec intent "show real-time lyrics or fall back".

import { QueueSongModel } from './PlayQueueModel'
import AudioPlayerService from './AudioPlayerService'
import LyricsViewModel from '../viewmodel/LyricsViewModel'
import { LrcParser } from './LyricsModel'

export type MiniLyricsListener = (songId: string, line: string, hasLyrics: boolean) => void

export class MiniLyricsController {
  private static instance: MiniLyricsController | null = null

  private lyricsViewModel: LyricsViewModel = new LyricsViewModel()
  private timerId: number = -1
  private listeners: MiniLyricsListener[] = []

  private currentSongId: string = ''
  private currentLine: string = ''
  private _currentSubLine: string = ''
  private hasLyrics: boolean = false

  // spec25 — Floating status-bar lyrics window reads the per-line translation
  // when 不显示翻译 toggle is OFF. Exposed via accessor rather than widening
  // the MiniLyricsListener signature so existing subscribers stay unchanged.
  public get currentSubLine(): string {
    return this._currentSubLine
  }

  // Cleaned line-level LRC for the currently playing song, consumed by
  // DesktopLyricsAVSessionController to drive AVMetadata.lyric. Built from
  // the parsed document so inline word-level (karaoke) timestamps are
  // stripped — the system overlay renders raw <mm:ss.xx> tags literally,
  // whereas this matches what the in-app playback page shows. Returns an
  // empty string when the song has no lyrics or before the load resolves.
  public getCurrentDisplayLrc(): string {
    return LrcParser.toPlainLrc(this.lyricsViewModel.document)
  }

  private songChangedListener: (song: QueueSongModel) => void = (): void => {}
  private initialized: boolean = false

  static getInstance(): MiniLyricsController {
    if (!MiniLyricsController.instance) {
      MiniLyricsController.instance = new MiniLyricsController()
    }
    return MiniLyricsController.instance
  }

  // Idempotent init — call once after AudioPlayerService.restoreFromPersisted
  // has run in EntryAbility.onCreate.
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true

    // Register listener on the multi-listener song-change bus.
    this.songChangedListener = (song: QueueSongModel): void => {
      this.onSongChanged(song)
    }
    AudioPlayerService.getInstance().addOnSongChangedListener(this.songChangedListener)

    // Load lyrics for the currently-restored song (app-restart path).
    const service = AudioPlayerService.getInstance()
    const fileUri = service.getCurrentFileUri()
    const songId = (AppStorage.get('currentSongId') as string) ?? ''
    if (fileUri.length > 0 && songId.length > 0) {
      this.currentSongId = songId
      // Fire-and-forget — when it resolves, the next tick picks up the cursor.
      this.lyricsViewModel.loadLyrics(fileUri, songId).then((): void => {
        this.tickOnce()
      }).catch((): void => {
        // Already logged inside LyricsViewModel; publish empty state.
        this.hasLyrics = false
        this.currentLine = ''
        this.notify()
      })
    }

    // Start the 200ms tick. Always-on: paused state is naturally handled by
    // AudioPlayerService.getCurrentTimeMs() freezing its anchor, so the cursor
    // freezes too. Tick cost is negligible (binary search + index compare).
    if (this.timerId === -1) {
      this.timerId = setInterval((): void => {
        this.tickOnce()
      }, 200) as number
    }
  }

  destroy(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
    AudioPlayerService.getInstance().removeOnSongChangedListener(this.songChangedListener)
    this.lyricsViewModel.destroy()
    this.initialized = false
  }

  // Register a listener. Called immediately with the current state so new
  // subscribers don't need a separate "initial sync" step — matches
  // CurrentSongCoverController.addListener behavior.
  addListener(fn: MiniLyricsListener): void {
    if (this.listeners.indexOf(fn) < 0) {
      this.listeners.push(fn)
    }
    fn(this.currentSongId, this.currentLine, this.hasLyrics)
  }

  removeListener(fn: MiniLyricsListener): void {
    const idx = this.listeners.indexOf(fn)
    if (idx >= 0) {
      this.listeners.splice(idx, 1)
    }
  }

  // Drop any lyric state and notify subscribers. Used when playback fully stops
  // (e.g. the currently playing song is removed from the library and the queue
  // becomes empty) — there is no song-changed event in that path, so without
  // this call the miniplayer subtitle keeps showing the previous song's lyric.
  // loadLyrics('', '') resets the underlying LyricsViewModel document and bumps
  // its loadId so any in-flight load for the removed song is discarded.
  clear(): void {
    this.currentSongId = ''
    this.currentLine = ''
    this._currentSubLine = ''
    this.hasLyrics = false
    this.lyricsViewModel.loadLyrics('', '').catch((): void => {})
    this.notify()
  }

  private notify(): void {
    const id = this.currentSongId
    const line = this.currentLine
    const has = this.hasLyrics
    for (const listener of this.listeners) {
      listener(id, line, has)
    }
  }

  private onSongChanged(song: QueueSongModel): void {
    this.currentSongId = song.id
    // Clear previous line immediately so the mini bar doesn't show the old
    // song's lyric during the async load window. LyricsViewModel.loadLyrics
    // already clears its document at entry; we mirror that on our publish
    // channel so subscribers fall back to artist during the gap.
    this.currentLine = ''
    this._currentSubLine = ''
    this.hasLyrics = false
    this.notify()

    this.lyricsViewModel.loadLyrics(song.fileUri, song.id).then((): void => {
      // Force a cursor evaluation against the current play position so the
      // first line appears without waiting for the next 200ms tick.
      this.tickOnce()
    }).catch((): void => {
      this.hasLyrics = false
      this.currentLine = ''
      this.notify()
    })
  }

  private tickOnce(): void {
    const timeMs = AudioPlayerService.getInstance().getCurrentTimeMs()
    this.lyricsViewModel.updateProgress(timeMs)

    const doc = this.lyricsViewModel.document
    const idx = this.lyricsViewModel.currentLineIndex
    const newHasLyrics = doc.isScrollable && doc.lines.length > 0
    let newLine = ''
    if (newHasLyrics && idx >= 0 && idx < doc.lines.length) {
      newLine = doc.lines[idx].mainText
      // spec25 — capture the per-line translation (subText) so the floating
      // status-bar lyrics window can render it when the user has translation
      // enabled. Kept in lockstep with currentLine; cleared when the line is.
      this._currentSubLine = doc.lines[idx].subText
    } else {
      this._currentSubLine = ''
    }

    if (newLine !== this.currentLine || newHasLyrics !== this.hasLyrics) {
      this.currentLine = newLine
      this.hasLyrics = newHasLyrics
      this.notify()
    }
  }
}

export default MiniLyricsController

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}

对字符串数组去重并保持首次出现顺序
function dedupeKeepOrderC(items: string[]): string[] {
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

// 歌曲信息详情展示：将原始元数据整理为字段-值的详情条目列表
export function buildSongInfoRowsB_H25(meta: Record<string, string>): Record<string, string>[] {
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
function buildAlbumSubtitleC_H25(artist: string, year: number, trackCount: number): string {
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

取专辑名首字母归类到 A-Z 或 # 索引分组键
function albumIndexKeyC_H25(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) return '#';
  const first = trimmed.charAt(0).toUpperCase();
  const code = first.charCodeAt(0);
  if (code >= 65 && code <= 90) {
    return first;
  }
  return '#';
}

计算两个整数的最大公约数
function greatestCommonDivisorC_H25(a: number, b: number): number {
  let x = Math.abs(Math.trunc(a));
  let y = Math.abs(Math.trunc(b));
  while (y !== 0) {
    const t = y;
    y = x % y;
    x = t;
  }
  return x;
}

判断字符串是否为回文（忽略大小写与空白）
function isPalindromeC_H25(text: string): boolean {
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

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC_H25(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}
