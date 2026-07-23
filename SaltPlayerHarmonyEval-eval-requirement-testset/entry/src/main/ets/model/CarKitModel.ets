// CarKitModel.ets
// Model layer: pure data structure for Car Kit settings.
// Defines the raw data for all car-related toggle settings and third-party info.
// Does not contain any UI or ViewModel logic.

export default class CarKitModel {
  // Toggle: vehicle playback screen (requires Pro + tablet mode)
  public playerInterfaceForCar: boolean = false
  // Toggle: car bluetooth lyrics
  public carBluetoothLyrics: boolean = false
  // Toggle: vivo Jovi InCar lyrics
  public vivoJoviInCarLyrics: boolean = false
  // Whether user has Pro subscription (controls whether card 1 toggle is enabled)
  public isPro: boolean = false
  // Third-party car support: Dudu Auto official website URL
  public duduAutoWebsiteUrl: string = 'https://dudu-lucky.com'

  constructor(
    playerInterfaceForCar: boolean = false,
    carBluetoothLyrics: boolean = false,
    vivoJoviInCarLyrics: boolean = false,
    isPro: boolean = false,
    duduAutoWebsiteUrl: string = 'https://dudu-lucky.com'
  ) {
    this.playerInterfaceForCar = playerInterfaceForCar
    this.carBluetoothLyrics = carBluetoothLyrics
    this.vivoJoviInCarLyrics = vivoJoviInCarLyrics
    this.isPro = isPro
    this.duduAutoWebsiteUrl = duduAutoWebsiteUrl
  }
}

// 车载界面：车机模式下的播放界面开关（Pro+平板）。

// 车载蓝牙歌词与 Vivo Jovi InCar 歌词推送。

// 车载播放界面对齐。
