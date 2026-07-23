// SettingsModel.ets
// Model layer: data structures for the Settings page
// Defines the core data for settings items and pro status
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

// Data structure for a single settings menu item
export class SettingsItemModel {
  public icon: Resource
  public text: Resource
  public route: string
  public pageName: string
  public iconFillColor?: ResourceColor

  constructor(icon: Resource, text: Resource, route: string, pageName: string, iconFillColor?: ResourceColor) {
    this.icon = icon
    this.text = text
    this.route = route
    this.pageName = pageName
    this.iconFillColor = iconFillColor
  }
}

// Data structure for the Salt Player Pro entry card on the settings page
// Rendered above the main settings group as a separate single-item card
export class ProEntryItemModel {
  public icon: Resource
  public text: Resource
  public pageName: string

  constructor(icon: Resource, text: Resource, pageName: string) {
    this.icon = icon
    this.text = text
    this.pageName = pageName
  }
}

// Data structure for Salt Player Pro status
export class ProStatusModel {
  public isPro: boolean = false

  constructor(isPro: boolean = false) {
    this.isPro = isPro
  }
}

// Data source that supplies raw model data to the ViewModel
// Provides the default settings items matching the Android SettingsScreen.kt order
export class SettingsDataSource {
  static getProEntryItem(): ProEntryItemModel {
    return new ProEntryItemModel(
      $r('app.media.ic_crown'),
      $r('app.string.salt_player_pro'),
      'SaltPlayerProPage'
    )
  }

  static getSettingsItems(): SettingsItemModel[] {
    return [
      new SettingsItemModel($r('app.media.ic_theme'), $r('app.string.user_interface'), 'user_interface',
        'UserInterfacePage'),
      // new SettingsItemModel($r('app.media.ic_accessibility'), $r('app.string.accessibility'), 'accessibility',
      //   'AccessibilityPage'),
      new SettingsItemModel($r('app.media.ic_settings_lyrics'), $r('app.string.lyrics'), 'lyrics_settings',
        'LyricsSettingsPage', '#32C85A'),
      // new SettingsItemModel($r('app.media.ic_car'), $r('app.string.car_kit'), 'car_kit', 'CarKitPage'),
      new SettingsItemModel($r('app.media.ic_audio_output'), $r('app.string.audio_output'), 'audio_output',
        'AudioOutputPage'),
      new SettingsItemModel($r('app.media.ic_notification'), $r('app.string.notification'), 'notification',
        'NotificationPage'),
      new SettingsItemModel($r('app.media.ic_startup_and_backend'), $r('app.string.startup_and_backend'),
        'startup_and_backend', 'StartupAndBackendPage'),
      // new SettingsItemModel($r('app.media.ic_language'), $r('app.string.language'), 'language_settings',
      //   'LanguageSettingsPage'),
      new SettingsItemModel($r('app.media.ic_laboratory'), $r('app.string.laboratory'), 'laboratory',
        'LaboratoryPage'),
      // new SettingsItemModel($r('app.media.ic_feedback'), $r('app.string.help_and_feedback'), 'help_and_feedback',
      //   'HelpAndFeedbackPage')
    ]
  }

  static getDefaultProStatus(): ProStatusModel {
    return new ProStatusModel(false)
  }
}

// Data structure that aggregates all settings page data
export default class SettingsModel {
  public proStatus: ProStatusModel = new ProStatusModel()
  public settingsItems: SettingsItemModel[] = []

  constructor(proStatus?: ProStatusModel, settingsItems?: SettingsItemModel[]) {
    if (proStatus) {
      this.proStatus = proStatus
    }
    if (settingsItems) {
      this.settingsItems = settingsItems
    }
  }
}
