# Spec15 — 隐藏歌词界面控制面板 (Hide Lyrics Screen Control Panel) Implementation Plan

## 1. Overview

Implement the **"隐藏歌词界面控制面板" (Hide Lyrics Screen Control Panel)** toggle. When enabled, the bottom control area of `PlayerPage` (time bar + play controls + icon panel) horizontally translates off-screen while the user swipes from the cover page (index 1) to the lyrics page (index 2), and remains hidden while lyrics page is fully visible. The lyrics area expands downward to use the freed space. The setting is a Pro-gated feature available from two entry points:

1. `LyricsInterfacePage` (设置 → 用户界面 → 歌词界面) — HdsListItemCard switch row, already scaffolded but not Pro-gated, not persisted, not connected to runtime rendering.
2. `LyricsInterfaceDialogComponent` (播放页 → 歌词页 → 底部齿轮 → 弹窗) — currently the dialog has the Pro-gated row **commented out** (`SettingsGroup3` builder is unused).

The setting must persist across app restarts and propagate live (without page reload) between the two entry points and the player render path.

## 2. MVVM Owner Boundary

| Layer | Owner | Responsibility |
|---|---|---|
| **Page (settings)** | `LyricsInterfacePage` | Renders Pro-gated switch row; delegates change to VM |
| **Page (player)** | `PlayerPage` | Reads `lyricsHideControlPanel` via `@StorageProp`; renders bottom-control translation/visibility; tracks Swiper gesture progress for animation |
| **Component (dialog)** | `LyricsInterfaceDialogComponent` | Re-enables `SettingsGroup3`; renders same Pro-gated switch row; delegates to VM |
| **ViewModel** | `LyricsInterfaceViewModel` | Owns `hideControlPanel` state; persists via `SettingsStore` (AppStorage + Preferences); seeds Pro status from a single source of truth |
| **Model** | `LyricsInterfaceModel` | Loads `hideControlPanel` from `AppStorage` in `loadFromStorage()`; persists in `saveToStorage()` |
| **EntryAbility** | `EntryAbility` | Registers `PersistentStorage.persistProp('lyricsHideControlPanel', false)` and SettingsStore restore on cold start |

**Key rule:** Persistence path is **ViewModel → SettingsStore.save → AppStorage + Preferences**. PlayerPage subscribes via `@StorageProp` only — it never writes. The setting flows ViewModel → AppStorage → both consumers (`LyricsInterfacePage @StorageProp`-equivalent via shared ViewModel singleton, and `PlayerPage @StorageProp`). Do not move persistence to Page. Do not introduce a parallel mirror state in `PlayerPageViewModel`.

## 3. Data Flow

```
User toggles switch
    (LyricsInterfacePage row OR LyricsInterfaceDialogComponent row)
        |
        v
LyricsInterfaceViewModel.updateHideControlPanel(val)
        |  (Pro-gated)
        v
    +---- this.hideControlPanel = val   (drives both entry-point switches via @ObjectLink / singleton)
    +---- this.model.hideControlPanel = val
    +---- SettingsStore.getInstance().save('lyricsHideControlPanel', val)
                 |
                 +-- AppStorage.setOrCreate('lyricsHideControlPanel', val)   (live)
                 +-- preferences.putSync + flushSync                          (cold-start durable)
        |
        v
PlayerPage @StorageProp('lyricsHideControlPanel') hideControlPanel: boolean
        |
        v
    Render branches:
      - PlayerControlsCluster: translateX driven by Swiper gesture progress (when hideControlPanel)
                               translateX = 0 (when !hideControlPanel)
      - LyricsArea bottom padding: collapsed (when hideControlPanel) / preserved (when !hideControlPanel)
```

## 4. Ground-Truth Anchors

Already in repo (do not duplicate):

- `entry/src/main/ets/model/LyricsInterfaceModel.ets`: `hideControlPanel: boolean = false` field + constructor param (line 20–37). Missing from `loadFromStorage()` (line 44) and `saveToStorage()` (line 63).
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`: `@Track hideControlPanel` (line 34), `syncFromModel` (line 83), `updateHideControlPanel` (line 170) — Pro-gated but writes only to model, no `SettingsStore.save` and no AppStorage broadcast. `isPro` defaults to `false`, never refreshed.
- `entry/src/main/ets/pages/LyricsInterfacePage.ets`: HdsListItemCard row already calls `viewModel.updateHideControlPanel` (line 182–201) but does NOT apply Pro-gating (no `enable:` attribute, no crown adjunct).
- `entry/src/main/ets/components/LyricsInterfaceDialogComponent.ets`: `SettingsGroup3` builder defined at line 202–222 with proper Pro-gating and `showProIcon`, but the builder call site at line 65 is commented out.
- `entry/src/main/ets/resources/base/element/string.json` (line 1320): `hide_lyrics_screen_control_panel` string exists in `base`, `zh`, `ug`.
- `entry/src/main/ets/pages/PlayerPage.ets`: bottom controls live in lines 570–574 (`PlayerTimeBar`, `PlayerControlBar`, `PlayerIconPanel`) inside the Page-0 Column under the Swiper. `hSwiperIndex`, `onGestureSwipe` (line 551), `onAnimationStart` (line 557), `onAnimationEnd` (line 563) are existing hook surfaces.
- `entry/src/main/ets/entryability/EntryAbility.ets` lines 73–79: existing pattern for `PersistentStorage.persistProp` + `SettingsStore.get` for lyrics keys.
- No landscape / full-screen lyrics page exists in the project (`MainPageViewModel` has only `isHorizontalDrag` for tab swiping; no landscape player UI). Scene 7 thus simplifies to "applies in `PlayerPage`".
- No RTL layout direction is detected/used anywhere in this codebase. Scene 6 reduces to "translate towards the left edge" (LTR only). The plan still parameterizes direction so an RTL fork can be added later without restructuring.

## 5. Implementation Steps

### Step 5.1 — Persistence Foundation

**File:** `entry/src/main/ets/entryability/EntryAbility.ets`

After the existing lyrics persistence block (line 79, after `PersistentStorage.persistProp('lyricsBlur', false)`), add:

```typescript
// Spec15: hide lyrics screen control panel (Pro-gated)
PersistentStorage.persistProp('lyricsHideControlPanel', false)
```

After the existing lyrics restore line (line 185, after the `lyricsBlur` restore), add:

```typescript
AppStorage.setOrCreate('lyricsHideControlPanel',
  ss.get('lyricsHideControlPanel', false) as boolean)
```

This guarantees the value is hydrated into AppStorage before any UI mounts.

### Step 5.2 — Model layer: load/save

**File:** `entry/src/main/ets/model/LyricsInterfaceModel.ets`

Extend `loadFromStorage()` to read `lyricsHideControlPanel`:

```typescript
static loadFromStorage(): LyricsInterfaceModel {
  // ...existing reads...
  const hideControlPanel = (AppStorage.get('lyricsHideControlPanel') as boolean) ?? false
  return new LyricsInterfaceModel(
    textSize, textAlignCenter, fontWeight, blur,
    karaokeCompatStrategyIndex, hideControlPanel, /* isPro filled by VM */ false
  )
}
```

Extend `saveToStorage()` to write `lyricsHideControlPanel`:

```typescript
saveToStorage(): void {
  // ...existing setOrCreate calls...
  AppStorage.setOrCreate('lyricsHideControlPanel', this.hideControlPanel)
}
```

### Step 5.3 — ViewModel: persistence + Pro single source

**File:** `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`

(a) In `syncFromModel()` (after the existing `AppStorage.setOrCreate` block at line 88–91), add:

```typescript
AppStorage.setOrCreate('lyricsHideControlPanel', this.hideControlPanel)
```

This guarantees PlayerPage `@StorageProp` is seeded on first VM construction even before any explicit toggle.

(b) Rewrite `updateHideControlPanel(value: boolean)` (currently at line 170–176) so it persists through `SettingsStore`:

```typescript
updateHideControlPanel(value: boolean): void {
  if (!this.isPro) {
    return  // Pro-gated: silently ignore non-Pro toggles (scene 8)
  }
  this.hideControlPanel = value
  this.model.hideControlPanel = value
  SettingsStore.getInstance().save('lyricsHideControlPanel', value)
}
```

This replaces the existing `this.model.saveToStorage()` call. `SettingsStore.save` already covers both AppStorage + Preferences. Calling `model.saveToStorage()` here would unnecessarily re-write every other lyrics key on every toggle; switching to a single-key write keeps the side-effect surface tight.

(c) Refresh `isPro` from a single source on every `loadSettings()` and at construction. There is **no global Pro AppStorage key** in this repo today — `SettingsViewModel.isPro` is also a local field defaulting to `false`. Two options:

- **Chosen path:** Read once via `AppStorage.get<boolean>('isPro') ?? false`. Plan also adds `PersistentStorage.persistProp('isPro', false)` in `EntryAbility` (next to other booleans) so a future "Pro activation" path can flip a single key and every gated screen reacts. Update `loadSettings()` and the constructor to seed `this.isPro = AppStorage.get<boolean>('isPro') ?? false`.

This avoids inventing a new model field. `LyricsInterfaceModel.isPro` already exists (line 21) and is ignored on storage round-trip — keep it as a transient field set by the VM.

### Step 5.4 — Settings page Pro-gating

**File:** `entry/src/main/ets/pages/LyricsInterfacePage.ets`

Update the HdsListItemCard at line 182–201 to:

1. Disable interaction when `!viewModel.isPro` (mirror the existing `enable: this.viewModel.isBlurSupported` pattern at line 159).
2. Render the crown adjunct icon when `!viewModel.isPro`.

Two compatible approaches with HdsListItemCard:

- Add `enable: this.viewModel.isPro` to the card.
- For the crown indicator: wrap the row in a `Row` and prepend an `Image($r('app.media.ic_crown'))` when `!this.viewModel.isPro`, OR use HdsListItemCard's `prefixItem` slot if available. Fall back to a leading `Image` in the primary text builder if the slot is missing.

Concrete sketch:

```typescript
HdsListItemCard({
  textItem: {
    primaryText: { text: $r('app.string.hide_lyrics_screen_control_panel') },
  },
  suffixItem: new SuffixSwitch({
    isCheck: this.viewModel.hideControlPanel,
    onChange: (val: boolean) => {
      this.viewModel.updateHideControlPanel(val)
    }
  }),
  cardPrefixMargin: 4,
  cardSuffixMargin: 4,
  cardBackgroundColor: Color.Transparent,
  enable: this.viewModel.isPro,
  // If HdsListItemCard supports prefixItem: emit crown when !isPro.
  // Otherwise: see fallback below.
})
```

**Fallback if `enable:` does not propagate to SuffixSwitch click suppression:** keep the Pro-gate check inside `updateHideControlPanel` (Step 5.3) — that already short-circuits writes for non-Pro users. The visual disabled state can be approximated by wrapping the card in `.opacity(this.viewModel.isPro ? 1.0 : 0.5)`.

### Step 5.5 — Dialog (player bottom-sheet) Pro-gating

**File:** `entry/src/main/ets/components/LyricsInterfaceDialogComponent.ets`

Uncomment the `this.SettingsGroup3()` call at line 65. The builder body at line 202–222 already wires `showProIcon: !this.viewModel.isPro`, `enabled: this.viewModel.isPro`, and the change handler. No new code needed inside `SettingsGroup3` — only the call-site uncomment.

### Step 5.6 — PlayerPage: render branch + animation

**File:** `entry/src/main/ets/pages/PlayerPage.ets`

(a) Add an `@StorageProp` near the existing lyrics-settings group (around line 86, after `lyricsBlur`):

```typescript
@StorageProp('lyricsHideControlPanel') lyricsHideControlPanel: boolean = false
```

(b) Track Swiper gesture progress used to compute translation. Add two `@State` fields next to the existing isLyricsExposed bookkeeping (around line 157):

```typescript
// Spec15: horizontal translation progress for the bottom-control cluster.
// 0 = fully on-screen (cover or info page), 1 = fully off-screen (lyrics page).
// Driven by Swiper.onGestureSwipe + onChange to follow the user's finger.
@State private bottomControlsHideProgress: number = 0
```

Add a private helper that resolves the screen-width-equivalent translation distance. PlayerPage already tracks `this.vm.screenHeight` via `onAreaChange` on the inner Stack (line 598–611). Add a parallel `screenWidth` field on `PlayerPageViewModel` (a single `@Track public screenWidth: number = 0` next to `screenHeight`, set in the same `onAreaChange`). Plus 1 px is fine — the translation only needs to clear the viewport.

(c) On `Swiper.onGestureSwipe(index, extraInfo)` (line 551), compute progress:

```typescript
.onGestureSwipe((index: number, extraInfo: SwiperAnimationEvent) => {
  if (index === 1 && extraInfo.currentOffset < 0) {
    this.isLyricsExposed = true
  }
  // Spec15: hide-progress follows finger between cover (1) ↔ lyrics (2).
  if (this.lyricsHideControlPanel && this.vm.screenWidth > 0) {
    let p = 0
    if (index === 1) {
      // cover → lyrics: currentOffset is negative as lyrics enters from right
      const ratio = Math.min(Math.max(-extraInfo.currentOffset / this.vm.screenWidth, 0), 1)
      p = ratio
    } else if (index === 2) {
      // lyrics → cover: currentOffset is positive as cover re-enters
      const ratio = Math.min(Math.max(extraInfo.currentOffset / this.vm.screenWidth, 0), 1)
      p = 1 - ratio
    }
    this.bottomControlsHideProgress = p
  }
})
```

On `onAnimationStart`/`onAnimationEnd` (lines 557–568) and on `onChange` (line 536), snap `bottomControlsHideProgress` to the final state when settled, with `animateTo` for the snap so a flick across the Swiper plays a smooth tail animation:

```typescript
.onChange((index: number) => {
  // ...existing assignments to vm.hSwiperIndex / advanceProgress()...
  if (this.lyricsHideControlPanel) {
    const target = index === 2 ? 1 : 0
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bottomControlsHideProgress = target
    })
  } else {
    // hideControlPanel off: always show controls
    this.bottomControlsHideProgress = 0
  }
})
```

(d) Apply the translation + opacity to the bottom-control Column (lines 570–576):

```typescript
Column() {
  this.PlayerTimeBar()
  this.PlayerControlBar()
  this.PlayerIconPanel()
}
.width('100%')
.justifyContent(FlexAlign.End)
.translate({
  x: this.lyricsHideControlPanel && this.vm.screenWidth > 0
    ? -this.bottomControlsHideProgress * this.vm.screenWidth
    : 0
})
// Fade in parallel so the cluster disappears cleanly when off-screen.
.opacity(this.lyricsHideControlPanel ? 1 - this.bottomControlsHideProgress : 1)
// Collapse height while fully off-screen so LyricsArea (layoutWeight 1)
// expands into the freed space. Stays at intrinsic height when partially
// visible so the slide animation has somewhere to play.
.height(this.lyricsHideControlPanel && this.bottomControlsHideProgress >= 1 ? 0 : undefined)
```

The `.height(0)` collapse fires only at progress >= 1 (lyrics page fully settled), so during the gesture / snap the cluster stays in its native row, slides horizontally, and only collapses once finished. The Swiper above uses `layoutWeight(1)` (line 534) so it naturally absorbs the freed pixels — this gives LyricsArea the "扩大歌词展示区域" effect from scenes 4.2.2 / 4.2.4.

(e) Bottom settings bar (歌词来源 / 翻译) inside `LyricsArea` (line 1468–1517) is **separate** from the bottom-control cluster and is governed only by `immersionMode` (already implemented). Scene 4.3 / 5.3 explicitly state this. No change needed.

(f) Sync `screenWidth` on the existing onAreaChange in `PlayerPage.build()` (line 598). Modify it to capture both dimensions:

```typescript
.onAreaChange((_: Area, newArea: Area) => {
  const newHeight = newArea.height as number
  const newWidth = newArea.width as number
  if (newHeight > 0 && newHeight !== this.vm.screenHeight) {
    // ...existing height-bookkeeping block...
  }
  if (newWidth > 0 && newWidth !== this.vm.screenWidth) {
    this.vm.screenWidth = newWidth
  }
})
```

### Step 5.7 — Initial snap state

When PlayerPage opens directly on lyrics page (`hSwiperIndex` restored as `2` from AppStorage, line 124 of `PlayerPageViewModel.ets`), the controls must already be off-screen. In `PlayerPage.aboutToAppear`, after `this.vm.initialize()`:

```typescript
// Spec15: seed slide state so a restart on the lyrics page does not flash
// the controls before the first onChange fires.
if (this.lyricsHideControlPanel && this.vm.hSwiperIndex === 2) {
  this.bottomControlsHideProgress = 1
} else {
  this.bottomControlsHideProgress = 0
}
```

### Step 5.8 — Reacting to setting flips while PlayerPage is mounted

When the user opens the dialog (which is rendered on top of PlayerPage), toggles the switch, and dismisses the dialog, PlayerPage must re-snap the controls. Because `lyricsHideControlPanel` is `@StorageProp`, the VM-driven AppStorage write triggers a re-render naturally. Add a `@Watch` to re-snap when the setting changes:

```typescript
@StorageProp('lyricsHideControlPanel') @Watch('onHideControlPanelChanged')
lyricsHideControlPanel: boolean = false

onHideControlPanelChanged(): void {
  if (!this.lyricsHideControlPanel) {
    // Setting flipped off: snap controls back in.
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bottomControlsHideProgress = 0
    })
  } else if (this.vm.hSwiperIndex === 2) {
    // Setting flipped on while on lyrics page: slide controls out.
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.bottomControlsHideProgress = 1
    })
  }
}
```

### Step 5.9 — Live cross-entry-point sync

Both `LyricsInterfacePage` and `LyricsInterfaceDialogComponent` consume `LyricsInterfaceViewModel.getInstance()` (singleton from `LyricsInterfaceViewModel.ets` line 16–22). When the settings page writes through `updateHideControlPanel`, the singleton's `@Track hideControlPanel` flips and both switches re-render. The dialog already receives the singleton through `bottomSheetBuilder()` (PlayerPage line 2170–2176 hands `this.vm.lyricsInterfaceViewModel` which is `LyricsInterfaceViewModel.getInstance()` — see `PlayerPageViewModel.ets` line 142). No new code is required for cross-screen sync — it falls out of the singleton.

### Step 5.10 — Pro state hydration

If a future "activate Pro" path writes `AppStorage.setOrCreate('isPro', true)`, the existing `LyricsInterfacePage.aboutToAppear` already calls `viewModel.loadSettings()` (line 36–38). Extend `loadSettings()` to also refresh `isPro`:

```typescript
loadSettings(): void {
  this.model = LyricsInterfaceModel.loadFromStorage()
  this.isPro = AppStorage.get<boolean>('isPro') ?? false
  this.model.isPro = this.isPro
  this.syncFromModel()
}
```

`aboutToAppear` is a one-shot lifecycle callback (per the standing MVVM rule) — it is sufficient here only because the settings page does not need live Pro changes mid-view; if Pro flips while the user is staring at the row, the next nav out/in will catch it. To make the page truly live, the optional follow-up is to add `@StorageProp('isPro') @Watch` on `LyricsInterfacePage`, mirroring the `immersionMode` pattern in `PlayerPage`. Deferred — not in spec scope.

## 6. Files Touched (summary)

| File | Change |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | `persistProp('lyricsHideControlPanel', false)`, `persistProp('isPro', false)`, SettingsStore restore for both |
| `entry/src/main/ets/model/LyricsInterfaceModel.ets` | `loadFromStorage`/`saveToStorage` cover `hideControlPanel` |
| `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` | `updateHideControlPanel` uses `SettingsStore.save`; seed `isPro` from AppStorage; `syncFromModel` mirrors into AppStorage; `loadSettings` refreshes Pro |
| `entry/src/main/ets/pages/LyricsInterfacePage.ets` | HdsListItemCard: `enable: this.viewModel.isPro`; opacity fallback if needed |
| `entry/src/main/ets/components/LyricsInterfaceDialogComponent.ets` | Uncomment `this.SettingsGroup3()` call site |
| `entry/src/main/ets/pages/PlayerPage.ets` | `@StorageProp('lyricsHideControlPanel')` + `@Watch`; `bottomControlsHideProgress` state; gesture/onChange wiring; translate/opacity/height on bottom-control Column; capture `screenWidth` |
| `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets` | Add `@Track public screenWidth: number = 0` |

## 7. Scene Coverage Verification

| Scene | Verification |
|---|---|
| 1. Pro user toggles on in settings page | `updateHideControlPanel` writes through `SettingsStore.save`; `@StorageProp` flips; PlayerPage `@Watch` snaps controls. |
| 2. Pro user toggles off in settings page | Same path; `@Watch` snaps controls back; height un-collapses. |
| 3. Dialog toggle in player | Dialog is bound to same singleton VM; same persistence path; PlayerPage `@Watch` reacts live without dismissing the sheet. |
| 4. Hide-on display effect | Translation drives off-screen on lyrics page; collapsed height frees vertical space for `LyricsArea`. Source tag / translation button untouched (governed only by `immersionMode`). |
| 5. Hide-off display effect | `bottomControlsHideProgress` clamped to 0; controls always rendered at full height. |
| 6. Slide animation during swipe | `onGestureSwipe` computes per-frame progress; `onChange`/`onAnimationStart`/`onAnimationEnd` animate the tail snap. LTR-only direction (no RTL in repo). |
| 7. Vertical normal UI only | Repo has no landscape / full-screen lyrics surfaces — single-path implementation is automatically scoped. |
| 8. Non-Pro user | `enable: this.viewModel.isPro` on HdsListItemCard + `showProIcon` in dialog + Pro-gate guard in `updateHideControlPanel` reject writes; opacity fallback shows disabled state. |

## 8. Risks & Mitigations

- **HdsListItemCard `enable:` may not suppress SuffixSwitch interactions on every API level.** Mitigation: keep the Pro-gate check inside `updateHideControlPanel` so writes are rejected regardless of UI affordance; add `.opacity(0.5)` fallback for the row.
- **Swiper `currentOffset` sign conventions may vary across API versions.** Mitigation: clamp to [0, 1] in both gesture branches; both `index===1` (cover→lyrics) and `index===2` (lyrics→cover) are handled symmetrically.
- **Cold-start race: `EntryAbility` AppStorage seeding happens before VM construction.** Both `persistProp` and `SettingsStore.get`-based fallback land before any UI renders, mirroring the existing `lyricsBlur` pattern proven in spec13.
- **`hideControlPanel` legacy data persisted via the old `model.saveToStorage()` path:** old path did NOT write `lyricsHideControlPanel` to AppStorage, so previously-toggled values were lost on restart. After this change, future toggles round-trip correctly; we accept the data loss on the boundary version.
- **No global Pro source today.** Adding `PersistentStorage.persistProp('isPro', false)` establishes the key so future Pro activation flows have a single write surface. All existing `isPro` fields across models can later switch from `false` defaults to `AppStorage.get<boolean>('isPro') ?? false` in a separate cleanup pass — outside spec15 scope but enabled by this plan.

## 9. Out of Scope

- Pro activation flow itself (payment, license, restore) — not in spec15.
- Landscape / full-screen lyrics UI behavior — does not exist in this codebase.
- Migrating other `isPro` callsites to the new global key — explicitly deferred per Step 5.3.
- Cross-process / desktop-lyrics control-panel hiding — desktop lyrics has its own surface, untouched.
