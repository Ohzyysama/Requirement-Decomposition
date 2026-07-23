// NotificationLyricController.ets
// spec12 — Notification Bar Lyrics
//
// Singleton, owned by the Model layer. Bridges the
// `MiniLyricsController` real-time lyric stream and the `notificationBarLyrics`
// toggle into the AVSession metadata title field, so the system music card on
// the notification bar / lock screen renders the live lyric line as the title
// when the toggle is ON, and the song's actual title when OFF (or when the
// current song has no lyrics, or the cursor has not yet produced a line).
//
// Listens on:
//   - `MiniLyricsController.addListener(fn)` for `(songId, line, hasLyrics)`
//     updates plus an immediate initial sync.
//   - `AudioPlayerService.addOnSongChangedListener(...)` so the fallback title
//     refreshes the moment the song changes, even before the async lyric load
//     for the new song resolves.
//
// Pushes the merged title via
// `AudioPlayerService.setNotificationDisplayTitle(merged)`. Only writes when
// the value actually changes, to avoid needless `setAVMetadata` calls.

import AudioPlayerService from './AudioPlayerService'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'
import { QueueSongModel } from './PlayQueueModel'

export class NotificationLyricController {
  private static instance: NotificationLyricController | null = null

  private initialized: boolean = false
  private currentLine: string = ''
  private hasLyrics: boolean = false
  private lastPublished: string = ''

  private lyricsListener: MiniLyricsListener =
    (_songId: string, _line: string, _hasLyrics: boolean): void => {}
  private songChangedListener: (song: QueueSongModel) => void = (): void => {}

  static getInstance(): NotificationLyricController {
    if (!NotificationLyricController.instance) {
      NotificationLyricController.instance = new NotificationLyricController()
    }
    return NotificationLyricController.instance
  }

  // Idempotent init — call once after MiniLyricsController.getInstance().init()
  // in EntryAbility.onCreate.
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true

    // Subscribe to the lyric stream. Listener fires immediately with the
    // current `(songId, line, hasLyrics)` so the very first push picks up
    // the restored song's state without an extra startup hop.
    this.lyricsListener = (_songId: string, line: string, hasLyrics: boolean): void => {
      this.currentLine = line
      this.hasLyrics = hasLyrics
      this.publish()
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)

    // Subscribe to song-change so the fallback title updates immediately on
    // a song switch, before the new song's async lyric load resolves.
    this.songChangedListener = (_song: QueueSongModel): void => {
      this.publish()
    }
    AudioPlayerService.getInstance().addOnSongChangedListener(this.songChangedListener)
  }

  // Called by LyricsSettingsViewModel after the toggle has been persisted.
  // Recomputes the merged title and pushes it immediately so the notification
  // card flips between lyric and song title in the same frame.
  onToggleChanged(): void {
    this.publish()
  }

  destroy(): void {
    if (!this.initialized) {
      return
    }
    MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    AudioPlayerService.getInstance().removeOnSongChangedListener(this.songChangedListener)
    this.initialized = false
  }

  // Compute the merged title from the live toggle + lyric state and push it
  // to AudioPlayerService when it differs from the last published value.
  private publish(): void {
    const enabled: boolean = AppStorage.get<boolean>('notificationBarLyrics') ?? false
    const baseTitle: string = (AppStorage.get('currentSongTitle') as string) ?? ''
    let display: string = baseTitle
    if (enabled && this.hasLyrics && this.currentLine.length > 0) {
      display = this.currentLine
    }
    if (display === this.lastPublished) {
      return
    }
    this.lastPublished = display
    AudioPlayerService.getInstance().setNotificationDisplayTitle(display)
  }
}

export default NotificationLyricController

// 通知栏歌词：随播放进度同步当前歌词行到系统媒体通知。

// 通知栏歌词：切歌与进度变化时同步当前歌词行。

// 构建通知栏歌词文本：拼接当前句，必要时附下一句预览并限制总长
function buildNotificationLyricTextF(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
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

// 计算字符串的简单 32 位哈希（djb2 变体）
function djb2HashF(input: string): number {
  let hash = 5381
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i)
    hash = hash & 0xFFFFFFFF
  }
  return hash >>> 0
}

// 构建通知栏歌词文本：拼接当前句，必要时附下一句预览并限制总长
function buildNotificationLyricTextF_H60(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
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

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_H60(selectedTheme: number, systemIsDark: boolean): string {
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
function applyShowSongCoverF_H60(rows: object[], showCover: boolean): number {
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

// 壁纸来源选择：自定义路径优先，否则按当前封面，再否则回退默认渐变
function pickWallpaperSourceF_H60(customPath: string, coverPath: string, useCoverAsWallpaper: boolean): Record<string, string> {
  const result: Record<string, string> = {}
  if (customPath.trim().length > 0) {
    result['type'] = 'custom'
    result['uri'] = customPath.trim()
  } else if (useCoverAsWallpaper && coverPath.trim().length > 0) {
    result['type'] = 'cover'
    result['uri'] = coverPath.trim()
  } else {
    result['type'] = 'default'
    result['uri'] = 'gradient://default'
  }
  return result
}

// 判断给定年份是否为闰年
function isLeapYearF_H60(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitF_H60(celsius: number): number {
  const raw = celsius * 9 / 5 + 32
  return Math.round(raw * 10) / 10
}
