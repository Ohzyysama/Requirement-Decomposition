// LanguageSettingsPage.ets
// Language settings page for Salt Player - corresponds to Android LanguageSettingsScreen.kt
// This page displays when user navigates: MainPage -> Menu -> Settings -> Language
// Layout structure:
//   - Title bar with back button and "语言" title (centered)
//   - Scrollable content with:
//     1. RoundedColumn: "系统语言" label + system language value (e.g., "en")
//     2. RoundedColumn: Warning banner (amber background) about unsupported user-defined language
//     3. RoundedColumn: "改变语言" item with current language sub-text + chevron (disabled)
//     4. RoundedColumn: "Help or Improve Translate" item with chevron
//
// MVVM Architecture:
//   View: LanguageSettingsPage (this file) - UI rendering and user interaction
//   ViewModel: LanguageSettingsViewModel - data binding and business logic
//   Model: LanguageSettingsModel - data structures and data access

import LanguageSettingsViewModel from '../viewmodel/LanguageSettingsViewModel'
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct LanguageSettingsPage {
  private navPathStack: NavPathStack = new NavPathStack()

  // ViewModel - View binds to ViewModel data, all state is managed by ViewModel
  @State viewModel: LanguageSettingsViewModel = new LanguageSettingsViewModel()

  aboutToAppear(): void {
    // Delegate data loading to ViewModel
    this.viewModel.loadLanguageData()
  }

  build() {
    NavDestination() {
      BasicScreen() {
      Stack() {
        Column() {
          // ========== Title Bar ==========
          this.TitleBar()

          // ========== Scrollable Content ==========
          Scroll() {
            Column() {
              // --- System Language Card ---
              this.SystemLanguageCard()

              // --- Warning: Unsupported Language (shown if system language not in supported list) ---
              if (!this.viewModel.isLanguageSupported) {
                this.UnsupportedLanguageWarning()
              }

              // --- Warning: User-defined language not supported on this channel ---
              if (this.viewModel.notSupportUserDefinedLanguage) {
                this.ChannelWarningCard()
              }

              // --- Change Language Item ---
              this.ChangeLanguageCard()

              // --- Help or Improve Translate Item ---
              this.HelpTranslateCard()
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)
        }
        .width('100%')
        .height('100%')

        // ========== Help Translation Dialog (overlay) ==========
        if (this.viewModel.showHelpTranslationDialog) {
          this.HelpTranslationDialog()
        }
      }
      .width('100%')
      .height('100%')
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ========== Title Bar Builder ==========
  @Builder
  TitleBar() {
    Row() {
      // Back button with larger clickable area (matching Android 49x49vp touch target)
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.salt_color_icon_foreground'))
      }
      .width(49)
      .height(49)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        // Delegate navigation to ViewModel
        this.viewModel.navigateBack(this.navPathStack)
      })
      .accessibilityText('返回')

      // Title text - centered
      Text($r('app.string.language'))
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // Spacer to balance back button for centering
      Row()
        .width(49)
        .height(49)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
  }

  // ========== System Language Card ==========
  @Builder
  SystemLanguageCard() {
    Column() {
      Text($r('app.string.system_language'))
        .fontSize(12)
        .fontColor($r('app.color.salt_color_sub_text'))

      Text(this.viewModel.systemLanguage)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .margin({ top: 4 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 7, bottom: 14 })
  }

  // ========== Unsupported Language Warning ==========
  @Builder
  UnsupportedLanguageWarning() {
    Column() {
      Row() {
        Image($r('app.media.ic_warning'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.warning_icon_color'))
          .margin({ right: 12 })

        Text("Your country or region's language may not be supported")
          .fontSize(15)
          .fontColor($r('app.color.colorTextForeground'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.warning_background'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Channel Warning Card ==========
  @Builder
  ChannelWarningCard() {
    Column() {
      Row() {
        Image($r('app.media.ic_warning'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.warning_icon_color'))
          .margin({ right: 12 })

        Text('The current app channel does not support user-defined language')
          .fontSize(15)
          .fontColor($r('app.color.colorTextForeground'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.warning_background'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Change Language Card ==========
  @Builder
  ChangeLanguageCard() {
    Row() {
      Column() {
        Text($r('app.string.change_the_language'))
          .fontSize(16)
          .fontColor(this.viewModel.notSupportUserDefinedLanguage
            ? $r('app.color.salt_color_sub_text')
            : $r('app.color.salt_color_icon_foreground'))

        Text(this.viewModel.currentDisplayLanguage)
          .fontSize(12)
          .fontColor($r('app.color.salt_color_sub_text'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // Chevron right arrow
      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.salt_color_sub_text'))
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 14 })
    .enabled(!this.viewModel.notSupportUserDefinedLanguage)
    .onClick(() => {
      // Delegate click handling to ViewModel
      this.viewModel.onChangeLanguageClick()
    })
  }

  // ========== Help or Improve Translate Card ==========
  @Builder
  HelpTranslateCard() {
    Row() {
      Text('Help or Improve Translate')
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)

      // Chevron right arrow
      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.salt_color_sub_text'))
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .padding({ left: 14, right: 14, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 14 })
    .onClick(() => {
      // Delegate to ViewModel
      this.viewModel.showHelpDialog()
    })
  }

  // ========== Help Translation Dialog ==========
  @Builder
  HelpTranslationDialog() {
    Column() {
      Column() {
        Text($r('app.string.help_translation'))
          .fontSize(18)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Medium)
          .margin({ bottom: 12 })

        Text($r('app.string.help_translation_intro'))
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))
          .margin({ bottom: 20 })

        Row() {
          Button($r('app.string.cancel'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .backgroundColor($r('app.color.salt_color_sub_background'))
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              // Delegate to ViewModel
              this.viewModel.dismissHelpDialog()
            })

          Blank()
            .width(12)

          Button($r('app.string.confirm'))
            .fontSize(14)
            .fontColor('#ffffffff')
            .backgroundColor($r('app.color.salt_color_high_light'))
            .borderRadius(8)
            .layoutWeight(1)
            .height(40)
            .onClick(() => {
              // Delegate to ViewModel
              this.viewModel.confirmHelpDialog()
            })
        }
        .width('100%')
      }
      .width('90%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.salt_color_dialog_background'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      // Delegate to ViewModel
      this.viewModel.dismissHelpDialog()
    })
  }
}
