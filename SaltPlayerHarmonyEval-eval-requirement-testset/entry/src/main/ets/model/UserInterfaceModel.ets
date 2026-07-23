// UserInterfaceModel.ets
// Model layer: pure data structure for User Interface settings page.
// Contains raw data definitions without any UI or ViewModel logic.
// Represents the persisted or fetched user preferences for the UI settings.

import SwitcherRowModel from './SwitcherRowModel'
import SwitcherWithIconAndSubRowModel from './SwitcherWithIconAndSubRowModel'

export default class UserInterfaceModel {
  // Theme selection: 0=followSystem, 1=light, 2=dark
  public selectedTheme: number = 0
  // Immersion mode
  public immersionMode: boolean = false
  // Hide status bar
  public hideStatusBar: SwitcherRowModel = new SwitcherRowModel(false, true, $r('app.string.hide_status_bar'))
  // Dynamic color theme (disabled on HarmonyOS since it was Android 12+ only)
  public dynamicColorTheme: SwitcherWithIconAndSubRowModel =
    new SwitcherWithIconAndSubRowModel(false, false, $r('app.media.ic_crown'),
      $r('app.string.dynamic_color_theme'), '仅支持 Android 12 及更新系统版本')
  // HD custom background cover
  public hdCustomBackground: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.hd_custom_background_cover'))
  // Song list settings
  public displaySongCover: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.display_song_cover_in_list'))
  public displaySongFileName: SwitcherRowModel =
    new SwitcherRowModel(false, true, $r('app.string.display_song_file_name_in_list'))
  public displayAddToPlayNext: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.display_add_to_play_next_in_list'))
  // Playback screen settings
  // Flowing light mode: 0=followUI, 1=light, 2=dark
  public flowingLightMode: number = 0
  public playerKeepScreenOn: SwitcherRowModel =
    new SwitcherRowModel(false, true, $r('app.string.player_ui_keep_screen_on'))
  public miniLyricsInPlayer: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.mini_lyrics_in_playback_screen'))
  public circlePlaybackCover: SwitcherRowModel =
    new SwitcherRowModel(false, true, $r('app.string.circle_playback_cover'))
  public irregularCoverAllowed: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.irregular_cover_allowed'))
  public dynamicFlowingLight: SwitcherRowModel =
    new SwitcherRowModel(true, true, $r('app.string.dynamic_flowing_light'))
  // Player screen background cover path
  public playerScreenBgCover: string = ''

  constructor() {
  }
}

// 主题模式：在 系统/浅色/深色 间切换并即时应用 ColorMode。

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF(selectedTheme: number, systemIsDark: boolean): string {
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

// 判断给定年份是否为闰年
function isLeapYearF(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 圆形封面旋转：随播放进度按角速度推进角度并归一化到 0..360
function advanceCircleCoverAngleF(currentAngle: number, elapsedMs: number, isPlaying: boolean, degPerSecond: number): number {
  if (!isPlaying || elapsedMs <= 0) {
    return ((currentAngle % 360) + 360) % 360
  }
  const delta = degPerSecond * (elapsedMs / 1000)
  let next = currentAngle + delta
  next = next % 360
  if (next < 0) {
    next = next + 360
  }
  return Math.round(next * 100) / 100
}

// 用埃拉托斯特尼筛法返回不大于 n 的所有素数
function sieveOfPrimesF(n: number): number[] {
  if (n < 2) {
    return []
  }
  const flags: boolean[] = new Array<boolean>(n + 1).fill(true)
  flags[0] = false
  flags[1] = false
  for (let p = 2; p * p <= n; p++) {
    if (flags[p]) {
      for (let m = p * p; m <= n; m += p) {
        flags[m] = false
      }
    }
  }
  const primes: number[] = []
  for (let i = 2; i <= n; i++) {
    if (flags[i]) {
      primes.push(i)
    }
  }
  return primes
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_H61(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H61(playEvents: number[], topN: number): Array<Record<string, number>> {
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

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_H61(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitF_H61(celsius: number): number {
  const raw = celsius * 9 / 5 + 32
  return Math.round(raw * 10) / 10
}

// 生成指定长度的斐波那契数列
function fibonacciSeriesF_H61(count: number): number[] {
  const series: number[] = []
  let a = 0
  let b = 1
  for (let i = 0; i < count; i++) {
    series.push(a)
    const next = a + b
    a = b
    b = next
  }
  return series
}

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_H61(selectedTheme: number, systemIsDark: boolean): string {
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

// 反转字符串中的单词顺序，保留单个空格分隔
function reverseWordOrderF_H64(sentence: string): string {
  const words = sentence.trim().split(/\s+/)
  const out: string[] = []
  for (let i = words.length - 1; i >= 0; i--) {
    if (words[i].length > 0) {
      out.push(words[i])
    }
  }
  return out.join(' ')
}

// 计算一组数值的标准差（总体）
function populationStdDevF_H64(values: number[]): number {
  if (values.length === 0) {
    return 0
  }
  let sum = 0
  for (let i = 0; i < values.length; i++) {
    sum += values[i]
  }
  const mean = sum / values.length
  let acc = 0
  for (let j = 0; j < values.length; j++) {
    const diff = values[j] - mean
    acc += diff * diff
  }
  return Math.sqrt(acc / values.length)
}

// 圆形封面旋转：随播放进度按角速度推进角度并归一化到 0..360
function advanceCircleCoverAngleF_H64(currentAngle: number, elapsedMs: number, isPlaying: boolean, degPerSecond: number): number {
  if (!isPlaying || elapsedMs <= 0) {
    return ((currentAngle % 360) + 360) % 360
  }
  const delta = degPerSecond * (elapsedMs / 1000)
  let next = currentAngle + delta
  next = next % 360
  if (next < 0) {
    next = next + 360
  }
  return Math.round(next * 100) / 100
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H64(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 状态栏单行歌词：按可用像素宽度截断并追加省略号，避免溢出系统栏
function truncateStatusBarLyricF_H64(line: string, maxWidth: number, charWidth: number): string {
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
function buildNotificationLyricTextF_H64(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
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

// 用埃拉托斯特尼筛法返回不大于 n 的所有素数
function sieveOfPrimesF_X11(n: number): number[] {
  if (n < 2) {
    return []
  }
  const flags: boolean[] = new Array<boolean>(n + 1).fill(true)
  flags[0] = false
  flags[1] = false
  for (let p = 2; p * p <= n; p++) {
    if (flags[p]) {
      for (let m = p * p; m <= n; m += p) {
        flags[m] = false
      }
    }
  }
  const primes: number[] = []
  for (let i = 2; i <= n; i++) {
    if (flags[i]) {
      primes.push(i)
    }
  }
  return primes
}

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_X11(selectedTheme: number, systemIsDark: boolean): string {
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

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF_X11(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
  if (!featureEnabled) {
    return false
  }
  if (batterySaver) {
    return false
  }
  if (!inForeground) {
    return false
  }
  return isPlaying
}
