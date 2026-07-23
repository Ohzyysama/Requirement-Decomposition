// MainMenuViewModel.ets
// ViewModel layer: provides data and logic for the MainMenuComponent view
// Bridges the View and Model layers per MVVM architecture

import { ConfigurationConstant } from '@kit.AbilityKit'
import { MenuItemData, ThemeOptionData, ThemeMode, MainMenuDataSource } from '../model/MainMenuModel'

@Observed
export default class MainMenuViewModel {
  // UI state: whether the theme panel is visible
  @Track public showThemePanel: boolean = false

  // UI state: theme icon rotation animation value
  @Track public themeIconRotation: number = 360

  // UI state: measured height of theme panel (for pushing menu groups down)
  @Track public themePanelHeight: number = 0

  // Data: current selected theme (synced with AppStorage externally via @StorageLink in View)
  // The ViewModel exposes methods but the actual selectedTheme is kept in AppStorage
  // so it remains globally accessible.

  // Data: menu items from Model layer
  @Track public readonly mainNavItems: MenuItemData[] = MainMenuDataSource.getMainNavItems()
  @Track public readonly utilNavItems: MenuItemData[] = MainMenuDataSource.getUtilNavItems()
  @Track public readonly themeOptions: ThemeOptionData[] = MainMenuDataSource.getThemeOptions()

  // Toggle theme panel visibility and return the target rotation value
  toggleThemePanel(): void {
    this.showThemePanel = !this.showThemePanel
    // The animation itself is driven by the View layer via animateTo,
    // but the target rotation is calculated here.
    this.themeIconRotation = this.showThemePanel ? 0 : 360
  }

  // Close theme panel and reset icon rotation
  closeThemePanel(): void {
    this.showThemePanel = false
    this.themeIconRotation = 360
  }

  // Update theme panel height (called from View onAreaChange callback)
  updateThemePanelHeight(height: number): void {
    this.themePanelHeight = height
  }

  // Get the color mode for a given theme mode (delegates to Model)
  getColorModeForTheme(mode: ThemeMode): ConfigurationConstant.ColorMode {
    return MainMenuDataSource.getColorModeForTheme(mode)
  }

  // Check if a theme option is currently selected
  isThemeSelected(mode: ThemeMode, selectedTheme: number): boolean {
    return selectedTheme === mode
  }
}
