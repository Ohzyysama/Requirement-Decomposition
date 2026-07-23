# Review Fix Report

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec24/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA`
- **Fix Date**: 2026-05-15
- **Total Issues in Report**: 10 scenarios (4 PASS, 3 PARTIAL, 0 FAIL, 3 UNABLE TO VERIFY) + 5 cross-cutting categories
- **Verified (CONFIRMED)**: 4 actionable issues
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Deferred (platform-limited)**: 3 scenarios (1, 2, 10)
- **Successfully Fixed**: 4
- **Failed to Fix**: 0
- **Fix Success Rate**: 100% of the 4 actionable issues targeted by this run

## Scope

This run was instructed to address the four actionable issues identified in `code-review-report.md`:

1. `SYSTEM_FLOAT_WINDOW` permission declaration missing in `module.json5` (cross-cutting — Permission Coverage; blocks scenarios 7 and 8)
2. Scenario 8 — no "no overlay permission" prompt when `ensurePermission()` returns false
3. Scenario 8 step 5 — no `onForeground` re-probe so the toggle does not auto-flip to ON after the user returns from system settings with permission newly granted
4. Scenario 6 step 6.1 — `MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow()` is a documented no-op that does not actually tear anything down

Platform-limited scenarios 1, 2, 10 (HarmonyOS does not allow third-party apps to customize system media-card actions or override the artist row) were **deferred** per instruction.

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|---------------|--------------|----------|--------|
| 1 | `ohos.permission.SYSTEM_FLOAT_WINDOW` not declared in `module.json5` | PARTIAL (cross-cutting Permission Coverage) | CONFIRMED | Read `entry/src/main/module.json5`; `requestPermissions` array (lines 38–51) contained only `INTERNET`, `FILE_ACCESS_PERSIST`, `KEEP_BACKGROUND_RUNNING`, `VIBRATE`. No `SYSTEM_FLOAT_WINDOW` entry. | Fixed |
| 2 | No "无悬浮窗权限" prompt on permission failure (scenario 8) | PARTIAL | CONFIRMED | Read `entry/src/main/ets/viewmodel/NotificationViewModel.ets:67-71`; on `granted === false` only `showDesktopLyricsButtonVM.isOn = false` ran. No `promptAction.showToast` call. The base/zh/ug `string.json` files had no matching resource key. | Fixed |
| 3 | No `onForeground` re-probe to auto-flip toggle ON after granting (scenario 8 step 5) | PARTIAL | CONFIRMED | Read `entry/src/main/ets/entryability/EntryAbility.ets:473-482`; `onForeground()` did not call any floating-window-permission re-probe. `FloatingWindowPermission.ets` exposed no API for this. | Fixed |
| 4 | `requestCloseFloatingWindow()` is a no-op (scenario 6 step 6.1) | PASS (with note) | CONFIRMED | Read `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:133-139`; method only re-published the AVSession state. No listener registry, no SettingsStore write of its own, no future-Spec18 integration hook. | Fixed |

## False Positive Analysis

None. All four issues flagged for action by the prompt were independently verified before fixes were applied.

## Scenario Fix Details

### Cross-Cutting: Permission Coverage — `SYSTEM_FLOAT_WINDOW`

- **Report Verdict**: PARTIAL (cross-cutting Permission Coverage; root cause for scenarios 7 + 8)
- **Fix Status**: Fixed

#### Issue 1: SYSTEM_FLOAT_WINDOW permission missing in module.json5

- **Verification**: CONFIRMED — `module.json5` `requestPermissions` array contained 4 entries (`INTERNET`, `FILE_ACCESS_PERSIST`, `KEEP_BACKGROUND_RUNNING`, `VIBRATE`). `FloatingWindowPermission.ets:10` references `'ohos.permission.SYSTEM_FLOAT_WINDOW'`, so the check `abilityAccessCtrl.checkAccessToken(...)` would always return `PERMISSION_DENIED` on real devices. The try/catch in `checkPermission` does not catch `PERMISSION_DENIED` because it is a normal return value, not an exception.
- **Fix Strategy**: Permission declaration (cross-cutting fix).
- **Android Reference**: `android.permission.SYSTEM_ALERT_WINDOW` in Android `AndroidManifest.xml` is the conceptual equivalent.
- **Changes Applied**:
  - Added `floating_window_permission_reason` string resource (base zh + ug + Uyghur localised). The Uyghur string was translated; the Chinese remains the canonical text.
  - Added `no_floating_window_permission` string resource for the toast in Fix 2.
  - Added a 5th entry to `module.json5#requestPermissions` for `ohos.permission.SYSTEM_FLOAT_WINDOW` with `reason: $string:floating_window_permission_reason` and `usedScene: { abilities: [EntryAbility], when: always }`.
- **Files Modified**:
  - `entry/src/main/module.json5`: added the permission entry.
  - `entry/src/main/resources/base/element/string.json`: added 2 string entries.
  - `entry/src/main/resources/zh/element/string.json`: added 2 string entries.
  - `entry/src/main/resources/ug/element/string.json`: added 2 string entries (Uyghur translation for reason, "لەيلىمە كۆزنەك ھوقۇقى يوق" for the toast).
- **API Documentation Used**: WebSearch — "HarmonyOS ohos.permission.SYSTEM_FLOAT_WINDOW module.json5 requestPermissions reason usedScene" — confirmed the `reason` + `usedScene` shape. Note: `SYSTEM_FLOAT_WINDOW` is classified as `system_grant` with restricted ACL availability; depending on APL the bundle may also need ACL-list configuration during signing. The signing material the project uses already accepted this permission at build time (build succeeded).
- **Compilation**: PASS (`assembleHap` succeeded, no new warnings).
- **Notes**: With this declaration in place, the scenario-7 "already granted" branch becomes reachable on real devices, and the scenario-8 "missing permission → jump to settings" path stops being shadowed by an unconditional `PERMISSION_DENIED`.

---

### Scenario 8 — No "无悬浮窗权限" prompt on permission failure

- **Report Verdict**: PARTIAL
- **Fix Status**: Fixed

#### Issue 2: missing toast on `ensurePermission()` failure

- **Verification**: CONFIRMED — `NotificationViewModel.onDesktopLyricsButtonChanged` rolled the UI row back to OFF silently. The spec text "弹出提示『无悬浮窗权限』" was not honoured.
- **Fix Strategy**: Resource + UI feedback (no Android counterpart since Android uses `Settings.canDrawOverlays` + a dialog, not a toast — but the spec wording explicitly calls for a 提示 here).
- **Android Reference**: The Android code path also routes to system settings on missing overlay permission; the user-feedback layer differs by spec.
- **Changes Applied**:
  - Added `no_floating_window_permission` string resource in three locales (alongside the permission-reason string).
  - Imported `promptAction` from `@kit.ArkUI` in `NotificationViewModel.ets` (matching the established pattern in `MainPageViewModel`, `SoundEffectDialogViewModel`, etc.).
  - After reverting the toggle to OFF on `!granted`, call `promptAction.showToast({ message: $r('app.string.no_floating_window_permission') })` inside a try/catch so a `promptAction` failure does not cascade.
- **Files Modified**:
  - `entry/src/main/ets/viewmodel/NotificationViewModel.ets`: added import + toast call.
  - `entry/src/main/resources/{base,zh,ug}/element/string.json`: added the toast string.
- **API Documentation Used**: Reused the existing project pattern in `MainPageViewModel.ets:1176`.
- **Compilation**: PASS.
- **Notes**: The toast fires both when `startAbility` fails outright and when the user returns from settings without granting. Both paths route through the same `granted === false` branch.

---

### Scenario 8 step 5 — Auto-flip toggle back to ON on return with permission

- **Report Verdict**: PARTIAL
- **Fix Status**: Fixed

#### Issue 3: no `onForeground` re-probe wired

- **Verification**: CONFIRMED — `EntryAbility.onForeground()` only reconciled AVPlayer state. `FloatingWindowPermission.ets` had no API to support a foreground re-probe.
- **Fix Strategy**: Lifecycle hook + observer pattern. Added `pendingGrantRequest` state and a `FloatingWindowGrantListener` registry to `FloatingWindowPermission`; the ViewModel subscribes on construction. `EntryAbility.onForeground` calls `FloatingWindowPermission.reprobeOnForeground()` which clears the pending flag, re-checks the permission, and fires listeners only when the user actually granted while away.
- **Android Reference**: Android typically uses `onActivityResult` with `Settings.ACTION_MANAGE_OVERLAY_PERMISSION`; HarmonyOS has no equivalent ability-result callback for this want, so a foreground re-probe is the correct adaptation.
- **Changes Applied**:
  - In `FloatingWindowPermission.ets`:
    - New exported type `FloatingWindowGrantListener = () => void`.
    - New static fields `pendingGrantRequest`, `grantListeners[]`.
    - New static methods `addGrantListener`, `removeGrantListener`, `reprobeOnForeground`.
    - `ensurePermission()` now flips `pendingGrantRequest = true` immediately before `startAbility(want)` and clears it on `startAbility` failure (so a failed launch does not leave the flag stuck across the next foreground).
    - `reprobeOnForeground()` clears the flag, re-checks the permission, and on `granted` snapshots-then-iterates the listener list (so a listener removing itself does not skip the next listener).
  - In `NotificationViewModel.ets`:
    - Added a private field `grantListener: FloatingWindowGrantListener` bound to `this.onFloatingWindowPermissionGranted()`.
    - Registered the listener in the constructor.
    - New private method `onFloatingWindowPermissionGranted()` that flips `showDesktopLyricsButtonVM.isOn = true`, persists via `model.saveShowDesktopLyricsButton(true)`, and pokes the controller's `onToggleChanged()`. It skips when the row is already ON to avoid double-fire when the user manually re-tapped before this listener arrived.
  - In `EntryAbility.ets`:
    - Imported `FloatingWindowPermission`.
    - Inside `onForeground()`, called `FloatingWindowPermission.reprobeOnForeground().catch(...)` with a hilog `WARN` fallback.
- **Files Modified**:
  - `entry/src/main/ets/model/FloatingWindowPermission.ets`: ~60 lines added.
  - `entry/src/main/ets/viewmodel/NotificationViewModel.ets`: import update + new field + constructor change + new method.
  - `entry/src/main/ets/entryability/EntryAbility.ets`: import + 5 lines in `onForeground()`.
- **API Documentation Used**: `UIAbility.onForeground` is documented as the resume callback (project already uses it for `AudioPlayerService.reconcileOnForeground`), so no external lookup was needed.
- **Compilation**: PASS.
- **Notes**: The listener fires at most once per `ensurePermission()` round-trip because `pendingGrantRequest` is cleared on the first re-probe. If the user grants and then revokes before the re-probe, the listener will not fire (correctly — they ended up without permission). The `bypass when isOn = true` guard inside the ViewModel listener guarantees safety against double-fire from the fast-grant case inside `ensurePermission()` itself (which already re-checks once via `await FloatingWindowPermission.checkPermission()` at the tail).

---

### Scenario 6 step 6.1 — `requestCloseFloatingWindow` no-op

- **Report Verdict**: PASS (with documented note about the no-op)
- **Fix Status**: Fixed (improved beyond the no-op)

#### Issue 4: no actual floating-window teardown integration point

- **Verification**: CONFIRMED — Confirmed by reading the method body. It only re-published the AVSession state and did not propagate `desktopLyrics=false` further. Confirmed by searching the project (`grep`) that no floating-window service exists yet (Spec18 has not landed); the only `desktopLyrics` references are in `EntryAbility`, `LyricsSettingsViewModel`, `NotificationViewModel`, `NotificationModel`.
- **Fix Strategy**: Observer pattern hook + defensive persistence. The controller becomes a self-contained close API: it writes `desktopLyrics=false` to both `AppStorage` and `SettingsStore` (via `SettingsStore.save`, which does both), notifies any registered `DesktopLyricsCloseListener` (the future Spec18 service will register here), and re-publishes the AVSession state.
- **Android Reference**: Android `MusicController.hideDesktopLyrics()` teardown — the conceptual equivalent. The current HarmonyOS code cannot implement the actual window hide because the spec18 window service does not exist; the listener registry is the integration point.
- **Changes Applied**:
  - In `MediaCardDesktopLyricsButtonController.ets`:
    - New exported type `DesktopLyricsCloseListener = () => void`.
    - New private field `closeListeners: DesktopLyricsCloseListener[]`.
    - New methods `addCloseListener(l)` and `removeCloseListener(l)`.
    - `requestCloseFloatingWindow()` now:
      1. Calls `SettingsStore.getInstance().save('desktopLyrics', false)` (which writes AppStorage + Preferences in one shot).
      2. Snapshots and iterates `closeListeners`, swallowing listener throws via try/catch + console.warn.
      3. Calls `publishLyricsState()` as before (keeps existing behaviour).
    - Added `import SettingsStore from './SettingsStore'`.
- **Files Modified**:
  - `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets`: ~40 lines added/changed.
- **API Documentation Used**: Reused project `SettingsStore` pattern (which already writes to AppStorage via `setOrCreate` + Preferences via `save`).
- **Compilation**: PASS.
- **Notes**: When Spec18 lands its floating-window service, it only needs to call `MediaCardDesktopLyricsButtonController.getInstance().addCloseListener(() => this.hide())` once in its init path — no Spec24 changes will be needed. The defensive `SettingsStore.save('desktopLyrics', false)` overlaps with the ViewModel's existing `model.saveDesktopLyricsEnabled(false)` call, but that overlap is idempotent (same key, same value) and makes the controller usable from other call sites (e.g. a future remote command) without depending on the ViewModel.

---

## Cross-Cutting Fixes

### Permission Coverage
- Permissions added: `ohos.permission.SYSTEM_FLOAT_WINDOW` with reason + usedScene.
- Runtime permission requests added: No — overlay permission is granted via system settings page (HarmonyOS does not surface this permission through `requestPermissionsFromUser`). The settings-page route via `startAbility(want)` in `FloatingWindowPermission.ensurePermission()` remains the only path; the new `onForeground` re-probe closes the loop.

### Navigation Updates
- Pages created: none.
- Routes registered: none. The "jump to system settings" want remains hard-coded against the Huawei settings bundle (`com.huawei.hmos.settings`). This was flagged in the review report as a separate issue but was not in this run's actionable list.

### Resource Additions
- Strings added in base + zh + ug: `floating_window_permission_reason`, `no_floating_window_permission`. Uyghur translations were authored fresh.
- Media resources needed (manual): none.

### State Management Changes
- `@Observed` / `@Track` decorators on `NotificationViewModel` are unchanged — `showDesktopLyricsButtonVM.isOn` was already observable.
- New non-decorated private `grantListener` field on `NotificationViewModel`: it is a stable function reference held for add/remove parity, not an observable, so no decorator is required.

## Remaining Issues

| # | Issue | Reason | Recommendation |
|---|-------|--------|----------------|
| 1 | Scenarios 1, 2, 10 visual surface | Platform-limited (HarmonyOS AVSession does not expose third-party custom card actions / artist-row override) | Defer per user instruction. The AVSession-extras emitted by the controller are forward-compatibility hooks. |
| 2 | Hard-coded Huawei settings want (`com.huawei.hmos.settings`) | Out of scope for this run | Track separately. Possible mitigations: (a) `try` the Huawei want, fall back to a generic OpenHarmony permission settings want; (b) when overlay permission is exposed via `requestPermissionsFromUser` in a future SDK, prefer that. |
| 3 | Spec18 desktop-lyrics floating window service does not exist yet | Out of spec24 scope | Spec18 implementation will register a listener via `MediaCardDesktopLyricsButtonController.getInstance().addCloseListener(...)`. The integration point now exists; no Spec24 change will be required. |
| 4 | ACL configuration may be required for `SYSTEM_FLOAT_WINDOW` on signing | System-level permission classification | This build succeeded with the existing signing material, so ACL is already permissive for this permission on the current signing profile. Verify on production signing if separate. |

## All Modified Files

| File | Issues Addressed | Change Summary |
|------|-----------------|----------------|
| `entry/src/main/module.json5` | Issue 1 | Added `SYSTEM_FLOAT_WINDOW` permission entry with `reason` and `usedScene` block. |
| `entry/src/main/resources/base/element/string.json` | Issues 1 + 2 | Added `floating_window_permission_reason` and `no_floating_window_permission` keys. |
| `entry/src/main/resources/zh/element/string.json` | Issues 1 + 2 | Same two keys in zh-CN. |
| `entry/src/main/resources/ug/element/string.json` | Issues 1 + 2 | Same two keys with Uyghur translations. |
| `entry/src/main/ets/viewmodel/NotificationViewModel.ets` | Issues 2 + 3 | Imports `promptAction` + `FloatingWindowGrantListener`. Added `grantListener` field, listener registration in constructor, `onFloatingWindowPermissionGranted()` handler, and a toast call on `!granted`. |
| `entry/src/main/ets/model/FloatingWindowPermission.ets` | Issue 3 | New `FloatingWindowGrantListener` export, `pendingGrantRequest` + listener registry, `addGrantListener`, `removeGrantListener`, `reprobeOnForeground`. `ensurePermission()` now sets/clears the pending flag. |
| `entry/src/main/ets/entryability/EntryAbility.ets` | Issue 3 | Imported `FloatingWindowPermission`. `onForeground()` calls `reprobeOnForeground()` with a `.catch` fallback. |
| `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets` | Issue 4 | New `DesktopLyricsCloseListener` export, `closeListeners[]` field, `addCloseListener`/`removeCloseListener` methods. `requestCloseFloatingWindow()` now persists `desktopLyrics=false` via `SettingsStore.save` and fires listeners before the existing publish. |

## Compilation Verification

- Tool: `hvigorw assembleHap --mode module -p module=entry --no-daemon`
- Environment: `DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk`
- Result: **BUILD SUCCESSFUL** in 6 s 686 ms.
- Iterations: 1 (no fix loop needed).
- Output HAP: `wsh-output/spec24/entry-default-signed.hap`.

No new warnings or errors were introduced by the review-fix changes. All four fixes compile cleanly.

## Recommendations

1. **Re-run code review** against this branch to confirm scenarios 7 + 8 verdicts move from PARTIAL to PASS now that `SYSTEM_FLOAT_WINDOW` is declared and the toast / re-probe are wired.
2. **Manual on-device verification** for scenario 8 end-to-end: tap toggle ON without permission → confirm jump to settings → toggle the permission ON in settings → return to app → confirm toggle row auto-flips to ON. Verify the toast appears when returning from settings *without* granting.
3. **Generalize the settings want** (separate work item, not in this run): wrap the Huawei-specific want in a try/catch and fall back to a generic permission management ability for non-Huawei builds.
4. **Spec18 integration** when that lands: register the floating-window service's `hide()` method via `MediaCardDesktopLyricsButtonController.getInstance().addCloseListener(...)`. The hook is in place.
5. **Production signing check**: confirm `SYSTEM_FLOAT_WINDOW` does not require additional ACL entries in the production signing profile (the debug profile accepted it).
