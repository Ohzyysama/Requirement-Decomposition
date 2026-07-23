# Spec10 Logic Plan — 自动播放 (Auto-Play on Launch)

## Source of truth

- Spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec10/plan.md`
- UI already built (Stage 3): switch row on `StartupAndBackendPage` with placeholder VM.

## Feature summary

Setting: 设置 → 启动与后台 → 自动播放 switch. Persisted, default OFF.
When ON and cold launch restores a valid current song from the persisted queue/progress,
the app auto-resumes playback from the saved position and shows a toast `自动播放`.
When OFF, or queue is empty after restore, nothing plays and no toast appears.

## Ground truth (existing code this plan builds on)

| Surface | File | Current state |
|---|---|---|
| VM (writer of autoPlayback) | `entry/src/main/ets/viewmodel/StartupAndBackendViewModel.ets` | `@Track autoPlayback` + `setAutoPlayback(val)` exists but `persistAutoPlayback()` is a TODO that only logs. |
| Model | `entry/src/main/ets/model/StartupAndBackendModel.ets` | Plain data class, unused by VM today. Kept for MVVM shape only. |
| Page (binding) | `entry/src/main/ets/pages/StartupAndBackendPage.ets` | HdsListItemCard + SuffixSwitch bound to `vm.autoPlayback`, calls `vm.setAutoPlayback(val)`. |
| Persistence layer | `entry/src/main/ets/model/SettingsStore.ets` | Singleton used by every other setting VM; `save(key, value)` writes AppStorage + Preferences cache, `get()` reads, `flush()` in `onBackground`. |
| Launch restore | `entry/src/main/ets/entryability/EntryAbility.ets::onCreate` | Already (a) `PersistentStorage.persistProp` for most toggles, (b) `AppStorage.setOrCreate(... ss.get(...))` pattern to backfill from Preferences, (c) calls `restoreFromPersisted(fileUri, songId, progress, duration)` + `restoreQueues(...)` on `AudioPlayerService`. Pending seek is wired through AVPlayer `prepared` state. |
| Playback kick-off on restored song | `AudioPlayerService.togglePlayPause()` | When `sourceLoaded` is false it pulls `pendingFileUri`/`pendingSongId` (or AppStorage fallback) and calls `play()`. `play()` runs through `doPlay()` → AVPlayer prepare → `stateChange:'prepared'` applies the `pendingSeekMs`. This is exactly the behavior Scene 4 needs. |
| Precedent trigger (spec9) | `entry/src/main/ets/pages/main/MainPage.ets::aboutToAppear` (lines ~376–383) | After `syncMiniPlayerData`, reads `AppStorage.get<boolean>('autoOpenPlaybackScreen')` and calls `this.vm.openPlayerImmediate()`. This is the one-shot launch hook; we mirror the pattern. |
| Toast API | `@kit.ArkUI` `promptAction.showToast({ message })` — already used across VMs (e.g. `MainPageViewModel`, `PlayerPageViewModel`). |
| String resource | `auto_playback` already exists in `base/zh/ug` string.json as `自动播放`. |

## MVVM owner boundaries (what must stay where)

- **Page** — only binds UI and performs the one-shot launch wiring.
  - `StartupAndBackendPage` already binds to VM; no changes.
  - `MainPage.aboutToAppear` calls a new VM action after the existing `autoOpenPlaybackScreen` check. Page does not read the flag itself and does not own playback logic.
- **ViewModel** — owns actions and validation.
  - `StartupAndBackendViewModel.setAutoPlayback(val)` writes to `SettingsStore` (no direct AppStorage fiddling — `SettingsStore.save` does both).
  - `MainPageViewModel.autoPlaybackOnLaunchIfEnabled()` (new) reads the flag and triggers the service; owns the toast side-effect.
- **Model / DataSource / Service** — owns state and playback.
  - `SettingsStore` persists `autoPlayback`.
  - `AudioPlayerService` is the single writer of playback state. Launch path uses the existing `togglePlayPause()` / `play()` API — no persistence logic moved into Page.
  - `EntryAbility.onCreate` owns restore wiring for the flag (parallel to every other persisted setting).
- Do not mirror the persisted flag as a second VM field on `MainPageViewModel` — it already reads flags via `AppStorage.get` (same pattern as `autoOpenPlaybackScreen`).
- `aboutToAppear` is one-shot and is the correct place for this trigger (it IS a cold-launch event, not live sync).

## Scenario → code mapping

| Scene | Behavior | Ownership |
|---|---|---|
| 1 | Default OFF shown on page | VM `@Track autoPlayback = false` + EntryAbility restore defaulting `false`. |
| 2 | User turns ON | Page → `vm.setAutoPlayback(true)` → `SettingsStore.save('autoPlayback', true)` (writes AppStorage + Preferences cache) → `flush()` on background. |
| 3 | User turns OFF | Symmetric. |
| 4 | Cold launch with flag ON + restored current song | EntryAbility.onCreate: restore queue + `restoreFromPersisted(...)`; MainPage.aboutToAppear (after `syncMiniPlayerData`) calls `vm.autoPlaybackOnLaunchIfEnabled()` which checks flag, checks a non-empty `currentSongId`/`currentSongFileUri`, calls `AudioPlayerService.togglePlayPause()`, shows `promptAction.showToast({ message: $r('app.string.auto_playback') })`. |
| 5 | Flag OFF | `autoPlaybackOnLaunchIfEnabled()` early-returns; queue/progress are already positioned by EntryAbility restore; UI remains paused. |
| 6 | Flag ON but no restored song | Same method sees empty `currentSongId` → early-return, no toast, no playback. |

## Change set

### 1. `StartupAndBackendViewModel.ets` — replace the TODO stub
- Import `SettingsStore`.
- Constructor reads initial value from `AppStorage.get<boolean>('autoPlayback')` (fall back to `model?.autoPlayback ?? false`).
- `setAutoPlayback(isOn)` writes `this.autoPlayback = isOn` and calls `SettingsStore.getInstance().save('autoPlayback', isOn)`. Remove the `console.info` stub.
- `toggleAutoPlayback()` stays but routes through `setAutoPlayback` to keep a single write path.

### 2. `EntryAbility.ets::onCreate` — register and restore the flag
- Add `PersistentStorage.persistProp('autoPlayback', false)` in the settings-persist block (next to `autoOpenPlaybackScreen` line ~93).
- In the `SettingsStore` restore block (next to `autoOpenPlaybackScreen` line ~137–138) add:
  `AppStorage.setOrCreate('autoPlayback', ss.get('autoPlayback', false) as boolean)`.
- No flush/onBackground change needed — `SettingsStore.getInstance().flush()` already covers all saved keys.

### 3. `MainPageViewModel.ets` — add launch action
- Import `AudioPlayerService` (already imported where needed) and `promptAction` (already imported line 26).
- New method `autoPlaybackOnLaunchIfEnabled()`:
  1. If `AppStorage.get<boolean>('autoPlayback') !== true` → return.
  2. Read `currentSongId` and `currentSongFileUri` from AppStorage; if either is empty → return (Scene 6).
  3. Query `AudioPlayerService.getInstance().isCurrentlyPlaying()` — if already playing (unlikely on cold launch but defensive) → return, no toast.
  4. Call `AudioPlayerService.getInstance().togglePlayPause()` — this goes through `play()` → `doPlay()` → AVPlayer prepare → `stateChange:'prepared'` applies `pendingSeekMs` (seeded earlier by `restoreFromPersisted`). Result: playback resumes at saved progress on the current song.
  5. Call `promptAction.showToast({ message: $r('app.string.auto_playback') })`.
- Keep the method idempotent and guard with a local `_autoPlaybackTriggered` flag so re-entries of `aboutToAppear` cannot double-fire.

### 4. `MainPage.ets::aboutToAppear` — wire the trigger
- After the `autoOpenPlaybackScreen` block (around line 381), add a parallel call:
  ```
  this.vm.autoPlaybackOnLaunchIfEnabled()
  ```
- Placement matters: must be AFTER `syncMiniPlayerData` so `currentSongId`/`currentSongFileUri` have been observed, and AFTER EntryAbility's synchronous queue restore (guaranteed by the `onCreate` → `onWindowStageCreate` → `loadContent` ordering).
- Do not guard with a page-level flag — VM-level `_autoPlaybackTriggered` in step 3 is the single source of truth.

### 5. `StartupAndBackendModel.ets` — no change required
Keep the data class to preserve the MVVM three-layer shape even though persistence now lives in `SettingsStore`. Matches the pattern used by other settings pages.

## Writer / reader / binding / refresh

- **Writer (setting value)**: `StartupAndBackendViewModel.setAutoPlayback` → `SettingsStore.save('autoPlayback', val)` → AppStorage + Preferences cache. Disk flush on `onBackground`.
- **Writer (playback state)**: `AudioPlayerService` (unchanged, single source of truth for AVPlayer + `isPlaying` AppStorage key).
- **Reader**: `MainPageViewModel.autoPlaybackOnLaunchIfEnabled` reads `AppStorage.get<boolean>('autoPlayback')`. `StartupAndBackendViewModel` reads from AppStorage on construction.
- **Binding path**: `StartupAndBackendPage` binds to `vm.autoPlayback` via SuffixSwitch `isCheck`.
- **Refresh path**: Switch toggle is local VM state — no cross-page refresh needed. The setting is read only at cold launch by MainPageVM. No mounted-page state mirrors the flag.

## Verification steps (Stage 5 / 7 handoff)

1. Build succeeds (`hvigor clean assembleHap`).
2. Scene 1: fresh install → StartupAndBackend page shows switch OFF.
3. Scene 2/3: toggle switch → kill app → relaunch → switch state persists.
4. Scene 4: with switch ON, play a song, pause mid-track, kill app, relaunch → on MainPage first render, toast `自动播放` appears and playback resumes at the saved position.
5. Scene 5: switch OFF, same flow → paused on launch, no toast.
6. Scene 6: switch ON, clear play queue (or fresh install), relaunch → no toast, no playback, no errors.

## Out-of-scope (to avoid scope creep)

- No changes to queue restore ordering or persistence schema.
- No new AppStorage keys beyond `autoPlayback`.
- No modification of AVPlayer state machine or background task logic.
- No Android `AUTO_PLAYBACK`-ism imports — we piggyback on the HMOS persistence already in place.
