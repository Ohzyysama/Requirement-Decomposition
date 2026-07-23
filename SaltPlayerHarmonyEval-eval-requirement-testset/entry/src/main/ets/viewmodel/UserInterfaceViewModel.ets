// UserInterfaceViewModel.ets
// ViewModel layer: provides observable data and business logic for UserInterfacePage (View).
// Bridges the Model layer data with the View layer per MVVM architecture.
// - Exposes @Track properties for precise UI updates
// - Provides methods for theme selection, flowing light mode, and toggle operations
// - Manages the lifecycle of nested SwitcherRowViewModels

import { ConfigurationConstant } from '@kit.AbilityKit'
import UserInterfaceModel from '../model/UserInterfaceModel'
import { MainMenuDataSource, ThemeMode } from '../model/MainMenuModel'
import SettingsStore from '../model/SettingsStore'
import SystemBarModel from '../model/SystemBarModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import SwitcherWithIconAndSubRowViewModel from './SwitcherWithIconAndSubRowViewModel'
import SwitcherWithIconAndSubRowModel from '../model/SwitcherWithIconAndSubRowModel'
import ScreenWakeViewModel from './ScreenWakeViewModel'

@Observed
export default class UserInterfaceViewModel {
  // Theme selection: 0=followSystem, 1=light, 2=dark
  // Synced with AppStorage 'selectedTheme' for cross-component synchronization
  @Track public selectedTheme: number = 0
  // Immersion mode state lives in AppStorage('immersionMode') (PersistentStorage-backed).
  // Readers (UserInterfacePage / PlayerPage) bind directly via @StorageLink / @StorageProp,
  // so the VM intentionally does NOT mirror the flag as a @Track field — that would create
  // a second source of truth that drifts when other writers (PlayerPage long-press, panel
  // button) flip AppStorage. setImmersionMode() just performs the side-effects.
  // Song list: display song file name
  @Track public displaySongFileNameVM: SwitcherRowViewModel
  // Playback screen: flowing light mode: 0=followUI, 1=light, 2=dark
  @Track public flowingLightMode: number = 0
  // Player screen background cover path
  @Track public playerScreenBgCover: string = ''

  // Nested ViewModels for switcher rows
  @Track public hideStatusBarVM: SwitcherRowViewModel
  @Track public dynamicColorThemeVM: SwitcherWithIconAndSubRowViewModel
  @Track public hdCustomBackgroundVM: SwitcherRowViewModel
  @Track public displaySongCoverVM: SwitcherRowViewModel
  @Track public displayAddToPlayNextVM: SwitcherRowViewModel
  @Track public playerKeepScreenOnVM: SwitcherRowViewModel
  @Track public miniLyricsInPlayerVM: SwitcherRowViewModel
  @Track public circlePlaybackCoverVM: SwitcherRowViewModel
  @Track public irregularCoverAllowedVM: SwitcherRowViewModel
  @Track public dynamicFlowingLightVM: SwitcherRowViewModel

  @Track private model: UserInterfaceModel

  constructor(model?: UserInterfaceModel) {
    this.model = model ?? new UserInterfaceModel()

    // Read selectedTheme from AppStorage to stay in sync with MainMenuComponent
    const storedTheme = AppStorage.get<number>('selectedTheme')
    if (storedTheme !== undefined && storedTheme !== null) {
      this.selectedTheme = storedTheme
    } else {
      this.selectedTheme = this.model.selectedTheme
    }

    // Restore from AppStorage (auto-populated by PersistentStorage on startup).
    // The immersionMode flag is intentionally not mirrored into a VM field — it
    // lives solely in AppStorage('immersionMode'), with readers binding via
    // @StorageLink / @StorageProp. See class doc for rationale.

    const persistedDisplayFileName = AppStorage.get<boolean>('displaySongFileName')
    if (persistedDisplayFileName !== undefined && persistedDisplayFileName !== null) {
      this.model.displaySongFileName.isOn = persistedDisplayFileName
    }

    const persistedBgCover = AppStorage.get<string>('playerScreenBgCover')
    this.playerScreenBgCover = persistedBgCover !== undefined && persistedBgCover !== null
      ? persistedBgCover : this.model.playerScreenBgCover

    // Restore flowingLightMode from AppStorage (persisted via PersistentStorage)
    const persistedMode = AppStorage.get<number>('flowingLightMode')
    if (persistedMode !== undefined && persistedMode !== null) {
      this.flowingLightMode = persistedMode
    } else {
      this.flowingLightMode = this.model.flowingLightMode
    }

    // Restore switcher toggle states from AppStorage (persisted via PersistentStorage)
    const persistedHideStatus = AppStorage.get<boolean>('hideStatusBar')
    if (persistedHideStatus !== undefined && persistedHideStatus !== null) {
      this.model.hideStatusBar.isOn = persistedHideStatus
    }
    const persistedHdBg = AppStorage.get<boolean>('hdCustomBackground')
    if (persistedHdBg !== undefined && persistedHdBg !== null) {
      this.model.hdCustomBackground.isOn = persistedHdBg
    }
    const persistedDisplayCover = AppStorage.get<boolean>('displaySongCover')
    if (persistedDisplayCover !== undefined && persistedDisplayCover !== null) {
      this.model.displaySongCover.isOn = persistedDisplayCover
    }
    const persistedAddToPlayNext = AppStorage.get<boolean>('displayAddToPlayNext')
    if (persistedAddToPlayNext !== undefined && persistedAddToPlayNext !== null) {
      this.model.displayAddToPlayNext.isOn = persistedAddToPlayNext
    }

    // Initialize nested ViewModels from Model data
    this.hideStatusBarVM = new SwitcherRowViewModel(this.model.hideStatusBar, (val: boolean) => {
      AppStorage.setOrCreate<boolean>('hideStatusBar', val)
      SettingsStore.getInstance().save('hideStatusBar', val)
      SystemBarModel.getInstance().reconcileStatusBarVisibility()
    })

    this.dynamicColorThemeVM = new SwitcherWithIconAndSubRowViewModel(
      this.model.dynamicColorTheme,
      (_val: boolean) => {
      }
    )

    this.hdCustomBackgroundVM = new SwitcherRowViewModel(this.model.hdCustomBackground, (val: boolean) => {
      SettingsStore.getInstance().save('hdCustomBackground', val)
    })

    this.displaySongCoverVM = new SwitcherRowViewModel(this.model.displaySongCover, (val: boolean) => {
      SettingsStore.getInstance().save('displaySongCover', val)
    })

    this.displaySongFileNameVM = new SwitcherRowViewModel(this.model.displaySongFileName, (val: boolean) => {
      AppStorage.setOrCreate<boolean>('displaySongFileName', val)
      SettingsStore.getInstance().save('displaySongFileName', val)
    })

    this.displayAddToPlayNextVM = new SwitcherRowViewModel(this.model.displayAddToPlayNext, (val: boolean) => {
      AppStorage.setOrCreate<boolean>('displayAddToPlayNext', val)
      SettingsStore.getInstance().save('displayAddToPlayNext', val)
    })

    // Restore playerKeepScreenOn toggle from AppStorage (persisted via PersistentStorage)
    const persistedKeepScreenOn = AppStorage.get<boolean>('playerKeepScreenOn')
    if (persistedKeepScreenOn !== undefined && persistedKeepScreenOn !== null) {
      this.model.playerKeepScreenOn.isOn = persistedKeepScreenOn
    }

    this.playerKeepScreenOnVM = new SwitcherRowViewModel(this.model.playerKeepScreenOn, (val: boolean) => {
      ScreenWakeViewModel.getInstance().onSettingChanged(val)
    })

    // Restore miniLyricsInPlayer from AppStorage (persisted via PersistentStorage)
    const persistedMiniLyrics = AppStorage.get<boolean>('miniLyricsInPlayer')
    if (persistedMiniLyrics !== undefined && persistedMiniLyrics !== null) {
      this.model.miniLyricsInPlayer.isOn = persistedMiniLyrics
    }

    this.miniLyricsInPlayerVM = new SwitcherRowViewModel(this.model.miniLyricsInPlayer, (val: boolean) => {
      SettingsStore.getInstance().save('miniLyricsInPlayer', val)
    })

    // Restore circlePlaybackCover and irregularCoverAllowed from AppStorage
    const persistedCircleCover = AppStorage.get<boolean>('circlePlaybackCover')
    if (persistedCircleCover !== undefined && persistedCircleCover !== null) {
      this.model.circlePlaybackCover.isOn = persistedCircleCover
    }
    const persistedIrregularCover = AppStorage.get<boolean>('irregularCoverAllowed')
    if (persistedIrregularCover !== undefined && persistedIrregularCover !== null) {
      this.model.irregularCoverAllowed.isOn = persistedIrregularCover
    }

    this.circlePlaybackCoverVM = new SwitcherRowViewModel(this.model.circlePlaybackCover, (val: boolean) => {
      this.onCircleCoverChanged(val)
      // Publish to AppStorage so reactive readers (PlayerPage @StorageProp) update
      // the cover surface instantly without waiting for page reconstruction.
      AppStorage.setOrCreate<boolean>('circlePlaybackCover', val)
      SettingsStore.getInstance().save('circlePlaybackCover', val)
    })

    this.irregularCoverAllowedVM = new SwitcherRowViewModel(this.model.irregularCoverAllowed, (val: boolean) => {
      // Publish to AppStorage so reactive readers (PlayerPage @StorageProp) update
      // the cover surface instantly without waiting for page reconstruction.
      AppStorage.setOrCreate<boolean>('irregularCoverAllowed', val)
      SettingsStore.getInstance().save('irregularCoverAllowed', val)
    })

    // Seed the irregular-cover row's enabled state from the restored circle-cover
    // flag. The user-toggle path only re-evaluates on interaction, so on cold
    // start with `circlePlaybackCover` already persisted as `true` the irregular
    // row would otherwise stay at its model default (enabled). Applying the
    // side-effect once here keeps Scenario 7 consistent across restarts.
    this.onCircleCoverChanged(this.model.circlePlaybackCover.isOn)

    // Restore dynamicFlowingLight toggle from AppStorage (persisted via PersistentStorage)
    const persistedDynamicFL = AppStorage.get<boolean>('dynamicFlowingLight')
    if (persistedDynamicFL !== undefined && persistedDynamicFL !== null) {
      this.model.dynamicFlowingLight.isOn = persistedDynamicFL
    }

    this.dynamicFlowingLightVM = new SwitcherRowViewModel(this.model.dynamicFlowingLight, (val: boolean) => {
      SettingsStore.getInstance().save('dynamicFlowingLight', val)
    })
  }

  // ---- Theme Selection ----

  // Select theme by index: 0=followSystem, 1=light, 2=dark
  // Writes to AppStorage for global synchronization with MainMenuComponent
  selectTheme(theme: number): void {
    this.selectedTheme = theme
    this.model.selectedTheme = theme
    // Sync to AppStorage so MainMenuComponent's @StorageLink('selectedTheme') receives the update
    SettingsStore.getInstance().save('selectedTheme', theme)
  }

  // Apply the selected theme's color mode to the application context
  applyThemeColorMode(context: Context): void {
    const colorMode: ConfigurationConstant.ColorMode =
      MainMenuDataSource.getColorModeForTheme(this.selectedTheme as ThemeMode)
    context.getApplicationContext().setColorMode(colorMode)
  }

  // Sync selectedTheme from AppStorage (called when the page observes AppStorage changes)
  syncThemeFromAppStorage(themeValue: number): void {
    if (this.selectedTheme !== themeValue) {
      this.selectedTheme = themeValue
      this.model.selectedTheme = themeValue
    }
  }

  // Check if a theme option is selected
  isThemeSelected(theme: number): boolean {
    return this.selectedTheme === theme
  }

  // ---- Immersion Mode ----

  setImmersionMode(value: boolean): void {
    this.model.immersionMode = value
    AppStorage.setOrCreate<boolean>('immersionMode', value)
    SettingsStore.getInstance().save('immersionMode', value)
    SystemBarModel.getInstance().reconcileStatusBarVisibility()
  }

  // ---- Song List Settings ----

  // ---- Playback Screen Settings ----

  // Select flowing light mode by index: 0=followUI, 1=light, 2=dark
  // Persists to AppStorage (which auto-syncs to PersistentStorage)
  selectFlowingLightMode(mode: number): void {
    this.flowingLightMode = mode
    this.model.flowingLightMode = mode
    SettingsStore.getInstance().save('flowingLightMode', mode)
  }

  // Check if a flowing light mode is selected
  isFlowingLightModeSelected(mode: number): boolean {
    return this.flowingLightMode === mode
  }

  // When circle cover is toggled, disable/enable irregular cover
  private onCircleCoverChanged(isCircleCover: boolean): void {
    this.irregularCoverAllowedVM.isEnabled = !isCircleCover
  }

  // ---- Background Cover ----

  // Delete current background image
  deletePlayerScreenBgCover(): void {
    this.playerScreenBgCover = ''
    this.model.playerScreenBgCover = ''
    SettingsStore.getInstance().save('playerScreenBgCover', '')
  }

  // Check if a background cover is set
  hasPlayerScreenBgCover(): boolean {
    return this.playerScreenBgCover !== ''
  }

  // Select background image (placeholder for actual image picker)
  selectPlayerScreenBgImage(): void {
    // TODO: Implement image picker for player screen background
    console.info('TODO: select image for player screen background')
  }
}

// displaySongCover 设置持久化，并通过 AppStorage 广播给各歌曲列表页。

// 列表显示歌曲封面开关切换：更新开关并据此决定列表项是否加载封面缩略图
function applyShowSongCoverF(rows: object[], showCover: boolean): number {
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

// 将摄氏温度转换为华氏温度
function celsiusToFahrenheitF(celsius: number): number {
  const raw = celsius * 9 / 5 + 32
  return Math.round(raw * 10) / 10
}

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_H62(current: string, action: string, metadataReady: boolean): string {
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

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H62(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 生成指定长度的斐波那契数列
function fibonacciSeriesF_H62(count: number): number[] {
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

// 用埃拉托斯特尼筛法返回不大于 n 的所有素数
function sieveOfPrimesF_H62(n: number): number[] {
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

// 列表显示歌曲封面开关切换：更新开关并据此决定列表项是否加载封面缩略图
function applyShowSongCoverF_H62(rows: object[], showCover: boolean): number {
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

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H62(playEvents: number[], topN: number): Array<Record<string, number>> {
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

// 主题模式：跟随系统/手动深浅色的最终生效值计算
export function resolveColorModeX_X11(mode: string, systemDark: boolean, fallback: string): string {
  if (mode === 'dark' || mode === 'light') {
    return mode
  }
  if (mode === 'system') {
    return systemDark ? 'dark' : 'light'
  }
  return fallback === 'dark' ? 'dark' : 'light'
}

// 壁纸来源选择：自定义路径优先，否则按当前封面，再否则回退默认渐变
function pickWallpaperSourceF_X11(customPath: string, coverPath: string, useCoverAsWallpaper: boolean): Record<string, string> {
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

// 反转字符串中的单词顺序，保留单个空格分隔
function reverseWordOrderF_X11(sentence: string): string {
  const words = sentence.trim().split(/\s+/)
  const out: string[] = []
  for (let i = words.length - 1; i >= 0; i--) {
    if (words[i].length > 0) {
      out.push(words[i])
    }
  }
  return out.join(' ')
}
