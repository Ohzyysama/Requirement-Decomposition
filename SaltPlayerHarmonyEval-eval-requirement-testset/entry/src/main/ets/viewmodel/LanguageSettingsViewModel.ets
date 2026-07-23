// LanguageSettingsViewModel.ets
// ViewModel layer for LanguageSettingsPage - provides data and services
// for the Language Settings page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes observable data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import {
  LanguageSettingsDataModel,
  LanguageSettingsDataSource
} from '../model/LanguageSettingsModel';

@Observed
export default class LanguageSettingsViewModel {
  // System language code (e.g., "en", "zh") - displayed on the system language card
  @Track public systemLanguage: string = '';

  // Current display language name (e.g., "English", "Chinese") - shown in change language card
  @Track public currentDisplayLanguage: string = '';

  // Whether the current app channel supports user-defined language
  @Track public notSupportUserDefinedLanguage: boolean = true;

  // Whether the system language is in the supported languages list
  @Track public isLanguageSupported: boolean = true;

  // Help translation dialog visibility state
  @Track public showHelpTranslationDialog: boolean = false;

  constructor() {
    // Load data will be called from aboutToAppear in View
  }

  /**
   * Loads language data from Model layer.
   * View calls this in aboutToAppear lifecycle.
   */
  loadLanguageData(): void {
    const data: LanguageSettingsDataModel = LanguageSettingsDataSource.loadLanguageData();
    this.systemLanguage = data.systemLanguage;
    this.currentDisplayLanguage = data.currentDisplayLanguage;
    this.notSupportUserDefinedLanguage = data.notSupportUserDefinedLanguage;
    this.isLanguageSupported = LanguageSettingsDataSource.isLanguageSupported(data.systemLanguage);
  }

  /**
   * Handles back navigation.
   * View calls this when user taps the back button.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }

  /**
   * Handles the "Change Language" card click.
   * Only takes action if user-defined language is supported.
   */
  onChangeLanguageClick(): void {
    if (!this.notSupportUserDefinedLanguage) {
      // TODO: navigate to ChangeLanguage page - not yet implemented
      console.info('TODO: navigate to ChangeLanguagePage');
    }
  }

  /**
   * Shows the help translation dialog.
   * View calls this when user taps the "Help or Improve Translate" card.
   */
  showHelpDialog(): void {
    this.showHelpTranslationDialog = true;
  }

  /**
   * Dismisses the help translation dialog.
   * View calls this when user taps cancel or the dialog background.
   */
  dismissHelpDialog(): void {
    this.showHelpTranslationDialog = false;
  }

  /**
   * Confirms the help translation dialog and opens the translation URL.
   * View calls this when user taps the confirm button.
   */
  confirmHelpDialog(): void {
    this.showHelpTranslationDialog = false;
    // TODO: Open URL in browser - https://github.com/Moriafly/SaltPlayerSource/tree/main/translations
    console.info('TODO: open translation URL in browser');
  }
}

// 多语言：语言设置页状态与切换。
