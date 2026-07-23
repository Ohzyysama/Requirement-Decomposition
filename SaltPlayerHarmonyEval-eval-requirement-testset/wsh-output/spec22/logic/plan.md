# Implementation Plan — spec22: "在列表中显示添加下一首播放" switch

Source spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec22/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 1. Goal

Make the existing Settings → 用户界面 → 歌曲列表 → "在列表中显示添加下一首播放" switch a real, live, cross-page setting:

1. The switch persists (already wired) — verify no regression.
2. Toggling the switch updates **all currently mounted song-list pages** without reconstruction (live refresh).
3. The "add to next play" button (line 193-212 of `SongItemComponent`) appears in song rows iff the flag is on AND multi-choice mode is off.
4. Click handler keeps existing behavior: `viewModel.handleAddToPlayNext()` + toast `successfully_added_to_next_play`.

The bulk of the wiring (Settings page row, `UserInterfaceViewModel.displayAddToPlayNextVM`, `SongItemViewModel.displayAddToPlayNext`, `SongItemComponent` gating, `EntryAbility.persistProp + AppStorage seed`, all string resources, sort-dialog display row) is already present from earlier work. The missing pieces are the **page-layer AppStorage→VM bridges** on each song-list page and one missing prop on MainPage's Song-tab `SongItemViewModel.create(...)` call.

## 2. Repo reality (writer / reader / binding / refresh)

### 2.1 Existing — do not duplicate

| Concern | Where it already lives |
| --- | --- |
| String resource `display_add_to_play_next_in_list` | `entry/src/main/resources/{base,zh,ug}/element/string.json` |
| Persistent key `displayAddToPlayNext` (default `true`) | `entry/src/main/ets/entryability/EntryAbility.ets:96` (`PersistentStorage.persistProp`) and `:148` (`AppStorage.setOrCreate` seeded from `SettingsStore`) |
| Settings switch row (writer) | `entry/src/main/ets/pages/UserInterfacePage.ets:443-461` |
| Settings switch VM + callback (persist + broadcast) | `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:126-129` — `displayAddToPlayNextVM` callback writes both `AppStorage.setOrCreate('displayAddToPlayNext', val)` and `SettingsStore.save('displayAddToPlayNext', val)` |
| Row gating in song item | `entry/src/main/ets/components/SongItemComponent.ets:192-212` — `if (this.viewModel.displayAddToPlayNext)` inside the `!multiChoiceMode` branch |
| Per-list page-VM seed of `displayAddToPlayNextInList` | `FolderContentPageViewModel.ets:54`, `PlaylistContentViewModel.ets:50`, `PlaylistSearchViewModel.ets:67` — all seeded `(AppStorage.get<boolean>('displayAddToPlayNext') ?? true)` |
| Sort-dialog "歌曲列表" display row (Scenarios 1/2/3 alt path) | `components/SongSortDialogComponent.ets:100-104` |

### 2.2 Gaps — these are the only owner-path violations the spec exposes

1. **MainPage Song tab does not push the flag to the row VM.**
   - `entry/src/main/ets/pages/main/MainPage.ets:1184-1224` builds `SongItemViewModel.create(song, { isCurrent, showCover, displayFileName, multiChoiceMode, checked, ...callbacks })` — note absence of `displayAddToPlayNext`. Row VM falls back to `SongItemViewModel`'s default `true`, so toggling off in Settings has no visible effect on the Song tab.
   - Additionally, `MainPageViewModel.displayAddToPlayNextInList` (`MainPageViewModel.ets:102`) is hard-coded `: boolean = true` — it is NOT seeded from `AppStorage.get('displayAddToPlayNext')`. First frame after cold-start with the user's preference = `false` would still show the button until the bridge fires.

2. **No `@StorageProp('displayAddToPlayNext') @Watch(...)` bridge on any song-list page.**
   - `displaySongCover` and `displaySongFileName` each have a `@StorageProp + @Watch` bridge in every consumer page (`MainPage`, `FolderContentPage`, `PlaylistContentPage`, `PlaylistSearchPage`, `AlbumContentPage`, `ArtistContentPage`, `SearchAllSongsPage`, `FolderPathPage`). The matching `displayAddToPlayNext` bridge is missing across the board.
   - Scenarios 2/3 require **live refresh of a mounted song-list page** when the Settings switch flips. Without the bridge, the page's `displayAddToPlayNextInList` field stays at the constructor-time snapshot — the canonical anti-pattern called out in the harness rules ("`aboutToAppear` / constructor seed is not live sync; do not rely on it for cross-page state").

3. **No `setDisplayAddToPlayNextInList(value)` setter on any list-page VM.**
   - The setter is what completes the AppStorage→Page→VM bridge (the pattern is already established by `setDisplaySongCoverInList` / `setDisplaySongFileNameInList`). Without it, the page-layer `@Watch` callback has nothing to call.

4. **`ArtistContentViewModel` caches long-lived row VMs.**
   - Unlike the other list pages, `ArtistContentViewModel.loadArtistData()` (`viewmodel/ArtistContentViewModel.ets:165-191`) builds `SongItemViewModel` instances once and stores them in `this.songs`; subsequent renders **do not** re-run `SongItemViewModel.create`. The existing `setDisplaySongCoverInList` / `setDisplaySongFileNameInList` setters explicitly walk `this.songs` and `reload()` the data source. The new `displayAddToPlayNext` setter must follow the same pattern.
   - `ArtistContentPage.ets:171` currently hard-codes `displayAddToPlayNext: true` — this must read the VM's field instead.

5. **`AlbumContentPage` hard-codes `displayAddToPlayNext: true`.**
   - `entry/src/main/ets/pages/AlbumContentPage.ets:153`. The album track list is a song list per the spec wording ("歌曲列表中每首歌曲"), so it must honor the toggle. The associated `AlbumContentViewModel` has no `displayAddToPlayNextInList` field today and the page has no bridge either; both must be added.

6. **`SearchAllSongsViewModel.createSongItemViewModel(...)` hard-codes `displayAddToPlayNext: true`.**
   - `viewmodel/SearchAllSongsViewModel.ets:316`. Page already has the seeded `displaySongCoverInList` / `displaySongFileNameInList` pattern, so adding the third axis is a straight mirror.

7. **`FolderPathPage` (subfolder song view) — verify.**
   - `pages/FolderPathPage.ets:70-74` uses `SongItemComponent` and reads `displaySongCoverInList` / `displayFileNameInList` from `FolderPathViewModel`, but `FolderPathViewModel` has no `displayAddToPlayNextInList` field today. Either it must be added (per the spec's "song list" language) or the row must hard-code `displayAddToPlayNext: false`. Audit indicates this page is presented as a "song list" UI, so add the field + bridge + thread it into the `SongItemViewModel.create(...)` call.

### 2.3 MVVM owner mapping (binding strictly to repo reality)

| Layer | Owner | Files touched |
| --- | --- | --- |
| Page (View) | `@StorageProp('displayAddToPlayNext') @Watch(handler)` field + handler `=>` `viewModel.setDisplayAddToPlayNextInList(value)`. Pass `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList` (or `this.vm.displayAddToPlayNextInList`) into every `SongItemViewModel.create(...)` call inside a `LazyForEach`. | MainPage, FolderContentPage, PlaylistContentPage, PlaylistSearchPage, AlbumContentPage, ArtistContentPage, SearchAllSongsPage, FolderPathPage |
| ViewModel | `@Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)` (where missing); `setDisplayAddToPlayNextInList(value): void` that early-returns when unchanged and, for the cached-row variant (Artist), also walks `this.songs` and `reload()`s the data source. The Track field is what `LazyForEach` re-reads on every render. | MainPageVM, AlbumContentVM, FolderPathVM (add field + setter); FolderContentPageVM, PlaylistContentVM, PlaylistSearchVM, SearchAllSongsVM, ArtistContentVM (add setter only; field already exists) |
| Model / Service | None. Persistence is already in `SettingsStore`; `AppStorage` already broadcasts. **Do not** introduce a new storage key or a new persistence write path. | — |

The Page → ViewModel boundary is preserved: pages never touch `SettingsStore` for this flag; they only forward the `AppStorage` value into a VM setter. The ViewModel owns the refresh of its data source.

## 3. Change list (precise, file-by-file)

### 3.1 `entry/src/main/ets/viewmodel/MainPageViewModel.ets`

1. Replace `@Track public displayAddToPlayNextInList: boolean = true` (line 102) with:
   ```
   @Track public displayAddToPlayNextInList: boolean =
     (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
   ```
2. Add a new setter immediately after `setDisplaySongFileNameInList` (line 540 region), mirroring its style:
   ```
   setDisplayAddToPlayNextInList(value: boolean): void {
     if (this.displayAddToPlayNextInList === value) return
     this.displayAddToPlayNextInList = value
   }
   ```
   Justification: the Song-tab `LazyForEach` rebuilds `SongItemViewModel` on every render with `displayAddToPlayNext: this.vm.displayAddToPlayNextInList`; flipping the `@Track` field is sufficient.
3. Do NOT touch `changeDisplaySetting('displayAddToPlayNextInList', value)` — it already sets the field and stays in place for the sort-dialog write path.

### 3.2 `entry/src/main/ets/pages/main/MainPage.ets`

1. Add a new `@StorageProp` + `@Watch` near the existing `storedDisplaySongFileName` block (line 108-109):
   ```
   @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')
   private storedDisplayAddToPlayNext: boolean = true
   ```
2. Add the corresponding handler near `onDisplaySongFileNameChanged` (around line 169-171):
   ```
   onDisplayAddToPlayNextChanged(): void {
     this.vm.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
   }
   ```
3. In the Song-tab `SongItemViewModel.create(...)` block (line 1185-1223), add `displayAddToPlayNext: this.vm.displayAddToPlayNextInList,` alongside the existing `showCover` / `displayFileName` / `multiChoiceMode` options. Place it next to `displayFileName` for readability.

### 3.3 `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets`

Add a `setDisplayAddToPlayNextInList(value: boolean)` setter after `setDisplaySongFileNameInList` (line 175-178 region), same shape as the existing two setters. Field on line 54 already exists.

### 3.4 `entry/src/main/ets/pages/FolderContentPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` next to the existing `storedDisplaySongFileName` (line 65-66).
2. Add handler:
   ```
   onDisplayAddToPlayNextChanged(): void {
     this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
   }
   ```
3. The page already passes `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList` at line 354 — no change there.

### 3.5 `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets`

Add `setDisplayAddToPlayNextInList(value: boolean)` setter after the existing setDisplaySongFileNameInList around line 332-335 region.

### 3.6 `entry/src/main/ets/pages/PlaylistContentPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` (next to existing `storedDisplaySongFileName` at line ~43).
2. Add handler `onDisplayAddToPlayNextChanged()` that calls `this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)`.
3. Page already passes `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList` (line 198) — no change.

### 3.7 `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets`

Add `setDisplayAddToPlayNextInList(value: boolean)` setter; field on line 67 already exists.

### 3.8 `entry/src/main/ets/pages/PlaylistSearchPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged')` field next to `storedDisplaySongFileName` (line ~54).
2. Add `onDisplayAddToPlayNextChanged()` handler.
3. Page already passes `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList` at line 204 — no change.

### 3.9 `entry/src/main/ets/viewmodel/AlbumContentViewModel.ets`

1. Add field after `displaySongFileNameInList` (line 59):
   ```
   @Track public displayAddToPlayNextInList: boolean =
     (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
   ```
2. Add `setDisplayAddToPlayNextInList(value: boolean)` setter mirroring the existing `setDisplaySongFileNameInList` in this VM.

### 3.10 `entry/src/main/ets/pages/AlbumContentPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` next to `storedDisplaySongFileName` (line ~60).
2. Add handler `onDisplayAddToPlayNextChanged()` → `this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)`.
3. Replace hard-coded `displayAddToPlayNext: true,` at line 153 with `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,`.

### 3.11 `entry/src/main/ets/viewmodel/ArtistContentViewModel.ets`

1. Add field next to `displaySongFileNameInList` (line 137):
   ```
   @Track public displayAddToPlayNextInList: boolean =
     (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
   ```
2. In `loadArtistData()` (line 165-191), replace `vm.displayAddToPlayNext = true` (line 175) with `vm.displayAddToPlayNext = this.displayAddToPlayNextInList`.
3. Add the cached-row variant of the setter (mirror the existing `setDisplaySongFileNameInList` at line 219-225):
   ```
   setDisplayAddToPlayNextInList(value: boolean): void {
     if (this.displayAddToPlayNextInList === value) return
     this.displayAddToPlayNextInList = value
     for (const vm of this.songs) {
       vm.displayAddToPlayNext = value
     }
     this.songDataSource.reload(Array.from(this.songs))
   }
   ```
   Rationale: cached row VMs (`this.songs`) hold their own `displayAddToPlayNext` field; flipping only the page-VM field would leave each row stale until `loadArtistData` runs again.

### 3.12 `entry/src/main/ets/pages/ArtistContentPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` next to `storedDisplaySongFileName` (line ~118).
2. Add handler → `this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)`.
3. Replace hard-coded `displayAddToPlayNext: true,` at line 171 with `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,`.

### 3.13 `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets`

1. Add field next to `displaySongFileNameInList` (line 65):
   ```
   @Track public displayAddToPlayNextInList: boolean =
     (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
   ```
2. Add `setDisplayAddToPlayNextInList(value)` setter mirroring `setDisplaySongFileNameInList` (line 76-82).
3. In `createSongItemViewModel(...)` (line 309-346), change `displayAddToPlayNext: true,` (line 316) to `displayAddToPlayNext: this.displayAddToPlayNextInList,`.

### 3.14 `entry/src/main/ets/pages/SearchAllSongsPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` next to `storedDisplaySongFileName` (line ~60).
2. Add handler → `this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)`.

### 3.15 `entry/src/main/ets/viewmodel/FolderPathViewModel.ets`

1. Add field next to `displaySongFileNameInList` (line 63):
   ```
   @Track public displayAddToPlayNextInList: boolean =
     (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
   ```
2. Add `setDisplayAddToPlayNextInList(value)` setter mirroring `setDisplaySongFileNameInList`.

### 3.16 `entry/src/main/ets/pages/FolderPathPage.ets`

1. Add `@StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true` next to `storedDisplaySongFileName` (line ~32).
2. Add handler → `this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)`.
3. In the `SongItemViewModel.create(...)` block (line 70-…), add `displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,` next to `displayFileName` (line 74).

### 3.17 `entry/src/main/ets/components/SongItemComponent.ets`

**No change.** Lines 192-212 already gate the "add to next" button on `viewModel.displayAddToPlayNext && !multiChoiceMode`. The space taken by the button is absorbed by the `.layoutWeight(1)` Column at line 153 — Scenarios 1/3/6's "标题和艺术家文本区域自动扩展/缩短" follows naturally because the title block fills the remaining row width when the 48-vp button stack is conditionally rendered.

### 3.18 `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`

**No change.** `displayAddToPlayNextVM`'s callback already writes to both `AppStorage` and `SettingsStore` (line 126-129); the persisted seed is restored on construction (line 95-98).

### 3.19 `entry/src/main/ets/entryability/EntryAbility.ets`

**No change.** `PersistentStorage.persistProp('displayAddToPlayNext', true)` (line 96) and the `AppStorage.setOrCreate('displayAddToPlayNext', ss.get(...))` cold-start re-seed (line 148) are both in place.

### 3.20 String resources

**No change** — `display_add_to_play_next_in_list` and `successfully_added_to_next_play` exist in base/zh/ug.

## 4. Refresh model (live update path, end-to-end)

```
[User flips switch on UserInterfacePage]
        │
        ▼
vm.displayAddToPlayNextVM.toggle()                 ── ViewModel owns the action
        │
        ▼
callback: AppStorage.setOrCreate('displayAddToPlayNext', val)
          SettingsStore.save('displayAddToPlayNext', val)   ── Model owns persistence
        │
        ▼
AppStorage('displayAddToPlayNext') broadcasts to every mounted page that holds
@StorageProp('displayAddToPlayNext')                ── HarmonyOS reactive primitive
        │
        ▼
each list page's @Watch handler fires:
  this.viewModel.setDisplayAddToPlayNextInList(this.stored…)   ── Page → VM
        │
        ▼
VM flips @Track field (and, for ArtistContent, walks cached row VMs +
  songDataSource.reload(...))                      ── VM owns refresh
        │
        ▼
LazyForEach re-reads vm.displayAddToPlayNextInList on next render and
SongItemViewModel.create(..., { displayAddToPlayNext: <new value> })
produces rows whose `displayAddToPlayNext` field reflects the live setting
        │
        ▼
SongItemComponent's `if (this.viewModel.displayAddToPlayNext)` re-evaluates,
showing or hiding the 48-vp add-to-next stack accordingly                       ── View
```

Cold-start path:
```
PersistentStorage → SettingsStore restore → AppStorage.setOrCreate (in EntryAbility)
   → each VM's constructor reads AppStorage.get('displayAddToPlayNext')
   → first frame is already correct, no flash
```

## 5. Scenario coverage

| Scenario | Path | Verification |
| --- | --- | --- |
| S1 (default ON, button visible) | EntryAbility seed → VM field default `true` → row default `true` → SongItemComponent renders button | Cold-start build; observe row in MainPage Song tab. |
| S2 (toggle off → button hides live) | Settings page write → AppStorage broadcast → Page `@Watch` → VM setter → @Track flip → LazyForEach re-renders rows | Open MainPage Song tab → open Settings → flip off → return to Song tab (or split-screen): button gone, title area widens. |
| S3 (toggle on → button restores live) | Same path, value `true` | Same as S2, reversed. |
| S4 (click adds to next + toast) | Row tap → `viewModel.handleAddToPlayNext()` → `vm.addToPlayNext(song)` (per page; already wired in MainPage line 1217-1219, FolderContent, Playlist…) → `AudioPlayerService.addToPlayNext` + `promptAction.showToast({ message: $r('app.string.successfully_added_to_next_play') })` (`SongItemComponent.ets:209`) | Tap button; confirm queue change + toast. |
| S5 (enter multi-choice → button hides) | Already covered by `SongItemComponent.ets:171-212` — the `if (multiChoiceMode)` branch renders the check column instead of the button. | Long-press to enter multi-choice; observe button replaced by check circle. |
| S6 (exit multi-choice → button restores) | Same conditional unwinds when `multiChoiceMode` flips back to `false`. | Exit multi-choice; observe button restored on rows where `displayAddToPlayNext` is on. |

## 6. Owner-boundary safeguards (per harness rules)

- **Page does not persist.** Pages only call `viewModel.setDisplayAddToPlayNextInList(...)`. The single writer to `SettingsStore` is `UserInterfaceViewModel.displayAddToPlayNextVM`'s callback. No new persistence path is introduced.
- **No mirror state.** Each list-page VM has exactly one `displayAddToPlayNextInList @Track` field, seeded from `AppStorage` on construction and updated via the setter. There is no second copy on the Page.
- **No reliance on `aboutToAppear` for live sync.** The bridge is `@StorageProp @Watch`, which fires on every AppStorage write while the page is mounted. The constructor-time seed only covers the first-frame value.
- **ArtistContent cached-row exception is acknowledged.** The setter explicitly walks `this.songs` and `reload()`s — the same already-established pattern used for `displaySongCoverInList` and `displaySongFileNameInList` in that VM (lines 205-225).
- **No fake defaults.** `MainPageViewModel.displayAddToPlayNextInList` is changed from hard-coded `true` to an AppStorage-seeded value so cold-start with a user preference of `false` does not flash a stale `true`.
- **No new AppStorage key.** Reuse the existing `'displayAddToPlayNext'`.

## 7. Out of scope (do not change)

- The SongItemComponent layout. The 48-vp button stack is already the existing layout; row text width re-flows automatically through `layoutWeight(1)`.
- The sort-dialog "歌曲列表" display row (S2 alt path) — already wired and unaffected.
- The Settings page row, its VM, and the persistent prop seed in EntryAbility — already correct.
- String resources.

## 8. Verification checklist (post-implementation)

- [ ] Build the project (no new compilation errors).
- [ ] Cold start with `displayAddToPlayNext=false` (manually set in SettingsStore): the Song tab first frame does NOT show the button. Confirms M3.1 seed change.
- [ ] Toggle off from Settings while Song tab is mounted (split screen if available, or pop back to it without page reconstruction): button disappears within one render. Confirms bridge.
- [ ] Same toggle from Settings affects FolderContent, PlaylistContent, PlaylistSearch, AlbumContent, ArtistContent, SearchAllSongs, FolderPath song lists. (ArtistContent additionally requires the cached-VM walk; verify by leaving an artist page open and toggling.)
- [ ] Tap the button → toast shows and song is queued next.
- [ ] Enter multi-choice → button hides; exit → button restores.
- [ ] App restart preserves the user's last choice.
