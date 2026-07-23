// SearchAllSongsPage.ets
// View layer: Search all songs page for Salt Player.
// MVVM: This View uses SearchAllSongsViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating all business logic and state management to the ViewModel.
// Navigated from MainPage search icon click.
// Contains:
//   - SearchTitleBar: search input with clear and cancel buttons
//   - Content area: empty state (NoneBox) or song list results
//   - SongMenuDialog: bottom sheet for song operations

import lottie, { AnimationItem } from '@ohos/lottie'
import { SongItemComponent, SongInfo } from '../components/SongItemComponent'
import { SongMenuDialogComponent } from '../components/SongMenuDialogComponent'
import { AddToPlaylistDialogComponent } from '../components/AddToPlaylistDialogComponent'
import { SearchAllSongsViewModel } from '../viewmodel/SearchAllSongsViewModel'
import { SongInfoData } from '../model/SongItemModel'
import { AlbumContentRouterParams } from './AlbumContentPage'
import { MainPageDataSource } from '../model/MainPageModel'
import { ArtistContentRouterParams } from './ArtistContentRouterParams'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { BasicScreen } from '../components/BasicScreen'
import { SongInformationComponent } from './SongInformationPage'
import { DeleteSongDialog } from '../components/DeleteSongDialog'
import { MusicDatabase } from '../model/MusicDatabase'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
// Scenario 2 fix: imports for shuffle / sort / multi-select parity with the
// song-page list — sort dialog, sort enum.
import { SongSortDialogComponent, SongLazySort } from '../components/SongSortDialogComponent'

// Re-export for backward compatibility with other pages that may import from here
export { SearchAllSongsRouterParams } from '../model/SearchAllSongsModel'

@Component
export struct SearchAllSongsPage {
  // ViewModel: single source of truth for this page's state and business logic
  @State viewModel: SearchAllSongsViewModel = new SearchAllSongsViewModel()
  @State showSongInfo: boolean = false
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController
  // Scenario 2 fix: dialog controller for the multi-choice "add to playlist"
  // batch action (separate from the single-song add-to-playlist controller
  // above so they don't interfere with each other when both are wired).
  private multiChoiceAddToPlaylistController?: CustomDialogController

  // Current playing state from AppStorage
  @StorageProp('currentSongId') currentSongId: string = ''
  @StorageProp('isPlaying') isPlaying: boolean = false
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  // Bridge the persisted "show cover in song list" preference into the VM
  // so mounted lists re-render live when the user toggles it from
  // Settings → UI. Default `true` matches the value seeded in EntryAbility.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')
  storedDisplaySongCover: boolean = true

  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" preference into the
  // VM so the search result list re-renders live when the user toggles it
  // from Settings → UI → 歌曲列表.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  storedDisplaySongFileName: boolean = false

  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" preference into the
  // VM so the search result list re-renders live when the user toggles it.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  storedDisplayAddToPlayNext: boolean = true

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

  // Text input controller for focus management (UI-only concern, stays in View)
  private textInputController: TextInputController = new TextInputController()
  // Lottie animation (UI-only concern, stays in View)
  private lottieRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private lottieCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lottieRenderingSettings)
  private lottieAnimItem: AnimationItem | null = null
  private navPathStack: NavPathStack = new NavPathStack()

  aboutToDisappear(): void {
    lottie.destroy(this.viewModel.LOTTIE_ANIM_NAME)
  }

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ========== Search Title Bar ==========
        this.SearchTitleBar()

        // ========== Content Area ==========
        if (!this.viewModel.hasResults) {
          // Empty state - NoneBox equivalent
          this.NoneBox()
        } else {
          // Toolbar (Random play / Sort / Multi-choice) — parity with song-page list
          if (this.viewModel.multiChoiceMode) {
            this.MultiChoiceTopBar()
          } else {
            this.ToolbarRow()
          }
          // Song list results
          this.SearchResultsList()
          // Multi-choice bottom action bar (visible only in multi-choice mode)
          if (this.viewModel.multiChoiceMode) {
            this.MultiChoiceBottomBar()
          }
        }
      }
      .width('100%')
      .height('100%')
      .bindSheet($$this.viewModel.showSongMenu, this.songSheetBuilder(), {
        detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        dragBar: false,
        showClose: false,
        backgroundColor: this.showSongInfo ? $r('app.color.colorPageBackground')
          : (this.isSystemDark ? $r('app.color.colorItemBackground') : $r('app.color.salt_color_sub_background')),
        onDisappear: () => {
          // Do NOT call closeSongMenu() here — it sets viewModel.showSongMenu
          // (the bindSheet boolean), and a late onDisappear would clobber a re-open.
          this.showSongInfo = false

        }
      })
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      // Delegate param parsing to ViewModel
      const params = context.pathInfo.param as Record<string, Object>
      if (params) {
        this.viewModel.initFromParams(params)
      }
    })
  }

  // ======================== Search Title Bar ========================
  @Builder
  SearchTitleBar() {
    Row() {
      // Search input box with rounded background
      Row() {
        // Search icon (left side)
        Image($r('app.media.ic_search'))
          .width(36)
          .height(36)
          .padding(9)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .opacity(0.5)
          .margin({ left: 4 })

        // Text input area
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
            // Delegate search logic to ViewModel
            this.viewModel.performSearch(value)
          })
          .defaultFocus(true)

        // Clear button (right side of search box)
        Image($r('app.media.ic_cancel'))
          .width(36)
          .height(36)
          .padding(8)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .onClick(() => {
            // Delegate clear logic to ViewModel
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

      // Cancel button
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

  // ======================== NoneBox (Empty State) ========================
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
    .padding({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ======================== Search Results List ========================
  @Builder
  SearchResultsList() {
    List() {
      ForEach(this.viewModel.searchResults, (song: SongInfoData) => {
        ListItem() {
          SongItemComponent({
            viewModel: this.viewModel.createSongItemViewModel(song, this.currentSongId, this.isPlaying)
          })
        }
      }, (song: SongInfoData) => song.id)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  // ======================== Toolbar Row (Random play / Sort / Multi-choice) ========================
  // Mirrors MainPage.ToolbarRow so the search result list offers the same
  // list-level affordances as the song-page list (SPEC 23 — scenario 2).
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

        Text(this.viewModel.searchResults.length.toString())
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ left: 6 })
      }
      .height(40)
      .padding({ left: 8, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.viewModel.randomPlay()
      })
      .accessibilityText('随机播放(' + this.viewModel.searchResults.length.toString() + ')')

      Blank()
        .layoutWeight(1)
        .height(40)

      Image($r('app.media.ic_sort'))
        .width(48)
        .height(40)
        .padding({ left: 18, right: 10, top: 10, bottom: 10 })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.showSortDialog = true
        })
        .accessibilityText('排序')
        .bindSheet($$this.viewModel.showSortDialog, this.sortDialogBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: false,
          showClose: false,
          backgroundColor: this.isSystemDark ? $r('app.color.colorPageBackground') : $r('app.color.salt_color_sub_background'),
          onDisappear: () => {
            this.viewModel.showSortDialog = false
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
    .padding({ right: 2 })
  }

  // ======================== Multi Choice Top Bar ========================
  @Builder
  MultiChoiceTopBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.viewModel.checkedCount === this.viewModel.searchResults.length ? '取消全选' : '全选')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_high_light'))
        .position({ x: 16, y: 0 })
        .height(40)
        .onClick(() => {
          this.viewModel.toggleSelectAll()
        })

      Text(`已选中 ${this.viewModel.checkedCount} 项`)
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

  // ======================== Multi Choice Bottom Bar ========================
  @Builder
  MultiChoiceBottomBar() {
    Row() {
      this.MultiChoiceControlItem($r('app.media.ic_remove'), '从音乐库中移除', () => {
        this.viewModel.removeSelectedFromLibrary()
      })
      this.MultiChoiceControlItem($r('app.media.ic_add'), '添加到歌单', () => {
        const orderedIds = this.viewModel.getSelectedSongIdsInOrder()
        setTimeout(() => {
          this.multiChoiceAddToPlaylistController = new CustomDialogController({
            builder: AddToPlaylistDialogComponent({
              songId: '',
              selectedSongIds: orderedIds,
              onPlaylistSelected: (_playlistId: string, _playlistName: string) => {
                promptAction.showToast({
                  message: $r('app.string.successfully_added_to_playlist')
                })
                this.viewModel.exitMultiChoiceMode()
              },
              onDismiss: () => {
                this.multiChoiceAddToPlaylistController?.close()
              }
            }),
            alignment: DialogAlignment.Center,
            customStyle: true,
            maskColor: '#80000000',
            openAnimation: { duration: 0 },
            closeAnimation: { duration: 0 }
          })
          this.multiChoiceAddToPlaylistController.open()
        }, 50)
      })
      this.MultiChoiceControlItem($r('app.media.ic_playlist_add_24'), '播放选中队列', () => {
        this.viewModel.playSelectedQueue()
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
        .fillColor(this.viewModel.checkedCount > 0 ?
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
    .opacity(this.viewModel.checkedCount > 0 ? 1.0 : 0.5)
    .onClick(() => {
      if (this.viewModel.checkedCount > 0) {
        onClick()
      }
    })
  }

  // ======================== Sort Dialog Builder ========================
  // `customizable` is intentionally false — the search result list has no
  // persistent custom order to drag-reorder against.
  @Builder
  sortDialogBuilder() {
    SongSortDialogComponent({
      songLazySort: this.viewModel.songLazySort,
      customizable: false,
      onSortClick: (sort: number) => {
        this.viewModel.changeSongSort(sort)
        this.viewModel.showSortDialog = false
      }
    })
  }

  // ======================== Song Sheet Builder (unified: menu or song info) ========================
  @Builder
  songSheetBuilder() {
    if (this.showSongInfo) {
      SongInformationComponent({ songInfo: this.viewModel.songMenuTarget as SongInfo })
    } else {
      this.songMenuBuilder()
    }
  }

  // ======================== Song Menu Dialog Builder ========================
  @Builder
  songMenuBuilder() {
    SongMenuDialogComponent({
      songInfo: this.viewModel.songMenuTarget as SongInfo,
      onDismiss: () => {
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
      },
      onPlayNext: () => {
        if (this.viewModel.songMenuTarget) {
          this.viewModel.addToPlayNext(this.viewModel.songMenuTarget)
        }
      },
      onShare: () => {
        let context = getContext(this) as common.UIAbilityContext
        this.viewModel.shareSong(context)
      },
      onArtistClick: (artistName: string) => {
        if (this.viewModel.songMenuTarget) {
          const target = this.viewModel.songMenuTarget
          const artists = MainPageDataSource.loadDefaultArtists()
          const artist = artists.find(a => a.name === artistName)
          this.navPathStack.pushPath({
            name: 'ArtistContentPage',
            param: {
              artistId: artist?.id ?? '',
              artistName: artistName,
              artistCoverUri: artist?.coverUri ?? '',
              artistCoverSongId: artist?.coverSongId ?? target.id
            } as ArtistContentRouterParams
          })
        }
      },
      onAlbumClick: () => {
        if (this.viewModel.songMenuTarget) {
          const target = this.viewModel.songMenuTarget
          const albumTitle = target.album
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
        }
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
}
