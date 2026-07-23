import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';
import { ScanningDataSource } from '../model/ScanningModel';
import ScanningDialogViewModel from '../viewmodel/ScanningDialogViewModel';
import { CoverCacheDb } from '../model/CoverCacheDb';
import { MusicDatabase } from '../model/MusicDatabase';
import AudioPlayerService from '../model/AudioPlayerService';
import { MiniLyricsController } from '../model/MiniLyricsController';
import { NotificationLyricController } from '../model/NotificationLyricController';
import { MediaCardCloseButtonController } from '../model/MediaCardCloseButtonController';
import { MediaCardDesktopLyricsButtonController } from '../model/MediaCardDesktopLyricsButtonController';
import FloatingWindowPermission from '../model/FloatingWindowPermission';
import { FloatingStatusBarLyricsController } from '../model/FloatingStatusBarLyricsController';
import { DesktopLyricsAVSessionController } from '../model/DesktopLyricsAVSessionController';

import { BlockedFolderDataSource } from '../model/BlockedFolderModel';

import { PlayModeConstants, QueueSongModel } from '../model/PlayQueueModel';
import ScreenWakeModel from '../model/ScreenWakeModel';
import SystemBarModel from '../model/SystemBarModel';
import SettingsStore from '../model/SettingsStore';
import { SaltPlayerProDataSource } from '../model/SaltPlayerProModel';
import { ImageKnife } from '@ohos/imageknifepro';


const DOMAIN = 0x0000;
const PLAYBACK_PREFS = 'playback_state';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    webview.WebviewController.initializeWebEngine()

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // PersistentStorage auto-persists these AppStorage keys to disk immediately on every change.
    // On restart, values are automatically restored from disk before any UI renders.
    // MUST be called BEFORE AppStorage.setOrCreate for the same keys.
    PersistentStorage.persistProp('currentSongTitle', '')
    PersistentStorage.persistProp('currentSongArtist', '')
    PersistentStorage.persistProp('currentSongId', '')
    PersistentStorage.persistProp('currentSongCoverUri', '')
    PersistentStorage.persistProp('currentSongFileUri', '')


    // Persist flowing light mode: 0=followUI, 1=light, 2=dark
    PersistentStorage.persistProp('flowingLightMode', 0)

    // Persist dynamic flowing light toggle (cover rotation control)
    PersistentStorage.persistProp('dynamicFlowingLight', true)

    // Persist play mode so it survives page re-entry and app restart
    PersistentStorage.persistProp('playMode', PlayModeConstants.CIRCLE)

    // Persist player keep screen on setting
    PersistentStorage.persistProp('playerKeepScreenOn', false)

    // Persist audio focus setting
    PersistentStorage.persistProp('audioFocusEnabled', true)
    console.info('[AudioFocus] EntryAbility: after persistProp, AppStorage value = ' +
      AppStorage.get<boolean>('audioFocusEnabled'))

    // Persist playback speed so it survives app restart
    PersistentStorage.persistProp('playbackSpeed', 1.0)

    // Detect initial system dark mode using ConfigurationConstant.ColorMode
    // (COLOR_MODE_DARK=0, COLOR_MODE_LIGHT=1) — unambiguous, unlike Environment.envProp.
    const initialColorMode = this.context.config?.colorMode
    const isSystemDark = initialColorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
    AppStorage.setOrCreate('isSystemDark', isSystemDark)

    // Lyrics interface settings — persisted so they survive app restart
    PersistentStorage.persistProp('lyricsTextSize', 20)
    PersistentStorage.persistProp('lyricsTextAlignCenter', false)
    PersistentStorage.persistProp('lyricsFontWeight', 600)
    // 0 = KaraokeCompatStrategy.CURRENT_LINE_ONLY (default)
    PersistentStorage.persistProp('lyricsKaraokeCompatStrategy', 0)
    // Spec13: lyrics-view blur toggle (off by default)
    PersistentStorage.persistProp('lyricsBlur', false)
    // Spec17: lyrics translation toggle (on by default)
    PersistentStorage.persistProp('lyricsOpenTranslation', true)
    // Spec15: hide lyrics screen control panel (Pro-gated)
    PersistentStorage.persistProp('lyricsHideControlPanel', false)
    // Spec15: global Pro state — established here so future Pro activation
    // flows have a single AppStorage key all gated screens can subscribe to.
    PersistentStorage.persistProp('isPro', false)

    // ---- 用户界面设置持久化 ----
    PersistentStorage.persistProp('selectedTheme', 0)
    PersistentStorage.persistProp('miniLyricsInPlayer', true)
    PersistentStorage.persistProp('immersionMode', false)
    PersistentStorage.persistProp('hideStatusBar', false)
    PersistentStorage.persistProp('hdCustomBackground', true)
    PersistentStorage.persistProp('displaySongCover', true)
    PersistentStorage.persistProp('displaySongFileName', false)
    PersistentStorage.persistProp('displayAddToPlayNext', true)
    PersistentStorage.persistProp('circlePlaybackCover', false)
    PersistentStorage.persistProp('irregularCoverAllowed', true)
    PersistentStorage.persistProp('playerScreenBgCover', '')
    PersistentStorage.persistProp('mainPageWallpaperPath', '')

    // Spec23: 显示关闭按钮 toggle (Notification 页) — defaults to ON
    PersistentStorage.persistProp('showCloseButton', true)

    // Spec24: 显示桌面歌词按钮 toggle (Notification 页) — defaults to ON
    PersistentStorage.persistProp('showDesktopLyricsButton', true)

    // Spec9: auto-open playback screen on app launch (实验室 toggle)
    PersistentStorage.persistProp('autoOpenPlaybackScreen', false)

    // Spec16: 3D lyrics effect (Pro-gated, 实验室 toggle)
    PersistentStorage.persistProp('lyricsUIEffect3D', false)

    // Spec10: auto-resume playback on cold launch (启动与后台 toggle)
    PersistentStorage.persistProp('autoPlayback', false)

    // ---- 歌词界面设置持久化 ----
    PersistentStorage.persistProp('desktopLyrics', false)
    PersistentStorage.persistProp('lockDesktopLyrics', false)
    PersistentStorage.persistProp('notificationBarLyrics', false)
    PersistentStorage.persistProp('systemLevelStatusBarLyrics', false)
    PersistentStorage.persistProp('statusBarLyricsNotShowTranslation', false)
    PersistentStorage.persistProp('xposedStatusBarLyrics', false)
    PersistentStorage.persistProp('xposedLyricGetter', false)
    PersistentStorage.persistProp('floatingWindowStatusBarLyrics', false)

    // Spec25: 悬浮窗状态栏歌词 sub-settings — defaults match the spec scenario 2:
    // 0% horizontal, 0 px vertical, 150 dp width, 14 dp font, 0xFF0470E6 blue,
    // left-aligned text, translation visible, no hide-on-player.
    PersistentStorage.persistProp('floatingWindowSbLrLeftRightPercent', 0)
    PersistentStorage.persistProp('floatingWindowSbLrUpDownPx', 0)
    PersistentStorage.persistProp('floatingWindowSbLrWidthDp', 150)
    PersistentStorage.persistProp('floatingWindowSbLrFontSizeDp', 14)
    PersistentStorage.persistProp('floatingWindowSbLrColor', 0xFF0470E6)
    PersistentStorage.persistProp('floatingWindowSbLrCenterAlign', false)
    PersistentStorage.persistProp('floatingWindowSbLrHideOnPlayer', false)

    // ---- 音频输出设置持久化 ----
    PersistentStorage.persistProp('volumeBalanceEnabled', true)
    PersistentStorage.persistProp('fadeInOutEnabled', true)
    PersistentStorage.persistProp('selectedOutputMode', 'audiotrack')
    PersistentStorage.persistProp('audioOutputFreq', 48000)
    PersistentStorage.persistProp('changeDeviceFreqEnabled', false)
    PersistentStorage.persistProp('compressorEnabled', false)
    // Spec14: resampling quality index for the 音频信息 dialog SRC 品质 row.
    // Default 2 = "16 POINT SINC" per RESAMPLING_QUALITY_LABELS.
    PersistentStorage.persistProp('resamplingQuality', 2)
    // Spec14: DSP section of the 音频信息 dialog — SALT PLAYER AUDIOFX V4 preset
    // name and V3 reverb toggle state, persisted from FxActivityViewModel.
    PersistentStorage.persistProp('fxPresetName', '')
    PersistentStorage.persistProp('v3ReverbEnabled', false)

    // ---- 从 Preferences 恢复设置（PersistentStorage 可能不可靠） ----
    // 初始化 SettingsStore 单例，供 ViewModel 在设置变更时立即写盘
    const ss = SettingsStore.getInstance()
    ss.init(this.context)
    // 用户界面设置
    AppStorage.setOrCreate('selectedTheme', ss.get('selectedTheme', 0) as number)
    AppStorage.setOrCreate('miniLyricsInPlayer', ss.get('miniLyricsInPlayer', true) as boolean)
    AppStorage.setOrCreate('immersionMode', ss.get('immersionMode', false) as boolean)
    AppStorage.setOrCreate('hideStatusBar', ss.get('hideStatusBar', false) as boolean)
    AppStorage.setOrCreate('hdCustomBackground', ss.get('hdCustomBackground', true) as boolean)
    AppStorage.setOrCreate('displaySongCover', ss.get('displaySongCover', true) as boolean)
    AppStorage.setOrCreate('displaySongFileName', ss.get('displaySongFileName', false) as boolean)
    AppStorage.setOrCreate('displayAddToPlayNext', ss.get('displayAddToPlayNext', true) as boolean)
    AppStorage.setOrCreate('circlePlaybackCover', ss.get('circlePlaybackCover', false) as boolean)
    AppStorage.setOrCreate('irregularCoverAllowed', ss.get('irregularCoverAllowed', true) as boolean)
    AppStorage.setOrCreate('playerScreenBgCover', ss.get('playerScreenBgCover', '') as string)
    AppStorage.setOrCreate('mainPageWallpaperPath', ss.get('mainPageWallpaperPath', '') as string)
    // Spec23: 显示关闭按钮 toggle — hydrate from Preferences so the toggle UI
    // reads the persisted value on the first frame.
    AppStorage.setOrCreate('showCloseButton', ss.get('showCloseButton', true) as boolean)
    // Spec24: 显示桌面歌词按钮 toggle — hydrate from Preferences so the toggle UI
    // reads the persisted value on the first frame.
    AppStorage.setOrCreate('showDesktopLyricsButton',
      ss.get('showDesktopLyricsButton', true) as boolean)
    // Spec9: auto-open playback screen flag (实验室)
    AppStorage.setOrCreate('autoOpenPlaybackScreen',
      ss.get('autoOpenPlaybackScreen', false) as boolean)
    // Spec16: 3D lyrics effect flag (实验室)
    AppStorage.setOrCreate('lyricsUIEffect3D',
      ss.get('lyricsUIEffect3D', false) as boolean)
    // Spec10: auto-resume playback flag (启动与后台)
    AppStorage.setOrCreate('autoPlayback', ss.get('autoPlayback', false) as boolean)
    // 歌词界面设置
    AppStorage.setOrCreate('desktopLyrics', ss.get('desktopLyrics', false) as boolean)
    AppStorage.setOrCreate('lockDesktopLyrics', ss.get('lockDesktopLyrics', false) as boolean)
    AppStorage.setOrCreate('notificationBarLyrics', ss.get('notificationBarLyrics', false) as boolean)
    AppStorage.setOrCreate('systemLevelStatusBarLyrics', ss.get('systemLevelStatusBarLyrics', false) as boolean)
    AppStorage.setOrCreate('statusBarLyricsNotShowTranslation',
      ss.get('statusBarLyricsNotShowTranslation', false) as boolean)
    AppStorage.setOrCreate('xposedStatusBarLyrics', ss.get('xposedStatusBarLyrics', false) as boolean)
    AppStorage.setOrCreate('xposedLyricGetter', ss.get('xposedLyricGetter', false) as boolean)
    AppStorage.setOrCreate('floatingWindowStatusBarLyrics',
      ss.get('floatingWindowStatusBarLyrics', false) as boolean)
    // Spec25: 悬浮窗状态栏歌词 sub-settings — hydrate the persisted geometry/style
    // so the float-window page reads correct values on the first frame.
    AppStorage.setOrCreate('floatingWindowSbLrLeftRightPercent',
      ss.get('floatingWindowSbLrLeftRightPercent', 0) as number)
    AppStorage.setOrCreate('floatingWindowSbLrUpDownPx',
      ss.get('floatingWindowSbLrUpDownPx', 0) as number)
    AppStorage.setOrCreate('floatingWindowSbLrWidthDp',
      ss.get('floatingWindowSbLrWidthDp', 150) as number)
    AppStorage.setOrCreate('floatingWindowSbLrFontSizeDp',
      ss.get('floatingWindowSbLrFontSizeDp', 14) as number)
    AppStorage.setOrCreate('floatingWindowSbLrColor',
      ss.get('floatingWindowSbLrColor', 0xFF0470E6) as number)
    AppStorage.setOrCreate('floatingWindowSbLrCenterAlign',
      ss.get('floatingWindowSbLrCenterAlign', false) as boolean)
    AppStorage.setOrCreate('floatingWindowSbLrHideOnPlayer',
      ss.get('floatingWindowSbLrHideOnPlayer', false) as boolean)
    // 音频输出设置
    AppStorage.setOrCreate('volumeBalanceEnabled', ss.get('volumeBalanceEnabled', true) as boolean)
    AppStorage.setOrCreate('fadeInOutEnabled', ss.get('fadeInOutEnabled', true) as boolean)
    AppStorage.setOrCreate('selectedOutputMode', ss.get('selectedOutputMode', 'audiotrack') as string)
    AppStorage.setOrCreate('audioOutputFreq', ss.get('audioOutputFreq', 48000) as number)
    AppStorage.setOrCreate('changeDeviceFreqEnabled', ss.get('changeDeviceFreqEnabled', false) as boolean)
    AppStorage.setOrCreate('compressorEnabled', ss.get('compressorEnabled', false) as boolean)
    AppStorage.setOrCreate('resamplingQuality', ss.get('resamplingQuality', 2) as number)
    // ---- 列表与扫描设置持久化 ----
    AppStorage.setOrCreate('songLazySort', ss.get('songLazySort', 1) as number) // 1 = SongLazySort.TITLE
    AppStorage.setOrCreate('folderSongLazySort', ss.get('folderSongLazySort', 1) as number) // 1 = SongLazySort.TITLE
    // 15 = SongLazySort.PLAYLIST_ADD_TIME — spec4 Scene 2: new playlists default
    // to "added to playlist, newest first" ordering.
    AppStorage.setOrCreate('playlistSongLazySort', ss.get('playlistSongLazySort', 15) as number)
    AppStorage.setOrCreate('albumSortType', ss.get('albumSortType', 0) as number) // 0 = AlbumSortType.TITLE
    AppStorage.setOrCreate('albumMinColumns', ss.get('albumMinColumns', 2) as number)
    AppStorage.setOrCreate('doNotScanBelow60s', ss.get('doNotScanBelow60s', false) as boolean)
    // 已有的持久化设置
    AppStorage.setOrCreate('flowingLightMode', ss.get('flowingLightMode', 0) as number)
    AppStorage.setOrCreate('dynamicFlowingLight', ss.get('dynamicFlowingLight', true) as boolean)
    AppStorage.setOrCreate('playerKeepScreenOn', ss.get('playerKeepScreenOn', false) as boolean)
    AppStorage.setOrCreate('audioFocusEnabled', ss.get('audioFocusEnabled', true) as boolean)
    AppStorage.setOrCreate('playbackSpeed', ss.get('playbackSpeed', 1.0) as number)
    AppStorage.setOrCreate('playMode', ss.get('playMode', PlayModeConstants.CIRCLE) as string)
    AppStorage.setOrCreate('lyricsTextSize', ss.get('lyricsTextSize', 20) as number)
    AppStorage.setOrCreate('lyricsTextAlignCenter', ss.get('lyricsTextAlignCenter', false) as boolean)
    AppStorage.setOrCreate('lyricsFontWeight', ss.get('lyricsFontWeight', 600) as number)
    AppStorage.setOrCreate('lyricsKaraokeCompatStrategy',
      ss.get('lyricsKaraokeCompatStrategy', 0) as number)
    AppStorage.setOrCreate('lyricsBlur', ss.get('lyricsBlur', false) as boolean)
    // Spec17: lyrics translation toggle (defaults to true so existing users
    // who never tapped the button still see translations).
    AppStorage.setOrCreate('lyricsOpenTranslation',
      ss.get('lyricsOpenTranslation', true) as boolean)
    // Spec15: hydrate hide-control-panel + global Pro flag from Preferences so
    // PlayerPage @StorageProp sees the correct values before the first render.
    AppStorage.setOrCreate('lyricsHideControlPanel',
      ss.get('lyricsHideControlPanel', false) as boolean)
    AppStorage.setOrCreate('isPro', ss.get('isPro', false) as boolean)

    hilog.info(DOMAIN, 'Restore', 'Settings restored from Preferences, selectedTheme=%{public}d',
      ss.get('selectedTheme', 0) as number)

    // 恢复持久化的主题到系统 ColorMode（避免重启后主题闪烁）
    const restoredTheme = AppStorage.get<number>('selectedTheme') ?? 0
    if (restoredTheme === 1) {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
    } else if (restoredTheme === 2) {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK)
    }

    // isPlaying always starts as false (never persist — playback stops on exit)
    AppStorage.setOrCreate('isPlaying', false)
    // Playback error message (empty = no error)
    AppStorage.setOrCreate('playbackError', '')

    // Player page visibility (not persisted — always starts hidden)
    AppStorage.setOrCreate('playerPageVisible', false)

    // Sleep timer state (not persisted — timer resets on app restart)
    AppStorage.setOrCreate('sleepTimerState', 0)
    AppStorage.setOrCreate('sleepTimerRemainingMs', 0)
    AppStorage.setOrCreate('sleepTimerIsExtendPhase', false)

    // Load progress/duration/fileUri from preferences (backup for PersistentStorage)
    let savedProgress = 0
    let savedDuration = 0
    let prefsFileUri = ''
    let prefsSongId = ''
    let prefsTitle = ''
    let prefsArtist = ''
    let prefsCoverUri = ''
    let savedQueueJson = ''
    let savedQueueIndex = -1
    let savedRandomQueueJson = ''
    let savedRandomQueueIndex = -1
    try {
      const store = preferences.getPreferencesSync(this.context, { name: PLAYBACK_PREFS })
      savedProgress = store.getSync('progress', 0) as number
      savedDuration = store.getSync('duration', 0) as number
      prefsFileUri = store.getSync('fileUri', '') as string
      prefsSongId = store.getSync('songId', '') as string
      prefsTitle = store.getSync('title', '') as string
      prefsArtist = store.getSync('artist', '') as string
      prefsCoverUri = store.getSync('coverUri', '') as string
      savedQueueJson = store.getSync('queue', '') as string
      savedQueueIndex = store.getSync('queueIndex', -1) as number
      savedRandomQueueJson = store.getSync('randomQueue', '') as string
      savedRandomQueueIndex = store.getSync('randomQueueIndex', -1) as number
    } catch (_e) {
      // first launch or read failure
    }

    // Prefer Preferences (sync-flushed) over PersistentStorage (async) so that
    // a song switch survived via flushSync is not overwritten by stale data.
    let savedFileUri = (prefsFileUri || (AppStorage.get('currentSongFileUri') as string)) ?? ''
    let savedSongId = (prefsSongId || (AppStorage.get('currentSongId') as string)) ?? ''
    if (prefsFileUri) {
      AppStorage.setOrCreate('currentSongFileUri', prefsFileUri)
    }
    if (prefsSongId) {
      AppStorage.setOrCreate('currentSongId', prefsSongId)
      AppStorage.setOrCreate('currentSongTitle', (prefsTitle || (AppStorage.get('currentSongTitle') as string)) ?? '')
      AppStorage.setOrCreate('currentSongArtist', (prefsArtist || (AppStorage.get('currentSongArtist') as string)) ?? '')
      AppStorage.setOrCreate('currentSongCoverUri', (prefsCoverUri || (AppStorage.get('currentSongCoverUri') as string)) ?? '')
    }

    hilog.info(DOMAIN, 'Restore', 'songId=%{public}s fileUri=%{public}s progress=%{public}d',
      savedSongId, savedFileUri.length > 0 ? 'yes' : 'no', savedProgress)

    // Restore AudioPlayerService pending state so play button can resume
    if (savedFileUri.length > 0 && savedSongId.length > 0) {
      AudioPlayerService.getInstance().restoreFromPersisted(
        savedFileUri, savedSongId, savedProgress, savedDuration
      )
    }

    // Restore play queue from preferences (dual queue: normal + random)
    if (savedQueueJson.length > 0) {
      try {
        const parseQueue = (json: string): QueueSongModel[] => {
          const arr: object[] = JSON.parse(json) as object[]
          return arr.map((item: object): QueueSongModel => {
            const obj = item as Record<string, string>
            return new QueueSongModel(
              obj['id'] ?? '', obj['title'] ?? '', obj['artist'] ?? '',
              obj['album'] ?? '', obj['subTitle'] ?? '', obj['fileUri'] ?? '', obj['coverUri'] ?? ''
            )
          })
        }
        const restoredNormalQueue = parseQueue(savedQueueJson)
        if (savedRandomQueueJson.length > 0) {
          // Full dual queue restore
          const restoredRandomQueue = parseQueue(savedRandomQueueJson)
          AudioPlayerService.getInstance().restoreQueues(
            restoredNormalQueue, savedQueueIndex,
            restoredRandomQueue, savedRandomQueueIndex
          )
          hilog.info(DOMAIN, 'Restore', 'dual queue restored: normal=%{public}d random=%{public}d',
            restoredNormalQueue.length, restoredRandomQueue.length)
        } else {
          // Legacy restore (no random queue saved)
          AudioPlayerService.getInstance().restoreQueue(restoredNormalQueue, savedQueueIndex)
          hilog.info(DOMAIN, 'Restore', 'queue restored (legacy): %{public}d songs, index=%{public}d',
            restoredNormalQueue.length, savedQueueIndex)
        }
      } catch (_e) {
        hilog.error(DOMAIN, 'Restore', 'Failed to restore queue from preferences')
      }
    }

    // Restore persisted play mode to service without reshuffling
    // (the random queue was already restored from preferences above)
    const savedPlayMode = (AppStorage.get('playMode') as string) ?? PlayModeConstants.CIRCLE
    AudioPlayerService.getInstance().restorePlayMode(savedPlayMode)

    // Provide UIAbility context for background audio task management
    AudioPlayerService.getInstance().initContext(this.context)

    // Initialize mini player lyrics controller AFTER restoreFromPersisted has
    // seeded AudioPlayerService with the last song's fileUri/progress. This
    // triggers an initial lyric load for the restored song (spec8 scenario 5)
    // and starts the 200ms tick that advances the subtitle line.
    MiniLyricsController.getInstance().init()

    // spec12 — Notification bar lyrics controller. Initialized AFTER
    // MiniLyricsController so its addListener call receives the current
    // (songId, line, hasLyrics) immediately and pushes the merged title to
    // AVSession before the very first 'prepared' / 'playing' state runs.
    NotificationLyricController.getInstance().init()

    // spec23 — Mirror the "显示关闭按钮" toggle into the AVSession extras +
    // custom session event stream. Initialized AFTER AudioPlayerService.initContext
    // so the session has already been created.
    MediaCardCloseButtonController.getInstance().init()

    // spec24 — Mirror the "显示桌面歌词按钮" toggle and the per-song
    // card-lyrics-active flag into AVSession extras + custom session event stream.
    // Initialized AFTER MiniLyricsController so its addListener call receives the
    // current (songId, line, hasLyrics) immediately and pushes a consistent
    // initial state.
    MediaCardDesktopLyricsButtonController.getInstance().init()

    // spec25 — Floating status-bar lyrics controller. Initialized AFTER
    // MiniLyricsController so the lyric stream is alive, AFTER
    // AudioPlayerService.initContext so it can read the UIAbility context, and
    // AFTER persistence hydration above so it sees the persisted geometry on
    // scenario 18 cold-start auto-show.
    FloatingStatusBarLyricsController.getInstance().init(this.context)

    // Desktop lyrics — official AVSession-based path. Runs AFTER
    // MiniLyricsController.init() so the lyrics-loaded listener sees
    // the restored song's LRC, and AFTER AudioPlayerService.initContext()
    // so the session-instance APIs are reachable.
    DesktopLyricsAVSessionController.getInstance().init()

    // Restore persisted playback speed
    const savedSpeed = AppStorage.get<number>('playbackSpeed') ?? 1.0
    if (savedSpeed !== 1.0) {
      AudioPlayerService.getInstance().setSpeed(savedSpeed)
    }

    // Initialize cover art RDB cache
    CoverCacheDb.init(this.context)
    CoverCacheDb.initCoverDir(this.context)
    ImageKnife.getInstance().initFileCache(this.context, 256, 256 * 1024 * 1024)
    CoverCacheDb.countCovers().then((count: number) => {
      hilog.info(DOMAIN, 'CoverDiag', 'RDB cover count on startup: %{public}d', count)
    })

    // Initialize music library database
    MusicDatabase.init(this.context)

    // Initialize blocked folders from persistent storage
    BlockedFolderDataSource.initFromContext(this.context)

    // Recover from a previously-interrupted scan: if the app was killed (or
    // the dialog dismissed) before the scan persisted its results, the URIs
    // it had already authorized are revoked here so those songs return to
    // the unauthorized state, matching the pre-scan situation.
    ScanningDataSource.recoverInterruptedScan(this.context).catch((e: Error) => {
      hilog.warn(DOMAIN, 'ScanRecover', 'recoverInterruptedScan failed: %{public}s', e.message)
    })

    // Migrate old Preferences data to RDB (one-time), then load from RDB
    ScanningDataSource.migrateFromPreferences(this.context).then(() => {
      return ScanningDataSource.loadFromDatabase()
    }).then(() => {
      // Re-activate persisted URI permissions so file access works after restart
      ScanningDataSource.activateStoredPermissions()
      // Notify UI that songs are loaded
      const currentVersion: number = AppStorage.get<number>('scanVersion') || 0
      AppStorage.setOrCreate<number>('scanVersion', currentVersion + 1)
    })

    // ---- IAP: startup check for non-consumable purchases (restore Pro status) ----
    // Query current entitlements on every launch to handle reinstalls or unfinished purchases.
    SaltPlayerProDataSource.initContext(this.context)
    SaltPlayerProDataSource.queryPurchases().then((hasPro) => {
      if (hasPro) {
        hilog.info(DOMAIN, 'IAP', 'Pro restored from IAP on startup')
      }
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, 'IAP', 'Startup queryPurchases failed: %{public}s', e.message)
    })

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // Safety flush: if the process is killed before onBackground() runs,
    // ensure any pending settings writes reach disk.
    SettingsStore.getInstance().flush()
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/main/MainPage', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // Initialize ScreenWakeModel with the main window for keep-screen-on control
      try {
        const mainWindow = windowStage.getMainWindowSync();
        ScreenWakeModel.getInstance().initWindow(mainWindow);
        SystemBarModel.getInstance().initWindow(mainWindow);
        // Honor persisted immersionMode / hideStatusBar flags on app launch so
        // the initial system bar state is correct before the first page renders.
        SystemBarModel.getInstance().reconcileStatusBarVisibility();
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'Failed to init ScreenWakeModel/SystemBarModel: %{public}s', JSON.stringify(e));
      }
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    // App is closing — cancel any scan still in flight so its in-memory grant
    // list gets revoked. The pending-grants record persisted to preferences
    // is the safety net if this teardown does not finish before the process
    // is killed; recoverInterruptedScan() in onCreate cleans it up next launch.
    try {
      ScanningDialogViewModel.getInstance().cancelScanning()
    } catch (e) {
      hilog.warn(DOMAIN, 'ScanCancel', 'cancelScanning on destroy failed: %{public}s',
        (e as Error).message)
    }

    // spec25 — Tear down the floating status-bar lyrics window so its system
    // surface does not leak across UIAbility restarts.
    try {
      FloatingStatusBarLyricsController.getInstance().destroy()
    } catch (e) {
      hilog.warn(DOMAIN, 'FloatingSbLr', 'destroy failed: %{public}s',
        (e as Error).message)
    }

    // Desktop lyrics (AVSession path) — disable the system overlay and
    // clear the AVMetadata.lyric override so the system smart bar stops
    // rendering after the UIAbility is torn down.
    try {
      DesktopLyricsAVSessionController.getInstance().destroy()
    } catch (e) {
      hilog.warn(DOMAIN, 'DesktopLyrics', 'destroy failed: %{public}s',
        (e as Error).message)
    }
  }

  // Called by the system when configuration changes (e.g. light↔dark theme switch).
  // Updates AppStorage so @StorageLink('isSystemDark') in pages reacts immediately.
  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      const isSystemDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
      hilog.info(DOMAIN, 'testTag', 'onConfigurationUpdate: colorMode=%{public}d isSystemDark=%{public}s',
        newConfig.colorMode, isSystemDark.toString())
      AppStorage.setOrCreate('isSystemDark', isSystemDark)
      // Update system bar icon colors to match the new theme.
      // The player page manages its own bar colors; this only affects pages that
      // follow the system theme (main page).
      SystemBarModel.getInstance().restoreToAppTheme()
    }
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // Reconcile AVPlayer position with wall-clock interpolation.
    // In muted background the system may stop advancing AVPlayer frames while
    // the live window keeps interpolating forward — seeking here closes the gap.
    AudioPlayerService.getInstance().reconcileOnForeground()
    // Bump timestamp so PlayerPage @Watch fires immediately and refreshes
    // progress without waiting for the 200ms timer tick.
    AppStorage.setOrCreate('foregroundTimestamp', new Date().getTime())
    // spec24 scenario 8 step 5: if the user was routed to the system overlay
    // permission settings, re-check on return so the toggle flips back to ON
    // automatically when the user granted the permission while away.
    FloatingWindowPermission.reprobeOnForeground().catch((e: Error) => {
      hilog.warn(DOMAIN, 'FloatingWindowPerm',
        'reprobeOnForeground failed: %{public}s', e.message)
    })
  }

  onBackground(): void {
    // Save playback state to preferences as backup (in case PersistentStorage fails)
    try {
      const service = AudioPlayerService.getInstance()
      const store = preferences.getPreferencesSync(this.context, { name: PLAYBACK_PREFS })
      store.putSync('progress', service.getCurrentTimeMs())
      store.putSync('duration', service.getDurationMs())
      store.putSync('fileUri', (AppStorage.get('currentSongFileUri') as string) ?? '')
      store.putSync('songId', (AppStorage.get('currentSongId') as string) ?? '')
      store.putSync('title', (AppStorage.get('currentSongTitle') as string) ?? '')
      store.putSync('artist', (AppStorage.get('currentSongArtist') as string) ?? '')
      store.putSync('coverUri', (AppStorage.get('currentSongCoverUri') as string) ?? '')
      // Persist dual play queue so it survives app restart
      store.putSync('queue', JSON.stringify(service.getNormalQueue()))
      store.putSync('queueIndex', service.getNormalIndex())
      store.putSync('randomQueue', JSON.stringify(service.getRandomQueue()))
      store.putSync('randomQueueIndex', service.getRandomIndex())
      store.flushSync()
    } catch (_e) {
      // save failed
    }

    // Flush all pending settings writes to disk.
    // SettingsStore.save() (called by ViewModels) writes to the Preferences memory cache;
    // this single flushSync() ensures everything reaches disk before the app is killed.
    SettingsStore.getInstance().flush()

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}

// 应用初始化与状态恢复：恢复播放队列与设置。
