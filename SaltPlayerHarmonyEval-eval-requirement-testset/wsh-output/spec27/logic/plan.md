# spec27 — 锁定桌面歌词 Implementation Plan

Project root: `/Users/moriafly/GitHub/SaltPlayerHarmony`
Spec file:    `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec27/plan.md`
Output:       `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec27/logic`

---

## 0. Scope & relationship to spec26

spec27 ("锁定桌面歌词") sits **on top of** spec26 (桌面歌词). spec26 already
landed the full desktop-lyrics floating window and the persisted
`lockDesktopLyrics` flag, the in-window Lock button, the setWindowTouchable
gating, and the master/lock dependency in `LyricsSettingsViewModel`. Most of
spec27 is therefore **already implemented**; what spec27 adds **above and
beyond spec26** is:

- Explicit, audited binding of the master-OFF state to the lock toggle's
  `enable` attribute (scenario 1). Already present but reverified.
- Hide the in-window control panel on lock (scenario 2 step 5). Already
  present (`DesktopLyricsWindow.requestLock()` sets
  `controlPanelVisible = false` before delegating).
- **Notification-bar lock state mirroring** (scenarios 2 step 7, 3 step 6,
  4 step 7, 5 step 6) — this is the NEW surface spec27 introduces.
- A **notification-bar entry point** for toggling the lock (scenario 5) —
  symmetric to spec25's "通过通知栏解锁" capability.
- Persistence audit of `lockDesktopLyrics` across the master toggle's
  OFF→ON cycle (scenario 6). Already covered because both flags are
  independent persisted keys; reverified.
- Persistence audit of `desktopLyricsYPercent` (scenario 7). Already
  covered by spec26 `DesktopLyricsController.persistY` writing to
  `SettingsStore`; reverified.

**Net new code** is concentrated on the notification-bar mirror — every
other scenario is "verify existing wiring and add tests / hardening".

### Scenario → owner map

| # | Topic                                                         | Owner                                                     | Status     |
| - | ------------------------------------------------------------- | --------------------------------------------------------- | ---------- |
| 1 | Master OFF → lock row disabled, taps no-op                    | `LyricsSettingsViewModel.lockDesktopLyricsVM.isEnabled`   | Existing   |
| 2 | Master ON → user flips lock ON (toast + panel hide + nbar)    | `LyricsSettingsViewModel` + `DesktopLyricsController`     | Partial    |
| 3 | Settings page unlocks (toast + nbar)                          | `LyricsSettingsViewModel` + `DesktopLyricsController`     | Partial    |
| 4 | In-window Lock button (toast + Settings row + nbar)           | `DesktopLyricsController.requestLock()`                   | Partial    |
| 5 | Notification-bar tap unlocks (toast + Settings row + nbar)    | New `DesktopLyricsLockNotificationController` (writer) → `DesktopLyricsController.applyLockedState` (refresh) | NEW |
| 6 | Lock persists across master OFF→ON re-toggle                  | Persisted `lockDesktopLyrics` + `DesktopLyricsController.show()` reads on (re)create | Existing |
| 7 | Drag → lock → cold-start position restore                     | `desktopLyricsYPercent` write on PanEnd + read on `show()` | Existing |

---

## 1. MVVM owner boundary (load-bearing)

The boundary inherited from spec26 stays intact. spec27 ADDS one new
sub-controller for the notification surface; nothing in the Page or
ViewModel learns about `notificationManager` APIs.

- **Page / Component (View)**:
  - `pages/LyricsSettingsPage.ets` — already binds the two `SwitcherRowVM`s.
    No change required for scenarios 1/2/3/4/5/6.
  - `pages/DesktopLyricsWindow.ets` — already gates panel visibility on
    `@StorageProp('lockDesktopLyrics')` and pipes the in-window Lock click
    into `DesktopLyricsController.requestLock()`.
- **ViewModel (Action)**:
  - `viewmodel/LyricsSettingsViewModel.ets` — already owns the lock-toggle
    `onChange` handler. We harden it to drive the **notification surface
    via the controller** (controller is the single owner of the system
    surfaces; the VM never touches `notificationManager` directly).
- **Model (State + Persistence + System surface)**:
  - `model/DesktopLyricsController.ets` — already owns the floating window
    and the `lockDesktopLyrics` writes from `requestLock()`. **Extended**
    in spec27 to ALSO own the notification-bar icon push, by delegating to
    a new sibling controller (see 2.1).
  - **NEW** `model/DesktopLyricsLockNotificationController.ets` —
    singleton; owns the system notification (`@kit.NotificationKit`) used
    as the lock indicator + unlock entry point. Pattern-derived from
    existing controllers like `MediaCardCloseButtonController`.

### Reader / Writer / Binding / Refresh map

| Surface                                | Writer (owner)                                                                              | Reader (binding)                                                       | Refresh path                                                                               |
| -------------------------------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `desktopLyrics` (master)               | `LyricsSettingsViewModel.onDesktopLyricsChanged`                                            | Settings page + `DesktopLyricsController` auto-show                    | `SettingsStore.save → AppStorage → @State / @StorageProp` re-render                        |
| `lockDesktopLyrics`                    | `LyricsSettingsViewModel.lockDesktopLyricsVM` handler **and** `DesktopLyricsController.requestLock()` **and** `DesktopLyricsLockNotificationController` (unlock from notification) | Settings page (`@State`/`SwitcherRowVM.isOn`), `DesktopLyricsWindow` (`@StorageProp`), `DesktopLyricsController.applyTouchableFromLock`, `DesktopLyricsLockNotificationController.publish` | `SettingsStore.save → AppStorage → applyLockedState() → all observers re-render`           |
| `lockDesktopLyricsVM.isEnabled`        | `LyricsSettingsViewModel.onDesktopLyricsChanged` (sets `= val`)                              | Settings page `HdsListItemCard.enable`                                  | direct `@Track` update                                                                     |
| `desktopLyricsYPercent`                | `DesktopLyricsController.persistY` (PanGesture end)                                          | `DesktopLyricsController.applyGeometry`                                 | `SettingsStore.save → AppStorage → applyGeometry on next show / poller`                    |
| Notification card (system surface)     | `DesktopLyricsLockNotificationController.publish` / `.cancel`                                | System UI                                                              | `notificationManager.publish` / `.cancel` direct                                           |

`@StorageProp` is the live-sync mechanism (proven in spec25/spec26).
`aboutToAppear` is not used as a sync point anywhere in this plan. No
mirror state; no fake defaults; persistence stays out of the Page.

---

## 2. Files to add

### 2.1 `entry/src/main/ets/model/DesktopLyricsLockNotificationController.ets` (new)

Singleton. Owns the system notification used as the "桌面歌词 已锁定 / 未锁定"
status mirror in the notification shade and as the **unlock entry point**
for scenario 5.

```
class DesktopLyricsLockNotificationController {
  static getInstance(): DesktopLyricsLockNotificationController

  init(ctx: common.UIAbilityContext): void   // EntryAbility.onCreate
  publishLockedIcon(): void                  // shows the "locked" notification
  publishUnlockedIcon(): void                // shows the "unlocked" notification
  cancel(): void                             // master toggle OFF or no-floating-window
  destroy(): void                            // EntryAbility.onWindowStageDestroy

  // Wired by EntryAbility into the user-tap intent: when the user taps the
  // notification, this method is invoked with the current lock value as
  // observed by the launching want (forwarded via parameters['lock']).
  onNotificationTap(): void
}
```

Implementation notes:

- Uses `@kit.NotificationKit` `notificationManager.publish(NotificationRequest)`.
  `NotificationRequest.id = NOTIFICATION_ID_LOCK_DESKTOP_LYRICS` (a stable
  module-local constant `7026` — chosen to not collide with spec23's
  notification IDs).
- Content type `notificationManager.SlotType.SERVICE_INFORMATION` so the
  card sits in the persistent group, not the "social" group.
- The notification body uses two existing string resources:
  `app.string.desktop_lyrics_locked` (when locked) and
  `app.string.desktop_lyrics_unlocked` (when unlocked). Title uses the
  existing `app.string.desktop_lyrics` ("桌面歌词").
- The notification is **tappable**. The tap intent is built via
  `wantAgent.getWantAgent` with an explicit
  `parameters: { 'spDesktopLyricsAction': 'toggleLock' }` so the
  ability's `onNewWant` handler can route into this controller.
- `init(ctx)` also registers an `onApplicationCreate` push of the current
  state when the master toggle is ON (idempotent — re-reads
  `AppStorage.get<boolean>('desktopLyrics')` and only publishes when
  master is ON). Matches spec27 scenario 6 (cold start with master ON +
  lock ON → notification shows "已锁定" on first frame).
- Touching `notificationManager` is wrapped in `try/catch` (spec23
  precedent) so unsupported API levels degrade to "no notification mirror"
  rather than crashing the app.
- **Singleton API only writes through `DesktopLyricsController.setLock(value)`**
  on unlock tap (NOT directly to `SettingsStore`). This keeps the
  authoritative writer single: the floating-window controller. The
  notification controller is a side-surface that reads the
  authoritative flag and pushes UI; it does not duplicate persistence
  logic.

### 2.2 (no new ViewModel)

The existing `LyricsSettingsViewModel` lock handler stays the writer for
the Settings-page lock change. We do not add a new ViewModel; spec27 is
not a new screen, it's a behavior layer on top of spec26's existing
Settings rows + window. (If we added one we would violate the spec
guidance to not create new ViewModels for behavior that is already owned
elsewhere.)

---

## 3. Files to edit

### 3.1 `entry/src/main/ets/model/DesktopLyricsController.ets`

Three small additions; no MVVM boundary moved.

1. **Centralize lock state propagation in a `applyLockedState()` method**
   that is called by every writer (the Settings page VM, the in-window
   `requestLock`, and the notification tap path). Today, the controller
   has `applyTouchableFromLock()` but the Settings-page VM separately
   calls it AND `promptAction.showToast` AND persists. Spec27 turns the
   controller into the single fan-out so the three call sites stay in
   sync:

   ```ts
   // Called by every writer of lockDesktopLyrics. Performs the
   // side-effects that must follow EVERY lock flip:
   //   1) re-apply window touchable
   //   2) hide the in-window control panel (handled by the @StorageProp
   //      observer in DesktopLyricsWindow; no controller code needed)
   //   3) push the notification mirror
   // Persistence and toast are the responsibility of the caller, so the
   // caller can vary the toast string (scenario 4 vs scenario 5 use the
   // same locked-toast string anyway, but the unlock path also writes
   // the lock OFF and toasts "已解锁").
   applyLockedState(): void {
     this.applyTouchableFromLock()
     const win = this.win
     const locked: boolean =
       AppStorage.get<boolean>('lockDesktopLyrics') ?? false
     // Only mirror the notification when the master is ON; if master is
     // OFF the notification is cancelled by hide().
     if (win) {
       if (locked) {
         DesktopLyricsLockNotificationController.getInstance()
           .publishLockedIcon()
       } else {
         DesktopLyricsLockNotificationController.getInstance()
           .publishUnlockedIcon()
       }
     }
   }
   ```

2. **Extend `requestLock(value: boolean = true)`** to take an explicit
   value so the same method works as the unlock tap target. The current
   no-arg `requestLock()` callers stay compatible because of the default
   parameter:

   ```ts
   requestLock(value: boolean = true): void {
     SettingsStore.getInstance().save('lockDesktopLyrics', value)
     this.applyLockedState()
     try {
       promptAction.showToast({ message:
         value ? $r('app.string.desktop_lyrics_locked')
               : $r('app.string.desktop_lyrics_unlocked') })
     } catch (e) {
       console.warn('DesktopLyricsController.requestLock toast: '
         + (e as Error).message)
     }
   }
   ```

3. **`show()` and `hide()` now also cancel/publish the notification**:

   ```ts
   // inside show() after applyTouchableFromLock():
   const lockedNow: boolean =
     AppStorage.get<boolean>('lockDesktopLyrics') ?? false
   if (lockedNow) {
     DesktopLyricsLockNotificationController.getInstance()
       .publishLockedIcon()
   } else {
     DesktopLyricsLockNotificationController.getInstance()
       .publishUnlockedIcon()
   }
   ```

   ```ts
   // inside hide() before destroyWindow:
   DesktopLyricsLockNotificationController.getInstance().cancel()
   ```

   Scenario 1 reads naturally from this: when master is OFF, `hide()` has
   already cancelled the notification, so the notification surface is also
   absent (no "lock indicator without lyrics"). Scenario 6 reads naturally
   too: when master flips back ON, `show()` re-creates the window AND
   re-publishes the persisted lock state — which means the notification
   icon and the touchable state and the position are all restored in the
   same call.

### 3.2 `entry/src/main/ets/viewmodel/LyricsSettingsViewModel.ets`

Reduce the lock handler from `(save + applyTouchable + toast)` to a single
controller call. The controller is the single owner of the side-effects:

```ts
this.lockDesktopLyricsVM = new SwitcherRowViewModel(
  new SwitcherRowModel(model.lockDesktopLyrics.isOn, model.lockDesktopLyrics.isEnabled,
    model.lockDesktopLyrics.text),
  (val: boolean) => {
    this.model.lockDesktopLyrics.isOn = val
    // Single writer: controller persists, applies touchable, publishes
    // the notification, and toasts. We pass the value explicitly so the
    // controller does not have to re-read AppStorage before persisting.
    DesktopLyricsController.getInstance().requestLock(val)
  }
)
```

This collapses spec26's three lines (save + applyTouchable + toast) into
one call. The end-user observable behavior is identical, but every writer
(Settings page, in-window button, notification tap) now funnels through
the same method — preventing the mirrored-state risk the plan rules call
out.

Also update the existing `onDesktopLyricsChanged(val)`: in the OFF branch
we set `this.lockDesktopLyricsVM.isEnabled = false` (existing line 152
already does this — preserve it). In the ON branch we set it to `true`.
**Scenario 1 fix audit**: the Settings page binds
`enable: this.vm.lockDesktopLyricsVM.isEnabled` (line 233), which is
driven from `model.lockDesktopLyrics.isEnabled` at construction and
flipped here on toggle. The existing line 81
(`model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn`) handles
the initial restore. **No code change needed**, but it must stay in place.

### 3.3 `entry/src/main/ets/entryability/EntryAbility.ets`

Three additions:

1. **Import** the new controller:

   ```ts
   import { DesktopLyricsLockNotificationController }
     from '../model/DesktopLyricsLockNotificationController'
   ```

2. **Init** in `onCreate` after `DesktopLyricsController.getInstance().init`:

   ```ts
   // spec27 — Notification-bar mirror for the lock state and the unlock
   // entry point. Initialized AFTER DesktopLyricsController so the
   // notification controller can safely call back into it on tap.
   DesktopLyricsLockNotificationController.getInstance()
     .init(this.context)
   ```

3. **Destroy** in `onWindowStageDestroy` alongside the existing
   `DesktopLyricsController.destroy()`:

   ```ts
   try {
     DesktopLyricsLockNotificationController.getInstance().destroy()
   } catch (e) {
     hilog.warn(DOMAIN, 'DesktopLyricsLockNotif', 'destroy failed: %{public}s',
       (e as Error).message)
   }
   ```

4. **Want-route handling** for the unlock notification tap. Add an
   `onNewWant` override on `EntryAbility` (or extend the existing one if
   present) that inspects
   `want.parameters['spDesktopLyricsAction']`. When it equals
   `'toggleLock'`, the existing AppStorage value is the current state,
   so we flip it through the controller:

   ```ts
   onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
     const action = want.parameters?.['spDesktopLyricsAction'] as string | undefined
     if (action === 'toggleLock') {
       const cur: boolean = AppStorage.get<boolean>('lockDesktopLyrics') ?? false
       // Scenario 5: only an unlock entry point — the notification only
       // appears in locked state with this action wired up. Still, defend
       // by toggling so a missed-edge cancel doesn't trap the user.
       DesktopLyricsController.getInstance().requestLock(!cur)
     }
   }
   ```

   If `onNewWant` already exists, append the branch; do not replace.

### 3.4 `entry/src/main/ets/pages/DesktopLyricsWindow.ets`

No code change needed for spec27 — `requestLock()` already exists from
spec26 and now goes through `applyLockedState()` automatically (transit
ively, because `requestLock()` calls `applyLockedState()`). Reverified.

### 3.5 `entry/src/main/ets/pages/LyricsSettingsPage.ets`

No code change. The existing markup already binds `enable` to
`lockDesktopLyricsVM.isEnabled` and `isCheck` to `lockDesktopLyricsVM.isOn`.

---

## 4. Resources

### 4.1 Strings

All resources for spec27 toasts and notification labels already exist:

| Key                            | Value          | File                                    |
| ------------------------------ | -------------- | --------------------------------------- |
| `desktop_lyrics`               | 桌面歌词        | `string.json:920`                       |
| `desktop_lyrics_locked`        | 桌面歌词已锁定 | `string.json:924`                       |
| `desktop_lyrics_unlocked`      | 桌面歌词已解锁 | `string.json:932`                       |
| `lock_desktop_lyrics`          | 锁定桌面歌词   | `string.json:1496`                      |
| `no_floating_window_permission`| 无悬浮窗权限   | (existing — used by spec25/spec26)      |

No new string resources required. The notification title reuses
`desktop_lyrics` and the body reuses the two toast strings to avoid
introducing a parallel "lock state" string set.

### 4.2 Icons

The notification icon uses the existing app icon resource
`app.media.app_icon` (already declared). No new media is added — the
notification visually distinguishes "locked" vs "unlocked" only via its
body text and an optional emoji prefix in the body string. Adding a
dedicated lock glyph is out of scope (would require a Pro media bundle
audit).

---

## 5. AppStorage keys

No new keys. spec27 reuses existing keys defined by spec26:

| Key                   | Type    | Default        | Writer                                          | Persisted? |
| --------------------- | ------- | -------------- | ----------------------------------------------- | ---------- |
| `desktopLyrics`       | boolean | false          | `LyricsSettingsViewModel.onDesktopLyricsChanged`| yes        |
| `lockDesktopLyrics`   | boolean | false          | `DesktopLyricsController.requestLock`           | yes        |
| `desktopLyricsYPercent`| number | 30             | `DesktopLyricsController.persistY`              | yes        |

The `lockDesktopLyrics` writer set expands by one: the notification-tap
entry point (`EntryAbility.onNewWant`) writes through
`DesktopLyricsController.requestLock`. Persistence is delegated; no new
writer of the AppStorage value itself.

---

## 6. Scenario-by-scenario verification

### Scenario 1 — master OFF → lock row disabled

- `LyricsSettingsViewModel.initFromModel` line 81:
  `model.lockDesktopLyrics.isEnabled = model.desktopLyrics.isOn`. When
  `desktopLyrics=false` after hydration, `isEnabled=false` → constructed
  `SwitcherRowViewModel.isEnabled=false`.
- `SwitcherRowViewModel.toggle()` guards with `if (this.isEnabled)`, so a
  tap is a no-op.
- `LyricsSettingsPage.ets:233` binds `enable: this.vm.lockDesktopLyricsVM.isEnabled`
  which the HDS card honors visually.
- **No code change**; reverified.

### Scenario 2 — master ON → user flips lock ON

- `LyricsSettingsPage` → `SwitcherRowViewModel.toggle()` →
  `onChange(true)` →
  `DesktopLyricsController.requestLock(true)`:
  1. `SettingsStore.save('lockDesktopLyrics', true)` (persistence)
  2. `applyLockedState()`:
     - `applyTouchableFromLock()` → `win.setWindowTouchable(false)` so
       touch passes through (step 4)
     - `DesktopLyricsLockNotificationController.publishLockedIcon()`
       (step 7 — notification bar shows locked icon)
  3. `DesktopLyricsWindow`'s `@StorageProp('lockDesktopLyrics')` flips
     → `controlPanelVisible && !lock` branch becomes false → panel
     hides (step 5)
  4. `promptAction.showToast({ message: app.string.desktop_lyrics_locked })`
     (step 6)
- The "panel hide on lock" condition is enforced by the existing build
  branch `if (this.controlPanelVisible && !this.lock)` in
  `DesktopLyricsWindow.ets:44/137`. Verified.

### Scenario 3 — Settings page unlocks

- Same path as scenario 2 with `val=false`. The toast resolves to
  `desktop_lyrics_unlocked`, `setWindowTouchable(true)` re-enables touch
  (step 4), `publishUnlockedIcon()` updates the notification (step 6).

### Scenario 4 — In-window Lock button

- `DesktopLyricsWindow.ets:163-170` already calls
  `this.controlPanelVisible = false; DesktopLyricsController.getInstance().requestLock()`
  (no-arg = `true`).
- `requestLock()` (now extended with default `value=true`) runs the same
  path as scenario 2. Settings-page row syncs automatically because
  `LyricsSettingsPage` reads through `vm.lockDesktopLyricsVM.isOn`, which
  is built from `model.lockDesktopLyrics.isOn`. We need one tiny addition
  to keep the model in sync with persistence: add a `@StorageProp` /
  `@Watch` on the model isn't possible directly, but
  `SwitcherRowViewModel.isOn` is `@Track`-ed — the controller's
  `SettingsStore.save` updates AppStorage. The Settings page does **not**
  observe AppStorage for the row's `isOn` (it reads
  `vm.lockDesktopLyricsVM.isOn`).

  To bridge that gap, the controller's `applyLockedState()` also nudges
  the live VM. Implementation: the `LyricsSettingsViewModel` registers
  itself as a `lockChangedListener` on the controller:

  ```ts
  // In DesktopLyricsController:
  private lockChangedListeners: ((v: boolean) => void)[] = []
  addLockChangedListener(l: (v: boolean) => void): void {
    if (this.lockChangedListeners.indexOf(l) === -1) {
      this.lockChangedListeners.push(l)
    }
  }
  removeLockChangedListener(l: (v: boolean) => void): void {
    const i = this.lockChangedListeners.indexOf(l)
    if (i !== -1) { this.lockChangedListeners.splice(i, 1) }
  }
  // inside applyLockedState():
  const v: boolean = AppStorage.get<boolean>('lockDesktopLyrics') ?? false
  for (const l of this.lockChangedListeners.slice()) {
    try { l(v) } catch (_e) { /* swallow */ }
  }

  // In LyricsSettingsViewModel.initFromModel — after constructing the lock VM:
  DesktopLyricsController.getInstance().addLockChangedListener(this.onExternalLockChanged)

  private onExternalLockChanged = (v: boolean): void => {
    if (this.lockDesktopLyricsVM.isOn !== v) {
      this.lockDesktopLyricsVM.isOn = v
    }
  }

  // and on destroy hook (aboutToDisappear of the page or VM disposal):
  DesktopLyricsController.getInstance().removeLockChangedListener(this.onExternalLockChanged)
  ```

  `aboutToDisappear` is acceptable here because it is the disposal
  callback (one-shot teardown), not a live-sync init — fully aligned with
  the spec rule that `aboutToAppear`/`aboutToDisappear` must not be used
  as live data sync points but can be used for one-shot setup/teardown.
  Live sync is still done through the listener registered above.

### Scenario 5 — Notification-bar unlock

- User taps the notification → system fires the `wantAgent` → the
  ability's `onNewWant` sees `parameters.spDesktopLyricsAction ==='toggleLock'`.
- Handler reads current `lockDesktopLyrics` and calls
  `DesktopLyricsController.requestLock(!cur)`. Same fan-out: persist +
  `applyLockedState()` (touchable + notification mirror) + toast.
- Settings page row syncs via the `lockChangedListener` plumbed in
  scenario 4.

### Scenario 6 — Lock persists across master OFF → ON

- `lockDesktopLyrics` is persisted independently via `SettingsStore`.
- Master OFF: `hide()` cancels the notification (no orphan "locked"
  notification while the window is gone). `lockDesktopLyrics`
  AppStorage value is preserved (we never clear it on master OFF).
- Master ON again: `show()` creates the window; after `applyGeometry()`
  and `applyTouchableFromLock()` we now also call the
  publish-locked/unlocked notification block (see edit 3.1 step 3). The
  position is restored from `desktopLyricsYPercent` by `applyGeometry()`.

### Scenario 7 — Drag → lock → cold start position restore

- Drag: spec26 `DesktopLyricsController.persistY()` writes
  `desktopLyricsYPercent` to `SettingsStore`. Verified.
- Lock: writes `lockDesktopLyrics` to `SettingsStore`. Verified.
- Cold start: `EntryAbility.onCreate` hydrates both keys from
  `SettingsStore.get(...)` into AppStorage (existing lines 197-198).
  `DesktopLyricsController.init` reads `desktopLyrics` (master) and, if
  true, calls `show()`. `show()` calls `applyGeometry()` (reads
  `desktopLyricsYPercent`) and `applyTouchableFromLock()` (reads
  `lockDesktopLyrics`) — both restored before the first frame renders.

---

## 7. Risks & mitigations

- **`@kit.NotificationKit` availability across API levels**: wrap every
  `notificationManager.publish/cancel` call in `try/catch`; on failure log
  a warning and proceed without the notification mirror. Lock behavior
  itself still works because the notification is a side-surface.
- **Want intent routing**: `onNewWant` may not fire if the ability is
  already foreground. Add a defensive same-process handler:
  `notificationManager.publish` is fired with an `actionButtons` array
  carrying the same `wantAgent`; tapping the notification body always
  brings the app forward and triggers `onNewWant`. If the ability never
  fully relaunches we still get the cold-start route via the existing
  AppStorage hydration. Tested-on-device verification deferred to the
  pipeline's self-test.
- **Listener leak on `LyricsSettingsViewModel`**: the listener registered
  in `initFromModel` must be removed when the page is destroyed. Hook
  into the page's `aboutToDisappear` (which is the documented one-shot
  teardown for `@Component`s) — that is the page's only acceptable use of
  a lifecycle callback in this plan.
- **Two writers + one notification surface**: the in-window Lock button,
  the Settings switch, and the notification tap all go through
  `DesktopLyricsController.requestLock(value)` — one writer, one
  publisher. No mirrored state, no parallel persistence paths.
- **Toast duplication on notification tap**: `requestLock` toasts. The
  notification tap routes through `requestLock`, so the user sees the
  toast even when their tap was on the notification (acceptable per spec
  scenario 5 step 4 "弹出提示"). The notification card itself is
  refreshed by `applyLockedState` so it doesn't disappear unexpectedly;
  the controller chooses publish-vs-cancel based on the master flag.

---

## 8. Wiring order (final)

```
EntryAbility.onCreate
  └ PersistentStorage.persistProp(... existing spec26 keys ...)
  └ SettingsStore.init
  └ AppStorage.setOrCreate(... hydration ...)
  └ AudioPlayerService.initContext
  └ MiniLyricsController.init
  └ NotificationLyricController.init
  └ MediaCardCloseButtonController.init
  └ MediaCardDesktopLyricsButtonController.init
  └ FloatingStatusBarLyricsController.init
  └ DesktopLyricsController.init
  └ DesktopLyricsLockNotificationController.init       ← NEW (spec27)

EntryAbility.onNewWant
  └ if (want.parameters.spDesktopLyricsAction === 'toggleLock')
       DesktopLyricsController.requestLock(!current)   ← NEW (spec27)

EntryAbility.onWindowStageDestroy
  └ FloatingStatusBarLyricsController.destroy
  └ DesktopLyricsController.destroy
  └ DesktopLyricsLockNotificationController.destroy    ← NEW (spec27)
```

---

## 9. Out of scope

- Custom lock-icon graphic — using existing app icon + body text. A
  dedicated 24-dp lock glyph would require Pro media bundling.
- Lock-state badge in the in-app status bar — spec27 limits the lock
  surface to (a) Settings switch, (b) in-window panel, (c) notification
  bar.
- Per-orientation lock memory — the spec scopes persistence to "当前
  设备" (current device); horizontal position is unmemorized by spec26
  by design and not revisited here.
- Cross-device sync of lock state via distributed AppStorage — explicitly
  scoped to "当前设备" in spec27 scenario 7.

---

## 10. Test plan (for the downstream verify / self-test stage)

1. Settings page: master OFF → lock row visibly disabled, tapping
   produces no toast and does not flip the icon.
2. Settings page: master ON → tap lock → toast "桌面歌词已锁定", panel
   on the in-window control disappears, notification card appears.
3. Drag the window with finger; tap unlock in Settings → window
   touchable again, toast "已解锁", notification card updates.
4. From a fresh launch, with `desktopLyrics=true` + `lockDesktopLyrics=true`
   persisted, the window appears at the persisted Y and is non-touchable
   from the first frame.
5. Toggle master OFF: notification card disappears. Toggle master ON:
   window reappears with restored lock+position; notification reappears.
6. Tap the notification card (lock indicator): window becomes touchable,
   toast "已解锁", Settings row flips OFF.
