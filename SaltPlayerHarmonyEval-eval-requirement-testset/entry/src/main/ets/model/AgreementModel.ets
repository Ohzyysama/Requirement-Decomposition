// AgreementModel.ets
// Model layer: persistence for the first-launch user-agreement gate.
//
// On first launch the app must present a modal blocking the UI until the
// user explicitly accepts the Terms of Use and Privacy Policy (regulatory
// compliance requirement for Chinese app stores, including Huawei AppGallery).
// Once accepted, the decision is stored in preferences and the modal is
// never shown again unless the user clears it via DevPage for testing.

import { preferences } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'

const PREF_FILE = 'user_agreement_prefs'
const KEY_AGREED = 'agreed'
const LOG_TAG = 'AgreementModel'

// URLs mirror the canonical sources exposed on the About page.
// Kept in this Model so the agreement dialog doesn't need to depend on
// AboutModel, which would be a backwards import direction.
export const TERMS_OF_USE_URL = 'https://xuncorp.com/salt/player/terms_of_user_harmony.html'
export const PRIVACY_POLICY_URL = 'https://xuncorp.com/salt/player/privacy_policy_harmony.html'

export class AgreementModel {
  private static async getStore(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, PREF_FILE)
  }

  // Returns true if the user has previously tapped "同意" on the
  // first-launch dialog. Falls back to false on read errors so the
  // dialog re-shows rather than silently bypassing compliance.
  static async hasAgreed(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const store = await AgreementModel.getStore(context)
      const value = await store.get(KEY_AGREED, false)
      return value === true
    } catch (e) {
      hilog.error(0, LOG_TAG, `hasAgreed read failed: ${(e as Error)?.message ?? e}`)
      return false
    }
  }

  static async setAgreed(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await AgreementModel.getStore(context)
      await store.put(KEY_AGREED, true)
      await store.flush()
    } catch (e) {
      hilog.error(0, LOG_TAG, `setAgreed write failed: ${(e as Error)?.message ?? e}`)
    }
  }

  // Dev-only. Wired from DevPage's "测试取消同意用户协议和隐私政策" item so
  // testers can re-trigger the first-launch dialog without reinstalling.
  static async clearAgreed(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await AgreementModel.getStore(context)
      await store.delete(KEY_AGREED)
      await store.flush()
    } catch (e) {
      hilog.error(0, LOG_TAG, `clearAgreed failed: ${(e as Error)?.message ?? e}`)
    }
  }
}
