// ExitAppDialog.ets
// View layer: Dialog component for exiting the app or returning to desktop
// Corresponds to Android ExitAppDialog.kt (Salt UI BasicDialog + ItemButton + ItemOuterTextButton)
// Screenshot page_0009: dialog with title "退出", two blue-text action items, and gray "取消" button
//
// MVVM architecture:
//   View: ExitAppDialog (this file)
//   ViewModel: ExitAppDialogViewModel
//   Model: ExitAppModel

import ExitAppDialogViewModel from '../viewmodel/ExitAppDialogViewModel'

@CustomDialog
export struct ExitAppDialog {
  controller: CustomDialogController
  // ViewModel instance provided by the parent component
  private viewModel: ExitAppDialogViewModel = new ExitAppDialogViewModel()

  build() {
    Column() {
      // Dialog title - Android: DialogTitle(text = stringResource(id = R.string.exit_app))
      // Screenshot: "退出" top-left, dark text, ~18fp, bold
      Text($r('app.string.exit_app'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })

      // Action buttons container - Android: RoundedColumn { ItemButton(...) }
      // Screenshot: white rounded container with two blue-text action items
      Column() {
        // Exit app button - Android: ItemButton(text = stringResource(R.string.exit_app))
        // Salt UI ItemButton text uses SaltTheme.colors.highlight (blue) color
        Row() {
          Text($r('app.string.exit_app'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_high_light'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(50)
        .padding({ left: 14, right: 14 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          // View delegates to ViewModel for business logic
          this.viewModel.handleExitApp()
          this.controller.close()
        })

        // Return to desktop button - Android: ItemButton(text = stringResource(R.string.return_to_desktop))
        Row() {
          Text($r('app.string.return_to_desktop'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_high_light'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(50)
        .padding({ left: 14, right: 14 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          // View delegates to ViewModel for business logic
          this.viewModel.handleReturnToDesktop()
          this.controller.close()
        })
      }
      .width('90%')
      .borderRadius(12)
      .backgroundColor($r('app.color.salt_color_white'))

      // Cancel button - Android: ItemOuterTextButton(text = cancel.uppercase(),
      //   textColor = SaltTheme.colors.subText, backgroundColor = SaltTheme.colors.subBackground)
      // Android light mode: subBackground = Color(0xFFFFFFFF) (white)
      Row() {
        Text($r('app.string.cancel'))
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .textAlign(TextAlign.Center)
      }
      .width('90%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .borderRadius(12)
      .backgroundColor($r('app.color.salt_color_white'))
      .margin({ top: 12, bottom: 14 })
      .onClick(() => {
        this.controller.close()
      })
    }
    .width('85%')
    .backgroundColor($r('app.color.salt_color_dialog_background'))
    .borderRadius(16)
  }
}

// 补充注释，无逻辑变更。
