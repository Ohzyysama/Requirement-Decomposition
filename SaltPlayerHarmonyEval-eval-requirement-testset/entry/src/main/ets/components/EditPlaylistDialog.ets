// EditPlaylistDialog.ets
// View layer: Edit Playlist Name dialog for Salt Player
// Displayed when the user selects "Edit" on a playlist menu; lets the user
// rename the playlist and confirm. Mirrors the styling of
// NewPlaylistDialogComponent (same title/input/button layout).

@CustomDialog
export struct EditPlaylistDialog {
  controller: CustomDialogController
  // Initial playlist name (pre-filled into the TextInput)
  playlistName: string = ''
  // Fired with the new name when the user taps Confirm
  onConfirm: (newName: string) => void = (_: string) => {}

  // Local editable copy — we don't mutate the prop directly so that ArkTS
  // dataflow stays clean and the parent's @Track field is only updated via
  // the explicit onConfirm callback.
  @State private currentName: string = ''

  aboutToAppear(): void {
    this.currentName = this.playlistName
  }

  build() {
    Column() {
      // Title — "重命名歌单" (reuses existing "edit" string resource)
      Text($r('app.string.edit'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 14, right: 14, top: 7, bottom: 12 })

      // Input field pre-filled with the current playlist name
      TextInput({ text: this.currentName })
        .height(49)
        .padding({ left: 14, right: 14 })
        .margin({ left: 14, right: 14 })
        .placeholderColor($r('app.color.colorSubTextForeground'))
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .caretColor($r('app.color.salt_color_high_light'))
        .backgroundColor($r('app.color.salt_color_dialog_background'))
        .borderRadius(8)
        .onChange((value: string) => {
          this.currentName = value
        })

      // Buttons row — Cancel + Confirm side by side
      Row() {
        // Cancel button
        Button($r('app.string.cancel'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .backgroundColor($r('app.color.salt_color_dialog_background'))
          .borderRadius(21)
          .onClick(() => {
            this.controller.close()
          })

        // Spacer between buttons
        Blank()
          .width(14)

        // Confirm button
        Button($r('app.string.confirm'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(21)
          .onClick(() => {
            this.onConfirm(this.currentName)
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

// 重命名歌单：去除首尾空白后校验非空，更新歌单名并持久化。
