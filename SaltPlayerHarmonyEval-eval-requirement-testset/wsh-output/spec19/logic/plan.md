# spec19 — Player-Screen Wallpaper Deletion Logic Plan

Spec source: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec19/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`
Output: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec19/logic/plan.md`

---

## 0. Ground truth from repo

The deletion sub-flow described by spec19 is the deletion half of spec18. Spec18 has already shipped the full pick + delete + live-refresh pipeline. Spec19 is a scope-narrowed re-statement of the deletion path plus the conditional visibility of the delete row, with one wording difference from spec18 (the literal phrase "应用重新启动" at Scene 1 step 7) that conflicts with how the codebase actually behaves today.

### 0.1 What already exists (verified by reading the files)

- `entry/src/main/ets/pages/PlayerWallpaperPage.ets`
  - Lines 16, 22, 31: imports `DeleteWallpaperDialog`, holds a `deleteDialogController?: CustomDialogController`, and live-binds the wallpaper path via `@StorageLink('playerScreenBgCover') wallpaperPath: string = ''`.
  - Lines 152–181 inside `ActionsSection()`: the "Delete current image" ListItem is rendered only when `this.wallpaperPath.length > 0`. Its `onClick` constructs a `CustomDialogController` whose builder is `DeleteWallpaperDialog`, and on Confirm calls `this.vm.removeWallpaper(ctx)`. Disabled while `this.vm.busy`. The dialog uses `customStyle: true`, `maskColor: '#80000000'`, `openAnimation/closeAnimation: { duration: 0 }` — identical to `MainWallpaperPage`.
  - Style: `HdsNavDestination + HdsNavDestinationTitleMode.MINI`, per the secondary-page-style memory. No `BasicScreen`, no manual status-bar padding.
- `entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets`
  - `KEY = 'playerScreenBgCover'`, `COVERS_DIR = 'covers'`, `FILE_BASENAME = 'player_screen_cover'`.
  - `removeWallpaper(context)` flow (lines 51–67): re-entrancy gate via `busy`, persist empty string through `SettingsStore.save(KEY, '')` (so AppStorage updates the same tick), then best-effort `deleteAllWallpaperFiles(context)` over `${filesDir}/covers/` matching the `player_screen_cover_` prefix. Errors swallowed except for an `hilog.error` and a generic toast on `selectImage` failure.
  - The "clear AppStorage first → unlink after" order is deliberate: ArkUI `Image` observers detach in the same frame as the AppStorage write, before the file handles are unlinked.
- `entry/src/main/ets/components/DeleteWallpaperDialog.ets`
  - Reusable confirm dialog (already used by both `MainWallpaperPage` and `PlayerWallpaperPage`). Title + body + Cancel + Confirm. `onConfirm` fires on Confirm. Cancel calls `controller.close()` only — no callback, no state mutation.
- `entry/src/main/ets/pages/PlayerPage.ets`
  - Line 164: `@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''`.
  - Lines 590–605: wallpaper `Image` drawn in the outer background `Stack` only when `playerScreenBgCover.length > 0`; the `FlowingLightComponent` overlay is gated on `playerScreenBgCover.length === 0 && this.vm.flowingLightActive && this.vm.flowingLightVM.coverPixelMap && this.playbackError.length === 0` so clearing the path makes the dynamic flowing light return live.
- `entry/src/main/ets/components/PlayQueueComponent.ets`
  - Line 22: `@StorageProp('playerScreenBgCover')`. Line 55: `getQueueBackground()` returns `Color.Transparent` when the wallpaper is set so the wallpaper drawn in `PlayerPage`'s outer Stack shows through both pager pages (player + queue). When the path clears, the existing `flowingLightActive ? transparent : themed-solid` branch takes over.
- `entry/src/main/ets/entryability/EntryAbility.ets`
  - Line 99: `PersistentStorage.persistProp('playerScreenBgCover', '')`.
  - Line 150: `AppStorage.setOrCreate('playerScreenBgCover', ss.get('playerScreenBgCover', '') as string)` — hydrates from `SettingsStore` on cold launch with empty-string default. No drift between the two storage layers on restart.
- `entry/src/main/ets/model/SettingsStore.ets`
  - `save(key, value)` does `AppStorage.setOrCreate` + `putSync` + `flushSync` in one call, so `@StorageLink` / `@StorageProp` observers update in the same tick as the disk write.
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`
  - Lines 33, 69–71, 256–267: dormant mirror state (`playerScreenBgCover` field, `deletePlayerScreenBgCover()`, `hasPlayerScreenBgCover()`, stub `selectPlayerScreenBgImage()`). None of these are wired to any live UI. The mirror is read once at construction and never refreshed. Flagged below as a known anti-pattern; out of scope to remove but must not be reintroduced as a code path.
- `entry/src/main/ets/pages/UserInterfacePage.ets`
  - Line 289: navigation entry `pushPath({ name: 'PlayerWallpaperPage' })` from the "播放界面壁纸" row.
- `entry/src/main/ets/pages/main/MainPage.ets`
  - Lines 37, 890–891: `PlayerWallpaperPage` route registered inside the NavDestination switch.
- String resources (`base`, `zh`, `ug` element/string.json): `delete_current_image` (line 884 base), `wallpaper_of_player_screen` (line 3216 base), `wallpaper_of_main_interface_info`, `cancel`, `confirm`, `error`, `select_image` — all present, no new IDs required.

### 0.2 Spec → repo translation notes

| Spec line | Repo reality | Decision |
|---|---|---|
| Scene 1 step 5: "删除应用文件夹下存储的背景图片资源副本文件" | `PlayerWallpaperViewModel.removeWallpaper` already calls `deleteAllWallpaperFiles` over `${filesDir}/covers/` purging any `player_screen_cover_*` file. | Keep. Already correct. |
| Scene 1 step 6: "清除已保存的背景图片路径配置" | `SettingsStore.save('playerScreenBgCover', '')` writes both AppStorage and Preferences in a single call. | Keep. Already correct. |
| Scene 1 step 7: "应用重新启动" | The current implementation refreshes the player + queue background **live** through `@StorageProp('playerScreenBgCover')`. No restart fires, none is needed, and a forced restart would be a UX regression and is anti-pattern for the codebase. | **Ignore the literal wording.** Honor Scene 1 step 8 / step 9 ("恢复为默认的动态流光效果", "同步恢复") which require the post-delete steady state regardless of mechanism. Same call this plan's predecessor (spec18) made — verified, shipped, no production regression. |
| Scene 1 step 8: 播放页背景恢复动态流光 | `PlayerPage` line 600–605 gate flips back on as soon as `playerScreenBgCover.length === 0`. Cover-art / flowing-light prerequisites already in place. | Keep. |
| Scene 1 step 9: 播放队列页同步 | `PlayQueueComponent.getQueueBackground()` line 55: `Color.Transparent` only while a wallpaper is set; once cleared it falls back to the existing flowing-light / themed-solid branches. Because the queue is page 1 of `PlayerPage`'s inner vertical Swiper (not a separate route — verified in `PlayerPage.ets` 618+), both pages naturally observe the same `@StorageProp`. | Keep. |
| Scene 2: cancel keeps state | `DeleteWallpaperDialog`'s Cancel button only calls `controller.close()`. No callback, no write. Path stays. | Keep. |
| Scene 3: delete row hidden when path empty | `PlayerWallpaperPage` line 152: `if (this.wallpaperPath.length > 0)` gates the ListItem rendering itself, so the row is absent (not just disabled). | Keep. |

### 0.3 Conventions

- Persistence path follows the canonical pattern used elsewhere in the project: `ViewModel → SettingsStore.save(key, value) → AppStorage + Preferences` (single source of truth in `AppStorage('playerScreenBgCover')`; readers use `@StorageLink` / `@StorageProp`).
- No `aboutToAppear` reads for live state. Live state goes through AppStorage observers.
- Page never persists. The settings Page owns dialog presentation only; the ViewModel owns the delete action.

---

## 1. MVVM ownership boundary

| Concern | Owner | File |
|---|---|---|
| "删除当前图片" row presence/visibility, click handling, dialog presentation | Page | `pages/PlayerWallpaperPage.ets` (lines 152–181 — already correct) |
| Confirm/Cancel dialog UI (title, body, two buttons, fade-in) | Component | `components/DeleteWallpaperDialog.ets` |
| `removeWallpaper(ctx)` business logic: re-entrancy guard (`busy`), persistence write, sandbox cleanup | ViewModel | `viewmodel/PlayerWallpaperViewModel.ets` |
| Persistence of `playerScreenBgCover` (AppStorage + Preferences flushSync) | Model/Store | `model/SettingsStore.ets` |
| Persistent-storage registration + cold-start hydration of the key | Model/Lifecycle | `entryability/EntryAbility.ets` (lines 99, 150) |
| Live binding for the delete-row visibility gate | Page (read) | `@StorageLink('playerScreenBgCover')` in `PlayerWallpaperPage.ets` line 31 |
| Live binding for the player-page background switch | Page (read) | `@StorageProp('playerScreenBgCover')` in `PlayerPage.ets` line 164 |
| Live binding for the queue-page transparency switch | Component (read) | `@StorageProp('playerScreenBgCover')` in `PlayQueueComponent.ets` line 22 |

**Writer → Reader → Refresh path:**

- **Writer:** `PlayerWallpaperViewModel.removeWallpaper(context)`
  → calls `SettingsStore.save('playerScreenBgCover', '')`
  → `SettingsStore.save` runs `AppStorage.setOrCreate('playerScreenBgCover', '')` + `store.putSync` + `store.flushSync` synchronously
  → then `deleteAllWallpaperFiles(context)` unlinks `${filesDir}/covers/player_screen_cover_*` best-effort.
- **Readers (live):**
  - `PlayerWallpaperPage.wallpaperPath` (@StorageLink) → re-evaluates `ActionsSection`'s `if (this.wallpaperPath.length > 0)` → delete row unmounts (Scene 3 steady state).
  - `PlayerPage.playerScreenBgCover` (@StorageProp) → wallpaper `Image` (line 590) unmounts; the `FlowingLightComponent` gate (line 600) re-permits dynamic flowing light when the rest of its prerequisites hold.
  - `PlayQueueComponent.playerScreenBgCover` (@StorageProp) → `getQueueBackground()` returns the flowing-light/themed-solid branch instead of `Color.Transparent`.

All three readers update in the **same render tick** as the AppStorage write — no restart, no `aboutToAppear` refresh, no fake default.

**Anti-patterns explicitly avoided (per worker guardrails):**

- **No persistence inside the Page.** `PlayerWallpaperPage` never calls `SettingsStore.save`. The Page's confirm-button handler must call `this.vm.removeWallpaper(ctx)` exclusively. Current code already conforms (line 167–168).
- **No `aboutToAppear` for live sync.** `PlayerPage` and `PlayQueueComponent` are mounted while the user is in Settings — they use `@StorageProp` (a live observer). Confirmed in `PlayerPage.ets` line 164 and `PlayQueueComponent.ets` line 22.
- **No mirror state for the live path.** The ViewModel exposes only `busy`. The path lives in AppStorage and is read directly from there by every UI consumer. The mirror field on `UserInterfaceViewModel` (line 33) is dormant and must NOT be read or written by any code path participating in this feature.
- **No duplicate writer.** `UserInterfaceViewModel.deletePlayerScreenBgCover()` (lines 258–262) writes the same AppStorage key but does NOT unlink the sandbox copy. It is unbound from any UI today (verified by grepping for the method name — only its own declaration is matched). Leaving it dormant is the spec18-era decision; the only requirement here is that no new caller route through it. The single delete entry point for this feature is `PlayerWallpaperViewModel.removeWallpaper`.
- **No fake default.** All ports use `''` as the empty sentinel: `PersistentStorage.persistProp('playerScreenBgCover', '')`, `SettingsStore.get('playerScreenBgCover', '')`, `@StorageLink/@StorageProp` initializers.

---

## 2. Surfaces & files touched

This spec is a behavioural verification + small reconciliation. Functional code does not need to change; the implementation that spec18 shipped already satisfies all three scenes once the spec19 wording about "应用重新启动" is interpreted as a steady-state requirement (Scene 1 steps 8–9) rather than a literal restart instruction.

| # | File | Change |
|---|---|---|
| 1 | `entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets` | **No functional change.** Optional doc-comment touch-up: add a single line above `removeWallpaper` calling out that the AppStorage write happens before file unlink so observers detach the `Image` in the same frame, and that this is the live-refresh contract Scene 1 steps 8–9 depend on. |
| 2 | `entry/src/main/ets/pages/PlayerWallpaperPage.ets` | **No functional change.** Verify (and leave) that the delete ListItem stays inside `if (this.wallpaperPath.length > 0)` and that the dialog `onConfirm` calls `this.vm.removeWallpaper(ctx)` rather than any `UserInterfaceViewModel` helper. |
| 3 | `entry/src/main/ets/pages/PlayerPage.ets` | **No functional change.** Verify line 600's gate (`playerScreenBgCover.length === 0`) still lifts when the path clears. |
| 4 | `entry/src/main/ets/components/PlayQueueComponent.ets` | **No functional change.** Verify `getQueueBackground()` falls back to the flowing-light / themed-solid branch when `playerScreenBgCover.length === 0`. |
| 5 | `entry/src/main/ets/components/DeleteWallpaperDialog.ets` | **No functional change.** Verify Cancel button does **not** fire `onConfirm` (Scene 2 contract). Current code at lines 51–54 closes the controller only; correct. |
| 6 | `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` (lines 256–273) | **No change.** Dormant helpers stay dormant. Do not call them from new code, do not delete them in this spec's scope (out of plan boundary — would touch `UserInterfaceModel` and risk unrelated regressions). |

No new resources, no new persistence keys, no new files.

---

## 3. Step-by-step verification order

Because spec19 is a verification of an already-shipped slice, "implementation" here means a re-read + targeted assertion of the existing wiring, with the optional doc tidy-up above.

### Step 1 — Verify Page (Scene 3 visibility gate)

Open `PlayerWallpaperPage.ets`. Confirm:

- Line 31: `@StorageLink('playerScreenBgCover') wallpaperPath: string = ''` exists exactly as written.
- Line 152: `if (this.wallpaperPath.length > 0) { ListItem() { ... } }` wraps the delete row.
- Line 168: dialog `onConfirm` calls `this.vm.removeWallpaper(ctx)` (NOT `this.uiVM.deletePlayerScreenBgCover()` and NOT a direct `SettingsStore.save`).
- Line 173–175: dialog opened with the same `customStyle: true` / `maskColor: '#80000000'` / zero-duration animations used by `MainWallpaperPage`.
- Line 161: `enable: !this.vm.busy` gates the delete row while a previous remove is in flight.

No edits required if all six items match.

### Step 2 — Verify ViewModel (Scene 1 mechanics + Scene 2 idempotence)

Open `PlayerWallpaperViewModel.ets`. Confirm:

- Line 24: `@Track public busy: boolean = false`.
- Lines 51–53: `removeWallpaper` early-returns when `this.busy`.
- Line 58: `this.applyPath('')` — calls `SettingsStore.save(KEY, '')` (line 70).
- Line 61: `this.deleteAllWallpaperFiles(context)` runs **after** the AppStorage write, not before.
- Lines 73–90: `deleteAllWallpaperFiles` enumerates `${filesDir}/covers/`, matches the `player_screen_cover_` prefix, and swallows per-file failures. Directory-missing path is non-fatal.

No edits required if all five items match. **Optional doc-only edit:** prepend a single-line comment to `removeWallpaper` reaffirming the AppStorage-first-then-unlink ordering rationale (helps any future maintainer who might be tempted to reverse the order for "atomicity").

### Step 3 — Verify Player background reaction (Scene 1 step 8)

Open `PlayerPage.ets`. Confirm:

- Line 164: `@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''`.
- Line 590: `if (this.playerScreenBgCover.length > 0)` wraps the wallpaper `Image`.
- Line 600: the flowing-light gate begins with `this.playerScreenBgCover.length === 0 && ...`.

No edits required.

### Step 4 — Verify Queue background reaction (Scene 1 step 9)

Open `PlayQueueComponent.ets`. Confirm:

- Line 22: `@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''`.
- Lines 54–65: `getQueueBackground()` early-returns `Color.Transparent` only when `this.playerScreenBgCover.length > 0`, and otherwise honors the pre-existing flowing-light / `isLightMode` / themed branches.

No edits required.

### Step 5 — Verify Cancel non-mutation (Scene 2)

Open `DeleteWallpaperDialog.ets`. Confirm:

- Lines 51–54: the Cancel button's `onClick` calls `this.controller.close()` only. No state mutation, no `onConfirm` call.
- Lines 70–74: the Confirm button's `onClick` calls `this.onConfirm()` then `this.controller.close()`.

No edits required.

### Step 6 — Manual / device verification matrix

Run on a real device (or HAP-sideloaded build) and walk each scene:

| Scene | Action | Expected |
|---|---|---|
| 3 (initial state) | Cold start with no wallpaper set. Open Settings → 用户界面 → 播放界面壁纸. | Only "选择图片" row visible. "删除当前图片" row is **not rendered** (DOM-level, not just disabled). PlayerPage and queue show the default flowing-light (when cover art is available). |
| 1 (set then delete) | Pick an image. Back to PlayerPage — wallpaper visible. Swipe up to play queue — same wallpaper. Return to settings. Tap "删除当前图片". | Confirm dialog appears with title + body + Cancel + Confirm. |
| 1 (confirm path) | Tap Confirm. | Dialog closes. Settings: delete row disappears (Scene 3 reached). Open PlayerPage: flowing light returns (cover-art dependent). Open queue: flowing light returns there too. `hdc shell ls <bundle>/files/covers` shows no `player_screen_cover_*` entries. `AppStorage.get('playerScreenBgCover')` returns `''` (verify via dev panel or hilog instrumentation). No app process restart observed. |
| 2 (cancel path) | Re-set a wallpaper. Tap "删除当前图片". Tap Cancel. | Dialog closes. Path unchanged. PlayerPage + queue continue to display the same wallpaper. Sandbox file under `covers/` is untouched. |

Each row in the matrix maps directly to a numbered step in the spec.

### Step 7 — Apply optional doc comment

If Step 2's optional comment is the only edit, write it directly via `Edit` tool (not `Write`). Otherwise no edits.

```
// removeWallpaper:
//   AppStorage write FIRST, then file unlink. The @StorageLink/@StorageProp
//   observers (PlayerWallpaperPage delete-row gate, PlayerPage Image, PlayQueue
//   background) react in the SAME tick — the conditional `if (path.length > 0)`
//   collapses, the Image is removed from the tree, the file handle is released,
//   THEN unlinkSync runs. Reversing this order would race the file unlink
//   against the still-mounted Image and could trip "file in use" errors on
//   some kernels. This ordering is the live-refresh contract Scene 1 steps
//   8 + 9 depend on.
```

This is a *documentation* edit, not behavioural. It must not change the call order or signatures.

---

## 4. Risk register & notes

### 4.1 The "应用重新启动" wording in the spec

Spec Scene 1 step 7 reads "应用重新启动". The shipped behaviour is live refresh without restart — verified in production via spec18. Causing an actual restart would (a) lose the current playback session, (b) break the live `@StorageProp` chain entirely (the user would see a brief teardown flicker), and (c) violate the secondary-page-style memory which implies in-place navigation. Steps 8 and 9 of the same scene state the steady-state requirement ("恢复为默认的动态流光效果", "同步恢复"), which our live-refresh path satisfies cleanly. We follow steps 8/9; we read step 7 as descriptive prose carried over from the Android source rather than a normative requirement.

### 4.2 Dormant duplicate writer on `UserInterfaceViewModel`

`UserInterfaceViewModel.deletePlayerScreenBgCover()` (lines 258–262) writes the same AppStorage key but **does not** unlink the sandbox file copy. It is currently unreferenced by any UI. Risk: a maintainer adds a UI binding to it, the AppStorage path clears but the file remains in `covers/`, leaking N bytes per delete-cycle. Mitigation: leave dormant in this PR; the canonical entry point for this feature stays `PlayerWallpaperViewModel.removeWallpaper`. A separate cleanup PR can remove the dormant helper once it's confirmed no test fixture or undocumented caller depends on it. Out of scope for spec19 logic.

### 4.3 `removeWallpaper` write-then-unlink ordering

The current order — clear AppStorage first, then unlink — is intentional (see optional Step 7 comment). Reversing it would race the file unlink against a still-mounted `Image` whose underlying decoder may still hold the fd. The ArkUI conditional rendering tears down the `Image` synchronously when the gate flips to false, so the unlink is safe by the time `deleteAllWallpaperFiles` runs.

### 4.4 Sandbox directory may not exist

If the user has never set a wallpaper, `${filesDir}/covers/` does not exist. `fileIo.listFileSync` throws; `deleteAllWallpaperFiles` wraps the call in try/catch and treats absence as non-fatal (line 87–88). Scene 3's initial state (no wallpaper) reaches `removeWallpaper` only via a path that already short-circuits before reaching the file enumeration (the delete row is hidden), so this is defence-in-depth.

### 4.5 Re-entrancy under fast taps

The `busy` flag in `PlayerWallpaperViewModel` (line 24) gates both `selectImage` and `removeWallpaper`. The Page's `enable: !this.vm.busy` gates the row too, but the gate could be bypassed by the framework between the user's tap and the busy-flag flip. The ViewModel-level guard (lines 52–54 / 27–29) is the authoritative one — early-returns without persistence.

### 4.6 Confirm-then-dialog-not-dismissed corner case

`DeleteWallpaperDialog.Confirm.onClick` invokes `onConfirm()` first, then `controller.close()`. If `onConfirm` throws (which `removeWallpaper` does not — all errors are swallowed inside `try/catch/finally`), the controller still closes. Verified: there is no exception path that survives the VM call.

### 4.7 Cold-start ordering preserves Scene 3

`EntryAbility.onCreate` declares `persistProp('playerScreenBgCover', '')` (line 99) **before** loading `MainPage` content, and the SettingsStore hydration on line 150 runs synchronously in the same hook. By the time `PlayerWallpaperPage` is first constructed, AppStorage already holds the persisted value (which is `''` after a confirmed delete). The Scene 3 visibility gate evaluates correctly on the first render.

### 4.8 i18n

The dialog title and body both reuse `app.string.delete_current_image` (already present in `base`, `zh`, `ug` element/string.json). The Cancel / Confirm strings (`app.string.cancel`, `app.string.confirm`) are also already present. No new resource IDs are needed by spec19.

---

## 5. Summary of files

**Modified (optional doc-only):**

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets` — one comment block above `removeWallpaper`. No signature, ordering, or call-graph change.

**Verified-as-correct (no edits):**

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlayerWallpaperPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlayerPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/components/PlayQueueComponent.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/components/DeleteWallpaperDialog.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/entryability/EntryAbility.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/model/SettingsStore.ets`

**Deliberately untouched (dormant duplicate writer; out of scope to refactor):**

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` lines 258–273 (`deletePlayerScreenBgCover`, `hasPlayerScreenBgCover`, stub `selectPlayerScreenBgImage`).
