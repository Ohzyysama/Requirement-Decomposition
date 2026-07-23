// MiniPlayerComponent.ets
// View layer: Mini player content row (album cover + title + play/queue).
//
// This component only renders the pill's INNER content. The outer morph
// container in MainPage owns the container shape (width/height/radius/
// position/material/gesture) and drives the pill→fullscreen interpolation.
// This component therefore has no background, no border, no blur, no gesture.
// It is sized to fill its parent (width 100% / height 56) and is removed
// from the tree (via conditional rendering in MainPage) as the player opens.

import MiniPlayerViewModel from '../viewmodel/MiniPlayerViewModel'
import { MiniPlayerDefaults } from '../pages/main/MiniPlayerContainer'

@Component
export struct MiniPlayerComponent {
  @ObjectLink viewModel: MiniPlayerViewModel

  build() {
    Row() {
      // Album cover thumbnail — stays fixed.
      // Geometry note: the morph container (in MainPage) has 16vp left padding
      // from the screen at progress=0. With cover width 36 and left margin 14,
      // the cover's right edge lands at 16+14+36 = 66vp from the screen's
      // left, matching the right edge of the song-list item cover (item left
      // margin 16 + cover width 50 = 66).
      Image(this.viewModel.coverPixelMap ?? $r('app.media.ic_song_cover_v5'))
        .width(36)
        .height(36)
        .borderRadius(4)
        .margin({ left: 14, right: 12 })
        .objectFit(ImageFit.Cover)

      // Song info — swipeable middle area with prev/next hint text
      Stack() {
        // "上一首" — right-aligned, initially fully off-screen to the left
        Row() {
          Text('上一首')
            .fontSize(14)
            .fontColor($r('app.color.colorSubTextForeground'))
            .fontWeight(FontWeight.Medium)
        }
        .width(this.viewModel.middleAreaWidth)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.End)
        .padding({ right: 12 })
        .translate({ x: -this.viewModel.middleAreaWidth + this.viewModel.swipeOffsetX })

        // "下一首" — left-aligned, initially fully off-screen to the right
        Row() {
          Text('下一首')
            .fontSize(14)
            .fontColor($r('app.color.colorSubTextForeground'))
            .fontWeight(FontWeight.Medium)
        }
        .width(this.viewModel.middleAreaWidth)
        .height('100%')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 12 })
        .translate({ x: this.viewModel.middleAreaWidth + this.viewModel.swipeOffsetX })

        // Song info, translates with swipe
        Column() {
          Text(this.viewModel.getDisplayTitle())
            .fontSize(14)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(this.viewModel.getSubtitle())
            .fontSize(12)
            .fontColor($r('app.color.colorSubTextForeground'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
            .width('100%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .translate({ x: this.viewModel.swipeOffsetX })
      }
      .layoutWeight(1)
      .height('100%')
      .clip(true)
      .onAreaChange((_: Area, newArea: Area) => {
        this.viewModel.middleAreaWidth = newArea.width as number
      })

      // Play/Pause button
      Image(this.viewModel.getPlayPauseIcon())
        .width(40)
        .height(40)
        .padding(10)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          this.viewModel.togglePlayPause()
        })
        .onTouch((event: TouchEvent) => {
          event.stopPropagation()
        })
        .accessibilityText(this.viewModel.getPlayPauseAccessibilityText())

      // Queue button
      Image($r('app.media.ic_play_queue'))
        .width(48)
        .height(56)
        .padding({ left: 8, right: 16, top: 16, bottom: 16 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.handleQueueClick()
        })
        .onTouch((event: TouchEvent) => {
          event.stopPropagation()
        })
        .accessibilityText('播放队列')
    }
    .width('100%')
    .height(MiniPlayerDefaults.BAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .onTouch((event: TouchEvent) => {
      this.viewModel.handleTouchEvent(event)
      event.stopPropagation()
    })
    // Empty onClick consumes the click event so it does not pass through
    // to underlying components (e.g. song list items behind the mini player).
    .onClick(() => {})
  }
}
