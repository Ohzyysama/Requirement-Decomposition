# Code Review Report — spec20: Karaoke Lyrics Animation Compatibility Strategy

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `7de441449346e15e2f69a4520238124063ff4b89`
- **Commit subject**: `[Human-AI] feat(lyrics): spec20 karaoke compat default to current line + relabel`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec20/plan.md`
- **Code Context**: `/Users/moriafly/GitHub/HomeTrans/Plugin/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/7de441449346e15e2f69a4520238124063ff4b89_result.json`
- **Review Date**: 2026-05-15
- **Total Scenarios**: 10
- **Results**: 10 PASS | 0 PARTIAL | 0 FAIL | 0 UNABLE TO VERIFY

The commit is a focused, low-risk delta that flips the default value of the
karaoke compatibility strategy from `EXPAND_ALL_LINES` (1) to
`CURRENT_LINE_ONLY` (0) and relabels the three options to spec20 wording
(`当前行` / `扩展全部` / `总是`). All other plumbing — the popup selector
in both entry points, persistence via `SettingsStore`, the
`KaraokeRenderDecision` matrix, the `@StorageProp` mirror in `PlayerPage`,
and the per-line `LyricsLineComponent` consumer — was already in place from
prior commits and is unchanged. Every spec20 scenario is fulfilled.

## Files Touched by the Commit

| # | File | Change |
|---|------|--------|
| 1 | `entry/src/main/ets/components/LyricsLineComponent.ets` | `@Prop karaokeStrategyIndex` default 1 → 0 |
| 2 | `entry/src/main/ets/entryability/EntryAbility.ets` | `persistProp` seed 1 → 0; `setOrCreate` fallback 1 → 0 |
| 3 | `entry/src/main/ets/model/LyricsInterfaceModel.ets` | Field default + ctor default + `loadFromStorage` fallback flipped to `CURRENT_LINE_ONLY` |
| 4 | `entry/src/main/ets/pages/PlayerPage.ets` | `@StorageProp` default 1 → 0 |
| 5 | `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` | `@Track karaokeCompatStrategyIndex` default flipped; labels `仅当前行 / 拓展全部行 / 总是` → `当前行 / 扩展全部 / 总是` |

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | 当前行 + mixed lines | PASS | — |
| 2 | 当前行 + no per-cell lines | PASS | — |
| 3 | 扩展全部 + at least one per-cell line | PASS | — |
| 4 | 扩展全部 + no per-cell lines | PASS | — |
| 5 | 总是 + some per-cell lines | PASS | — |
| 6 | 总是 + no per-cell lines (uniform sweep) | PASS | — |
| 7 | Dialog-side change syncs to settings page | PASS | — |
| 8 | Settings-page change syncs to player view | PASS | — |
| 9 | First-run default = 当前行 | PASS | — |
| 10 | Song switch re-evaluates strategy on new doc | PASS | — |

## Detailed Scenario Reviews

### Scenario 1: 当前行 + 部分歌词行带单字时间戳

**Description**: User selects `当前行` (index 0). Some lines have per-cell
karaoke timing, others do not. Per-cell lines should render the karaoke
wipe; non-cell lines should render plain whole-line text.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:34-36` — `CURRENT_LINE_ONLY` branch returns `hasCells` (i.e. `line.cells.length > 0`) per line; no document-level fallback.
- `entry/src/main/ets/components/LyricsLineComponent.ets:381-454` — `shouldRenderPerWord` gate selects the layered karaoke `Stack` for per-cell lines and the legacy whole-line `Text` for non-cell lines.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:42-46` — option labels updated to `当前行 / 扩展全部 / 总是`; selecting the first option writes index `0`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:178-183` — `updateKaraokeStrategy` writes through `SettingsStore.save`, which both updates `AppStorage` (drives the `@StorageProp` in `PlayerPage` line 83) and persists via `Preferences.flushSync`.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 2: 当前行 + 当前歌曲所有歌词行都没有单字时间戳

**Description**: User selects `当前行`. Song has no per-cell data on any
line. No karaoke wipe should be displayed for any line.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:34-36` — when `strategyIndex === 0`, the branch returns `hasCells`; if every line has `cells.length === 0`, every line returns `false`, so the per-word render path is skipped for the entire song.
- `entry/src/main/ets/components/LyricsLineComponent.ets:444-454` — the `else` branch renders plain whole-line `Text` with `mainOpacity` dim curve. No karaoke layering, no uniform-sweep fallback.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 3: 扩展全部 + 至少一行有单字时间戳

**Description**: User selects `扩展全部` (index 1). At least one line in
the document has per-cell timing. All lines (including those without cells)
should render with the karaoke effect (uniform sweep for non-cell lines).

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/LyricsModel.ets:62` — `LyricsDocument.hasAnyKaraoke = lines.some(line => line.cells.length > 0)` is precomputed once per document.
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:37-39` — `EXPAND_ALL_LINES` branch returns `hasAnyKaraokeInDoc`. So when at least one line has cells, every line returns `true`.
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:48-57` — `shouldUseUniformWordSweep` returns `true` for lines with `cells.length === 0` under this strategy, which tells `LyricsLineComponent` to drive the wipe via `computeLineProgress` (uniform across the whole line based on `startTime`/`endTime`).
- `entry/src/main/ets/components/LyricsLineComponent.ets:218-223` — `computeKaraokePosition` correctly falls back to `computeLineProgress` when `cells.length === 0`, producing the uniform sweep.
- `entry/src/main/ets/pages/PlayerPage.ets:1439-1440` — `hasAnyKaraokeInDoc: this.vm.lyricsHasAnyKaraoke` is fed to every `LyricsLineComponent`, refreshed via `PlayerPageViewModel.refreshLyricsLines` (line 914).

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 4: 扩展全部 + 所有歌词行都没有单字时间戳

**Description**: User selects `扩展全部`. No line in the document has
per-cell data. No karaoke effect should display.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/LyricsModel.ets:62` — `hasAnyKaraoke` is `false` for such a document.
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:37-39` — `EXPAND_ALL_LINES` branch returns `hasAnyKaraokeInDoc`, i.e. `false` for every line.
- `entry/src/main/ets/components/LyricsLineComponent.ets:444-454` — every line falls into the whole-line `Text` branch with no karaoke layers.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 5: 总是 + 当前歌曲歌词中有单字时间戳

**Description**: User selects `总是` (index 2). Some lines have per-cell
timing. All lines should render with karaoke effect.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:40-42` — `ALWAYS` branch returns `true` unconditionally regardless of `hasCells` or `hasAnyKaraokeInDoc`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:381-432` — every line enters the layered karaoke `Stack`. Per-cell lines use `computeCellProgress` (line 168), non-cell lines use `computeLineProgress` (line 154) via the `hasCells ? ... : ...` branch at line 219.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 6: 总是 + 当前歌曲歌词中没有任何单字时间戳

**Description**: User selects `总是`. No line has cells. All lines should
still render with a karaoke effect (uniform sweep over the line duration).

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:40-42` — `ALWAYS` returns `true` even when `hasAnyKaraokeInDoc` is `false`.
- `entry/src/main/ets/model/KaraokeRenderDecision.ets:48-57` — `shouldUseUniformWordSweep` returns `true` because `shouldRenderPerWord` is `true` and `line.cells.length === 0`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:218-223` — falls back to `computeLineProgress` which interpolates from `line.startTime → line.endTime` over the smoothed playhead, producing the uniform sweep the spec calls for.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 7: 播放页面板改策略 → 设置页同步显示

**Description**: User opens the lyrics settings panel from the player page,
picks a new strategy. The change must take effect immediately on the
player page lyrics, and the settings page (entered later) must display the
same value.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/components/LyricsInterfaceDialogComponent.ets:367-369` — menu item click invokes `viewModel.updateKaraokeStrategy(index)`.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:178-183` — that method updates `@Track karaokeCompatStrategyIndex`, mirrors to `model`, calls `model.saveToStorage()` (writes `AppStorage`), and then `SettingsStore.save(...)` (writes `AppStorage` again + `Preferences.flushSync`).
- `entry/src/main/ets/pages/PlayerPage.ets:83` — `@StorageProp('lyricsKaraokeCompatStrategy')` subscribes to that key, so the new index is picked up on the next frame.
- `entry/src/main/ets/pages/PlayerPage.ets:1439` — passed straight into `LyricsLineComponent.karaokeStrategyIndex` for every list item.
- Both the dialog and the settings page consume the **same** `LyricsInterfaceViewModel.getInstance()` singleton (`LyricsInterfaceViewModel.ets:14-22`; `LyricsInterfacePage.ets:30`; `PlayerPageViewModel.ets:142`), so the dialog mutation immediately flows to `LyricsInterfacePage.getKaraokeStrategyText()` once it appears.
- `LyricsInterfacePage.ets:37-39` — `aboutToAppear` additionally re-runs `viewModel.loadSettings()` to reconcile from `AppStorage`, giving a belt-and-suspenders refresh.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 8: 设置页改策略 → 播放页歌词实时同步

**Description**: User is on the player page, navigates to the settings
page, picks a new strategy. When they return to the player page, the
lyrics view must reflect the new strategy.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/LyricsInterfacePage.ets:264` — `KaraokeStrategyMenu` row click invokes `viewModel.updateKaraokeStrategy(index)`, exactly the same path as the dialog.
- `entry/src/main/ets/pages/PlayerPage.ets:83` — `@StorageProp('lyricsKaraokeCompatStrategy')` is a reactive subscription: as soon as `SettingsStore.save` flips the `AppStorage` key, the `PlayerPage` instance re-evaluates the property, triggering re-render of the `ForEach` in `LyricsArea`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:22` — `@Prop karaokeStrategyIndex` is reactive, so even live (not just on return) the karaoke gate at line 381-383 re-evaluates whenever the parent's `@StorageProp` changes.
- The dialog uses the same singleton, so its menu also shows the new value (`LyricsInterfaceDialogComponent.ets:356-358`).

**Gaps**: None — the wiring is bidirectional.

**Suggestions**: None.

---

### Scenario 9: 用户从未修改过该设置，默认 = 当前行

**Description**: Fresh install or a user who never touched the option.
The default must be `当前行` (index 0).

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/entryability/EntryAbility.ets:76-77` — `PersistentStorage.persistProp('lyricsKaraokeCompatStrategy', 0)` seeds index `0` on first run when no persisted value exists.
- `entry/src/main/ets/entryability/EntryAbility.ets:196-197` — restoration path uses `ss.get('lyricsKaraokeCompatStrategy', 0)`, so even if Preferences is uninitialized the default is `0`.
- `entry/src/main/ets/model/LyricsInterfaceModel.ets:19, 28, 50` — Model field default, constructor default, and `loadFromStorage` fallback all use `KaraokeCompatStrategy.CURRENT_LINE_ONLY` (= 0).
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:33` — `@Track karaokeCompatStrategyIndex` default is `CURRENT_LINE_ONLY`.
- `entry/src/main/ets/pages/PlayerPage.ets:83` — `@StorageProp` initial fallback is `0`.
- `entry/src/main/ets/components/LyricsLineComponent.ets:22` — `@Prop` default is `0`, ensuring `CURRENT_LINE_ONLY` semantics even if the parent never sets it explicitly.
- Persisted user choices survive: `PersistentStorage.persistProp(key, defaultValue)` does **not** overwrite an existing persisted value; it only seeds when absent. So users who previously picked `EXPAND_ALL_LINES` on prior builds keep their choice (matches the commit message's "Persisted user choices are preserved" claim).

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 10: 切歌后，策略基于新歌词数据重新生效

**Description**: User has chosen a strategy. They switch songs (prev/next,
queue, auto-advance). The strategy must be re-applied against the new
song's lyrics document.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:560-573` and `624-638` — both song-change reset paths clear `lyricsLines`, `lyricsHasAnyKaraoke = false`, and bump `lyricsVersionTag`, then load fresh lyrics via `lyricsViewModel.loadLyrics`.
- `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:906-919` — `refreshLyricsLines` re-reads `lyricsViewModel.document.hasAnyKaraoke` whenever `lyricsVersion` changes (i.e. after a new doc is parsed), so `lyricsHasAnyKaraoke` mirrors the new song's data.
- `entry/src/main/ets/model/LyricsModel.ets:62` — `hasAnyKaraoke` is computed once per parsed document, ensuring per-song accuracy.
- `entry/src/main/ets/pages/PlayerPage.ets:1428-1466` — the `ForEach` keys lines by `lyricsVersionTag + index + startTime`, so the entire list rebuilds on song change, sending the fresh `karaokeStrategyIndex` + `hasAnyKaraokeInDoc` to each new `LyricsLineComponent`.
- `KaraokeRenderDecision.shouldRenderPerWord` is a pure function of `(strategyIndex, line, hasAnyKaraokeInDoc)` — no cached state, so the per-line decision is re-evaluated for every new doc.
- Concretely:
  - `当前行`: per-line `hasCells` check is run fresh against the new song's lines.
  - `扩展全部`: new `hasAnyKaraokeInDoc` (computed in `LyricsDocument` ctor) governs all lines.
  - `总是`: every line renders karaoke unconditionally (`ALWAYS` branch returns `true`).

**Gaps**: None.

**Suggestions**: None.

---

## Cross-Cutting Issues

### Permission Coverage

No new permissions needed by spec20 — the change is purely UI/state. No
`module.json5` updates required, and none were made.

### Navigation Completeness

Both entry points to the karaoke strategy option remain reachable:
- Settings → 歌词 → 歌词界面 (`LyricsInterfacePage.KaraokeSection`).
- Player → settings sheet (`LyricsInterfaceDialogComponent.SettingsGroup2`).

Both share the `LyricsInterfaceViewModel` singleton and the
`lyricsKaraokeCompatStrategy` `AppStorage` key, so the two entry points
stay in sync as the spec requires.

### State Management

The architecture follows a clean reactive chain:

```
User selects option (dialog OR settings page)
    -> ViewModel.updateKaraokeStrategy(index)
    -> model.karaokeCompatStrategyIndex = index
    -> model.saveToStorage()            // mirrors to AppStorage
    -> SettingsStore.save(key, index)   // AppStorage + Preferences.flushSync
        -> AppStorage subscribers fire:
            * PlayerPage @StorageProp(lyricsKaraokeCompatStrategy)
                -> LyricsLineComponent @Prop karaokeStrategyIndex
                    -> KaraokeRenderDecision.shouldRenderPerWord
```

This is correct and idiomatic ArkUI MVVM. `@Track` on the singleton's
field also ensures the settings page UI label re-renders when the dialog
mutates it (same ViewModel instance).

### API Compatibility

No new APIs introduced by this commit. `PersistentStorage`, `AppStorage`,
`@kit.ArkData/preferences`, `@Track`, `@ObjectLink`, `@StorageProp`, and
`@Prop` are all stable HarmonyOS / ArkUI primitives present in the rest
of the codebase. No version risk.

### Resource Completeness

- Heading string `app.string.karaoke_lyrics_animation_compatibility_strategy`
  is present (`resources/base/element/string.json:1440`, value
  `卡拉 OK（逐字）歌词动画兼容策略`).
- Option labels are hard-coded strings in `LyricsInterfaceViewModel.karaokeStrategyOptions`
  (`当前行 / 扩展全部 / 总是`), matching the spec exactly.
- **Minor observation (non-blocking)**: legacy resources
  `expand_all_lines` (= `拓展全部行`) and `only_current_line` (= `仅当前行`)
  still exist in `resources/base/element/string.json` and the `zh` / `ug`
  variants, but are no longer referenced by any `.ets` file (verified by
  grep over `entry/src/main/ets/**/*.ets`). They are dead resources only —
  no functional impact. The translations under `zh/` and `ug/` likewise
  reference these dead keys and do not affect runtime.

## Final Assessment

**Overall Verdict**: PASS

- **Fully covered scenarios**: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 (all 10).
- **Partially covered scenarios**: none.
- **Not covered scenarios**: none.

The commit is small, surgical, and complete. It correctly:

1. Flips the default to `CURRENT_LINE_ONLY` across **every** layer where a
   default value lives (Model field/ctor/load fallback, ViewModel `@Track`
   default, `EntryAbility` `persistProp` seed and `setOrCreate` fallback,
   `PlayerPage` `@StorageProp` fallback, and `LyricsLineComponent` `@Prop`
   fallback). Missing any one of these layers would have left a stale `1`
   in some edge path; the commit covers them all.
2. Updates the user-visible labels to the spec20 wording while leaving the
   underlying `KaraokeCompatStrategy` index map (0/1/2) intact — so any
   already-persisted user choice continues to map to the same semantic
   strategy.
3. Does **not** touch `KaraokeRenderDecision`, which is the actual
   decision matrix consumed at render time. That matrix was already
   correct per the spec, so no logic change is needed.

**Recommended Priority Fixes**: None blocking. The single low-priority
hygiene item below can be deferred or skipped at the reviewer's
discretion:

1. (Cosmetic, optional) Remove the now-orphan `expand_all_lines` and
   `only_current_line` entries from `resources/base/element/string.json`
   and the `zh/` and `ug/` mirrors. They are dead strings with no runtime
   impact, but pruning them keeps the resource files honest and avoids
   future translators wasting effort on unreferenced keys.
