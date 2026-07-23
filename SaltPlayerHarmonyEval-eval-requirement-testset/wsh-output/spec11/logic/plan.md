# Spec11 Logic Implementation Plan — Play/Pause Fade In/Out

Source spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec11/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 1. Scope and behavior summary

Hook a fade envelope onto `AVPlayer.setVolume(0.0..1.0)` around every user-initiated play/pause transition. Song-switch paths (next/prev/queue tap/autoplay-on-completion) skip the outgoing fade-out but benefit from fade-in when the new song starts playing. Toggle is real-time (read from AppStorage per-call). Fade duration is 500 ms. Operations are serialized so a resume requested during an active fade-out waits for the fade-out to finish before starting fade-in.

## 2. Repo reality (already present)

- `AudioOutputViewModel.fadeInOutEnabled` tracked, wired through `setFadeInOutEnabled()` → `SettingsStore.save('fadeInOutEnabled', value)` which updates AppStorage + Preferences.
- `AudioOutputViewModel.initFadeInOutVM()` builds `fadeInOutVM: SwitcherRowViewModel` with the correct resource.
- `EntryAbility.ets` already calls `PersistentStorage.persistProp('fadeInOutEnabled', true)` and restores it into AppStorage from `SettingsStore` on startup (default `true`).
- `AudioOutputPage.ets` has the fade switcher row commented out under `AudioOutputTogglesCard()`.
- `AudioPlayerService` singleton owns the `media.AVPlayer` instance; all user entry points (`pause`, `resume`, `togglePlayPause`, `skipNext`, `skipPrevious`, `playByIdInQueue`, `setQueue`, `play`, `stop`, `clear`) go through it.
- Existing serialization lock on song switches: `playLock` promise (used by `play()`, `stop()`, `clear()`).

## 3. MVVM owner boundaries (authoritative)

| Concern | Owner | File |
|---|---|---|
| Switch UI row (rendering + tap → toggle) | Page | `entry/src/main/ets/pages/AudioOutputPage.ets` |
| Switch state + action (toggle handler, persist) | ViewModel | `entry/src/main/ets/viewmodel/AudioOutputViewModel.ets` |
| Persist flag (AppStorage + Preferences) | Model (store) | already: `SettingsStore`, `PersistentStorage.persistProp` (EntryAbility) |
| Fade envelope + pause/resume orchestration + mutex | Model (service) | `entry/src/main/ets/model/AudioPlayerService.ets` |
| Reading `fadeInOutEnabled` at each pause/resume call | Model (service) | same |
| Callers (PlayerPage, MiniPlayer, MainPage, SleepTimer, ExitApp, AVSession callbacks) | ViewModel / Model only call `service.pause()` / `service.resume()` / `service.togglePlayPause()` | unchanged |

Rules honored:
- Persistence stays in `SettingsStore` + `PersistentStorage` (already the owner path).
- Fade state lives in the service (the one owner of the AVPlayer lifecycle); not duplicated in the VM or the page.
- No reliance on `aboutToAppear` for live sync — the switch row re-reads the tracked VM field on every render tick.
- No mirror state in the page for fade — the VM is the one source for UI.
- Song-switch paths never set `setVolume(0)` without a follow-up ramp; no partial/stuck-mute states.

## 4. Concrete edits

### 4.1 Page — reveal the switcher row

File: `entry/src/main/ets/pages/AudioOutputPage.ets`
- In `AudioOutputTogglesCard()`, uncomment the `ItemSwitcherRowComponent({ vm: this.vm.fadeInOutVM })` block that renders after the audio-focus switcher. `vm.initFadeInOutVM()` is already invoked in `aboutToAppear()`.
- No layout/style change.

### 4.2 ViewModel — re-sync UI state after switch

File: `entry/src/main/ets/viewmodel/AudioOutputViewModel.ets`
- In `setFadeInOutEnabled(value)`, after persisting, also push to the child `fadeInOutVM.isOn` so the toggle matches when re-entered from navigation stack. Example: `this.fadeInOutVM.isOn = value`.
- Inside `initFadeInOutVM()`, seed from current `AppStorage.get<boolean>('fadeInOutEnabled') ?? this.fadeInOutEnabled` rather than the stale local only — live value wins when the page remounts after the flag changed elsewhere (not expected today, but keeps the owner path clean).

No persistence added here — owner path is `SettingsStore`.

### 4.3 Service — fade envelope, mutex, and hooks

File: `entry/src/main/ets/model/AudioPlayerService.ets`

Add private fields:
- `private _fadeLock: Promise<void> = Promise.resolve()` — serializes user pause/resume envelope calls (scenario 7).
- `private _fadeInPendingForNextPrepared: boolean = false` — set true in `doPlay()` right before `fdSrc` assignment when fade-in should apply to the newly loaded song; consumed in `stateChange:'prepared'` handler.
- `private _currentVolume: number = 1.0` — last applied volume (so fade-out starts from the correct level if user previously ramped manually; currently always 1.0).
- `private static readonly FADE_DURATION_MS = 500`
- `private static readonly FADE_STEPS = 20` (25 ms tick granularity — smooth and cheap)

Constants for AppStorage key: keep using `'fadeInOutEnabled'` directly (no new key).

Helper: `private isFadeEnabled(): boolean` → `return AppStorage.get<boolean>('fadeInOutEnabled') ?? true`. Reading per-call satisfies scenario 6 (real-time effective).

Helper: `private safeSetVolume(v: number): void` →
- Clamp to `[0, 1]`.
- If `this.avPlayer` is null, return.
- Try/catch around `this.avPlayer.setVolume(v)` (AVPlayer rejects in states `idle | initialized | released | error`). Log at warn, never throw.
- On success set `this._currentVolume = v`.

Helper: `private async rampVolume(from: number, to: number): Promise<void>`:
- Linear interpolation across `FADE_STEPS` steps, each `FADE_DURATION_MS / FADE_STEPS` ms.
- Abort early if `avPlayer` becomes null or enters `error`/`released` (detected via a nullable flag `_fadeAborted` that `setupListeners` flips in those states).
- Always finalize by writing the `to` value so we never leave a half-applied volume.

Helper: `private withFadeLock(op: () => Promise<void>): Promise<void>`:
- Chain on `this._fadeLock` (mirrors the existing `playLock` pattern). Next call awaits previous.

Modify entry points:

`pause(): Promise<void>`  (change return type to Promise; existing callers can still ignore it)
1. Early-out as today: only proceed if `avPlayer && this._isPlaying`.
2. Flip `this._playbackIntentActive = false` immediately (existing behavior, so interrupt-caused behavior is consistent).
3. Serialize through `withFadeLock(async () => { ... })`:
   - If `isFadeEnabled()`, `await rampVolume(this._currentVolume, 0.0)`.
   - Always finish by calling `this.avPlayer.pause()` (existing behavior).
4. Keep the synchronous `AppStorage.setOrCreate('isPlaying', ...)` updates inside the existing `stateChange:'paused'` handler — do not duplicate.

`resume(): Promise<void>`
1. Early-out as today: only proceed if `avPlayer && !this._isPlaying`.
2. Serialize through `withFadeLock(async () => { ... })`:
   - Capture `pendingSeek` (existing code path).
   - `await this.applyAudioFocusMode()` (existing).
   - If `isFadeEnabled()`, call `safeSetVolume(0)` **before** `player.play()`; else `safeSetVolume(1)`.
   - `player.play()` and apply `pendingSeek` (existing).
   - If `isFadeEnabled()`, `await rampVolume(0, 1)`.
   - Else (no fade) ensure volume ends at 1 via a final `safeSetVolume(1)`.

`togglePlayPause()` — no signature change. Internally it still calls `pause()` / `resume()`; those now return Promises but `togglePlayPause` does not need to await (callers are fire-and-forget).

Song switch: `doPlay()` in `AudioPlayerService`
1. Inside the song-switching branch (`this.currentSongId !== songId || !this._isPlaying`), right before `player.fdSrc = ...`, set `this._fadeInPendingForNextPrepared = isFadeEnabled()`. This does NOT apply any outgoing fade-out (per scenario 5 — switch is immediate).
2. In `stateChange:'prepared'` handler, before calling `player.play()` (end of the current prepared branch, after `applyAudioFocusMode(player).then(...)`):
   - If `this._fadeInPendingForNextPrepared`, call `safeSetVolume(0)` before `player.play()`, then after `player.play()` returns, kick off `rampVolume(0, 1)` (no need to block 'prepared' on the ramp — schedule via `void this.rampVolume(0, 1)`).
   - Else call `safeSetVolume(1)`.
   - Reset the flag to `false`.
3. This guarantees scenario 1 (resume after pause, same song): no reset happens because `this._isPlaying` is false and `this.currentSongId === songId`, so we go through `resume()` → fade branch; the `prepared` path is not re-entered.

Error/stop paths: in `stateChange:'error' | 'stopped' | 'released'` and `avPlayer.on('error', ...)`:
- Release the fade lock by resolving any pending ramp: set `_fadeAborted` flag; the active `rampVolume()` loop polls it every tick and exits early.
- Clear `_fadeInPendingForNextPrepared = false`.

AudioInterrupt `INTERRUPT_FORCE`:
- Already flips `_playbackIntentActive = false`. Add: abort any active fade (`_fadeAborted = true`), set `safeSetVolume(1)` on next resume (handled by resume’s branch). The system pause happened outside our control — no fade-out is applied (matches platform behavior and spec intent).

No changes to `stop()`, `clear()`, `setQueue()`, `addToPlayNext()`, `skipNext()`, `skipPrevious()`, `playByIdInQueue()` other than that they transitively benefit from the `doPlay()` prepared-fade-in hook for the new song.

## 5. Scenario coverage map

| Scenario | Owner path | How covered |
|---|---|---|
| 1 — paused → play, fade-in | Page toggle OFF-held true, user taps play, VM/button → `service.resume()` | Service `resume()` ramps 0 → 1 over 500 ms after `player.play()` |
| 2 — playing → pause, fade-out | Page button → `service.pause()` | Service `pause()` ramps current → 0, then `player.pause()` |
| 3 — flag OFF, play without fade | Same paths, `isFadeEnabled()` false | Service sets volume 1, no ramp |
| 4 — flag OFF, pause without fade | Same paths | Service calls `player.pause()` directly without ramp |
| 5 — song switch (next/prev/queue tap) | `service.skipNext/skipPrevious/playByIdInQueue` → internal `play()` → `doPlay()` → `reset()` | No outgoing fade-out; incoming song fade-in gated by `_fadeInPendingForNextPrepared` in `prepared` |
| 6 — real-time effective | Reader is `AppStorage.get('fadeInOutEnabled')` in `isFadeEnabled()` called per-op | No player restart, no cached flag |
| 7 — mutex fade-out then fade-in | `_fadeLock` chain | `resume()` awaits in-flight `pause()` fade before starting; envelope order preserved |

## 6. Edge cases considered

- `setVolume` rejected in wrong state: `safeSetVolume` catches silently and moves on.
- `rampVolume` outliving the AVPlayer: abort flag set on `released`/`error`.
- Sleep timer path (`SleepTimerService.pause()` → `saveStateBeforeExit()` → `terminateApp()`): `pause()` now returns a Promise, but the existing sleep-timer callsite does not await. That means sleep-timer exit may start fade-out and then be interrupted by `release()`. Acceptable — app is terminating; we do not add an await to keep the change surface small. Document in the service comment.
- AVSession remote commands: `session.on('play' | 'pause')` handlers call the same `resume()` / `pause()` — inherit fade behavior automatically.
- Exit dialog (`ExitAppModel.pause()`): same path; fade-out plays briefly before app moves on — benign.
- Audio focus loss mid-fade: `audioInterrupt:INTERRUPT_FORCE` aborts the fade; next resume re-ramps 0 → 1 if still enabled.

## 7. Non-goals / explicit out-of-scope

- No exponential ramp curve — linear over 500 ms is sufficient and matches the spec’s "平滑".
- No user-configurable fade duration.
- No per-song ducking.
- No change to crossfade between songs (spec explicitly excludes fade on switch).

## 8. Manual verification plan (post-implementation)

1. Settings → Audio Output: switcher visible, default ON; toggle persists across app restart.
2. Scenario 1/2: Play, wait, pause → audible 500 ms ramp; resume → audible ramp up.
3. Scenario 3/4: Toggle OFF, pause/resume → instantaneous, no perceptible ramp.
4. Scenario 5: With flag ON, tap next/prev during playback → no fade-out on outgoing song; new song fades in.
5. Scenario 6: Flip switch in the middle of a playback session → next tap honors new setting without restart.
6. Scenario 7: Tap pause, within 300 ms tap play → observe single combined ramp (down then up), not clipped/layered.
7. Stress: rapid pause/play taps → no stuck-mute state; final state matches last tap.
8. Mini-player and notification/media-session controls exercise the same behavior (they route to the same service).

## 9. File touch list

- `entry/src/main/ets/pages/AudioOutputPage.ets` — uncomment fade switch row.
- `entry/src/main/ets/viewmodel/AudioOutputViewModel.ets` — sync `fadeInOutVM.isOn` on set; seed from AppStorage in `initFadeInOutVM`.
- `entry/src/main/ets/model/AudioPlayerService.ets` — fade envelope, mutex, `doPlay`/`prepared` hook, abort on error/release.

No new files. No resource changes (strings already present). No EntryAbility change (persistence already wired).
