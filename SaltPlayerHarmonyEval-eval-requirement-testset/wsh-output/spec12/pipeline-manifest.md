# Pipeline Manifest — spec12 (notification bar lyrics)

**Started**: 2026-05-14T08:51:59+08:00
**Finished**: 2026-05-14T09:57:00+08:00
**Duration**: 1h 05m 01s
**Session JSONL**: `2b576bfa-5025-4603-af53-032f9a701935.jsonl`

## Configuration

| Key | Value |
|-----|-------|
| ANDROID | `/Users/moriafly/GitHub/SPA` |
| HMOS | `/Users/moriafly/GitHub/SaltPlayerHarmony` |
| OUTPUT | `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec12` |
| SKIP | `true` |
| MAX_ROUNDS | `2` (ignored) |
| VARIANT | `baseline` |

## Baseline Cost Snapshot (pre-Stage 1)

| Field | Value |
|-------|------:|
| total_tokens | 480,126,143 |
| estimated_cost_usd | $1724.3839 |
| pre-existing subagents | 56 |

## Stage Status

| # | Stage | Status | Notes |
|---|-------|--------|-------|
| 1-3 | SKIPPED | ✅ | |
| 4 | Logic Dev (baseline) | ✅ | 4 source files; commit `3564808e` **[Human-AI] ✓, no swept artifacts ✓** |
| 5 | Build | ✅ | BUILD SUCCESS iter 1 |
| 6 | Code Review | ✅ | **PASS** (6 PASS / 1 UNABLE — Scene 5 deferred to hardware) |
| 6a | Review Fix | ✅ | Nothing to fix |
| 6b | Rebuild | ✅ | BUILD SUCCESS iter 1 |
| 7, 7a, 7b, 8 | SKIPPED | ✅ | |

## Cost Summary

| Stage | Subagent | Total Tokens | Est. Cost |
|-------|----------|-------------:|----------:|
| 1-3, 7/7a/7b/8 (skipped) | — | 0 | $0.00 |
| 4 - Logic Dev (context) | logic-context-builder-minimal (`agent-a156027c7fd1b6518`) | 3,538,842 | $8.0040 |
| 4a - Logic Dev (coding) | logic-coding-minimal (`agent-ac683b8b87a5d853e`) | 4,113,484 | $8.6956 |
| 5 - Build | build-fixer (`agent-a0ecc7371c610e84e`) | 1,423,783 | $2.9607 |
| 6 - Code Review | code-reviewer (`agent-a09026a908f731e10`) | 3,514,944 | $7.3212 |
| 6a - Review Fix | review-fixer (`agent-a36bc80497e48d11b`) | 632,061 | $1.5639 |
| 6b - Rebuild | build-fixer (`agent-a18245abafad095d8`) | 568,204 | $1.2041 |
| **Subagent subtotal** | | **13,791,318** | **$29.75** |
| **Pipeline delta (incl. main session orchestration)** | | **61.5M** | **$236.67** |

## Defect Summary

| Stage | Report File | Defects Found | Defects Fixed | Not Fixed | Details |
|-------|-------------|---------------|---------------|-----------|---------|
| 6 - Code Review | `code-review-report.md` | 0 | — | — | 7 scenarios: 6 PASS / 0 PARTIAL / 0 FAIL / 1 UNABLE TO VERIFY (Scene 5 — pause holds last-line; code path inspected as correct, runtime depends on AVPlayer state). Overall: PASS. 2 minor non-blocking polish notes. |
| 6a - Review Fix | `review-fix-report.md` | 0 | 0 | 0 | No fixes; UNABLE deferred to Stage 7 hardware verification. commit-id: none. |
| 7 / 7a / 8 | — | Skipped | Skipped | Skipped | skip=true |

**Net defect status**: 0 actionable. 7th consecutive clean code-review pipeline (spec6, spec7, spec3, spec9, spec10, spec11, spec12).

## Output Inventory

- `plan.md` — 7-scenario notification-bar lyrics spec
- `logic/plan.md` — context builder plan
- `logic/commit-info.md` + `commit-info.md` — commit `3564808e`
- **Commit `3564808e` `[Human-AI] feat(notification-bar-lyrics): wire spec12 toggle to AVSession title`** ✓
  - `model/NotificationLyricController.ets` — new singleton (104 lines): listens on MiniLyricsController + song-change bus, reads `notificationBarLyrics` and `currentSongTitle` live from AppStorage, pushes merged title via `setNotificationDisplayTitle`, dedupes via `lastPublished`
  - `model/AudioPlayerService.ets` — +28: private `_displayTitleOverride`, public `setNotificationDisplayTitle`, threaded into `updateSessionMetadata` and `updateSessionCoverImage` (override-or-baseTitle resolution)
  - `viewmodel/LyricsSettingsViewModel.ets` — +13: `onNotificationBarLyricsChanged` persists flag via SettingsStore + pokes controller for immediate flip
  - `entryability/EntryAbility.ets` — +7: init `NotificationLyricController` after `MiniLyricsController` (correct init order — Mini fires immediately with current state)
  - ✨ **No swept pipeline artifacts** — third clean logic commit in a row (spec3, spec11, spec12)
- `code-review-report.md` — 7-scenario verdicts
- `review-fix-report.md` + `review-fix-commit-info.md` (commit-id: none)
- `build-fix-report.md` + `build-fix-commit-info.md` (commit-id: none, 6b rebuild iter 1)
- `entry-default-signed.hap` — 30,295,827 bytes (final deliverable)

## Session Inventory (new subagents this pipeline)

| ID | Agent Type | Total Tokens | Cost |
|----|-----|-------------:|-----:|
| `agent-a156027c7fd1b6518` | logic-context-builder-minimal | 3,538,842 | $8.0040 |
| `agent-ac683b8b87a5d853e` | logic-coding-minimal | 4,113,484 | $8.6956 |
| `agent-a0ecc7371c610e84e` | build-fixer (Stage 5) | 1,423,783 | $2.9607 |
| `agent-a09026a908f731e10` | code-reviewer | 3,514,944 | $7.3212 |
| `agent-a36bc80497e48d11b` | review-fixer | 632,061 | $1.5639 |
| `agent-a18245abafad095d8` | build-fixer (Stage 6b) | 568,204 | $1.2041 |
| **Subtotal (6 subagents)** | | **13,791,318** | **$29.75** |

## Notable

1. **Cleanest pipeline in the session by subagent cost**: $29.75 across 6 subagents, all completed first-shot (no retries, no resumes). The minimal-agent flakes from spec10/spec11 didn't recur.
2. **Architecture**: spec12 plays cleanly into existing infrastructure. `MiniLyricsController` already publishes `(songId, line, hasLyrics)` for its mini-lyrics consumer; reusing the same listener fan-out for notification-bar override means zero duplicate state. `_displayTitleOverride` is the single source of truth on the service side.
3. **Correct init ordering**: `MiniLyricsController.init()` first, then `NotificationLyricController.init()` — and because `MiniLyricsController.addListener` fires immediately with current state, the new controller picks up the restored song without a startup race.
4. **Scene 5 (pause holds last line) is hardware-only**: code reviewer marked it UNABLE TO VERIFY because the code path is correct on inspection (the 200ms tick freezes when `getCurrentTimeMs()` anchor freezes, and `publish()` dedupes via `lastPublished`) but full pause behavior depends on AVPlayer state on real hardware. Worth a manual check.

## Manual verification checklist (Stage 7 skipped)

- Scene 1: switch on, play song with lyrics → notification title shows live lyric line
- Scene 2: switch on, play song without lyrics → notification title shows song title (fallback)
- Scene 3: switch on, playing with lyrics → skip to no-lyrics song → title falls back to song title
- Scene 4: switch on, playing → skip to a different song with lyrics → title shows new song's lyric
- Scene 5: switch on, playing → pause → notification title freezes at the last lyric line **(needs hardware)**
- Scene 6: switch off (default) → title is always song title regardless of lyrics presence
- Scene 7: switch on while playing → flip switch off → title immediately reverts to song title
