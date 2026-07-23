# Review Fix Report — spec21

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec21/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA`
- **Fix Date**: 2026/05/15
- **Total Issues in Report**: 4 (2 minor gaps in Scenario 4 + 2 optional suggestions)
- **Verified (CONFIRMED)**: 0
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Non-actionable (working-as-designed / optional)**: 4
- **Successfully Fixed**: 0
- **Failed to Fix**: 0
- **Fix Success Rate**: N/A (no blocking issues to fix)

## Executive Summary

The code-review report's **Final Assessment** is `PASS WITH MINOR NOTES` with
**"No blocking issues."** Three of four scenarios are full PASS. The sole
PARTIAL scenario (Scenario 4) lists two "Minor" notes — both of which the
report itself explicitly characterises as working-as-designed:

- Gap 1 (literal `%` in non-URI paths): the report says
  *"matches the spec example"* and *"In practice the visible result for
  ordinary filenames is correct."*
- Gap 2 (format-suffix fallback when `path` is empty): the report says
  *"This is consistent with the spec ('文件名完整显示，不去除扩展名部分'
  — only relevant when there IS a file name)."*

Both "Recommended Priority Fixes" at the end of the report are tagged
**"(Optional / low priority)"** — a unit test and a defensive guard, neither
required by the spec.

Per the Review Fixer principle **"Minimal changes: only fix confirmed issues.
Do not refactor or 'improve' working code"**, no code modifications were
applied. The implementation in commit `fe56cb7` already satisfies the spec.

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|----------------|--------------|----------|--------|
| 1 | Scenario 4 — literal `%` chars in non-URI paths get unconditionally `decodeURIComponent`d | PARTIAL — Minor | NOT A DEFECT | `SongItemModel.ets:56–74` matches the spec example; report says "matches the spec example exactly" | No fix needed |
| 2 | Scenario 4 — `getDisplayTitle()` fallback omits `.{format}` suffix when `path` is empty but `format` is set | PARTIAL — Minor | NOT A DEFECT | `SongItemViewModel.ets:114–127`; report says "consistent with the spec" | No fix needed |
| 3 | Optional suggestion — add unit test for `fileNameFromPath` | Optional / low priority | NOT A DEFECT | Not required by spec; testing infra not in scope of this fix | No fix needed |
| 4 | Optional suggestion — gate `decodeURIComponent` behind `raw.includes('%')` | Optional / low priority | NOT A DEFECT | Current behaviour matches the spec's stated example | No fix needed |

## Detailed Analysis of Reported Items

### Item 1 — Scenario 4 Gap: literal `%` characters in non-URI paths

**Report claim**: `fileNameFromPath()` applies `decodeURIComponent`
unconditionally, so a future plain filesystem path containing `%XX` would be
silently decoded.

**Verification**:
- Read `entry/src/main/ets/model/SongItemModel.ets:56–74`.
- Confirmed: helper uses `decodeURIComponent` in a try/catch.
- Confirmed: per the project's own contract documented in the helper's
  comment, `Track.path` is in URI form (`file:///…`) with URL-encoded byte
  sequences — so decoding is correct for actual data.
- The behaviour matrix in the review report (line 217–224) shows the helper
  produces the **exact spec example output** (`周杰伦 - 晴天.flac`) for both
  the URI-encoded form and the plain-text form.
- The report itself acknowledges: *"In practice the visible result for
  ordinary filenames is correct."*

**Verdict**: This is not a defect. The "literal `%` in plain path" edge case
is hypothetical (no code path in the project produces such a value) and would
contradict the helper's stated contract. Fixing it would be a defensive
refactor unrelated to the spec.

**Action**: None.

### Item 2 — Scenario 4 Gap: format-suffix fallback

**Report claim**: When `path` is empty/null and `format` is set,
`getDisplayTitle()` returns the bare `title` (without `.{format}` suffix)
because the file-name branch returns before the format branch.

**Verification**:
- Read `entry/src/main/ets/viewmodel/SongItemViewModel.ets:113–127`.
- Confirmed control flow: if `displayFileName` is true and
  `fileNameFromPath(this.path)` is non-empty, return file name. Otherwise
  fall through to `if (this.format) { return title.format }; return title`.
- Confirmed: when `displayFileName` is true and the file-name extraction
  yields empty, the function falls through and DOES still apply the format
  suffix because the early-return is conditional on `fileName.length > 0`.

Re-reading lines 117–121:

```ts
if (this.displayFileName) {
  const fileName = fileNameFromPath(this.path)
  if (fileName.length > 0) {
    return fileName
  }
}
```

The file-name branch only returns when `fileName.length > 0`. When the
extraction yields empty, control falls through to the `if (this.format)`
branch on line 123. So the format suffix IS applied on the fallback path.

**Verdict**: The report's reading of this code path appears to be inverted —
the suffix branch DOES execute on fallback. Even taking the report's reading
at face value, it explicitly classifies this as *"consistent with the
spec"*. Either way: not a defect.

**Action**: None.

### Item 3 — Optional: add unit test

**Report claim**: Suggest adding a `fileNameFromPath` unit test for the spec
example, trailing slash, empty, undefined, and encoded vs. decoded inputs.

**Verification**:
- Marked by the report as **"(Optional / low priority)"**.
- Not part of the spec's acceptance criteria.
- The Review Fixer's scope is to fix code-review defects, not to add new
  test coverage.

**Action**: None. (Could be picked up as a separate test-coverage task.)

### Item 4 — Optional: gate `decodeURIComponent` with `%` check

**Report claim**: If `Track.path` ever holds non-URI paths with literal `%`,
gate the decode step behind `raw.includes('%')`.

**Verification**:
- Marked by the report as **"(Optional / low priority)"**.
- Report itself says: *"Optional — current behavior matches the spec's
  stated example."*
- Changing this would alter a contract that the helper's own comment
  explicitly documents (URI-form input).

**Action**: None.

## False Positive Analysis

No false positives in the strict sense — the report did not assert that any
specific defect exists. The PARTIAL verdict is labeled as covering "minor
edge cases [that] merit either a comment or a unit test" — i.e. notes for
future work, not defects to fix.

## Scenario Fix Details

### Scenario 1 — Default OFF, lists show metadata title

- **Report Verdict**: PASS
- **Issues Found**: 0
- **Fix Status**: N/A (no fix needed)

### Scenario 2 — Switch ON, lists swap to file names live + persist

- **Report Verdict**: PASS
- **Issues Found**: 0
- **Fix Status**: N/A (no fix needed)

### Scenario 3 — Switch OFF, lists swap back to titles live + persist

- **Report Verdict**: PASS
- **Issues Found**: 0
- **Fix Status**: N/A (no fix needed)

### Scenario 4 — Displayed file name = last path segment, extension kept

- **Report Verdict**: PARTIAL (two Minor notes + two Optional suggestions)
- **Issues Found**: 0 actionable defects
- **Fix Status**: N/A — implementation matches the spec example exactly;
  notes are documentation hints rather than defects

## Cross-Cutting Fixes

All cross-cutting sections in the review report are PASS:

- **Permission Coverage**: No new permission required (data already
  available via `Track.path`).
- **Navigation Completeness**: Toggle row already reachable from
  `UserInterfacePage.ets` at the expected position.
- **State Management**: Plumbing follows the proven `displaySongCover`
  pattern across all eight list surfaces.
- **API Compatibility**: Only uses already-established project APIs.
- **Resource Completeness**: Strings exist in `base`, `zh`, `ug` locales.
- **Spec Scope Coverage**: All eight list surfaces in the app are wired.

No cross-cutting fixes were applied or needed.

## Remaining Issues

None. All four items in the report are non-actionable per the report's own
characterisation.

| # | Item | Reason | Recommendation |
|---|------|--------|----------------|
| 1 | Literal `%` in non-URI paths | Hypothetical edge case; report says current behaviour matches spec | Track in a code-quality backlog if non-URI paths are ever introduced |
| 2 | Format-suffix on empty-path fallback | Working as designed; report calls it "consistent with the spec" | Document in `SongItemViewModel.ets` if desired, but no behaviour change |
| 3 | Unit test for `fileNameFromPath` | Optional / low priority | Add in a future test-coverage task |
| 4 | `%`-guard on decode | Optional / low priority; current behaviour matches the spec example | Defer until non-URI paths become a real source |

## All Modified Files

None. No source files were modified in this fix pass.

## Recommendations

1. **No re-review necessary** — the implementation already passes the
   code review at the "PASS WITH MINOR NOTES" tier. The notes are
   advisory, not blocking.
2. **Optional follow-up tasks** for a future iteration (not blocking):
   - Add `fileNameFromPath` unit tests next to
     `entry/src/test/SearchAllSongs.test.ets`.
   - If the project ever introduces a non-URI `Track.path` source, revisit
     the `decodeURIComponent` contract.
3. **Manual testing**: Verify the four scenarios on a real device
   (toggle ON/OFF, restart app, confirm all eight list pages refresh
   live). The code-review already verified each plumbing point statically.
