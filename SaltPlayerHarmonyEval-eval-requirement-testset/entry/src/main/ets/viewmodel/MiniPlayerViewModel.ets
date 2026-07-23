// MiniPlayerViewModel.ets
// ViewModel layer: provides observable data and action logic for MiniPlayerComponent
// Bridges the View and Model layers per MVVM architecture
//
// Cover art: subscribes to CurrentSongCoverController (single source of truth).
// Does NOT load covers independently — mirrors Android's MiniPlayer.kt which
// observes MusicController.coverBitmap.collectAsState().

import MiniPlayerModel from '../model/MiniPlayerModel'
import { image } from '@kit.ImageKit'
import { CurrentSongCoverController } from '../model/CurrentSongCoverController'
import { MiniLyricsController } from '../model/MiniLyricsController'

@Observed
export default class MiniPlayerViewModel {
  @Track public currentSongTitle: string = ''
  @Track public currentSongArtist: string = ''
  @Track public isPlaying: boolean = false
  @Track public currentSongId: string = ''
  @Track public currentSongCoverUri: string = ''
  @Track public coverPixelMap: image.PixelMap | undefined = undefined
  @Track public swipeOffsetX: number = 0
  @Track public middleAreaWidth: number = 0
  // Current real-time lyric line — populated by MiniLyricsController.
  // When hasLyrics is true AND currentLyricLine is non-empty, the subtitle
  // row displays this instead of the artist (spec8 INV-A).
  @Track public currentLyricLine: string = ''
  @Track public hasLyrics: boolean = false

  // Callbacks to notify parent when user interactions occur
  @Track public onPlayPauseClick: () => void = () => {}
  @Track public onQueueClick: () => void = () => {}
  @Track public onMiniPlayerClick: () => void = () => {}
  @Track public onTouchEvent: (event: TouchEvent) => void = () => {}

  // Listener reference kept so we could removeListener later if needed
  private coverListener: (songId: string, pm: image.PixelMap | undefined) => void
  // Lyrics listener — same proxy-this caveat as coverListener.
  private lyricsListener: (songId: string, line: string, hasLyrics: boolean) => void =
    (_songId: string, _line: string, _hasLyrics: boolean): void => {}

  constructor(model?: MiniPlayerModel) {
    if (model) {
      this.updateFromModel(model)
    }
    // NOTE: Do NOT subscribe to CurrentSongCoverController here!
    // In ArkUI, @Observed uses a Proxy for change detection. The constructor's
    // `this` is the raw object — arrow functions here bypass the proxy, so
    // setting @Track fields won't trigger UI updates. Call subscribeToController()
    // from a method invoked on the proxy instead (e.g., from initMiniPlayer).
    this.coverListener = (_songId: string, _pm: image.PixelMap | undefined): void => {}
  }

  // Must be called AFTER the proxy is set up (i.e., from a method called on the
  // proxy object, not in the constructor). This ensures the arrow function captures
  // the proxy `this`, making @Track assignments trigger ArkUI re-renders.
  subscribeToController(): void {
    this.coverListener = (_songId: string, pm: image.PixelMap | undefined): void => {
      this.coverPixelMap = pm
    }
    CurrentSongCoverController.getInstance().addListener(this.coverListener)
  }

  // Same proxy-this discipline as subscribeToController(): must be called
  // from a method on the @Observed proxy, not the constructor, so the arrow
  // function captures the proxy `this` and @Track assignments trigger rerenders.
  subscribeToLyricsController(): void {
    this.lyricsListener = (_songId: string, line: string, hasLyrics: boolean): void => {
      this.currentLyricLine = line
      this.hasLyrics = hasLyrics
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: MiniPlayerModel): void {
    this.currentSongTitle = model.songTitle
    this.currentSongArtist = model.songArtist
    this.isPlaying = model.isPlaying
  }

  // Export current state back to Model
  toModel(): MiniPlayerModel {
    return new MiniPlayerModel(this.currentSongTitle, this.currentSongArtist, this.isPlaying)
  }

  // Toggle play/pause state and notify parent
  togglePlayPause(): void {
    this.onPlayPauseClick()
  }

  // Handle queue button click
  handleQueueClick(): void {
    this.onQueueClick()
  }

  // Handle mini player bar click
  handleMiniPlayerClick(): void {
    this.onMiniPlayerClick()
  }

  // Handle touch event on mini player bar
  handleTouchEvent(event: TouchEvent): void {
    this.onTouchEvent(event)
  }

  // Get the play/pause button icon resource based on current state
  getPlayPauseIcon(): Resource {
    return this.isPlaying ? $r('app.media.ic_mini_player_pause') : $r('app.media.ic_mini_player_play')
  }

  // Get the accessibility text for the play/pause button
  getPlayPauseAccessibilityText(): string {
    return this.isPlaying ? '\u6682\u505c\u97f3\u4e50' : '\u64ad\u653e\u97f3\u4e50'
  }

  // Get the display title, falling back to app name resource if empty
  getDisplayTitle(): ResourceStr {
    return this.currentSongTitle || $r('app.string.app_name')
  }

  // Resolve the subtitle row per spec8 invariants:
  //   INV-A: timed lyrics available at current position → current lyric line
  //   INV-B: no lyrics (or lyric empty at current position) → artist
  //   INV-C: no lyrics AND artist is empty → empty string (Text renders empty)
  // Called by MiniPlayerComponent; both @Track deps (currentLyricLine,
  // currentSongArtist, hasLyrics) trigger a rebuild when they change.
  getSubtitle(): string {
    if (this.hasLyrics && this.currentLyricLine.length > 0) {
      return this.currentLyricLine
    }
    return this.currentSongArtist
  }

  // Update cover art when current song changes.
  // Delegates to the central controller — the actual PixelMap is delivered
  // via the listener registered in the constructor.
  updateCover(songId: string, _coverUri: string): void {
    this.currentSongId = songId
    // songId IS the fileUri in SPH — no AppStorage dependency.
    CurrentSongCoverController.getInstance().loadForSong(songId)
  }
}
