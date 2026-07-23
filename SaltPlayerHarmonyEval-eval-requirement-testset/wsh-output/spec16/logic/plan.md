# Spec16 — 立体歌词效果 (3D Lyrics Effect) Implementation Plan

## 1. Overview

Implement the **"立体歌词效果" (3D Lyrics Effect)** toggle in the Laboratory (实验室) page. When enabled, the lyrics list inside `PlayerPage` renders with a Y-axis rotation + horizontal translation compensation, producing a perspective/stereo effect with vertical fading-edge masks at the top/bottom of the list. When disabled (default), the lyrics list renders flat. The setting is Pro-gated, persists across cold start, and propagates live to the player without page reload.

The plan covers **all seven scenes** in `spec-file` plan.md:

| Scene | Behavior |
|---|---|
| 1 | Pro user opens the toggle in Laboratory → state flips to on, `textAlignCenter` is force-disabled (mutual exclusion), value persisted. |
| 2 | Pro user closes the toggle → state flips to off, value persisted. |
| 3 | Toggle on + lyrics non-empty → PlayerPage lyrics List renders with Y-rotation + X-translation + top/bottom gradient masks. |
| 4 | Toggle off + lyrics non-empty → PlayerPage lyrics List renders without 3D transform (existing flat path). |
| 5 | Toggle on + song switch (prev/next/queue/auto) → 3D effect persists across the song-change animation. |
| 6 | Toggle on + empty lyrics → empty-lyrics placeholder renders normally; 3D transform NOT applied to the placeholder. |
| 7 | Non-Pro user → switch row is rendered disabled (greyed) with the crown icon; taps are ignored. |

## 2. MVVM Owner Boundary

| Layer | Owner | Responsibility |
|---|---|---|
| **Page (settings)** | `LaboratoryPage` | Renders the Pro-gated `lyricsEffect3DVM` switcher; delegates `onChange` to ViewModel. |
| **Page (player)** | `PlayerPage` | Reads `lyricsUIEffect3D` via `@StorageProp`; applies `rotate({ y: ... })` + `translate({ x: ... })` + tunes `fadingEdge` on the lyrics List; never writes. |
| **ViewModel (settings)** | `LaboratoryViewModel` | Owns `lyricsEffect3DVM` toggle action `onLyricsEffect3DChanged`; persists via `SettingsStore`; enforces mutual exclusion with `lyricsTextAlignCenter`. |
| **ViewModel (lyrics-interface)** | `LyricsInterfaceViewModel` | Receives the cross-row flip of `textAlignCenter` (via shared `AppStorage` key + singleton refresh on `loadSettings`). Does not own `lyricsUIEffect3D`. |
| **Model (settings)** | `LaboratoryModel` | Pure data field `lyricsUIEffect3D`; no persistence inside. |
| **DataSource** | `SettingsStore` | Single persistence path (AppStorage + Preferences flushSync) for `lyricsUIEffect3D`. |
| **EntryAbility** | `EntryAbility` | Registers `PersistentStorage.persistProp('lyricsUIEffect3D', false)`, then hydrates AppStorage from `SettingsStore.get` on cold start before any page mounts. |

**Key rules (do not violate):**

- Persistence path is **ViewModel → SettingsStore.save → AppStorage + Preferences**. `LaboratoryPage` must not write Preferences directly.
- `PlayerPage` subscribes via `@StorageProp` only — no mirror state in `PlayerPageViewModel`.
- Mutual exclusion (Scene 1 — disabling `textAlignCenter` when `lyricsUIEffect3D` becomes true) lives in the **writer** (`LaboratoryViewModel`), not in the consumer (`PlayerPage`). The writer flips both keys through `SettingsStore.save` so AppStorage subscribers (`LyricsInterfacePage` `@ObjectLink`-ed VM and `PlayerPage`'s `@StorageProp('lyricsTextAlignCenter')`) react in the same tick.
- The settings dialog and settings page that own `lyricsTextAlignCenter` must NOT each carry an independent mirror of the same value. `LyricsInterfaceViewModel.loadSettings()` already re-reads from `LyricsInterfaceModel.loadFromStorage()`, which reads `AppStorage.get('lyricsTextAlignCenter')`; the cross-row flip therefore propagates correctly **only if the writer also calls `AppStorage.setOrCreate`** (this is the SettingsStore.save contract).
- `aboutToAppear` is one-shot; it is fine for hydrating once on page entry (as today) but it is **NOT** the live-sync path. The live path is `@StorageProp` + `@Observed`/`@Track`.
- No fake defaults: the persisted floor is `false`, identical to Android `Config.LYRICS_UI_EFFECT_3D` default `false`.

## 3. Data Flow

```
User toggles 3D switch in LaboratoryPage
        |
        v
SwitcherWithIconAndSubRowViewModel.toggle()
        |  (guarded by isEnabled = isPro)
        v
LaboratoryViewModel.onLyricsEffect3DChanged(isOn)
        |
        +---- this.model.lyricsUIEffect3D = isOn
        +---- SettingsStore.getInstance().save('lyricsUIEffect3D', isOn)
        |          |
        |          +-- AppStorage.setOrCreate('lyricsUIEffect3D', isOn)         (live)
        |          +-- preferences.putSync + flushSync                          (cold-start durable)
        |
        +---- if (isOn) {
        |        // Mutual exclusion (Scene 1): cancel center alignment
        |        SettingsStore.getInstance().save('lyricsTextAlignCenter', false)
        |          +-- AppStorage.setOrCreate('lyricsTextAlignCenter', false)
        |          +-- preferences.putSync + flushSync
        |        // also flip the singleton VM so LyricsInterfaceDialog/Page
        |        // re-render immediately on return
        |        LyricsInterfaceViewModel.getInstance().refreshTextAlignFromStorage()
        |     }
        v
PlayerPage @StorageProp('lyricsUIEffect3D') lyricsUIEffect3D: boolean
                       @StorageProp('lyricsTextAlignCenter') lyricsTextAlignCenter: boolean
        |
        v
   Render branches:
     - LyricsArea > List: when lyricsUIEffect3D:
         .rotate({ x: 0, y: 1, z: 0, angle: -ROTATION_DEG, centerY: '50%', centerX: '0%' })
         .translate({ x: TRANSLATION_VP })
         .fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(MASK_VP) })
       when !lyricsUIEffect3D:
         no rotate, no translate, existing fadingEdge(80vp) unchanged
     - Empty-lyrics Column (`vm.lyricsLines.length === 0` branch): NEVER apply the 3D transform (Scene 6). The Column stays flat regardless of `lyricsUIEffect3D`.
```

## 4. Ground-Truth Anchors

Already in repo (do not duplicate):

- `entry/src/main/ets/model/LaboratoryModel.ets`: field `lyricsUIEffect3D: boolean = false` (line 8) + constructor param (line 16). Pure data — no persistence inside, which matches the convention.
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets`:
  - `@Track public lyricsEffect3DVM: SwitcherWithIconAndSubRowViewModel` (line 28).
  - Child VM constructed via `SwitcherWithIconAndSubRowModel(this.model.lyricsUIEffect3D, this.isPro, ic_crown, '立体歌词效果', '')` (line 68–79). Crown icon + Pro-gated `isEnabled` is already wired.
  - `onLyricsEffect3DChanged` (line 120) currently writes to model only with a `TODO: Persist with data preferences` comment — this is the surface we must fix.
  - `this.isPro = this.model.isPro` (line 52) — currently always `false` because `LaboratoryModel.isPro` defaults to `false`. Must be replaced with the same `AppStorage.get<boolean>('isPro')` pattern that `LyricsInterfaceViewModel.constructor` already uses (line 65) so a future Pro activation lights this row up live.
- `entry/src/main/ets/pages/LaboratoryPage.ets`: switcher row is already wired via `ItemSwitcherWithIconAndSubRowComponent({ vm: this.viewModel.lyricsEffect3DVM })` (line 57). UI complete; no changes needed in this file beyond an `aboutToAppear` Pro-refresh on entry.
- `entry/src/main/ets/model/SettingsStore.ets`: singleton with `save(key, value)` that writes `AppStorage.setOrCreate` + `putSync` + `flushSync`. Direct match for our persistence path.
- `entry/src/main/ets/entryability/EntryAbility.ets`:
  - Existing block at line 80–101 declares `PersistentStorage.persistProp` for every persisted key (incl. `lyricsHideControlPanel` line 81, `lyricsTextSize`, `lyricsBlur`, ...).
  - Existing block at line 132–168 restores each key from `SettingsStore.get` into AppStorage so the value is hydrated before any page mounts.
  - Spec9 pattern (`autoOpenPlaybackScreen`) on lines 100–101 and 147–149 is the closest reference for a laboratory-toggle persistence row.
- `entry/src/main/ets/pages/PlayerPage.ets`:
  - Lyrics rendering anchor: `LyricsArea` builder line 1372–1624. The scrollable List lives at lines 1377–1479; the empty-lyrics placeholder Column is at lines 1557–1568; the static (non-timed) `Scroll` is at lines 1486–1555.
  - Existing `@StorageProp` lyrics keys (lines 77–86): `lyricsTextSize`, `lyricsTextAlignCenter`, `lyricsFontWeight`, `lyricsKaraokeCompatStrategy`, `lyricsBlur`. We add `lyricsUIEffect3D` in the same block.
  - Existing `.fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })` already lives on the List (line 1437) and on the static Scroll (line 1512). Scene 3 only requires that the mask still works under the 3D rotation — the same `fadingEdge` call satisfies this and renders on the rotated layer.
  - `LengthMetrics` is already imported (line 29) from `@ohos.arkui.node`.
- `entry/src/main/ets/components/LyricsLineComponent.ets`: per-line component already supports `textAlignCenter` and karaoke / blur props. **No changes** — the 3D transform is applied to the **List container**, not per-line, which mirrors Android `LyricsContainer(threeEffect = effect3D, ...)` (one transform on the whole list).
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`:
  - Singleton via `getInstance()` (line 16–22).
  - `loadSettings()` (line 73) already re-reads `LyricsInterfaceModel.loadFromStorage()` which pulls `lyricsTextAlignCenter` from AppStorage. Re-entering the dialog or settings page after the Laboratory flip is therefore correct. The Laboratory-time live flip (while the dialog is dismissed) is handled by `AppStorage.setOrCreate('lyricsTextAlignCenter', false)` since the consumer reads the AppStorage key.
- `entry/src/main/ets/model/LyricsInterfaceModel.ets`:
  - `loadFromStorage()` already reads `AppStorage.get('lyricsTextAlignCenter')` (line 46). No change.
- Android reference (read-only):
  - `LaboratoryScreen.kt` lines 52–60: mutual exclusion identical to what we wire — toggling 3D on also calls `lyricsViewTextAlignCenter.postValue(false)` + `mmkv.encode(LYRICS_VIEW_TEXT_ALIGN_CENTER, false)`. We mirror this exactly via two `SettingsStore.save` calls in one method.
  - `LyricsScreen.kt` line 89: `effect3D = playerViewModel.lyricsUIEffect3D` passed to `LyricsContainer(threeEffect = ...)`. PlayerPage's render branch mirrors this with a top-level transform on the lyrics List.

## 5. Implementation Steps

### Step 5.1 — Persistence foundation

**File:** `entry/src/main/ets/entryability/EntryAbility.ets`

(a) In the persistence-prop registration block, after the existing `autoOpenPlaybackScreen` line (line 101), add:

```typescript
// Spec16: 3D lyrics effect (Pro-gated, 实验室 toggle)
PersistentStorage.persistProp('lyricsUIEffect3D', false)
```

(b) In the AppStorage restore block, after the existing `autoOpenPlaybackScreen` restore (line 148–149), add:

```typescript
// Spec16: 3D lyrics effect flag (实验室)
AppStorage.setOrCreate('lyricsUIEffect3D',
  ss.get('lyricsUIEffect3D', false) as boolean)
```

This guarantees `lyricsUIEffect3D` is hydrated into AppStorage before `PlayerPage` mounts.

### Step 5.2 — ViewModel: persistence + Pro hydration + mutual exclusion

**File:** `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets`

(a) In the constructor, after the existing `persistedAutoOpen` seed (line 47–51), add a 3D-effect seed from AppStorage so the first frame reflects the cold-start value:

```typescript
const persisted3D = AppStorage.get<boolean>('lyricsUIEffect3D')
if (persisted3D !== undefined) {
  this.model.lyricsUIEffect3D = persisted3D
}
```

(b) Replace the line `this.isPro = this.model.isPro` (line 52) with a global-AppStorage read so any future Pro activation reaches this VM (mirrors `LyricsInterfaceViewModel.constructor` line 65):

```typescript
this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
this.model.isPro = this.isPro
```

(c) Add a `loadSettings()` body that re-reads both AppStorage keys, so `LaboratoryPage.aboutToAppear` (added in Step 5.3) can refresh the Pro state and the live 3D state on re-entry (replaces the existing empty TODO body at line 159):

```typescript
loadSettings(): void {
  this.isPro = (AppStorage.get<boolean>('isPro') ?? false)
  this.model.isPro = this.isPro
  const persisted3D = AppStorage.get<boolean>('lyricsUIEffect3D')
  if (persisted3D !== undefined) {
    this.model.lyricsUIEffect3D = persisted3D
    this.lyricsEffect3DVM.isOn = persisted3D
  }
  // Pro state may have changed → refresh isEnabled on the child VM
  this.lyricsEffect3DVM.isEnabled = this.isPro
  this.saltUiMaterialVM.isEnabled = this.isPro
  this.liquidGlassVM.isEnabled = this.isPro
}
```

(d) Replace `onLyricsEffect3DChanged` (line 120–126) with the spec-compliant implementation:

```typescript
private onLyricsEffect3DChanged(isOn: boolean): void {
  this.model.lyricsUIEffect3D = isOn
  // Spec16: persist (AppStorage + Preferences flushSync).
  // PlayerPage subscribes via @StorageProp; the write here is the live broadcast.
  SettingsStore.getInstance().save('lyricsUIEffect3D', isOn)
  // Scene 1: mutual exclusion with lyricsTextAlignCenter.
  // When 3D is turned ON, force center alignment OFF. When turned OFF,
  // leave center alignment alone (user's prior choice is preserved).
  if (isOn) {
    SettingsStore.getInstance().save('lyricsTextAlignCenter', false)
    // Keep the LyricsInterfaceViewModel singleton in sync so the next
    // settings-page / dialog entry reflects the flip without staleness.
    // This is a non-binding sync write — the AppStorage key set above is
    // already the authoritative source for PlayerPage's @StorageProp.
    try {
      LyricsInterfaceViewModel.getInstance().refreshTextAlignFromStorage()
    } catch (_e) {
      // VM not constructed yet — no-op; loadSettings() will pick it up
      // on the next entry.
    }
  }
}
```

Add the import at the top of the file:

```typescript
import LyricsInterfaceViewModel from './LyricsInterfaceViewModel'
```

### Step 5.3 — Page: refresh Pro state and live value on entry

**File:** `entry/src/main/ets/pages/LaboratoryPage.ets`

(a) Add an `aboutToAppear` that calls `viewModel.loadSettings()`. This mirrors `LyricsInterfacePage.aboutToAppear` (line 37–39) and `LyricsInterfaceViewModel.loadSettings`:

```typescript
aboutToAppear(): void {
  this.viewModel.loadSettings()
}
```

This is **NOT** the live-sync path (`@StorageProp` handles that for PlayerPage). It is only the one-shot reconciliation for the Laboratory page itself when the user re-enters the page after Pro activation or after manual storage edits.

### Step 5.4 — LyricsInterfaceViewModel: cross-row sync helper

**File:** `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`

Add a public method to re-pull `lyricsTextAlignCenter` from AppStorage after an external writer (LaboratoryViewModel) flipped it. This avoids tripping `SettingsStore.save` a second time (already saved by LaboratoryViewModel) and keeps the singleton VM consistent for the next dialog/page render.

```typescript
// Spec16: external sync hook. Called by LaboratoryViewModel after the
// mutual-exclusion flip writes lyricsTextAlignCenter through AppStorage.
// We update the @Track field directly so subscribers re-render, but skip
// SettingsStore.save (the caller already persisted).
refreshTextAlignFromStorage(): void {
  const v = (AppStorage.get<boolean>('lyricsTextAlignCenter') ?? false)
  this.textAlignCenter = v
  this.model.textAlignCenter = v
}
```

Place this method near `updateTextAlignCenter` (line 139).

### Step 5.5 — PlayerPage: @StorageProp + render branch

**File:** `entry/src/main/ets/pages/PlayerPage.ets`

(a) In the lyrics-interface `@StorageProp` block (lines 77–86), after the existing `lyricsBlur` line, add:

```typescript
// Spec16: 3D lyrics effect toggle (实验室). Live-reactive — toggling
// the switch in Laboratory rebuilds LyricsArea's transform on the next frame.
@StorageProp('lyricsUIEffect3D') lyricsUIEffect3D: boolean = false
```

(b) In the `LyricsArea` builder, wrap the scrollable List branch's transform chain so that **only when `lyricsUIEffect3D === true`** the rotate + translate are applied. The simplest minimally-invasive approach is to append three new modifier calls to the **List** at line 1431–1479, guarded with conditional values:

After the existing line 1437 `.fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })`, append (still on the List):

```typescript
.rotate(this.lyricsUIEffect3D
  ? { x: 0, y: 1, z: 0, angle: -PlayerPage.LYRICS_3D_ROTATION_DEG,
      centerX: '0%', centerY: '50%', perspective: PlayerPage.LYRICS_3D_PERSPECTIVE }
  : undefined)
.translate(this.lyricsUIEffect3D
  ? { x: PlayerPage.LYRICS_3D_TRANSLATE_X_VP }
  : undefined)
```

The static (non-timed) `Scroll` branch (line 1486–1555) mirrors the same rotate/translate using identical constants — when the doc is static-text-only, the Scroll IS the lyrics container, so it must rotate too for Scene 3 parity.

(c) Add static constants at the top of the `PlayerPage` struct (alongside existing private fields), keeping all magic numbers in one place:

```typescript
// Spec16: 3D lyrics effect geometry. Mirrors Android LyricsContainer's
// `threeEffect = true` path (one transform on the whole list container,
// fading-edge mask comes from the existing .fadingEdge call).
// Tunable; the values below match the visual feel of the Android source.
private static readonly LYRICS_3D_ROTATION_DEG: number = 22
private static readonly LYRICS_3D_TRANSLATE_X_VP: string | number = -28
private static readonly LYRICS_3D_PERSPECTIVE: number = 1.6
```

Numbers are tuned for "slight rotation, list still readable" — they are **not** the spec's contract. The spec's contract is "lyrics整体沿Y轴旋转一定角度,并进行相应的水平位移补偿,呈现出立体透视效果". The compensation (`translate.x`) cancels the visual drift of the rotated list off the left edge of the viewport. The plan deliberately externalizes these to constants so a follow-up tuning pass can adjust them without touching the wiring.

(d) Scene 6 — empty-lyrics Column at lines 1557–1568: **do NOT** add the rotate/translate to this Column. The empty placeholder must stay flat. Verify by code-reading that the new modifier chain is appended to the `List` and `Scroll` branches only.

(e) Scene 5 — song-switch animation: the existing song-change re-renders `LyricsArea` via `vm.lyricsLines` swap and `vm.lyricsVersionTag`. Because `lyricsUIEffect3D` is read via `@StorageProp` and not gated on the song id, the rotate/translate applies to every new song without extra wiring.

### Step 5.6 — Verify there is no stale "TODO Persist" path

After Step 5.2 lands, grep the repo for `TODO: Persist with data preferences` in `LaboratoryViewModel.ets` and confirm only the **Get Album Art** / **Salt UI Material** / **Liquid Glass** comments remain (those are out of scope for spec16). The 3D one must be gone.

## 6. Acceptance per Scene

| Scene | Verification |
|---|---|
| 1 | Toggle on in Laboratory → AppStorage `lyricsUIEffect3D=true`, AppStorage `lyricsTextAlignCenter=false`, Preferences both flushed. Re-enter LyricsInterfacePage → center-align switch shows OFF (via `loadSettings → loadFromStorage → AppStorage.get`). |
| 2 | Toggle off → AppStorage `lyricsUIEffect3D=false`, Preferences flushed. `lyricsTextAlignCenter` unchanged. |
| 3 | Toggle on + non-empty lyrics → PlayerPage lyrics List has `.rotate({y:1, angle: -22})` and `.translate({x: -28vp})`; `.fadingEdge(true, 80vp)` already present → top/bottom gradient masks visible. |
| 4 | Toggle off → no `.rotate` / no `.translate` (both `undefined`) — list renders flat (current baseline). |
| 5 | Switch song while 3D on → new `vm.lyricsLines` is rendered with the same List container; transform is on the container, so it survives the swap. |
| 6 | Toggle on + no lyrics → empty-lyrics Column renders flat (no transform on that Column). |
| 7 | Non-Pro user → `lyricsEffect3DVM.isEnabled = isPro = false` → `ItemSwitcherWithIconAndSubRowComponent` row has `.enabled(false).opacity(0.5)` (lines 46–47 of the component) → tap routes through `RippleWrapper.onAction → vm.toggle() → guarded by `if (this.isEnabled)` (line 39 of `SwitcherWithIconAndSubRowViewModel`). Crown icon rendered via `iconRes` already wired in `LaboratoryViewModel.initChildViewModels` line 72. |

## 7. Files Touched

| File | Purpose |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | persistProp + cold-start restore for `lyricsUIEffect3D` |
| `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets` | Pro hydration, persistence, mutual-exclusion writer, `loadSettings()` body |
| `entry/src/main/ets/pages/LaboratoryPage.ets` | `aboutToAppear → viewModel.loadSettings()` |
| `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` | `refreshTextAlignFromStorage()` helper |
| `entry/src/main/ets/pages/PlayerPage.ets` | `@StorageProp('lyricsUIEffect3D')`, three new constants, rotate/translate on the scrollable List and the static Scroll (NOT on the empty placeholder) |

Files explicitly **not** modified:

- `entry/src/main/ets/model/LaboratoryModel.ets` — already has the field; no persistence inside the model is the convention here.
- `entry/src/main/ets/model/LyricsInterfaceModel.ets` — `lyricsTextAlignCenter` load/save already present and correct.
- `entry/src/main/ets/components/LyricsLineComponent.ets` — 3D transform is on the list container, not per-line.
- `entry/src/main/ets/components/LyricsComponent.ets` — unused in PlayerPage (PlayerPage inlines its own `LyricsArea`); leaving the component untouched keeps blast radius bounded.

## 8. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `rotate`/`translate` modifier with `undefined` may or may not be a no-op depending on ArkTS version. | Default values `LYRICS_3D_ROTATION_DEG=22`, `LYRICS_3D_TRANSLATE_X_VP=-28` are stable. If `undefined` is rejected by the compiler, fall back to two separate `if` branches that conditionally append the modifiers (each branch returns the List with or without the chained calls). Both branches share the same List ID/key, so ArkUI diff is a property update, not a tree rebuild — the existing user-scroll/edge-flag state is preserved across the toggle. |
| `LyricsInterfaceViewModel.getInstance()` constructs the VM the first time it is called, which may happen on the Laboratory toggle before any settings page mounts. Constructing a VM just to refresh a flag has a small cost. | Acceptable — the singleton is cheap (a few Track fields), constructed lazily, and reused thereafter by all settings entry points. The `try/catch` around the call protects against any constructor-time exception (e.g., a hypothetical AppStorage-not-ready edge case) and silently falls through to the `loadSettings` re-read on next entry. |
| Pro state may flip between page entries (future feature). | `LaboratoryPage.aboutToAppear → loadSettings()` re-reads `isPro` from AppStorage and re-sets `isEnabled` on the three Pro-gated child VMs. PlayerPage does not gate on Pro — the rendered 3D effect simply reflects the stored flag. |
| Empty-lyrics placeholder under 3D mode might be expected to also rotate. | Spec scene 6 explicitly says "立体效果不影响空歌词的展示" (the 3D effect does not affect the empty-lyrics display). Plan keeps the empty Column flat. |
| If a user has both 3D on and somehow flips `lyricsTextAlignCenter` to true via Preferences manipulation, the next render of PlayerPage would show centered text on a rotated list — visually fine but spec-violating. | Out of scope. The writer enforces mutual exclusion; there is no in-app path to violate it. |

## 9. Out of Scope

- Tuning the exact `ROTATION_DEG` / `TRANSLATE_X_VP` / `PERSPECTIVE` values. The plan picks reasonable defaults; visual polish is a separate task.
- RTL layout direction. The repo has no RTL support today (per spec15 ground truth), so the translate direction is hardcoded LTR (`-28vp` pushes the rotated layer back into the viewport).
- Pro activation flow. The plan reads `AppStorage.get<boolean>('isPro')` which is already registered in `EntryAbility` line 84.
- Mini-lyrics / desktop-lyrics 3D effect — spec scope is the player-page lyrics list only.
- Karaoke wipe interaction with 3D rotation. Karaoke clipping is per-line and lives inside `LyricsLineComponent`; rotating the parent List does not change the wipe correctness. No interaction needed.
