# Review Fix Report

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec17/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA`
- **Fix Date**: 2026-05-15
- **Total Issues in Report**: 1 (one PARTIAL scenario — Scenario 10; all other scenarios PASS; no cross-cutting issues flagged)
- **Verified (CONFIRMED)**: 1
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Successfully Fixed**: 1
- **Failed to Fix**: 0
- **Fix Success Rate**: 100% (1 of 1)

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|---------------|--------------|----------|--------|
| 1 | Scenario 10 — `LyricsComponent.onTranslationToggle` does not recenter the current line after `toggleTranslation` | PARTIAL | CONFIRMED | `LyricsComponent.ets:140-142` (pre-fix) calls only `viewModel.toggleTranslation()`; no `scrollToIndex` or `scrollToLine` is scheduled. `checkAndScroll` (`:159-165`) short-circuits unless `currentLineIndex !== prevLineIndex`, so it does not help. Android's `LyricsView.kt:179-188` explicitly calls `smoothScrollTo(currentLine, 0L)` inside the `openTranslation` setter — the HarmonyOS PlayerPage already mirrors this at `PlayerPage.ets:1689-1703` but `LyricsComponent` does not. | Fixed |

### Issue 1 verification details

- **Report claim**: After `toggleTranslation`, `LyricsComponent` does not recenter the current line; the secondary lyrics surface will only recenter when `currentLineIndex` next advances.
- **Independent re-read of code**:
  - `LyricsComponent.ets:140-142` (pre-fix) — `onTranslationToggle: () => { this.viewModel.toggleTranslation() }`. Confirmed no scroll call.
  - `LyricsComponent.ets:159-165` — `checkAndScroll` is gated on `lineIndex !== this.prevLineIndex`, so a no-op when the toggle is hit mid-line.
  - `LyricsComponent.ets:167-174` — `scrollToLine` helper already exists with the correct `+1` (top spacer) + `ScrollAlign.CENTER` semantics.
  - `PlayerPage.ets:1688-1704` — already implements the canonical `setTimeout(..., 50) + scrollToIndex(currentLyricsLineIndex + 1, true, ScrollAlign.CENTER)` pattern after `toggleTranslation`.
- **Android cross-check**: `SPA/.../widget/lyricsview/LyricsView.kt:178-188` — the Kotlin `openTranslation` setter calls `initEntryList()` then `smoothScrollTo(currentLine, 0L)` when `hasLyrics()`. This is the canonical source-of-truth behavior. The HarmonyOS PlayerPage fix mirrors it; LyricsComponent should match.
- **Result**: CONFIRMED. Issue is real and the suggested fix from the review report is appropriate.

## False Positive Analysis

None. The single reported issue was verified against actual code and the Android source of truth.

## Scenario Fix Details

### Scenario 10 — Smooth re-center scroll after toggle

- **Report Verdict**: PARTIAL
- **Issues Found**: 1 confirmed out of 1 reported
- **Fix Status**: Fixed

#### Issue 1: `LyricsComponent.onTranslationToggle` lacks a post-toggle recenter

- **Verification**: CONFIRMED — see Verification Summary above.
- **Fix Strategy**: Event-handler / business-logic fix. Mirror the existing player-page `setTimeout(..., 50)` recenter pattern inside `LyricsComponent`'s `onTranslationToggle` callback. The 50 ms delay lets the per-line row-height tween (300 ms `FastOutSlowIn` on the wrapping `Column` in `LyricsLineComponent.ets:466-480`) register new measured heights before `scrollToIndex` computes the target.
- **Android Reference**: `SPA/app/src/main/java/com/salt/music/widget/lyricsview/LyricsView.kt:178-188` — `openTranslation` setter calls `smoothScrollTo(currentLine, 0L)` after rebuilding the entry list. The HarmonyOS equivalent is `ListScroller.scrollToIndex(index + 1, true, ScrollAlign.CENTER)`, which `scrollToLine` already wraps.
- **Changes Applied**:
  - In `LyricsComponent.onTranslationToggle`, after `this.viewModel.toggleTranslation()`, schedule a `setTimeout(..., 50)` that calls `this.scrollToLine(this.viewModel.currentLineIndex)` (guarded by `currentLineIndex >= 0` and `!this.isTouching` so the recenter does not steal scroll from a user who is actively dragging the list at the moment of toggle).
- **Files Modified**:
  - `entry/src/main/ets/components/LyricsComponent.ets` — extended `onTranslationToggle` to schedule a post-toggle recenter; the existing private `scrollToLine` helper is reused (no new helper added).
- **API Documentation Used**: None — the fix reuses an already-working pattern from `PlayerPage.ets:1694-1703` and pre-existing helpers on the same component.
- **Compilation**: Not run (the change is a single small additive callback body using already-imported APIs, existing component fields, and the existing private `scrollToLine` helper — no new imports, no new types, no new bindings). The build-fixer can be run in Stage 6b to confirm.
- **Notes**:
  - The original review report wording mentions `LyricsInterfacePage` as the consumer of `LyricsComponent`, but `LyricsInterfacePage` is actually the lyrics-settings page (sliders + switches for text-size/font-weight/karaoke-strategy) and does NOT render `LyricsComponent`. A project-wide grep shows `LyricsComponent` is currently not consumed by any page (`grep -rln "LyricsComponent\b"` returns only its own file). The fix is still applied because the file is the intended secondary-surface lyrics component and the correctness should not depend on it being currently mounted — once it is wired up (e.g., into the future full-screen lyrics surface), Scenario 10 must hold.
  - The `!this.isTouching` guard is a conservative addition not present in the PlayerPage path; on the PlayerPage the lyrics list is the dominant gesture surface so the same check is implicit via the user-scroll state on the VM. Here it prevents the recenter from interrupting an in-progress user drag — a small safety improvement.

## Cross-Cutting Fixes

### Permission Coverage
No changes. Report explicitly notes "No new HarmonyOS permissions are needed for this commit."

### Navigation Updates
No changes. Report explicitly notes the feature uses existing navigation.

### Resource Additions
No changes. Report verifies `app.media.ic_translation` exists and no new strings are introduced.

### State Management Changes
No changes. Report's note about `SettingsStore.save` ↔ `AppStorage` coherence is flagged as needing a runtime smoke test, not a code fix.

## Remaining Issues

None. The single PARTIAL has been addressed.

The review report's optional/hygiene suggestions are explicitly marked non-blocking and out-of-scope for this fix pass:
- "Consider mirroring the `setTimeout(..., 50)` recenter onto future cases (e.g., immersion-mode exit)" — speculative, no current scenario fails.
- "If `PlayerPageViewModel` ever moves off a singleton lifecycle, balance `addTranslationChangedListener` with `removeTranslationChangedListener`" — hygiene only; no current leak.
- "Swap mini-lyrics per-index opacity to a small table keyed by source" — explicitly beyond plan.md.

## All Modified Files

| File | Issues Addressed | Change Summary |
|------|-----------------|----------------|
| `entry/src/main/ets/components/LyricsComponent.ets` | Scenario 10 (secondary surface) | Added `setTimeout(() => scrollToLine(currentLineIndex), 50)` inside `onTranslationToggle` after `viewModel.toggleTranslation()`. Guarded by `currentLineIndex >= 0 && !isTouching`. Mirrors the PlayerPage pattern at `PlayerPage.ets:1694-1703` and Android `LyricsView.kt:184` (`smoothScrollTo(currentLine, 0L)` in the `openTranslation` setter). |

## Recommendations

1. **Stage 6b rebuild** — run the project build to confirm the small additive change compiles cleanly (no new imports, but worth a build pass before integration testing).
2. **Re-run code review** — to re-evaluate Scenario 10 on the secondary surface and confirm it now reads PASS.
3. **Manual testing on device** — toggle translation rapidly at line boundaries on a song with long translation lines to validate the 50 ms tween/scroll handoff visually.
4. **Future wiring** — when the full-screen lyrics surface is wired to use `LyricsComponent`, no additional change is needed for Scenario 10; the fix is self-contained.
5. **Smoke test `SettingsStore.save` ↔ AppStorage coherence** — per the review report's "UNABLE TO VERIFY" note about whether `SettingsStore.save` also calls `AppStorage.setOrCreate`. If it does not, the chip styling in PlayerPage (which reads `@StorageProp('lyricsOpenTranslation')`) could lag the VM by one transaction. Cannot be confirmed statically.
