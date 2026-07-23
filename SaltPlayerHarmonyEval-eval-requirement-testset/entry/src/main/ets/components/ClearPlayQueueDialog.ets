// ClearPlayQueueDialog.ets
// View layer: Confirmation dialog for clearing the play queue
// Corresponds to Android YesNoDialog in PlayQueueUI.kt PlayQueueTitleBar
// Shows: title "清空播放队列", content "是否清空当前播放队列？",
//        cancel button (outline) and confirm button (blue filled)
//
// MVVM: This View uses ClearPlayQueueDialogViewModel for business logic.
//       The View handles UI rendering and user interaction,
//       delegating the confirm action to the ViewModel.

import ClearPlayQueueDialogViewModel from '../viewmodel/ClearPlayQueueDialogViewModel'

@CustomDialog
export struct ClearPlayQueueDialog {
  controller: CustomDialogController
  // ViewModel instance provided by the parent component (PlayQueueComponent)
  viewModel: ClearPlayQueueDialogViewModel = new ClearPlayQueueDialogViewModel()

  build() {
    Column() {
      // Dialog title - "清空播放队列"
      // Screenshot: top-left aligned, bold, dark text, ~18fp
      Text($r('app.string.clearing_play_queue'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      // Dialog content - "是否清空当前播放队列？"
      // Screenshot: below title, normal weight, dark text, ~15fp
      Text($r('app.string.whether_to_clear_the_current_playback_queue'))
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      // Button row - Cancel (left, outline) and Confirm (right, blue filled)
      // Screenshot: two side-by-side rounded buttons with equal width
      Row() {
        // Cancel button - outline style, gray text
        // Screenshot: "取消" centered, rounded ~20vp corners, no fill, border-like appearance
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor($r('app.color.salt_color_sub_text'))
          .backgroundColor($r('app.color.salt_color_sub_background'))
          .borderRadius(20)
          .layoutWeight(1)
          .height(42)
          .onClick(() => {
            this.controller.close()
          })

        // Spacer between buttons
        Blank()
          .width(16)

        // Confirm button - filled blue
        // Screenshot: "确定" centered, rounded ~20vp corners, blue background, white text
        Button($r('app.string.confirm'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(20)
          .layoutWeight(1)
          .height(42)
          .onClick(() => {
            // Delegate confirm action to ViewModel
            this.viewModel.handleConfirm()
            this.controller.close()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }
    .backgroundColor($r('app.color.salt_color_dialog_background'))
    .borderRadius(16)
    .margin({ left: 24, right: 24 })
  }
}

// 调整 import 顺序，无功能变更。
