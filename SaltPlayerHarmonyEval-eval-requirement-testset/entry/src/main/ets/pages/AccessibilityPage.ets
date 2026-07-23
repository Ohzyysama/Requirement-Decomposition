// AccessibilityPage.ets
// View layer: Accessibility settings page for Salt Player
// Corresponds to Android AccessibilityScreen.kt
// This page displays when user navigates: MainPage -> Menu -> Settings -> Accessibility
// Layout structure:
//   - Title bar with back button and "无障碍" title
//   - Scrollable content with:
//     1. Section title "显示大小缩放"
//     2. RoundedColumn with info tip, slider (display size scale), toggle switch (follow system font), warning tip
//     3. RoundedColumn with "刷新并重启主界面" button
//     4. RoundedColumn with "系统无障碍设置" item with external link icon
//
// MVVM Architecture:
//   - View: this file (AccessibilityPage.ets) - UI layout and user interaction
//   - ViewModel: AccessibilityViewModel.ets - observable state and business logic
//   - Model: AccessibilityModel.ets - raw data structure

import AccessibilityViewModel from '../viewmodel/AccessibilityViewModel'
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct AccessibilityPage {
  private navPathStack: NavPathStack = new NavPathStack()

  // ViewModel: single source of truth for this page
  @State viewModel: AccessibilityViewModel = new AccessibilityViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ========== Error Dialog ==========
        if (this.viewModel.showErrorDialog) {
          this.ErrorDialog()
        }

        // ========== Title Bar ==========
        this.TitleBar()

        // ========== Scrollable Content ==========
        Scroll() {
          Column() {
            // --- Section Title: 显示大小缩放 ---
            Text($r('app.string.zoom_display_size'))
              .fontSize(12)
              .fontColor($r('app.color.salt_color_sub_text'))
              .width('100%')
              .padding({ left: 28, top: 18, bottom: 10 })

            // --- Display Size Scale Card ---
            this.DisplaySizeScaleCard()

            // --- Refresh and Restart Button Card ---
            this.RestartButtonCard()

            // --- System Accessibility Settings Card ---
            this.SystemAccessibilityCard()
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
        this.navPathStack.pop()
      })
      .accessibilityText('返回')

      // Title text - left-aligned after back button (matching Android layout)
      Text($r('app.string.accessibility'))
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
  }

  // ========== Display Size Scale Card ==========
  @Builder
  DisplaySizeScaleCard() {
    Column() {
      // Info tip text
      Text($r('app.string.zoom_display_size_info'))
        .fontSize(12)
        .fontColor($r('app.color.salt_color_sub_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })

      // Slider row: label + value + slider
      Column() {
        // Label row with text and current value
        Row() {
          Text($r('app.string.zoom_display_size'))
            .fontSize(16)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .layoutWeight(1)

          // View binds ViewModel's data for display
          Text(this.viewModel.getDisplaySizeScaleText())
            .fontSize(16)
            .fontColor($r('app.color.salt_color_sub_text'))
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10 })

        // Slider - View triggers ViewModel method on user interaction
        Slider({
          value: this.viewModel.displaySizeScale,
          min: 0.5,
          max: 2.0,
          step: 0.1
        })
          .blockColor($r('app.color.salt_color_high_light'))
          .trackColor('#e0e0e0')
          .selectedColor($r('app.color.salt_color_high_light'))
          .width('100%')
          .padding({ left: 14, right: 14, top: 4, bottom: 4 })
          .onChange((value: number) => {
            this.viewModel.updateDisplaySizeScale(value)
          })
      }
      .width('100%')

      // Toggle switch: follow system font scale
      Row() {
        Text($r('app.string.follow_system_font_scale'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)

        // View binds ViewModel's data for toggle state
        Toggle({ type: ToggleType.Switch, isOn: this.viewModel.followSystemFontScale })
          .selectedColor($r('app.color.salt_color_high_light'))
          .onChange((isOn: boolean) => {
            this.viewModel.setFollowSystemFontScale(isOn)
          })
      }
      .width('100%')
      .height(49)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // View triggers ViewModel method on click
        this.viewModel.toggleFollowSystemFontScale()
      })

      // Warning tip text
      Text($r('app.string.zoom_display_size_tip'))
        .fontSize(12)
        .fontColor($r('app.color.salt_color_sub_text'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 12 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Refresh and Restart Button Card ==========
  @Builder
  RestartButtonCard() {
    Column() {
      Row() {
        Text($r('app.string.refresh_and_restart_the_main_screen'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_high_light'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(49)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // View delegates business logic to ViewModel
        this.viewModel.refreshAndRestart()
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== System Accessibility Settings Card ==========
  @Builder
  SystemAccessibilityCard() {
    Column() {
      Row() {
        Text($r('app.string.system_accessibility_settings'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)

        // External link icon (matching Android ItemArrowType.Link)
        Image($r('app.media.ic_open_in_new'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.salt_color_sub_text'))
      }
      .width('100%')
      .height(49)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // View delegates business logic to ViewModel
        this.viewModel.openSystemAccessibilitySettings()
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Error Dialog Builder ==========
  @Builder
  ErrorDialog() {
    Column()
      .width(0)
      .height(0)
      .onAppear(() => {
        AlertDialog.show({
          title: $r('app.string.error'),
          message: $r('app.string.unable_to_start_system_accessibility_settings'),
          confirm: {
            value: 'OK',
            action: () => {
              // View delegates dialog dismissal to ViewModel
              this.viewModel.dismissErrorDialog()
            }
          },
          cancel: () => {
            this.viewModel.dismissErrorDialog()
          }
        })
      })
  }
}

// 无障碍设置入口页。

// 无障碍设置入口：调整无障碍页布局与入口项。
