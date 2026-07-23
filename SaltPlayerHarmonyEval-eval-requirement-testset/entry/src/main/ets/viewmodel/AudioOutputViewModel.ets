// AudioOutputViewModel.ets
// ViewModel layer: provides observable data and business logic for AudioOutputPage (View).
// Bridges the Model layer with the View layer per MVVM architecture.
// The View calls ViewModel methods for user actions; ViewModel updates state and Model accordingly.

import AudioOutputModel, { SpeedLevelModel, AudioOutputModeModel } from '../model/AudioOutputModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import SwitcherRowModel from '../model/SwitcherRowModel'
import AudioPlayerService from '../model/AudioPlayerService'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class AudioOutputViewModel {
  // --- Observable state properties (View binds to these) ---

  @Track public audioFocusEnabled: boolean = true
  @Track public volumeBalanceEnabled: boolean = true
  @Track public fadeInOutEnabled: boolean = true
  @Track public selectedOutputMode: string = 'audiotrack'
  @Track public sampleRateMin: number = 4000
  @Track public sampleRateMax: number = 192000
  @Track public audioOutputFreq: number = 48000
  @Track public changeDeviceFreqEnabled: boolean = false
  @Track public compressorEnabled: boolean = false
  @Track public currentSpeed: number = AppStorage.get<number>('playbackSpeed') ?? 1.00

  // Sub-ViewModel for fadeInOut switcher row
  @Track public fadeInOutVM: SwitcherRowViewModel = new SwitcherRowViewModel()

  // --- Data from Model (rendered via ForEach in the View) ---
  @Track public speedLevels: SpeedLevelModel[] = AudioOutputModel.SPEED_LEVELS
  @Track public outputModes: AudioOutputModeModel[] = AudioOutputModel.OUTPUT_MODES

  // --- Internal Model reference ---
  @Track private model: AudioOutputModel = new AudioOutputModel()

  constructor() {
    this.loadFromModel()
  }

  // Load state from Model, restoring persisted values from AppStorage where available
  private loadFromModel(): void {
    this.audioFocusEnabled = AppStorage.get<boolean>('audioFocusEnabled') ?? true
    this.volumeBalanceEnabled = AppStorage.get<boolean>('volumeBalanceEnabled') ?? this.model.volumeBalanceEnabled
    this.fadeInOutEnabled = AppStorage.get<boolean>('fadeInOutEnabled') ?? this.model.fadeInOutEnabled
    this.selectedOutputMode = AppStorage.get<string>('selectedOutputMode') ?? this.model.selectedOutputMode
    this.sampleRateMin = this.model.sampleRateMin
    this.sampleRateMax = this.model.sampleRateMax
    this.audioOutputFreq = AppStorage.get<number>('audioOutputFreq') ?? this.model.audioOutputFreq
    this.changeDeviceFreqEnabled = AppStorage.get<boolean>('changeDeviceFreqEnabled') ?? this.model.changeDeviceFreqEnabled
    this.compressorEnabled = AppStorage.get<boolean>('compressorEnabled') ?? this.model.compressorEnabled
    this.currentSpeed = this.model.currentSpeed
  }

  // Initialize the fadeInOut sub-ViewModel (must be called in aboutToAppear with resource)
  initFadeInOutVM(): void {
    // Seed from AppStorage (live value wins) so the switch reflects the latest
    // persisted state when the page remounts after the flag changed elsewhere.
    const liveValue = AppStorage.get<boolean>('fadeInOutEnabled') ?? this.fadeInOutEnabled
    this.fadeInOutEnabled = liveValue
    const switcherModel = new SwitcherRowModel(liveValue, true, $r('app.string.fade_in_or_out_during_play_or_pause'))
    this.fadeInOutVM = new SwitcherRowViewModel(switcherModel, (value: boolean) => {
      this.setFadeInOutEnabled(value)
    })
  }

  // --- User action methods (called from View event handlers) ---

  setAudioFocusEnabled(value: boolean): void {
    this.audioFocusEnabled = value
    this.model.audioFocusEnabled = value
    SettingsStore.getInstance().save('audioFocusEnabled', value)
    console.info('[AudioFocus] VM.setAudioFocusEnabled: value = ' + value +
      ', AppStorage after set = ' + AppStorage.get<boolean>('audioFocusEnabled'))
    AudioPlayerService.getInstance().applyAudioFocusMode()
  }

  setVolumeBalanceEnabled(value: boolean): void {
    this.volumeBalanceEnabled = value
    this.model.volumeBalanceEnabled = value
    SettingsStore.getInstance().save('volumeBalanceEnabled', value)
  }

  setFadeInOutEnabled(value: boolean): void {
    this.fadeInOutEnabled = value
    this.model.fadeInOutEnabled = value
    SettingsStore.getInstance().save('fadeInOutEnabled', value)
    // Keep the child switcher row's observable state in sync so it reflects
    // the toggled value when the page is re-entered from the navigation stack.
    this.fadeInOutVM.isOn = value
  }

  setSelectedOutputMode(mode: string): void {
    this.selectedOutputMode = mode
    this.model.selectedOutputMode = mode
    SettingsStore.getInstance().save('selectedOutputMode', mode)
  }

  setAudioOutputFreq(freq: number): void {
    this.audioOutputFreq = freq
    this.model.audioOutputFreq = freq
    SettingsStore.getInstance().save('audioOutputFreq', freq)
  }

  setChangeDeviceFreqEnabled(value: boolean): void {
    this.changeDeviceFreqEnabled = value
    this.model.changeDeviceFreqEnabled = value
    SettingsStore.getInstance().save('changeDeviceFreqEnabled', value)
  }

  setCompressorEnabled(value: boolean): void {
    this.compressorEnabled = value
    this.model.compressorEnabled = value
    SettingsStore.getInstance().save('compressorEnabled', value)
  }

  setCurrentSpeed(speed: number): void {
    this.currentSpeed = speed
    this.model.currentSpeed = speed
    SettingsStore.getInstance().save('playbackSpeed', speed)
    AudioPlayerService.getInstance().setSpeed(speed)
  }

  // Check if a given speed value is the currently selected speed
  isSpeedSelected(speed: number): boolean {
    return Math.round(speed * 100) === Math.round(this.currentSpeed * 100)
  }

  // Restore all audio output settings to defaults
  restoreDefaults(): void {
    this.model.restoreDefaults()
    this.selectedOutputMode = this.model.selectedOutputMode
    this.audioOutputFreq = this.model.audioOutputFreq
    this.changeDeviceFreqEnabled = this.model.changeDeviceFreqEnabled
    SettingsStore.getInstance().save('selectedOutputMode', this.selectedOutputMode)
    SettingsStore.getInstance().save('audioOutputFreq', this.audioOutputFreq)
    SettingsStore.getInstance().save('changeDeviceFreqEnabled', this.changeDeviceFreqEnabled)
  }

  // Get the formatted sample rate range string
  getSampleRateRangeText(): string {
    return `${this.sampleRateMin} Hz ~ ${this.sampleRateMax} Hz`
  }

  // Get the formatted audio output freq text
  getAudioOutputFreqText(): string {
    return `${this.audioOutputFreq} Hz`
  }
}

// 音频输出：枚举音频输出设备并展示编码/采样率信息。
