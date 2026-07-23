# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `eae8d5b1f615016375db937727c22934f852e258`
- **Commit Title**: `[Human-AI] feat(spec26): add draggable desktop lyrics floating window`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec26/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/eae8d5b1f615016375db937727c22934f852e258_result.json`
- **Review Date**: 2026/05/15
- **Total Scenarios**: 13
- **Results**: 8 PASS | 4 PARTIAL | 0 FAIL | 1 UNABLE TO VERIFY

The commit introduces a new singleton `DesktopLyricsController`, a new `pages/DesktopLyricsWindow.ets`, hydration/teardown in `EntryAbility`, and wires the master + lock toggles in `LyricsSettingsViewModel`. The structural pieces — system float window lifecycle, lyric/subtitle observable plumbing, persistence keys with sensible defaults, permission probe, pan-to-drag, tap-to-toggle, lock pass-through — are all present. Several spec corners are not honored: the "暂无歌词" fallback text is not rendered, the lock-toggle row stays disabled on cold start when the master is persisted ON, and the desktop-lyrics master toggle does not re-enable the lock row's "enabled" flag on the very first render.

## Scenario Coverage Summary

| #  | Scenario                                              | Verdict           | Key Gaps |
|----|-------------------------------------------------------|-------------------|----------|
| 1  | Enable desktop lyrics with permission granted         | PARTIAL           | "暂无歌词" fallback not rendered when both `line` and `subTitle` are empty |
| 2  | Enable desktop lyrics without permission              | PASS              | — |
| 3  | Disable desktop lyrics                                | PASS              | — |
| 4  | Drag lyric window via gesture                         | PASS              | — |
| 5  | Tap lyric text to toggle control panel                | PASS              | — |
| 6  | Lock desktop lyrics from in-window panel              | PARTIAL           | No toast on lock from in-window button (spec scenario 6 step 5) |
| 7  | Unlock desktop lyrics via Settings switch             | PARTIAL           | `lockDesktopLyricsVM.isEnabled` initialized to `false`; the lock row is disabled on entry, so the user cannot interact with it from Settings |
| 8  | Lyric content updates on song change / line tick      | PASS              | — |
| 9  | Auto-restore on app cold start                        | PASS              | — |
| 10 | Adjust font size via control panel                    | PASS              | — |
| 11 | Change color via control panel                        | PASS              | — |
| 12 | Control playback via in-window panel                  | PASS              | — |
| 13 | Locked window passes touches through                  | UNABLE TO VERIFY  | Static review can't confirm `setWindowTouchable(false)` actually achieves pass-through on a real device; code path is correct |

## Detailed Scenario Reviews

### Scenario 1: Enable desktop lyrics with permission granted

**Description**: User opens 设置-歌词, flips the "桌面歌词" switch ON, permission is granted, desktop lyrics window appears, toast "桌面歌词已开启" shown, switch state persisted. When no lyrics, shows "暂无歌词".

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets:131-157` — `onDesktopLyricsChanged()` probes permission, persists `desktopLyrics`, calls `DesktopLyricsController.show()`, toasts `desktop_lyrics_opened`.
- `entry/src/main/ets/model/DesktopLyricsController.ets:118-167` — `show()` creates `TYPE_SYSTEM_ALERT` window, loads `pages/DesktopLyricsWindow`, applies geometry + touchable.
- `entry/src/main/ets/model/FloatingWindowPermission.ets:42-101` — `ensurePermission()` checks token, routes to system settings if missing.
- `entry/src/main/resources/base/element/string.json:920,928` — `desktop_lyrics_closed` / `desktop_lyrics_opened` resources exist.
- `entry/src/main/resources/base/profile/main_pages.json` — `pages/DesktopLyricsWindow` registered.
- `entry/src/main/module.json5:52-60` — `ohos.permission.SYSTEM_FLOAT_WINDOW` declared with reason + usedScene.

**Gaps**:
- `DesktopLyricsWindow.displayMain()` (`pages/DesktopLyricsWindow.ets:177-191`) returns plain `''` when both `line` and `fallback` are empty. The comment on lines 184-190 explicitly acknowledges: *"the simple contract: when nothing is known we return an empty string so the Text node degenerates to invisible."* Spec scenario 1 step 5 mandates: *"若当前无歌词则显示'暂无歌词'"*. The resource `$r('app.string.no_lyrics')` exists (`base/element/string.json:2256`, zh value "暂无歌词") but is never referenced.
- A user enabling the feature on a song without lyrics (or before MiniLyricsController emits its first tick) will see an empty float window for the first display, which contradicts the spec.

**Suggestions**:
1. In `DesktopLyricsWindow.build()`, render an additional `Text($r('app.string.no_lyrics'))` node when `!this.hasLyrics && this.line.length === 0 && this.fallback.length === 0`, or change `displayMain()` to return a sentinel and render the Resource conditionally.
2. Alternatively seed `desktopLyricsHasLyrics=false` and have `DesktopLyricsController.init()` push the localized "no lyrics" string into `desktopLyricsLine` when the lyric stream reports no lyrics. The current `lyricsListener` (`DesktopLyricsController.ets:79-84`) only relays raw text — it does not insert the fallback.

---

### Scenario 2: Enable desktop lyrics without permission

**Description**: User flips switch ON, permission is denied, toast "没有悬浮窗权限", switch reverts to OFF, window not shown.

**Verdict**: PASS

**Evidence**:
- `viewmodel/LyricsSettingsViewModel.ets:131-141` — `ensurePermission()` returns `false`, viewmodel reverts both `desktopLyricsVM.isOn` and `model.desktopLyrics.isOn` to `false`, toasts `no_floating_window_permission`, **does not** call `show()` and **does not** persist `desktopLyrics=true`.
- `string.json:232` — `no_floating_window_permission` resource present.

---

### Scenario 3: Disable desktop lyrics

**Description**: User flips switch OFF, window disappears, toast "桌面歌词已关闭", state persisted.

**Verdict**: PASS

**Evidence**:
- `viewmodel/LyricsSettingsViewModel.ets:142-156` — On `val=false`, calls `SettingsStore.save('desktopLyrics', false)`, calls `DesktopLyricsController.hide()`, toasts `desktop_lyrics_closed`, disables the lock toggle row.
- `model/DesktopLyricsController.ets:170-183` — `hide()` calls `destroyWindow()` and stops the geometry watcher; idempotent.

---

### Scenario 4: Drag lyric window via gesture

**Description**: When desktop lyrics is showing and unlocked, the user drags the lyric area to move the window. Final Y is persisted.

**Verdict**: PASS

**Evidence**:
- `pages/DesktopLyricsWindow.ets:107-121` — `PanGesture({ direction: PanDirection.Vertical, distance: 5 })` with `onActionUpdate` calling `nudgeYPx(event.offsetY)` and `onActionEnd` calling `persistY()`.
- `model/DesktopLyricsController.ets:228-271` — `nudgeYPx()` clamps to `[0, screenH - heightPx]` and calls `win.moveWindowTo()`; `persistY()` converts current Y px to percent and writes `desktopLyricsYPercent` via `SettingsStore.save`.
- Spec wording "支持水平和垂直方向的自由拖动" — the controller decides X is fixed to 0 (full-width window per the controller comment at lines 14-16). This is a documented design deviation, not a bug, since vertical drag plus full-width layout satisfies the intent and X-drag with a screen-wide window has no meaning. Verdict remains PASS, with a note.

**Notes**:
- The spec mentions horizontal drag but the implementation chose a full-width window. Acceptable interpretation; flagged for awareness.

---

### Scenario 5: Tap lyric text to toggle control panel

**Description**: Single tap on lyric text (no movement) toggles the music + style panels.

**Verdict**: PASS

**Evidence**:
- `pages/DesktopLyricsWindow.ets:99-106` — `TapGesture({ count: 1 }).onAction` flips `this.controlPanelVisible` while not locked.
- `GestureGroup(GestureMode.Exclusive, ...)` (`:99`) correctly separates tap from pan so a drag does not also fire a tap.
- `:44-76` (style panel) and `:125-164` (music panel) both gated by `this.controlPanelVisible && !this.lock`.

---

### Scenario 6: Lock desktop lyrics from in-window panel

**Description**: User taps lyric → control panel opens → taps Lock → window enters locked state (touches pass through), control panel hides, toast "桌面歌词已锁定", lock persisted.

**Verdict**: PARTIAL

**Evidence**:
- `pages/DesktopLyricsWindow.ets:151-158` — Lock button hides the panel (`this.controlPanelVisible = false`) and calls `DesktopLyricsController.getInstance().requestLock()`.
- `model/DesktopLyricsController.ets:326-329` — `requestLock()` persists `lockDesktopLyrics=true` and calls `applyTouchableFromLock()`.
- `model/DesktopLyricsController.ets:275-296` — `applyTouchableFromLock()` reads `lockDesktopLyrics` and calls `win.setWindowTouchable(!locked)`.

**Gaps**:
- Spec scenario 6 step 5 says: *"弹出toast提示'桌面歌词已锁定'"*. `requestLock()` does **not** emit a toast. The settings-page lock toggle (`LyricsSettingsViewModel.ets:98-101`) toasts `desktop_lyrics_locked` / `desktop_lyrics_unlocked`, but the in-window Lock button takes a different code path through `DesktopLyricsController.requestLock()`, which has no toast.
- Note: `promptAction.showToast` from inside a float-window page would target the float-window's UIContext; whether the toast surfaces depends on the system. Still, the spec explicitly requires it and the current code makes no attempt.

**Suggestions**:
1. Either toast inside `requestLock()` (importing `promptAction` and calling `showToast({ message: $r('app.string.desktop_lyrics_locked') })`), or fire a toast from `DesktopLyricsWindow.build()` Lock button's `onClick` before delegating.

---

### Scenario 7: Unlock desktop lyrics via Settings page

**Description**: User enters 设置-歌词, finds "锁定桌面歌词" switch (currently ON), turns it OFF, lyrics become touchable again, toast "桌面歌词已解锁".

**Verdict**: PARTIAL

**Evidence**:
- `viewmodel/LyricsSettingsViewModel.ets:91-103` — The lock toggle handler updates the model, persists `lockDesktopLyrics`, calls `DesktopLyricsController.applyTouchableFromLock()`, and toasts `desktop_lyrics_unlocked` / `desktop_lyrics_locked`. Logic is correct.
- `pages/LyricsSettingsPage.ets:217-235` — The HdsListItemCard binds `enable: this.vm.lockDesktopLyricsVM.isEnabled`.

**Gaps**:
- **Initialization bug**: `model/LyricsSettingsModel.ets:11` declares `lockDesktopLyrics = new SwitcherRowModel(false, false, …)` — i.e. `isEnabled` defaults to **`false`**. `viewmodel/LyricsSettingsViewModel.ets:91-93` constructs `lockDesktopLyricsVM` with `model.lockDesktopLyrics.isEnabled`, which is `false`. `isEnabled` is only updated when the master toggle changes (`:145 — this.lockDesktopLyricsVM.isEnabled = val`).
- Consequence: when a user closes the app with `desktopLyrics=true` + `lockDesktopLyrics=true`, then reopens and navigates to 设置-歌词, the lock row appears **disabled** (greyed out, `enable=false`). The user cannot toggle it OFF from Settings — scenario 7 is unreachable until the user toggles the master switch or restarts the app and toggles the master.
- Worse, the page also calls `new LyricsSettingsViewModel()` on every entry (`pages/LyricsSettingsPage.ets:44`), so the bug reproduces every time the page is entered.

**Suggestions**:
1. In `LyricsSettingsViewModel.initFromModel()` (around line 73), after reading `persistedDesktop`, set `model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn` so the SwitcherRowViewModel constructor at `:91` picks up the correct initial enable state.

---

### Scenario 8: Lyric content updates on song change / line tick

**Description**: When lyric line changes, window updates. When song changes, window updates. When no lyrics, show subtitle; if also empty, show blank.

**Verdict**: PASS

**Evidence**:
- `model/DesktopLyricsController.ets:79-96` — `lyricsListener` writes `desktopLyricsLine` + `desktopLyricsHasLyrics` + `desktopLyricsSubLine` on every MiniLyricsController emission. `songChangedListener` clears those keys and seeds `desktopLyricsArtistFallback` from the new song's `subTitle`.
- `pages/DesktopLyricsWindow.ets:18-23` — `@StorageProp` bindings for all four keys.
- `pages/DesktopLyricsWindow.ets:177-191` — `displayMain()` priority `line → fallback → empty`, matching the spec scenario 8 step 4 ("副标题为空则显示空白").
- Subtitle line (`subLine` at `:86-93`) — when MiniLyricsController emits a subText (e.g. karaoke translation), it is published via `MiniLyricsController.currentSubLine` and read into AppStorage at `DesktopLyricsController.ets:82-83`.

---

### Scenario 9: Auto-restore on app cold start

**Description**: When the app launches with `desktopLyrics=true` persisted, the float window appears automatically at the persisted Y.

**Verdict**: PASS

**Evidence**:
- `entryability/EntryAbility.ets:122-148` — `PersistentStorage.persistProp('desktopLyrics', false)` registers the key for auto-restore.
- `entryability/EntryAbility.ets:197-235` — Hydration from `SettingsStore` (Preferences) into AppStorage for `desktopLyrics`, `lockDesktopLyrics`, `desktopLyricsYPercent`, `desktopLyricsFontSizeDp`, `desktopLyricsColor`.
- `entryability/EntryAbility.ets:427-430` — `DesktopLyricsController.init(this.context)` is called **after** hydration, MiniLyricsController init, and AudioPlayerService.initContext.
- `model/DesktopLyricsController.ets:108-114` — `init()` reads `AppStorage.get<boolean>('desktopLyrics')` and calls `show()` when true.

---

### Scenario 10: Adjust font size via control panel

**Description**: Style panel has A-/A+ buttons. Each press changes font by 4 dp, clamped to [12, 36]. Changes persist.

**Verdict**: PASS

**Evidence**:
- `pages/DesktopLyricsWindow.ets:45-59` — A- and A+ buttons call `bumpFontSize(-1)` / `bumpFontSize(1)`.
- `model/DesktopLyricsController.ets:29-32` — Constants `FONT_SIZE_MIN=12`, `FONT_SIZE_MAX=36`, `FONT_SIZE_STEP=4`.
- `model/DesktopLyricsController.ets:299-316` — `setFontSize()` clamps to `[12, 36]`; `bumpFontSize()` steps by `FONT_SIZE_STEP`; `setFontSize()` writes through `SettingsStore.save('desktopLyricsFontSizeDp', v)`.
- `pages/DesktopLyricsWindow.ets:22,82` — `@StorageProp('desktopLyricsFontSizeDp')` propagates the new value to `Text.fontSize(this.fontSizeDp)`.
- Default at `EntryAbility.ets:146,228` — `20` dp, well inside [12, 36] and on the 4 dp step grid from 12.

---

### Scenario 11: Change color via control panel

**Description**: Palette of highlight/green/red/white colors. Tap changes color immediately and persists.

**Verdict**: PASS

**Evidence**:
- `pages/DesktopLyricsWindow.ets:33-38` — Palette `[0xFF0470E6, 0xFF057748, 0xFFBE002F, 0xFFFFFFFF]` (highlight blue, green, red, white) — matches spec wording.
- `pages/DesktopLyricsWindow.ets:60-70` — `ForEach` renders one Circle per palette ARGB; tap calls `setColor(argb)`.
- `model/DesktopLyricsController.ets:319-321` — `setColor()` persists via `SettingsStore.save('desktopLyricsColor', argb)`.
- `pages/DesktopLyricsWindow.ets:23,83` — `@StorageProp('desktopLyricsColor')` flows into `Text.fontColor(this.colorArgb)`.
- The selection-indicator stroke (`:65 — stroke(this.colorArgb === argb ? Color.White : Color.Transparent)`) gives visual feedback for the current selection.

---

### Scenario 12: Control playback via in-window panel

**Description**: Music panel has previous / play-pause / next / lock buttons. Each performs the matching action on the player.

**Verdict**: PASS

**Evidence**:
- `pages/DesktopLyricsWindow.ets:127-150` — Previous → `AudioPlayerService.skipPrevious()`; play/pause → `togglePlayPause()`; next → `skipNext()`.
- `model/AudioPlayerService.ets:1172,1493,1529` — All three methods exist on the service.
- `pages/DesktopLyricsWindow.ets:25` — `@StorageProp('isPlaying')` drives the play/pause icon swap (`:137 — Button(this.isPlaying ? '||' : '>')`).
- Lock button: see Scenario 6.

**Notes**:
- Previous/play-pause/next button labels use plain `||` and `>` ASCII characters with a code comment explaining the deliberate choice (`:134-137`). Not a defect but visually crude; acceptable per spec which does not specify icons.

---

### Scenario 13: Locked window passes touches through

**Description**: When locked, the float window does not consume touches; the user can interact with whatever is underneath.

**Verdict**: UNABLE TO VERIFY

**Evidence**:
- `model/DesktopLyricsController.ets:275-296` — `applyTouchableFromLock()` calls `this.win.setWindowTouchable(!locked)`. Returns a Promise on newer SDKs, with a graceful try/catch fallback.
- `pages/DesktopLyricsWindow.ets:170` — `.hitTestBehavior(this.lock ? HitTestMode.Transparent : HitTestMode.Default)` as the in-process complement.
- Both the system-level `setWindowTouchable` and the in-process `hitTestBehavior` are present, which is the correct belt-and-suspenders strategy.

**Why "Unable to verify"**:
- Whether `setWindowTouchable(false)` actually forwards touches to the underlying app/desktop is device- and API-version-dependent. Static review confirms the call is wired correctly; runtime verification on a real device is required to confirm pass-through works as advertised in spec scenario 13 step 3.

---

## Cross-Cutting Issues

### Permission Coverage

`entry/src/main/module.json5:52-60` declares `ohos.permission.SYSTEM_FLOAT_WINDOW` with reason and usedScene. The permission is correctly probed by `FloatingWindowPermission.checkPermission()` before showing the float window. **PASS**.

### Navigation Completeness

- `pages/DesktopLyricsWindow` registered in `resources/base/profile/main_pages.json`. **PASS**.
- The Settings → 歌词 → 桌面歌词 row is in `LyricsSettingsPage` and renders correctly. **PASS**.

### State Management

- AppStorage keys used (`desktopLyrics`, `lockDesktopLyrics`, `desktopLyricsYPercent`, `desktopLyricsFontSizeDp`, `desktopLyricsColor`, `desktopLyricsLine`, `desktopLyricsSubLine`, `desktopLyricsHasLyrics`, `desktopLyricsArtistFallback`) — all created in `EntryAbility.onCreate` and bound via `@StorageProp` in the float window page.
- Persistent keys (`desktopLyrics`, `lockDesktopLyrics`, `desktopLyricsYPercent`, `desktopLyricsFontSizeDp`, `desktopLyricsColor`) are registered with `PersistentStorage.persistProp` **and** also hydrated from `SettingsStore.get(...)` so the Preferences-backed source-of-truth wins. Defensive pattern, consistent with the rest of the project.
- **Concern**: `lockDesktopLyricsVM.isEnabled` is **not** mirrored to a StorageProp or seeded from `desktopLyrics` at ViewModel construction (see scenario 7 gap).

### API Compatibility

- `window.WindowType.TYPE_SYSTEM_ALERT`, `window.createWindow`, `window.Window.setUIContent`, `setWindowBackgroundColor`, `resize`, `moveWindowTo`, `setWindowTouchable`, `showWindow`, `destroyWindow` — all standard `@kit.ArkUI` window APIs available in current targets. Used elsewhere in the project (FloatingStatusBarLyricsController) without issue. **PASS**.
- `setWindowTouchable` return type variation between SDKs is handled defensively (`:285-291`). **PASS**.
- `MiniLyricsListener` signature matches the controller's exported type. **PASS**.

### Resource Completeness

- All required string resources exist in both `base` and `zh` locales: `desktop_lyrics`, `lock_desktop_lyrics`, `desktop_lyrics_opened`, `desktop_lyrics_closed`, `desktop_lyrics_locked`, `desktop_lyrics_unlocked`, `no_floating_window_permission`, `previous`, `next`.
- **Missing usage**: `no_lyrics` resource exists (`base/element/string.json:2256`, zh = "暂无歌词") but is **never referenced by the desktop lyrics window** — see scenario 1 gap.

---

## Final Assessment

**Overall Verdict**: PASS WITH ISSUES

The desktop lyrics feature is structurally complete and well-architected: the singleton controller correctly mirrors the spec25 pattern, the float window lifecycle is bookended by `EntryAbility.onCreate` / `onWindowStageDestroy`, persistence is properly wired through `SettingsStore` + `PersistentStorage`, and the gesture handling cleanly separates tap from pan via `GestureGroup(Exclusive)`. 9 of 13 scenarios pass cleanly; 4 have specific, narrow gaps that do not invalidate the feature.

- **Fully covered scenarios**: 2, 3, 4, 5, 8, 9, 10, 11, 12.
- **Partially covered scenarios**:
  - **1** — "暂无歌词" fallback string not rendered (high user impact: first-time enable on a song without lyrics shows an empty window).
  - **6** — In-window Lock button does not emit the "桌面歌词已锁定" toast (low user impact: the operation succeeds, only the feedback is missing).
  - **7** — Lock toggle row on Settings page initializes with `isEnabled=false` and only flips to `true` when the master switch is toggled in the same session. After a cold restart with `desktopLyrics=true` already persisted, the user cannot interact with the Settings-page lock row to unlock — they must first toggle master OFF/ON or use the in-window Lock button reversal flow, which doesn't currently exist. High user impact.
- **Not covered scenarios**: none (no FAILs).
- **Cannot statically verify**: 13 (touch pass-through behavior of `setWindowTouchable(false)`).

**Recommended Priority Fixes**:

1. **[High]** `LyricsSettingsViewModel.initFromModel()` — seed `model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn` before constructing `lockDesktopLyricsVM` (around `viewmodel/LyricsSettingsViewModel.ets:73`). Unblocks scenario 7 after cold start.
2. **[High]** `DesktopLyricsWindow.build()` — render `Text($r('app.string.no_lyrics'))` when `!this.hasLyrics && this.line.length === 0 && this.fallback.length === 0`, replacing the silent empty-string fallback at `pages/DesktopLyricsWindow.ets:177-191`. Honors scenario 1 step 5.
3. **[Low]** `DesktopLyricsController.requestLock()` — show a toast (`$r('app.string.desktop_lyrics_locked')`) before/after the `applyTouchableFromLock()` call so scenario 6 step 5 is satisfied. Either inside the controller or as a separate call from the in-window Lock button `onClick` in `DesktopLyricsWindow.ets:151-158`.
4. **[Verification]** Manually test scenario 13 on a real device to confirm `setWindowTouchable(false)` truly forwards touches to the underlying app/launcher.
