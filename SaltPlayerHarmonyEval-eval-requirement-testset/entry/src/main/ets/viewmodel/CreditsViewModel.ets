// CreditsViewModel.ets
// ViewModel layer for CreditsPage - provides data and services for the Credits page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import {
  CreditsSectionModel,
  CreditsCopyrightModel,
  CreditsProjectInfoModel,
  CreditsDataSource
} from '../model/CreditsModel';

@Observed
export default class CreditsViewModel {
  // Credits sections for display (sections with title and names)
  @Track public sections: CreditsSectionModel[] = [];

  // Copyright text displayed after all sections
  @Track public copyrightText: string = '';

  // Project initiation resource displayed at the very end
  @Track public projectInitiationResource: Resource | undefined = undefined;

  // Layout measurement state for scroll animation
  @Track public contentAreaHeight: number = 0;
  @Track public totalScrollHeight: number = 0;

  constructor() {
    this.loadData();
  }

  /**
   * Loads data from the Model layer and populates ViewModel properties.
   */
  private loadData(): void {
    this.sections = CreditsDataSource.getCreditsSections();

    const copyright: CreditsCopyrightModel = CreditsDataSource.getCopyright();
    this.copyrightText = copyright.copyrightText;

    const projectInfo: CreditsProjectInfoModel = CreditsDataSource.getProjectInfo();
    this.projectInitiationResource = projectInfo.projectInitiationResource;
  }

  /**
   * Updates the content area height (visible scroll area height).
   * Called by the View when the scroll area's layout changes.
   */
  updateContentAreaHeight(height: number): void {
    this.contentAreaHeight = height;
  }

  /**
   * Updates the total scroll content height.
   * Called by the View when the scroll content's layout changes.
   */
  updateTotalScrollHeight(height: number): void {
    this.totalScrollHeight = height;
  }

  /**
   * Calculates the scroll distance for the auto-scroll animation.
   */
  getScrollDistance(): number {
    return this.totalScrollHeight - this.contentAreaHeight;
  }

  /**
   * Calculates the scroll animation duration based on scroll distance.
   * Uses the same proportional calculation as the Android version.
   */
  getScrollDuration(): number {
    const scrollDistance = this.getScrollDistance();
    return Math.max(
      CreditsDataSource.BASE_SCROLL_DURATION_MS,
      scrollDistance * CreditsDataSource.SCROLL_SPEED_FACTOR
    );
  }

  /**
   * Returns the scroll animation delay before starting auto-scroll.
   */
  getScrollDelay(): number {
    return CreditsDataSource.SCROLL_DELAY_MS;
  }

  /**
   * Handles the back navigation action.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }
}
