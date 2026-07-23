# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `3564808e32596cb4c192023e4ef1747619e2a591`
- **Commit Title**: `[Human-AI] feat(notification-bar-lyrics): wire spec12 toggle to AVSession title`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec12/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/3564808e32596cb4c192023e4ef1747619e2a591_result.json`
- **Review Date**: 2026-05-12
- **Total Scenarios**: 7
- **Results**: 6 PASS | 0 PARTIAL | 0 FAIL | 1 UNABLE TO VERIFY

## Files in scope (commit diff)

- `entry/src/main/ets/model/NotificationLyricController.ets` (new, 104 lines)
- `entry/src/main/ets/model/AudioPlayerService.ets` (+24 / -4)
- `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets` (+11 / -2)
- `entry/src/main/ets/entryability/EntryAbility.ets` (+7)

## Architecture summary

The commit introduces a singleton bridge (`NotificationLyricController`) that fuses two existing streams into the AVSession metadata title field used by the system music card:

1. `MiniLyricsController.addListener(...)` — `(songId, line, hasLyrics)` real-time stream, fires immediately on subscribe and on every cursor change.
2. `AudioPlayerService.addOnSongChangedListener(...)` — fires when the playing song changes; `notifySongChanged` updates `AppStorage.currentSongTitle` BEFORE invoking listeners (`AudioPlayerService.ets:76-85`), so any downstream `publish()` reads the new base title atomically.

`AudioPlayerService` gains a `_displayTitleOverride: string | null` field (line 136) and a public `setNotificationDisplayTitle(merged)` (lines 408-416). Both metadata writers (`updateSessionMetadata` line 358, `updateSessionCoverImage` line 389) now resolve the title as `override-or-baseTitle`, so cover loads do not clobber the lyric line.

`LyricsSettingsViewModel.onNotificationBarLyricsChanged` (lines 108-112) persists the toggle and calls `NotificationLyricController.getInstance().onToggleChanged()` to flip the title in the same frame.

Init order in `EntryAbility.onCreate` (lines 302-314): `AudioPlayerService.initContext` → `MiniLyricsController.init` → `NotificationLyricController.init`. Because `MiniLyricsController.addListener` fires immediately with the current `(songId, line, hasLyrics)` (line 104), the new controller picks up the restored song's state without a startup hop.

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | Toggle ON, song has lyrics — title shows live lyric line | PASS | — |
| 2 | Toggle ON, current song has no lyrics — title stays as song title | PASS | — |
| 3 | Toggle ON, switch to lyric-less song — title falls back to song title | PASS | — |
| 4 | Toggle ON, switch to lyric-bearing song — title shows new song's live lyric | PASS | — |
| 5 | Toggle ON, pause — title freezes at last lyric line | UNABLE TO VERIFY | Static analysis confirms anchor freeze; needs device verification |
| 6 | Toggle OFF (default) — title always shows song title | PASS | — |
| 7 | Toggle flipped OFF mid-playback — title reverts to song title in same frame | PASS | — |

## Detailed Scenario Reviews

### Scenario 1 — Toggle ON, song has lyrics, live lyric line shown

**Description**: User opens the toggle, the playing song has lyrics, the notification card title displays the real-time lyric line and updates as the cursor advances.

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/model/NotificationLyricController.ets:62-66` — lyric listener stores `currentLine`/`hasLyrics` and calls `publish()`.
- `NotificationLyricController.ets:88-101` — `publish()` selects the lyric line when `enabled && hasLyrics && currentLine.length > 0`.
- `MiniLyricsController.ets:158-175` — 200 ms tick recomputes the cursor and notifies subscribers on every line change.
- `AudioPlayerService.ets:362-367` — `updateSessionMetadata` writes the override into `avSession.AVMetadata.title`.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 2 — Toggle ON, current song has no lyrics

**Description**: Toggle is ON but the playing song has no embedded or sidecar lyrics. The notification card title remains the song title.

**Verdict**: PASS

**Evidence**:
- `MiniLyricsController.ets:163-164` — `newHasLyrics = doc.isScrollable && doc.lines.length > 0`; static-only or empty docs report `hasLyrics=false`. Comment block at `MiniLyricsController.ets:14-17` documents this exactly.
- `NotificationLyricController.ets:90-94` — when `hasLyrics` is false, `display = baseTitle` (the current song title).
- `AudioPlayerService.ets:362` — `baseTitle` is `AppStorage.currentSongTitle`, which `notifySongChanged` keeps current.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 3 — Toggle ON, switch to a lyric-less song

**Description**: While displaying live lyrics, user switches to a song with no lyrics; the title falls back to the new song's title.

**Verdict**: PASS

**Evidence**:
- `AudioPlayerService.ets:73-86` — `notifySongChanged` writes the new `currentSongTitle` into AppStorage *before* invoking song-changed listeners.
- `MiniLyricsController.ets:137-156` — on song change clears `currentLine=''`, `hasLyrics=false`, then notifies; this triggers `NotificationLyricController.lyricsListener` → `publish()` which now falls back to the new base title.
- `NotificationLyricController.ets:69-73` — additionally subscribes to `addOnSongChangedListener` so the fallback also fires from the song-change bus, covering edge cases where the lyrics path defers.
- After `MiniLyricsController.loadLyrics` resolves with no scrollable lines (`MiniLyricsController.ets:147-155`), `hasLyrics` stays false → title remains the song title.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 4 — Toggle ON, switch to a lyric-bearing song

**Description**: User switches to a song with lyrics; the notification title shows the line corresponding to the current playback position and updates with the cursor.

**Verdict**: PASS

**Evidence**:
- Initial transition handled identically to Scenario 3: title flips to the new song title while the async load is in flight (`MiniLyricsController.ets:143-145`).
- `MiniLyricsController.ets:147-150` — once `loadLyrics` resolves it calls `tickOnce()` immediately, so the first line appears without waiting 200 ms.
- `MiniLyricsController.ets:158-175` then keeps publishing on every cursor change → `NotificationLyricController.publish()` pushes each new line via `setNotificationDisplayTitle`.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 5 — Toggle ON, pause holds last lyric line

**Description**: While displaying live lyrics, user pauses. The notification title freezes at the lyric line corresponding to pause time.

**Verdict**: UNABLE TO VERIFY (statically: looks correct; needs device verification)

**Evidence**:
- `MiniLyricsController.ets:9-11` documents that the 200 ms tick is "always-on: paused state is naturally handled by `AudioPlayerService.getCurrentTimeMs()` freezing its anchor, so the cursor freezes too."
- `MiniLyricsController.ets:170-174` — only re-publishes when the line index changes; once frozen, it stops issuing notifications, and `NotificationLyricController.publish()` dedupes via `lastPublished` (`NotificationLyricController.ets:96-99`), so no spurious AVSession writes.
- `AudioPlayerService.getCurrentTimeMs()` anchor-freeze on pause is project-internal behaviour relied upon by spec8 and earlier; full guarantee depends on the AVPlayer state machine on real hardware.

**Gaps**: None at the static-analysis level. Behaviour during pause depends on `AudioPlayerService.getCurrentTimeMs()` returning a frozen value, which static review cannot fully prove.

**Suggestions**: Add a device-side check during integration testing: pause for ~3 seconds and confirm the notification card title does not advance. (Tracked in Stage 7 — Self-Testing.)

---

### Scenario 6 — Toggle OFF (default) — title always shows song title

**Description**: Toggle is in its default OFF state. Notification title always shows the song title regardless of lyric availability.

**Verdict**: PASS

**Evidence**:
- `EntryAbility.ets:102` — `PersistentStorage.persistProp('notificationBarLyrics', false)` seeds the default to OFF.
- `NotificationLyricController.ets:90` — `const enabled = AppStorage.get<boolean>('notificationBarLyrics') ?? false`. When OFF, the line-merge branch at `:92-94` is skipped, so `display = baseTitle`.
- `AudioPlayerService.ets:358-386` writes that base title into the AVSession metadata.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 7 — Toggle flipped OFF mid-playback restores song title

**Description**: User has toggle ON and live lyrics are showing. User opens settings and turns the toggle OFF. The notification title immediately reverts to the song title.

**Verdict**: PASS

**Evidence**:
- `LyricsSettingsViewModel.ets:108-112` — `onNotificationBarLyricsChanged` persists the new value via `SettingsStore.save` (which writes AppStorage synchronously, `SettingsStore.ets:41-42`) and then calls `NotificationLyricController.onToggleChanged()`.
- `NotificationLyricController.ets:75-78` — `onToggleChanged()` calls `publish()`.
- `NotificationLyricController.ets:88-101` — with `enabled=false`, the merged display becomes `baseTitle`. Because the previous published value was a lyric line, `display !== lastPublished`, and `setNotificationDisplayTitle(baseTitle)` runs.
- `AudioPlayerService.ets:413-416` — `setNotificationDisplayTitle` writes the override and calls `updateSessionMetadata`, which pushes the new title to `avSession.setAVMetadata`.

**Gaps**: None.

**Suggestions**: None.

---

## Cross-Cutting Issues

### Permission Coverage
No new permissions are required. AVSession metadata writes use the already-active `avSession.AVSession` created in `AudioPlayerService.initContext` (line 221). Background audio permission and AVSession capability were already declared for prior specs.

### Navigation Completeness
Settings → 歌词 → 通知栏歌词 toggle is rendered by `LyricsSettingsPage.ets:230-232` (`NotificationBarLyricsSection`) and bound to `vm.notificationBarLyricsVM`. Page navigation is unchanged by this commit.

### State Management
- Persistence: `notificationBarLyrics` is persisted via `PersistentStorage.persistProp` (`EntryAbility.ets:102`) and rehydrated into AppStorage on `aboutToAppear` (`EntryAbility.ets:148`).
- AppStorage flow: `LyricsSettingsViewModel.onNotificationBarLyricsChanged` updates AppStorage synchronously through `SettingsStore.save`, then triggers a `publish()` that re-reads it. No race condition.
- Lifecycle: `NotificationLyricController.init()` is idempotent (line 50 guard); `destroy()` (lines 80-87) properly removes both listeners. There is no explicit destroy site in `EntryAbility`, which is acceptable for a process-lifetime singleton.
- Memory: listeners are stored as named instance fields and registered/unregistered with the correct identity, so no leaks.

### API Compatibility
- `avSession.AVMetadata.title` and `setAVMetadata` are stable system APIs already in use elsewhere in `AudioPlayerService`.
- No new ArkTS or HarmonyOS Kit APIs are introduced.

### Resource Completeness
- The `app.string.notification_bar_lyrics` resource is referenced by `LyricsSettingsModel.ets:14-15` and was already present pre-commit. No new resource files are required.

## Final Assessment

**Overall Verdict**: PASS

- **Fully covered scenarios**: 1, 2, 3, 4, 6, 7
- **Partially covered scenarios**: (none)
- **Not covered scenarios**: (none)
- **Requires runtime verification**: 5 (pause-freeze behaviour relies on AVPlayer anchor semantics that cannot be fully proven by static review).

The commit cleanly fulfils the spec. The single override field on `AudioPlayerService` plus the dedupe in `publish()` keeps `setAVMetadata` calls minimal. Init order, AppStorage write-before-listener-call ordering inside `notifySongChanged`, and `MiniLyricsController.addListener`'s immediate replay together guarantee that title transitions (song change, toggle flip, pause/resume) happen in the same frame as the user-visible event.

**Recommended Priority Fixes**:
1. None blocking. Verify Scenario 5 on device during Stage 7 self-testing — confirm the notification card title does not advance while paused.

**Optional polish (non-blocking)**:
- `setNotificationDisplayTitle` always rewrites the override even when called with the same merged string. This is harmless because `NotificationLyricController.publish()` already dedupes via `lastPublished`, but if this method gains other callers in the future, mirroring the dedupe inside `AudioPlayerService` would be defensive.
- When the toggle is OFF, `setNotificationDisplayTitle` is called with the song title rather than `null`. This works correctly today (the override equals the base title), but passing `null` in the OFF path would make the override semantics in the comment at `AudioPlayerService.ets:130-135` literally true. Cosmetic only.
