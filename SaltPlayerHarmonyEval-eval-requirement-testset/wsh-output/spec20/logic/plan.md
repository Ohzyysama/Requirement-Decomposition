# Spec20 Implementation Plan — Karaoke Lyrics Animation Compatibility Strategy

## Scope

设置-歌词-歌词界面 和 播放页歌词设置面板 两处提供"卡拉OK歌词动画兼容策略"选项，三种值，默认"当前行"，立即生效、持久化、两处双向同步、跟随歌曲切换。

Spec covers ten scenarios; the existing codebase already wires the strategy end-to-end (Model + ViewModel + Settings Page + Player dialog + LyricsLineComponent + KaraokeRenderDecision + PlayerPage). Spec20 only changes default value, label strings, and locks in the existing live-sync wiring. No new persistence path, no new state owner.

## Ground Truth — Existing Wiring

| Layer | File | Responsibility |
|---|---|---|
| Model (data + persistence) | `entry/src/main/ets/model/LyricsInterfaceModel.ets` | Owns `karaokeCompatStrategyIndex`; `KaraokeCompatStrategy` enum (`CURRENT_LINE_ONLY=0`, `EXPAND_ALL_LINES=1`, `ALWAYS=2`); `loadFromStorage` / `saveToStorage` against `AppStorage['lyricsKaraokeCompatStrategy']`. |
| Model (render decision) | `entry/src/main/ets/model/KaraokeRenderDecision.ets` | Pure `shouldRenderPerWord(strategy, line, hasAnyKaraokeInDoc)` — already matches all six per-strategy scenarios in the spec. No change needed. |
| Model (doc flag) | `entry/src/main/ets/model/LyricsModel.ets:62` | `LyricsDocument.hasAnyKaraoke` precomputed at parse time → drives `EXPAND_ALL_LINES`. |
| Persistence backend | `entry/src/main/ets/model/SettingsStore.ets` (via VM) + `PersistentStorage.persistProp('lyricsKaraokeCompatStrategy', ...)` in `EntryAbility.onCreate`. AppStorage <→ Preferences round-trip happens on launch. |
| ViewModel (singleton) | `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` | `LyricsInterfaceViewModel.getInstance()` — same instance shared by settings page and player dialog. Holds `@Track karaokeCompatStrategyIndex`, `karaokeStrategyOptions`, `updateKaraokeStrategy`, `getKaraokeStrategyText`, `loadSettings`. |
| View — Settings page | `entry/src/main/ets/pages/LyricsInterfacePage.ets` | `KaraokeSection` row + `KaraokeStrategyMenu`. Calls `viewModel.updateKaraokeStrategy(index)`. Reloads via `aboutToAppear → loadSettings`. |
| View — Player dialog | `entry/src/main/ets/components/LyricsInterfaceDialogComponent.ets` | `SettingsGroup2` row + same `KaraokeStrategyMenu`. Calls `viewModel.updateKaraokeStrategy(index)` on the shared singleton. |
| View — Lyrics renderer | `entry/src/main/ets/components/LyricsComponent.ets` and `entry/src/main/ets/components/LyricsLineComponent.ets` | `LyricsLineComponent` consumes `karaokeStrategyIndex` + `hasAnyKaraokeInDoc` via `@Prop`, decides via `KaraokeRenderDecision.shouldRenderPerWord`. |
| View — Player page (live re-render) | `entry/src/main/ets/pages/PlayerPage.ets:83` | `@StorageProp('lyricsKaraokeCompatStrategy') lyricsKaraokeCompatStrategy: number = 1` — pushes the live value into `LyricsLineComponent.karaokeStrategyIndex` for every line on every change. |
| Strings | `entry/src/main/resources/{base,zh,ug}/element/string.json` (key `karaoke_lyrics_animation_compatibility_strategy`) — used for the row title. Option labels are hard-coded in the VM (`karaokeStrategyOptions`). |

## MVVM Boundary

- **Page / Component (View).** `LyricsInterfacePage`, `LyricsInterfaceDialogComponent`, `LyricsComponent`, `LyricsLineComponent`. Render menu + lyrics; delegate user taps to the VM. No persistence calls here.
- **ViewModel.** `LyricsInterfaceViewModel` (singleton). Sole writer of the strategy: `updateKaraokeStrategy` is the only action path. It writes `@Track` field → `model.karaokeCompatStrategyIndex` → `model.saveToStorage()` → `SettingsStore.save('lyricsKaraokeCompatStrategy', index)`. Both write paths land on the same AppStorage key, which the player reads via `@StorageProp`.
- **Model / DataSource.** `LyricsInterfaceModel` owns the schema and persistence; `KaraokeRenderDecision` is the pure decision rule; `LyricsModel.LyricsDocument.hasAnyKaraoke` is the per-song flag.
- **Refresh path for the lyrics list.** Already correct: AppStorage key → PlayerPage `@StorageProp` → `LyricsLineComponent` `@Prop`. Settings page + dialog share the same VM singleton, so opening either view shows the current value. Do **not** add a mirror state or a new owner.

## What Spec20 Actually Changes

The spec is mostly a re-statement of existing behaviour, with two concrete deltas plus one default-value flip:

### Delta 1 — Default strategy is "当前行" (`CURRENT_LINE_ONLY = 0`)

Repo currently defaults to `EXPAND_ALL_LINES = 1` in five places. Flip all five to `0`. Migration is one-way: previously-persisted user choices are preserved by `Preferences.get('lyricsKaraokeCompatStrategy', <default>)`; only new installs and the in-memory fallback are affected.

Targets:
1. `entry/src/main/ets/model/LyricsInterfaceModel.ets`
   - Field initializer `public karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.EXPAND_ALL_LINES` → `KaraokeCompatStrategy.CURRENT_LINE_ONLY`.
   - Constructor default parameter `karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.EXPAND_ALL_LINES` → `CURRENT_LINE_ONLY`.
   - `loadFromStorage` fallback `?? KaraokeCompatStrategy.EXPAND_ALL_LINES` → `?? KaraokeCompatStrategy.CURRENT_LINE_ONLY`.
2. `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`
   - `@Track public karaokeCompatStrategyIndex: number = KaraokeCompatStrategy.EXPAND_ALL_LINES` → `CURRENT_LINE_ONLY`.
3. `entry/src/main/ets/entryability/EntryAbility.ets`
   - `PersistentStorage.persistProp('lyricsKaraokeCompatStrategy', 1)` → `0`. Also update the comment to "0 = CURRENT_LINE_ONLY (default)".
   - `AppStorage.setOrCreate('lyricsKaraokeCompatStrategy', ss.get('lyricsKaraokeCompatStrategy', 1) as number)` → `ss.get(..., 0)`.
4. `entry/src/main/ets/pages/PlayerPage.ets`
   - `@StorageProp('lyricsKaraokeCompatStrategy') lyricsKaraokeCompatStrategy: number = 1` → `: number = 0`. (This is just the pre-hydration fallback; `EntryAbility.onCreate` always seeds AppStorage before the player mounts, but the literal still must agree.)
5. `entry/src/main/ets/components/LyricsLineComponent.ets`
   - `@Prop karaokeStrategyIndex: number = 1` → `: number = 0`. Same rationale as above — the prop is always supplied, but the default should match the new convention.

### Delta 2 — Option labels exactly match the spec

Spec uses **"当前行"** / **"扩展全部"** / **"总是"**. Repo currently has `'仅当前行', '拓展全部行', '总是'`. Fix the array in **one** place (the VM, which is the single source of truth for both views):

- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets`, field `karaokeStrategyOptions`:
  ```ts
  @Track public readonly karaokeStrategyOptions: string[] = [
    '当前行',       // 0 = CURRENT_LINE_ONLY
    '扩展全部',     // 1 = EXPAND_ALL_LINES
    '总是'          // 2 = ALWAYS
  ]
  ```

`getKaraokeStrategyText()` and both `KaraokeStrategyMenu` builders (in the page and the dialog) read this array directly, so no further edits are needed.

### Delta 3 (no-op verification) — Decision logic, live sync, song switch

The remaining seven scenarios already work in the repo. The plan does **not** modify the rendering, decision, or refresh code — but the implementation must verify them and add a short comment in the page/dialog tying the wiring to spec20:

- **Scenario 1 (CURRENT_LINE_ONLY, mixed lines).** `KaraokeRenderDecision.shouldRenderPerWord` with `strategyIndex===0` returns `line.cells.length>0` per line. No code change.
- **Scenario 2 (CURRENT_LINE_ONLY, no cells anywhere).** Same path returns `false` for every line. No code change.
- **Scenario 3 (EXPAND_ALL_LINES, at least one karaoke line).** `LyricsDocument.hasAnyKaraoke` is `true` → branch returns `true` for every line → uniform sweep on lines without cells via `shouldUseUniformWordSweep`. No code change.
- **Scenario 4 (EXPAND_ALL_LINES, no cells anywhere).** `hasAnyKaraoke=false` → branch returns `false` for every line. No code change.
- **Scenario 5/6 (ALWAYS).** Branch returns `true` unconditionally, including for documents with zero karaoke data. No code change.
- **Scenario 7 (dialog → settings sync).** Both surfaces target the same `LyricsInterfaceViewModel.getInstance()` and write through `SettingsStore.save`. When the user later opens the settings page, `aboutToAppear → loadSettings → syncFromModel` re-pulls from AppStorage (which the dialog already updated), so the row sub-text matches. PlayerPage re-renders lyrics immediately via `@StorageProp`. No code change.
- **Scenario 8 (settings → dialog sync).** Same direction. The dialog is rebuilt every time `BottomSheetType.LYRICS_INTERFACE` opens, and it `@ObjectLink`s the shared singleton VM, so it always reads the up-to-date value. When the user later returns to the player, PlayerPage's `@StorageProp` already reflects the new value, so lyrics are correct without an extra step. No code change.
- **Scenario 9 (first run / default).** Covered by Delta 1.
- **Scenario 10 (song switch).** When a new song's lyrics load, `LyricsViewModel` populates `LyricsDocument.hasAnyKaraoke` from the new line set; PlayerPage's `@StorageProp lyricsKaraokeCompatStrategy` is unchanged; `LyricsLineComponent` props re-evaluate. The decision rule is re-applied per line on the next render. No code change.

## Owner Boundary — Hands-Off List

To avoid accidentally re-introducing the bugs the MVVM guardrails warn about:

- Do **not** add a second writer for `lyricsKaraokeCompatStrategy` outside `LyricsInterfaceViewModel.updateKaraokeStrategy`. The page and the dialog must call the VM, never `AppStorage.setOrCreate` directly.
- Do **not** mirror the strategy onto a per-page `@State` field. The `@StorageProp` in PlayerPage is the only mirror needed; settings page reads the VM `@Track` directly.
- Do **not** rely on `aboutToAppear` of `LyricsInterfacePage` for live sync — it is only a load-on-entry, kept for the cross-ability restart case noted in the existing comment. Live sync between dialog and page already runs through the shared VM + AppStorage; the lifecycle reload is a belt-and-braces backup.
- Do **not** change `KaraokeRenderDecision`. The matrix in the file header already matches the spec exactly.
- Do **not** edit the strings in `string.json` for the row label — the spec only changes the **option labels**, which live in the VM array. The row title `karaoke_lyrics_animation_compatibility_strategy` is unchanged.

## Files To Edit (Final List)

1. `entry/src/main/ets/model/LyricsInterfaceModel.ets` — three default-value flips (field, ctor param, `loadFromStorage` fallback).
2. `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` — one default-value flip on `@Track karaokeCompatStrategyIndex`; rewrite the three `karaokeStrategyOptions` entries.
3. `entry/src/main/ets/entryability/EntryAbility.ets` — `persistProp` literal `1` → `0` and the `ss.get(..., 1)` fallback → `0` + comment update.
4. `entry/src/main/ets/pages/PlayerPage.ets` — `@StorageProp` literal default `1` → `0`.
5. `entry/src/main/ets/components/LyricsLineComponent.ets` — `@Prop karaokeStrategyIndex` literal default `1` → `0`.

No new files. No string-resource edits. No KaraokeRenderDecision edits. No PlayerPage layout edits.

## Migration / Backwards Compatibility

`SettingsStore` (Preferences-backed) reads existing user values via `ss.get('lyricsKaraokeCompatStrategy', <default>)`. Users who already chose a strategy keep it. Only fresh installs and never-set caches land on the new default `0 = CURRENT_LINE_ONLY`. The `karaokeStrategyOptions` rewording is display-only; the persisted integer index is unchanged across the rename, so `0/1/2` continue to map to the same render branches.

## Verification (manual against the ten scenarios)

After the edits build cleanly:

- Fresh-install run: open settings → row shows "当前行"; menu shows "当前行 / 扩展全部 / 总是"; the first option is highlighted.
- Open player → lyrics: a song with mixed karaoke lines shows per-word only on lines that have cells (Scenario 1); a song with no karaoke shows plain rendering on every line (Scenario 2).
- Pick "扩展全部" in the dialog: every line of a partially-karaoke song renders per-word; switching to a karaoke-free song collapses them all to plain (Scenarios 3/4).
- Pick "总是": all lines render per-word, including karaoke-free songs (Scenarios 5/6).
- Open settings page after changing in dialog: the row sub-text shows the dialog's choice (Scenario 7). Reverse direction: change in settings, return to player → lyrics already re-rendered (Scenario 8).
- Next song / queue change / auto-advance: per-strategy behaviour re-applies against the new document's `hasAnyKaraoke` (Scenario 10).

## Out of Scope

- Pro-gating (none required by spec20).
- Style of the menu popup beyond the existing `bindMenu` builder.
- Animation tuning of the karaoke wipe itself.
- Adding new strategy values (the enum stays at three entries).
