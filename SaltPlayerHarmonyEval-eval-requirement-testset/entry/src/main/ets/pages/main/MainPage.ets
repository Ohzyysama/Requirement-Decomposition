// MainPage.ets
// View layer: Main page for Salt Player.
// MVVM: This View uses MainPageViewModel for state and logic.
// The View only handles UI rendering and user interaction,
// delegating all business logic and state management to the ViewModel.

import { MiniPlayerContainer, MiniPlayerDefaults } from './MiniPlayerContainer'
import { SongItemComponent, SongInfo } from '../../components/SongItemComponent'
import { SongItemViewModel } from '../../viewmodel/SongItemViewModel'
import RightABCModel from '../../model/RightABCModel'
import { MainMenuComponent } from '../../components/MainMenuComponent'
import { SongSortDialogComponent, SongLazySort } from '../../components/SongSortDialogComponent'
import { SongMenuDialogComponent } from '../../components/SongMenuDialogComponent'
import { AlbumTabComponent } from '../../components/AlbumTabComponent'
import { ArtistItemComponent } from '../../components/ArtistItemComponent'
import { ArtistItemViewModel } from '../../viewmodel/ArtistItemViewModel'
import { FolderContentComponent, SDCardInfo, FolderInfo } from '../../components/FolderContentComponent'
import { PlaylistTabComponent } from '../../components/PlaylistTabComponent'
import { NewPlaylistDialogComponent } from '../../components/NewPlaylistDialogComponent'
import { AddToPlaylistDialogComponent } from '../../components/AddToPlaylistDialogComponent'
import { DeleteSongDialog } from '../../components/DeleteSongDialog'

import { AlbumListSettingsDialogComponent, AlbumSortType } from '../../components/AlbumListSettingsDialogComponent'
import { SettingsPage } from '../SettingsPage'
import { AlbumContentPage, AlbumContentRouterParams } from '../AlbumContentPage'
import { ArtistContentPage } from '../ArtistContentPage'
import { ArtistContentRouterParams } from '../ArtistContentRouterParams'
import { FolderContentPage } from '../FolderContentPage'
import { FolderPathPage } from '../FolderPathPage'
import { SearchAllSongsPage, SearchAllSongsRouterParams } from '../SearchAllSongsPage'
import { MediaSourcePage } from '../MediaSourcePage'
import { MusicLibraryPage } from '../MusicLibraryPage'
import { AboutPage } from '../AboutPage'
import { StatisticsPage } from '../StatisticsPage'
import { UserInterfacePage } from '../UserInterfacePage'
import { MainWallpaperPage } from '../MainWallpaperPage'
import { PlayerWallpaperPage } from '../PlayerWallpaperPage'
import { SaltPlayerProPage } from '../SaltPlayerProPage'
import { AccessibilityPage } from '../AccessibilityPage'
import { CarKitPage } from '../CarKitPage'
import { LyricsSettingsPage } from '../LyricsSettingsPage'
import { LyricsInterfacePage } from '../LyricsInterfacePage'
import { FloatingWindowStatusBarLyricsPage } from '../FloatingWindowStatusBarLyricsPage'
import { common } from '@kit.AbilityKit'
import { promptAction } from '@kit.ArkUI'
import { NotificationPage } from '../NotificationPage'
import { StartupAndBackendPage } from '../StartupAndBackendPage'
import { AudioOutputPage } from '../AudioOutputPage'
import { LanguageSettingsPage } from '../LanguageSettingsPage'
import { LaboratoryPage } from '../LaboratoryPage'
import { HelpAndFeedbackPage } from '../HelpAndFeedbackPage'
import { WindowsPlatformPage } from '../WindowsPlatformPage'
import { WebPage } from '../WebPage'
import { FxActivityPage } from '../FxActivityPage'
import { CreditsPage } from '../CreditsPage'
import { DevPage } from '../DevPage'
import { TabletModePage } from '../TabletModePage'
import { BackgroundMusicProtectionPage } from '../BackgroundMusicProtectionPage'
import { BlockedFoldersPage } from '../BlockedFoldersPage'
import { PlaylistContentPage, PlaylistContentRouterParams } from '../PlaylistContentPage'
import { PlaylistSearchPage } from '../PlaylistSearchPage'
import { SongInformationComponent } from '../SongInformationPage'
import MainPageViewModel from '../../viewmodel/MainPageViewModel'
import { MainPageDataSource } from '../../model/MainPageModel'
import { SongInfoData } from '../../model/SongItemModel'
import AudioPlayerService from '../../model/AudioPlayerService'
import { MusicDatabase } from '../../model/MusicDatabase'
import SettingsStore from '../../model/SettingsStore'
import { vibrator } from '@kit.SensorServiceKit'
import { UserAgreementDialog } from '../../components/UserAgreementDialog'
import { AgreementModel } from '../../model/AgreementModel'

@Entry
@Component
struct MainPage {
  // ========== ViewModel (single source of truth for state and logic) ==========
  @State vm: MainPageViewModel = new MainPageViewModel()
  // First-level @State for album grid minimum columns, so ArkUI can track changes
  // and re-render AlbumTabComponent. @State only observes first-level property changes,
  // so vm.albumListSettingsVM.minimumColumns (second-level) won't trigger re-render.
  @State albumMinColumns: number = (AppStorage.get<number>('albumMinColumns') ?? 2)
  // First-launch agreement gate. Rendered as a top-layer overlay inside the
  // outer Stack of build(). Default true so the UI is blocked until the
  // async hasAgreed() check completes — if we defaulted to false, the main
  // UI would flash before the dialog appears on first launch.
  @State showAgreementDialog: boolean = true
  // ========== Navigation ==========
  private navPathStack: NavPathStack = new NavPathStack()
  // ========== AppStorage synced state ==========
  @StorageLink('currentSongTitle') @Watch('onMiniPlayerDataChanged') currentSongTitle: string = ''
  @StorageLink('currentSongArtist') @Watch('onMiniPlayerDataChanged') currentSongArtist: string = ''
  @StorageLink('currentSongId') @Watch('onMiniPlayerDataChanged') currentSongId: string = ''
  @StorageLink('currentSongCoverUri') @Watch('onMiniPlayerDataChanged') currentSongCoverUri: string = ''
  @StorageLink('isPlaying') @Watch('onMiniPlayerDataChanged') isPlaying: boolean = false
  @StorageLink('hideBottomBar') hideBottomBar: boolean = false
  @StorageProp('scanVersion') @Watch('onScanCompleted') scanVersion: number = 0
  @StorageProp('artistGeoReset') @Watch('onArtistGeoReset') private artistGeoReset: number = 0
  @StorageProp('closePlayerTrigger') @Watch('onClosePlayerRequested') private closePlayerTrigger: number = 0
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  // Bridge the persisted "show cover in song list" setting into the VM so
  // mounted lists refresh live when the user toggles it from Settings → UI.
  // Default `true` matches the value seeded in EntryAbility.onCreate.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')
  private storedDisplaySongCover: boolean = true
  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" setting into the VM
  // so mounted song lists refresh live when the user toggles it from
  // Settings → UI → 歌曲列表. Default `false` matches the persistProp seed.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged')
  private storedDisplaySongFileName: boolean = false
  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" setting into the VM
  // so mounted song lists refresh live when the user toggles it from
  // Settings → UI → 歌曲列表. Default `true` matches the persistProp seed.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
  private storedDisplayAddToPlayNext: boolean = true
  // ========== System bar insets for edge-to-edge padding ==========
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0
  @StorageProp('mainPageWallpaperPath') mainPageWallpaperPath: string = ''
  // ========== Scrollers (UI-only, not in ViewModel) ==========
  private listScroller: Scroller = new Scroller()
  private artistListScroller: Scroller = new Scroller()
  // ========== AlphabetIndexer Selected State ==========
  @State private songAlphabetSelected: number = 0
  @State private artistAlphabetSelected: number = 0
  // Custom popup state for AlphabetIndexer (shared across tabs)
  @State private alphabetPopupLetter: string = ''
  @State private alphabetPopupVisible: boolean = false
  // ========== Custom Sort Drag Reorder State ==========
  @State private isDragReordering: boolean = false
  @State private dragSongId: string = ''
  @State private dragConsumedOffset: number = 0
  @State private dragCurrentOffsetY: number = 0
  @State private pendingShowSongInfo: boolean = false // Flag to open song info after menu closes
  // Auto-scroll when dragging near list edges
  private dragAutoScrollTimer: number = -1
  private songListAreaRect: Area | null = null
  private dragAutoScrollAccum: number = 0 // cumulative auto-scroll distance (+ = scrolled down)
  private dragLastEventOffsetY: number = 0 // last event.offsetY from PanGesture
  // ========== Dialog Controllers ==========
  private newPlaylistDialogController: CustomDialogController = new CustomDialogController({
    builder: NewPlaylistDialogComponent({
      onConfirm: (name: string) => {
        this.vm.addPlaylist(name)
      },
      onCancel: () => {
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: '#80000000'
  })
  private addToPlaylistDialogController?: CustomDialogController
  private deleteSongDialogController?: CustomDialogController

  // ========== @Watch: Sync AppStorage data into ViewModel ==========
  onMiniPlayerDataChanged(): void {
    this.vm.syncMiniPlayerData(this.currentSongTitle, this.currentSongArtist, this.isPlaying,
      this.currentSongId, this.currentSongCoverUri)
  }

  // Refresh song list when scan completes
  onScanCompleted(): void {
    this.vm.refreshSongList()
  }

  // Forward AppStorage 'displaySongCover' writes into the VM so the song
  // list re-renders live when the user toggles the setting from Settings → UI.
  onDisplaySongCoverChanged(): void {
    this.vm.setDisplaySongCoverInList(this.storedDisplaySongCover)
  }

  // spec21 — Forward AppStorage 'displaySongFileName' writes into the VM so
  // the song list re-renders live when the user toggles it from Settings → UI.
  onDisplaySongFileNameChanged(): void {
    this.vm.setDisplaySongFileNameInList(this.storedDisplaySongFileName)
  }

  // spec22 — Forward AppStorage 'displayAddToPlayNext' writes into the VM so
  // the song list re-renders live when the user toggles it from Settings → UI.
  onDisplayAddToPlayNextChanged(): void {
    this.vm.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
  }

  // Reset geometry transition on artist items after ArtistContentPage pops
  onArtistGeoReset(): void {
    for (const artist of this.vm.artistList) {
      if (artist.geoActive) {
        artist.geoActive = false
      }
    }
  }

  // Triggered by NavDestination pages (e.g. AlbumContentPage) via AppStorage
  // when they intercept a back press while the player overlay is open.
  onClosePlayerRequested(): void {
    if (this.vm.showPlayer) {
      const playerPage = (AppStorage.get('playerCurrentPage') as number) ?? 0
      if (playerPage === 1) {
        const trigger = (AppStorage.get('playerBackToPlayer') as number) ?? 0
        AppStorage.setOrCreate('playerBackToPlayer', trigger + 1)
      } else {
        this.vm.closePlayerAnimated((params: AnimateParam, cb: () => void) => {
          this.getUIContext().animateTo(params, cb)
        })
      }
    }
  }

  /**
   * System back press handler.
   * Mirrors Android MainActivity's two BackHandlers:
   *  1. Queue visible (currentPage=1) → scroll back to player
   *  2. Player visible → close player
   * Returns true to consume the event, false to let the system handle it (exit app).
   */
  onBackPress(): boolean {
    // 1. Player overlay is showing
    if (this.vm.showPlayer) {
      const playerPage = (AppStorage.get('playerCurrentPage') as number) ?? 0
      if (playerPage === 1) {
        // Queue is showing → trigger PlayerPage to scroll back to player
        const trigger = (AppStorage.get('playerBackToPlayer') as number) ?? 0
        AppStorage.setOrCreate('playerBackToPlayer', trigger + 1)
        return true
      }
      // Player page is showing → animated drawer close
      this.vm.closePlayerAnimated((params: AnimateParam, cb: () => void) => {
        this.getUIContext().animateTo(params, cb)
      })
      return true
    }
    // 2. Drawer is open → close drawer
    if (this.vm.isDrawerOpen) {
      this.vm.closeDrawer((params: AnimateParam, cb: () => void) => {
        this.getUIContext().animateTo(params, cb)
      })
      return true
    }
    // Let system handle (pop NavPathStack or exit app)
    return false
  }

  // ========== Drag Auto-Scroll Helpers ==========
  private startDragAutoScroll(direction: number): void {
    // direction: -1 = scroll up (finger near top), 1 = scroll down (finger near bottom)
    if (this.dragAutoScrollTimer !== -1) {
      return
    }
    const SCROLL_SPEED = 8 // vp per tick
    const INTERVAL = 16 // ms (~60fps)
    this.dragAutoScrollTimer = setInterval(() => {
      if (!this.isDragReordering) {
        this.stopDragAutoScroll()
        return
      }
      this.listScroller.scrollBy(0, direction * SCROLL_SPEED)
      // Accumulate scroll distance so the dragged item follows
      this.dragAutoScrollAccum += direction * SCROLL_SPEED
      this.applyDragOffset(this.dragLastEventOffsetY)
    }, INTERVAL)
  }

  // Unified offset logic: computes visual offset and triggers item moves.
  // Called from both PanGesture.onActionUpdate and the auto-scroll timer.
  private applyDragOffset(eventOffsetY: number): void {
    const effectiveOffset = eventOffsetY + this.dragAutoScrollAccum
    const remaining = effectiveOffset - this.dragConsumedOffset

    const currentIndex =
      this.vm.songList.findIndex((s: SongInfo) => s.id === this.dragSongId)
    if (currentIndex < 0) {
      this.dragCurrentOffsetY = remaining
      return
    }
    const steps = Math.round(remaining / 72)
    if (steps !== 0) {
      const targetIndex =
        Math.max(0, Math.min(this.vm.songList.length - 1, currentIndex + steps))
      if (targetIndex !== currentIndex) {
        this.vm.moveSong(currentIndex, targetIndex)
        this.dragConsumedOffset += (targetIndex - currentIndex) * 72
      }
    }
    // Clamp visual offset so the item can't be dragged beyond list boundaries
    const maxDown = (this.vm.songList.length - 1 - currentIndex) * 72
    const maxUp = -currentIndex * 72
    this.dragCurrentOffsetY = Math.max(maxUp, Math.min(maxDown,
      effectiveOffset - this.dragConsumedOffset))
  }

  private stopDragAutoScroll(): void {
    if (this.dragAutoScrollTimer !== -1) {
      clearInterval(this.dragAutoScrollTimer)
      this.dragAutoScrollTimer = -1
    }
  }

  private updateDragAutoScroll(fingerScreenY: number): void {
    if (!this.songListAreaRect) {
      this.stopDragAutoScroll()
      return
    }
    const listTop = this.songListAreaRect.globalPosition as Position
    const listHeight = this.songListAreaRect.height as number
    const EDGE_ZONE = 80 // vp from edge to trigger auto-scroll
    const relativeY = fingerScreenY - (listTop.y as number ?? 0)

    if (relativeY < EDGE_ZONE) {
      // Near top edge — scroll up
      if (this.dragAutoScrollTimer === -1) {
        this.startDragAutoScroll(-1)
      }
    } else if (relativeY > listHeight - EDGE_ZONE) {
      // Near bottom edge — scroll down
      if (this.dragAutoScrollTimer === -1) {
        this.startDragAutoScroll(1)
      }
    } else {
      this.stopDragAutoScroll()
    }
  }

  aboutToAppear(): void {
    // First-launch agreement gate: only show the dialog when the preference
    // is NOT already set. Default showAgreementDialog is true so the UI is
    // blocked until this async read resolves; here we flip it to false as
    // soon as we confirm a previous acceptance, avoiding a flash of the
    // dialog for returning users.
    const context = getContext(this) as common.UIAbilityContext
    AgreementModel.hasAgreed(context).then((agreed: boolean) => {
      if (agreed) {
        this.showAgreementDialog = false
      }
    })

    // Lightweight init: restores UI state and sets up callbacks (no data loading)
    this.vm.initialize()
    this.vm.playlistTabViewModel.onPlaylistClickAction = (playlistId: string) => {
      const playlist = this.vm.playlistTabViewModel.playlistItems.find(p => p.id === playlistId)
      this.navPathStack.pushPath({
        name: 'PlaylistContentPage',
        param: {
          playlistId: playlistId,
          playlistName: playlist?.name ?? '',
          playlistSongCount: playlist?.count ?? 0,
        } as PlaylistContentRouterParams
      })
    }
    this.vm.playlistTabViewModel.onExportPlaylistAction = (playlistId: string) => {
      this.vm.exportPlaylistToTxt(getContext(this) as common.UIAbilityContext, playlistId)
    }
    this.albumMinColumns = this.vm.albumListSettingsVM.minimumColumns

    // If DB load already finished in EntryAbility (cache is populated),
    // @Watch('scanVersion') won't fire for the initial value, so load data now.
    // Otherwise, onScanCompleted() will trigger when loadFromDatabase() completes.
    if (MainPageDataSource.hasData()) {
      this.vm.refreshSongList()
    }

    // Intercept NavPathStack POP operations when the player overlay is open.
    // Without this, system back on any NavDestination page (ArtistContentPage,
    // settings pages, etc.) pops the page instead of closing the player, because
    // @Entry.onBackPress() only fires when the NavPathStack is empty.
    // Mirrors Android's BackHandler(enabled = playerIsExpanded) priority.
    this.navPathStack.setInterception({
      willShow: (from: NavDestinationContext | NavBar, to: NavDestinationContext | NavBar,
        operation: NavigationOperation, isAnimated: boolean) => {
        if (operation === NavigationOperation.POP && this.vm.showPlayer) {
          // Re-push the popped page to cancel the pop, then close the player.
          const fromCtx = from as NavDestinationContext
          if (fromCtx?.pathInfo) {
            this.navPathStack.pushPathByName(fromCtx.pathInfo.name, fromCtx.pathInfo.param, false)
          }
          // Close player (with queue-page check)
          const playerPage = (AppStorage.get('playerCurrentPage') as number) ?? 0
          if (playerPage === 1) {
            const trigger = (AppStorage.get('playerBackToPlayer') as number) ?? 0
            AppStorage.setOrCreate('playerBackToPlayer', trigger + 1)
          } else {
            this.vm.closePlayerAnimated((params: AnimateParam, cb: () => void) => {
              this.getUIContext().animateTo(params, cb)
            })
          }
        }
      }
    })

    // Initialize MiniPlayerViewModel callbacks
    this.vm.initMiniPlayer(
      this.currentSongTitle,
      this.currentSongArtist,
      this.isPlaying,
      () => {
        AudioPlayerService.getInstance().togglePlayPause()
      },
      () => {
        this.vm.openPlayerWithQueue((params: AnimateParam, cb: () => void) => {
          this.getUIContext().animateTo(params, cb)
        })
      },
      () => {
        this.vm.openPlayerAnimated((params: AnimateParam, cb: () => void) => {
          this.getUIContext().animateTo(params, cb)
        })
      },
      (event: TouchEvent) => {
        this.vm.handleMiniPlayerTouch(event, (params: AnimateParam, cb: () => void) => {
          this.getUIContext().animateTo(params, cb)
        })
      }
    )

    // Manually trigger initial sync including cover art loading.
    // @Watch does NOT fire for the initial PersistentStorage-restored values,
    // so we must explicitly load the cover here.
    this.vm.syncMiniPlayerData(this.currentSongTitle, this.currentSongArtist, this.isPlaying,
      this.currentSongId, this.currentSongCoverUri)

    // Spec9 Scene 3: if the Laboratory "启动软件自动打开播放界面" toggle is on,
    // open the fullscreen player immediately after UI/VM init. No animation —
    // avoids the one-frame flash of the main page. Placed after
    // syncMiniPlayerData so PlayerPage mounts onto the correct current-song
    // metadata.
    if (AppStorage.get<boolean>('autoOpenPlaybackScreen') === true) {
      this.vm.openPlayerImmediate()
    }

    // Spec10: if 启动与后台 → 自动播放 is on and EntryAbility restored a valid
    // current song, resume playback at the saved position and toast 自动播放.
    // VM-internal flag prevents double-fire across re-entries of aboutToAppear.
    this.vm.autoPlaybackOnLaunchIfEnabled()
  }

  build() {
    Stack() {
      // ========== Wallpaper (behind everything) ==========
      if (this.mainPageWallpaperPath.length > 0) {
        Image(this.mainPageWallpaperPath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }

      // ========== Main Page Content ==========
      // ========== Navigation Container ==========
      Navigation(this.navPathStack) {
        // ========== Push Drawer Area ==========
        Stack({ alignContent: Alignment.TopStart }) {
          // ========== Sidebar ==========
          Column() {
            MainMenuComponent({
              onMenuItemClick: (route: string) => {
                if (this.vm.blockClickAfterSwipe) {
                  return
                }
                const navRoute = this.vm.handleMenuNavigation(route)
                if (navRoute.length > 0) {
                  this.navPathStack.pushPath({ name: navRoute })
                }
              },
              onCloseMenu: () => {
                this.vm.closeDrawer((params: AnimateParam, cb: () => void) => {
                  this.getUIContext().animateTo(params, cb)
                })
              }
            })
          }
          .width(this.vm.sidebarWidthVp)
          .height('100%')
          .translate({ x: this.vm.drawerOffset - this.vm.sidebarWidthVp })

          // ========== Main Content ==========
          Stack() {
            Column() {
              // ========== Title Bar ==========
              this.TitleBar()

              // ========== Main Content Area ==========
              if (this.vm.currentTab === 'song') {
                this.SongTabContent()
              } else if (this.vm.currentTab === 'album') {
                this.AlbumTabContent()
              } else if (this.vm.currentTab === 'playlist') {
                this.PlaylistTabContent()
              } else if (this.vm.currentTab === 'artist') {
                this.ArtistTabContent()
              } else if (this.vm.currentTab === 'folder') {
                this.FolderTabContent()
              } else {
                this.PlaceholderTabContent()
              }
            }
            .width('100%')
            .height('100%')
            .padding({ top: this.statusBarHeight })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
          .translate({ x: this.vm.drawerOffset })
        }
        .width('100%')
        .clip(true)
        .onTouch((event: TouchEvent) => {
          this.vm.handleDrawerTouch(event, (params: AnimateParam, cb: () => void) => {
            this.getUIContext().animateTo(params, cb)
          })
        })
        .layoutWeight(1)
      }
      .navDestination(this.pageMap)
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      .width('100%')
      .height('100%')

      MiniPlayerContainer({
        vm: this.vm,
        onNavigateToAlbum: (albumTitle: string) => {
          // Close the full-screen player overlay first so the destination page
          // is visible (mirrors the song-menu album-click handler below).
          this.vm.closePlayer()
          const album = this.vm.albumList.find(a => a.title === albumTitle)
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
        onNavigateToArtist: (artistName: string) => {
          this.vm.closePlayer()
          const artist = this.vm.artistList.find(a => a.name === artistName)
          this.navPathStack.pushPath({
            name: 'ArtistContentPage',
            param: {
              artistId: artist?.id ?? '',
              artistName: artistName,
              artistCoverUri: artist?.coverUri ?? '',
              artistCoverSongId: artist?.coverSongId ?? ''
            } as ArtistContentRouterParams
          })
        }
      })
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .bindSheet($$this.vm.showSongSheet, this.songSheetBuilder(), {
          detents: [SheetSize.FIT_CONTENT, '66%', SheetSize.LARGE],
          preferType: SheetType.BOTTOM,
          dragBar: false,
          showClose: false,
          backgroundColor: this.vm.showSongInfo ? $r('app.color.colorPageBackground')
            : (this.isSystemDark ? $r('app.color.colorItemBackground') : $r('app.color.salt_color_sub_background')),
          onDisappear: () => {
            // Only reset secondary state (which content to show inside the sheet).
            // Do NOT reset showSongSheet here — it is already managed by the $$
            // two-way binding (gesture dismiss) and onDismiss (programmatic dismiss).
            // Resetting it in onDisappear causes a race condition: if the user
            // re-opens the sheet before this callback fires, the late reset
            // clobbers the new 'true' state and the sheet retracts.
            this.vm.showSongMenu = false
            this.vm.showSongInfo = false
          }
        })

      // ========== First-Launch Agreement Overlay ==========
      // Mounted as the last child of the outer Stack so it renders on top
      // of everything else. Controlled by @State showAgreementDialog which
      // defaults to true and is flipped to false once AgreementModel
      // confirms prior acceptance (see aboutToAppear).
      if (this.showAgreementDialog) {
        UserAgreementDialog({
          showDialog: $showAgreementDialog,
        })
      }
    }
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      this.vm.updateScreenSize(newValue.width as number, newValue.height as number)
    })
  }

  // ======================== Song Tab Content ========================
  @Builder
  SongTabContent() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.vm.songList.length > 0) {
          if (this.vm.multiChoiceMode) {
            this.MultiChoiceTopBar()
          } else {
            this.ToolbarRow()
          }
        }
        this.SongListArea()
        if (this.vm.multiChoiceMode) {
          this.MultiChoiceBottomBar()
        }
      }
      .width('100%')
      .height('100%')

      if (this.vm.showRightABC && this.vm.songList.length > 0) {
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

          AlphabetIndexer({ arrayValue: new RightABCModel().alphabetArray, selected: $$this.songAlphabetSelected })
            .onSelect((index: number) => {
              const char = new RightABCModel().alphabetArray[index]
              this.vm.scrollToChar(char, this.listScroller)
              this.alphabetPopupLetter = char
              this.alphabetPopupVisible = true
              vibrator.startVibration({ type: 'time', duration: 20 }, { id: 0, usage: 'touch' })
            })
            .selectedColor($r('app.color.colorSubTextForeground'))
            .selectedBackgroundColor(Color.Transparent)
            .usingPopup(false)
            .autoCollapse(false)
            .selectedFont({ size: 10, weight: FontWeight.Bold })
            .font({ size: 10 })
            .itemSize(15)
            .alignStyle(IndexerAlign.Left)
            .hitTestBehavior(HitTestMode.Block)
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
      }

      if (this.vm.songList.length > 0 && !this.vm.multiChoiceMode) {
        this.LocateCurrentSongButton()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  // ======================== Album Tab Content ========================
  @Builder
  AlbumTabContent() {
    AlbumTabComponent({
      albumDataSource: this.vm.albumDataSource,
      albumYearDataSource: this.vm.albumYearDataSource,
      albumCount: this.vm.albumList.length,
      albumSortType: this.vm.albumListSettingsVM.albumSortType,
      minimumColumns: this.albumMinColumns,
      isDataLoading: this.vm.isDataLoading,
      onAlbumClick: (albumId: string) => {
        if (this.vm.blockClickAfterSwipe) {
          return
        }
        const album = this.vm.albumList.find(a => a.id === albumId)
        this.navPathStack.pushPath({
          name: 'AlbumContentPage',
          param: {
            albumId: albumId,
            albumTitle: album?.title ?? '',
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
      onSettingsClick: () => {
        this.vm.openAlbumListSettings()
      },
      onScanMusicClick: () => {
        this.navPathStack.pushPath({ name: 'MediaSourcePage' })
      }
    })
      .layoutWeight(1)
      .width('100%')
  }

  // ======================== Playlist Tab Content ========================
  @Builder
  PlaylistTabContent() {
    PlaylistTabComponent({
      viewModel: this.vm.playlistTabViewModel
    })
      .layoutWeight(1)
      .width('100%')
  }

  // ======================== Artist Tab Content ========================
  @Builder
  ArtistTabContent() {
    Stack({ alignContent: Alignment.End }) {
      if (this.vm.artistList.length > 0) {
        List({ scroller: this.artistListScroller }) {
          LazyForEach(this.vm.artistDataSource, (artist: ArtistItemViewModel) => {
            ListItem() {
              ArtistItemComponent({
                artistVM: artist,
                onItemClick: () => {
                  if (this.vm.blockClickAfterSwipe) {
                    return
                  }
                  this.navPathStack.pushPath({
                    name: 'ArtistContentPage',
                    param: {
                      artistId: artist.id,
                      artistName: artist.name,
                      artistCoverUri: artist.coverUri,
                      artistCoverSongId: artist.coverSongId
                    } as ArtistContentRouterParams
                  })
                }
              })
            }
          }, (artist: ArtistItemViewModel) => artist.id)
        }
        .width('100%')
        .height('100%')
        .padding({ right: 20 })
        .contentEndOffset(96)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      } else if (!this.vm.isDataLoading) {
        Column() {
          Button($r('app.string.scan_music'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.salt_color_high_light'))
            .borderRadius(24)
            .onClick(() => {
              this.navPathStack.pushPath({ name: 'MediaSourcePage' })
            })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 8 })
      }

      if (this.vm.artistList.length > 0) {
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

          AlphabetIndexer({ arrayValue: new RightABCModel().alphabetArray, selected: $$this.artistAlphabetSelected })
            .onSelect((index: number) => {
              const char = new RightABCModel().alphabetArray[index]
              this.vm.scrollArtistToChar(char, this.artistListScroller)
              this.alphabetPopupLetter = char
              this.alphabetPopupVisible = true
              vibrator.startVibration({ type: 'time', duration: 20 }, { id: 0, usage: 'touch' })
            })
            .selectedColor($r('app.color.colorSubTextForeground'))
            .selectedBackgroundColor(Color.Transparent)
            .usingPopup(false)
            .autoCollapse(false)
            .selectedFont({ size: 10, weight: FontWeight.Bold })
            .font({ size: 10 })
            .itemSize(15)
            .alignStyle(IndexerAlign.Left)
            .hitTestBehavior(HitTestMode.Block)
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
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  // ======================== Folder Tab Content ========================
  @Builder
  FolderTabContent() {
    FolderContentComponent({
      sdCards: this.vm.sdCards,
      folders: this.vm.folderList,
      onSDCardClick: (path: string) => {
        if (this.vm.blockClickAfterSwipe) {
          return
        }
        this.navPathStack.pushPath({
          name: 'FolderPathPage',
          param: {
            'path': path,
            'title': path === '/storage/emulated/0' ? '\u5185\u90e8\u5b58\u50a8' : path.split('/').pop() || path
          } as Record<string, string>
        })
      },
      onFolderClick: (folderPath: string) => {
        if (this.vm.blockClickAfterSwipe) {
          return
        }
        const rawName = folderPath.split('/').pop() || folderPath
        let folderName = rawName
        try {
          folderName = decodeURIComponent(rawName)
        } catch (e) {
          // Use raw name if decode fails
        }
        const folderParams: Record<string, string | boolean> = {
          'folderPath': folderPath,
          'folderName': folderName
        }
        this.navPathStack.pushPath({
          name: 'FolderContentPage',
          param: folderParams
        })
      },
      onFolderMenuClick: (folder: FolderInfo) => {
        console.info('TODO: handle folder menu click')
      },
      onHideFolderConfirmed: () => {
        this.vm.refreshFolderList()
      }
    })
      .layoutWeight(1)
      .width('100%')
  }

  // ======================== Placeholder Tab Content ========================
  @Builder
  PlaceholderTabContent() {
    Column() {
      Text(`${this.vm.currentTab} tab`)
        .fontSize(14)
        .fontColor($r('app.color.colorSubTextForeground'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ======================== Page Map for Navigation ========================
  @Builder
  pageMap(name: string) {
    if (name === 'SettingsPage') {
      SettingsPage()
    } else if (name === 'AlbumContentPage') {
      AlbumContentPage()
    } else if (name === 'ArtistContentPage') {
      ArtistContentPage()
    } else if (name === 'FolderContentPage') {
      FolderContentPage()
    } else if (name === 'FolderPathPage') {
      FolderPathPage()
    } else if (name === 'SearchAllSongsPage') {
      SearchAllSongsPage()
    } else if (name === 'MediaSourcePage') {
      MediaSourcePage()
    } else if (name === 'MusicLibraryPage') {
      MusicLibraryPage()
    } else if (name === 'AboutPage') {
      AboutPage()
    } else if (name === 'StatisticsPage') {
      StatisticsPage()
    } else if (name === 'UserInterfacePage') {
      UserInterfacePage()
    } else if (name === 'MainWallpaperPage') {
      MainWallpaperPage()
    } else if (name === 'PlayerWallpaperPage') {
      PlayerWallpaperPage()
    } else if (name === 'SaltPlayerProPage') {
      SaltPlayerProPage()
    } else if (name === 'AccessibilityPage') {
      AccessibilityPage()
    } else if (name === 'CarKitPage') {
      CarKitPage()
    } else if (name === 'LyricsSettingsPage') {
      LyricsSettingsPage()
    } else if (name === 'LyricsInterfacePage') {
      LyricsInterfacePage()
    } else if (name === 'FloatingWindowStatusBarLyricsPage') {
      FloatingWindowStatusBarLyricsPage()
    } else if (name === 'NotificationPage') {
      NotificationPage()
    } else if (name === 'StartupAndBackendPage') {
      StartupAndBackendPage()
    } else if (name === 'AudioOutputPage') {
      AudioOutputPage()
    } else if (name === 'LanguageSettingsPage') {
      LanguageSettingsPage()
    } else if (name === 'LaboratoryPage') {
      LaboratoryPage()
    } else if (name === 'HelpAndFeedbackPage') {
      HelpAndFeedbackPage()
    } else if (name === 'WindowsPlatformPage') {
      WindowsPlatformPage()
    } else if (name === 'WebPage') {
      WebPage()
    } else if (name === 'FxActivityPage') {
      FxActivityPage()
    } else if (name === 'CreditsPage') {
      CreditsPage()
    } else if (name === 'DevPage') {
      DevPage()
    } else if (name === 'TabletModePage') {
      TabletModePage()
    } else if (name === 'BackgroundMusicProtectionPage') {
      BackgroundMusicProtectionPage()
    } else if (name === 'BlockedFoldersPage') {
      BlockedFoldersPage()
    } else if (name === 'PlaylistContentPage') {
      PlaylistContentPage()
    } else if (name === 'PlaylistSearchPage') {
      PlaylistSearchPage()
    }
  }

  // ======================== Title Bar ========================
  @Builder
  TitleBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.vm.getTitleResource())
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .padding({ left: 56, right: 56 })
        .width('100%')

      // Left: Menu icon
      Image($r('app.media.ic_menu'))
        .width(56)
        .height(56)
        .padding(16)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .position({ x: 0, y: 0 })
        .onClick(() => {
          this.vm.toggleDrawer((params: AnimateParam, cb: () => void) => {
            this.getUIContext().animateTo(params, cb)
          })
        })
        .accessibilityText('\u83dc\u5355')

      // Right icon
      if (this.vm.currentTab === 'song') {
        Image($r('app.media.ic_search'))
          .width(56)
          .height(56)
          .padding(17)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .position({ x: '100%', y: 0 })
          .translate({ x: -56 })
          .onClick(() => {
            this.navPathStack.pushPath({
              name: 'SearchAllSongsPage',
              param: {
                validCount: this.vm.songList.length,
                currentSongTitle: this.currentSongTitle,
                currentSongArtist: this.currentSongArtist,
                isPlaying: this.isPlaying
              } as SearchAllSongsRouterParams
            })
          })
          .accessibilityText('\u641c\u7d22')
      } else if (this.vm.currentTab === 'album') {
        Image($r('app.media.ic_rows'))
          .width(56)
          .height(56)
          .padding(17.5)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .position({ x: '100%', y: 0 })
          .translate({ x: -56 })
          .onClick(() => {
            this.vm.openAlbumListSettings()
          })
          .accessibilityText($r('app.string.album_list_settings'))
          .bindSheet($$this.vm.showAlbumListSettings, this.albumListSettingsDialogBuilder(), {
            detents: ['60%', SheetSize.LARGE],
            dragBar: false,
            showClose: false,
            backgroundColor: this.isSystemDark ? $r('app.color.colorPageBackground') :
              $r('app.color.salt_color_sub_background'),
            onDisappear: () => {
              this.vm.closeAlbumListSettings()
            }
          })
      } else if (this.vm.currentTab === 'folder') {
        Image($r('app.media.ic_search'))
          .width(56)
          .height(56)
          .padding(17)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .position({ x: '100%', y: 0 })
          .translate({ x: -56 })
          .onClick(() => {
            this.navPathStack.pushPath({
              name: 'SearchAllSongsPage',
              param: {
                validCount: this.vm.songList.length,
                currentSongTitle: this.currentSongTitle,
                currentSongArtist: this.currentSongArtist,
                isPlaying: this.isPlaying
              } as SearchAllSongsRouterParams
            })
          })
          .accessibilityText('\u641c\u7d22')
      } else if (this.vm.currentTab === 'playlist') {
        Image($r('app.media.ic_more_vert'))
          .width(56)
          .height(56)
          .padding(17.75)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .position({ x: '100%', y: 0 })
          .translate({ x: -56 })
          .onClick(() => {
            this.vm.togglePlaylistPopupMenu()
          })
          .bindPopup(this.vm.showPlaylistPopupMenu, {
            builder: this.playlistPopupMenuBuilder(),
            placement: Placement.BottomRight,
            popupColor: $r('app.color.salt_color_white'),
            enableArrow: false,
            radius: 16,
            shadow: {
              radius: 24,
              color: '#30000000',
              offsetY: 4
            },
            onStateChange: (e: PopupStateChangeParam) => {
              if (!e.isVisible) {
                this.vm.closePlaylistPopupMenu()
              }
            }
          })
      }
    }
    .width('100%')
    .height(56)
  }

  // ======================== Toolbar Row ========================
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

        Text(this.vm.songList.length.toString())
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ left: 6 })
      }
      .height(40)
      .padding({ left: 8, right: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.vm.randomPlay()
      })
      .accessibilityText('\u968f\u673a\u64ad\u653e(' + this.vm.songList.length.toString() + ')')

      Blank()
        .layoutWeight(1)
        .height(40)
        .gesture(
          TapGesture({ count: 2 })
            .onAction(() => {
              this.listScroller.scrollToIndex(0)
            })
        )

      Image($r('app.media.ic_sort'))
        .width(48)
        .height(40)
        .padding({
          left: 18,
          right: 10,
          top: 10,
          bottom: 10
        })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.vm.showSortDialog = true
        })
        .accessibilityText('\u6392\u5e8f')
        .bindSheet($$this.vm.showSortDialog, this.sortDialogBuilder(), {
          detents: [SheetSize.FIT_CONTENT],
          dragBar: false,
          showClose: false,
          backgroundColor: this.isSystemDark ? $r('app.color.colorPageBackground') :
            $r('app.color.salt_color_sub_background'),
          onDisappear: () => {
            this.vm.showSortDialog = false
          }
        })

      Image($r('app.media.ic_multiple_choice'))
        .width(48)
        .height(40)
        .padding({
          left: 9,
          right: 17,
          top: 10,
          bottom: 10
        })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.vm.enterMultiChoiceMode()
        })
        .accessibilityText('\u591a\u9009')
    }
    .width('100%')
    .height(40)
    .padding({ right: 2 })
  }

  // ======================== Song List Area ========================
  @Builder
  SongListArea() {
    if (this.vm.songList.length === 0 && !this.vm.isDataLoading) {
      Column() {
        Button($r('app.string.scan_music'))
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(24)
          .onClick(() => {
            this.navPathStack.pushPath({ name: 'MediaSourcePage' })
          })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 16, right: 16, top: 8 })
    } else {
      Refresh({ refreshing: $$this.vm.isRefreshing }) {
        List({ scroller: this.listScroller }) {
          LazyForEach(this.vm.songDataSource, (song: SongInfo) => {
            ListItem() {
              SongItemComponent({
                viewModel: SongItemViewModel.create(song, {
                  isCurrent: song.id === this.vm.currentSongId,
                  showCover: this.vm.displaySongCoverInList,
                  displayFileName: this.vm.displaySongFileNameInList,
                  displayAddToPlayNext: this.vm.displayAddToPlayNextInList,
                  multiChoiceMode: this.vm.multiChoiceMode,
                  checked: this.vm.checkedMap[song.id] === true,
                  onItemClickAction: () => {
                    if (this.vm.blockClickAfterSwipe) {
                      return
                    }
                    if (song.id === this.vm.currentSongId && this.isPlaying) {
                      this.vm.openPlayerAnimated((params: AnimateParam, cb: () => void) => {
                        this.getUIContext().animateTo(params, cb)
                      })
                    } else {
                      this.vm.currentSongId = song.id
                      this.currentSongTitle = song.title
                      this.currentSongArtist = song.artist
                      this.currentSongId = song.id
                      this.currentSongCoverUri = song.coverUri
                      this.vm.playSong(song.id, song.title, song.artist, song.fileUri)
                    }
                  },
                  onItemLongClickAction: () => {
                    // In custom sort mode, long press is handled by drag gesture
                    if (this.vm.songLazySort !== SongLazySort.NONE) {
                      this.vm.openSongMenu(song)
                    }
                  },
                  onMenuClickAction: () => {
                    this.vm.openSongMenu(song)
                  },
                  onAddToPlayNextAction: () => {
                    this.vm.addToPlayNext(song)
                  },
                  onCheckedChangeAction: (checked: boolean) => {
                    this.vm.updateSongChecked(song.id, checked)
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
                    if (this.vm.songLazySort !== SongLazySort.NONE || this.vm.multiChoiceMode) {
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
                    if (!this.isDragReordering) {
                      return
                    }
                    // Save for auto-scroll timer to reuse
                    this.dragLastEventOffsetY = event.offsetY

                    // Auto-scroll when finger is near list edges
                    const finger = event.fingerList[0]
                    if (finger) {
                      this.updateDragAutoScroll(finger.globalY)
                    }

                    // Update visual offset and trigger item moves
                    this.applyDragOffset(event.offsetY)
                  })
                  .onActionEnd(() => {
                    this.stopDragAutoScroll()
                    this.isDragReordering = false
                    this.dragSongId = ''
                    this.dragCurrentOffsetY = 0
                    this.dragConsumedOffset = 0
                    this.dragAutoScrollAccum = 0
                    this.dragLastEventOffsetY = 0
                  })
                  .onActionCancel(() => {
                    this.stopDragAutoScroll()
                    this.isDragReordering = false
                    this.dragSongId = ''
                    this.dragCurrentOffsetY = 0
                    this.dragConsumedOffset = 0
                    this.dragAutoScrollAccum = 0
                    this.dragLastEventOffsetY = 0
                  })
              )
            )
            // scanVersion is mixed into the key so that pull-to-refresh and
            // scan-complete events force LazyForEach to discard cached items
            // and re-run the builder against the freshly mutated SongInfoData
            // (e.g. a backfilled quality tag). With song.id alone, stable keys
            // make the framework reuse existing components, which kept the old
            // quality value visible until the user navigated away and back.
          }, (song: SongInfo) => song.id + ':' + this.scanVersion)
        }
        .width('100%')
        .height('100%')
        .cachedCount(5)
        .padding({ right: 2 })
        .contentEndOffset(96)
        .scrollBar(this.vm.showRightABC ? BarState.Off : BarState.Auto)
        .edgeEffect(EdgeEffect.None)
        .enableScrollInteraction(!this.isDragReordering)
        .onAreaChange((_: Area, newArea: Area) => {
          this.songListAreaRect = newArea
        })
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.SELF_FIRST
        })
      }
      .layoutWeight(1)
      .onRefreshing(() => {
        this.vm.handleRefresh(getContext(this) as common.UIAbilityContext)
      })
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
        this.vm.locateCurrentSong(this.listScroller)
      })
    }
    .width(56)
    .height(96)
    .margin({ right: 2, bottom: 84 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText('\u5b9a\u4f4d\u5f53\u524d\u64ad\u653e\u6b4c\u66f2')
  }

  // ======================== Multi Choice Top Bar ========================
  @Builder
  MultiChoiceTopBar() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.vm.checkedCount === this.vm.songList.length ? '\u53d6\u6d88\u5168\u9009' : '\u5168\u9009')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_high_light'))
        .position({ x: 16, y: 0 })
        .height(40)
        .onClick(() => {
          this.vm.toggleSelectAll()
        })

      Text(`\u5df2\u9009\u4e2d ${this.vm.checkedCount} \u9879`)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))

      Image($r('app.media.ic_cancel'))
        .width(48)
        .height(40)
        .padding({
          left: 9,
          right: 17,
          top: 10,
          bottom: 10
        })
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .position({ x: '100%', y: 0 })
        .translate({ x: -48 })
        .onClick(() => {
          this.vm.exitMultiChoiceMode()
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
        this.vm.removeSelectedFromLibrary()
      })
      this.MultiChoiceControlItem($r('app.media.ic_add'), '\u6dfb\u52a0\u5230\u6b4c\u5355', () => {
        setTimeout(() => {
          this.addToPlaylistDialogController = new CustomDialogController({
            builder: AddToPlaylistDialogComponent({
              songId: '',
              selectedSongIds: this.vm.getSelectedSongIdsInOrder(),
              onPlaylistSelected: (playlistId: string, playlistName: string) => {
                promptAction.showToast({ message: `添加到${playlistName}` })
                this.vm.exitMultiChoiceMode()
              },
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
      this.MultiChoiceControlItem($r('app.media.ic_playlist_add_24'), '\u64ad\u653e\u9009\u4e2d\u961f\u5217', () => {
        this.vm.playSelectedQueue()
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
        .fillColor(this.vm.checkedCount > 0 ?
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
    .opacity(this.vm.checkedCount > 0 ? 1.0 : 0.5)
    .onClick(() => {
      if (this.vm.checkedCount > 0) {
        onClick()
      }
    })
  }

  // ======================== Sort Dialog Builder ========================
  @Builder
  sortDialogBuilder() {
    SongSortDialogComponent({
      songLazySort: this.vm.songLazySort,
      customizable: true,
      displaySongCoverInList: this.vm.displaySongCoverInList,
      displaySongFileNameInList: this.vm.displaySongFileNameInList,
      displayAddToPlayNextInList: this.vm.displayAddToPlayNextInList,
      onSortClick: (sort: number) => {
        this.vm.changeSongSort(sort)
        this.vm.showSortDialog = false
      },
      onDisplaySettingChange: (key: string, value: boolean) => {
        this.vm.changeDisplaySetting(key, value)
      }
    })
  }

  // ======================== Album List Settings Dialog Builder ========================
  @Builder
  albumListSettingsDialogBuilder() {
    AlbumListSettingsDialogComponent({
      viewModel: this.vm.albumListSettingsVM,
      onSortTypeChange: (sortType: number) => {
        console.info(`Album sort type changed to: ${sortType}`)
        this.vm.sortAndGroupAlbums()
        SettingsStore.getInstance().save('albumSortType', sortType)
      },
      onMinColumnsChange: (columns: number) => {
        console.info(`Album minimum columns changed to: ${columns}`)
        this.albumMinColumns = columns
        SettingsStore.getInstance().save('albumMinColumns', columns)
      }
    })
  }

  // ======================== Song Menu Dialog Builder ========================
  @Builder
  songMenuBuilder() {
    SongMenuDialogComponent({
      songInfo: this.vm.songMenuTarget as SongInfo,
      onDismiss: () => {
        this.vm.showSongSheet = false
      },
      onAddToPlaylist: () => {
        const targetSong = this.vm.songMenuTarget
        if (!targetSong) {
          return
        }
        setTimeout(() => {
          this.addToPlaylistDialogController = new CustomDialogController({
            builder: AddToPlaylistDialogComponent({
              songId: targetSong.id,
              onPlaylistSelected: (playlistId: string, playlistName: string) => {
                promptAction.showToast({ message: `添加到${playlistName}` })
              },
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
        this.vm.addToPlayNext(this.vm.songMenuTarget)
      },
      onShare: () => {
        let context = getContext(this) as common.UIAbilityContext
        this.vm.shareSong(context)
      },
      onArtistClick: (artistName: string) => {
        const targetId = this.vm.songMenuTarget.id
        this.vm.closePlayer()
        const artist = this.vm.artistList.find(a => a.name === artistName)
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
        const targetAlbum = this.vm.songMenuTarget.album
        this.vm.closePlayer()
        const album = this.vm.albumList.find(a => a.title === targetAlbum)
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
        this.vm.openSongInfo()
      },
      onRemoveFromLibrary: () => {
        const targetSong = this.vm.songMenuTarget
        if (!targetSong) {
          return
        }
        setTimeout(() => {
          this.deleteSongDialogController = new CustomDialogController({
            builder: DeleteSongDialog({
              songTitle: targetSong.title,
              onConfirm: async () => {
                if (targetSong.path && targetSong.path.length > 0) {
                  const ok = await MusicDatabase.deleteTrackByPath(targetSong.path)
                  if (ok) {
                    this.vm.removeSongFromListById(targetSong.id)
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

  // ======================== Song Sheet Builder (unified) ========================
  @Builder
  songSheetBuilder() {
    if (this.vm.showSongInfo) {
      SongInformationComponent({ songInfo: this.vm.songMenuTarget as SongInfo })
    } else if (this.vm.showSongMenu) {
      this.songMenuBuilder()
    }
  }

  // ======================== Song Information Sheet Builder ========================
  @Builder
  songInfoSheetBuilder() {
    SongInformationComponent({ songInfo: this.vm.songMenuTarget as SongInfo })
  }

  // ======================== Playlist Popup Menu Builder ========================
  @Builder
  playlistPopupMenuBuilder() {
    Column() {
      Row() {
        Text($r('app.string.new_playlist'))
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .layoutWeight(1)

        Image($r('app.media.ic_add'))
          .width(42)
          .height(42)
          .padding(9)
          .fillColor($r('app.color.salt_color_icon_foreground'))
      }
      .width('100%')
      .height(42)
      .padding({ left: 14, right: 0 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.vm.closePlaylistPopupMenu()
        this.newPlaylistDialogController.open()
      })

      Row() {
        Text($r('app.string.import_playlist'))
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)

        Text(' (.txt)')
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)

        Blank()
          .layoutWeight(1)

        Image($r('app.media.ic_file_download'))
          .width(42)
          .height(42)
          .padding(9)
          .fillColor($r('app.color.salt_color_icon_foreground'))
      }
      .width('100%')
      .height(42)
      .padding({ left: 14, right: 0 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.vm.closePlaylistPopupMenu()
        this.vm.importPlaylistFromTxt(getContext(this))
      })
    }
    .width(166)
    .borderRadius(16)
  }
}
