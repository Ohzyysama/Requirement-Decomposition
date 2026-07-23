// DeleteSongDialog.ets
// View layer: Confirmation dialog for removing a song from the music library
// Shows: title "从音乐库中移除", content "从音乐库中移除 {songTitle} 吗?",
//        cancel button (outline) and confirm button (blue filled)
// Note: This only removes the song from the app's database, it does NOT delete the original file
//
// MVVM architecture:
//   View: DeleteSongDialog (this file)
//   ViewModel: DeleteSongDialogViewModel
//   Model: DeleteSongModel

import DeleteSongDialogViewModel from '../viewmodel/DeleteSongDialogViewModel'
import { DeleteSongInfo } from '../model/DeleteSongModel'

@CustomDialog
export struct DeleteSongDialog {
  controller: CustomDialogController
  songTitle: string = ''
  onConfirm: () => void = () => {}
  private viewModel: DeleteSongDialogViewModel = new DeleteSongDialogViewModel()

  // Start fully transparent; animate to opaque in aboutToAppear to prevent
  // the cancel button's light background from flashing on the first frame.
  @State private contentOpacity: number = 0

  aboutToAppear(): void {
    // Initialize ViewModel with Model data
    this.viewModel.initWithSongInfo(new DeleteSongInfo(this.songTitle))
    this.viewModel.onConfirmAction = this.onConfirm
    // Fade in dialog content — the first frame renders at opacity 0 so no flash
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 1
    })
  }

  build() {
    Column() {
      // Dialog title - "从音乐库中移除"
      Text(this.viewModel.titleResource)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      // Dialog content - "从音乐库中移除 {songTitle} 吗?"
      Text(this.viewModel.getConfirmMessage())
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      // Button row - Cancel (left) and Confirm (right, blue filled)
      Row() {
        // Cancel button - gray text, light background
        Row() {
          Text(this.viewModel.cancelTextResource)
            .fontSize(15)
            .fontColor($r('app.color.salt_color_sub_text'))
        }
        .layoutWeight(1)
        .height(42)
        .borderRadius(20)
        .backgroundColor($r('app.color.salt_color_sub_background'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.viewModel.handleCancel()
          this.controller.close()
        })

        // Spacer between buttons
        Blank()
          .width(16)

        // Confirm button - filled blue
        Row() {
          Text(this.viewModel.confirmTextResource)
            .fontSize(15)
            .fontColor(Color.White)
        }
        .layoutWeight(1)
        .height(42)
        .borderRadius(20)
        .backgroundColor($r('app.color.salt_color_high_light'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.viewModel.handleConfirm()
          this.controller.close()
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }
    .opacity(this.contentOpacity)
    .backgroundColor($r('app.color.salt_color_dialog_background'))
    .borderRadius(16)
    .margin({ left: 24, right: 24 })
  }
}
