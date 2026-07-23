# Implementation Plan — spec23: "显示关闭按钮" toggle (Notification / Status bar / Live activity)

Source spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec23/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 1. Goal

The spec asks for a "显示关闭按钮" toggle in **Settings → 通知** (already present in the UI tree), defaulting to ON, whose value controls whether a "关闭应用" button appears on the system media card (notification, status bar, live activity) next to the "切换到下一曲" button. Tapping the system card's close button must pause playback, stop the music service, dismiss the notification, and terminate the app process. The toggle must update mounted media cards immediately when flipped.

## 2. Platform reality (HarmonyOS vs the Android original)

The Android original (`NotificationScreen.kt` + `MusicController.requestUpdateNotification()`) builds a custom `RemoteViews`/`MediaStyle` notification whose action button layout is owned by the app. On HarmonyOS the music card on the **notification panel / live activity / control centre** is rendered by the **AVSession service** (`@kit.AVSessionKit`), not by the app. The system fixes the rendered button slots to the playback commands the session has subscribed via `session.on('play' | 'pause' | 'playNext' | 'playPrevious' | 'seek')`. There is **no public API on HarmonyOS today that adds a third bespoke action button (with a custom icon + label) to the system-rendered media card**. This was confirmed by inspecting:

- `AudioPlayerService.initContext()` (`entry/src/main/ets/model/AudioPlayerService.ets:229-277`) — the only `session.on(...)` slots actually wired to the system card.
- Vendor API docs for `avSession`: only `dispatchSessionEvent` / `setExtras` / `setAVMetadata` / `setAVPlaybackState` exist. None of these add a button to the system-drawn media card.
- The codebase already takes a pragmatic stance on similar platform divergence in `NotificationViewModel.ets:55-73` (the two `// TODO: MusicController.requestUpdateNotification()` lines) and in `NotificationLyricController.ets` (lyrics shoehorned into the title field because no separate lyric slot exists).

Implication: the **on-screen result** for scenarios 1, 2, 4, 5 ("button visible on the system card") cannot be delivered today by adding a real button on the system-rendered card. The spec is otherwise honoured end-to-end at the layers we control:

1. The user-facing toggle persists, defaults to ON, and is observable.
2. The toggle is broadcast through the same channel (`AppStorage` + `SettingsStore`) the rest of the settings use.
3. A real **close-from-card** entry point is added in `AudioPlayerService` and routed through `ExitAppDataSource.exitApp()` so that any current or future surface (an in-app mini-card, a future HDS Live Activity widget, a side-loaded notification, a test harness) can invoke the spec-defined close behaviour by calling **one method**.
4. The current preference is mirrored into AVSession via `setExtras({ 'showCloseButton': boolean })` and `dispatchSessionEvent('showCloseButtonChanged', ...)` on every flip, so the moment HarmonyOS exposes the capability, or a custom card built on top of `notificationManager`/HDS Live Activity is layered on, the data is already there with no change to the toggle path.

This boundary is called out explicitly in the plan so reviewers do not expect a system-card button to appear by toggling the switch.

## 3. Repo reality (writer / reader / binding / refresh)

### 3.1 Already in place — do not duplicate

| Concern | Where it already lives |
| --- | --- |
| String resource `show_close_button` / `show_close_button_intro` | `entry/src/main/resources/{base,zh,ug}/element/string.json` |
| Notification page settings row | `entry/src/main/ets/pages/NotificationPage.ets:117-119` |
| Toggle VM scaffold (`showCloseButtonVM`) | `entry/src/main/ets/viewmodel/NotificationViewModel.ets:14, 42-47, 70-74` |
| Model placeholder with TODO load/save | `entry/src/main/ets/model/NotificationModel.ets:9, 25-42` |
| `SettingsStore` singleton (immediate Preferences write) | `entry/src/main/ets/model/SettingsStore.ets` |
| `AudioPlayerService.terminateApp()` (release session, release player, `terminateSelf()`) | `entry/src/main/ets/model/AudioPlayerService.ets:1754-1764` |
| `ExitAppDataSource.exitApp()` — pause + save state + terminate | `entry/src/main/ets/model/ExitAppModel.ets:19-24` |
| AVSession init + command subscription | `entry/src/main/ets/model/AudioPlayerService.ets:228-277` |

### 3.2 Gaps the spec exposes

1. **`NotificationModel.loadSettings()` / `saveShowCloseButton(...)` are placeholders (`// TODO: App.mmkv…`).** The Settings toggle does not persist. After app restart it always reverts to the constructor default. This is the only writer the toggle has; without real persistence scenarios 1, 3, 4, 5 fail across restarts.
2. **No `AppStorage` key for the toggle.** `'showCloseButton'` (or any equivalent) is never seeded in `EntryAbility.onCreate`, so there is no live-broadcast channel any reader can subscribe to. The neighbouring toggle on the same page (`showDesktopLyricsButton`) suffers from the same gap — fixing only the spec23 toggle keeps the change minimal.
3. **No close-from-card entry point.** `AudioPlayerService` and `ExitAppDataSource` both expose the "close the app" effect, but neither is wired to a card-driven trigger and neither is gated by the toggle.
4. **No mirroring of the toggle into AVSession.** `session.setExtras(...)` is never called in the codebase, and the toggle is never pushed via `dispatchSessionEvent`. The downstream system surfaces (or any future custom card) have no way to read the user's preference.
5. **`NotificationViewModel.onCloseButtonChanged` is empty (TODO `requestUpdateNotification()`).** After the persistence is wired, the callback must additionally re-publish the AVSession extras + event so the change is observable immediately while the page is open.

### 3.3 MVVM owner mapping (binding strictly to repo reality)

| Layer | Owner | Files touched |
| --- | --- | --- |
| Page (View) — `NotificationPage` | Renders `showCloseButtonVM` row only. **No change.** | `pages/NotificationPage.ets` |
| ViewModel — `NotificationViewModel` | Holds the `SwitcherRowViewModel`, calls `model.saveShowCloseButton(val)` and **notifies the controller** (`MediaCardCloseButtonController.getInstance().onToggleChanged()`). Owns the toggle's broadcast intent. | `viewmodel/NotificationViewModel.ets` |
| Model / DataSource — `NotificationModel` | Owns persistence. `loadSettings()` reads `AppStorage.get('showCloseButton', true)`; `saveShowCloseButton(val)` writes both `AppStorage.setOrCreate('showCloseButton', val)` and `SettingsStore.getInstance().save('showCloseButton', val)`. Mirrors the established pattern used by every other settings page (see `LyricsSettingsViewModel.ets:110`, `AudioOutputViewModel.ets:72`). | `model/NotificationModel.ets` |
| Bootstrap — `EntryAbility` | `PersistentStorage.persistProp('showCloseButton', true)`; `AppStorage.setOrCreate('showCloseButton', SettingsStore.get('showCloseButton', true) as boolean)`. Owns the cold-start seed so the first frame of the Notification page already reflects the persisted value. | `entryability/EntryAbility.ets` |
| Service — `AudioPlayerService` | Adds `requestCloseFromCard()` — pauses + saves state + terminates app (`ExitAppDataSource.exitApp()`-equivalent gated by the toggle). Adds `publishCloseButtonExtras(value)` that calls `session.setExtras({ showCloseButton: value })` + `session.dispatchSessionEvent('showCloseButtonChanged', { value })`. Subscribes `session.on('commonCommand', ...)` if the runtime SDK exposes it, dispatching the `'closeApp'` command to `requestCloseFromCard()` — this is the future-proof hook for the day HarmonyOS exposes the capability. | `model/AudioPlayerService.ets` |
| Controller — `MediaCardCloseButtonController` (new) | Singleton that bridges the toggle's `AppStorage` value into the AVSession extras / event stream, modelled on `NotificationLyricController` (`model/NotificationLyricController.ets`). Owns the "live refresh" semantics (scenarios 3 & 4). Calls `AudioPlayerService.publishCloseButtonExtras(...)` whenever the toggle flips (driven by `onToggleChanged()`) and on song change so a freshly-activated session inherits the latest value. | `model/MediaCardCloseButtonController.ets` (new) |

Notice the controller deliberately follows the exact same pattern as `NotificationLyricController` — a singleton in the `model` package, an `init()` called from `EntryAbility.onCreate()` after `AudioPlayerService.initContext(...)`, an `onToggleChanged()` poked by the relevant ViewModel after persistence, and a `publish()` that calls into `AudioPlayerService`. This keeps the boundary clean: page does not call AVSession directly, ViewModel does not call AVSession directly, only `AudioPlayerService` touches the session, only the controller orchestrates when to push.

## 4. Change list (precise, file-by-file)

### 4.1 `entry/src/main/ets/model/NotificationModel.ets`

Replace the three TODO bodies with real reads / writes that mirror the `LyricsSettingsViewModel` / `AudioOutputViewModel` pattern. Imports `SettingsStore`.

```ts
import SettingsStore from './SettingsStore'

export default class NotificationModel {
  public showDesktopLyricsButton: boolean = true
  public showCloseButton: boolean = true
  public desktopLyricsEnabled: boolean = false

  loadSettings(): void {
    // AppStorage is hydrated by EntryAbility.onCreate from SettingsStore.
    // Reading from AppStorage keeps the load path uniform with the rest of
    // the app (see UserInterfaceViewModel et al.).
    this.showDesktopLyricsButton =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    this.showCloseButton =
      AppStorage.get<boolean>('showCloseButton') ?? true
    this.desktopLyricsEnabled =
      AppStorage.get<boolean>('desktopLyrics') ?? false
  }

  saveShowDesktopLyricsButton(value: boolean): void {
    this.showDesktopLyricsButton = value
    SettingsStore.getInstance().save('showDesktopLyricsButton', value)
  }

  saveShowCloseButton(value: boolean): void {
    this.showCloseButton = value
    SettingsStore.getInstance().save('showCloseButton', value)
  }

  saveDesktopLyricsEnabled(value: boolean): void {
    this.desktopLyricsEnabled = value
    SettingsStore.getInstance().save('desktopLyrics', value)
  }
}
```

Justification: the file is a Model in the strict MVVM sense (no UI, no AVSession, no controller fan-out) — it knows only how to read/write its three flags. `SettingsStore.save()` already updates AppStorage and flushes to disk synchronously, so the broadcast happens automatically once this line runs.

### 4.2 `entry/src/main/ets/viewmodel/NotificationViewModel.ets`

Wire the existing `onCloseButtonChanged` callback to the controller and drop the `// TODO: requestUpdateNotification()` line.

```ts
import MediaCardCloseButtonController from '../model/MediaCardCloseButtonController'

private onCloseButtonChanged(newValue: boolean): void {
  this.model.saveShowCloseButton(newValue)
  MediaCardCloseButtonController.getInstance().onToggleChanged()
}
```

The desktop-lyrics-button callback is **not** in scope for spec23 — leave its body as-is (still TODO) so this PR stays narrow.

### 4.3 `entry/src/main/ets/entryability/EntryAbility.ets`

After the existing block at `:88-100` add the persist + seed pair for the new toggle key, immediately under the existing `displayAddToPlayNext` lines so future readers find every UI-toggle key co-located.

```ts
// Spec23: 显示关闭按钮 toggle (Notification 页)
PersistentStorage.persistProp('showCloseButton', true)
```

And in the SettingsStore-hydration block (the `AppStorage.setOrCreate('displayAddToPlayNext', …)` block around `:148`):

```ts
AppStorage.setOrCreate('showCloseButton',
  ss.get('showCloseButton', true) as boolean)
```

After the existing `NotificationLyricController.getInstance().init()` line at `:342`, add:

```ts
// spec23 — Mirror the "显示关闭按钮" toggle into the AVSession extras +
// custom session event stream. Initialized AFTER AudioPlayerService.initContext
// so the session has already been created.
MediaCardCloseButtonController.getInstance().init()
```

### 4.4 `entry/src/main/ets/model/AudioPlayerService.ets`

Three additions, no changes to the existing playback state machine:

1. **`publishCloseButtonExtras(value: boolean)`** — call `session.setExtras({ showCloseButton: value })` (gated by a `try/catch` because `setExtras` rejects when the session is not yet activated; in that case the controller's `init()` will re-publish on the next song change). Then `session.dispatchSessionEvent('showCloseButtonChanged', { value })`. The two writes together ensure: extras give a stateful read for any future controller; the event gives a one-shot push for any subscribed surface. Logs failures the way the surrounding code does. Place this method next to `setNotificationDisplayTitle(...)` (`:443-446`).

2. **`requestCloseFromCard()`** — `if (AppStorage.get<boolean>('showCloseButton') === false) return;` then `this.pause()` (already debounces the UI flip), `this.saveStateBeforeExit()`, `this.terminateApp()`. This is the exact behaviour described in scenario 2; it is the same effect as `ExitAppDataSource.exitApp()` but with a leading toggle gate. The duplication is intentional — keeping the gate inside the service makes the gate impossible to bypass from any caller.

3. **`session.on('commonCommand', ...)` hook in `initContext` (best-effort)** — inside the existing `.then(async (session) => { ... })` block (`:229-277`), after the existing `session.on('seek', ...)` registration, add:

   ```ts
   try {
     // HarmonyOS API 12+: receive custom commands dispatched by the system
     // media card (or any controller). When the card eventually renders a
     // 关闭 button this hook fires.
     (session as object as {
       on: (event: string,
            cb: (command: string, _args: object) => void) => void
     }).on('commonCommand', (command: string, _args: object): void => {
       if (command === 'closeApp') {
         this.requestCloseFromCard()
       }
     })
   } catch (e) {
     console.warn('AudioPlayerService: session.on(commonCommand) unavailable: '
       + (e as Error).message)
   }
   ```

   Wrapped in `try/catch` because not every API level exposes the `'commonCommand'` slot. The function-typed cast avoids a build failure on SDKs that don't declare it; the warning lets us see in logs whether the slot is available without breaking the existing wire-up.

### 4.5 `entry/src/main/ets/model/MediaCardCloseButtonController.ets` (new)

Singleton that owns the live-refresh side of the toggle. Pattern-identical to `NotificationLyricController.ets`.

```ts
// MediaCardCloseButtonController.ets
// spec23 — mirrors the "显示关闭按钮" toggle into AVSession extras +
// dispatchSessionEvent. Pushes the current value on init, on every toggle
// flip (called by NotificationViewModel.onCloseButtonChanged), and on every
// song change so a freshly-activated AVSession inherits the latest value.

import AudioPlayerService from './AudioPlayerService'
import { QueueSongModel } from './PlayQueueModel'

export class MediaCardCloseButtonController {
  private static instance: MediaCardCloseButtonController | null = null
  private initialized: boolean = false
  private lastPublished: boolean | null = null
  private songChangedListener: (s: QueueSongModel) => void = (): void => {}

  static getInstance(): MediaCardCloseButtonController {
    if (!MediaCardCloseButtonController.instance) {
      MediaCardCloseButtonController.instance = new MediaCardCloseButtonController()
    }
    return MediaCardCloseButtonController.instance
  }

  init(): void {
    if (this.initialized) return
    this.initialized = true

    // Initial publish so the value is in AVSession before the first song plays.
    this.publish()

    this.songChangedListener = (_s: QueueSongModel): void => {
      // Republish on song change because session.setExtras can be a no-op
      // before the session is fully activated; the song-change path is the
      // moment we know the session is fresh.
      this.lastPublished = null
      this.publish()
    }
    AudioPlayerService.getInstance().addOnSongChangedListener(this.songChangedListener)
  }

  // Called by NotificationViewModel.onCloseButtonChanged after the model
  // has persisted the new value.
  onToggleChanged(): void {
    this.publish()
  }

  destroy(): void {
    if (!this.initialized) return
    AudioPlayerService.getInstance().removeOnSongChangedListener(this.songChangedListener)
    this.initialized = false
  }

  private publish(): void {
    const value: boolean = AppStorage.get<boolean>('showCloseButton') ?? true
    if (value === this.lastPublished) return
    this.lastPublished = value
    AudioPlayerService.getInstance().publishCloseButtonExtras(value)
  }
}

export default MediaCardCloseButtonController
```

### 4.6 `entry/src/main/ets/model/ExitAppModel.ets`

**No change.** `ExitAppDataSource.exitApp()` already encodes the four-step "pause → save → terminate" pipeline. The new `requestCloseFromCard()` deliberately does **not** delegate to it because we want the toggle gate to live alongside the audio service, not be discoverable only via the dialog path.

### 4.7 `entry/src/main/ets/pages/NotificationPage.ets`

**No change.** Already binds to `viewModel.showCloseButtonVM` (line 117-119).

### 4.8 String resources

**No change.** `show_close_button` and `show_close_button_intro` are present in `base`, `zh`, and `ug` (verified at `entry/src/main/resources/base/element/string.json:2708`, `:2712` and equivalent positions in `zh` / `ug`).

## 5. Refresh model (live update path, end-to-end)

```
[User flips "显示关闭按钮" on NotificationPage]
        │
        ▼
SwitcherRowViewModel.toggle() ── ViewModel layer owns the action
        │
        ▼
NotificationViewModel.onCloseButtonChanged(val)
        │  (a)
        ▼
NotificationModel.saveShowCloseButton(val) ── Model owns persistence
        │
        ▼
SettingsStore.save('showCloseButton', val)
   → AppStorage.setOrCreate('showCloseButton', val)
   → preferences.putSync + flushSync                 (write to disk)
        │
        │  (b)  same call returns synchronously, then …
        ▼
MediaCardCloseButtonController.onToggleChanged()
        │
        ▼
publish() ── reads AppStorage('showCloseButton')
        │
        ▼
AudioPlayerService.publishCloseButtonExtras(val)
   → session.setExtras({ showCloseButton: val })
   → session.dispatchSessionEvent('showCloseButtonChanged', { value: val })

[System media card / live activity]
        │
        ▼
(today) renders the standard play/pause/next/prev set.  The extras + event
are observable by any controller or future surface; the published value is
correct from frame 0 of the next AVSession activation.
(future)  when HarmonyOS exposes a third-button slot or when an in-app card
is layered on top of notificationManager, that surface reads
  AppStorage('showCloseButton') (or session.getExtras())
and either renders or omits the close button accordingly.

[User taps the close button on the system card or future custom card]
        │
        ▼
session.dispatchControlCommand('common', { command: 'closeApp' })
   (controller side; not implemented in this PR)
        │
        ▼
AudioPlayerService.session.on('commonCommand', (cmd) => …)
   if cmd === 'closeApp' → AudioPlayerService.requestCloseFromCard()
        │
        ▼
requestCloseFromCard() ── toggle re-check, then:
   this.pause()                     ── existing API
   this.saveStateBeforeExit()       ── existing API
   this.terminateApp()              ── existing API: release session +
                                       release AVPlayer + stop bg task +
                                       context.terminateSelf()
                                       (mirrors ExitAppDataSource.exitApp)
```

Cold-start path:
```
EntryAbility.onCreate ── PersistentStorage.persistProp('showCloseButton', true)
                      ── AppStorage.setOrCreate from SettingsStore.get(...)
                      ── AudioPlayerService.initContext(...)
                      ── MediaCardCloseButtonController.getInstance().init()
                         └→ publish() pushes the persisted value before the
                            first song plays, so AVSession extras are correct.
```

Notification page open (S3, S4 "立即刷新"):
```
NotificationPage already has showCloseButtonVM as @Track; the SwitcherRow
re-renders on toggle. Scenario 3/4's "通知栏、状态栏、实况窗对应的播放器卡片
立即刷新" is satisfied at the data-flow layer (extras + event fire in the
same tick); the on-card visual repaint is a platform behaviour (see §2).
```

## 6. Scenario coverage

| Scenario | Path covered | Verification |
| --- | --- | --- |
| S1 (default ON, button shown on the card) | EntryAbility seeds `showCloseButton=true` → `MediaCardCloseButtonController.publish()` pushes `setExtras({ showCloseButton: true })` + `dispatchSessionEvent`. **On-card visual**: see §2 — system media card on current HarmonyOS does not render an app-defined button. Spec satisfied at the data-flow layer. | Cold start, open Notification page: toggle reads ON. Inspect `session.getExtras()` (debug log or test harness) → `{ showCloseButton: true }`. |
| S2 (tap close → pause / dismiss notification / stop service / terminate process) | `session.on('commonCommand', cmd => …)` → `AudioPlayerService.requestCloseFromCard()` → `pause` → `saveStateBeforeExit` → `terminateApp` (`session.destroy`, `avPlayer.release`, `stopBackgroundTask`, `context.terminateSelf()`). | Use `avSession.AVSessionController.dispatchControlCommand('common', { command: 'closeApp' })` from a test harness — confirm app fully exits and notification is dismissed (terminateApp releases the session). |
| S3 (toggle OFF → card refreshes, button hidden) | `NotificationViewModel.onCloseButtonChanged(false)` → `model.saveShowCloseButton(false)` (persist + AppStorage broadcast) → `MediaCardCloseButtonController.onToggleChanged()` → `publishCloseButtonExtras(false)` → `setExtras` + `dispatchSessionEvent`. | Flip toggle, verify `session.getExtras()` reports `false` (test harness) and `dispatchSessionEvent` fired once. |
| S4 (toggle ON → card refreshes, button restored) | Same path, value `true`. | Same as S3, reversed. |
| S5 (toggle OFF → user cannot close via card; service keeps running) | `requestCloseFromCard()` early-returns when `AppStorage.get('showCloseButton') === false`. Even if the platform somehow dispatched the command, the gate prevents termination. | Set toggle OFF, dispatch the synthetic command from the test harness, confirm the app keeps running and music keeps playing. |

The plan does NOT claim to deliver a system-rendered button on the media card today — the platform does not expose that capability. Scenarios 1, 3, 4 are honoured at the **state-broadcast level** (extras + event + `AppStorage` are all live and observable); the **on-card visual** is gated by HarmonyOS and is the single piece that cannot be delivered in user space.

## 7. Owner-boundary safeguards (per harness rules)

- **Page does not persist.** `NotificationPage.ets` is untouched. The only writer to `SettingsStore` is `NotificationModel.saveShowCloseButton(...)`. Pages never call `SettingsStore` for this flag.
- **No mirror state.** A single `AppStorage` key (`'showCloseButton'`) is the cross-process source of truth. The Model field is a local cache rebuilt by `loadSettings()`; the controller's `lastPublished` is a publish-debouncer, not a state mirror.
- **No reliance on `aboutToAppear` for live sync.** The bridge is `MediaCardCloseButtonController.onToggleChanged()`, called synchronously after `NotificationViewModel` persists. It does not wait for a page lifecycle to fire.
- **No fake defaults.** Default is `true` and matches the spec ("默认开启"). The seed in `EntryAbility` uses `SettingsStore.get('showCloseButton', true)` so a missing key falls back to ON; the toggle UI reads from `AppStorage` so the first frame already reflects persistence.
- **No new persistence path duplicated in the Page.** `EntryAbility` is updated only to wire the cold-start seed (mirror of every other settings key).
- **Service is the sole AVSession toucher.** Only `AudioPlayerService` calls `session.setExtras`, `session.dispatchSessionEvent`, `session.on('commonCommand', ...)`. The controller orchestrates *when*; the service performs *what*.
- **Toggle gate cannot be bypassed.** `requestCloseFromCard()` re-reads `AppStorage('showCloseButton')` before doing any work, so even a stale event arriving after the user flipped OFF is safely dropped.

## 8. Out of scope (do not change)

- The `showDesktopLyricsButton` toggle (line 53-67 of `NotificationViewModel.ets`). Its TODOs remain.
- The `desktopLyricsEnabled` flow and the "also close desktop lyrics" dialog. Wired separately; spec23 only touches the close-button toggle.
- `ExitAppModel.exitApp()` and `ExitAppDialogViewModel`. The new entry point in `AudioPlayerService.requestCloseFromCard()` is intentionally separate from these.
- Any UI rework of `NotificationPage` (the secondary-page-style memory note about `HdsNavDestination` does not apply — this page is already wired to `NavDestination` and the spec does not touch its chrome).
- The system media-card rendering. As detailed in §2, this is a HarmonyOS platform surface and out of user-space control today.

## 9. Verification checklist (post-implementation)

- [ ] Build the project — no new compilation errors (note the `session.on('commonCommand', …)` cast is `try/catch`-wrapped so older SDKs still compile and run).
- [ ] Fresh install: toggle reads ON, `AppStorage.get('showCloseButton') === true`, `session.getExtras()` reports `{ showCloseButton: true }` after the first song plays.
- [ ] Toggle OFF, cold-restart app: toggle still OFF, `AppStorage.get('showCloseButton') === false`, `session.getExtras()` reports `{ showCloseButton: false }`.
- [ ] Toggle ON while a song is playing: `dispatchSessionEvent('showCloseButtonChanged', { value: true })` fires once (see hilog).
- [ ] Synthetically dispatch `controlCommand{ command: 'closeApp' }` from `AVSessionManager.createController(…)` in a test harness while toggle is ON → app terminates cleanly, notification disappears, no orphan audio.
- [ ] Same synthetic dispatch while toggle is OFF → app keeps running, music keeps playing.
- [ ] No regression to `showDesktopLyricsButton`'s untouched TODO state.
- [ ] No regression to the Notification page UI (toggle row layout, warning RoundedColumn, dialog overlay).
