// LyricsSettingsViewModel.ets
// ViewModel layer: provides observable data and business logic for LyricsSettingsPage (View).
// Bridges the Model layer with the View layer per MVVM architecture.
// The View binds to this ViewModel; user interactions invoke ViewModel methods,
// which in turn update the Model and notify the View of state changes.

import LyricsSettingsModel from '../model/LyricsSettingsModel'
import SwitcherRowModel from '../model/SwitcherRowModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import SettingsStore from '../model/SettingsStore'
import NotificationLyricController from '../model/NotificationLyricController'
import DesktopLyricsAVSessionController from '../model/DesktopLyricsAVSessionController'
import { promptAction } from '@kit.ArkUI'

@Observed
export default class LyricsSettingsViewModel {
  // Desktop lyrics toggle viewmodels (reusing existing SwitcherRowViewModel)
  @Track public desktopLyricsVM: SwitcherRowViewModel = new SwitcherRowViewModel()
  @Track public lockDesktopLyricsVM: SwitcherRowViewModel = new SwitcherRowViewModel()
  @Track public notificationBarLyricsVM: SwitcherRowViewModel = new SwitcherRowViewModel()

  // Status bar lyrics section
  @Track public systemLevelStatusBarLyrics: boolean = false
  @Track public statusBarLyricsNotShowTranslation: boolean = false

  // Xposed status bar lyrics section
  @Track public xposedStatusBarLyrics: boolean = false
  @Track public xposedLyricGetter: boolean = false

  // Dialog visibility
  @Track public showXposedLyricGetterDialog: boolean = false

  // Pro state
  @Track public isPro: boolean = false

  // Underlying model (data source)
  @Track private model: LyricsSettingsModel = new LyricsSettingsModel()

  // NOTE: The Settings page binds the 桌面歌词 / 锁定歌词 SuffixSwitches
  // directly to the AppStorage keys 'desktopLyrics' / 'lockDesktopLyrics'
  // via @StorageProp. The system overlay's lock and close gestures are
  // mirrored into those keys by DesktopLyricsAVSessionController
  // (stateCb writes 'lockDesktopLyrics'; handleExternalClose writes both),
  // so the switches re-read reliably without this VM having to fan out
  // listeners and rebuild SwitcherRowViewModels — the nested
  // @Observed/@Track → HdsListItemCard rebuild path proved unreliable
  // under API 23 strict mode (see git history of this file).

  constructor() {
    this.initFromModel(this.model)
  }

  // Initialize ViewModel from Model data
  initFromModel(model: LyricsSettingsModel): void {
    this.model = model
    this.isPro = model.isPro

    // Restore from AppStorage (auto-populated by PersistentStorage on startup)
    const persistedSysStatusBar = AppStorage.get<boolean>('systemLevelStatusBarLyrics')
    this.systemLevelStatusBarLyrics = persistedSysStatusBar !== undefined && persistedSysStatusBar !== null
      ? persistedSysStatusBar : model.systemLevelStatusBarLyrics

    const persistedNotShowTrans = AppStorage.get<boolean>('statusBarLyricsNotShowTranslation')
    this.statusBarLyricsNotShowTranslation = persistedNotShowTrans !== undefined && persistedNotShowTrans !== null
      ? persistedNotShowTrans : model.statusBarLyricsNotShowTranslation

    const persistedXposedStatus = AppStorage.get<boolean>('xposedStatusBarLyrics')
    this.xposedStatusBarLyrics = persistedXposedStatus !== undefined && persistedXposedStatus !== null
      ? persistedXposedStatus : model.xposedStatusBarLyrics

    const persistedXposedGetter = AppStorage.get<boolean>('xposedLyricGetter')
    this.xposedLyricGetter = persistedXposedGetter !== undefined && persistedXposedGetter !== null
      ? persistedXposedGetter : model.xposedLyricGetter

    // Restore switcher toggle states from AppStorage
    const persistedDesktop = AppStorage.get<boolean>('desktopLyrics')
    if (persistedDesktop !== undefined && persistedDesktop !== null) {
      model.desktopLyrics.isOn = persistedDesktop
    }
    const persistedLockDesktop = AppStorage.get<boolean>('lockDesktopLyrics')
    if (persistedLockDesktop !== undefined && persistedLockDesktop !== null) {
      model.lockDesktopLyrics.isOn = persistedLockDesktop
    }
    // spec26 scenario 7 — after a cold start with desktopLyrics persisted as
    // true, the lock toggle row must be interactive so the user can flip the
    // lock from the Settings page. The model's static default for
    // lockDesktopLyrics.isEnabled is `false`; mirror the master switch's
    // restored ON/OFF state into it before constructing the lock VM below so
    // SwitcherRowViewModel picks up the correct initial enable state.
    model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn
    const persistedNotifBar = AppStorage.get<boolean>('notificationBarLyrics')
    if (persistedNotifBar !== undefined && persistedNotifBar !== null) {
      model.notificationBarLyrics.isOn = persistedNotifBar
    }

    // Initialize desktop lyrics VM
    this.desktopLyricsVM = this.buildDesktopLyricsVM()

    // Initialize lock desktop lyrics VM
    this.lockDesktopLyricsVM = this.buildLockDesktopLyricsVM()

    // Initialize notification bar lyrics VM
    this.notificationBarLyricsVM = new SwitcherRowViewModel(
      new SwitcherRowModel(model.notificationBarLyrics.isOn, model.notificationBarLyrics.isEnabled,
        model.notificationBarLyrics.text),
      (val: boolean) => {
        this.onNotificationBarLyricsChanged(val)
      }
    )
  }

  // spec12 — Notification bar lyrics toggle handler. Persists the flag and
  // notifies the singleton NotificationLyricController so the AVSession title
  // flips between lyric line and song title in the same frame.
  onNotificationBarLyricsChanged(val: boolean): void {
    this.model.notificationBarLyrics.isOn = val
    SettingsStore.getInstance().save('notificationBarLyrics', val)
    NotificationLyricController.getInstance().onToggleChanged()
  }

  // --- Business logic methods (called by View) ---

  // Handle desktop lyrics toggle change. Drives the system AVSession
  // desktop-lyrics overlay through DesktopLyricsAVSessionController.
  // No SYSTEM_FLOAT_WINDOW permission required — the system overlay is
  // rendered by the OS smart bar, not as an application float window.
  async onDesktopLyricsChanged(val: boolean): Promise<void> {
    this.model.desktopLyrics.isOn = val
    this.model.lockDesktopLyrics.isEnabled = val
    // save() writes the value into AppStorage too, so the page's
    // @StorageProp('desktopLyrics') (master isCheck) and the lock row's
    // `enable: this.desktopLyricsOn` re-read in the same frame.
    SettingsStore.getInstance().save('desktopLyrics', val)
    try {
      await DesktopLyricsAVSessionController.getInstance().setEnabled(val)
    } catch (e) {
      console.warn('LyricsSettingsViewModel.setEnabled: ' + (e as Error).message)
    }
    promptAction.showToast({
      message: val
        ? $r('app.string.desktop_lyrics_opened')
        : $r('app.string.desktop_lyrics_closed')
    })
  }

  // Handle the 锁定歌词 toggle from the Settings page. Persists the flag
  // (save() mirrors it into AppStorage so the page's
  // @StorageProp('lockDesktopLyrics') re-reads) and drives the system
  // overlay lock state through the controller.
  setLockDesktopLyrics(val: boolean): void {
    this.model.lockDesktopLyrics.isOn = val
    SettingsStore.getInstance().save('lockDesktopLyrics', val)
    DesktopLyricsAVSessionController.getInstance().setLocked(val).catch((e: Error) => {
      console.warn('LyricsSettingsViewModel.setLocked: ' + e.message)
    })
    try {
      promptAction.showToast({
        message: val
          ? $r('app.string.desktop_lyrics_locked')
          : $r('app.string.desktop_lyrics_unlocked')
      })
    } catch (e) {
      console.warn('LyricsSettingsViewModel.setLocked toast: ' + (e as Error).message)
    }
  }

  // Construct the desktop-lyrics master SwitcherRowViewModel. The page no
  // longer reads its isOn/isEnabled for the switch (those bind to
  // @StorageProp('desktopLyrics')); it is kept for the row label text.
  private buildDesktopLyricsVM(): SwitcherRowViewModel {
    const m = this.model.desktopLyrics
    return new SwitcherRowViewModel(
      new SwitcherRowModel(m.isOn, m.isEnabled, m.text),
      (val: boolean) => {
        this.onDesktopLyricsChanged(val).catch((e: Error) => {
          console.warn('LyricsSettingsViewModel.onDesktopLyricsChanged: ' + e.message)
        })
      }
    )
  }

  // Construct the lock-desktop-lyrics SwitcherRowViewModel. As with the
  // master VM above, the page binds the switch to @StorageProp; this VM is
  // retained for the row label text and delegates its onChange to
  // setLockDesktopLyrics so the business logic lives in one place.
  private buildLockDesktopLyricsVM(): SwitcherRowViewModel {
    const m = this.model.lockDesktopLyrics
    return new SwitcherRowViewModel(
      new SwitcherRowModel(m.isOn, m.isEnabled, m.text),
      (val: boolean) => {
        this.setLockDesktopLyrics(val)
      }
    )
  }

  // Handle system-level status bar lyrics toggle
  onSystemLevelStatusBarLyricsChanged(val: boolean): void {
    this.systemLevelStatusBarLyrics = val
    this.model.systemLevelStatusBarLyrics = val
    SettingsStore.getInstance().save('systemLevelStatusBarLyrics', val)
    // TODO: Business logic - AppConfig.updateMeizuStatusBarLyrics
  }

  // Handle status bar lyrics not show translation toggle
  onStatusBarLyricsNotShowTranslationChanged(val: boolean): void {
    this.statusBarLyricsNotShowTranslation = val
    this.model.statusBarLyricsNotShowTranslation = val
    SettingsStore.getInstance().save('statusBarLyricsNotShowTranslation', val)
    // TODO: Business logic - AppConfig.statusBarLyricsNotShowTranslation
  }

  // Handle xposed status bar lyrics toggle
  onXposedStatusBarLyricsChanged(val: boolean): void {
    this.xposedStatusBarLyrics = val
    this.model.xposedStatusBarLyrics = val
    SettingsStore.getInstance().save('xposedStatusBarLyrics', val)
    if (!val) {
      // TODO: Business logic - MIUIStatusBarLyrics.stopLyrics()
    }
  }

  // Handle xposed lyric-getter toggle request (before confirmation)
  onXposedLyricGetterToggleRequested(val: boolean): void {
    if (val) {
      // Show confirmation dialog before enabling
      this.showXposedLyricGetterDialog = true
    } else {
      this.xposedLyricGetter = false
      this.model.xposedLyricGetter = false
      SettingsStore.getInstance().save('xposedLyricGetter', false)
      // TODO: Business logic - App.mmkv.encode(Config.XPOSED_LYRIC_GETTER, false)
      // TODO: Business logic - MIUIStatusBarLyrics.stopLyrics()
    }
  }

  // Confirm enabling Xposed Lyric-Getter (called from dialog confirm button)
  confirmXposedLyricGetter(): void {
    this.xposedLyricGetter = true
    this.model.xposedLyricGetter = true
    SettingsStore.getInstance().save('xposedLyricGetter', true)
    // Auto-disable system level status bar lyrics when enabling Xposed Lyric-Getter
    this.systemLevelStatusBarLyrics = false
    this.model.systemLevelStatusBarLyrics = false
    SettingsStore.getInstance().save('systemLevelStatusBarLyrics', false)
    this.showXposedLyricGetterDialog = false
    // TODO: Business logic - App.mmkv.encode(Config.XPOSED_LYRIC_GETTER, true)
    // TODO: Business logic - MusicController.meizuStatusBarLyric = false
  }

  // Cancel Xposed Lyric-Getter dialog
  cancelXposedLyricGetterDialog(): void {
    this.showXposedLyricGetterDialog = false
  }

  // Dismiss Xposed Lyric-Getter dialog (e.g., clicking overlay)
  dismissXposedLyricGetterDialog(): void {
    this.showXposedLyricGetterDialog = false
  }

  // Check if the floating window section is actionable (Pro only)
  canAccessFloatingWindow(): boolean {
    return this.isPro
  }

  // One-shot teardown invoked by the page's aboutToDisappear. The desktop
  // lyrics switches now sync through AppStorage @StorageProp bindings, so
  // there are no controller listeners to unregister; kept as a stable hook
  // for any future teardown the page needs.
  dispose(): void {
  }
}
