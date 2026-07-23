// SystemBarModel.ets
// Model layer: edge-to-edge (immersive) window setup and system bar control.
//
// Mirrors Android's enableEdgeToEdge() + WindowInsets pattern:
//   - Content extends under both status bar and navigation bar
//   - Both system bars are fully transparent
//   - Status/nav bar icon colors adapt to light/dark theme or player flowing light
//   - statusBarHeight / navBarHeight are stored in AppStorage for components
//     to apply as top/bottom padding (equivalent to Android WindowInsets padding)
// Singleton — initialized once with the main window from EntryAbility.

import { window, display } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

const TAG: string = 'SystemBarModel'

export default class SystemBarModel {
  private static instance: SystemBarModel | undefined = undefined
  private mainWindow: window.Window | undefined = undefined

  private constructor() {
  }

  static getInstance(): SystemBarModel {
    if (!SystemBarModel.instance) {
      SystemBarModel.instance = new SystemBarModel()
    }
    return SystemBarModel.instance
  }

  // Initialize with the main window reference and enable edge-to-edge layout.
  // Must be called after windowStage.loadContent so the window is available.
  initWindow(mainWindow: window.Window): void {
    this.mainWindow = mainWindow

    try {
      // Enable full-screen layout — content extends under status bar and nav bar
      mainWindow.setWindowLayoutFullScreen(true)
      hilog.info(0, TAG, 'setWindowLayoutFullScreen(true) succeeded')
    } catch (e) {
      hilog.warn(0, TAG, 'setWindowLayoutFullScreen failed: %{public}s', (e as Error).message)
    }

    // Calculate and publish safe area inset heights (in vp) so UI components
    // can apply padding — equivalent to Android's WindowInsets.
    this.publishInsetHeights(mainWindow)

    // Set both system bars transparent with theme-appropriate content colors
    const isSystemDark: boolean = (AppStorage.get('isSystemDark') as boolean) ?? false
    this.applyBarColors(isSystemDark)
  }

  // Read system bar avoid areas and publish heights (in vp) to AppStorage.
  private publishInsetHeights(win: window.Window): void {
    try {
      // px → vp conversion factor
      const density = display.getDefaultDisplaySync().densityPixels

      // Status bar height (top)
      const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
      const statusBarHeightVp = systemArea.topRect.height / density

      // Navigation indicator height (bottom gesture bar / nav bar)
      const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
      const navBarHeightVp = Math.max(navArea.bottomRect.height / density, 28)

      AppStorage.setOrCreate<number>('statusBarHeight', statusBarHeightVp)
      AppStorage.setOrCreate<number>('navBarHeight', navBarHeightVp)

      hilog.info(0, TAG, 'Insets: statusBar=%{public}fvp navBar=%{public}fvp density=%{public}f',
        statusBarHeightVp, navBarHeightVp, density)
    } catch (e) {
      hilog.warn(0, TAG, 'publishInsetHeights failed: %{public}s', (e as Error).message)
      AppStorage.setOrCreate<number>('statusBarHeight', 0)
      AppStorage.setOrCreate<number>('navBarHeight', 28)
    }
  }

  setStatusBarVisible(visible: boolean): void {
    if (!this.mainWindow) return
    try {
      this.mainWindow.setSpecificSystemBarEnabled('status', visible)
      hilog.info(0, TAG, 'setStatusBarVisible: %{public}s', visible.toString())
    } catch (e) {
      hilog.warn(0, TAG, 'setStatusBarVisible failed: %{public}s', (e as Error).message)
    }
  }

  // Reconcile the status bar's visibility from the two persisted flags that
  // can request a hidden status bar: 'immersionMode' (player immersive scene)
  // and 'hideStatusBar' (user-level setting). The status bar is hidden iff
  // either flag is true. Any code path that flips either flag should call
  // this afterwards instead of reaching for setStatusBarVisible directly.
  reconcileStatusBarVisibility(): void {
    if (!this.mainWindow) return
    const immersion: boolean = (AppStorage.get<boolean>('immersionMode') ?? false)
    const hide: boolean = (AppStorage.get<boolean>('hideStatusBar') ?? false)
    const shouldHide: boolean = immersion || hide
    try {
      this.mainWindow.setSpecificSystemBarEnabled('status', !shouldHide)
      hilog.info(0, TAG, 'reconcile: immersion=%{public}s hide=%{public}s visible=%{public}s',
        immersion.toString(), hide.toString(), (!shouldHide).toString())
    } catch (e) {
      hilog.warn(0, TAG, 'reconcile failed: %{public}s', (e as Error).message)
    }
  }

  // Set system bar content colors for the player page.
  setStatusBarContentColor(isLight: boolean): void {
    if (!this.mainWindow) return
    try {
      const contentColor = isLight ? '#ff000000' : '#ffffffff'
      const barProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: contentColor
      }
      this.mainWindow.setWindowSystemBarProperties(barProps)
    } catch (e) {
      hilog.warn(0, TAG, 'setStatusBarContentColor failed: %{public}s', (e as Error).message)
    }
  }

  // Restore system bar content colors to match the app's current theme.
  restoreToAppTheme(): void {
    if (!this.mainWindow) return
    const isSystemDark: boolean = (AppStorage.get('isSystemDark') as boolean) ?? false
    this.applyBarColors(isSystemDark)
  }

  private applyBarColors(isDark: boolean): void {
    if (!this.mainWindow) return
    try {
      const contentColor = isDark ? '#ffffffff' : '#ff000000'
      const barProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: contentColor,
        navigationBarColor: '#00000000',
        navigationBarContentColor: contentColor
      }
      this.mainWindow.setWindowSystemBarProperties(barProps)
      hilog.info(0, TAG, 'applyBarColors: isDark=%{public}s', isDark.toString())
    } catch (e) {
      hilog.warn(0, TAG, 'applyBarColors failed: %{public}s', (e as Error).message)
    }
  }
}

// 沉浸模式状态切换：进入时隐藏状态栏/导航栏与控制面板，退出时恢复可见
function computeImmersiveBarStateF(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}

// 将罗马数字字符串解析为整数
function romanToIntegerF(roman: string): number {
  const map = new Map<string, number>()
  map.set('I', 1); map.set('V', 5); map.set('X', 10)
  map.set('L', 50); map.set('C', 100); map.set('D', 500); map.set('M', 1000)
  let total = 0
  for (let i = 0; i < roman.length; i++) {
    const cur = map.get(roman[i]) ?? 0
    const nxt = i + 1 < roman.length ? (map.get(roman[i + 1]) ?? 0) : 0
    total += cur < nxt ? -cur : cur
  }
  return total
}

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG_H67(event: string, playing: boolean): string {
  if (event === 'gain') {
    return playing ? 'resume' : 'idle'
  }
  if (event === 'lossTransient') {
    return playing ? 'pause' : 'idle'
  }
  if (event === 'lossDuck') {
    return playing ? 'duck' : 'idle'
  }
  if (event === 'loss') {
    return 'stop'
  }
  return 'idle'
}

// 音量平衡：将 -1..1 的平衡值映射为左右声道增益系数
export function computeChannelGainsG_H67(balance: number): number[] {
  let b = balance
  if (b < -1) {
    b = -1
  } else if (b > 1) {
    b = 1
  }
  const left = b <= 0 ? 1 : 1 - b
  const right = b >= 0 ? 1 : 1 + b
  const lr = Math.round(left * 1000) / 1000
  const rr = Math.round(right * 1000) / 1000
  return [lr, rr]
}

// 淡入淡出：按总时长与步进生成线性插值的音量包络序列
export function buildFadeEnvelopeG_H67(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps = Math.max(1, Math.floor(durationMs / stepMs))
  const envelope: number[] = []
  for (let i = 0; i <= steps; i++) {
    const ratio = i / steps
    const v = from + (to - from) * ratio
    envelope.push(Math.round(v * 1000) / 1000)
  }
  return envelope
}

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorG_H67(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderG_H67(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 沉浸模式状态切换：进入时隐藏状态栏/导航栏与控制面板，退出时恢复可见
function computeImmersiveBarStateF_H67(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}
