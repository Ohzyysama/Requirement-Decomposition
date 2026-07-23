// PlayerPageViewModel.ets
// ViewModel layer: business logic and state management for PlayerPage (View).
// Bridges the Model layer (PlayerPageModel, PlayQueueModel) with the View layer.
// Exposes @Track-decorated state properties for fine-grained UI updates.
// View calls ViewModel methods for all user interactions; ViewModel updates Model and state.

import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import {
  CurrentSongModel,
  PlaybackProgressModel,
  AudioInfoModel,
  BottomSheetType,
  extractFileExtension
} from '../model/PlayerPageModel'
import { Guqin } from '../model/Guqin'
import { ArtistInfoData, AlbumInfoData } from '../model/MainPageModel'
import { ArtistItemViewModel } from './ArtistItemViewModel'
import PlayQueueViewModel, { QueueSongItemViewModel } from './PlayQueueViewModel'
import LyricsInterfaceViewModel from './LyricsInterfaceViewModel'
import LyricsViewModel from './LyricsViewModel'
import AudioInfoDialogViewModel from './AudioInfoDialogViewModel'
import { LyricsLine } from '../model/LyricsModel'
import FlowingLightViewModel from './FlowingLightViewModel'
import { CurrentSongCoverController } from '../model/CurrentSongCoverController'
import { MiniLyricsController } from '../model/MiniLyricsController'

import { FlowingLightThemeResolver, FlowingLightMode } from '../model/FlowingLightModel'
import { MainPageDataSource } from '../model/MainPageModel'
import { SongInfoData } from '../model/SongItemModel'
import SettingsStore from '../model/SettingsStore'
import SystemBarModel from '../model/SystemBarModel'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeOption } from '@ohos/imageknifepro'

import { image } from '@kit.ImageKit'
import { promptAction } from '@kit.ArkUI'
import AudioPlayerService from '../model/AudioPlayerService'

export interface IrregularCoverEnvelope {
  widthPercent: string
  heightPercent: string
}

@Observed
export default class PlayerPageViewModel {
  // ==================== Song Info State ====================
  @Track public currentSongId: string = ''
  @Track public playMode: string = (AppStorage.get<string>('playMode') ?? PlayModeConstants.CIRCLE)

  // ==================== Playback Progress State ====================
  @Track public currentProgress: number = 0
  @Track public duration: number = 0
  @Track public isSeeking: boolean = false
  @Track public seekProgress: number = 0

  // ==================== Large Image Overlay State ====================
  @Track public showLargeImage: boolean = false
  @Track public largeImageScale: number = 1
  @Track public largeImageOffsetX: number = 0
  @Track public largeImageOffsetY: number = 0

  // ==================== Immersion Mode State ====================
  // Source of truth: AppStorage key 'immersionMode' (PersistentStorage-backed in EntryAbility).
  // Hydrated on VM construction; subsequent changes flow in via
  // PlayerPage.@StorageProp('immersionMode') + @Watch -> syncImmersionFromStorage.
  @Track public immersionMode: boolean = (AppStorage.get<boolean>('immersionMode') ?? false)

  // ==================== Song Switch Animation State ====================
  @Track public playerTopAnimRight: boolean = true
  @Track public songInfoTranslateX: number = 0
  @Track public songInfoOpacity: number = 1

  // ==================== Button Press State ====================
  @Track public prevBtnOpacity: number = 1
  @Track public playBtnOpacity: number = 1
  @Track public nextBtnOpacity: number = 1

  // ==================== Theme State ====================
  @Track public isLightMode: boolean = true
  // Reactive foreground color — updated directly when flowing light colors change.
  // Using a @Track property instead of a method ensures ArkUI re-renders immediately.
  @Track public themeForeground: string = '#ff050f19'
  // Color filter matrix for tinting SVG icons — derived from themeForeground.
  // Uses colorFilter instead of fillColor because fillColor is unreliable for SVGs
  // with complex path attributes (stroke, fill-rule, multi-path).
  @Track public themeIconColorFilter: number[] = FlowingLightThemeResolver.buildIconColorFilter('#ff050f19')

  // ==================== Flowing Light State ====================
  @Track public flowingLightVM: FlowingLightViewModel = new FlowingLightViewModel()
  @Track public coverPixelMap: image.PixelMap | undefined = undefined
  @Track public flowingLightActive: boolean = false

  // ==================== Irregular Cover Layout State ====================
  // Drives whether the rectangular (non-circle) cover branch on PlayerPage
  // preserves the original aspect ratio or renders as a centre-cropped square.
  // Hydrated from AppStorage on VM construction; subsequent external writes
  // flow in via PlayerPage.@StorageProp('irregularCoverAllowed') +
  // setIrregularCoverAllowed().
  @Track public irregularCoverAllowed: boolean = (AppStorage.get<boolean>('irregularCoverAllowed') ?? true)
  // Intrinsic bitmap dimensions of the current cover. Captured in
  // onControllerCoverChanged() via image.PixelMap.getImageInfo() so the
  // envelope helper can derive width/height percentages without the View
  // doing any math.
  @Track public coverIntrinsicWidth: number = 0
  @Track public coverIntrinsicHeight: number = 0

  // ==================== Vertical Pager State ====================
  @Track public scrollOffset: number = 0
  @Track public currentPage: number = 0
  @Track public dismissOffset: number = 0

  /**
   * Update currentPage and sync to AppStorage so MainPage.onBackPress() can read it.
   * Mirrors Android's queuePagerState.currentPage used by BackHandler in MainActivity.
   */
  setCurrentPage(page: number): void {
    this.currentPage = page
    AppStorage.setOrCreate('playerCurrentPage', page)
  }

  // ==================== Horizontal Swiper State ====================
  // Restore from AppStorage so the cover/lyrics page survives PlayerPage destruction.
  @Track public hSwiperIndex: number = (AppStorage.get<number>('playerHSwiperIndex') ?? 1)

  // ==================== Pager Drag State ====================
  @Track public isPagerDragging: boolean = false

  // ==================== Queue State ====================
  @Track public normalQueueSongs: QueueSongModel[] = []
  @Track public randomQueueSongs: QueueSongModel[] = []
  @Track public queueIndex: string = '1 / 1'

  // ==================== Bottom Sheet State ====================
  @Track public showBottomSheet: boolean = false
  @Track public bottomSheetType: string = BottomSheetType.NONE

  // ==================== PlayQueue ViewModel ====================
  @Track public playQueueViewModel: PlayQueueViewModel = new PlayQueueViewModel()

  // ==================== LyricsInterface ViewModel ====================
  @Track public lyricsInterfaceViewModel: LyricsInterfaceViewModel = LyricsInterfaceViewModel.getInstance()

  // ==================== AudioInfoDialog ViewModel (spec14) ====================
  // Owns all display strings for the 音频信息 bottom sheet; updated every
  // time the sheet is opened via openBottomSheet(AUDIO_OUTPUT_INFO).
  @Track public audioInfoDialogVM: AudioInfoDialogViewModel = new AudioInfoDialogViewModel()

  // ==================== Lyrics ViewModel ====================
  @Track public lyricsViewModel: LyricsViewModel = new LyricsViewModel()
  // Callback for View to scroll lyrics after initial load completes
  public onLyricsInitialScrollNeeded?: () => void

  // ==================== Reactive Display Properties ====================
  // Using @Track properties instead of methods ensures ArkUI re-renders when data changes
  @Track public miniLyricsLines: string[] = []
  @Track public audioInfoSummary: string = ''
  @Track public lyricsLines: LyricsLine[] = []
  @Track public lyricsIsScrollable: boolean = false
  @Track public lyricsSourceText: string = ''
  @Track public lyricsSourceTag: string = 'NOT FOUND'
  @Track public currentLyricsLineIndex: number = -1
  @Track public lyricsVersionTag: number = 0
  // Reactive mirrors of LyricsViewModel/document state needed by LyricsLineComponent's
  // karaoke render branch. Refreshed on every advanceProgress tick (200ms) so the
  // per-cell highlight and uniform sweep update during playback.
  @Track public lyricsHasAnyKaraoke: boolean = false
  @Track public lyricsHasTranslation: boolean = false
  @Track public lyricsCurrentTimeMs: number = 0

  // Flag: when true, the next onSongChanged callback skips the full array
  // rebuild and only syncs metadata.  Set after an in-place splice removal so
  // the subsequent playByIdInQueue → onSongChanged doesn't undo the splice.
  private queueArraySynced: boolean = false

  // Lyric line-click seek settling window. After the user taps a lyric line
  // we call AudioPlayerService.seek asynchronously; until the player lands at
  // the new position the advanceProgress tick can still observe the *old*
  // playback time and yank the highlighted line + progress slider back to the
  // pre-seek state, causing a visible flicker between the tapped line and the
  // one before it. While Date.now() < this epoch, advanceProgress skips the
  // currentTime read entirely. LyricsViewModel's currentTimeMs / currentLineIndex
  // remain at the values set by seekToLine, so the UI stays on the tapped line
  // through the seek transient.
  private lyricLineSeekIgnoreUntilEpoch: number = 0
  private static readonly LYRIC_LINE_SEEK_WINDOW_MS: number = 700

  // ==================== Model Layer ====================
  @Track private audioInfoModel: AudioInfoModel = new AudioInfoModel()

  // ==================== Internal Touch Tracking ====================
  @Track public screenHeight: number = 0
  // Spec15: full viewport width, captured alongside screenHeight in
  // PlayerPage.onAreaChange. Drives the horizontal translation distance of
  // the bottom-control cluster when 隐藏歌词界面控制面板 is on.
  @Track public screenWidth: number = 0
  @Track public isQueueListAtTop: boolean = true
  @Track public isTouchInQueueList: boolean = false
  @Track public isLyricsAtTop: boolean = true
  @Track public isLyricsAtBottom: boolean = false
  @Track public touchStartX: number = 0
  @Track public touchStartY: number = 0
  @Track public isDragging: boolean = false
  @Track public isDirectionLocked: boolean = false
  @Track public isHorizontalSwiping: boolean = false
  @Track public offsetAtDragStart: number = 0
  public lastTouchY: number = 0
  public lastTouchTime: number = 0
  public touchVelocity: number = 0
  @Track public initialShowQueue: boolean = false

  // ==================== Current Song Album/Artist Info ====================
  @Track public currentSongAlbum: string = ''
  @Track public currentSongAlbumArtist: string = ''
  @Track public currentSongArtist: string = ''
  @Track public currentSongCoverUri: string = ''
  @Track public currentSongFilePath: string = ''
  @Track public currentSongCodec: string = ''
  // Spec9: music info panel reactive bindings.
  @Track public currentSongFormatDisplay: string = ''
  @Track public currentSongAudioDetails: string = ''
  // spec14: ReplayGain display text (e.g. "RG -3.5 dB"), empty if not applicable
  @Track public currentReplayGainText: string = ''
  @Track public currentSongAlbumCoverUri: string = ''
  @Track public currentSongAlbumCoverOption: ImageKnifeOption = PlayerPageViewModel.defaultCoverOption()
  @Track public currentSongArtistCoverUri: string = ''
  @Track public currentSongArtistCoverOption: ImageKnifeOption = PlayerPageViewModel.defaultCoverOption()
  @Track public currentSongArtistCount: number = 0
  // Spec9: primary artist name for the "participating artist" card. Derived
  // from Guqin.getArtists(song.artist)[0] so the displayed name stays
  // consistent with the aggregated cover and track count (which look up by
  // primary artist only). For a song with artist "A/B" the card shows "A".
  @Track public currentSongPrimaryArtist: string = ''
  @Track public participatingArtists: ArtistItemViewModel[] = []

  // ==================== Callbacks ====================
  @Track public onCloseAction: () => void = () => {}
  @Track public onShowSongMenuAction: () => void = () => {}
  @Track public onNavigateToAlbumAction: (albumTitle: string) => void = () => {}
  @Track public onNavigateToArtistAction: (artistName: string) => void = () => {}
  @Track public onNavigateToFxActivityAction: () => void = () => {}

  // ==================== Initialization ====================

  initialize(): void {
    // Initialize model data
    const service = AudioPlayerService.getInstance()

    // Spec17: when the translation toggle flips, rebuild the cover-page
    // mini-lyrics so the interleaving (or its absence) takes effect even
    // when the user is currently on the cover page (no advanceProgress tick
    // is required for the change to become visible).
    this.lyricsViewModel.addTranslationChangedListener((_open: boolean): void => {
      this.refreshMiniLyrics()
    })

    // Subscribe to the central cover controller — receives PixelMap updates
    // for the current playing song. Mirrors Android's collectAsState() pattern
    // where PlayerScreen, MiniPlayer and FlowingLight all share the same
    // MusicController.coverBitmap StateFlow.
    CurrentSongCoverController.getInstance().addListener(
      (songId: string, pm: image.PixelMap | undefined): void => {
        this.onControllerCoverChanged(songId, pm)
      })
    // Bridge the flowing light VM to the same controller.
    this.flowingLightVM.subscribeToController()

    // Read flowing light mode and system color mode to determine effective theme
    this.applyFlowingLightSettings()

    // Wire up flowing light color extraction callback
    this.flowingLightVM.onColorsExtracted = () => {
      this.updateThemeForeground()
      this.syncFlowingLightToQueue()
    }

    // Restore current song id from AppStorage
    const persistedSongId = AppStorage.get('currentSongId') as string
    if (persistedSongId && persistedSongId.length > 0) {
      this.currentSongId = persistedSongId
    }

    // Restore progress and duration from service (may have persisted values)
    const restoredProgress = service.getCurrentTimeMs()
    const restoredDuration = service.getDurationMs()
    if (restoredDuration > 0) {
      this.currentProgress = restoredProgress
      this.duration = restoredDuration
    }

    // Load both queues from the service (service is the single source of truth)
    // No local reshuffling — the service maintains both queues persistently.
    this.normalQueueSongs = service.getNormalQueue()
    this.randomQueueSongs = service.getRandomQueue()

    // Sync playMode to service (does NOT reshuffle if mode is already set)
    service.setPlayMode(this.playMode)

    this.updateQueueIndex()

    // Register onSongChanged callback from AudioPlayerService
    service.onSongChanged = (song: QueueSongModel): void => {
      console.info('PlayerPageVM.onSongChanged callback: songId=' + song.id + ' title=' + song.title)
      this.currentSongId = song.id
      this.currentSongAlbum = song.album ?? ''
      this.currentSongArtist = song.artist ?? ''
      this.currentSongCoverUri = song.coverUri ?? ''
      this.currentSongAlbumCoverUri = song.coverUri ?? ''
      this.updateCurrentSongAlbumArtist(song.id)
      this.loadInfoPageCovers(song.id, song.album ?? '', song.artist ?? '')
      // Reload both queues from the service — the random queue may have been
      // reshuffled when skipNext() reached the end in random mode.
      this.normalQueueSongs = service.getNormalQueue()
      this.randomQueueSongs = service.getRandomQueue()
      this.updateQueueIndex()
      if (this.queueArraySynced) {
        // Array was already updated in-place (e.g. splice removal) — skip full rebuild
        this.queueArraySynced = false
        this.syncPlayQueueViewModelMetadata()
      } else {
        this.syncPlayQueueViewModel()
      }
      // Load lyrics for the new song
      // Immediately clear old lyrics from UI, then refresh again when new lyrics are loaded
      this.lyricsViewModel.loadLyrics(song.fileUri, song.id).then(() => {
        this.refreshLyricsLines()
        this.refreshMiniLyrics()
      })
      this.refreshLyricsLines()
      // Update audio info from song data
      this.updateAudioInfo(song.id)
      // Directly update cover art and flowing light — don't rely on
      // AppStorage → @StorageLink → @Watch chain which may not fire reliably
      this.updateCoverArt(song.id, song.coverUri)
    }

    // Register onQueueInserted callback — when a song is added via "play next",
    // reload both queues from service (service manages both queues atomically)
    // and update PlayQueueComponent display in-place.
    service.onQueueInserted = (song: QueueSongModel, _insertIndex: number): void => {
      // Reload both queues from the service (single source of truth)
      this.normalQueueSongs = service.getNormalQueue()
      this.randomQueueSongs = service.getRandomQueue()

      // Update PlayQueueComponent display in-place: remove duplicate, insert after current song
      this.playQueueViewModel.songs.removeById(song.id)
      const currentDisplayIdx = this.playQueueViewModel.songs.indexOfId(this.currentSongId)
      const item = new QueueSongItemViewModel()
      item.updateFromModel(song)
      this.playQueueViewModel.songs.insertAt(currentDisplayIdx >= 0 ? currentDisplayIdx + 1 : 0, item)

      this.updateQueueIndex()
      this.playQueueViewModel.queueIndex = this.queueIndex
    }

    // Load lyrics and audio info for initial song if available
    const initialFileUri = service.getCurrentFileUri()
    if (initialFileUri.length > 0 && this.currentSongId.length > 0) {
      this.lyricsViewModel.loadLyrics(initialFileUri, this.currentSongId).then(() => {
        // Immediately sync to current playback position so lyrics
        // jump to the correct line instead of starting from the top
        this.lyricsViewModel.updateProgress(service.getCurrentTimeMs())
        this.refreshLyricsLines()
        this.refreshMiniLyrics()
        // Notify View to scroll to the current line immediately
        if (this.onLyricsInitialScrollNeeded) {
          this.onLyricsInitialScrollNeeded()
        }
      })
      this.updateAudioInfo(this.currentSongId)
      this.updateCurrentSongAlbumArtist(this.currentSongId)
      const initSongs = MainPageDataSource.loadDefaultSongs()
      const initSong: SongInfoData | undefined = initSongs.find((s: SongInfoData) => s.id === this.currentSongId)
      if (initSong) {
        this.currentSongAlbum = initSong.album ?? ''
        this.currentSongArtist = initSong.artist ?? ''
        this.currentSongCoverUri = initSong.coverUri ?? ''
        this.currentSongAlbumCoverUri = initSong.coverUri ?? ''
        this.loadInfoPageCovers(initSong.id, initSong.album ?? '', initSong.artist ?? '')
      }
    }

    // Initialize PlayQueueViewModel with callbacks
    this.syncPlayQueueViewModel()
    this.playQueueViewModel.onSongClickAction = (songId: string) => {
      // Navigate to the song by ID — preserves both queues and their order
      service.playByIdInQueue(songId)
    }
    this.playQueueViewModel.onRemoveSongAction = (songId: string) => {
      this.removeSongFromQueue(songId)
    }
    this.playQueueViewModel.onClearQueueAction = () => {
      this.clearQueue()
    }
    this.playQueueViewModel.onPlayModeClickAction = () => {
      this.cyclePlayMode()
    }
    this.playQueueViewModel.onDismissAction = () => {
      // Will be handled by view via callback
    }
    this.playQueueViewModel.onListAtTopAction = (atTop: boolean) => {
      this.isQueueListAtTop = atTop
    }
    this.playQueueViewModel.onListTouchAction = (inList: boolean) => {
      this.isTouchInQueueList = inList
    }
  }

  // ==================== Theme Computed Properties ====================

  // Foreground color for player UI text/icons.
  // Mirrors Salt Player Android's reDrawFlowingLightView mode logic:
  //   Mode 0 (follow UI) + dark system → WHITE (playerThemeDefault.playerActivityMainColor)
  //   Mode 0 (follow UI) + light system → magicColor (accent from cover)
  //   Mode 1 (light flowing) → magicColor (accent from cover)
  //   Mode 2 (dark flowing) → WHITE
  //
  // In our code, isLightMode is already resolved by applyFlowingLightSettings() to
  // represent whether the effective flowing light mode is light. So accent color is
  // applied only when isLightMode == true (the "magicColor" path).
  getThemeForeground(): string {
    if (this.flowingLightActive
        && this.isLightMode
        && this.flowingLightVM.colorExtracted
        && this.flowingLightVM.accentColor.length > 0) {
      return this.flowingLightVM.accentColor
    }
    return this.isLightMode ? '#ff050f19' : '#ffffffff'
  }

  getThemeBackground(): string {
    return this.isLightMode ? '#ffffffff' : '#ff000000'
  }

  // Progress slider track color — theme foreground mixed with low alpha (~15%).
  // Replaces the 'ff' alpha prefix in themeForeground (#ffRRGGBB) with '26'.
  getTrackBarColor(): string {
    const fg = this.themeForeground
    if (fg.length === 9 && fg.charAt(0) === '#') {
      return '#26' + fg.substring(3)
    }
    return fg
  }

  // Update the reactive themeForeground property.
  // Must be called whenever flowingLightActive, colorExtracted, or foregroundColor changes.
  updateThemeForeground(): void {
    this.themeForeground = this.getThemeForeground()
    this.themeIconColorFilter = FlowingLightThemeResolver.buildIconColorFilter(this.themeForeground)
  }

  // Read the persisted flowing light mode and system color mode, then apply the
  // correct overlay colors and theme foreground so the player UI matches the
  // effective light/dark flowing light setting on startup.
  applyFlowingLightSettings(): void {
    // Read flowing light mode from AppStorage (0=followUI, 1=light, 2=dark)
    const flowingLightMode: number =
      (AppStorage.get('flowingLightMode') as number) ?? FlowingLightMode.FOLLOW_UI

    // Read system dark mode flag set by EntryAbility.onConfigurationUpdate
    // (uses ConfigurationConstant.ColorMode which has unambiguous DARK=0, LIGHT=1 values)
    const isSystemDark: boolean = (AppStorage.get('isSystemDark') as boolean) ?? false

    // Resolve whether the effective flowing light should be light
    const isLightFlowing: boolean = FlowingLightThemeResolver.resolve(flowingLightMode, isSystemDark)

    // Apply overlay colors to the flowing light layer
    this.flowingLightVM.applyFlowingLightMode(isLightFlowing)

    // Update the player page theme mode so text/icon colors adapt
    this.isLightMode = isLightFlowing

    // Refresh the foreground color and icon color filter to match the new theme
    this.updateThemeForeground()
  }

  // ==================== Time Formatting ====================

  formatTime(ms: number): string {
    const totalSeconds = Math.floor(ms / 1000)
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    const minStr = minutes < 10 ? '0' + minutes.toString() : minutes.toString()
    const secStr = seconds < 10 ? '0' + seconds.toString() : seconds.toString()
    return minStr + ':' + secStr
  }

  // ==================== Play Mode ====================

  getPlayModeIcon(): Resource {
    switch (this.playMode) {
      case PlayModeConstants.CIRCLE:
        return $r('app.media.ic_player_circle')
      case PlayModeConstants.REPEAT_ONE:
        return $r('app.media.ic_player_repeat_one')
      case PlayModeConstants.RANDOM:
      default:
        return $r('app.media.ic_player_random')
    }
  }

  getPlayModeDescription(): string {
    switch (this.playMode) {
      case PlayModeConstants.CIRCLE:
        return '列表循环播放模式'
      case PlayModeConstants.REPEAT_ONE:
        return '单曲循环播放模式'
      case PlayModeConstants.RANDOM:
      default:
        return '随机播放模式'
    }
  }

  cyclePlayMode(): void {
    switch (this.playMode) {
      case PlayModeConstants.CIRCLE:
        this.playMode = PlayModeConstants.REPEAT_ONE
        break
      case PlayModeConstants.REPEAT_ONE:
        this.playMode = PlayModeConstants.RANDOM
        break
      case PlayModeConstants.RANDOM:
      default:
        this.playMode = PlayModeConstants.CIRCLE
        break
    }
    // Service handles reshuffling when switching to RANDOM
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(this.playMode)
    // Reload random queue from service (may have been reshuffled)
    this.randomQueueSongs = service.getRandomQueue()
    this.updateQueueIndex()
    this.syncPlayQueueViewModel()
    SettingsStore.getInstance().save('playMode', this.playMode)
    console.info('Play mode changed to: ' + this.playMode)
  }

  // ==================== Queue Management ====================

  private updateQueueIndex(): void {
    const displayQueue = this.playMode === PlayModeConstants.RANDOM
      ? this.randomQueueSongs : this.normalQueueSongs
    if (displayQueue.length === 0) {
      this.queueIndex = '0 / 0'
      return
    }
    const currentIndex = displayQueue.findIndex((song: QueueSongModel) => song.id === this.currentSongId)
    const displayIndex = currentIndex >= 0 ? currentIndex + 1 : 1
    this.queueIndex = displayIndex + ' / ' + displayQueue.length
  }

  removeSongFromQueue(songId: string): void {
    const isCurrentSong = (songId === this.currentSongId)
    const service = AudioPlayerService.getInstance()

    // Remove from both internal queues (service manages indices)
    service.removeSongFromInternalQueue(songId)

    // Reload both queues from service
    this.normalQueueSongs = service.getNormalQueue()
    this.randomQueueSongs = service.getRandomQueue()

    const displayQueue = this.playMode === PlayModeConstants.RANDOM
      ? this.randomQueueSongs : this.normalQueueSongs

    if (displayQueue.length === 0) {
      // Queue is now empty — stop playback, reset to default state
      this.currentSongId = ''
      this.queueIndex = '0 / 0'
      // Deactivate AVSession first so the system live activity disappears
      // before avPlayer.reset() changes the player state (prevents brief flash).
      service.deactivateSession()
      service.stop()
      this.currentProgress = 0
      this.duration = 0
      // Reset lyrics so the player page shows default state instead of stale lyrics
      this.lyricsViewModel.loadLyrics('', '')
      this.miniLyricsLines = []
      this.lyricsLines = []
      this.lyricsIsScrollable = false
      this.lyricsSourceText = ''
      this.lyricsSourceTag = 'NOT FOUND'
      this.currentLyricsLineIndex = -1
      this.lyricsHasAnyKaraoke = false
      this.lyricsHasTranslation = false
      this.flowingLightActive = false
      this.flowingLightVM.updateCover('', '')
      // Rotation lifecycle is managed exclusively by FlowingLightComponent
      // via isPlaying + transitionProgress; do not call stopRotation() here.
      this.updateThemeForeground()
      this.syncFlowingLightToQueue()
      this.syncPlayQueueViewModel()
      return
    }

    // Update queue UI first (before playByIdInQueue which synchronously
    // triggers onSongChanged) so the list removal is already visible.
    this.updateQueueIndex()
    this.playQueueViewModel.removeSong(songId)
    this.syncPlayQueueViewModelMetadata()

    if (isCurrentSong) {
      // Service already adjusted indices — play the song at the new current position
      const nextIndex = service.getCurrentIndex()
      const nextSong = displayQueue[nextIndex >= 0 ? nextIndex : 0]

      // Clear the removed song's cover art / flowing light state
      this.coverPixelMap = undefined
      this.flowingLightActive = false
      this.flowingLightVM.updateCover('', '')
      this.updateThemeForeground()
      this.syncFlowingLightToQueue()

      // Prevent the synchronous onSongChanged callback from doing a full
      // array rebuild — the VM array is already correct after removeSong().
      this.queueArraySynced = true

      // Play the next song using playByIdInQueue to preserve queue order
      if (nextSong) {
        service.playByIdInQueue(nextSong.id)
      }
    }
  }

  clearQueue(): void {
    this.normalQueueSongs = []
    this.randomQueueSongs = []
    this.currentSongId = ''
    this.queueIndex = '0 / 0'
    const service = AudioPlayerService.getInstance()
    // Deactivate AVSession first so the system live activity disappears
    // before avPlayer.reset() changes the player state (prevents brief flash).
    service.deactivateSession()
    // Stop AudioPlayerService playback and clear its internal queue
    service.clearQueue()
    // Reset progress display
    this.currentProgress = 0
    this.duration = 0
    // Reset lyrics state so player page shows default (no lyrics) instead of stale lyrics
    this.lyricsViewModel.loadLyrics('', '')
    this.miniLyricsLines = []
    this.lyricsLines = []
    this.lyricsIsScrollable = false
    this.lyricsSourceText = ''
    this.lyricsSourceTag = 'NOT FOUND'
    this.currentLyricsLineIndex = -1
    this.lyricsHasAnyKaraoke = false
    this.lyricsHasTranslation = false
    this.lyricsCurrentTimeMs = 0
    this.lyricsVersionTag++
    // Reset cover art / flowing light render background
    this.coverPixelMap = undefined
    this.flowingLightActive = false
    this.flowingLightVM.updateCover('', '')
    // Rotation lifecycle is managed exclusively by FlowingLightComponent
    // via isPlaying + transitionProgress; do not call stopRotation() here.
    this.updateThemeForeground()
    this.syncFlowingLightToQueue()
    // service.clearQueue() does not fire a song-changed event, so the lyric
    // controller would keep publishing the previous song's line as the
    // miniplayer subtitle. Drop its state so the subtitle returns to default.
    MiniLyricsController.getInstance().clear()
    this.syncPlayQueueViewModel()
    // After clearing, the queue list is empty and therefore at the top by
    // definition. The List's onReachStart does not reliably fire when its data
    // is replaced with an empty array, so without this reset the swipe-down
    // dismiss gate (PlayerPage handlePagerDrag, page-1 branch) stays closed
    // whenever the user had scrolled the list before clearing — making it
    // impossible to swipe back to the player after clearing a long queue.
    this.isQueueListAtTop = true
  }

  // ==================== PlayQueue ViewModel Sync ====================

  syncPlayQueueViewModel(): void {
    const displayQueue = this.playMode === PlayModeConstants.RANDOM
      ? this.randomQueueSongs : this.normalQueueSongs
    this.playQueueViewModel.loadSongs(displayQueue)
    this.syncPlayQueueViewModelMetadata()
  }

  // Sync only metadata fields (not the songs array) to PlayQueueViewModel.
  // Use this after in-place array mutations (e.g. removeSong) to avoid
  // recreating the entire array and causing list flicker.
  private syncPlayQueueViewModelMetadata(): void {
    this.playQueueViewModel.currentSongId = this.currentSongId
    this.playQueueViewModel.currentSongTitle = AppStorage.get('currentSongTitle') as string || ''
    this.playQueueViewModel.currentSongArtist = AppStorage.get('currentSongArtist') as string || ''
    this.playQueueViewModel.coverPixelMap = this.coverPixelMap
    this.playQueueViewModel.queueIndex = this.queueIndex
    this.playQueueViewModel.playMode = this.playMode
    this.playQueueViewModel.pagerDragging = this.isPagerDragging
    this.playQueueViewModel.flowingLightActive = this.flowingLightActive
    this.playQueueViewModel.foregroundColor = this.themeForeground
    this.playQueueViewModel.isLightMode = this.isLightMode
    this.playQueueViewModel.iconColorFilter = this.themeIconColorFilter
  }

  // ==================== Playback Progress ====================

  advanceProgress(): void {
    const service = AudioPlayerService.getInstance()
    const realDuration = service.getDurationMs()
    if (realDuration > 0) {
      this.duration = realDuration
    }
    // Skip the live position read while a lyric-line seek is still settling
    // (see lyricLineSeekIgnoreUntilEpoch). Without this guard, the player's
    // stale pre-seek time leaks in here and yanks the highlight back to the
    // line that was current before the tap — visible as a flicker.
    const inLyricLineSeekWindow = Date.now() < this.lyricLineSeekIgnoreUntilEpoch
    if (!this.isSeeking && service.isPlaybackIntentActive() && !inLyricLineSeekWindow) {
      this.currentProgress = service.getCurrentTimeMs()
      // Update lyrics only during normal playback — during seek,
      // handleSeekMoving updates lyrics with the seek position directly
      this.lyricsViewModel.updateProgress(service.getCurrentTimeMs())
    }
    this.refreshMiniLyrics()
    this.refreshLyricsLines()
    this.refreshAudioInfoSummary()
  }

  // Centralized entry point for "user tapped a lyric line to seek". Mirrors
  // the body of PlayerPage.LyricsArea's onLineClick, plus opens the
  // post-seek-settling window so advanceProgress can't yank the UI back to
  // the previous line while the player is still landing at the seek target.
  handleLyricLineClick(timeMs: number, lineIndex: number): void {
    this.currentProgress = timeMs
    this.currentLyricsLineIndex = lineIndex
    this.lyricsViewModel.seekToLine(lineIndex)
    this.lyricLineSeekIgnoreUntilEpoch =
      Date.now() + PlayerPageViewModel.LYRIC_LINE_SEEK_WINDOW_MS
    AudioPlayerService.getInstance().seek(timeMs)
  }

  handleSeekBegin(value: number): void {
    if (this.duration <= 0) return
    this.isSeeking = true
    this.seekProgress = value
  }

  handleSeekMoving(value: number): void {
    if (this.duration <= 0) return
    this.seekProgress = value
    // Update lyrics to follow the seek position immediately
    this.lyricsViewModel.updateProgress(value)
    this.refreshLyricsLines()
  }

  handleSeekEnd(): void {
    if (!this.isSeeking) return
    this.currentProgress = this.seekProgress
    this.isSeeking = false
    // Update lyrics to the final seek position immediately
    this.lyricsViewModel.updateProgress(this.seekProgress)
    this.refreshLyricsLines()
    this.refreshMiniLyrics()
    AudioPlayerService.getInstance().seek(this.seekProgress)
  }

  getDisplayProgress(): number {
    return this.isSeeking ? this.seekProgress : this.currentProgress
  }

  // ==================== Playback Controls ====================

  togglePlayPause(): void {
    AudioPlayerService.getInstance().togglePlayPause()
    // Reset press opacity immediately to prevent stuck state when Image source changes
    this.playBtnOpacity = 1
  }

  skipNext(): void {
    AudioPlayerService.getInstance().skipNext()
  }

  skipPrevious(): void {
    AudioPlayerService.getInstance().skipPrevious()
  }

  toggleImmersionMode(): void {
    const next: boolean = !this.immersionMode
    this.immersionMode = next
    AppStorage.setOrCreate('immersionMode', next)
    SettingsStore.getInstance().save('immersionMode', next)
    SystemBarModel.getInstance().reconcileStatusBarVisibility()
    console.info('Immersion mode: ' + next)
  }

  // Same as toggleImmersionMode(), plus a toast announcing the new state.
  // Used by PlayerPage's long-press-on-play/pause entry point (scene 1.2 / 4).
  toggleImmersionModeWithToast(): void {
    this.toggleImmersionMode()
    const msg: Resource = this.immersionMode
      ? $r('app.string.immersion_mode_on')
      : $r('app.string.immersion_mode_off')
    promptAction.showToast({ message: msg })
  }

  // Reconcile local VM flag with an external change to AppStorage 'immersionMode'
  // (e.g. user flipped the setting from the User Interface settings page).
  // Invoked from PlayerPage's @StorageProp('immersionMode') @Watch handler.
  syncImmersionFromStorage(value: boolean): void {
    if (this.immersionMode !== value) {
      this.immersionMode = value
      SystemBarModel.getInstance().reconcileStatusBarVisibility()
    }
  }

  // ==================== Song Switch Animation ====================

  getSongSwitchSlideOut(isNext: boolean): number {
    return isNext ? -400 : 400
  }

  getSongSwitchSlideIn(isNext: boolean): number {
    return isNext ? 400 : -400
  }

  prepareSongSwitchSlideOut(isNext: boolean): void {
    this.playerTopAnimRight = isNext
    this.songInfoTranslateX = this.getSongSwitchSlideOut(isNext)
    this.songInfoOpacity = 0
  }

  prepareSongSwitchSlideIn(isNext: boolean): void {
    this.songInfoTranslateX = this.getSongSwitchSlideIn(isNext)
  }

  completeSongSwitchSlideIn(): void {
    this.songInfoTranslateX = 0
    this.songInfoOpacity = 1
  }

  // ==================== Large Image ====================

  showLargeImageOverlay(): void {
    this.largeImageScale = 1
    this.largeImageOffsetX = 0
    this.largeImageOffsetY = 0
    this.showLargeImage = true
  }

  hideLargeImageOverlay(): void {
    this.showLargeImage = false
  }

  updateLargeImageScale(scale: number): void {
    this.largeImageScale = Math.max(0.5, Math.min(scale, 5))
  }

  updateLargeImageOffset(offsetX: number, offsetY: number): void {
    this.largeImageOffsetX = offsetX
    this.largeImageOffsetY = offsetY
  }

  // ==================== Bottom Sheet ====================

  openBottomSheet(type: string): void {
    this.bottomSheetType = type
    if (type === BottomSheetType.AUDIO_OUTPUT_INFO) {
      const songs = MainPageDataSource.loadDefaultSongs()
      const currentSong: SongInfoData | undefined =
        songs.find((s: SongInfoData) => s.id === this.currentSongId)
      this.audioInfoDialogVM.updateFrom(currentSong).then(() => {
        this.showBottomSheet = true
      }).catch((e: Error) => {
        console.warn('audioInfoDialogVM.updateFrom failed: ' + e.message)
        this.showBottomSheet = true
      })
    } else {
      this.showBottomSheet = true
    }
  }

  closeBottomSheet(): void {
    this.showBottomSheet = false
    this.bottomSheetType = BottomSheetType.NONE
  }

  // ==================== Button Press Effects ====================
  // When flowing light is active, skip opacity effect to avoid
  // background bleed-through that looks like a color change.

  handlePrevBtnDown(): void {
    if (!this.flowingLightActive) {
      this.prevBtnOpacity = 0.5
    }
  }

  handlePrevBtnUp(): void {
    this.prevBtnOpacity = 1
  }

  handlePlayBtnDown(): void {
    if (!this.flowingLightActive) {
      this.playBtnOpacity = 0.5
    }
  }

  handlePlayBtnUp(): void {
    this.playBtnOpacity = 1
  }

  handleNextBtnDown(): void {
    if (!this.flowingLightActive) {
      this.nextBtnOpacity = 0.5
    }
  }

  handleNextBtnUp(): void {
    this.nextBtnOpacity = 1
  }

  // ==================== Audio Info ====================

  getAudioInfoFormat(): string {
    return this.audioInfoModel.format
  }

  getAudioInfoDetails(): string {
    return this.audioInfoModel.getDisplayText()
  }

  getAudioInfoSampleRate(): number {
    return this.audioInfoModel.sampleRate
  }

  getAudioInfoBitrate(): number {
    return this.audioInfoModel.bitrate
  }

  // ==================== Mini Lyrics (below album cover) ====================

  // Refresh lyrics lines @Track properties when lyricsVersion changes
  refreshLyricsLines(): void {
    const ver = this.lyricsViewModel.lyricsVersion
    if (ver !== this.lyricsVersionTag) {
      this.lyricsVersionTag = ver
      this.lyricsLines = this.lyricsViewModel.document.lines
      this.lyricsIsScrollable = this.lyricsViewModel.document.isScrollable
      this.lyricsSourceText = this.lyricsViewModel.document.sourceText
      this.lyricsSourceTag = this.lyricsViewModel.getSourceTag()
      this.lyricsHasAnyKaraoke = this.lyricsViewModel.document.hasAnyKaraoke
      this.lyricsHasTranslation = this.lyricsViewModel.hasTranslation
    }
    // Always sync currentLineIndex for @Prop isCurrent in LyricsLineComponent
    this.currentLyricsLineIndex = this.lyricsViewModel.currentLineIndex
    // Always sync currentTimeMs so per-cell opacity / uniform sweep advance each tick
    this.lyricsCurrentTimeMs = this.lyricsViewModel.currentTimeMs
  }

  // Refresh the @Track miniLyricsLines property so ArkUI re-renders.
  // Spec17: when the translation toggle is on AND the song has translation
  // lines, interleave each main line with its subText (translation) so the
  // cover-page mini-lyrics block mirrors the toggle state in real time. The
  // window shrinks from 3 to 2 main lines when translation is on so the
  // rendered total stays within the existing 88vp MiniLyricsArea height.
  refreshMiniLyrics(): void {
    const doc = this.lyricsViewModel.document
    if (!doc.isScrollable || doc.lines.length === 0) {
      this.miniLyricsLines = []
      return
    }
    // If before the first lyric line, show from line 0
    const idx = this.lyricsViewModel.currentLineIndex < 0 ? 0 : this.lyricsViewModel.currentLineIndex
    const showTr = this.lyricsViewModel.openTranslation && this.lyricsViewModel.hasTranslation
    const lyricLineCap = showTr ? 2 : 3
    const lines: string[] = []
    for (let i = idx; i < Math.min(idx + lyricLineCap, doc.lines.length); i++) {
      const text = doc.lines[i].mainText
      if (text.length > 0) {
        lines.push(text)
        if (showTr && doc.lines[i].subText.length > 0) {
          lines.push(doc.lines[i].subText)
        }
      }
    }
    this.miniLyricsLines = lines
  }

  // Update audioInfoModel from the song data source by song ID
  updateAudioInfo(songId: string): void {
    const songs = MainPageDataSource.loadDefaultSongs()
    const song: SongInfoData | undefined = songs.find((s: SongInfoData) => s.id === songId)
    if (song) {
      const ext: string = extractFileExtension(song.path, song.fileUri)
      this.audioInfoModel = new AudioInfoModel(
        song.format ?? '', song.channels ?? 0, song.sampleRate ?? 0, song.bitrate ?? 0, ext
      )
      this.currentSongFilePath = song.path ?? ''
      this.currentSongCodec = song.codec ?? song.format ?? ''
      // spec14: format replay gain display
      const rgDb = song.replayGainDb ?? ''
      if (rgDb.length > 0 && (AppStorage.get<boolean>('volumeBalanceEnabled') ?? true)) {
        this.currentReplayGainText = 'RG ' + rgDb
      } else {
        this.currentReplayGainText = ''
      }
    } else {
      this.audioInfoModel = new AudioInfoModel()
      this.currentSongFilePath = ''
      this.currentSongCodec = ''
      this.currentReplayGainText = ''
    }
    this.currentSongFormatDisplay = this.audioInfoModel.getDisplayFormat()
    this.currentSongAudioDetails = this.audioInfoModel.getDisplayText()
    this.refreshAudioInfoSummary()
  }

  // Refresh the @Track audioInfoSummary property so ArkUI re-renders
  refreshAudioInfoSummary(): void {
    const parts: string[] = []
    const format = this.audioInfoModel.format
    if (format.length > 0) {
      parts.push(format)
    }
    if (this.audioInfoModel.sampleRate > 0) {
      const khz = this.audioInfoModel.sampleRate / 1000
      parts.push(khz.toString() + ' kHz')
    }
    if (this.audioInfoModel.bitrate > 0) {
      parts.push(Math.round(this.audioInfoModel.bitrate / 1000).toString() + ' kbps')
    }
    // spec14: append replay gain if available
    if (this.currentReplayGainText.length > 0) {
      parts.push(this.currentReplayGainText)
    }
    this.audioInfoSummary = parts.length > 0 ? parts.join('  ') : ''
  }

  updateCurrentSongAlbumArtist(songId: string): void {
    const songs = MainPageDataSource.loadDefaultSongs()
    const song: SongInfoData | undefined = songs.find((s: SongInfoData) => s.id === songId)
    this.currentSongAlbumArtist = song?.albumArtist ?? ''
  }

  // Spec9: look up the primary artist aggregate (name + cover + track count)
  // for the participating-artist card. If the song's artist is empty or not
  // found, the fields default to '' / '' / 0 so the UI falls back to
  // "未知艺术家" and "0 首".
  updateCurrentSongArtistAggregate(song: SongInfoData | undefined): void {
    if (!song || !song.artist || song.artist.length === 0) {
      this.currentSongPrimaryArtist = ''
      this.currentSongArtistCoverUri = ''
      this.currentSongArtistCount = 0
      this.participatingArtists = []
      return
    }
    const names: string[] = Guqin.getArtists(song.artist)
    if (names.length === 0) {
      this.currentSongPrimaryArtist = ''
      this.currentSongArtistCoverUri = ''
      this.currentSongArtistCount = 0
      this.participatingArtists = []
      return
    }
    const primaryName: string = names[0]
    this.currentSongPrimaryArtist = primaryName
    const allArtists: ArtistInfoData[] = MainPageDataSource.loadDefaultArtists()
    const hit: ArtistInfoData | undefined = allArtists.find(
      (a: ArtistInfoData) => a.name === primaryName)
    this.currentSongArtistCoverUri = hit?.coverUri ?? ''
    this.currentSongArtistCount = hit?.count ?? 0

    this.participatingArtists = names.map((name: string) => {
      const artist: ArtistInfoData | undefined = allArtists.find(
        (a: ArtistInfoData) => a.name === name)
      const vm = new ArtistItemViewModel(
        artist?.id ?? '',
        name,
        artist?.count ?? 0,
        artist?.coverUri ?? '',
        '',
        artist?.coverSongId ?? ''
      )
      vm.loadCoverIfNeeded()
      return vm
    })
  }

  // Spec9: always-present "N 首" helper for the artist card track count.
  getDisplayArtistCountText(): string {
    return `${this.currentSongArtistCount} 首`
  }

  static defaultCoverOption(): ImageKnifeOption {
    const opt = new ImageKnifeOption()
    opt.placeholderSrc = $r('app.media.ic_song_cover_v5')
    opt.errorSrc = $r('app.media.ic_song_cover_v5')
    opt.objectFit = ImageFit.Cover
    return opt
  }

  private albumCoverLoadedKey: string = ''
  private artistCoverLoadedKey: string = ''

  loadAlbumCover(coverSongId: string): void {
    if (coverSongId.length === 0) {
      this.albumCoverLoadedKey = ''
      this.currentSongAlbumCoverOption = PlayerPageViewModel.defaultCoverOption()
      return
    }
    if (coverSongId === this.albumCoverLoadedKey) return
    this.albumCoverLoadedKey = coverSongId
    this.currentSongAlbumCoverOption = PlayerPageViewModel.defaultCoverOption()

    const uri = CoverCacheDb.getCoverFileUri(coverSongId)
    if (uri.length > 0) {
      const opt = PlayerPageViewModel.defaultCoverOption()
      opt.loadSrc = uri
      this.currentSongAlbumCoverOption = opt
      return
    }

    const capturedKey = coverSongId
    CoverCacheDb.ensureCoverFile(coverSongId).then((fileUri: string) => {
      if (this.albumCoverLoadedKey !== capturedKey) return
      if (fileUri.length > 0) {
        const opt = PlayerPageViewModel.defaultCoverOption()
        opt.loadSrc = fileUri
        this.currentSongAlbumCoverOption = opt
        return
      }
      return CoverArtExtractor.extractAndCache(coverSongId, coverSongId).then(() => {
        if (this.albumCoverLoadedKey !== capturedKey) return
        const extracted = CoverCacheDb.getCoverFileUri(coverSongId)
        if (extracted.length > 0) {
          const opt = PlayerPageViewModel.defaultCoverOption()
          opt.loadSrc = extracted
          this.currentSongAlbumCoverOption = opt
        } else {
          this.albumCoverLoadedKey = ''
        }
      })
    }).catch((_e: Error) => {
      this.albumCoverLoadedKey = ''
    })
  }

  loadArtistCover(coverSongId: string): void {
    if (coverSongId.length === 0) {
      this.artistCoverLoadedKey = ''
      this.currentSongArtistCoverOption = PlayerPageViewModel.defaultCoverOption()
      return
    }
    if (coverSongId === this.artistCoverLoadedKey) return
    this.artistCoverLoadedKey = coverSongId
    this.currentSongArtistCoverOption = PlayerPageViewModel.defaultCoverOption()

    const uri = CoverCacheDb.getCoverFileUri(coverSongId)
    if (uri.length > 0) {
      const opt = PlayerPageViewModel.defaultCoverOption()
      opt.loadSrc = uri
      this.currentSongArtistCoverOption = opt
      return
    }

    const capturedKey = coverSongId
    CoverCacheDb.ensureCoverFile(coverSongId).then((fileUri: string) => {
      if (this.artistCoverLoadedKey !== capturedKey) return
      if (fileUri.length > 0) {
        const opt = PlayerPageViewModel.defaultCoverOption()
        opt.loadSrc = fileUri
        this.currentSongArtistCoverOption = opt
        return
      }
      return CoverArtExtractor.extractAndCache(coverSongId, coverSongId).then(() => {
        if (this.artistCoverLoadedKey !== capturedKey) return
        const extracted = CoverCacheDb.getCoverFileUri(coverSongId)
        if (extracted.length > 0) {
          const opt = PlayerPageViewModel.defaultCoverOption()
          opt.loadSrc = extracted
          this.currentSongArtistCoverOption = opt
        } else {
          this.artistCoverLoadedKey = ''
        }
      })
    }).catch((_e: Error) => {
      this.artistCoverLoadedKey = ''
    })
  }

  loadInfoPageCovers(songId: string, album: string, artist: string): void {
    const songs = MainPageDataSource.loadDefaultSongs()
    const currentSongInfo: SongInfoData | undefined =
      songs.find((s: SongInfoData) => s.id === songId)
    this.updateCurrentSongArtistAggregate(currentSongInfo ?? {
      id: songId, title: '', artist: artist, album: album,
      subTitle: '', coverUri: '', valid: true, quality: 0
    })

    const albums = MainPageDataSource.loadDefaultAlbums()
    const albumHit: AlbumInfoData | undefined =
      albums.find((a: AlbumInfoData) => a.title === album)
    this.loadAlbumCover(albumHit?.coverSongId ?? songId)

    const artists = MainPageDataSource.loadDefaultArtists()
    const primaryName = Guqin.getArtists(artist)[0] ?? ''
    const artistHit: ArtistInfoData | undefined =
      artists.find((a: ArtistInfoData) => a.name === primaryName)
    this.loadArtistCover(artistHit?.coverSongId ?? songId)
  }

  // ==================== Pager Background Color ====================

  getPagerBackgroundColor(): string {
    if (this.flowingLightActive && this.flowingLightVM.coverPixelMap) {
      // Use themed solid background behind the 65%-opacity flowing light layer
      // so the correct base color shows through (white for light, black for dark)
      return this.isLightMode ? '#ffffffff' : '#ff1a1a1a'
    }
    // When no cover art, use background color matching the flowing light mode
    if (this.isLightMode) {
      return this.scrollOffset < -this.screenHeight * 0.1 ? '#fff7f9fa' : '#ffffffff'
    } else {
      return this.scrollOffset < -this.screenHeight * 0.1 ? '#ff1a1a1a' : '#ff000000'
    }
  }

  // ==================== Cover Art Loading ====================

  // Handler for controller cover change events.
  private onControllerCoverChanged(_songId: string, pm: image.PixelMap | undefined): void {
    if (pm) {
      this.coverPixelMap = pm
      this.flowingLightActive = true
    } else {
      this.coverPixelMap = undefined
      this.flowingLightActive = false
    }
    // Capture intrinsic dimensions asynchronously so the irregular-cover
    // envelope can use the bitmap's real aspect ratio. On failure or no
    // cover, fall back to 0 which forces the square branch.
    this.captureCoverIntrinsicSize(pm)
    this.updateThemeForeground()
    this.syncFlowingLightToQueue()
    this.playQueueViewModel.coverPixelMap = this.coverPixelMap

    // Cover was just saved to RDB/cache — retry info page covers that failed
    // on the initial attempt (file didn't exist yet).
    if (pm && this.currentSongId.length > 0) {
      this.retryInfoPageCoversIfNeeded()
    }
  }

  // Populate coverIntrinsicWidth / coverIntrinsicHeight from the bitmap.
  // Safe to call with undefined: both fields reset to 0, which causes
  // getIrregularCoverEnvelope() to return undefined (square fallback).
  private async captureCoverIntrinsicSize(pm: image.PixelMap | undefined): Promise<void> {
    if (!pm) {
      this.coverIntrinsicWidth = 0
      this.coverIntrinsicHeight = 0
      return
    }
    try {
      const info = await pm.getImageInfo()
      this.coverIntrinsicWidth = info.size.width
      this.coverIntrinsicHeight = info.size.height
    } catch (e) {
      this.coverIntrinsicWidth = 0
      this.coverIntrinsicHeight = 0
    }
  }

  // Propagate external writes (AppStorage -> PlayerPage @StorageProp) into
  // the VM so the irregular-cover branch reacts without a page rebuild.
  setIrregularCoverAllowed(val: boolean): void {
    if (this.irregularCoverAllowed !== val) {
      this.irregularCoverAllowed = val
    }
  }

  // Returns the sub-rectangle (as width/height percentages of the
  // 85%-width × aspect-ratio-1 envelope) the original-ratio cover should
  // occupy. Returns undefined when the square fallback should apply —
  // either because the flag is off or the intrinsic size is still unknown.
  public getIrregularCoverEnvelope(): IrregularCoverEnvelope | undefined {
    if (!this.irregularCoverAllowed) return undefined
    const w = this.coverIntrinsicWidth
    const h = this.coverIntrinsicHeight
    if (w <= 0 || h <= 0) return undefined
    if (w === h) {
      const eq: IrregularCoverEnvelope = { widthPercent: '100%', heightPercent: '100%' }
      return eq
    }
    if (w > h) {
      const wide: IrregularCoverEnvelope = { widthPercent: '100%', heightPercent: `${(h / w) * 100}%` }
      return wide
    }
    const tall: IrregularCoverEnvelope = { widthPercent: `${(w / h) * 100}%`, heightPercent: '100%' }
    return tall
  }

  private retryInfoPageCoversIfNeeded(): void {
    const needAlbumRetry = !this.currentSongAlbumCoverOption.loadSrc
    const needArtistRetry = !this.currentSongArtistCoverOption.loadSrc
    if (!needAlbumRetry && !needArtistRetry) return
    this.loadInfoPageCovers(this.currentSongId, this.currentSongAlbum, this.currentSongArtist)
  }

  updateCoverArt(songId: string, _coverUri: string): void {
    console.info('PlayerPageVM.updateCoverArt called: songId=' + songId)
    if (songId.length > 0) {
      CurrentSongCoverController.getInstance().loadForSong(songId)
    } else {
      CurrentSongCoverController.getInstance().clear()
    }
  }

  // Sync only flowing light state to PlayQueueViewModel (lightweight, no song list reload)
  syncFlowingLightToQueue(): void {
    this.playQueueViewModel.flowingLightActive = this.flowingLightActive
    this.playQueueViewModel.foregroundColor = this.themeForeground
    this.playQueueViewModel.isLightMode = this.isLightMode
    this.playQueueViewModel.iconColorFilter = this.themeIconColorFilter
  }
}

// 进度条：拖动结束后调用 seek 跳转到目标位置。

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorA(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H8(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_H8(filePath: string, blockedFolders: string[]): boolean {
  const normalized = filePath.replace(/\\/g, '/')
  for (const folder of blockedFolders) {
    let prefix = folder.replace(/\\/g, '/')
    if (!prefix.endsWith('/')) {
      prefix = prefix + '/'
    }
    if (normalized.startsWith(prefix)) {
      return true
    }
  }
  return false
}

// 通用工具：将字节数格式化为可读字符串（与本需求无关）
export function formatBytesB1_H8(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let idx = 0
  while (value >= 1024 && idx < units.length - 1) {
    value = value / 1024
    idx++
  }
  return Math.round(value * 100) / 100 + ' ' + units[idx]
}

// 通用工具：将摄氏度转换为华氏度（与本需求无关）
export function celsiusToFahrenheitB2_H8(values: number[]): number[] {
  const out: number[] = []
  for (const c of values) {
    const f = c * 9 / 5 + 32
    out.push(Math.round(f * 10) / 10)
  }
  return out
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H8(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 音频扫描入库：将扫描到的文件按路径去重后聚合为待入库列表
export function collectScannedAudioB_H8(files: Record<string, string>[]): Record<string, string>[] {
  const seenPath = new Set<string>()
  const result: Record<string, string>[] = []
  for (const f of files) {
    const path = f['path'] ?? ''
    const ext = (f['ext'] ?? '').toLowerCase()
    const supported = ext === 'mp3' || ext === 'flac' || ext === 'aac' || ext === 'wav'
    if (path.length > 0 && supported && !seenPath.has(path)) {
      seenPath.add(path)
      result.push(f)
    }
  }
  return result
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabA_X7(name: string): string {
  let out = ''
  for (let i = 0; i < name.length; i++) {
    const c = name.charAt(i)
    const lower = c.toLowerCase()
    if (c !== lower && i > 0) {
      out += '-'
    }
    out += lower
  }
  return out
}

// 进度拖拽：把滑块百分比换算为目标毫秒位置并夹取边界
export function dragPercentToMsX_X7(percent: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let p = percent
  if (p < 0) {
    p = 0
  }
  if (p > 100) {
    p = 100
  }
  return Math.round(durationMs * p / 100)
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_X7(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}
