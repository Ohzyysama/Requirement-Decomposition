# Spec13 Logic Implementation Plan — Lyrics View Blur

Spec source: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec13/plan.md`

Wire the existing UI-only "歌词视图模糊" switch in `设置 > 歌词 > 歌词界面`
(`LyricsInterfacePage`) to a real, persisted setting that drives a
distance-based blur on non-current lyric lines inside `PlayerPage`'s lyrics
swimlane. Blur must suppress while the user is dragging/scrolling the lyrics
list, must reposition when the current line changes (progress tick or song
change), and the switch must be disabled on devices below the supported OS
level.

---

## 1. Repo reality (read before editing)

### 1.1 Existing surfaces (already in place)

- Switch UI placeholder
  `entry/src/main/ets/pages/LyricsInterfacePage.ets:31` — `@State lyricsViewBlur: boolean = false`
  rendered as an `HdsListItemCard` + `SuffixSwitch` at lines 144–166. The
  comment marks it as "not persisted, not bound to any blur effect yet."
- ViewModel field + action stub
  `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:32` — `@Track public blur: boolean = false`
  and `updateBlur(value)` at lines 143–147 (writes to `model.blur`,
  `model.saveToStorage()`, but does NOT call `SettingsStore` so the value
  is not persisted to Preferences).
- Model field + ctor wiring
  `entry/src/main/ets/model/LyricsInterfaceModel.ets:16` — `public blur: boolean = false`
  but `loadFromStorage` (line 42) hardcodes `false` and `saveToStorage`
  (line 60) never writes `lyricsBlur` to `AppStorage`.
- Resource string
  `entry/src/main/resources/base/element/string.json:1528` — `lyrics_view_blur` = "歌词视图模糊"
  (also present in `zh/` and `ug/` variants).
- Lyrics rendering pipeline
  `entry/src/main/ets/pages/PlayerPage.ets:1207` `LyricsArea()` builder, with
  `ForEach` at line 1219 instantiating `LyricsLineComponent` per line,
  passing per-line props (`isCurrent`, `currentTimeMs`, etc.). The
  alternate `entry/src/main/ets/components/LyricsComponent.ets` is dead
  code (no callers — `grep` confirms only its own file references the
  symbol) and is intentionally left untouched.
- User-scroll signal
  `entry/src/main/ets/viewmodel/LyricsViewModel.ets:23` — `@Track public isUserScrolling: boolean = false`
  flipped by `onUserScrollStart` / `onUserScrollEnd` (lines 154–166) and
  reset by `resumeAutoSync` (line 169). Already wired from PlayerPage's
  lyrics List `.onTouch` at lines 1287–1302.
- Persistence convention used by sibling lyrics keys
  `entry/src/main/ets/entryability/EntryAbility.ets:73-77` for
  `lyricsTextSize`, `lyricsTextAlignCenter`, `lyricsFontWeight`,
  `lyricsKaraokeCompatStrategy` — `PersistentStorage.persistProp` +
  `SettingsStore.get` restore + `AppStorage.setOrCreate`. Spec13 adopts
  the identical pattern for `lyricsBlur`.

### 1.2 MVVM owner boundary (single-source-of-truth path)

- Page owner: `LyricsInterfacePage` (View — switch UI + lifecycle), `PlayerPage` (View — lyrics rendering).
- ViewModel owner: `LyricsInterfaceViewModel` (action `updateBlur`, observable `blur`, `isBlurSupported`).
- Model / persistence owner: `LyricsInterfaceModel` (default + load/save), `SettingsStore` (Preferences memory cache), `EntryAbility` (cold-start restore + `PersistentStorage` declaration).
- Live-binding path (cross-page): `AppStorage('lyricsBlur')` is the single live source of truth. Writers go through `LyricsInterfaceViewModel.updateBlur` → `SettingsStore.save` (which writes AppStorage + Preferences). Readers are:
  - `LyricsInterfaceViewModel.blur` (used by the settings switch),
  - `PlayerPage.@StorageProp('lyricsBlur')` (used to gate the per-line blur in `LyricsArea`).
- Refresh path on the player: `@StorageProp('lyricsBlur')` is reactive — toggling the switch instantly re-renders `LyricsLineComponent` props in the `ForEach`. No mirror state, no `aboutToAppear`-as-sync.
- Refresh path on cold start: `EntryAbility.onCreate` → `PersistentStorage.persistProp` + restore from `SettingsStore.get` → `AppStorage` → VM construction reads via `LyricsInterfaceModel.loadFromStorage`.

---

## 2. Data + state design

### 2.1 New AppStorage key

Key: `lyricsBlur` (boolean, default `false`).
- Writer: `LyricsInterfaceViewModel.updateBlur` (only path the switch uses).
- Readers: `LyricsInterfaceViewModel.blur` (settings page); `PlayerPage.@StorageProp('lyricsBlur')` (player).
- Persistence: declared via `PersistentStorage.persistProp('lyricsBlur', false)` AND restored from `SettingsStore.get('lyricsBlur', false)` in `EntryAbility.onCreate`, matching the dual-channel pattern used by `lyricsTextSize` & friends. `SettingsStore.save` is invoked on every toggle so Preferences receives the write immediately (the `PersistentStorage`-only path has been observed unreliable per the comment on `SettingsStore.ets:3-8`).

### 2.2 OS gating for the switch

Spec scenario 7 says: "系统版本低于12 ... 开关显示但禁用". Use `deviceInfo.sdkApiVersion`
(matches "API 12" semantics — the existing `MiniPlayerContainer.ets:9` uses
`deviceInfo.distributionOSApiVersion >= 60100` for HDS material, which is a
different concept; sdkApiVersion is the right field for the spec wording).

- Add a static accessor `LyricsInterfaceModel.isBlurSupported(): boolean`
  that returns `deviceInfo.sdkApiVersion >= 12`. Wrapped in `try/catch` so
  emulators / mocks that throw on the property access fall back to `true`
  (favor showing the feature over silently hiding it on dev builds).
- Surface as `@Track public isBlurSupported: boolean` on
  `LyricsInterfaceViewModel`, initialised from the model accessor at
  construction time. Static across the app session — no listener needed.
- The page uses `enable: this.viewModel.isBlurSupported` on the
  `HdsListItemCard`, mirroring the pattern at
  `UserInterfacePage.ets:355`.

### 2.3 Blur radius math (per line)

Per scenario 2 ("距离越近越轻 ... 超过一定距离后达到最大值"):

- Distance `d = abs(index - currentLineIndex)` (computed by `PlayerPage`
  in the `ForEach` body — already has both values cheaply).
- Radius (vp): `radius = clamp(d * STEP_VP, 0, MAX_VP)` with
  `STEP_VP = 1.5`, `MAX_VP = 6.0`.
  - `d=0` (current line) → 0 vp (no blur, satisfies scenario 2 "当前播放的歌词行清晰显示").
  - `d=1` → 1.5 vp; `d=2` → 3.0 vp; `d=3` → 4.5 vp; `d>=4` → 6.0 vp (cap).
- These constants are exposed as private `static readonly` fields on
  `LyricsLineComponent` so they can be tuned without touching call sites.
- When `currentLineIndex < 0` (no current line yet — empty doc, before
  first line, or stale during song-change), all lines render unblurred
  (treat as `d=0`). Caller passes `lineDistance = 0` when there is no
  current line.

### 2.4 Suppression rules

`LyricsLineComponent` reads three new `@Prop`s and computes a single
effective radius internally:

```
private effectiveBlurRadius(): number {
  if (!this.blurEnabled) return 0          // global toggle off (scenario 1, 3)
  if (this.suppressBlur) return 0          // user is dragging/scrolling (scenario 5)
  if (this.isCurrent) return 0             // current line stays clear (scenario 2, 4, 6)
  if (this.lineDistance <= 0) return 0     // safety
  return Math.min(this.lineDistance * STEP_VP, MAX_VP)
}
```

`suppressBlur` is sourced from `this.vm.lyricsViewModel.isUserScrolling`
(already `@Track`) at the call site. A `@State` reset would not be
sufficient since the flag flips multiple times per gesture.

### 2.5 Realtime updates

- Current-line change (scenario 4): `PlayerPage`'s `LyricsArea` passes
  `lineDistance` derived from `this.vm.currentLyricsLineIndex` for each
  iteration. When `currentLyricsLineIndex` (Track) updates inside
  `PlayerPageViewModel.refreshLyricsLines` (already wired by the playback
  tick path), the entire `ForEach` re-evaluates — every visible line's
  `lineDistance` (and therefore `effectiveBlurRadius`) refreshes in the
  same frame.
- Song change (scenario 6): `loadLyrics` in `LyricsViewModel` resets
  `currentLineIndex` to `-1`, then `findCurrentLine` reassigns it on the
  next progress tick. The same `ForEach` recomputation path covers it,
  and the temporary `-1` window means every line is unblurred during the
  brief reload — acceptable, matches the spec phrasing "歌词内容刷新为新歌曲的歌词".
- Drag/scroll (scenario 5): `LyricsViewModel.isUserScrolling` is already
  set to `true` on `TouchType.Down` (PlayerPage.ets:1291) and back to
  `false` after `USER_SCROLL_RESUME_DELAY` (3 s) or immediate
  `resumeAutoSync`. Reading it in the `ForEach` body subscribes the per-
  iteration prop list — toggle propagates to all visible
  `LyricsLineComponent`s in the next render.

---

## 3. Editing plan (multi-wave)

### Wave 1 — Persistence + Model/VM foundation

**File: `entry/src/main/ets/model/LyricsInterfaceModel.ets`**
- Add import for `deviceInfo` from `@kit.BasicServicesKit` (or `@ohos.deviceInfo` to match existing usage at `MiniPlayerContainer.ets:9` — pick `@kit.BasicServicesKit` since `DevModel.ets:6` already does, keeping kit imports consistent).
- Inside `loadFromStorage()` (line 42): read `const blur = (AppStorage.get('lyricsBlur') as boolean) ?? false` and pass into the constructor instead of the hardcoded `false` at line 52.
- Inside `saveToStorage()` (line 60): add `AppStorage.setOrCreate('lyricsBlur', this.blur)` so the model write paths are symmetric.
- Add static method `static isBlurSupported(): boolean` returning `deviceInfo.sdkApiVersion >= 12`, wrapped in try/catch returning `true` on throw.

**File: `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`**
- Add `@Track public isBlurSupported: boolean = LyricsInterfaceModel.isBlurSupported()`.
- In `syncFromModel()` (line 71): add `AppStorage.setOrCreate('lyricsBlur', this.blur)` so a cold-loaded model seeds the AppStorage key for any `@StorageProp` subscribers (matches the existing pattern for `lyricsTextSize` etc. at lines 83–86).
- Replace the body of `updateBlur(value)` (line 143) with:
  ```
  updateBlur(value: boolean): void {
    if (!this.isBlurSupported) return
    this.blur = value
    this.model.blur = value
    SettingsStore.getInstance().save('lyricsBlur', value)
  }
  ```
  (Drops `model.saveToStorage()` — `SettingsStore.save` already updates AppStorage; the symmetric `AppStorage.setOrCreate` inside `saveToStorage` is kept for callers that go through the model.)

**File: `entry/src/main/ets/entryability/EntryAbility.ets`**
- After line 77 (next to the other `lyrics*` `persistProp` calls): add `PersistentStorage.persistProp('lyricsBlur', false)`.
- After line 182 (next to the matching `setOrCreate` block): add `AppStorage.setOrCreate('lyricsBlur', ss.get('lyricsBlur', false) as boolean)`.

### Wave 2 — Settings page wiring

**File: `entry/src/main/ets/pages/LyricsInterfacePage.ets`**
- Delete the `@State lyricsViewBlur: boolean = false` declaration (line 31).
- In the existing `HdsListItemCard` block at lines 144–166:
  - Replace `isCheck: this.lyricsViewBlur` with `isCheck: this.viewModel.blur`.
  - Replace the `onChange` body `this.lyricsViewBlur = val` with `this.viewModel.updateBlur(val)`.
  - Add `enable: this.viewModel.isBlurSupported` to the `HdsListItemCard` constructor object (mirrors `UserInterfacePage.ets:355`).
- Drop the placeholder comment block at lines 144–145 ("UI placeholder ... not persisted ...") since it's no longer accurate.

### Wave 3 — Player rendering

**File: `entry/src/main/ets/components/LyricsLineComponent.ets`**
- Add three new `@Prop` declarations after the existing `@Prop hasAnyKaraokeInDoc`:
  ```
  @Prop blurEnabled: boolean = false
  @Prop lineDistance: number = 0
  @Prop suppressBlur: boolean = false
  ```
- Add private static constants near the top of the class:
  ```
  private static readonly BLUR_STEP_VP: number = 1.5
  private static readonly BLUR_MAX_VP: number = 6.0
  ```
- Add private method `effectiveBlurRadius()` per the formula in §2.4.
- In `build()` (line 323 `Column() { ... }`), after the existing `.scale(...)`/`.onClick(...)` chain on the outer `Column` (lines 421–429): append `.blur(this.effectiveBlurRadius())`. ArkUI's `.blur()` accepts a vp number; `0` is treated as "no blur" so the current line / suppressed cases incur no compositing overhead.
- `@Prop` triggers a recompute on every prop change — no extra `@Watch` is needed because `effectiveBlurRadius()` is read inline by `.blur(...)` and ArkUI re-evaluates the chain when any read prop changes.

**File: `entry/src/main/ets/pages/PlayerPage.ets`**
- Add `@StorageProp('lyricsBlur') lyricsBlur: boolean = false` near the existing lyrics interface `@StorageProp` block (line 77–83).
- In the `ForEach` callback inside `LyricsArea()` (the `LyricsLineComponent({...})` literal at lines 1221–1249), add three additional fields:
  ```
  blurEnabled: this.lyricsBlur,
  lineDistance: this.vm.currentLyricsLineIndex >= 0
    ? Math.abs(index - this.vm.currentLyricsLineIndex)
    : 0,
  suppressBlur: this.vm.lyricsViewModel.isUserScrolling,
  ```
- Reading `this.vm.lyricsViewModel.isUserScrolling` inside the `ForEach`
  body subscribes the @Track field correctly (the existing
  `this.vm.currentLyricsLineIndex` read on line 1223 follows the same
  pattern). No additional state plumbing is required.

### Wave 4 — Verification

- Static checks:
  - Confirm new `@Prop`s use literal defaults (ArkUI requires this).
  - Confirm `deviceInfo.sdkApiVersion` is read inside try/catch (some HSP build paths expose only a partial deviceInfo shim).
- Lint pass: `code-linter.json5` is at repo root — run the project lint task afterwards.
- Manual smoke (handed off to self-test stage):
  1. Cold start, open `设置 > 歌词 > 歌词界面`: switch shows OFF.
  2. Open player, lyrics scroll: no blur (scenario 1).
  3. Toggle switch ON, return to player: non-current lines blurred with progressive intensity (scenario 2).
  4. During playback: blur tracks new current line as it advances (scenario 4).
  5. Drag/scroll lyrics list: all blur removed; release + 3 s timer or tap to seek removes scroll lock and blur returns (scenario 5).
  6. Skip to next song: blur re-anchors to the new current line (scenario 6).
  7. Toggle OFF: blur disappears (scenario 3).
  8. Restart app: switch state preserved.
  9. (If a low-API simulator is available) Switch row appears disabled (scenario 7).

---

## 4. Out-of-scope / explicit non-goals

- `entry/src/main/ets/components/LyricsComponent.ets` is dead code (no
  callers in the repo). It is intentionally left unchanged — touching it
  risks cargo-cult code. If a future caller adds it back, the same
  three-prop contract from §3 Wave 3 should be applied.
- The static (non-scrollable) lyrics branch in `PlayerPage.ets:1309` is a
  single `Text` with no notion of a "current line" — blur is not applied
  there; spec scenarios all assume scrollable timed lyrics.
- The desktop-lyrics / mini-lyrics renderers are independent surfaces and
  out of scope for this spec.
- No animation curve is wrapped around `.blur()` — the radius change
  follows the natural ArkUI prop-change render. If a future polish pass
  wants smoothing, an `animation({ duration: 200, curve: Curve.Smooth })`
  modifier can be appended, but spec text does not require it.

---

## 5. Files touched (summary)

- `entry/src/main/ets/entryability/EntryAbility.ets` — add `lyricsBlur` persist + restore.
- `entry/src/main/ets/model/LyricsInterfaceModel.ets` — load/save AppStorage key + `isBlurSupported` accessor.
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` — `isBlurSupported` field, fix `updateBlur` to use `SettingsStore`, seed AppStorage in `syncFromModel`.
- `entry/src/main/ets/pages/LyricsInterfacePage.ets` — drop `@State` placeholder, bind switch to VM, gate `enable`.
- `entry/src/main/ets/components/LyricsLineComponent.ets` — three new `@Prop`s, blur math, `.blur()` modifier.
- `entry/src/main/ets/pages/PlayerPage.ets` — `@StorageProp('lyricsBlur')`, three additional props per `ForEach` iteration.

No new files are introduced.
