// StartupAndBackendViewModel.ets
// ViewModel layer: provides observable data and business logic for the Startup & Backend settings page
// Bridges the View and Model layers per MVVM architecture
// The View (StartupAndBackendPage) binds to this ViewModel for all display data and user actions

import StartupAndBackendModel from '../model/StartupAndBackendModel'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class StartupAndBackendViewModel {
  @Track public autoPlayback: boolean = false

  constructor(model?: StartupAndBackendModel) {
    // Prefer the already-restored AppStorage value (seeded by EntryAbility.onCreate
    // from SettingsStore). Fall back to the optional model, then to the default.
    const stored = AppStorage.get<boolean>('autoPlayback')
    if (stored !== undefined) {
      this.autoPlayback = stored
    } else if (model) {
      this.updateFromModel(model)
    }
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: StartupAndBackendModel): void {
    this.autoPlayback = model.autoPlayback
  }

  // Export current ViewModel state to Model
  toModel(): StartupAndBackendModel {
    return new StartupAndBackendModel(this.autoPlayback)
  }

  // Toggle the auto playback switch — routed through setAutoPlayback so
  // the write path (state + persistence) stays single-source.
  toggleAutoPlayback(): void {
    this.setAutoPlayback(!this.autoPlayback)
  }

  // Set the auto playback switch to a specific value and persist it.
  // SettingsStore.save writes to AppStorage + Preferences memory cache;
  // the actual disk flush happens on EntryAbility.onBackground.
  setAutoPlayback(isOn: boolean): void {
    this.autoPlayback = isOn
    SettingsStore.getInstance().save('autoPlayback', isOn)
  }
}

// 启动与后台：autoPlayback 持久化。
