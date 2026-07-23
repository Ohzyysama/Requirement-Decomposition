# Code Review Report — spec21

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `fe56cb758f08271c9d27427decc78ade61755864`
- **Commit subject**: `[Human-AI] feat(spec21): show song file names in lists when toggled`
- **Parent**: `b2d1db9ed6e57087cbec6901f47caaf89ea6465f`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec21/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/fe56cb758f08271c9d27427decc78ade61755864_result.json`
- **Review Date**: 2026/05/15
- **Total Scenarios**: 4
- **Results**: 3 PASS | 1 PARTIAL | 0 FAIL | 0 UNABLE TO VERIFY

## Scope of Commit

Commit `fe56cb7` touches 18 files (+234 / −2). It wires the existing
`displaySongFileName` AppStorage key (already declared/persisted in
`EntryAbility.onCreate` from a previous spec) through every mounted song list:

- Adds `fileNameFromPath()` in `SongItemModel.ets` (last-segment extractor,
  `decodeURIComponent` for URI-form `Track.path`).
- Adds `@Track displayFileName` flag and a `getDisplayTitle()` branch in
  `SongItemViewModel.ets`, plus an `options.displayFileName` field on the
  static `create()` factory.
- Adds `@StorageProp('displaySongFileName')` + `@Watch` bridges in every
  song-list page: `MainPage`, `AlbumContentPage`, `ArtistContentPage`,
  `FolderContentPage`, `FolderPathPage`, `PlaylistContentPage`,
  `PlaylistSearchPage`, `SearchAllSongsPage`.
- Adds `displaySongFileNameInList` @Track field + `setDisplaySongFileNameInList`
  setter in the matching VMs (`MainPageViewModel`, `AlbumContentViewModel`,
  `ArtistContentViewModel`, `FolderContentPageViewModel`, `FolderPathViewModel`,
  `PlaylistContentViewModel`, `PlaylistSearchViewModel`,
  `SearchAllSongsViewModel`).
- Threads `displayFileName: this.viewModel.displaySongFileNameInList` into
  every `SongItemViewModel.create()` call site for those lists.
- `ArtistContentViewModel` (which caches long-lived row VMs) additionally
  walks `this.songs` and reloads its LazyDataSource so the cached rows pick up
  the new flag.

The UI toggle row in `UserInterfacePage.ets` (lines 423–442) and the
`displaySongFileNameVM` wiring in `UserInterfaceViewModel.ets` (lines 121–124)
were already present before this commit; this commit only consumes the
existing `AppStorage('displaySongFileName')` key.

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | Default OFF — lists show metadata title | PASS | — |
| 2 | Turning the switch ON — lists live-switch to file names, persisted across restarts | PASS | — |
| 3 | Turning the switch OFF — lists live-switch back to metadata titles, persisted across restarts | PASS | — |
| 4 | File-name = last path segment, extension kept | PARTIAL | Decoded value uses URL-decoding of URI form; meets the spec example but the spec wording "实际存储路径" is satisfied only after URL decode |

## Detailed Scenario Reviews

### Scenario 1 — Default OFF, lists show metadata title

**Description**: First launch (or untouched setting): the switch is OFF and
every song list (Song tab, Playlist / Album / Artist / Folder detail,
FolderPath, all-songs / in-playlist search) shows the metadata title.

**Verdict**: PASS

**Evidence**:

- `entry/src/main/ets/entryability/EntryAbility.ets:95` — seeds the persisted
  default: `PersistentStorage.persistProp('displaySongFileName', false)`.
- `entry/src/main/ets/entryability/EntryAbility.ets:147` — restores the value
  from `SettingsStore` falling back to `false`.
- `entry/src/main/ets/viewmodel/SongItemViewModel.ets:44–45` —
  `@Track public displayFileName: boolean = false` (per-row default false).
- `entry/src/main/ets/viewmodel/SongItemViewModel.ets:204–206` —
  `create()` only overrides `vm.displayFileName` when
  `options.displayFileName !== undefined`, so call sites that omit it leave
  the safe default.
- `getDisplayTitle()` early-return guard:
  `entry/src/main/ets/viewmodel/SongItemViewModel.ets:114–120` — only enters
  the file-name branch when `this.displayFileName` is `true`.
- Every list VM seeds its mirror to `false` when AppStorage has the default:
  `MainPageViewModel.ets:101`, `AlbumContentViewModel.ets:59`,
  `ArtistContentViewModel.ets:137`, `FolderContentPageViewModel.ets:53`,
  `FolderPathViewModel.ets:63`, `PlaylistContentViewModel.ets:49`,
  `PlaylistSearchViewModel.ets:48`, `SearchAllSongsViewModel.ets:65` — all
  use `(AppStorage.get<boolean>('displaySongFileName') ?? false)`.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 2 — User flips switch ON, lists swap to file names live and persist

**Description**: User goes to 设置 → 用户界面 → 歌曲列表, turns
"在列表中显示歌曲文件名" ON. All song lists immediately swap the primary text
to the file name (including extension). Setting persists across app restart.

**Verdict**: PASS

**Evidence**:

- **Switch row** (already shipped pre-commit):
  - `entry/src/main/ets/pages/UserInterfacePage.ets:423–442` — `HdsListItemCard`
    with `primaryText = $r('app.string.display_song_file_name_in_list')` and
    `SuffixSwitch` bound to `this.vm.displaySongFileNameVM`.
  - `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:121–124` — on
    toggle, writes `AppStorage.setOrCreate('displaySongFileName', val)` and
    `SettingsStore.getInstance().save('displaySongFileName', val)`, so the
    flag both propagates in-memory and is persisted to disk.
  - Resource strings: `entry/src/main/resources/base/element/string.json:988`
    (`display_song_file_name_in_list = "在列表中显示歌曲文件名"`) and
    `:992` (intro) — present in `base`, `zh`, and `ug` locales.
- **Live propagation from AppStorage to every list page** (the commit's core
  contribution): each list page has `@StorageProp('displaySongFileName')`
  with a `@Watch` that calls the matching VM setter:
  - `MainPage.ets:106–110` + `:166–170` (forwards to
    `MainPageViewModel.setDisplaySongFileNameInList`,
    `MainPageViewModel.ets:540–543`).
  - `AlbumContentPage.ets:57–62` + `:76–79`
    → `AlbumContentViewModel.ets:307–315`.
  - `ArtistContentPage.ets:115–117` + `:138–142`
    → `ArtistContentViewModel.ets:215–223` (also reloads the cached row VMs
    and the LazyDataSource — important because this VM caches long-lived
    `SongItemViewModel` instances rather than rebuilding them every render).
  - `FolderContentPage.ets:62–64` + `:95–98`
    → `FolderContentPageViewModel.ets:171–178`.
  - `FolderPathPage.ets:29–31` + `:42–45`
    → `FolderPathViewModel.ets:74–80`.
  - `PlaylistContentPage.ets:40–44` + `:89–92`
    → `PlaylistContentViewModel.ets:329–335`.
  - `PlaylistSearchPage.ets:51–55` + `:99–102`
    → `PlaylistSearchViewModel.ets:224–230`.
  - `SearchAllSongsPage.ets:57–61` + `:66–69`
    → `SearchAllSongsViewModel.ets:76–82`.
- **Row-level consumption**: every `SongItemViewModel.create()` call site in
  these lists passes
  `displayFileName: this.viewModel.displaySongFileNameInList`:
  - Song tab: `pages/main/MainPage.ets:1188`.
  - Album: `pages/AlbumContentPage.ets:154`.
  - Artist: `viewmodel/ArtistContentViewModel.ets:174` (cached-row path) and
    `pages/ArtistContentPage.ets:170` (template path).
  - Folder: `pages/FolderContentPage.ets:351`.
  - FolderPath: `pages/FolderPathPage.ets:74`.
  - Playlist: `pages/PlaylistContentPage.ets:196`.
  - PlaylistSearch: `pages/PlaylistSearchPage.ets:202`.
  - SearchAllSongs: `viewmodel/SearchAllSongsViewModel.ets:313`.
- **Display**:
  `SongItemViewModel.getDisplayTitle()` at
  `entry/src/main/ets/viewmodel/SongItemViewModel.ets:114–120` calls
  `fileNameFromPath(this.path)` when `displayFileName` is true and falls back
  to the original `title` (with optional format suffix) when the path yields
  an empty string. The row text is rendered by
  `entry/src/main/ets/components/SongItemComponent.ets:114`
  (`Text(this.viewModel.getDisplayTitle())`).
- **Persistence**: `PersistentStorage.persistProp('displaySongFileName', false)`
  (`EntryAbility.ets:95`) plus the explicit `SettingsStore.save(...)` call
  inside the toggle callback (`UserInterfaceViewModel.ets:123`) means the
  new value survives an app restart. On next launch
  `EntryAbility.ets:147` re-seeds AppStorage from `SettingsStore`, and each
  list VM seeds its mirror from AppStorage on construction.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 3 — User flips switch OFF, lists swap back to titles live and persist

**Description**: Same flow as Scenario 2 in reverse: turn the switch OFF and
all lists revert to metadata titles immediately; setting persists.

**Verdict**: PASS

**Evidence**: The same plumbing as Scenario 2 — the switch callback writes
`val` (now `false`) into AppStorage + `SettingsStore`; the `@StorageProp`
`@Watch` on each page fires; each VM setter performs the equality early-out
(`if (this.displaySongFileNameInList === value) return`) and then assigns;
`getDisplayTitle()` falls through to the metadata-title branch on the next
render. Persistence works the same way.

- `getDisplayTitle()` fallback to title:
  `entry/src/main/ets/viewmodel/SongItemViewModel.ets:121–125`.
- Idempotent setter pattern (e.g. `MainPageViewModel.ets:541–542`,
  `AlbumContentViewModel.ets:313–314`, etc.) — avoids redundant re-renders
  when the page first mounts and the @Watch fires with the same value.

**Gaps**: None.

**Suggestions**: None.

---

### Scenario 4 — Displayed file name = last path segment with extension

**Description**: The displayed text equals the file's actual on-disk last
path segment, including the extension. Example from the spec:
path `"/storage/music/周杰伦 - 晴天.flac"` should show `"周杰伦 - 晴天.flac"`.

**Verdict**: PARTIAL

**Evidence**:

- `entry/src/main/ets/model/SongItemModel.ets:55–74` — `fileNameFromPath()`:
  - Returns `''` for `null`/`undefined`/empty (caller falls back to title).
  - `lastIndexOf('/')` → `raw.substring(slash + 1)` extracts the last
    segment.
  - Extension is NOT stripped — `substring(slash + 1)` keeps everything after
    the last `/`, so `周杰伦 - 晴天.flac` survives intact (matches the spec
    example).
  - `decodeURIComponent` is applied in a try/catch (best-effort), with the
    raw segment returned on `URIError`.

**Behaviour matrix**:

| Input `Track.path`                              | Output                  | Spec match? |
|-------------------------------------------------|-------------------------|-------------|
| `file:///storage/music/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.flac` | `周杰伦 - 晴天.flac` | yes — matches the example exactly after URL-decode |
| `/storage/music/周杰伦 - 晴天.flac`             | `周杰伦 - 晴天.flac`     | yes |
| `file:///data/Music/Song.mp3`                   | `Song.mp3`              | yes |
| `/data/Music/Song%2520Name.mp3` (literal `%`)   | `Song%20Name.mp3` (one decode pass) | edge case — input had a literal `%` |
| `undefined` / `null` / `''`                     | `''` → fall back to title | yes (intentional safety, prevents blank rows) |
| `/data/Music/`  (trailing slash)                | `''` → fall back to title | yes (cannot derive a file name from a directory path) |

**Gaps**:

- **Minor — semantic mismatch with literal `%` characters in the on-disk
  name.** Because `Track.path` is documented in the helper's comment as
  URI-form (`file:///…`) with URL-encoded byte sequences, the helper applies
  `decodeURIComponent` unconditionally. If a future code path stores a plain
  filesystem path that happens to contain a literal `%XX` byte sequence, that
  sequence will be silently decoded. This is consistent with the rest of the
  app (where `Track.path` is treated as URI form) and matches the spec
  example, but is worth noting because the spec's wording is "实际存储路径"
  — i.e. the raw on-disk path. In practice the visible result for ordinary
  filenames is correct.
- **Minor — track-rebuilding fallback.** Empty/null/whitespace `path` falls
  back to `title` (which is the desired behaviour per Scenario 1's invariant
  that rows never blank). However, the fallback path uses the title alone
  *without* the existing `.{format}` suffix (`getDisplayTitle()` returns
  `fileName` before the format-suffix branch). Practically this only matters
  for the unlikely case where `path` is unset but `format` is set — at that
  point the user has the switch ON but no path to read, so the rendered text
  is `title` only. This is consistent with the spec ("文件名完整显示，不去除
  扩展名部分" — only relevant when there IS a file name) but worth calling
  out.

**Suggestions**:

1. Consider adding a unit test (similar to
   `entry/src/test/SearchAllSongs.test.ets`) for `fileNameFromPath` covering
   the example case, trailing-slash, empty, undefined, and the
   already-decoded vs. encoded inputs — to lock in the spec example as a
   regression baseline.
2. If `Track.path` may at some point carry plain (non-URI) paths,
   tighten the decode step to a guard such as
   `raw.includes('%') ? decodeURIComponent(segment) : segment` so that bare
   filesystem paths with literal `%` survive untouched. Optional — current
   behavior matches the spec's stated example.

## Cross-Cutting Issues

### Permission Coverage

No new permission is required by this feature. It reads an in-memory string
already stored on each track record (`Track.path` is populated from the
SQLite music DB at `MusicDatabase.ets:808` and on every subsequent query).

### Navigation Completeness

The toggle row at `UserInterfacePage.ets:423–442` already lives in the
"Settings → 用户界面 → 歌曲列表" group adjacent to `displaySongCover` and
`displayAddToPlayNext`, so the path described in the scenario doc
("设置-用户界面" → "歌曲列表" 分类) is reachable from the existing settings
navigation graph. Verified by reading
`pages/UserInterfacePage.ets:407–462` (the surrounding `List` block) and the
prior toggles using the same `HdsListItemCard` pattern.

### State Management

`displaySongFileName` follows the **exact same pattern** as the existing
`displaySongCover` AppStorage key:

- Persisted via `PersistentStorage.persistProp` + `SettingsStore.save` on
  write.
- Mirrored in each list VM as a `@Track` field seeded from `AppStorage.get`.
- Each list page bridges live updates with `@StorageProp + @Watch` →
  `vm.setDisplaySongFileNameInList(...)`.
- Setters guard with an equality early-out to suppress redundant render
  cycles.
- `ArtistContentViewModel` correctly walks the cached `this.songs` array and
  calls `songDataSource.reload(...)` (lines 220–223) because that VM keeps
  long-lived `SongItemViewModel` instances rather than rebuilding them every
  render — without this, the cached rows would keep the stale value. This
  mirrors how `setDisplaySongCoverInList` is implemented in the same file.

Overall the pattern is consistent across all eight list surfaces and reuses
the already-proven `displaySongCover` plumbing.

### API Compatibility

The commit only uses already-established APIs in the project:
`@StorageProp`, `@Watch`, `@Track`, `AppStorage.get/setOrCreate`,
`PersistentStorage.persistProp`, `decodeURIComponent`, plain string
`lastIndexOf` / `substring`. No new HarmonyOS Kit dependency.

### Resource Completeness

- `app.string.display_song_file_name_in_list` and
  `app.string.display_song_file_name_in_list_intro` exist in `base/zh/ug`
  locales (`resources/base/element/string.json:988,992` and the matching
  files under `resources/zh/` and `resources/ug/`).
- No new icons / media required.

### Coverage of Spec Scope

The spec lists "all song lists" — Song tab, playlist detail, album detail,
artist detail, folder detail, etc. The commit covers:

- Song tab (`MainPage`)
- Album detail (`AlbumContentPage`)
- Artist detail (`ArtistContentPage`)
- Folder detail (`FolderContentPage`)
- FolderPath (`FolderPathPage`)
- Playlist detail (`PlaylistContentPage`)
- In-playlist search (`PlaylistSearchPage`)
- All-songs search (`SearchAllSongsPage`)

This appears to enumerate every list-of-songs surface in the app. No
additional song-list page was found that consumes `SongItemViewModel.create`
without threading `displayFileName`; spot-checked
`SongMenuDialogComponent.ets` and confirmed it consumes the row VM passed in
from the parent rather than building its own — so it inherits the parent
page's setting automatically.

## Final Assessment

**Overall Verdict**: PASS WITH MINOR NOTES

- **Fully covered scenarios**: 1, 2, 3.
- **Partially covered scenarios**: 4 — the file-name extraction matches the
  spec example exactly and handles the common URI form correctly, but two
  minor edge cases (literal `%` in non-URI paths, and the format-suffix
  fallback path) merit either a comment or a unit test to lock the behavior
  in. Neither prevents the spec from working as described.
- **Not covered scenarios**: none.

**Recommended Priority Fixes**:

1. (Optional / low priority) Add a `fileNameFromPath` unit test with the
   exact spec example and the empty/null/trailing-slash inputs to prevent
   future regressions.
2. (Optional / low priority) If `Track.path` is ever expected to hold plain
   filesystem paths rather than URIs, gate the `decodeURIComponent` call
   behind `raw.includes('%')` (or change the contract documentation to say
   "URI form only").

No blocking issues.
