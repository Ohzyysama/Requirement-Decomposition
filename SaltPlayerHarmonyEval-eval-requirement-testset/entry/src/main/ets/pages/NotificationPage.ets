// NotificationPage.ets
// View layer: Notification settings page for Salt Player - corresponds to Android NotificationScreen.kt
// This page displays when user navigates: MainPage -> Menu -> Settings -> Notification
// Follows MVVM architecture:
//   - View (this file): UI layout, delegates all user interactions to ViewModel
//   - ViewModel (NotificationViewModel.ets): business logic, observable state, bridges Model and View
//   - Model (NotificationModel.ets): raw data structure and persistence
//
// Style: HdsNavDestination + MINI title mode, wallpaper-aware background.

import NotificationViewModel from '../viewmodel/NotificationViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixSwitch,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct NotificationPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  // ViewModel: single source of truth for this page
  @State viewModel: NotificationViewModel = new NotificationViewModel()

  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  build() {
    HdsNavDestination() {
      Stack() {
        Scroll(this.scroller) {
          Column() {
            // --- Toggle Items ---
            this.ToggleItemsGroup()

            // --- Warning Info ---
            this.WarningInfoGroup()

            // Bottom spacer for MiniPlayer
            Blank()
              .height(MiniPlayerDefaults.TOTAL_HEIGHT)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // Also close desktop lyrics dialog overlay
        if (this.viewModel.showAlsoCloseDesktopLyricsDialog) {
          this.AlsoCloseDesktopLyricsDialog()
        }
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
          mainTitle: $r('app.string.notification'),
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ========== Toggle Items Group ==========
  @Builder
  ToggleItemsGroup() {
    List({ space: 0 }) {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: this.viewModel.showDesktopLyricsButtonVM.text },
          },
          suffixItem: new SuffixSwitch({
            isCheck: this.viewModel.showDesktopLyricsButtonVM.isOn,
            onChange: (_val: boolean) => {
              this.viewModel.showDesktopLyricsButtonVM.toggle()
            }
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          enable: this.viewModel.showDesktopLyricsButtonVM.isEnabled,
        })
      }
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: this.viewModel.showCloseButtonVM.text },
          },
          suffixItem: new SuffixSwitch({
            isCheck: this.viewModel.showCloseButtonVM.isOn,
            onChange: (_val: boolean) => {
              this.viewModel.showCloseButtonVM.toggle()
            }
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          enable: this.viewModel.showCloseButtonVM.isEnabled,
        })
      }
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .divider({
      strokeWidth: 0.5,
      color: $r('sys.color.comp_divider'),
      startMargin: 16,
      endMargin: 16,
    })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Warning Info Group ==========
  @Builder
  WarningInfoGroup() {
    Column() {
      Row() {
        // Warning icon (SVG, tinted by theme)
        Image($r('app.media.ic_warning'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.warning_icon_color'))
          .margin({ right: 12 })

        // Warning text
        Text($r('app.string.notification_screen_warning'))
          .fontSize(15)
          .fontColor($r('app.color.colorTextForeground'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor($r('app.color.warning_background'))
    .margin({ bottom: 12 })
  }

  // ========== Also Close Desktop Lyrics Dialog ==========
  @Builder
  AlsoCloseDesktopLyricsDialog() {
    Column() {
      Column() {
        Text($r('app.string.also_close_desktop_lyrics'))
          .fontSize(18)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })

        Text($r('app.string.also_close_desktop_lyrics_intro'))
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))
          .margin({ bottom: 24 })

        Row() {
          Button($r('app.string.cancel'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              // Delegate cancel action to ViewModel
              this.viewModel.cancelCloseDesktopLyrics()
            })

          Button($r('app.string.confirm'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_high_light'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              // Delegate confirm action to ViewModel
              this.viewModel.confirmCloseDesktopLyrics()
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.salt_color_white'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      // Delegate dismiss action to ViewModel
      this.viewModel.dismissDialog()
    })
  }
}
