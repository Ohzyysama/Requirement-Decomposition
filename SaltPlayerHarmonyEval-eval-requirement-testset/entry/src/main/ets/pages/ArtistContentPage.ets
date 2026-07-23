// ArtistContentPage.ets
// View layer: Artist detail content page for Salt Player.
// MVVM: This View binds to ArtistContentViewModel for all data and logic.
//       The View only handles UI rendering and delegates user interactions
//       to ViewModel methods. No business logic resides in this file.
//
// Corresponds to Android ArtistContentScreen.kt (ui/screen/artist/ArtistContentScreen.kt)
// Displays: back button, artist image, artist name, shuffle play, collapse/expand songs,
// song list, album section header, album list.
// Navigation: Menu -> Artists -> click artist name -> this page

import { SongItemComponent } from '../components/SongItemComponent'
import { SongInfoData } from '../model/SongItemModel'
import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import { SongMenuDialogComponent } from '../components/SongMenuDialogComponent'
import { AddToPlaylistDialogComponent } from '../components/AddToPlaylistDialogComponent'
import { DeleteSongDialog } from '../components/DeleteSongDialog'
import { MusicDatabase } from '../model/MusicDatabase'
import { AlbumContentRouterParams } from './AlbumContentPage'
import ArtistContentViewModel, { AlbumItemViewModel } from '../viewmodel/ArtistContentViewModel'
import { ArtistContentRouterParams } from './ArtistContentRouterParams'
import { shareSongFile } from '../model/ShareUtil'
import { MainPageDataSource } from '../model/MainPageModel'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { SongInformationComponent } from './SongInformationPage'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'

@Component
struct ArtistAlbumItemRow {
  @ObjectLink albumVm: AlbumItemViewModel
  onAlbumClick: (albumVm: AlbumItemViewModel) => void = () => {}

  aboutToAppear(): void {
    this.albumVm.loadCoverIfNeeded()
  }

  aboutToReuse(params: ESObject): void {
    this.albumVm.loadCoverIfNeeded()
  }

  build() {
    Row() {
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.albumVm.coverOption })
          .width(50)
          .height(50)
      }
      .width(50)
      .height(50)
      .borderRadius(8)
      .clip(true)
      .backgroundColor($r('app.color.salt_color_song_cover'))

      Column() {
        Text(this.albumVm.hasTitle ? this.albumVm.title : $r('app.string.unknown_album_title'))
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.albumVm.titleOpacity)

        Text(this.albumVm.hasAlbumArtist ? this.albumVm.albumArtist : $r('app.string.unknown_album_artist'))
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 1 })
          .opacity(this.albumVm.albumArtistOpacity)

        Text(this.albumVm.songCountText)
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 1 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onAlbumClick(this.albumVm)
    })
  }
}

@Component
export struct ArtistContentPage {
  // ViewModel: single source of truth for all page state and logic
  @State viewModel: ArtistContentViewModel = new ArtistContentViewModel()
  @State showSongInfo: boolean = false
  @State artistCoverOption: ImageKnifeOption = new ImageKnifeOption()

  // Observe current playing song id from AppStorage so highlight syncs on skip next/previous
  @StorageProp('currentSongId') @Watch('onCurrentSongChanged') storedCurrentSongId: string = ''
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  // Bridge the persisted "show cover in song list" preference into the VM
  // so mounted lists re-render live when the user toggles it from
  // Settings → UI. Default `true` matches the value seeded in EntryAbility.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')
  storedDisplaySongCover: boolean = true

  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" preference into the
  // VM so the cached SongItemViewModel rows refresh live when the user toggles
  // it from Settings → UI → 歌曲列表. Default `false` matches EntryAbility.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  storedDisplaySongFileName: boolean = false

  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" preference into the
  // VM so the cached SongItemViewModel rows refresh live when the user toggles
  // it from Settings → UI → 歌曲列表. Default `true` matches EntryAbility.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  storedDisplayAddToPlayNext: boolean = true

  // Non-state infrastructure (scroller, nav stack, dialog controller)
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController
  private listScroller: Scroller = new Scroller()
  private navPathStack: NavPathStack = new NavPathStack()

  // Sync AppStorage currentSongId to ViewModel when player switches songs (next/previous)
  onCurrentSongChanged(): void {
    this.viewModel.currentSongId = this.storedCurrentSongId
  }

  // Forward AppStorage 'displaySongCover' writes into the VM so the song
  // list refreshes live when the user toggles the setting from Settings → UI.
  onDisplaySongCoverChanged(): void {
    this.viewModel.setDisplaySongCoverInList(this.storedDisplaySongCover)
  }

  // spec21 — Forward AppStorage 'displaySongFileName' writes into the VM so
  // the cached song rows refresh live when the user toggles the setting.
  onDisplaySongFileNameChanged(): void {
    this.viewModel.setDisplaySongFileNameInList(this.storedDisplaySongFileName)
  }

  // spec22 — Forward AppStorage 'displayAddToPlayNext' writes into the VM so
  // the cached song rows refresh live when the user toggles the setting.
  onDisplayAddToPlayNextChanged(): void {
    this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          // ===== Fixed title bar =====
          this.TopBar()

          // ===== Main scrollable content area =====
          List({ scroller: this.listScroller }) {
            // Header: artist info + shuffle/collapse row
            ListItem() {
              Column() {
                this.ArtistTopSection()
                this.ShuffleAndCollapseRow()
              }
              .width('100%')
            }

            // ===== Song List (when not collapsed, lazy) =====
            if (!this.viewModel.isSongsCollapsed) {
              LazyForEach(this.viewModel.songDataSource, (songVm: SongItemViewModel) => {
                ListItem() {
                  SongItemComponent({
                    viewModel: SongItemViewModel.create(songVm.toModel(), {
                      isCurrent: songVm.id === this.viewModel.currentSongId,
                      showCover: this.viewModel.displaySongCoverInList,
                      displayFileName: this.viewModel.displaySongFileNameInList,
                      displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,
                      onItemClickAction: () => {
                        this.viewModel.playSong(songVm)
                      },
                      onItemLongClickAction: () => {
                        this.viewModel.openSongMenu(songVm)
                      },
                      onAddToPlayNextAction: () => {
                        this.viewModel.addSongToPlayNext(songVm)
                      },
                      onMenuClickAction: () => {
                        this.viewModel.openSongMenu(songVm)
                      }
                    })
                  })
                }
              }, (songVm: SongItemViewModel) => songVm.id)
            }

            // ===== Albums Section Header =====
            ListItem() {
              Text($r('app.string.albums'))
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.salt_color_icon_foreground'))
                .padding({ left: 16, top: 16, right: 16, bottom: 4 })
                .width('100%')
            }

            // ===== Album List (lazy) =====
            LazyForEach(this.viewModel.albumDataSource, (albumVm: AlbumItemViewModel) => {
              ListItem() {
                ArtistAlbumItemRow({
                  albumVm: albumVm,
                  onAlbumClick: (vm: AlbumItemViewModel) => {
                    this.navPathStack.pushPath({
                      name: 'AlbumContentPage',
                      param: {
                        albumId: vm.id,
                        albumTitle: vm.title,
                        albumArtist: vm.albumArtist,
                        albumCount: vm.count,
                        albumYear: vm.year,
                        albumCoverUri: vm.coverUri,
                        albumCoverSongId: vm.coverSongId
                      } as AlbumContentRouterParams
                    })
                  }
                })
              }
            }, (albumVm: AlbumItemViewModel) => albumVm.id)
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .layoutWeight(1)
          .contentEndOffset(96)
          .onScroll(() => {
            const yOffset = this.listScroller.currentOffset().yOffset
            this.viewModel.showTitleInBar = yOffset > 200
          })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.colorPageBackground'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.viewModel.showSongMenu, this.songSheetBuilder(), {
        detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        backgroundColor: this.showSongInfo ? $r('app.color.colorPageBackground')
          : (this.isSystemDark ? $r('app.color.colorItemBackground') : $r('app.color.salt_color_sub_background')),
        showClose: false,
        dragBar: false,
        onDisappear: () => {
          // Do NOT call closeSongMenu() here — it sets viewModel.showSongMenu
          // (the bindSheet boolean), and a late onDisappear after navigation
          // would clobber a re-open. The $$ binding and onDismiss already handle it.
          this.showSongInfo = false

        }
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.colorPageBackground'))
    .onBackPressed(() => {
      // If the player overlay is open, close it instead of popping this page.
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
      // Read params and initialize ViewModel
      const params = context.pathInfo.param as Record<string, Object>
      if (params) {
        this.viewModel.initFromParams(params)
        // Initialize artist cover option defaults
        this.artistCoverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
        this.artistCoverOption.errorSrc = $r('app.media.ic_song_cover_v5')
        this.artistCoverOption.objectFit = ImageFit.Cover
        // Load artist cover via file URI
        const coverKey = (params['artistCoverSongId'] as string) ?? ''
        if (coverKey.length > 0) {
          const fileUri = CoverCacheDb.getCoverFileUri(coverKey)
          if (fileUri.length > 0) {
            this.artistCoverOption.loadSrc = fileUri
          } else {
            CoverCacheDb.ensureCoverFile(coverKey).then((uri: string) => {
              if (uri.length > 0) {
                this.artistCoverOption.loadSrc = uri
                return
              }
              return CoverArtExtractor.extractAndCache(coverKey, coverKey)
            }).then(() => {
              const u = CoverCacheDb.getCoverFileUri(coverKey)
              if (u.length > 0) {
                this.artistCoverOption.loadSrc = u
              }
            }).catch((_e: Error) => { /* fallback image will be shown */ })
          }
        }
      }
      // Load artist data via ViewModel (which calls Model layer)
      this.viewModel.loadArtistData()
    })
  }

  // ======================== Top Bar ========================
  @Builder
  TopBar() {
    Stack({ alignContent: Alignment.Start }) {
      Image($r('app.media.ic_arrow_back'))
        .width(56)
        .height(56)
        .padding(18)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          this.navPathStack.pop()
        })
        .accessibilityText('\u8FD4\u56DE')

      Text(this.viewModel.showTitleInBar ? this.viewModel.artistName : '')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(56)
        .padding({ left: 56, right: 56 })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(56)
  }

  // ======================== Artist Top Section ========================
  @Builder
  ArtistTopSection() {
    Column() {
      // Artist circle image
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.artistCoverOption })
          .width(100)
          .height(100)
      }
      .width(100)
      .height(100)
      .borderRadius(50)
      .clip(true)
      .backgroundColor($r('app.color.salt_color_song_cover'))
      Blank().height(12)

      // Artist name
      Text(this.viewModel.hasArtistName
        ? this.viewModel.artistName
        : $r('app.string.unknown_artist'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .opacity(this.viewModel.artistNameOpacity)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Center)
  }

  // ======================== Shuffle Play + Collapse Row ========================
  @Builder
  ShuffleAndCollapseRow() {
    Row() {
      // Random Play (left side)
      Row() {
        Image($r('app.media.ic_random_play_mini'))
          .width(40)
          .height(40)
          .padding(4)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .objectFit(ImageFit.Contain)

        Text(this.viewModel.songCountText)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ left: 6 })
      }
      .height(40)
      .padding({ left: 8, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.viewModel.shufflePlayAll()
      })
      .accessibilityText(`\u968F\u673A\u64AD\u653E(${this.viewModel.songCountText})`)

      Blank()

      // Collapse / Expand toggle (right side)
      Row() {
        Text(this.viewModel.isSongsCollapsed ? $r('app.string.expand') : $r('app.string.collapse'))
          .fontSize(14)
          .fontColor($r('app.color.colorTextForeground'))
      }
      .height(40)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.viewModel.toggleSongsCollapsed()
      })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  // ======================== Song Sheet Builder (unified: menu or song info) ========================
  @Builder
  songSheetBuilder() {
    if (this.showSongInfo) {
      SongInformationComponent({ songInfo: this.viewModel.menuSongInfo })
    } else {
      this.SongMenuSheet()
    }
  }

  // ======================== Song Menu Bottom Sheet ========================
  @Builder
  SongMenuSheet() {
    SongMenuDialogComponent({
      songInfo: this.viewModel.menuSongInfo,
      onDismiss: () => {
        this.viewModel.closeSongMenu()
      },
      onAddToPlaylist: () => {
        const targetSong = this.viewModel.menuSongInfo
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
        this.viewModel.playNextFromMenu()
      },
      onShare: () => {
        let context = getContext(this) as common.UIAbilityContext
        shareSongFile(context, this.viewModel.menuSongInfo.title, this.viewModel.menuSongInfo.fileUri)
      },
      onArtistClick: (artistName: string) => {
        if (artistName === this.viewModel.artistName) {
          return
        }
        const targetId = this.viewModel.menuSongInfo.id
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
        const albumName = this.viewModel.menuSongInfo.album
        // If the target album page already exists in the nav stack, pop back to it
        const pathNames = this.navPathStack.getAllPathName()
        for (let i = pathNames.length - 1; i >= 0; i--) {
          if (pathNames[i] === 'AlbumContentPage') {
            const param = this.navPathStack.getParamByIndex(i) as AlbumContentRouterParams
            if (param && param.albumTitle === albumName) {
              this.navPathStack.popToIndex(i)
              return
            }
          }
        }
        const albums = MainPageDataSource.loadDefaultAlbums()
        const album = albums.find(a => a.title === albumName)
        this.navPathStack.pushPath({
          name: 'AlbumContentPage',
          param: {
            albumId: album?.id ?? '',
            albumTitle: albumName,
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
        console.info('TODO: open music tag editor')
      },
      onHearusySpectrum: () => {
        console.info('TODO: open hearusy spectrum')
      },
      onEmoScroll: () => {
        console.info('TODO: open emo scroll')
      },
      onSongInfo: () => {
        this.showSongInfo = true
      },
      onRemoveFromLibrary: () => {
        const targetSong = this.viewModel.menuSongInfo
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
        console.info('TODO: copy song text')
      }
    })
  }
}

// 艺术家详情：展示艺术家及其全部曲目列表。
