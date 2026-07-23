// SettingsViewModel.ets
// ViewModel layer: provides observable data and business logic for the Settings page
// Bridges the View and Model layers per MVVM architecture
// The View (SettingsPage) binds to this ViewModel for all display data and user actions
// ViewModel does not directly access UI resources; it retrieves data from the Model layer

import SettingsModel, { SettingsItemModel, ProEntryItemModel, ProStatusModel, SettingsDataSource } from '../model/SettingsModel'

@Observed
export default class SettingsViewModel {
  @Track public isPro: boolean = false
  @Track public settingsItems: SettingsItemModel[] = []
  @Track public proEntry: ProEntryItemModel = SettingsDataSource.getProEntryItem()

  constructor() {
    // Load data from Model layer via DataSource
    this.settingsItems = SettingsDataSource.getSettingsItems()
    // Read Pro status from global AppStorage (persisted by EntryAbility / SettingsStore)
    this.isPro = AppStorage.get<boolean>('isPro') ?? false
  }

  // Resource id for the Pro entry subtitle (activated / disabled)
  // Reads directly from AppStorage so it updates after Pro activation without page recreation.
  getProSubtitleRes(): Resource {
    return (AppStorage.get<boolean>('isPro') ?? false) ? $r('app.string.activated') : $r('app.string.disabled')
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: SettingsModel): void {
    this.isPro = model.proStatus.isPro
    this.settingsItems = model.settingsItems
  }

  // Export current ViewModel state to Model
  toModel(): SettingsModel {
    return new SettingsModel(
      new ProStatusModel(this.isPro),
      this.settingsItems
    )
  }

  // Handle navigation for the Salt Player Pro card
  getProPageName(): string {
    return 'SaltPlayerProPage'
  }

  // Handle navigation for the Windows card
  getWindowsPageName(): string {
    return 'WindowsPlatformPage'
  }

  // Resolve page name for a settings item route
  // The ViewModel encapsulates the route-to-pageName mapping logic
  resolvePageName(route: string): string {
    for (let item of this.settingsItems) {
      if (item.route === route) {
        return item.pageName
      }
    }
    console.info('Unknown settings route: ' + route)
    return ''
  }

  // Handle menu item click - navigates to the target page
  // View calls this method when user taps a settings item
  onSettingsItemClick(navPathStack: NavPathStack, item: SettingsItemModel): void {
    let pageName: string = item.pageName
    if (pageName.length > 0) {
      navPathStack.pushPath({ name: pageName })
    }
  }

  // Handle Pro card click - navigates to the Pro page
  onProCardClick(navPathStack: NavPathStack): void {
    navPathStack.pushPath({ name: this.getProPageName() })
  }

  // Handle Windows card click - navigates to the Windows page
  onWindowsCardClick(navPathStack: NavPathStack): void {
    navPathStack.pushPath({ name: this.getWindowsPageName() })
  }

  // Handle the back navigation action
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop()
  }

  // Toggle Pro status (for future use when pro activation is implemented)
  toggleProStatus(): void {
    this.isPro = !this.isPro
  }

  // Set Pro status to a specific value
  setProStatus(isPro: boolean): void {
    this.isPro = isPro
  }

  // Refresh Pro status from global AppStorage
  refreshProStatus(): void {
    this.isPro = AppStorage.get<boolean>('isPro') ?? false
  }
}
