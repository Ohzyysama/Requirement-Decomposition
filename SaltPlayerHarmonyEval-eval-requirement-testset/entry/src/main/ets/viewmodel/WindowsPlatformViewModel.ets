// WindowsPlatformViewModel.ets
// ViewModel layer for WindowsPlatformPage - provides data and services for the
// Windows Platform promotion page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import { common } from '@kit.AbilityKit';
import {
  WindowsPlatformBrandingModel,
  WindowsPlatformLinkItemModel,
  WindowsPlatformDataSource
} from '../model/WindowsPlatformModel';

@Observed
export default class WindowsPlatformViewModel {
  // Branding information for display
  @Track public brandingTitle: string = '';
  @Track public brandingSubtitle: string = '';
  @Track public promotionalImageResource: Resource | undefined = undefined;

  // Link items for display
  @Track public officialWebsiteItem: WindowsPlatformLinkItemModel | null = null;
  @Track public microsoftStoreItem: WindowsPlatformLinkItemModel | null = null;

  // Download section title
  @Track public downloadSectionTitle: Resource | undefined = undefined;

  constructor() {
    this.loadData();
  }

  /**
   * Loads data from the Model layer and populates ViewModel properties.
   */
  private loadData(): void {
    const branding: WindowsPlatformBrandingModel = WindowsPlatformDataSource.getBranding();
    this.brandingTitle = branding.title;
    this.brandingSubtitle = branding.subtitle;
    this.promotionalImageResource = branding.promotionalImageResource;

    this.officialWebsiteItem = WindowsPlatformDataSource.getOfficialWebsiteItem();
    this.microsoftStoreItem = WindowsPlatformDataSource.getMicrosoftStoreItem();
    this.downloadSectionTitle = WindowsPlatformDataSource.getDownloadSectionTitle();
  }

  /**
   * Handles the back navigation action.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }

  /**
   * Handles official website link click.
   * Opens the official website URL in an external browser.
   */
  openOfficialWebsite(context: common.UIAbilityContext): void {
    if (this.officialWebsiteItem) {
      this.openUrlInBrowser(context, this.officialWebsiteItem.url);
    }
  }

  /**
   * Handles Microsoft Store link click.
   * Opens the Microsoft Store URL in an external browser.
   */
  openMicrosoftStore(context: common.UIAbilityContext): void {
    if (this.microsoftStoreItem) {
      this.openUrlInBrowser(context, this.microsoftStoreItem.url);
    }
  }

  /**
   * Opens the given URL in an external browser.
   * Encapsulates the platform-specific URL opening logic.
   */
  private openUrlInBrowser(context: common.UIAbilityContext, url: string): void {
    try {
      context.openLink(url);
    } catch (err) {
      console.error('Failed to open URL in browser: ' + url);
    }
  }
}

// Windows：平台页状态。
