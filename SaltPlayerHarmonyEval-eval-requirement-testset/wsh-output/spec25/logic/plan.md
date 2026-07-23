# Implementation Plan — spec25: 悬浮窗状态栏歌词 (Floating Window Status-Bar Lyrics)

Source spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec25/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 1. Goal

The spec asks for a fully-working "悬浮窗状态栏歌词" sub-feature reachable from **设置 → 歌词 → 悬浮窗状态栏歌词**. The user toggles a master switch; when ON and the system overlay permission is granted, the app draws a real **system-level floating window** in the status-bar region that scrolls (marquee) the currently-playing lyric line in real time. The user customises position (X %, Y px), width (50–750 dp), font size (8–32 dp), text color (predefined palette), text alignment (left or centered), and three behaviour switches:

- 状态栏歌词不显示翻译 — show only main text, never sub-text translation lines.
- 在播放界面隐藏 — hide the floating window while the in-app player page is on top.
- (the master switch itself).

All settings persist across app restart. On cold start, if the master is ON and permission is still granted, the floating window re-appears with the persisted parameters. On pause, the lyric text fades out (window stays alive); on resume, it fades back in. When the song has no lyrics the window stays alive but empty. Behaviour is detailed in 19 scenarios in the source spec.

## 2. Platform reality (HarmonyOS specifics)

### 2.1 Overlay window — supported by `@kit.ArkUI`

HarmonyOS exposes `window.createWindow({ ctx, name, windowType: window.WindowType.TYPE_SYSTEM_FLOAT })` for system-level overlay windows. Gated by `ohos.permission.SYSTEM_FLOAT_WINDOW`, which is already declared in `entry/src/main/module.json5:52-60`. The permission must be granted via the system settings page (not a runtime dialog) — the project already implements that flow in `model/FloatingWindowPermission.ets` (used by spec24 for an unrelated toggle). We reuse the same helper here.

### 2.2 Window UI hosting

Two viable approaches exist for hosting an ArkUI component inside a system float window:

1. **`window.loadContent('pages/path', context)`** — loads an ArkTS page entry. Heaviest but most idiomatic.
2. **`window.setUIContent(...)`** with an inline `@Builder`-style component path — same loader, different entry.

We pick approach 1: a dedicated page file `pages/FloatingStatusBarLyricsWindow.ets` rendering the lyric Text. The page reads all live state from `AppStorage` (StorageLink/StorageProp), so when settings change in the Settings page (a *different* window), AppStorage propagates to the float window automatically. This avoids hand-rolled inter-window IPC.

### 2.3 Status-bar region position

The user spec says "0% = leftmost, 100% = rightmost" for X and "0 px = top of status bar, N px = lower offset" for Y. The float window is sized by `window.resize(widthPx, heightPx)` and positioned by `window.moveWindowTo(xPx, yPx)`. We translate the user-facing units (% width, px offset, dp width/font) into device pixels by reading the screen width from `display.getDefaultDisplaySync()` once at creation and on screen-rotation events; dp→px via the `density` field of the same display.

### 2.4 Marquee / scrolling text

`@kit.ArkUI` ships `Marquee({ src: string, start: boolean, loop: -1, fromStart: false, step, fontSize, fontColor })`. We use it when the rendered text overflow exceeds the float window's width; otherwise show static `Text`. The MVVM-clean path: a tiny `@State overflow: boolean` toggle inside the page, driven by `onAreaChange` measurement against the configured width.

### 2.5 Live-data sources already wired

- Lyric stream — `model/MiniLyricsController.ets` publishes `(songId, line, hasLyrics)` to listeners on a 200 ms tick. Used by `NotificationLyricController` (spec12) and `MediaCardDesktopLyricsButtonController` (spec24). We piggy-back: a new singleton controller subscribes; no second timer.
- Lyric translation toggle gate — we ALREADY have a per-line `subText` field in `LyricsDocument` (`model/LyricsModel.ets:31, 51, 61`). Spec25's `statusBarLyricsNotShowTranslation` flag only changes whether the float window shows two lines (`mainText` + `subText`) or one (`mainText`). The actual lyric model is unchanged.
- Play/pause stream — `AppStorage('isPlaying')` is the existing live boolean written by `AudioPlayerService` on every state transition. We bind to it for the fade-in/fade-out behaviour.
- Player page visibility — `AppStorage('playerPageVisible')`, written by `ScreenWakeViewModel.onPlayerVisibilityChanged` (verified at `viewmodel/ScreenWakeViewModel.ets:59`) and seeded `false` by `EntryAbility.onCreate` (verified at `entryability/EntryAbility.ets:245`). We re-use it for scenario 16/17 ("在播放界面隐藏" gating).

### 2.6 What this plan delivers vs. what is platform-bound

In contrast to spec24 (which could not deliver the on-card render because the system owns the AVSession surface), spec25 is end-to-end deliverable: the app owns the float window and the entire pipeline. There are no system-rendered surfaces we cannot reach. Every scenario S1–S19 maps to concrete code in this plan.

## 3. Repo reality (writer / reader / binding / refresh)

### 3.1 Already in place — do not duplicate

| Concern | Where it already lives |
| --- | --- |
| Master AppStorage key `floatingWindowStatusBarLyrics` | `EntryAbility.ets:128, 186-187` (persist + hydrate) |
| Persisted disk write on master toggle | `pages/FloatingWindowStatusBarLyricsPage.ets:142-144` (page writes via SettingsStore — **NOTE: page-owns-persistence is an MVVM violation; the plan moves it into a ViewModel; see §4.2**) |
| Permission probe + system-settings jump | `model/FloatingWindowPermission.ets` — `checkPermission()`, `ensurePermission()`, `reprobeOnForeground()`, `addGrantListener()` / `removeGrantListener()`. The `reprobeOnForeground()` hook is already called from `EntryAbility.onForeground()` (`entryability/EntryAbility.ets:486-489`). |
| Overlay permission declared | `entry/src/main/module.json5:51-60` |
| Lyric stream | `model/MiniLyricsController.ets` — `addListener(fn)` publishes `(songId, line, hasLyrics)` initially and on each 200 ms tick |
| Lyric translation per-line | `LyricsLine.subText` in `model/LyricsModel.ets:31` |
| Play/pause flag | `AppStorage('isPlaying')` written throughout `AudioPlayerService.ets` |
| Player-page visibility flag | `AppStorage('playerPageVisible')` written by `ScreenWakeViewModel.onPlayerVisibilityChanged` |
| `statusBarLyricsNotShowTranslation` master toggle key | Already persisted at `EntryAbility.ets:125` and surfaced in `LyricsSettingsViewModel.statusBarLyricsNotShowTranslation` for the system-level status bar lyrics elsewhere |
| Master nav row "悬浮窗状态栏歌词" | `pages/LyricsSettingsPage.ets:160-191` (pushes `'FloatingWindowStatusBarLyricsPage'` onto the nav stack) |
| Sub-page UI scaffold | `pages/FloatingWindowStatusBarLyricsPage.ets` — full UI is already wired with master switch + 6 sliders + 3 sub-switches + color picker dialog overlay. Most local fields are `@State`-only; persistence is missing for everything *except* the master toggle. |
| String resources for "悬浮窗状态栏歌词", "位置", "大小", "宽度", "左右位置", "上下位置", "选择颜色", "歌词文本居中对齐(_info)", "在播放界面隐藏", "状态栏歌词不显示翻译(_info)", "floating_window_status_bar_lyrics_tip", "no_floating_window_permission(_tip)" | Already in `base/element/string.json` and `zh/`, `ug/` (verified above) |
| MainPage NavDestination registration | `pages/main/MainPage.ets:928-929` |

### 3.2 Gaps the spec exposes

1. **The sub-page violates the MVVM owner-boundary today.** `FloatingWindowStatusBarLyricsPage.ets:142-144` writes the master toggle directly via `SettingsStore.getInstance().save(...)`. All other slider/switch handlers (lines 175, 191, 205, 226, 273, 304, 333) merely mutate local `@State` fields and never persist. The color picker `Confirm` button at `:435-439` has a TODO comment "Persist selected color". On every app restart the user-configured values reset to the in-file defaults, which already contradict the spec defaults (e.g. `@State leftRightPosition: number = 50` vs spec default 0%). Concretely:
   - **Per the spec defaults (scenario 2):** left/right=0%, up/down=0 px, width=150 dp, fontSize=14 dp, color=blue, alignment=left, center-aligned=OFF, hide-translation=OFF, hide-on-player=OFF.
   - **Per the current page defaults:** leftRight=50, upDown=50, width=80 (interpreted as the 0–100 slider range, not dp), fontSize=24, color=white, alignment=left, all sub-switches=OFF. Slider ranges in the page also do not match the spec (width 0–100 vs 50–750 dp; fontSize 12–48 vs 8–32 dp).
2. **No floating-window service module exists.** The float window itself (creation, destruction, resize, position, opacity, marquee) is unimplemented. The page only owns the *settings UI*.
3. **No live binding between settings and a (yet-to-be-built) float window.** Even after persistence is fixed, scenarios 7–13 require sub-100 ms reaction to slider drags. Reactive binding via AppStorage (`@StorageLink`) inside the float-window page is the cleanest path; pull-on-every-tick is not.
4. **No permission probe on master toggle.** Scenario 1 says when permission is missing, the toggle must remain OFF and prompt the user. Current code just writes `true` and trusts the system.
5. **No cold-start auto-show.** Scenario 18 requires the float window to re-appear at boot if the master is persisted ON. EntryAbility hydrates the boolean but does nothing with it.
6. **No fade-in/fade-out on play/pause.** Scenarios 5/6 require the lyric text (not the whole window) to fade. Pure UI concern — must live in the float-window page using `animation({ duration: 300, curve: Curve.EaseInOut })` on `.opacity(...)`.
7. **No "hide on player page" gating.** Scenarios 16/17 need a `@StorageProp('playerPageVisible')` watcher inside the float window page that switches the text container's `.visibility(Visibility.Hidden)` when both the toggle and `playerPageVisible` are true.
8. **No "no translation" gating.** Scenarios 14/15 need a second `Text` element bound to `LyricsLine.subText`, conditionally rendered based on the `statusBarLyricsNotShowTranslation` flag scoped to *this* feature. The spec uses the SAME flag name as the existing system-level status-bar setting. Two interpretations:
   - **Interpretation A**: Share the AppStorage key. Pro: one place to toggle for the user; con: the system-level and floating-window features have independent UI rows that will out-of-sync each other if they read different storage. Choose A — the existing `LyricsSettingsViewModel` reads `statusBarLyricsNotShowTranslation` and would otherwise become a desynced mirror.

### 3.3 MVVM owner mapping (binding strictly to repo reality)

| Layer | Owner | Files touched |
| --- | --- | --- |
| Page (Settings sub-page) — `FloatingWindowStatusBarLyricsPage` | Renders the toggle + sliders + sub-switches + color picker dialog. **Does NOT persist** — every UI handler calls a ViewModel method. Uses `@StorageLink` on every persisted AppStorage key so the UI reflects writes from any source (controller, restored values on first frame). | `pages/FloatingWindowStatusBarLyricsPage.ets` |
| ViewModel — `FloatingWindowStatusBarLyricsViewModel` (new) | Holds toggles + slider values as `@Track` fields hydrated from AppStorage in the constructor. Every setter calls `SettingsStore.getInstance().save(key, value)` (which mirrors to AppStorage). On master flip ON: invoke `FloatingWindowPermission.ensurePermission()` and only proceed when granted (scenario 1 / 2). On master flip ON success: call `FloatingStatusBarLyricsController.getInstance().show()`. On master flip OFF: call `controller.hide()`. On individual setting change: nothing else — the running window observes AppStorage directly. | `viewmodel/FloatingWindowStatusBarLyricsViewModel.ets` (new) |
| Page (float window content) — `FloatingStatusBarLyricsWindow` | Tiny ArkTS page loaded via `window.loadContent('pages/FloatingStatusBarLyricsWindow', ctx)`. Renders the lyric Text with marquee, fade animations, alignment, color. Reads every parameter from AppStorage with `@StorageLink/@StorageProp`. Subscribes to a model-layer publisher (the controller) for the current lyric line + hasLyrics. Owns the marquee start/stop, opacity animation, and visibility gating logic. No persistence; no system calls beyond UI rendering. | `pages/FloatingStatusBarLyricsWindow.ets` (new) — registered in `resources/base/profile/main_pages.json` |
| Controller / Service — `FloatingStatusBarLyricsController` (new singleton in `model/`) | Owns the system-level window lifecycle (`window.createWindow`, `loadContent`, `resize`, `moveWindowTo`, `setWindowBackgroundColor` transparent, `setWindowOpacity` etc.), the lyric publish (subscribes to `MiniLyricsController` + `AudioPlayerService` song-change), and the cold-start auto-show. Exposes `show()`, `hide()`, `applyGeometry()`, `init()`. Owned at app process scope; called by EntryAbility on boot and by the sub-page ViewModel on toggle. Listens to AppStorage changes via `AppStorage.on('keyName', ...)` for live updates of position/width/size/color/alignment so it can reposition / resize the window without touching the page-layer UI logic. The window content page itself reacts via `@StorageLink` for color/font/alignment/text changes; the **window-manager-side** properties (position + size) must be set imperatively here. | `model/FloatingStatusBarLyricsController.ets` (new) |
| Permission helper — `FloatingWindowPermission` | Existing — used as-is. The ViewModel calls `ensurePermission()`; the helper handles the system-settings jump + foreground re-probe + grant listener. | `model/FloatingWindowPermission.ets` (unchanged) |
| Bootstrap — `EntryAbility` | Adds persistence registrations for every new key (`floatingWindowSbLrLeftRight`, etc., see §4.7), hydrates them from `SettingsStore`, and after `MediaCardDesktopLyricsButtonController.getInstance().init()` calls `FloatingStatusBarLyricsController.getInstance().init(this.context)` so the controller has the UIAbility context for `createWindow`. | `entryability/EntryAbility.ets` |

The boundary mirrors spec24's pattern:

- Page does no system calls and no persistence.
- ViewModel orchestrates (permission probe → persist → tell controller).
- Controller owns the system-window object and the live publishes.
- Service (`AudioPlayerService`, `MiniLyricsController`) is the lyric/play source — untouched.

## 4. Change list (precise, file-by-file)

### 4.1 `entry/src/main/ets/entryability/EntryAbility.ets`

Add persistence for every NEW spec25 key, plus the hydration block immediately after the existing `floatingWindowStatusBarLyrics` block (`:128, :186-187`).

```ts
// Spec25: 悬浮窗状态栏歌词 sub-settings — see plan §4.7 for the canonical keys.
PersistentStorage.persistProp('floatingWindowSbLrLeftRightPercent', 0)     // %
PersistentStorage.persistProp('floatingWindowSbLrUpDownPx', 0)             // px
PersistentStorage.persistProp('floatingWindowSbLrWidthDp', 150)            // dp
PersistentStorage.persistProp('floatingWindowSbLrFontSizeDp', 14)          // dp
PersistentStorage.persistProp('floatingWindowSbLrColor', 0xFF0470E6)       // ARGB int
PersistentStorage.persistProp('floatingWindowSbLrCenterAlign', false)
PersistentStorage.persistProp('floatingWindowSbLrHideOnPlayer', false)
// statusBarLyricsNotShowTranslation already exists at :125, :182 — reuse it.
```

In the SettingsStore-hydration block (next to `floatingWindowStatusBarLyrics` at `:186-187`):

```ts
AppStorage.setOrCreate('floatingWindowSbLrLeftRightPercent',
  ss.get('floatingWindowSbLrLeftRightPercent', 0) as number)
AppStorage.setOrCreate('floatingWindowSbLrUpDownPx',
  ss.get('floatingWindowSbLrUpDownPx', 0) as number)
AppStorage.setOrCreate('floatingWindowSbLrWidthDp',
  ss.get('floatingWindowSbLrWidthDp', 150) as number)
AppStorage.setOrCreate('floatingWindowSbLrFontSizeDp',
  ss.get('floatingWindowSbLrFontSizeDp', 14) as number)
AppStorage.setOrCreate('floatingWindowSbLrColor',
  ss.get('floatingWindowSbLrColor', 0xFF0470E6) as number)
AppStorage.setOrCreate('floatingWindowSbLrCenterAlign',
  ss.get('floatingWindowSbLrCenterAlign', false) as boolean)
AppStorage.setOrCreate('floatingWindowSbLrHideOnPlayer',
  ss.get('floatingWindowSbLrHideOnPlayer', false) as boolean)
```

After `MediaCardDesktopLyricsButtonController.getInstance().init()` at `:370`, add:

```ts
// spec25 — Floating status-bar lyrics controller. Initialized AFTER
// MiniLyricsController so the lyric stream is alive, AFTER
// AudioPlayerService.initContext so it can read the UIAbility context, and
// AFTER persistence hydration above so it sees the persisted geometry on
// scenario 18 cold-start auto-show.
FloatingStatusBarLyricsController.getInstance().init(this.context)
```

Import the new controller alongside the others at the top:

```ts
import { FloatingStatusBarLyricsController }
  from '../model/FloatingStatusBarLyricsController';
```

Add a teardown call in `onWindowStageDestroy()` (existing at `:445`) right after the `cancelScanning()` block:

```ts
try {
  FloatingStatusBarLyricsController.getInstance().destroy()
} catch (e) {
  hilog.warn(DOMAIN, 'FloatingSbLr', 'destroy failed: %{public}s',
    (e as Error).message)
}
```

The `FloatingWindowPermission.reprobeOnForeground` chain in `onForeground()` (`:486-489`) is already wired — the new ViewModel will register itself as a grant listener so the master toggle flips ON automatically when the user returns from settings with permission granted (scenario 1 last bullet, mirrors spec24's pattern).

### 4.2 `entry/src/main/ets/pages/FloatingWindowStatusBarLyricsPage.ets`

Convert the page from "owns state + persists master" to "renders ViewModel state, delegates every action". Replace the body of the component.

- Drop every `@State` field except short-lived UI state (e.g. `showColorPickerDialog`). Replace with `@State vm: FloatingWindowStatusBarLyricsViewModel = new FloatingWindowStatusBarLyricsViewModel()` and read every setting from `this.vm.*`.
- Drop the `@StorageLink('floatingWindowStatusBarLyrics')` field (the ViewModel owns it via its own `@StorageLink`/`@Track`).
- The master switch's `onChange` becomes `(val) => this.vm.onMasterToggleChanged(val)`.
- The position/width/size sliders' `onValueChange` become `(val) => this.vm.onLeftRightPercentChanged(val)` / `.onUpDownPxChanged(...)` / `.onWidthDpChanged(...)` / `.onFontSizeDpChanged(...)`.
- Slider `min` / `max` / `step` come from `this.vm.XYZRange` constants exposed on the ViewModel (single source of truth). Bind UI ranges to spec values:
  - leftRightPercent: min 0, max 100, step 1
  - upDownPx: min 0, max 100, step 1
  - widthDp: min 50, max 750, step 1
  - fontSizeDp: min 8, max 32, step 0.5  (spec gives a float for default 14.0; granular)
- The three sub-switches (`lyrics_text_left_aligned`, `status_bar_lyrics_not_show_translation`, `hide_on_playback_screen`) bind to `this.vm.centerAlign` / `this.vm.notShowTranslation` / `this.vm.hideOnPlayer` and call `vm.onCenterAlignChanged(val)` / `vm.onNotShowTranslationChanged(val)` / `vm.onHideOnPlayerChanged(val)`. **Note**: the existing UI string is `lyrics_text_left_aligned` ("歌词文本居中对齐" in the zh translation? — verify and rename if mismatched; current usage at `:267-275` reads "left aligned" semantics in the variable name and the row toggles the *centered* state per the spec, so the spec wording "歌词文本居中对齐开关" matches the toggle-on=center behaviour. Keep the string key, only re-purpose to mean center-on).
- The color picker dialog's Confirm button calls `this.vm.onColorChanged(this.selectedColor)` and then closes the dialog.
- The local `colorPalette` array values are the five-row predefined palette already present at `:55-59`. Keep them — they match the spec's intent of a small predefined palette. Convert them to plain `number[]` (ARGB ints) so the ViewModel can persist them via `SettingsStore.save('floatingWindowSbLrColor', n)`.

The page still uses the `secondary_page_style` pattern (HdsNavDestination + MINI). Do NOT touch the title-bar block.

### 4.3 `entry/src/main/ets/viewmodel/FloatingWindowStatusBarLyricsViewModel.ets` (new)

```ts
// FloatingWindowStatusBarLyricsViewModel.ets
// spec25 — Owns the action layer for the 悬浮窗状态栏歌词 settings page.
// Persists every change via SettingsStore (which mirrors to AppStorage so
// downstream readers — the float-window page, the controller — see it live).
// Coordinates the floating-window permission probe on master-toggle ON, and
// pokes the FloatingStatusBarLyricsController to show/hide the window.

import SettingsStore from '../model/SettingsStore'
import FloatingWindowPermission, { FloatingWindowGrantListener }
  from '../model/FloatingWindowPermission'
import FloatingStatusBarLyricsController
  from '../model/FloatingStatusBarLyricsController'
import { promptAction } from '@kit.ArkUI'

@Observed
export default class FloatingWindowStatusBarLyricsViewModel {
  // ---- Master toggle (gated by overlay permission) ----
  @Track public master: boolean =
    (AppStorage.get<boolean>('floatingWindowStatusBarLyrics') ?? false)

  // ---- Position / size / style (hydrated from AppStorage) ----
  @Track public leftRightPercent: number =
    (AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0)
  @Track public upDownPx: number =
    (AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0)
  @Track public widthDp: number =
    (AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150)
  @Track public fontSizeDp: number =
    (AppStorage.get<number>('floatingWindowSbLrFontSizeDp') ?? 14)
  @Track public color: number =
    (AppStorage.get<number>('floatingWindowSbLrColor') ?? 0xFF0470E6)
  @Track public centerAlign: boolean =
    (AppStorage.get<boolean>('floatingWindowSbLrCenterAlign') ?? false)
  @Track public notShowTranslation: boolean =
    (AppStorage.get<boolean>('statusBarLyricsNotShowTranslation') ?? false)
  @Track public hideOnPlayer: boolean =
    (AppStorage.get<boolean>('floatingWindowSbLrHideOnPlayer') ?? false)

  // Slider range constants (single source of truth shared with the View)
  public readonly LR_MIN: number = 0
  public readonly LR_MAX: number = 100
  public readonly UD_MIN: number = 0
  public readonly UD_MAX: number = 100
  public readonly W_MIN: number = 50
  public readonly W_MAX: number = 750
  public readonly F_MIN: number = 8
  public readonly F_MAX: number = 32

  private grantListener: FloatingWindowGrantListener = (): void => {
    this.onPermissionGrantedFromSettings()
  }

  constructor() {
    FloatingWindowPermission.addGrantListener(this.grantListener)
  }

  // Master switch — scenario 1, 2, 3
  async onMasterToggleChanged(newValue: boolean): Promise<void> {
    if (newValue) {
      const granted = await FloatingWindowPermission.ensurePermission()
      if (!granted) {
        // Revert the row (UI binds to this.master), surface a toast.
        this.master = false
        try {
          promptAction.showToast({
            message: $r('app.string.no_floating_window_permission')
          })
        } catch (_e) { /* toast best-effort */ }
        return
      }
    }
    this.master = newValue
    SettingsStore.getInstance().save('floatingWindowStatusBarLyrics', newValue)
    if (newValue) {
      FloatingStatusBarLyricsController.getInstance().show()
    } else {
      FloatingStatusBarLyricsController.getInstance().hide()
    }
  }

  // ---- Per-setting handlers — persist + UI mirrors via SettingsStore.save ----
  onLeftRightPercentChanged(v: number): void {
    this.leftRightPercent = v
    SettingsStore.getInstance().save('floatingWindowSbLrLeftRightPercent', v)
  }
  onUpDownPxChanged(v: number): void {
    this.upDownPx = v
    SettingsStore.getInstance().save('floatingWindowSbLrUpDownPx', v)
  }
  onWidthDpChanged(v: number): void {
    this.widthDp = v
    SettingsStore.getInstance().save('floatingWindowSbLrWidthDp', v)
  }
  onFontSizeDpChanged(v: number): void {
    this.fontSizeDp = v
    SettingsStore.getInstance().save('floatingWindowSbLrFontSizeDp', v)
  }
  onColorChanged(v: number): void {
    this.color = v
    SettingsStore.getInstance().save('floatingWindowSbLrColor', v)
  }
  onCenterAlignChanged(v: boolean): void {
    this.centerAlign = v
    SettingsStore.getInstance().save('floatingWindowSbLrCenterAlign', v)
  }
  onNotShowTranslationChanged(v: boolean): void {
    this.notShowTranslation = v
    // Share the key with the system-level status-bar setting per §3.2 / interp A.
    SettingsStore.getInstance().save('statusBarLyricsNotShowTranslation', v)
  }
  onHideOnPlayerChanged(v: boolean): void {
    this.hideOnPlayer = v
    SettingsStore.getInstance().save('floatingWindowSbLrHideOnPlayer', v)
  }

  // FloatingWindowPermission grant-listener — fires when the user returns
  // from the system settings page with the permission newly granted.
  // Spec25 scenario 1 implies the master stays OFF if the user denies, but
  // the spec24 precedent (auto-flip ON when the user actually granted) is
  // consistent with user intent — we follow that pattern here so a returning
  // user doesn't need to re-tap the toggle when they granted what we asked
  // for. This mirrors NotificationViewModel.onFloatingWindowPermissionGranted.
  private onPermissionGrantedFromSettings(): void {
    if (this.master) {
      return
    }
    this.master = true
    SettingsStore.getInstance().save('floatingWindowStatusBarLyrics', true)
    FloatingStatusBarLyricsController.getInstance().show()
  }

  // Page lifecycle — called by aboutToDisappear of the page.
  destroy(): void {
    FloatingWindowPermission.removeGrantListener(this.grantListener)
  }
}
```

### 4.4 `entry/src/main/ets/model/FloatingStatusBarLyricsController.ets` (new)

```ts
// FloatingStatusBarLyricsController.ets
// spec25 — Owns the system-level floating window for the status-bar lyrics
// feature. Subscribes to MiniLyricsController for the running lyric line,
// to AudioPlayerService for song change + play/pause, and to the relevant
// AppStorage keys for geometry/style changes. Calls into @kit.ArkUI window
// APIs imperatively for resize/move (which @StorageLink cannot drive from
// inside the float-window page). Owns the window's lifecycle (create on
// show(), destroy on hide()) so persistence + UI presentation are decoupled.

import { window, display } from '@kit.ArkUI'
import { common } from '@kit.AbilityKit'
import AudioPlayerService from './AudioPlayerService'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'
import { QueueSongModel } from './PlayQueueModel'

const WINDOW_NAME = 'floating-status-bar-lyrics'
const WINDOW_CONTENT_PAGE = 'pages/FloatingStatusBarLyricsWindow'

export class FloatingStatusBarLyricsController {
  private static instance: FloatingStatusBarLyricsController | null = null

  private ctx: common.UIAbilityContext | null = null
  private win: window.Window | null = null
  private initialized: boolean = false
  private creating: boolean = false   // re-entry guard while async createWindow

  private songChangedListener: (s: QueueSongModel) => void = (): void => {}
  private lyricsListener: MiniLyricsListener =
    (_id: string, _l: string, _h: boolean): void => {}

  // AppStorage change observers. Kept as named members so we can detach in
  // destroy() — addStorageLink-style mirroring inside a non-component class
  // is done via AppStorage.on(...). When the SDK has no such hook (older
  // releases), the float-window page itself reacts via @StorageLink for
  // color/font/alignment/text/visibility. The controller still needs to
  // observe geometry keys imperatively because the window object — not the
  // page — owns position + size.
  private geometryWatcherIds: number[] = []

  static getInstance(): FloatingStatusBarLyricsController {
    if (!FloatingStatusBarLyricsController.instance) {
      FloatingStatusBarLyricsController.instance =
        new FloatingStatusBarLyricsController()
    }
    return FloatingStatusBarLyricsController.instance
  }

  // Idempotent. Called from EntryAbility.onCreate after AudioPlayerService
  // and MiniLyricsController are alive.
  init(ctx: common.UIAbilityContext): void {
    if (this.initialized) {
      return
    }
    this.initialized = true
    this.ctx = ctx

    // Subscribe to lyric stream — float-window page reads the line directly
    // via @StorageLink, so the controller's only job here is to mirror the
    // stream into AppStorage keys the page binds to.
    this.lyricsListener = (_songId: string, line: string, has: boolean): void => {
      AppStorage.setOrCreate<string>('floatingWindowSbLrLine', line)
      AppStorage.setOrCreate<boolean>('floatingWindowSbLrHasLyrics', has)
      // Also publish subText for the translation toggle path — see §4.5 for
      // why we expose it here rather than in the page.
      AppStorage.setOrCreate<string>('floatingWindowSbLrSubLine',
        this.currentSubLineFor(line))
    }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)

    // Reset the line buffer on song change so a fresh load starts empty.
    this.songChangedListener = (_s: QueueSongModel): void => {
      AppStorage.setOrCreate<string>('floatingWindowSbLrLine', '')
      AppStorage.setOrCreate<string>('floatingWindowSbLrSubLine', '')
    }
    AudioPlayerService.getInstance()
      .addOnSongChangedListener(this.songChangedListener)

    // Scenario 18 — cold-start auto-show. We do this LAST so all the keys are
    // populated for the first frame of the float-window page.
    const master: boolean =
      AppStorage.get<boolean>('floatingWindowStatusBarLyrics') ?? false
    if (master) {
      // Skip the permission probe on this path — the user already accepted at
      // some earlier point and the master is durable. If the system has since
      // revoked the permission, createWindow will reject and we surface a warn.
      this.show().catch((e: Error) => {
        console.warn('FloatingStatusBarLyricsController.init: '
          + 'auto-show failed: ' + e.message)
      })
    }
  }

  // Create + load the float window. Idempotent (re-call to nudge geometry).
  async show(): Promise<void> {
    if (this.win) {
      this.applyGeometry()
      return
    }
    if (!this.ctx || this.creating) {
      return
    }
    this.creating = true
    try {
      const w = await window.createWindow({
        ctx: this.ctx,
        name: WINDOW_NAME,
        windowType: window.WindowType.TYPE_SYSTEM_FLOAT
      })
      this.win = w
      await w.setUIContent(WINDOW_CONTENT_PAGE)
      await w.setWindowBackgroundColor('#00000000')
      // Make sure the window doesn't intercept touches — pure overlay.
      try {
        await w.setWindowTouchable(false)
      } catch (_e) { /* older SDK fallback */ }
      this.applyGeometry()
      // Watch for geometry-key changes so a slider drag in the Settings page
      // resizes / moves the live window. We poll on AppStorage subscribers;
      // the page-side @StorageLink path already handles color/font/text.
      this.startGeometryWatchers()
      await w.showWindow()
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.show: ' + (e as Error).message)
      this.win = null
    } finally {
      this.creating = false
    }
  }

  // Tear the window down. Idempotent.
  async hide(): Promise<void> {
    this.stopGeometryWatchers()
    const w = this.win
    this.win = null
    if (!w) {
      return
    }
    try {
      await w.destroyWindow()
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.hide: ' + (e as Error).message)
    }
  }

  // Apply current AppStorage geometry to the live window.
  // Called from show() and from every geometry-key change.
  applyGeometry(): void {
    if (!this.win) {
      return
    }
    const d = display.getDefaultDisplaySync()
    const density = d.densityPixels      // px per dp
    const screenW = d.width              // px
    const widthDp: number =
      AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
    const upDownPx: number =
      AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
    const lrPercent: number =
      AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
    const widthPx = Math.round(widthDp * density)
    const heightPx = Math.round(40 * density)    // height = font cap + padding
    const xPx = Math.round((screenW - widthPx) * (lrPercent / 100))
    const yPx = Math.round(upDownPx * density)
    try {
      this.win.resize(widthPx, heightPx)
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.applyGeometry resize: '
        + (e as Error).message)
    }
    try {
      this.win.moveWindowTo(xPx, yPx)
    } catch (e) {
      console.warn('FloatingStatusBarLyricsController.applyGeometry move: '
        + (e as Error).message)
    }
  }

  destroy(): void {
    this.hide().catch((_e: Error) => { /* swallow */ })
    MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    AudioPlayerService.getInstance()
      .removeOnSongChangedListener(this.songChangedListener)
    this.initialized = false
  }

  // ---- AppStorage geometry watchers ----
  // The HarmonyOS API surface for raw "AppStorage key changed" callbacks is
  // limited; we use a simple polling subscriber on the keys we care about
  // and call applyGeometry() when they differ from the last applied snapshot.
  // The cost is ~3 reads / 250 ms only when the float window is alive.
  private lastLrPercent: number = -1
  private lastUpDownPx: number = -1
  private lastWidthDp: number = -1
  private geomTimerId: number = -1

  private startGeometryWatchers(): void {
    this.lastLrPercent =
      AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
    this.lastUpDownPx =
      AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
    this.lastWidthDp =
      AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
    if (this.geomTimerId !== -1) {
      return
    }
    this.geomTimerId = setInterval((): void => {
      const lr =
        AppStorage.get<number>('floatingWindowSbLrLeftRightPercent') ?? 0
      const ud = AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0
      const w = AppStorage.get<number>('floatingWindowSbLrWidthDp') ?? 150
      if (lr !== this.lastLrPercent || ud !== this.lastUpDownPx || w !== this.lastWidthDp) {
        this.lastLrPercent = lr
        this.lastUpDownPx = ud
        this.lastWidthDp = w
        this.applyGeometry()
      }
    }, 250) as number
  }

  private stopGeometryWatchers(): void {
    if (this.geomTimerId !== -1) {
      clearInterval(this.geomTimerId)
      this.geomTimerId = -1
    }
  }

  // Read the current sub-line from the LyricsViewModel maintained inside
  // MiniLyricsController. The MiniLyricsListener already gives us mainText;
  // the spec wants `subText` of the same LyricsLine when translation is on.
  // For the v1 path we expose the sub-line via a parallel publisher hook on
  // MiniLyricsController (planned in §4.6) and read it directly from there.
  private currentSubLineFor(_main: string): string {
    return MiniLyricsController.getInstance().currentSubLine ?? ''
  }
}

export default FloatingStatusBarLyricsController
```

If the HarmonyOS SDK in use does not support `display.getDefaultDisplaySync()` or `window.setWindowTouchable(false)`, the calls are individually wrapped in `try/catch`, so the worst case is a window that intercepts touches (degraded UX, not a crash) or a fixed-size window (won't update on slider drag); the rest of the feature still works.

### 4.5 `entry/src/main/ets/pages/FloatingStatusBarLyricsWindow.ets` (new)

```ts
// FloatingStatusBarLyricsWindow.ets
// spec25 — UI content of the system-level floating window. Reads every
// rendered parameter from AppStorage so changes in the Settings page (a
// different ArkTS window) propagate live with no extra IPC. Owns:
//   - main lyric Text + optional sub-line Text
//   - marquee/scroll behaviour when the text overflows the configured width
//   - fade-in/fade-out animation on play/pause
//   - visibility gating against playerPageVisible + hideOnPlayer
//
// MVVM owner: this is the View. No persistence, no system calls, no business
// rules beyond presentation.

@Entry
@Component
struct FloatingStatusBarLyricsWindow {
  @StorageProp('floatingWindowSbLrLine') line: string = ''
  @StorageProp('floatingWindowSbLrSubLine') subLine: string = ''
  @StorageProp('floatingWindowSbLrHasLyrics') hasLyrics: boolean = false
  @StorageProp('floatingWindowSbLrWidthDp') widthDp: number = 150
  @StorageProp('floatingWindowSbLrFontSizeDp') fontSizeDp: number = 14
  @StorageProp('floatingWindowSbLrColor') colorArgb: number = 0xFF0470E6
  @StorageProp('floatingWindowSbLrCenterAlign') centerAlign: boolean = false
  @StorageProp('statusBarLyricsNotShowTranslation') notShowTranslation: boolean = false
  @StorageProp('floatingWindowSbLrHideOnPlayer') hideOnPlayer: boolean = false
  @StorageProp('playerPageVisible') playerPageVisible: boolean = false
  @StorageProp('isPlaying') isPlaying: boolean = false

  // Local UI-only state
  @State textOverflow: boolean = false

  build() {
    Column() {
      if (this.shouldRenderText()) {
        // Wrap in a fade-driven container so play/pause animates opacity
        // on the lyric *text*, not the whole window.
        Column() {
          if (this.textOverflow) {
            Marquee({
              src: this.line,
              start: this.isPlaying,
              step: 6,
              loop: -1,
              fromStart: false,
              fontSize: this.fontSizeDp,
              fontColor: this.colorArgb,
            })
              .width(`${this.widthDp}vp`)
          } else {
            Text(this.line)
              .fontSize(this.fontSizeDp)
              .fontColor(this.colorArgb)
              .width(`${this.widthDp}vp`)
              .textAlign(this.centerAlign ? TextAlign.Center : TextAlign.Start)
              .maxLines(1)
              .onAreaChange((_o, n) => {
                // Heuristic: when the rendered single-line Text would clip
                // because its intrinsic width exceeds widthDp, switch to
                // marquee. We use ellipsis-vs-fit heuristics in a follow-up
                // (Text.measure is not always available); for v1 use the
                // overflow flag set by the parent watcher below.
              })
          }
          if (!this.notShowTranslation && this.subLine.length > 0) {
            Text(this.subLine)
              .fontSize(this.fontSizeDp * 0.85)
              .fontColor(this.colorArgb)
              .width(`${this.widthDp}vp`)
              .textAlign(this.centerAlign ? TextAlign.Center : TextAlign.Start)
              .maxLines(1)
          }
        }
        .opacity(this.isPlaying ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseInOut })
      }
    }
    .width(`${this.widthDp}vp`)
    .height('100%')
    .visibility(this.isHiddenByPlayer() ? Visibility.Hidden : Visibility.Visible)
  }

  // Scenario 2 step 7, 19: lyric text is invisible when no lyrics yet, even
  // though the window exists. Achieved by not rendering Marquee/Text at all.
  private shouldRenderText(): boolean {
    return this.hasLyrics && this.line.length > 0
  }

  // Scenario 16/17: hide while player page is on top.
  private isHiddenByPlayer(): boolean {
    return this.hideOnPlayer && this.playerPageVisible
  }
}
```

Register the new entry page in `entry/src/main/resources/base/profile/main_pages.json`:

```jsonc
{
  "src": [
    // ...existing entries...
    "pages/FloatingStatusBarLyricsWindow"
  ]
}
```

**Marquee overflow detection.** ArkTS does not expose `Text.measureText` in every release. For v1 we rely on the platform's built-in clipping: when `Text` content overflows `width(widthDp vp)` the platform draws an ellipsis. The spec's scenario 4 ("跑马灯") fallback then requires switching to `Marquee`. The pragmatic approach: ALWAYS render `Marquee` (it auto-stops/auto-renders static when content fits the width). That removes the overflow-detection problem and matches scenario 5's "未超出宽度时不滚动" naturally (Marquee shows static text when `src` width ≤ container width). Replace the conditional above with a single `Marquee` block during implementation if testing reveals `Marquee`-only rendering looks correct for static lines too.

### 4.6 `entry/src/main/ets/model/MiniLyricsController.ets` — expose subLine

Add a `public get currentSubLine(): string` accessor (one-liner) so the controller in §4.4 can read the current line's translation without touching `LyricsViewModel` from outside the model layer.

```ts
// Inside MiniLyricsController, next to the existing currentLine field:
private _currentSubLine: string = ''
public get currentSubLine(): string { return this._currentSubLine }

// In tickOnce(), where currentLine is updated:
if (newHasLyrics && idx >= 0 && idx < doc.lines.length) {
  newLine = doc.lines[idx].mainText
  this._currentSubLine = doc.lines[idx].subText
} else {
  this._currentSubLine = ''
}
```

Alternative: instead of leaking sub-line via the controller, make `MiniLyricsListener` carry an extra `subLine` argument. That is a wider blast radius (every existing listener has to update), so we choose the additive accessor.

### 4.7 String / resource changes

**No new strings required.** Verified existing keys:

- `floating_window_status_bar_lyrics`, `_info`, `_tip` — `base:1196-1207`
- `left_and_right_position`, `up_and_down_position` — `base:1476, 3120`
- `position`, `size`, `width` — `base:2480, 2744, 3236`
- `lyrics_text_left_aligned`, `_info` — `base:1540, 1544`
- `status_bar_lyrics_not_show_translation`, `_info` — `base:2924, 2928`
- `hide_on_playback_screen` — `base:1328`
- `choose_color` — `base:620`
- `no_floating_window_permission`, `_tip` — `base:232, 2252`
- `floating_window_permission_reason` — `base:228`

All exist in `zh/` and `ug/` variants too.

### 4.8 `entry/src/main/ets/pages/LyricsSettingsPage.ets`

**No change.** The nav row already pushes `'FloatingWindowStatusBarLyricsPage'` (verified at `:177`).

### 4.9 `entry/src/main/ets/pages/main/MainPage.ets`

**No change.** The NavDestination switch already maps `'FloatingWindowStatusBarLyricsPage'` to the component (verified at `:928-929`). The new float-window content page is loaded via `window.setUIContent` and is NOT a NavDestination — no MainPage wiring.

### 4.10 `entry/src/main/module.json5`

**No change.** `ohos.permission.SYSTEM_FLOAT_WINDOW` already declared.

## 5. Refresh model (live update path, end-to-end)

```
SETTINGS PAGE (a Settings sub-page, lives inside the main app window)
─────────────────────────────────────────────────────────────────────
[User drags any slider / flips any switch / picks a color]
        │
        ▼
FloatingWindowStatusBarLyricsViewModel.on*Changed(val)
        │
        ▼
SettingsStore.save('floatingWindowSbLr*', val)
   → preferences.putSync + flushSync                (durable, on-disk)
   → AppStorage.setOrCreate                          (live, in-memory)
        │
        ▼
   AppStorage @StorageLink subscribers in the float-window page
   refresh on the next frame; controller.applyGeometry() refreshes
   window position / size on the next 250 ms watcher tick.

MASTER SWITCH ON
────────────────
[User flips master OFF→ON]
        │
        ▼
ViewModel.onMasterToggleChanged(true)
        │
        ▼
FloatingWindowPermission.ensurePermission()
        │
        ├── granted → continue
        └── missing → startAbility(...) to system settings page;
                       on user return EntryAbility.onForeground fires
                       FloatingWindowPermission.reprobeOnForeground();
                       on permission grant: grant-listener flips master
                       back to ON via onPermissionGrantedFromSettings().
        │
        ▼
SettingsStore.save('floatingWindowStatusBarLyrics', true)
        │
        ▼
FloatingStatusBarLyricsController.show()
   → window.createWindow(TYPE_SYSTEM_FLOAT)
   → window.setUIContent('pages/FloatingStatusBarLyricsWindow')
   → window.setWindowBackgroundColor('#00000000')
   → applyGeometry()  (reads AppStorage; resize + moveWindowTo)
   → startGeometryWatchers()
   → window.showWindow()
        │
        ▼
FloatingStatusBarLyricsWindow.@Entry renders
   @StorageProp picks up: line, subLine, widthDp, fontSizeDp, colorArgb,
                           centerAlign, notShowTranslation, hideOnPlayer,
                           playerPageVisible, isPlaying

MASTER SWITCH OFF
─────────────────
ViewModel.onMasterToggleChanged(false)
   → SettingsStore.save('floatingWindowStatusBarLyrics', false)
   → controller.hide() → stopGeometryWatchers() → window.destroyWindow()

LIVE LYRIC TICK (scenario 4)
────────────────────────────
MiniLyricsController.tickOnce()  (every 200 ms while initialised)
   → if (mainText changed):
        listener(songId, line, hasLyrics) fires
            │
            ▼
        controller.lyricsListener(...)
            → AppStorage.setOrCreate('floatingWindowSbLrLine', line)
            → AppStorage.setOrCreate('floatingWindowSbLrSubLine',
                MiniLyricsController.getInstance().currentSubLine)
            → AppStorage.setOrCreate('floatingWindowSbLrHasLyrics', has)
            │
            ▼
        @StorageProp in FloatingStatusBarLyricsWindow refreshes the Marquee
        / Text on the next frame.

PLAY/PAUSE FADE (scenarios 5, 6)
────────────────────────────────
AudioPlayerService sets AppStorage('isPlaying', false) on pause
   → FloatingStatusBarLyricsWindow @StorageProp picks it up
   → animation({ duration: 300 }) on .opacity transitions to 0
On resume: AppStorage('isPlaying', true) → opacity transitions to 1.

PLAYER PAGE GATING (scenarios 16, 17)
─────────────────────────────────────
ScreenWakeViewModel.onPlayerVisibilityChanged(true|false)
   → AppStorage.setOrCreate('playerPageVisible', ...)
   → @StorageProp in window page refreshes .visibility() depending on
     hideOnPlayer + playerPageVisible.

COLD START (scenario 18)
────────────────────────
EntryAbility.onCreate:
   PersistentStorage.persistProp registers keys.
   SettingsStore.get(...) hydrates AppStorage.
   AudioPlayerService.initContext.
   MiniLyricsController.init.
   NotificationLyricController.init.
   MediaCardCloseButtonController.init.
   MediaCardDesktopLyricsButtonController.init.
   FloatingStatusBarLyricsController.init(this.context):
      if AppStorage('floatingWindowStatusBarLyrics') === true:
         show() (no permission probe — relies on system-level grant durability)

NO-LYRICS SONG (scenario 19)
────────────────────────────
MiniLyricsController publishes hasLyrics=false on song change for a song
with no LRC. Window page reads @StorageProp('floatingWindowSbLrHasLyrics'),
shouldRenderText() returns false, no Text rendered. When the user advances
to a song with lyrics the publish resumes and Text reappears.
```

## 6. Scenario coverage

| Scenario | Path covered | Verification |
| --- | --- | --- |
| S1 (master ON without permission → prompt + stay OFF) | `ViewModel.onMasterToggleChanged(true)` → `FloatingWindowPermission.ensurePermission()` returns false → `master = false`, toast `no_floating_window_permission`. | Revoke overlay permission, flip master. Verify toast + master stays OFF + nothing created. |
| S2 (master ON with permission → window shows with defaults) | `ensurePermission()` true → `SettingsStore.save('floatingWindowStatusBarLyrics', true)` → `controller.show()` → `createWindow` → `setUIContent` → `applyGeometry` reads default AppStorage values (0%, 0px, 150dp, 14dp, 0xFF0470E6, centerAlign=false). | Fresh install, grant permission, flip master ON. Verify float window appears at top-left of status-bar region with blue 14dp left-aligned lyric. |
| S3 (master OFF → window removed) | `onMasterToggleChanged(false)` → `controller.hide()` → `destroyWindow`. | Flip master OFF. Verify window gone within ~200 ms. |
| S4 (playback advances → live lyric scroll) | `MiniLyricsController.tickOnce` (200 ms) → controller listener updates AppStorage → window page Marquee `src` changes. Overflow content scrolls automatically. | Play song with long lyric line and short width (e.g. 50 dp). Verify marquee scrolls right→left. Width 750 dp on a short line: no scrolling, static text. |
| S5 (pause → text fades out) | `AppStorage('isPlaying') = false` → page `.opacity` animates to 0 over 300 ms. Window object stays alive. | Press pause. Lyric fades out within 300 ms; flip master OFF then ON: window recreated, text re-appears immediately. |
| S6 (resume → text fades in) | `AppStorage('isPlaying') = true` → page `.opacity` animates to 1. | Press play. Lyric fades in within 300 ms. |
| S7 (drag X slider 0–100 %) | `onLeftRightPercentChanged(val)` → SettingsStore save → controller geometry watcher (250 ms) calls `applyGeometry` → `moveWindowTo`. | Drag slider end-to-end. Verify window moves horizontally; after app restart slider position is preserved. |
| S8 (drag Y slider 0–100 px) | `onUpDownPxChanged(val)` → save → geometry watcher → applyGeometry → moveWindowTo. | Drag slider. Verify window moves vertically. Restart preserves. |
| S9 (drag width 50–750 dp) | `onWidthDpChanged(val)` → save → both controller (window resize) + page (`width('${widthDp}vp')`) react. Marquee auto-decides static-vs-scroll based on widthPx. | Drag width slider. Verify window resizes; long content starts scrolling when width narrow. Restart preserves. |
| S10 (drag font size 8–32 dp) | `onFontSizeDpChanged(val)` → save → page `@StorageProp` updates `fontSize` reactively. | Drag font slider. Verify text grows/shrinks immediately. Restart preserves. |
| S11 (color picker → tap a swatch) | Page Confirm button → `vm.onColorChanged(swatchInt)` → save → page `@StorageProp('floatingWindowSbLrColor')` updates `fontColor`. | Open dialog, tap red, confirm. Window text turns red. Restart preserves. |
| S12 (center align ON) | `onCenterAlignChanged(true)` → save → page `textAlign(TextAlign.Center)`. | Toggle on. Text becomes centered within widthDp. Restart preserves. |
| S13 (center align OFF) | Same path with val=false → `textAlign(TextAlign.Start)`. | Toggle off. Left-aligned. |
| S14 (translation hide ON) | `onNotShowTranslationChanged(true)` → save `statusBarLyricsNotShowTranslation` → page `if (!notShowTranslation && subLine.length>0)` evaluates false → sub-Text omitted. | Play song with translation. Toggle on. Only one line shows. |
| S15 (translation hide OFF) | Toggle off → both lines render. | Toggle off. Both main + sub render. |
| S16 (hide on player ON + open player page) | `onHideOnPlayerChanged(true)` → save → user opens PlayerPage → ScreenWakeViewModel writes `playerPageVisible=true` → window page `.visibility(Visibility.Hidden)`. | Toggle on, open player. Window hidden until player closed. |
| S17 (hide on player ON + leave player) | `playerPageVisible=false` → `.visibility(Visibility.Visible)`. | Close player. Window reappears. |
| S18 (cold start with master ON → auto-show) | `EntryAbility.onCreate` hydrates AppStorage from SettingsStore, then `FloatingStatusBarLyricsController.init` reads master flag and calls `show()`. | Restart app with master previously ON. Window appears within a few seconds of launch (after `init`). |
| S19 (no-lyrics song) | `MiniLyricsController` publishes `hasLyrics=false`. Page `shouldRenderText()` returns false. | Play instrumental track. Window stays alive, no text visible. Switch to song with lyrics: text appears. |

## 7. Owner-boundary safeguards (per harness rules)

- **Page does not persist.** `FloatingWindowStatusBarLyricsPage` calls only `vm.on*Changed(...)`. Master toggle persistence moves out of the Page (currently violates MVVM at `:142-144`) into the ViewModel.
- **No mirror state.** Every persisted setting has exactly one AppStorage key. The ViewModel's `@Track` fields are hydrated FROM AppStorage in the constructor and are kept in sync with `SettingsStore.save` (which writes both AppStorage and disk). The controller never holds a private copy — it reads AppStorage at the moment it needs the value. The float-window page binds via `@StorageProp` / `@StorageLink`.
- **`aboutToAppear` is NOT used for live sync.** The ViewModel constructor seeds initial state once; everything thereafter flows via SettingsStore.save → AppStorage → @StorageLink. The float-window page is an `@Entry`-rooted ArkTS page in a separate window; `aboutToAppear` there only triggers the initial render — no business logic.
- **No fake defaults.** Default values match the spec's "scenario 2" defaults exactly (0%, 0 px, 150 dp, 14 dp, 0xFF0470E6 blue, left-align, no-center, no-hide-translation, no-hide-on-player). Defaults are placed in `EntryAbility.persistProp`, NOT in field initializers — so changing the default requires changing exactly one line and there's no risk of a UI-layer "ghost" default disagreeing with the persisted one.
- **Float window lifecycle is owned by the controller.** Page does not call `window.createWindow`. ViewModel does not call `window.createWindow`. Only `FloatingStatusBarLyricsController.show()` does. Mirrors spec24's controller-owns-the-AVSession-write boundary.
- **Permission probe is in the Model layer.** ViewModel calls `FloatingWindowPermission.ensurePermission()`. The page never touches the permission API.
- **Live updates flow through one channel.** AppStorage is the single bus. The float-window page reads everything reactively; the controller imperatively resizes/moves because the *window object* (not the page) owns geometry — that's the only imperative path.
- **Per-song reset of the rendered line happens in the controller.** Song-changed listener clears AppStorage('floatingWindowSbLrLine') / subLine so the window doesn't carry an old line into a new song's load window.
- **Sub-line publish exits the model layer cleanly.** Adding `currentSubLine` to `MiniLyricsController` is preferred over leaking `LyricsViewModel` references into `FloatingStatusBarLyricsController`. The controller is one consumer; future consumers can do the same.

## 8. Out of scope (do not change)

- `LyricsModel`, `LyricsViewModel`, `LyricsLoader` — unchanged. Translation rendering uses the existing `LyricsLine.subText` field.
- `AudioPlayerService` — unchanged. We only read `AppStorage('isPlaying')` and subscribe via the existing `addOnSongChangedListener` bus.
- `NotificationLyricController` (spec12), `MediaCardCloseButtonController` (spec23), `MediaCardDesktopLyricsButtonController` (spec24) — unchanged. The new controller subscribes to the same lyric stream but never blocks them.
- `LyricsSettingsPage` — unchanged.
- `MainPage` NavDestination map — unchanged.
- `module.json5` — unchanged.
- The desktop lyrics floating window (spec18) — different window, different feature. The `desktopLyrics` AppStorage key is independent.
- The system-level status bar lyrics path (the row above the floating-window row on `LyricsSettingsPage`) — shares only the `statusBarLyricsNotShowTranslation` key per §3.2 / Interp A. No code changes to the system-level path.

## 9. Verification checklist (post-implementation)

- [ ] Build the project — no new compilation errors. `window`, `display` imports compile; `WindowType.TYPE_SYSTEM_FLOAT` exists in the SDK in use; if not, fall back to `TYPE_FLOAT` and surface a warning.
- [ ] Fresh install + grant overlay permission. Open Lyrics Settings → 悬浮窗状态栏歌词. Flip master ON. Verify a transparent overlay appears at top-left of status-bar region with blue, 14 dp, left-aligned lyric.
- [ ] Drag each slider end-to-end. Verify live UI update on every drag step within ~250 ms (controller geometry watcher) for X/Y/width; immediate (next frame) for font size and color. Verify the values persist after force-killing and relaunching the app.
- [ ] Toggle 居中对齐 / 不显示翻译 / 在播放界面隐藏. Verify each:
   - 居中对齐 ON → text centered within widthDp; OFF → text left-aligned.
   - 不显示翻译 ON → sub-line hidden even for songs with `subText`; OFF → sub-line rendered below main.
   - 在播放界面隐藏 ON → opening PlayerPage hides the float window; closing PlayerPage shows it.
- [ ] Open color picker → tap each swatch → Confirm → window text color matches. Cancel button does not change persistence.
- [ ] Pause → text fades out over ~300 ms. Resume → text fades in. Window itself never destroyed in this path.
- [ ] Skip to song with no LRC. Window stays alive, text empty. Skip back to a song with LRC; text resumes.
- [ ] Skip to song with a long lyric line that exceeds the configured widthDp. Verify marquee scrolling kicks in. Increase widthDp until line fits → marquee stops scrolling.
- [ ] Master OFF → window disappears within ~200 ms.
- [ ] Master ON without permission (revoke first) → toast appears, master stays OFF. Tap toggle again → system settings opens; grant permission, navigate back. Verify EntryAbility.onForeground re-probes; ViewModel grant-listener fires; master flips to ON; window appears.
- [ ] Force-kill the app with master ON. Relaunch. Verify the float window re-appears with the persisted geometry/color/font/alignment within a few seconds of launch (after `MiniLyricsController.init` + `FloatingStatusBarLyricsController.init`).
- [ ] No regression to spec23 (showCloseButton), spec24 (showDesktopLyricsButton), spec12 (notification bar lyrics title override), MiniLyricsController 200 ms tick, or the in-app player's lyric panel.
