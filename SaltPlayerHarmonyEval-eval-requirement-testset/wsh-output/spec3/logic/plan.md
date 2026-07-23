# Implementation Plan — Delete Main Wallpaper Confirmation (spec3)

Spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec3/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`
Branch at time of planning: `wsh-release-3`

## 0. Baseline (repo reality, verified from source)

The wallpaper feature is already wired end-to-end from spec2. Current state, verified:

- View: `entry/src/main/ets/pages/MainWallpaperPage.ets`
  - `HdsNavDestination` + `MINI` title mode (matches secondary-page memory; no `BasicScreen`, no manual status-bar padding).
  - `@StorageLink('mainPageWallpaperPath') wallpaperPath: string = ''` is the reader for "Remove row" visibility.
  - Remove row (`ActionsSection()` lines 90–106) uses `$r('app.string.delete_current_image')` ("删除当前图片").
  - On click it calls `this.vm.removeWallpaper(ctx)` **directly** — no confirmation step today.
  - The row is rendered only when `this.wallpaperPath.length > 0`, so scene 4 ("not set → button hidden") is already satisfied by the existing `if` guard.
- ViewModel: `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`
  - `removeWallpaper(context)` already: clears the path via `applyPath('')` first, then best-effort sweeps `filesDir` for any `main_wallpaper_*` leftovers via `deleteAllWallpaperFiles()`. Errors from `unlinkSync` are swallowed (scene 3 — missing file — already tolerated by `try/catch` around each `unlinkSync`).
  - `applyPath()` is the single write path and delegates to `SettingsStore.getInstance().save(KEY, path)` (AppStorage + Preferences memory cache).
  - `@Track busy` guards against concurrent actions.
- Model: `entry/src/main/ets/model/SettingsStore.ets`
  - `save()` updates `AppStorage` immediately, then `putSync` to the Preferences memory cache. Disk flush is done in `EntryAbility.onBackground()`.
- Bootstrap: `entry/src/main/ets/entryability/EntryAbility.ets` — persists the key (line 90), restores it on startup (line 132), flushes on background.
- Background reader: `entry/src/main/ets/pages/main/MainPage.ets` — `@StorageProp('mainPageWallpaperPath')` renders `Image(path)` at `ImageFit.Cover` in the Main Content Stack. Auto-refreshes when the key flips.
- Strings: `delete_current_image`, `wallpaper_of_main_screen`, `wallpaper_of_main_interface_info`, `cancel`, `confirm` — all already present in `resources/base/element/string.json`. No new strings required.
- Dialog reference implementations in the repo: `DeletePlaylistDialog.ets`, `DeleteSongDialog.ets`, `ReBecomeDialog.ets` — all `@CustomDialog` opened via `CustomDialogController` from the owning Page, with `onConfirm: () => void` callback and `controller.close()` wiring.

**Gap vs. spec3**: scenes 1, 2, 3 explicitly require a confirmation dialog between the Remove tap and the actual delete. Today the Remove tap deletes immediately — no dialog. That is the only behavioral gap. Scene 4 (button hidden when unset) is already correct.

## 1. MVVM owner boundary (must stay explicit)

| Layer | Owner | Responsibility |
|---|---|---|
| View — `MainWallpaperPage` | UI + navigation + dialog hosting | Owns the `CustomDialogController` instance for the new confirm dialog. Opens it when the Remove row is tapped. Passes `onConfirm` that calls `vm.removeWallpaper(ctx)`. Reads `@StorageLink('mainPageWallpaperPath')` to keep the row gated. |
| View — `DeleteWallpaperDialog` (new component) | UI only | Pure presentational `@CustomDialog`: title, body sentence, Cancel/Confirm buttons. No state, no persistence, no AppStorage reads. Fires `onConfirm` then closes the controller. Cancel path just closes the controller. |
| ViewModel — `MainWallpaperViewModel` | Actions + state | `removeWallpaper(ctx)` unchanged in contract. Still the **only** caller of `applyPath('')` and `deleteAllWallpaperFiles()`. Retains `busy` guard. |
| Model — `SettingsStore` | Persistence | Single writer path (`save('mainPageWallpaperPath', '')`). Unchanged. |
| Model — `EntryAbility` | Bootstrap | Unchanged. |

Rules honored:
- Persistence stays inside the existing `MainWallpaperViewModel → SettingsStore` owner path. The new dialog does not persist, does not touch AppStorage, and does not do file IO.
- `aboutToAppear` is used only for the opacity fade-in in the new dialog (presentation), matching `DeletePlaylistDialog` and `DeleteSongDialog`. Not used as a live-sync bridge.
- No mirror state, no fake default. The cross-page binding remains `mainPageWallpaperPath` in AppStorage (PersistentStorage-backed).
- Writer: `MainWallpaperViewModel.applyPath('')` → `SettingsStore.save('mainPageWallpaperPath', '')`.
- Readers: `MainPage` (`@StorageProp` — background image), `MainWallpaperPage` (`@StorageLink` — Remove-row gate).
- Binding path: AppStorage key `mainPageWallpaperPath`.
- Refresh path: unchanged. `SettingsStore.save()` flips AppStorage → framework observers re-render synchronously on both pages.

## 2. Change set

### 2.1 New file — `entry/src/main/ets/components/DeleteWallpaperDialog.ets`

Styled after `DeletePlaylistDialog.ets` (same visual shell: title, body text, Cancel/Confirm row, fade-in, 16 radius, 24 side padding).

Signature:
```
@CustomDialog
export struct DeleteWallpaperDialog {
  controller: CustomDialogController
  onConfirm: () => void = () => {}
  @State private contentOpacity: number = 0

  aboutToAppear(): void { ... fade-in ... }

  build() { Column { Title Text, Body Text, Row{ Cancel, Blank, Confirm } } }
}
```

Text bindings:
- Title: `$r('app.string.delete_current_image')` ("删除当前图片") — reuses existing string; title mirrors the action the user is about to confirm.
- Body: `$r('app.string.wallpaper_of_main_screen')` wrapped with a short literal "吗?" is not acceptable (would hard-code). Instead, use the title plus a neutral short body: reuse `$r('app.string.delete_current_image')` as the body sentence — consistent with `DeletePlaylistDialog`, which only shows the `playlistName` in the body. Since the spec body is just the confirmation question, the title already conveys the intent; keep the body line to reuse `$r('app.string.delete_current_image')` to avoid introducing any new string resource.
- Cancel: `$r('app.string.cancel')`.
- Confirm: `$r('app.string.confirm')`.

Behavior:
- Cancel tap → `controller.close()`. Dialog never calls any VM method or Model. Scene 2 complete.
- Confirm tap → `onConfirm()` then `controller.close()`.

Styling tokens reused (already in repo): `app.color.salt_color_icon_foreground`, `app.color.salt_color_sub_text`, `app.color.salt_color_sub_background`, `app.color.salt_color_high_light`, `app.color.salt_color_dialog_background`.

### 2.2 Edit — `entry/src/main/ets/pages/MainWallpaperPage.ets`

Changes localized to the View layer (no logic leaks):

1. Add import:
   - `import { DeleteWallpaperDialog } from '../components/DeleteWallpaperDialog'`
2. Add a private controller field on the `@Component`:
   - `private deleteDialogController?: CustomDialogController`
3. In `ActionsSection()`, replace the Remove `ListItem` `onClick` body. New flow:
   - Capture `ctx = this.getUIContext().getHostContext() as common.UIAbilityContext`.
   - Instantiate `this.deleteDialogController = new CustomDialogController({ builder: DeleteWallpaperDialog({ controller: this.deleteDialogController as CustomDialogController, onConfirm: () => this.vm.removeWallpaper(ctx) }), alignment: DialogAlignment.Center, customStyle: true, maskColor: '#80000000', openAnimation: { duration: 0 }, closeAnimation: { duration: 0 } })` — same shape PlaylistContentPage uses for `DeleteSongDialog`.
   - `this.deleteDialogController.open()`.
4. Keep the `if (this.wallpaperPath.length > 0)` guard around the Remove row exactly as-is (scene 4).
5. Keep `enable: !this.vm.busy` so a stale busy state still suppresses the tap.

### 2.3 ViewModel — `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`

**No changes.** `removeWallpaper(context)` already does exactly what scenes 1 and 3 require:
- Scene 1 step 6–8: `applyPath('')` flips the key → `MainWallpaperPage` Remove-row hides and `MainPage` drops the Image. `deleteAllWallpaperFiles(context)` unlinks the sandbox copy.
- Scene 3 step 6–8: `deleteAllWallpaperFiles()` wraps each `unlinkSync` in `try/catch` and swallows errors, so a missing file is tolerated. `applyPath('')` still clears the config.

### 2.4 Strings — `entry/src/main/resources/base/element/string.json` and locale variants

**No changes.** All required strings exist already (`delete_current_image`, `cancel`, `confirm`).

### 2.5 EntryAbility / persistence / background reader

**No changes.** Persistence path already covers the scenarios; spec3 is entirely a UX-gate change on top of spec2.

## 3. Scene-by-scene traceability

| Scene | Trigger | Owner-path | Readers refreshed |
|---|---|---|---|
| 1 (confirm delete, file exists) | `MainWallpaperPage` Remove row tap → opens `DeleteWallpaperDialog` → Confirm → `onConfirm` = `vm.removeWallpaper(ctx)` → `applyPath('')` → `SettingsStore.save` → `deleteAllWallpaperFiles(ctx)` unlinks sandbox copy | View opens dialog. VM owns action. Model owns persistence. | `MainPage` (`@StorageProp`) drops background image. `MainWallpaperPage` (`@StorageLink`) hides Remove row. |
| 2 (cancel) | Remove row tap → dialog opens → Cancel → `controller.close()` | Dialog only. VM/Model untouched. | None — path unchanged. |
| 3 (confirm delete, file missing) | Same as scene 1; `deleteAllWallpaperFiles()`'s per-entry `try/catch` swallows `unlinkSync` failure on a vanished file | Same | Same as scene 1 — path still cleared. |
| 4 (no wallpaper → no button) | `if (this.wallpaperPath.length > 0)` guard in `ActionsSection()` already in place | View | N/A |

## 4. Risks / notes

- **String reuse for dialog body.** We deliberately reuse `delete_current_image` for both title and body to avoid introducing a new string key. This matches the existing pattern in `DeletePlaylistDialog`, which uses a single data-driven line. If the product later wants a separate confirmation sentence, adding a new `app.string.delete_current_image_confirm` is a one-line resource addition with no code-shape change.
- **Dialog controller lifetime.** `CustomDialogController` is constructed inside the `onClick` (same pattern as `PlaylistContentPage.DeleteSongDialog`). The reference is stored on `this.deleteDialogController` so the `controller` field passed into the builder matches. This mirrors proven patterns already merged.
- **Busy-guard interaction.** `vm.busy` is checked by the View via `enable: !this.vm.busy`. The confirm path calls `vm.removeWallpaper(ctx)` which re-checks `this.busy` at the top — double-defense.
- **No new persistence writers.** Only the existing `SettingsStore.save` path remains.
- **No lifecycle abuse.** `aboutToAppear` is used only for opacity fade-in inside the new dialog (UX polish), not for state sync.
- **Scope isolation.** `PlayerPage` and play-queue screens do not bind `mainPageWallpaperPath`; the key's readership is strictly `MainPage` + `MainWallpaperPage`. Unchanged by this spec.

## 5. File touch list

- New: `entry/src/main/ets/components/DeleteWallpaperDialog.ets`
- Edited: `entry/src/main/ets/pages/MainWallpaperPage.ets`
- Untouched (confirmed): `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`, `entry/src/main/ets/model/SettingsStore.ets`, `entry/src/main/ets/entryability/EntryAbility.ets`, `entry/src/main/ets/pages/main/MainPage.ets`, `entry/src/main/resources/**/element/string.json`.

## 6. Verification plan

1. Build `entry` to confirm no type errors (`@CustomDialog` signature, `CustomDialogController` init order).
2. Manual trace against each scene in section 3 via reading the diff — matches control flow exactly.
3. Runtime check on device (picked up in Stage 7 self-test): set a wallpaper; tap Remove → dialog appears; Cancel → row and background persist; Remove → Confirm → row hides, `MainPage` background resets, sandbox file gone; with file manually removed from sandbox, repeat — no crash, still clears config.
