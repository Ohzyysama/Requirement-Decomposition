# Review Fix Report

## Overview

- **Review Report**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec27/code-review-report.md`
- **HarmonyOS Project**: `/Users/moriafly/GitHub/SaltPlayerHarmony`
- **Android Source**: `/Users/moriafly/GitHub/SPA` (not consulted — fix is HarmonyOS-internal WantAgent/PendingIntent plumbing with no Android counterpart)
- **Fix Date**: 2026/05/15
- **Top Priority (from caller)**: Harden Scenario 5 by encoding the target state in the WantAgent parameter (`'requestUnlock'` / `'requestLock'`) instead of `!cur` in `onNewWant`. Scenario 2 PARTIAL is incidental and intentionally skipped.

## Headline Numbers

- **Total Issues in Report**: 2 (both PARTIAL — Scenario 2 and Scenario 5; 0 FAIL)
- **Verified (CONFIRMED)**: 1 — Scenario 5 toggle-semantics gap
- **Intentionally Skipped per Caller Instruction**: 1 — Scenario 2 (caller explicitly excluded this from scope)
- **False Positives**: 0
- **Uncertain (skipped)**: 0
- **Successfully Fixed**: 1
- **Failed to Fix**: 0
- **Fix Success Rate**: 1/1 = 100% of in-scope confirmed issues

## Verification Summary

| # | Issue | Report Verdict | Verification | Evidence | Action |
|---|-------|----------------|--------------|----------|--------|
| 1 | Scenario 5 — notification tap is a *toggle* (`!cur`), not a directional unlock; vulnerable to publish/tap state drift | PARTIAL | CONFIRMED | `EntryAbility.ets:560-573` reads `AppStorage.get('lockDesktopLyrics')` and dispatches `requestLock(!cur)`; `DesktopLyricsLockNotificationController.ets` builds a single `cachedWantAgent` with `'toggleLock'` marker and re-uses it for both card states | Fixed |
| 2 | Scenario 2 — Settings-path lock does not explicitly hide control panel (auto-hides via `!lock` render gate) | PARTIAL | (out of scope per caller) | Caller explicitly noted "Scenario 2 PARTIAL is incidental, no fix needed." | Skipped |

### Verification details for Issue #1

- Read `EntryAbility.ets:540-575`. Confirmed line 566 calls `AppStorage.get<boolean>('lockDesktopLyrics') ?? false` and line 567 passes `!cur` to `requestLock`. The dispatch direction is therefore determined by the *current persisted* value at tap time, not by the publisher's intent at notification-publish time.
- Read `DesktopLyricsLockNotificationController.ets` start-to-end. Confirmed `init()` (lines 46-82 in pre-fix file) builds exactly **one** `cachedWantAgent` whose only marker parameter is `'spDesktopLyricsAction': 'toggleLock'`, and `publish(locked)` (lines 124-156 in pre-fix file) attaches this same agent to both `publish(true)` ("已锁定" card) and `publish(false)` ("已解锁" card). No directional signal is encoded in the PendingIntent.
- Searched the project for any other consumer of `spDesktopLyricsAction` — only one route exists (`EntryAbility.onNewWant`), so changing the parameter scheme is a closed-system refactor with no external API contract.

Conclusion: the report's gap is real. In the happy path the user observes correct directional behavior because `cur` *should* equal the displayed card's state, but any drift (publish lag during a master-OFF→ON cycle, a competing writer racing the tap, OS-side stale card after backgrounding) flips the tap into a re-lock.

## False Positive Analysis

None.

## Scenario Fix Details

### Scenario 5: 桌面歌词已锁定时，用户通过通知栏解锁桌面歌词

- **Report Verdict**: PARTIAL
- **Issues Found**: 1 confirmed
- **Fix Status**: Fixed

#### Issue 1: Notification tap is non-directional ("toggle"), not a strict unlock/lock

- **Verification**: CONFIRMED — see Verification Summary above. Two independent indicators (one cached WantAgent, action marker `'toggleLock'`; `!cur` in onNewWant) jointly produce the toggle semantics flagged by the reviewer.
- **Fix Strategy**: API/business-logic change — re-shape the WantAgent layer to encode the *target* outcome at publish time, then dispatch directly in the tap handler with no AppStorage read.
- **Android Reference**: Not applicable. WantAgent is a HarmonyOS-only primitive; the Android codebase has no counterpart to mirror here. The fix follows the report's own recommended pattern, which mirrors how Android `PendingIntent` extras are routinely keyed by target state to avoid race conditions.
- **API Documentation Used**: Existing `AudioPlayerService` precedent in this same project (`entry/src/main/ets/model/AudioPlayerService.ets:110-308`) — confirmed `wantAgent.getWantAgent` returns a `Promise<WantAgent>` and that `requestCode` differentiates otherwise-identical agents under the system's PendingIntent coalescing. No new API surface was introduced.
- **Changes Applied**:
  - Replaced the single `cachedWantAgent` field with two: `cachedWantAgentRequestUnlock` and `cachedWantAgentRequestLock`.
  - Extracted a private `buildWantAgent(action, requestCode)` helper. `init()` now pre-builds both agents with distinct `requestCode` values (1 and 2) and distinct `spDesktopLyricsAction` markers (`'requestUnlock'`, `'requestLock'`). The two requestCodes defensively prevent system-side PendingIntent coalescing under `UPDATE_PRESENT_FLAG`.
  - `publish(locked)` now selects the WantAgent whose marker matches the **opposite** state of the card it is publishing: the "已锁定" card carries the `'requestUnlock'` agent, and the "已解锁" card carries the `'requestLock'` agent. This makes the tap's intended outcome explicit at the publisher.
  - `destroy()` clears both cached agent references.
  - `EntryAbility.onNewWant` no longer reads `AppStorage.get('lockDesktopLyrics')` or computes `!cur`. It now dispatches directly: `action === 'requestUnlock'` → `requestLock(false)`; `action === 'requestLock'` → `requestLock(true)`. Any other / missing action string is a no-op, same as before.
  - Updated the leading comment block above `onNewWant` and the file-level docstring of `DesktopLyricsLockNotificationController` to describe the new directional contract; left an explicit "spec27 scenario-5 hardening" tag in both files for future grep-ability.
- **Files Modified**:
  - `entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets` — replaced single agent with two directional agents, added `buildWantAgent` helper, taught `publish()` to pick the opposite-state agent, updated `destroy()` to clear both.
  - `entry/src/main/ets/entryability/EntryAbility.ets` — `onNewWant` now branches on `'requestUnlock'` / `'requestLock'` and dispatches directly without reading current state; comment block updated.
- **Compilation**: PASS (`hvigorw assembleHap` — `BUILD SUCCESSFUL in 5 s 958 ms`, fresh signed HAP regenerated and copied to `wsh-output/spec27/entry-default-signed.hap`).
- **Notes**:
  - The fix preserves every other invariant the reviewer praised: single-writer funnel via `requestLock`, idempotent `publish` via `lastPublished`, try/catch around all `notificationManager` calls, listener re-entrancy via `.slice()` fan-out, and the existing `aboutToDisappear` teardown contract.
  - The first publish after `init()` can land before either `wantAgent.getWantAgent` Promise resolves (Promise chain is async). In that case `tapAgent` is `null` and the notification is published with `wantAgent: undefined` — the card still renders, but the tap is inert. This is the same window the old code had (its single agent also resolved asynchronously), so this is not a regression. Once a subsequent `publish()` runs (e.g. on the next `requestLock` call) the cached agent is in place and tap routing works normally. If this turned out to matter in practice we could re-publish on the agent's `.then` callback, but no current scenario exercises that window aggressively enough to merit the extra complexity.
  - `requestCode: 1` vs `requestCode: 2` — chosen as small, stable, non-zero distinct codes. The earlier code used `0`. Distinct request codes are the documented HarmonyOS escape hatch when two otherwise-identical WantAgents must be treated as separate PendingIntents under `UPDATE_PRESENT_FLAG`, mirroring the long-standing Android `PendingIntent.getActivity(ctx, requestCode, ...)` convention.

---

## Cross-Cutting Fixes

### Permission Coverage

No change. All notification permissions already in place from spec26.

### Navigation Updates

No change. Single dispatch path through `EntryAbility.onNewWant` preserved.

### Resource Additions

No change. `desktop_lyrics_locked` / `desktop_lyrics_unlocked` / `desktop_lyrics` / `lock_desktop_lyrics` strings already exist (per cross-cutting report section).

### State Management Changes

No decorator changes. The single-writer funnel via `DesktopLyricsController.requestLock` remains the only persisted-state writer; the fix only changes *which arrow into the funnel is fired* by the notification tap.

## Remaining Issues

| # | Issue | Reason | Recommendation |
|---|-------|--------|----------------|
| 1 | Scenario 2 — Settings-path lock does not explicitly hide control panel | Out of scope per caller's instruction. Reviewer themselves marked this as "vacuously met" because the in-window panel is not visible during the Settings flow and the `!lock` render gate already auto-hides it elsewhere. | Optional future hardening as the reviewer suggested: have `applyLockedState` write `AppStorage.set('desktopLyricsControlPanelVisible', false)` and bind the in-window panel to that key. Not blocking. |

## All Modified Files

| File | Issues Addressed | Change Summary |
|------|------------------|----------------|
| `entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets` | Scenario 5 directional intent encoding | Replaced single `cachedWantAgent` with two state-keyed agents (`cachedWantAgentRequestUnlock`, `cachedWantAgentRequestLock`), added `buildWantAgent` helper, taught `publish()` to attach the opposite-state agent, updated `destroy()` to clear both, refreshed comments |
| `entry/src/main/ets/entryability/EntryAbility.ets` | Scenario 5 directional dispatch | `onNewWant` now dispatches `requestLock(false)` / `requestLock(true)` on `'requestUnlock'` / `'requestLock'` action strings without reading AppStorage; old `'toggleLock'` + `!cur` path removed; comment block updated |

## Recommendations

1. **Re-run code review** against the new commit — Scenario 5 should now be PASS, while Scenario 2 remains PARTIAL (by intention).
2. **Manual smoke test on device**:
   - Lock via in-window button, then tap the "已锁定" notification → expect unlock toast and Settings switch flips OFF.
   - Unlock via Settings, then tap the "已解锁" notification → expect lock toast and Settings switch flips ON.
   - Force a publish/tap drift (toggle master OFF then quickly ON, then tap the stale-looking notification) — the directional encoding should now make the outcome match the *card text*, not the current state.
3. **Optional follow-up** (Scenario 2 nice-to-have): when revisiting, add an explicit `AppStorage.set('desktopLyricsControlPanelVisible', false)` write in `applyLockedState` for newly-locked transitions and bind the in-window page's `controlPanelVisible` to that key, per the reviewer's suggestion. Not required for spec27 to pass.
