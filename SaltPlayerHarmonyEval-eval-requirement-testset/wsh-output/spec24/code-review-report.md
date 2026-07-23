# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `565e6305e159aa9849060e57fb98f4eac33123c3`
- **Author / Date**: Moriafly, 2026-05-19
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec24/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/565e6305e159aa9849060e57fb98f4eac33123c3_result.json`
- **Files Touched**:
  - `entry/src/main/ets/entryability/EntryAbility.ets` (+15)
  - `entry/src/main/ets/model/AudioPlayerService.ets` (+75)
  - `entry/src/main/ets/model/FloatingWindowPermission.ets` (new, +73)
  - `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets` (new, +174)
  - `entry/src/main/ets/viewmodel/NotificationViewModel.ets` (+46/-12)
- **Total Scenarios**: 10
- **Results**: 4 PASS | 3 PARTIAL | 0 FAIL | 3 UNABLE TO VERIFY

**Platform note (applies to scenarios 1, 2, 3, 4, 5, 6.3, 7.5, 8.6, 9, 10).** HarmonyOS AVSession does not let a third-party app add a custom action button to the system media card, nor override the artist-row text on that card. The implementation under review treats the AVSession layer as a publish surface: it stores user intent (`showDesktopLyricsButton` toggle) and per-song state (`cardLyricsActive`, `cardLyricsLine`) as session extras and broadcasts them via `dispatchSessionEvent`. The visual contract of the spec (a card button to the left of "previous track", artist-row replaced by a lyric line) cannot be enforced by app code on stock HarmonyOS. The review therefore evaluates each scenario against the level of contract this code can realistically provide — persistence, gate logic, and event emission — and marks the surface rendering itself as UNABLE TO VERIFY where it is the user-visible part of the scenario.

---

## Scenario Coverage Summary

| #  | Scenario                                                        | Verdict             | Key Gaps |
|----|-----------------------------------------------------------------|---------------------|----------|
| 1  | Toggle ON by default, lyric button appears on card              | PARTIAL             | Default persisted, but no system-card button surface in HarmonyOS — extra `showDesktopLyricsButton` only published |
| 2  | User taps lyric button, artist row becomes running lyric        | PARTIAL             | Controller wiring complete; no surface consumes `cardLyricsActive`/`cardLyricsLine` extras |
| 3  | User taps lyric button again, artist row restored               | PASS                | Controller toggle state flips and republishes |
| 4  | Switch song while in lyric mode, line updates / falls back      | PASS                | `addOnSongChangedListener` resets per-song flag and republishes |
| 5  | Tap button while song has no lyrics — no-op                     | PASS                | `requestToggleLyricsActive` gates on `hasLyrics` and silently returns |
| 6  | Turn toggle OFF; if desktop-lyrics floating window on, dialog   | PASS                | Live `AppStorage('desktopLyrics')` read; dialog + confirm path wired |
| 7  | Toggle ON with floating-window permission already granted       | PARTIAL             | `SYSTEM_FLOAT_WINDOW` not declared in `module.json5` — `checkPermission` will swallow `e` and return `true` (dev-fallback path), so the flip still works but the probe is degenerate |
| 8  | Toggle ON without permission — jump to system settings          | PARTIAL             | Same missing-declaration issue; relies on emulator/dev fallback; `startAbility` want is best-guess and not verified |
| 9  | Toggle state survives app restart                               | PASS                | `PersistentStorage.persistProp` + `SettingsStore` hydrate on `onCreate` |
| 10 | Lyric button is in expanded view only, not compact              | UNABLE TO VERIFY    | No app-side surface today; OS-managed card layout |

---

## Detailed Scenario Reviews

### Scenario 1 — Toggle ON by default, lyric button appears on card

**Description**: New installs default the toggle to ON; the system media card shows a lyrics button to the left of the previous-track button while a song plays.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/entryability/EntryAbility.ets:107` — `PersistentStorage.persistProp('showDesktopLyricsButton', true)` registers the default ON.
- `entry/src/main/ets/entryability/EntryAbility.ets:164-165` — `ss.get('showDesktopLyricsButton', true)` re-hydrates AppStorage from SettingsStore on cold boot.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:55-58` — `init()` calls `publishToggle()` to push the default value into AVSession before the first song.
- `entry/src/main/ets/model/AudioPlayerService.ets:502-525` — `publishDesktopLyricsButtonExtras` writes `setExtras({ showDesktopLyricsButton })` and dispatches `showDesktopLyricsButtonChanged`.

**Gaps**:
- HarmonyOS AVSession does not surface a custom action button on the system media card; the spec's visual contract (lyric button left of prev-track) cannot be honoured by app code alone. The commit acknowledges this in the controller header comment.
- The published `showDesktopLyricsButton` extra is consumed by no in-process surface — there is no card-rendering subscriber that flips a button into view.

**Suggestions**:
- Document on the spec side that the AVSession-extra contract is a forward-compatibility hook for a future system-card extension point or for the app's own live-activity / live-window surface (Spec18 desktop lyrics floating window has its own controller). Without a consumer the publish is dead code today.

---

### Scenario 2 — User taps lyric button, artist row becomes running lyric

**Description**: When the user taps the card's lyric button, the artist-info area on the card is replaced by the current lyric line, which keeps updating with playback progress.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/model/AudioPlayerService.ets:259-265` — `session.on('commonCommand')` routes `'toggleCardLyrics'` to `MediaCardDesktopLyricsButtonController.requestToggleLyricsActive()`.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:108-124` — `requestToggleLyricsActive` toggles `isLyricsActive`, gated by `showDesktopLyricsButton` toggle and `hasLyrics`.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:80-93` — `MiniLyricsController.addListener` provides the running-line tick (200 ms) which is republished while `isLyricsActive`.
- `entry/src/main/ets/model/AudioPlayerService.ets:534-563` — `publishCardLyricsState` writes both `setExtras({ cardLyricsActive, cardLyricsLine })` and `dispatchSessionEvent('cardLyricsStateChanged', { active, line })`.

**Gaps**:
- HarmonyOS AVSession has no API for a third-party app to override the artist-row text on the system media card. The extras + event the controller emits have no consumer surface today.
- The card cannot dispatch `commonCommand('toggleCardLyrics')` either, because the OS-managed card has no UI route to invoke it. The handler is therefore only reachable by direct in-process invocation or by a future controller / live-window we ship.

**Suggestions**:
- Either downgrade scenario 2 in the spec to "future-proof" or build a Spec18-style floating window that subscribes to `cardLyricsStateChanged` and renders the lyric row itself (the controller already publishes the state for it).

---

### Scenario 3 — User taps lyric button again, artist row restored

**Description**: A second tap on the lyric button restores the artist row.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:115-124` — `requestToggleLyricsActive` is a symmetric flip: `this.isLyricsActive = !this.isLyricsActive`, followed by `publishLyricsState()`.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:163-173` — `publishLyricsState` collapses to `(active=false, line='')` when `isLyricsActive` is false, so the published state reads "artist row".

**Gaps**:
- None at the logic level. The user-visible part (the OS card actually rendering the swap-back) is constrained by scenario-2's surface gap, not by this commit.

---

### Scenario 4 — Switch song while in lyric mode, line updates / falls back

**Description**: While the artist row is showing lyrics, switching tracks updates to the new song's lyric or falls back to the artist row when no lyrics exist.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:62-74` — `songChangedListener` resets `isLyricsActive = false`, clears `currentLine`, invalidates last-published cache, and republishes both extras. This honours the spec's "per-song" reset.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:78-94` — `MiniLyricsController` listener feeds `hasLyrics` and `currentLine`, and `publishLyricsState` only emits a non-empty line when `active && hasLyrics`.

**Gaps**:
- The spec wording in step 4 of scenario 4 says "if no lyrics, blank or restore artist row." The current implementation lands the row state at `active=false, line=''` immediately on song change, which corresponds to "artist row restored" — consistent with the spec's preferred fallback.

---

### Scenario 5 — Tap button while song has no lyrics — no-op

**Description**: If the current song has no timestamped lyrics, tapping the lyric button does nothing.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:112-118` — `requestToggleLyricsActive` returns early when `!this.isLyricsActive && !this.hasLyrics`. This guards the OFF→ON transition exactly per the spec wording.

**Gaps**:
- Toggling OFF→ON is correctly gated, but the early-return shape `!isLyricsActive && !hasLyrics` permits an existing active state to flip OFF even if the current song has just lost its lyrics — which is the desired behaviour and matches the spec.

---

### Scenario 6 — Turn toggle OFF; if desktop-lyrics floating window on, dialog

**Description**: Disabling the toggle hides the lyric button immediately; if the desktop-lyrics floating window is currently visible, prompt the user about also closing it.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/NotificationViewModel.ets:74-87` — On OFF flip, persists via `model.saveShowDesktopLyricsButton(false)`, then reads `AppStorage.get<boolean>('desktopLyrics')` LIVE (not the stale `desktopLyricsEnabled` mirror) and gates the dialog on the actual floating-window state.
- `entry/src/main/ets/viewmodel/NotificationViewModel.ets:99-107` — `confirmCloseDesktopLyrics()` saves `desktopLyrics=false` and calls `MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow()`.
- `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets:96-105` — On toggle OFF the controller also forces `isLyricsActive=false` and republishes, honouring scenario step 4: "if the artist-info area was showing lyrics, restore the artist info."

**Gaps**:
- `MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow()` is a documented no-op today (`...this is the integration point`). Closing the actual floating window will fail silently until Spec18's floating-window controller registers a hook. The `desktopLyrics=false` flag is still persisted, so a re-launch will not show the window — but the *currently visible* window will not be torn down. The spec wording ("关闭桌面歌词悬浮窗") is therefore only honoured at the persistence layer.

**Suggestions**:
- Resolve the cross-spec wiring: have the Spec18 desktop-lyrics window service register itself as a listener on `AppStorage('desktopLyrics')` and tear down on `false`, OR have `requestCloseFloatingWindow()` call directly into that service when it lands.

---

### Scenario 7 — Toggle ON with floating-window permission already granted

**Description**: Flipping the toggle ON when the app already holds the system overlay permission succeeds immediately and shows the button.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/viewmodel/NotificationViewModel.ets:59-72` — Async `onDesktopLyricsButtonChanged(true)` awaits `FloatingWindowPermission.ensurePermission()` and reverts the UI row to OFF on failure.
- `entry/src/main/ets/model/FloatingWindowPermission.ets:12-25` — `checkPermission` reads `abilityAccessCtrl.checkAccessToken` against `ohos.permission.SYSTEM_FLOAT_WINDOW`.

**Gaps**:
- `entry/src/main/module.json5:38-51` declares only `INTERNET`, `FILE_ACCESS_PERSIST`, `KEEP_BACKGROUND_RUNNING`, `VIBRATE`. The permission `ohos.permission.SYSTEM_FLOAT_WINDOW` is not declared, so the runtime check will return `PERMISSION_DENIED` regardless of system state on a real device. The try/catch in `checkPermission` only catches API-availability errors (returning `true` as the dev/emulator fallback) — `checkAccessToken` returning `PERMISSION_DENIED` is not an exception, it is a normal return value, so the function correctly returns `false` on real devices. The "already granted" branch is therefore unreachable on real hardware without a manifest change.
- `entry/src/main/ets/model/FloatingWindowPermission.ets:51-58` — The want used to jump to system settings (`bundleName: 'com.huawei.hmos.settings'`, `abilityName: 'com.huawei.hmos.settings.MainAbility'`, `uri: 'application_info_entry'`) is hard-coded against a Huawei build. The code path is not verified on stock OpenHarmony.

**Suggestions**:
- Add `ohos.permission.SYSTEM_FLOAT_WINDOW` to `entry/src/main/module.json5#requestPermissions` with an appropriate `reason` and `usedScene` block. Without it the toggle ON-flip cannot succeed on real devices.
- Verify the settings want on the target device family. If unstable, fall back to `abilityAccessCtrl.requestPermissionsFromUser` for a user-grant dialog where possible.

---

### Scenario 8 — Toggle ON without permission — jump to system settings

**Description**: Flipping the toggle ON without permission jumps the user to the system permission settings page; on return, the toggle reflects the granted/denied result.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/model/FloatingWindowPermission.ets:32-65` — `ensurePermission()` checks first, opens `startAbility(want)`, then re-checks once for the fast-grant case.
- `entry/src/main/ets/viewmodel/NotificationViewModel.ets:66-71` — On final `granted === false`, the toggle row UI is reverted to OFF without re-firing the callback.

**Gaps**:
- Same `module.json5` declaration gap as scenario 7.
- The "return to app and re-check" handoff is a single synchronous re-check inside the same Promise (`return await FloatingWindowPermission.checkPermission()` at the tail). A user that takes longer than the Promise resolution to grant permission and return will see the toggle flip to OFF; the next OFF→ON attempt will then succeed because the permission is now granted. This is acceptable but the spec's phrase "返回应用后开关自动切换为开启状态" (toggle automatically flips to ON after returning) is not strictly honoured — it requires a foreground re-probe (e.g. via `onForeground`) that this commit does not wire up.
- The `startAbility` failure path (`return false`) does not surface a "no permission" toast/dialog to the user. The spec wording "弹出提示『无悬浮窗权限』" (show a "no overlay permission" prompt) is not implemented; the UI silently reverts to OFF.

**Suggestions**:
- Wire a `Lifecycle.onForeground` hook in `NotificationPage` / `EntryAbility` to re-call `FloatingWindowPermission.checkPermission()` and, if it now returns `true`, re-trigger `model.saveShowDesktopLyricsButton(true)` + `controller.onToggleChanged()` and flip the UI back to ON.
- Show a toast/snackbar when `startAbility` fails or when the user returns without granting.

---

### Scenario 9 — Toggle state survives app restart

**Description**: The toggle state set by the user persists across an app exit + relaunch.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/entryability/EntryAbility.ets:107` — `PersistentStorage.persistProp('showDesktopLyricsButton', true)` registers the AppStorage key for persistence.
- `entry/src/main/ets/entryability/EntryAbility.ets:164-165` — Cold-start hydration from `SettingsStore` into AppStorage runs in `onCreate`.
- `entry/src/main/ets/model/NotificationModel.ets:27-34` — `loadSettings()` reads `AppStorage.get<boolean>('showDesktopLyricsButton') ?? true`, so the ViewModel constructor surfaces the persisted value.
- `entry/src/main/ets/model/NotificationModel.ets:36-39` — `saveShowDesktopLyricsButton` writes to `SettingsStore` (Preferences-backed) on every flip.

**Gaps**:
- None.

---

### Scenario 10 — Lyric button is in expanded view only, not compact

**Description**: In a compact card view (collapsed notification), only previous/play-pause/next are shown; the lyric button appears only in the expanded view.

**Verdict**: UNABLE TO VERIFY

**Evidence**:
- No app code controls compact vs. expanded layout of the OS media card.
- The controller does not differentiate the publish for compact/expanded — there is only one `showDesktopLyricsButton` extra.

**Gaps**:
- Same root cause as scenarios 1/2: stock HarmonyOS does not let third-party apps lay out card actions per visual variant. The spec's requirement is unverifiable from app code alone.

**Suggestions**:
- If the app eventually owns its own live-window surface, encode the compact/expanded variant explicitly on that surface and ignore this requirement for the system card.

---

## Cross-Cutting Issues

### Permission Coverage

- `ohos.permission.SYSTEM_FLOAT_WINDOW` is referenced by `FloatingWindowPermission.checkPermission` (`entry/src/main/ets/model/FloatingWindowPermission.ets:10`) but **not declared** in `entry/src/main/module.json5` (`requestPermissions` block, lines 38-51). On real devices `checkAccessToken` will return `PERMISSION_DENIED`, and the dev/emulator fallback inside the try/catch will not activate (because `PERMISSION_DENIED` is not an exception). Scenarios 7 and 8 are blocked on this declaration.
- All other permissions used by the commit (none beyond existing AVSession scope) are already declared.

### Navigation Completeness

- `NotificationPage` (`entry/src/main/ets/pages/NotificationPage.ets`) already renders the toggle row via `ItemSwitcherRowComponent({ vm: viewModel.showDesktopLyricsButtonVM })` (line 112-114) and the dialog overlay (line 56-58). Navigation from Settings → Notification page is pre-existing and not touched by this commit.
- The "jump to system settings" navigation in scenario 8 uses `startAbility(want)` and depends on the want being valid for the target ROM (Huawei-flavoured today).

### State Management

- `@Track public showDesktopLyricsButtonVM` (`NotificationViewModel.ets:16`) is the observable surface — sound MVVM.
- `AppStorage` keys (`showDesktopLyricsButton`, `desktopLyrics`) are used as the live source of truth in both the ViewModel (scenario 6 dialog gate, `NotificationViewModel.ets:82`) and the controller (`MediaCardDesktopLyricsButtonController.ets:97-99`, `109-110`). Reading AppStorage live rather than caching in fields is the correct call here and avoids the stale-snapshot bug the commit explicitly calls out.
- The controller correctly invalidates `lastPublishedToggle`/`lastPublishedActive`/`lastPublishedLine` on song change (`MediaCardDesktopLyricsButtonController.ets:67-69`) so the de-dup short-circuit does not block a fresh AVSession from receiving its initial values.
- `init()` is idempotent via `this.initialized`. `destroy()` exists and removes both listeners — no leak risk.

### API Compatibility

- `session.setExtras` and `session.dispatchSessionEvent` are available in `avSession` and are wrapped in try/catch + `.catch` handlers — both throw-on-call and reject-after-call paths are handled.
- `abilityAccessCtrl.checkAccessToken` requires API 9+ which is well within the project baseline.
- `PersistentStorage.persistProp` is API-9-stable.

### Resource Completeness

- `app.string.show_desktop_lyrics_button`, `app.string.also_close_desktop_lyrics`, `app.string.also_close_desktop_lyrics_intro` are all present in `entry/src/main/resources/base/element/string.json`, `zh/element/string.json`, and `ug/element/string.json`. Localization coverage is complete.
- No "no overlay permission" string resource exists (`无悬浮窗权限`), aligned with the gap noted in scenario 8.

---

## Final Assessment

**Overall Verdict**: PASS WITH ISSUES

- **Fully covered scenarios** (4): 3, 4, 5, 6, 9.
- **Partially covered scenarios** (3): 1, 2, 7, 8. Scenarios 1/2 are limited by the platform (no third-party card-action / artist-row API); scenarios 7/8 are limited by the missing `SYSTEM_FLOAT_WINDOW` declaration in `module.json5` and a hard-coded Huawei settings want.
- **Unable to verify** (1): 10. Compact vs. expanded card layout is not under app control.
- **Failed scenarios** (0).

**Recommended Priority Fixes**:

1. **Add `ohos.permission.SYSTEM_FLOAT_WINDOW` to `entry/src/main/module.json5#requestPermissions`** with an appropriate `reason` (e.g. `$string:floating_window_permission_reason`) and `usedScene`. Without this, scenarios 7 and 8 do not work on real devices — `checkAccessToken` will always return `PERMISSION_DENIED`.
2. **Add a "no overlay permission" toast / snackbar** when `FloatingWindowPermission.ensurePermission()` returns false, to honour scenario 8's "弹出提示『无悬浮窗权限』" wording.
3. **Wire `onForeground` re-probe** in `NotificationPage` or `EntryAbility` so that returning from the system settings page after granting permission automatically flips the toggle back to ON, as scenario 8 step 5 requires.
4. **Resolve the floating-window-teardown cross-spec wiring** (`MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow` is a documented no-op today) so that scenario 6 step 6.1 ("用户点击确认，关闭桌面歌词悬浮窗") actually closes a currently-visible window, not only the persisted flag.
5. **Document the platform limitation** for scenarios 1, 2, 10 in the spec — the AVSession extras + custom session events emitted by this commit are forward-compatibility hooks. The user-visible artist-row swap on the system media card cannot be implemented today; if needed, build a dedicated live-window / floating surface that subscribes to `cardLyricsStateChanged`.
6. **Verify or generalize the settings want** in `FloatingWindowPermission.ensurePermission()` for non-Huawei builds; consider falling back to `abilityAccessCtrl.requestPermissionsFromUser` when the want fails.
