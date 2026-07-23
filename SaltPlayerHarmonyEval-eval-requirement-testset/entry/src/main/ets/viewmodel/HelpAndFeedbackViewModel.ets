// HelpAndFeedbackViewModel.ets
// ViewModel layer for HelpAndFeedbackPage - provides data and services
// for the Help and Feedback page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes observable data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import {
  HelpAndFeedbackItemModel,
  HelpAndFeedbackDataSource
} from '../model/HelpAndFeedbackModel';

@Observed
export default class HelpAndFeedbackViewModel {
  // Menu items exposed to View for rendering
  @Track public menuItems: HelpAndFeedbackItemModel[];

  constructor() {
    // Load data from Model layer via DataSource
    this.menuItems = HelpAndFeedbackDataSource.getMenuItems();
  }

  /**
   * Returns the list of menu items for the Help and Feedback page.
   */
  getMenuItems(): HelpAndFeedbackItemModel[] {
    return this.menuItems;
  }

  /**
   * Handles menu item click - navigates to the target page.
   * View calls this method when user taps a menu item.
   */
  onMenuItemClick(navPathStack: NavPathStack, item: HelpAndFeedbackItemModel): void {
    if (item.navigationParam !== null) {
      navPathStack.pushPath({
        name: item.navigationTarget,
        param: item.navigationParam
      });
    } else {
      navPathStack.pushPath({ name: item.navigationTarget });
    }
  }

  /**
   * Handles the back navigation action.
   * View calls this method when user taps the back button.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }
}

// 用户反馈：技术支持外链入口。
