// PlaylistTabComponent.ets
// View layer: Playlist list view component for Salt Player
// Corresponds to Android PlaylistScreen.kt (ui/main/playlist/PlaylistScreen.kt)
// Displays playlists in a vertical list with cover, name, and song count
// Includes: reorderable list items, popup menu for new/import playlist, item menu dialogs
//
// MVVM Architecture:
//   View: PlaylistTabComponent (this file)
//   ViewModel: PlaylistTabViewModel
//   Model: PlaylistModel

import PlaylistTabViewModel, { PlaylistItemViewModel } from '../viewmodel/PlaylistTabViewModel'
import lottie, { AnimationItem } from '@ohos/lottie'

import { EditPlaylistDialog } from './EditPlaylistDialog'
import { DeletePlaylistDialog } from './DeletePlaylistDialog'

import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'

// Per-row cover component. Playlist covers are sourced from the playlist's
// top song (most recently added) and must be lazy-loaded via CoverCacheDb —
// Track.coverUri is a raw extraction key, not an Image src, so wiring it
// directly into Image() left every row blank. Mirrors the album/artist
// cover-loading pattern (see AlbumYearListItemComponent).
@Component
struct PlaylistListCover {
  @Prop @Watch('onCoverSongIdChanged') coverSongId: string = ''
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()
  private loadedCoverKey: string = ''

  aboutToAppear(): void {
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover
    this.loadCover()
  }

  aboutToRecycle(): void {
    this.loadedCoverKey = ''
  }

  onCoverSongIdChanged(): void {
    if (this.coverSongId !== this.loadedCoverKey) {
      this.loadCover()
    }
  }

  loadCover(): void {
    const songId = this.coverSongId
    this.loadedCoverKey = songId
    if (!songId || songId.length === 0) return
    const uri = CoverCacheDb.getCoverFileUri(songId)
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri
      return
    }
    const capturedKey = songId
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (this.loadedCoverKey !== capturedKey) return
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri
        return
      }
      return CoverArtExtractor.extractAndCache(songId, songId)
    }).then(() => {
      if (this.loadedCoverKey !== capturedKey) return
      const u = CoverCacheDb.getCoverFileUri(songId)
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Stack() {
      ImageKnifeComponent({ imageKnifeOption: this.coverOption })
        .width(56)
        .height(56)
    }
    .width(56)
    .height(56)
  }
}

@Component
export struct PlaylistTabComponent {
  // ViewModel binding: the parent component passes in the ViewModel instance
  @ObjectLink viewModel: PlaylistTabViewModel

  // Playlist list scroller
  private listScroller: Scroller = new Scroller()

  // Lottie animation for empty state
  private lottieRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private lottieCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lottieRenderingSettings)
  private lottieAnimItem: AnimationItem | null = null

  // Dialog state variables
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  @State showPlaylistMenu: boolean = false
  private editDialogController?: CustomDialogController
  private deleteDialogController?: CustomDialogController

  // Drag-reorder state — mirrors PlaylistContentPage's custom-sort drag path.
  // Long-press on a row enters drag mode; subsequent pan events translate the
  // visual offset and call viewModel.movePlaylist when the finger crosses a
  // row boundary (72vp = one PlaylistItemRow height).
  @State private isDragReordering: boolean = false
  @State private dragPlaylistId: string = ''
  @State private dragConsumedOffset: number = 0
  @State private dragCurrentOffsetY: number = 0
  private dragAutoScrollTimer: number = -1
  private playlistListAreaRect: Area | null = null
  private dragAutoScrollAccum: number = 0
  private dragLastEventOffsetY: number = 0
  private static readonly ROW_HEIGHT_VP: number = 72

  aboutToDisappear() {
    lottie.destroy('lottie_empty_playlist')
    this.stopDragAutoScroll()
  }

  // ========== Drag-Reorder Helpers (parity with PlaylistContentPage) ==========
  private startDragAutoScroll(direction: number): void {
    if (this.dragAutoScrollTimer !== -1) return
    const SCROLL_SPEED = 8
    const INTERVAL = 16
    this.dragAutoScrollTimer = setInterval(() => {
      if (!this.isDragReordering) {
        this.stopDragAutoScroll()
        return
      }
      this.listScroller.scrollBy(0, direction * SCROLL_SPEED)
      this.dragAutoScrollAccum += direction * SCROLL_SPEED
      this.applyDragOffset(this.dragLastEventOffsetY)
    }, INTERVAL)
  }

  private stopDragAutoScroll(): void {
    if (this.dragAutoScrollTimer !== -1) {
      clearInterval(this.dragAutoScrollTimer)
      this.dragAutoScrollTimer = -1
    }
  }

  private applyDragOffset(eventOffsetY: number): void {
    const effectiveOffset = eventOffsetY + this.dragAutoScrollAccum
    const remaining = effectiveOffset - this.dragConsumedOffset
    const currentIndex =
      this.viewModel.playlistItems.findIndex((p: PlaylistItemViewModel) => p.id === this.dragPlaylistId)
    if (currentIndex < 0) {
      this.dragCurrentOffsetY = remaining
      return
    }
    const rowHeight = PlaylistTabComponent.ROW_HEIGHT_VP
    const steps = Math.round(remaining / rowHeight)
    if (steps !== 0) {
      const targetIndex =
        Math.max(0, Math.min(this.viewModel.playlistItems.length - 1, currentIndex + steps))
      if (targetIndex !== currentIndex) {
        this.viewModel.movePlaylist(currentIndex, targetIndex)
        this.dragConsumedOffset += (targetIndex - currentIndex) * rowHeight
      }
    }
    const maxDown = (this.viewModel.playlistItems.length - 1 - currentIndex) * rowHeight
    const maxUp = -currentIndex * rowHeight
    this.dragCurrentOffsetY = Math.max(maxUp, Math.min(maxDown,
      effectiveOffset - this.dragConsumedOffset))
  }

  private updateDragAutoScroll(fingerScreenY: number): void {
    if (!this.playlistListAreaRect) {
      this.stopDragAutoScroll()
      return
    }
    const listTop = this.playlistListAreaRect.globalPosition as Position
    const listHeight = this.playlistListAreaRect.height as number
    const EDGE_ZONE = 80
    const relativeY = fingerScreenY - (listTop.y as number ?? 0)
    if (relativeY < EDGE_ZONE) {
      if (this.dragAutoScrollTimer === -1) this.startDragAutoScroll(-1)
    } else if (relativeY > listHeight - EDGE_ZONE) {
      if (this.dragAutoScrollTimer === -1) this.startDragAutoScroll(1)
    } else {
      this.stopDragAutoScroll()
    }
  }

  private resetDragState(): void {
    this.stopDragAutoScroll()
    this.isDragReordering = false
    this.dragPlaylistId = ''
    this.dragCurrentOffsetY = 0
    this.dragConsumedOffset = 0
    this.dragAutoScrollAccum = 0
    this.dragLastEventOffsetY = 0
  }

  build() {
    Column() {
      if (this.viewModel.isEmpty()) {
        // Empty state - matches Android NoneBox()
        Column() {
          Canvas(this.lottieCanvasCtx)
            .width(100)
            .height(100)
            .opacity(0.75)
            .onReady(() => {
              this.lottieAnimItem = lottie.loadAnimation({
                container: this.lottieCanvasCtx,
                renderer: 'canvas',
                loop: true,
                autoplay: true,
                name: 'lottie_empty_playlist',
                path: 'lottie_empty.json'
              })
              if (this.lottieAnimItem) {
                this.lottieAnimItem.setSpeed(0.5)
              }
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // Playlist list - matches Android LazyColumn with PlaylistItem
        List({ scroller: this.listScroller }) {
          ForEach(this.viewModel.playlistItems, (playlist: PlaylistItemViewModel) => {
            ListItem() {
              this.PlaylistItemRow(playlist)
            }
            // Key includes name + count + coverSongId so ForEach rebuilds a row
            // when any of those change after an add/remove/rename in any surface
            // (PlaylistContentPage remove, AddToPlaylist commit, PlaylistSearchPage
            // remove, edit-playlist rename). Keying on id alone caused ArkUI to
            // reuse the existing ListItem with the old closure, so returning to
            // this tab (or renaming inline via the more-options menu) left the
            // row showing stale fields. Mirrors the same fix on
            // AddToPlaylistDialogComponent's row key.
            .translate({ y: (this.isDragReordering && playlist.id === this.dragPlaylistId) ? this.dragCurrentOffsetY : 0 })
            .scale({
              x: (this.isDragReordering && playlist.id === this.dragPlaylistId) ? 1.05 : 1,
              y: (this.isDragReordering && playlist.id === this.dragPlaylistId) ? 1.05 : 1
            })
            .opacity((this.isDragReordering && playlist.id === this.dragPlaylistId) ? 0.8 : 1)
            .zIndex((this.isDragReordering && playlist.id === this.dragPlaylistId) ? 999 : 0)
            .shadow(this.isDragReordering && playlist.id === this.dragPlaylistId
              ? { radius: 12, color: '#40000000', offsetY: 4 }
              : { radius: 0, color: '#00000000', offsetY: 0 })
            .animation({ duration: this.isDragReordering ? 0 : 200, curve: Curve.EaseOut })
            .parallelGesture(
              GestureGroup(GestureMode.Sequence,
                LongPressGesture({ repeat: false, duration: 400 })
                  .onAction(() => {
                    this.isDragReordering = true
                    this.dragPlaylistId = playlist.id
                    this.dragConsumedOffset = 0
                    this.dragCurrentOffsetY = 0
                    this.dragAutoScrollAccum = 0
                    this.dragLastEventOffsetY = 0
                  }),
                PanGesture({ direction: PanDirection.Vertical })
                  .onActionUpdate((event: GestureEvent) => {
                    if (!this.isDragReordering) return
                    this.dragLastEventOffsetY = event.offsetY
                    const finger = event.fingerList[0]
                    if (finger) {
                      this.updateDragAutoScroll(finger.globalY)
                    }
                    this.applyDragOffset(event.offsetY)
                  })
                  .onActionEnd(() => {
                    this.resetDragState()
                  })
                  .onActionCancel(() => {
                    this.resetDragState()
                  })
              )
            )
          }, (playlist: PlaylistItemViewModel) => `${playlist.id}_${playlist.name}_${playlist.count}_${playlist.coverSongId}`)
        }
        .width('100%')
        .layoutWeight(1)
        .contentEndOffset(96)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .padding({ top: 1 })
        .enableScrollInteraction(!this.isDragReordering)
        .onAreaChange((_: Area, newArea: Area) => {
          this.playlistListAreaRect = newArea
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ======================== Playlist Item Row ========================
  // Matches Android PlaylistItem: Row with cover(56dp) + Column(name + count) + more_vert icon
  @Builder
  PlaylistItemRow(playlist: PlaylistItemViewModel) {
    Row() {
      // Playlist cover — lazy-loaded via CoverCacheDb keyed by the top song's
      // id. Shows the default placeholder until the cover JPEG is ensured.
      Stack() {
        PlaylistListCover({ coverSongId: playlist.coverSongId })
      }
      .width(56)
      .height(56)
      .margin({ left: 16 })
      .borderRadius(5)
      .clip(true)

      // Name and count column
      Column() {
        Text(playlist.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(playlist.getSongCountText())
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .margin({ top: 1 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      // More options button
      Image($r('app.media.ic_more_vert'))
        .width(56)
        .height(56)
        .padding(18)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.openPlaylistMenu(playlist)
          this.showPlaylistMenu = true
        })
    }
    .width('100%')
    .height(72)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.viewModel.handlePlaylistClick(playlist.id)
    })
    // Playlist item menu dialog
    .bindSheet(this.showPlaylistMenu && this.viewModel.menuTargetPlaylist.id === playlist.id,
      this.playlistMenuBuilder(), {
        detents: ['60%', SheetSize.LARGE],
        dragBar: false,
        showClose: false,
        backgroundColor: this.isSystemDark ? $r('app.color.salt_color_dialog_background') : $r('app.color.salt_color_sub_background'),
        onDisappear: () => {
          this.showPlaylistMenu = false
          this.viewModel.closePlaylistMenu()
        }
      })
  }

  // ======================== Playlist Menu Dialog Builder ========================
  @Builder
  playlistMenuBuilder() {
    Column() {
      // Dialog title - playlist name
      Text(this.viewModel.menuTargetPlaylist.name)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      // Menu items in rounded column
      Column() {
        // Edit name
        this.PlaylistMenuItemRow($r('app.media.ic_edit'), $r('app.string.edit'), () => {
          this.showPlaylistMenu = false
          this.viewModel.openEditDialog()
          setTimeout(() => {
            this.openEditDialog()
          }, 100)
        })

        // Export (.txt)
        this.PlaylistMenuItemRow($r('app.media.ic_file_download'), $r('app.string.export_txt'), () => {
          this.showPlaylistMenu = false
          this.viewModel.handleExport()
        })

        // Delete playlist
        this.PlaylistMenuItemRow($r('app.media.ic_delete_forever'), $r('app.string.delete_playlist'), () => {
          this.showPlaylistMenu = false
          this.viewModel.openDeleteDialog()
          setTimeout(() => {
            this.openDeleteDialog()
          }, 100)
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorPageBackground'))
      .clip(true)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  // ======================== Playlist Menu Item ========================
  @Builder
  PlaylistMenuItemRow(icon: Resource, text: ResourceStr, onClick: () => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)

      Text(text)
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16 })
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick()
    })
  }

  // ======================== Open Edit Dialog ========================
  private openEditDialog(): void {
    this.editDialogController = new CustomDialogController({
      builder: EditPlaylistDialog({
        controller: this.editDialogController as CustomDialogController,
        playlistName: this.viewModel.editPlaylistName,
        onConfirm: (newName: string) => {
          this.viewModel.updateEditPlaylistName(newName)
          this.viewModel.handleConfirmEdit()
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: '#80000000',
      openAnimation: { duration: 0 },
      closeAnimation: { duration: 0 }
    })
    this.editDialogController.open()
  }

  // ======================== Open Delete Dialog ========================
  private openDeleteDialog(): void {
    this.deleteDialogController = new CustomDialogController({
      builder: DeletePlaylistDialog({
        controller: this.deleteDialogController as CustomDialogController,
        playlistName: this.viewModel.menuTargetPlaylist.name,
        onConfirm: () => {
          this.viewModel.handleConfirmDelete()
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      maskColor: '#80000000',
      openAnimation: { duration: 0 },
      closeAnimation: { duration: 0 }
    })
    this.deleteDialogController.open()
  }
}
