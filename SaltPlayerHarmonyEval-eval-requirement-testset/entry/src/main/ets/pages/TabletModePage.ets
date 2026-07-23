// TabletModePage.ets
// View layer: Tablet mode settings page for Salt Player
// Corresponds to Android TabletModeScreen.kt
// Navigation path: MainPage -> Menu -> Settings -> User Interface -> Tablet Mode
//
// MVVM Architecture:
//   - View: this file (TabletModePage.ets) - UI layout and user interaction
//   - ViewModel: TabletModeViewModel.ets - observable state and business logic
//   - Model: TabletModeModel.ets - raw data structure

import TabletModeViewModel from '../viewmodel/TabletModeViewModel'
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct TabletModePage {
  private navPathStack: NavPathStack = new NavPathStack()

  // ViewModel: single source of truth for this page
  @State viewModel: TabletModeViewModel = new TabletModeViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ========== Title Bar ==========
        this.TitleBar()

        // ========== Scrollable Content ==========
        Scroll() {
          Column() {
            // --- Introduction Card ---
            this.IntroductionCard()

            // --- Keyboard Shortcuts Section ---
            this.KeyboardShortcutsSectionTitle()
            this.KeyboardShortcutsCard()
          }
          .alignItems(HorizontalAlign.Start)
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

      Text($r('app.string.tablet_mode'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Blank().width(49)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
  }

  // ========== Introduction Card Builder ==========
  @Builder
  IntroductionCard() {
    Column() {
      Text($r('app.string.tablet_mode_intro'))
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Keyboard Shortcuts Section Title Builder ==========
  @Builder
  KeyboardShortcutsSectionTitle() {
    Text($r('app.string.keyboard_shortcuts'))
      .fontSize(12)
      .fontColor($r('app.color.salt_color_sub_text'))
      .width('100%')
      .padding({ left: 14, top: 18, bottom: 8 })
  }

  // ========== Keyboard Shortcuts Card Builder ==========
  @Builder
  KeyboardShortcutsCard() {
    Column() {
      // Info tip
      Text($r('app.string.keyboard_shortcuts_intro'))
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .padding({ left: 14, right: 14, top: 12, bottom: 4 })
        .width('100%')

      // Toggle: Space bar play/pause - View binds ViewModel's data
      Row() {
        Text($r('app.string.space_bar_play_or_pause_music'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.viewModel.spaceBarPlayOrPause })
          .onChange((isOn: boolean) => {
            // View delegates state change to ViewModel
            this.viewModel.setSpaceBarPlayOrPause(isOn)
          })
          .selectedColor($r('app.color.salt_color_icon_foreground'))
      }
      .width('100%')
      .height(49)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 14, right: 14 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .clip(true)
  }
}

// 平板键盘快捷键设置。
