// ReBecomeDialog.ets
// View layer: "重新激活" dialog component - corresponds to Android ReBecomeDialog.kt
// Shown when user taps "曾购买过诚信会员？" link on SaltPlayerProPage
//
// MVVM architecture:
//   View: ReBecomeDialog (this file)
//   ViewModel: ReBecomeDialogViewModel
//   Model: ReBecomeModel

import ReBecomeDialogViewModel from '../viewmodel/ReBecomeDialogViewModel'

@Component
export struct ReBecomeDialog {
  onDismiss: () => void = () => {}
  onActivate: () => void = () => {}

  // ViewModel instance - provides data and handles business logic
  private viewModel: ReBecomeDialogViewModel = new ReBecomeDialogViewModel()

  build() {
    Column() {
      // Semi-transparent background overlay
      Column()
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#80000000')
        .onClick(() => {
          // View delegates to ViewModel for dismiss logic
          this.viewModel.handleDismiss()
          this.onDismiss()
        })

      // Dialog content panel
      Column() {
        // Dialog title - text provided by ViewModel
        Text(this.viewModel.titleText)
          .fontSize(18)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .padding({ left: 16, top: 20, right: 16, bottom: 12 })

        // Description card - text provided by ViewModel
        Column() {
          Text(this.viewModel.descriptionText)
            .fontSize(13)
            .fontColor($r('app.color.salt_color_sub_text'))
            .lineHeight(20)
            .padding({ left: 16, top: 12, right: 16, bottom: 12 })
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('app.color.salt_color_sub_background'))
        .margin({ left: 16, right: 16, bottom: 8 })

        // Action buttons card
        Column() {
          // Activate button
          Row() {
            Text($r('app.string.activate'))
              .fontSize(15)
              .fontColor($r('app.color.salt_color_high_light'))
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            // View delegates to ViewModel for activate logic
            this.viewModel.handleActivate()
            this.onActivate()
          })

          Divider()
            .width('100%')
            .height(0.5)
            .color($r('app.color.salt_color_cutting_line'))

          // Cancel button - text provided by ViewModel
          Row() {
            Text(this.viewModel.cancelText)
              .fontSize(15)
              .fontColor($r('app.color.salt_color_sub_text'))
              .fontWeight(FontWeight.Medium)
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            // View delegates to ViewModel for dismiss logic
            this.viewModel.handleDismiss()
            this.onDismiss()
          })
        }
        .width('100%')
        .borderRadius(12)
        .backgroundColor($r('app.color.salt_color_sub_background'))
        .margin({ left: 16, right: 16, bottom: 20 })
      }
      .width('100%')
      .backgroundColor($r('app.color.salt_color_dialog_background'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }
}
