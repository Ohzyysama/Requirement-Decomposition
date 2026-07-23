// HelpAndFeedbackPage.ets
// View layer (Page component) for Help and Feedback - MVVM architecture.
// This page displays when user navigates: MainPage -> Menu -> Settings -> Help and Feedback
// View layer responsibilities:
//   - Renders UI based on ViewModel data
//   - Delegates user interactions to ViewModel methods
//   - Does not contain business logic
// Layout structure:
//   - Title bar with back button and "帮助与反馈" title (centered)
//   - Scrollable content with menu items from ViewModel

// import ViewModel
import HelpAndFeedbackViewModel from '../viewmodel/HelpAndFeedbackViewModel';
// import Model type for ForEach item typing
import { HelpAndFeedbackItemModel } from '../model/HelpAndFeedbackModel';
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct HelpAndFeedbackPage {
  private navPathStack: NavPathStack = new NavPathStack()
  // View binds ViewModel data
  @State viewModel: HelpAndFeedbackViewModel = new HelpAndFeedbackViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ========== Title Bar ==========
        this.TitleBar()

        // ========== Scrollable Content ==========
        Scroll() {
          Column() {
            // Render menu items from ViewModel
            ForEach(this.viewModel.getMenuItems(), (item: HelpAndFeedbackItemModel) => {
              this.RoundedItem(item)
            })
          }
          .width('100%')
          .padding({ left: 14, right: 14 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
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
      // Back button with larger clickable area (matching Android 49x49dp touch target)
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
        // Delegate back navigation to ViewModel
        this.viewModel.navigateBack(this.navPathStack)
      })
      .accessibilityText('返回')

      // Title text - centered
      Text($r('app.string.help_and_feedback'))
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

  // ========== Rounded Item Builder ==========
  @Builder
  RoundedItem(item: HelpAndFeedbackItemModel) {
    Column() {
      Row() {
        // Item text
        Text(item.text)
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
      .height(49)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 14, right: 10 })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ top: 7, bottom: 7 })
    .clip(true)
    .onClick(() => {
      // Delegate item click to ViewModel
      this.viewModel.onMenuItemClick(this.navPathStack, item)
    })
  }
}
