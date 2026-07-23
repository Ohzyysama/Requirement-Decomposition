// ScreenWakeModel.ets
// Model layer: handles the system API calls for keeping the screen awake.
// Uses window.setWindowKeepScreenOn to control screen wakelock.
// This model encapsulates all system-level screen wake operations.

import { window } from '@kit.ArkUI'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'ScreenWakeModel'

export default class ScreenWakeModel {
  private static instance: ScreenWakeModel | undefined = undefined
  private windowStage: window.Window | undefined = undefined
  private isKeepScreenOn: boolean = false

  private constructor() {
  }

  static getInstance(): ScreenWakeModel {
    if (!ScreenWakeModel.instance) {
      ScreenWakeModel.instance = new ScreenWakeModel()
    }
    return ScreenWakeModel.instance
  }

  // Initialize with the main window reference.
  // Must be called after windowStage.loadContent so the window is available.
  initWindow(mainWindow: window.Window): void {
    this.windowStage = mainWindow
    hilog.info(DOMAIN, TAG, 'Window initialized for screen wake control')
  }

  // Set screen keep-on state via system API.
  // Returns true if the operation succeeded.
  setKeepScreenOn(keepOn: boolean): void {
    if (!this.windowStage) {
      hilog.warn(DOMAIN, TAG, 'Window not initialized, cannot set keep screen on')
      return
    }
    if (this.isKeepScreenOn === keepOn) {
      return
    }
    try {
      this.windowStage.setWindowKeepScreenOn(keepOn).then(() => {
        this.isKeepScreenOn = keepOn
        hilog.info(DOMAIN, TAG, 'setWindowKeepScreenOn success: %{public}s', keepOn.toString())
      }).catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'setWindowKeepScreenOn failed: %{public}s', err.message)
      })
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'setWindowKeepScreenOn exception: %{public}s', JSON.stringify(err))
    }
  }

  // Get current keep screen on state
  getKeepScreenOn(): boolean {
    return this.isKeepScreenOn
  }
}

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
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

// 计算一组数值的标准差（总体）
function populationStdDevF(values: number[]): number {
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

// 屏幕常亮裁决：仅当开关开启且正在播放且在前台时请求 keep-screen-on
function shouldKeepScreenOnF_H66(featureEnabled: boolean, isPlaying: boolean, inForeground: boolean, batterySaver: boolean): boolean {
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

// 构建通知栏歌词文本：拼接当前句，必要时附下一句预览并限制总长
function buildNotificationLyricTextF_H66(currentLine: string, nextLine: string, showNext: boolean, maxLen: number): string {
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

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG_H66(event: string, playing: boolean): string {
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
export function computeChannelGainsG_H66(balance: number): number[] {
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

// 将罗马数字字符串解析为整数
function romanToIntegerF_H66(roman: string): number {
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

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorG_H66(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}
