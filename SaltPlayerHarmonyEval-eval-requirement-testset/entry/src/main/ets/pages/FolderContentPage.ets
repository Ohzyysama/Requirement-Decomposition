// FolderContentPage.ets
// View layer: Folder content page for Salt Player
// Corresponds to Android FolderContentScreen.kt
// Shows the songs inside a specific folder, with:
//   - Title bar with back button and folder name
//   - SongLazyColumn: toolbar row (shuffle, sort, multi-select) + song list + right ABC + locate button
// Navigation: MainPage (folder tab) -> click folder -> FolderContentPage
//
// MVVM Architecture:
//   View: FolderContentPage (this file) - pure UI rendering and user interaction
//   ViewModel: FolderContentPageViewModel - observable state and business logic
//   Model: FolderContentPageModel - raw data structures and data access
//
// The View binds to ViewModel properties for display and calls ViewModel methods
// in response to user interactions. The View does NOT contain business logic.

import { SongItemComponent } from '../components/SongItemComponent'
import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import { SongInfoData } from '../model/SongItemModel'
import { MusicDatabase } from '../model/MusicDatabase'
import RightABCModel from '../model/RightABCModel'
import { SongSortDialogComponent } from '../components/SongSortDialogComponent'
import { SongMenuDialogComponent } from '../components/SongMenuDialogComponent'
import { AddToPlaylistDialogComponent } from '../components/AddToPlaylistDialogComponent'
import { DeleteSongDialog } from '../components/DeleteSongDialog'
import { AlbumContentRouterParams } from './AlbumContentPage'
import { MainPageDataSource } from '../model/MainPageModel'
import { ArtistContentRouterParams } from './ArtistContentRouterParams'
import { shareSongFile } from '../model/ShareUtil'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import FolderContentPageViewModel from '../viewmodel/FolderContentPageViewModel'
import { SongInformationComponent } from './SongInformationPage'
import { FolderContentParams, MultiChoiceAction } from '../model/FolderContentPageModel'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

// Re-export FolderContentParams so existing consumers can import from this file
export { FolderContentParams } from '../model/FolderContentPageModel'

@Component
export struct FolderContentPage {
  // ViewModel: single source of truth for all page state and business logic.
  // View binds to ViewModel properties and calls ViewModel methods for user interactions.
  @State viewModel: FolderContentPageViewModel = new FolderContentPageViewModel()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''

  // AppStorage-synced properties for current playing state (read-only from AppStorage)
  @StorageProp('currentSongTitle') currentSongTitle: string = ''
  @StorageProp('currentSongArtist') currentSongArtist: string = ''
  @StorageProp('currentSongId') @Watch('onCurrentSongChanged') currentSongId: string = ''
  @StorageProp('currentSongCoverUri') currentSongCoverUri: string = ''
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  // Bridge the persisted "show cover in song list" preference into the VM
  // so mounted lists re-render live when the user toggles it from
  // Settings → UI. Default `true` matches the value seeded in EntryAbility.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')
  storedDisplaySongCover: boolean = true

  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" preference into the
  // VM so the folder track list re-renders live when the user toggles it from
  // Settings → UI → 歌曲列表.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  storedDisplaySongFileName: boolean = false

  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" preference into the
  // VM so the folder track list re-renders live when the user toggles it.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  storedDisplayAddToPlayNext: boolean = true

  // Sheet binding requires direct @State booleans for $$ two-way binding
  @State showSortDialog: boolean = false
  @State showSongMenu: boolean = false
  @State showSongInfo: boolean = false
  @State private alphabetSelected: number = 0
  @State private alphabetPopupLetter: string = ''
  @State private alphabetPopupVisible: boolean = false

  // Scroller for the song list (View-only concern, not in ViewModel)
  private listScroller: Scroller = new Scroller()
  private navPathStack: NavPathStack = new NavPathStack()

  // Delete song confirmation dialog controller (created on-demand)
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController

  // Sync AppStorage currentSongId to ViewModel when player switches songs (next/previous)
  onCurrentSongChanged(): void {
    this.viewModel.currentSongId = this.currentSongId
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

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          // ========== Title Bar ==========
          this.TitleBar()

          // ========== SongLazyColumn Content ==========
          Stack({ alignContent: Alignment.BottomEnd }) {
            Column() {
              // Toolbar row (random play, sort, multi-select)
              if (!this.viewModel.isSongListEmpty()) {
                if (this.viewModel.multiChoiceMode) {
                  this.MultiChoiceTopBar()
                } else {
                  this.ToolbarRow()
                }
              }

              // Song list
              this.SongListArea()

              // Multi-choice bottom bar
              if (this.viewModel.multiChoiceMode) {
                this.MultiChoiceBottomBar()
              }
            }
            .width('100%')
            .height('100%')

            // Right ABC index
            if (this.viewModel.shouldShowRightABC()) {
              Row() {
                if (this.alphabetPopupVisible) {
                  Stack() {
                    Text(this.alphabetPopupLetter)
                      .fontSize(32)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.salt_color_high_light'))
                  }
                  .width(56)
                  .height(56)
                  .borderRadius(28)
                  .backgroundColor($r('app.color.salt_color_sub_background'))
                  .alignContent(Alignment.Center)
                }

                AlphabetIndexer({ arrayValue: new RightABCModel().alphabetArray, selected: $$this.alphabetSelected })
                  .onSelect((index: number) => {
                    const char = new RightABCModel().alphabetArray[index]
                    this.scrollToChar(char)
                    this.alphabetPopupLetter = char
                    this.alphabetPopupVisible = true
                  })
                  .selectedColor($r('app.color.colorSubTextForeground'))
                  .selectedBackgroundColor(Color.Transparent)
                  .usingPopup(false)
                  .autoCollapse(false)
                  .selectedFont({ size: 10, weight: FontWeight.Bold })
                  .font({ size: 10 })
                  .itemSize(15)
                  .alignStyle(IndexerAlign.Left)
                  .onTouch((event: TouchEvent) => {
                    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                      this.alphabetPopupVisible = false
                    }
                  })
              }
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .height('100%')
              .offset({ x: 3 })
              .padding({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
              .hitTestBehavior(HitTestMode.Transparent)
            }

            // Locate current playing song button
            if (this.viewModel.shouldShowLocateButton()) {
              this.LocateCurrentSongButton()
            }
          }
          .layoutWeight(1)
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
      .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
      .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      // Read navigation params and initialize ViewModel
      const params = context.pathInfo.param as FolderContentParams
      if (params) {
        this.viewModel.initFromParams(params)
        if (params.isPlaying !== undefined) {
          this.isPlaying = params.isPlaying
        }
      }
      // Load songs via ViewModel
      this.viewModel.loadSongs()
    })
    .bindSheet($$this.showSongMenu, this.songSheetBuilder(), {
      detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
      dragBar: false,
      showClose: false,
      backgroundColor: this.showSongInfo ? $r('app.color.colorPageBackground')
        : (this.isSystemDark ? $r('app.color.colorItemBackground') : $r('app.color.salt_color_sub_background')),
      onDisappear: () => {
        // Do NOT reset showSongMenu here — already managed by $$ binding
        // and onDismiss. Late onDisappear after navigation would clobber a re-open.
        this.showSongInfo = false
        this.viewModel.closeSongMenu()

      }
    })
  }

  // ======================== Title Bar ========================
  @Builder
  TitleBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.viewModel.folderName)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .padding({ left: 56, right: 56 })
        .width('100%')

      Image($r('app.media.ic_arrow_back'))
        .width(56)
        .height(56)
        .padding(18)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .position({ x: 0, y: 0 })
        .onClick(() => {
          this.navPathStack.pop()
        })
        .accessibilityText('\u8FD4\u56DE')
    }
    .width('100%')
    .height(56)
  }

  // ======================== Toolbar Row ========================
  @Builder
  ToolbarRow() {
    Row() {
      // Random play button
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
        this.viewModel.randomPlayAll()
      })
      .accessibilityText('\u968F\u673A\u64AD\u653E(' + this.viewModel.getSongCountText() + ')')

      // Spacer with double-click to scroll to top
      Blank()
        .layoutWeight(1)
        .height(40)
        .gesture(
          TapGesture({ count: 2 })
            .onAction(() => {
              this.listScroller.scrollToIndex(0)
            })
        )

      // Sort button
      Image($r('app.media.ic_sort'))
        .width(48)
        .height(40)
        .padding({ left: 18, right: 10, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.showSortDialog = true
          this.viewModel.openSortDialog()
        })
        .accessibilityText('\u6392\u5E8F')
        .bindSheet($$this.showSortDialog, this.sortDialogBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: false,
          showClose: false,
          backgroundColor: this.isSystemDark ? $r('app.color.colorPageBackground') : $r('app.color.salt_color_sub_background'),
          onDisappear: () => {
            this.showSortDialog = false
            this.viewModel.closeSortDialog()
          }
        })

      // Multi-select button
      Image($r('app.media.ic_multiple_choice'))
        .width(48)
        .height(40)
        .padding({ left: 9, right: 17, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.enterMultiChoiceMode()
        })
        .accessibilityText('\u591A\u9009')
    }
    .width('100%')
    .height(40)
    .padding({ right: 2 })
  }

  // ======================== Song List Area ========================
  @Builder
  SongListArea() {
    if (this.viewModel.isSongListEmpty()) {
      // Empty state
      Column() {
        Text('\u6CA1\u6709\u6B4C\u66F2')
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ scroller: this.listScroller }) {
        LazyForEach(this.viewModel.songDataSource, (song: SongInfoData) => {
          ListItem() {
            SongItemComponent({
              viewModel: SongItemViewModel.create(song, {
                isCurrent: this.viewModel.isCurrentSong(song.id),
                showCover: this.viewModel.displaySongCoverInList,
                displayFileName: this.viewModel.displaySongFileNameInList,
                multiChoiceMode: this.viewModel.multiChoiceMode,
                checked: this.viewModel.checkedMap[song.id] === true,
                displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,
                onItemClickAction: () => {
                  if (this.viewModel.multiChoiceMode) {
                    return
                  }
                  if (this.viewModel.isCurrentSong(song.id)) {
                    console.info('TODO: expand to full player via MiniPlayer')
                  } else {
                    this.viewModel.playSong(song)
                    this.currentSongTitle = song.title
                    this.currentSongArtist = song.artist
                  }
                },
                onItemLongClickAction: () => {
                  this.viewModel.openSongMenu(song)
                  this.showSongMenu = true
                },
                onMenuClickAction: () => {
                  this.viewModel.openSongMenu(song)
                  this.showSongMenu = true
                },
                onAddToPlayNextAction: () => {
                  this.viewModel.addToPlayNext(song)
                },
                onCheckedChangeAction: (checked: boolean) => {
                  this.viewModel.toggleSongChecked(song.id, checked)
                }
              })
            })
          }
        }, (song: SongInfoData) => song.id)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ right: 2 })
      .contentEndOffset(96)
      .scrollBar(this.viewModel.shouldShowRightABC() ? BarState.Off : BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
  }

  // ======================== Locate Current Song Button ========================
  @Builder
  LocateCurrentSongButton() {
    Column() {
      Stack() {
        Image($r('app.media.ic_location'))
          .width('100%')
          .height('100%')
          .padding(10)
          .fillColor($r('app.color.colorSubIconForeground'))
          .objectFit(ImageFit.Contain)
      }
      .width(40)
      .height(40)
      .borderRadius(16)
      .backgroundColor($r('app.color.salt_color_white'))
      .onClick(() => {
        const index = this.viewModel.findCurrentSongIndex()
        if (index !== -1) {
          this.listScroller.scrollToIndex(index)
        }
      })
    }
    .width(56)
    .height(96)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText('\u5B9A\u4F4D\u5F53\u524D\u64AD\u653E\u6B4C\u66F2')
  }

  // ======================== Multi Choice Top Bar ========================
  @Builder
  MultiChoiceTopBar() {
    Stack({ alignContent: Alignment.Center }) {
      // Select all / Deselect all
      Text(this.viewModel.getSelectAllLabel())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_high_light'))
        .position({ x: 16, y: 0 })
        .height(40)
        .onClick(() => {
          this.viewModel.toggleSelectAll()
        })

      // Selected count
      Text(this.viewModel.getCheckedCountText())
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))

      // Cancel button
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

  // ======================== Multi Choice Bottom Bar ========================
  @Builder
  MultiChoiceBottomBar() {
    Row() {
      this.MultiChoiceControlItem($r('app.media.ic_remove'), '\u4ECE\u97F3\u4E50\u5E93\u4E2D\u79FB\u9664', () => {
        if (this.viewModel.checkedCount <= 0) return
        const count = this.viewModel.checkedCount
        setTimeout(() => {
          this.deleteSongDialogController = new CustomDialogController({
            builder: DeleteSongDialog({
              songTitle: `${count} \u9996\u6B4C\u66F2`,
              onConfirm: async () => {
                await this.viewModel.removeSelectedFromLibrary()
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
      })

      // Spec5 S6: Folder multi-select → 添加到歌单.
      this.MultiChoiceControlItem($r('app.media.ic_add'), '\u6DFB\u52A0\u5230\u6B4C\u5355', () => {
        const orderedIds = this.viewModel.getSelectedSongIdsInOrder()
        setTimeout(() => {
          this.addToPlaylistDialogController = new CustomDialogController({
            builder: AddToPlaylistDialogComponent({
              songId: '',
              selectedSongIds: orderedIds,
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

      this.MultiChoiceControlItem($r('app.media.ic_playlist_add_24'), '\u64AD\u653E\u9009\u4E2D\u961F\u5217', () => {
        this.viewModel.handleMultiChoiceAction(MultiChoiceAction.PLAY_SELECTED_QUEUE)
      })
    }
    .width('100%')
    .height(56)
    .backgroundColor($r('app.color.salt_color_on_page_background'))
    .margin({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
  }

  @Builder
  MultiChoiceControlItem(icon: Resource, text: string, onClick: () => void) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.viewModel.isMultiChoiceActionEnabled() ?
          $r('app.color.salt_color_high_light') : $r('app.color.colorSubTextForeground'))

      Text(text)
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
    .opacity(this.viewModel.isMultiChoiceActionEnabled() ? 1.0 : 0.5)
    .onClick(() => {
      if (this.viewModel.isMultiChoiceActionEnabled()) {
        onClick()
      }
    })
  }

  // ======================== Sort Dialog Builder ========================
  @Builder
  sortDialogBuilder() {
    SongSortDialogComponent({
      songLazySort: this.viewModel.songLazySort,
      customizable: false,
      displaySongCoverInList: this.viewModel.displaySongCoverInList,
      displaySongFileNameInList: this.viewModel.displaySongFileNameInList,
      displayAddToPlayNextInList: this.viewModel.displayAddToPlayNextInList,
      onSortClick: (sort: number) => {
        this.viewModel.changeSortType(sort)
      },
      onDisplaySettingChange: (key: string, value: boolean) => {
        this.viewModel.updateDisplaySetting(key, value)
      }
    })
  }

  // ======================== Song Sheet Builder (unified: menu or song info) ========================
  @Builder
  songSheetBuilder() {
    if (this.showSongInfo) {
      SongInformationComponent({ songInfo: this.viewModel.songMenuTarget })
    } else {
      this.songMenuBuilder()
    }
  }

  // ======================== Song Menu Dialog Builder ========================
  @Builder
  songMenuBuilder() {
    SongMenuDialogComponent({
      songInfo: this.viewModel.songMenuTarget,
      onDismiss: () => {
        this.showSongMenu = false
        this.viewModel.closeSongMenu()
      },
      onAddToPlaylist: () => {
        const targetSong = this.viewModel.songMenuTarget
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
        this.viewModel.addToPlayNext(this.viewModel.songMenuTarget)
      },
      onShare: () => {
        let context = getContext(this) as common.UIAbilityContext
        shareSongFile(context, this.viewModel.songMenuTarget.title, this.viewModel.songMenuTarget.fileUri)
      },
      onArtistClick: (artistName: string) => {
        const targetId = this.viewModel.songMenuTarget.id
        const artists = MainPageDataSource.loadDefaultArtists()
        const artist = artists.find(a => a.name === artistName)
        this.navPathStack.pushPath({
          name: 'ArtistContentPage',
          param: {
            artistId: artist?.id ?? '',
            artistName: artistName,
            artistCoverUri: artist?.coverUri ?? '',
            artistCoverSongId: artist?.coverSongId ?? targetId
          } as ArtistContentRouterParams
        })
      },
      onAlbumClick: () => {
        const albumTitle = this.viewModel.songMenuTarget.album
        const album = MainPageDataSource.loadDefaultAlbums().find(a => a.title === albumTitle)
        this.navPathStack.pushPath({
          name: 'AlbumContentPage',
          param: {
            albumId: album?.id ?? '',
            albumTitle: albumTitle,
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
      onMusicTagEdit: () => {
        console.info('TODO: launch music tag editor - not yet implemented')
      },
      onHearusySpectrum: () => {
        console.info('TODO: launch Hearusy Spectrum - not yet implemented')
      },
      onEmoScroll: () => {
        console.info('TODO: launch Emo Scroll - not yet implemented')
      },
      onSongInfo: () => {
        this.showSongInfo = true
      },
      onRemoveFromLibrary: () => {
        const targetSong = this.viewModel.songMenuTarget
        if (!targetSong) return
        setTimeout(() => {
          this.deleteSongDialogController = new CustomDialogController({
            builder: DeleteSongDialog({
              songTitle: targetSong.title,
              onConfirm: async () => {
                if (targetSong.path && targetSong.path.length > 0) {
                  const ok = await MusicDatabase.deleteTrackByPath(targetSong.path)
                  if (ok) {
                    this.viewModel.removeSongFromListById(targetSong.id)
                    await MusicDatabase.handleSongRemovedFromLibrary(targetSong.id, targetSong.fileUri)
                  }
                }
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
      onCopyText: () => {
        console.info('TODO: show CopyDialog - not yet implemented')
      }
    })
  }

  // ======================== View Helper (scroll only) ========================
  private scrollToChar(char: string): void {
    const index = this.viewModel.getScrollIndexForChar(char)
    if (index >= 0) {
      this.listScroller.scrollToIndex(index, true)
    }
  }
}

// 文件夹浏览：列出文件夹与子文件夹及其中的音频文件。

// 文件夹浏览：优化大目录下的列表滚动性能。
