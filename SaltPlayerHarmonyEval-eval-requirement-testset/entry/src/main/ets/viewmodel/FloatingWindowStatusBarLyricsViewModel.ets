// FloatingWindowStatusBarLyricsViewModel.ets
// spec25 — Owns the action layer for the 悬浮窗状态栏歌词 settings page.
// Persists every change via SettingsStore (which mirrors to AppStorage so
// downstream readers — the float-window page, the controller — see it live).
// Coordinates the floating-window permission probe on master-toggle ON, and
// pokes the FloatingStatusBarLyricsController to show/hide the window.

import SettingsStore from '../model/SettingsStore'
import FloatingWindowPermission, { FloatingWindowGrantListener } from '../model/FloatingWindowPermission'
import FloatingStatusBarLyricsController from '../model/FloatingStatusBarLyricsController'
import { promptAction } from '@kit.ArkUI'

@Observed
export default class FloatingWindowStatusBarLyricsViewModel {
  // ---- Master toggle (gated by overlay permission) ----
  @Track public master: boolean =
    (AppStorage.get<boolean>('floatingWindowStatusBarLyrics') ?? false)

  // ---- Position / size / style (hydrated from AppStorage) ----
  @Track public leftRightPercent: number =
    (AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0)
  @Track public upDownPx: number =
    (AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0)
  @Track public widthDp: number =
    (AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150)
  @Track public fontSizeDp: number =
    (AppStorage.get<number>('floatingWindowSbLrFontSizeDp') ?? 14)
  @Track public color: number =
    (AppStorage.get<number>('floatingWindowSbLrColor') ?? 0xFF0470E6)
  @Track public centerAlign: boolean =
    (AppStorage.get<boolean>('floatingWindowSbLrCenterAlign') ?? false)
  @Track public notShowTranslation: boolean =
    (AppStorage.get<boolean>('statusBarLyricsNotShowTranslation') ?? false)
  @Track public hideOnPlayer: boolean =
    (AppStorage.get<boolean>('floatingWindowSbLrHideOnPlayer') ?? false)

  // Slider range constants (single source of truth shared with the View).
  // @Track is required on every UI-read field of an @Observed object
  // under the strict tracking enforced by API 23 runtime — even
  // readonly constants. Crash signature without @Track:
  //   "Illegal usage of not @Track'ed property 'LR_MIN' on UI!"
  @Track public readonly LR_MIN: number = 0
  @Track public readonly LR_MAX: number = 100
  @Track public readonly UD_MIN: number = 0
  @Track public readonly UD_MAX: number = 100
  @Track public readonly W_MIN: number = 50
  @Track public readonly W_MAX: number = 750
  @Track public readonly F_MIN: number = 8
  @Track public readonly F_MAX: number = 32

  private grantListener: FloatingWindowGrantListener = (): void => {
    this.onPermissionGrantedFromSettings()
  }

  constructor() {
    FloatingWindowPermission.addGrantListener(this.grantListener)
  }

  // Master switch — scenario 1, 2, 3
  async onMasterToggleChanged(newValue: boolean): Promise<void> {
    if (newValue) {
      const granted = await FloatingWindowPermission.ensurePermission()
      if (!granted) {
        // Revert the row (UI binds to this.master), surface a toast.
        this.master = false
        try {
          promptAction.showToast({
            message: $r('app.string.no_floating_window_permission')
          })
        } catch (_e) {
          // toast best-effort
        }
        return
      }
    }
    this.master = newValue
    SettingsStore.getInstance().save('floatingWindowStatusBarLyrics', newValue)
    if (newValue) {
      FloatingStatusBarLyricsController.getInstance().show().catch((e: Error) => {
        console.warn('FloatingWindowStatusBarLyricsViewModel.show: ' + e.message)
      })
    } else {
      FloatingStatusBarLyricsController.getInstance().hide().catch((e: Error) => {
        console.warn('FloatingWindowStatusBarLyricsViewModel.hide: ' + e.message)
      })
    }
  }

  // ---- Per-setting handlers — persist + UI mirrors via SettingsStore.save ----
  onLeftRightPercentChanged(v: number): void {
    this.leftRightPercent = v
    SettingsStore.getInstance().save('floatingWindowSbLrLeftRightPercent', v)
  }

  onUpDownPxChanged(v: number): void {
    this.upDownPx = v
    SettingsStore.getInstance().save('floatingWindowSbLrUpDownPx', v)
  }

  onWidthDpChanged(v: number): void {
    this.widthDp = v
    SettingsStore.getInstance().save('floatingWindowSbLrWidthDp', v)
  }

  onFontSizeDpChanged(v: number): void {
    this.fontSizeDp = v
    SettingsStore.getInstance().save('floatingWindowSbLrFontSizeDp', v)
  }

  onColorChanged(v: number): void {
    this.color = v
    SettingsStore.getInstance().save('floatingWindowSbLrColor', v)
  }

  onCenterAlignChanged(v: boolean): void {
    this.centerAlign = v
    SettingsStore.getInstance().save('floatingWindowSbLrCenterAlign', v)
  }

  onNotShowTranslationChanged(v: boolean): void {
    this.notShowTranslation = v
    // Share the key with the system-level status-bar setting per plan §3.2 / interp A.
    SettingsStore.getInstance().save('statusBarLyricsNotShowTranslation', v)
  }

  onHideOnPlayerChanged(v: boolean): void {
    this.hideOnPlayer = v
    SettingsStore.getInstance().save('floatingWindowSbLrHideOnPlayer', v)
  }

  // FloatingWindowPermission grant-listener — fires when the user returns
  // from the system settings page with the permission newly granted.
  // Spec25 scenario 1 implies the master stays OFF if the user denies, but
  // the spec24 precedent (auto-flip ON when the user actually granted) is
  // consistent with user intent — we follow that pattern here so a returning
  // user doesn't need to re-tap the toggle when they granted what we asked
  // for. This mirrors NotificationViewModel.onFloatingWindowPermissionGranted.
  private onPermissionGrantedFromSettings(): void {
    if (this.master) {
      return
    }
    this.master = true
    SettingsStore.getInstance().save('floatingWindowStatusBarLyrics', true)
    FloatingStatusBarLyricsController.getInstance().show().catch((e: Error) => {
      console.warn('FloatingWindowStatusBarLyricsViewModel.permGrant: '
        + e.message)
    })
  }

  // Page lifecycle — called by aboutToDisappear of the page.
  destroy(): void {
    FloatingWindowPermission.removeGrantListener(this.grantListener)
  }
}
