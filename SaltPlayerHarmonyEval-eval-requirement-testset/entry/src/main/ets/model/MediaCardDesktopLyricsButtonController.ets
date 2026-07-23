// MediaCardDesktopLyricsButtonController.ets
// spec24 — mirrors the "显示桌面歌词按钮" toggle into AVSession extras +
// dispatchSessionEvent, and additionally owns the per-song "card lyrics row
// active" flag and the running-lyric publish. Pattern-identical to
// MediaCardCloseButtonController plus a MiniLyricsController subscription.
//
//   - singleton in the model package
//   - init() called from EntryAbility.onCreate() after
//     MediaCardCloseButtonController.getInstance().init()
//   - onToggleChanged() poked by NotificationViewModel after persistence
//   - requestToggleLyricsActive() poked by AudioPlayerService when the system
//     card dispatches the 'toggleCardLyrics' common command (future-proof
//     hook; the card cannot dispatch this today, see plan section 2)
//   - requestCloseFloatingWindow() poked by NotificationViewModel after the
//     user confirms the "also close desktop lyrics" dialog (scenario 6)
//   - publish() calls into AudioPlayerService.publishDesktopLyricsButtonExtras
//   - publishCardLyricsState() calls into AudioPlayerService.publishCardLyricsState

import AudioPlayerService from './AudioPlayerService'
import { QueueSongModel } from './PlayQueueModel'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'
import SettingsStore from './SettingsStore'

// Listener invoked when the controller wants the desktop-lyrics floating
// window torn down (scenario 6 step 6.1). The Spec18 floating-window service
// is expected to register itself here when it lands; until then the controller
// still ensures the `desktopLyrics=false` flag is consistently propagated
// across AppStorage + SettingsStore.
export type DesktopLyricsCloseListener = () => void

export class MediaCardDesktopLyricsButtonController {
  private static instance: MediaCardDesktopLyricsButtonController | null = null

  private initialized: boolean = false
  private lastPublishedToggle: boolean | null = null
  private lastPublishedActive: boolean | null = null
  private lastPublishedLine: string = ''

  // In-memory only (per spec; resets on cold start and on song change)
  private isLyricsActive: boolean = false
  private currentSongId: string = ''
  private currentLine: string = ''
  private hasLyrics: boolean = false

  private lyricsListener: MiniLyricsListener =
    (_id: string, _l: string, _h: boolean): void => {}
  private songChangedListener: (s: QueueSongModel) => void = (): void => {}
  // Subscribers waiting to tear down the desktop-lyrics floating window. The
  // controller does not own the window itself; the future Spec18 service
  // registers a listener here so its lifecycle stays inside one module.
  private closeListeners: DesktopLyricsCloseListener[] = []

  static getInstance(): MediaCardDesktopLyricsButtonController {
    if (!MediaCardDesktopLyricsButtonController.instance) {
      MediaCardDesktopLyricsButtonController.instance =
        new MediaCardDesktopLyricsButtonController()
    }
    return MediaCardDesktopLyricsButtonController.instance
  }

  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true

    // Push the current toggle so it lands in AVSession before the first song
    // plays (matches the spec23 pattern).
    this.publishToggle()
    // Initial card-lyrics state: artist row shown, line empty.
    this.publishLyricsState()

    // Subscribe to song-change so we reset the per-song lyric-active flag and
    // re-publish so a freshly-activated AVSession sees the latest values.
    this.songChangedListener = (s: QueueSongModel): void => {
      this.currentSongId = s.id
      this.isLyricsActive = false       // scenario 4: per-song
      this.currentLine = ''
      this.lastPublishedToggle = null   // force republish on song change
      this.lastPublishedActive = null
      this.lastPublishedLine = ''
      this.publishToggle()
      this.publishLyricsState()
    }
    AudioPlayerService.getInstance()
      .addOnSongChangedListener(this.songChangedListener)

    // Subscribe to MiniLyricsController so we can publish the running line
    // while isLyricsActive is true. The listener fires immediately with the
    // current state on add (per the MiniLyricsController contract).
    this.lyricsListener = (songId: string, line: string, has: boolean): void => {
      this.currentSongId = songId
      this.currentLine = line
      this.hasLyrics = has
      // Only re-emit when active; the toggle-driven publish below still runs
      // when the user clicks the card's lyric button so the system can swap
      // the row.
      if (this.isLyricsActive) {
        this.publishLyricsState()
      }
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)
  }

  // Called by NotificationViewModel.onDesktopLyricsButtonChanged after the
  // model has persisted the new value. Re-reads AppStorage so the published
  // value matches the source of truth (no risk of stale parameter).
  onToggleChanged(): void {
    this.publishToggle()
    // If the user just disabled the toggle, also force the card-lyrics row
    // back to artist (scenario 6: "如果关闭开关前艺术家信息展示区域正在显示
    // 歌词，则恢复显示艺术家信息").
    const enabled: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (!enabled && this.isLyricsActive) {
      this.isLyricsActive = false
      this.publishLyricsState()
    }
  }

  // Called by AudioPlayerService when the system card dispatches a
  // 'toggleCardLyrics' commonCommand. Gated by:
  //   - the user's toggle being ON
  //   - the current song actually having timestamped lyrics (spec scenario 5:
  //     "由于当前歌曲无歌词，艺术家信息展示区域保持显示艺术家信息，不发生变化")
  requestToggleLyricsActive(): void {
    const toggleOn: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (!toggleOn) {
      return
    }
    if (!this.isLyricsActive && !this.hasLyrics) {
      // Spec scenario 5: silently no-op when current song has no lyrics.
      return
    }
    this.isLyricsActive = !this.isLyricsActive
    this.publishLyricsState()
  }

  // Called by NotificationViewModel.confirmCloseDesktopLyrics(). Wraps any
  // floating-window teardown (e.g. window manager hide) in one place so the
  // ViewModel does not own a system-surface lifecycle. The actual floating
  // window machinery for spec18 desktop lyrics is out of scope for spec24;
  // when that service lands it registers a DesktopLyricsCloseListener here
  // via addCloseListener() so the existing wiring keeps working.
  requestCloseFloatingWindow(): void {
    // 1) Make the "desktop lyrics off" intent durable across AppStorage +
    //    SettingsStore. The ViewModel already writes this, but writing it
    //    again here makes the controller a self-contained close API so any
    //    other entry point (e.g. a future remote command) gets the same
    //    persistence behaviour for free.
    SettingsStore.getInstance().save('desktopLyrics', false)

    // 2) Notify any registered floating-window service so it can hide the
    //    actual window. When no service is registered (the situation today
    //    because Spec18 has not landed) this is a no-op besides the
    //    persistence above, matching the documented contract.
    const snapshot = this.closeListeners.slice()
    for (const l of snapshot) {
      try {
        l()
      } catch (e) {
        console.warn('MediaCardDesktopLyricsButtonController.'
          + 'requestCloseFloatingWindow: listener threw - '
          + (e as Error).message)
      }
    }

    // 3) Re-publish so any AVSession subscriber sees the consistent state.
    this.publishLyricsState()
  }

  // Registration hook used by the Spec18 desktop-lyrics window service when it
  // lands. The controller does not own the window; it only owns the close API.
  addCloseListener(l: DesktopLyricsCloseListener): void {
    if (this.closeListeners.indexOf(l) === -1) {
      this.closeListeners.push(l)
    }
  }

  removeCloseListener(l: DesktopLyricsCloseListener): void {
    const idx = this.closeListeners.indexOf(l)
    if (idx !== -1) {
      this.closeListeners.splice(idx, 1)
    }
  }

  destroy(): void {
    if (!this.initialized) {
      return
    }
    AudioPlayerService.getInstance()
      .removeOnSongChangedListener(this.songChangedListener)
    MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    this.initialized = false
  }

  private publishToggle(): void {
    const value: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (value === this.lastPublishedToggle) {
      return
    }
    this.lastPublishedToggle = value
    AudioPlayerService.getInstance().publishDesktopLyricsButtonExtras(value)
  }

  private publishLyricsState(): void {
    // When active and lyrics exist, publish the running line; otherwise empty.
    const active = this.isLyricsActive && this.hasLyrics
    const line = active ? this.currentLine : ''
    if (active === this.lastPublishedActive && line === this.lastPublishedLine) {
      return
    }
    this.lastPublishedActive = active
    this.lastPublishedLine = line
    AudioPlayerService.getInstance().publishCardLyricsState(active, line)
  }
}

export default MediaCardDesktopLyricsButtonController

// 媒体卡桌面歌词按钮：通知中切换桌面歌词。
