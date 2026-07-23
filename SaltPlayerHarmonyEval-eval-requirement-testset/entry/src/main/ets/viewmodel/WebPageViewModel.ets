// WebPageViewModel.ets
// ViewModel layer for WebPage - provides data and services for the Web page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes observable data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import { WebPageConfig, WebPageLoadingState } from '../model/WebPageModel'

@Observed
export default class WebPageViewModel {
  // ========== Observable UI state (bound to View) ==========

  // Web page title displayed in the title bar
  @Track public webViewTitle: string = ''

  // Loading progress (0-100)
  @Track public progress: number = 0

  // Whether the progress bar is visible
  @Track public isProgressVisible: boolean = true

  // ========== Internal state (not directly used in UI) ==========

  // URL to load, passed via navigation params
  @Track private url: string = ''

  // Whether the Web controller is attached and ready
  @Track private isControllerReady: boolean = false

  // ========== Data loading from Model ==========

  /**
   * Extracts the URL from navigation parameters.
   * Transforms raw navigation context data into a usable URL string.
   */
  extractUrlFromParams(rawParam: Object | undefined): string {
    if (rawParam) {
      const paramObj = rawParam as Record<string, Object>
      const extractedUrl = paramObj['url'] as string
      if (extractedUrl) {
        this.url = extractedUrl
        return this.url
      }
    }
    return ''
  }

  /**
   * Returns the current URL to load.
   */
  getUrl(): string {
    return this.url
  }

  /**
   * Sets the controller ready state.
   */
  setControllerReady(ready: boolean): void {
    this.isControllerReady = ready
  }

  /**
   * Returns whether the controller is ready.
   */
  getIsControllerReady(): boolean {
    return this.isControllerReady
  }

  // ========== Event handling methods (called by View) ==========

  /**
   * Handles web page title update from the WebView.
   * View calls this when onTitleReceive event fires.
   */
  onTitleReceived(title: string | undefined): void {
    if (title && title !== 'about:blank' && title !== '') {
      this.webViewTitle = title
    }
  }

  /**
   * Handles loading progress change from the WebView.
   * View calls this when onProgressChange event fires.
   * Returns true if loading is complete (progress === 100).
   */
  onProgressChanged(newProgress: number): boolean {
    this.progress = newProgress
    if (newProgress === WebPageConfig.PROGRESS_COMPLETE) {
      return true
    } else {
      if (!this.isProgressVisible) {
        this.isProgressVisible = true
      }
      return false
    }
  }

  /**
   * Hides the progress bar after a delay.
   * Called by the View after loading completes.
   */
  hideProgressBar(): void {
    this.isProgressVisible = false
  }

  /**
   * Handles web page error logging.
   * View calls this when onErrorReceive event fires.
   */
  onErrorReceived(errorCode: number, errorInfo: string): void {
    console.error(`${WebPageConfig.LOG_TAG} onErrorReceive: ${errorCode} ${errorInfo}`)
  }

  /**
   * Handles HTTP error logging.
   * View calls this when onHttpErrorReceive event fires.
   */
  onHttpErrorReceived(responseCode: number, requestUrl: string): void {
    console.error(`${WebPageConfig.LOG_TAG} onHttpErrorReceive: ${responseCode} url=${requestUrl}`)
  }

  /**
   * Handles load URL failure logging.
   */
  onLoadUrlFailed(error: Error | Object): void {
    console.error(`${WebPageConfig.LOG_TAG} loadUrl failed: ${JSON.stringify(error)}`)
  }

  /**
   * Handles the back navigation action.
   * View calls this method when user taps the back button.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop()
  }

  /**
   * Handles the page appearing event.
   */
  onPageAppear(): void {
    // No-op: keep MiniPlayer visible like other HDS pages
  }

  /**
   * Handles the page disappearing event.
   */
  onPageDisappear(): void {
    // No-op: keep MiniPlayer visible like other HDS pages
  }

  /**
   * Returns the WebView user agent string from Model config.
   */
  getUserAgent(): string {
    return WebPageConfig.USER_AGENT
  }

  /**
   * Returns the progress hide delay in milliseconds from Model config.
   */
  getProgressHideDelay(): number {
    return WebPageConfig.PROGRESS_HIDE_DELAY_MS
  }
}
