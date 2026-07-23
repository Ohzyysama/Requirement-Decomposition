# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `5c620cf9682fac5f29d76124350ab650c2c34a71`
- **Commit Subject**: `[Human-AI] feat(player-cover): wire spec7 'Allow Irregular Cover' end-to-end`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec7/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/5c620cf9682fac5f29d76124350ab650c2c34a71_result.json`
- **Review Date**: 2026-05-12
- **Total Scenarios**: 6
- **Results**: 6 PASS | 0 PARTIAL | 0 FAIL | 0 UNABLE TO VERIFY

## Scope of Commit

The commit wires the "Allow Irregular Cover" toggle end-to-end on the player:

| File | Change |
|------|--------|
| `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` | Settings callback now publishes `irregularCoverAllowed` to `AppStorage` (live fan-out). |
| `entry/src/main/ets/pages/UserInterfacePage.ets` | Switch `isCheck` rebound to `@StorageLink('irregularCoverAllowed')` for live mirror. |
| `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets` | New `@Track irregularCoverAllowed`, intrinsic width/height fields, `captureCoverIntrinsicSize()`, `setIrregularCoverAllowed()`, and `getIrregularCoverEnvelope()` helper. |
| `entry/src/main/ets/pages/PlayerPage.ets` | New `@StorageProp` + `@Watch` reader feeds VM; rectangular cover branch split into irregular-ratio / square-fallback inside an 85% Stack envelope. Circle mode unchanged. |

Pre-commit infrastructure already present:
- `EntryAbility.ets:88` — `PersistentStorage.persistProp('irregularCoverAllowed', true)` (default ON, persisted).
- `EntryAbility.ets:130` — `AppStorage.setOrCreate('irregularCoverAllowed', ss.get('irregularCoverAllowed', true) as boolean)` (rehydrate from SettingsStore on cold start).
- `UserInterfaceModel.ets:38` — `irregularCoverAllowed` row defaults to `true`.
- `UserInterfaceViewModel.ets:149-152, 251-253` — restores from AppStorage; disables row when `circlePlaybackCover` is on.
- `resources/base/element/string.json:1411-1414` — `"irregular_cover_allowed": "允许不规则封面"`.

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | Default ON, player renders cover at original ratio | PASS | — |
| 2 | Toggle OFF → player renders square-cropped cover | PASS | — |
| 3 | Toggle ON again → player restores original ratio | PASS | — |
| 4 | Circle cover ON → irregular switch disabled, circle forced | PASS | — |
| 5 | Song switch refreshes cover per current flag | PASS | Brief square fallback during async `getImageInfo()` (see note) |
| 6 | Persistence across app restart | PASS | — |

## Detailed Scenario Reviews

### Scenario 1 — Default ON, player shows cover at original aspect ratio

**Verdict**: PASS

**Evidence**:
- Default seeded to `true` via `PersistentStorage.persistProp('irregularCoverAllowed', true)` — `entry/src/main/ets/entryability/EntryAbility.ets:88`.
- Model default `true` — `entry/src/main/ets/model/UserInterfaceModel.ets:38`.
- PlayerPage reader default `true` — `entry/src/main/ets/pages/PlayerPage.ets:123`.
- VM hydration `AppStorage.get<boolean>('irregularCoverAllowed') ?? true` — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:100`.
- Envelope math implements the three sub-rules (square / wider / taller) — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:1210-1217`:
  - `w === h` → `100% × 100%`
  - `w > h` → `100% × (h/w)%` (height shrinks)
  - `h > w` → `(w/h)% × 100%` (width shrinks)
- Renderer uses `ImageFit.Contain` with the computed width/height percentages inside an 85%×aspect-ratio-1 Stack — `entry/src/main/ets/pages/PlayerPage.ets:1071-1094, 1127-1129`.

**Gaps**: None.

---

### Scenario 2 — Toggle OFF persists and switches player to square crop

**Verdict**: PASS

**Evidence**:
- Settings switch wired via `vm.irregularCoverAllowedVM.toggle()` — `entry/src/main/ets/pages/UserInterfacePage.ets:384-390`.
- Toggle callback fans out to both AppStorage and SettingsStore (immediate effect + persistence) — `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:162-167`:
  - `AppStorage.setOrCreate<boolean>('irregularCoverAllowed', val)` (instant live fan-out)
  - `SettingsStore.getInstance().save('irregularCoverAllowed', val)` (persistent store, complements `PersistentStorage`)
- PlayerPage `@Watch('onIrregularCoverAllowedChanged')` → `this.vm.setIrregularCoverAllowed(this.irregularCoverAllowed)` — `entry/src/main/ets/pages/PlayerPage.ets:121-123, 318-322`.
- VM setter updates `@Track` field → triggers rerender — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:1200-1204`.
- When flag off, `getIrregularCoverEnvelope()` returns `undefined` (line 1212) → branch falls through to `ImageFit.Cover` at `100%×100%` inside the 85%×1 Stack (square crop, pixel-identical to pre-spec7 rendering) — `entry/src/main/ets/pages/PlayerPage.ets:1095-1117`.

**Gaps**: None.

---

### Scenario 3 — Toggle ON again restores original-ratio rendering

**Verdict**: PASS

**Evidence**:
- Same bidirectional wiring as Scenario 2; toggling `false → true` re-runs `UserInterfaceViewModel.ets:162-167` → AppStorage updated → PlayerPage `@Watch` fires → `setIrregularCoverAllowed(true)` → `getIrregularCoverEnvelope()` now returns ratio-preserving percentages — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:1210-1217`.
- `@StorageLink('irregularCoverAllowed')` in the settings page ensures the switch's `isCheck` mirror is live after external restoration too — `entry/src/main/ets/pages/UserInterfacePage.ets:64, 384`.

**Gaps**: None.

---

### Scenario 4 — Circle cover ON disables irregular switch, forces circle rendering

**Verdict**: PASS

**Evidence**:
- Disable in settings UI driven by the live AppStorage `circlePlaybackCover` flag AND VM `isEnabled` — `entry/src/main/ets/pages/UserInterfacePage.ets:394`:
  ```
  enable: !this.circlePlaybackCover && this.vm.irregularCoverAllowedVM.isEnabled
  ```
- VM side-effect on circle toggle keeps `irregularCoverAllowedVM.isEnabled` in lock-step — `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:251-253`.
- Cold-start reconciliation: `onCircleCoverChanged(this.model.circlePlaybackCover.isOn)` applied in ctor so the disabled state survives restart with circle=true — `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:174`.
- Player-side: when `circlePlaybackCover` is true the rectangular branch (and thus `getIrregularCoverEnvelope`) is never entered; `CirclePlaybackCoverComponent` renders instead — `entry/src/main/ets/pages/PlayerPage.ets:1049-1063`. Turning circle off restores the rectangular branch and re-applies the flag, satisfying step 4 of the scenario.

**Gaps**: None.

**Note**: Spec step 3 says "regardless of the previous state of 允许不规则封面, the cover is forced to crop-fill the circle." The implementation satisfies this because the circle branch is taken before the irregular check — the flag has no visual effect while circle mode is on.

---

### Scenario 5 — Switching song refreshes cover per current flag

**Verdict**: PASS

**Evidence**:
- Cover changes funnel through `onControllerCoverChanged(_songId, pm)` which now calls `this.captureCoverIntrinsicSize(pm)` on every change — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:1157-1178`.
- `captureCoverIntrinsicSize` awaits `pm.getImageInfo()` and writes into the `@Track coverIntrinsicWidth / coverIntrinsicHeight` fields (reset to 0 on `undefined` or failure) — `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:1182-1196`.
- Because `getIrregularCoverEnvelope()` reads from `@Track` fields, the View re-evaluates the branch on every song switch, automatically honoring whichever mode the flag is in.

**Gaps / Note**:
- `captureCoverIntrinsicSize` is asynchronous. Between the moment `coverPixelMap` becomes the new bitmap and `getImageInfo()` resolves, `coverIntrinsicWidth/Height` can remain at their previous value (no explicit reset-to-0 before the await), which means on a quick switch the Image briefly renders at the **previous** song's aspect ratio before snapping to the new one. This is a minor visual artifact, not a functional failure, and does not contradict the scenario's stated behavior. Consider resetting width/height to 0 before the await so the transient rendering is always an envelope-sized square rather than a misaligned previous ratio.

**Suggestion (optional)**: In `captureCoverIntrinsicSize`, clear `coverIntrinsicWidth/Height` before awaiting `getImageInfo()` for deterministic transitions on song switch.

---

### Scenario 6 — Persistence across app restart

**Verdict**: PASS

**Evidence**:
- `PersistentStorage.persistProp('irregularCoverAllowed', true)` — `entry/src/main/ets/entryability/EntryAbility.ets:88`.
- Complementary SettingsStore write on every toggle — `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:166`.
- On cold start, EntryAbility rehydrates AppStorage from SettingsStore — `entry/src/main/ets/entryability/EntryAbility.ets:130`:
  ```
  AppStorage.setOrCreate('irregularCoverAllowed', ss.get('irregularCoverAllowed', true) as boolean)
  ```
- `UserInterfaceViewModel` re-reads the rehydrated value when the settings page is constructed — `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:149-152` — so the switch's displayed state matches the last persisted value.
- PlayerPage reads the same AppStorage key via `@StorageProp` default seeded by `setIrregularCoverAllowed(this.irregularCoverAllowed)` in `aboutToAppear` — `entry/src/main/ets/pages/PlayerPage.ets:358`.

**Gaps**: None.

---

## Cross-Cutting Issues

### Permission Coverage
No new permissions required; the feature is purely a display toggle backed by app-local storage. No changes to `module.json5`.

### Navigation Completeness
Both affected pages already exist (`UserInterfacePage`, `PlayerPage`) and are reachable through the existing settings / playback routes. No routing changes needed.

### State Management
- AppStorage key `irregularCoverAllowed` is the single live source of truth; it is `PersistentStorage`-backed, fanned out by the settings VM callback, and consumed by both `@StorageLink` (settings switch) and `@StorageProp+@Watch` (player).
- `PlayerPageViewModel.setIrregularCoverAllowed` guards against redundant writes (equality check) which prevents spurious rerenders.
- Seeding on `aboutToAppear` (PlayerPage.ets:358) protects against the narrow window where the VM is constructed before the Watch fires.
- `coverIntrinsicWidth/Height` are `@Track` — the envelope helper re-evaluates reactively on both song change and flag change.

### API Compatibility
Uses only first-party APIs already present in the project:
- `AppStorage.get / setOrCreate` (decorators and runtime).
- `image.PixelMap.getImageInfo()` (already used elsewhere in `PlayerPageViewModel`).
- `@Track`, `@StorageProp`, `@StorageLink`, `@Watch`, `ImageFit.Contain` / `ImageFit.Cover`.
No deprecated or version-sensitive APIs introduced.

### Resource Completeness
The switch label resource `app.string.irregular_cover_allowed` ("允许不规则封面") is already present at `entry/src/main/resources/base/element/string.json:1411-1414`. No new media or string resources required.

## Final Assessment

**Overall Verdict**: PASS

All six scenarios in `wsh-output/spec7/plan.md` are implemented end-to-end. The state path is symmetric and cleanly layered:

```
Settings UI switch
   └─ SwitcherRowViewModel.toggle()
        └─ UserInterfaceViewModel callback
             ├─ AppStorage.setOrCreate('irregularCoverAllowed', val)  ──▶  PlayerPage @StorageProp + @Watch
             │                                                              └─ vm.setIrregularCoverAllowed(val)
             │                                                                   └─ @Track field → rerender envelope branch
             └─ SettingsStore.save('irregularCoverAllowed', val)  (persistence)
```

The only non-blocking observation is the brief transitional state during async `getImageInfo()` on song switch (Scenario 5). It does not break the scenario and can be tightened later with a pre-await reset.

- **Fully covered scenarios**: 1, 2, 3, 4, 5, 6.
- **Partially covered scenarios**: none.
- **Not covered scenarios**: none.

**Recommended Priority Fixes**:
1. (Optional / nice-to-have) In `PlayerPageViewModel.captureCoverIntrinsicSize`, reset `coverIntrinsicWidth/Height` to 0 before awaiting `getImageInfo()`, so that during a song switch the player renders at the square fallback envelope (rather than briefly the previous song's ratio) before snapping to the new bitmap's true ratio.
