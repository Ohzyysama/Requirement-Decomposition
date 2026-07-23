// AboutViewModel.ets
// ViewModel layer for AboutPage - provides data and services for the About page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import { AboutMenuItemModel, AppInfoModel, AboutDataSource } from '../model/AboutModel';
import { WebPageRouterParams } from '../pages/WebPage';
import { bundleManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

@Observed
export default class AboutViewModel {
  // App information for display
  @Track public appName: string = '';
  @Track public versionText: string = '';
  @Track public registrationNumber: string = '';
  @Track public customerServiceEmail: string = '';
  @Track public copyrightText: string = '';
  @Track public iconColor: string = '';

  // Internal navigation URL (not directly rendered in UI)
  @Track private registrationUrl: string = '';
  // Menu items rendered via ForEach in the View
  @Track private menuItems: AboutMenuItemModel[] = [];

  constructor() {
    this.loadData();
  }

  /**
   * Loads data from the Model layer and populates ViewModel properties.
   * Version text is resolved at runtime from BundleManager rather than hard-coded.
   */
  private loadData(): void {
    const appInfo: AppInfoModel = AboutDataSource.getAppInfo();
    this.appName = appInfo.appName;
    this.versionText = this.readVersionFromBundle();
    this.registrationNumber = appInfo.registrationNumber;
    this.registrationUrl = appInfo.registrationUrl;
    this.customerServiceEmail = appInfo.customerServiceEmail;
    this.copyrightText = appInfo.copyrightText;
    this.iconColor = appInfo.iconColor;
    this.menuItems = AboutDataSource.getMenuItems();
  }

  /**
   * Reads "<versionName> <versionCode>" from the current app bundle.
   */
  private readVersionFromBundle(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return `${info.versionName} ${info.versionCode}`;
    } catch (e) {
      hilog.warn(0, 'AboutViewModel', 'readVersionFromBundle failed: %{public}s',
        (e as Error).message);
      return '';
    }
  }

  /**
   * Returns the list of menu items.
   */
  getMenuItems(): AboutMenuItemModel[] {
    return this.menuItems;
  }

  /**
   * Handles the registration number item click.
   * Navigates to the registration website.
   */
  navigateToRegistration(navPathStack: NavPathStack): void {
    navPathStack.pushPath({
      name: 'WebPage',
      param: new WebPageRouterParams(this.registrationUrl)
    });
  }

  /**
   * Handles menu item click.
   * Navigates to the appropriate page based on the menu item configuration.
   */
  navigateToMenuItem(navPathStack: NavPathStack, menuItem: AboutMenuItemModel): void {
    if (menuItem.targetUrl.length > 0) {
      // Web page navigation
      navPathStack.pushPath({
        name: menuItem.targetPage,
        param: new WebPageRouterParams(menuItem.targetUrl)
      });
    } else {
      // Internal page navigation
      navPathStack.pushPath({ name: menuItem.targetPage });
    }
  }

  /**
   * Handles double-click on the app name to navigate to DevPage.
   */
  navigateToDevPage(navPathStack: NavPathStack): void {
    navPathStack.pushPath({ name: 'DevPage' });
  }
}

// 关于页状态。
