# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `1a493ecee9d1641b06c30334d6365dc9a070408c` — `[Human-AI] feat(spec27): 锁定桌面歌词 add notification-bar lock mirror + unlock tap`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec27/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/1a493ecee9d1641b06c30334d6365dc9a070408c_result.json`
- **Review Date**: 2026/05/15
- **Total Scenarios**: 7
- **Results**: 5 PASS | 2 PARTIAL | 0 FAIL | 0 UNABLE TO VERIFY

The commit's stated focus is the *notification-bar mirror* and *unlock-from-notification* layer on top of spec26 桌面歌词. It also funnels every lock writer (Settings VM, in-window Lock button, notification tap) through a single `DesktopLyricsController.requestLock(value)` entry point so persistence, touchable, notification mirror, and toast stay in lock-step. Spec27 is therefore an incremental layer — most of the underlying lock semantics (touchable pass-through, position persistence, control-panel hide, master-switch dependency) already shipped in spec26 and are still wired correctly here.

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | 桌面歌词开关关闭时锁定开关不可操作 | PASS | — |
| 2 | 用户开启锁定桌面歌词（Settings 路径） | PARTIAL | Settings-path toggle does not hide control panel (no in-window panel is shown from Settings, so the requirement is vacuously met, but cross-surface tap target is not addressed) |
| 3 | 用户通过设置页解锁桌面歌词 | PASS | — |
| 4 | 通过悬浮窗 Lock 按钮锁定 | PASS | — |
| 5 | 通过通知栏解锁 | PARTIAL | Notification tap *toggles* the persisted value (not strict "unlock"); if state drift makes it `false`, the tap will re-lock |
| 6 | 关闭再打开桌面歌词后保持锁定状态 | PASS | — |
| 7 | 锁定后位置在当前设备上持久保存 | PASS | — |

## Detailed Scenario Reviews

### Scenario 1: 桌面歌词开关关闭时，锁定桌面歌词开关不可操作

**Description**: With the master 桌面歌词 switch OFF, the 锁定桌面歌词 row must be visibly disabled and reject user taps.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:95` — `model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn` mirrors the master switch into the lock row's enable state on initialization (spec24 fix preserved).
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:176` — `this.lockDesktopLyricsVM.isEnabled = val` updates the enable state every time the master switch flips.
- `entry/src/main/ets/pages/LyricsSettingsPage.ets:242` — `enable: this.vm.lockDesktopLyricsVM.isEnabled` binds the UI row's enable state to the VM.

**Gaps**: none.

**Suggestions**: none.

---

### Scenario 2: 桌面歌词开关打开时，用户开启锁定桌面歌词

**Description**: User opens Settings-歌词 with master ON; taps 锁定桌面歌词 from OFF to ON. Expected outcome:
1. Floating window fixed in current position; touch-pass-through engaged.
2. Control panel hidden.
3. Toast "桌面歌词已锁定".
4. Notification-bar icon updated to locked.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:123` — Settings switch funnels through `DesktopLyricsController.getInstance().requestLock(val)`.
- `entry/src/main/ets/model/DesktopLyricsController.ets:366-379` — `requestLock(value)` persists, calls `applyLockedState()`, and shows the locked/unlocked toast based on `value`.
- `entry/src/main/ets/model/DesktopLyricsController.ets:387-400` — `applyLockedState()` calls `applyTouchableFromLock()` (touchable pass-through) and `publishLockNotification()` (notification mirror).
- `entry/src/main/ets/pages/DesktopLyricsWindow.ets:24,182` — `@StorageProp('lockDesktopLyrics')` drives `.hitTestBehavior(this.lock ? HitTestMode.Transparent : HitTestMode.Default)`, ensuring touches pass through when locked.
- `entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets:124-156` — Notification publish renders `桌面歌词已锁定`; idempotent re-publish via `lastPublished` cache.

**Gaps**:
- Scenario 2 step 5 says "桌面歌词悬浮窗上的控制面板隐藏". The Settings page is in the main app window, so the in-window control panel is not visible during this flow. The flow does NOT explicitly hide the in-window panel state from the Settings path. In practice the panel auto-hides when `lock` flips via `@StorageProp` (`DesktopLyricsWindow.ets:42,137` gate the panel on `!this.lock`), so the requirement is effectively met. Still worth a note: there is no explicit `controlPanelVisible = false` reset on lock-from-Settings (only the in-window Lock button at `DesktopLyricsWindow.ets:168` sets it).

**Suggestions**: Optional — In `applyLockedState()`, also push a key (e.g. `AppStorage.set('desktopLyricsControlPanelVisible', false)`) when newly locked, and bind the in-window page's `controlPanelVisible` to that key. Today the panel disappears because its render is gated on `!lock`, so the user observation matches the spec.

---

### Scenario 3: 桌面歌词已锁定时，用户通过设置页解锁桌面歌词

**Description**: Toggle 锁定桌面歌词 from ON to OFF in Settings. Expected: floating window regains touch interactivity, toast "桌面歌词已解锁", notification icon flips to unlocked.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:115-124` — `onChange` handler calls `requestLock(val)` for both ON and OFF.
- `entry/src/main/ets/model/DesktopLyricsController.ets:370-374` — Toast branches: `value ? desktop_lyrics_locked : desktop_lyrics_unlocked`.
- `entry/src/main/ets/model/DesktopLyricsController.ets:387-389` — `applyLockedState` re-applies touchable (now `true`, restoring interactivity) and re-publishes the notification (now "已解锁").
- `entry/src/main/resources/base/element/string.json:932` — `desktop_lyrics_unlocked` resource exists with value "桌面歌词已解锁".

**Gaps**: none.

**Suggestions**: none.

---

### Scenario 4: 用户通过桌面歌词悬浮窗上的锁定按钮锁定桌面歌词

**Description**: From the in-window control panel, tap "锁定". Expected: panel hides, window pass-through engaged, toast, Settings switch syncs, notification icon flips to locked.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/DesktopLyricsWindow.ets:167-170` — In-window Lock button handler sets `controlPanelVisible = false` then calls `DesktopLyricsController.getInstance().requestLock()` (defaults to `true`).
- `entry/src/main/ets/model/DesktopLyricsController.ets:366-378` — `requestLock(true)` persists `lockDesktopLyrics=true`, runs `applyLockedState()`, toasts locked.
- `entry/src/main/ets/model/DesktopLyricsController.ets:387-400` — `applyLockedState()` fans out: touchable, notification mirror, and `lockChangedListeners` (Settings VM observer).
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:45-52,133-134` — `onExternalLockChanged` is registered with the controller in `initFromModel`; when fired it mirrors the value into `lockDesktopLyricsVM.isOn` and `model.lockDesktopLyrics.isOn` (with a self-loop guard via the `!==` check). Settings page switch updates without re-entering its own `onChange`.

**Gaps**: none.

**Suggestions**: none.

---

### Scenario 5: 桌面歌词已锁定时，用户通过通知栏解锁桌面歌词

**Description**: With state currently LOCKED, the user taps the notification card. Expected: window regains touch, toast 已解锁, Settings switch syncs to OFF, notification icon flips to unlocked.

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets:56-77` — A `WantAgent` is pre-built with `parameters.spDesktopLyricsAction === 'toggleLock'` and `actionType: START_ABILITY`, then cached on `cachedWantAgent`. The published notification at `publish()` (line 134-147) attaches this WantAgent so the tap re-launches `EntryAbility`.
- `entry/src/main/ets/entryability/EntryAbility.ets:560-573` — `onNewWant` reads `spDesktopLyricsAction`, and on match invokes `DesktopLyricsController.getInstance().requestLock(!cur)` where `cur` is the current persisted value of `lockDesktopLyrics`.
- The downstream effects (touchable restore, toast, Settings sync, notification flip) follow the same `applyLockedState()` + listener-fanout pipeline already verified in scenarios 3 and 4.

**Gaps**:
1. **Tap semantics are "toggle", not "unlock"**. The spec scenario is unambiguous about direction ("已锁定 → 解锁"). Although in the happy path the persisted value should be `true` when the locked-state card is showing, any drift (e.g. publish lag, state writer bug, OS-side stale card) will cause the tap to re-lock instead of unlock. The controller already distinguishes locked vs. unlocked via `publish(true)` / `publish(false)`. A more defensive form would be to encode the action target in the WantAgent (`spDesktopLyricsAction: 'unlock'` for the locked card, `'lock'` for the unlocked card, with two distinct WantAgents or a parameterized one), then in `onNewWant` set explicitly `requestLock(false)` / `requestLock(true)` instead of `!cur`. Today both cards re-use the *same* cached agent, so the only routing signal is the current persisted value.
2. **One cached WantAgent for both states**. `init()` builds `cachedWantAgent` once at startup; `publish(locked)` always re-uses it. This is fine because the agent only carries a generic `toggleLock` marker, but it reinforces gap #1 — the system can never tell the two notification states apart, only the app can, via AppStorage at tap time.

**Suggestions**:
- Recommended: change the WantAgent parameter to carry the *desired* outcome (e.g. `'unlockLock'` for the locked-state card, `'lockLock'` for the unlocked-state card). Pre-build two `WantAgent` instances in `init()` and pick the appropriate one in `publish()`. Then in `EntryAbility.onNewWant`, dispatch directly without reading the current value:
  ```ts
  if (action === 'requestUnlock') requestLock(false)
  else if (action === 'requestLock') requestLock(true)
  ```
  This eliminates the race between the user's tap and a competing writer, and makes the directionality explicit at the source of truth (the notification publisher), matching the scenario wording.
- Alternative if a single agent is preferred: rebuild the cached WantAgent on each `publish(locked)` with the *target* (opposite) value embedded.

---

### Scenario 6: 锁定状态下关闭桌面歌词开关，再次打开桌面歌词时保持之前的锁定状态

**Description**: With master ON + lock ON, turn master OFF (window vanishes) then turn master ON again. The floating window should reappear with lock state preserved (touch-pass-through, position fixed).

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/DesktopLyricsController.ets:131-186` — `show()` calls `applyGeometry()`, `applyTouchableFromLock()`, and `publishLockNotification()` after `showWindow()`. Touchable is read from `AppStorage('lockDesktopLyrics')`, which has been persisted by `SettingsStore` and remains `true` across the master OFF→ON cycle because the lock toggle was never flipped.
- `entry/src/main/ets/model/DesktopLyricsController.ets:189-212` — `hide()` cancels the notification (`DesktopLyricsLockNotificationController.cancel()`) but does NOT clear `lockDesktopLyrics` — only the master switch (`desktopLyrics`) is flipped by the user. The lock value persists.
- `entry/src/main/ets/entryability/EntryAbility.ets:199` — `lockDesktopLyrics` is hydrated from `SettingsStore` into `AppStorage` on app launch (and continues to live in `AppStorage` across hide/show cycles within the same UIAbility).

**Gaps**: none.

**Suggestions**: none.

---

### Scenario 7: 锁定桌面歌词后，歌词位置在当前设备上持久保存

**Description**: User drags floating window to a position, enables lock, then restarts the app. After restart the floating window should re-appear at the locked position.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/DesktopLyricsController.ets:282-300` — `persistY()` writes `desktopLyricsYPercent` via `SettingsStore.save(...)`. (Called on PanGesture end from `DesktopLyricsWindow`.)
- `entry/src/main/ets/model/DesktopLyricsController.ets:233-251` — `applyGeometry()` reads `desktopLyricsYPercent` (default 30) and calls `win.moveWindowTo(...)` on every show.
- `entry/src/main/ets/entryability/EntryAbility.ets:122-127` — In `init()`, after persistence hydration, if `desktopLyrics` is `true` the controller auto-calls `show()`, which calls `applyGeometry()`. (Note: I'm citing the `DesktopLyricsController.init` block at controller lines 120-128; the cold-start auto-restore is the spec26 mechanism.)
- The lock state does not invalidate this — locking simply flips touchable; position is computed from the same persisted Y percent.

**Gaps**: none.

**Suggestions**: none.

---

## Cross-Cutting Issues

### Permission Coverage

The new notification mirror calls `notificationManager.publish()`. The current `entry/src/main/module.json5` declares these permissions:
- `ohos.permission.INTERNET`
- `ohos.permission.FILE_ACCESS_PERSIST`
- `ohos.permission.KEEP_BACKGROUND_RUNNING`
- `ohos.permission.VIBRATE`
- `ohos.permission.SYSTEM_FLOAT_WINDOW`

`notificationManager.publish` for a `SERVICE_INFORMATION` slot from a foreground UIAbility is allowed without an explicit `ohos.permission.NOTIFICATION_CONTROLLER` declaration in current API levels (it does require user-side notification permission, which is typically granted on first publish). The project already calls `notificationManager` from `DesktopLyricsLockNotificationController` (new) and indirectly through `NotificationLyricController` via AVSession metadata for the lock-screen / status-bar lyric scrolling, and these previously worked. The implementation correctly try/catches the publish call so a denied permission degrades gracefully to "no notification mirror" without breaking core lock behavior.

**Status**: PASS (matches existing notification-using code paths in the project; no new manifest-level permission gap).

### Navigation Completeness

- The Settings-page row exists and is enable-gated by the master switch.
- The in-window Lock button exists in the panel that opens on first tap.
- The notification card brings the app forward (`START_ABILITY` action with `UPDATE_PRESENT_FLAG`), and `EntryAbility.onNewWant` is the documented entry point for re-launch.

**Status**: PASS.

### State Management

The commit consolidates lock-state writers to a single funnel (`DesktopLyricsController.requestLock`) which now does:
1. `SettingsStore.save('lockDesktopLyrics', value)` — persisted and pushed into AppStorage by SettingsStore.
2. `applyLockedState()`:
   - `applyTouchableFromLock()` — re-applies window touchable.
   - `publishLockNotification()` — re-publishes notification mirror.
   - Listener fan-out — Settings VM `onExternalLockChanged` synchronizes the switch.
3. Toast.

The listener fan-out walks a `.slice()` copy of the listener array (`DesktopLyricsController.ets:393`), which is the correct pattern for re-entrant safety. The Settings VM listener has an `!==` guard before re-assignment so it does not bounce the VM's own `onChange` back into `requestLock` and cause an infinite loop. The page tears down the listener in `aboutToDisappear` via `vm.dispose()` (added in this commit).

**Status**: PASS — clean and re-entrancy-safe.

### API Compatibility

- `@kit.NotificationKit.notificationManager.publish` — stable since API 9; `SERVICE_INFORMATION` slot type and `NOTIFICATION_CONTENT_BASIC_TEXT` are both pre-API-12.
- `@kit.AbilityKit.wantAgent.getWantAgent` + `WantAgentFlags.UPDATE_PRESENT_FLAG` — stable.
- `UIAbility.onNewWant(want, launchParam)` — stable since API 9.
- `@kit.ArkUI.window.setWindowTouchable` — used in spec26, still valid.

**Status**: PASS.

### Resource Completeness

- `app.string.desktop_lyrics` — present (base/zh/ug).
- `app.string.desktop_lyrics_locked` — present (base value "桌面歌词已锁定").
- `app.string.desktop_lyrics_unlocked` — present (base value "桌面歌词已解锁").
- `app.string.lock_desktop_lyrics` — present (used by both the in-window Lock button and the Settings row title).
- `DesktopLyricsLockNotificationController.lookupString` has a hard-coded Chinese fallback so the notification still renders even if the resource lookup fails.

**Status**: PASS.

---

## Final Assessment

**Overall Verdict**: PASS WITH ISSUES

- **Fully covered scenarios**: 1, 3, 4, 6, 7.
- **Partially covered scenarios**:
  - **Scenario 2** — the Settings-path lock flow does not explicitly hide the in-window control panel state (it auto-hides via the `!this.lock` render gate, so the user-visible behavior matches the spec; nothing is broken, but the wiring is incidental).
  - **Scenario 5** — the notification-tap path is a *toggle*, not a strict directional unlock. In the happy path the result matches the spec; in any state-drift scenario the tap could re-lock instead of unlocking.

**Recommended Priority Fixes** (ordered by user impact):

1. **(Scenario 5)** Make the notification-tap action directional. Encode the *target* state (`'requestUnlock'` for the locked card, `'requestLock'` for the unlocked card) in the WantAgent parameter, and dispatch directly in `onNewWant`. This removes any race between the publish-time state and the tap-time state and matches the scenario wording precisely.
2. **(Scenario 2 — nice-to-have)** Add an explicit `controlPanelVisible = false` reset on every external lock-flip (e.g. via an AppStorage key written by `applyLockedState` when newly locked, bound to the page's `controlPanelVisible`). The current behavior happens to do the right thing because the panel render is gated on `!lock`, but making this explicit hardens it against future refactors that might split panel visibility from lock state.

**Strengths of this commit**:
- Single-writer funnel via `requestLock(value)` is the right abstraction — it makes future writers trivial to add and impossible to forget the fan-out steps.
- Listener registration uses a stable arrow-function field reference so add/remove identity holds.
- Listener iteration uses `.slice()` to be re-entrancy-safe.
- Notification publish is idempotent via `lastPublished` cache, so repeated calls do not churn the notification shade.
- All notification operations are try/catched with warn-level logging; failure degrades to "no mirror" rather than crashing the app.
- WantAgent is built once and cached; matches the AudioPlayerService precedent in the project.
- One-shot teardown via `aboutToDisappear` / `dispose()` prevents listener leaks across navigation.

**Key file locations for follow-up**:
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/model/DesktopLyricsController.ets` (lines 366-436)
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets` (entire file, new)
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/entryability/EntryAbility.ets` (lines 433-573)
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets` (lines 45-52, 115-134, 259-265)
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/LyricsSettingsPage.ets` (lines 47-52 — `aboutToDisappear` teardown hook)
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/DesktopLyricsWindow.ets` (lines 163-170, 182 — in-window Lock button + hit-test gate)
