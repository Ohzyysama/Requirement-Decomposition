# Plan: 在列表中显示封面 (displaySongCover)

Implementation plan for SPEC `/Users/moriafly/GitHub/SaltPlayerHarmony/SPEC/plan.md` against HarmonyOS project `/Users/moriafly/GitHub/SaltPlayerHarmony`.

## 1. Ground Truth — What Already Exists

Writer path (Settings → persistence) is complete:

- `entry/src/main/ets/pages/UserInterfacePage.ets` — toggles `this.vm.displaySongCoverVM` (line 300–320 of the "Song List" section).
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` — `displaySongCoverVM` change callback persists the value through the Model surface:
  - Line 110–112: `new SwitcherRowViewModel(this.model.displaySongCover, (val) => SettingsStore.getInstance().save('displaySongCover', val))`.
  - On construction, line 86–89 seeds the switch from `AppStorage.get<boolean>('displaySongCover')`.
- `entry/src/main/ets/model/SettingsStore.ets` — `save(key, value)` writes to both `AppStorage.setOrCreate(...)` and the `preferences` memory cache; `flush()` is invoked on `onBackground` (disk write).
- `entry/src/main/ets/entryability/EntryAbility.ets`
  - Line 84: `PersistentStorage.persistProp('displaySongCover', true)` — default on, persisted across restarts.
  - Line 125: `AppStorage.setOrCreate('displaySongCover', ss.get('displaySongCover', true) as boolean)` — restores from Preferences at startup (primary source, as PersistentStorage is flagged unreliable).

Reader path is the gap. Consumer ViewModels expose a local `displaySongCoverInList` that is read from AppStorage only at construction, with no live sync. Four consumer pages hard-code `showCover: true` and do not consult the setting at all.

Consumer audit (from grep over `entry/src/main/ets/`):

| Page | Binding line | Current state |
|---|---|---|
| `pages/main/MainPage.ets` | 1095 | `showCover: true` hard-coded — BUG, ignores setting |
| `pages/ArtistContentPage.ets` | 145 | `showCover: true` hard-coded — BUG |
| `pages/FolderPathPage.ets` | 51 | `showCover: true` hard-coded — BUG |
| `pages/SearchAllSongsPage.ets` (via `SearchAllSongsViewModel.createSongItemViewModel`) | VM line 280 | `showCover: true` hard-coded — BUG |
| `pages/FolderContentPage.ets` | 324 | `showCover: this.viewModel.displaySongCoverInList` — wired to VM, VM reads AppStorage only at construction (line 52) — mounted-page refresh broken |
| `pages/PlaylistContentPage.ets` | 174 | wired to VM (line 42) — same mounted-page refresh gap |
| `pages/PlaylistSearchPage.ets` | 180 | wired to VM (line 65) — same mounted-page refresh gap |
| `pages/AlbumContentPage.ets` | 139 | `showCover: false, showTrackNumber: true` — intentional Android parity (track numbers displayed instead); `SongItemComponent` lets `showTrackNumber` win over `showCover`. No change required. |

Android equivalents in `SPA` treat this as a single app-level preference that any song-list composable consumes; the HarmonyOS consumers must do the same.

## 2. MVVM Owner Boundary

| Concern | Owner | Notes |
|---|---|---|
| Persistence and shared truth | `SettingsStore` + AppStorage key `displaySongCover` | Already writing to both paths; do not duplicate. |
| Action (toggle) | `UserInterfaceViewModel.displaySongCoverVM` | Unchanged; writer is correct. |
| Per-page reactive state | Each consumer ViewModel's `displaySongCoverInList` | @Track field, updated via a ViewModel method called by the Page-layer @StorageProp @Watch bridge. Matches the existing `playerKeepScreenOn` / `scanVersion` / `isPlaying` bridging pattern (UserInterfacePage line 46, MainPage lines 83–87, etc.). |
| UI wiring and lifecycle | Each Page (`@StorageProp('displaySongCover') @Watch(...)`) | One-line bridge per page; page forwards the value into its VM. `aboutToAppear` is NOT used as a sync source. |
| Default value at first launch | `PersistentStorage.persistProp('displaySongCover', true)` in `EntryAbility.onCreate` | Already present. |

Do not push persistence into Pages. Do not introduce a mirror of the persisted key under a new name. Do not rely on `aboutToAppear` for sync — it only fires when the Page is first mounted, which would break mounted-page refresh (scenario 2 and 3 require mounted lists to update live).

## 3. Implementation Tasks

### 3.1 Consumer ViewModels — expose live reader + setter

For each ViewModel below, add (or confirm) an `@Track public displaySongCoverInList` field and a public setter method so the Page-layer bridge can forward AppStorage writes into the ViewModel. Construct default from `AppStorage.get<boolean>('displaySongCover') ?? true` so initial render matches persisted value.

- `entry/src/main/ets/viewmodel/MainPageViewModel.ets`
  - Line 94: change initializer from `true` to `(AppStorage.get<boolean>('displaySongCover') ?? true)` (match the pattern already used in `FolderContentPageViewModel` line 52).
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.
  - Leave the existing `changeDisplaySetting('displaySongCoverInList', value)` path untouched (it is driven by SongSortDialog's local toggle, which is a parallel UX and out of scope for this spec).

- `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets`
  - Line 52 initializer already correct.
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.

- `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets`
  - Line 42 initializer already correct.
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.

- `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets`
  - Line 65 initializer already correct.
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.

- `entry/src/main/ets/viewmodel/ArtistContentViewModel.ets`
  - Add `@Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)`.
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.
  - In `loadArtistData()` (line 163) replace `vm.showCover = true` with `vm.showCover = this.displaySongCoverInList`. Because the Artist page keeps a cached array of pre-built `SongItemViewModel` instances in `this.songs`, the setter must also walk the cached array and update each `vm.showCover`, then reload the LazyDataSource so mounted pages re-render. Add a helper:
    ```
    setDisplaySongCoverInList(value: boolean): void {
      if (this.displaySongCoverInList === value) return
      this.displaySongCoverInList = value
      for (const vm of this.songs) vm.showCover = value
      this.songDataSource.reload(Array.from(this.songs))
    }
    ```

- `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets`
  - Add `@Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)`.
  - Add `setDisplaySongCoverInList(value: boolean): void { this.displaySongCoverInList = value }`.
  - In `createSongItemViewModel` (line 277) change `showCover: true` to `showCover: this.displaySongCoverInList`.

- `entry/src/main/ets/viewmodel/FolderPathViewModel.ets` (new)
  - Open the file, add the same `@Track` field and setter.
  - In `createSongItemViewModel` (invoked from `FolderPathPage` line 49), thread `showCover: this.displaySongCoverInList` through. Verify exact function signature before editing.

### 3.2 Consumer Pages — bridge AppStorage into the ViewModel

Pattern (matches `UserInterfacePage` line 46 and the several `@StorageProp @Watch` bridges already on `MainPage`):

```
@StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged') storedDisplaySongCover: boolean = true

onDisplaySongCoverChanged(): void {
  this.<vm-field>.setDisplaySongCoverInList(this.storedDisplaySongCover)
}
```

Apply to:

- `entry/src/main/ets/pages/main/MainPage.ets`
  - Add the bridge (VM field is `this.vm`).
  - Line 1095: change `showCover: true` → `showCover: this.vm.displaySongCoverInList`.
  - Keep the existing `displaySongCoverInList` SongSortDialog pathway unchanged.

- `entry/src/main/ets/pages/ArtistContentPage.ets`
  - Add the bridge (VM field is `this.viewModel`).
  - Line 145: change `showCover: true` → `showCover: this.viewModel.displaySongCoverInList`.

- `entry/src/main/ets/pages/FolderContentPage.ets`
  - Add the bridge; body calls `this.viewModel.setDisplaySongCoverInList(this.storedDisplaySongCover)`. Line 324 binding already correct.

- `entry/src/main/ets/pages/FolderPathPage.ets`
  - Add the bridge; line 51: replace `showCover: true` with `showCover: this.viewModel.displaySongCoverInList`.

- `entry/src/main/ets/pages/PlaylistContentPage.ets`
  - Add the bridge; line 174 already reads the VM field — no binding change.

- `entry/src/main/ets/pages/PlaylistSearchPage.ets`
  - Add the bridge; line 180 already correct.

- `entry/src/main/ets/pages/SearchAllSongsPage.ets`
  - Add the bridge; line 229 calls `createSongItemViewModel` which now reads the VM's `displaySongCoverInList`, so no binding change required at the page level.

`AlbumContentPage`: no change. Track-number mode (`showTrackNumber: true`) overrides `showCover` in `SongItemComponent` build logic, matching Android.

### 3.3 Settings page correctness check

`UserInterfaceViewModel.displaySongCoverVM` already persists via `SettingsStore`. Confirm by reading the switch value off `this.model.displaySongCover.isOn` at construction (line 87–89 already handles this). No changes needed.

Edge case: the `UserInterfacePage` also has the same "mounted-page refresh" concern — if the user opens `UserInterfacePage`, backgrounds the app, and the stored value changes via another edit path, the switch must still reflect the current value. The settings page is the only writer in scope, so this is unnecessary. Leave alone.

## 4. Writer → Reader → Binding → Refresh Summary

| Step | Path |
|---|---|
| Writer (user action) | `UserInterfacePage` switch onChange → `UserInterfaceViewModel.displaySongCoverVM.toggle()` → callback → `SettingsStore.save('displaySongCover', val)` |
| Persistence | `SettingsStore.save` writes `AppStorage.setOrCreate('displaySongCover', val)` and `preferences.putSync('displaySongCover', val)`; disk flush happens on `onBackground`. PersistentStorage mirror (`persistProp`) auto-covers the AppStorage path too. |
| Reader (shared truth) | AppStorage key `displaySongCover` |
| Binding (per consumer page) | Page-level `@StorageProp('displaySongCover') @Watch(handler)`; handler calls `vm.setDisplaySongCoverInList(value)`; UI reads `vm.displaySongCoverInList` via `SongItemViewModel.create({ showCover: vm.displaySongCoverInList, ... })`. Because the builder body re-runs when the @Track field changes, LazyForEach items re-instantiate with the new `showCover` value. |
| Refresh (mounted pages) | `@Watch` fires whenever AppStorage value changes, even on pages mounted beneath the NavPathStack top. Each mounted consumer receives the update independently. No aboutToAppear reliance. |
| Refresh (Artist page specifically) | `ArtistContentViewModel.setDisplaySongCoverInList` walks cached `this.songs` and calls `songDataSource.reload` because its `SongItemViewModel` instances are long-lived (stored inside a typed array) rather than re-created per build like the other pages. |
| Cold start (scenario 4) | `EntryAbility.onCreate` runs `PersistentStorage.persistProp('displaySongCover', true)` and overwrites with `ss.get('displaySongCover', true)`. Consumer VMs read `AppStorage.get('displaySongCover')` in their field initializers, so first-frame render matches persisted value. |

## 5. Verification Plan

### 5.1 Static / compile

- Build the HAP with hvigor: `hvigor --mode module -p module=entry@default -p product=default assembleHap` from the project root. Expect zero ArkTS errors. Run after each file batch to catch type drift.
- `arkts-lint` / editor static check on edited files. The @StorageProp bridge must declare a default (`true`) to match the persisted default.

### 5.2 Functional (manual on device, Android parity checklist)

- **Scenario 1 (default on)** — Fresh install. All list pages in the table above should show covers. AlbumContent still shows track numbers (by design).
- **Scenario 2 (toggle off live)** — From MainPage, open two song-list pages one after another (e.g., push PlaylistContentPage). Without closing them, go to Settings → UI → toggle "在列表中显示歌曲封面" off. Pop back through the stack; each mounted list must show no covers immediately. Open ArtistContentPage / FolderContentPage / FolderPathPage / SearchAllSongsPage / PlaylistSearchPage in turn — all must show no covers without needing a re-entry.
- **Scenario 3 (toggle on live)** — Inverse of scenario 2.
- **Scenario 4 (persistence)** — Toggle off → background app for >1 s (triggers `flush()`) → kill process → relaunch. Settings switch reads off; song lists render without covers.
- **Parallel scroll check** — While a LazyForEach song list is scrolling, toggle the switch. The visible rows should swap layout without crash (cover → track-number-or-blank transition). Because `showTrackNumber` is false on these pages, the branch falls through and the 16dp left padding + song text start directly; confirm against Android parity screenshots.
- **SongSortDialog regression** — Existing SongSortDialog has its own local `displaySongCoverInList` toggle that is NOT in scope and does not write back to AppStorage. Confirm its behavior is unchanged: toggling in the dialog still updates only the owning page's local VM state. Out-of-scope for this spec; noted so review does not mistake it for a regression.

### 5.3 Edge cases

- Page opened while value is in flight: @StorageProp's default (`true`) seeds the page variable, then the matching AppStorage entry (already set in EntryAbility) synchronously overwrites it on construction. No flash of wrong state.
- Two consumer pages mounted simultaneously: each owns its own bridge; each ViewModel updates independently. No cross-page coupling introduced.
- SearchAllSongs uses `ForEach` (not Lazy) so the entire list rebuilds when the VM's @Track field changes. No extra reload call needed.

## 6. Non-Goals

- Rewiring SongSortDialog's per-page display toggles. Android has parallel per-list toggles too; they are not what this spec governs.
- Changing AlbumContentPage's `showCover: false`.
- Adding a new preference key. The existing `displaySongCover` is the single source of truth.
- Migrating off PersistentStorage. SettingsStore already compensates.

## 7. Files to Touch

Edits:

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/MainPageViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/ArtistContentViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/FolderPathViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/main/MainPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/ArtistContentPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/FolderContentPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/FolderPathPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlaylistContentPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlaylistSearchPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/SearchAllSongsPage.ets`

Read-only (reference / confirm):

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/UserInterfacePage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/model/SettingsStore.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/entryability/EntryAbility.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/components/SongItemComponent.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/AlbumContentPage.ets`
