# Implementation Plan — spec7: Allow Irregular Cover

Spec: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec7/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## Summary

Wire the "Allow Irregular Cover" (`irregularCoverAllowed`) setting end-to-end so the PlayerPage album cover renders either (a) at its original aspect ratio bounded by an 85%-width / aspect-ratio-1 envelope when the flag is on, or (b) as a centre-cropped square when the flag is off. Circle mode (`circlePlaybackCover`) continues to force-crop regardless.

The UI row, persistence, and AppStorage plumbing already exist. The gaps are:
1. The VM callback for `irregularCoverAllowedVM` writes to `SettingsStore` but not to `AppStorage`, so `@StorageProp` readers on PlayerPage do not see live flips without a page rebuild.
2. PlayerPage never reads `irregularCoverAllowed`; its non-circle branch always renders a fixed 85% square with `ImageFit.Cover`, which equates to the flag-off behaviour.
3. The PlayerPageViewModel does not compute intrinsic cover dimensions, so there is no scaled-envelope size to drive the flag-on branch.

## Owner boundary (MVVM)

| Concern | Owner | File |
|---|---|---|
| Persistence of `irregularCoverAllowed` | Model / SettingsStore | `entry/src/main/ets/model/SettingsStore.ets` |
| Cold-start restore into AppStorage | Ability (bootstrap) | `entry/src/main/ets/entryability/EntryAbility.ets` (already wired; no change) |
| Writer for the flag | UserInterfaceViewModel (via `SwitcherRowViewModel` callback) | `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` |
| Setting row UI + live binding | UserInterfacePage | `entry/src/main/ets/pages/UserInterfacePage.ets` |
| Cover layout state derivation | PlayerPageViewModel | `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets` |
| Cover rendering | PlayerPage | `entry/src/main/ets/pages/PlayerPage.ets` |

Binding / refresh matrix for cross-page live sync:

- **Writer**: `UserInterfaceViewModel.irregularCoverAllowedVM` callback → `AppStorage.setOrCreate('irregularCoverAllowed', val)` + `SettingsStore.save('irregularCoverAllowed', val)`.
- **Reader (same page)**: `UserInterfacePage` mirrors `@StorageLink('irregularCoverAllowed')` to re-render the `SuffixSwitch.isCheck`, matching the pattern already used for `circlePlaybackCover` / `hideStatusBar` / `immersionMode`.
- **Reader (PlayerPage)**: `@StorageProp('irregularCoverAllowed') @Watch('onCoverLayoutFlagChanged')` feeds `PlayerPageViewModel.setIrregularCoverAllowed(val)`; the VM recomputes cover envelope dimensions which are bound into `AlbumCoverArea`.
- **Refresh on song change**: existing `onControllerCoverChanged(songId, pixelMap)` already updates `coverPixelMap`; extend it to capture intrinsic `coverIntrinsicWidth` / `coverIntrinsicHeight` from `pixelMap.getImageInfo()` so the envelope recomputes automatically on the next render pass. No `aboutToAppear` polling is introduced.
- **Persistence**: `SettingsStore` (Preferences) is the disk owner; `PersistentStorage.persistProp('irregularCoverAllowed', true)` at `EntryAbility.onCreate` keeps AppStorage hydrated on cold start, and the explicit `AppStorage.setOrCreate('irregularCoverAllowed', ss.get(...))` at `EntryAbility.ets:130` guards against PersistentStorage races.

No persistence path is added to the Page. No mirror `@State` or fake default is introduced to PlayerPage for this flag — `@StorageProp` is the single live source for readers, and the VM holds the derived layout dimensions.

## Scenario coverage map

| Scene | Required behaviour | Current status | Work |
|---|---|---|---|
| 1. Default ON, original ratio | Flag defaults true; cover rendered at original ratio inside 85% envelope | Flag defaults true in Model / PersistentStorage / UI. Rendering always square. | Add ratio-preserving layout in `AlbumCoverArea`. |
| 2. Toggle OFF → square crop | Switch off, cover crops to square immediately | Switch toggles persist; PlayerPage unaffected. | Writer pushes to AppStorage; PlayerPage reads via `@StorageProp`; VM swaps envelope to square. |
| 3. Toggle ON → restore ratio | Switch on again, cover returns to original ratio | Same gap as Scene 1/2. | Same fix as Scene 1/2. |
| 4. Circle mode disables irregular switch + forces crop | Switch disabled, circle renderer crops | `enable: !this.circlePlaybackCover` on row; `CirclePlaybackCoverComponent` uses `ImageFit.Cover`. | No change needed; verify still holds after the PlayerPage branch refactor. |
| 5. Song change refresh | New cover follows current flag | `onControllerCoverChanged` already replaces `coverPixelMap`. | Extend it to capture intrinsic width/height so envelope recomputes with the new bitmap. |
| 6. Persistence across restart | Flag value preserved | `SettingsStore` + `PersistentStorage` + cold-start restore present. | Confirm only — no change. |

## Detailed changes

### 1. `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`

Inside the `irregularCoverAllowedVM` `SwitcherRowViewModel` callback (currently only calls `SettingsStore.save`), also publish to AppStorage so `@StorageProp` readers on PlayerPage react instantly:

```ts
this.irregularCoverAllowedVM = new SwitcherRowViewModel(this.model.irregularCoverAllowed, (val: boolean) => {
  AppStorage.setOrCreate<boolean>('irregularCoverAllowed', val)
  SettingsStore.getInstance().save('irregularCoverAllowed', val)
})
```

This mirrors the pattern already used for `circlePlaybackCover` (lines 154–160) and `hideStatusBar`.

### 2. `entry/src/main/ets/pages/UserInterfacePage.ets`

Add a `@StorageLink('irregularCoverAllowed')` field so the switch's `isCheck` reflects live AppStorage (identical to the `circlePlaybackCover` treatment at line 58). Bind the switch `isCheck` to that link and keep the existing toggle path:

```ts
@StorageLink('irregularCoverAllowed') irregularCoverAllowed: boolean = true

// in the irregular-cover ListItem:
suffixItem: new SuffixSwitch({
  isCheck: this.irregularCoverAllowed,
  onChange: (val: boolean) => {
    if (this.irregularCoverAllowed !== val) {
      this.vm.irregularCoverAllowedVM.toggle()
    }
  }
}),
enable: !this.circlePlaybackCover && this.vm.irregularCoverAllowedVM.isEnabled,
```

Rationale: the VM's in-memory `isOn` and AppStorage can drift when the writer path is split; `@StorageLink` gives the switch a single live source, matching the reviewed Circle-cover wiring.

### 3. `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets`

Add state + a derivation function; no new persistence:

```ts
@Track public coverIntrinsicWidth: number = 0
@Track public coverIntrinsicHeight: number = 0
@Track public irregularCoverAllowed: boolean = true

setIrregularCoverAllowed(val: boolean): void {
  if (this.irregularCoverAllowed !== val) {
    this.irregularCoverAllowed = val
  }
}

// Called whenever coverPixelMap is replaced.
private async captureCoverIntrinsicSize(pm: image.PixelMap | undefined): Promise<void> {
  if (!pm) {
    this.coverIntrinsicWidth = 0
    this.coverIntrinsicHeight = 0
    return
  }
  try {
    const info = await pm.getImageInfo()
    this.coverIntrinsicWidth = info.size.width
    this.coverIntrinsicHeight = info.size.height
  } catch (e) {
    this.coverIntrinsicWidth = 0
    this.coverIntrinsicHeight = 0
  }
}
```

Invoke `captureCoverIntrinsicSize(pm)` at the top of `onControllerCoverChanged` (PlayerPageViewModel.ets around line 1138) so every song change updates both `coverPixelMap` and its intrinsic size. This keeps Scene 5 live without `aboutToAppear` polling.

Expose a builder helper for the ratio-preserving envelope dimensions (width / height factors of the 85% × aspect-ratio-1 bounding square) so the Page does not do math:

```ts
// When flag on and intrinsic size known, returns the sub-rectangle of the
// 85%-width square that the image should occupy. Returns undefined when the
// fallback (square crop) should apply.
public getIrregularCoverEnvelope(): { widthPercent: string, heightPercent: string } | undefined {
  if (!this.irregularCoverAllowed) return undefined
  const w = this.coverIntrinsicWidth
  const h = this.coverIntrinsicHeight
  if (w <= 0 || h <= 0) return undefined
  if (w === h) return { widthPercent: '100%', heightPercent: '100%' }
  if (w > h) return { widthPercent: '100%', heightPercent: `${(h / w) * 100}%` }
  return { widthPercent: `${(w / h) * 100}%`, heightPercent: '100%' }
}
```

### 4. `entry/src/main/ets/pages/PlayerPage.ets`

Add a live-reactive reader and pipe it to the VM:

```ts
@StorageProp('irregularCoverAllowed')
@Watch('onIrregularCoverAllowedChanged')
irregularCoverAllowed: boolean = true

onIrregularCoverAllowedChanged(): void {
  this.vm.setIrregularCoverAllowed(this.irregularCoverAllowed)
}

aboutToAppear(): void {
  // ... existing body ...
  this.vm.setIrregularCoverAllowed(this.irregularCoverAllowed)
}
```

Refactor `AlbumCoverArea` (current rectangular branch at `PlayerPage.ets:1044`) to host the cover inside a fixed 85%-width / aspect-ratio-1 `Stack` envelope that is always reserved, and render either the original-ratio `Image` or the cropped `Image` inside:

```ts
} else {
  Stack() {
    if (this.vm.coverPixelMap) {
      const env = this.vm.getIrregularCoverEnvelope()
      if (env) {
        Image(this.vm.coverPixelMap)
          .width(env.widthPercent)
          .height(env.heightPercent)
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .clip(true)
          .shadow({ radius: 30, color: '#0d000000', offsetX: 0, offsetY: 6 })
          .onClick(() => { this.hSwiperController.showNext() })
          .gesture(
            LongPressGesture().onAction(() => {
              this.vm.showLargeImageOverlay()
            })
          )
      } else {
        Image(this.vm.coverPixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .clip(true)
          .shadow({ radius: 30, color: '#0d000000', offsetX: 0, offsetY: 6 })
          .onClick(() => { this.hSwiperController.showNext() })
          .gesture(
            LongPressGesture().onAction(() => {
              this.vm.showLargeImageOverlay()
            })
          )
      }
    } else {
      Image($r('app.media.ic_song_cover_v5'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .clip(true)
    }
  }
  .width('85%')
  .aspectRatio(1)
  .alignContent(Alignment.Center)
}
```

Rationale:
- The outer `Stack` keeps layout footprint stable across flag flips (same 85% square the circle branch already reserves), so Scenes 2/3 have no jitter.
- `ImageFit.Contain` on the inner `Image` combined with the percent-based envelope guarantees the original aspect is preserved; the dominant dimension fills the square and the other is proportionally smaller.
- `ImageFit.Cover` on the square branch matches prior behaviour for Scenes 2 and 4 (when circle is on, this branch is never executed — circle component always crops).
- When `coverIntrinsicWidth/Height` are still 0 (e.g., before `getImageInfo` resolves), `getIrregularCoverEnvelope()` returns undefined and the cropped branch renders; once intrinsic size lands the VM @Track bump triggers a re-render.

### 5. `entry/src/main/ets/entryability/EntryAbility.ets`

No change. `PersistentStorage.persistProp('irregularCoverAllowed', true)` (line 88) and the explicit `AppStorage.setOrCreate('irregularCoverAllowed', ss.get('irregularCoverAllowed', true))` (line 130) already cover Scene 6.

### 6. `entry/src/main/ets/model/UserInterfaceModel.ets`

No change. `irregularCoverAllowed` already defaults to `true`.

## Non-goals / explicitly out of scope

- No change to `CirclePlaybackCoverComponent`; Scene 4 continues to use `ImageFit.Cover` unchanged.
- No cross-fade / animated re-layout on flag flip; spec does not require it.
- No change to `largeImageOverlay`; the zoomed overlay already uses `ImageFit.Contain` and is therefore correct for both flag states.
- No refactor of song-change signal path; reuse `onControllerCoverChanged`.

## Verification

Build with `hvigor assembleHap` (or DevEco's equivalent) after changes and exercise:
1. Fresh install → switch is on, cover on PlayerPage shows original ratio for a non-square asset.
2. Toggle off in UserInterfacePage → PlayerPage cover immediately becomes square-cropped (no re-entry required).
3. Toggle back on → original ratio returns.
4. Enable Circle mode → Allow Irregular switch becomes disabled; cover is a rotating circle.
5. Skip to next/previous track → new cover respects the current flag state.
6. Kill and relaunch the app → flag state persists in both the settings row and the PlayerPage rendering.

Tests:
- No unit tests are added; the changes are view-layer layout and thin wiring, and the project has no ArkUI snapshot harness for the PlayerPage.
