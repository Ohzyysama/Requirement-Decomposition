# Implementation Plan — Main Page Wallpaper (spec2)

Spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec2/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`
Branch at time of planning: `wsh-release-3`

## 0. Baseline (repo reality)

The feature is already scaffolded. Verified from source:

- View: `entry/src/main/ets/pages/MainWallpaperPage.ets`
  - HdsNavDestination + MINI title mode (matches secondary-page memory).
  - `@StorageLink('mainPageWallpaperPath') wallpaperPath: string = ''` — reader for preview + Remove row visibility.
  - "Select image" row calls `vm.selectImage(ctx)`.
  - "Remove" row calls `vm.removeWallpaper()` (shown only when path is non-empty).
- ViewModel: `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`
  - `selectImage(ctx)` → `photoAccessHelper.PhotoViewPicker.select()` → `copyToSandbox()` → `applyPath(dest)`.
  - Empty-selection early-return already present (scene 3).
  - `copyToSandbox()` writes to `${filesDir}/main_wallpaper_${Date.now()}${ext}` and calls `cleanupOldFiles(keepPath)` which deletes every sibling `main_wallpaper_*` except the one just copied (scene 2 old-file cleanup).
  - `removeWallpaper()` currently only `applyPath('')`.
  - `applyPath(path)` → `SettingsStore.getInstance().save(KEY, path)` → AppStorage + Preferences memory cache.
- Nav entry: `UserInterfacePage.ets` line 166 → `navPathStack.pushPath({ name: 'MainWallpaperPage' })`.
- Page map: `MainPage.ets` line 842 registers `MainWallpaperPage`.
- Background layer: `MainPage.ets` lines 408–414 — the Main Content `Stack` renders `Image(this.mainPageWallpaperPath)` at `ImageFit.Cover` behind the main Column; bound via `@StorageProp('mainPageWallpaperPath')`.
- Persistence: `EntryAbility.ets`
  - Line 90: `PersistentStorage.persistProp('mainPageWallpaperPath', '')`.
  - Line 132: `AppStorage.setOrCreate('mainPageWallpaperPath', ss.get('mainPageWallpaperPath', '') as string)` — restores from `SettingsStore` on startup.
  - Line 430: `SettingsStore.getInstance().flush()` in `onBackground()` — flushes writes to disk.
- Other surfaces: `PlayerPage.ets` and PlayQueue screens do **not** bind `mainPageWallpaperPath` — scene 5 already satisfied by construction.

## 1. MVVM owner boundary (must stay explicit)

| Layer | Owner | Responsibility |
|---|---|---|
| View — `MainWallpaperPage` | UI + navigation | Renders preview (`@StorageLink wallpaperPath`), shows/hides Remove row, calls VM actions, obtains `UIAbilityContext` and passes it in. |
| View — `UserInterfacePage` | UI + navigation | Pushes `MainWallpaperPage` onto the nav stack. |
| View — `MainPage` | UI + lifecycle | Reads `@StorageProp('mainPageWallpaperPath')` and paints it under the Main Content Stack. No persistence, no mutation. |
| ViewModel — `MainWallpaperViewModel` | Actions | Image picker flow, sandbox copy, cleanup of old files, clear state on remove, busy-guard. Does not touch UI directly. |
| Model — `SettingsStore` | Persistence | Single write path for `mainPageWallpaperPath` → AppStorage (live) + Preferences memory cache (durable after flush). |
| Model — `EntryAbility` | Bootstrap | Persists the key, restores it on startup, flushes on background. |

Rules honored:
- Persistence stays in the `SettingsStore` owner path — no new writers in Page.
- `aboutToAppear` is not used as a live-sync bridge. The cross-page binding uses `@StorageProp` / `@StorageLink`, which is framework-level live.
- No mirror state or fake default; `MainPage` and `MainWallpaperPage` both bind the same AppStorage key.
- Writer: `MainWallpaperViewModel.applyPath()` → `SettingsStore.save('mainPageWallpaperPath', ...)`.
- Readers: `MainPage` (background paint), `MainWallpaperPage` (preview + Remove-row gating).
- Binding path: AppStorage key `mainPageWallpaperPath` (PersistentStorage-backed).
- Refresh path: `SettingsStore.save()` flips AppStorage immediately → `@StorageLink` / `@StorageProp` observers re-render synchronously.

## 2. Gap analysis against the spec

Scenes 1, 2, 3, 5, 6 are met by current code. One real gap:

**Scene 4, step 4 — delete the saved wallpaper file from the sandbox on remove.**
Current `removeWallpaper()` only clears the path; the old `main_wallpaper_*` file is left behind in `filesDir`. Scenes 1 and 2 work because `cleanupOldFiles` runs inside `copyToSandbox`; on pure remove (no new file), cleanup never runs. Fix: extend `removeWallpaper(context)` to read the current path, clear it first, then unlink the file if it matches the `main_wallpaper_` prefix under `filesDir`. Make cleanup best-effort (non-fatal on failure) to stay consistent with existing `cleanupOldFiles`.

Secondary improvements (low risk, same owner path):
- Pass `UIAbilityContext` to `removeWallpaper()` from the View, same pattern `selectImage()` already uses.
- In `MainWallpaperViewModel`, read the current path from AppStorage (not from a mirror field) to avoid stale state.
- Optional hardening: sweep any stray `main_wallpaper_*` files on remove (covers the edge case where multiple files accumulated if a prior run crashed mid-copy).

No other scene requires code changes.

## 3. Change set

### 3.1 `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`

1. Change `removeWallpaper()` signature to accept `context: common.UIAbilityContext`.
2. Implementation:
   - Read `currentPath` from `AppStorage.get<string>('mainPageWallpaperPath') ?? ''`.
   - Call `applyPath('')` first so the UI (MainPage background, preview, Remove row visibility) updates before filesystem work.
   - Best-effort delete via a new private helper `deleteAllWallpaperFiles(context)` that enumerates `filesDir`, unlinks every `main_wallpaper_*` entry, and swallows errors. Covers both the current path and any stragglers.
   - Wrap in try/catch with hilog.error like `selectImage`; no toast on failure (silent cleanup matches `cleanupOldFiles` behavior).
3. Keep `applyPath(path)` as the single persistence entry point — unchanged.
4. Keep `copyToSandbox` / `cleanupOldFiles` unchanged. They already cover scene 2.
5. Busy-guard: reuse `this.busy` around `removeWallpaper` so rapid double-tap cannot race with an in-flight `selectImage`.

### 3.2 `entry/src/main/ets/pages/MainWallpaperPage.ets`

1. In the Remove `HdsListItemCard.onClick`, resolve `UIAbilityContext` the same way `selectImage` does and pass it in:
   ```
   const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
   this.vm.removeWallpaper(ctx)
   ```
2. No other changes. Preview binding, navigation, title bar all match the secondary-page style memory.

### 3.3 No changes to `MainPage.ets`, `UserInterfacePage.ets`, `EntryAbility.ets`, or `SettingsStore.ets`

- `MainPage` background painter is correct; `@StorageProp('mainPageWallpaperPath')` gives live refresh when the VM writes through `SettingsStore.save()`.
- `UserInterfacePage` already pushes `MainWallpaperPage`.
- `EntryAbility` already persists, restores, and flushes the key.
- `SettingsStore` already writes AppStorage + Preferences memory cache; flush on background is in place.

## 4. Scene-by-scene traceability

| Scene | Trigger | Writer | Reader(s) | Refresh |
|---|---|---|---|---|
| 1 (first set) | `MainWallpaperPage` Select row → `vm.selectImage(ctx)` | `applyPath()` → `SettingsStore.save()` | `MainPage` `@StorageProp`, `MainWallpaperPage` `@StorageLink` | Immediate via AppStorage observer |
| 2 (replace) | Same as scene 1; `cleanupOldFiles(keepPath)` deletes previous files | Same | Same | Same |
| 3 (cancel picker) | `result.photoUris.length === 0` early return; `busy` reset in `finally` | — | — | No change |
| 4 (remove) | Remove row → `vm.removeWallpaper(ctx)` | `applyPath('')` then `deleteAllWallpaperFiles()` | Same | Preview switches to placeholder, Remove row hides (`wallpaperPath.length > 0`), MainPage background clears |
| 5 (scope) | N/A — player/queue screens do not bind the key | — | Only `MainPage` and `MainWallpaperPage` | — |
| 6 (restart) | `EntryAbility.onCreate` | `ss.get('mainPageWallpaperPath', '')` → `AppStorage.setOrCreate` | Both readers bind the key on first render | PersistentStorage + Preferences both seeded at startup |

## 5. Risks / notes

- `MainPage`'s Image reload after replace: `@StorageProp` + `Image(this.mainPageWallpaperPath)` will re-render because the path string changes (timestamped filename). No extra key needed.
- `fileIo.listFileSync` on `filesDir` runs on the UI thread in `cleanupOldFiles`. Scope is tiny (only `main_wallpaper_*` files) and already in use; keep the same pattern for `deleteAllWallpaperFiles`.
- Do **not** introduce a Page-side mirror of `mainPageWallpaperPath`. The VM must read through AppStorage, not hold its own copy, to avoid drift.
- Do **not** move the filesystem work into `aboutToAppear` or `aboutToDisappear` — those are one-shot lifecycle callbacks and would break the live-refresh contract.
- `SettingsStore.save()` performs a `putSync` into the in-memory cache; disk persistence happens in `onBackground` via `flush()`. This is acceptable because `PersistentStorage.persistProp('mainPageWallpaperPath', '')` also provides a parallel persistence path. Restart durability is already covered in production.

## 6. Verification

Manual walkthrough against the spec, in this order:

1. Scene 1: Settings → User Interface → 主界面壁纸 → Select → pick photo → main screen background applies. Re-enter Settings, background still visible under list cards.
2. Scene 2: Repeat selection with a different photo → preview + MainPage background update; inspect `filesDir` — only one `main_wallpaper_*` file present.
3. Scene 3: Open picker, press back → no toast, no path change, Remove row stays as it was.
4. Scene 4: With a wallpaper set, tap Remove → preview shows placeholder, Remove row disappears, MainPage background clears, `filesDir` has no `main_wallpaper_*` file.
5. Scene 5: With wallpaper set, open player and play queue → neither shows the main wallpaper.
6. Scene 6: With wallpaper set, kill the app, relaunch → MainPage shows the same wallpaper; MainWallpaperPage preview shows the same image.

Build verification: run the project build (see Stage 5) after the edits; no new imports beyond what `MainWallpaperViewModel.ets` already uses (`@kit.CoreFileKit` `fileIo`, `@kit.AbilityKit` `common`).

## 7. Out of scope

- No new string resources (`wallpaper_of_main_screen`, `wallpaper_of_main_interface_info`, `select_image`, `remove` already exist; verified at lines 2660, 3176, 3180 of `string.json`).
- No change to player/queue backgrounds — spec explicitly excludes them and repo already honors that.
- No migration: the key is already persisted in two paths; pre-existing installs need no data fix-up.
