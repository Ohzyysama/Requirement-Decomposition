// PlaylistSearchPage.ets
// View layer: In-playlist search surface (spec7).
// Opened from PlaylistContentPage's 搜索 icon. Filters the current playlist's
// songs by a keyword and exposes the same per-row + multi-select operations
// as playlist detail (随机播放 / 排序 / 多选 / 从此歌单中移除 / 添加到歌单 / …).
//
// MVVM: delegates all state + business logic to PlaylistSearchViewModel.
// Re-reads the playlist snapshot from the DB so concurrent add (S2) and
// remove (S3) mutations — whether originating here or elsewhere — are always
// reflected via the shared 'playlistVersion' AppStorage bus.

import lottie, { AnimationItem } from '@ohos/lottie'
import { SongItemComponent, SongInfo } from '../components/SongItemComponent'
import { SongMenuDialogComponent } from '../components/SongMenuDialogComponent'
import { SongSortDialogComponent } from '../components/SongSortDialogComponent'
import { AddToPlaylistDialogComponent } from '../components/AddToPlaylistDialogComponent'
import { DeleteSongDialog } from '../components/DeleteSongDialog'
import { RemoveFromPlaylistDialog } from '../components/RemoveFromPlaylistDialog'
import { BasicScreen } from '../components/BasicScreen'
import { SongLazySort } from '../model/SongSortModel'
import { SongInfoData } from '../model/SongItemModel'
import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import PlaylistSearchViewModel, { PlaylistSearchRouterParams } from '../viewmodel/PlaylistSearchViewModel'
import { SongInformationComponent } from './SongInformationPage'
import { AlbumContentRouterParams } from '../model/AlbumContentModel'
import { MainPageDataSource } from '../model/MainPageModel'
import { ArtistContentRouterParams } from './ArtistContentRouterParams'
import { shareSongFile } from '../model/ShareUtil'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

export { PlaylistSearchRouterParams } from '../viewmodel/PlaylistSearchViewModel'

@Component
export struct PlaylistSearchPage {
  @State viewModel: PlaylistSearchViewModel = new PlaylistSearchViewModel()
  @State showSongMenuDialog: boolean = false
  @State showSortDialog: boolean = false
  @State showSongInfo: boolean = false

  @StorageProp('currentSongId') @Watch('onCurrentSongChanged') storedCurrentSongId: string = ''
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  // Refresh when any sibling surface bumps playlistVersion (S2/S3 live).
  @StorageProp('playlistVersion') @Watch('onPlaylistVersionChanged') playlistVersion: number = 0
  // Bridge the persisted "show cover in song list" preference into the VM
  // so mounted lists re-render live when the user toggles it from
  // Settings → UI. Default `true` matches the value seeded in EntryAbility.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')
  storedDisplaySongCover: boolean = true
  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" preference into the
  // VM so the in-playlist search result list re-renders live when the user
  // toggles it from Settings → UI → 歌曲列表.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  storedDisplaySongFileName: boolean = false
  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" preference into the
  // VM so the in-playlist search result list re-renders live when the user
  // toggles it from Settings → UI → 歌曲列表.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  storedDisplayAddToPlayNext: boolean = true

  private textInputController: TextInputController = new TextInputController()
  private navPathStack: NavPathStack = new NavPathStack()
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController
  private removeFromPlaylistDialogController?: CustomDialogController
  private listScroller: Scroller = new Scroller()

  // Custom-sort drag-reorder state — mirrors PlaylistContentPage / MainPage.
  // Active only when viewModel.songLazySort === SongLazySort.NONE (custom sort).
  @State private isDragReordering: boolean = false
  @State private dragSongId: string = ''
  @State private dragConsumedOffset: number = 0
  @State private dragCurrentOffsetY: number = 0
  private dragAutoScrollTimer: number = -1
  private songListAreaRect: Area | null = null
  private dragAutoScrollAccum: number = 0
  private dragLastEventOffsetY: number = 0
  private static readonly ROW_HEIGHT_VP: number = 72

  // Lottie empty-state
  private lottieRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private lottieCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lottieRenderingSettings)
  private lottieAnimItem: AnimationItem | null = null

  aboutToDisappear(): void {
    lottie.destroy(this.viewModel.LOTTIE_ANIM_NAME)
  }

  onCurrentSongChanged(): void {
    this.viewModel.currentSongId = this.storedCurrentSongId
  }

  onPlaylistVersionChanged(): void {
    this.viewModel.refreshFromDb()
  }

  // Forward AppStorage 'displaySongCover' writes into the VM so the song
  // list refreshes live when the user toggles the setting from Settings → UI.
  onDisplaySongCoverChanged(): void {
    this.viewModel.setDisplaySongCoverInList(this.storedDisplaySongCover)
  }

  // spec21 — Forward AppStorage 'displaySongFileName' writes into the VM.
  onDisplaySongFileNameChanged(): void {
    this.viewModel.setDisplaySongFileNameInList(this.storedDisplaySongFileName)
  }

  // spec22 — Forward AppStorage 'displayAddToPlayNext' writes into the VM.
  onDisplayAddToPlayNextChanged(): void {
    this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
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
      this.viewModel.searchResults.findIndex((s: SongInfoData) => s.id === this.dragSongId)
    if (currentIndex < 0) {
      this.dragCurrentOffsetY = remaining
      return
    }
    const rowHeight = PlaylistSearchPage.ROW_HEIGHT_VP
    const steps = Math.round(remaining / rowHeight)
    if (steps !== 0) {
      const targetIndex =
        Math.max(0, Math.min(this.viewModel.searchResults.length - 1, currentIndex + steps))
      if (targetIndex !== currentIndex) {
        this.viewModel.moveSongInResults(currentIndex, targetIndex)
        this.dragConsumedOffset += (targetIndex - currentIndex) * rowHeight
      }
    }
    const maxDown = (this.viewModel.searchResults.length - 1 - currentIndex) * rowHeight
    const maxUp = -currentIndex * rowHeight
    this.dragCurrentOffsetY = Math.max(maxUp, Math.min(maxDown,
      effectiveOffset - this.dragConsumedOffset))
  }

  private updateDragAutoScroll(fingerScreenY: number): void {
    if (!this.songListAreaRect) {
      this.stopDragAutoScroll()
      return
    }
    const listTop = this.songListAreaRect.globalPosition as Position
    const listHeight = this.songListAreaRect.height as number
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
    this.dragSongId = ''
    this.dragCurrentOffsetY = 0
    this.dragConsumedOffset = 0
    this.dragAutoScrollAccum = 0
    this.dragLastEventOffsetY = 0
  }

  build() {
    NavDestination() {
      BasicScreen() {
        Column() {
          this.SearchTitleBar()

          if (!this.viewModel.hasResults) {
            this.NoneBox()
          } else {
            if (this.viewModel.multiChoiceMode) {
              this.MultiChoiceTopBar()
            } else {
              this.ToolbarRow()
            }

            List({ scroller: this.listScroller }) {
              ForEach(this.viewModel.searchResults, (song: SongInfoData) => {
                ListItem() {
                  SongItemComponent({
                    viewModel: SongItemViewModel.create(song as SongInfo, {
                      isCurrent: this.viewModel.isSongCurrent(song.id),
                      showCover: this.viewModel.displaySongCoverInList,
                      displayFileName: this.viewModel.displaySongFileNameInList,
                      showTrackNumber: false,
                      displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,
                      multiChoiceMode: this.viewModel.multiChoiceMode,
                      checked: this.viewModel.isChecked(song.id),
                      onItemClickAction: () => {
                        if (this.viewModel.multiChoiceMode) {
                          this.viewModel.setChecked(song.id, !this.viewModel.isChecked(song.id))
                        } else {
                          this.viewModel.playSong(song)
                        }
                      },
                      onItemLongClickAction: () => {
                        // Custom sort mode consumes long-press as drag — skip menu.
                        if (this.viewModel.songLazySort === SongLazySort.NONE) return
                        this.viewModel.openSongMenu(song)
                        this.showSongMenuDialog = true
                      },
                      onMenuClickAction: () => {
                        this.viewModel.openSongMenu(song)
                        this.showSongMenuDialog = true
                      },
                      onAddToPlayNextAction: () => {
                        this.viewModel.addToPlayNext(song)
                      },
                      onCheckedChangeAction: (checked: boolean) => {
                        this.viewModel.setChecked(song.id, checked)
                      }
                    })
                  })
                }
                .translate({ y: (this.isDragReordering && song.id === this.dragSongId) ? this.dragCurrentOffsetY : 0 })
                .scale({
                  x: (this.isDragReordering && song.id === this.dragSongId) ? 1.05 : 1,
                  y: (this.isDragReordering && song.id === this.dragSongId) ? 1.05 : 1
                })
                .opacity((this.isDragReordering && song.id === this.dragSongId) ? 0.8 : 1)
                .zIndex((this.isDragReordering && song.id === this.dragSongId) ? 999 : 0)
                .shadow(this.isDragReordering && song.id === this.dragSongId
                  ? { radius: 12, color: '#40000000', offsetY: 4 }
                  : { radius: 0, color: '#00000000', offsetY: 0 })
                .animation({ duration: this.isDragReordering ? 0 : 200, curve: Curve.EaseOut })
                .parallelGesture(
                  GestureGroup(GestureMode.Sequence,
                    LongPressGesture({ repeat: false, duration: 400 })
                      .onAction(() => {
                        if (this.viewModel.songLazySort !== SongLazySort.NONE ||
                          this.viewModel.multiChoiceMode) {
                          return
                        }
                        this.isDragReordering = true
                        this.dragSongId = song.id
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
              }, (song: SongInfoData) => song.id)
            }
            .width('100%')
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .enableScrollInteraction(!this.isDragReordering)
            .onAreaChange((_: Area, newArea: Area) => {
              this.songListAreaRect = newArea
            })

            if (this.viewModel.multiChoiceMode) {
              this.MultiChoiceBottomBar()
            }
          }
        }
        .width('100%')
        .height('100%')
        .bindSheet($$this.showSongMenuDialog, this.songSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
          preferType: SheetType.BOTTOM,
          showClose: false,
          dragBar: false,
          backgroundColor: this.showSongInfo ? $r('app.color.colorPageBackground')
            : (this.isSystemDark ? $r('app.color.colorItemBackground') :
              $r('app.color.salt_color_sub_background')),
          onDisappear: () => {
            this.showSongInfo = false
            this.viewModel.closeSongMenu()
          }
        })
      }
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      if (this.viewModel.multiChoiceMode) {
        this.viewModel.exitMultiChoiceMode()
        return true
      }
      const isPlayerOpen = AppStorage.get<boolean>('showPlayerOverlay') ?? false
      if (isPlayerOpen) {
        const t = (AppStorage.get<number>('closePlayerTrigger') ?? 0) + 1
        AppStorage.setOrCreate('closePlayerTrigger', t)
        return true
      }
      return false
    })
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      const params = context.pathInfo.param as PlaylistSearchRouterParams | undefined
      if (params) {
        this.viewModel.initFromParams(params)
        this.viewModel.loadPlaylistSnapshot()
      }
    })
  }

  // ======================== Search Title Bar ========================
  @Builder
  SearchTitleBar() {
    Row() {
      Row() {
        Image($r('app.media.ic_search'))
          .width(36)
          .height(36)
          .padding(9)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .opacity(0.5)
          .margin({ left: 4 })

        TextInput({
          text: this.viewModel.keyword,
          placeholder: this.viewModel.getSearchPlaceholder(),
          controller: this.textInputController
        })
          .layoutWeight(1)
          .height(36)
          .backgroundColor(Color.Transparent)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .placeholderColor($r('app.color.colorSubTextForeground'))
          .placeholderFont({ size: 13, weight: FontWeight.Bold })
          .caretColor($r('app.color.salt_color_high_light'))
          .padding({ left: 0, right: 0 })
          .borderRadius(0)
          .onChange((value: string) => {
            this.viewModel.performSearch(value)
          })
          .defaultFocus(true)

        Image($r('app.media.ic_cancel'))
          .width(36)
          .height(36)
          .padding(8)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .onClick(() => {
            this.viewModel.clearSearch()
            this.textInputController.caretPosition(0)
          })
          .accessibilityText($r('app.string.clear'))
      }
      .layoutWeight(1)
      .height(36)
      .borderRadius(18)
      .backgroundColor($r('app.color.salt_color_sub_background'))
      .margin({ left: 16 })
      .alignItems(VerticalAlign.Center)
      .clip(true)

      Text($r('app.string.cancel'))
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_high_light'))
        .padding({ left: 16, right: 16 })
        .height('100%')
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.navPathStack.pop()
        })
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
  }

  // ======================== Empty State ========================
  @Builder
  NoneBox() {
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
            name: this.viewModel.LOTTIE_ANIM_NAME,
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
  }

  // ======================== Toolbar (shuffle / count / sort / multi-choice) ========================
  @Builder
  ToolbarRow() {
    Row() {
      Row() {
        Image($r('app.media.ic_player_random'))
          .width(40)
          .height(40)
          .padding(10)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .objectFit(ImageFit.Contain)

        Text(this.viewModel.getSongCountText())
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ left: 6 })
      }
      .height(40)
      .padding({ left: 8, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.viewModel.shufflePlayResults()
      })

      Blank()
        .layoutWeight(1)
        .height(40)

      Image($r('app.media.ic_sort'))
        .width(48)
        .height(40)
        .padding({ left: 18, right: 10, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.showSortDialog = true
        })
        .accessibilityText('排序')
        .bindSheet($$this.showSortDialog, this.sortDialogBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: false,
          showClose: false,
          backgroundColor: this.isSystemDark ? $r('app.color.colorPageBackground') :
            $r('app.color.salt_color_sub_background'),
          onDisappear: () => {
            this.showSortDialog = false
          }
        })

      Image($r('app.media.ic_multiple_choice'))
        .width(48)
        .height(40)
        .padding({ left: 9, right: 17, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.enterMultiChoiceMode()
        })
        .accessibilityText('多选')
    }
    .width('100%')
    .height(40)
  }

  // ======================== Multi-choice Top Bar ========================
  @Builder
  MultiChoiceTopBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.viewModel.getSelectAllLabel())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_high_light'))
        .position({ x: 16, y: 0 })
        .height(40)
        .onClick(() => {
          this.viewModel.toggleSelectAll()
        })

      Text(this.viewModel.getCheckedCountText())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))

      Image($r('app.media.ic_cancel'))
        .width(48)
        .height(40)
        .padding({ left: 9, right: 17, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .position({ x: '100%', y: 0 })
        .translate({ x: -48 })
        .onClick(() => {
          this.viewModel.exitMultiChoiceMode()
        })
    }
    .width('100%')
    .height(40)
  }

  // ======================== Multi-choice Bottom Bar ========================
  @Builder
  MultiChoiceBottomBar() {
    Row() {
      this.MultiChoiceControlItem($r('app.media.ic_remove'), '从音乐库中移除', () => {
        this.deleteSongDialogController = new CustomDialogController({
          builder: DeleteSongDialog({
            controller: this.deleteSongDialogController as CustomDialogController,
            songTitle: `${this.viewModel.checkedCount()} 首歌曲`,
            onConfirm: async () => {
              await this.viewModel.removeCheckedFromLibrary()
              this.viewModel.exitMultiChoiceMode()
            }
          }),
          alignment: DialogAlignment.Center,
          customStyle: true,
          maskColor: '#80000000',
          openAnimation: { duration: 0 },
          closeAnimation: { duration: 0 }
        })
        this.deleteSongDialogController.open()
      })

      this.MultiChoiceControlItem($r('app.media.ic_delete_forever'), '从歌单中删除', () => {
        this.removeFromPlaylistDialogController = new CustomDialogController({
          builder: RemoveFromPlaylistDialog({
            controller: this.removeFromPlaylistDialogController as CustomDialogController,
            songTitle: `${this.viewModel.checkedCount()} 首歌曲`,
            onConfirm: () => {
              this.viewModel.removeCheckedFromPlaylist()
              this.viewModel.exitMultiChoiceMode()
            }
          }),
          alignment: DialogAlignment.Center,
          customStyle: true,
          maskColor: '#80000000',
          openAnimation: { duration: 0 },
          closeAnimation: { duration: 0 }
        })
        this.removeFromPlaylistDialogController.open()
      })

      this.MultiChoiceControlItem($r('app.media.ic_add'), '添加到歌单', () => {
        setTimeout(() => {
          this.addToPlaylistDialogController = new CustomDialogController({
            builder: AddToPlaylistDialogComponent({
              songId: '',
              selectedSongIds: this.viewModel.getSelectedSongIdsInOrder(),
              onPlaylistSelected: (_playlistId: string, _playlistName: string) => {
                promptAction.showToast({
                  message: $r('app.string.successfully_added_to_playlist')
                })
                this.viewModel.exitMultiChoiceMode()
              },
              // Self-close bridge — the dialog's auto-wired `this.controller`
              // resolves undefined inside its deferred close path, so the
              // host closes via its own controller reference instead.
              onDismiss: () => {
                this.addToPlaylistDialogController?.close()
              }
            }),
            alignment: DialogAlignment.Center,
            customStyle: true,
            maskColor: '#80000000',
            openAnimation: { duration: 0 },
            closeAnimation: { duration: 0 }
          })
          this.addToPlaylistDialogController.open()
        }, 50)
      })

      this.MultiChoiceControlItem($r('app.media.ic_playlist_add_24'), '播放选中队列', () => {
        this.viewModel.playSelectedQueue()
        this.viewModel.exitMultiChoiceMode()
      })
    }
    .width('100%')
    .height(56)
    .backgroundColor($r('app.color.salt_color_on_page_background'))
    .margin({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
  }

  private isMultiChoiceActionEnabled(): boolean {
    return this.viewModel.checkedCount() > 0
  }

  @Builder
  MultiChoiceControlItem(icon: Resource, label: string, onClick: () => void) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.isMultiChoiceActionEnabled() ?
          $r('app.color.salt_color_high_light') : $r('app.color.colorSubTextForeground'))

      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.colorSubTextForeground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .opacity(this.isMultiChoiceActionEnabled() ? 1.0 : 0.5)
    .onClick(() => {
      if (this.isMultiChoiceActionEnabled()) {
        onClick()
      }
    })
  }

  // ======================== Sort Dialog ========================
  @Builder
  sortDialogBuilder() {
    SongSortDialogComponent({
      songLazySort: this.viewModel.songLazySort,
      customizable: true,
      showPlaylistAddTime: true,
      displaySongCoverInList: this.viewModel.displaySongCoverInList,
      displaySongFileNameInList: this.viewModel.displaySongFileNameInList,
      displayAddToPlayNextInList: this.viewModel.displayAddToPlayNextInList,
      onSortClick: (sort: number) => {
        this.viewModel.changeSortType(sort)
        this.showSortDialog = false
      },
      onDisplaySettingChange: (key: string, value: boolean) => {
        this.viewModel.updateDisplaySetting(key, value)
      }
    })
  }

  // ======================== Song Sheet Builder ========================
  @Builder
  songSheetBuilder() {
    if (this.showSongInfo && this.viewModel.menuTargetSong) {
      SongInformationComponent({ songInfo: this.viewModel.menuTargetSong as SongInfo })
    } else if (this.viewModel.menuTargetSong) {
      SongMenuDialogComponent({
        songInfo: this.viewModel.menuTargetSong as SongInfo,
        onDismiss: () => {
          this.showSongMenuDialog = false
        },
        onAddToPlaylist: () => {
          const targetSong = this.viewModel.menuTargetSong
          if (!targetSong) return
          setTimeout(() => {
            this.addToPlaylistDialogController = new CustomDialogController({
              builder: AddToPlaylistDialogComponent({
                songId: targetSong.id,
                onPlaylistSelected: (_playlistId: string, _playlistName: string) => {
                  promptAction.showToast({
                    message: $r('app.string.successfully_added_to_playlist')
                  })
                },
                // Self-close bridge — see note at the multi-choice call site above.
                onDismiss: () => {
                  this.addToPlaylistDialogController?.close()
                }
              }),
              alignment: DialogAlignment.Center,
              customStyle: true,
              maskColor: '#80000000',
              openAnimation: { duration: 0 },
              closeAnimation: { duration: 0 }
            })
            this.addToPlaylistDialogController.open()
          }, 50)
        },
        onPlayNext: () => {
          const targetSong = this.viewModel.menuTargetSong
          if (targetSong) {
            this.viewModel.addToPlayNext(targetSong)
          }
        },
        onShare: () => {
          const context = getContext(this) as common.UIAbilityContext
          const song = this.viewModel.menuTargetSong
          if (song) {
            shareSongFile(context, song.title, song.fileUri)
          }
        },
        onArtistClick: (artistName: string) => {
          this.navPathStack.pushPath({
            name: 'ArtistContentPage',
            param: {
              artistId: '',
              artistName: artistName,
              artistCoverUri: '',
              artistCoverSongId: this.viewModel.menuTargetSong?.id ?? ''
            } as ArtistContentRouterParams
          })
        },
        onAlbumClick: () => {
          const targetAlbum = this.viewModel.menuTargetSong?.album ?? ''
          const album = MainPageDataSource.loadDefaultAlbums().find(a => a.title === targetAlbum)
          this.navPathStack.pushPath({
            name: 'AlbumContentPage',
            param: {
              albumId: album?.id ?? '',
              albumTitle: targetAlbum,
              albumArtist: album?.albumArtist ?? '',
              albumCount: album?.count ?? 0,
              albumYear: album?.year ?? 0,
              albumCoverUri: album?.coverUri ?? '',
              albumCoverSongId: album?.coverSongId ?? '',
              albumDuration: '',
              albumHz: 0,
              albumBits: 0,
              albumIsHiRes: false,
              albumCopyright: ''
            } as AlbumContentRouterParams
          })
        },
        onSongInfo: () => {
          this.showSongInfo = true
        },
        onRemoveFromLibrary: () => {
          const targetSong = this.viewModel.menuTargetSong
          if (!targetSong) return
          setTimeout(() => {
            this.deleteSongDialogController = new CustomDialogController({
              builder: DeleteSongDialog({
                controller: this.deleteSongDialogController as CustomDialogController,
                songTitle: targetSong.title,
                onConfirm: async () => {
                  await this.viewModel.removeSongFromLibrary(targetSong)
                  this.showSongMenuDialog = false
                }
              }),
              alignment: DialogAlignment.Center,
              customStyle: true,
              maskColor: '#80000000',
              openAnimation: { duration: 0 },
              closeAnimation: { duration: 0 }
            })
            this.deleteSongDialogController.open()
          }, 50)
        },
        showRemoveFromPlaylist: true,
        onRemoveFromPlaylist: () => {
          const targetSong = this.viewModel.menuTargetSong
          if (!targetSong) return
          setTimeout(() => {
            this.removeFromPlaylistDialogController = new CustomDialogController({
              builder: RemoveFromPlaylistDialog({
                controller: this.removeFromPlaylistDialogController as CustomDialogController,
                songTitle: targetSong.title,
                onConfirm: () => {
                  this.viewModel.removeSongFromPlaylist(targetSong.id)
                  this.showSongMenuDialog = false
                }
              }),
              alignment: DialogAlignment.Center,
              customStyle: true,
              maskColor: '#80000000',
              openAnimation: { duration: 0 },
              closeAnimation: { duration: 0 }
            })
            this.removeFromPlaylistDialogController.open()
          }, 50)
        }
      })
    }
  }
}

// 歌单内搜索：按名称前缀过滤当前歌单内的歌曲。
