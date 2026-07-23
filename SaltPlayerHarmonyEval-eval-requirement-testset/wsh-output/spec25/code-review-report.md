# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `c5429812a469cd14341acea93683214c3f678930`
- **Follow-up build-fix commit**: `a8f2b8053d2cf6ab5e2137740c51b6b9b9c5a12b` (WindowType + Marquee attribute-method fixes)
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec25/plan.md`
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/c5429812a469cd14341acea93683214c3f678930_result.json`
- **Review Date**: 2026/05/15
- **Total Scenarios**: 19
- **Results**: 13 PASS | 5 PARTIAL | 0 FAIL | 1 UNABLE TO VERIFY

The commit wires the "悬浮窗状态栏歌词" (floating status-bar lyrics) feature end-to-end:

- View — `entry/src/main/ets/pages/FloatingWindowStatusBarLyricsPage.ets` (rewritten, MVVM-clean) and `entry/src/main/ets/pages/FloatingStatusBarLyricsWindow.ets` (new system-window content page).
- ViewModel — `entry/src/main/ets/viewmodel/FloatingWindowStatusBarLyricsViewModel.ets` (new) — owns the master toggle, persistence, permission gate, and show/hide orchestration.
- Controller / Model — `entry/src/main/ets/model/FloatingStatusBarLyricsController.ets` (new) — owns the system-level window lifecycle, geometry watchers, song-changed reset, and the lyric/sub-line mirror into AppStorage.
- `MiniLyricsController.ets` — exposes `currentSubLine` so the floating window can render translations without widening the listener signature.
- `EntryAbility.ets` — persists & hydrates 7 new sub-setting keys, kicks off scenario-18 cold-start auto-show via `FloatingStatusBarLyricsController.init(...)`, tears down on `onWindowStageDestroy`.
- `main_pages.json` — registers `pages/FloatingStatusBarLyricsWindow` so `setUIContent` resolves.

---

## Scenario Coverage Summary

| #  | Scenario                                                  | Verdict             | Key Gaps |
|----|-----------------------------------------------------------|---------------------|----------|
| 1  | 主开关 ON, 权限未授予 → 提示并保持 OFF                       | PASS                | — |
| 2  | 主开关 ON, 权限已授予 → 创建悬浮窗按默认参数显示              | PASS                | — |
| 3  | 主开关 OFF → 移除悬浮窗                                    | PASS                | — |
| 4  | 实时滚动展示当前歌词 + 跑马灯                              | PASS                | — |
| 5  | 暂停时歌词文本淡出                                         | PARTIAL             | Fade animation only triggers when surrounding visibility/text changes; current binding may not animate on `isPlaying` change alone. |
| 6  | 恢复播放时歌词文本淡入                                      | PARTIAL             | Same fade-binding caveat as Scenario 5. |
| 7  | 左右位置滑块 0%–100% 实时移动                              | PASS                | — |
| 8  | 上下位置滑块 0px–100px 实时移动                            | PARTIAL             | Slider passes a `vp/dp` numeric value but `applyGeometry` multiplies by `densityPixels` again; on a 3× device 100 "px" becomes 300 device px. Behavioral, not a crash. |
| 9  | 宽度滑块 50dp–750dp 实时变化 + 跑马灯触发                  | PASS                | — |
| 10 | 字体大小滑块 8dp–32dp 实时变化                              | PASS                | — |
| 11 | 颜色选择弹窗 → 实时更新文本颜色                              | PASS                | — |
| 12 | 居中对齐开关 ON                                            | PASS                | — |
| 13 | 居中对齐开关 OFF → 左对齐                                  | PASS                | — |
| 14 | 不显示翻译 ON → 仅展示原文                                 | PASS                | — |
| 15 | 不显示翻译 OFF → 展示原文 + 翻译                           | PASS                | — |
| 16 | 在播放界面隐藏 ON → 进入播放页时隐藏歌词                    | PASS                | — |
| 17 | 在播放界面隐藏 ON → 离开播放页时恢复显示                    | PASS                | — |
| 18 | 服务启动时按开关状态自动恢复悬浮窗                          | PASS                | — |
| 19 | 无歌词歌曲 → 悬浮窗不展示文本                              | UNABLE TO VERIFY    | Logic correct on `hasLyrics=false` but cold-start path needs runtime to flip the flag after the lyrics load resolves. |

---

## Detailed Scenario Reviews

### Scenario 1: 用户打开主开关但未授予悬浮窗权限

**Description**: 用户点击主开关 (OFF→ON)；系统未授予悬浮窗权限；应弹出提示、引导授权，开关保持 OFF。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/FloatingWindowStatusBarLyricsViewModel.ets:56-70` — `onMasterToggleChanged(true)` awaits `FloatingWindowPermission.ensurePermission()`; on denial it reverts `this.master = false` and shows the `no_floating_window_permission` toast.
- `entry/src/main/ets/model/FloatingWindowPermission.ets:63-101` — `ensurePermission()` checks via `abilityAccessCtrl`, then launches the system settings page through `startAbility(want)` and re-probes.
- Permission `ohos.permission.SYSTEM_FLOAT_WINDOW` is declared in `entry/src/main/module.json5:51-60`.
- String `app.string.no_floating_window_permission` exists at `string.json:232`.

**Gaps**: none.

---

### Scenario 2: 用户打开主开关，已授权 → 悬浮窗显示

**Description**: 主开关切到 ON；权限已授；按默认参数 (0%, 0px, 150dp, 14dp, 0xFF0470E6, 左对齐) 创建悬浮窗；正在播放则立即展示当前行，未播放则保留窗口但不可见歌词。

**Verdict**: PASS

**Evidence**:
- `FloatingWindowStatusBarLyricsViewModel.ets:73-83` — after `ensurePermission()` returns true, calls `SettingsStore.save('floatingWindowStatusBarLyrics', true)` then `FloatingStatusBarLyricsController.show()`.
- `FloatingStatusBarLyricsController.ets:93-134` — `show()` creates the window via `window.createWindow({ ctx, name, windowType: WindowType.TYPE_SYSTEM_ALERT })` (post-fix in a8f2b80), loads `pages/FloatingStatusBarLyricsWindow`, sets transparent BG, calls `applyGeometry()`, then `showWindow()`.
- Defaults are seeded in `EntryAbility.ets:131-141`: `PersistentStorage.persistProp('floatingWindowSbLrLeftRightPercent', 0)`, `... UpDownPx, 0`, `... WidthDp, 150`, `... FontSizeDp, 14`, `... Color, 0xFF0470E6`, `... CenterAlign, false`, `... HideOnPlayer, false`. The shared `statusBarLyricsNotShowTranslation` defaults to false at `EntryAbility.ets:126`.
- "Window exists but lyric invisible when not playing" — `FloatingStatusBarLyricsWindow.ets:30-67`: gated by `shouldRenderText()` (returns `hasLyrics && line.length > 0`) and the fade container's `opacity(this.isPlaying ? 1 : 0)`.

**Gaps**: none.

---

### Scenario 3: 用户关闭主开关

**Description**: 主开关 ON→OFF；悬浮窗移除。

**Verdict**: PASS

**Evidence**:
- `FloatingWindowStatusBarLyricsViewModel.ets:78-82` — `onMasterToggleChanged(false)` saves the flag then calls `FloatingStatusBarLyricsController.hide()`.
- `FloatingStatusBarLyricsController.ets:137-150` — `hide()` stops geometry watchers and calls `win.destroyWindow()`.

**Gaps**: none.

---

### Scenario 4: 播放时实时滚动展示当前歌词 + 跑马灯溢出滚动

**Description**: 随播放进度推进当前行变化时悬浮窗实时更新；超出宽度时跑马灯滚动，未超出则静态展示。

**Verdict**: PASS

**Evidence**:
- `MiniLyricsController.ets:168-191` — 200ms tick updates `currentLine` and `_currentSubLine`; calls `notify()` on change.
- `FloatingStatusBarLyricsController.ets:60-67` — listener mirrors `(line, has, subLine)` into the AppStorage keys the window page reads (`floatingWindowSbLrLine`, `floatingWindowSbLrHasLyrics`, `floatingWindowSbLrSubLine`).
- `FloatingStatusBarLyricsWindow.ets:38-47` — renders `Marquee({ src: this.line, start: this.isPlaying, step: 6, loop: -1, fromStart: false })`; post-fix in a8f2b80 the `fontSize`/`fontColor` moved to attribute methods (`.fontSize(this.fontSizeDp).fontColor(this.colorArgb)`). Marquee natively static-displays when the text fits and scrolls when it overflows, matching the spec.

**Gaps**: none.

---

### Scenario 5: 暂停时歌词文本淡出

**Description**: 暂停后悬浮窗保留，仅歌词文本以淡出动画隐藏。

**Verdict**: PARTIAL

**Evidence**:
- `FloatingStatusBarLyricsWindow.ets:32-61` — wraps the lyric text in a `Column().opacity(this.isPlaying ? 1 : 0).animation({ duration: 300, curve: Curve.EaseInOut })`. `isPlaying` is published by `AudioPlayerService` (`AudioPlayerService.ets:696, 722, 739, …`).

**Gaps**:
- In ArkTS, `.animation(...)` declaratively animates property changes that happen **after** the animation modifier is applied to the component on the next frame. With `@StorageProp` change driving `opacity`, the rebuild rebuilds the whole subtree, and whether the opacity transition is smoothly animated (rather than snapped) is not strictly guaranteed in every SDK rev. The implementation is broadly correct but follows the legacy implicit-animation pattern; spec wording "淡出动画" is satisfied if the runtime triggers the implicit animation correctly.

**Suggestions**:
- For deterministic transitions, wrap the opacity change in `animateTo({ duration: 300, curve: Curve.EaseInOut }, () => { this.opacityValue = 0 })` driven from a `@Watch('isPlaying')` callback, or use `transition` modifiers; only needed if QA observes a snap rather than a fade.

---

### Scenario 6: 恢复播放时歌词文本淡入

**Description**: 恢复播放时歌词文本以淡入动画显示。

**Verdict**: PARTIAL

**Evidence**: same code path as Scenario 5 — `opacity(this.isPlaying ? 1 : 0)` with `.animation({ duration: 300 })` at `FloatingStatusBarLyricsWindow.ets:59-60`.

**Gaps**: same implicit-animation caveat.

**Suggestions**: same as Scenario 5.

---

### Scenario 7: 调整左右位置 0%–100%

**Description**: 拖动左右位置滑块；悬浮窗水平实时移动；持久化保存。

**Verdict**: PASS

**Evidence**:
- Slider range `LR_MIN=0, LR_MAX=100, step=1` at `FloatingWindowStatusBarLyricsViewModel.ets:38-39`, bound in `FloatingWindowStatusBarLyricsPage.ets:169-176`.
- `onLeftRightPercentChanged` persists via `SettingsStore.save('floatingWindowSbLrLeftRightPercent', v)` (`FloatingWindowStatusBarLyricsViewModel.ets:86-89`), which also mirrors into AppStorage.
- The 250 ms `setInterval` geometry watcher (`FloatingStatusBarLyricsController.ets:217-229`) detects the AppStorage change and calls `applyGeometry()` which computes `xPx = (screenW - widthPx) * (lrPercent/100)` and `moveWindowTo(xPx, yPx)`.
- Persistence on cold start: `EntryAbility.ets:134, 202` (persistProp + restore).

**Gaps**: none. The 250 ms polling sounds slow but for a drag it's perceptibly continuous; the spec says "实时移动", which this satisfies.

---

### Scenario 8: 调整上下位置 0px–100px

**Description**: 拖动上下位置滑块；范围 0px–100px；悬浮窗垂直实时偏移；持久化保存。

**Verdict**: PARTIAL

**Evidence**:
- Slider `UD_MIN=0, UD_MAX=100, step=1`, label `app.string.up_and_down_position`, bound in `FloatingWindowStatusBarLyricsPage.ets:184-191`.
- Persisted via `onUpDownPxChanged` → `SettingsStore.save('floatingWindowSbLrUpDownPx', v)` (`FloatingWindowStatusBarLyricsViewModel.ets:91-94`).
- Applied in `FloatingStatusBarLyricsController.ets:170-180`: `const upDownPx = AppStorage.get<number>('floatingWindowSbLrUpDownPx') ?? 0; const yPx = Math.round(upDownPx * density)`.

**Gaps**:
- The setting name and spec wording say "0px..100px", but `applyGeometry()` multiplies it by `display.getDefaultDisplaySync().densityPixels` (`yPx = upDownPx * density`). `display.densityPixels` is the px-per-vp scale (≈3 on a typical phone). The result is the slider's numeric value is interpreted as vp/dp, not px as the spec states. The behavior is otherwise correct — the window moves vertically as the slider moves — but a value of "100" lands at ~300 real device pixels on a high-density screen.

**Suggestions**:
- If the spec must be honored literally, change `yPx = Math.round(upDownPx)` (treat the value as already in px) and rename the AppStorage key / slider label accordingly. If the project prefers dp semantics, update the spec & UI label to "0dp–100dp" — the current code already behaves as dp.

---

### Scenario 9: 调整宽度 50dp–750dp，跑马灯按需触发

**Description**: 宽度滑块 50dp–750dp 实时变化；超出新宽度则跑马灯。

**Verdict**: PASS

**Evidence**:
- Range `W_MIN=50, W_MAX=750` (`FloatingWindowStatusBarLyricsViewModel.ets:42-43`), bound in `FloatingWindowStatusBarLyricsPage.ets:199-206`.
- Persisted via `onWidthDpChanged` → `SettingsStore.save('floatingWindowSbLrWidthDp', v)`.
- `applyGeometry()` resizes the window: `widthPx = Math.round(widthDp * density); win.resize(widthPx, heightPx)` (`FloatingStatusBarLyricsController.ets:168-186`).
- Marquee width follows the same value: `.width(\`${this.widthDp}vp\`)` (`FloatingStatusBarLyricsWindow.ets:47`). Marquee's built-in behavior takes care of "static when fits, scrolls when overflows".

**Gaps**: none.

---

### Scenario 10: 调整字体大小 8dp–32dp

**Description**: 拖动字体大小滑块 8dp–32dp；悬浮窗字体实时变化；持久化保存。

**Verdict**: PASS

**Evidence**:
- Range `F_MIN=8, F_MAX=32, step=0.5` (`FloatingWindowStatusBarLyricsViewModel.ets:44-45`), bound in `FloatingWindowStatusBarLyricsPage.ets:220-227`.
- Persisted via `onFontSizeDpChanged` → `SettingsStore.save('floatingWindowSbLrFontSizeDp', v)`.
- Marquee picks up `.fontSize(this.fontSizeDp)` (post-fix in a8f2b80) and the sub-line `Text` uses `this.fontSizeDp * 0.85` (`FloatingStatusBarLyricsWindow.ets:45, 51`).
- Window height auto-scales: `heightPx = Math.round((fontSizeDp * 2 + 20) * density)` (`FloatingStatusBarLyricsController.ets:178`).

**Gaps**: none.

---

### Scenario 11: 选择颜色弹窗 → 实时更新文本颜色

**Description**: 点击 "选择颜色" 弹出颜色选择弹窗（预设颜色列表）；选择并确认后悬浮窗文本颜色实时更新；持久化保存。

**Verdict**: PASS

**Evidence**:
- Color palette of 11 preset colors at `FloatingWindowStatusBarLyricsPage.ets:49-53`.
- Dialog overlay built with `Stack` + conditional `ColorPickerDialogOverlay()` at `FloatingWindowStatusBarLyricsPage.ets:88-90, 388-460`.
- Confirm button calls `this.vm.onColorChanged(this.pendingColor)` (`FloatingWindowStatusBarLyricsPage.ets:441-444`).
- `onColorChanged(v)` → `SettingsStore.save('floatingWindowSbLrColor', v)`; window page binds `@StorageProp('floatingWindowSbLrColor')` and applies it to `Marquee.fontColor(this.colorArgb)` and the sub-line `Text.fontColor(this.colorArgb)` (`FloatingStatusBarLyricsWindow.ets:21, 46, 52`).

**Gaps**: none.

---

### Scenario 12: 居中对齐开关 ON

**Description**: 打开居中对齐开关；悬浮窗文本从左对齐切换为居中；持久化保存。

**Verdict**: PASS

**Evidence**:
- Toggle row at `FloatingWindowStatusBarLyricsPage.ets:267-290`, bound to `this.vm.centerAlign`; persisted via `onCenterAlignChanged` → `SettingsStore.save('floatingWindowSbLrCenterAlign', v)`.
- Applied at `FloatingStatusBarLyricsWindow.ets:54, 65`: subline `.textAlign(this.centerAlign ? TextAlign.Center : TextAlign.Start)` and the column's `alignItems(this.centerAlign ? HorizontalAlign.Center : HorizontalAlign.Start)`.

**Gaps**: none. The Marquee itself doesn't expose a per-line text-align (it scrolls), but the `Column.alignItems` honors centering for the marquee's container; combined with `.width(${this.widthDp}vp)` the marquee occupies the same width either way, so visually centering shows up only when the line is short enough to not scroll — which is the spec-expected behavior.

---

### Scenario 13: 居中对齐开关 OFF → 左对齐

**Description**: 关闭居中对齐开关；恢复左对齐；持久化保存。

**Verdict**: PASS

**Evidence**: same code path as Scenario 12 with `centerAlign = false`; `HorizontalAlign.Start` and `TextAlign.Start` are applied.

**Gaps**: none.

---

### Scenario 14: 不显示翻译 ON → 仅展示原文

**Description**: 打开 "状态栏歌词不显示翻译" 开关；当前歌曲有翻译时，悬浮窗仅展示原文第一行。

**Verdict**: PASS

**Evidence**:
- Toggle bound to `this.vm.notShowTranslation` (`FloatingWindowStatusBarLyricsPage.ets:298-317`); persisted via `onNotShowTranslationChanged` → `SettingsStore.save('statusBarLyricsNotShowTranslation', v)` (deliberately shared with the system-level status-bar setting per plan §3.2; the key is also persisted at `EntryAbility.ets:126`).
- Translation render gate at `FloatingStatusBarLyricsWindow.ets:23, 49-57`: `if (!this.notShowTranslation && this.subLine.length > 0) { Text(this.subLine)... }`. When `notShowTranslation = true` the sub-line `Text` is not rendered, leaving only the Marquee with the main lyric.

**Gaps**: none.

---

### Scenario 15: 不显示翻译 OFF → 展示原文 + 翻译

**Description**: 关闭 "不显示翻译" 开关；当前歌曲有翻译时，悬浮窗同时展示原文 + 翻译。

**Verdict**: PASS

**Evidence**:
- Same toggle as Scenario 14. When `notShowTranslation = false` and `this.subLine.length > 0`, the sub-line Text renders below the Marquee (`FloatingStatusBarLyricsWindow.ets:49-57`).
- `MiniLyricsController.ets:181` writes `_currentSubLine = doc.lines[idx].subText`; `FloatingStatusBarLyricsController.ets:62-66` mirrors it into `floatingWindowSbLrSubLine` on every lyric tick.

**Gaps**: none.

---

### Scenario 16: 在播放界面隐藏 ON → 进入播放页时隐藏

**Description**: 打开 "在播放界面隐藏" 开关；用户切换到播放页面时悬浮窗歌词隐藏。

**Verdict**: PASS

**Evidence**:
- Toggle at `FloatingWindowStatusBarLyricsPage.ets:328-347`, bound to `this.vm.hideOnPlayer`; persisted via `onHideOnPlayerChanged` → `SettingsStore.save('floatingWindowSbLrHideOnPlayer', v)`.
- `playerPageVisible` is published by `ScreenWakeViewModel.setVisible(...)` at `entry/src/main/ets/viewmodel/ScreenWakeViewModel.ets:59`.
- Visibility gate at `FloatingStatusBarLyricsWindow.ets:24, 66, 76-78`: `isHiddenByPlayer() = hideOnPlayer && playerPageVisible`; applied to `.visibility(... ? Visibility.Hidden : Visibility.Visible)` on the root `Column`. The spec wording "悬浮窗歌词区域停止显示歌词" (the lyric area stops displaying lyrics) is satisfied — the window stays alive but its content is hidden.

**Gaps**: none.

---

### Scenario 17: 离开播放页时悬浮窗歌词恢复显示

**Description**: 在播放界面隐藏 ON 状态下离开播放页面，悬浮窗歌词恢复显示。

**Verdict**: PASS

**Evidence**: same path as Scenario 16 — `playerPageVisible` flips back to `false` on `ScreenWakeViewModel.setVisible(false)`, `isHiddenByPlayer()` returns false, `.visibility(Visibility.Visible)` restores rendering.

**Gaps**: none.

---

### Scenario 18: 服务启动时自动恢复悬浮窗

**Description**: 应用音乐播放服务启动时，读取持久化开关状态；若 ON 则自动按已保存设置参数创建悬浮窗。

**Verdict**: PASS

**Evidence**:
- All 8 sub-setting keys persisted with `PersistentStorage.persistProp(...)` at `EntryAbility.ets:129-141` and hydrated from `SettingsStore` at `EntryAbility.ets:198-215`.
- `FloatingStatusBarLyricsController.init(ctx)` is called after `MiniLyricsController.getInstance().init()` and after persistence hydration (`EntryAbility.ets:400-405`).
- Inside `init()` (`FloatingStatusBarLyricsController.ets:50-90`): reads `AppStorage.get<boolean>('floatingWindowStatusBarLyrics')`; if true, calls `this.show()`. `applyGeometry()` reads the persisted geometry keys before `showWindow()`.

**Gaps**: none.

---

### Scenario 19: 播放无歌词的歌曲时悬浮窗不展示文本

**Description**: 当前播放歌曲无歌词时，悬浮窗保持空白；切到有歌词的歌曲恢复展示。

**Verdict**: UNABLE TO VERIFY (the code path is correct, but runtime confirmation is needed)

**Evidence**:
- `FloatingStatusBarLyricsWindow.shouldRenderText() = this.hasLyrics && this.line.length > 0` (`FloatingStatusBarLyricsWindow.ets:71-73`) — when false, the lyric subtree is not rendered.
- `MiniLyricsController.tickOnce()` sets `newHasLyrics = doc.isScrollable && doc.lines.length > 0` (`MiniLyricsController.ets:174`); a static-only or empty lyrics file yields `hasLyrics = false`.
- `FloatingStatusBarLyricsController` listener mirrors `has` into `floatingWindowSbLrHasLyrics` (`FloatingStatusBarLyricsController.ets:60-66`).
- `songChangedListener` resets `floatingWindowSbLrLine = ''` and `floatingWindowSbLrSubLine = ''` immediately on song change (`FloatingStatusBarLyricsController.ets:70-75`).

**Gaps**: requires a real device + a no-lyric track to confirm the AppStorage path actually flips on the first lyric-load resolve; the static logic is sound.

**Suggestions**: covered by integration-test pass.

---

## Cross-Cutting Issues

### Permission Coverage
- `ohos.permission.SYSTEM_FLOAT_WINDOW` is declared in `entry/src/main/module.json5:51-60` and matches the constant `FLOATING_WINDOW_PERM` in `FloatingWindowPermission.ets:10`. The reason string `floating_window_permission_reason` is declared in `string.json`.

### Navigation Completeness
- `LyricsSettingsPage.ets:177` pushes `{ name: 'FloatingWindowStatusBarLyricsPage' }`.
- `MainPage.ets:43, 928-929` imports and renders the page in the central `NavDestination` switch — navigation is complete.

### State Management
- The ViewModel uses `@Observed` + `@Track` per HMOS V2 conventions; the Page holds it as `@State` and reads through `this.vm.xxx`. Persisted state lives in AppStorage; the float-window page binds via `@StorageProp` so it reacts live across the system-level window boundary.
- The 250 ms `setInterval` geometry watcher (`FloatingStatusBarLyricsController.startGeometryWatchers`) is a reasonable workaround since `@StorageLink` cannot bind to `window.resize` / `moveWindowTo` directly. The watcher is correctly torn down in `hide()` and `destroy()`.
- Singleton lifecycle: `FloatingStatusBarLyricsController` is correctly `init`-once / `destroy`-on-stage-destroy.

### API Compatibility
- `window.WindowType.TYPE_SYSTEM_ALERT` is the post-fix enum value (originally `TYPE_SYSTEM_FLOAT`, replaced in `a8f2b8053d`). `TYPE_SYSTEM_ALERT` is the standard system-window type for an overlay backed by `SYSTEM_FLOAT_WINDOW` permission on current HMOS SDKs.
- `Marquee` now uses attribute-method form `.fontSize(...).fontColor(...)` instead of options (also fixed in `a8f2b8053d`), aligning with current ArkUI typing rules.
- `setUIContent('pages/FloatingStatusBarLyricsWindow')` matches the entry registered in `main_pages.json`.
- `setWindowTouchable(false)` is best-effort and wrapped in try/catch, so older SDKs don't break.

### Resource Completeness
All UI strings referenced are present in `entry/src/main/resources/base/element/string.json`:
- `floating_window_status_bar_lyrics`, `floating_window_status_bar_lyrics_tip`, `position`, `size`, `width`, `left_and_right_position`, `up_and_down_position`, `choose_color`, `lyrics_text_left_aligned`, `lyrics_text_left_aligned_info`, `status_bar_lyrics_not_show_translation`, `hide_on_playback_screen`, `no_floating_window_permission`, `cancel`, `confirm`, plus `app.media.ic_warning`, `app.color.warning_icon_color`, `app.color.warning_background`, `app.color.salt_color_high_light`, `app.color.salt_color_white`, `app.color.colorSubTextForeground`, `app.color.colorPageBackground`, `app.color.colorItemBackgroundHalfTransparency`, `app.color.colorTextForeground` (verified).

---

## Final Assessment

**Overall Verdict**: **PASS WITH ISSUES** — the feature is wired end-to-end and 13 of 19 scenarios are fully covered. The remaining 5 PARTIAL items and 1 UNABLE TO VERIFY all fall into "behavioral nuances to confirm on device" rather than "missing implementation".

**Fully covered scenarios**: 1, 2, 3, 4, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18.

**Partially covered scenarios**:
- **5 / 6 — fade-in/fade-out on play/pause**: the implementation uses ArkUI implicit `.animation()` driven by `@StorageProp('isPlaying')` change. May render as a snap rather than a smooth fade on some SDK revs; if QA confirms a snap, switch to explicit `animateTo` from a `@Watch('isPlaying')` callback.
- **8 — up-and-down position units**: the slider value is treated as vp/dp (multiplied by `densityPixels`) but the spec says "0px–100px". Behavior is otherwise functional; either rename spec to dp or drop the density multiplier and treat the value as raw px.

**Not covered scenarios**: none.

**Unable to verify**:
- **19** — no-lyric track empty rendering: logic is sound; needs a runtime check on a real device.

**Recommended Priority Fixes** (highest user impact first):
1. Resolve the px-vs-dp ambiguity in Scenario 8 — either update the spec to say "0dp–100dp" (matches current code) or remove the `* density` factor in `FloatingStatusBarLyricsController.applyGeometry()` (matches the spec wording).
2. If runtime testing shows a snap rather than a fade in Scenarios 5 / 6, switch the play/pause opacity transition to an explicit `animateTo` block triggered by `@Watch('isPlaying')`.
3. Smoke-test Scenario 19 on a device with both a no-lyric MP3 and an LRC track to confirm the empty rendering switches correctly.
4. (Optional, nice-to-have) The geometry watcher polls every 250 ms with three `AppStorage.get` calls; consider an event-driven `@Watch` on each key inside the controller via a stub `@Observed` proxy if perceived lag during slider drag is reported.
