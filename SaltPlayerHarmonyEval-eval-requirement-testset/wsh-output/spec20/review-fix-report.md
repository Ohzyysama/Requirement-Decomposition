# Review Fix Report — spec20

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec20/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA`
- **Fix Date**: 2026-05-15
- **Total Issues in Report**: 1 (single non-blocking cosmetic observation)
- **Verified (CONFIRMED)**: 1
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Successfully Fixed**: 1
- **Failed to Fix**: 0
- **Fix Success Rate**: 100%

The review verdict was `10/10 PASS` for all spec20 scenarios. The only
follow-up item was a non-blocking hygiene observation: two legacy string
resource keys (`expand_all_lines`, `only_current_line`) remained in the
i18n bundles after the spec20 commit relabelled the karaoke compatibility
options to the new wording (`当前行 / 扩展全部 / 总是`). This report
documents the verification of that observation and the cleanup.

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|---------------|--------------|----------|--------|
| 1 | Dead string resources `expand_all_lines` and `only_current_line` in `base/zh/ug` `string.json` | Non-blocking cosmetic | CONFIRMED | Grep of `entry/src/**/*.ets`, `*.ts`, `*.json`, `*.json5`, and `*.js` returned zero references — keys appear only in the three locale `string.json` files and in auto-generated `entry/build/.../ids_map/id_defined.json` (regenerated at build time). | Pruned |

### Verification details

Command run:
```
grep -rn "expand_all_lines\|only_current_line" \
  /Users/moriafly/GitHub/SaltPlayerHarmony \
  --include="*.ets" --include="*.ts" --include="*.json" \
  --include="*.json5" --include="*.js"
```

Matches found (pre-fix):

- `entry/src/main/resources/base/element/string.json:1112` — `expand_all_lines`
- `entry/src/main/resources/base/element/string.json:2308` — `only_current_line`
- `entry/src/main/resources/zh/element/string.json:828` — `expand_all_lines`
- `entry/src/main/resources/zh/element/string.json:1428` — `only_current_line`
- `entry/src/main/resources/ug/element/string.json:828` — `expand_all_lines`
- `entry/src/main/resources/ug/element/string.json:1424` — `only_current_line`
- `entry/build/default/intermediates/res/.../id_defined.json` (build artifact, regenerated)
- `entry/build/debug/intermediates/res/.../id_defined.json` (build artifact, regenerated)

Cross-check for `$r('app.string.expand_all_lines' / 'app.string.only_current_line')` form returned zero hits as well.

Conclusion: the two keys are truly dead in the source tree — current option
labels are hard-coded strings in `LyricsInterfaceViewModel.karaokeStrategyOptions`
(`当前行 / 扩展全部 / 总是`), per the review report's Resource Completeness
section.

## False Positive Analysis

None.

## Fix Details

### Issue: Dead string resource keys

- **Verification**: CONFIRMED — keys exist in three locale bundles but
  zero references in source code.
- **Fix Strategy**: Dead code cleanup (resource pruning).
- **Android Reference**: Not applicable — these were legacy
  HarmonyOS-side labels superseded by inlined ArkTS strings; the Android
  project has its own SharedPreferences-backed option labels that are
  unrelated.
- **Changes Applied**:
  - Removed the `expand_all_lines` and `only_current_line` entries from
    each of the three locale `string.json` files. Surrounding entries
    (`expand`, `experimental`, `only_android_d_and_later_systems_are_supported`,
    `open_sl_es_intro`) are preserved verbatim.
- **Files Modified**:
  - `entry/src/main/resources/base/element/string.json`: removed both keys
  - `entry/src/main/resources/zh/element/string.json`: removed both keys
  - `entry/src/main/resources/ug/element/string.json`: removed both keys
- **API Documentation Used**: None — straight resource removal.
- **Compilation**: Not separately rebuilt at this step; spec20 Stage 6b
  rebuild task (`#57`) will pick this up. The change is a pure removal of
  entries with zero compile-time or run-time references, so no compile
  or runtime regression is possible.
- **Post-fix verification**: Re-ran the same grep with `--exclude-dir=build`
  scope — zero matches in the source tree.
- **Notes**: The two stale entries in `entry/build/.../id_defined.json`
  are build-time artifacts and will be regenerated cleanly on the next
  compile. No manual cleanup needed.

## Cross-Cutting Fixes

### Permission Coverage
- No changes.

### Navigation Updates
- No changes.

### Resource Additions
- None added. Two strings removed (per-locale): `expand_all_lines`,
  `only_current_line`.

### State Management Changes
- No changes.

## Remaining Issues

None.

## All Modified Files

| File | Issues Addressed | Change Summary |
|------|-----------------|----------------|
| `entry/src/main/resources/base/element/string.json` | Dead resource cleanup | Removed orphan keys `expand_all_lines` and `only_current_line` |
| `entry/src/main/resources/zh/element/string.json` | Dead resource cleanup | Removed orphan keys `expand_all_lines` and `only_current_line` |
| `entry/src/main/resources/ug/element/string.json` | Dead resource cleanup | Removed orphan keys `expand_all_lines` and `only_current_line` |

## Recommendations

1. **Rebuild** (Stage 6b, task `#57`) — confirm the project still compiles
   cleanly and `id_defined.json` artifacts regenerate without the removed
   keys.
2. **No further code review needed** — review verdict was already
   `10/10 PASS`; this fix is hygiene only.
3. **Manual testing not required** — the removed keys had zero runtime
   consumers.
