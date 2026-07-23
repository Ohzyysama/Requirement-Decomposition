@CustomDialog
export struct RemoveFromPlaylistDialog {
  controller: CustomDialogController
  songTitle: string = ''
  onConfirm: () => void = () => {}
  @State private contentOpacity: number = 0

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.contentOpacity = 1
    })
  }

  build() {
    Column() {
      Text('从歌单中移除')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      Text(`从歌单中移除 ${this.songTitle} 吗?`)
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })

      Row() {
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

        Blank().width(16)

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
