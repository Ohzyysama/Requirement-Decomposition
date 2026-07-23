// AudioPlayerService.ets
// Model layer: singleton service wrapping AVPlayer for audio playback.
// Manages AVPlayer lifecycle, state transitions, and progress tracking.
// Updates AppStorage 'isPlaying' so UI layers react via @StorageLink.

import { media } from '@kit.MediaKit'
import { audio } from '@kit.AudioKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { fileIo, fileShare } from '@kit.CoreFileKit'
import { backgroundTaskManager } from '@kit.BackgroundTasksKit'
import { wantAgent, WantAgent } from '@kit.AbilityKit'
import { common } from '@kit.AbilityKit'
import { avSession } from '@kit.AVSessionKit'
import { preferences } from '@kit.ArkData'
import { image } from '@kit.ImageKit'
import { QueueSongModel, PlayModeConstants } from './PlayQueueModel'
import { CurrentSongCoverController, CurrentCoverListener } from './CurrentSongCoverController'
import { MusicDatabase } from './MusicDatabase'
import MediaCardDesktopLyricsButtonController from './MediaCardDesktopLyricsButtonController'

const PLAYBACK_PREFS = 'playback_state'

export default class AudioPlayerService {
  private static instance: AudioPlayerService | null = null
  private avPlayer: media.AVPlayer | null = null
  private currentFd: number = -1
  private currentSongId: string = ''
  private _currentTimeMs: number = 0
  private _durationMs: number = 0
  private _isPlaying: boolean = false
  // Tracks the user's intent to play, independent of AVPlayer state.
  // The system may pause AVPlayer in muted background, but the user's intent
  // is still "playing".  Set true by user-initiated play/resume; set false
  // only by user-initiated pause/stop/completed/error.
  private _playbackIntentActive: boolean = false
  // Seek position to apply on next resume() when seek is called while not playing
  private _pendingResumeSeek: number = -1
  private _currentSpeed: number = AppStorage.get<number>('playbackSpeed') ?? 1.0
  private initialized: boolean = false
  private sourceLoaded: boolean = false

  // Dual queue management (mirrors Android PlaybackQueue architecture)
  // normalQueue: original song order; randomQueue: shuffled order
  private normalQueue: QueueSongModel[] = []
  private normalIndex: number = -1
  private randomQueue: QueueSongModel[] = []
  private randomIndex: number = -1
  private playMode: string = PlayModeConstants.CIRCLE
  onSongChanged: ((song: QueueSongModel) => void) | null = null
  onQueueInserted: ((song: QueueSongModel, insertIndex: number) => void) | null = null

  // Multi-listener bus for song-change events. The legacy `onSongChanged`
  // single slot is preserved (used by PlayerPageViewModel), and this list
  // allows additional subscribers (e.g. MiniLyricsController) to coexist
  // without the last-registration-wins conflict.
  private onSongChangedListeners: ((song: QueueSongModel) => void)[] = []

  addOnSongChangedListener(cb: (song: QueueSongModel) => void): void {
    if (this.onSongChangedListeners.indexOf(cb) < 0) {
      this.onSongChangedListeners.push(cb)
    }
  }

  removeOnSongChangedListener(cb: (song: QueueSongModel) => void): void {
    const idx = this.onSongChangedListeners.indexOf(cb)
    if (idx >= 0) {
      this.onSongChangedListeners.splice(idx, 1)
    }
  }

  // Fire both the legacy single-slot callback and every listener registered
  // on the multi-listener bus. All internal song-change notify sites call
  // this helper instead of invoking `this.onSongChanged` directly.
  private notifySongChanged(song: QueueSongModel): void {
    // Push song metadata to AppStorage so MiniPlayer and MainPage refresh
    // even when PlayerPageViewModel hasn't been initialized yet.
    AppStorage.setOrCreate('currentSongTitle', song.title)
    AppStorage.setOrCreate('currentSongArtist', song.artist)
    AppStorage.setOrCreate('currentSongId', song.id)
    AppStorage.setOrCreate('currentSongCoverUri', song.coverUri)
    // Persist immediately so the song survives process kill / IDE reinstall
    this.persistCurrentSong(song)
    if (this.onSongChanged) {
      this.onSongChanged(song)
    }
    for (const cb of this.onSongChangedListeners) {
      cb(song)
    }
  }

  // Persist current song metadata to Preferences immediately on song change.
  // This ensures playback state survives even if the app is killed before
  // onBackground() fires (e.g. IDE Build & Run).
  private persistCurrentSong(song: QueueSongModel): void {
    if (!this.uiContext) {
      return
    }
    try {
      const store = preferences.getPreferencesSync(this.uiContext, { name: PLAYBACK_PREFS })
      store.putSync('songId', song.id)
      store.putSync('fileUri', song.fileUri)
      store.putSync('title', song.title)
      store.putSync('artist', song.artist)
      store.putSync('coverUri', song.coverUri ?? '')
      store.flushSync()
    } catch (e) {
      console.error('AudioPlayerService: persistCurrentSong failed - ' + (e as Error).message)
    }
  }

  // Sleep timer hook: when set, song completion calls this instead of auto-skipping
  onSongCompletedDuringSleepTimer: (() => void) | null = null

  // Throttle AVSession position sync during playback (ms since last update)
  private lastSessionSyncTime: number = 0

  // Wall-clock anchor for progress interpolation (same approach AVSession uses
  // for the Live Activity).  Updated whenever we get a reliable position from
  // AVPlayer (timeUpdate callback, seek, play/resume).  When AVPlayer stops
  // firing timeUpdate (e.g. muted background playback), getCurrentTimeMs()
  // interpolates: anchorPosition + (now - anchorWallTime) * speed.
  private _anchorPositionMs: number = 0
  private _anchorWallTimeMs: number = 0

  // Restored playback state (persisted across app restarts)
  private pendingFileUri: string = ''
  private pendingSongId: string = ''
  private pendingSeekMs: number = -1

  // Background task management
  private uiContext: common.UIAbilityContext | null = null
  private cachedWantAgent: WantAgent | null = null
  private bgTaskRunning: boolean = false

  // AVSession for background playback and system media controls
  private session: avSession.AVSession | null = null

  // Listeners notified once when the AVSession transitions from null to
  // a live instance after the async createAVSession resolves. Consumed by
  // controllers (e.g. DesktopLyricsAVSessionController) that need to run
  // session-instance APIs at app-start but were initialized before the
  // session creation Promise resolved. Listeners are dropped after firing.
  private sessionReadyListeners: (() => void)[] = []

  // Public accessor for the live session — consumed by controllers that
  // call session-instance APIs directly (e.g. DesktopLyricsAVSessionController
  // for enableDesktopLyric / setDesktopLyricVisible / setDesktopLyricState).
  // Returns null until initContext() has created the session, or after
  // deactivateSession() has torn it down.
  getSession(): avSession.AVSession | null {
    return this.session
  }

  // Run `cb` when the AVSession is live. Fires synchronously if the
  // session already exists; otherwise queues for invocation after the
  // createAVSession Promise resolves in initContext(). One-shot — the
  // listener is dropped after firing.
  addSessionReadyListener(cb: () => void): void {
    if (this.session) {
      try { cb() } catch (_e) { /* swallow */ }
      return
    }
    this.sessionReadyListeners.push(cb)
  }
  // When true, suppress all setAVPlaybackState calls so async stop/reset
  // callbacks don't briefly re-show the live activity after deactivation.
  private sessionDeactivated: boolean = false
  // Promise from session.deactivate() — awaited in stop()/clear() to ensure
  // the session is fully deactivated before avPlayer.reset() fires.
  private deactivatePromise: Promise<void> | null = null

  // AudioSession for cross-app audio focus management
  private audioSessionManager: audio.AudioSessionManager | null = null
  private audioSessionActive: boolean = false

  // Cover art listener for AVSession metadata updates
  private coverListener: CurrentCoverListener | null = null
  // Default cover PixelMap for AVSession when song has no artwork
  private defaultCoverPixelMap: image.PixelMap | null = null

  // spec12 — Notification bar lyrics override.
  // When non-null and non-empty, replaces the AVSession metadata title field
  // (which the system renders as the notification card title). Set by
  // NotificationLyricController; cleared back to null only when that
  // controller publishes an empty string. All metadata writers fall back to
  // `currentSongTitle` when this override is null/empty.
  private _displayTitleOverride: string | null = null

  // Raw LRC string for AVMetadata.lyric — drives the system AVSession
  // desktop-lyrics overlay rendering. Empty string omits the field (system
  // stops rendering desktop lyrics for this session). Written by
  // DesktopLyricsAVSessionController on song change after the LRC for the
  // new song has been parsed.
  private _desktopLyricsLrc: string = ''

  // Debounced queue save timer
  private queueSaveTimerId: number = -1

  // spec21 — per-song play-count accumulator. Scoped to the current play
  // "session" on one song; resets when the song changes. The commit gate
  // (60s played, or 90% of duration for songs shorter than 60s) fires at
  // most once per session.
  private playCountSongId: string = ''
  private playCountAccumMs: number = 0
  private playCountCommitted: boolean = false
  private playCountLastTickWall: number = 0

  // spec14 — volume balance multiplier. Applied to fade envelope so that
  // ReplayGain-tagged songs play at consistent perceived volume.
  private _volumeBalanceMultiplier: number = 1.0

  // Serialization lock for play() — prevents rapid sequential calls from
  // corrupting the AVPlayer state machine (e.g. setting fdSrc while a
  // previous reset() is still in-flight).
  private playLock: Promise<void> = Promise.resolve()
  // Resolved when AVPlayer reaches 'playing' or 'error' state after fdSrc is set.
  // Used by doPlay() to wait for the full state machine pipeline to finish.
  private playReadyResolve: (() => void) | null = null
  // Suppresses error UI flash during deliberate song switches (reset triggers
  // a transient AVPlayer error that should not be shown to the user).
  private _switchingTrack: boolean = false
  private _errorDebounceTimer: number = -1

  // ==================== spec11 — Play/Pause Fade In/Out ====================
  // Serializes user pause/resume envelope calls so that a resume arriving
  // mid-fade-out waits for the fade-out to finish before starting fade-in.
  private _fadeLock: Promise<void> = Promise.resolve()
  // Set true in doPlay() when a new song is being loaded and fade is enabled;
  // consumed in stateChange:'prepared' to fade the new song in from 0.
  private _fadeInPendingForNextPrepared: boolean = false
  // Last applied volume (0..1). Ramps start from this value so we never
  // leave a partial/stuck-mute state even if the user toggles the flag mid-ramp.
  private _currentVolume: number = 1.0
  // Set true on error/released/audio-force-interrupt so any active ramp exits
  // its loop early instead of continuing to poke a dead AVPlayer.
  private _fadeAborted: boolean = false
  private static readonly FADE_DURATION_MS: number = 500
  private static readonly FADE_STEPS: number = 20
  // Note: sleep-timer exit path does not await pause()'s ramp — app terminates.

  private constructor() {
  }

  static getInstance(): AudioPlayerService {
    if (!AudioPlayerService.instance) {
      AudioPlayerService.instance = new AudioPlayerService()
    }
    return AudioPlayerService.instance
  }

  getContext(): common.UIAbilityContext | null {
    return this.uiContext
  }

  initContext(context: common.UIAbilityContext): void {
    this.uiContext = context
    // Load default cover from resources for AVSession when song has no artwork
    try {
      const mgr = context.resourceManager
      const data = mgr.getMediaContentSync($r('app.media.ic_song_cover_v5').id)
      const imgSource = image.createImageSource(data.buffer)
      this.defaultCoverPixelMap = imgSource.createPixelMapSync()
      imgSource.release()
    } catch (e) {
      console.error('AudioPlayerService: failed to load default cover - ' + (e as Error).message)
    }
    // Pre-create the WantAgent so it's ready when playback starts
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: context.abilityInfo.bundleName,
          abilityName: context.abilityInfo.name
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    }
    wantAgent.getWantAgent(wantAgentInfo).then((agent: WantAgent) => {
      this.cachedWantAgent = agent
      console.info('AudioPlayerService: WantAgent cached')
    }).catch((err: Error) => {
      console.error('AudioPlayerService: WantAgent creation failed - ' + err.message)
    })

    // Create AVSession for background playback and system media controls
    avSession.createAVSession(context, 'SaltPlayer', 'audio').then(async (session: avSession.AVSession) => {
      this.session = session
      await session.activate()
      // Flush any one-shot session-ready listeners queued by controllers
      // that booted before this Promise resolved (e.g. the desktop-lyrics
      // controller's cold-start auto-enable path). Snapshot + clear so a
      // listener cannot accidentally re-queue itself into the live list.
      const pending = this.sessionReadyListeners.slice()
      this.sessionReadyListeners.length = 0
      for (const cb of pending) {
        try { cb() } catch (_e) { /* swallow */ }
      }
      // Register system media control commands
      session.on('play', () => {
        if (!this.avPlayer || !this.sourceLoaded) {
          this.togglePlayPause()
        } else {
          this.resume()
        }
      })
      session.on('pause', () => {
        this.pause()
      })
      session.on('playNext', () => {
        this.skipNext()
      })
      session.on('playPrevious', () => {
        this.skipPrevious()
      })
      session.on('seek', (time: number) => {
        this.seek(time)
      })
      // spec23 — HarmonyOS API 12+: receive custom commands dispatched by the
      // system media card (or any controller). When the card eventually
      // renders a 关闭 button this hook fires. Wrapped in try/catch because
      // not every API level exposes the 'commonCommand' slot.
      try {
        session.on('commonCommand', (command: string, _args: Record<string, Object>): void => {
          if (command === 'closeApp') {
            this.requestCloseFromCard()
          } else if (command === 'toggleCardLyrics') {
            // spec24 — Card-driven lyric/artist swap request. Routed to the
            // controller which owns the in-process state and the publish.
            MediaCardDesktopLyricsButtonController.getInstance()
              .requestToggleLyricsActive()
          }
        })
      } catch (e) {
        console.warn('AudioPlayerService: session.on(commonCommand) unavailable: '
          + (e as Error).message)
      }
      console.info('AudioPlayerService: AVSession created and activated')
      // Push initial state after a short delay so the system media service has
      // time to register the new session; without this the play/pause button
      // may stay grey on cold start.
      setTimeout(() => {
        if (!this.session) {
          return
        }
        const initialState = this.currentSongId.length > 0
          ? avSession.PlaybackState.PLAYBACK_STATE_PAUSE
          : avSession.PlaybackState.PLAYBACK_STATE_STOP
        this.updateSessionPlaybackState(initialState)
        if (this.currentSongId.length > 0) {
          this.updateSessionMetadata()
        }
      }, 300)
      // Listen for cover art changes and push updated mediaImage to AVSession.
      // Covers load asynchronously via CurrentSongCoverController, often after
      // updateSessionMetadata() has already been called during 'prepared'.
      this.coverListener = (_songId: string, pm: image.PixelMap | undefined) => {
        this.updateSessionCoverImage(pm)
      }
      CurrentSongCoverController.getInstance().addListener(this.coverListener)
    }).catch((err: Error) => {
      console.error('AudioPlayerService: AVSession creation failed - ' + err.message)
    })
  }

  private startBackgroundTask(): void {
    if (this.bgTaskRunning || !this.uiContext || !this.cachedWantAgent) {
      return
    }
    try {
      backgroundTaskManager.startBackgroundRunning(
        this.uiContext,
        backgroundTaskManager.BackgroundMode.AUDIO_PLAYBACK,
        this.cachedWantAgent
      ).then(() => {
        this.bgTaskRunning = true
        console.info('AudioPlayerService: background task started')
      }).catch((err: Error) => {
        console.error('AudioPlayerService: startBackgroundRunning failed - ' + err.message)
      })
    } catch (e) {
      console.error('AudioPlayerService: background task error - ' + (e as Error).message)
    }
  }

  private stopBackgroundTask(): void {
    if (!this.bgTaskRunning || !this.uiContext) {
      return
    }
    try {
      backgroundTaskManager.stopBackgroundRunning(this.uiContext).then(() => {
        this.bgTaskRunning = false
        console.info('AudioPlayerService: background task stopped')
      }).catch((err: Error) => {
        console.error('AudioPlayerService: stopBackgroundRunning failed - ' + err.message)
      })
    } catch (e) {
      console.error('AudioPlayerService: stop bg task error - ' + (e as Error).message)
    }
  }

  private async ensurePlayer(): Promise<media.AVPlayer> {
    if (!this.avPlayer) {
      this.avPlayer = await media.createAVPlayer()
      this.setupListeners(this.avPlayer)
      this.initialized = true
    }
    return this.avPlayer
  }

  // Apply audio focus mode based on user setting.
  // When audio focus is enabled (default): use INDEPENDENT_MODE, system manages focus normally.
  // When audio focus is disabled: use SHARE_MODE + AudioSession with CONCURRENCY_MIX_WITH_OTHERS
  // to allow cross-app audio mixing without interrupting other apps.
  async applyAudioFocusMode(player?: media.AVPlayer): Promise<void> {
    const target = player ?? this.avPlayer
    const enabled = AppStorage.get<boolean>('audioFocusEnabled') ?? true

    // Set AVPlayer interrupt mode
    if (target) {
      target.audioInterruptMode = enabled
        ? audio.InterruptMode.INDEPENDENT_MODE
        : audio.InterruptMode.SHARE_MODE
    }

    // Manage AudioSession for cross-app focus
    if (!enabled) {
      // Activate AudioSession with MIX strategy to allow cross-app mixing
      await this.activateAudioSessionMix()
    } else {
      // Deactivate AudioSession to restore normal focus behavior
      await this.deactivateAudioSessionMix()
    }

    console.info('[AudioFocus] applyAudioFocusMode: enabled = ' + enabled +
      ', audioSessionActive = ' + this.audioSessionActive)
  }

  private async activateAudioSessionMix(): Promise<void> {
    if (this.audioSessionActive) {
      return
    }
    try {
      if (!this.audioSessionManager) {
        const audioManager = audio.getAudioManager()
        this.audioSessionManager = audioManager.getSessionManager()
      }
      const strategy: audio.AudioSessionStrategy = {
        concurrencyMode: audio.AudioConcurrencyMode.CONCURRENCY_MIX_WITH_OTHERS
      }
      await this.audioSessionManager.activateAudioSession(strategy)
      this.audioSessionActive = true
      console.info('[AudioFocus] AudioSession activated with MIX_WITH_OTHERS')
    } catch (err) {
      const error = err as BusinessError
      console.error('[AudioFocus] Failed to activate AudioSession: ' + error.code + ' ' + error.message)
    }
  }

  private async deactivateAudioSessionMix(): Promise<void> {
    if (!this.audioSessionActive || !this.audioSessionManager) {
      return
    }
    try {
      await this.audioSessionManager.deactivateAudioSession()
      this.audioSessionActive = false
      console.info('[AudioFocus] AudioSession deactivated')
    } catch (err) {
      const error = err as BusinessError
      console.error('[AudioFocus] Failed to deactivate AudioSession: ' + error.code + ' ' + error.message)
    }
  }

  private updateSessionMetadata(): void {
    if (!this.session || this.sessionDeactivated) {
      return
    }
    const baseTitle = (AppStorage.get('currentSongTitle') as string) ?? ''
    const override = this._displayTitleOverride
    const title = (override !== null && override.length > 0) ? override : baseTitle
    const metadata: avSession.AVMetadata = {
      assetId: this.currentSongId,
      title: title,
      artist: (AppStorage.get('currentSongArtist') as string) ?? '',
      duration: this._durationMs > 0 ? this._durationMs : undefined
    }
    if (this._desktopLyricsLrc.length > 0) {
      metadata.lyric = this._desktopLyricsLrc
    }
    // Prefer PixelMap from CurrentSongCoverController (covers are loaded
    // on-demand as PixelMap, not as URI strings, so coverUri is usually empty).
    const coverPixelMap = CurrentSongCoverController.getInstance().coverPixelMap
    if (coverPixelMap) {
      metadata.mediaImage = coverPixelMap
    } else {
      const coverUri = (AppStorage.get('currentSongCoverUri') as string) ?? ''
      if (coverUri.length > 0) {
        metadata.mediaImage = coverUri
      } else if (this.defaultCoverPixelMap) {
        metadata.mediaImage = this.defaultCoverPixelMap
      }
    }
    this.session.setAVMetadata(metadata).catch((err: Error) => {
      console.error('AudioPlayerService: setAVMetadata failed - ' + err.message)
    })
  }

  private updateSessionCoverImage(pm: image.PixelMap | undefined): void {
    if (!this.session || this.sessionDeactivated) {
      return
    }
    const baseTitle = (AppStorage.get('currentSongTitle') as string) ?? ''
    const override = this._displayTitleOverride
    const title = (override !== null && override.length > 0) ? override : baseTitle
    const metadata: avSession.AVMetadata = {
      assetId: this.currentSongId,
      title: title,
      artist: (AppStorage.get('currentSongArtist') as string) ?? '',
      duration: this._durationMs > 0 ? this._durationMs : undefined
    }
    if (this._desktopLyricsLrc.length > 0) {
      metadata.lyric = this._desktopLyricsLrc
    }
    metadata.mediaImage = pm ? pm : (this.defaultCoverPixelMap ?? undefined)
    this.session.setAVMetadata(metadata).catch((err: Error) => {
      console.error('AudioPlayerService: setAVMetadata(cover) failed - ' + err.message)
    })
  }

  // spec12 — Push the merged notification title (lyric line when toggle is ON
  // and a line is available, otherwise the song title) into the AVSession
  // metadata. Called by NotificationLyricController on every lyric line
  // change, every song change, and every toggle flip. Pass `null` or `''` to
  // clear the override and fall back to `currentSongTitle`.
  setNotificationDisplayTitle(merged: string | null): void {
    this._displayTitleOverride = merged
    this.updateSessionMetadata()
  }

  // Push the raw LRC payload that the system reads as AVMetadata.lyric.
  // Drives the AVSession desktop-lyrics overlay (also picked up by control
  // center / lock screen / smart bar where the system surfaces lyrics).
  // Called by DesktopLyricsAVSessionController after the new song's LRC
  // has been parsed. Empty string clears the field.
  setDesktopLyricsLrc(lrc: string): void {
    if (this._desktopLyricsLrc === lrc) {
      return
    }
    this._desktopLyricsLrc = lrc
    this.updateSessionMetadata()
  }

  // spec23 — Mirror the "显示关闭按钮" toggle into AVSession state. Two writes:
  //   1) setExtras({ showCloseButton: value }) — stateful read for any future
  //      controller or surface that wants to query the current value.
  //   2) dispatchSessionEvent('showCloseButtonChanged', { value }) — one-shot
  //      push for any subscribed surface (live activity / media card / test
  //      harness).
  // Both are wrapped in try/catch because setExtras can reject when the
  // session is not yet fully activated; in that case
  // MediaCardCloseButtonController re-publishes on the next song change.
  publishCloseButtonExtras(value: boolean): void {
    if (!this.session) {
      return
    }
    try {
      const extras: Record<string, Object> = { 'showCloseButton': value }
      this.session.setExtras(extras).catch((err: Error) => {
        console.warn('AudioPlayerService: setExtras(showCloseButton) failed - ' + err.message)
      })
    } catch (e) {
      console.warn('AudioPlayerService: setExtras(showCloseButton) threw - ' + (e as Error).message)
    }
    try {
      const eventArgs: Record<string, Object> = { 'value': value }
      this.session.dispatchSessionEvent('showCloseButtonChanged', eventArgs).catch((err: Error) => {
        console.warn('AudioPlayerService: dispatchSessionEvent(showCloseButtonChanged) failed - '
          + err.message)
      })
    } catch (e) {
      console.warn('AudioPlayerService: dispatchSessionEvent(showCloseButtonChanged) threw - '
        + (e as Error).message)
    }
  }

  // spec24 — Mirror the "显示桌面歌词按钮" toggle into AVSession state. Same
  // shape as publishCloseButtonExtras: a stateful setExtras write plus a
  // one-shot dispatched event. Both wrapped in try/catch because setExtras can
  // reject when the session is not yet fully activated.
  publishDesktopLyricsButtonExtras(value: boolean): void {
    if (!this.session) {
      return
    }
    try {
      const extras: Record<string, Object> = { 'showDesktopLyricsButton': value }
      this.session.setExtras(extras).catch((err: Error) => {
        console.warn('AudioPlayerService: setExtras(showDesktopLyricsButton) failed - '
          + err.message)
      })
    } catch (e) {
      console.warn('AudioPlayerService: setExtras(showDesktopLyricsButton) threw - '
        + (e as Error).message)
    }
    try {
      const eventArgs: Record<string, Object> = { 'value': value }
      this.session.dispatchSessionEvent('showDesktopLyricsButtonChanged', eventArgs)
        .catch((err: Error) => {
          console.warn('AudioPlayerService: dispatchSessionEvent('
            + 'showDesktopLyricsButtonChanged) failed - ' + err.message)
        })
    } catch (e) {
      console.warn('AudioPlayerService: dispatchSessionEvent(showDesktopLyricsButtonChanged) threw - '
        + (e as Error).message)
    }
  }

  // spec24 — Publish the in-card "lyric or artist" intent + current lyric line
  // for surfaces that drive the artist->lyric row swap. Two writes:
  //   1) setExtras({ 'cardLyricsActive': boolean, 'cardLyricsLine': string })
  //   2) dispatchSessionEvent('cardLyricsStateChanged', { active, line })
  // Called by MediaCardDesktopLyricsButtonController on every state change
  // (toggle flip from card OR running-line update while active).
  publishCardLyricsState(active: boolean, line: string): void {
    if (!this.session) {
      return
    }
    try {
      const extras: Record<string, Object> = {
        'cardLyricsActive': active,
        'cardLyricsLine': line
      }
      this.session.setExtras(extras).catch((err: Error) => {
        console.warn('AudioPlayerService: setExtras(cardLyrics*) failed - '
          + err.message)
      })
    } catch (e) {
      console.warn('AudioPlayerService: setExtras(cardLyrics*) threw - '
        + (e as Error).message)
    }
    try {
      const eventArgs: Record<string, Object> = {
        'active': active, 'line': line
      }
      this.session.dispatchSessionEvent('cardLyricsStateChanged', eventArgs)
        .catch((err: Error) => {
          console.warn('AudioPlayerService: dispatchSessionEvent(cardLyricsStateChanged) failed - '
            + err.message)
        })
    } catch (e) {
      console.warn('AudioPlayerService: dispatchSessionEvent(cardLyricsStateChanged) threw - '
        + (e as Error).message)
    }
  }

  // spec23 — Card-driven close request. Re-reads the toggle gate so a stale
  // event arriving after the user flipped OFF is safely dropped, then
  // executes the spec-defined four-step close pipeline:
  //   pause → save state → terminate (releases AVSession + AVPlayer,
  //   stops background task, calls context.terminateSelf()).
  // Mirrors the effect of ExitAppDataSource.exitApp(); the gate lives here
  // so it cannot be bypassed by any caller.
  async requestCloseFromCard(): Promise<void> {
    const enabled: boolean = AppStorage.get<boolean>('showCloseButton') ?? true
    if (!enabled) {
      console.info('AudioPlayerService: requestCloseFromCard ignored - toggle is OFF')
      return
    }
    try {
      await this.pause()
    } catch (e) {
      console.warn('AudioPlayerService: requestCloseFromCard pause failed - ' + (e as Error).message)
    }
    this.saveStateBeforeExit()
    await this.terminateApp()
  }

  // Deactivate the AVSession so the system live activity / notification disappears.
  // Called when the queue is emptied and there is nothing left to play.
  deactivateSession(): void {
    if (!this.session) {
      return
    }
    this.sessionDeactivated = true
    this.deactivatePromise = this.session.deactivate().catch((err: Error) => {
      console.error('AudioPlayerService: AVSession deactivate failed - ' + err.message)
    })
  }

  // Re-activate the AVSession so the system live activity reappears.
  private activateSession(): void {
    if (!this.session) {
      return
    }
    this.sessionDeactivated = false
    this.deactivatePromise = null
    this.session.activate().catch((err: Error) => {
      console.error('AudioPlayerService: AVSession activate failed - ' + err.message)
    })
  }

  private updateSessionPlaybackState(state: avSession.PlaybackState): void {
    if (!this.session || this.sessionDeactivated) {
      return
    }
    const playbackState: avSession.AVPlaybackState = {
      state: state,
      // Report the real playback rate so the system extrapolates the desktop
      // lyrics / media-control position at the same speed the in-app player
      // uses (getCurrentTimeMs interpolates with _currentSpeed). Omitting this
      // makes the system assume 1.0x, drifting the overlay against the app.
      speed: this._currentSpeed
    }
    // Only attach position when an active player exists; on cold-start the
    // system media service may reject or ignore a position with no backing
    // audio session, causing the play/pause button to stay grey.
    if (this.avPlayer && this._isPlaying) {
      // Use the interpolated position (the same value the playback page renders
      // and the lyric cursor uses) paired with the current wall clock, so the
      // (elapsedTime, updateTime) anchor we hand the system matches the in-app
      // truth at this instant. Reporting the raw last-timeUpdate _currentTimeMs
      // with updateTime=now instead leaves the system to extrapolate from a
      // stale anchor, which is what made the overlay's line jumps run ahead.
      playbackState.position = {
        elapsedTime: this.getCurrentTimeMs(),
        updateTime: new Date().getTime()
      }
    }
    this.session.setAVPlaybackState(playbackState).catch((err: Error) => {
      console.error('AudioPlayerService: setAVPlaybackState failed - ' + err.message)
    })
  }

  private setupListeners(player: media.AVPlayer): void {
    player.on('stateChange', (state: string) => {
      switch (state) {
        case 'idle':
          this._isPlaying = false
          this.sourceLoaded = false
          break
        case 'initialized':
          this.sourceLoaded = true
          player.prepare()
          break
        case 'prepared':
          this._durationMs = player.duration
          // Apply pending seek from either persistence restore or user seek-while-paused
          const seekTarget = this._pendingResumeSeek >= 0
            ? this._pendingResumeSeek
            : (this.pendingSeekMs >= 0 && this.currentSongId === this.pendingSongId
              ? this.pendingSeekMs : -1)
          if (seekTarget >= 0) {
            player.seek(seekTarget)
            this._currentTimeMs = seekTarget
            this._anchorPositionMs = seekTarget
            this._anchorWallTimeMs = new Date().getTime()
          }
          this.pendingSeekMs = -1
          this._pendingResumeSeek = -1
          this.pendingSongId = ''
          this.updateSessionMetadata()
          // Re-apply playback speed after reset (reset reverts to 1.0)
          if (this._currentSpeed !== 1.0) {
            const clampedRate = Math.max(0.125, Math.min(4.0, this._currentSpeed))
            player.setPlaybackRate(clampedRate)
          }
          this.applyAudioFocusMode(player).then(async () => {
            // spec14: read ReplayGain and compute volume balance multiplier
            if (this.isVolumeBalanceEnabled()) {
              const rgDb = await MusicDatabase.getReplayGainDb(this.currentSongId)
              this._volumeBalanceMultiplier = this.parseReplayGainDb(rgDb)
            } else {
              this._volumeBalanceMultiplier = 1.0
            }
            // spec11: if a song-switch fade-in is pending, mute before play()
            // so the first frames are silent, then ramp 0 → balanceMultiplier over 500 ms.
            // Otherwise ensure volume is at balanceMultiplier.
            if (this._fadeInPendingForNextPrepared) {
              this._fadeInPendingForNextPrepared = false
              this.safeSetVolume(0)
              player.play()
              void this.rampVolume(0, this._volumeBalanceMultiplier)
            } else {
              this.safeSetVolume(this._volumeBalanceMultiplier)
              player.play()
            }
          })
          break
        case 'playing':
          this._isPlaying = true
          this._playbackIntentActive = true
          this._pendingResumeSeek = -1
          AppStorage.setOrCreate('isPlaying', true)
          AppStorage.setOrCreate('playbackError', '')
          // spec21: start/resume the play-count accumulator for this song.
          this.resetPlayCountSession(this.currentSongId)
          this.playCountLastTickWall = Date.now()
          // Anchor wall-clock for interpolation
          this._anchorPositionMs = this._currentTimeMs
          this._anchorWallTimeMs = new Date().getTime()
          this.lastSessionSyncTime = this._anchorWallTimeMs
          // Re-activate session in case it was deactivated (e.g. queue was emptied).
          // Also refresh metadata — it was skipped during 'prepared' when the flag was still true.
          this.activateSession()
          this.updateSessionMetadata()
          this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
          this.startBackgroundTask()
          // Signal doPlay() that the state machine pipeline is complete
          if (this.playReadyResolve) {
            this.playReadyResolve()
            this.playReadyResolve = null
          }
          break
        case 'paused':
          // spec21: flush last delta before the player stops advancing time.
          this.advancePlayCountAccum()
          this.playCountLastTickWall = 0
          this._isPlaying = false
          AppStorage.setOrCreate('isPlaying', false)
          this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
          this.stopBackgroundTask()
          break
        case 'completed':
          // spec21: flush last delta. Do NOT force-commit here — the
          // threshold (60s played, or 90% of duration for short songs) must
          // be checked against actual accumulated play time. A user can seek
          // to near the end of a song so that 'completed' fires while
          // accumulated play time is far below threshold; in that case the
          // count must not increment. advancePlayCountAccum() commits only
          // when the threshold is genuinely met.
          this.advancePlayCountAccum()
          this.playCountLastTickWall = 0
          this._isPlaying = false
          this._playbackIntentActive = false
          this._currentTimeMs = this._durationMs
          AppStorage.setOrCreate('isPlaying', false)
          this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_COMPLETED)
          if (this.onSongCompletedDuringSleepTimer) {
            // Sleep timer is waiting for song to end — stop and exit instead of auto-skipping
            this.onSongCompletedDuringSleepTimer()
          } else {
            this.skipNext()
          }
          break
        case 'stopped':
          // spec21: flush and freeze the accumulator on stop.
          this.advancePlayCountAccum()
          this.playCountLastTickWall = 0
          this._isPlaying = false
          this._playbackIntentActive = false
          // spec11: abort any active fade ramp; clear any pending song-switch fade-in.
          this._fadeAborted = true
          this._fadeInPendingForNextPrepared = false
          AppStorage.setOrCreate('isPlaying', false)
          this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP)
          this.stopBackgroundTask()
          break
        case 'released':
          this._isPlaying = false
          this._playbackIntentActive = false
          // spec11: abort any active fade ramp so it doesn't poke a dead AVPlayer.
          this._fadeAborted = true
          this._fadeInPendingForNextPrepared = false
          break
        case 'error':
          // spec21: freeze the accumulator; don't commit a partial count.
          this.playCountLastTickWall = 0
          this._isPlaying = false
          this._playbackIntentActive = false
          // spec11: abort any active fade ramp; clear pending flag.
          this._fadeAborted = true
          this._fadeInPendingForNextPrepared = false
          AppStorage.setOrCreate('isPlaying', false)
          console.error('AudioPlayerService: AVPlayer entered error state')
          // Signal doPlay() so the serialization lock is released on error too
          if (this.playReadyResolve) {
            this.playReadyResolve()
            this.playReadyResolve = null
          }
          break
      }
    })

    player.on('timeUpdate', (timeMs: number) => {
      if (this._pendingResumeSeek < 0) {
        this._currentTimeMs = timeMs
        // Refresh wall-clock anchor so interpolation stays accurate
        this._anchorPositionMs = timeMs
        this._anchorWallTimeMs = new Date().getTime()
        // spec21: advance the play-count accumulator while actively playing.
        if (this._isPlaying) {
          this.advancePlayCountAccum()
        }
        // Periodically re-anchor the AVSession position so the system playback
        // control and the desktop-lyrics overlay stay accurate. Kept at 1s
        // (was 3s): the system free-runs its own clock between updates, so a
        // long gap let the overlay's lyric line advance ahead of the in-app
        // view before the next re-sync corrected it.
        if (this._isPlaying) {
          const now = this._anchorWallTimeMs
          if (now - this.lastSessionSyncTime >= 1000) {
            this.lastSessionSyncTime = now
            this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
          }
        }
      }
    })

    player.on('error', (err: Error) => {
      console.error('AudioPlayerService: AVPlayer error - ' + err.message)
      this._isPlaying = false
      this._playbackIntentActive = false
      // spec11: abort any active fade ramp on hard error.
      this._fadeAborted = true
      this._fadeInPendingForNextPrepared = false
      AppStorage.setOrCreate('isPlaying', false)
      // Debounce error display to avoid flash during rapid song switches.
      // If a new doPlay() starts within 300ms, it clears this timer.
      if (this._errorDebounceTimer !== -1) {
        clearTimeout(this._errorDebounceTimer)
      }
      this._errorDebounceTimer = setTimeout(() => {
        this._errorDebounceTimer = -1
        if (!this._switchingTrack) {
          AppStorage.setOrCreate('playbackError', '播放出错')
        }
      }, 300)
      // Release serialization lock on error
      if (this.playReadyResolve) {
        this.playReadyResolve()
        this.playReadyResolve = null
      }
    })

    player.on('audioInterrupt', (event: audio.InterruptEvent) => {
      if (event.forceType === audio.InterruptForceType.INTERRUPT_FORCE) {
        switch (event.hintType) {
          case audio.InterruptHint.INTERRUPT_HINT_PAUSE:
          case audio.InterruptHint.INTERRUPT_HINT_STOP:
            this._playbackIntentActive = false
            this._anchorWallTimeMs = 0
            // spec11: the system forced pause without going through our fade
            // envelope. Abort any in-flight ramp; the next resume() will
            // re-ramp 0 → 1 if fade is still enabled.
            this._fadeAborted = true
            break
          default:
            break
        }
      }
    })
  }

  async play(fileUri_: string, songId: string): Promise<void> {
    // Serialize play requests — each call waits for the previous one to finish
    // (including its reset/prepare/fdSrc pipeline) before starting.
    const previous = this.playLock
    let unlock: () => void = () => {}
    this.playLock = new Promise<void>((resolve) => { unlock = resolve })
    try {
      await previous
    } catch (_) { /* ignore previous errors */ }

    try {
      await this.doPlay(fileUri_, songId)
    } finally {
      unlock()
    }
  }

  private async doPlay(fileUri_: string, songId: string): Promise<void> {
    if (!fileUri_) {
      console.error('AudioPlayerService: fileUri is empty')
      return
    }

    // Suppress transient AVPlayer errors during the entire song-switch pipeline
    this._switchingTrack = true
    // Cancel any pending error display from a previous failed play
    if (this._errorDebounceTimer !== -1) {
      clearTimeout(this._errorDebounceTimer)
      this._errorDebounceTimer = -1
    }

    // Clear any previous playback error
    AppStorage.setOrCreate('playbackError', '')

    // Persist the fileUri so it survives app restart (PersistentStorage auto-saves)
    AppStorage.setOrCreate('currentSongFileUri', fileUri_)

    try {
      const isNewPlayer = !this.avPlayer
      const player = await this.ensurePlayer()

      // If switching songs, reset the player
      if (this.currentSongId !== songId || !this._isPlaying) {
        // Only reset if the player already had a source loaded; skip for freshly created players
        if (!isNewPlayer && this.sourceLoaded) {
          await player.reset()
        }
        this.closeFd()
        this.sourceLoaded = false

        this.currentSongId = songId
        this._currentTimeMs = 0
        this._durationMs = 0

        let file: fileIo.File | null = null
        try {
          file = fileIo.openSync(fileUri_, fileIo.OpenMode.READ_ONLY)
        } catch (openErr) {
          // Permission may have expired after app restart — try re-activating
          console.warn('AudioPlayerService: openSync failed, trying activatePermission - ' +
            (openErr as Error).message)
          try {
            const policy: fileShare.PolicyInfo = {
              uri: fileUri_,
              operationMode: fileShare.OperationMode.READ_MODE
            } as fileShare.PolicyInfo
            await fileShare.activatePermission([policy])
            file = fileIo.openSync(fileUri_, fileIo.OpenMode.READ_ONLY)
            console.info('AudioPlayerService: activatePermission succeeded, file opened')
          } catch (retryErr) {
            console.error('AudioPlayerService: retry after activatePermission also failed - ' +
              (retryErr as Error).message)
            throw (retryErr instanceof Error) ? retryErr : new Error(String(retryErr))
          }
        }

        this.currentFd = file.fd
        const stat = fileIo.statSync(file.fd)

        // Wait for the full AVPlayer state machine pipeline:
        // fdSrc set → 'initialized' → prepare() → 'prepared' → play() → 'playing'
        const playReady = new Promise<void>((resolve) => {
          this.playReadyResolve = resolve
        })
        // spec11: when fade is enabled, the new song fades in from silence after
        // 'prepared' calls player.play(). No outgoing fade-out on song switch.
        this._fadeInPendingForNextPrepared = this.isFadeEnabled()
        player.fdSrc = { fd: file.fd, offset: 0, length: stat.size }
        // Wait until AVPlayer reaches 'playing' or 'error' state
        await playReady
      }
      this._switchingTrack = false
    } catch (err) {
      console.error('AudioPlayerService: play failed - ' + (err as Error).message)
      this._isPlaying = false
      this._playbackIntentActive = false
      this._switchingTrack = false
      this.sourceLoaded = false
      AppStorage.setOrCreate('isPlaying', false)
      AppStorage.setOrCreate('playbackError', '无法找到文件')
    }
  }

  // ==================== spec11 — Fade helpers ====================

  // Read the toggle live on every pause/resume call so the flag takes effect
  // in real time with no player restart or cached value.
  private isFadeEnabled(): boolean {
    return AppStorage.get<boolean>('fadeInOutEnabled') ?? true
  }

  // spec14 — Read the volume balance toggle live. The change only takes effect
  // on the next song switch (doPlay reads this in the 'prepared' handler).
  private isVolumeBalanceEnabled(): boolean {
    return AppStorage.get<boolean>('volumeBalanceEnabled') ?? true
  }

  // spec14 — Convert a ReplayGain dB string (e.g. "-3.5 dB") to a linear volume
  // multiplier. Returns 1.0 for empty/invalid strings. Clamps to [0, 1] so
  // positive gains (which would require volume > 1.0) are silently ignored.
  private parseReplayGainDb(gainStr: string): number {
    if (!gainStr || gainStr.length === 0) return 1.0
    const match = gainStr.match(/([+-]?\d+(?:\.\d+)?)/)
    if (!match) return 1.0
    const db = parseFloat(match[1])
    if (isNaN(db)) return 1.0
    // dB to linear: 10^(db/20)
    const multiplier = Math.pow(10, db / 20)
    // Clamp to [0, 1] for safety (AVPlayer volume range)
    return Math.max(0, Math.min(1, multiplier))
  }

  // Clamp to [0, 1] and set the AVPlayer volume, tolerating wrong-state errors.
  // AVPlayer.setVolume rejects in states idle/initialized/released/error, which
  // we may transiently hit during fade-out → pause and during song switch.
  // spec14: the envelope value v (0..1) is multiplied by _volumeBalanceMultiplier
  // so the effective volume never exceeds the balance-adjusted ceiling.
  private safeSetVolume(v: number): void {
    if (!this.avPlayer) {
      return
    }
    const envelope = Math.max(0, Math.min(1, v))
    const effective = Math.max(0, Math.min(1, envelope * this._volumeBalanceMultiplier))
    try {
      this.avPlayer.setVolume(effective)
      this._currentVolume = envelope
    } catch (e) {
      console.warn('AudioPlayerService: setVolume failed - ' + (e as Error).message)
    }
  }

  // Linear ramp from `from` to `to` over FADE_DURATION_MS, FADE_STEPS ticks.
  // Aborts early if _fadeAborted flips (set by error/released/interrupt paths).
  // Always finalizes with the target value so we never leave a half-applied volume.
  private async rampVolume(from: number, to: number): Promise<void> {
    this._fadeAborted = false
    const steps = AudioPlayerService.FADE_STEPS
    const tickMs = AudioPlayerService.FADE_DURATION_MS / steps
    const startFrom = Math.max(0, Math.min(1, from))
    const endTo = Math.max(0, Math.min(1, to))
    for (let i = 1; i <= steps; i++) {
      if (this._fadeAborted || !this.avPlayer) {
        break
      }
      const t = i / steps
      const v = startFrom + (endTo - startFrom) * t
      this.safeSetVolume(v)
      // Sleep for one tick
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, tickMs)
      })
    }
    // Always finalize so volume lands exactly on the target.
    if (this.avPlayer) {
      this.safeSetVolume(endTo)
    }
  }

  // Chain user pause/resume envelope calls onto a single promise mirror of
  // the existing playLock pattern. Next call awaits previous.
  private withFadeLock(op: () => Promise<void>): Promise<void> {
    const previous = this._fadeLock
    let unlock: () => void = (): void => {}
    this._fadeLock = new Promise<void>((resolve: () => void): void => {
      unlock = resolve
    })
    const task = (async (): Promise<void> => {
      try {
        await previous
      } catch (_) { /* ignore previous errors */ }
      try {
        await op()
      } finally {
        unlock()
      }
    })()
    return task
  }

  async pause(): Promise<void> {
    if (!this.avPlayer || !this._isPlaying) {
      return
    }
    // Flip intent immediately so interrupt-caused behavior stays consistent,
    // even before the fade-out finishes.
    this._playbackIntentActive = false
    // Update UI state immediately so the play/pause icon reflects the user's
    // intent right away, while the audio continues its fade-out envelope.
    AppStorage.setOrCreate('isPlaying', false)
    // Also push the paused state to AVSession immediately so the system media
    // card (control centre / notification) updates without waiting for fade-out.
    this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
    const player = this.avPlayer
    await this.withFadeLock(async (): Promise<void> => {
      if (this.isFadeEnabled() && this.avPlayer && this._isPlaying) {
        await this.rampVolume(this._currentVolume, 0.0)
      }
      if (this.avPlayer && this._isPlaying) {
        try {
          player.pause()
        } catch (e) {
          console.warn('AudioPlayerService: pause failed - ' + (e as Error).message)
        }
      }
    })
  }

  // Fully stop playback: reset AVPlayer source, clear duration/progress, clear queue position.
  // Use this when the current song is removed from the library.
  // Acquires playLock so that any subsequent play() call waits for the AVPlayer reset to finish,
  // preventing state machine conflicts (same pattern as clear()).
  stop(): void {
    // Immediate UI state cleanup — callers see the change synchronously
    this._isPlaying = false
    this._playbackIntentActive = false
    AppStorage.setOrCreate('isPlaying', false)
    AppStorage.setOrCreate('currentSongFileUri', '')
    AppStorage.setOrCreate('currentSongTitle', '')
    AppStorage.setOrCreate('currentSongArtist', '')
    AppStorage.setOrCreate('currentSongId', '')
    AppStorage.setOrCreate('currentSongCoverUri', '')

    // Acquire playLock so that any subsequent play() call waits for stop to finish
    const previous = this.playLock
    let unlock: () => void = () => {}
    this.playLock = new Promise<void>((resolve) => { unlock = resolve })

    // Async teardown — callers don't await, but play() will wait via playLock
    previous.catch(() => {}).then(async () => {
      try {
        // Ensure session deactivation completes before resetting player,
        // so the system never sees "session active + audio stopped".
        if (this.deactivatePromise) {
          try { await this.deactivatePromise } catch (_) {}
          this.deactivatePromise = null
        }
        if (this.avPlayer) {
          try {
            await this.avPlayer.reset()
          } catch (e) {
            console.error('AudioPlayerService: stop reset failed - ' + (e as Error).message)
          }
        }
        this.closeFd()
        this._currentTimeMs = 0
        this._durationMs = 0
        this.currentSongId = ''
        this.sourceLoaded = false
        this.pendingFileUri = ''
        this.pendingSongId = ''
        this.pendingSeekMs = -1
        this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP)
        this.stopBackgroundTask()
      } finally {
        unlock()
      }
    })
  }

  async resume(): Promise<void> {
    if (!this.avPlayer || this._isPlaying) {
      return
    }
    const player = this.avPlayer
    const pendingSeek = this._pendingResumeSeek
    this._pendingResumeSeek = -1
    await this.withFadeLock(async (): Promise<void> => {
      if (!this.avPlayer || this._isPlaying) {
        return
      }
      await this.applyAudioFocusMode()
      const fade = this.isFadeEnabled()
      // spec14: ramp target is _volumeBalanceMultiplier, not 1.0
      const rampTarget = this._volumeBalanceMultiplier
      if (fade) {
        // Start from silence so the first frames after play() are inaudible
        // rather than punching in at full volume.
        this.safeSetVolume(0)
      } else {
        this.safeSetVolume(rampTarget)
      }
      try {
        player.play()
        if (pendingSeek >= 0) {
          player.seek(pendingSeek)
        }
      } catch (e) {
        console.warn('AudioPlayerService: resume play failed - ' + (e as Error).message)
        return
      }
      if (fade) {
        await this.rampVolume(0, rampTarget)
      } else {
        // Ensure volume ends at rampTarget in case a prior fade left it partial.
        this.safeSetVolume(rampTarget)
      }
    })
  }

  togglePlayPause(): void {
    if (!this.avPlayer || !this.sourceLoaded) {
      // No player initialized yet or no source loaded — try to restore from persisted state
      let fileUri = this.pendingFileUri
      let songId = this.pendingSongId
      if (!fileUri) {
        // Fallback: read directly from AppStorage (set by PersistentStorage or play())
        fileUri = (AppStorage.get('currentSongFileUri') as string) ?? ''
        songId = (AppStorage.get('currentSongId') as string) ?? ''
      }
      if (fileUri.length > 0 && songId.length > 0) {
        this.pendingFileUri = ''
        this.play(fileUri, songId).catch((e: Error) => {
          console.error('AudioPlayerService: restore play failed - ' + e.message)
        })
      }
      return
    }
    if (this._isPlaying) {
      this.pause()
    } else {
      this.resume()
    }
  }

  seek(timeMs: number): void {
    this._currentTimeMs = timeMs
    this._anchorPositionMs = timeMs
    this._anchorWallTimeMs = new Date().getTime()
    if (this.avPlayer && this._isPlaying) {
      this.avPlayer.seek(timeMs)
      this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
    } else {
      // Player not playing — avPlayer.seek() may not take effect.
      // Save for resume() to apply when playback starts.
      this._pendingResumeSeek = timeMs
      this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PAUSE)
    }
  }

  setSpeed(speed: number): void {
    this._currentSpeed = speed
    AppStorage.setOrCreate('playbackSpeed', speed)
    if (this.avPlayer) {
      // setPlaybackRate accepts arbitrary float (valid range 0.125 ~ 4.0)
      const clampedRate = Math.max(0.125, Math.min(4.0, speed))
      this.avPlayer.setPlaybackRate(clampedRate)
    }
  }

  getSpeed(): number {
    return this._currentSpeed
  }

  /**
   * Called when the app returns to foreground.  If the user intended to play
   * but AVPlayer's position drifted behind the wall-clock interpolation
   * (happens during muted background where the system stops advancing frames),
   * seek AVPlayer forward so the actual position matches the live window.
   */
  reconcileOnForeground(): void {
    if (!this._playbackIntentActive || !this.avPlayer || this._anchorWallTimeMs <= 0) {
      return
    }
    const interpolated = this.getCurrentTimeMs()
    const drift = interpolated - this._currentTimeMs
    // Only seek if drift exceeds 1 second (avoids unnecessary seeks in normal playback)
    if (drift > 1000) {
      this._anchorPositionMs = interpolated
      this._anchorWallTimeMs = new Date().getTime()
      this._currentTimeMs = interpolated
      if (this._isPlaying) {
        this.avPlayer.seek(interpolated)
        this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_PLAY)
      }
    }
  }

  getCurrentTimeMs(): number {
    // While playback intent is active, interpolate from the wall-clock anchor
    // so the position stays accurate even when AVPlayer.timeUpdate stops
    // firing (e.g. muted background playback where the system may pause the
    // AVPlayer).  This is the same approach the system Live Activity uses
    // via AVSession.position (elapsedTime + wallClockDelta).
    if (this._playbackIntentActive && this._anchorWallTimeMs > 0) {
      const elapsed = (new Date().getTime() - this._anchorWallTimeMs) * this._currentSpeed
      const interpolated = this._anchorPositionMs + elapsed
      // Clamp to [0, duration] to avoid overshooting
      const clamped = this._durationMs > 0
        ? Math.min(interpolated, this._durationMs)
        : interpolated
      return Math.max(0, clamped)
    }
    return this._currentTimeMs
  }

  getDurationMs(): number {
    return this._durationMs
  }

  isPlaybackIntentActive(): boolean {
    return this._playbackIntentActive
  }

  isCurrentlyPlaying(): boolean {
    return this._isPlaying
  }

  private closeFd(): void {
    if (this.currentFd >= 0) {
      try {
        fileIo.closeSync(this.currentFd)
      } catch (e) {
        // ignore close errors
      }
      this.currentFd = -1
    }
  }

  // ==================== Queue Management ====================

  setQueue(songs: QueueSongModel[], startIndex: number): void {
    this.normalQueue = songs.slice()
    if (songs.length === 0) {
      this.normalIndex = -1
      this.randomQueue = []
      this.randomIndex = -1
      this.scheduleQueueSave()
      return
    }
    this.normalIndex = Math.max(0, Math.min(startIndex, songs.length - 1))
    // Build randomQueue: current song at [0], rest shuffled (Fisher-Yates)
    this.buildRandomQueue()
    const song = this.normalQueue[this.normalIndex]
    this.play(song.fileUri, song.id).catch((): void => {})
    this.notifySongChanged(song)
    this.scheduleQueueSave()
  }

  setPlayMode(mode: string): void {
    const oldMode = this.playMode
    this.playMode = mode
    // When switching to RANDOM, reshuffle the random queue
    if (mode === PlayModeConstants.RANDOM && oldMode !== PlayModeConstants.RANDOM) {
      this.reshuffleRandomQueue()
      this.scheduleQueueSave()
    }
  }

  // Restore play mode without triggering reshuffle (used during app startup)
  restorePlayMode(mode: string): void {
    this.playMode = mode
  }

  // Returns the display queue based on current play mode
  getQueue(): QueueSongModel[] {
    return this.playMode === PlayModeConstants.RANDOM ? this.randomQueue : this.normalQueue
  }

  // Returns the display index based on current play mode
  getCurrentIndex(): number {
    return this.playMode === PlayModeConstants.RANDOM ? this.randomIndex : this.normalIndex
  }

  getNormalQueue(): QueueSongModel[] {
    return this.normalQueue
  }

  getRandomQueue(): QueueSongModel[] {
    return this.randomQueue
  }

  getNormalIndex(): number {
    return this.normalIndex
  }

  getRandomIndex(): number {
    return this.randomIndex
  }

  // Build randomQueue from normalQueue: current song at [0], rest Fisher-Yates shuffled
  private buildRandomQueue(): void {
    if (this.normalQueue.length === 0) {
      this.randomQueue = []
      this.randomIndex = -1
      return
    }
    const currentSong = this.normalQueue[this.normalIndex]
    const rest = this.normalQueue.filter((_s: QueueSongModel, i: number) => i !== this.normalIndex)
    // Fisher-Yates shuffle
    for (let i = rest.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const temp = rest[i]
      rest[i] = rest[j]
      rest[j] = temp
    }
    this.randomQueue = [currentSong, ...rest]
    this.randomIndex = 0
  }

  // Reshuffle randomQueue keeping current song at [0]
  private reshuffleRandomQueue(): void {
    if (this.normalQueue.length === 0 || this.normalIndex < 0) {
      return
    }
    const currentSong = this.normalQueue[this.normalIndex]
    const rest = this.normalQueue.filter((s: QueueSongModel) => s.id !== currentSong.id)
    // Fisher-Yates shuffle
    for (let i = rest.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const temp = rest[i]
      rest[i] = rest[j]
      rest[j] = temp
    }
    this.randomQueue = [currentSong, ...rest]
    this.randomIndex = 0
  }

  // Sync randomIndex to point to the same song as normalQueue[normalIndex]
  private syncRandomIndexToNormalIndex(): void {
    if (this.normalIndex < 0 || this.normalIndex >= this.normalQueue.length) {
      this.randomIndex = -1
      return
    }
    const targetId = this.normalQueue[this.normalIndex].id
    const idx = this.randomQueue.findIndex((s: QueueSongModel) => s.id === targetId)
    this.randomIndex = idx >= 0 ? idx : 0
  }

  // Sync normalIndex to point to the same song as randomQueue[randomIndex]
  private syncNormalIndexToRandomIndex(): void {
    if (this.randomIndex < 0 || this.randomIndex >= this.randomQueue.length) {
      this.normalIndex = -1
      return
    }
    const targetId = this.randomQueue[this.randomIndex].id
    const idx = this.normalQueue.findIndex((s: QueueSongModel) => s.id === targetId)
    this.normalIndex = idx >= 0 ? idx : 0
  }

  // Navigate to a specific song by id (used when user clicks a song in queue)
  playByIdInQueue(songId: string): void {
    if (this.playMode === PlayModeConstants.RANDOM) {
      const idx = this.randomQueue.findIndex((s: QueueSongModel) => s.id === songId)
      if (idx >= 0) {
        this.randomIndex = idx
        this.syncNormalIndexToRandomIndex()
      }
    } else {
      const idx = this.normalQueue.findIndex((s: QueueSongModel) => s.id === songId)
      if (idx >= 0) {
        this.normalIndex = idx
        this.syncRandomIndexToNormalIndex()
      }
    }
    const song = this.playMode === PlayModeConstants.RANDOM
      ? this.randomQueue[this.randomIndex] : this.normalQueue[this.normalIndex]
    if (song) {
      this.play(song.fileUri, song.id).catch((): void => {})
      this.notifySongChanged(song)
      this.scheduleQueueSave()
    }
  }

  addToPlayNext(song: QueueSongModel): void {
    // If current song is the one being added, do nothing
    const currentSong = this.playMode === PlayModeConstants.RANDOM
      ? (this.randomIndex >= 0 ? this.randomQueue[this.randomIndex] : null)
      : (this.normalIndex >= 0 ? this.normalQueue[this.normalIndex] : null)
    if (currentSong && currentSong.id === song.id) {
      return
    }
    // If queue is empty, add as first song to both queues and start playback immediately
    if (this.normalQueue.length === 0) {
      this.normalQueue.push(song)
      this.normalIndex = 0
      this.randomQueue.push(song)
      this.randomIndex = 0
      console.info('AudioPlayerService.addToPlayNext: queue was empty, auto-playing songId=' +
        song.id + ' fileUri=' + song.fileUri)
      this.play(song.fileUri, song.id).then(() => {
        console.info('AudioPlayerService.addToPlayNext: auto-play started successfully')
      }).catch((e: Error) => {
        console.error('AudioPlayerService.addToPlayNext: auto-play failed - ' + e.message)
      })
      this.notifySongChanged(song)
      this.scheduleQueueSave()
      return
    }
    // Remove duplicates from both queues
    const existingNormal = this.normalQueue.findIndex((q: QueueSongModel) => q.id === song.id)
    if (existingNormal >= 0) {
      this.normalQueue.splice(existingNormal, 1)
      if (existingNormal < this.normalIndex) {
        this.normalIndex--
      } else if (existingNormal === this.normalIndex) {
        // Edge case: shouldn't happen since we check currentSong above
        this.normalIndex = Math.min(this.normalIndex, this.normalQueue.length - 1)
      }
    }
    const existingRandom = this.randomQueue.findIndex((q: QueueSongModel) => q.id === song.id)
    if (existingRandom >= 0) {
      this.randomQueue.splice(existingRandom, 1)
      if (existingRandom < this.randomIndex) {
        this.randomIndex--
      } else if (existingRandom === this.randomIndex) {
        this.randomIndex = Math.min(this.randomIndex, this.randomQueue.length - 1)
      }
    }
    // Insert after current position in BOTH queues
    const normalInsert = this.normalIndex + 1
    this.normalQueue.splice(normalInsert, 0, song)
    const randomInsert = this.randomIndex + 1
    this.randomQueue.splice(randomInsert, 0, song)

    if (this.onQueueInserted) {
      this.onQueueInserted(song, this.playMode === PlayModeConstants.RANDOM ? randomInsert : normalInsert)
    }
    this.scheduleQueueSave()
  }

  skipNext(): void {
    console.info('AudioPlayerService.skipNext: normalLen=' + this.normalQueue.length +
      ' randomLen=' + this.randomQueue.length +
      ' playMode=' + this.playMode + ' normalIdx=' + this.normalIndex + ' randomIdx=' + this.randomIndex)
    if (this.normalQueue.length === 0) {
      return
    }
    // Single song in queue or repeat-one mode: restart current song from beginning
    if (this.normalQueue.length === 1 || this.playMode === PlayModeConstants.REPEAT_ONE) {
      this.seek(0)
      if (this.avPlayer) {
        this.avPlayer.play()
      }
      return
    }
    let song: QueueSongModel
    if (this.playMode === PlayModeConstants.RANDOM) {
      if (this.randomIndex >= this.randomQueue.length - 1) {
        // At end of random queue: reshuffle with current song at [0], then play [1]
        this.reshuffleRandomQueue()
        this.randomIndex = this.randomQueue.length > 1 ? 1 : 0
      } else {
        this.randomIndex++
      }
      this.syncNormalIndexToRandomIndex()
      song = this.randomQueue[this.randomIndex]
    } else {
      this.normalIndex = (this.normalIndex + 1) % this.normalQueue.length
      this.syncRandomIndexToNormalIndex()
      song = this.normalQueue[this.normalIndex]
    }
    this.play(song.fileUri, song.id).catch((): void => {})
    this.notifySongChanged(song)
    this.scheduleQueueSave()
  }

  skipPrevious(): void {
    console.info('AudioPlayerService.skipPrevious: normalLen=' + this.normalQueue.length +
      ' normalIdx=' + this.normalIndex + ' randomIdx=' + this.randomIndex +
      ' currentTimeMs=' + this._currentTimeMs)
    if (this.normalQueue.length === 0) {
      return
    }
    // Single song in queue: restart current song from beginning
    if (this.normalQueue.length === 1) {
      this.seek(0)
      if (this.avPlayer) {
        this.avPlayer.play()
      }
      return
    }
    let song: QueueSongModel
    if (this.playMode === PlayModeConstants.RANDOM) {
      this.randomIndex = (this.randomIndex - 1 + this.randomQueue.length) % this.randomQueue.length
      this.syncNormalIndexToRandomIndex()
      song = this.randomQueue[this.randomIndex]
    } else {
      this.normalIndex = (this.normalIndex - 1 + this.normalQueue.length) % this.normalQueue.length
      this.syncRandomIndexToNormalIndex()
      song = this.normalQueue[this.normalIndex]
    }
    this.play(song.fileUri, song.id).catch((): void => {})
    this.notifySongChanged(song)
    this.scheduleQueueSave()
  }

  // ==================== Stop & Clear ====================

  /**
   * Stop playback completely — resets AVPlayer, closes file descriptor,
   * clears internal state. Used when the play queue is emptied.
   */
  async clear(): Promise<void> {
    // Acquire playLock so that any subsequent play() call waits for clear to finish,
    // preventing AVPlayer state conflicts (e.g. clear resets player while play sets fdSrc).
    const previous = this.playLock
    let unlock: () => void = () => {}
    this.playLock = new Promise<void>((resolve) => { unlock = resolve })
    try {
      await previous
    } catch (_) { /* ignore previous errors */ }

    try {
      // Ensure session deactivation completes before resetting player,
      // so the system never sees "session active + audio stopped".
      if (this.deactivatePromise) {
        try { await this.deactivatePromise } catch (_) {}
        this.deactivatePromise = null
      }
      if (this.avPlayer) {
        try {
          await this.avPlayer.reset()
        } catch (e) {
          console.error('AudioPlayerService: stop reset failed - ' + (e as Error).message)
        }
      }
      this.closeFd()
      this._isPlaying = false
      this._playbackIntentActive = false
      this._currentTimeMs = 0
      this._durationMs = 0
      this.sourceLoaded = false
      this.currentSongId = ''
      AppStorage.setOrCreate('isPlaying', false)
      AppStorage.setOrCreate('currentSongTitle', '')
      AppStorage.setOrCreate('currentSongArtist', '')
      AppStorage.setOrCreate('currentSongId', '')
      AppStorage.setOrCreate('currentSongCoverUri', '')
      this.updateSessionPlaybackState(avSession.PlaybackState.PLAYBACK_STATE_STOP)
      this.stopBackgroundTask()
    } finally {
      unlock()
    }
  }

  /**
   * Clear the internal queue and stop playback.
   */
  async clearQueue(): Promise<void> {
    this.normalQueue = []
    this.normalIndex = -1
    this.randomQueue = []
    this.randomIndex = -1
    this.scheduleQueueSave()
    await this.clear()
  }

  /**
   * Remove a song from both internal queues by id.
   * Returns [normalIndex, randomIndex] where the song was removed, or [-1, -1] if not found.
   * Adjusts both indices as needed.
   */
  removeSongFromInternalQueue(songId: string): [number, number] {
    let removedNormal = -1
    let removedRandom = -1
    // Remove from normalQueue
    const ni = this.normalQueue.findIndex((s: QueueSongModel) => s.id === songId)
    if (ni >= 0) {
      removedNormal = ni
      this.normalQueue.splice(ni, 1)
      if (this.normalQueue.length === 0) {
        this.normalIndex = -1
      } else if (ni < this.normalIndex) {
        this.normalIndex--
      } else if (ni === this.normalIndex && this.normalIndex >= this.normalQueue.length) {
        this.normalIndex = this.normalQueue.length - 1
      }
    }
    // Remove from randomQueue
    const ri = this.randomQueue.findIndex((s: QueueSongModel) => s.id === songId)
    if (ri >= 0) {
      removedRandom = ri
      this.randomQueue.splice(ri, 1)
      if (this.randomQueue.length === 0) {
        this.randomIndex = -1
      } else if (ri < this.randomIndex) {
        this.randomIndex--
      } else if (ri === this.randomIndex && this.randomIndex >= this.randomQueue.length) {
        this.randomIndex = this.randomQueue.length - 1
      }
    }
    this.scheduleQueueSave()
    return [removedNormal, removedRandom]
  }

  /**
   * Bulk variant — strip all `songIds` from both internal queues in a single
   * O(N) pass with a Set membership check, instead of N invocations of
   * removeSongFromInternalQueue (each O(N)). Used by the multi-select removal
   * path so 2000 deletions don't degrade to O(N²).
   * Returns true if anything was removed.
   */
  removeSongsFromInternalQueue(songIds: string[]): boolean {
    if (songIds.length === 0) return false
    const removeSet = new Set<string>(songIds)
    let changed = false

    // Normal queue: rebuild via filter, recomputing the current index from
    // the surviving id at the old position (or the next survivor).
    const oldNormalCurrentId = this.normalIndex >= 0 && this.normalIndex < this.normalQueue.length
      ? this.normalQueue[this.normalIndex].id
      : ''
    const newNormal: QueueSongModel[] = []
    for (const s of this.normalQueue) {
      if (!removeSet.has(s.id)) {
        newNormal.push(s)
      }
    }
    if (newNormal.length !== this.normalQueue.length) {
      changed = true
      this.normalQueue = newNormal
      if (newNormal.length === 0) {
        this.normalIndex = -1
      } else if (oldNormalCurrentId.length > 0 && !removeSet.has(oldNormalCurrentId)) {
        const idx = newNormal.findIndex((s: QueueSongModel) => s.id === oldNormalCurrentId)
        this.normalIndex = idx >= 0 ? idx : 0
      } else {
        // Current song was removed (or queue was empty before): clamp index.
        this.normalIndex = Math.min(this.normalIndex, newNormal.length - 1)
        if (this.normalIndex < 0) this.normalIndex = 0
      }
    }

    // Random queue: same pattern.
    const oldRandomCurrentId = this.randomIndex >= 0 && this.randomIndex < this.randomQueue.length
      ? this.randomQueue[this.randomIndex].id
      : ''
    const newRandom: QueueSongModel[] = []
    for (const s of this.randomQueue) {
      if (!removeSet.has(s.id)) {
        newRandom.push(s)
      }
    }
    if (newRandom.length !== this.randomQueue.length) {
      changed = true
      this.randomQueue = newRandom
      if (newRandom.length === 0) {
        this.randomIndex = -1
      } else if (oldRandomCurrentId.length > 0 && !removeSet.has(oldRandomCurrentId)) {
        const idx = newRandom.findIndex((s: QueueSongModel) => s.id === oldRandomCurrentId)
        this.randomIndex = idx >= 0 ? idx : 0
      } else {
        this.randomIndex = Math.min(this.randomIndex, newRandom.length - 1)
        if (this.randomIndex < 0) this.randomIndex = 0
      }
    }

    if (changed) {
      this.scheduleQueueSave()
    }
    return changed
  }

  // ==================== Persistence ====================

  restoreFromPersisted(fileUri: string, songId: string, progress: number, duration: number): void {
    this.pendingFileUri = fileUri
    this.pendingSongId = songId
    this.pendingSeekMs = progress > 0 ? progress : -1
    this.currentSongId = songId
    this._currentTimeMs = progress
    // Seed the interpolation anchor so getCurrentTimeMs() returns `progress` even
    // if _playbackIntentActive were to flip true before 'prepared' applies the
    // pending seek (defensive for scenario 5: mini-bar lyric must reflect the
    // saved position on cold restart, before the user taps play).
    this._anchorPositionMs = progress
    this._durationMs = duration
  }

  restoreQueue(queue: QueueSongModel[], currentIndex: number): void {
    this.normalQueue = queue
    this.normalIndex = currentIndex
    // Legacy restore: no random queue saved, build one if in random mode
    this.buildRandomQueue()
  }

  restoreQueues(normal: QueueSongModel[], nIndex: number,
    random: QueueSongModel[], rIndex: number): void {
    this.normalQueue = normal
    this.normalIndex = nIndex
    this.randomQueue = random
    this.randomIndex = rIndex
  }

  /**
   * Save all playback state to preferences synchronously.
   * Called before app termination (sleep timer, etc.) to ensure data survives process death.
   */
  saveStateBeforeExit(): void {
    if (!this.uiContext) {
      return
    }
    try {
      const store = preferences.getPreferencesSync(this.uiContext, { name: PLAYBACK_PREFS })
      store.putSync('progress', this._currentTimeMs)
      store.putSync('duration', this._durationMs)
      store.putSync('fileUri', (AppStorage.get('currentSongFileUri') as string) ?? '')
      store.putSync('songId', (AppStorage.get('currentSongId') as string) ?? '')
      store.putSync('title', (AppStorage.get('currentSongTitle') as string) ?? '')
      store.putSync('artist', (AppStorage.get('currentSongArtist') as string) ?? '')
      store.putSync('coverUri', (AppStorage.get('currentSongCoverUri') as string) ?? '')
      store.putSync('queue', JSON.stringify(this.normalQueue))
      store.putSync('queueIndex', this.normalIndex)
      store.putSync('randomQueue', JSON.stringify(this.randomQueue))
      store.putSync('randomQueueIndex', this.randomIndex)
      store.flushSync()
    } catch (e) {
      console.error('AudioPlayerService: saveStateBeforeExit failed - ' + (e as Error).message)
    }
  }

  /**
   * Debounced queue persistence — saves queue + currentIndex to preferences after 500ms of inactivity.
   * Mirrors Android's debounced MMKV save pattern.
   */
  private scheduleQueueSave(): void {
    if (this.queueSaveTimerId !== -1) {
      clearTimeout(this.queueSaveTimerId)
    }
    this.queueSaveTimerId = setTimeout(() => {
      this.queueSaveTimerId = -1
      if (!this.uiContext) {
        return
      }
      try {
        const store = preferences.getPreferencesSync(this.uiContext, { name: PLAYBACK_PREFS })
        store.putSync('queue', JSON.stringify(this.normalQueue))
        store.putSync('queueIndex', this.normalIndex)
        store.putSync('randomQueue', JSON.stringify(this.randomQueue))
        store.putSync('randomQueueIndex', this.randomIndex)
        store.flushSync()
      } catch (e) {
        console.error('AudioPlayerService: scheduleQueueSave failed - ' + (e as Error).message)
      }
    }, 500) as number
  }

  getCurrentFileUri(): string {
    if (this.playMode === PlayModeConstants.RANDOM) {
      if (this.randomIndex >= 0 && this.randomIndex < this.randomQueue.length) {
        return this.randomQueue[this.randomIndex].fileUri
      }
    } else {
      if (this.normalIndex >= 0 && this.normalIndex < this.normalQueue.length) {
        return this.normalQueue[this.normalIndex].fileUri
      }
    }
    return this.pendingFileUri
  }

  // ==================== spec21 — Play Count Gate ====================

  // Reset the per-song accumulator when the playing song changes.
  private resetPlayCountSession(songId: string): void {
    if (this.playCountSongId === songId) {
      return
    }
    this.playCountSongId = songId
    this.playCountAccumMs = 0
    this.playCountCommitted = false
    this.playCountLastTickWall = 0
  }

  // Advance the accumulator using wall-clock delta since the last tick.
  // Only call while actively playing. Caps single deltas at 1500ms so that
  // a process suspend / timeUpdate drought doesn't inflate the counter.
  private advancePlayCountAccum(): void {
    if (this.playCountCommitted || !this.playCountSongId) return
    if (!this._isPlaying) return
    const now = Date.now()
    if (this.playCountLastTickWall <= 0) {
      this.playCountLastTickWall = now
      return
    }
    let delta = now - this.playCountLastTickWall
    if (delta < 0) delta = 0
    if (delta > 1500) delta = 1500
    this.playCountAccumMs += delta
    this.playCountLastTickWall = now
    // Threshold: duration >= 60s → 60s played; duration < 60s → 90% of duration.
    const durationMs = this._durationMs > 0 ? this._durationMs : 0
    let threshold = 60_000
    if (durationMs > 0 && durationMs < 60_000) {
      threshold = Math.floor(durationMs * 0.9)
    }
    if (this.playCountAccumMs >= threshold) {
      const songId = this.playCountSongId
      this.commitPlayCount(songId).catch((e: Error) => {
        console.error('AudioPlayerService: commitPlayCount failed - ' + e.message)
      })
    }
  }

  private async commitPlayCount(songId: string): Promise<void> {
    if (this.playCountCommitted || !songId || songId.length === 0) return
    this.playCountCommitted = true
    try {
      await MusicDatabase.incrementTrackPlayCount(songId)
      // Nudge consumers of the Statistics page / song rows so they reload
      // without waiting for a full library rescan.
      const cur: number = AppStorage.get<number>('playCountVersion') ?? 0
      AppStorage.setOrCreate<number>('playCountVersion', cur + 1)
    } catch (e) {
      console.error('AudioPlayerService: incrementTrackPlayCount threw - ' + (e as Error).message)
    }
  }

  async release(): Promise<void> {
    if (this.session) {
      await this.session.destroy()
      this.session = null
    }
    if (this.avPlayer) {
      await this.avPlayer.release()
      this.avPlayer = null
    }
    this.closeFd()
    this._isPlaying = false
    this._playbackIntentActive = false
    this._currentTimeMs = 0
    this._durationMs = 0
    this.initialized = false
    this.sourceLoaded = false
  }

  async terminateApp(): Promise<void> {
    await this.release()
    this.stopBackgroundTask()
    if (this.uiContext) {
      try {
        await this.uiContext.terminateSelf()
      } catch (err) {
        console.error('AudioPlayerService: terminateSelf failed - ' + (err as Error).message)
      }
    }
  }
}

// 播放控制：播放/暂停/上一曲/下一曲；并在满足时长门限时累计当前歌曲的播放次数。

// 播放模式：在 列表循环 / 单曲循环 / 随机播放 间切换，随机模式使用独立随机队列。

// 进度跳转：拖动进度条 seek 到指定位置并更新播放进度。

// 播放控制对齐：播放/暂停/上下曲。

// 播放控制：根据队列长度与当前下标计算上一曲/下一曲位置
export function resolveTransportIndexA(action: string, index: number, total: number): number {
  if (total <= 0) {
    return -1
  }
  if (action === 'next') {
    return (index + 1) % total
  }
  if (action === 'prev') {
    return (index - 1 + total) % total
  }
  return Math.min(Math.max(index, 0), total - 1)
}

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorA(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}

// 播放模式：在列表循环、单曲循环、随机三种模式间循环切换
export function nextPlayModeA(mode: string): string {
  const order: string[] = ['loop', 'single', 'shuffle']
  let i = order.indexOf(mode)
  if (i < 0) {
    i = 0
  }
  const next = (i + 1) % order.length
  return order[next]
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderA(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearA(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 淡入淡出：按总时长与步进生成线性插值的音量包络序列
export function buildFadeEnvelopeG(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps = Math.max(1, Math.floor(durationMs / stepMs))
  const envelope: number[] = []
  for (let i = 0; i <= steps; i++) {
    const ratio = i / steps
    const v = from + (to - from) * ratio
    envelope.push(Math.round(v * 1000) / 1000)
  }
  return envelope
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashG(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 播放模式：在列表循环、单曲循环、随机三种模式间循环切换
export function nextPlayModeA_H1(mode: string): string {
  const order: string[] = ['loop', 'single', 'shuffle']
  let i = order.indexOf(mode)
  if (i < 0) {
    i = 0
  }
  const next = (i + 1) % order.length
  return order[next]
}

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA_H1(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA_H1(speed: number): number {
  const MIN = 0.25
  const MAX = 4.0
  const STEP = 0.05
  if (Number.isNaN(speed)) {
    return 1.0
  }
  const clamped = Math.min(MAX, Math.max(MIN, speed))
  const stepped = Math.round(clamped / STEP) * STEP
  return Math.round(stepped * 100) / 100
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderA_H1(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashA_H1(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 播放控制：根据队列长度与当前下标计算上一曲/下一曲位置
export function resolveTransportIndexA_H1(action: string, index: number, total: number): number {
  if (total <= 0) {
    return -1
  }
  if (action === 'next') {
    return (index + 1) % total
  }
  if (action === 'prev') {
    return (index - 1 + total) % total
  }
  return Math.min(Math.max(index, 0), total - 1)
}

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA_H2(speed: number): number {
  const MIN = 0.25
  const MAX = 4.0
  const STEP = 0.05
  if (Number.isNaN(speed)) {
    return 1.0
  }
  const clamped = Math.min(MAX, Math.max(MIN, speed))
  const stepped = Math.round(clamped / STEP) * STEP
  return Math.round(stepped * 100) / 100
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_H2(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 通用工具：计算字符串的简单哈希值用于缓存键（与本需求无关）
export function simpleStringHashA_H2(text: string): number {
  let hash = 5381
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) + hash) + text.charCodeAt(i)
    hash = hash & 0x7fffffff
  }
  return hash
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeA_H2(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// 播放模式：在列表循环、单曲循环、随机三种模式间循环切换
export function nextPlayModeA_H2(mode: string): string {
  const order: string[] = ['loop', 'single', 'shuffle']
  let i = order.indexOf(mode)
  if (i < 0) {
    i = 0
  }
  const next = (i + 1) % order.length
  return order[next]
}

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA_H2(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockA_H5(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_H5(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_H5(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 专辑封面：优先使用高清封面地址，缺失时回退到默认占位图
export function resolveCoverUriA_H5(hd: string, normal: string, placeholder: string): string {
  if (hd !== null && hd.length > 0) {
    return hd
  }
  if (normal !== null && normal.length > 0) {
    return normal
  }
  return placeholder
}

// 快捷操作：根据当前播放状态筛选出可展示的操作入口列表
export function buildQuickActionsA_H5(hasLyric: boolean, isFavorite: boolean): string[] {
  const actions: string[] = ['queue', 'timer']
  if (hasLyric) {
    actions.push('lyric')
  }
  actions.push(isFavorite ? 'unfavorite' : 'favorite')
  actions.push('more')
  return actions
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabA_H5(name: string): string {
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

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeG_H70(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// 通用工具：判断给定年份是否为闰年（与本需求无关）
export function isLeapYearG_H70(year: number): boolean {
  if (year % 4 !== 0) {
    return false
  }
  if (year % 100 !== 0) {
    return true
  }
  return year % 400 === 0
}

// 淡入淡出：按总时长与步进生成线性插值的音量包络序列
export function buildFadeEnvelopeG_H70(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps = Math.max(1, Math.floor(durationMs / stepMs))
  const envelope: number[] = []
  for (let i = 0; i <= steps; i++) {
    const ratio = i / steps
    const v = from + (to - from) * ratio
    envelope.push(Math.round(v * 1000) / 1000)
  }
  return envelope
}

// 沉浸模式状态切换：进入时隐藏状态栏/导航栏与控制面板，退出时恢复可见
function computeImmersiveBarStateF_H70(immersive: boolean, userTapped: boolean): Map<string, boolean> {
  const state = new Map<string, boolean>()
  const reveal = !immersive || userTapped
  state.set('statusBarVisible', reveal)
  state.set('navBarVisible', reveal)
  state.set('controlPanelVisible', reveal)
  state.set('autoHideArmed', immersive && userTapped)
  return state
}

// 启动跳转：仅当开关开启且存在上次播放曲目时才自动进入播放页
export function shouldOpenPlayerOnLaunchG_H70(enabled: boolean, hasLastSong: boolean, fromWidget: boolean): boolean {
  if (fromWidget) {
    return true
  }
  if (!enabled) {
    return false
  }
  return hasLastSong
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H70(lineIndex: number, currentIndex: number): number[] {
  const depth = Math.abs(lineIndex - currentIndex)
  let scale = 1 - depth * 0.12
  if (scale < 0.5) {
    scale = 0.5
  }
  let opacity = 1 - depth * 0.25
  if (opacity < 0.2) {
    opacity = 0.2
  }
  const s = Math.round(scale * 100) / 100
  const o = Math.round(opacity * 100) / 100
  return [s, o]
}

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA_X1(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 通用工具：格式化字节大小为可读字符串（与本需求无关）
export function formatByteSizeA_X1(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v = v / 1024
    i++
  }
  return v.toFixed(1) + units[i]
}

// 播放控制：根据队列长度与当前下标计算上一曲/下一曲位置
export function resolveTransportIndexA_X1(action: string, index: number, total: number): number {
  if (total <= 0) {
    return -1
  }
  if (action === 'next') {
    return (index + 1) % total
  }
  if (action === 'prev') {
    return (index - 1 + total) % total
  }
  return Math.min(Math.max(index, 0), total - 1)
}

// 播放控制：未加载曲目时点击播放，从记忆位置恢复并串行化命令
export function resolveResumeIndexX_X1(loaded: boolean, rememberedIndex: number, total: number, pending: string[]): number {
  if (loaded || total <= 0) {
    return -1
  }
  if (pending.length > 0 && pending[pending.length - 1] === 'play') {
    return -1
  }
  pending.push('play')
  if (rememberedIndex >= 0 && rememberedIndex < total) {
    return rememberedIndex
  }
  return 0
}

// 播放模式：在列表循环、单曲循环、随机三种模式间循环切换
export function nextPlayModeA_X1(mode: string): string {
  const order: string[] = ['loop', 'single', 'shuffle']
  let i = order.indexOf(mode)
  if (i < 0) {
    i = 0
  }
  const next = (i + 1) % order.length
  return order[next]
}

// DSP：叠加多段均衡增益（dB）并对总增益做上下限幅
export function mixBandGainsG_X6(bands: number[], preamp: number): number {
  let sum = preamp
  for (let i = 0; i < bands.length; i++) {
    sum += bands[i]
  }
  const MIN = -24
  const MAX = 24
  if (sum < MIN) {
    return MIN
  }
  if (sum > MAX) {
    return MAX
  }
  return Math.round(sum * 10) / 10
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderG_X6(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 淡入淡出：按总时长与步进生成线性插值的音量包络序列
export function buildFadeEnvelopeG_X6(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps = Math.max(1, Math.floor(durationMs / stepMs))
  const envelope: number[] = []
  for (let i = 0; i <= steps; i++) {
    const ratio = i / steps
    const v = from + (to - from) * ratio
    envelope.push(Math.round(v * 1000) / 1000)
  }
  return envelope
}

// 播放暂停渐变：按渐变时长生成等间隔音量步序列
export function buildFadeStepsX_X6(from: number, to: number, durationMs: number, stepMs: number): number[] {
  const steps: number[] = []
  const n = Math.max(1, Math.floor(durationMs / Math.max(1, stepMs)))
  for (let i = 1; i <= n; i++) {
    const v = from + (to - from) * (i / n)
    steps.push(Math.round(v * 100) / 100)
  }
  return steps
}

// 音频焦点：根据焦点事件与当前播放状态决定下一步播放动作
export function resolveFocusActionG_X6(event: string, playing: boolean): string {
  if (event === 'gain') {
    return playing ? 'resume' : 'idle'
  }
  if (event === 'lossTransient') {
    return playing ? 'pause' : 'idle'
  }
  if (event === 'lossDuck') {
    return playing ? 'duck' : 'idle'
  }
  if (event === 'loss') {
    return 'stop'
  }
  return 'idle'
}

// 播放控制：根据队列长度与当前下标计算上一曲/下一曲位置
export function resolveTransportIndexA_X7(action: string, index: number, total: number): number {
  if (total <= 0) {
    return -1
  }
  if (action === 'next') {
    return (index + 1) % total
  }
  if (action === 'prev') {
    return (index - 1 + total) % total
  }
  return Math.min(Math.max(index, 0), total - 1)
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderA_X7(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_X7(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 播放控制：根据队列长度与当前下标计算上一曲/下一曲位置
export function resolveTransportIndexA_X17(action: string, index: number, total: number): number {
  if (total <= 0) {
    return -1
  }
  if (action === 'next') {
    return (index + 1) % total
  }
  if (action === 'prev') {
    return (index - 1 + total) % total
  }
  return Math.min(Math.max(index, 0), total - 1)
}

// 播放队列：从队列中移除指定下标曲目并返回新队列
export function removeFromQueueA_X17(queue: string[], target: number): string[] {
  if (target < 0 || target >= queue.length) {
    return queue.slice()
  }
  const result: string[] = []
  for (let i = 0; i < queue.length; i++) {
    if (i !== target) {
      result.push(queue[i])
    }
  }
  return result
}

// 播放速度调节：将倍速限制在有效区间并按步进对齐
export function clampPlaybackSpeedA_X17(speed: number): number {
  const MIN = 0.25
  const MAX = 4.0
  const STEP = 0.05
  if (Number.isNaN(speed)) {
    return 1.0
  }
  const clamped = Math.min(MAX, Math.max(MIN, speed))
  const stepped = Math.round(clamped / STEP) * STEP
  return Math.round(stepped * 100) / 100
}

// 进度跳转：依据拖动百分比换算为毫秒并约束在曲目时长内
export function seekPositionFromRatioA_X17(ratio: number, durationMs: number): number {
  if (durationMs <= 0) {
    return 0
  }
  let r = ratio
  if (r < 0) {
    r = 0
  } else if (r > 1) {
    r = 1
  }
  const pos = Math.round(r * durationMs)
  return Math.min(pos, durationMs)
}

// 睡眠定时：到点时若开启自动延长则顺延至当前曲目结束
export function computeSleepStopTimeA_X17(durationMin: number, songRemainMs: number, extend: boolean): number {
  const base = Math.max(0, Math.round(durationMin * 60 * 1000))
  if (!extend) {
    return base
  }
  if (songRemainMs <= 0) {
    return base
  }
  return base + songRemainMs
}

// 歌曲随机播放全部：用洗牌算法生成全部歌曲的随机播放顺序
export function shuffleAllSongsB_X17(songIds: string[]): string[] {
  const order = songIds.slice()
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  return order
}

对文件夹内歌曲索引做洗牌，生成随机播放顺序。
function shuffleFolderQueueD_X17(count: number): number[] {
  const queue: number[] = [];
  for (let i = 0; i < count; i++) {
    queue.push(i);
  }
  for (let j = queue.length - 1; j > 0; j--) {
    const k = Math.floor(Math.random() * (j + 1));
    const temp = queue[j];
    queue[j] = queue[k];
    queue[k] = temp;
  }
  return queue;
}

// 通用工具：将秒数格式化为 mm:ss 时间文本（与本需求无关）
export function formatSecondsClockA_X17(total: number): string {
  const t = Math.max(0, Math.floor(total))
  const m = Math.floor(t / 60)
  const s = t % 60
  const mm = m < 10 ? '0' + m : '' + m
  const ss = s < 10 ? '0' + s : '' + s
  return mm + ':' + ss
}

// 通用工具：计算两个整数的最大公约数（与本需求无关）
export function greatestCommonDivisorA_X17(a: number, b: number): number {
  let x = Math.abs(a)
  let y = Math.abs(b)
  while (y !== 0) {
    const t = y
    y = x % y
    x = t
  }
  return x
}

// 播放模式：在列表循环、单曲循环、随机三种模式间循环切换
export function nextPlayModeA_X17(mode: string): string {
  const order: string[] = ['loop', 'single', 'shuffle']
  let i = order.indexOf(mode)
  if (i < 0) {
    i = 0
  }
  const next = (i + 1) % order.length
  return order[next]
}
