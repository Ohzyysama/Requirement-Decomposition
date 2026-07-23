# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `25e2f1cdd8ae05af44b1b9419eddf5d93e1c00c2` — "feat(logic): wire lyrics view blur to player rendering and persistence"
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec13/plan.md` (歌词视图模糊 SPEC)
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/25e2f1cdd8ae05af44b1b9419eddf5d93e1c00c2_result.json`
- **Review Date**: 2026-05-12
- **Total Scenarios**: 7
- **Results**: 5 PASS | 1 PARTIAL | 0 FAIL | 1 UNABLE TO VERIFY

The commit wires the previously UI-only lyrics-view blur switch (Spec12 placeholder) to a real persisted setting and applies a distance-based `.blur()` to non-current lyric lines on `PlayerPage`. The implementation closely follows the Wave 1 / Wave 2 / Wave 3 plan in `wsh-output/spec13/logic/plan.md` and reuses the existing `lyricsTextSize` persistence pattern.

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | Default OFF, lyrics render unblurred on first entry | PASS | — |
| 2 | Toggle ON applies distance-graded blur to non-current lines | PASS | — |
| 3 | Toggle OFF removes blur, all lines clear | PASS | — |
| 4 | Blur tracks current line as playback advances | PASS | — |
| 5 | Drag/scroll temporarily suppresses blur | PASS | — |
| 6 | Song change re-anchors blur to new current line | PASS | — |
| 7 | Sub-API-12 device: switch shown but disabled, with hint text | PARTIAL | Hint text under the switch is missing; only `enable=false` is wired. Also UNABLE TO VERIFY end-to-end without a low-API device. |

## Detailed Scenario Reviews

### Scenario 1: Default OFF, lyrics render unblurred on first entry

**Description**: User enters 设置 > 歌词 > 歌词界面 for the first time. Switch shows OFF; player lyrics render with no blur.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/entryability/EntryAbility.ets:79` — `PersistentStorage.persistProp('lyricsBlur', false)` declares default.
- `entry/src/main/ets/entryability/EntryAbility.ets:185` — restored from `SettingsStore` (default `false`) into AppStorage at cold start.
- `entry/src/main/ets/model/LyricsInterfaceModel.ets:48,55` — `loadFromStorage` reads `lyricsBlur` from AppStorage, default `false`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:32` — `@Track public blur: boolean = false`.
- `entry/src/main/ets/pages/LyricsInterfacePage.ets:151` — switch `isCheck` bound to `this.viewModel.blur`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:339-341,453` — `effectiveBlurRadius()` returns 0 when `blurEnabled` is false, then `.blur(this.effectiveBlurRadius())` applied unconditionally on the outer `Column`.
- `entry/src/main/ets/pages/PlayerPage.ets:86,1236` — `@StorageProp('lyricsBlur') lyricsBlur: boolean = false` flows into `blurEnabled`.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 2: Toggle ON applies distance-graded blur

**Description**: User opens the switch; non-current lines get blur whose intensity grows with distance from the current line, capped at a max.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/LyricsInterfacePage.ets:152-154` — `onChange` calls `this.viewModel.updateBlur(val)`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:149-154` — `updateBlur` updates `@Track blur`, model, and persists via `SettingsStore.save('lyricsBlur', value)` (writes to both AppStorage and Preferences memory cache).
- `entry/src/main/ets/pages/PlayerPage.ets:1236-1240` — for each line in the `ForEach`, `lineDistance = currentLineIndex >= 0 ? abs(index - currentLineIndex) : 0`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:7-10,338-347` — `BLUR_STEP_VP = 1.5`, `BLUR_MAX_VP = 6.0`; radius scales linearly with distance and is capped at the max (matches "距离越近越轻 / 距离越远越重 / 超过一定距离达到最大值").
- `entry/src/main/ets/components/LyricsLineComponent.ets:341` — current line returns 0 (clear), satisfying "当前正在播放的歌词行清晰显示".

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 3: Toggle OFF removes blur

**Description**: User closes the switch; all lyric lines render with the same clarity.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:149-154` — same path; `value=false` persists OFF.
- `entry/src/main/ets/components/LyricsLineComponent.ets:339` — `if (!this.blurEnabled) return 0` short-circuits before any per-line math runs; the outer `Column.blur(0)` is effectively a no-op.
- Reactivity: `PlayerPage.@StorageProp('lyricsBlur')` re-renders the `ForEach` body on toggle, so the change is live without re-entering the player page.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 4: Blur tracks the current line in real time during playback

**Description**: As playback advances, the blur "follow" changes — new current line becomes clear, the previous current line gains blur, and all distances are recomputed.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:903` — `currentLyricsLineIndex` (Track) is reassigned every progress refresh.
- `entry/src/main/ets/pages/PlayerPage.ets:1237-1239` — `lineDistance` is recomputed inline in the `ForEach` body using the live `currentLyricsLineIndex`. ArkUI re-evaluates the prop list when the Track value changes, so every visible line's `lineDistance` (and therefore `effectiveBlurRadius()`) refreshes in the same frame.
- `entry/src/main/ets/components/LyricsLineComponent.ets:26-28` — `blurEnabled`, `lineDistance`, `suppressBlur` are all `@Prop`, so each `ForEach` iteration receives the up-to-date values.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 5: Manual drag/scroll temporarily suppresses blur

**Description**: While the user drags or scrolls the lyrics list, all blur is removed; after release + cooldown, blur returns based on the (possibly resumed) current line.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LyricsViewModel.ets:23,154-166` — `@Track isUserScrolling` flips to `true` on `onUserScrollStart` and back to `false` after `USER_SCROLL_RESUME_DELAY` via `resumeAutoSync`.
- `entry/src/main/ets/pages/PlayerPage.ets:1295-1299` — `onTouch` on the lyrics List calls `lyricsViewModel.onUserScrollStart()` on `TouchType.Down`.
- `entry/src/main/ets/pages/PlayerPage.ets:1240` — `suppressBlur: this.vm.lyricsViewModel.isUserScrolling` propagates the flag into the per-line component.
- `entry/src/main/ets/components/LyricsLineComponent.ets:340` — `if (this.suppressBlur) return 0` short-circuits before any other check; all visible lines render clear during scroll.
- After release the timer drops `isUserScrolling` to `false`, the `ForEach` re-renders, and blur returns based on the now-restored current line — matching "停止拖动/滚动后，模糊效果恢复".

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 6: Song change re-anchors blur to the new current line

**Description**: User skips to next/prev/queue/auto-next; lyrics reload and blur re-anchors to the new song's current line.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:556,621` — `currentLyricsLineIndex` is reset to `-1` on song-change paths (e.g. `onSongChanged`), then re-assigned on the next progress tick (line 903).
- `entry/src/main/ets/pages/PlayerPage.ets:1237-1239` — when `currentLyricsLineIndex < 0`, `lineDistance` is forced to `0`, so `LyricsLineComponent.effectiveBlurRadius()` returns 0 (line 342), matching the brief "all clear" window during reload (acceptable per the plan's §2.5).
- Once `currentLyricsLineIndex` is reassigned, the new `ForEach` evaluation propagates fresh distances; blur re-anchors automatically.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 7: Sub-API-12 device — switch shown but disabled, with hint text

**Description**: On devices with system version below 12, the switch is rendered but disabled, and a hint message below explains the requirement.

**Verdict**: PARTIAL (also UNABLE TO VERIFY end-to-end without a low-API device)

**Evidence (what's implemented)**:
- `entry/src/main/ets/model/LyricsInterfaceModel.ets:75-81` — `static isBlurSupported()` returns `deviceInfo.sdkApiVersion >= 12`, with try/catch falling back to `true`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:39` — `@Track public isBlurSupported = LyricsInterfaceModel.isBlurSupported()`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:150` — `updateBlur` early-returns if not supported, so even a stuck UI cannot persist the value.
- `entry/src/main/ets/pages/LyricsInterfacePage.ets:159` — `enable: this.viewModel.isBlurSupported` on the `HdsListItemCard`, mirroring the `UserInterfacePage.ets:293,312,355,399` pattern.

**Gaps**:
- Spec scenario 7 step 3 explicitly requires: "开关下方显示提示信息，说明仅支持系统版本12及以上的设备." The current code only disables the switch — there is no `Text` below the row or any other hint. `LyricsInterfacePage.ets:142-165` shows the switch row alone, with no conditional hint string.
- No corresponding string resource (e.g. `lyrics_view_blur_min_api_hint`) was added to `entry/src/main/resources/base/element/string.json`.
- End-to-end verification on an actual sub-API-12 device cannot be performed by static review.

**Suggestions**:
- Add a string resource, e.g. `lyrics_view_blur_min_api_hint = "仅支持系统版本 12 及以上的设备"` to base/zh/ug variants of `string.json`.
- Below the `List` block in `LyricsInterfacePage.AppearanceSection()` (around line 165), conditionally render a hint when `!this.viewModel.isBlurSupported`:
  ```
  if (!this.viewModel.isBlurSupported) {
    Text($r('app.string.lyrics_view_blur_min_api_hint'))
      .fontSize(12)
      .fontColor($r('sys.color.font_secondary'))
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })
  }
  ```
- Optionally: also add a smoke-test note for self-test on a low-API simulator (already called out in §3 step 9 of the logic plan).

---

## Cross-Cutting Issues

### Permission Coverage
No new system permissions are required. `.blur()` is a pure rendering-side modifier and `deviceInfo.sdkApiVersion` is a public API. No changes to `entry/src/main/module.json5` are needed.

### Navigation Completeness
Switch lives on the existing `LyricsInterfacePage` (settings > lyrics > lyrics screen). Navigation is unchanged from Spec12; no new routes added or required.

### State Management
- Single source of truth: `AppStorage('lyricsBlur')`. Writers go through `LyricsInterfaceViewModel.updateBlur` → `SettingsStore.save` (which writes both AppStorage and Preferences). Readers: VM `@Track blur` (settings page), `PlayerPage.@StorageProp('lyricsBlur')` (player). This matches the dual-channel pattern used by `lyricsTextSize` & friends.
- Reactivity is correct: `@StorageProp` on `PlayerPage` re-renders `ForEach`; per-line `@Prop` changes propagate `lineDistance` and `suppressBlur` from the VM Track flags.
- `syncFromModel()` (`LyricsInterfaceViewModel.ets:90`) seeds `AppStorage` for `lyricsBlur` so cold-loaded models prime any `@StorageProp` subscribers consistently.
- Minor non-blocking observation: `updateBlur` writes via `SettingsStore.save` and bypasses `model.saveToStorage()`. Symmetric, but it does mean direct callers of `model.saveToStorage()` still flush via `AppStorage.setOrCreate` only (no Preferences). Today there are no such callers for this key — current behavior is correct.

### API Compatibility
- `compatibleSdkVersion`: 6.0.2 (API 22). `targetSdkVersion`: 6.1.0 (API 23). `deviceInfo.sdkApiVersion` is widely available; the try/catch wrapper in `isBlurSupported()` defends against the rare case where the property access throws on a mock/emulator.
- `.blur(number)` is a base ArkUI modifier available on the project's API range.
- The `enable` field on `HdsListItemCard` is consistent with sibling usages (`UserInterfacePage.ets`).

### Resource Completeness
- `lyrics_view_blur` string is present at `entry/src/main/resources/base/element/string.json:1528` (Spec12 already shipped it).
- Missing: hint string for scenario 7 (see Scenario 7 gaps).
- No new images/icons needed.

---

## Final Assessment

**Overall Verdict**: PASS WITH ISSUES

The core blur feature (scenarios 1-6) is implemented correctly, persists across restarts, and integrates cleanly with the existing MVVM + AppStorage pattern. The blur math (1.5 vp step, 6.0 vp cap) matches the spec's "距离越近越轻 / 越远越重 / 超过一定距离达到最大值" wording. Drag-suppression, song-change re-anchoring, and live progress tracking all flow through the existing `LyricsViewModel` / `PlayerPageViewModel` Track signals without any new race-prone state.

The single gap is scenario 7's hint text under the disabled switch — the disable behavior itself is wired (gate in VM + `enable` on the card), but the user-facing explanation is missing.

- **Fully covered scenarios**: 1, 2, 3, 4, 5, 6.
- **Partially covered scenarios**: 7 (switch disable works; hint text and string resource missing; runtime verification on a low-API device deferred to self-test).
- **Not covered scenarios**: none.

**Recommended Priority Fixes**:
1. (Low-medium) Add `lyrics_view_blur_min_api_hint` string and conditionally render it below the switch row when `!viewModel.isBlurSupported`. Closes scenario 7 gap.
2. (Optional) During self-test, exercise the low-API path on a sub-API-12 simulator (or a temporary forced `isBlurSupported = false` override) to confirm both the disabled state and the hint render correctly.
