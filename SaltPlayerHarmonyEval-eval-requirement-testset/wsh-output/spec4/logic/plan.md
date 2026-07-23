# Logic Plan — spec4 (沉浸模式)

Target: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec4/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 0. Ground Truth (what already exists)

- `AppStorage` key `immersionMode` is already persistence-backed
  (`EntryAbility.onCreate` line 81: `PersistentStorage.persistProp('immersionMode', false)`,
  restored line 123 from `SettingsStore`). Default `false`.
- `AppStorage` key `hideStatusBar` is persisted the same way (lines 82 / 124).
- `SystemBarModel` (`entry/src/main/ets/model/SystemBarModel.ets`) owns the window and
  exposes `setStatusBarVisible(boolean)`, called today by `PlayerPage.aboutToAppear/Disappear`
  and `PlayerPageViewModel.toggleImmersionMode / syncImmersionFromStorage`.
- `PlayerPageViewModel` already has `toggleImmersionMode()` (writes AppStorage + SettingsStore
  + calls `SystemBarModel.setStatusBarVisible(!next)`) and `syncImmersionFromStorage(value)`.
- `PlayerPage.ets`:
  - Has `@StorageProp('immersionMode') @Watch('onImmersionChanged')` → syncs VM.
  - Collapses top bar, mini-lyrics row, lyrics settings bar, time bar, and icon panel via
    `this.vm.immersionMode`.
  - `ImmersionModeButton` in MusicInfoPanel already calls `this.vm.toggleImmersionMode()`.
- `UserInterfaceViewModel.setImmersionMode(value)` exists but only writes the VM flag,
  the model, and `SettingsStore.save('immersionMode', value)` — it does NOT write
  `AppStorage.setOrCreate` and does NOT reconcile the system bar.
- `UserInterfacePage.ets` renders the `immersion_mode` `HdsListItemCard` (lines 187-201)
  with a hard-coded `SuffixSwitch({ isCheck: false, onChange: (_val) => {} })` — live-dead.
- `PlayerPage` play/pause long-press (line ~1756-1760) currently calls
  `this.vm.togglePlayPause()` — spec4 scenes 1.2 / 2.2 / 3.2 / 4 require it to toggle
  immersion mode (with toast) instead.
- No code currently reads `hideStatusBar` into the window — scene 3 "status bar stays
  hidden" is not honored today.

## 1. MVVM owner boundaries

- **View — `UserInterfacePage.ets`**: UI only. Add `@StorageLink('immersionMode')`
  on the struct, bind `HdsListItemCard.SuffixSwitch.isCheck` to it, delegate `onChange`
  to `vm.setImmersionMode(val)`. No persistence, no system-bar calls.
- **View — `PlayerPage.ets`**: UI only. Long-press of the play/pause button delegates to
  `vm.toggleImmersionModeWithToast()`. `aboutToAppear` / `aboutToDisappear` delegate
  system-bar reconciliation to `SystemBarModel`.
- **ViewModel — `UserInterfaceViewModel.ets`**: Owns the user-facing action.
  `setImmersionMode(v)` writes VM + model + AppStorage + SettingsStore and asks
  `SystemBarModel` to reconcile. `hideStatusBarVM` callback also writes AppStorage
  and asks `SystemBarModel` to reconcile.
- **ViewModel — `PlayerPageViewModel.ets`**: Owns the player-surface action.
  `toggleImmersionMode()` writes VM + AppStorage + SettingsStore and reconciles the
  system bar. New `toggleImmersionModeWithToast()` wraps it and shows a toast.
  `syncImmersionFromStorage(v)` reconciles the system bar instead of calling
  `setStatusBarVisible(!v)` directly.
- **Model — `SystemBarModel.ets`**: Owns the window. Adds
  `reconcileStatusBarVisibility()` that reads both `immersionMode` and `hideStatusBar`
  from AppStorage and calls `setSpecificSystemBarEnabled('status', !(immersion || hide))`.
  The existing `setStatusBarVisible` is kept for backwards compatibility but no code
  outside the Model should call it after this spec.
- **App entry — `EntryAbility.ets`**: After `SystemBarModel.initWindow(mainWindow)`
  (line 358), call `SystemBarModel.getInstance().reconcileStatusBarVisibility()` so
  the initial bar state honors the persisted flags before the first page renders.

Anti-patterns explicitly avoided:

- No mirror state for immersion — `AppStorage.immersionMode` is the single source of truth;
  `PlayerPageViewModel.immersionMode` / `UserInterfaceViewModel.immersionMode` are
  @Track reflections that are written by the same action paths and resynced on Watch.
- `aboutToAppear` is not used as live sync — `PlayerPage` already relies on
  `@StorageProp('immersionMode') @Watch` for that.
- No page writes `setSpecificSystemBarEnabled` — only `SystemBarModel` does.

## 2. Change list

### 2.1 `entry/src/main/ets/model/SystemBarModel.ets`

Add a public method:

```ts
reconcileStatusBarVisibility(): void {
  if (!this.mainWindow) return
  const immersion = (AppStorage.get<boolean>('immersionMode') ?? false)
  const hide      = (AppStorage.get<boolean>('hideStatusBar') ?? false)
  const shouldHide = immersion || hide
  try {
    this.mainWindow.setSpecificSystemBarEnabled('status', !shouldHide)
    hilog.info(0, TAG, 'reconcile: immersion=%{public}s hide=%{public}s visible=%{public}s',
      immersion.toString(), hide.toString(), (!shouldHide).toString())
  } catch (e) {
    hilog.warn(0, TAG, 'reconcile failed: %{public}s', (e as Error).message)
  }
}
```

Keep existing `setStatusBarVisible(visible)` intact; new callers use `reconcile…()`.

### 2.2 `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`

- In `setImmersionMode(value)`:
  - Keep existing writes to `this.immersionMode`, `this.model.immersionMode`,
    `SettingsStore.save('immersionMode', value)`.
  - Add `AppStorage.setOrCreate<boolean>('immersionMode', value)` so
    PlayerPage's `@StorageProp('immersionMode') @Watch` fires when the user flips
    the switch from the settings page (scene 1.1 / 2.1 / 3.1).
  - Add `SystemBarModel.getInstance().reconcileStatusBarVisibility()` at the end.
- In the `hideStatusBarVM` constructor callback (lines 96-98): change the body from
  only `SettingsStore.save('hideStatusBar', val)` to also
  `AppStorage.setOrCreate<boolean>('hideStatusBar', val)` +
  `SystemBarModel.getInstance().reconcileStatusBarVisibility()`. This lets scenes 2/3
  do the right thing when the user flips either setting.
- Import `SystemBarModel` from `'../model/SystemBarModel'` at top of file.

### 2.3 `entry/src/main/ets/pages/UserInterfacePage.ets`

- Add to the `@Component struct UserInterfacePage` body (next to the existing
  `@StorageLink('playerKeepScreenOn')`):

  ```ts
  @StorageLink('immersionMode') immersionMode: boolean = false
  ```

  `@StorageLink` (not `@StorageProp`) so the page both reads external writes AND
  propagates local changes through the switch.
- Replace the immersion_mode `HdsListItemCard` block (lines 187-201). The new
  `SuffixSwitch`:

  ```ts
  suffixItem: new SuffixSwitch({
    isCheck: this.immersionMode,
    onChange: (val: boolean) => {
      if (this.immersionMode !== val) {
        this.vm.setImmersionMode(val)
      }
    }
  }),
  ```

  (Pattern mirrors the existing `playerKeepScreenOn` row at lines 271-286.)

### 2.4 `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets`

- Import `promptAction` from `'@kit.ArkUI'` if not already imported (see
  `MainPageViewModel.ets` for the existing convention).
- In `toggleImmersionMode()` (lines 717-724): replace
  `SystemBarModel.getInstance().setStatusBarVisible(!next)` with
  `SystemBarModel.getInstance().reconcileStatusBarVisibility()` so Scene 3 (immersion
  off but `hideStatusBar=true`) keeps the bar hidden.
- In `syncImmersionFromStorage(value)` (lines 729-733): same replacement.
- Add:

  ```ts
  toggleImmersionModeWithToast(): void {
    this.toggleImmersionMode()
    const msg: Resource = this.immersionMode
      ? $r('app.string.immersion_mode_on')
      : $r('app.string.immersion_mode_off')
    promptAction.showToast({ message: msg })
  }
  ```

### 2.5 `entry/src/main/ets/pages/PlayerPage.ets`

- In `PlayerControlBar()` (play/pause button, ~line 1755-1760): change the
  `LongPressGesture().onAction` body from `this.vm.togglePlayPause()` to
  `this.vm.toggleImmersionModeWithToast()`. Short-click still runs
  `togglePlayPause()`. This fulfils scene 1.2 / 2.2 / 3.2 and the toast in scene 4.
- `aboutToAppear` (line 333-335): replace
  `if (this.immersionMode) SystemBarModel.getInstance().setStatusBarVisible(false)`
  with `SystemBarModel.getInstance().reconcileStatusBarVisibility()`. Covers the case
  where `hideStatusBar=true` but `immersionMode=false` at player open.
- `aboutToDisappear` (line 377): replace
  `SystemBarModel.getInstance().setStatusBarVisible(true)` with
  `SystemBarModel.getInstance().reconcileStatusBarVisibility()`. Otherwise leaving
  the player forces the status bar visible even when `hideStatusBar=true`.

### 2.6 `entry/src/main/ets/entryability/EntryAbility.ets`

In `onWindowStageCreate` (lines 354-361), right after the `SystemBarModel.getInstance().initWindow(mainWindow)` call, add:

```ts
SystemBarModel.getInstance().reconcileStatusBarVisibility()
```

so the initial status bar state on app launch honors persisted `immersionMode` and
`hideStatusBar` flags (scene 5 default false, plus respect of either flag if the
user had flipped it earlier).

### 2.7 Resource strings

Add two keys to `entry/src/main/resources/base/element/string.json`,
`entry/src/main/resources/zh/element/string.json`, and
`entry/src/main/resources/ug/element/string.json` (placed next to the existing
`immersion_mode` / `immersion_mode_explain` entries):

- `immersion_mode_on`
  - base (English): `Immersion mode on`
  - zh: `沉浸模式已开启`
  - ug: base fallback is acceptable if no translation exists.
- `immersion_mode_off`
  - base (English): `Immersion mode off`
  - zh: `沉浸模式已关闭`
  - ug: base fallback.

## 3. Binding / Refresh paths per spec scenario

- **Scene 1 (enter immersion)**:
  - 1.1 switch on settings page → `UserInterfaceViewModel.setImmersionMode(true)` →
    AppStorage `immersionMode=true` + SettingsStore + `SystemBarModel.reconcile` →
    `PlayerPage.@StorageProp @Watch('onImmersionChanged')` → `vm.syncImmersionFromStorage(true)`.
    Status bar hides (`immersion||hide` = true). All player conditional builders collapse
    via `this.vm.immersionMode` (opacity/height/animation already wired).
  - 1.2 long-press play/pause → `PlayerPageViewModel.toggleImmersionModeWithToast()` →
    same writer path + toast.
  - 1.3 MusicInfoPanel `ImmersionModeButton` → `vm.toggleImmersionMode()` → same.
- **Scene 2 (exit, hide off)**: writer sets immersion=false; reconcile sees both false,
  status bar visible; player UI restores.
- **Scene 3 (exit, hide on)**: writer sets immersion=false; reconcile sees hide=true,
  status bar stays hidden; player UI otherwise restores normally.
- **Scene 4**: only the long-press entry point shows the toast (via dedicated VM method).
- **Scene 5**: `EntryAbility.onCreate` seeds defaults; `onWindowStageCreate` reconcile
  yields visible status bar; VM defaults `immersionMode=false` so nothing collapses.

## 4. Verification

- Static: `hvigorw build` (same command the pipeline's Stage 5 uses). Plan touches
  only ArkTS files and string resources — no new gradle or oh-package deps.
- Manual checks after install:
  - Settings → 用户界面 → 沉浸模式 toggles status bar and player UI both ways.
  - Player long-press of play/pause: toast fires, immersion flips, short click still
    plays/pauses.
  - Panel 沉浸模式 button stays in sync after either of the above.
  - Toggle 沉浸模式 off while 隐藏状态栏 is on: status bar remains hidden.
  - Restart app with 沉浸模式=true persisted: status bar hidden before first render.

## 5. Out of scope

- `hideStatusBar` UI row. UserInterfacePage does not currently render that switch;
  spec4 does not ask for it. Adding it would be a separate spec. The VM callback is
  still upgraded so any existing / future UI surface writing `hideStatusBar` through
  `UserInterfaceViewModel` behaves correctly.
- Visual animation timing of the collapsing elements. Existing `.animation({ duration: 300 })`
  modifiers on the conditional rows already satisfy the "以动画方式隐藏 / 恢复" requirement.
- Lyrics settings bar, Hi-Res badge, and "迷你歌词 / 音频信息" hiding — already wired to
  `this.vm.immersionMode`. No further change needed for spec coverage.
