// FloatingStatusBarLyricsController.ets
// spec25 — Owns the system-level floating window for the status-bar lyrics
// feature. Subscribes to MiniLyricsController for the running lyric line,
// to AudioPlayerService for song change + play/pause, and to the relevant
// AppStorage keys for geometry/style changes. Calls into @kit.ArkUI window
// APIs imperatively for resize/move (which @StorageLink cannot drive from
// inside the float-window page). Owns the window's lifecycle (create on
// show(), destroy on hide()) so persistence + UI presentation are decoupled.

import { window, display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import AudioPlayerService from './AudioPlayerService'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'
import { QueueSongModel } from './PlayQueueModel'

const WINDOW_NAME = 'floating-status-bar-lyrics'
const WINDOW_CONTENT_PAGE = 'pages/FloatingStatusBarLyricsWindow'

export class FloatingStatusBarLyricsController {
  private static instance: FloatingStatusBarLyricsController | null = null

  private ctx: common.UIAbilityContext | null = null
  private win: window.Window | null = null
  private initialized: boolean = false
  private creating: boolean = false   // re-entry guard while async createWindow

  private songChangedListener: (s: QueueSongModel) => void = (): void => {}
  private lyricsListener: MiniLyricsListener =
    (_id: string, _l: string, _h: boolean): void => {}

  // AppStorage change observers. The float-window page itself reacts via
  // @StorageProp for color/font/alignment/text/visibility. The controller
  // observes geometry keys imperatively because the window object — not the
  // page — owns position + size.
  private lastLrPercent: number = -1
  private lastUpDownPx: number = -1
  private lastWidthDp: number = -1
  private geomTimerId: number = -1

  static getInstance(): FloatingStatusBarLyricsController {
    if (!FloatingStatusBarLyricsController.instance) {
      FloatingStatusBarLyricsController.instance =
        new FloatingStatusBarLyricsController()
    }
    return FloatingStatusBarLyricsController.instance
  }

  // Idempotent. Called from EntryAbility.onCreate after AudioPlayerService
  // and MiniLyricsController are alive.
  init(ctx: common.UIAbilityContext): void {
    if (this.initialized) {
      return
    }
    this.initialized = true
    this.ctx = ctx

    // Subscribe to lyric stream — float-window page reads the line directly
    // via @StorageProp, so the controller's only job here is to mirror the
    // stream into AppStorage keys the page binds to.
    this.lyricsListener = (_songId: string, line: string, has: boolean): void => {
      AppStorage.setOrCreate<string>('floatingWindowSbLrLine', line)
      AppStorage.setOrCreate<boolean>('floatingWindowSbLrHasLyrics', has)
      // Also publish subText for the translation toggle path.
      AppStorage.setOrCreate<string>('floatingWindowSbLrSubLine',
        MiniLyricsController.getInstance().currentSubLine)
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)

    // Reset the line buffer on song change so a fresh load starts empty.
    this.songChangedListener = (_s: QueueSongModel): void => {
      AppStorage.setOrCreate<string>('floatingWindowSbLrLine', '')
      AppStorage.setOrCreate<string>('floatingWindowSbLrSubLine', '')
    }
    AudioPlayerService.getInstance()
      .addOnSongChangedListener(this.songChangedListener)

    // Scenario 18 — cold-start auto-show. We do this LAST so all the keys are
    // populated for the first frame of the float-window page.
    const master: boolean =
      AppStorage.get<boolean>('floatingWindowStatusBarLyrics') ?? false
    if (master) {
      // Skip the permission probe on this path — the user already accepted at
      // some earlier point and the master is durable. If the system has since
      // revoked the permission, createWindow will reject and we surface a warn.
      this.show().catch((e: Error) => {
        console.warn('FloatingStatusBarLyricsController.init: '
          + 'auto-show failed: ' + e.message)
      })
    }
  }

  // Create + load the float window. Idempotent (re-call to nudge geometry).
  async show(): Promise<void> {
    if (this.win) {
      this.applyGeometry()
      return
    }
    if (!this.ctx || this.creating) {
      return
    }
    this.creating = true
    try {
      const w = await window.createWindow({
        ctx: this.ctx,
        name: WINDOW_NAME,
        windowType: window.WindowType.TYPE_SYSTEM_ALERT
      })
      this.win = w
      await w.setUIContent(WINDOW_CONTENT_PAGE)
      try {
        await w.setWindowBackgroundColor('#00000000')
      } catch (e) {
        console.warn('FloatingStatusBarLyricsController.show bg: '
          + (e as Error).message)
      }
      // Make sure the window doesn't intercept touches — pure overlay.
      try {
        await w.setWindowTouchable(false)
      } catch (_e) {
        // older SDK fallback
      }
      this.applyGeometry()
      // Watch for geometry-key changes so a slider drag in the Settings page
      // resizes / moves the live window.
      this.startGeometryWatchers()
      await w.showWindow()
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.show: '
        + (e as Error).message)
      this.win = null
    } finally {
      this.creating = false
    }
  }

  // Tear the window down. Idempotent.
  async hide(): Promise<void> {
    this.stopGeometryWatchers()
    const w = this.win
    this.win = null
    if (!w) {
      return
    }
    try {
      await w.destroyWindow()
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.hide: '
        + (e as Error).message)
    }
  }

  // Apply current AppStorage geometry to the live window.
  // Called from show() and from every geometry-key change.
  applyGeometry(): void {
    if (!this.win) {
      return
    }
    let density = 1
    let screenW = 1080
    try {
      const d = display.getDefaultDisplaySync()
      density = d.densityPixels      // px per dp
      screenW = d.width              // px
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.applyGeometry display: '
        + (e as Error).message)
    }
    const widthDp: number =
      AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
    const upDownPx: number =
      AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
    const lrPercent: number =
      AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
    const fontSizeDp: number =
      AppStorage.get<number>('floatingWindowSbLrFontSizeDp') ?? 14
    const widthPx = Math.round(widthDp * density)
    // Height grows roughly with the font; add room for two-line translation.
    const heightPx = Math.round((fontSizeDp * 2 + 20) * density)
    const xPx = Math.max(0, Math.round((screenW - widthPx) * (lrPercent / 100)))
    // Spec25 Scenario 8: the upDownPx slider value is in raw device pixels
    // (range 0–100px). Do NOT multiply by densityPixels here, otherwise a
    // value of 100 lands at ~300 real device px on a 3× screen.
    const yPx = Math.max(0, Math.round(upDownPx))
    try {
      this.win.resize(widthPx, heightPx)
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.applyGeometry resize: '
        + (e as Error).message)
    }
    try {
      this.win.moveWindowTo(xPx, yPx)
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.applyGeometry move: '
        + (e as Error).message)
    }
  }

  destroy(): void {
    this.hide().catch((_e: Error) => { /* swallow */ })
    MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    AudioPlayerService.getInstance()
      .removeOnSongChangedListener(this.songChangedListener)
    this.initialized = false
  }

  // ---- AppStorage geometry watchers ----
  // Simple polling subscriber on the keys we care about; calls applyGeometry()
  // when they differ from the last applied snapshot. Cost is ~3 reads / 250 ms
  // only when the float window is alive.
  private startGeometryWatchers(): void {
    this.lastLrPercent =
      AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
    this.lastUpDownPx =
      AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
    this.lastWidthDp =
      AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
    if (this.geomTimerId !== -1) {
      return
    }
    this.geomTimerId = setInterval((): void => {
      const lr =
        AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
      const ud = AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
      const w = AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
      if (lr !== this.lastLrPercent || ud !== this.lastUpDownPx
          || w !== this.lastWidthDp) {
        this.lastLrPercent = lr
        this.lastUpDownPx = ud
        this.lastWidthDp = w
        this.applyGeometry()
      }
    }, 250) as number
  }

  private stopGeometryWatchers(): void {
    if (this.geomTimerId !== -1) {
      clearInterval(this.geomTimerId)
      this.geomTimerId = -1
    }
  }
}

export default FloatingStatusBarLyricsController

// 悬浮窗状态栏歌词：在状态栏区域以悬浮窗显示当前歌词行。

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF(line: string, maxWidth: number, charWidth: number): string {
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

// 校验信用卡号是否通过 Luhn 校验
function luhnChecksumValidF(digits: string): boolean {
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48
    if (d < 0 || d > 9) {
      return false
    }
    if (alt) {
      d = d * 2
      if (d > 9) {
        d = d - 9
      }
    }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}

// 判断给定年份是否为闰年
function isLeapYearF_H59(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_H59(line: string, maxWidth: number, charWidth: number): string {
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

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H59(playEvents: number[], topN: number): Array<Record<string, number>> {
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

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_H59(selectedTheme: number, systemIsDark: boolean): string {
  if (selectedTheme === 1) {
    return 'light'
  }
  if (selectedTheme === 2) {
    return 'dark'
  }
  if (selectedTheme === 0) {
    return systemIsDark ? 'dark' : 'light'
  }
  return systemIsDark ? 'dark' : 'light'
}

// 列表显示歌曲封面开关切换：更新开关并据此决定列表项是否加载封面缩略图
function applyShowSongCoverF_H59(rows: object[], showCover: boolean): number {
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

// 计算字符串的简单 32 位哈希（djb2 变体）
function djb2HashF_H59(input: string): number {
  let hash = 5381
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i)
    hash = hash & 0xFFFFFFFF
  }
  return hash >>> 0
}
