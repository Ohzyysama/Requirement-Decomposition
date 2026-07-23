// AlbumContentPage.ets
// View layer: Album detail/content page for Salt Player.
// MVVM architecture:
//   View: AlbumContentPage (this file) - pure UI rendering and user interaction
//   ViewModel: AlbumContentViewModel - observable state and business logic
//   Model: AlbumContentModel - raw data structures and data access
//
// Corresponds to Android AlbumContentScreen.kt
// Shows: title bar with back button, album cover + info, stats row, song list, participating artists
// Navigated from album list in MainPage (via AlbumTabComponent)

import { SongItemComponent, SongInfo } from '../components/SongItemComponent'
import { SongInfoData } from '../model/SongItemModel'
import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import { SongMenuDialogComponent } from '../components/SongMenuDialogComponent'
import { AddToPlaylistDialogComponent } from '../components/AddToPlaylistDialogComponent'
import { DeleteSongDialog } from '../components/DeleteSongDialog'
import { MusicDatabase } from '../model/MusicDatabase'
import { ArtistItemComponent } from '../components/ArtistItemComponent'
import { ArtistItemViewModel } from '../viewmodel/ArtistItemViewModel'
import { ArtistContentRouterParams } from './ArtistContentRouterParams'
import { MainPageDataSource } from '../model/MainPageModel'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import AlbumContentViewModel from '../viewmodel/AlbumContentViewModel'
import { AlbumContentRouterParams, DiscSongGroupData } from '../model/AlbumContentModel'
import { AlbumSongFlatItem } from '../model/AlbumContentLazyDataSource'
import { SongInformationComponent } from './SongInformationPage'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'

// Re-export AlbumContentRouterParams so existing consumers can import from this file
export { AlbumContentRouterParams } from '../model/AlbumContentModel'

@Component
export struct AlbumContentPage {
  // ViewModel: single source of truth for all page state and business logic.
  // View binds to ViewModel properties and calls ViewModel methods for user interactions.
  @State viewModel: AlbumContentViewModel = new AlbumContentViewModel()

  // Local UI state for bindSheet two-way binding ($$).
  // The $$ operator requires a @State variable directly on the component;
  // it cannot deeply observe into an @Observed object's property.
  @State showSongMenuDialog: boolean = false
  @State showSongInfo: boolean = false
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()

  // Observe current playing song id from AppStorage so highlight syncs on skip next/previous
  @StorageProp('currentSongId') @Watch('onCurrentSongChanged') storedCurrentSongId: string = ''

  // Dark mode detection for blurred background gradient color
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  // Status bar height (vp) — used to extend blur background into the status bar area
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" preference into the
  // VM so the album track list re-renders live when the user toggles it from
  // Settings → UI → 歌曲列表. Default `false` matches EntryAbility's persistProp.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  storedDisplaySongFileName: boolean = false

  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" preference into the
  // VM so the album track list re-renders live when the user toggles it.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  storedDisplayAddToPlayNext: boolean = true

  private scroller: Scroller = new Scroller()
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController
  private navPathStack: NavPathStack = new NavPathStack()
  // Pending delete: saved when user taps "remove from library" in the song menu,
  // then consumed in bindSheet onDisappear to open the delete dialog after the
  // sheet has fully dismissed (avoids animation overlap that causes button flash).

  // Sync AppStorage currentSongId to ViewModel when player switches songs (next/previous)
  onCurrentSongChanged(): void {
    this.viewModel.currentSongId = this.storedCurrentSongId
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes into the VM.
  onDisplaySongFileNameChanged(): void {
    this.viewModel.setDisplaySongFileNameInList(this.storedDisplaySongFileName)
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes into the VM.
  onDisplayAddToPlayNextChanged(): void {
    this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // Layer 1: Blurred album cover background
        // Always rendered (no conditional) to avoid flicker on cover load.
        // No .position() to avoid leaking outside NavDestination during pop transition.
        Stack() {
          ImageKnifeComponent({ imageKnifeOption: this.coverOption })
            .width('100%')
            .height('100%')
            .blur(80)
            .opacity(0.6)

          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              angle: 180,
              colors: [['#00000000', 0.0], [this.isSystemDark ? '#ff0c0c0c' : '#fff7f9fa', 1.0]]
            })
        }
        .width('100%')
        .height('48%')
        .hitTestBehavior(HitTestMode.None)

        // Layer 2: Main content
        Column() {
          this.TitleBar()

          List({ scroller: this.scroller }) {
            // Header: album info + stats
            ListItem() {
              Column() {
                this.AlbumTopSection()
                Blank().height(12)
                this.StatsRow()
                Blank().height(16)
              }
              .width('100%')
            }

            // Song list: flattened disc headers + songs (lazy)
            LazyForEach(this.viewModel.songDataSource, (item: AlbumSongFlatItem) => {
              if (item.isGroupHeader) {
                ListItem() {
                  Column() {
                    this.ItemDivider()
                    if (item.disc !== 0) {
                      Row() {
                        Text(`DISC ${item.disc}`)
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.colorTextForeground'))

                        Text(` (${item.songCount} / ${item.discDuration})`)
                          .fontSize(12)
                          .fontWeight(FontWeight.Bold)
                          .fontColor($r('app.color.colorTextForeground'))
                          .opacity(0.35)
                      }
                      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
                    }
                  }
                }
              } else {
                ListItem() {
                  SongItemComponent({
                    viewModel: SongItemViewModel.create(item.song as SongInfo, {
                      isCurrent: this.viewModel.isSongCurrent((item.song as SongInfo).id),
                      showCover: false,
                      showTrackNumber: true,
                      trackNumber: 0,
                      displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,
                      displayFileName: this.viewModel.displaySongFileNameInList,
                      onItemClickAction: () => {
                        this.viewModel.playSong(item.song as SongInfo)
                      },
                      onItemLongClickAction: () => {
                        this.viewModel.openSongMenu(item.song as SongInfo)
                        this.showSongMenuDialog = true
                      },
                      onMenuClickAction: () => {
                        this.viewModel.openSongMenu(item.song as SongInfo)
                        this.showSongMenuDialog = true
                      },
                      onAddToPlayNextAction: () => {
                        this.viewModel.addToPlayNext(item.song as SongInfo)
                      }
                    })
                  })
                }
              }
            }, (item: AlbumSongFlatItem) => {
              if (item.isGroupHeader) {
                return `gh_${item.disc}`
              }
              return (item.song as SongInfo).id
            })

            // Footer: divider + copyright + participating artists
            ListItem() {
              Column() {
                this.ItemDivider()

                if (this.viewModel.hasCopyright) {
                  Column() {
                    Text($r('app.string.copyright'))
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor($r('app.color.salt_color_high_light'))
                      .padding({ left: 16, right: 16, top: 16, bottom: 4 })
                      .width('100%')

                    Text(this.viewModel.albumCopyright)
                      .fontSize(14)
                      .fontColor($r('app.color.colorSubTextForeground'))
                      .padding({ left: 16, right: 16, bottom: 12 })
                      .width('100%')
                  }
                  .width('100%')

                  this.ItemDivider()
                }

                if (this.viewModel.hasParticipatingArtists) {
                  Text($r('app.string.participating_artists'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.salt_color_high_light'))
                    .padding({ left: 16, right: 16, top: 16, bottom: 4 })
                    .width('100%')

                  ForEach(this.viewModel.participatingArtists, (artist: ArtistItemViewModel) => {
                    ArtistItemComponent({
                      artistVM: artist,
                      onItemClick: () => {
                        this.getUIContext().animateTo({
                          duration: 350,
                          curve: Curve.Friction
                        }, () => {
                          this.navPathStack.pushPath({
                            name: 'ArtistContentPage',
                            param: {
                              artistId: artist.id,
                              artistName: artist.name,
                              artistCoverUri: artist.coverUri,
                              artistCoverSongId: artist.coverSongId
                            } as ArtistContentRouterParams
                          }, false)
                        })
                      }
                    })
                  }, (artist: ArtistItemViewModel) => artist.id)
                }
              }
              .width('100%')
            }
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .layoutWeight(1)
          .contentEndOffset(96)
          .onScroll(() => {
            const yOffset = this.scroller.currentOffset().yOffset
            this.viewModel.updateScrollOffset(yOffset)
          })
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight })
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .backgroundColor($r('app.color.colorPageBackground'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet($$this.showSongMenuDialog, this.songSheetBuilder(), {
        detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        showClose: false,
        dragBar: false,
        backgroundColor: this.showSongInfo ? $r('app.color.colorPageBackground')
          : (this.isSystemDark ? $r('app.color.colorItemBackground') : $r('app.color.salt_color_sub_background')),
        onDisappear: () => {
          // Do NOT reset showSongMenuDialog here — already managed by $$ binding
          // and onDismiss. Late onDisappear after navigation would clobber a re-open.
          this.showSongInfo = false
          this.viewModel.closeSongMenu()

        }
      })
    }
    .hideTitleBar(true)
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
      const params = context.pathInfo.param as AlbumContentRouterParams | undefined
      if (params) {
        this.viewModel.initFromParams(params)
        // Initialize cover option
        this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
        this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
        this.coverOption.objectFit = ImageFit.Cover
        // Load cover via file URI
        const coverKey = params.albumCoverSongId ?? ''
        if (coverKey.length > 0) {
          const fileUri = CoverCacheDb.getCoverFileUri(coverKey)
          if (fileUri.length > 0) {
            this.coverOption.loadSrc = fileUri
          } else {
            CoverCacheDb.ensureCoverFile(coverKey).then((uri: string) => {
              if (uri.length > 0) {
                this.coverOption.loadSrc = uri
                return
              }
              return CoverArtExtractor.extractAndCache(coverKey, coverKey)
            }).then(() => {
              const u = CoverCacheDb.getCoverFileUri(coverKey)
              if (u.length > 0) {
                this.coverOption.loadSrc = u
              }
            }).catch((_e: Error) => { /* fallback image will be shown */ })
          }
        }
      }
      // Load album data via ViewModel (which delegates to Model)
      this.viewModel.loadAlbumData()
    })
  }

  // ===== Title Bar (matches Android ScreenTitleBar: 56dp height, back button + centered title) =====
  @Builder
  TitleBar() {
    Stack({ alignContent: Alignment.Start }) {
      // Back button: 56x56vp area, icon with 18vp padding
      Image($r('app.media.ic_arrow_back'))
        .width(56)
        .height(56)
        .padding(18)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .objectFit(ImageFit.Contain)
        .onClick(() => {
          this.navPathStack.pop()
        })
        .accessibilityText('返回')

      // Centered title (only shown when scrolled past album top)
      Text(this.viewModel.showTitleInBar ? this.viewModel.albumTitle : '')
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

  // ===== Album Top Section (matches Android AlbumTop: cover image + album info) =====
  @Builder
  AlbumTopSection() {
    Row() {
      // Album cover image (120vp, rounded corners 8vp, border)
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.coverOption })
          .width(120)
          .height(120)
      }
      .width(120)
      .height(120)
      .borderRadius(8)
      .border({ width: 1, color: '#0Dffffff' })
      .clip(true)
      .onClick(() => {
        this.viewModel.showAlbumCoverBigImage()
      })

      // Album info column
      Column() {
        // Album title
        Text(this.viewModel.hasTitle ? this.viewModel.albumTitle : $r('app.string.unknown_album_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .textAlign(TextAlign.Start)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.viewModel.titleOpacity)

        Blank().height(4)

        // Album artist
        Text(this.viewModel.hasArtist ? this.viewModel.albumArtist : $r('app.string.unknown_album_artist'))
          .fontSize(14)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .textAlign(TextAlign.Start)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.viewModel.artistOpacity)

        Blank().height(8)

        // Audio quality info row
        Row() {
          Column() {
            if (this.viewModel.albumBits !== 0) {
              Text(`${this.viewModel.albumBits} bits`)
                .fontSize(8)
                .fontColor($r('app.color.salt_color_icon_foreground'))
            }
            if (this.viewModel.albumHz !== 0) {
              Text(`${this.viewModel.albumHz} Hz`)
                .fontSize(8)
                .fontColor($r('app.color.salt_color_icon_foreground'))
            }
          }
        }
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .alignItems(VerticalAlign.Center)
  }

  // ===== Stats Row (song count, duration, year) =====
  // Note: Values are referenced directly from this.viewModel instead of being passed
  // as @Builder parameters, because ArkUI V1 does not track dependency changes for
  // values passed by parameter to @Builder methods (the Text would not re-render).
  @Builder
  StatsRow() {
    Row() {
      Column() {
        Text(this.viewModel.songCountText)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .textAlign(TextAlign.Center)
          .width('100%')

        Blank().height(1)

        Text($r('app.string.song'))
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .layoutWeight(1)

      Column() {
        Text(this.viewModel.durationText)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .textAlign(TextAlign.Center)
          .width('100%')

        Blank().height(1)

        Text($r('app.string.duration'))
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .layoutWeight(1)

      Column() {
        Text(this.viewModel.yearText)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .textAlign(TextAlign.Center)
          .width('100%')

        Blank().height(1)

        Text($r('app.string.year'))
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
  }

  // ===== Item Divider =====
  @Builder
  ItemDivider() {
    Divider()
      .width('100%')
      .strokeWidth(0.5)
      .color($r('app.color.colorSubTextForeground'))
      .opacity(0.15)
      .margin({ left: 16, right: 16 })
  }

  // ===== Song Sheet Builder (unified: menu or song info) =====
  @Builder
  songSheetBuilder() {
    if (this.showSongInfo) {
      SongInformationComponent({ songInfo: this.viewModel.menuSong })
    } else {
      this.SongMenuSheet()
    }
  }

  // ===== Song Menu Bottom Sheet =====
  @Builder
  SongMenuSheet() {
    SongMenuDialogComponent({
      songInfo: this.viewModel.menuSong,
      onDismiss: () => {
        this.showSongMenuDialog = false
        this.viewModel.closeSongMenu()
      },
      onAddToPlaylist: () => {
        const targetSong = this.viewModel.menuSong
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
        this.viewModel.playNext()
      },
      onShare: () => {
        let context = getContext(this) as common.UIAbilityContext
        this.viewModel.shareSong(context)
      },
      onArtistClick: (artistName: string) => {
        const targetId = this.viewModel.menuSong.id
        // If the target artist page already exists in the nav stack, pop back to it
        const pathNames = this.navPathStack.getAllPathName()
        for (let i = pathNames.length - 1; i >= 0; i--) {
          if (pathNames[i] === 'ArtistContentPage') {
            const param = this.navPathStack.getParamByIndex(i) as ArtistContentRouterParams
            if (param && param.artistName === artistName) {
              this.navPathStack.popToIndex(i)
              return
            }
          }
        }
        const artist = this.viewModel.participatingArtists.find((a: ArtistItemViewModel) => a.name === artistName)
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
        const albumName = this.viewModel.menuSong.album
        if (albumName === this.viewModel.albumTitle) {
          return
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
        this.viewModel.editMusicTag()
      },
      onHearusySpectrum: () => {
        this.viewModel.openHearusySpectrum()
      },
      onEmoScroll: () => {
        this.viewModel.openEmoScroll()
      },
      onSongInfo: () => {
        this.showSongInfo = true
      },
      onRemoveFromLibrary: () => {
        const targetSong = this.viewModel.menuSong
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
        this.viewModel.copyText()
      }
    })
  }
}

// 专辑详情：展示专辑封面、艺术家与该专辑下的曲目列表。
