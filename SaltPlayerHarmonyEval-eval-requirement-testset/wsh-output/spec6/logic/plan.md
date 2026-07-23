# Spec6 — Hide Status Bar Switch: Logic Implementation Plan

## 1. Spec summary

`wsh-output/spec6/plan.md` specifies a single 用户界面 settings switch — 隐藏状态栏 — that:

- Defaults to OFF; persists across launches.
- When ON, hides the device top status bar immediately.
- When OFF, shows the status bar immediately unless 沉浸模式 is currently ON (in which case the bar stays hidden because the other flag still requests hide).
- On cold start, the persisted switch must already be reflected before first paint.
- Bottom sheets/dialogs (bindSheet / CustomDialog) must NOT flip the status bar. Whatever hide/show state was in effect before opening a sheet must persist while it is open (scenes 5 & 6).

The effective rule is the disjunction that `SystemBarModel.reconcileStatusBarVisibility()` already implements: status bar is hidden iff `immersionMode || hideStatusBar`.

## 2. Reality check against the repo

The hide-status-bar functionality is almost fully wired already — this spec is really a finish-wiring task for the UI row placeholder.

### Already in place

- `entry/src/main/ets/model/UserInterfaceModel.ets:15` — `hideStatusBar: SwitcherRowModel` with default `isOn=false, isEnabled=true`, label `$r('app.string.hide_status_bar')`.
- `entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets:36,82-85,100-104` — `hideStatusBarVM: SwitcherRowViewModel` is constructed, restores persisted value from `AppStorage.get<boolean>('hideStatusBar')`, and on toggle persists via `AppStorage.setOrCreate` + `SettingsStore.save` and calls `SystemBarModel.getInstance().reconcileStatusBarVisibility()`.
- `entry/src/main/ets/model/SystemBarModel.ets:94-106` — `reconcileStatusBarVisibility()` reads both `immersionMode` and `hideStatusBar` from `AppStorage` and hides the bar iff either is true. This is the single owner of `setSpecificSystemBarEnabled('status', ...)` outside the raw `setStatusBarVisible`.
- `entry/src/main/ets/entryability/EntryAbility.ets:82` — `PersistentStorage.persistProp('hideStatusBar', false)` auto-persists any AppStorage write.
- `entry/src/main/ets/entryability/EntryAbility.ets:124` — On startup, value is re-hydrated from `SettingsStore` into AppStorage (belt-and-suspenders with PersistentStorage).
- `entry/src/main/ets/entryability/EntryAbility.ets:358-361` — After `windowStage.loadContent`, `SystemBarModel.initWindow(mainWindow)` is called, then immediately `reconcileStatusBarVisibility()` — meaning on cold start the persisted `hideStatusBar` is honored before/at first frame (scene 4).
- `entry/src/main/ets/pages/PlayerPage.ets:344,386` — PlayerPage also reconciles on appear/disappear, so navigating onto/off the player does not desync the bar.
- `entry/src/main/ets/viewmodel/PlayerPageViewModel.ets:723,743` — long-press and external sync paths also go through `reconcileStatusBarVisibility()`.

### The only gap — the switch row UI is a placeholder

`entry/src/main/ets/pages/UserInterfacePage.ets:218-231`:

```
ListItem() {
  HdsListItemCard({
    textItem: {
      primaryText: { text: $r('app.string.hide_status_bar') },
    },
    suffixItem: new SuffixSwitch({
      isCheck: false,
      onChange: (_val: boolean) => {}
    }),
    ...
  })
}
```

`isCheck` is hard-coded `false` and `onChange` is a no-op. So the ViewModel’s wiring is live but the View never binds to it — toggling the visible switch persists nothing and does not trigger reconcile.

### Bottom sheets / dialogs (scenes 5 & 6)

A repo-wide grep for `setSpecificSystemBarEnabled` / `setStatusBarVisible` returns only `SystemBarModel.ets` itself (owner) and callers that all go through `reconcileStatusBarVisibility()` — EntryAbility startup, UserInterfaceViewModel toggles, PlayerPageViewModel toggles, and PlayerPage appear/disappear. No dialog/sheet code (`CustomDialog`, `bindSheet`, `bindContentCover`) touches the status bar at all, and `showInSubWindow` is not used anywhere. Therefore scenes 5 & 6 are satisfied transparently — no sheet opens a sub-window, none of them mutate system-bar state, so whatever `reconcileStatusBarVisibility()` last set persists through the sheet lifecycle.

Conclusion: scenes 5 & 6 require verification only, not code changes.

## 3. MVVM owner boundaries (explicit)

- Page / Component (`UserInterfacePage.ets`) — owns only the View binding. Reads live state via `@StorageLink('hideStatusBar')` for `isCheck`. `onChange` delegates to `vm.hideStatusBarVM.toggle()`.
- ViewModel (`UserInterfaceViewModel.hideStatusBarVM`, already wired) — owns the action. Its change callback persists to `AppStorage` + `SettingsStore` and calls the Model refresh.
- Model (`SystemBarModel.reconcileStatusBarVisibility`) — owns the side-effect on the window (`setSpecificSystemBarEnabled('status', …)`). Reads both AppStorage flags. This is the single refresh path — no caller elsewhere should call `setStatusBarVisible` directly.
- PersistentStorage (`EntryAbility`) — owns cold-start re-hydration. `SettingsStore` owns warm persistence.

Rules respected:

- Persistence stays in the existing owner path (VM callback + `SettingsStore`). We do NOT move persistence into the Page.
- No `aboutToAppear` one-shot read for live sync; we use `@StorageLink('hideStatusBar')` for live bidirectional binding.
- No mirror field in the VM — matches the same rationale already documented for `immersionMode` in `UserInterfaceViewModel.ets:23-27`. AppStorage is the single source of truth; `@StorageLink` in the Page echoes it back.
- No "fake default" — we bind to the real AppStorage key that is already seeded by `EntryAbility` before any UI renders.

## 4. Writer / Reader / Binding / Refresh table

| Actor | Role | Path |
|---|---|---|
| User tap on switch | UI event | `UserInterfacePage` `SuffixSwitch.onChange` → `vm.hideStatusBarVM.toggle()` |
| `SwitcherRowViewModel.toggle()` | Flip + notify | `isOn = !isOn`; calls its `onChange` callback |
| `hideStatusBarVM` onChange callback (already in `UserInterfaceViewModel.ets:100-104`) | Writer | `AppStorage.setOrCreate('hideStatusBar', val)` + `SettingsStore.save('hideStatusBar', val)` + `SystemBarModel.reconcileStatusBarVisibility()` |
| `PersistentStorage.persistProp('hideStatusBar', false)` | Persistence | Auto-flush on AppStorage change |
| `SettingsStore` | Backup persistence | Written through VM callback, re-hydrated in `EntryAbility.onCreate` |
| `EntryAbility.onWindowStageCreate` | Cold-start refresh | `SystemBarModel.initWindow` then `reconcileStatusBarVisibility()` |
| `UserInterfacePage.@StorageLink('hideStatusBar')` (NEW) | Live reader for the switch | Binds to AppStorage so external writes propagate, and toggles round-trip |
| `SystemBarModel.reconcileStatusBarVisibility()` | Single refresh path | Reads `immersionMode || hideStatusBar`, calls `setSpecificSystemBarEnabled('status', !shouldHide)` |

## 5. Edit plan

Only one file needs edits. Everything else is verification.

### 5.1 `entry/src/main/ets/pages/UserInterfacePage.ets`

**Add a StorageLink field** near the existing `immersionMode` / `circlePlaybackCover` storage links (around lines 46-58):

```
// Mirrors AppStorage('hideStatusBar') so the switch reflects live changes
// (including cold-start re-hydration performed by EntryAbility) and so the
// ViewModel callback's write round-trips back into isCheck without a page
// reconstruction. Writer is vm.hideStatusBarVM.toggle(), which persists via
// SettingsStore and reconciles the status bar through SystemBarModel.
@StorageLink('hideStatusBar') hideStatusBar: boolean = false
```

**Replace the placeholder row** (lines 218-231) so it binds to `this.hideStatusBar` and delegates `onChange` to the VM. Mirror the exact guard pattern used by the other rows in the same file (`immersionMode`, `circlePlaybackCover`) so writes are idempotent and do not loop:

```
ListItem() {
  HdsListItemCard({
    textItem: {
      primaryText: { text: $r('app.string.hide_status_bar') },
    },
    suffixItem: new SuffixSwitch({
      isCheck: this.hideStatusBar,
      onChange: (val: boolean) => {
        if (this.hideStatusBar !== val) {
          this.vm.hideStatusBarVM.toggle()
        }
      }
    }),
    cardPrefixMargin: 4,
    cardSuffixMargin: 4,
    cardBackgroundColor: Color.Transparent,
  })
}
```

Rationale:

- `isCheck: this.hideStatusBar` reads the live AppStorage value via `@StorageLink`, so scene 4 (cold start with persisted `true`) shows the switch already on.
- `this.vm.hideStatusBarVM.toggle()` goes through the existing VM callback — AppStorage write → PersistentStorage auto-flush → SettingsStore save → `reconcileStatusBarVisibility()`.
- The `if (this.hideStatusBar !== val)` guard matches the pattern used on the sibling rows and avoids redundant callbacks when the Switch re-emits the current state.

No other file edits are required — all persistence, cold-start hydration, and refresh paths are already wired.

## 6. Scene-by-scene verification

### Scene 1 — turn ON

1. `hideStatusBar = false` (default). User taps the switch; `SuffixSwitch.onChange(true)` fires.
2. Guard `this.hideStatusBar !== true` passes → `hideStatusBarVM.toggle()` flips `isOn` to `true` and invokes its onChange.
3. Callback runs `AppStorage.setOrCreate('hideStatusBar', true)` (PersistentStorage flushes to disk), `SettingsStore.save('hideStatusBar', true)` (backup), and `reconcileStatusBarVisibility()`.
4. `reconcileStatusBarVisibility()` reads immersionMode=false, hideStatusBar=true → shouldHide=true → `setSpecificSystemBarEnabled('status', false)` → bar hides. ✓
5. `@StorageLink('hideStatusBar')` in the page receives the write; `isCheck` stays true.

### Scene 2 — turn OFF, no immersion

1. Starting state hideStatusBar=true, immersionMode=false; switch is ON.
2. Tap → onChange(false); guard passes; VM toggle → callback persists `false` and reconciles.
3. `reconcileStatusBarVisibility()` reads immersionMode=false, hideStatusBar=false → shouldHide=false → `setSpecificSystemBarEnabled('status', true)` → bar shows. ✓

### Scene 3 — turn OFF while immersion is ON

1. State: hideStatusBar=true, immersionMode=true.
2. Tap → VM persists hideStatusBar=false, reconciles.
3. Reconcile sees immersionMode=true → shouldHide=true → bar stays hidden. ✓ (Correct — the player-driven flag is still requesting hide.)

### Scene 4 — cold start with switch ON

1. `EntryAbility.onCreate` calls `PersistentStorage.persistProp('hideStatusBar', false)`, but PersistentStorage only applies the default when no persisted value exists — the stored `true` wins. Then the belt-and-suspenders line `AppStorage.setOrCreate('hideStatusBar', ss.get('hideStatusBar', false))` from SettingsStore confirms the value.
2. `onWindowStageCreate` runs `windowStage.loadContent('pages/main/MainPage', …)` and in its callback calls `SystemBarModel.initWindow(mainWindow)` and `reconcileStatusBarVisibility()`. Reconcile reads hideStatusBar=true → hides the bar. ✓
3. When the user later opens Settings → User Interface, `@StorageLink('hideStatusBar')` resolves to `true` so the switch is shown ON. ✓

### Scene 5 — sheet opens while hideStatusBar=true

A grep for `setSpecificSystemBarEnabled`, `setStatusBarVisible`, and `showInSubWindow` confirms that no dialog, bindSheet, or CustomDialog caller mutates system-bar state in this repo. Therefore opening a sheet leaves `reconcileStatusBarVisibility`'s prior result untouched — the bar stays hidden. ✓ No code change required.

### Scene 6 — sheet opens while hideStatusBar=false and immersion=false

Same argument as Scene 5 — no sheet path touches the status bar, so the bar stays visible. ✓

## 7. DFX considerations

- Logging — `reconcileStatusBarVisibility()` already logs `immersion=<…> hide=<…> visible=<…>` via `hilog`. No extra logs needed.
- Error paths — `setSpecificSystemBarEnabled` is wrapped in try/catch inside SystemBarModel; a failure warns to hilog and leaves the persisted state intact. The switch UI will still reflect the user intent via `@StorageLink`, matching the spec's "开关状态持久化存储" step.
- Concurrency — reconcile is synchronous and runs on the UI thread. No race between immersion and hideStatusBar writers; the last writer re-reads both flags before calling `setSpecificSystemBarEnabled`.

## 8. Files touched

- Edit: `entry/src/main/ets/pages/UserInterfacePage.ets` — add `@StorageLink('hideStatusBar')` field; replace the placeholder switch row body with the live-bound version above.

No new files. No changes to Model, ViewModel, SystemBarModel, or EntryAbility.

## 9. Post-edit validation

1. Build: `hvigor assembleHap` (or the pipeline’s build stage) — zero new errors/warnings expected; the new `@StorageLink` field mirrors the pattern used for `immersionMode` and `circlePlaybackCover` directly above it.
2. Manual walkthrough on device for all six scenes, especially:
   - Cold launch with `hideStatusBar=true` already persisted (scene 4).
   - Toggle OFF while immersion is ON (scene 3) — bar must stay hidden.
   - Open a bottom sheet (e.g., song more-menu) in both hidden and visible states (scenes 5, 6).
3. Optional regression check — verify PlayerPage long-press immersion toggle still works when hideStatusBar=true (bar remains hidden regardless of immersion flips, since the OR rule is symmetric).
