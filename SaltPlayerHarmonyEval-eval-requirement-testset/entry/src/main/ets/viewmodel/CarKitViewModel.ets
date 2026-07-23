// CarKitViewModel.ets
// ViewModel layer: provides observable data and business logic for CarKitPage (View).
// Bridges the Model layer (CarKitModel) with the View layer (CarKitPage).
// Manages the state of all car kit settings and exposes methods for user interactions.

import CarKitModel from '../model/CarKitModel'
import SwitcherWithIconAndSubRowViewModel from './SwitcherWithIconAndSubRowViewModel'
import SwitcherWithIconAndSubRowModel from '../model/SwitcherWithIconAndSubRowModel'

@Observed
export default class CarKitViewModel {
  // Card 1: Sub-ViewModel for playback screen toggle (icon + title + subtitle + toggle)
  @Track public playbackScreenVM: SwitcherWithIconAndSubRowViewModel
  // Card 2: Car Bluetooth Lyrics toggle state (first-level for proper observability)
  @Track public carBluetoothLyricsIsOn: boolean = false
  // Card 3: vivo Jovi InCar lyrics toggle state (first-level for proper observability)
  @Track public vivoJoviInCarLyricsIsOn: boolean = false
  // Dudu Auto website URL
  @Track public duduAutoWebsiteUrl: string = 'https://dudu-lucky.com'

  // The underlying model data
  @Track private model: CarKitModel

  constructor(model?: CarKitModel) {
    this.model = model ?? new CarKitModel()

    // Card 1: Playback Screen for Car (icon + title + subtitle + toggle)
    this.playbackScreenVM = new SwitcherWithIconAndSubRowViewModel(
      new SwitcherWithIconAndSubRowModel(
        this.model.playerInterfaceForCar,
        this.model.isPro,
        $r('app.media.ic_crown'),
        $r('app.string.playback_screen_for_car'),
        $r('app.string.playback_screen_for_car_intro')
      ),
      (val: boolean) => {
        this.onPlayerInterfaceForCarChanged(val)
      }
    )

    // Card 2: Car Bluetooth Lyrics
    this.carBluetoothLyricsIsOn = this.model.carBluetoothLyrics

    // Card 3: vivo Jovi InCar lyrics
    this.vivoJoviInCarLyricsIsOn = this.model.vivoJoviInCarLyrics

    this.duduAutoWebsiteUrl = this.model.duduAutoWebsiteUrl
  }

  // --- Business logic methods ---

  // Called when the "playback screen for car" toggle changes
  private onPlayerInterfaceForCarChanged(isOn: boolean): void {
    this.model.playerInterfaceForCar = isOn
    // TODO: Persist setting via AppConfig/MMKV equivalent
    console.info('CarKitViewModel: playerInterfaceForCar changed to: ' + isOn)
  }

  // Called when the "car bluetooth lyrics" toggle changes
  onCarBluetoothLyricsChanged(isOn: boolean): void {
    this.carBluetoothLyricsIsOn = isOn
    this.model.carBluetoothLyrics = isOn
    // TODO: Persist setting and request update media session
    console.info('CarKitViewModel: carBluetoothLyrics changed to: ' + isOn)
  }

  // Called when the "vivo Jovi InCar lyrics" toggle changes
  onVivoJoviInCarLyricsChanged(isOn: boolean): void {
    this.vivoJoviInCarLyricsIsOn = isOn
    this.model.vivoJoviInCarLyrics = isOn
    // TODO: Persist setting and request update media session
    console.info('CarKitViewModel: vivoJoviInCarLyrics changed to: ' + isOn)
  }

  // Called when user taps the "official website" link for Dudu Auto
  openDuduAutoWebsite(): void {
    // TODO: Open URL in browser using @ohos.app.ability.common context
    console.info('CarKitViewModel: TODO: Open URL ' + this.duduAutoWebsiteUrl + ' in browser')
  }

  // Export current state back to Model
  toModel(): CarKitModel {
    return new CarKitModel(
      this.playbackScreenVM.isOn,
      this.carBluetoothLyricsIsOn,
      this.vivoJoviInCarLyricsIsOn,
      this.playbackScreenVM.isEnabled,
      this.duduAutoWebsiteUrl
    )
  }
}

// 车机：车载播放界面状态。
