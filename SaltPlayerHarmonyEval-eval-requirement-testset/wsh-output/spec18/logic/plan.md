# spec18 — 播放界面选择图片 Logic Implementation Plan

Spec source: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec18/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

---

## 0. Ground truth from repo

### 0.1 What already exists

The UI shell, navigation, persistence registration, and a "settings-side" delete helper for the player-screen wallpaper are already wired. The picker/IO logic is **explicitly stubbed**. What's missing is wiring the page actions through a real ViewModel that does the same job `MainWallpaperViewModel` does for the main-page wallpaper, and consuming the chosen path in both PlayerPage and PlayQueueComponent.

Already present:

- `entry/src/main/ets/pages/PlayerWallpaperPage.ets`
  - Built as a UI-only mirror of `MainWallpaperPage`; its "选择图片" and "删除当前图片" rows are `// TODO` placeholders.
  - Already uses `HdsNavDestination + HdsNavDestinationTitleMode.MINI` per the secondary-page-style memory; do not touch the chrome.
  - Currently re-uses `UserInterfaceViewModel` only for the flowing-light radio row (`isFlowingLightModeSelected` / `selectFlowingLightMode`). That re-use stays.
- `entry/src/main/ets/pages/UserInterfacePage.ets` (line 289)
  - Push route `'PlayerWallpaperPage'` from the `播放界面壁纸` row — already navigates.
- `entry/src/main/ets/pages/main/MainPage.ets` (lines 37, 890–891)
  - `PlayerWallpaperPage` is registered inside the NavDestination switch, alongside `MainWallpaperPage`.
- `entry/src/main/ets/entryability/EntryAbility.ets`
  - Line 99: `PersistentStorage.persistProp('playerScreenBgCover', '')` — AppStorage key already declared.
  - Line 150: `AppStorage.setOrCreate('playerScreenBgCover', ss.get('playerScreenBgCover', '') as string)` — hydrated from `SettingsStore` on cold launch.
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`
  - Lines 33, 69–71: reads `playerScreenBgCover` from AppStorage into a mirrored `@Track` field (used by no live UI today).
  - Lines 256–273: `deletePlayerScreenBgCover()`, `hasPlayerScreenBgCover()`, and a stub `selectPlayerScreenBgImage()`. The delete helper only zeroes the path and persists — it does NOT purge the sandbox file.
- `entry/src/main/ets/model/UserInterfaceModel.ets` (line 43)
  - `public playerScreenBgCover: string = ''` — pure data, fine to leave as-is.
- `entry/src/main/ets/components/DeleteWallpaperDialog.ets`
  - Reusable confirm dialog already used by `MainWallpaperPage`. Reuse it here verbatim — no changes.
- `entry/src/main/ets/viewmodel/MainWallpaperViewModel.ets`
  - Reference implementation for the **same** picker + sandbox-copy + persist + cleanup flow (key `mainPageWallpaperPath`, basename `main_wallpaper`). Mirror its structure exactly for player wallpaper.
- `entry/src/main/ets/pages/main/MainPage.ets` (lines 107, 444–449)
  - Pattern for consuming a wallpaper AppStorage key: declare `@StorageProp('<key>')` and conditionally render `Image(<path>).objectFit(ImageFit.Cover)` behind the page chrome.
- `entry/src/main/ets/pages/PlayerPage.ets`
  - The background stack (lines 567–586) renders a solid color from `this.vm.getPagerBackgroundColor()` plus, conditionally, a `FlowingLightComponent` overlay. This is the insertion point for the custom-wallpaper image.
- `entry/src/main/ets/components/PlayQueueComponent.ets`
  - The play queue is rendered as a vertical Swiper page inside `PlayerPage` (see PlayerPage.ets lines 587–656 — the play queue is page 1 in the vertical pager, **not** a separate route). Its background is computed by `getQueueBackground()` (transparent when flowing-light is active so the player's flowing-light layer shows through). With a custom wallpaper, both pages need to share the same image — the spec's "播放队列页作为播放页的子页面，共享同一背景图" is satisfied automatically by placing the wallpaper inside the outer Stack BEHIND the inner pager Stack, **provided** `PlayQueueComponent` does not paint an opaque background over it.

### 0.2 Spec → repo translation notes

- **AppStorage key**: reuse the existing `playerScreenBgCover` rather than introducing a new key. It already has all the plumbing (persistProp, SettingsStore hydration, default `''`). The mirror field in `UserInterfaceViewModel` is dead code from a UI-only seed; we will not depend on it, but we don't need to remove it either.
- **Sandbox path**: per the spec ("covers/player_screen_cover"), put the file under `${context.filesDir}/covers/player_screen_cover<ts><ext>`. We mirror `MainWallpaperViewModel`'s `<basename>_<timestamp><ext>` convention so leftover files from a crash-mid-copy are cleanable. Stored value is `'file://' + absolutePath`, matching how `mainPageWallpaperPath` is stored and consumed today.
- **"应用重新启动以刷新界面" (Scene 3 step 5)**: this line in the spec is an outdated implementation detail leaking from the Android original. Scene 1 step 9 already requires **real-time** update ("实时更新"). We honor the real-time semantics — same as `MainWallpaperPage` does today — so the deletion path also takes effect live without a restart. The spec author's intent (verified by Scene 1 step 9 + Scene 4 step 6) is "wallpaper applied/removed live; default dynamic flowing-light returns when path is empty". A reactive @StorageProp on both PlayerPage and PlayQueueComponent satisfies this.
- **"设置自定义背景图后，默认的动态流光效果被禁用" (Scene 4 step 6)**: gate `FlowingLightComponent` visibility on `playerScreenBgCover.length === 0`. The wallpaper image fills the same Stack slot the flowing light occupied.
- **Picker cancellation (Scene 2)**: the system picker resolves with an empty `photoUris` array on user cancel — already handled in `MainWallpaperViewModel.selectImage`. Same code path here.

### 0.3 Repo conventions for live wallpaper state

`MainWallpaperPage` is the canonical pattern. The flow is:

1. Page declares `@StorageLink('mainPageWallpaperPath') wallpaperPath: string = ''` — used to gate the conditional "Delete" row.
2. Selecting an image runs through `MainWallpaperViewModel.selectImage`, which copies to sandbox, then calls `SettingsStore.save(KEY, path)`. `SettingsStore.save` does `AppStorage.setOrCreate(key, value)` + `putSync` + `flushSync`, so the path becomes live everywhere AppStorage('mainPageWallpaperPath') is read.
3. Consumers (`MainPage` background) use `@StorageProp` for read-only live binding.

We replicate exactly this pattern for the player screen.

---

## 1. MVVM ownership boundary

| Concern | Owner | File |
|---|---|---|
| UI for the "选择图片" / "删除当前图片" rows, confirmation dialog presentation, conditional Delete row | Page / Component | `pages/PlayerWallpaperPage.ets`, `components/DeleteWallpaperDialog.ets` |
| Picker invocation, sandbox copy, sandbox cleanup, `busy` flag, persistence write | ViewModel | `viewmodel/PlayerWallpaperViewModel.ets` (new) |
| Persistence (AppStorage + Preferences) for the wallpaper path | Model / DataSource | `model/SettingsStore.ets` (no change), `entryability/EntryAbility.ets` (no change — already wired) |
| Player-page background composition (image vs flowing light vs solid) | Page | `pages/PlayerPage.ets` |
| Play queue background composition (must not occlude wallpaper) | Component | `components/PlayQueueComponent.ets` |
| Dynamic flowing-light gating (disabled when wallpaper is set) | Page | `pages/PlayerPage.ets` (gate inside the existing `if (this.vm.flowingLightActive && ...)` block) |

Persistence path (writer → reader):

- Writer: `PlayerWallpaperViewModel.selectImage` → on success calls `SettingsStore.save('playerScreenBgCover', destPathUri)`; `PlayerWallpaperViewModel.removeWallpaper` → calls `SettingsStore.save('playerScreenBgCover', '')` then purges sandbox files.
- Reader (settings page UI gate): `@StorageLink('playerScreenBgCover')` in `PlayerWallpaperPage`.
- Reader (player background): `@StorageProp('playerScreenBgCover')` in `PlayerPage`.
- Reader (play queue background): `@StorageProp('playerScreenBgCover')` in `PlayQueueComponent` (so it can stay transparent when the wallpaper is set, just as it already stays transparent when flowing-light is active).

Anti-patterns explicitly avoided (per worker guardrails):

- **No persistence inside Page.** The Page owns UI; persistence stays in `PlayerWallpaperViewModel` → `SettingsStore`. We do NOT call `SettingsStore.save` from `PlayerWallpaperPage.ets` (or from `UserInterfaceViewModel.deletePlayerScreenBgCover`, whose half-implementation we will not call).
- **No mirror state for the live path.** The ViewModel exposes only `busy`. The path lives in AppStorage; the page and player consume it via `@StorageLink` / `@StorageProp`. The existing `playerScreenBgCover: string` field on `UserInterfaceViewModel` is **not** the live source — it is a stale snapshot taken on construction. We will leave it untouched but never read it for the wallpaper feature.
- **No `aboutToAppear` for live sync.** `PlayerPage` is mounted while the user navigates to settings; an `aboutToAppear`-only refresh would miss the in-flight update. `@StorageProp` is the live channel.
- **No fake default.** Default `''` is consistent across `PersistentStorage.persistProp`, `SettingsStore.get` fallback, `@StorageLink` initializer, `@StorageProp` initializer, and the new VM constants.
- **No duplicate writer.** `UserInterfaceViewModel.deletePlayerScreenBgCover()` (lines 258–262) would partially overlap with `PlayerWallpaperViewModel.removeWallpaper`. Since `deletePlayerScreenBgCover` is not bound to any UI today, leaving it dormant is fine. Do NOT call it from the new Page — the new VM is the single delete entry point.

---

## 2. Surfaces & files touched

| # | File | Change |
|---|---|---|
| 1 | `entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets` | **NEW**. Mirror of `MainWallpaperViewModel` with `KEY = 'playerScreenBgCover'` and `FILE_BASENAME = 'player_screen_cover'`. Optionally place files under a `covers/` subdir (see step 1 below). Same `selectImage`, `removeWallpaper`, `copyToSandbox`, `deriveExtension`, `cleanupOldFiles`, `deleteAllWallpaperFiles` shape. |
| 2 | `entry/src/main/ets/pages/PlayerWallpaperPage.ets` | Wire the two action rows: instantiate `PlayerWallpaperViewModel`, add `@StorageLink('playerScreenBgCover') wallpaperPath: string = ''`, replace the two `TODO` `onClick` callbacks with `vm.selectImage(ctx)` and `DeleteWallpaperDialog → vm.removeWallpaper(ctx)`. Gate the Delete row on `this.wallpaperPath.length > 0` (matches `MainWallpaperPage` exactly). Disable both rows while `vm.busy`. Add the `aboutToAppear`-less wiring used by `MainWallpaperPage` (no lifecycle work; the dialog controller is instantiated lazily inside `onClick`). |
| 3 | `entry/src/main/ets/pages/PlayerPage.ets` | (a) Add `@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''` next to the other `@StorageProp`s (e.g. after `irregularCoverAllowed`, before `immersionMode`). (b) Inside the outer background Stack (around line 568–581), render `Image(this.playerScreenBgCover).objectFit(ImageFit.Cover).width('100%').height('100%').expandSafeArea(...)` when `this.playerScreenBgCover.length > 0`, BEHIND the conditional `FlowingLightComponent`. (c) Gate the existing flowing-light branch `if (this.vm.flowingLightActive && ... && this.playbackError.length === 0)` with `&& this.playerScreenBgCover.length === 0` so the wallpaper replaces (not stacks on top of) the dynamic flowing-light. (d) The fallback solid background Column already underneath stays — it's harmless behind a fully opaque cover image and provides a fallback for the moment between path-clear and unmount. |
| 4 | `entry/src/main/ets/components/PlayQueueComponent.ets` | Extend `getQueueBackground()` to return `Color.Transparent` when a custom wallpaper is set, so the wallpaper rendered in `PlayerPage`'s outer background Stack shows through the queue page. Add a new `@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''` field on the component. The existing `flowingLightActive`-based transparent path stays as the second condition. Foreground text colors: the current branch already picks "dark-mode white" or "light-mode resource color" when `!flowingLightActive`. When a wallpaper is present but `flowingLightActive` is false (e.g. no cover art OR flowing-light explicitly disabled), follow the same `isLightMode`-based foreground rule the current code uses — the spec does not require automatic contrast adaptation against the user-chosen image, and the `MainWallpaperPage` precedent for `MainPage` does not do contrast adaptation either. |

No edits to `EntryAbility.ets`, `SettingsStore.ets`, `UserInterfaceViewModel.ets`, `UserInterfaceModel.ets`, `UserInterfacePage.ets`, or `MainPage.ets` are needed.

No new string resources needed (`select_image`, `delete_current_image`, `wallpaper_of_player_screen` already exist; the `wallpaper_of_main_interface_info` info string is currently reused by `PlayerWallpaperPage` for the bottom helper text and we keep that).

---

## 3. Step-by-step implementation order

### Step 1 — Create `PlayerWallpaperViewModel.ets`

Path: `entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets`

Copy `MainWallpaperViewModel.ets` and substitute:

- `TAG = 'PlayerWallpaperVM'`
- `KEY = 'playerScreenBgCover'`
- `FILE_BASENAME = 'player_screen_cover'`

Sandbox layout decision: spec asks for `covers/player_screen_cover`. Implement as:

```
const COVERS_DIR = 'covers'
const FILE_BASENAME = 'player_screen_cover'

private async copyToSandbox(context: common.UIAbilityContext, srcUri: string): Promise<string> {
  const ext = this.deriveExtension(srcUri)
  const dir = `${context.filesDir}/${COVERS_DIR}`
  try { fileIo.mkdirSync(dir) } catch (_e) { /* exists */ }
  const destPath = `${dir}/${FILE_BASENAME}_${Date.now()}${ext}`
  // … same open/copyFile/close as MainWallpaperViewModel …
  this.cleanupOldFiles(context, destPath)
  return 'file://' + destPath
}
```

Adapt `cleanupOldFiles` / `deleteAllWallpaperFiles` to enumerate `${context.filesDir}/${COVERS_DIR}` instead of `context.filesDir`. Both methods stay best-effort with swallowed errors, identical to `MainWallpaperViewModel`.

Public API (identical signatures to `MainWallpaperViewModel`):

- `@Track public busy: boolean = false`
- `async selectImage(context: common.UIAbilityContext): Promise<void>`
- `async removeWallpaper(context: common.UIAbilityContext): Promise<void>`

Internal helpers (private): `applyPath`, `copyToSandbox`, `deriveExtension`, `cleanupOldFiles`, `deleteAllWallpaperFiles`. All errors are surfaced via `hilog.error` + a single `promptAction.showToast({ message: $r('app.string.error') })` on the `selectImage` failure path (same as MainWallpaperVM).

### Step 2 — Wire `PlayerWallpaperPage.ets`

Replace `@State vm: UserInterfaceViewModel` with two state fields:

```
@State vm: PlayerWallpaperViewModel = new PlayerWallpaperViewModel()
@State uiVM: UserInterfaceViewModel = new UserInterfaceViewModel()    // flowing-light theme row only
@StorageLink('playerScreenBgCover') wallpaperPath: string = ''
private deleteDialogController?: CustomDialogController
```

Update the `ThemeSection` builder to read from `this.uiVM` (not `this.vm`) for `isFlowingLightModeSelected` / `selectFlowingLightMode`.

Rewrite `ActionsSection`:

- `选择图片` ListItem → `enable: !this.vm.busy`, `onClick: () => this.vm.selectImage(ctx)` where `ctx = this.getUIContext().getHostContext() as common.UIAbilityContext`.
- `删除当前图片` ListItem → only render when `this.wallpaperPath.length > 0`. `enable: !this.vm.busy`. `onClick` opens `DeleteWallpaperDialog` whose `onConfirm` calls `this.vm.removeWallpaper(ctx)`. Use the identical `CustomDialogController` block as `MainWallpaperPage` (alignment Center, customStyle true, `maskColor: '#80000000'`, `openAnimation: { duration: 0 }`, `closeAnimation: { duration: 0 }`).

Imports to add at the top of `PlayerWallpaperPage.ets`:

```
import PlayerWallpaperViewModel from '../viewmodel/PlayerWallpaperViewModel'
import { common } from '@kit.AbilityKit'
import { DeleteWallpaperDialog } from '../components/DeleteWallpaperDialog'
```

Keep the `UserInterfaceViewModel` import for the theme radio row.

### Step 3 — Render wallpaper in `PlayerPage.ets`

Add field (next to the other `@StorageProp`s in the lyrics / cover cluster, e.g. line 142 area):

```
@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''
```

In `build()` (line 568+), restructure the inner background Stack:

```
Stack() {
  // Fallback solid background (always present)
  Column()
    .width('100%')
    .height('100%')
    .backgroundColor(this.vm.getPagerBackgroundColor())
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

  // Custom wallpaper (Scene 4): user-selected image fills the screen.
  if (this.playerScreenBgCover.length > 0) {
    Image(this.playerScreenBgCover)
      .width('100%')
      .height('100%')
      .objectFit(ImageFit.Cover)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  // Flowing light overlay — Scene 4 requires this be DISABLED when a wallpaper is set,
  // Scene 5 requires it to appear as the default when no wallpaper is set.
  if (this.playerScreenBgCover.length === 0
      && this.vm.flowingLightActive
      && this.vm.flowingLightVM.coverPixelMap
      && this.playbackError.length === 0) {
    FlowingLightComponent({ viewModel: this.vm.flowingLightVM })
  }
}
```

No changes needed in `PlayerPageViewModel.getPagerBackgroundColor()` — when a wallpaper is set, the solid color is still drawn underneath but is fully occluded by the Cover-fit image, which is the desired visual.

### Step 4 — Make `PlayQueueComponent.ets` transparent over the wallpaper

Add at the top of the struct fields:

```
@StorageProp('playerScreenBgCover') playerScreenBgCover: string = ''
```

Adjust `getQueueBackground()`:

```
private getQueueBackground(): ResourceColor {
  // Custom wallpaper takes precedence: the wallpaper lives in PlayerPage's outer
  // Stack (BELOW the inner pager) and must show through both player and queue pages.
  if (this.playerScreenBgCover.length > 0) {
    return Color.Transparent
  }
  if (this.viewModel.flowingLightActive) {
    return Color.Transparent
  }
  if (!this.viewModel.isLightMode) {
    return '#ff1a1a1a'
  }
  return $r('app.color.colorPageBackground')
}
```

No changes to the foreground-color helpers (`getIconForeground`, `getSubTextForeground`) — they already pick light/dark-aware tokens when flowing-light is not active; the spec does not ask for cover-aware contrast.

### Step 5 — Manual verification matrix

| Scene | Manual check |
|---|---|
| 1 | Settings → 用户界面 → 播放界面壁纸 → 选择图片. Pick an image. Toast does not appear. Back out to player — wallpaper is visible behind UI. Swipe up to play queue — same wallpaper. |
| 2 | Open picker, hit back. No toast, no file write (`hdc shell ls <bundle>/files/covers` shows no new entry), `AppStorage.get('playerScreenBgCover')` is unchanged. |
| 3 | With wallpaper set, tap 删除当前图片 → confirm. Player and queue immediately return to dynamic flowing light. `${filesDir}/covers/player_screen_cover_*` is gone. **No restart required** (spec line "应用重新启动以刷新界面" intentionally ignored, justified above). |
| 4 | With wallpaper set: enter Player and PlayQueue. Same image fills both. No FlowingLightComponent in the tree (verify via debug print or by toggling cover art availability — flow-light branch must stay off). |
| 5 | Clear wallpaper. Enter Player and PlayQueue. Default flowing light visible (cover art needed for the existing gate). |

---

## 4. Risk register and notes

### 4.1 Concurrent settings writers

`UserInterfaceViewModel.deletePlayerScreenBgCover()` still exists and writes the same key. It is unreferenced by any UI today, but a future caller could create a double-writer scenario. Mitigation: leave it in place (no spec scope to refactor), do not call it from new code. If a maintainer ever needs to delete from elsewhere, they should route through `PlayerWallpaperViewModel.removeWallpaper` so the sandbox cleanup runs.

### 4.2 Stale `playerScreenBgCover` field on `UserInterfaceViewModel`

The mirror field on the VM is initialized once from AppStorage and never refreshed. It is unused by the visible UI. We do not depend on it; nothing reads it. Removing it is out of scope.

### 4.3 `ImageFit.Cover` vs spec wording

Spec Scene 4 step 4: "图片以裁剪方式填充整个屏幕". `ImageFit.Cover` is the ArkUI equivalent: scale to fill, crop overflow. Match.

### 4.4 Play queue is a Swiper page, not a route

Verified via `PlayerPage.ets` lines 587–656: the play queue is page index 1 in the inner vertical pager Swiper, sharing the outer Stack with the player. Therefore putting the wallpaper in the outer Stack is sufficient — there is no separate route to wire. Step 4 only needs to keep `PlayQueueComponent` from painting an opaque rectangle over it.

### 4.5 Picker permission

`photoAccessHelper.PhotoViewPicker.select` triggers the system photo picker, which on HarmonyOS does not require a runtime permission grant (the picker handles consent). Already proven by `MainWallpaperViewModel`.

### 4.6 Sandbox cleanup race

`removeWallpaper` clears `AppStorage` first (so observers detach the image), then unlinks files. ArkUI Image holds onto the underlying decode but releases the file handle when the component unmounts; the conditional `if (this.playerScreenBgCover.length > 0)` evaluates to false in the same frame the AppStorage write lands, so the `Image` is removed before unlink runs. Same flow as `MainWallpaperViewModel` — proven in production.

### 4.7 Cold-start order

`EntryAbility.onCreate` calls `PersistentStorage.persistProp('playerScreenBgCover', '')` **before** `loadContent`, so the very first render of `MainPage` (and any reachable child including `PlayerPage`) sees the restored value. No additional ordering work needed.

### 4.8 No spec5 references to "covers/" outside this feature

Searched the repo — `covers/` does not collide with any existing sandbox directory (the cover-art RDB cache uses `CoverCacheDb.initCoverDir`, which writes elsewhere). The new directory is feature-private.

### 4.9 Resource I18n

`wallpaper_of_main_interface_info` is currently reused by `PlayerWallpaperPage` for the bottom helper sentence. The string is generic enough to be acceptable (it talks about "背景色"); the spec does not require a new string. Leaving as-is — if a UX request later asks for a player-specific info line, that is a strings-only change outside this plan.

---

## 5. Summary of files

**New:**

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/viewmodel/PlayerWallpaperViewModel.ets`

**Modified:**

- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlayerWallpaperPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/pages/PlayerPage.ets`
- `/Users/moriafly/GitHub/SaltPlayerHarmony/entry/src/main/ets/components/PlayQueueComponent.ets`

**Untouched (verified sufficient):**

- `entryability/EntryAbility.ets` — `playerScreenBgCover` already persisted + hydrated.
- `model/SettingsStore.ets` — generic write path already in use.
- `components/DeleteWallpaperDialog.ets` — reused as-is.
- `pages/main/MainPage.ets` — `PlayerWallpaperPage` route already registered.
- `pages/UserInterfacePage.ets` — `播放界面壁纸` entry already navigates.
- `resources/base/element/string.json` (and zh / ug variants) — `select_image`, `delete_current_image`, `wallpaper_of_player_screen`, `wallpaper_of_main_interface_info` all exist.
