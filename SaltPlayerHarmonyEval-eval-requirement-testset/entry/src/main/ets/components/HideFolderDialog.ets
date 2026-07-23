// HideFolderDialog.ets
// View layer: Confirmation dialog for hiding a folder from the music library
// Corresponds to Android FolderMenuDialog.kt → YesNoDialog (Salt UI)
// Shows: title "隐藏文件夹", content "是否要隐藏文件夹 {path} 及其子文件夹下的所有歌曲？",
//        cancel button (gray) and confirm button (blue filled)
//
// MVVM architecture:
//   View: HideFolderDialog (this file)
//   ViewModel: FolderMenuDialogViewModel (reused)
//   Model: FolderMenuModel (reused)

@CustomDialog
export struct HideFolderDialog {
  controller: CustomDialogController
  folderPath: string = ''
  onConfirm: () => void = () => {}

  @State private contentOpacity: number = 0

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 1
    })
  }

  build() {
    Column() {
      // Dialog title - "隐藏文件夹" left-aligned, matching Android YesNoDialog title
      Text($r('app.string.hide_folder'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      // Dialog content - "是否要隐藏文件夹 {path} 及其子文件夹下的所有歌曲？"
      Text(`是否要隐藏文件夹 ${this.folderPath} 及其子文件夹下的所有歌曲？`)
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      // Button row - Cancel (left, gray) and Confirm (right, blue filled)
      Row() {
        // Cancel button - gray text, light background
        Row() {
          Text($r('app.string.cancel'))
            .fontSize(15)
            .fontColor($r('app.color.salt_color_sub_text'))
        }
        .layoutWeight(1)
        .height(42)
        .borderRadius(20)
        .backgroundColor($r('app.color.salt_color_sub_background'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.controller.close()
        })

        Blank()
          .width(16)

        // Confirm button - blue filled
        Row() {
          Text($r('app.string.confirm'))
            .fontSize(15)
            .fontColor(Color.White)
        }
        .layoutWeight(1)
        .height(42)
        .borderRadius(20)
        .backgroundColor($r('app.color.salt_color_high_light'))
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onConfirm()
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
