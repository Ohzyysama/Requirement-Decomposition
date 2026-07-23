// WebPage.ets
// View layer for WebPage - responsible for UI display only.
// Displays a web page in a WebView with HDS native title bar.
// A thin progress bar appears at the top of the WebView area during page loading.
// Accessed via: AboutPage -> "App 备案号" / "软件使用条款" / "隐私协议" / "开放源代码许可"
//               HelpAndFeedbackPage, SkyScreen, etc.
//
// MVVM Architecture:
//   View (this file) -> ViewModel (WebPageViewModel) -> Model (WebPageModel)
//   View only handles UI rendering and delegates all business logic to ViewModel.

import { webview } from '@kit.ArkWeb'
import WebPageViewModel from '../viewmodel/WebPageViewModel'
import { WebPageConfig } from '../model/WebPageModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

// Re-export WebPageRouterParams from Model for backward compatibility.
// Other modules (AboutViewModel, HelpAndFeedbackModel, etc.) import it from here.
export { WebPageRouterParams } from '../model/WebPageModel'

@Component
export struct WebPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private webController: webview.WebviewController = new webview.WebviewController()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // ViewModel instance - all UI state and business logic is managed here
  @State viewModel: WebPageViewModel = new WebPageViewModel()

  build() {
    HdsNavDestination() {
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
          // WebView - full size within the Stack
          Web({ src: '', controller: this.webController })
            .width('100%')
            .height('100%')
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(false)
            .mixedMode(MixedMode.All)
            .darkMode(WebDarkMode.Auto)
            .forceDarkAccess(true)
            .overviewModeAccess(true)
            .metaViewport(true)
            .userAgent(this.viewModel.getUserAgent())
            .onControllerAttached(() => {
              this.viewModel.setControllerReady(true)
              const url = this.viewModel.getUrl()
              if (url) {
                this.webController.loadUrl(url)
              }
            })
            .onErrorReceive((event) => {
              if (event) {
                this.viewModel.onErrorReceived(
                  event.error.getErrorCode(),
                  event.error.getErrorInfo()
                )
              }
            })
            .onHttpErrorReceive((event) => {
              if (event) {
                this.viewModel.onHttpErrorReceived(
                  event.response.getResponseCode(),
                  event.request.getRequestUrl()
                )
              }
            })
            .onTitleReceive((event) => {
              if (event) {
                this.viewModel.onTitleReceived(event.title)
              }
            })
            .onProgressChange((event) => {
              if (event) {
                const isComplete = this.viewModel.onProgressChanged(event.newProgress)
                if (isComplete) {
                  setTimeout(() => {
                    this.viewModel.hideProgressBar()
                  }, this.viewModel.getProgressHideDelay())
                }
              }
            })

          // Progress bar overlay at the top
          if (this.viewModel.isProgressVisible) {
            Row()
              .width(this.viewModel.progress + '%')
              .height(WebPageConfig.PROGRESS_BAR_HEIGHT)
              .backgroundColor($r('app.color.salt_color_high_light'))
              .animation({ duration: 200 })
          }
        }
        .width('100%')
        .layoutWeight(1)

        Blank().height(MiniPlayerDefaults.TOTAL_HEIGHT)
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: this.viewModel.webViewTitle,
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onWillAppear(() => {
      this.viewModel.onPageAppear()
    })
    .onWillDisappear(() => {
      this.viewModel.onPageDisappear()
    })
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      // Delegate URL extraction to ViewModel
      const rawParam: Object | undefined = context.pathInfo.param as Object | undefined
      const url = this.viewModel.extractUrlFromParams(rawParam)
      if (url && this.viewModel.getIsControllerReady()) {
        try {
          this.webController.loadUrl(url)
        } catch (e) {
          this.viewModel.onLoadUrlFailed(e as Error)
        }
      }
    })
  }
}
