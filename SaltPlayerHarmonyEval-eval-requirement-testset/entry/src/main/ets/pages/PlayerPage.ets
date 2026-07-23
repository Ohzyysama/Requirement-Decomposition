// PlayerPage.ets
// View layer: Full-screen music player UI component for Salt Player.
// MVVM: This View uses PlayerPageViewModel for all business logic and state.
//       The View only handles UI rendering and user interaction,
//       delegating data operations and state management to the ViewModel.
//
// Uses a vertical 2-page pager model (like Android VerticalPager):
//   Page 0 (scrollOffset=0): Player content
//   Page 1 (scrollOffset=-screenHeight): Play queue
// Swipe up/down scrolls between pages with finger-following drag.

import { PlayQueueComponent } from '../components/PlayQueueComponent'
import { SoundEffectDialogComponent } from '../components/SoundEffectDialogComponent'
import { AudioOutputInfoDialogComponent } from '../components/AudioOutputInfoDialogComponent'
import { SleepTimerDialogComponent } from '../components/SleepTimerDialogComponent'
import { LyricsInterfaceDialogComponent } from '../components/LyricsInterfaceDialogComponent'
import { LyricsLineComponent } from '../components/LyricsLineComponent'
import { FlowingLightComponent } from '../components/FlowingLightComponent'
import { CirclePlaybackCoverComponent } from '../components/CirclePlaybackCoverComponent'
import { FlowingLightConfig } from '../model/FlowingLightModel'
import { LyricsLine } from '../model/LyricsModel'
import { BottomSheetType } from '../model/PlayerPageModel'
import PlayerPageViewModel from '../viewmodel/PlayerPageViewModel'
import { ArtistItemViewModel } from '../viewmodel/ArtistItemViewModel'
import ScreenWakeViewModel from '../viewmodel/ScreenWakeViewModel'
import SystemBarModel from '../model/SystemBarModel'
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit'
import { LengthMetrics } from '@ohos.arkui.node'
import { ImageKnifeComponent } from '@ohos/imageknifepro'

@Component
export struct PlayerPage {
  // Callback to close player and return to main page
  onClose: () => void = () => {}
  // Callback when the user drags downward to dismiss (value 0..1).
  // Allows MainPage to drive playerProgress directly from the dismiss gesture.
  onDismissDrag: (progress: number) => void = () => {}
  // Callback when the user released a dismiss drag but did not pass the
  // close threshold — bounce back to fully open.
  onDismissCancel: () => void = () => {}
  // Callback to show song menu dialog
  onShowSongMenu: () => void = () => {}
  // Callback to show sleep timer dialog
  onShowSleepTimer: () => void = () => {}
  // Callback to show audio effect dialog
  onShowAudioEffect: () => void = () => {}
  // Callback to navigate to album content page
  onNavigateToAlbum: (albumTitle: string) => void = () => {}
  // Callback to navigate to artist content page
  onNavigateToArtist: (artistName: string) => void = () => {}
  // Callback to navigate to audio FX page
  onNavigateToFxActivity: () => void = () => {}
  // Whether to open directly to the queue page
  initialShowQueue: boolean = false

  // ==================== ViewModel ====================
  // Single @State ViewModel drives all UI state via @Track properties
  @State vm: PlayerPageViewModel = new PlayerPageViewModel()

  // ==================== AppStorage Links (shared across pages) ====================
  @StorageLink('currentSongTitle') @Watch('onSongTitleChanged') currentSongTitle: string = ''
  @StorageLink('currentSongArtist') @Watch('onSongArtistChanged') currentSongArtist: string = ''
  // Display states: updated at the right animation moment to avoid mid-animation text jumps
  @State private displayTitle: string = ''
  @State private displayArtist: string = ''
  private isSongSwitchAnimating: boolean = false
  // Debounce rapid skip clicks — ignore clicks within 500ms of each other
  private lastSkipTime: number = 0
  @StorageLink('isPlaying') isPlaying: boolean = false
  @StorageLink('currentSongId') @Watch('onSongChanged') currentSongId: string = ''
  @StorageLink('currentSongCoverUri') @Watch('onSongChanged') currentSongCoverUri: string = ''
  // Listen for system dark mode changes (set by EntryAbility.onConfigurationUpdate)
  @StorageLink('isSystemDark') @Watch('onSystemDarkChanged') isSystemDark: boolean = false

  // ==================== Lyrics Interface Settings (real-time via AppStorage) ====================
  @StorageProp('lyricsTextSize') lyricsTextSize: number = 20
  @StorageProp('lyricsTextAlignCenter') lyricsTextAlignCenter: boolean = false
  @StorageProp('lyricsFontWeight') lyricsFontWeight: number = 600
  // Karaoke compat strategy (0=current line only, 1=expand all lines, 2=always).
  // Mirrors AppStorage 'lyricsKaraokeCompatStrategy' so changes from any of the three
  // settings entry points re-render LyricsArea immediately.
  @StorageProp('lyricsKaraokeCompatStrategy') lyricsKaraokeCompatStrategy: number = 0
  // Spec13: lyrics-view blur toggle. Reactive — toggling the switch in the
  // settings page instantly re-renders LyricsLineComponent props in the ForEach.
  @StorageProp('lyricsBlur') lyricsBlur: boolean = false
  // Spec17: lyrics translation toggle. Reactive — the bottom-bar button reads
  // this for its active/inactive visual; the underlying VM state is updated
  // by LyricsViewModel.toggleTranslation (which persists via SettingsStore).
  @StorageProp('lyricsOpenTranslation') lyricsOpenTranslation: boolean = true
  // Reactive mirror of LyricsViewModel.isUserScrolling via AppStorage so
  // LyricsLineComponent's suppressBlur prop refreshes instantly without
  // relying on deep @Track穿透.
  @StorageProp('lyricsIsUserScrolling') lyricsIsUserScrolling: boolean = false
  // Spec16: 3D lyrics effect toggle (实验室). Live-reactive — toggling
  // the switch in Laboratory rebuilds LyricsArea's transform on the next frame.
  // When true, the scrollable List (and the static Scroll branch) is rotated
  // around the Y axis with an X-translation compensation. The empty-lyrics
  // placeholder Column stays flat (Scene 6).
  @StorageProp('lyricsUIEffect3D') lyricsUIEffect3D: boolean = false
  // Spec15: hide-control-panel toggle. When on, the bottom Time/Control/Icon
  // cluster slides off-screen as the user swipes to the lyrics page, and the
  // freed vertical space is absorbed by LyricsArea. Live-reactive via
  // @StorageProp + @Watch so the dialog (rendered on top of PlayerPage) can
  // flip the flag and the controls re-snap without dismissing the sheet.
  //
  // SCOPE (Spec15 requirements 7.3 / 7.4): this flag is intentionally
  // PORTRAIT-NORMAL-PLAYER ONLY. If a landscape player or fullscreen lyrics
  // page is added in the future, that new UI MUST ignore this flag — do not
  // wire the same @StorageProp into it without an explicit portrait guard,
  // since the spec restricts the bottom-cluster slide effect to the normal
  // portrait player only.
  @StorageProp('lyricsHideControlPanel')
  @Watch('onHideControlPanelChanged')
  lyricsHideControlPanel: boolean = false

  // ==================== System Bar Insets (edge-to-edge) ====================
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 0

  // ==================== Keep Screen On Setting ====================
  @StorageProp('playerKeepScreenOn') playerKeepScreenOn: boolean = false

  // ==================== Back Press Trigger (from MainPage.onBackPress) ====================
  @StorageProp('playerBackToPlayer') @Watch('onPlayerBackToPlayer') playerBackToPlayer: number = 0

  // ==================== Dismiss Offset Reset (from MainPage.closePlayerAnimated) ====================
  @StorageProp('playerDismissReset') @Watch('onDismissReset') playerDismissReset: number = 0

  // ==================== Sleep Timer State (reactive via AppStorage) ====================
  @StorageProp('sleepTimerState') sleepTimerState: number = 0
  @StorageProp('sleepTimerRemainingMs') sleepTimerRemainingMs: number = 0
  @StorageProp('sleepTimerIsExtendPhase') sleepTimerIsExtendPhase: boolean = false

  // ==================== Playback Speed ====================
  @StorageProp('playbackSpeed') playbackSpeed: number = 1.0

  // ==================== Volume Balance (spec14) ====================
  // Mirrors 'volumeBalanceEnabled' in AppStorage. When the user toggles the
  // switch in AudioOutputPage, re-evaluate the current song's "RG xx dB"
  // suffix in audioInfoSummary so the bottom info bar updates live without
  // having to skip to the next song.
  @StorageProp('volumeBalanceEnabled')
  @Watch('onVolumeBalanceChanged')
  volumeBalanceEnabled: boolean = true

  // ==================== Mini Lyrics Setting ====================
  @StorageProp('miniLyricsInPlayer') miniLyricsInPlayer: boolean = true

  // ==================== Circle Playback Cover ====================
  // When on, AlbumCoverArea renders CirclePlaybackCoverComponent instead of
  // the rectangle Image. Live-reactive via @StorageProp so toggles from the
  // User Interface settings page take effect without reloading the player.
  @StorageProp('circlePlaybackCover') circlePlaybackCover: boolean = false

  // ==================== Irregular Cover Allowed ====================
  // When on (and circle mode off), AlbumCoverArea renders the cover at its
  // original aspect ratio inside the 85% envelope. Off reverts to the
  // centre-cropped square. @Watch pushes external writes (User Interface
  // settings page) into the VM so the rectangular branch reacts without a
  // page rebuild. Single live source of truth is AppStorage.
  @StorageProp('irregularCoverAllowed')
  @Watch('onIrregularCoverAllowedChanged')
  irregularCoverAllowed: boolean = true

  // ==================== Immersion Mode (global) ====================
  // Mirrors 'immersionMode' in AppStorage (PersistentStorage-backed).
  // @Watch pushes updates made elsewhere (User Interface settings page) into the VM
  // so PlayerPage / MusicInfoPanel / LyricsArea all react to external toggles.
  @StorageProp('immersionMode') @Watch('onImmersionChanged') immersionMode: boolean = false

  // ==================== Player Screen Wallpaper (spec18) ====================
  // User-selected custom wallpaper, persisted under 'playerScreenBgCover'.
  // Empty string = no wallpaper, default dynamic flowing-light branch wins.
  // Non-empty = render the image as the player/queue background; the
  // FlowingLightComponent overlay is suppressed (Scene 4).
  @StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''

  // ==================== Playback Error State ====================
  @StorageProp('playbackError') playbackError: string = ''

  // ==================== Foreground Sync ====================
  // EntryAbility.onForeground() bumps this timestamp; the @Watch fires
  // immediately so progress refreshes without waiting for the 200ms timer.
  @StorageProp('foregroundTimestamp') @Watch('onReturnToForeground') foregroundTs: number = 0

  // ==================== View-only state (Swiper controller) ====================
  private hSwiperController: SwiperController = new SwiperController()
  private progressTimerId: number = -1
  private lyricsScroller: ListScroller = new ListScroller()
  @State private lyricsContainerHeight: number = 0
  @State private prevLyricsLineIndex: number = -1

  // ==================== Spec16: 3D lyrics effect geometry ====================
  // Mirrors Android LyricsContainer's `threeEffect = true` path (a single
  // transform applied to the whole list container; the fading-edge mask is
  // produced by the existing .fadingEdge call on the List/Scroll).
  // Tunable; the values below match the visual feel of the Android source.
  private static readonly LYRICS_3D_ROTATION_DEG: number = 35
  private static readonly LYRICS_3D_TRANSLATE_X_VP: number = 0
  private static readonly LYRICS_3D_PERSPECTIVE: number = -17
  // Lyrics edge state captured at touch start (avoids race with scroll events)
  private lyricsAtTopOnTouchStart: boolean = true
  private lyricsAtBottomOnTouchStart: boolean = false
  // Whether the current touch started inside the lyrics List (not the settings bar below it)
  private isTouchInLyricsList: boolean = false
  // Whether lyrics are at least partially visible in the Swiper.
  // Set true by onGestureSwipe (user swiping towards lyrics) and onAnimationStart (snap to lyrics).
  // Reset to false only by onAnimationEnd / onChange when fully settled on cover page.
  // This bridges all timing gaps for gesture detection (active swipe, snap-forward, snap-back).
  private isLyricsExposed: boolean = false
  // Spec15: horizontal translation progress for the bottom-control cluster.
  // 0 = fully visible at native position (cover / info page).
  // 1 = fully off-screen (lyrics page settled). Driven by Swiper.onGestureSwipe
  // to follow the finger and animated via onChange to snap at the rest state.
  @State private bottomControlsHideProgress: number = 0
  // Multi-touch lyrics scroll: when one finger holds Swiper at partial position and
  // another finger scrolls lyrics vertically. Swiper blocks child List gestures during
  // its own gesture, so we manually call lyricsScroller.scrollBy() for the second finger.
  private primaryTouchId: number = -1
  private multiTouchFingerId: number = -1
  private multiTouchLastY: number = 0
  // Tracks whether multi-touch scroll has reached lyrics edge and transitioned to page drag
  private multiTouchDraggingPage: boolean = false
  // Suppresses onReachEnd/onReachStart during programmatic scrollToIndex animations
  private isProgrammaticScrolling: boolean = false
  // Tracks previous isUserScrolling state to detect transition from scrolling to auto-sync
  private wasUserScrolling: boolean = false
  // Set when switching to lyrics page, forces scroll on next timer tick
  private needsForceScrollToCurrentLine: boolean = false

  // ==================== Music Info Panel scroll edge tracking ====================
  // The leftmost Swiper page (MusicInfoPanel) is a vertical Scroll. While the
  // user is mid-scrolling the inner content, the page-level pager (dismiss /
  // open queue) MUST stay disengaged — otherwise both the Scroll AND the page
  // translate at finger speed, the info content visually moves at 2x while the
  // playbar moves at 1x, and a growing gap appears between them.
  //
  // Strategy (simpler than the lyrics-page pattern, which can rely on the
  // viewmodel's lyricsIsScrollable flag): in the direction-lock branch, SKIP
  // the page-drag activation when the user is swiping in a direction the inner
  // Scroll can still consume. Concretely:
  //   swipe up   while NOT at bottom edge → inner Scroll handles
  //   swipe down while NOT at top    edge → inner Scroll handles
  //   otherwise                            → fall through to page-drag
  // Defaults (atTop=true, atBottom=false) yield correct behavior for
  // scrollable-at-top content immediately, even before onAreaChange has fired.
  // For non-scrollable content (info fits viewport), height tracking sets
  // atBottom=true so swipe-up still reaches the queue page.
  private infoScroller: Scroller = new Scroller()
  private isInfoPanelAtTop: boolean = true
  private isInfoPanelAtBottom: boolean = false
  // @State (not private): the constraintSize.minHeight binding on the inner Column
  // depends on infoViewportHeight. Without reactivity the Column's minHeight
  // stays at 0 forever, the Column shrinks to fit content, and the top buttons
  // visually drop when switching to a shorter song.
  @State infoContentHeight: number = 0
  @State infoViewportHeight: number = 0
  private isTouchInInfoPanel: boolean = false
  private infoAtTopOnTouchStart: boolean = true
  private infoAtBottomOnTouchStart: boolean = false

  private updateInfoBottomEdgeForLayout(): void {
    // When content fits viewport (non-scrollable), force atBottom=true so the
    // page pager engages on swipe-up — same UX as the AlbumCoverArea page.
    if (this.infoContentHeight > 0 && this.infoViewportHeight > 0
      && this.infoContentHeight <= this.infoViewportHeight + 1) {
      this.isInfoPanelAtBottom = true
    }
  }

  // ==================== Plain-text Lyrics scroll edge tracking ====================
  // For non-timed lyrics (plain text, no timestamps): mirrors the info-panel
  // handoff pattern. The inner Scroll consumes vertical gestures while content
  // is still scrollable; the page-level pager (dismiss / open queue) only
  // engages at the top/bottom edge. Without this, swiping up on plain-text
  // lyrics would always start the page drag and visibly tear away from the
  // playbar long before the lyrics finish scrolling.
  private plainLyricsScroller: Scroller = new Scroller()
  private isPlainLyricsAtTop: boolean = true
  private isPlainLyricsAtBottom: boolean = false
  @State plainLyricsContentHeight: number = 0
  @State plainLyricsViewportHeight: number = 0
  private isTouchInPlainLyrics: boolean = false
  private plainLyricsAtTopOnTouchStart: boolean = true
  private plainLyricsAtBottomOnTouchStart: boolean = false

  private updatePlainLyricsBottomEdgeForLayout(): void {
    if (this.plainLyricsContentHeight > 0 && this.plainLyricsViewportHeight > 0
      && this.plainLyricsContentHeight <= this.plainLyricsViewportHeight + 1) {
      this.isPlainLyricsAtBottom = true
    }
  }

  // Scroll lyrics list to the current active line.
  // Normally only scrolls when lineIndex changes, but also force-scrolls when:
  // 1. User scroll just ended (isUserScrolling: true → false) during a long interlude
  // 2. Swiper just switched to lyrics page (needsForceScrollToCurrentLine flag)
  private scrollLyricsToCurrentLine(smooth: boolean = true): void {
    const lineIndex = this.vm.lyricsViewModel.currentLineIndex
    const isUserScrolling = this.vm.lyricsViewModel.isUserScrolling

    // Detect transitions that require force-scroll even if lineIndex hasn't changed
    if (!isUserScrolling) {
      if (this.wasUserScrolling || this.needsForceScrollToCurrentLine) {
        this.prevLyricsLineIndex = -1
        this.needsForceScrollToCurrentLine = false
      }
    }
    this.wasUserScrolling = isUserScrolling

    if (lineIndex >= 0 && lineIndex !== this.prevLyricsLineIndex && !isUserScrolling) {
      this.prevLyricsLineIndex = lineIndex
      this.vm.isLyricsAtTop = false
      this.vm.isLyricsAtBottom = false
      this.isProgrammaticScrolling = true
      try {
        // +1 because first item is the top spacer
        this.lyricsScroller.scrollToIndex(lineIndex + 1, smooth, ScrollAlign.CENTER)
      } catch (_e) {
        // ignore scroll errors
      }
    }
  }

  // Title/artist watch: defer update if song-switch animation is in progress
  onSongTitleChanged(): void {
    if (!this.isSongSwitchAnimating) {
      this.displayTitle = this.currentSongTitle
    }
  }

  onSongArtistChanged(): void {
    if (!this.isSongSwitchAnimating) {
      this.displayArtist = this.currentSongArtist
    }
  }

  // Song change handler: triggers cover art, flowing light, and lyrics reset
  onSongChanged(): void {
    console.info('PlayerPage.onSongChanged @Watch fired: songId=' + this.currentSongId)
    this.vm.updateCoverArt(this.currentSongId, this.currentSongCoverUri)
    // Reset lyrics scroll state for new song
    this.prevLyricsLineIndex = -1
    try {
      this.lyricsScroller.scrollToIndex(0, false)
    } catch (_e) {
      // ignore if scroller not attached
    }
    // Reset info-panel scroll to top so the new song's content always renders
    // with the Keep-Screen-On button anchored at the same place. Without this,
    // a non-zero yOffset from the previous song persists and the top row
    // visually shifts when artist count / card heights change.
    try {
      this.infoScroller.scrollTo({ xOffset: 0, yOffset: 0 })
    } catch (_e) {
      // ignore if scroller not attached
    }
    this.isInfoPanelAtTop = true
    this.isInfoPanelAtBottom = false
    // Re-evaluate fade for the new song's content (height may differ).
    this.updateInfoBottomEdgeForLayout()
    // Reset plain-text lyrics scroll for the new song.
    try {
      this.plainLyricsScroller.scrollTo({ xOffset: 0, yOffset: 0 })
    } catch (_e) {
      // ignore if scroller not attached
    }
    this.isPlainLyricsAtTop = true
    this.isPlainLyricsAtBottom = false
    this.updatePlainLyricsBottomEdgeForLayout()
  }

  // Back press trigger handler: when MainPage increments playerBackToPlayer,
  // animate from queue page back to player page (mirrors Android BackHandler for queue).
  onPlayerBackToPlayer(): void {
    if (this.vm.currentPage === 1) {
      this.scrollToPlayer()
    }
  }

  // When MainPage starts a close animation, reset dismissOffset immediately
  // so the morph container owns the entire visual transition.
  onDismissReset(): void {
    if (this.vm.dismissOffset > 0) {
      this.vm.dismissOffset = 0
    }
  }

  // System dark mode change handler: re-apply flowing light settings
  // so "follow UI" mode reacts to light↔dark system theme switch
  onSystemDarkChanged(): void {
    console.info('PlayerPage.onSystemDarkChanged @Watch fired: isSystemDark=' + this.isSystemDark)
    this.vm.applyFlowingLightSettings()
    this.vm.syncFlowingLightToQueue()
    // Update status bar content color to match the new player theme
    SystemBarModel.getInstance().setStatusBarContentColor(this.vm.isLightMode)
  }

  onReturnToForeground(): void {
    this.vm.advanceProgress()
    this.scrollLyricsToCurrentLine()
  }

  // Keep PlayerPageViewModel.immersionMode aligned with the global AppStorage
  // value. This fires whenever another page (or another callsite) flips the
  // setting via SettingsStore.save / AppStorage.setOrCreate.
  onImmersionChanged(): void {
    this.vm.syncImmersionFromStorage(this.immersionMode)
  }

  // Keep PlayerPageViewModel.irregularCoverAllowed aligned with AppStorage.
  // Fires when the User Interface settings page toggles the flag.
  onIrregularCoverAllowedChanged(): void {
    this.vm.setIrregularCoverAllowed(this.irregularCoverAllowed)
  }

  // spec14: re-evaluate the current song's RG suffix when the volume balance
  // switch flips. Without this, audioInfoSummary holds the value computed at
  // the last song switch and "RG x dB" only appears/disappears after the user
  // skips tracks.
  onVolumeBalanceChanged(): void {
    if (this.vm.currentSongId.length > 0) {
      this.vm.updateAudioInfo(this.vm.currentSongId)
    }
  }

  // Spec15: react to live flips of 隐藏歌词界面控制面板.
  // - Off:  snap controls back into the row regardless of swiper page.
  // - On while parked on the lyrics page (index 2): slide controls out so
  //   the user sees the result without having to re-swipe.
  // The dialog (LyricsInterfaceDialogComponent) sits on top of PlayerPage as a
  // bottom sheet, so this @Watch is what makes the toggle feel live without
  // requiring the user to dismiss the sheet.
  onHideControlPanelChanged(): void {
    const ctx = this.getUIContext()
    if (!this.lyricsHideControlPanel) {
      ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.bottomControlsHideProgress = 0
      })
    } else if (this.vm.hSwiperIndex === 2) {
      ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.bottomControlsHideProgress = 1
      })
    } else {
      // On cover/info: leave progress at 0 — the gesture/onChange wiring
      // will animate it as soon as the user actually swipes.
      this.bottomControlsHideProgress = 0
    }
  }

  // Start cross-fade animation for flowing light (called via onCoverLoaded callback)
  private startFlowingLightCrossFade(): void {
    if (this.vm.flowingLightVM.isCrossFading) {
      animateTo({
        duration: FlowingLightConfig.CROSS_FADE_DURATION,
        curve: Curve.EaseInOut,
        onFinish: () => {
          this.vm.flowingLightVM.completeCrossFade()
        }
      }, () => {
        this.vm.flowingLightVM.currentOpacity = 1
        this.vm.flowingLightVM.previousOpacity = 0
      })
    }
  }

  aboutToAppear(): void {
    // Initialize display text from current AppStorage values
    this.displayTitle = this.currentSongTitle
    this.displayArtist = this.currentSongArtist

    // Pass initial configuration to ViewModel
    this.vm.initialShowQueue = this.initialShowQueue
    this.vm.onCloseAction = this.onClose
    this.vm.onShowSongMenuAction = this.onShowSongMenu
    this.vm.onNavigateToAlbumAction = this.onNavigateToAlbum
    this.vm.onNavigateToArtistAction = this.onNavigateToArtist
    this.vm.onNavigateToFxActivityAction = this.onNavigateToFxActivity

    // Initialize ViewModel (loads model data, sets up queue, wires callbacks)
    this.vm.initialize()

    // Seed the irregular-cover flag from AppStorage. Without this the VM
    // default would win until the User Interface page triggers a @Watch.
    this.vm.setIrregularCoverAllowed(this.irregularCoverAllowed)

    // Spec15: seed the bottom-control slide state so a cold launch that
    // restores hSwiperIndex=2 (lyrics page) doesn't flash the controls
    // visible for one frame before onChange fires.
    if (this.lyricsHideControlPanel && this.vm.hSwiperIndex === 2) {
      this.bottomControlsHideProgress = 1
    } else {
      this.bottomControlsHideProgress = 0
    }

    // Reconcile the status bar from the two persisted flags
    // ('immersionMode' and 'hideStatusBar'). This replaces the old
    // immersionMode-only branch so Scene 3 (hideStatusBar=true,
    // immersionMode=false) also keeps the bar hidden when the player opens.
    SystemBarModel.getInstance().reconcileStatusBarVisibility()

    // Wire up lyrics scroll callback — when lyrics finish loading for the
    // current song (page re-open), scroll to the playing line.
    // Use setTimeout to wait for the List to finish layout after ForEach data update.
    // Use non-smooth (instant) scroll to avoid visible animation from top.
    this.vm.onLyricsInitialScrollNeeded = () => {
      setTimeout(() => {
        // Force prevLyricsLineIndex reset so scrollLyricsToCurrentLine will act
        this.prevLyricsLineIndex = -1
        this.scrollLyricsToCurrentLine(false)
      }, 100)
    }

    // Wire up flowing light cross-fade callback (requires UIContext, kept in View)
    this.vm.flowingLightVM.onCoverLoaded = () => {
      this.startFlowingLightCrossFade()
    }

    // Load initial cover art if a song is already playing
    if (this.currentSongId.length > 0) {
      this.vm.updateCoverArt(this.currentSongId, this.currentSongCoverUri)
    }

    // Wire up the dismiss action to View's scrollToPlayer (requires UIContext)
    this.vm.playQueueViewModel.onDismissAction = () => {
      this.scrollToPlayer()
    }

    // Start progress simulation timer - delegates to ViewModel
    this.progressTimerId = setInterval(() => {
      this.vm.advanceProgress()
      // Auto-scroll lyrics to current line
      this.scrollLyricsToCurrentLine()
    }, 50)
  }

  aboutToDisappear(): void {
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId)
      this.progressTimerId = -1
    }
    SystemBarModel.getInstance().reconcileStatusBarVisibility()
  }

  // ==================== Animation Helpers (require UIContext, kept in View) ====================

  private animateSongSwitch(isNext: boolean): void {
    this.vm.playerTopAnimRight = isNext
    this.isSongSwitchAnimating = true

    // Slide out current title
    animateTo({ duration: 250, curve: Curve.EaseIn }, () => {
      this.vm.prepareSongSwitchSlideOut(isNext)
    })

    // After slide out, apply new data and slide in
    setTimeout(() => {
      // Snap display text to latest AppStorage values while invisible
      this.displayTitle = this.currentSongTitle
      this.displayArtist = this.currentSongArtist
      this.isSongSwitchAnimating = false

      this.vm.prepareSongSwitchSlideIn(isNext)
      animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
        this.vm.completeSongSwitchSlideIn()
      })
    }, 260)
  }

  private scrollToQueue(): void {
    this.vm.playQueueViewModel.scrollToCurrentSong()
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut,
      onFinish: () => {
        this.vm.setCurrentPage(1)
      }
    }, () => {
      this.vm.scrollOffset = -this.vm.screenHeight
    })
  }

  private scrollToPlayer(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut,
      onFinish: () => { this.vm.setCurrentPage(0) }
    }, () => {
      this.vm.scrollOffset = 0
    })
  }

  // ==================== Build ====================

  build() {
    // Outer Stack: dismiss translate + safe-area background
    Stack() {
      // Background covers safe area (status bar / nav bar)
      Stack() {
        // Fallback solid background
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.vm.getPagerBackgroundColor())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // Spec18: custom player-screen wallpaper. When set, fills the entire
        // background (cropped) and the FlowingLightComponent below is suppressed
        // so the wallpaper is the sole dynamic background. The play queue is a
        // sibling page in the inner pager, so this single image shows through
        // both player and queue.
        if (this.playerScreenBgCover.length > 0) {
          Image(this.playerScreenBgCover)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }

        // Flowing light background (visible when cover art is available and no error).
        // Spec18 Scene 4: disabled when a custom wallpaper is set.
        if (this.playerScreenBgCover.length === 0
            && this.vm.flowingLightActive
            && this.vm.flowingLightVM.coverPixelMap
            && this.playbackError.length === 0) {
          FlowingLightComponent({ viewModel: this.vm.flowingLightVM })
        }
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // Inner Stack: pager clipping (no expandSafeArea -> clip matches logical bounds)
      Stack() {
        Column() {
          // ===== Page 0: Player =====
          Column() {
            this.PlayerTopBar()

            Swiper(this.hSwiperController) {
              // Page 0: Music info panel (swipe right from cover)
              this.MusicInfoPanel()
              // Page 1: Album cover (default page)
              this.AlbumCoverArea()
              // Page 2: Lyrics (swipe left from cover)
              this.LyricsArea()
            }
            .index(this.vm.hSwiperIndex)
            .indicator(false)
            .loop(false)
            .cachedCount(2)
            .layoutWeight(1)
            .width('100%')
            .onChange((index: number) => {
              this.vm.hSwiperIndex = index
              AppStorage.setOrCreate('playerHSwiperIndex', index)
              // Switching away from lyrics page: cancel user-scroll lock and immediately sync to current position
              if (index !== 2) {
                this.vm.lyricsViewModel.resumeAutoSync()
              }
              // Switching TO lyrics page: flag force-scroll so the next timer tick
              // scrolls to the current line, even during a long interlude.
              if (index === 2) {
                this.vm.lyricsViewModel.resumeAutoSync()
                this.needsForceScrollToCurrentLine = true
              }
              this.vm.advanceProgress()
              // Spec15: snap the bottom-control slide progress to the page's
              // final state. The active gesture already updated it in real
              // time via onGestureSwipe; this handles flick / programmatic
              // page changes where onGestureSwipe never fires.
              if (this.lyricsHideControlPanel) {
                const target: number = (index === 2) ? 1 : 0
                this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.bottomControlsHideProgress = target
                })
              } else {
                this.bottomControlsHideProgress = 0
              }
            })
            .onGestureSwipe((index: number, extraInfo: SwiperAnimationEvent) => {
              // Swiping from cover (index 1) with negative offset means lyrics becoming visible
              if (index === 1 && extraInfo.currentOffset < 0) {
                this.isLyricsExposed = true
              }
              // Spec15: drive the bottom-control slide off-screen while the
              // user's finger moves between cover (1) and lyrics (2).
              if (this.lyricsHideControlPanel && this.vm.screenWidth > 0) {
                let progress: number = this.bottomControlsHideProgress
                const off: number = extraInfo.currentOffset
                if (index === 1) {
                  // cover → lyrics: currentOffset is negative as lyrics enters
                  const ratio: number = Math.min(Math.max(-off / this.vm.screenWidth, 0), 1)
                  progress = ratio
                } else if (index === 2) {
                  // lyrics → cover: currentOffset is positive as cover re-enters
                  const ratio: number = Math.min(Math.max(off / this.vm.screenWidth, 0), 1)
                  progress = 1 - ratio
                }
                this.bottomControlsHideProgress = progress
              }
            })
            .onAnimationStart((_index: number, targetIndex: number) => {
              if (targetIndex === 2) {
                this.isLyricsExposed = true
              }
              // Don't reset for targetIndex=0 — lyrics are still visible during snap-back animation
            })
            .onAnimationEnd((index: number) => {
              // Only reset when fully settled on cover page (lyrics no longer visible)
              if (index === 1) {
                this.isLyricsExposed = false
              }
            })

            Column() {
              this.PlayerTimeBar()
              this.PlayerControlBar()
              this.PlayerIconPanel()
            }
            .width('100%')
            .justifyContent(FlexAlign.End)
            // Spec15: when 隐藏歌词界面控制面板 is on, slide the cluster
            // horizontally off the viewport as the user moves toward lyrics
            // page, fade in parallel, then collapse out of layout once settled
            // so LyricsArea (layoutWeight 1) absorbs the freed pixels.
            // When the toggle is off, the modifiers compile to identity values
            // and the cluster renders at its native position / size.
            .translate({
              x: this.lyricsHideControlPanel && this.vm.screenWidth > 0
                ? -this.bottomControlsHideProgress * this.vm.screenWidth
                : 0
            })
            .opacity(this.lyricsHideControlPanel
              ? 1 - this.bottomControlsHideProgress
              : 1)
            .visibility(this.lyricsHideControlPanel && this.bottomControlsHideProgress >= 1
              ? Visibility.None
              : Visibility.Visible)
          }
          .width('100%')
          .height(this.vm.screenHeight > 0 ? this.vm.screenHeight : '100%')
          .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })

          // ===== Page 1: Queue =====
          Column() {
            PlayQueueComponent({
              viewModel: this.vm.playQueueViewModel
            })
          }
          .width('100%')
          .height(this.vm.screenHeight > 0 ? this.vm.screenHeight : '100%')
          .padding({ top: this.statusBarHeight, bottom: this.navBarHeight })
        }
        .width('100%')
        .translate({ y: this.vm.scrollOffset })
      }
      .width('100%')
      .height('100%')
      .clip(true)
      .onAreaChange((_: Area, newArea: Area) => {
        const newHeight = newArea.height as number
        const newWidth = newArea.width as number
        if (newHeight > 0 && newHeight !== this.vm.screenHeight) {
          const wasOnQueue = this.vm.currentPage === 1 || (this.vm.screenHeight === 0 && this.initialShowQueue)
          this.vm.screenHeight = newHeight
          if (wasOnQueue) {
            this.vm.playQueueViewModel.scrollToCurrentSong()
            this.vm.scrollOffset = -newHeight
            this.vm.setCurrentPage(1)
          } else {
            this.vm.scrollOffset = 0
          }
        }
        // Spec15: capture viewport width so the hide-control slide can use
        // a real off-screen distance instead of guessing.
        if (newWidth > 0 && newWidth !== this.vm.screenWidth) {
          this.vm.screenWidth = newWidth
        }
      })
      .bindSheet($$this.vm.showBottomSheet, this.bottomSheetBuilder(), {
        detents: this.vm.bottomSheetType === BottomSheetType.AUDIO_OUTPUT_INFO
          ? [SheetSize.MEDIUM, SheetSize.LARGE]
          : [SheetSize.FIT_CONTENT, SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        dragBar: true,
        showClose: false,
        backgroundColor: this.vm.bottomSheetType === BottomSheetType.LYRICS_INTERFACE
          ? $r('app.color.colorPageBackground')
          : (this.isSystemDark ? $r('app.color.salt_color_white') : $r('app.color.salt_color_sub_background')),
        onDisappear: () => {
          this.vm.closeBottomSheet()
        }
      })

      // ===== Large Image Overlay =====
      if (this.vm.showLargeImage) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#ff1a1a1a')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

          Image(this.vm.coverPixelMap ?? $r('app.media.ic_song_cover_v5'))
            .width('100%')
            .objectFit(ImageFit.Contain)
            .scale({ x: this.vm.largeImageScale, y: this.vm.largeImageScale })
            .translate({ x: this.vm.largeImageOffsetX, y: this.vm.largeImageOffsetY })
            .gesture(
              GestureGroup(GestureMode.Parallel,
                PinchGesture({ fingers: 2 })
                  .onActionUpdate((event: GestureEvent) => {
                    this.vm.updateLargeImageScale(event.scale)
                  }),
                PanGesture()
                  .onActionUpdate((event: GestureEvent) => {
                    this.vm.updateLargeImageOffset(event.offsetX, event.offsetY)
                  })
              )
            )

          Image($r('app.media.ic_cancel'))
            .width(56)
            .height(56)
            .padding(16)
            .fillColor(Color.White)
            .position({ right: 0, top: 0 })
            .margin({ top: 44 })
            .onClick(() => {
              this.vm.hideLargeImageOverlay()
            })
        }
        .width('100%')
        .height('100%')
        .transition(
          TransitionEffect.opacity(0).animation({ duration: 200 })
        )
      }
    }
    .width('100%')
    .height('100%')
    // Fade the ENTIRE player page (background + flowing light + content) so it
    .onTouch((event: TouchEvent) => {
      this.handlePagerDrag(event)
    })
    // Empty onClick consumes click events on blank areas so they do not
    // pass through to the Navigation content underneath.
    .onClick(() => {})
    // GestureGroup on the root node consumes all common gesture events on
    // blank areas so they do not pass through to the MainPage content underneath.
    .gesture(
      GestureGroup(GestureMode.Parallel,
        TapGesture(),
        LongPressGesture(),
        PanGesture(),
        SwipeGesture(),
        PinchGesture(),
        RotationGesture()
      )
    )
  }

  // ==================== Vertical Pager Drag Handler ====================
  // Drag up: scroll from player (page 0) to queue (page 1)
  // Drag down: scroll from queue (page 1) to player (page 0)
  // Both pages move as one connected unit (relay effect).
  // Note: This handler stays in View because it requires UIContext for animations.
  private handlePagerDrag(event: TouchEvent): void {
    const touch = event.touches[0]
    if (!touch) return

    switch (event.type) {
      case TouchType.Down:
        if (event.touches.length === 1) {
          // ---- First finger: normal initialization ----
          this.primaryTouchId = touch.id
          this.vm.touchStartX = touch.x
          this.vm.touchStartY = touch.y
          this.vm.isDragging = false
          this.vm.isDirectionLocked = false
          this.vm.isHorizontalSwiping = false
          this.vm.offsetAtDragStart = this.vm.scrollOffset
          this.vm.lastTouchY = touch.y
          this.vm.lastTouchTime = event.timestamp
          this.vm.touchVelocity = 0
          // Snapshot lyrics edge state using scroller offset for accuracy
          // (onReachStart/onReachEnd callbacks may be stale from auto-scrolling)
          if (this.isTouchInLyricsList || (this.vm.currentPage === 0 && (this.vm.hSwiperIndex === 2 || this.isLyricsExposed))) {
            const offset = this.lyricsScroller.currentOffset()
            this.lyricsAtTopOnTouchStart = offset ? offset.yOffset <= 0 : this.vm.isLyricsAtTop
            this.lyricsAtBottomOnTouchStart = this.vm.isLyricsAtBottom
          } else {
            this.lyricsAtTopOnTouchStart = this.vm.isLyricsAtTop
            this.lyricsAtBottomOnTouchStart = this.vm.isLyricsAtBottom
          }
          // Snapshot info-panel edge state. Use scroller offset for top accuracy;
          // bottom relies on the sticky onScrollEdge flag.
          if (this.vm.currentPage === 0 && this.vm.hSwiperIndex === 0) {
            const infoOffset = this.infoScroller.currentOffset()
            this.infoAtTopOnTouchStart = infoOffset ? infoOffset.yOffset <= 0 : this.isInfoPanelAtTop
            this.infoAtBottomOnTouchStart = this.isInfoPanelAtBottom
          } else {
            this.infoAtTopOnTouchStart = this.isInfoPanelAtTop
            this.infoAtBottomOnTouchStart = this.isInfoPanelAtBottom
          }
          // Snapshot plain-text lyrics edge state (mirrors info-panel logic).
          if (this.vm.currentPage === 0 && (this.vm.hSwiperIndex === 2 || this.isLyricsExposed)
            && !this.vm.lyricsIsScrollable && this.vm.lyricsSourceText.length > 0) {
            const offset = this.plainLyricsScroller.currentOffset()
            this.plainLyricsAtTopOnTouchStart = offset ? offset.yOffset <= 0 : this.isPlainLyricsAtTop
            this.plainLyricsAtBottomOnTouchStart = this.isPlainLyricsAtBottom
          } else {
            this.plainLyricsAtTopOnTouchStart = this.isPlainLyricsAtTop
            this.plainLyricsAtBottomOnTouchStart = this.isPlainLyricsAtBottom
          }
        } else if (event.touches.length > 1 && this.multiTouchFingerId < 0
          && this.isLyricsExposed && this.vm.currentPage === 0 && this.vm.lyricsIsScrollable) {
          // ---- Second finger: initialize multi-touch lyrics scroll ----
          // Swiper blocks child List gestures during its own drag, so we manually
          // scroll lyrics via lyricsScroller.scrollBy() for the second finger.
          for (const t of event.touches) {
            if (t.id !== this.primaryTouchId) {
              this.multiTouchFingerId = t.id
              this.multiTouchLastY = t.y
              this.multiTouchDraggingPage = false
              this.vm.lyricsViewModel.onUserScrollStart()
              break
            }
          }
        }
        break

      case TouchType.Move:
        // ---- Multi-touch lyrics scroll (second finger) ----
        if (this.multiTouchFingerId >= 0) {
          let scrollFinger: TouchObject | undefined = undefined
          for (const t of event.touches) {
            if (t.id === this.multiTouchFingerId) {
              scrollFinger = t
              break
            }
          }
          if (scrollFinger) {
            const fingerDelta = scrollFinger.y - this.multiTouchLastY // positive = down, negative = up
            this.multiTouchLastY = scrollFinger.y
            // Speed multiplier for multi-touch lyrics scroll (scrollBy has no native
            // momentum/fling, so a >1x factor compensates for the lack of inertia)
            const scrollDelta = fingerDelta * 1.5
            if (Math.abs(fingerDelta) > 0.5) {
              if (this.multiTouchDraggingPage) {
                // Already transitioned to page drag — update scrollOffset or dismissOffset
                if (this.vm.dismissOffset > 0 || (this.vm.scrollOffset === 0 && fingerDelta > 0)) {
                  this.vm.dismissOffset = Math.max(0, Math.min(this.vm.dismissOffset + fingerDelta, this.vm.screenHeight))
                } else {
                  let newOffset = this.vm.scrollOffset + fingerDelta
                  newOffset = Math.max(-this.vm.screenHeight, Math.min(newOffset, 0))
                  this.vm.scrollOffset = newOffset
                }
              } else {
                // Check edges dynamically
                const offset = this.lyricsScroller.currentOffset()
                const atTop = offset ? offset.yOffset <= 0 : this.vm.isLyricsAtTop
                const atBottom = this.vm.isLyricsAtBottom
                if (atBottom && fingerDelta < 0) {
                  // At bottom + finger up → transition to page drag (go to queue)
                  this.multiTouchDraggingPage = true
                  let newOffset = this.vm.scrollOffset + fingerDelta
                  this.vm.scrollOffset = Math.max(-this.vm.screenHeight, Math.min(newOffset, 0))
                } else if (atTop && fingerDelta > 0) {
                  // At top + finger down → transition to page drag (dismiss)
                  this.multiTouchDraggingPage = true
                  this.vm.dismissOffset = Math.max(0, Math.min(fingerDelta, this.vm.screenHeight))
                } else {
                  // Scroll lyrics with speed multiplier
                  try {
                    this.lyricsScroller.scrollBy(0, -scrollDelta)
                  } catch (_e) { /* ignore */ }
                }
              }
            }
          }
        }

        // ---- Single-touch direction lock and page drag (first finger) ----
        if (!this.vm.isDirectionLocked) {
          const dx = touch.x - this.vm.touchStartX
          const dy = touch.y - this.vm.touchStartY
          const absDx = Math.abs(dx)
          const absDy = Math.abs(dy)
          if (absDx > 15 || absDy > 15) {
            this.vm.isDirectionLocked = true
            if (absDx > absDy) {
              // Horizontal swipe dominant → let Swiper handle it, skip vertical drag
              this.vm.isHorizontalSwiping = true
            } else {
              // Vertical swipe dominant → check if lyrics page should handle scroll
              const isOnLyricsPage = this.vm.currentPage === 0
                && (this.vm.hSwiperIndex === 2 || this.isLyricsExposed)
                && this.vm.lyricsIsScrollable
                && this.isTouchInLyricsList
              // Info panel (leftmost Swiper page): SKIP the page-drag activation
              // when the inner Scroll can still consume the gesture (swiping up
              // while not at bottom, or swiping down while not at top). Falls
              // through to the existing currentPage===0 branches at edges or
              // when content is non-scrollable.
              const isOnInfoPanel = this.vm.currentPage === 0
                && this.vm.hSwiperIndex === 0
                && this.isTouchInInfoPanel
              // Plain-text (non-timed) lyrics on the lyrics page: behaves like
              // the info panel — inner Scroll consumes mid-content gestures,
              // page drag only engages at the top/bottom edge.
              const isOnPlainLyrics = this.vm.currentPage === 0
                && (this.vm.hSwiperIndex === 2 || this.isLyricsExposed)
                && !this.vm.lyricsIsScrollable
                && this.vm.lyricsSourceText.length > 0
                && this.isTouchInPlainLyrics
              if (isOnLyricsPage && dy < 0 && this.lyricsAtBottomOnTouchStart) {
                // Swipe up at bottom edge → go to queue
                this.vm.isDragging = true
                this.vm.touchStartY = touch.y
                this.vm.offsetAtDragStart = 0
              } else if (isOnLyricsPage && dy > 0 && this.lyricsAtTopOnTouchStart) {
                // Swipe down at top edge → dismiss player
                this.vm.isDragging = true
                this.vm.touchStartY = touch.y
                this.vm.offsetAtDragStart = 0
              } else if (isOnLyricsPage) {
                // Middle of lyrics → let lyrics list handle scroll, don't activate isDragging
              } else if (isOnPlainLyrics && dy < 0 && !this.plainLyricsAtBottomOnTouchStart) {
                // Plain-text lyrics, swipe up while inner Scroll can still scroll down → let Scroll handle
              } else if (isOnPlainLyrics && dy > 0 && !this.plainLyricsAtTopOnTouchStart) {
                // Plain-text lyrics, swipe down while inner Scroll can still scroll up → let Scroll handle
              } else if (isOnInfoPanel && dy < 0 && !this.infoAtBottomOnTouchStart) {
                // Swipe up while inner Scroll can still scroll down → let Scroll handle
              } else if (isOnInfoPanel && dy > 0 && !this.infoAtTopOnTouchStart) {
                // Swipe down while inner Scroll can still scroll up → let Scroll handle
              } else if (this.vm.currentPage === 0 && dy < 0) {
                this.vm.isDragging = true
                this.vm.touchStartY = touch.y
                this.vm.offsetAtDragStart = 0
              } else if (this.vm.currentPage === 0 && dy > 0) {
                this.vm.isDragging = true
                this.vm.touchStartY = touch.y
                this.vm.offsetAtDragStart = 0
              } else if (this.vm.currentPage === 1 && dy > 0
                && (!this.vm.isTouchInQueueList || this.vm.isQueueListAtTop)) {
                this.vm.isDragging = true
                this.vm.isPagerDragging = true
                this.vm.playQueueViewModel.pagerDragging = true
                this.vm.touchStartY = touch.y
                this.vm.offsetAtDragStart = -this.vm.screenHeight
              }
            }
          }
        }
        // Track velocity from recent touch movement (first finger)
        const now = event.timestamp
        const dt = now - this.vm.lastTouchTime
        if (dt > 0) {
          this.vm.touchVelocity = (touch.y - this.vm.lastTouchY) / dt * 1000000 // px/s (timestamp is in ns)
        }
        this.vm.lastTouchY = touch.y
        this.vm.lastTouchTime = now
        if (this.vm.isDragging) {
          const dy = touch.y - this.vm.touchStartY
          if (this.vm.currentPage === 0 && this.vm.offsetAtDragStart === 0 && dy > 0) {
            // Dismiss drag: drive MainPage's playerProgress directly so the morph
            // container shrinks in real time with the finger.
            const dismissProgress = Math.min(dy / this.vm.screenHeight, 1)
            this.vm.dismissOffset = dy
            this.onDismissDrag(1 - dismissProgress)
          } else {
            let newOffset = this.vm.offsetAtDragStart + dy
            newOffset = Math.max(-this.vm.screenHeight, Math.min(newOffset, 0))
            this.vm.scrollOffset = newOffset
          }
          // Prevent the touch event from bubbling up to the morph container's
          // PanGesture, which would compete with the player page's drag logic
          // and cause visual glitches when closing.
          event.stopPropagation()
        }
        break

      case TouchType.Up:
      case TouchType.Cancel:
        // ---- Multi-touch scroll finger released ----
        if (this.multiTouchFingerId >= 0) {
          let multiFingerStillDown = false
          for (const t of event.touches) {
            if (t.id === this.multiTouchFingerId) {
              multiFingerStillDown = true
              break
            }
          }
          if (!multiFingerStillDown) {
            if (this.multiTouchDraggingPage) {
              // Snap page after multi-touch page drag
              if (this.vm.dismissOffset > this.vm.screenHeight * 0.1) {
                this.onClose()
                this.getUIContext().animateTo({
                  duration: 400, curve: Curve.EaseOut,
                  onFinish: () => { this.vm.dismissOffset = 0 }
                }, () => { this.vm.dismissOffset = this.vm.screenHeight })
              } else if (this.vm.dismissOffset > 0) {
                this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
                  this.vm.dismissOffset = 0
                })
              } else if (this.vm.scrollOffset < -this.vm.screenHeight * 0.02) {
                this.scrollToQueue()
              } else if (this.vm.scrollOffset !== 0) {
                this.scrollToPlayer()
              }
            }
            this.multiTouchFingerId = -1
            this.multiTouchDraggingPage = false
            // Don't call onUserScrollEnd() here — keep isUserScrolling=true and
            // isTouching=true so auto-scroll won't jump lyrics back to the playing
            // line. The user may put the finger back to continue scrolling.
            // onUserScrollEnd() is called below when ALL fingers are released.
          }
        }
        // End user scroll only when all fingers are released
        if (event.touches.length === 0) {
          this.primaryTouchId = -1
          this.multiTouchFingerId = -1
          this.multiTouchDraggingPage = false
          if (this.vm.lyricsViewModel.isUserScrolling) {
            this.vm.lyricsViewModel.onUserScrollEnd()
          }
        }

        // ---- Single-touch page snap (existing logic) ----
        if (this.vm.isDragging) {
          const noScrollDisplacement = Math.abs(this.vm.scrollOffset) < 1
          if (this.vm.dismissOffset > this.vm.screenHeight * 0.1 && noScrollDisplacement) {
            // Let MainPage's closePlayerAnimated drive the entire visual transition.
            // Do NOT animate dismissOffset here — it is purely a gesture-tracking
            // value now (translate has been removed) and would fight the morph
            // container's spring animation.
            this.onClose()
          } else if (this.vm.dismissOffset > 0 && noScrollDisplacement) {
            // Dismiss threshold not met — bounce back to fully open.
            this.onDismissCancel()
          } else {
            // The user produced an upward page-scroll displacement while a stale
            // dismissOffset was still > 0. Recover the morph container first, then
            // let the normal velocity/distance snap logic decide the destination.
            if (this.vm.dismissOffset > 0) {
              this.vm.dismissOffset = 0
              this.onDismissCancel()
            }
            // Velocity-based or distance-based page switching
            const velocity = this.vm.touchVelocity // px/s, positive = downward
            const VELOCITY_THRESHOLD = 300 // px/s — a brisk flick
            const DISTANCE_THRESHOLD = 0.02 // 2% of screen height

            if (this.vm.currentPage === 0 && velocity < -VELOCITY_THRESHOLD) {
              // Fast upward flick on player → go to queue
              this.scrollToQueue()
            } else if (this.vm.currentPage === 1 && velocity > VELOCITY_THRESHOLD) {
              // Fast downward flick on queue → go to player
              this.scrollToPlayer()
            } else if (this.vm.scrollOffset < -this.vm.screenHeight * DISTANCE_THRESHOLD
              && this.vm.currentPage === 0) {
              this.scrollToQueue()
            } else if (this.vm.currentPage === 1
              && this.vm.scrollOffset > -this.vm.screenHeight * (1 - DISTANCE_THRESHOLD)) {
              this.scrollToPlayer()
            } else if (this.vm.currentPage === 1) {
              this.scrollToQueue()
            } else {
              this.scrollToPlayer()
            }
          }
        }
        this.vm.isDragging = false
        this.vm.isDirectionLocked = false
        this.vm.isHorizontalSwiping = false
        this.vm.isPagerDragging = false
        this.vm.playQueueViewModel.pagerDragging = false
        break
    }
  }

  // ==================== Media Router Icon Builder ====================
  @Builder
  MediaRouterIcon() {
    Image($r('app.media.ic_media_router'))
      .width(56)
      .height(56)
      .padding(18)
      .fillColor(this.vm.themeForeground)
      .objectFit(ImageFit.Contain)
  }

  // ==================== Player Top Bar ====================
  @Builder
  PlayerTopBar() {
    Row() {
      Column() {
        Text(this.displayTitle || $r('app.string.app_name'))
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.vm.themeForeground)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(this.displayArtist || 'Hi~')
            .fontSize(13)
            .fontColor(this.vm.themeForeground)
            .opacity(0.5)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              console.info('TODO: navigate to artist page - not yet implemented')
            })
        }
        .margin({ top: 1 })
        .width('100%')
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 14 })
      .translate({ x: this.vm.songInfoTranslateX })
      .opacity(this.vm.songInfoOpacity)

      // Media router: render icon outside AVCastPicker because
      // fillColor does not work inside AVCastPicker's customPicker builder.
      Stack() {
        Image($r('app.media.ic_media_router'))
          .width(56)
          .height(56)
          .padding(18)
          .fillColor(this.vm.themeForeground)
          .objectFit(ImageFit.Contain)
          .hitTestBehavior(HitTestMode.None)

        AVCastPicker({
          normalColor: Color.Transparent,
          activeColor: Color.Transparent,
          onStateChange: (state: AVCastPickerState) => {
            if (state === AVCastPickerState.STATE_APPEARING) {
              console.info('AVCastPicker appearing')
            }
          }
        })
          .width(56)
          .height(56)
      }
      .width(56)
      .height(56)
    }
    .width('100%')
    // Keep the top bar's height stable (only fade opacity) so the Swiper
    // beneath it doesn't grow upward when entering immersion mode. This
    // prevents the music-info panel content (including the immersion-mode
    // toggle itself) from jumping up while sibling layout animations are
    // mid-transition.
    .height(88)
    .padding({ left: 16, right: 12 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.vm.immersionMode ? 0 : 1)
    .animation({ duration: 300 })
  }

  // ==================== Album Cover Area ====================
  @Builder
  AlbumCoverArea() {
    Column() {
      if (this.playbackError.length > 0) {
        // Error display — replaces album art when file is missing
        Column() {
          Row() {
            Image($r('app.media.ic_warning'))
              .width(20)
              .height(20)
              .fillColor('#CCAA00')
              .margin({ right: 6 })
            Text('错误')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
          }
          .alignItems(VerticalAlign.Center)

          Text(this.playbackError)
            .fontSize(13)
            .fontColor('#999999')
            .margin({ top: 4 })
        }
        .width('85%')
        .aspectRatio(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .borderRadius(8)
      } else {
        if (this.circlePlaybackCover) {
          CirclePlaybackCoverComponent({
            onLongPress: () => {
              this.vm.showLargeImageOverlay()
            },
          })
        } else {
          // Rectangular (non-circle) branch. When the "Allow Irregular Cover"
          // flag is on AND the bitmap's intrinsic size is known, the VM's
          // envelope helper returns percentage dimensions that preserve the
          // original aspect ratio within the 85% × 1 square. Otherwise fall
          // back to the square crop (prior behaviour) so Scenes 2/4 stay
          // pixel-identical to the old rendering.
          Stack() {
            if (this.vm.coverPixelMap) {
              if (this.vm.getIrregularCoverEnvelope()) {
                Image(this.vm.coverPixelMap)
                  .width(this.vm.getIrregularCoverEnvelope()!.widthPercent)
                  .height(this.vm.getIrregularCoverEnvelope()!.heightPercent)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(8)
                  .clip(true)
                  .shadow({
                    radius: 30,
                    color: '#0d000000',
                    offsetX: 0,
                    offsetY: 6
                  })
                  .onClick(() => {
                    this.hSwiperController.showNext()
                  })
                  .gesture(
                    LongPressGesture()
                      .onAction(() => {
                        this.vm.showLargeImageOverlay()
                      })
                  )
              } else {
                Image(this.vm.coverPixelMap)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
                  .clip(true)
                  .shadow({
                    radius: 30,
                    color: '#0d000000',
                    offsetX: 0,
                    offsetY: 6
                  })
                  .onClick(() => {
                    this.hSwiperController.showNext()
                  })
                  .gesture(
                    LongPressGesture()
                      .onAction(() => {
                        this.vm.showLargeImageOverlay()
                      })
                  )
              }
            } else {
              Image($r('app.media.ic_song_cover_v5'))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .borderRadius(8)
                .clip(true)
            }
          }
          .width('85%')
          .aspectRatio(1)
          .alignContent(Alignment.Center)
        }
      }

      // Mini lyrics or audio info below cover
      // Wrap in a Column whose height/opacity animate with immersionMode so the
      // transition matches the rest of the elements (PlayerTopBar / PlayerTimeBar
      // / bottom icon bar) instead of hard-disappearing via an if/else switch.
      Column() {
        if (this.miniLyricsInPlayer) {
          this.MiniLyricsArea()
        } else {
          this.AudioInfoBelowCover()
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .height(this.vm.immersionMode ? 0 : undefined)
      .opacity(this.vm.immersionMode ? 0 : 1)
      .animation({ duration: 300 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    // Cover re-centers when immersion is on: extra top padding gives the album
    // cover more space above it, mirroring Android PlayerCover.kt's
    // immersionModePaddingTop animation.
    .padding({ top: this.vm.immersionMode ? 48 : 0 })
    .animation({ duration: 300 })
  }

  @Builder
  MiniLyricsArea() {
    Column() {
      ForEach(this.vm.miniLyricsLines, (line: string, index: number) => {
        Text(line)
          .fontSize(12)
          .fontColor(this.vm.themeForeground)
          .opacity(index === 0 ? 0.9 : 0.5)
          .fontWeight(index === 0 ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%')
          .margin({ top: index === 0 ? 0 : 2 })
      }, (line: string, index: number) => index.toString() + '_' + line)
    }
    .width('85%')
    .height(88)
    .padding({ top: 40, bottom: 4 })
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.hSwiperController.showNext()
    })
  }

  @Builder
  AudioInfoBelowCover() {
    Column() {
      Column()
      Text(this.vm.audioInfoSummary)
        .fontSize(12)
        .fontColor(this.vm.themeForeground)
        .opacity(0.5)
        .maxLines(1)
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('85%')
    .height(88)
    .justifyContent(FlexAlign.End)
    .alignItems(HorizontalAlign.Center)
  }

  // ==================== Lyrics Area (swipe left from album cover) ====================
  @Builder
  LyricsArea() {
    Column() {
      if (this.vm.lyricsIsScrollable) {
        // Multi-line scrollable lyrics
        List({ scroller: this.lyricsScroller }) {
          // Top spacer for centering first line
          ListItem() {
            Column()
              .width('100%')
              .height(this.lyricsContainerHeight > 0 ? this.lyricsContainerHeight * 0.5 : 200)
          }

          ForEach(this.vm.lyricsLines, (line: LyricsLine, index: number) => {
            ListItem() {
              LyricsLineComponent({
                line: line,
                isCurrent: index === this.vm.currentLyricsLineIndex,
                showTranslation: this.lyricsOpenTranslation
                  && this.vm.lyricsHasTranslation,
                textSize: this.lyricsTextSize,
                fontWeightValue: this.lyricsFontWeight,
                textAlignCenter: this.lyricsTextAlignCenter,
                themeColor: this.vm.themeForeground,
                karaokeStrategyIndex: this.lyricsKaraokeCompatStrategy,
                hasAnyKaraokeInDoc: this.vm.lyricsHasAnyKaraoke,
                currentTimeMs: this.vm.lyricsCurrentTimeMs,
                blurEnabled: this.lyricsBlur,
                lineDistance: this.vm.currentLyricsLineIndex >= 0
                  ? Math.abs(index - this.vm.currentLyricsLineIndex)
                  : 0,
                // Suppress blur while the user is actively scrolling the lyrics
                // list so all lines remain readable. Uses @StorageProp mirror
                // (lyricsIsUserScrolling) to avoid deep @Track穿透 unreliability.
                suppressBlur: this.lyricsIsUserScrolling,
                effect3D: this.lyricsUIEffect3D,
                onLineClick: () => {
                  const line = this.vm.lyricsLines[index]
                  if (!line) return
                  // Clear stale edge flags and suppress onReachEnd/onReachStart
                  // during the upcoming programmatic scroll animation
                  this.vm.isLyricsAtTop = false
                  this.vm.isLyricsAtBottom = false
                  this.isProgrammaticScrolling = true
                  // Single entry point for line-click seek. Sets UI state,
                  // updates LyricsViewModel, opens the post-seek settling
                  // window (so advanceProgress can't pull the highlight back
                  // to the previous line while the audio service is still
                  // landing on the new position), and dispatches the seek.
                  this.vm.handleLyricLineClick(line.startTime, index)
                }
              })
            }
          }, (line: LyricsLine, index: number) =>
          this.vm.lyricsVersionTag + '_' + index.toString() + '_' + line.startTime.toString())

          // Bottom spacer
          ListItem() {
            Column()
              .width('100%')
              .height(this.lyricsContainerHeight > 0 ? this.lyricsContainerHeight * 0.5 : 200)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(10)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })
        // Spec16: 3D lyrics effect (实验室). When the toggle is on, rotate the
        // entire List around the Y-axis with a horizontal-translation
        // compensation; when off, both transforms degenerate to identity so
        // the flat baseline is preserved (Scene 4). Mirrors Android
        // LyricsContainer's `threeEffect = true` path. The .fadingEdge above
        // produces the top/bottom gradient masks under the rotated layer (Scene 3).
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.lyricsUIEffect3D ? -PlayerPage.LYRICS_3D_ROTATION_DEG : 0,
          centerX: '0%',
          centerY: '50%',
          perspective: PlayerPage.LYRICS_3D_PERSPECTIVE
        })
        .translate({ x: this.lyricsUIEffect3D ? PlayerPage.LYRICS_3D_TRANSLATE_X_VP : 0 })
        .enableScrollInteraction(!this.vm.isDragging)
        .onReachStart(() => {
          if (!this.isProgrammaticScrolling) {
            this.vm.isLyricsAtTop = true
            this.vm.isLyricsAtBottom = false
          }
        })
        .onReachEnd(() => {
          if (!this.isProgrammaticScrolling) {
            this.vm.isLyricsAtBottom = true
            this.vm.isLyricsAtTop = false
          }
        })
        .onDidScroll((scrollOffset: number) => {
          if (scrollOffset > 0) {
            this.vm.isLyricsAtTop = false
          } else if (scrollOffset < 0) {
            this.vm.isLyricsAtBottom = false
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isProgrammaticScrolling = false
            this.isTouchInLyricsList = true
            this.vm.lyricsViewModel.onUserScrollStart()
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isTouchInLyricsList = false
            // Skip onUserScrollEnd when multi-touch lyrics scroll is active (finger 1
            // still holding Swiper) — prevents auto-scroll from jumping lyrics back to
            // the playing line between finger lifts. handlePagerDrag calls onUserScrollEnd
            // when all fingers are released.
            if (this.multiTouchFingerId < 0) {
              this.vm.lyricsViewModel.onUserScrollEnd()
            }
          }
        })
        .onAreaChange((_: Area, newArea: Area) => {
          const newHeight = newArea.height as number
          if (newHeight > 0) {
            this.lyricsContainerHeight = newHeight
          }
        })
      } else if (this.vm.lyricsSourceText.length > 0) {
        // Static (non-timed) lyrics — same handoff pattern as MusicInfoPanel:
        // inner Scroll consumes vertical gestures while content is scrollable;
        // page drag only engages at the top/bottom edge. EdgeEffect.None (vs.
        // Spring) avoids overscroll bounce that would otherwise visually pull
        // the page apart at the edges before the handoff fires.
        Scroll(this.plainLyricsScroller) {
          Column() {
            Text(this.vm.lyricsSourceText)
              .fontSize(this.lyricsTextSize)
              .fontWeight(this.lyricsFontWeight)
              .fontColor(this.vm.themeForeground)
              .opacity(0.8)
              .width('100%')
              .padding({ top: 16, bottom: 16 })
              .textAlign(this.lyricsTextAlignCenter
                ? TextAlign.Center : TextAlign.Start)
          }
          .width('100%')
          .onAreaChange((_: Area, newArea: Area) => {
            const h = newArea.height as number
            if (h > 0 && h !== this.plainLyricsContentHeight) {
              this.plainLyricsContentHeight = h
              this.updatePlainLyricsBottomEdgeForLayout()
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
        .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })
        // Spec16: parity with the timed-list path — when a song has only
        // static (non-timed) text, the Scroll IS the lyrics container, so
        // the 3D rotation must apply to it for Scene 3 consistency.
        .rotate({
          x: 0,
          y: 1,
          z: 0,
          angle: this.lyricsUIEffect3D ? -PlayerPage.LYRICS_3D_ROTATION_DEG : 0,
          centerX: '0%',
          centerY: '50%',
          perspective: PlayerPage.LYRICS_3D_PERSPECTIVE
        })
        .translate({ x: this.lyricsUIEffect3D ? PlayerPage.LYRICS_3D_TRANSLATE_X_VP : 0 })
        .onAreaChange((_: Area, newArea: Area) => {
          const h = newArea.height as number
          if (h > 0 && h !== this.plainLyricsViewportHeight) {
            this.plainLyricsViewportHeight = h
            this.updatePlainLyricsBottomEdgeForLayout()
          }
        })
        .onScrollEdge((side: Edge) => {
          if (side === Edge.Top) {
            this.isPlainLyricsAtTop = true
            // Mid-gesture handoff: a continuous swipe-down that scrolled the
            // inner Scroll to its top edge should keep dragging the page
            // downward (dismiss), instead of stalling at the edge.
            if (this.isTouchInPlainLyrics && this.vm.currentPage === 0 && !this.vm.isDragging) {
              this.vm.isDragging = true
              this.vm.touchStartY = this.vm.lastTouchY
              this.vm.offsetAtDragStart = 0
            }
          } else if (side === Edge.Bottom) {
            this.isPlainLyricsAtBottom = true
            // Symmetric handoff at the bottom: continuous swipe-up flows into
            // the page-drag that opens the play queue.
            if (this.isTouchInPlainLyrics && this.vm.currentPage === 0 && !this.vm.isDragging) {
              this.vm.isDragging = true
              this.vm.touchStartY = this.vm.lastTouchY
              this.vm.offsetAtDragStart = 0
            }
          }
        })
        .onDidScroll((_xOffset: number, yOffsetDelta: number) => {
          if (yOffsetDelta > 0) {
            this.isPlainLyricsAtTop = false
          } else if (yOffsetDelta < 0) {
            this.isPlainLyricsAtBottom = false
          }
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.isTouchInPlainLyrics = true
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.isTouchInPlainLyrics = false
          }
        })
      } else {
        // Empty lyrics placeholder
        Column() {
          Text($r('app.string.no_lyrics'))
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.vm.themeForeground)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
      }

      // Bottom settings bar
      Row() {
        // Left: lyrics settings icon + source tag
        Row() {
          Image($r('app.media.ic_player_lyrics'))
            .width(18)
            .height(18)
            .fillColor(this.vm.themeForeground)
            .objectFit(ImageFit.Contain)
            .padding({ top: 2, bottom: 3, left: 2, right: 2 })
            .border({ width: 1,
              color: '#80A0A0A0', radius: 3 })

          Text(this.vm.lyricsSourceTag)
            .fontSize(13)
            .fontColor(this.vm.themeForeground)
            .opacity(0.75)
            .margin({ left: 6 })
        }
        .padding({ right: 16, top: 8, bottom: 8 })
        .borderRadius(20)
        .onClick(() => {
          this.vm.openBottomSheet(BottomSheetType.LYRICS_INTERFACE)
        })
        .accessibilityText('歌词设置')

        Blank()

        if (this.vm.lyricsHasTranslation) {
          Row() {
            Text('译')
              .fontSize(11.5)
              .fontColor(this.lyricsOpenTranslation
                ? (this.vm.isLightMode ? '#ffffffff' : '#ff000000')
                : this.vm.themeForeground)
              .animation({ duration: 200, curve: Curve.FastOutSlowIn })
          }
          .size({ width: 18, height: 18 })
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .backgroundColor(this.lyricsOpenTranslation ? this.vm.themeForeground : '#00000000')
          .border({
            width: 1,
            color: this.lyricsOpenTranslation
              ? this.vm.themeForeground
              : '#80A0A0A0',
            radius: 3
          })
          .animation({ duration: 200, curve: Curve.FastOutSlowIn })
          .onClick(() => {
            this.vm.lyricsViewModel.toggleTranslation()
            setTimeout(() => {
              if (this.vm.currentLyricsLineIndex >= 0) {
                try {
                  this.lyricsScroller.scrollToIndex(
                    this.vm.currentLyricsLineIndex + 1, true, ScrollAlign.CENTER)
                } catch (_e) {
                }
              }
            }, 50)
          })
          .accessibilityText('翻译开关')
          .padding({ top: 0.5 })
        }
      }
      .width('100%')
      .height(this.vm.immersionMode ? 0 : 48)
      .opacity(this.vm.immersionMode ? 0 : 1)
      .animation({ duration: 300 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 30, right: 30 })
    .clip(true)
  }

  // ==================== Music Info Panel (swipe right from album cover) ====================
  @Builder
  MusicInfoPanel() {
    // Outer Column with explicit '100%' height + Scroll using layoutWeight(1)
    // mirrors LyricsArea. This guarantees the Scroll viewport is pinned to the
    // Swiper page height so tall content (e.g. many artists) is hidden behind
    // the bottom edge and reachable only via scroll, instead of letting the
    // Scroll wrap-content and grow with the content.
    Column() {
    Scroll(this.infoScroller) {
      Column() {
        // ---- Control Buttons 2x2 Grid ----
        Row() {
          this.KeepScreenOnButton()
          this.ImmersionModeButton()
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

          // Row() {
          //   this.PanelControlButton($r('app.media.ic_salt_player_audio_fx'), 'Original Sound', () => {
          //     this.vm.onNavigateToFxActivityAction()
          //   })
          //   this.PanelControlButton($r('app.media.ic_dlna'), 'DLNA (beta)', () => {
          //     console.info('TODO: show DLNA dialog')
          //   })
          // }
          // .width('100%')
          // .margin({ top: 8 })
          // .justifyContent(FlexAlign.SpaceBetween)

          // ---- Audio Information Card ----
          Column() {
            Text($r('app.string.audio_information'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.vm.themeForeground)
              .width('100%')

            Text(this.vm.currentSongFormatDisplay)
              .fontSize(13)
              .fontColor(this.vm.themeForeground)
              .opacity(0.5)
              .width('100%')
              .margin({ top: 16 })

            Text(this.vm.currentSongAudioDetails)
              .fontSize(13)
              .fontColor(this.vm.themeForeground)
              .opacity(0.5)
              .width('100%')
              .margin({ top: 6 })
          }
          .margin({ top: 10 })
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#08000000')
          .onClick(() => {
            this.vm.openBottomSheet(BottomSheetType.AUDIO_OUTPUT_INFO)
          })

          // ---- From Album Card ----
          Column() {
            Text($r('app.string.from_album'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.vm.themeForeground)
              .width('100%')

            Row() {
              Stack() {
                ImageKnifeComponent({ imageKnifeOption: this.vm.currentSongAlbumCoverOption })
                  .width(48)
                  .height(48)
              }
              .width(48)
              .height(48)
              .borderRadius(6)
              .clip(true)

              Column() {
                Text(this.vm.currentSongAlbum.length > 0
                  ? this.vm.currentSongAlbum
                  : $r('app.string.unknown_album_title'))
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.vm.themeForeground)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(this.vm.currentSongAlbumArtist.length > 0
                  ? this.vm.currentSongAlbumArtist
                  : $r('app.string.unknown_album_artist'))
                  .fontSize(13)
                  .fontColor(this.vm.themeForeground)
                  .opacity(0.5)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              .margin({ left: 12 })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Center)
          }
          .margin({ top: 8 })
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#08000000')
          .onClick(() => {
            if (this.vm.currentSongAlbum) {
              this.vm.onNavigateToAlbumAction(this.vm.currentSongAlbum)
            }
          })

          // ---- Participating Artists Card ----
          // Hide the entire section (including the "参与创作的艺术家" title) when
          // the song has no participating artists.
          if (this.vm.participatingArtists.length > 0) {
          Column() {
            Text($r('app.string.participating_artists'))
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.vm.themeForeground)
              .width('100%')

            ForEach(this.vm.participatingArtists, (artistVM: ArtistItemViewModel) => {
              Row() {
                Stack() {
                  ImageKnifeComponent({ imageKnifeOption: artistVM.coverOption })
                    .width(48)
                    .height(48)
                }
                .width(48)
                .height(48)
                .borderRadius(24)
                .clip(true)

                Column() {
                  Text(artistVM.hasName
                    ? artistVM.name
                    : $r('app.string.unknown_artist'))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.vm.themeForeground)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Text(artistVM.songCountText)
                    .fontSize(13)
                    .fontColor(this.vm.themeForeground)
                    .opacity(0.5)
                }
                .layoutWeight(1)
                .margin({ left: 12 })
                .alignItems(HorizontalAlign.Start)
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                if (artistVM.name) {
                  this.vm.onNavigateToArtistAction(artistVM.name)
                }
              })
            }, (artistVM: ArtistItemViewModel) => artistVM.id + artistVM.name)
          }
          .margin({ top: 8 })
          .padding(12)
          .borderRadius(12)
          .backgroundColor('#08000000')
          }
        }
      .width('100%')
      .padding({ top: 8, bottom: 8, left: 30, right: 30 })
      .justifyContent(FlexAlign.Start)
      // Force the Column to occupy at least the Scroll viewport so its top
      // edge anchors at yOffset=0 regardless of how short the content is.
      // Without this the Scroll vertically centres a shorter Column (e.g. a
      // single-artist song) and the Keep-Screen-On button visibly drops
      // when switching from a multi-artist song.
      .constraintSize({
        minHeight: this.infoViewportHeight > 0 ? this.infoViewportHeight : 0
      })
      .onAreaChange((_: Area, newArea: Area) => {
        const h = newArea.height as number
        if (h > 0 && h !== this.infoContentHeight) {
          this.infoContentHeight = h
          this.updateInfoBottomEdgeForLayout()
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    // EdgeEffect.None: no overscroll bounce, so swipe-up past the last card
    // does NOT reveal a growing blank gap below the participating-artists row.
    .edgeEffect(EdgeEffect.None)
    // True alpha-mask gradient at top/bottom edges — same effect used in the
    // lyrics List (LyricsArea). The Scroll component supports fadingEdge as part
    // of ScrollableCommonMethod, so the fade automatically appears at the edges
    // where content overflows and disappears at the edges where it does not.
    .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })
    .onAreaChange((_: Area, newArea: Area) => {
      const h = newArea.height as number
      if (h > 0 && h !== this.infoViewportHeight) {
        this.infoViewportHeight = h
        this.updateInfoBottomEdgeForLayout()
      }
    })
    .onScrollEdge((side: Edge) => {
      if (side === Edge.Top) {
        this.isInfoPanelAtTop = true
        // Mid-gesture handoff: if the user is still pulling down and the inner
        // Scroll has bottomed out at the top edge (nothing more to scroll up),
        // start a page-drag so the dismiss gesture takes over from this point.
        // Reset touch anchors so dy is measured from the current finger position.
        if (this.isTouchInInfoPanel && this.vm.currentPage === 0 && !this.vm.isDragging) {
          this.vm.isDragging = true
          this.vm.touchStartY = this.vm.lastTouchY
          this.vm.offsetAtDragStart = 0
        }
      } else if (side === Edge.Bottom) {
        this.isInfoPanelAtBottom = true
        // Symmetric handoff at the bottom: a continuous swipe-up that scrolled
        // the inner Scroll to its end should keep dragging the page upward into
        // the play queue, instead of stalling and forcing the user to lift and
        // re-touch.
        if (this.isTouchInInfoPanel && this.vm.currentPage === 0 && !this.vm.isDragging) {
          this.vm.isDragging = true
          this.vm.touchStartY = this.vm.lastTouchY
          this.vm.offsetAtDragStart = 0
        }
      }
    })
    .onDidScroll((_xOffset: number, yOffsetDelta: number) => {
      // Positive delta = scrolling further down (away from top edge);
      // negative delta = scrolling up (away from bottom edge).
      if (yOffsetDelta > 0) {
        this.isInfoPanelAtTop = false
      } else if (yOffsetDelta < 0) {
        this.isInfoPanelAtBottom = false
      }
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.isTouchInInfoPanel = true
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.isTouchInInfoPanel = false
      }
    })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PanelControlButton(icon: Resource, label: string, onClick: () => void, isActive: boolean = false) {
    Row() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(isActive ? '#ff4285f4' : this.vm.themeForeground)
        .objectFit(ImageFit.Contain)

      Text(label)
        .fontSize(13)
        .fontColor(isActive ? '#ff4285f4' : this.vm.themeForeground)
        .margin({ left: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('48%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(isActive ? '#1a4285f4' : '#08000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => { onClick() })
  }

  // Dedicated builder for Keep-Screen-On button: directly references
  // this.playerKeepScreenOn (@StorageProp) so ArkUI re-renders when the
  // shared setting flips — e.g. from Settings → User Interface.
  // (Generic PanelControlButton passes isActive by value, which won't update.)
  @Builder
  KeepScreenOnButton() {
    Row() {
      Image($r('app.media.ic_light'))
        .width(24)
        .height(24)
        .fillColor(this.playerKeepScreenOn ? '#ffffffff' : this.vm.themeForeground)
        .objectFit(ImageFit.Contain)

      Text($r('app.string.player_ui_keep_screen_on'))
        .fontSize(13)
        .fontColor(this.playerKeepScreenOn ? '#ffffffff' : this.vm.themeForeground)
        .margin({ left: 8 })
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .marqueeOptions({ loop: -1, start: true, step: 3, fromStart: true })
        .layoutWeight(1)
    }
    .width('48%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.playerKeepScreenOn ? '#ff4285f4' : '#08000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      ScreenWakeViewModel.getInstance().onSettingChanged(!this.playerKeepScreenOn)
    })
  }

  // Dedicated builder for Immersion Mode button: uses @StorageProp('immersionMode')
  // (same pattern as KeepScreenOnButton) so ArkUI reliably re-renders on state change.
  @Builder
  ImmersionModeButton() {
    Row() {
      Image($r('app.media.ic_immersion'))
        .width(24)
        .height(24)
        .fillColor(this.immersionMode ? '#ffffffff' : this.vm.themeForeground)
        .objectFit(ImageFit.Contain)

      Text('沉浸模式')
        .fontSize(13)
        .fontColor(this.immersionMode ? '#ffffffff' : this.vm.themeForeground)
        .margin({ left: 8 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('48%')
    .height(52)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor(this.immersionMode ? '#ff4285f4' : '#08000000')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.vm.toggleImmersionMode()
    })
  }

  // ==================== Player Time / Seek Bar ====================
  @Builder
  PlayerTimeBar() {
    Column() {
      Slider({
        value: this.vm.getDisplayProgress(),
        min: 0,
        max: this.vm.duration > 0 ? this.vm.duration : 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .padding({ left: 24, right: 24 })
        .height(14)
        .trackThickness(2)
        .blockSize({ width: 0, height: 0 })
        .blockColor(Color.Transparent)
        .selectedColor(this.vm.themeForeground)
        .trackColor(this.vm.getTrackBarColor())
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.Begin) {
            this.vm.handleSeekBegin(value)
          } else if (mode === SliderChangeMode.Moving) {
            this.vm.handleSeekMoving(value)
            this.scrollLyricsToCurrentLine()
          } else if (mode === SliderChangeMode.End) {
            this.vm.handleSeekEnd()
            this.scrollLyricsToCurrentLine()
          }
        })

      Row() {
        Text(this.vm.formatTime(this.vm.getDisplayProgress()))
          .fontSize(12)
          .fontColor(this.vm.themeForeground)
          .opacity(this.vm.isSeeking ? 0.15 : 0.72)

        Blank()

        Text(this.vm.formatTime(this.vm.duration))
          .fontSize(12)
          .fontColor(this.vm.themeForeground)
          .opacity(this.vm.isSeeking ? 0.15 : 0.72)
          .onClick(() => {
            console.info('TODO: show duration dialog')
          })
      }
      .width('100%')
      .padding({ left: 29.5, right: 29.5 })
      .margin({ top: 4 })
    }
    .width('100%')
    // Hide via opacity only — keep the bar's height stable so toggling
    // immersion mode does not reflow surrounding components.
    .opacity(this.vm.immersionMode ? 0 : 1)
    .animation({ duration: 300 })
  }

  // ==================== Play Control Bar ====================
  @Builder
  PlayerControlBar() {
    Row() {
      Image($r('app.media.ic_round_skip_previous_24'))
        .width(56)
        .height(56)
        .padding(8)
        .fillColor(this.vm.themeForeground)
        .objectFit(ImageFit.Contain)
        .clickEffect(null)
        .hoverEffect(HoverEffect.None)
        .onClick(() => {
          const now = Date.now()
          if (now - this.lastSkipTime < 700) return
          this.lastSkipTime = now
          this.animateSongSwitch(false)
          this.vm.skipPrevious()
        })
        .priorityGesture(
          LongPressGesture()
            .onAction(() => {
              const now = Date.now()
              if (now - this.lastSkipTime < 700) return
              this.lastSkipTime = now
              this.animateSongSwitch(false)
              this.vm.skipPrevious()
            })
        )
        .accessibilityText($r('app.string.previous'))

      // Play/Pause button: both icons always rendered to avoid
      // component recreation flash when switching source
      Stack() {
        Image($r('app.media.ic_mini_player_play'))
          .width(64)
          .height(64)
          .padding(17)
          .fillColor(this.vm.themeForeground)
          .objectFit(ImageFit.Contain)
          .visibility(this.isPlaying ? Visibility.Hidden : Visibility.Visible)

        Image($r('app.media.ic_mini_player_pause'))
          .width(64)
          .height(64)
          .padding(17)
          .fillColor(this.vm.themeForeground)
          .objectFit(ImageFit.Contain)
          .visibility(this.isPlaying ? Visibility.Visible : Visibility.Hidden)
      }
      .width(64)
      .height(64)
      .margin({ left: 16, right: 16 })
      .clickEffect(null)
      .hoverEffect(HoverEffect.None)
      .onClick(() => {
        this.vm.togglePlayPause()
      })
      .priorityGesture(
        LongPressGesture()
          .onAction(() => {
            this.vm.toggleImmersionModeWithToast()
          })
      )
      .accessibilityText(this.isPlaying ? $r('app.string.pause_music') : $r('app.string.play_music'))

      Image($r('app.media.ic_round_skip_next_24'))
        .width(56)
        .height(56)
        .padding(8)
        .fillColor(this.vm.themeForeground)
        .objectFit(ImageFit.Contain)
        .clickEffect(null)
        .hoverEffect(HoverEffect.None)
        .onClick(() => {
          const now = Date.now()
          if (now - this.lastSkipTime < 700) return
          this.lastSkipTime = now
          this.animateSongSwitch(true)
          this.vm.skipNext()
        })
        .priorityGesture(
          LongPressGesture()
            .onAction(() => {
              const now = Date.now()
              if (now - this.lastSkipTime < 700) return
              this.lastSkipTime = now
              this.animateSongSwitch(true)
              this.vm.skipNext()
            })
        )
        .accessibilityText($r('app.string.next'))
    }
    .width('100%')
    .height(64)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  // ==================== Bottom Icon Panel ====================
  @Builder
  PlayerIconPanel() {
    Row() {
      // Play mode button
      Column() {
        Image(this.vm.getPlayModeIcon())
          .width(24)
          .height(24)
          .fillColor(this.vm.themeForeground)
          .objectFit(ImageFit.Contain)
      }
      .layoutWeight(1)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.vm.cyclePlayMode()
      })
      .accessibilityText(this.vm.getPlayModeDescription())

      this.SleepTimerIconItem(() => {
        this.vm.openBottomSheet(BottomSheetType.SLEEP_TIMER)
      })
      this.AudioEffectIconItem(() => {
        this.vm.openBottomSheet(BottomSheetType.AUDIO_EFFECT)
      })
      this.BottomIconItem($r('app.media.ic_play_queue'), '播放队列', 24, () => {
        this.scrollToQueue()
      })
      this.BottomIconItem($r('app.media.ic_player_more'), '更多', 21.5, () => {
        this.onShowSongMenu()
      })
    }
    .width('100%')
    // Hide via opacity only — keep the panel's height stable so toggling
    // immersion mode does not reflow surrounding components.
    .height(72)
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .opacity(this.vm.immersionMode ? 0 : 1)
    .animation({ duration: 300 })
  }

  @Builder
  BottomIconItem(icon: Resource, description: string, iconSize: number, onClick: () => void) {
    Column() {
      Image(icon)
        .width(iconSize)
        .height(iconSize)
        .fillColor(this.vm.themeForeground)
        .objectFit(ImageFit.Contain)
    }
    .layoutWeight(1)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { onClick() })
    .accessibilityText(description)
  }

  @Builder
  SleepTimerIconItem(onClick: () => void) {
    Column() {
      Image($r('app.media.ic_sleep_timer'))
        .width(24)
        .height(24)
        .fillColor(this.vm.themeForeground)
        .objectFit(ImageFit.Contain)

      if (this.sleepTimerState !== 0) {
        Text(this.formatSleepTimerSubText())
          .fontSize(9)
          .fontColor(this.vm.themeForeground)
          .margin({ top: 2 })
      }
    }
    .layoutWeight(1)
    .height(56)
    .padding({ top: 16 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { onClick() })
    .accessibilityText('睡眠定时')
  }

  private formatSleepTimerSubText(): string {
    const totalSeconds = Math.ceil(this.sleepTimerRemainingMs / 1000)
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n
    let timeStr: string
    if (hours > 0) {
      timeStr = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
    } else {
      timeStr = `${pad(minutes)}:${pad(seconds)}`
    }
    return this.sleepTimerIsExtendPhase ? `+${timeStr}` : timeStr
  }

  @Builder
  AudioEffectIconItem(onClick: () => void) {
    Column() {
      Image($r('app.media.ic_audio_effect'))
        .width(22)
        .height(22)
        .fillColor(this.vm.themeForeground)
        .objectFit(ImageFit.Contain)

      if (Math.round(this.playbackSpeed * 100) !== 100) {
        Text(`x${this.playbackSpeed.toFixed(2)}`)
          .fontSize(9)
          .fontColor(this.vm.themeForeground)
          .margin({ top: 2 })
      }
    }
    .layoutWeight(1)
    .height(56)
    .padding({ top: 17 })
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { onClick() })
    .accessibilityText('音频效果')
  }

  @Builder
  bottomSheetBuilder() {
    if (this.vm.bottomSheetType === BottomSheetType.AUDIO_EFFECT) {
      SoundEffectDialogComponent({
        onDismiss: () => {
          this.vm.closeBottomSheet()
        }
      })
    } else if (this.vm.bottomSheetType === BottomSheetType.SLEEP_TIMER) {
      SleepTimerDialogComponent({
        onStart: (minutes: number, autoExtend: boolean) => {
          console.info(`Sleep timer started: ${minutes} minutes, autoExtend: ${autoExtend}`)
        },
        onDismiss: () => {
          this.vm.closeBottomSheet()
        }
      })
    } else if (this.vm.bottomSheetType === BottomSheetType.LYRICS_INTERFACE) {
      LyricsInterfaceDialogComponent({
        viewModel: this.vm.lyricsInterfaceViewModel,
        sourceTag: this.vm.lyricsSourceTag,
        onDismiss: () => {
          this.vm.closeBottomSheet()
        }
      })
    } else if (this.vm.bottomSheetType === BottomSheetType.AUDIO_OUTPUT_INFO) {
      AudioOutputInfoDialogComponent({
        viewModel: this.vm.audioInfoDialogVM,
        onDismiss: () => {
          this.vm.closeBottomSheet()
        }
      })
    }
  }
}

// 歌词翻译：切换翻译显示开关时，通过 @StorageProp 即时刷新歌词区域的译文行。

// 迷你歌词：播放页可切换迷你歌词模式，封面与歌词并排展示。
