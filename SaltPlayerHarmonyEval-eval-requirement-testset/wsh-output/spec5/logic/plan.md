# Logic Plan — spec5 (圆形播放封面)

Target: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec5/plan.md`
Project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

## 0. Ground Truth (what already exists)

- `AppStorage` key `circlePlaybackCover` (default `false`) is persisted in
  `entry/src/main/ets/entryability/EntryAbility.ets` (line 87) and restored from
  `SettingsStore` on startup (line 129). `irregularCoverAllowed` (default `true`)
  is the same (lines 88, 130).
- `UserInterfaceViewModel.circlePlaybackCoverVM` (viewmodel/UserInterfaceViewModel.ets
  lines 154-157) already wires the switch action:
  - `onCircleCoverChanged(val)` flips `this.irregularCoverAllowedVM.isEnabled = !val`.
  - `SettingsStore.save('circlePlaybackCover', val)`.
  - But the method does NOT write `AppStorage.setOrCreate('circlePlaybackCover', …)`,
    so PlayerPage cannot observe live flips via `@StorageProp` today.
- `UserInterfacePage.ets` renders the `circle_playback_cover` `HdsListItemCard`
  (lines 317-330) with a hard-coded `SuffixSwitch({ isCheck: false,
  onChange: (_val) => {} })` — live-dead, does not reflect state, does not write.
  The "允许不规则封面" row is NOT rendered anywhere in the page body.
- `PlayerPage.AlbumCoverArea()` (pages/PlayerPage.ets lines 992-1071) always
  renders the cover as a rectangle: `Image(this.vm.coverPixelMap ?? $r('…ic_song_cover_v5'))`
  with `.borderRadius(8)`, `.shadow(...)`, long-press → large overlay, click → swipe to lyrics.
  The same `AlbumCoverArea()` is used whether `miniLyricsInPlayer` is on or off;
  the mini-lyrics row is wrapped in a sibling `Column()` beneath it.
- `CurrentSongCoverController` publishes the current song `PixelMap` to subscribers
  (listeners in `PlayerPageViewModel` / `FlowingLightViewModel`). When a song has
  no embedded cover, the controller publishes `pm=undefined`; `vm.coverPixelMap`
  becomes `undefined` and the current code falls back to the placeholder
  `$r('app.media.ic_song_cover_v5')`.
- `FlowingLightComponent.ets` shows the canonical ArkUI pattern for an infinite
  linear rotation driven by `UIContext.createAnimator` (lines 49-91):
  `duration`, `easing: 'linear'`, `iterations: -1`, `begin: 0`, `end: 360`;
  state kept in a VM `@Track rotation*: number`, paired with `.rotate({ angle: … })`.
  `syncRotationState()` pauses / plays based on `dynamicFlowingLight && isPlaying`.
- `@StorageProp('isPlaying')` is already bound on `PlayerPage` (line 69) and on
  `FlowingLightComponent` (line 30), with play/pause published by
  `AudioPlayerService.ets` (multiple `AppStorage.setOrCreate('isPlaying', …)`).
- `@StorageLink('currentSongId')` + `@Watch('onSongChanged')` exists on `PlayerPage`
  (line 70) — every skip / queue jump / auto-advance updates this key, so it is
  the correct reset trigger for scenes 4 / 5.
- `SystemBarModel.getInstance().reconcileStatusBarVisibility()` is unrelated to
  this spec and is left untouched.
- No HarmonyOS car-player page exists. `MainPage.ets` only routes `'CarKitPage'`
  (settings page) and `'TabletModePage'`; there is no `PlayerCarUI` / `CarPlayerPage`.
  Scene 9 therefore has no live player surface in HarmonyOS today — the plan keeps
  the circle cover component reusable (via a `forceCircle` prop) so a future car
  player page can opt in.

## 1. MVVM owner boundaries

- **View — `UserInterfacePage.ets`**: UI only. Mirror the `playerKeepScreenOn`
  row pattern: add `@StorageLink('circlePlaybackCover')` on the struct and bind
  the `SuffixSwitch.isCheck` to it; delegate `onChange` to
  `vm.circlePlaybackCoverVM.toggle()` (which flows through the existing VM
  callback). No direct persistence, no direct AppStorage writes from the page.
- **View — `PlayerPage.ets`**: UI only. In `AlbumCoverArea()`, branch on
  `@StorageProp('circlePlaybackCover')`:
  - on → render the new `CirclePlaybackCoverComponent`;
  - off → keep the existing `Image(...)` rectangle branch.
  No persistence, no rotation state. Rotation lifecycle is owned by the new
  component.
- **Component — `CirclePlaybackCoverComponent.ets`** (new): owns the rotation
  animator and the reset-on-song-change animation. Inputs: `coverPixelMap`
  (PixelMap | undefined), `onLongPress` callback. Reads `isPlaying` and
  `currentSongId` from AppStorage via `@StorageProp`. Does NOT write to any
  settings or AppStorage. Component-local state is correct here because
  rotation angle is a transient view concern, not persisted state.
- **ViewModel — `UserInterfaceViewModel.ets`**: extend `circlePlaybackCoverVM`
  callback to also write `AppStorage.setOrCreate('circlePlaybackCover', val)` so
  the player page's `@StorageProp` sees the change immediately (matches the
  immersion-mode pattern established in spec4). No UI in the VM.
- **Model — `SettingsStore.ets`**: unchanged. It is already the persistence
  owner; only the VM calls it, never the page or the component.

Anti-patterns explicitly avoided:

- No mirror state for `circlePlaybackCover` in any VM. `AppStorage.circlePlaybackCover`
  is the single source of truth; all readers use `@StorageLink` / `@StorageProp`.
- `aboutToAppear` is not treated as live sync in `PlayerPage` or the new component:
  the `@StorageProp` bindings drive live updates; `aboutToAppear` is only used for
  initial wiring.
- Rotation state is not persisted (no PersistentStorage key). A circle that
  kept its angle across relaunch is out of scope and would cost Disk I/O per frame.
- No `setSpecificSystemBarEnabled` or other system-bar calls from the component /
  page — unrelated concern, owned by `SystemBarModel` from spec4.
- The placeholder switch (`isCheck: false`) in `UserInterfacePage.ets` is a fake
  default and is replaced with the real binding, not just re-wired from inside.

## 2. Change list

### 2.1 `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets`

Upgrade the `circlePlaybackCoverVM` callback (lines 154-157) so the setting is
also written to AppStorage for reactive readers:

```ts
this.circlePlaybackCoverVM = new SwitcherRowViewModel(this.model.circlePlaybackCover, (val: boolean) => {
  this.onCircleCoverChanged(val)
  AppStorage.setOrCreate<boolean>('circlePlaybackCover', val)
  SettingsStore.getInstance().save('circlePlaybackCover', val)
})
```

No other change in this file. `onCircleCoverChanged(isCircleCover)` already
handles scene 7 (`this.irregularCoverAllowedVM.isEnabled = !isCircleCover`).

### 2.2 `entry/src/main/ets/pages/UserInterfacePage.ets`

- Add to the struct body (next to the existing
  `@StorageLink('playerKeepScreenOn')` and `@StorageLink('immersionMode')`):

  ```ts
  @StorageLink('circlePlaybackCover') circlePlaybackCover: boolean = false
  ```

  `@StorageLink` (not `@StorageProp`) so the row both reflects external writes
  AND propagates local changes.
- Replace the `circle_playback_cover` `HdsListItemCard` block (lines 317-330)
  with a live-wired version mirroring the `playerKeepScreenOn` row (lines 279-296):

  ```ts
  ListItem() {
    HdsListItemCard({
      textItem: {
        primaryText: { text: $r('app.string.circle_playback_cover') },
      },
      suffixItem: new SuffixSwitch({
        isCheck: this.circlePlaybackCover,
        onChange: (val: boolean) => {
          if (this.circlePlaybackCover !== val) {
            this.vm.circlePlaybackCoverVM.toggle()
          }
        }
      }),
      cardPrefixMargin: 4,
      cardSuffixMargin: 4,
      cardBackgroundColor: Color.Transparent,
    })
  }
  ```

  `.toggle()` flips the VM `isOn`, fires the callback (writing AppStorage +
  SettingsStore + disabling irregular cover), so `@StorageLink` updates propagate
  back to `isCheck` on the next render.

### 2.3 `entry/src/main/ets/components/CirclePlaybackCoverComponent.ets` (new)

Sibling of `FlowingLightComponent.ets`. Keeps the animator lifecycle close to
the view it serves. Responsibilities:

- Render the cover PixelMap clipped to a circle, with shadow, centered in an
  aspect-ratio-1 box sized `85%` wide (same footprint as the current rectangle
  cover so the column layout does not jump when switching modes).
- Drive a linear, infinite 25-second rotation via `UIContext.createAnimator`
  (`iterations: -1`, `begin: 0`, `end: 360`, `easing: 'linear'`).
- Pause / play the animator based on `@StorageProp('isPlaying')`.
- On `@StorageProp('currentSongId')` change, run a 250 ms linear animation back
  to angle 0 (via `this.getUIContext().animateTo(...)`, not the infinite
  animator), then if `isPlaying` at the end of the reset, cancel + re-create +
  play the infinite animator starting from 0. If `!isPlaying`, leave the
  component at angle 0 without starting rotation (scene 5).
- Fire `onLongPress` on long-press of the cover (so the large-image overlay
  path from the existing rectangle branch stays reachable).
- If `coverPixelMap` is `undefined` (scene 6), render nothing — return an empty
  Column with `width('100%')` and matching aspect ratio to preserve layout,
  instead of showing the `ic_song_cover_v5` placeholder or an empty circle.

Sketch:

```ts
// CirclePlaybackCoverComponent.ets
import { AnimatorResult } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'

@Component
export struct CirclePlaybackCoverComponent {
  coverPixelMap: image.PixelMap | undefined = undefined
  onLongPress: () => void = () => {}
  // Allows a future car player page to force-on regardless of setting.
  forceCircle: boolean = false

  @StorageProp('isPlaying') @Watch('onPlayStateChanged') isPlayingProp: boolean = false
  @StorageProp('currentSongId') @Watch('onSongChanged') songId: string = ''

  @State private rotationDeg: number = 0
  private anim: AnimatorResult | null = null
  // Accumulated offset so that pause/resume continues from the last angle
  // instead of snapping back to 0 on the next iteration.
  private baseAngle: number = 0
  private isResetting: boolean = false

  aboutToAppear(): void {
    this.createAnimator()
    this.syncRotationState()
  }

  aboutToDisappear(): void {
    this.destroyAnimator()
  }

  private createAnimator(): void {
    this.anim = this.getUIContext().createAnimator({
      duration: 25_000,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: 360,
    })
    this.anim.onFrame = (v: number) => {
      if (!this.isResetting) {
        this.rotationDeg = (v + this.baseAngle) % 360
      }
    }
  }

  private destroyAnimator(): void {
    if (this.anim) {
      this.anim.onFrame = (_v: number) => {}
      this.anim.cancel()
      this.anim = null
    }
  }

  private syncRotationState(): void {
    if (this.isResetting) return
    if (this.isPlayingProp) {
      this.anim?.play()
    } else {
      // Freeze at current angle (scene 3.3): record baseAngle so resume picks up
      // from the same point, then stop the animator so rotationDeg stops updating.
      this.baseAngle = this.rotationDeg
      this.anim?.pause()
    }
  }

  onPlayStateChanged(): void { this.syncRotationState() }

  onSongChanged(): void {
    // Scene 4 / 5: 250 ms smooth return to 0, then (conditionally) restart.
    this.isResetting = true
    this.anim?.pause()
    const ctx = this.getUIContext()
    ctx.animateTo({
      duration: 250,
      curve: Curve.Linear,
      onFinish: () => {
        this.isResetting = false
        this.baseAngle = 0
        this.rotationDeg = 0
        // Restart from 0 so the animator's internal progress aligns with angle 0.
        this.destroyAnimator()
        this.createAnimator()
        if (this.isPlayingProp) {
          this.anim?.play()
        }
      },
    }, () => {
      this.rotationDeg = 0
    })
  }

  build() {
    Column() {
      if (this.coverPixelMap) {
        Stack() {
          Image(this.coverPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius({ topLeft: 9999, topRight: 9999, bottomLeft: 9999, bottomRight: 9999 })
            .clip(true)
            .rotate({ angle: this.rotationDeg })
            .shadow({ radius: 30, color: '#0d000000', offsetX: 0, offsetY: 6 })
            .gesture(LongPressGesture().onAction(() => { this.onLongPress() }))
        }
        .width('100%')
        .aspectRatio(1)
      }
    }
    .width('85%')
    .aspectRatio(1)
  }
}
```

Notes:

- `borderRadius` set with all four corners `9999` produces a circle for any
  square box (matches the HarmonyOS idiom for circular avatars used elsewhere
  in this project, e.g. participating artist cover in PlayerPage.ets line 1447).
- `.rotate({ angle: … })` is the same API used by `FlowingLightComponent`.
- Reset is driven by `animateTo`, NOT by trying to re-program the animator mid-
  iteration. The animator is destroyed and re-created after the reset so the
  next iteration starts at 0 / angle 0.

### 2.4 `entry/src/main/ets/pages/PlayerPage.ets`

In the `AlbumCoverArea()` builder (lines 992-1071):

- Add a `@StorageProp('circlePlaybackCover')` to the struct body next to the
  existing `@StorageProp('miniLyricsInPlayer')`:

  ```ts
  @StorageProp('circlePlaybackCover') circlePlaybackCover: boolean = false
  ```

- In the `else` branch of the `playbackError` check (lines 1021-1043), branch
  again on `this.circlePlaybackCover`:

  ```ts
  if (this.circlePlaybackCover) {
    if (this.vm.coverPixelMap) {
      CirclePlaybackCoverComponent({
        coverPixelMap: this.vm.coverPixelMap,
        onLongPress: () => { this.vm.showLargeImageOverlay() },
      })
    }
    // Scene 6: no placeholder / empty circle when coverPixelMap is undefined.
  } else {
    // Existing rectangle Image(...) block, unchanged.
  }
  ```

- Add the import at the top of the file:

  ```ts
  import { CirclePlaybackCoverComponent } from '../components/CirclePlaybackCoverComponent'
  ```

- No other changes in PlayerPage. The existing `MiniLyricsArea()` column
  (lines 1049-1061) keeps working — its siblings adapt to whichever cover
  renderer runs. Footprint stays `85% × aspect-ratio 1`, same as the rectangle.

### 2.5 (Optional) Scene 9 note

No HarmonyOS car-player page exists today (`MainPage.ets` only routes
`CarKitPage` / `TabletModePage`). The component exposes `forceCircle: boolean`
so that when the car player page is added, it can pass `forceCircle: true` and
the same component handles the car path without needing another copy of the
rotation logic. For this spec, scene 9 is documented as "future: when
`CarPlayerPage` lands, render `CirclePlaybackCoverComponent({ forceCircle: true, … })`
regardless of `circlePlaybackCover`". No code is added for that path now.

## 3. Binding / Refresh paths per spec scenario

- **Scene 1 (toggle on)**:
  - User flips switch in `UserInterfacePage` →
    `circlePlaybackCoverVM.toggle()` → callback writes AppStorage +
    SettingsStore + disables `irregularCoverAllowedVM`.
  - `PlayerPage.@StorageProp('circlePlaybackCover')` updates → rebuild runs →
    `AlbumCoverArea()` takes the circle branch.
  - `CirclePlaybackCoverComponent.aboutToAppear` creates the animator;
    `syncRotationState()` plays it iff `isPlaying`.
- **Scene 2 (toggle off)**: reverse of scene 1 — rectangle branch runs,
  circle component unmounts, its animator is cancelled in `aboutToDisappear`.
- **Scene 3 (play / pause while circle on)**: `@StorageProp('isPlaying')`
  → `onPlayStateChanged` → `syncRotationState`. Pause records `baseAngle`
  before `anim.pause()`, so the static angle stays. Resume calls `anim.play()`
  and `onFrame` resumes from `(v + baseAngle) % 360`.
- **Scene 4 (skip while playing)**: `@StorageProp('currentSongId')`
  → `onSongChanged` → `animateTo(250ms)` drives `rotationDeg` → 0 →
  `onFinish` recreates the animator and plays it (`isPlayingProp === true`).
- **Scene 5 (skip while paused)**: same reset path, but `onFinish` observes
  `!isPlayingProp` and leaves the cover at 0 without playing the animator.
- **Scene 6 (no cover)**: `vm.coverPixelMap === undefined`, both the wrapping
  `if (this.vm.coverPixelMap)` in `AlbumCoverArea` and the inner
  `if (this.coverPixelMap)` in the component short-circuit. Nothing renders.
- **Scene 7 (irregular cover disabled)**: handled entirely by
  `onCircleCoverChanged` in `UserInterfaceViewModel`, which is invoked
  from the switch callback. `irregularCoverAllowedVM.isEnabled` flips;
  when / if UI renders the irregular row, the `enable` prop reflects it
  automatically. No separate wiring needed.
- **Scene 8 (mini lyrics mode)**: `AlbumCoverArea()` is the same surface in
  both modes, so circle rendering & rotation / pause / reset behavior work
  identically whether `miniLyricsInPlayer` is on or off.
- **Scene 9 (car mode)**: no HarmonyOS car player page exists. Deferred.
  Component's `forceCircle` prop lets a future car page bypass the setting.

## 4. Verification

- Static: `hvigorw build` (same command the pipeline's Stage 5 uses). Plan
  touches three ArkTS files and adds one new component; no gradle / oh-package
  change.
- Manual checks after install:
  - Settings → 用户界面 → 圆形播放封面 off (default): player shows rectangle.
  - Toggle on: player cover turns circle, rotates while playing at ~25 s / rev.
  - Pause: cover freezes at the current angle. Resume: continues from same angle.
  - Skip next / previous / queue-tap while playing: cover spins back to 0 over
    ~250 ms then keeps rotating.
  - Skip while paused: cover spins back to 0 over ~250 ms then sits still.
  - Song with no embedded cover: no placeholder, no empty circle.
  - Toggle on → settings switch "允许不规则封面" row (if ever rendered)
    becomes disabled; toggle off re-enables it.
  - Mini lyrics mode: same rotation behavior as non-mini.
  - Toggle off → rectangle returns, no animator keeps running in the
    background (component unmounts, `destroyAnimator` cancels it).

## 5. Out of scope

- A dedicated HarmonyOS car player page / `PlayerCarPage`. The `forceCircle`
  prop is the only concession for a future car page; no routing or page
  scaffold is added here.
- Persisting the rotation angle across app relaunch or across songs.
- Cross-fade between rectangle and circle when the setting toggles —
  the current swap is a hard (immediate) branch, matching Android
  `PlayerCover.kt` which also hard-switches by `circlePlaybackCover`.
- Rendering the "允许不规则封面" row in `UserInterfacePage`. The spec only
  requires the state to be disabled when circle cover is on — the VM wiring
  satisfies that. Adding a new row in the UI is a separate spec.
- MiniPlayer (mini pill in `MainPage`) cover shape. The spec scopes this to
  the playback page. The mini pill stays rectangular — unchanged.
