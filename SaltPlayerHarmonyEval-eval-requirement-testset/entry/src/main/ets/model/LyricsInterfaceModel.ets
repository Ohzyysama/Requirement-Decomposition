// LyricsInterfaceModel.ets
// Model layer: pure data structures and data access for lyrics interface settings.
// MVVM role: Defines raw data structures, handles data persistence (load/save),
// and provides business data to the ViewModel. Does not interact with UI directly.

import { deviceInfo } from '@kit.BasicServicesKit'

export class KaraokeCompatStrategy {
  static readonly CURRENT_LINE_ONLY: number = 0
  static readonly EXPAND_ALL_LINES: number = 1
  static readonly ALWAYS: number = 2
}

export default class LyricsInterfaceModel {
  public textSize: number = 20
  public textAlignCenter: boolean = false
  public fontWeight: number = 600
  public blur: boolean = false
  public karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.CURRENT_LINE_ONLY
  public hideControlPanel: boolean = false
  public isPro: boolean = false

  constructor(
    textSize: number = 20,
    textAlignCenter: boolean = false,
    fontWeight: number = 600,
    blur: boolean = false,
    karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.CURRENT_LINE_ONLY,
    hideControlPanel: boolean = false,
    isPro: boolean = false
  ) {
    this.textSize = textSize
    this.textAlignCenter = textAlignCenter
    this.fontWeight = fontWeight
    this.blur = blur
    this.karaokeCompatStrategyIndex = karaokeCompatStrategyIndex
    this.hideControlPanel = hideControlPanel
    this.isPro = isPro
  }

  // ========== Data access methods (persistence) ==========

  // Load settings from persistent storage and return a Model instance
  static loadFromStorage(): LyricsInterfaceModel {
    const textSize = (AppStorage.get('lyricsTextSize') as number) ?? 20
    const textAlignCenter = (AppStorage.get('lyricsTextAlignCenter') as boolean) ?? false
    const fontWeight = (AppStorage.get('lyricsFontWeight') as number) ?? 600
    const blur = (AppStorage.get('lyricsBlur') as boolean) ?? false
    const karaokeCompatStrategyIndex =
      (AppStorage.get('lyricsKaraokeCompatStrategy') as number) ?? KaraokeCompatStrategy.CURRENT_LINE_ONLY
    // Spec15: hide-control-panel toggle is hydrated from AppStorage here so a
    // restart respects the previously-persisted value.
    const hideControlPanel = (AppStorage.get('lyricsHideControlPanel') as boolean) ?? false
    return new LyricsInterfaceModel(
      textSize,
      textAlignCenter,
      fontWeight,
      blur,
      karaokeCompatStrategyIndex,
      hideControlPanel,
      false
    )
  }

  // Save current Model data to persistent storage
  saveToStorage(): void {
    AppStorage.setOrCreate('lyricsTextSize', this.textSize)
    AppStorage.setOrCreate('lyricsTextAlignCenter', this.textAlignCenter)
    AppStorage.setOrCreate('lyricsFontWeight', this.fontWeight)
    AppStorage.setOrCreate('lyricsBlur', this.blur)
    AppStorage.setOrCreate('lyricsKaraokeCompatStrategy', this.karaokeCompatStrategyIndex)
    // Spec15: round-trip the hide-control-panel flag so callers using the
    // bulk-save path also surface this setting to AppStorage subscribers.
    AppStorage.setOrCreate('lyricsHideControlPanel', this.hideControlPanel)
  }

  // Whether the lyrics blur feature is supported on the current device.
  // Spec13 scenario 7: API 12+ required; below that the switch is shown
  // but disabled. Wrapped in try/catch so emulators / mocks that throw on
  // the property access fall back to true (favor showing the feature).
  static isBlurSupported(): boolean {
    try {
      return deviceInfo.sdkApiVersion >= 12
    } catch (_e) {
      return true
    }
  }
}
