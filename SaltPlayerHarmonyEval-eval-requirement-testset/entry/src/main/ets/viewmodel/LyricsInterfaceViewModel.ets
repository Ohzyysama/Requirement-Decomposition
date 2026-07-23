// LyricsInterfaceViewModel.ets
// ViewModel layer: provides observable data and business logic for LyricsInterfaceDialogComponent (View).
// MVVM role: Bridges the Model layer data with the View layer.
//   - Upward: exposes @Track state variables that drive UI updates via @ObjectLink in the View.
//   - Downward: reads from and writes to Model layer (LyricsInterfaceModel) for data persistence.
// View calls ViewModel methods on user interaction; ViewModel updates its own state and notifies Model.

import LyricsInterfaceModel, { KaraokeCompatStrategy } from '../model/LyricsInterfaceModel'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class LyricsInterfaceViewModel {
  // ========== Singleton ==========
  private static _instance: LyricsInterfaceViewModel | null = null

  static getInstance(): LyricsInterfaceViewModel {
    if (!LyricsInterfaceViewModel._instance) {
      const model = LyricsInterfaceModel.loadFromStorage()
      LyricsInterfaceViewModel._instance = new LyricsInterfaceViewModel(model)
    }
    return LyricsInterfaceViewModel._instance
  }

  // ========== Observable state properties (drive UI refresh via @Track) ==========
  @Track public textSize: number = 20
  @Track public textAlignCenter: boolean = false
  @Track public fontWeight: number = 600

  // Pending slider values (only used by settings UI, do NOT drive lyrics rendering)
  @Track public pendingTextSize: number = 24
  @Track public pendingFontWeight: number = 600
  @Track public blur: boolean = false
  @Track public karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.CURRENT_LINE_ONLY
  @Track public hideControlPanel: boolean = false
  @Track public isPro: boolean = false

  // Spec13: lyrics-view blur is gated by device API level (>=12). When
  // unsupported, the switch is rendered but disabled (scenario 7).
  @Track public isBlurSupported: boolean = LyricsInterfaceModel.isBlurSupported()

  // Karaoke strategy option labels (read-only display data)
  @Track public readonly karaokeStrategyOptions: string[] = [
    '当前行',
    '扩展全部',
    '总是'
  ]

  // Slider configuration constants (read-only)
  @Track public readonly textSizeMin: number = 12
  @Track public readonly textSizeMax: number = 48
  @Track public readonly textSizeSteps: number = 36
  @Track public readonly fontWeightMin: number = 100
  @Track public readonly fontWeightMax: number = 900
  @Track public readonly fontWeightSteps: number = 8

  // Internal Model reference (not exposed to View)
  @Track private model: LyricsInterfaceModel = new LyricsInterfaceModel()

  constructor(model?: LyricsInterfaceModel) {
    if (model) {
      this.model = model
    }
    // Spec15: seed isPro from the global AppStorage key. EntryAbility
    // persists 'isPro' so any future activation path lands in a single place.
    this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
    this.model.isPro = this.isPro
    this.syncFromModel()
  }

  // ========== Model <-> ViewModel synchronization ==========

  // Load settings from Model layer into ViewModel state
  loadSettings(): void {
    this.model = LyricsInterfaceModel.loadFromStorage()
    // Spec15: refresh Pro state from the global AppStorage key on every
    // settings-page entry so the gated row updates after activation.
    this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
    this.model.isPro = this.isPro
    this.syncFromModel()
  }

  // Sync ViewModel properties from the internal Model
  private syncFromModel(): void {
    this.textSize = this.model.textSize
    this.textAlignCenter = this.model.textAlignCenter
    this.fontWeight = this.model.fontWeight
    this.pendingTextSize = this.model.textSize
    this.pendingFontWeight = this.model.fontWeight
    this.blur = this.model.blur
    this.karaokeCompatStrategyIndex = this.model.karaokeCompatStrategyIndex
    this.hideControlPanel = this.model.hideControlPanel
    this.isPro = this.model.isPro
    // Initialize AppStorage so @StorageProp subscribers get correct initial values
    // Use AppStorage directly here (not SettingsStore) — this is a read-back, not a user change
    AppStorage.setOrCreate('lyricsTextSize', this.textSize)
    AppStorage.setOrCreate('lyricsTextAlignCenter', this.textAlignCenter)
    AppStorage.setOrCreate('lyricsFontWeight', this.fontWeight)
    AppStorage.setOrCreate('lyricsBlur', this.blur)
    AppStorage.setOrCreate('lyricsKaraokeCompatStrategy', this.karaokeCompatStrategyIndex)
    // Spec15: surface hide-control-panel so PlayerPage @StorageProp wakes up
    // on first VM construction even before any explicit toggle.
    AppStorage.setOrCreate('lyricsHideControlPanel', this.hideControlPanel)
  }

  // Update ViewModel from an external Model instance
  updateFromModel(model: LyricsInterfaceModel): void {
    this.model = model
    this.syncFromModel()
  }

  // Export current ViewModel state back to a Model instance
  toModel(): LyricsInterfaceModel {
    return new LyricsInterfaceModel(
      this.textSize,
      this.textAlignCenter,
      this.fontWeight,
      this.blur,
      this.karaokeCompatStrategyIndex,
      this.hideControlPanel,
      this.isPro
    )
  }

  // ========== Business logic methods (called by View on user interaction) ==========

  // Update pending text size from slider value (only updates slider display, NOT lyrics view)
  updateTextSize(value: number): void {
    this.pendingTextSize = Math.round(value)
  }

  // Save text size -- persists via SettingsStore (AppStorage + Preferences) and updates Model
  saveTextSize(): void {
    this.textSize = this.pendingTextSize
    this.model.textSize = this.textSize
    SettingsStore.getInstance().save('lyricsTextSize', this.textSize)
  }

  // Toggle text alignment center
  updateTextAlignCenter(value: boolean): void {
    this.textAlignCenter = value
    this.model.textAlignCenter = value
    this.model.saveToStorage()
    SettingsStore.getInstance().save('lyricsTextAlignCenter', value)
  }

  // Spec16: external sync hook. Called by LaboratoryViewModel after the
  // mutual-exclusion flip writes lyricsTextAlignCenter through AppStorage.
  // We update the @Track field directly so subscribers re-render, but skip
  // SettingsStore.save (the caller already persisted).
  refreshTextAlignFromStorage(): void {
    const v = (AppStorage.get<boolean>('lyricsTextAlignCenter') ?? false)
    this.textAlignCenter = v
    this.model.textAlignCenter = v
  }

  // Update pending font weight from slider value (only updates slider display, NOT lyrics view)
  updateFontWeight(value: number): void {
    this.pendingFontWeight = Math.round(value)
  }

  // Save font weight -- persists via SettingsStore (AppStorage + Preferences) and updates Model
  saveFontWeight(): void {
    this.fontWeight = this.pendingFontWeight
    this.model.fontWeight = this.fontWeight
    SettingsStore.getInstance().save('lyricsFontWeight', this.fontWeight)
  }

  // Toggle blur mode -- persists via SettingsStore (AppStorage + Preferences)
  // and updates Model. Suppressed on unsupported devices (scenario 7).
  updateBlur(value: boolean): void {
    if (!this.isBlurSupported) return
    this.blur = value
    this.model.blur = value
    SettingsStore.getInstance().save('lyricsBlur', value)
  }

  // Change karaoke compatibility strategy
  updateKaraokeStrategy(index: number): void {
    this.karaokeCompatStrategyIndex = index
    this.model.karaokeCompatStrategyIndex = index
    this.model.saveToStorage()
    SettingsStore.getInstance().save('lyricsKaraokeCompatStrategy', index)
  }

  // Get current karaoke strategy display text
  getKaraokeStrategyText(): string {
    return this.karaokeStrategyOptions[this.karaokeCompatStrategyIndex]
  }

  // Toggle hide control panel — persisted via SettingsStore (AppStorage + Preferences).
  updateHideControlPanel(value: boolean): void {
    this.hideControlPanel = value
    this.model.hideControlPanel = value
    SettingsStore.getInstance().save('lyricsHideControlPanel', value)
  }

  // Calculate slider step value (utility)
  getSliderStep(min: number, max: number, steps: number): number {
    return steps > 0 ? (max - min) / steps : 1
  }
}
