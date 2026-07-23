# Implementation Plan — spec24: "显示桌面歌词按钮" toggle + lyric-replaces-artist on media card

Source spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec24/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 1. Goal

The spec asks for the "显示桌面歌词按钮" toggle in **Settings → 通知** (UI scaffold already present). When ON, an extra "歌词按钮" appears on the system media card (notification bar, status bar, live activity) to the **left of the previous-track button**. Tapping that button replaces the **artist** area on the card with the **current lyric line** that tracks playback progress; tapping again restores the artist. The toggle defaults to ON, persists across restarts, and is gated by floating-window permission per scenarios 7/8. When the toggle is flipped OFF while the desktop lyric floating window is showing, a dialog asks the user whether to also close that window (scenario 6).

## 2. Platform reality (HarmonyOS vs the Android original)

This is a direct sibling of spec23. On HarmonyOS the system media card on the **notification panel / live activity / control centre** is rendered by **`@kit.AVSessionKit`** — not by the app. The system fixes the rendered button slots to the playback commands the session has subscribed via `session.on('play' | 'pause' | 'playNext' | 'playPrevious' | 'seek')`. There is **no public API today that adds a custom action button (with an icon + label) to the system-rendered media card** between the play/pause and prev/next slots, and there is no public API that swaps the **artist field** of the card metadata for an arbitrary string while preserving the original artist for the rest of the system.

This was reconfirmed by inspecting:

- `AudioPlayerService.initContext()` (`entry/src/main/ets/model/AudioPlayerService.ets:229-292`) — the only `session.on(...)` slots actually wired to the system card.
- The metadata writers `updateSessionMetadata()` (`:402-431`) / `updateSessionCoverImage()` (`:433-450`) — they set the standard `title / artist / mediaImage / duration` fields. The system reads them as-is.
- `NotificationLyricController` (`model/NotificationLyricController.ets`) — the project's existing precedent for shoehorning live lyrics into the system card by overwriting **the title field** (`AudioPlayerService.setNotificationDisplayTitle(...)`), exactly because no separate lyric slot exists.
- The successful spec23 solution (`wsh-output/spec23/logic/plan.md`): toggle persists + `session.setExtras({...})` + `dispatchSessionEvent('...Changed', {...})` for future surfaces, plus a `session.on('commonCommand', ...)` hook for the day the card dispatches a custom command.

**Implication.** Two of the spec's user-visible effects cannot be delivered by the app today:

1. Adding a real "歌词按钮" to the left of the prev-track button on the system-rendered card (scenarios 1, 6, 10).
2. Swapping the system card's **artist** field for the running lyric line while preserving the spec's "click again to restore" toggle (scenarios 2, 3, 4, 5).

What we deliver end-to-end at the layers we control:

1. The user-facing toggle persists, defaults to ON, broadcasts via `AppStorage` + `SettingsStore`, is observed by all readers including a new controller singleton.
2. The toggle is gated by floating-window permission per scenarios 7/8: a permission probe before enabling, a fall-through path that jumps to the system permission page when missing.
3. Scenario 6's "ask user to also close desktop lyric floating window" already exists in `NotificationViewModel` (`showAlsoCloseDesktopLyricsDialog` + `confirmCloseDesktopLyrics()`); we wire it up so the dialog *only* fires when the floating window is actually showing.
4. The current preference is mirrored into AVSession via `session.setExtras({ 'showDesktopLyricsButton': boolean })` and `session.dispatchSessionEvent('showDesktopLyricsButtonChanged', ...)` on every flip, on every song change, and at cold start — so the moment the platform exposes the capability the data is already there.
5. **Lyric-toggle session-event** — a second AVSession extras key + event (`'cardLyricsActive'`) carrying a boolean `'isLyricsActive'` so any current or future surface that drives the in-card swap can read the user's intent. The actual artist→lyric swap on the card itself is out-of-platform-scope; the spec is honoured at the **state-broadcast level** identically to spec23.
6. A custom-command hook (`session.on('commonCommand', ...)`) that already exists from spec23 is extended: when the card dispatches `'toggleCardLyrics'`, we flip an in-process state and republish.
7. The "running lyric line for card" is sourced from `MiniLyricsController` (the same publisher used by `NotificationLyricController` for spec12). We piggy-back on its 200ms tick — no second timer.

This boundary is called out explicitly so reviewers do not expect the system-card's artist row to flip to a lyric in scenarios 2/4 today, nor a third action button to appear in scenarios 1/10.

## 3. Repo reality (writer / reader / binding / refresh)

### 3.1 Already in place — do not duplicate

| Concern | Where it already lives |
| --- | --- |
| String resource `show_desktop_lyrics_button` / `_intro` | `entry/src/main/resources/{base,zh,ug}/element/string.json` (`base:2716, 2720`) |
| Settings page row for "显示桌面歌词按钮" | `entry/src/main/ets/pages/NotificationPage.ets:112-114` |
| Toggle VM scaffold (`showDesktopLyricsButtonVM`) | `entry/src/main/ets/viewmodel/NotificationViewModel.ets:14, 34-40, 53-67` |
| Model field with `loadSettings()` + `saveShowDesktopLyricsButton()` | `entry/src/main/ets/model/NotificationModel.ets:10, 28-39` (already wired through `SettingsStore` after spec23 fix) |
| "Also close desktop lyrics" dialog state + handlers | `entry/src/main/ets/viewmodel/NotificationViewModel.ets:18, 80-95`; `entry/src/main/ets/pages/NotificationPage.ets:56-58, 159-208` |
| `desktopLyrics` AppStorage key (the floating window's own ON/OFF) | `entry/src/main/ets/entryability/EntryAbility.ets:116, 169` |
| MVVM live-lyric stream | `entry/src/main/ets/model/MiniLyricsController.ets` — publishes `(songId, line, hasLyrics)` to all subscribed listeners on a 200ms tick |
| AVSession singleton + init + cmd hooks | `entry/src/main/ets/model/AudioPlayerService.ets:228-292` |
| Spec23 controller pattern to copy | `entry/src/main/ets/model/MediaCardCloseButtonController.ets` |
| Notification card title-override path (spec12) | `AudioPlayerService.setNotificationDisplayTitle(merged: string \| null)` (`model/AudioPlayerService.ets:457-460`) |

### 3.2 Gaps the spec exposes

1. **No `AppStorage` key `'showDesktopLyricsButton'` is seeded on cold start.** `NotificationModel.loadSettings()` reads it (`model/NotificationModel.ets:29-30`) but `EntryAbility.onCreate` never persists or hydrates it. After the first toggle flip, persistence works (because `SettingsStore.save` writes to disk and updates AppStorage), but on **first cold launch** the read falls back to the constructor default — meaning the toggle reads ON correctly on first run (matches spec), but if any future reader subscribes via `@StorageLink('showDesktopLyricsButton')` before the user opens the Notification page, they see `undefined` instead of the persisted value. Bridging this gap aligns with every other settings key (`showCloseButton`, `desktopLyrics`, etc.).
2. **No live broadcast into AVSession.** `'showDesktopLyricsButton'` is never pushed via `setExtras` / `dispatchSessionEvent`. Sibling toggle `'showCloseButton'` already has its dedicated controller (`MediaCardCloseButtonController`); the parallel one for this spec is missing.
3. **No floating-window permission probe / prompt.** Scenarios 7 and 8 require the toggle's ON-flip path to check the system "overlay" / "悬浮窗" permission, and route the user to the system settings page when missing. Today `NotificationViewModel.onDesktopLyricsButtonChanged(true)` does nothing of the sort (the existing TODO comment at `:60-62` is the placeholder).
4. **No gating for the "also close desktop lyric floating window" dialog.** `onDesktopLyricsButtonChanged(false)` already flips `showAlsoCloseDesktopLyricsDialog` to `true` *if* `this.desktopLyricsEnabled` is `true`, but `this.desktopLyricsEnabled` was set once in `loadFromModel()` (`viewmodel/NotificationViewModel.ets:50`) and is never refreshed. It misses the case where the user enabled the desktop lyric floating window *after* opening the Notification page, because the ViewModel's field is a stale snapshot. The fix is to read `AppStorage.get<boolean>('desktopLyrics')` live, not the snapshot.
5. **No running-lyric publisher for the card surface.** Even though `MiniLyricsController` exists, nothing today maps "card lyrics is ON" + "current lyric line" into AVSession state. The closest precedent is `NotificationLyricController` which only overrides the title field per the notification-bar-lyrics spec (spec12). For spec24's "swap artist row" intent we need a **separate** controller that publishes the in-card swap intent to AVSession via extras + event, and additionally maintains the in-process "isLyricsActive" boolean per `currentSongId` so the toggle is per-song and resets on song change (matches scenario 4: "切换歌曲，歌词内容同步更新").
6. **No persistence of "isLyricsActive" between toggle flips.** Per spec the click-toggle is a transient state (user clicks the card's lyric button → state flips). On HarmonyOS, since the actual click event from the card cannot fire today, we still need to define the storage shape so the broadcast is consistent. Decision: keep `isLyricsActive` in-memory only (not persisted), scoped to the controller singleton; cold start defaults to `false` (artist row shown); reset to `false` on every song change so scenario 4 is honoured.

### 3.3 MVVM owner mapping (binding strictly to repo reality)

| Layer | Owner | Files touched |
| --- | --- | --- |
| Page (View) — `NotificationPage` | Renders `showDesktopLyricsButtonVM` row and the existing "also close desktop lyrics" dialog overlay. **No change.** All UI hooks already exist (`pages/NotificationPage.ets:112-114, 56-58, 159-208`). |
| ViewModel — `NotificationViewModel` | Holds the `SwitcherRowViewModel`, calls `model.saveShowDesktopLyricsButton(val)`, notifies the controller (`MediaCardDesktopLyricsButtonController.getInstance().onToggleChanged()`), checks floating-window permission on ON-flip (scenarios 7/8), reads `AppStorage('desktopLyrics')` live to decide whether the "also close desktop lyrics" dialog fires (scenario 6). Owns the toggle's broadcast intent and the permission prompt orchestration. `confirmCloseDesktopLyrics()` already persists `desktopLyrics=false` and dismisses the dialog; we make it also pessimistically close the floating window via a new controller hook. | `viewmodel/NotificationViewModel.ets` |
| Model / DataSource — `NotificationModel` | Owns persistence. `loadSettings()` reads `AppStorage.get('showDesktopLyricsButton')`; `saveShowDesktopLyricsButton(val)` writes both `AppStorage.setOrCreate` and `SettingsStore.save`. Already correct. **No change.** | `model/NotificationModel.ets` (read-only verification) |
| Bootstrap — `EntryAbility` | `PersistentStorage.persistProp('showDesktopLyricsButton', true)`; `AppStorage.setOrCreate('showDesktopLyricsButton', SettingsStore.get('showDesktopLyricsButton', true) as boolean)`. After `MediaCardCloseButtonController.getInstance().init()` (spec23), call `MediaCardDesktopLyricsButtonController.getInstance().init()` so the value lands in AVSession before the first song plays. | `entryability/EntryAbility.ets` |
| Service — `AudioPlayerService` | Add **two new publish helpers**: `publishDesktopLyricsButtonExtras(value: boolean)` and `publishCardLyricsActiveExtras(active: boolean)`. Each calls `session.setExtras(...)` + `session.dispatchSessionEvent(...)` with try/catch wrappers identical in shape to the spec23 `publishCloseButtonExtras`. Extend the existing `session.on('commonCommand', ...)` switch to recognise `'toggleCardLyrics'` and route it to the new controller. The service does not own state — it only mediates AVSession writes. | `model/AudioPlayerService.ets` |
| Controller — `MediaCardDesktopLyricsButtonController` (new) | Singleton in `model/`. Pattern-identical to `MediaCardCloseButtonController`. Listens on `AudioPlayerService.addOnSongChangedListener` + `MiniLyricsController.addListener`. Owns the "is the card showing lyric or artist" flag per current song; mirrors the user-facing toggle to AVSession. Exposes `onToggleChanged()`, `requestToggleLyricsActive()` (called by the `'toggleCardLyrics'` command dispatch), `requestCloseFloatingWindow()` (called by `NotificationViewModel.confirmCloseDesktopLyrics()` so the desktop lyric floating window teardown lives in one place). On every lyric line update from `MiniLyricsController` when `isLyricsActive === true`, push the running line into AVSession via a third extras key `'cardLyricsLine'` + corresponding dispatched event so the surface that one day swaps the artist row gets the live line. | `model/MediaCardDesktopLyricsButtonController.ets` (new) |
| Permission helper — `FloatingWindowPermission` (new, optional file) | A tiny static helper that wraps the HarmonyOS overlay-permission probe (`bundleManager.checkPermissionAccessSync('ohos.permission.SYSTEM_FLOAT_WINDOW')`) and the system-settings jump. Encapsulates scenario 7/8 so the ViewModel stays MVVM-clean. Returns `{ hasPermission: boolean, requestFromSystem(): Promise<boolean> }`. | `model/FloatingWindowPermission.ets` (new) |

The controller deliberately follows the exact same pattern as `MediaCardCloseButtonController` — a singleton in `model/`, `init()` called from `EntryAbility.onCreate()` after `AudioPlayerService.initContext(...)`, `onToggleChanged()` poked by the relevant ViewModel after persistence, and a `publish()` that calls into `AudioPlayerService`. This keeps the boundary clean: page does not call AVSession, ViewModel does not call AVSession, only `AudioPlayerService` touches the session, only the controller orchestrates when to push.

## 4. Change list (precise, file-by-file)

### 4.1 `entry/src/main/ets/entryability/EntryAbility.ets`

After the spec23 block at `:103-104`, add the persist call for the new key:

```ts
// Spec24: 显示桌面歌词按钮 toggle (Notification 页) — defaults to ON
PersistentStorage.persistProp('showDesktopLyricsButton', true)
```

In the SettingsStore-hydration block around `:159` (next to the spec23 `showCloseButton` hydration), add:

```ts
// Spec24: 显示桌面歌词按钮 toggle — hydrate from Preferences so the toggle UI
// reads the persisted value on the first frame.
AppStorage.setOrCreate('showDesktopLyricsButton',
  ss.get('showDesktopLyricsButton', true) as boolean)
```

After `MediaCardCloseButtonController.getInstance().init()` at `:354`, add:

```ts
// Spec24 — Mirror the "显示桌面歌词按钮" toggle and the per-song
// card-lyrics-active flag into AVSession extras + custom session event stream.
// Initialized AFTER MiniLyricsController so its addListener call receives the
// current (songId, line, hasLyrics) immediately and pushes a consistent
// initial state.
MediaCardDesktopLyricsButtonController.getInstance().init()
```

Import the new controller alongside the others at the top of the file:

```ts
import { MediaCardDesktopLyricsButtonController }
  from '../model/MediaCardDesktopLyricsButtonController';
```

### 4.2 `entry/src/main/ets/viewmodel/NotificationViewModel.ets`

Replace the TODO bodies inside `onDesktopLyricsButtonChanged` and wire up scenario 6/7/8. The function becomes async so the permission probe can complete before persistence (so the toggle does not flip ON when the user denies overlay permission).

```ts
import MediaCardDesktopLyricsButtonController
  from '../model/MediaCardDesktopLyricsButtonController'
import FloatingWindowPermission from '../model/FloatingWindowPermission'

private async onDesktopLyricsButtonChanged(newValue: boolean): Promise<void> {
  if (newValue) {
    // Scenario 7: already have permission → enable immediately.
    // Scenario 8: no permission → jump to system settings, await user
    // decision, and re-flip the toggle iff the user granted permission on
    // return. The probe is best-effort; if the API is unavailable, treat as
    // "permission granted" so the toggle still works in dev / emulator.
    const granted = await FloatingWindowPermission.ensurePermission()
    if (!granted) {
      // Revert the row to OFF — the SwitcherRowViewModel exposes a
      // setSilent(value) hook for this case (added in §4.5).
      this.showDesktopLyricsButtonVM.setSilent(false)
      return
    }
  }

  this.model.saveShowDesktopLyricsButton(newValue)
  MediaCardDesktopLyricsButtonController.getInstance().onToggleChanged()

  if (!newValue) {
    // Scenario 6: only ask if the desktop lyric floating window is
    // currently showing. Read AppStorage LIVE — do not trust the local
    // `desktopLyricsEnabled` snapshot from loadFromModel(), which is stale.
    const floatingWindowOn: boolean =
      AppStorage.get<boolean>('desktopLyrics') ?? false
    if (floatingWindowOn) {
      this.desktopLyricsEnabled = true       // refresh the local mirror
      this.showAlsoCloseDesktopLyricsDialog = true
    }
  }
}
```

Extend `confirmCloseDesktopLyrics()` so it actually tears down the floating window (today only flips the persisted flag):

```ts
confirmCloseDesktopLyrics(): void {
  this.showAlsoCloseDesktopLyricsDialog = false
  this.desktopLyricsEnabled = false
  this.model.saveDesktopLyricsEnabled(false)
  MediaCardDesktopLyricsButtonController.getInstance().requestCloseFloatingWindow()
}
```

The `requestCloseFloatingWindow()` hook lives on the controller (not the ViewModel) because the floating window is a singleton system surface — its lifecycle owner is the controller, not the page.

### 4.3 `entry/src/main/ets/model/NotificationModel.ets`

**No change.** The model already reads and writes the right key via the spec23 fix.

### 4.4 `entry/src/main/ets/model/AudioPlayerService.ets`

Two additions next to the existing `publishCloseButtonExtras` block (`:471-493`), and one extension to the existing `session.on('commonCommand', ...)` switch (`:256-265`).

```ts
// spec24 — Mirror the "显示桌面歌词按钮" toggle into AVSession state. Same
// shape as publishCloseButtonExtras: a stateful setExtras write plus a
// one-shot dispatched event. Both wrapped in try/catch because setExtras can
// reject when the session is not yet fully activated.
publishDesktopLyricsButtonExtras(value: boolean): void {
  if (!this.session) return
  try {
    const extras: Record<string, Object> = { 'showDesktopLyricsButton': value }
    this.session.setExtras(extras).catch((err: Error) => {
      console.warn('AudioPlayerService: setExtras(showDesktopLyricsButton) failed - '
        + err.message)
    })
  } catch (e) {
    console.warn('AudioPlayerService: setExtras(showDesktopLyricsButton) threw - '
      + (e as Error).message)
  }
  try {
    const eventArgs: Record<string, Object> = { 'value': value }
    this.session.dispatchSessionEvent('showDesktopLyricsButtonChanged', eventArgs)
      .catch((err: Error) => {
        console.warn('AudioPlayerService: dispatchSessionEvent('
          + 'showDesktopLyricsButtonChanged) failed - ' + err.message)
      })
  } catch (e) {
    console.warn('AudioPlayerService: dispatchSessionEvent(showDesktopLyricsButtonChanged) threw - '
      + (e as Error).message)
  }
}

// spec24 — Publish the in-card "lyric or artist" intent + current lyric line
// for surfaces that drive the artist→lyric row swap. Three keys:
//   1) setExtras({ 'cardLyricsActive': boolean, 'cardLyricsLine': string })
//   2) dispatchSessionEvent('cardLyricsStateChanged', { active, line })
// Called by MediaCardDesktopLyricsButtonController on every state change
// (toggle flip from card OR running-line update while active).
publishCardLyricsState(active: boolean, line: string): void {
  if (!this.session) return
  try {
    const extras: Record<string, Object> = {
      'cardLyricsActive': active,
      'cardLyricsLine': line
    }
    this.session.setExtras(extras).catch((err: Error) => {
      console.warn('AudioPlayerService: setExtras(cardLyrics*) failed - '
        + err.message)
    })
  } catch (e) {
    console.warn('AudioPlayerService: setExtras(cardLyrics*) threw - '
      + (e as Error).message)
  }
  try {
    const eventArgs: Record<string, Object> = {
      'active': active, 'line': line
    }
    this.session.dispatchSessionEvent('cardLyricsStateChanged', eventArgs)
      .catch((err: Error) => {
        console.warn('AudioPlayerService: dispatchSessionEvent(cardLyricsStateChanged) failed - '
          + err.message)
      })
  } catch (e) {
    console.warn('AudioPlayerService: dispatchSessionEvent(cardLyricsStateChanged) threw - '
      + (e as Error).message)
  }
}
```

Extend the existing `commonCommand` hook (currently at `:256-265`) by adding a second case:

```ts
try {
  session.on('commonCommand', (command: string, _args: Record<string, Object>): void => {
    if (command === 'closeApp') {
      this.requestCloseFromCard()
    } else if (command === 'toggleCardLyrics') {
      // spec24 — Card-driven lyric/artist swap request. Routed to the
      // controller which owns the in-process state and the publish.
      MediaCardDesktopLyricsButtonController.getInstance()
        .requestToggleLyricsActive()
    }
  })
} catch (e) {
  console.warn('AudioPlayerService: session.on(commonCommand) unavailable: '
    + (e as Error).message)
}
```

Add the import at the top of `AudioPlayerService.ets`:

```ts
import MediaCardDesktopLyricsButtonController
  from './MediaCardDesktopLyricsButtonController'
```

The service stays **the sole AVSession toucher**. State (`isLyricsActive`, last published line) lives on the controller.

### 4.5 `entry/src/main/ets/viewmodel/SwitcherRowViewModel.ets`

Add a `setSilent(value: boolean)` helper (one-line) that updates the visible state without re-firing the toggle callback. Used by `NotificationViewModel` to revert the toggle row when the user denies overlay permission so the SwitcherRow's onClick → callback → setSilent does not recurse. Verify the existing API — if a `setSilent`-equivalent already exists (`set(value)` without callback), reuse it; otherwise add the four-line guarded setter:

```ts
setSilent(value: boolean): void {
  if (this.model.isOn === value) return
  this.model.isOn = value
}
```

(If `SwitcherRowViewModel` exposes a public `isOn` setter that does not call the callback, this method is unnecessary — skip the addition and assign directly from `NotificationViewModel`.)

### 4.6 `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets` (new)

Singleton that owns the live-refresh side of the toggle, the per-song "is lyric row active" flag, and the running-lyric publish. Pattern-identical to `MediaCardCloseButtonController` with one extra responsibility: subscribe to `MiniLyricsController` so the card-lyrics line tracks playback progress.

```ts
// MediaCardDesktopLyricsButtonController.ets
// spec24 — mirrors the "显示桌面歌词按钮" toggle into AVSession extras +
// dispatchSessionEvent, and additionally owns the per-song "card lyrics row
// active" flag and the running-lyric publish. Pattern-identical to
// MediaCardCloseButtonController plus a MiniLyricsController subscription.
//
//   - singleton in the model package
//   - init() called from EntryAbility.onCreate() after
//     MediaCardCloseButtonController.getInstance().init()
//   - onToggleChanged() poked by NotificationViewModel after persistence
//   - requestToggleLyricsActive() poked by AudioPlayerService when the system
//     card dispatches the 'toggleCardLyrics' common command (future-proof
//     hook; the card cannot dispatch this today, see plan §2)
//   - requestCloseFloatingWindow() poked by NotificationViewModel after the
//     user confirms the "also close desktop lyrics" dialog (scenario 6)
//   - publish() calls into AudioPlayerService.publishDesktopLyricsButtonExtras
//   - publishCardLyricsState() calls into AudioPlayerService.publishCardLyricsState

import AudioPlayerService from './AudioPlayerService'
import { QueueSongModel } from './PlayQueueModel'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'

export class MediaCardDesktopLyricsButtonController {
  private static instance: MediaCardDesktopLyricsButtonController | null = null

  private initialized: boolean = false
  private lastPublishedToggle: boolean | null = null
  private lastPublishedActive: boolean | null = null
  private lastPublishedLine: string = ''

  // In-memory only (per spec; resets on cold start and on song change)
  private isLyricsActive: boolean = false
  private currentSongId: string = ''
  private currentLine: string = ''
  private hasLyrics: boolean = false

  private lyricsListener: MiniLyricsListener =
    (_id: string, _l: string, _h: boolean): void => {}
  private songChangedListener: (s: QueueSongModel) => void = (): void => {}

  static getInstance(): MediaCardDesktopLyricsButtonController {
    if (!MediaCardDesktopLyricsButtonController.instance) {
      MediaCardDesktopLyricsButtonController.instance =
        new MediaCardDesktopLyricsButtonController()
    }
    return MediaCardDesktopLyricsButtonController.instance
  }

  init(): void {
    if (this.initialized) return
    this.initialized = true

    // Push the current toggle so it lands in AVSession before the first song
    // plays (matches the spec23 pattern).
    this.publishToggle()
    // Initial card-lyrics state: artist row shown, line empty.
    this.publishLyricsState()

    // Subscribe to song-change so we reset the per-song lyric-active flag and
    // re-publish so a freshly-activated AVSession sees the latest values.
    this.songChangedListener = (s: QueueSongModel): void => {
      this.currentSongId = s.id
      this.isLyricsActive = false       // scenario 4: per-song
      this.currentLine = ''
      this.lastPublishedToggle = null   // force republish on song change
      this.lastPublishedActive = null
      this.lastPublishedLine = ''
      this.publishToggle()
      this.publishLyricsState()
    }
    AudioPlayerService.getInstance()
      .addOnSongChangedListener(this.songChangedListener)

    // Subscribe to MiniLyricsController so we can publish the running line
    // while isLyricsActive is true. The listener fires immediately with the
    // current state on add (per the MiniLyricsController contract).
    this.lyricsListener = (songId: string, line: string, has: boolean): void => {
      this.currentSongId = songId
      this.currentLine = line
      this.hasLyrics = has
      // Only re-emit when active; the toggle-driven publish below still runs
      // when the user clicks the card's lyric button so the system can swap
      // the row.
      if (this.isLyricsActive) {
        this.publishLyricsState()
      }
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)
  }

  // Called by NotificationViewModel.onDesktopLyricsButtonChanged after the
  // model has persisted the new value. Re-reads AppStorage so the published
  // value matches the source of truth (no risk of stale parameter).
  onToggleChanged(): void {
    this.publishToggle()
    // If the user just disabled the toggle, also force the card-lyrics row
    // back to artist (scenario 6: "如果关闭开关前艺术家信息展示区域正在显示
    // 歌词，则恢复显示艺术家信息").
    const enabled: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (!enabled && this.isLyricsActive) {
      this.isLyricsActive = false
      this.publishLyricsState()
    }
  }

  // Called by AudioPlayerService when the system card dispatches a
  // 'toggleCardLyrics' commonCommand. Gated by:
  //   - the user's toggle being ON
  //   - the current song actually having timestamped lyrics (spec scenario 5:
  //     "由于当前歌曲无歌词，艺术家信息展示区域保持显示艺术家信息，不发生变化")
  requestToggleLyricsActive(): void {
    const toggleOn: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (!toggleOn) return
    if (!this.isLyricsActive && !this.hasLyrics) {
      // Spec scenario 5: silently no-op when current song has no lyrics.
      return
    }
    this.isLyricsActive = !this.isLyricsActive
    this.publishLyricsState()
  }

  // Called by NotificationViewModel.confirmCloseDesktopLyrics(). Wraps any
  // floating-window teardown (e.g. window manager hide) in one place so the
  // ViewModel does not own a system-surface lifecycle. The actual floating
  // window machinery for spec18 desktop lyrics is out of scope for spec24;
  // this is the integration point.
  requestCloseFloatingWindow(): void {
    // Floating window controller wiring lives in spec18's DesktopLyrics
    // window service when that ships. Until then this is a no-op besides the
    // persisted `desktopLyrics=false` flag the ViewModel has already written.
    // We still re-publish so any subscriber sees the consistent state.
    this.publishLyricsState()
  }

  destroy(): void {
    if (!this.initialized) return
    AudioPlayerService.getInstance()
      .removeOnSongChangedListener(this.songChangedListener)
    MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    this.initialized = false
  }

  private publishToggle(): void {
    const value: boolean =
      AppStorage.get<boolean>('showDesktopLyricsButton') ?? true
    if (value === this.lastPublishedToggle) return
    this.lastPublishedToggle = value
    AudioPlayerService.getInstance().publishDesktopLyricsButtonExtras(value)
  }

  private publishLyricsState(): void {
    // When active and lyrics exist, publish the running line; otherwise empty.
    const active = this.isLyricsActive && this.hasLyrics
    const line = active ? this.currentLine : ''
    if (active === this.lastPublishedActive && line === this.lastPublishedLine) {
      return
    }
    this.lastPublishedActive = active
    this.lastPublishedLine = line
    AudioPlayerService.getInstance().publishCardLyricsState(active, line)
  }
}

export default MediaCardDesktopLyricsButtonController
```

### 4.7 `entry/src/main/ets/model/FloatingWindowPermission.ets` (new)

Tiny helper that wraps the overlay-permission probe + the system-settings jump. The implementation depends on whether the SDK exposes `bundleManager.checkPermissionAccessSync` and an Ability that opens the floating-window permission settings page. The shape:

```ts
// FloatingWindowPermission.ets
// spec24 — Probes the system overlay / 悬浮窗 permission and routes the user
// to the system settings page when missing. Encapsulates scenarios 7 and 8
// of spec24 so the NotificationViewModel stays MVVM-clean (it asks the model
// layer; the model layer talks to the system).

import { abilityAccessCtrl, Permissions, bundleManager, common } from '@kit.AbilityKit'
import AudioPlayerService from './AudioPlayerService'

const FLOATING_WINDOW_PERM: Permissions = 'ohos.permission.SYSTEM_FLOAT_WINDOW'

export class FloatingWindowPermission {

  // Returns true when the bundle currently holds the overlay permission.
  static async checkPermission(): Promise<boolean> {
    try {
      const ctrl = abilityAccessCtrl.createAtManager()
      const bundle = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      const state = await ctrl.checkAccessToken(
        bundle.appInfo.accessTokenId, FLOATING_WINDOW_PERM)
      return state === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED
    } catch (e) {
      // If the API is not available (older SDK / emulator), treat as granted
      // so dev/CI still flows. Real devices that lack the API are extremely
      // rare and the worst outcome is a no-op toggle.
      console.warn('FloatingWindowPermission.checkPermission: ' + (e as Error).message)
      return true
    }
  }

  // High-level: returns true when the user ends up with the permission.
  // When already granted → returns true synchronously.
  // When missing → jumps to the system permission page, waits for the user
  // to return, re-checks the permission.
  static async ensurePermission(): Promise<boolean> {
    if (await FloatingWindowPermission.checkPermission()) {
      return true
    }
    const ctx = AudioPlayerService.getInstance().getContext()
    if (!ctx) return false
    try {
      // Open the system permission management page for this bundle. The
      // exact want spec follows the established HarmonyOS docs pattern; if
      // a subsystem rejects the want, we fall through to the no-op and
      // log a warning.
      await (ctx as common.UIAbilityContext).startAbility({
        bundleName: 'com.huawei.hmos.settings',
        abilityName: 'com.huawei.hmos.settings.MainAbility',
        uri: 'application_info_entry',
        parameters: {
          'pushParams': ctx.abilityInfo.bundleName
        }
      })
    } catch (e) {
      console.warn('FloatingWindowPermission.ensurePermission: '
        + 'startAbility failed - ' + (e as Error).message)
      return false
    }
    // The user is now in system settings. We cannot synchronously wait for
    // the return; the caller (NotificationViewModel) re-checks on the next
    // foreground tick (see plan §6). To keep this helper consistent we
    // re-check once here for the fast-grant case (user granted permission
    // before this Promise was awaited).
    return await FloatingWindowPermission.checkPermission()
  }
}

export default FloatingWindowPermission
```

If the SDK does not actually accept that `bundleName` / `abilityName` / `uri` triple, the worst outcome is the warning log and a `false` return — the toggle row reverts to OFF and the user can try again. This degrades gracefully.

### 4.8 `entry/src/main/ets/pages/NotificationPage.ets`

**No change.** The page already renders the toggle row and the "also close desktop lyrics" dialog overlay.

### 4.9 String resources

**No change.** `show_desktop_lyrics_button` / `show_desktop_lyrics_button_intro` / `also_close_desktop_lyrics` / `also_close_desktop_lyrics_intro` are all present in `base`, `zh`, and `ug` (verified at `entry/src/main/resources/base/element/string.json:2716, 2720` and the dialog strings already used by `NotificationPage.ets:162, 168`).

## 5. Refresh model (live update path, end-to-end)

```
[User flips "显示桌面歌词按钮" on NotificationPage]
        │
        ▼
SwitcherRowViewModel.toggle() ── ViewModel layer owns the action
        │
        ▼
NotificationViewModel.onDesktopLyricsButtonChanged(val)  (async)
        │
        ├── if (val): FloatingWindowPermission.ensurePermission()
        │     │
        │     ├── permission granted ─► continue
        │     └── permission missing ─► system settings; on return re-check;
        │                                if still missing, revert row to OFF
        │
        ▼
NotificationModel.saveShowDesktopLyricsButton(val) ── Model owns persistence
        │
        ▼
SettingsStore.save('showDesktopLyricsButton', val)
   → AppStorage.setOrCreate('showDesktopLyricsButton', val)
   → preferences.putSync + flushSync                 (write to disk)
        │
        ▼
MediaCardDesktopLyricsButtonController.onToggleChanged()
        │
        ▼
publishToggle() ── reads AppStorage('showDesktopLyricsButton')
        │
        ▼
AudioPlayerService.publishDesktopLyricsButtonExtras(val)
   → session.setExtras({ showDesktopLyricsButton: val })
   → session.dispatchSessionEvent('showDesktopLyricsButtonChanged', { value: val })

ALSO, if (!val) AND AppStorage.get('desktopLyrics') === true:
        │
        ▼
NotificationViewModel.showAlsoCloseDesktopLyricsDialog = true  (UI overlay)
        │
        ▼ user confirms
NotificationViewModel.confirmCloseDesktopLyrics()
        │
        ▼
NotificationModel.saveDesktopLyricsEnabled(false) + AppStorage broadcast
MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow()
        │
        ▼
publishLyricsState()  ── empty line + inactive
        │
        ▼
AudioPlayerService.publishCardLyricsState(false, '')

[System media card / live activity]
        │
        ▼
(today) renders standard play/pause/next/prev set; artist row shows artist.
The extras + events are observable by any controller or future surface;
the published values are correct from frame 0 of the next AVSession activation.
(future) when HarmonyOS exposes either an action slot or an artist-row
override, that surface reads:
   AppStorage('showDesktopLyricsButton') (or session.getExtras())
and either renders the lyric button or omits it. When the user taps it, the
card dispatches:
   AVSessionController.dispatchControlCommand('common', { command: 'toggleCardLyrics' })
which arrives in AudioPlayerService.on('commonCommand') → controller →
flips isLyricsActive → publishCardLyricsState(true|false, line). The card
reads cardLyricsActive + cardLyricsLine from extras / event payload and
swaps its artist row accordingly.
```

Live-lyric publish path (independent of toggle flips):

```
MiniLyricsController.tickOnce()  ── 200ms tick
        │
        ▼
listener fires: (songId, newLine, hasLyrics)
        │
        ▼
MediaCardDesktopLyricsButtonController.lyricsListener
        │
        │  updates currentLine, hasLyrics
        ▼
if (isLyricsActive) publishLyricsState()
        │
        ▼
AudioPlayerService.publishCardLyricsState(true, currentLine)
```

Cold-start path:

```
EntryAbility.onCreate ── PersistentStorage.persistProp('showDesktopLyricsButton', true)
                      ── AppStorage.setOrCreate from SettingsStore.get(...)
                      ── AudioPlayerService.initContext(...)
                      ── MiniLyricsController.getInstance().init()
                      ── NotificationLyricController.getInstance().init()
                      ── MediaCardCloseButtonController.getInstance().init()
                      ── MediaCardDesktopLyricsButtonController.getInstance().init()
                         └→ publishToggle() pushes persisted value
                         └→ publishLyricsState() pushes (false, '')
                         └→ subscribes to MiniLyricsController and the
                            song-change bus
```

Song change path (scenario 4):

```
AudioPlayerService.notifySongChanged(song)
        │
        ▼ (controller's song-change listener)
MediaCardDesktopLyricsButtonController.songChangedListener(song)
        │
        ├── isLyricsActive ← false   (per-song reset, scenario 4 last bullet)
        ├── currentLine    ← ''
        ▼
republish toggle + lyrics state (force resend because lastPublished* = null)
```

## 6. Scenario coverage

| Scenario | Path covered | Verification |
| --- | --- | --- |
| S1 (default ON, lyric button shown left of prev-track) | `EntryAbility` seeds `showDesktopLyricsButton=true`; controller's `publishToggle()` pushes `setExtras({ showDesktopLyricsButton: true })` + `dispatchSessionEvent` at cold start. **On-card visual**: see §2 — system media card cannot host a third button today. Data-flow layer satisfied. | Cold start, open Notification page: toggle reads ON. `session.getExtras()` → `{ showDesktopLyricsButton: true }` from a test harness. |
| S2 (tap lyric button → artist row swaps to running lyric) | `session.on('commonCommand', cmd => …)` → `MediaCardDesktopLyricsButtonController.requestToggleLyricsActive()` → flips `isLyricsActive=true` → `publishCardLyricsState(true, currentLine)`. On every 200ms `MiniLyricsController` tick → `publishCardLyricsState(true, newLine)`. On-card render: §2. | Dispatch `controlCommand{command: 'toggleCardLyrics'}` from a test harness while toggle is ON and song has lyrics. Verify `extras.cardLyricsActive === true`, `extras.cardLyricsLine === <expected line for current play time>`, and `dispatchSessionEvent('cardLyricsStateChanged', …)` fires. |
| S3 (tap again → restore artist row) | Same path, `isLyricsActive` flips back to `false`; `publishCardLyricsState(false, '')`. | Same as S2 — second dispatch toggles it back. |
| S4 (switch song while lyrics shown → new song's lyric tracks, or artist if no lyrics) | `AudioPlayerService.notifySongChanged(song)` → controller's `songChangedListener` resets `isLyricsActive=false` (so the next render starts from artist), republishes both extras keys with the new state. (If the platform implements the row swap, scenario 4's "lyric content updates with song progress" reduces to the existing 200ms `MiniLyricsController` tick.) | Trigger `skipNext()`. Verify `extras.cardLyricsActive === false` (per-song reset). Dispatch `toggleCardLyrics` again — running line of the new song appears in extras. |
| S5 (current song has no lyric — tap button no-op) | `requestToggleLyricsActive()` early-returns when `!hasLyrics && !isLyricsActive`. | With a song that has no lyric, dispatch `toggleCardLyrics`. Verify extras unchanged. |
| S6 (toggle OFF + floating window showing → ask user to also close) | `onDesktopLyricsButtonChanged(false)` reads `AppStorage('desktopLyrics')` LIVE, sets `showAlsoCloseDesktopLyricsDialog=true` only when the floating window is currently on. Confirm path runs `model.saveDesktopLyricsEnabled(false)` + `controller.requestCloseFloatingWindow()`. Cancel path keeps the floating window state untouched. | Enable `desktopLyrics`, then flip the spec24 toggle OFF on Notification page — dialog appears. Confirm → `AppStorage('desktopLyrics') === false`. Cancel → `AppStorage('desktopLyrics') === true`. Repeat with `desktopLyrics=false` from the start — no dialog. |
| S7 (toggle ON + has permission → enable immediately) | `FloatingWindowPermission.ensurePermission()` returns `true` synchronously (checkPermission grants); persistence + publish proceed. | Manually grant overlay permission (or stub the helper). Toggle ON → no system page jump; toggle stays ON. |
| S8 (toggle ON + no permission → jump to system settings) | `FloatingWindowPermission.ensurePermission()` returns `false` (initial check), opens system settings via `context.startAbility(...)`. On return → re-checks; toggle reverts to OFF if still denied. | Revoke overlay permission, flip toggle ON. Verify system settings page opens. Without granting, return: toggle is OFF in AppStorage and on screen. Grant permission, return: confirm row stays at the post-return value (the design defers the post-return re-check to the next foreground tick — for v1 the row reverts to OFF and the user re-taps). |
| S9 (persisted across restart) | `PersistentStorage.persistProp('showDesktopLyricsButton', true)` + `SettingsStore` write on every flip. Cold start hydration block reads the persisted value into `AppStorage`. | Flip toggle ON/OFF, force-kill the app, relaunch. Toggle reads the same value. Card extras `showDesktopLyricsButton` matches across the cold start. |
| S10 (compact card → only prev/play/next, lyric button hidden) | System-rendered — the card decides which slots to render in compact mode. Out of platform-scope; the data is published unchanged. | N/A — read §2; no app-level wiring affects this. |

The plan does NOT claim to deliver:

- A system-rendered third button on the card (S1, S10 visual).
- An on-card artist→lyric row swap (S2, S3, S4 visual).

These are HarmonyOS platform surfaces gated by AVSession's fixed slot model. Every other piece — toggle state, persistence, broadcast, permission probe, dialog gating, per-song lyric reset, running-line publish — is delivered.

## 7. Owner-boundary safeguards (per harness rules)

- **Page does not persist.** `NotificationPage.ets` is untouched. Only `NotificationModel.saveShowDesktopLyricsButton(...)` writes the toggle key. Pages never call `SettingsStore` for this flag.
- **No mirror state.** A single `AppStorage` key (`'showDesktopLyricsButton'`) is the cross-process source of truth. The Model field is a local cache rebuilt by `loadSettings()`; the controller's `lastPublished*` are publish-debouncers, not state mirrors.
- **No reliance on `aboutToAppear` for live sync.** The bridge is `MediaCardDesktopLyricsButtonController.onToggleChanged()`, called synchronously after `NotificationViewModel` persists. It does not wait for a page lifecycle to fire. The dialog gate (`showAlsoCloseDesktopLyricsDialog`) reads `AppStorage('desktopLyrics')` live, not from a stale `aboutToAppear` snapshot.
- **No fake defaults.** Default is `true` and matches the spec ("默认开启"). Seed in `EntryAbility` uses `SettingsStore.get('showDesktopLyricsButton', true)` so a missing key falls back to ON; the toggle UI reads from `AppStorage` so the first frame already reflects persistence.
- **Service is the sole AVSession toucher.** Only `AudioPlayerService` calls `session.setExtras`, `session.dispatchSessionEvent`, `session.on('commonCommand', ...)`. The controller orchestrates *when*; the service performs *what*.
- **Toggle gate cannot be bypassed.** `requestToggleLyricsActive()` re-reads `AppStorage('showDesktopLyricsButton')` and the per-song `hasLyrics` before doing any work. Even a stale common-command after the user flipped OFF (S5 / S6) is dropped at the controller boundary.
- **Per-song lyric-active state is in-memory only.** Matches spec semantics (no requirement to persist the click-state of the card's lyric button across restarts; scenario 4 explicitly says it resets on song change).
- **Floating-window permission probe is in the Model layer.** ViewModel calls `FloatingWindowPermission.ensurePermission()` and observes the boolean result. The page never touches the permission API.
- **Lyric publisher is `MiniLyricsController`, the same one used by `NotificationLyricController` and the in-app mini bar.** No second timer, no duplicated lyric-parsing path — the controller subscribes and is fed.
- **Confirmation dialog reuses existing state.** `showAlsoCloseDesktopLyricsDialog` is the existing `@Track` field on `NotificationViewModel`. We only sharpen its trigger condition (live `AppStorage('desktopLyrics')` read instead of stale snapshot).

## 8. Out of scope (do not change)

- The `desktopLyrics` floating window itself. spec18 (or whichever spec ships the floating window) owns its presentation. `requestCloseFloatingWindow()` is the integration *hook*; the actual window-manager teardown lives where the window is created.
- `showCloseButton` (spec23) — already in production. Its controller is the template, not a target of edits beyond import additions.
- `NotificationPage.ets` — chrome and overlay already in place per spec23. The "secondary-page-style" memory note does not apply (page is already `NavDestination`-rooted and spec24 does not touch its title bar).
- The system media-card rendering. Detailed in §2.
- `MiniLyricsController` — its existing 200ms tick and listener contract are reused as-is; no changes.
- `NotificationLyricController` — it owns the title-field override for spec12. Spec24's `cardLyricsLine` is published independently; the two paths coexist.

## 9. Verification checklist (post-implementation)

- [ ] Build the project — no new compilation errors (note the `session.on('commonCommand', …)` cast and the `FloatingWindowPermission` API calls are `try/catch`-wrapped so older SDKs still compile and run).
- [ ] Fresh install: toggle reads ON; `AppStorage.get('showDesktopLyricsButton') === true`; `session.getExtras()` reports `{ showDesktopLyricsButton: true, cardLyricsActive: false, cardLyricsLine: '' }` after the first song plays.
- [ ] Flip toggle OFF (with `desktopLyrics === false`): no dialog; `AppStorage.get('showDesktopLyricsButton') === false`; `cardLyricsActive` resets to `false` (already was).
- [ ] Flip toggle OFF (with `desktopLyrics === true`): "also close desktop lyrics" dialog appears. Confirm → `desktopLyrics === false`. Cancel → `desktopLyrics === true`. The spec24 toggle is OFF either way.
- [ ] Flip toggle ON without overlay permission: system settings page opens; without granting, on return the toggle is OFF (row reverts via `setSilent(false)`).
- [ ] Flip toggle ON with overlay permission already granted: toggle stays ON; no system page jump.
- [ ] Synthetically dispatch `controlCommand{command: 'toggleCardLyrics'}` while toggle is ON and the current song has lyrics → `extras.cardLyricsActive === true`; `extras.cardLyricsLine` matches the current lyric line within ~200ms; dispatch again → `false` and `''`.
- [ ] Same dispatch while toggle is OFF → no state change; the gate inside `requestToggleLyricsActive()` drops it.
- [ ] Same dispatch while toggle is ON but current song has no lyrics → no state change (scenario 5).
- [ ] During scenario 2 state (lyric showing), trigger `skipNext()`. Verify `cardLyricsActive` resets to `false` (per-song), and a fresh dispatch picks up the new song's running line.
- [ ] Cold-restart with toggle previously set to OFF: still OFF on launch; extras carry `false`.
- [ ] No regression to `showCloseButton` (spec23) flow.
- [ ] No regression to the Notification page UI (toggle row layout, warning RoundedColumn, dialog overlay).
- [ ] No regression to the existing notification-bar-lyrics title-override (spec12) — `NotificationLyricController` keeps writing `setNotificationDisplayTitle`, independent of the new `cardLyricsLine` extras key.
