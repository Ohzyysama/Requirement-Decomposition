# spec17 — 歌词翻译 Logic Implementation Plan

Spec source: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec17/plan.md`
Target project: `/Users/moriafly/GitHub/SaltPlayerHarmony`

---

## 0. Ground truth from repo

The bulk of the feature is **already wired**. What is missing is (a) persistence of `openTranslation`, (b) the active/inactive button visual treatment described in the spec, (c) the 300ms reveal/hide motion on the translation row, (d) recentering the lyrics list after the row height change, and (e) mini-lyrics under the cover reflecting the toggle.

What already exists in code:

- `entry/src/main/ets/viewmodel/LyricsViewModel.ets`
  - `@Track openTranslation: boolean = true`
  - `@Track hasTranslation: boolean = false` (set from `LyricsDocument.hasTranslation`)
  - `toggleTranslation()` flips `openTranslation`.
- `entry/src/main/ets/model/LyricsModel.ets`
  - `LyricsLine.subText` populated by the LRC parser (same-timestamp lines merge as translation).
  - `LyricsDocument.hasTranslation = lines.some(l => l.subText.length > 0)`.
- `entry/src/main/ets/components/LyricsComponent.ets` — already passes `showTranslation = openTranslation && hasTranslation` into `LyricsLineComponent`, already mounts `LyricsSettingsBarComponent` with translation callbacks. (Used by mini lyrics container, not by `PlayerPage.LyricsArea`.)
- `entry/src/main/ets/components/LyricsLineComponent.ets` — already renders `subText` when `showTranslation && line.subText.length > 0`, with `mainOpacity` (1.0 current / 0.3 others) and `subOpacity` (0.7 current / 0.2 others) driven via `animateTo` on `onIsCurrentChanged`.
- `entry/src/main/ets/pages/PlayerPage.ets` — `LyricsArea()` builder feeds `showTranslation: this.vm.lyricsViewModel.openTranslation && this.vm.lyricsViewModel.hasTranslation` into `LyricsLineComponent`; the play-page bottom-bar translation button (lines 1643–1657) is **commented out**. This page is the actual one used in production by the spec (`播放页歌词区域`).

Repo conventions for new persistent flags (mirrors `lyricsBlur`, `lyricsHideControlPanel`, `miniLyricsInPlayer`):
1. Declare `PersistentStorage.persistProp('<key>', <default>)` in `EntryAbility.onCreate`.
2. Hydrate from `SettingsStore` with `AppStorage.setOrCreate('<key>', ss.get('<key>', <default>) as boolean)`.
3. Read in views via `@StorageProp('<key>')`. ViewModels mutate via `SettingsStore.getInstance().save('<key>', val)` which both writes `AppStorage` and `flushSync`-es to Preferences.

---

## 1. MVVM ownership boundary

| Concern | Owner | File |
|---|---|---|
| UI for the translation button (active / inactive style, immersion hide) | Page / Component | `pages/PlayerPage.ets`, `components/LyricsSettingsBarComponent.ets` |
| UI animation for translation text reveal/hide (300ms fade + height) | Component | `components/LyricsLineComponent.ets` |
| Re-anchoring scroll to current line after row height change | Page (`LyricsArea`) | `pages/PlayerPage.ets` |
| Translation toggle action, visibility predicate, mini-lyrics composition (with translation appended) | ViewModel | `viewmodel/LyricsViewModel.ets`, `viewmodel/PlayerPageViewModel.ets` |
| Persistence of `openTranslation` (writer + reader binding path) | Model / DataSource (SettingsStore + Preferences) | `model/SettingsStore.ets`, `entryability/EntryAbility.ets` |
| Mini-bar / notification stream translation propagation | Model (`MiniLyricsController`) | `model/MiniLyricsController.ets` |

Persistence path (writer → reader):
- Writer: `LyricsViewModel.toggleTranslation()` → calls `SettingsStore.save('lyricsOpenTranslation', val)` → writes to `AppStorage` and disk.
- Reader: `@StorageProp('lyricsOpenTranslation')` in `PlayerPage` and `MiniLyricsController` consumes `AppStorage.get`.
- `LyricsViewModel.openTranslation` is hydrated from `AppStorage` on construction (one-time pull) and on `loadLyrics` re-entry (no-op besides re-reading `hasTranslation`); the `@StorageProp` in views is the live reactive surface — `aboutToAppear` is not used for live sync.

Anti-patterns explicitly avoided:
- No mirror state in `PlayerPage`; the page reads `openTranslation` from the `@StorageProp` and from `vm.lyricsViewModel.openTranslation` (same AppStorage source feeds both via the toggle path).
- No fake default in `PlayerPage`; the default `true` is the same in `PersistentStorage.persistProp`, `SettingsStore.get` fallback, `@StorageProp` initializer, and `LyricsViewModel` constructor — keep them aligned.
- No persistence call in `PlayerPage`; persistence stays in `LyricsViewModel.toggleTranslation` (the existing action entry point), which delegates to `SettingsStore`.

---

## 2. Surfaces & files touched

| # | File | Change |
|---|---|---|
| 1 | `entry/src/main/ets/entryability/EntryAbility.ets` | Add `PersistentStorage.persistProp('lyricsOpenTranslation', true)` and `AppStorage.setOrCreate('lyricsOpenTranslation', ss.get('lyricsOpenTranslation', true) as boolean)` next to `lyricsBlur`. |
| 2 | `entry/src/main/ets/viewmodel/LyricsViewModel.ets` | Hydrate `openTranslation` from AppStorage in constructor; in `toggleTranslation()` flip the state AND call `SettingsStore.getInstance().save('lyricsOpenTranslation', this.openTranslation)`. Also reset `openTranslation` from `AppStorage` at the top of `loadLyrics` so an in-process re-construction picks up an external change (defensive — both the ViewModel field and the `@StorageProp` resolve to the same key). |
| 3 | `entry/src/main/ets/components/LyricsSettingsBarComponent.ets` | Replace the "译" text-button styling with the spec-mandated icon button: inactive = bordered icon, active = filled-background hollow icon. Use `app.media.ic_translation` SVG; flip `fillColor` between themed fg and themed bg to fake "hollow" against the filled chip. Keep the existing `onTranslationToggle` hook and `if (hasTranslation)` guard. |
| 4 | `entry/src/main/ets/components/LyricsLineComponent.ets` | Wrap the existing `if (this.showTranslation && this.line.subText.length > 0)` Text in a Column whose `.height(this.translationHeight)`, `.opacity(this.translationOpacity)` track an `animateTo({ duration: 300 })`. Drive it from a new `@Prop @Watch('onShowTranslationChanged') showTranslation: boolean` field (already a plain field today — promote). Reset state on `aboutToAppear` so newly-spawned items don't animate from 0. Use `Text.measure`-less approach: keep `height(undefined)` for natural height when visible and `height(0)` when hidden, wrapped in `clip(true)` on the outer Column so the height tween animates the cell instead of overflowing. |
| 5 | `entry/src/main/ets/pages/PlayerPage.ets` | (a) Add `@StorageProp('lyricsOpenTranslation') lyricsOpenTranslation: boolean = true` (used only for the button's visual state, not for the line filter — the filter stays on the VM read so cross-page binding is one direction). (b) Un-comment the translation button block in `LyricsArea`'s bottom-bar row and re-style it per spec (mirrors the change to `LyricsSettingsBarComponent`). Hide using `visibility(this.vm.immersionMode || this.lyricsHideControlPanel ? Visibility.None : Visibility.Visible)` for the **whole** bottom bar; per-button visibility for translation extra-gated on `this.vm.lyricsViewModel.hasTranslation`. (c) After tapping translation toggle, schedule `this.lyricsScroller.scrollToIndex(this.vm.currentLyricsLineIndex + 1, true, ScrollAlign.CENTER)` inside a 30ms `setTimeout` so the recenter happens after the row height tween starts, matching scenario 10's "smooth scroll to current line in viewport". |
| 6 | `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets` | Extend `refreshMiniLyrics()` to append translation `subText` under each line when `openTranslation && hasTranslation`. Mini-lyrics is a `string[]` today; switch to interleaving so each visible main line is followed by its translation. Bump `miniLyricsLines` array regeneration when `LyricsViewModel.openTranslation` changes — add an explicit `onTranslationToggleChanged()` hook called from `toggleTranslation` (see below). |
| 7 | `entry/src/main/ets/viewmodel/LyricsViewModel.ets` | Add a listener registration `addTranslationChangedListener(fn)` and notify all listeners inside `toggleTranslation()`. `PlayerPageViewModel.init` and `MiniLyricsController.init` both subscribe and call `refreshMiniLyrics()` / `tickOnce()` respectively. |
| 8 | `entry/src/main/ets/model/MiniLyricsController.ets` | When the lyrics published to the mini bar are rendered as a single subtitle string, append `" — " + subText` if `openTranslation && hasTranslation && idx in range && lines[idx].subText.length > 0`. Read `openTranslation` from `AppStorage.get<boolean>('lyricsOpenTranslation')` per tick (no listener needed — already ticks at 200ms). |

No new files are required.

---

## 3. Step-by-step implementation order

1. **Persistence registration** (`EntryAbility.ets`)
   - In `onCreate`, next to `PersistentStorage.persistProp('lyricsBlur', false)`, add:
     `PersistentStorage.persistProp('lyricsOpenTranslation', true)`
   - In the `SettingsStore` restore block (next to the `lyricsBlur` line):
     `AppStorage.setOrCreate('lyricsOpenTranslation', ss.get('lyricsOpenTranslation', true) as boolean)`
   - Default `true` so existing users who never tapped the button still see translations.

2. **ViewModel toggle persistence** (`LyricsViewModel.ets`)
   - Import `SettingsStore` from `'../model/SettingsStore'`.
   - In the field initializer for `openTranslation`, fold in the stored value:
     `@Track public openTranslation: boolean = (AppStorage.get<boolean>('lyricsOpenTranslation') ?? true)`
   - Rewrite `toggleTranslation()`:
     ```
     this.openTranslation = !this.openTranslation
     SettingsStore.getInstance().save('lyricsOpenTranslation', this.openTranslation)
     for (const fn of this.translationListeners) fn(this.openTranslation)
     ```
   - Add private `translationListeners: Array<(open: boolean) => void> = []` and `addTranslationChangedListener / removeTranslationChangedListener` methods (mirror `MiniLyricsController.addListener`).
   - In `loadLyrics`, do **not** mutate `openTranslation` (the persisted state is independent of the song).

3. **Settings-bar button restyle** (`LyricsSettingsBarComponent.ets`)
   - Replace the `Text('译')` button with a 32×32 chip:
     ```
     Stack({ alignContent: Alignment.Center }) {
       if (this.openTranslation) {
         // active: filled background + hollow icon (fillColor = transparent / contrasting)
         Column()
           .width(32).height(32).borderRadius(16)
           .backgroundColor(this.themeColor)
         Image($r('app.media.ic_translation'))
           .width(18).height(18)
           .fillColor(Color.Transparent)   // hollow look
           .stroke(this.themeColor)         // ArkUI Image supports stroke when SVG has stroke attrs
       } else {
         // inactive: bordered icon-only
         Column()
           .width(32).height(32).borderRadius(16)
           .border({ width: 1, color: this.themeColor + '80' })
         Image($r('app.media.ic_translation'))
           .width(18).height(18)
           .fillColor(this.themeColor)
       }
     }
     ```
   - If SVG `stroke` is not honored by `Image`, fall back to two static SVG assets `ic_translation_filled` / `ic_translation_outline` and pick by `openTranslation`. Both files already mirror the existing `ic_translation.svg` style — only one new asset would be added under `entry/src/main/resources/base/media/`. Decide at implementation time; the plan accepts either path.
   - Keep `accessibilityText('翻译开关')`, keep the `onTranslationToggle` plumbing.
   - Use `animation({ duration: 200, curve: Curve.FastOutSlowIn })` on the Stack so the active/inactive cross-fade matches the existing `.animation({ duration: 200 })` on the old button.

4. **Translation row reveal/hide animation** (`LyricsLineComponent.ets`)
   - Promote `showTranslation: boolean` from plain field to `@Prop @Watch('onShowTranslationChanged') showTranslation: boolean = false`.
   - Add `@State private translationOpacity: number = 1` and `@State private translationVisible: boolean = true`.
   - In `aboutToAppear`, initialize:
     ```
     this.translationVisible = this.showTranslation && this.line.subText.length > 0
     this.translationOpacity = this.translationVisible ? 1 : 0
     ```
   - Implement `onShowTranslationChanged()`:
     ```
     const shouldShow = this.showTranslation && this.line.subText.length > 0
     animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
       this.translationVisible = shouldShow
       this.translationOpacity = shouldShow ? 1 : 0
     })
     ```
   - Wrap the existing `if (this.showTranslation && this.line.subText.length > 0)` block in `Column() { … }` with `.height(this.translationVisible ? undefined : 0)`, `.opacity(this.translationOpacity)`, `.clip(true)`. ArkUI animates `height` from current measured value to `0` only when an explicit number is set; to make it tween, use a two-tier approach: when collapsing, first read the measured natural height via `onAreaChange` into `@State translationNaturalHeight`, then in `onShowTranslationChanged` set `translationVisible` after a frame so the height value is concretely animatable (`height(this.translationVisible ? this.translationNaturalHeight : 0)`). This matches the pattern used by `Column().height(this.vm.immersionMode ? 0 : undefined).animation({ duration: 300 })` already in `PlayerPage`. Use `.animation({ duration: 300, curve: Curve.FastOutSlowIn })` on the wrapper Column rather than `animateTo` if simpler — the existing immersion-mode rows do exactly that.
   - Sub-opacity continues to be driven by `mainOpacity` / `subOpacity` (`isCurrent` 0.7 vs 0.2), per scenario 1 step 7's "current line fully opaque, others reduced opacity". Do not collide the two animations: `subOpacity` is the long-term dim level (0.2 vs 0.7); `translationOpacity` is the show/hide tween (0 vs 1). The actual rendered opacity is `subOpacity * translationOpacity` — multiply them inline on the Text.

5. **PlayerPage bottom-bar wiring** (`PlayerPage.ets`)
   - Add `@StorageProp('lyricsOpenTranslation') lyricsOpenTranslation: boolean = true` next to the other lyrics `@StorageProp`s (around line 86).
   - Inside `LyricsArea`'s bottom-bar Row (currently lines ~1616–1665), un-comment and replace the translation button with the same Stack-based filled/outlined chip used in step 3. Source `this.lyricsOpenTranslation` for the visual state and `this.vm.lyricsViewModel.toggleTranslation` for the action. Show only when `this.vm.lyricsViewModel.hasTranslation` is true (scenario 3).
   - The whole bottom bar already collapses to height 0 under immersion (`.height(this.vm.immersionMode ? 0 : 48)`), so scenario 9 is satisfied without further work — confirm in self-test.
   - After the toggle, schedule a re-center:
     ```
     onTranslationToggle: () => {
       this.vm.lyricsViewModel.toggleTranslation()
       setTimeout(() => {
         if (this.vm.currentLyricsLineIndex >= 0) {
           this.lyricsScroller.scrollToIndex(this.vm.currentLyricsLineIndex + 1, true, ScrollAlign.CENTER)
         }
       }, 50)
     }
     ```
     The 50ms wait lets the height tween register so the post-tween viewport math lands the current line in the center (scenario 10). `scrollToIndex(..., true, ...)` already animates the scroll.
   - Pass `showTranslation: this.vm.lyricsViewModel.openTranslation && this.vm.lyricsViewModel.hasTranslation` to `LyricsLineComponent` — already in place; verify no regression.

6. **Mini-lyrics with translation** (`PlayerPageViewModel.ets`)
   - In the constructor / `init`, after `this.lyricsViewModel = new LyricsViewModel()`, register:
     ```
     this.lyricsViewModel.addTranslationChangedListener((_open: boolean): void => {
       this.refreshMiniLyrics()
     })
     ```
   - Rewrite `refreshMiniLyrics()` to interleave translation lines when `openTranslation && hasTranslation`. The current pre-line cap is 3 lines (`Math.min(idx + 3, doc.lines.length)`); when translation is on, halve the lyric window to 2 lines so the rendered output stays at 3–4 visible rows in the 88vp `MiniLyricsArea` height.
   - Example shape:
     ```
     const showTr = this.lyricsViewModel.openTranslation && this.lyricsViewModel.hasTranslation
     const lyricLineCap = showTr ? 2 : 3
     for (let i = idx; i < Math.min(idx + lyricLineCap, doc.lines.length); i++) {
       const main = doc.lines[i].mainText
       if (main.length > 0) {
         lines.push(main)
         if (showTr && doc.lines[i].subText.length > 0) {
           lines.push(doc.lines[i].subText)
         }
       }
     }
     ```
   - `PlayerPage.MiniLyricsArea` already does `ForEach(this.vm.miniLyricsLines, …)` with per-index opacity (0.9 for first, 0.5 for others). Translation rows will inherit this; revisit only if visual diff is unacceptable in self-test.

7. **Mini-lyrics in the mini player / notification** (`MiniLyricsController.ets`)
   - Inside `tickOnce()`, after computing `newLine`, if `(AppStorage.get<boolean>('lyricsOpenTranslation') ?? true)` is true AND the line has a `subText`, set `newLine = mainText + ' / ' + subText` (or use `\n` if the mini-bar Text renders multiline — confirm in self-test; both are minor UI choices). Keep the change scoped: it does NOT affect the published `hasLyrics` flag.
   - This satisfies scenarios 6, 7, 8 (mini-lyrics tracking translation state in real time), including the case where the user toggles in the lyrics page and swipes back to the cover.

8. **Default visibility on entry** (`PlayerPage.LyricsArea`)
   - On first mount, `this.vm.lyricsViewModel.openTranslation` already reflects the persisted value (initialized at VM construction time). No additional refresh is needed — the `@StorageProp` reacts when `toggleTranslation` writes, and the `vm.lyricsViewModel.openTranslation` field is `@Track` so the LyricsArea `showTranslation` recomputes per render frame.

---

## 4. Scenario coverage map

| Scenario | Where satisfied |
|---|---|
| 1. Active button + 300ms fade + height tween + per-line opacity | Step 3 (button), Step 4 (line animation) |
| 2. Inactive button + 300ms fade-out + height collapse | Step 3, Step 4 (same path, reverse) |
| 3. Button hidden when no translation | Step 5 (button gated on `hasTranslation`); already in `LyricsSettingsBarComponent` |
| 4. Song switch with translation: button stays active | `loadLyrics` resets `hasTranslation` from new doc; `openTranslation` is independent and untouched (Step 2) |
| 5. Song switch without translation: button hides, state preserved | Same gate; `openTranslation` persists across song changes |
| 6. Mini-lyrics shows translation when on | Step 7 (`MiniLyricsController.tickOnce`), Step 6 (`PlayerPageViewModel.refreshMiniLyrics`) |
| 7. Mini-lyrics hides translation when off | Same path, opposite branch |
| 8. Toggle in lyrics page → mini-lyrics updates on swipe back | Step 6 listener fires on toggle; Step 7 polls AppStorage on every 200ms tick |
| 9. Immersion mode hides button, state preserved | Bottom bar already collapses under `immersionMode`; state is decoupled (`@StorageProp` + persisted) |
| 10. Smooth scroll to current line after toggle | Step 5 `setTimeout` + `scrollToIndex(..., smooth=true, CENTER)` |

---

## 5. DFX, regressions, build-time checks

- **Stable AppStorage key**: `'lyricsOpenTranslation'` — chosen to align with the existing `lyrics*` namespace; no collision with `statusBarLyricsNotShowTranslation`, which is its semantic inverse for the status-bar channel only.
- **Default value chain audit**: ensure `PersistentStorage.persistProp` default, `SettingsStore.get` fallback, `@StorageProp` initializer, and `LyricsViewModel` field initializer all read `true`.
- **`@StorageProp` cannot be initialized from `AppStorage.get` at field-decl time** — instead, initialize the `@StorageProp` field with the literal default; the framework hydrates from AppStorage at render time. The `LyricsViewModel.openTranslation` field is the only place we evaluate `AppStorage.get` at field-init time, and that runs at VM construction in `PlayerPageViewModel.init` (which runs **after** `EntryAbility.onCreate` does `AppStorage.setOrCreate('lyricsOpenTranslation', …)`).
- **Listener leak**: `addTranslationChangedListener` must be paired with `removeTranslationChangedListener` in `PlayerPageViewModel.destroy` (if present); follow the existing `MiniLyricsController.destroy` pattern. If `PlayerPageViewModel` has no destroy hook, no removal is needed because both objects live the lifetime of the process.
- **Animation budget**: each line's translation tween uses `animateTo` independently. With ~10 visible lines × 300ms tween, this is well within ArkUI's frame budget. The List's `cachedCount(10)` ensures off-screen lines don't animate.
- **No karaoke regression**: the karaoke wipe path (`KaraokeRenderDecision.shouldRenderPerWord`) is independent of `subText` — only `mainText` is wiped. The wrapper Column holding the translation Text is sibling to the karaoke stack, so the wipe is unaffected.
- **No translation in notification status bar** (scenario excluded per spec): the existing `statusBarLyricsNotShowTranslation` flag governs that channel; our changes apply only to `MiniLyricsController.tickOnce`'s in-app subtitle. If `NotificationLyricController` reads `MiniLyricsController.currentLine`, the appended translation would leak there — confirm and special-case if needed. (Verified in repo: `NotificationLyricController.lyricsListener` consumes `(songId, line, hasLyrics)` from `MiniLyricsController`. To keep the notification bar untouched, branch in `MiniLyricsController.tickOnce`: store `mainText` for in-app subscribers and emit a separate "with translation" channel, OR simpler: leave `MiniLyricsController.currentLine` as `mainText` only and apply the translation join at the consumer site instead. **Decision: defer the join to the consumer — `PlayerPageViewModel.refreshMiniLyrics` (Step 6) handles its own translation interleaving; `MiniLyricsController` continues to publish `mainText` only.** This removes Step 7 from the must-do list.)

**Revised Step 7 (post-audit)**: `MiniLyricsController` is **not** modified. Translation handling for the cover-page mini-lyrics is fully owned by `PlayerPageViewModel.refreshMiniLyrics`. The notification bar (which has its own translation toggle: `statusBarLyricsNotShowTranslation`) remains correct without changes.

---

## 6. Verification checklist (Stage 7 self-test guidance)

- [ ] Toggle translation on a song that has both `mainText` and `subText` — translation rows fade in across the visible window, height grows smoothly, current line stays centered.
- [ ] Toggle off — symmetric fade and height collapse.
- [ ] Skip to a song without `subText` — button disappears; toggling other UI not blocked.
- [ ] Skip back to a translated song — button reappears in the previously-set state (active or inactive).
- [ ] Kill the app, relaunch — translation state is the same as before kill.
- [ ] Cover page mini-lyrics shows interleaved translation when on, plain when off.
- [ ] Enter immersion — bottom bar (including button) hidden; translations remain visible if open.
- [ ] Exit immersion — bottom bar restored, button reflects state.
- [ ] Karaoke per-word wipe still works on a karaoke-style line while translation rows are visible.
- [ ] Notification subtitle does NOT include translation (regression check on the existing notification flag).
