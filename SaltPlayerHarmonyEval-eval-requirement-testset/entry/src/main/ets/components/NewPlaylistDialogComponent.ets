// NewPlaylistDialogComponent.ets
// View layer: New Playlist dialog UI component for Salt Player
// Uses NewPlaylistDialogViewModel for state and logic per MVVM architecture
// Corresponds to Android NewPlaylistDialog.kt (ui/main/playlist/NewPlaylistDialog.kt)

import NewPlaylistDialogViewModel from '../viewmodel/NewPlaylistDialogViewModel'

@CustomDialog
export struct NewPlaylistDialogComponent {
  // Dialog controller - required for CustomDialog
  controller: CustomDialogController

  // ViewModel instance - provides data and handles logic
  // The parent component initializes this with appropriate callbacks
  @State viewModel: NewPlaylistDialogViewModel = new NewPlaylistDialogViewModel()

  // Callback when confirm is pressed with a valid name
  onConfirm: (name: string) => void = () => {}

  // Callback when cancel is pressed or dialog is dismissed
  onCancel: () => void = () => {}

  aboutToAppear(): void {
    // Wire up callbacks from parent to ViewModel
    this.viewModel = new NewPlaylistDialogViewModel(this.onConfirm, this.onCancel)
  }

  build() {
    Column() {
      // Title - "新建歌单"
      Text(this.viewModel.titleResource)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 14, right: 14, top: 7, bottom: 12 })

      // Input field - playlist name
      TextInput({ text: this.viewModel.playlistName, placeholder: this.viewModel.placeholderResource })
        .height(49)
        .padding({ left: 14, right: 14 })
        .margin({ left: 14, right: 14 })
        .placeholderColor($r('app.color.colorSubTextForeground'))
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .caretColor($r('app.color.salt_color_high_light'))
        .backgroundColor($r('app.color.salt_color_dialog_background'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.viewModel.updatePlaylistName(value)
        })

      // Buttons row - cancel + confirm side by side
      Row() {
        // Cancel button
        Button(this.viewModel.cancelTextResource)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .backgroundColor($r('app.color.salt_color_dialog_background'))
          .borderRadius(21)
          .onClick(() => {
            this.viewModel.handleCancel()
            this.controller.close()
          })

        // Spacer between buttons
        Blank()
          .width(14)

        // Confirm button
        Button(this.viewModel.confirmTextResource)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(21)
          .onClick(() => {
            // Always invoke the host callback — empty / too-long names must
            // still emit their toast (host handles validation). Dialog closes
            // unconditionally so the UI doesn't appear stuck on invalid input.
            this.viewModel.handleConfirm()
            this.controller.close()
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 20, bottom: 14 })
    }
    .width('86%')
    .padding({ top: 7 })
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_sub_background'))
  }
}

// 创建歌单：输入框内容去除首尾空白后若为空则禁用「创建」按钮，避免生成空名歌单。
