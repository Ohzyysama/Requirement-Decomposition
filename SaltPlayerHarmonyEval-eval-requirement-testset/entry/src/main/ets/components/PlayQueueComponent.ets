// PlayQueueComponent.ets
// View layer: Play queue panel that slides up from the player screen
// Corresponds to Android PlayQueueUI in PlayerNormalUI.kt
// Shows: drag-to-dismiss handle, current song info, queue count, song list, play mode chip
// Includes ClearPlayQueueDialog (YesNoDialog) triggered by "清除" button
//
// MVVM: This View uses PlayQueueViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating business logic to the ViewModel.

import { ClearPlayQueueDialog } from './ClearPlayQueueDialog'
import PlayQueueViewModel, { QueueSongItemViewModel } from '../viewmodel/PlayQueueViewModel'

@Component
export struct PlayQueueComponent {
  // ViewModel instance provided by the parent component (PlayerPage)
  @ObjectLink viewModel: PlayQueueViewModel

  // Spec18: custom player-screen wallpaper path. When non-empty the queue
  // background must stay transparent so the wallpaper rendered in PlayerPage's
  // outer Stack (below the inner pager) shows through both player and queue.
  @StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''

  private listScroller: Scroller = new Scroller()

  aboutToAppear(): void {
    // Wire up the scroll-to-current-song callback so the parent can trigger it
    this.viewModel.onScrollToCurrentSongAction = () => {
      const index = this.viewModel.getCurrentSongIndex()
      if (index >= 0) {
        try {
          this.listScroller.scrollToIndex(index, false, ScrollAlign.START)
        } catch (_e) {
          // ignore if scroller not yet attached
        }
      }
    }
  }

  // Clear play queue confirmation dialog controller
  // View uses ViewModel's clearDialogViewModel to manage dialog data and logic
  private clearQueueDialogController: CustomDialogController = new CustomDialogController({
    builder: ClearPlayQueueDialog({
      viewModel: this.viewModel.clearDialogViewModel
    }),
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  // Get queue page background — transparent when a custom wallpaper is set
  // (spec18) or when flowing light is active so the parent's background Stack
  // (wallpaper Image or FlowingLightComponent) shows through; themed solid
  // color otherwise.
  private getQueueBackground(): ResourceColor {
    if (this.playerScreenBgCover.length > 0) {
      return Color.Transparent
    }
    if (this.viewModel.flowingLightActive) {
      return Color.Transparent
    }
    if (!this.viewModel.isLightMode) {
      return '#ff1a1a1a'
    }
    return $r('app.color.colorPageBackground')
  }

  // Get foreground color — use flowing light color, dark mode white, or resource color
  private getIconForeground(): ResourceColor {
    if (this.viewModel.flowingLightActive && this.viewModel.foregroundColor.length > 0) {
      return this.viewModel.foregroundColor
    }
    // When no cover art but dark mode is active, use white text
    if (!this.viewModel.isLightMode) {
      return '#ffffffff'
    }
    return $r('app.color.salt_color_icon_foreground')
  }

  private getSubTextForeground(): ResourceColor {
    if (this.viewModel.flowingLightActive && this.viewModel.foregroundColor.length > 0) {
      return this.viewModel.foregroundColor
    }
    // When no cover art but dark mode is active, use white text
    if (!this.viewModel.isLightMode) {
      return '#ffffffff'
    }
    return $r('app.color.colorSubTextForeground')
  }

  build() {
    Column() {
      // ==================== Top drag-to-dismiss area ====================
      Column() {
        // Hint text "Swipe down to return to player"
        Text('此处向下轻扫以返回播放界面')
          .fontSize(12)
          .fontColor(this.getSubTextForeground())
          .opacity(0.5)
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 10, bottom: 16 })

        // Current song info row
        Row() {
          // Album cover thumbnail
          Image(this.viewModel.coverPixelMap ?? $r('app.media.ic_song_cover_v5'))
            .width(42)
            .height(42)
            .borderRadius(4)
            .objectFit(ImageFit.Cover)

          // Song title and subtitle
          Column() {
            Text(this.viewModel.currentSongTitle)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.getIconForeground())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.viewModel.getCurrentSongSubtitle())
              .fontSize(13)
              .fontColor(this.getSubTextForeground())
              .opacity(0.5)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .margin({ left: 12 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 26, right: 26 })

        // Queue header: index | title "播放队列" | clear button
        // `0/0` index and "清除" use only the secondary text color here — no
        // additional `.opacity(0.5)` on top. The sub-text color is already
        // designed as a WCAG-compliant secondary token; halving its alpha
        // dropped contrast to ~1.67:1 in the empty-queue state, which the
        // Huawei AppGallery audit flagged as below the 3:1 minimum.
        Row() {
          Text(this.viewModel.queueIndex)
            .fontSize(13)
            .fontColor(this.getSubTextForeground())

          Blank()

          Text($r('app.string.play_queue'))
            .fontSize(18)
            .fontColor(this.getIconForeground())

          Blank()

          Text('清除')
            .fontSize(14)
            .fontColor(this.getSubTextForeground())
            .onClick(() => {
              this.clearQueueDialogController.open()
            })
        }
        .width('100%')
        .padding({ left: 26, right: 26, top: 16, bottom: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .onClick(() => {
        this.viewModel.handleDismiss()
      })

      // Divider
      Divider()
        .color(this.viewModel.isLightMode
          ? (this.viewModel.flowingLightActive ? '#20000000' : $r('app.color.salt_color_cutting_line'))
          : '#20ffffff')
        .width('85%')
        .height(0.5)

      // ==================== Queue Song List ====================
      // Use LazyForEach so only visible items are realized — clearing or
      // rebuilding a 1000+ song queue no longer destroys N ListItems.
      List({ scroller: this.listScroller }) {
        LazyForEach(this.viewModel.songs, (song: QueueSongItemViewModel) => {
          ListItem() {
            this.QueueSongItem(song)
          }
          .transition(TransitionEffect.OPACITY.combine(
            TransitionEffect.translate({ y: -20 }).animation({ duration: 250, curve: Curve.EaseOut })))
        }, (song: QueueSongItemViewModel) => song.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ top: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .enableScrollInteraction(!this.viewModel.pagerDragging)
      .onReachStart(() => {
        this.viewModel.handleListAtTop(true)
      })
      .onDidScroll(() => {
        // After clearing a long queue, the List takes time to tear down its
        // virtualized items while the scroller still reports the previous
        // yOffset. Without this guard, residual onDidScroll calls would
        // repeatedly mark the (now empty) list as "not at top", blocking the
        // swipe-down dismiss until the framework finally settles.
        if (this.viewModel.songs.totalCount() === 0) {
          this.viewModel.handleListAtTop(true)
          return
        }
        const offset = this.listScroller.currentOffset()
        if (offset.yOffset > 0) {
          this.viewModel.handleListAtTop(false)
        }
      })
      .onTouch((event: TouchEvent) => {
        // Empty list: treat touches as outside the list so the parent pager's
        // swipe-down dismiss gate isn't gated by isTouchInQueueList.
        if (this.viewModel.songs.totalCount() === 0) {
          this.viewModel.handleListTouch(false)
          return
        }
        if (event.type === TouchType.Down) {
          this.viewModel.handleListTouch(true)
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.viewModel.handleListTouch(false)
        }
      })

      // ==================== Bottom Divider ====================
      Divider()
        .color(this.viewModel.isLightMode
          ? (this.viewModel.flowingLightActive ? '#20000000' : $r('app.color.salt_color_cutting_line'))
          : '#20ffffff')
        .width('85%')
        .height(0.5)

      // ==================== Play Mode Chip (bottom) ====================
      Row() {
        this.PlayModeChip()
      }
      .width('100%')
      .padding({ left: 26, right: 26, top: 16, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getQueueBackground())
  }

  @Builder
  QueueSongItem(song: QueueSongItemViewModel) {
    Row() {
      // Song info
      Column() {
        Text(song.title)
          .fontSize(15)
          .fontWeight(FontWeight.Normal)
          .fontColor(this.getIconForeground())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(song.artist + (song.album ? ' - ' + song.album : ''))
          .fontSize(12)
          .fontColor(this.getSubTextForeground())
          .opacity(0.5)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      // Remove from queue button
      Column() {
        Image($r('app.media.ic_remove'))
          .width(21)
          .height(21)
          .fillColor(this.getSubTextForeground())
          .objectFit(ImageFit.Contain)
      }
      .width(42)
      .height(42)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.viewModel.handleRemoveSong(song.id)
      })
      .accessibilityText('从播放队列中移除')
    }
    .padding({ left: 12, right: 8, top: 10, bottom: 10 })
    .margin({ left: 16, right: 16 })
    .borderRadius(12)
    .backgroundColor(this.viewModel.shouldHighlightSong(song.id) ?
      (this.viewModel.isLightMode
        ? (this.viewModel.flowingLightActive ? '#15000000' : $r('app.color.salt_color_sub_background'))
        : '#15ffffff')
      : Color.Transparent)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.viewModel.handleSongPress(song.id)
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.viewModel.handleSongRelease()
      }
    })
    .onClick(() => {
      this.viewModel.handleSongClick(song.id)
    })
  }

  @Builder
  PlayModeChip() {
    Row() {
      Text(this.viewModel.getPlayModeText())
        .fontSize(13)
        .fontColor(this.getIconForeground())
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(16)
    .backgroundColor(this.viewModel.isLightMode
      ? (this.viewModel.flowingLightActive ? '#15000000' : $r('app.color.salt_color_sub_background'))
      : '#15ffffff')
    .onClick(() => {
      this.viewModel.handlePlayModeClick()
    })
  }
}

// 播放队列：展示当前队列，支持点击播放、单项移除与清空队列。
