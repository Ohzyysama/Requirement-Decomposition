// ScreenWakeViewModel.ets
// ViewModel layer: manages the screen wake lock logic based on user settings
// and player/queue page visibility state.
//
// Logic:
// - When "playerKeepScreenOn" setting is ON:
//   - If player page or play queue page is in expanded/visible state -> keep screen on
//   - If player page and play queue page are both collapsed/hidden -> restore normal screen timeout
// - When "playerKeepScreenOn" setting is OFF:
//   - Always restore normal screen timeout behavior
//
// Uses AppStorage key 'playerKeepScreenOn' (persisted via PersistentStorage) to track the setting.
// Uses AppStorage key 'playerPageVisible' to track whether player/queue page is shown.

import ScreenWakeModel from '../model/ScreenWakeModel'
import SettingsStore from '../model/SettingsStore'
import { hilog } from '@kit.PerformanceAnalysisKit'

const DOMAIN: number = 0x0000
const TAG: string = 'ScreenWakeViewModel'

export default class ScreenWakeViewModel {
  private static instance: ScreenWakeViewModel | undefined = undefined

  private constructor() {
  }

  static getInstance(): ScreenWakeViewModel {
    if (!ScreenWakeViewModel.instance) {
      ScreenWakeViewModel.instance = new ScreenWakeViewModel()
    }
    return ScreenWakeViewModel.instance
  }

  // Called whenever the player keep screen on setting changes, or
  // whenever the player/queue page visibility changes.
  // Evaluates the current state and sets the screen wakelock accordingly.
  updateScreenWakeState(): void {
    const settingOn = (AppStorage.get<boolean>('playerKeepScreenOn') ?? false)
    const playerVisible = (AppStorage.get<boolean>('playerPageVisible') ?? false)

    const shouldKeepOn = settingOn && playerVisible

    hilog.info(DOMAIN, TAG,
      'updateScreenWakeState: settingOn=%{public}s playerVisible=%{public}s shouldKeepOn=%{public}s',
      settingOn.toString(), playerVisible.toString(), shouldKeepOn.toString())

    ScreenWakeModel.getInstance().setKeepScreenOn(shouldKeepOn)
  }

  // Called when the user toggles the "keep screen on" setting in UserInterfacePage.
  onSettingChanged(isOn: boolean): void {
    SettingsStore.getInstance().save('playerKeepScreenOn', isOn)
    this.updateScreenWakeState()
  }

  // Called when the player page or play queue page visibility changes.
  onPlayerVisibilityChanged(isVisible: boolean): void {
    AppStorage.setOrCreate<boolean>('playerPageVisible', isVisible)
    this.updateScreenWakeState()
  }
}

// 屏幕常亮：播放且播放页可见时保持屏幕常亮。
