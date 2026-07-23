# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `4c3493f36875c768497bf084ddf96d63bbdb15d0`
- **Branch**: `wsh-release-3`
- **Parent**: `4fa7658bec8548cd8aebde0036c30d909cd34cdc`
- **Commit subject**: `feat(logic): wire displaySongCover toggle to live-refresh all song lists`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/SPEC/plan.md`
- **Code Context**: `/Users/moriafly/GitHub/HomeTrans/Plugin/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/4c3493f36875c768497bf084ddf96d63bbdb15d0_result.json`
- **Review Date**: 2026-05-08
- **Total Scenarios**: 4
- **Results**: 3 PASS | 1 UNABLE TO VERIFY | 0 PARTIAL | 0 FAIL

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | Default on: covers visible in song lists on first launch | PASS | — |
| 2 | Toggle off: covers hide live across all song lists | PASS | — |
| 3 | Toggle on: covers reappear live across all song lists | PASS | — |
| 4 | State persists across app restart | UNABLE TO VERIFY (static) — code path complete, requires runtime confirmation on device |

## Detailed Scenario Reviews

### Scenario 1: Default on (switch defaults to ON, all song lists show covers)

**Description**: Fresh install or user hasn't changed the setting. The `displaySongCover` switch is on by default, and every song list in the app (main song tab, playlist detail, artist detail, folder detail, folder path, search) renders covers. The album detail page intentionally shows track numbers instead (Android parity).

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/entryability/EntryAbility.ets:84` — `PersistentStorage.persistProp('displaySongCover', true)` seeds the key with `true` on first launch.
- `entry/src/main/ets/entryability/EntryAbility.ets:125` — `AppStorage.setOrCreate('displaySongCover', ss.get('displaySongCover', true))` resolves the authoritative value from Preferences with `true` fallback on cold start.
- `entry/src/main/ets/viewmodel/MainPageViewModel.ets:97` — `@Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)` seeds the VM before the first build pass.
- Same pattern in:
  - `entry/src/main/ets/viewmodel/ArtistContentViewModel.ets:132`
  - `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets:52`
  - `entry/src/main/ets/viewmodel/FolderPathViewModel.ets:58`
  - `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets:42`
  - `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets:65`
  - `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets:58`
- `entry/src/main/ets/pages/main/MainPage.ets:1106` — `showCover: this.vm.displaySongCoverInList`. All other consumer pages also read from the VM field (see below).
- `entry/src/main/ets/pages/AlbumContentPage.ets:139-140` — deliberately `showCover: false, showTrackNumber: true`. `SongItemComponent.ets:91-99` builds track number first, so the album detail page keeps the track-number layout regardless of the setting. This matches Android parity and the plan's explicit non-goal.
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:86-88` — the Settings page switch itself seeds from AppStorage at construction, so the visible toggle state also starts `true` on fresh install.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 2: User toggles the switch OFF — all mounted song lists hide covers immediately

**Description**: From Settings → User Interface, toggling "在列表中显示歌曲封面" off must (a) persist immediately and (b) cause all currently mounted song-list pages to re-render without covers, without requiring navigation away and back.

**Verdict**: PASS

**Evidence**:

Writer path:
- `entry/src/main/ets/pages/UserInterfacePage.ets:306-312` — switch `onChange` calls `this.vm.displaySongCoverVM.toggle()`.
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:110-112` — `displaySongCoverVM` change callback invokes `SettingsStore.getInstance().save('displaySongCover', val)`.
- `entry/src/main/ets/model/SettingsStore.ets:41-50` — `save` writes to both `AppStorage.setOrCreate(key, value)` (immediate broadcast) and `preferences.putSync(key, value)` (memory cache).

Bridge path (one per consumer page):
- `entry/src/main/ets/pages/main/MainPage.ets:91-93` and `145-148` — `@StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged')` + handler that calls `this.vm.setDisplaySongCoverInList(this.storedDisplaySongCover)`.
- `entry/src/main/ets/pages/ArtistContentPage.ets:111-113` and `126-129` — identical pattern.
- `entry/src/main/ets/pages/FolderContentPage.ets:58-59` and `83-86`.
- `entry/src/main/ets/pages/FolderPathPage.ets:26` and `32-34`.
- `entry/src/main/ets/pages/PlaylistContentPage.ets:38-39` and `79-82`.
- `entry/src/main/ets/pages/PlaylistSearchPage.ets:48-49` and `89-92`.
- `entry/src/main/ets/pages/SearchAllSongsPage.ets:54-58`.

Reader path (VM setters) — each flips the `@Track` field, triggering re-render of any dependent `build()` body:
- `entry/src/main/ets/viewmodel/MainPageViewModel.ets:456-459`
- `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets:166-169`
- `entry/src/main/ets/viewmodel/FolderPathViewModel.ets:64-67`
- `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets:294-297`
- `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets:219-222`
- `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets:64-67`
- `entry/src/main/ets/viewmodel/ArtistContentViewModel.ets:199-206` — additionally walks the cached `this.songs` array and calls `songDataSource.reload(...)` because `SongItemViewModel` instances are long-lived on this page. Correctly handles the Artist-specific caching gotcha the plan calls out.

Binding path — every consumer reads from the VM field:
- `entry/src/main/ets/pages/main/MainPage.ets:1106` → `showCover: this.vm.displaySongCoverInList`
- `entry/src/main/ets/pages/ArtistContentPage.ets:157` → `showCover: this.viewModel.displaySongCoverInList`
- `entry/src/main/ets/pages/FolderContentPage.ets:336` → `showCover: this.viewModel.displaySongCoverInList`
- `entry/src/main/ets/pages/FolderPathPage.ets:62` → `showCover: this.viewModel.displaySongCoverInList`
- `entry/src/main/ets/pages/PlaylistContentPage.ets:185` → `showCover: this.viewModel.displaySongCoverInList`
- `entry/src/main/ets/pages/PlaylistSearchPage.ets:191` → `showCover: this.viewModel.displaySongCoverInList`
- `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets:294` → `showCover: this.displaySongCoverInList` (page invokes `this.viewModel.createSongItemViewModel(...)` at `SearchAllSongsPage.ets:239` which now reads the field).

Rendering:
- `entry/src/main/ets/components/SongItemComponent.ets:91-99` — `showTrackNumber` first, then `showCover`, otherwise the left content area is skipped entirely. Re-entry into `build` with the new option correctly drops the cover container.
- `entry/src/main/ets/viewmodel/SongItemViewModel.ets:173-175` — `showCover` is copied from `options` by the `create` factory, so every LazyForEach/ForEach re-build propagates the flipped value into each row VM.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 3: User toggles the switch ON — covers reappear live

**Description**: Inverse of Scenario 2. After covers were hidden, toggling the switch on restores them on every mounted list.

**Verdict**: PASS

**Evidence**: Identical wiring as Scenario 2 — the same writer, bridge, reader, and binding paths carry a `true` value just as symmetrically. The equality guard in each setter (`if (this.displaySongCoverInList === value) return`) is safe because the @StorageProp @Watch fires with the new AppStorage value after `save()` completes.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 4: State persists across app restart

**Description**: After the user turns the setting off, backgrounds the app, force-kills it, and relaunches, the switch must read off and all song lists must render without covers.

**Verdict**: UNABLE TO VERIFY (static). All code paths required to satisfy this scenario are present and correctly chained; actual persistence across a cold start is a runtime behavior that requires on-device confirmation.

**Evidence** (code path is complete):
- Write to memory cache: `entry/src/main/ets/model/SettingsStore.ets:45` — `this.store.putSync(key, value)` on every `save()`.
- Flush to disk on background: `entry/src/main/ets/entryability/EntryAbility.ets:403-430` — `onBackground()` calls `SettingsStore.getInstance().flush()` which invokes `this.store.flushSync()` (`SettingsStore.ets:53-60`).
- Store init on startup: `EntryAbility.ets:116-117` — `ss.init(context)` opens the `settings_state` Preferences before any restore reads.
- Restore on cold start: `EntryAbility.ets:125` — `AppStorage.setOrCreate('displaySongCover', ss.get('displaySongCover', true) as boolean)` pulls the persisted value into AppStorage before any consumer VM reads it.
- Belt-and-suspenders: `EntryAbility.ets:84` — `PersistentStorage.persistProp('displaySongCover', true)` covers the AppStorage auto-persist path as well. (`SettingsStore.ets:3` notes PersistentStorage is flagged unreliable on some devices, which is why the Preferences path is the primary source.)
- Settings switch reads from AppStorage: `UserInterfaceViewModel.ets:86-89` seeds the visible toggle state from AppStorage, so after relaunch the switch reflects the persisted value.

**Gaps**: None in static code.

**Suggestions**: Exercise the plan's Scenario 4 manual check on a device (toggle off → wait >1s in background → kill → relaunch) to confirm the disk flush and restore work as intended. This is a runtime check, not a code gap.

---

## Cross-Cutting Issues

### Permission Coverage
No new runtime permissions required. The displaySongCover feature uses AppStorage and the app-local Preferences sandbox only. No changes to `entry/src/main/module.json5` were needed or made.

### Navigation Completeness
All seven consumer pages wired in this commit (MainPage, ArtistContentPage, FolderContentPage, FolderPathPage, PlaylistContentPage, PlaylistSearchPage, SearchAllSongsPage) are already routable via the existing NavPathStack. UserInterfacePage's switch is reachable from Settings → User Interface as before. No navigation regressions introduced.

### State Management
The `@StorageProp('displaySongCover') @Watch(...)` bridge is the right primitive: it fires whenever the AppStorage key changes, even on pages that are mounted beneath the stack top, matching the same pattern already used for `playerKeepScreenOn`, `playlistVersion`, `currentSongId`, and similar shared keys.

One observation on `MainPageViewModel`: both `changeDisplaySetting('displaySongCoverInList', value)` (driven by the in-dialog toggle in `SongSortDialogComponent`, which does not persist) and `setDisplaySongCoverInList(...)` (driven by the settings-page bridge, which does persist) write to the same `@Track` field. If the user opens the sort dialog and toggles it while the global setting is on, the main list will appear to honor the dialog's local state until the next AppStorage write fires. The plan explicitly puts this SongSortDialog pathway out of scope; this review flags it only for awareness. No action required for the current scenario set.

Equality guard in all setters (`if (this.<field> === value) return`) correctly prevents redundant reload of the Artist LazyDataSource and avoids extra builder runs on other pages.

### API Compatibility
No new HarmonyOS APIs introduced. `@StorageProp`, `@Watch`, `@Track`, `AppStorage.get`, `PersistentStorage.persistProp`, and `@ohos.data.preferences` are all already in widespread use elsewhere in the project. Compatible with the project's current API target.

### Resource Completeness
String `app.string.display_song_cover_in_list` used at `UserInterfacePage.ets:304` was already present pre-commit (no change needed). No new media, color, or layout resources are required or introduced.

---

## Final Assessment

**Overall Verdict**: PASS

- **Fully covered scenarios**: 1 (default on), 2 (toggle off live), 3 (toggle on live).
- **Runtime-dependent scenario**: 4 (persistence across restart) — all static wiring is correct; actual disk round-trip needs a manual device verification per the plan's Scenario 4 checklist.
- **Not covered scenarios**: None.

The implementation accurately follows `SPEC/logic/plan.md` end-to-end: writer → AppStorage + Preferences → per-page `@StorageProp @Watch` bridge → VM setter → `showCover` binding. The Artist-specific long-lived `SongItemViewModel` array is handled with an explicit walk-and-reload path; SearchAllSongs' non-lazy ForEach is correctly relied on for re-render. AlbumContentPage intentionally remains on `showCover: false, showTrackNumber: true` per Android parity, and `SongItemComponent`'s build order (`showTrackNumber` > `showCover`) guarantees that behavior.

**Recommended Priority Fixes**: None blocking. Optional follow-ups (out of scope for this commit):

1. Reconcile the SongSortDialog's per-page `displaySongCoverInList` toggle with the global setting, so transient dialog state does not shadow an AppStorage update while the dialog is open. Tracked as a non-goal by the plan; recommend deferring to a follow-up spec if Android parity requires it.
2. Perform the manual Scenario 4 device check (toggle off → background → kill → relaunch) during QA to close the runtime gap flagged above.
