# spec12 — Notification Bar Lyrics — Implementation Plan

## Goal

Wire the existing `notificationBarLyrics` toggle (Settings → Lyrics → 通知栏歌词,
already persisted via `SettingsStore` + `PersistentStorage`) so that when ON, the
**title field** of the system AVSession metadata (which is what HarmonyOS
renders as the title on the notification bar / lock-screen music card) is
replaced with the current real-time lyric line, and when OFF (or there is no
lyric / no current line yet) it falls back to the song's actual title.

Default: OFF. Behavior must match each of the seven scenarios in the spec.

## MVVM Owner Boundary

| Concern                                                        | Owner                                              |
|----------------------------------------------------------------|----------------------------------------------------|
| Settings UI (toggle row, page chrome)                          | `LyricsSettingsPage` (View)                        |
| Toggle action + persisted-flag wiring                          | `LyricsSettingsViewModel` (existing — extend `(val) => ...`) |
| Live notification-title synthesis (writer)                     | `NotificationLyricController` (Model — NEW)        |
| AVSession metadata write (`setAVMetadata` with merged title)   | `AudioPlayerService` (Model — small extension)     |
| Real-time lyric source                                         | `MiniLyricsController` (Model — already exists)    |
| Toggle storage / persistence                                   | `SettingsStore` + `PersistentStorage` (existing)   |

Key rules respected:

- Page does not write metadata. The Page only flips the persisted flag through
  the existing ViewModel callback.
- ViewModel does not own the live refresh path — it only persists the flag and
  notifies the new controller of the change so the controller re-renders the
  current title.
- Persistence stays in `SettingsStore` (the existing owner). No new MMKV/RDB.
- `aboutToAppear` is **not** used as live sync. The controller listens on the
  song-change bus + the existing 200 ms `MiniLyricsController` listener and
  pushes title updates to AVSession in real time.
- No mirror state, no fake defaults. The flag is read live from
  `AppStorage.get<boolean>('notificationBarLyrics')` (which is the source of
  truth maintained by `SettingsStore.save` + `PersistentStorage`).

## Repo Reality (writer / reader / refresh path)

- **Toggle writer (already exists)**:
  `LyricsSettingsViewModel.initFromModel` builds `notificationBarLyricsVM`'s
  on-change callback as
  `SettingsStore.getInstance().save('notificationBarLyrics', val)`. That call
  updates AppStorage **and** the Preferences memory cache (flushed on
  `onBackground`). `EntryAbility.onCreate` rehydrates AppStorage from
  Preferences (line 147). The TODO comment on line 100 is what spec12 fills in.

- **Lyric source (already exists)**:
  `MiniLyricsController` (singleton) is initialized in `EntryAbility.onCreate`
  after `AudioPlayerService.restoreFromPersisted`. It subscribes to the
  multi-listener song-change bus on `AudioPlayerService` and runs a 200 ms
  cursor tick. It exposes `addListener(fn)` with signature
  `(songId, line, hasLyrics)`. New subscribers are immediately invoked with the
  current state — perfect for the controller's startup bootstrap.

- **AVSession metadata (already exists)**:
  `AudioPlayerService.updateSessionMetadata()` and
  `updateSessionCoverImage(pm)` both call `session.setAVMetadata({ title: ... })`
  reading `AppStorage.get('currentSongTitle')`. They are private. The system
  notification card reflects the most recently set `title`.

- **Refresh path** to keep the notification card in sync:
  1. Song changes → `notifySongChanged` → `MiniLyricsController.onSongChanged`
     → controller listener fires with new `(songId, line, hasLyrics)`.
  2. Lyric line changes → 200 ms tick in `MiniLyricsController.tickOnce`
     → controller listener fires with new `(songId, line, hasLyrics)`.
  3. Toggle changes → `LyricsSettingsViewModel.onNotificationBarLyricsChanged`
     → controller `onToggleChanged()` re-renders title immediately.
  4. Pause / resume / completion / clear: lyric line stays last-known until the
     next change (matches scenario 5 — pause freezes on the last line).
  5. Stop / clear queue: `AudioPlayerService.stop()` / `clear()` clears
     `currentSongTitle` to `''` and the controller publishes `''`. AVSession
     stays deactivated (existing behavior).

## Files To Add / Edit

### NEW: `entry/src/main/ets/model/NotificationLyricController.ets`

Singleton, owned by Model layer. Mirrors the shape of
`MiniLyricsController` / `CurrentSongCoverController` (same project pattern):

- `init()` — idempotent. Called once from `EntryAbility.onCreate` **after**
  `MiniLyricsController.getInstance().init()`.
- Subscribes to `MiniLyricsController.getInstance().addListener(fn)` so it
  gets `(songId, line, hasLyrics)` updates plus an immediate initial sync.
- Holds latest `(line, hasLyrics)` in private fields.
- On every listener fire, AND on `onToggleChanged()` (called by the ViewModel),
  computes the merged title and calls
  `AudioPlayerService.getInstance().setNotificationDisplayTitle(merged)`.
- Title resolution:
  - Read live: `enabled = AppStorage.get<boolean>('notificationBarLyrics') ?? false`
  - Read live: `title = AppStorage.get<string>('currentSongTitle') ?? ''`
  - If `enabled && hasLyrics && line.length > 0` → display = `line`
  - Else → display = `title`
  - When `display` differs from the last published value, push to
    `AudioPlayerService`. Otherwise no-op (avoids needless `setAVMetadata`).
- Also subscribes to song-change directly via
  `AudioPlayerService.getInstance().addOnSongChangedListener(...)` so the
  fallback title updates **immediately** on song switch even before the
  `MiniLyricsController` async lyric load resolves (covers scenarios 3 & 4
  cleanly without flicker).
- No `aboutToAppear` use; no UI touch; survives across pages because it lives
  in the singleton bus.

### EDIT: `entry/src/main/ets/model/AudioPlayerService.ets`

Add the minimum surface for the controller to push the merged title without
changing the existing reader path:

1. Add a private field `private _displayTitleOverride: string | null = null`.
2. Add public method:
   ```
   setNotificationDisplayTitle(merged: string | null): void {
     this._displayTitleOverride = merged
     this.updateSessionMetadata()
   }
   ```
3. In `updateSessionMetadata()` and `updateSessionCoverImage()`, replace the
   `title:` field source with:
   `const baseTitle = (AppStorage.get('currentSongTitle') as string) ?? ''`
   `metadata.title = (this._displayTitleOverride !== null && this._displayTitleOverride.length > 0) ? this._displayTitleOverride : baseTitle`
   Everything else (artist, duration, mediaImage, assetId) stays untouched.
4. No other call site changes — every existing place that currently calls
   `updateSessionMetadata()` (prepared, playing, cover-listener) automatically
   picks up the override.
5. On `stop()` / `clear()` the existing code already wipes `currentSongTitle`
   to `''`. After that, when the controller receives the next listener fire,
   it will publish `''` as the merged title; AVSession is deactivated anyway.
   No extra logic needed here.

### EDIT: `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets`

Replace the TODO inline lambda for `notificationBarLyricsVM` with a call to a
new instance method `onNotificationBarLyricsChanged(val: boolean)`:

```
onNotificationBarLyricsChanged(val: boolean): void {
  this.model.notificationBarLyrics.isOn = val
  SettingsStore.getInstance().save('notificationBarLyrics', val)
  // Notify the singleton controller so the AVSession title flips immediately
  NotificationLyricController.getInstance().onToggleChanged()
}
```

This keeps action + state in the ViewModel and delegates persistence + refresh
to their owners (`SettingsStore` / `NotificationLyricController`).

### EDIT: `entry/src/main/ets/entryability/EntryAbility.ets`

Add one line right after the existing `MiniLyricsController.getInstance().init()`
call (around line 307):

```
NotificationLyricController.getInstance().init()
```

Initialization order matters: `AudioPlayerService.restoreFromPersisted` →
`AudioPlayerService.initContext` (creates AVSession) → `MiniLyricsController.init`
→ `NotificationLyricController.init`. The new controller's listener fires
immediately with the current `(songId, line, hasLyrics)`, so the very first
AVSession metadata push (during 'prepared' / 'playing' inside
`AudioPlayerService`) already sees the override if the toggle was ON before
restart.

## Scenario-by-Scenario Verification

1. **Toggle ON, song with lyrics, playing** —
   `MiniLyricsController` tick produces `(line, hasLyrics=true)` every 200 ms.
   Controller pushes merged title each time the line changes; only rewrites
   AVSession when the value actually differs. System notification title
   refreshes in real time. PASS.

2. **Toggle ON, song without lyrics** —
   `hasLyrics = doc.isScrollable && doc.lines.length > 0` is false (no
   embedded LRC, no sidecar `.lrc`). Controller falls through to `baseTitle`.
   AVSession title equals song title. PASS.

3. **Toggle ON, switching to a song with no lyrics** —
   Switching fires `notifySongChanged` first → controller's
   `addOnSongChangedListener` fallback path immediately publishes the new
   `currentSongTitle`. Then `MiniLyricsController.onSongChanged` runs,
   eventually publishes `(line='', hasLyrics=false)` for the new song —
   controller publishes the same title again (no-op gate). PASS.

4. **Toggle ON, switching to a song with lyrics** —
   Same path: fallback title shows first; once the new song's lyrics load and
   the 200 ms tick produces a non-empty line, the controller publishes the
   line as the merged title. Real-time updates continue. PASS.

5. **Toggle ON, paused** —
   `AudioPlayerService.pause()` doesn't change `currentSongTitle` or the
   `MiniLyricsController` cursor, just freezes time. The last published
   merged title (the line at pause time) stays on AVSession until the next
   listener fire (which won't come until resume / song change). PASS.

6. **Toggle OFF (default)** —
   `enabled = false` → controller always picks `baseTitle`. AVSession title
   equals song title regardless of lyric state. PASS.

7. **Toggle OFF mid-playback** —
   `LyricsSettingsViewModel.onNotificationBarLyricsChanged(false)` →
   `SettingsStore.save('notificationBarLyrics', false)` (AppStorage flips) →
   `NotificationLyricController.onToggleChanged()` recomputes immediately and
   publishes `baseTitle`. Notification title flips back to the song title in
   the same frame. PASS.

## Race / Lifecycle Notes

- The controller's `onToggleChanged()` and listener callback both call into
  `AudioPlayerService.setNotificationDisplayTitle`, which wraps
  `updateSessionMetadata()`. `setAVMetadata` is async; concurrent calls are
  safe (the system serializes them on the AVSession). A listener fire that
  arrives mid-toggle simply produces the latest merged title.
- `sessionDeactivated` guard in `AudioPlayerService.updateSessionMetadata`
  already short-circuits when the queue is empty / cleared. The controller
  doesn't need to know about session lifecycle.
- The `_displayTitleOverride` is a single field, no observed/track decoration
  needed (it does not drive UI state — only AVSession push).
- Per-song reset: not required. When `currentSongTitle` becomes `''` (clear),
  the merged title also becomes `''` (since override is at most equal to the
  empty line under those conditions). Otherwise the override is harmless
  because every `updateSessionMetadata` call recomputes from
  `AppStorage.get('currentSongTitle')` plus the latest override.

## Out Of Scope

- Restart/race-edge cases for `MiniLyricsController` already handled by its
  own loadId / clear() logic. spec12 reuses them as-is.
- Notification card subtitle / artwork / actions — untouched.
- Other lyric outputs (desktop lyrics, status bar, Xposed) — untouched.
- New persistence — none. The toggle key `notificationBarLyrics` already
  exists in `EntryAbility` and `SettingsStore`.

## Verification Commands

After implementation:

- Build: `hvigorw assembleHap --mode module -p product=default --no-daemon`
- Manual: launch app, play a song with `.lrc`, observe the system
  notification card title cycles with each lyric line; toggle off in
  Settings → 歌词 → 通知栏歌词, observe title reverts to the song name.
