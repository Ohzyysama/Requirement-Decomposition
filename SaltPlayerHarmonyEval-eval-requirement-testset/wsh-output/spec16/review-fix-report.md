# Review Fix Report

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec16/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA`
- **Fix Date**: 2026/05/15
- **Total Issues in Report**: 1 (Scenario 3 PARTIAL — visual-fidelity gap with 2 sub-points)
- **Verified (CONFIRMED)**: 0
- **False Positives**: 0
- **Uncertain (skipped)**: 1
- **Successfully Fixed**: 0
- **Failed to Fix**: 0
- **Fix Success Rate**: N/A (0 confirmed issues required code fixes)

The code-review report classified the spec16 commit `232c0c8` as **PASS WITH ISSUES**: 6 of 7 scenarios PASS, 1 PARTIAL (Scenario 3), 0 FAIL. The single PARTIAL is a runtime visual-fidelity concern that cannot be confirmed or fixed via static code change. No cross-cutting issues (Permissions, Navigation, State Management, API Compatibility, Resource Completeness) were flagged.

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|---------------|--------------|----------|--------|
| 1 | Scene 3 — 22°/-28vp/perspective 1.6 may not match Android visually | PARTIAL | UNCERTAIN | Geometry constants are present and wired (`PlayerPage.ets:170-177, 1459-1468, 1547-1556`); however Android's `com.xuncorp.spc.lyrics.component.LyricsContainer` is a closed third-party lib (only entry point in `LyricsUI3.kt:64` passes `threeEffect = effect3D` — no rotation angle, perspective, or translate-x value is derivable from Android source). The only Android in-tree 3D helper, `Camera3D.kt:14`, uses an unrelated `-15f` default for cover art, not lyrics. | Skipped — no objective static target to fix against |
| 1b | Scene 3 — possible left-edge clipping on small/foldable screens (`centerX:'0%'` + `translate:{x:-28}`) | PARTIAL (suggestion) | UNCERTAIN | Concern is theoretical; no concrete failing device or screenshot evidence available at static-analysis time. | Skipped — needs Stage 7 real-device verification |

## False Positive Analysis

None. The report's PARTIAL verdict for Scene 3 is accurate as written — it explicitly states static analysis cannot confirm visual parity, and the verification step here arrived at the same conclusion.

## Scenario Fix Details

### Scenario 3 — 开启后播放页歌词以立体效果展示（含渐变遮罩）

- **Report Verdict**: PARTIAL
- **Issues Found**: 0 confirmed out of 2 sub-points reported (both UNCERTAIN)
- **Fix Status**: Deferred — no static fix applicable

#### Issue 1: Geometry constants (22° / -28vp / perspective 1.6) may not visually match Android `LyricsContainer(threeEffect=true)`
- **Verification**: UNCERTAIN
  - Read `entry/src/main/ets/pages/PlayerPage.ets:170-177` — constants `LYRICS_3D_ROTATION_DEG=22`, `LYRICS_3D_TRANSLATE_X_VP=-28`, `LYRICS_3D_PERSPECTIVE=1.6` are defined as documented.
  - Read `entry/src/main/ets/pages/PlayerPage.ets:1459-1468` and `1547-1556` — both the timed-lyrics `List` and the static-lyrics `Scroll` apply identical `.rotate({y:1, angle: ?-22:0, centerX:'0%', centerY:'50%', perspective:1.6})` + `.translate({x: ?-28:0})` with the gate on `this.lyricsUIEffect3D`.
  - Searched Android source: `LyricsUI3.kt:64` invokes `LyricsContainer(threeEffect = effect3D, ...)` from package `com.xuncorp.spc.lyrics.component` — this is a **closed third-party library**, not in-tree source, so the exact internal rotation angle / perspective / translate values cannot be extracted from the Android codebase.
  - Searched all Android in-tree files: the only `rotationY` references are `SpwCover.kt:95` (`180f`, cover flip) and `Camera3D.kt:14` (`-15f` default for cover-art transform). Neither is the lyrics path.
- **Why no fix**: There is no objective Android-side ground-truth angle/perspective to align against statically. Adjusting the HarmonyOS constants without a runtime reference would be guesswork and could regress an already-acceptable look. The report itself recommends real-device screenshot comparison at Stage 7 (Self-Testing), which is the correct pipeline phase for this work.
- **Action**: Deferred to Stage 7 (Self-Testing). Constants remain at current values.

#### Issue 1b: `centerX:'0%'` + `translate:{x:-28}` may cause left-edge clipping on small or foldable screens
- **Verification**: UNCERTAIN
  - No concrete failing-device evidence cited in the review report.
  - The behavior is identical to the Android `LyricsContainer(threeEffect=true)` intent (pivot at the left edge, shift content slightly left to compensate for the Y-rotation perspective). Whether this clips depends on actual screen width and lyrics padding, observable only on a real device.
  - Source-code review of `entry/src/main/ets/pages/PlayerPage.ets:1452, 1543` shows `.fadingEdge(true, { fadingEdgeLength: 80 })` is applied on both branches, which softens edge artifacts.
- **Why no fix**: Speculative — no reproducible bug. Mitigation (e.g., screen-width-relative translate) would require runtime measurements not available in static review.
- **Action**: Deferred to Stage 7 (Self-Testing). If clipping is observed on a target device, the fix can be implemented then as a follow-up `LYRICS_3D_TRANSLATE_X_VP` adjustment or a `displaySync.width`-relative computation.

## Cross-Cutting Fixes

All cross-cutting sections in the review report were PASS. No fixes applied.

### Permission Coverage
- Report verdict: PASS — spec16 is a pure UI-transform + Preferences-persistence feature, no permissions involved.
- Changes: none.

### Navigation Updates
- Report verdict: PASS — entry path `MainPage → Menu → Settings → Laboratory` already wired by spec9 / spec15; commit `232c0c8` did not touch routes.
- Changes: none.

### Resource Additions
- Report verdict: PASS — `$r('app.string.lyrics_3d_effect_label')`, `$r('app.media.ic_crown')`, `$r('app.string.no_lyrics')` all already present (verified by spec16 build-fix-report showing successful compile).
- Changes: none.

### State Management Changes
- Report verdict: PASS — `@StorageProp('lyricsUIEffect3D')`, `@Track lyricsEffect3DVM` + `@ObjectLink`, `@Track textAlignCenter` with `refreshTextAlignFromStorage` cross-VM sync, single-write-point `SettingsStore.save()`. No circular subscriptions or duplicate persistence.
- Changes: none.

### API Version Compatibility
- Report verdict: PASS — `.rotate({perspective})`, `.translate({x})`, `.fadingEdge`, `@StorageProp` all within current project baseline (API 12+, already in use since spec13/15).
- Changes: none.

## Remaining Issues

| # | Issue | Reason | Recommendation |
|---|-------|--------|----------------|
| 1 | Visual parity of 3D rotation with Android lyrics | UNCERTAIN — Android side is a closed third-party lib; HarmonyOS values appear reasonable but rendering can only be judged on-device | Stage 7 real-device side-by-side screenshot comparison; if delta is significant, tune `LYRICS_3D_ROTATION_DEG` / `LYRICS_3D_TRANSLATE_X_VP` / `LYRICS_3D_PERSPECTIVE` then |
| 1b | Possible left-edge clipping on small/foldable screens | UNCERTAIN — no concrete failing-device evidence; theoretical concern only | Stage 7 verification on at least one small-screen device; if reproducible, switch `LYRICS_3D_TRANSLATE_X_VP` to a screen-width-relative computation |

## All Modified Files

None. No source files were modified in this review-fix pass.

## Recommendations

1. **Proceed to Stage 7 (Self-Testing)** — the only remaining concern is real-device visual parity, which is the explicit purpose of Stage 7. The current commit is structurally complete and compiles.
2. **At Stage 7, capture side-by-side screenshots** of:
   - HarmonyOS PlayerPage with `lyricsUIEffect3D = true`
   - Android lyrics screen with the same toggle on
   for both timed-lyrics and static-lyrics paths.
3. **If small-screen clipping is observed**, follow up with a screen-width-relative `translate` calculation rather than a fixed `-28vp`.
4. **No re-build needed** — since no source files were changed, the spec16 HAP package (`wsh-output/spec16/entry-default-signed.hap`) remains current.
