// MainMenuModel.ets
// Model layer: data structures and data operations for the main menu
// Contains menu item definitions and theme-related data/logic

import { ConfigurationConstant } from '@kit.AbilityKit'

// Menu item data structure
export class MenuItemData {
  public icon: Resource
  public text: Resource
  public iconColor: string
  public iconPadding: number
  public route: string

  constructor(icon: Resource, text: Resource, iconColor: string, iconPadding: number, route: string) {
    this.icon = icon
    this.text = text
    this.iconColor = iconColor
    this.iconPadding = iconPadding
    this.route = route
  }
}

// Theme mode enum
export enum ThemeMode {
  FOLLOW_SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

// Theme option data structure
export class ThemeOptionData {
  public icon: Resource
  public title: Resource
  public mode: ThemeMode
  public iconWidth: number
  public iconHeight: number

  constructor(icon: Resource, title: Resource, mode: ThemeMode, iconWidth: number = 24, iconHeight: number = 24) {
    this.icon = icon
    this.title = title
    this.mode = mode
    this.iconWidth = iconWidth
    this.iconHeight = iconHeight
  }
}

// Data source providing menu configuration data
export class MainMenuDataSource {
  // First group: main navigation categories
  static getMainNavItems(): MenuItemData[] {
    return [
      new MenuItemData($r('app.media.ic_song'), $r('app.string.songs'), '#ff32c85a', 0, 'song'),
      new MenuItemData($r('app.media.ic_album_24'), $r('app.string.albums'), '#ffff3c32', 0, 'album'),
      new MenuItemData($r('app.media.ic_artist'), $r('app.string.artists'), '#ffffc551', 1, 'artist'),
      new MenuItemData($r('app.media.ic_folder'), $r('app.string.folders'), '#ff5856d6', 1, 'folder'),
      new MenuItemData($r('app.media.ic_playlist'), $r('app.string.playlists'), '#ff0078ff', 0, 'playlist')
    ]
  }

  // Second group: utilities and settings
  static getUtilNavItems(): MenuItemData[] {
    return [
      new MenuItemData($r('app.media.ic_token'), $r('app.string.scan_music'), '#ff5856d6', 0, 'media_source'),
      new MenuItemData($r('app.media.ic_store'), $r('app.string.music_library'), '#ffffc551', 0, 'music_library'),
      new MenuItemData($r('app.media.ic_statistics'), $r('app.string.statistics'), '#ffff3c32', 0, 'statistics'),
      new MenuItemData($r('app.media.ic_settings'), $r('app.string.settings'), '#ff32c85a', 0, 'settings'),
      new MenuItemData($r('app.media.ic_info'), $r('app.string.about'), '#ff0078ff', 0, 'about')
    ]
  }

  // Theme options
  static getThemeOptions(): ThemeOptionData[] {
    return [
      new ThemeOptionData($r('app.media.ic_harmony'), $r('app.string.follow_system'), ThemeMode.FOLLOW_SYSTEM, 52, 11),
      new ThemeOptionData($r('app.media.ic_light'), $r('app.string.light'), ThemeMode.LIGHT),
      new ThemeOptionData($r('app.media.ic_dark'), $r('app.string.dark'), ThemeMode.DARK)
    ]
  }

  // Map ThemeMode to system ConfigurationConstant.ColorMode
  static getColorModeForTheme(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.FOLLOW_SYSTEM:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
      case ThemeMode.LIGHT:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      case ThemeMode.DARK:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET
    }
  }
}
