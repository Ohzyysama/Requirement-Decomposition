// DeleteWallpaperDialog.ets
// View layer: Confirmation dialog for deleting the current main-screen wallpaper.
// Styled after DeletePlaylistDialog: title + body sentence + Cancel/Confirm row.
// Pure presentational — no state, no persistence, no AppStorage reads.

@CustomDialog
export struct DeleteWallpaperDialog {
  controller: CustomDialogController
  // Fired when the user taps Confirm
  onConfirm: () => void = () => {}

  // Start fully transparent; animate to opaque in aboutToAppear to prevent
  // the cancel button's light background from flashing on the first frame.
  @State private contentOpacity: number = 0

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 1
    })
  }

  build() {
    Column() {
      // Dialog title — reuses "delete_current_image" string
      Text($r('app.string.delete_current_image'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      // Body sentence — reuse same string to avoid introducing a new resource
      Text($r('app.string.delete_current_image'))
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      // Button row — Cancel (left) and Confirm (right, blue filled)
      Row() {
        // Cancel button
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

        // Spacer between buttons
        Blank()
          .width(16)

        // Confirm button — filled blue
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
