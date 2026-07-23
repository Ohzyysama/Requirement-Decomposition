// NotificationModel.ets
// Model layer: pure data structure for notification settings.
// Defines the raw data without any UI or ViewModel logic.
// Corresponds to Android's notification config data (Config.SHOW_NOTIFICATION_DESKTOP_LYRICS_BUTTON,
// Config.SHOW_NOTIFICATION_CLOSE_BUTTON, Config.DESKTOP_LYRICS).

import SettingsStore from './SettingsStore'

export default class NotificationModel {
  public showDesktopLyricsButton: boolean = true
  public showCloseButton: boolean = true
  public desktopLyricsEnabled: boolean = false

  constructor(
    showDesktopLyricsButton: boolean = true,
    showCloseButton: boolean = true,
    desktopLyricsEnabled: boolean = false
  ) {
    this.showDesktopLyricsButton = showDesktopLyricsButton
    this.showCloseButton = showCloseButton
    this.desktopLyricsEnabled = desktopLyricsEnabled
  }

  // Load persisted settings from AppStorage (hydrated by EntryAbility.onCreate
  // from SettingsStore on app startup). Reading from AppStorage keeps the load
  // path uniform with the rest of the app (see UserInterfaceViewModel et al.).
  loadSettings(): void {
    this.showDesktopLyricsButton =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    this.showCloseButton =
      AppStorage.get<boolean>('showCloseButton') ?? true
    this.desktopLyricsEnabled =
      AppStorage.get<boolean>('desktopLyrics') ?? false
  }

  saveShowDesktopLyricsButton(value: boolean): void {
    this.showDesktopLyricsButton = value
    SettingsStore.getInstance().save('showDesktopLyricsButton', value)
  }

  saveShowCloseButton(value: boolean): void {
    this.showCloseButton = value
    SettingsStore.getInstance().save('showCloseButton', value)
  }

  saveDesktopLyricsEnabled(value: boolean): void {
    this.desktopLyricsEnabled = value
    SettingsStore.getInstance().save('desktopLyrics', value)
  }
}

// 通知栏控制：配置媒体通知中的桌面歌词按钮与关闭按钮显隐。

// 通知高对比文字色：根据背景亮度选择高对比文字颜色。
