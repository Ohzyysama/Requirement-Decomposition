// WebPageModel.ets
// Model layer for WebPage - defines core data structures for the web page display.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

/**
 * Router parameter class for WebPage navigation.
 * Used by other modules (AboutViewModel, HelpAndFeedbackModel, etc.)
 * to pass the URL when navigating to WebPage.
 */
export class WebPageRouterParams {
  url: string = ''

  constructor(url: string) {
    this.url = url
  }
}

/**
 * Represents the web page loading state data.
 * Captures the raw data about web page loading progress and metadata.
 */
export class WebPageLoadingState {
  public title: string = ''
  public progress: number = 0
  public isLoading: boolean = true

  constructor(title?: string, progress?: number, isLoading?: boolean) {
    if (title !== undefined) {
      this.title = title
    }
    if (progress !== undefined) {
      this.progress = progress
    }
    if (isLoading !== undefined) {
      this.isLoading = isLoading
    }
  }
}

/**
 * WebView configuration constants.
 * Encapsulates the static configuration for the WebView component.
 */
export class WebPageConfig {
  static readonly USER_AGENT: string =
    'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36'
  static readonly PROGRESS_HIDE_DELAY_MS: number = 300
  static readonly PROGRESS_COMPLETE: number = 100
  static readonly PROGRESS_BAR_HEIGHT: number = 1
  static readonly TITLE_BAR_HEIGHT: number = 49
  static readonly BACK_BUTTON_SIZE: number = 49
  static readonly BACK_BUTTON_PADDING: number = 14
  static readonly LOG_TAG: string = '[WebPage]'
}
