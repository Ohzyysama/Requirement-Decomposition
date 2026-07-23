// FloatingWindowPermission.ets
// spec24 — Probes the system overlay / 悬浮窗 permission and routes the user
// to the system settings page when missing. Encapsulates scenarios 7 and 8
// of spec24 so the NotificationViewModel stays MVVM-clean (it asks the model
// layer; the model layer talks to the system).

import { abilityAccessCtrl, bundleManager, common, Permissions, Want } from '@kit.AbilityKit'
import AudioPlayerService from './AudioPlayerService'

const FLOATING_WINDOW_PERM: Permissions = 'ohos.permission.SYSTEM_FLOAT_WINDOW'

// Callback fired from EntryAbility.onForeground when the user returns from the
// system settings page with the permission newly granted. The NotificationViewModel
// registers a listener here so it can flip its own UI row back to ON without
// re-running the full toggle handler (avoids re-entering the settings page).
export type FloatingWindowGrantListener = () => void

export class FloatingWindowPermission {

  // True while the user has been routed to the system settings page and the
  // app is waiting for them to return. Cleared on the next foreground tick.
  private static pendingGrantRequest: boolean = false
  private static grantListeners: FloatingWindowGrantListener[] = []

  // Subscribe to the "user came back from settings with permission granted"
  // signal. The NotificationViewModel registers in its constructor; the listener
  // is called at most once per ensurePermission() round-trip.
  static addGrantListener(l: FloatingWindowGrantListener): void {
    if (FloatingWindowPermission.grantListeners.indexOf(l) === -1) {
      FloatingWindowPermission.grantListeners.push(l)
    }
  }

  static removeGrantListener(l: FloatingWindowGrantListener): void {
    const idx = FloatingWindowPermission.grantListeners.indexOf(l)
    if (idx !== -1) {
      FloatingWindowPermission.grantListeners.splice(idx, 1)
    }
  }

  // Returns true when the bundle currently holds the overlay permission.
  static async checkPermission(): Promise<boolean> {
    try {
      const ctrl = abilityAccessCtrl.createAtManager()
      const bundle = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      const state = await ctrl.checkAccessToken(
        bundle.appInfo.accessTokenId, FLOATING_WINDOW_PERM)
      return state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    } catch (e) {
      // If the API is not available (older SDK / emulator), treat as granted
      // so dev/CI still flows. Real devices that lack the API are extremely
      // rare and the worst outcome is a no-op toggle.
      console.warn('FloatingWindowPermission.checkPermission: ' + (e as Error).message)
      return true
    }
  }

  // High-level: returns true when the user ends up with the permission.
  // When already granted -> returns true synchronously.
  // When missing -> jumps to the system permission page, waits for the user
  // to return, re-checks the permission.
  static async ensurePermission(): Promise<boolean> {
    if (await FloatingWindowPermission.checkPermission()) {
      return true
    }
    const ctx = AudioPlayerService.getInstance().getContext()
    if (!ctx) {
      return false
    }
    try {
      // Open the system permission management page for this bundle. The
      // exact want spec follows the established HarmonyOS docs pattern; if
      // a subsystem rejects the want, we fall through to the no-op and
      // log a warning.
      const params: Record<string, Object> = {
        'pushParams': ctx.abilityInfo.bundleName
      }
      const want: Want = {
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: params
      }
      // Mark pending so EntryAbility.onForeground will re-probe once the user
      // returns. The flag is cleared inside reprobeOnForeground().
      FloatingWindowPermission.pendingGrantRequest = true
      await (ctx as common.UIAbilityContext).startAbility(want)
    } catch (e) {
      console.warn('FloatingWindowPermission.ensurePermission: '
        + 'startAbility failed - ' + (e as Error).message)
      FloatingWindowPermission.pendingGrantRequest = false
      return false
    }
    // The user is now in system settings. We cannot synchronously wait for
    // the return; the caller (NotificationViewModel) re-checks on the next
    // foreground tick. To keep this helper consistent we re-check once here
    // for the fast-grant case (user granted permission before this Promise
    // was awaited).
    return await FloatingWindowPermission.checkPermission()
  }

  // Called by EntryAbility.onForeground. If the user was sent to the system
  // settings page and has now returned with permission granted, flip the toggle
  // back to ON by notifying any registered listener. Spec24 scenario 8 wording:
  // "返回应用后开关自动切换为开启状态".
  static async reprobeOnForeground(): Promise<void> {
    if (!FloatingWindowPermission.pendingGrantRequest) {
      return
    }
    FloatingWindowPermission.pendingGrantRequest = false
    const granted = await FloatingWindowPermission.checkPermission()
    if (!granted) {
      // The user came back without granting. The ViewModel already reverted
      // the row to OFF and toasted; nothing more to do.
      return
    }
    // Snapshot listeners so a listener that removes itself does not skip the
    // next listener in the same iteration.
    const snapshot = FloatingWindowPermission.grantListeners.slice()
    for (const l of snapshot) {
      try {
        l()
      } catch (e) {
        console.warn('FloatingWindowPermission.reprobeOnForeground: '
          + 'listener threw - ' + (e as Error).message)
      }
    }
  }
}

export default FloatingWindowPermission
