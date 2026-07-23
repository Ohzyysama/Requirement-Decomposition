// LanguageSettingsModel.ets
// Model layer for LanguageSettingsPage - defines core data structures
// and provides data access for language settings.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

import { i18n } from '@kit.LocalizationKit'

/**
 * Represents the language settings data structure.
 * Contains system language info and supported language configuration.
 */
export class LanguageSettingsDataModel {
  public systemLanguage: string = '';
  public currentDisplayLanguage: string = '';
  public notSupportUserDefinedLanguage: boolean = true;

  constructor(systemLanguage: string, currentDisplayLanguage: string, notSupportUserDefinedLanguage: boolean) {
    this.systemLanguage = systemLanguage;
    this.currentDisplayLanguage = currentDisplayLanguage;
    this.notSupportUserDefinedLanguage = notSupportUserDefinedLanguage;
  }
}

/**
 * Provides data access for language settings.
 * Data source that supplies raw model data to the ViewModel.
 */
export class LanguageSettingsDataSource {
  // Supported languages list (from Android LanguageSettingsScreen.kt)
  private static readonly supportedLanguages: string[] =
    ['en', 'es', 'in', 'ja', 'zh', 'pt', 'tr', 'ko', 'ku', 'de', 'fr', 'ru'];

  // Help translation URL
  static readonly HELP_TRANSLATION_URL: string =
    'https://github.com/Moriafly/SaltPlayerSource/tree/main/translations';

  /**
   * Loads system language information from i18n API.
   * Returns a LanguageSettingsDataModel with system language data.
   */
  static loadLanguageData(): LanguageSettingsDataModel {
    const langTag = i18n.System.getSystemLanguage();
    const primaryLang = langTag.split('-')[0];
    const displayLanguage = i18n.System.getDisplayLanguage(primaryLang, primaryLang, true);
    // Based on Android source: notSupportUserDefinedLanguage = AppChannel.isGooglePlay() || AppChannel.isOfficial()
    const notSupported = true;

    return new LanguageSettingsDataModel(primaryLang, displayLanguage, notSupported);
  }

  /**
   * Checks if the given language code is in the supported languages list.
   */
  static isLanguageSupported(languageCode: string): boolean {
    return LanguageSettingsDataSource.supportedLanguages.includes(languageCode);
  }
}

// 多语言：选择应用语言，支持跟随系统或手动指定。

// 多语言对齐：补充语言项的本地化名称。

// 多语言：补充语言项的本地化显示名。
