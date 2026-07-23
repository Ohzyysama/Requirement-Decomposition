// SleepTimerDialogViewModel.ets
// ViewModel layer: provides data and logic for the SleepTimerDialogComponent view
// Bridges the View and Model layers per MVVM architecture

import { SleepTimerConfig, SleepTimerConstants, SleepTimerState } from '../model/SleepTimerModel'
import SleepTimerService from '../model/SleepTimerService'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class SleepTimerDialogViewModel {
  // Sleep duration in minutes, bound to the slider and display text
  @Track public sleepMinutes: number =
    (SettingsStore.getInstance().get('sleepTimerMinutes', SleepTimerConstants.DEFAULT_MINUTES)) as number

  // Whether to automatically extend to the end of the current song
  @Track public autoExtend: boolean =
    (SettingsStore.getInstance().get('sleepTimerAutoExtend', true)) as boolean

  // Countdown display state
  @Track public isCountdownActive: boolean = false
  @Track public countdownText: string = '00:00'
  @Track public isExtendPhase: boolean = false

  // Update the sleep duration from the slider
  updateSleepMinutes(value: number): void {
    this.sleepMinutes = Math.round(value)
    SettingsStore.getInstance().save('sleepTimerMinutes', this.sleepMinutes)
  }

  // Toggle the auto-extend setting
  toggleAutoExtend(): void {
    this.autoExtend = !this.autoExtend
    SettingsStore.getInstance().save('sleepTimerAutoExtend', this.autoExtend)
  }

  // Set the auto-extend value directly
  setAutoExtend(isOn: boolean): void {
    this.autoExtend = isOn
    SettingsStore.getInstance().save('sleepTimerAutoExtend', this.autoExtend)
  }

  // Start the sleep timer using the current configuration
  startTimer(): SleepTimerConfig {
    const config = new SleepTimerConfig()
    config.minutes = this.sleepMinutes
    config.autoExtend = this.autoExtend
    SleepTimerService.getInstance().start(config)
    this.isCountdownActive = true
    this.syncFromService()
    return config
  }

  // Stop the timer
  stopTimer(): void {
    SleepTimerService.getInstance().cancel()
    this.isCountdownActive = false
    this.isExtendPhase = false
    this.countdownText = '00:00'
  }

  // Sync state from the global service (called on dialog open and periodically)
  syncFromService(): void {
    const service = SleepTimerService.getInstance()
    const state = service.getState()
    const remainingMs = service.getRemainingMs()

    this.isCountdownActive = (state === SleepTimerState.TICK ||
      state === SleepTimerState.TICK_UNTIL_SONG_END)
    this.isExtendPhase = service.getIsExtendPhase()
    this.countdownText = this.formatCountdown(remainingMs)
  }

  private formatCountdown(ms: number): string {
    const totalSeconds = Math.ceil(ms / 1000)
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    const pad = (n: number): string => n < 10 ? '0' + n : '' + n

    let timeStr: string
    if (hours > 0) {
      timeStr = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
    } else {
      timeStr = `${pad(minutes)}:${pad(seconds)}`
    }

    return this.isExtendPhase ? `+${timeStr}` : timeStr
  }

  // Get the minimum slider value
  getMinMinutes(): number {
    return SleepTimerConstants.MIN_MINUTES
  }

  // Get the maximum slider value
  getMaxMinutes(): number {
    return SleepTimerConstants.MAX_MINUTES
  }

  // Get the slider step value
  getSliderStep(): number {
    return SleepTimerConstants.SLIDER_STEP
  }
}

// 睡眠定时对话框：滑动选择定时分钟数。
