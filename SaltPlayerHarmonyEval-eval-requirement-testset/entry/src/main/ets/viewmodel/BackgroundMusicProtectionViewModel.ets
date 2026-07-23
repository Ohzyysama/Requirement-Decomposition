// BackgroundMusicProtectionViewModel.ets
// ViewModel layer for BackgroundMusicProtectionPage - provides data and services
// for the Background Music Protection page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes observable data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import {
  ProtectItemModel,
  ProtectionSectionModel,
  BackgroundMusicProtectionDataSource
} from '../model/BackgroundMusicProtectionModel';

@Observed
export default class BackgroundMusicProtectionViewModel {
  // Section data exposed to View for rendering
  @Track public readableCheckSection: ProtectionSectionModel;
  @Track public selfCheckSection: ProtectionSectionModel;
  @Track public cautiousSuggestionSection: ProtectionSectionModel;

  constructor() {
    // Load data from Model layer via DataSource
    this.readableCheckSection = BackgroundMusicProtectionDataSource.getReadableCheckItemsCN(
      $r('app.string.readable_check_items')
    );
    this.selfCheckSection = BackgroundMusicProtectionDataSource.getSelfCheckItems(
      $r('app.string.self_check_items')
    );
    this.cautiousSuggestionSection = BackgroundMusicProtectionDataSource.getCautiousSuggestions();
  }

  /**
   * Returns readable check items from the readable section.
   */
  getReadableCheckItems(): ProtectItemModel[] {
    return this.readableCheckSection.items;
  }

  /**
   * Returns all self-check items.
   */
  getSelfCheckItems(): ProtectItemModel[] {
    return this.selfCheckSection.items;
  }

  /**
   * Returns all cautious suggestion items.
   */
  getCautiousSuggestionItems(): ProtectItemModel[] {
    return this.cautiousSuggestionSection.items;
  }

  /**
   * Returns the tip text for cautious suggestions section.
   */
  getCautiousSuggestionTip(): string {
    return this.cautiousSuggestionSection.tipText;
  }

  /**
   * Handles the "refresh" button click in the readable check items section.
   * Re-detects the autostart state. Currently a placeholder for future implementation.
   */
  refreshAutostartDetection(): void {
    console.info('TODO: refresh autostart state detection');
  }

  /**
   * Handles the back navigation action.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }
}

// 后台保活：厂商保护引导状态。
