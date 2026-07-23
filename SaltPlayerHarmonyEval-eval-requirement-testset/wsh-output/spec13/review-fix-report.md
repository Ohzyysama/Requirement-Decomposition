# Review Fix Report

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec13/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA` (not consulted — the gap is HarmonyOS-only UI text and a string resource; no Android counterpart to mirror)
- **Fix Date**: 2026-05-12
- **Total Issues in Report**: 1 actionable (1 PARTIAL scenario; 5 PASS, 1 PASS+UNABLE-TO-VERIFY-runtime)
- **Verified (CONFIRMED)**: 1
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Successfully Fixed**: 1
- **Failed to Fix**: 0
- **Fix Success Rate**: 100%

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|---------------|--------------|----------|--------|
| 1 | Scenario 7 — hint text under disabled blur switch missing; string resource `lyrics_view_blur_min_api_hint` not present | PARTIAL | CONFIRMED | `LyricsInterfacePage.ets:142–164` shows the switch row only — no `Text` below; grep across the project for `lyrics_view_blur_min_api_hint` and similar hint keys returned zero matches; the `string.json` files in `base/`, `zh/`, `ug/` had no such entry | Fixed |

## False Positive Analysis

None. The single PARTIAL the report raised was confirmed by reading the actual files.

## Scenario Fix Details

### Scenario 7: Sub-API-12 device — switch shown but disabled, with hint text

- **Report Verdict**: PARTIAL
- **Issues Found**: 1 confirmed out of 1 reported
- **Fix Status**: Fixed (UI + string resource); runtime verification on a real sub-API-12 device remains a manual self-test step

#### Issue 1: Hint text below the disabled blur switch is missing, plus the supporting string resource

- **Verification**: CONFIRMED
  - Read `entry/src/main/ets/pages/LyricsInterfacePage.ets:142–164`. The blur row is a single `HdsListItemCard` inside a `List`; immediately after the closing `}` of that `List`, the `Column` proceeds straight to `.padding(...)` modifiers — there is no conditional `Text` rendering a hint.
  - Grepped the entire project for `lyrics_view_blur_min_api_hint` / `blur.*hint` / `min.*api` — zero matches in both source and `resources/`.
  - `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:39` already exposes `@Track public isBlurSupported`, so the conditional branch can read it directly.
- **Fix Strategy**: Resource (string) + UI (conditional `Text`)
- **Android Reference**: Not used — this is a HarmonyOS-only API-floor hint with no Android counterpart.
- **Changes Applied**:
  - Added a new string entry `lyrics_view_blur_min_api_hint` with value `仅支持系统版本 12 及以上的设备` to all three language variants of `string.json` (`base/`, `zh/`, `ug/`). Per project convention, the `ug/` file already mirrors zh-CN copy verbatim for this cluster (see `lyrics_view_blur` itself, which uses the same Chinese string under `ug/`), so we follow that existing pattern.
  - Added a conditional `Text($r('app.string.lyrics_view_blur_min_api_hint'))` directly below the blur switch's `List` block inside `AppearanceSection`, gated by `if (!this.viewModel.isBlurSupported)`. Styling matches the report's suggestion: `fontSize(12)`, `fontColor($r('sys.color.font_secondary'))`, padding `{ left: 16, right: 16, top: 4, bottom: 8 }`. The hint sits inside the same card `Column` that already wraps the blur row, so its background, border-radius, and clip behave consistently with the row above.
- **Files Modified**:
  - `entry/src/main/resources/base/element/string.json`: inserted `lyrics_view_blur_min_api_hint` after `lyrics_view_blur`.
  - `entry/src/main/resources/zh/element/string.json`: inserted the same key+value.
  - `entry/src/main/resources/ug/element/string.json`: inserted the same key+value (follows the existing project convention of reusing zh-CN copy for this cluster).
  - `entry/src/main/ets/pages/LyricsInterfacePage.ets`: added the `if (!this.viewModel.isBlurSupported) { Text(...) }` block below the blur switch list.
- **API Documentation Used**: None required — only existing project APIs (`Text`, `$r`, `@Track` on the existing `isBlurSupported` field) were used.
- **Compilation**: PASS (`assembleHap` completed `BUILD SUCCESSFUL in 6 s 471 ms`, `CompileArkTS` finished cleanly; only pre-existing deprecation warnings in unrelated files).
- **Notes**:
  - End-to-end runtime check still requires a sub-API-12 device or simulator, which the review report itself flagged as deferred to manual self-test. The disabled state and hint will only appear when `deviceInfo.sdkApiVersion < 12`.
  - Optional follow-up (not done because it falls outside the reported gap): a temporary debug override on `LyricsInterfaceModel.isBlurSupported()` could let testers force the disabled branch on a high-API device.

---

## Cross-Cutting Fixes

### Permission Coverage
No changes. The report's cross-cutting section already concluded no new permissions are needed for `.blur()` / `deviceInfo.sdkApiVersion`.

### Navigation Updates
No changes. Switch lives on the existing `LyricsInterfacePage`.

### Resource Additions
- Strings added: 1 key — `lyrics_view_blur_min_api_hint` — added to `base`, `zh`, `ug` variants (3 files).
- Media resources needed (manual): none.

### State Management Changes
No decorator changes. The new `Text` reads the existing `@Track public isBlurSupported` from the singleton `LyricsInterfaceViewModel` already held in the page's `@State viewModel`, so reactivity is identical to the disabled state on the switch above.

## Remaining Issues

| # | Issue | Reason | Recommendation |
|---|-------|--------|----------------|
| 1 | Scenario 7 runtime verification on a sub-API-12 device | UNABLE TO VERIFY by static review (also flagged as such in the original report) | Self-test on a low-API simulator, or temporarily force `isBlurSupported = false` to confirm both the disabled toggle and the hint render correctly. |

## All Modified Files

| File | Issues Addressed | Change Summary |
|------|-----------------|----------------|
| `entry/src/main/resources/base/element/string.json` | Scenario 7 (resource) | Added `lyrics_view_blur_min_api_hint` after `lyrics_view_blur` |
| `entry/src/main/resources/zh/element/string.json` | Scenario 7 (resource) | Added `lyrics_view_blur_min_api_hint` after `lyrics_view_blur` |
| `entry/src/main/resources/ug/element/string.json` | Scenario 7 (resource) | Added `lyrics_view_blur_min_api_hint` after `lyrics_view_blur` |
| `entry/src/main/ets/pages/LyricsInterfacePage.ets` | Scenario 7 (UI) | Added conditional hint `Text` below the blur switch when `!isBlurSupported` |

## Recommendations

1. Re-run code review against the new commit to confirm scenario 7 flips from PARTIAL to PASS.
2. Manual self-test: force `LyricsInterfaceModel.isBlurSupported()` to `false` (or test on a sub-API-12 device) and verify both the switch is disabled and the new hint renders directly under it inside the same card.
3. Build and deploy: the signed HAP at `entry/build/default/outputs/default/entry-default-signed.hap` already includes this change.
