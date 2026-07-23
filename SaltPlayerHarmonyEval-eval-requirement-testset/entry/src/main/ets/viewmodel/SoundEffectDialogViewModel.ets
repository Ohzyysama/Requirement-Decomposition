// SoundEffectDialogViewModel.ets
// ViewModel layer: provides data and logic for SoundEffectDialogComponent (View).
// Bridges the Model layer data with the View layer, exposing state variables and methods.
// View calls ViewModel methods on user interaction; ViewModel delegates to Model for data operations.

import { SpeedLevelItem, SoundEffectConstants, SoundEffectDataSource } from '../model/SoundEffectModel'
import { promptAction } from '@kit.ArkUI'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class SoundEffectDialogViewModel {
  // Current playback speed, initialized from AppStorage for cross-component sync
  @Track public currentSpeed: number = AppStorage.get<number>('playbackSpeed') ?? SoundEffectConstants.DEFAULT_SPEED

  // Whether the compressor is enabled, bound to the compressor toggle UI
  @Track public compressorEnabled: boolean = false

  // Available speed levels for the speed selector (rendered via ForEach in the View)
  @Track private speedLevels: SpeedLevelItem[] = SoundEffectConstants.getSpeedLevels()

  // Get all speed level items for the View to render
  getSpeedLevels(): SpeedLevelItem[] {
    return this.speedLevels
  }

  // Check if a given speed value is currently selected
  // Uses integer comparison to avoid floating-point precision issues
  isSpeedSelected(speed: number): boolean {
    return Math.round(speed * 100) === Math.round(this.currentSpeed * 100)
  }

  // Called by View when user selects a speed level
  selectSpeed(speed: number): void {
    this.currentSpeed = speed
    SettingsStore.getInstance().save('playbackSpeed', speed)
    SoundEffectDataSource.applySpeed(speed)
  }

  // Called by View when user toggles the compressor
  setCompressorEnabled(enabled: boolean): void {
    this.compressorEnabled = enabled
    SoundEffectDataSource.setCompressorEnabled(enabled)
  }

  // Called by View when user taps the MAX Audio concert hall atmosphere item
  onConcertHallAtmosphereClick(): void {
    SoundEffectDataSource.openConcertHallAtmosphere()
  }

  // Called by View when user taps the system equalizer item
  // Returns true if the dialog should be dismissed
  onSystemEqualizerClick(): boolean {
    promptAction.showToast({ message: 'HarmonyOS 暂不支持系统均衡器' })
    return true
  }

  // Called by View when user taps the AUDIOFX V4 item
  onAudioFxV4Click(): void {
    SoundEffectDataSource.openAudioFxV4()
  }
}
