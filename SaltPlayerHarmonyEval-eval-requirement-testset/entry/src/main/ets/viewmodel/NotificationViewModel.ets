// NotificationViewModel.ets
// ViewModel layer: provides observable data and business logic for the NotificationPage (View).
// Bridges the NotificationModel (data) and NotificationPage (UI) per MVVM architecture.
// View calls ViewModel methods to handle user interactions; ViewModel updates Model for persistence.

import NotificationModel from '../model/NotificationModel'
import SwitcherRowModel from '../model/SwitcherRowModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import MediaCardCloseButtonController from '../model/MediaCardCloseButtonController'
import MediaCardDesktopLyricsButtonController from '../model/MediaCardDesktopLyricsButtonController'
import FloatingWindowPermission, { FloatingWindowGrantListener } from '../model/FloatingWindowPermission'
import { promptAction } from '@kit.ArkUI'

@Observed
export default class NotificationViewModel {
  // ---- Toggle ViewModels for the two switcher rows ----
  @Track public showDesktopLyricsButtonVM: SwitcherRowViewModel = new SwitcherRowViewModel()
  @Track public showCloseButtonVM: SwitcherRowViewModel = new SwitcherRowViewModel()

  // ---- Dialog state ----
  @Track public showAlsoCloseDesktopLyricsDialog: boolean = false

  // ---- Desktop lyrics feature state ----
  @Track public desktopLyricsEnabled: boolean = false

  // ---- Model (data source) ----
  @Track private model: NotificationModel = new NotificationModel()

  // Listener bound once in the constructor; removed by a future destroy() if
  // the ViewModel ever gets one. Kept as a field so the reference is stable
  // across removeGrantListener() calls.
  private grantListener: FloatingWindowGrantListener = (): void => {
    this.onFloatingWindowPermissionGranted()
  }

  constructor() {
    this.loadFromModel()
    // Scenario 8 step 5: "返回应用后开关自动切换为开启状态". When the user came
    // back from system settings with the permission newly granted, flip the
    // toggle row back to ON and re-fire the persistence + controller wiring
    // without re-routing them through ensurePermission() (which would jump
    // back to settings again).
    FloatingWindowPermission.addGrantListener(this.grantListener)
  }

  // Initialize ViewModel from Model data
  loadFromModel(): void {
    this.model.loadSettings()

    // Initialize "Show desktop lyrics button" switcher
    this.showDesktopLyricsButtonVM = new SwitcherRowViewModel(
      new SwitcherRowModel(this.model.showDesktopLyricsButton, true, $r('app.string.show_desktop_lyrics_button')),
      (newValue: boolean) => {
        this.onDesktopLyricsButtonChanged(newValue)
      }
    )

    // Initialize "Show close button" switcher
    this.showCloseButtonVM = new SwitcherRowViewModel(
      new SwitcherRowModel(this.model.showCloseButton, true, $r('app.string.show_close_button')),
      (newValue: boolean) => {
        this.onCloseButtonChanged(newValue)
      }
    )

    this.desktopLyricsEnabled = this.model.desktopLyricsEnabled
  }

  // Handle toggle of "Show desktop lyrics button".
  // Scenarios 7/8: gate ON-flip behind floating-window permission probe.
  // Scenario 6: when flipping OFF while the desktop lyric floating window is
  // currently showing, ask the user whether to also close it.
  private async onDesktopLyricsButtonChanged(newValue: boolean): Promise<void> {
    if (newValue) {
      // Scenario 7: already have permission -> enable immediately.
      // Scenario 8: no permission -> jump to system settings, await user
      // decision, and re-flip the toggle iff the user granted permission on
      // return. The probe is best-effort; if the API is unavailable, treat as
      // "permission granted" so the toggle still works in dev / emulator.
      const granted = await FloatingWindowPermission.ensurePermission()
      if (!granted) {
        // Revert the row to OFF without firing the callback again.
        this.showDesktopLyricsButtonVM.isOn = false
        // Scenario 8 wording: surface a "no overlay permission" prompt to the
        // user so the silent UI revert is not unexplained.
        try {
          promptAction.showToast({
            message: $r('app.string.no_floating_window_permission')
          })
        } catch (e) {
          console.warn('NotificationViewModel: showToast failed - '
            + (e as Error).message)
        }
        return
      }
    }

    this.model.saveShowDesktopLyricsButton(newValue)
    MediaCardDesktopLyricsButtonController.getInstance().onToggleChanged()

    if (!newValue) {
      // Scenario 6: only ask if the desktop lyric floating window is
      // currently showing. Read AppStorage LIVE — do not trust the local
      // `desktopLyricsEnabled` snapshot from loadFromModel(), which is stale.
      const floatingWindowOn: boolean =
        AppStorage.get<boolean>('desktopLyrics') ?? false
      if (floatingWindowOn) {
        this.desktopLyricsEnabled = true       // refresh the local mirror
        this.showAlsoCloseDesktopLyricsDialog = true
      }
    }
  }

  // Handle toggle of "Show close button"
  private onCloseButtonChanged(newValue: boolean): void {
    this.model.saveShowCloseButton(newValue)
    // spec23 — push the new toggle value into AVSession extras +
    // dispatchSessionEvent so any subscribed surface (media card / live
    // activity) sees it in the same tick.
    MediaCardCloseButtonController.getInstance().onToggleChanged()
  }

  // Called by FloatingWindowPermission.reprobeOnForeground when the user
  // returns from the system settings page with the permission newly granted.
  // Spec24 scenario 8 step 5 wording: "返回应用后开关自动切换为开启状态".
  private onFloatingWindowPermissionGranted(): void {
    // If the row is already ON (e.g., user manually re-tapped before this
    // listener fired), nothing to do.
    if (this.showDesktopLyricsButtonVM.isOn) {
      return
    }
    this.showDesktopLyricsButtonVM.isOn = true
    this.model.saveShowDesktopLyricsButton(true)
    MediaCardDesktopLyricsButtonController.getInstance().onToggleChanged()
  }

  // User confirmed to also close desktop lyrics
  confirmCloseDesktopLyrics(): void {
    this.showAlsoCloseDesktopLyricsDialog = false
    this.desktopLyricsEnabled = false
    this.model.saveDesktopLyricsEnabled(false)
    // spec24 — controller owns any floating-window teardown integration point
    // so the ViewModel stays out of system-surface lifecycle.
    MediaCardDesktopLyricsButtonController.getInstance().requestCloseFloatingWindow()
  }

  // User cancelled the "also close desktop lyrics" dialog
  cancelCloseDesktopLyrics(): void {
    this.showAlsoCloseDesktopLyricsDialog = false
  }

  // Dismiss dialog (e.g. tap on overlay background)
  dismissDialog(): void {
    this.showAlsoCloseDesktopLyricsDialog = false
  }
}
