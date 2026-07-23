# Logic Plan — spec9 (启动软件自动打开播放界面)

Target spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec9/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 0. Ground Truth (what already exists)

- UI row already wired.
  - `entry/src/main/ets/pages/LaboratoryPage.ets` renders the switch via
    `ItemSwitcherRowComponent({ vm: this.viewModel.autoOpenPlaybackVM })` (line 48).
  - `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets` owns
    `autoOpenPlaybackVM: SwitcherRowViewModel` (line 24), seeds it from
    `model.autoOpenPlaybackScreen`, and registers
    `onAutoOpenPlaybackChanged(isOn)` (lines 104-108) — the body is a TODO that
    only updates the in-memory model and logs. **No persistence. No AppStorage write.**
  - `entry/src/main/ets/model/LaboratoryModel.ets` defines `autoOpenPlaybackScreen: boolean`
    default `false` (line 7).
- Settings persistence pattern is already established.
  - `entry/src/main/ets/model/SettingsStore.ets` singleton: `init(context)` in
    `EntryAbility.onCreate`, `save(key, value)` writes `AppStorage.setOrCreate` +
    `preferences.putSync`, `flush()` in `EntryAbility.onBackground`, `get(key, default)`
    read on restore.
  - `EntryAbility.ets`:
    - Line 118-119: `SettingsStore.getInstance().init(this.context)`.
    - Lines 121-170: every persisted UI/player/audio flag is restored
      `AppStorage.setOrCreate(key, ss.get(key, default))`. There is **no** entry for
      `autoOpenPlaybackScreen` today.
    - Line 433: `SettingsStore.getInstance().flush()` in `onBackground`.
- Player-overlay state is owned by `MainPageViewModel`.
  - `showPlayer: boolean`, `playerProgress: number` (0=mini, 1=fullscreen),
    `initialShowQueue: boolean`, `playerSwipeOffset: number`.
  - `AppStorage.showPlayerOverlay` mirror is written whenever those change.
  - `openPlayerAnimated(animateTo)` / `openPlayerWithVelocity(v, animateTo)` /
    `openPlayerWithQueue(animateTo)` all require a UI animator callback that the
    Page obtains via `this.getUIContext().animateTo`. None of them are "open
    immediately without animation" — the post-spring state is `showPlayer = true`,
    `playerProgress = 1`, `playerSwipeOffset = mainScreenHeight`,
    `AppStorage.showPlayerOverlay = true`, plus
    `ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)` and
    `applyPlayerStatusBarColor()`.
  - `MiniPlayerContainer` mounts `PlayerPage()` only when
    `this.vm.showPlayer || this.vm.isPlayerSwiping || this.vm.playerProgress > 0.001`
    (line 109). Setting `showPlayer = true` + `playerProgress = 1` is sufficient
    to render the fullscreen player. Mini-player pill auto-fades via
    `getMiniPlayerAlpha()` (returns 0 once progress > ~0.94) so "迷你播放器隐藏"
    is satisfied without additional work.
- `MainPage.aboutToAppear` already calls `this.vm.initialize()`, sets up
  `navPathStack.setInterception`, initializes `miniPlayerVM` callbacks, and
  triggers the initial `syncMiniPlayerData(...)`. This is the only place where
  per-launch setup runs for the main page.
- String resources for the lab row:
  - `auto_open_playback_label` = "启动软件自动打开播放界面" (base 3256, zh 2264).
    No additional strings are required for this spec.

## 1. MVVM owner boundaries

Per the spec, three distinct flows exist; they all go through the same writer.

- **Model — `SettingsStore`**: owns persistence. Already the single source of
  truth for `boolean | number | string` app settings. New key
  `autoOpenPlaybackScreen` joins the same pattern.
- **App entry — `EntryAbility`**:
  - `onCreate`: seeds `PersistentStorage.persistProp('autoOpenPlaybackScreen', false)`
    (alongside the other persisted keys at lines 78-114) AND restores the
    SettingsStore copy into AppStorage (alongside lines 121-170). SettingsStore
    is the authoritative source on restart (PersistentStorage is a best-effort
    backup that EntryAbility already distrusts for these keys).
  - `onBackground`: already calls `SettingsStore.getInstance().flush()`; nothing
    to change.
- **ViewModel — `LaboratoryViewModel`**: owns the toggle action.
  `onAutoOpenPlaybackChanged(isOn)` writes `this.model.autoOpenPlaybackScreen`
  (already done) and calls `SettingsStore.getInstance().save('autoOpenPlaybackScreen', isOn)`.
  The `SwitcherRowViewModel.isOn` flip is already driven by
  `ItemSwitcherRowComponent` (View → VM) and the VM then persists. No UI work.
- **ViewModel — `MainPageViewModel`**: owns the player-overlay action.
  Adds `openPlayerImmediate()` (no animation) that sets the exact fullscreen
  state that the spring `onFinish` blocks already set (see below). Reuses
  existing state fields; adds no new fields.
- **Page — `MainPage`**: owns lifecycle wiring. `aboutToAppear` reads the
  restored `AppStorage.autoOpenPlaybackScreen`. When `true`, call
  `this.vm.openPlayerImmediate()` **after** the existing `initialize()`,
  `initMiniPlayer(...)`, and `syncMiniPlayerData(...)` block so the player page
  opens onto a VM that already has the correct song metadata / cover.
- **Page — `LaboratoryPage`**: already correct — delegates to its VM via
  `ItemSwitcherRowComponent`. No change.

Anti-patterns explicitly avoided:

- Persistence never moves into `LaboratoryPage` — the ViewModel owner path
  already exists for every other toggle in this page (e.g. `saltUiMaterialVM`,
  `liquidGlassVM`, `lyricsEffect3DVM`), which go through `SettingsStore` via
  their own VM callbacks. The existing `getAlbumArt`/`lyricsUIEffect3D` TODOs
  are separate concerns and are **not** expanded in this plan — spec9 only
  touches `autoOpenPlaybackScreen`.
- `aboutToAppear` is only used to read the **already-persisted** value at
  launch. No live sync. The setting change path never goes through
  `aboutToAppear`.
- No mirror state in `MainPageViewModel` for `autoOpenPlaybackScreen`.
  AppStorage is the single source of truth; the only consumer is
  `MainPage.aboutToAppear`.
- No fake default that differs from the persisted default — all three tiers
  (model, PersistentStorage, SettingsStore restore) use `false`.

## 2. Change list

### 2.1 `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets`

Imports — add at the top (next to the existing `LaboratoryModel` import):

```ts
import SettingsStore from '../model/SettingsStore'
```

Replace `onAutoOpenPlaybackChanged` (lines 104-108):

```ts
private onAutoOpenPlaybackChanged(isOn: boolean): void {
  this.model.autoOpenPlaybackScreen = isOn
  SettingsStore.getInstance().save('autoOpenPlaybackScreen', isOn)
}
```

Also, in the constructor / `initChildViewModels`, seed the child
`SwitcherRowViewModel` from the restored AppStorage value so re-entering the
lab page after a persist reflects the stored value even though the parent page
re-constructs the VM on every mount:

```ts
// LaboratoryViewModel constructor body — before initChildViewModels()
const persisted = AppStorage.get<boolean>('autoOpenPlaybackScreen')
if (persisted !== undefined) {
  this.model.autoOpenPlaybackScreen = persisted
}
```

(This mirrors the pattern `MainPageViewModel` uses for `displaySongCoverInList`
at line 97 — seed from AppStorage so the first frame is correct.)

Scenes 2 and 4 are both covered: toggling the switch calls
`SwitcherRowViewModel.toggle()` → `onChange` → `onAutoOpenPlaybackChanged(isOn)`
→ persisted immediately. Re-entry re-reads from AppStorage.

### 2.2 `entry/src/main/ets/entryability/EntryAbility.ets`

Two small additions inside `onCreate`.

Near line 90 (the "用户界面设置持久化" `PersistentStorage.persistProp` block),
add one more line:

```ts
PersistentStorage.persistProp('autoOpenPlaybackScreen', false)
```

Near line 127 (the `AppStorage.setOrCreate('displayAddToPlayNext', ...)` line,
inside the "从 Preferences 恢复设置" block), add:

```ts
AppStorage.setOrCreate('autoOpenPlaybackScreen',
  ss.get('autoOpenPlaybackScreen', false) as boolean)
```

Placement rationale: this spec is experimental-lab scope, but SettingsStore
is global and EntryAbility already restores all lab-adjacent flags here.
Keeping the two additions adjacent to the UI group is fine — it avoids
introducing a new section for a single key.

No change to `onBackground`; the existing `SettingsStore.getInstance().flush()`
already persists the newly-added key.

### 2.3 `entry/src/main/ets/viewmodel/MainPageViewModel.ets`

Add a new public method in the "Player Operations" section (near
`openPlayerAnimated` at line 1026). Sets the exact fullscreen-player terminal
state without animation — this is what scene 3 needs:

```ts
// Open the player overlay immediately without animation. Used at app launch
// when the Laboratory "启动软件自动打开播放界面" setting is enabled. Mirrors the
// post-spring terminal state of openPlayerAnimated — status bar reconcile,
// wake-lock, and AppStorage mirror are all applied.
openPlayerImmediate(): void {
  this.animGeneration++
  this.showPlayer = true
  this.isPlayerSwiping = false
  this.playerSwipeOffset = this.mainScreenHeight
  this.playerProgress = 1
  this.initialShowQueue = false
  this.miniPullOffsetY = 0
  AppStorage.setOrCreate('showPlayerOverlay', true)
  AppStorage.setOrCreate('playerCurrentPage', 0)
  ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)
  this.applyPlayerStatusBarColor()
}
```

Notes:
- `animGeneration++` preserves the existing "newer animation wins" invariant
  used by the three spring-based openers — even though this method is
  synchronous, any in-flight animation (e.g. a spring started by another code
  path) is invalidated.
- Uses `this.mainScreenHeight` — at `aboutToAppear` time it is 0, which is the
  same initial value the spring openers see. ArkUI's `onAreaChange` on the
  outer `Stack` (MainPage.ets line 518) fires during layout after
  `aboutToAppear` and updates it via `updateScreenSize`. Because
  `MiniPlayerContainer` renders `PlayerPage` whenever
  `showPlayer || isPlayerSwiping || playerProgress > 0.001`, and the fullscreen
  morph height derives from `playerProgress` (already 1), the 0→measured
  transition of `mainScreenHeight` does not un-mount the player or change its
  visual "fullscreen" state. Setting `playerSwipeOffset = mainScreenHeight`
  keeps the value consistent with the spring-open terminal state; when
  `onAreaChange` later sets `mainScreenHeight`, the subsequent re-render still
  holds `playerProgress = 1` so the player stays fullscreen.

### 2.4 `entry/src/main/ets/pages/main/MainPage.ets`

In `aboutToAppear` (line 291), at the **end** of the method (after the final
`this.vm.syncMiniPlayerData(...)` at line 373-374), append:

```ts
// Spec9 Scene 3: if the Laboratory "启动软件自动打开播放界面" is on, open the
// fullscreen player immediately after UI/VM init. No animation — matches the
// spec ("应用启动后自动展开播放界面"), and avoids the one-frame flash of the
// main page.
if (AppStorage.get<boolean>('autoOpenPlaybackScreen') === true) {
  this.vm.openPlayerImmediate()
}
```

Rationale:
- Reads the AppStorage value restored by EntryAbility (section 2.2). No direct
  Preferences read — Page must not touch persistence.
- Placed after `vm.initialize()` and `syncMiniPlayerData` so the player page
  has the correct current-song metadata when it mounts via
  `MiniPlayerContainer`'s conditional.
- No navigation stack interaction — the player overlay is a
  `Stack`-mounted child of `MainPage`, not an `NavDestination`, so it does not
  affect `navPathStack`.
- No guard on song list presence: the spec says "显示完整的播放页面内容";
  the player page handles the empty-song state on its own. If no song is
  restored, PlayerPage still shows the shell.

### 2.5 No change

- `LaboratoryModel.ets` — already has `autoOpenPlaybackScreen: boolean` default `false`.
- `LaboratoryPage.ets` — delegates to `viewModel.autoOpenPlaybackVM` via the
  existing `ItemSwitcherRowComponent`.
- `PlayerPage.ets` — receives `@StorageProp('showPlayerOverlay')` /
  other AppStorage drivers already in place. No explicit open hook needed
  because the VM state flip drives the mount.
- Resource strings — `auto_open_playback_label` already exists.

## 3. Binding / Refresh paths per spec scenario

- **Scene 1 — default off, launch normally**
  - EntryAbility restores `autoOpenPlaybackScreen=false` into AppStorage.
  - `MainPage.aboutToAppear` reads `false` → does not call `openPlayerImmediate()`.
  - Result: main page + mini-player pill as today.
- **Scene 2 — turn on from lab**
  - `LaboratoryPage` toggle → `SwitcherRowViewModel.toggle()` → `onChange(true)`
    → `LaboratoryViewModel.onAutoOpenPlaybackChanged(true)` →
    `SettingsStore.save('autoOpenPlaybackScreen', true)` → AppStorage + prefs
    memory cache are both updated. Disk flush happens in
    `EntryAbility.onBackground` (already wired).
  - Re-entering `LaboratoryPage` re-constructs `LaboratoryViewModel`, which now
    seeds `this.model.autoOpenPlaybackScreen` from the AppStorage value and
    therefore the switch renders as on.
- **Scene 3 — on, then launch**
  - EntryAbility restores `autoOpenPlaybackScreen=true` from SettingsStore into
    AppStorage.
  - `MainPage.aboutToAppear` reads `true` → calls
    `vm.openPlayerImmediate()` → `showPlayer=true`, `playerProgress=1`,
    `showPlayerOverlay=true` → `MiniPlayerContainer` mounts `PlayerPage`
    fullscreen; mini-player pill opacity falls to 0 by the existing
    `getMiniPlayerAlpha()` step; status bar color reconciles via
    `applyPlayerStatusBarColor()`.
- **Scene 4 — turn off from lab**
  - Same writer path as Scene 2 with `isOn=false`. SettingsStore + AppStorage
    updated immediately.
- **Scene 5 — off, then launch**
  - Same as Scene 1 (default path). No regression because the added code path
    short-circuits on `false`.

## 4. Verification

- Static: `hvigorw assembleHap` (the command used by the pipeline's Stage 5).
  Only ArkTS files are touched; no resource additions, no new oh-package deps.
- Manual:
  - Fresh install → 实验室开关 off → launch → main page shows, player not open
    (Scene 1/5).
  - Toggle 启动软件自动打开播放界面 on → quit → relaunch → player opens
    fullscreen, mini-player hidden (Scene 3).
  - Close player (back / swipe down) → navigate app → exit → relaunch → player
    opens fullscreen again (persistence confirmed across process death).
  - Toggle off → quit → relaunch → main page + pill (Scene 5).
  - Restart while a song is restored from the playback state → player opens
    on that song (metadata path: `syncMiniPlayerData` runs before
    `openPlayerImmediate`).

## 5. Out of scope

- Other `// TODO: Persist with data preferences` sites in `LaboratoryViewModel`
  (`getAlbumArt`, `lyricsUIEffect3D`, `saltUiMaterial`, `liquidGlass`) — those
  are separate spec items. Spec9 only persists `autoOpenPlaybackScreen`.
- Any animation tuning of the auto-open. Spec says "自动展开", no timing
  requirement — the instant-set path matches the intent and avoids the
  one-frame flash that a spring-from-0 would introduce at cold-start.
- Opening the player with the queue visible. Spec scene 3 says "显示完整的
  播放页面内容", not "队列页". `initialShowQueue = false` mirrors the default
  `openPlayerAnimated` behaviour.
- Interaction with immersion mode / hideStatusBar (owned by spec4). The new
  opener calls `applyPlayerStatusBarColor()` which is the same status-bar
  reconciliation used by every other open path, so any composition with
  spec4's reconcile flow continues to work.
