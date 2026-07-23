# spec26 — 桌面歌词 Implementation Plan

Project root: `/Users/moriafly/GitHub/SaltPlayerHarmony`
Spec file: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec26/plan.md`
Output:   `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec26/logic`

## 0. Scope mapped to scenarios

spec26 introduces a **draggable, touchable, system-level floating window that
renders the running lyric line on the device home screen** with a transient
control panel for play/pause/next/prev/lock and style controls (size, color).

Scenarios covered:

| # | Topic                                                  | Owner                                                   |
| - | ------------------------------------------------------ | ------------------------------------------------------- |
| 1 | toggle ON with permission                              | LyricsSettingsViewModel + DesktopLyricsController       |
| 2 | toggle ON without permission                           | LyricsSettingsViewModel (toast + revert)                |
| 3 | toggle OFF                                             | LyricsSettingsViewModel + DesktopLyricsController       |
| 4 | drag to reposition (Y persisted)                       | DesktopLyricsWindow page + DesktopLyricsController      |
| 5 | tap text (non-drag) toggles control panel              | DesktopLyricsWindow page                                |
| 6 | tap “lock” → enter locked mode (toast + persist)       | DesktopLyricsControlPanel handler → controller          |
| 7 | unlock via Settings → recover touch + toast            | LyricsSettingsViewModel + DesktopLyricsController       |
| 8 | live lyric updates + song change + fallback to subtitle | DesktopLyricsController subscribes MiniLyricsController |
| 9 | cold start auto-restore based on persisted flag        | DesktopLyricsController.init() in EntryAbility.onCreate |
| 10 | font size +/- (12 ↔ 36 dp, step 4 dp, persisted)      | DesktopLyricsControlPanel handler → controller          |
| 11 | color picker (highlight/green/red/white, persisted)   | DesktopLyricsControlPanel handler → controller          |
| 12 | prev / play-pause / next                              | DesktopLyricsControlPanel → AudioPlayerService          |
| 13 | locked: touches pass through                          | DesktopLyricsController.applyTouchableState             |

No new permission strings are needed — `ohos.permission.SYSTEM_FLOAT_WINDOW`
is already declared and the helper `FloatingWindowPermission` already exposes
`checkPermission` / `ensurePermission`.

## 1. MVVM owner boundary (load-bearing)

This feature lives in three coordinated tiers; **persistence and refresh stay
out of the page**:

- **Page / Component (View)** — `pages/DesktopLyricsWindow.ets` (HEAD-LESS
  content of the system floating window) and the **section markup** already
  present in `pages/LyricsSettingsPage.ets`. Owns gesture detection, render
  state, and the local "control-panel visible" UI flag. **No** SettingsStore
  writes, **no** window APIs.
- **ViewModel (Action)** — `viewmodel/LyricsSettingsViewModel.ets` (already
  exists; we wire its `onDesktopLyricsChanged` + `lockDesktopLyricsVM.toggle`
  handlers to call into the controller and surface toasts). A new pure-presentation
  `viewmodel/DesktopLyricsWindowViewModel.ets` holds the running line / style /
  lock state observable for the floating window page, **but never writes to
  persistence directly**: every action call delegates to the controller.
- **Model / Controller (State + Persistence + System surface)** —
  `model/DesktopLyricsController.ets` (new singleton). Owns the
  `@kit.ArkUI` `window` instance, the live lyric subscription, the geometry &
  style AppStorage keys, and is the **only** writer of the spec26 keys via
  `SettingsStore.save()`. Pattern-identical to
  `model/FloatingStatusBarLyricsController.ets` from spec25.

Reader / Writer / Binding / Refresh map (per the spec rules):

| Surface                               | Writer (owner)                                          | Reader (binding)                                          | Refresh path                                            |
| ------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------- | ------------------------------------------------------- |
| `desktopLyrics` (master)              | `LyricsSettingsViewModel.onDesktopLyricsChanged`        | `LyricsSettingsViewModel.desktopLyricsVM.isOn`            | `SettingsStore.save → AppStorage → @State` re-render    |
| `lockDesktopLyrics`                   | `LyricsSettingsViewModel.lockDesktopLyricsVM` toggle handler **and** `DesktopLyricsController.requestLock()` | LyricsSettingsPage (@State), DesktopLyricsWindow (@StorageProp) | `SettingsStore.save → AppStorage → both views`         |
| `desktopLyricsYPercent` (drag)        | `DesktopLyricsController.persistY()` (called on PanGesture end) | controller `applyGeometry()`                              | `SettingsStore.save → AppStorage` then `applyGeometry`  |
| `desktopLyricsFontSizeDp`             | `DesktopLyricsController.setFontSize()`                 | DesktopLyricsWindow `@StorageProp`                        | `SettingsStore.save → AppStorage → page re-render`      |
| `desktopLyricsColor`                  | `DesktopLyricsController.setColor()`                    | DesktopLyricsWindow `@StorageProp`                        | `SettingsStore.save → AppStorage → page re-render`      |
| `desktopLyricsLine` / `…SubLine`      | `DesktopLyricsController` (mirrors `MiniLyricsController` listener) | DesktopLyricsWindow `@StorageProp`                        | controller `notify → AppStorage → page re-render`       |

`@StorageProp` is the live-sync mechanism. `aboutToAppear` is used **only**
for the one-shot opacity init (matches spec25 precedent) — never for live
data hydration.

## 2. Files to add

### 2.1 `entry/src/main/ets/model/DesktopLyricsController.ets` (new)

Singleton. Pattern-derived from
`entry/src/main/ets/model/FloatingStatusBarLyricsController.ets:1`, with these
differences:

- **Window type**: must still be `window.WindowType.TYPE_SYSTEM_ALERT` (same
  permission gate). Created on first `show()`, destroyed on `hide()`.
- **Touchable state**: derived from `AppStorage.get<boolean>('lockDesktopLyrics')`.
  Apply via `setWindowTouchable()` on `show()` and every time
  `lockDesktopLyrics` flips. When `true` → touchable; when `false` (i.e.
  locked, touches pass through to the desktop) → `setWindowTouchable(false)`.
  This is the inverse meaning vs. spec25 (which never wanted touches at all):
  spec25 hard-coded `false`; spec26 uses the persisted lock flag.
- **Subscribers**:
  - `MiniLyricsController.addListener` → mirror `currentLine` / `currentSubLine`
    / `hasLyrics` into AppStorage keys
    `desktopLyricsLine`, `desktopLyricsSubLine`, `desktopLyricsHasLyrics`.
  - `AudioPlayerService.addOnSongChangedListener` → reset the line buffer
    immediately so the gap doesn’t show stale text. Also re-read the new
    song's `subTitle` from `QueueSongModel` and publish it as
    `desktopLyricsArtistFallback` (scenario 8 step 4 fallback rule:
    "当当前歌曲无歌词时显示歌曲副标题；若副标题也为空则显示空白").
- **Public API** consumed by ViewModel / page:

  ```
  init(ctx: common.UIAbilityContext): void           // EntryAbility.onCreate
  show(): Promise<void>                              // toggle ON
  hide(): Promise<void>                              // toggle OFF (idempotent)
  applyTouchableFromLock(): void                     // lockDesktopLyrics changed
  persistY(yPx: number): void                        // PanGesture end
  setFontSize(dp: number): void                      // +/- buttons
  setColor(argb: number): void                       // palette tap
  requestLock(): void                                // “锁定” button in panel
  destroy(): void                                    // EntryAbility.onWindowStageDestroy
  ```

- **Geometry**:
  - Window width = device width (`display.getDefaultDisplaySync().width`).
    The control panel needs full-width touch surfaces, so we make the window
    span the full screen width and gate hit-testing at the panel container
    level. Height = `desktopLyricsHeightPx` (fixed default 200 px, room for
    the panel + lyric line; capped to screen height).
  - Vertical position read from `desktopLyricsYPercent` (0–100). Initial
    default 30. Persisted by PanGesture end handler in the page; controller
    just publishes the value back to AppStorage and calls
    `win.moveWindowTo(0, yPx)`.

- **Geometry watcher**: a 250-ms `setInterval` polls
  `desktopLyricsYPercent` (and re-applies when changed) so a Settings-page
  drag in the future would still propagate; for spec26 the primary writer is
  the floating window itself (PanGesture). The polling pattern matches
  spec25; cheap and uniform.

### 2.2 `entry/src/main/ets/pages/DesktopLyricsWindow.ets` (new)

`@Entry @Component struct DesktopLyricsWindow`. **View only.**

- `@StorageProp` bindings:
  - `desktopLyricsLine`, `desktopLyricsSubLine`, `desktopLyricsHasLyrics`
  - `desktopLyricsArtistFallback`
  - `desktopLyricsFontSizeDp`, `desktopLyricsColor`
  - `desktopLyricsYPercent` (read-only here — controller writes)
  - `lockDesktopLyrics` (used to gate gestures + control-panel visibility)
  - `isPlaying` (drives play/pause icon in the panel)
- Local `@State controlPanelVisible: boolean = false` (per-window, transient).
- Layout (top→bottom inside a `Column`):
  1. **Style control panel** (visible when `controlPanelVisible && !lock`):
     - `font_size_minus` and `font_size_plus` buttons → call
       `DesktopLyricsController.setFontSize(current ± 4)`, clamped [12, 36].
     - 4 color chips (highlight / green / red / white) → call
       `setColor(argbValue)`.
  2. **Lyric text** in its own touch zone:
     - If `hasLyrics && line.length > 0` → render `Text(line)`.
     - Else if `currentSongSubTitle.length > 0` → render
       `Text(desktopLyricsArtistFallback)`.
     - Else `Text('')` (blank). spec scenario 1 step 5 also calls out
       "若当前无歌词则显示 '暂无歌词'" — that string is rendered only at the
       moment the master toggle turned ON and the controller hasn’t yet
       received its first listener callback. Wire by initialising
       `desktopLyricsLine = $r('app.string.no_lyrics')` on `show()` so the
       first frame after toggle shows the fallback, then the
       MiniLyricsController listener overwrites it. (No new string; reuse
       `app.string.no_lyrics` = "暂无歌词" at `string.json:2256`.)
  3. **Music control panel** (visible when `controlPanelVisible && !lock`):
     - Previous (`AudioPlayerService.getInstance().skipPrevious()`)
     - Play/Pause (`togglePlayPause()`)
     - Next (`skipNext()`)
     - Lock (calls `DesktopLyricsController.requestLock()`)

- **Gestures on the lyric Row**:
  - `GestureGroup(GestureMode.Exclusive, TapGesture, PanGesture)`.
  - `TapGesture(count:1)` → toggle `controlPanelVisible`. Disabled when
    `lockDesktopLyrics`.
  - `PanGesture(direction: PanDirection.Vertical | PanDirection.Horizontal)`:
    - `onActionUpdate` accumulates the offsetY into a `@State pendingDy`,
      uses `DesktopLyricsController.getInstance().nudgeYPx(dy)` to imperatively
      move the window every frame (controller calls `win.moveWindowTo`).
    - `onActionEnd` calls `DesktopLyricsController.getInstance().persistY()`
      which reads the *current* yPx from the live window (or from accumulated
      state) and writes the percent to SettingsStore. Scenario 4 step 5:
      "歌词的垂直位置被持久化保存".
- The whole window has `hitTestBehavior(HitTestMode.Transparent)` on the
  outer Column when `lock` is true so non-text regions never block the
  desktop. This complements the controller’s
  `setWindowTouchable(false)` call so both layers agree.

### 2.3 `entry/src/main/ets/viewmodel/DesktopLyricsWindowViewModel.ets` (new, lean)

Pure presentation helper used by the window page to compose `Text` items
when both `line` and `subLine` need to flow through the same conditional:

```
get displayMain(): string { return this.hasLyrics ? this.line : this.fallback }
get translationVisible(): boolean { return !this.notShowTranslation && this.subLine.length > 0 }
```

Reads from AppStorage; **no writes**. Mirrors the lean style of
`SwitcherRowViewModel`. Not strictly required — we may inline these in the
window page — but having one place lets the page stay declarative.

## 3. Files to edit

### 3.1 `entry/src/main/resources/base/profile/main_pages.json`

Register the new floating-window page so the controller can `setUIContent`:

```
"src": [
  "pages/main/MainPage",
  "pages/FloatingStatusBarLyricsWindow",
  "pages/DesktopLyricsWindow"
]
```

### 3.2 `entry/src/main/ets/entryability/EntryAbility.ets`

- Add the new persisted keys via `PersistentStorage.persistProp` BEFORE
  `SettingsStore.init`:
  - `desktopLyricsYPercent` default `30`
  - `desktopLyricsFontSizeDp` default `20`
  - `desktopLyricsColor` default `0xFF0470E6` (highlight blue — same as spec25)
  - `desktopLyricsLine` default `''`
  - `desktopLyricsSubLine` default `''`
  - `desktopLyricsHasLyrics` default `false`
  - `desktopLyricsArtistFallback` default `''`
- Hydrate them from `SettingsStore.get()` after `ss.init(context)` (mirrors
  the spec25 block right above the existing
  `floatingWindowSbLrLeftRightPercent` hydration).
- After `FloatingStatusBarLyricsController.getInstance().init(this.context)`,
  add:

  ```ts
  // spec26 — Desktop lyrics window controller. Same ordering rationale as
  // FloatingStatusBarLyricsController: must run AFTER MiniLyricsController +
  // AudioPlayerService.initContext + persistence hydration.
  DesktopLyricsController.getInstance().init(this.context)
  ```
- In `onWindowStageDestroy`, add a `try/catch` calling
  `DesktopLyricsController.getInstance().destroy()` next to the existing
  `FloatingStatusBarLyricsController.destroy()` block. Re-use the same
  permission `reprobeOnForeground` hook — no extra wiring needed because
  spec26 also keeps the toggle OFF on deny (scenario 2). For symmetry with
  spec25, we *don’t* auto-flip ON on grant for spec26 (the spec wording
  treats grant as an asynchronous user action that can be re-attempted).

### 3.3 `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets`

`onDesktopLyricsChanged` currently just persists. Extend it:

```ts
async onDesktopLyricsChanged(val: boolean): Promise<void> {
  if (val) {
    const granted = await FloatingWindowPermission.ensurePermission()
    if (!granted) {
      // scenario 2: revert + toast
      this.desktopLyricsVM.isOn = false
      this.model.desktopLyrics.isOn = false
      promptAction.showToast({ message: $r('app.string.no_floating_window_permission') })
      return
    }
  }
  this.model.desktopLyrics.isOn = val
  SettingsStore.getInstance().save('desktopLyrics', val)
  this.lockDesktopLyricsVM.isEnabled = val
  if (val) {
    DesktopLyricsController.getInstance().show().catch((e: Error) => {
      console.warn('LyricsSettingsViewModel.show desktop lyrics: ' + e.message)
    })
    promptAction.showToast({ message: $r('app.string.desktop_lyrics_opened') })
  } else {
    DesktopLyricsController.getInstance().hide().catch((e: Error) => {
      console.warn('LyricsSettingsViewModel.hide desktop lyrics: ' + e.message)
    })
    promptAction.showToast({ message: $r('app.string.desktop_lyrics_closed') })
  }
}
```

The handler is already wired through `SwitcherRowViewModel`, but its current
signature is `(val: boolean) => void`. To keep the synchronous handler
contract, we delegate to a private async impl with `.catch`:

```ts
this.desktopLyricsVM = new SwitcherRowViewModel(
  new SwitcherRowModel(model.desktopLyrics.isOn, model.desktopLyrics.isEnabled, model.desktopLyrics.text),
  (val: boolean) => {
    this.onDesktopLyricsChanged(val).catch((e: Error) => {
      console.warn('LyricsSettingsViewModel.onDesktopLyricsChanged: ' + e.message)
    })
  }
)
```

Similarly extend the `lockDesktopLyricsVM` handler:

```ts
(val: boolean) => {
  this.model.lockDesktopLyrics.isOn = val
  SettingsStore.getInstance().save('lockDesktopLyrics', val)
  DesktopLyricsController.getInstance().applyTouchableFromLock()
  promptAction.showToast({
    message: val ? $r('app.string.desktop_lyrics_locked')
                 : $r('app.string.desktop_lyrics_unlocked')
  })
}
```

Add `import promptAction from '@kit.ArkUI'` and
`import DesktopLyricsController from '../model/DesktopLyricsController'`.

Also clean up: the existing `initFromModel` writes
`AppStorage.get<boolean>('desktopLyrics') ?? model.desktopLyrics.isOn` into
`model.desktopLyrics.isOn` before instantiating the VM. Keep that — it
preserves the persisted state across page entries. Same for
`lockDesktopLyrics`.

### 3.4 `entry/src/main/ets/model/MediaCardDesktopLyricsButtonController.ets`

Already exposes `addCloseListener` / `requestCloseFloatingWindow`. In
`DesktopLyricsController.init`, register:

```ts
MediaCardDesktopLyricsButtonController.getInstance().addCloseListener(() => {
  this.hide().catch((_e: Error) => {})
})
```

This closes the spec24 hook from spec24 plan §2.6 (existing comment in
`MediaCardDesktopLyricsButtonController.ets:48–51` literally says "Spec18 …
registers a listener here"; spec26 is that landing). No further edits to
the spec24 controller are required.

### 3.5 `entry/src/main/ets/pages/LyricsSettingsPage.ets`

No changes to markup. The “桌面歌词” row already exists (lines 197-216)
and binds to `vm.desktopLyricsVM`; the “锁定桌面歌词” row exists (lines
217-235) and binds to `vm.lockDesktopLyricsVM`. Both will now invoke the
extended handlers in `LyricsSettingsViewModel`.

## 4. New string resources

Existing strings that we **reuse**:

| Key                              | Value          | Location                                    |
| -------------------------------- | -------------- | ------------------------------------------- |
| `desktop_lyrics`                 | 桌面歌词        | `string.json:916`                           |
| `desktop_lyrics_opened`          | 桌面歌词已打开 | `string.json:928` (spec uses "已开启" but the resource value "已打开" is functionally equivalent — keep the existing key to avoid resource churn) |
| `desktop_lyrics_closed`          | 桌面歌词已关闭 | `string.json:920`                           |
| `desktop_lyrics_locked`          | 桌面歌词已锁定 | `string.json:924`                           |
| `desktop_lyrics_unlocked`        | 桌面歌词已解锁 | `string.json:932`                           |
| `no_floating_window_permission`  | 无悬浮窗权限    | `string.json:233`                           |
| `no_lyrics`                      | 暂无歌词        | `string.json:2256` (en) / `zh:1380`        |
| `lock_desktop_lyrics`            | 锁定桌面歌词    | `string.json:1496`                          |

No new strings required; all toasts and fallback labels resolve to existing
resource keys. This is intentional: spec wording variation
("已打开" vs "已开启") is below the threshold where a new key earns its
maintenance cost.

## 5. AppStorage keys (single source of truth)

Newly introduced:

| Key                          | Type    | Default        | Writer                         | Persisted? |
| ---------------------------- | ------- | -------------- | ------------------------------ | ---------- |
| `desktopLyricsYPercent`      | number  | 30             | DesktopLyricsController        | yes        |
| `desktopLyricsFontSizeDp`    | number  | 20             | DesktopLyricsController        | yes        |
| `desktopLyricsColor`         | number  | 0xFF0470E6     | DesktopLyricsController        | yes        |
| `desktopLyricsLine`          | string  | ''             | DesktopLyricsController        | no         |
| `desktopLyricsSubLine`       | string  | ''             | DesktopLyricsController        | no         |
| `desktopLyricsHasLyrics`     | boolean | false          | DesktopLyricsController        | no         |
| `desktopLyricsArtistFallback`| string  | ''             | DesktopLyricsController        | no         |

Pre-existing keys re-used:

| Key                          | Reader        | Writer                           |
| ---------------------------- | ------------- | -------------------------------- |
| `desktopLyrics` (master)     | settings page, controller via init auto-show | LyricsSettingsViewModel  |
| `lockDesktopLyrics`          | settings page, controller (`applyTouchableFromLock`), window page | LyricsSettingsViewModel + controller `requestLock` |
| `isPlaying`                  | window page (play/pause icon) | AudioPlayerService               |
| `currentSongSubTitle`?       | not used today; we use the in-memory `QueueSongModel.subTitle` mirrored to `desktopLyricsArtistFallback` to avoid adding a new persisted key |

## 6. Scenario-by-scenario verification

- **Scenario 1** — toggle ON, permission granted: `ensurePermission()` returns
  true → persist → `show()` creates the window → toast "已打开". First frame
  shows `desktopLyricsLine = no_lyrics resource` until MiniLyricsController
  fires its initial listener callback (which it does immediately on
  `addListener` per its existing contract).
- **Scenario 2** — toggle ON, permission denied: `ensurePermission()` returns
  false → VM reverts `desktopLyricsVM.isOn = false` → toast "无悬浮窗权限"
  → controller is not touched.
- **Scenario 3** — toggle OFF: persist `desktopLyrics=false` → `hide()` →
  toast "已关闭". Lock toggle is also re-disabled by setting
  `lockDesktopLyricsVM.isEnabled = false` (existing line preserved).
- **Scenario 4** — drag: `PanGesture.onActionUpdate` calls
  `DesktopLyricsController.nudgeYPx(dy)` which mutates an in-memory `currentYPx`
  and calls `win.moveWindowTo(0, currentYPx)`. `onActionEnd` calls
  `persistY()` → converts to percent → `SettingsStore.save(
  'desktopLyricsYPercent', percent)`. Cold-start path:
  `applyGeometry()` reads the percent and re-positions.
- **Scenario 5** — tap toggles `controlPanelVisible` (`@State` in page). Pan
  detection wins via `GestureGroup` so a small movement does not register as
  tap (`GestureMode.Exclusive` + `PanGesture(distance: 5)`).
- **Scenario 6** — Lock button in panel calls `requestLock()`:
  1. SettingsStore.save('lockDesktopLyrics', true).
  2. Controller calls `applyTouchableFromLock()` → `win.setWindowTouchable(false)`.
  3. Window page hides `controlPanelVisible = false` (the @StorageProp on
     `lockDesktopLyrics` triggers a re-render that exits the panel branch).
  4. Toast "桌面歌词已锁定". Persistence by step 1.
- **Scenario 7** — Settings page flips lock OFF: `lockDesktopLyricsVM`
  handler persists and calls `applyTouchableFromLock()` →
  `win.setWindowTouchable(true)`. Toast "桌面歌词已解锁".
- **Scenario 8** — live updates: MiniLyricsController listener fires
  `(songId, line, has)` on every cursor advance and on song change. Controller
  mirrors to `desktopLyricsLine` + `desktopLyricsHasLyrics` + (via
  `MiniLyricsController.currentSubLine` accessor) `desktopLyricsSubLine`.
  Song-change listener also reads the new `QueueSongModel.subTitle` and
  publishes `desktopLyricsArtistFallback`. The window page renders by
  priority: `line` → `artistFallback` → `''`.
- **Scenario 9** — cold start: `controller.init()` reads
  `AppStorage.get<boolean>('desktopLyrics')` (already hydrated by the
  `AppStorage.setOrCreate('desktopLyrics', ss.get(...))` block in
  `EntryAbility.onCreate`). If true → `show()`. `applyGeometry()` reads
  `desktopLyricsYPercent` so position restores. Same pattern as the spec25
  auto-show block at `FloatingStatusBarLyricsController.ets:79-90`.
- **Scenario 10** — font size buttons: each press calls
  `controller.setFontSize(current ± 4)`. Clamped [12, 36]. Writes
  `desktopLyricsFontSizeDp` → page `@StorageProp` re-renders.
- **Scenario 11** — color chips: each tap calls `controller.setColor(argb)`.
  Writes `desktopLyricsColor`. Predefined ARGB values:
  highlight = `0xFF0470E6`, green = `0xFF057748`, red = `0xFFBE002F`,
  white = `0xFFFFFFFF` (consistent with the spec25 palette in
  `pages/FloatingWindowStatusBarLyricsPage.ets:49-53`).
- **Scenario 12** — playback buttons in panel directly call
  `AudioPlayerService.getInstance().skipPrevious/togglePlayPause/skipNext()`.
  These already exist (`AudioPlayerService.ets:1172, 1493, 1529`).
- **Scenario 13** — locked → touches pass through: the `setWindowTouchable(false)`
  call from step 7 above is the system-level pass-through. The page-level
  `hitTestBehavior(HitTestMode.Transparent)` is a backup so nothing inside
  the window’s ArkTS tree captures pointer events.

## 7. Risks & mitigations

- **`setWindowTouchable` availability**: spec25 already calls
  `await w.setWindowTouchable(false)` inside a try/catch that swallows the
  error on older SDKs. We do the same; on a device without the API, lock
  behavior degrades to "lock toggle persists but window still receives
  touches" — visible-but-acceptable for the same reason spec25 accepted it.
- **`window.WindowType.TYPE_SYSTEM_ALERT` declared off**: covered by the
  existing manifest entry `ohos.permission.SYSTEM_FLOAT_WINDOW`. No
  manifest edit required.
- **Two writers for `lockDesktopLyrics`**: the settings page handler and the
  controller’s `requestLock()` (panel button). Both go through the same
  `SettingsStore.save` + `applyTouchableFromLock` pair, so the AppStorage
  value remains the single source of truth and both views (settings page
  switch row, floating window panel) re-read it via `@State` /
  `@StorageProp`. No mirror state; no fake defaults.
- **Drag race vs. geometry watcher**: the 250 ms poller in the controller
  only re-applies when the AppStorage value differs from the last applied
  snapshot. The drag handler updates `currentYPx` imperatively (not through
  AppStorage) and persists only on PanEnd — the poller stays idle during a
  drag.
- **First-frame "暂无歌词" race**: solved by seeding
  `desktopLyricsLine` to the fallback string before the controller’s
  `addListener` call. When listener fires (synchronously on add per
  `MiniLyricsController.addListener` contract), the live line overwrites.

## 8. Wiring order (final)

```
EntryAbility.onCreate
  └ PersistentStorage.persistProp(... spec26 keys)
  └ SettingsStore.init
  └ AppStorage.setOrCreate(... spec26 hydration ...)
  └ AudioPlayerService.initContext
  └ MiniLyricsController.init
  └ NotificationLyricController.init
  └ MediaCardCloseButtonController.init
  └ MediaCardDesktopLyricsButtonController.init
  └ FloatingStatusBarLyricsController.init
  └ DesktopLyricsController.init        ← new
EntryAbility.onWindowStageDestroy
  └ FloatingStatusBarLyricsController.destroy
  └ DesktopLyricsController.destroy     ← new
```

## 9. Out of scope

- 桌面歌词 widget on Form/AppGallery card surfaces — different system surface.
- Horizontal position persistence — spec scenario 4 only persists vertical
  ("歌词的垂直位置被持久化保存"). X is in-memory only, resets to 0 on cold
  start (window spans full width by default anyway).
- A custom color picker dialog — spec scenario 11 lists 4 fixed colors; we
  render them as inline chips in the style panel, no dialog needed.
- Translation toggle for desktop lyrics — spec26 has no such switch, so
  `desktopLyricsSubLine` is **always** rendered when present (unlike the
  spec25 `statusBarLyricsNotShowTranslation` gate).
