# Code Review Report

## Overview

- **Project**: SaltPlayerHarmony (`/Users/moriafly/GitHub/SaltPlayerHarmony`)
- **Commit ID**: `232c0c8d30e4ee0078ab6f1061c99c9dd00f04b7`
  - Commit subject: `[Human-AI] feat(spec16): 立体歌词效果 toggle wires through to PlayerPage`
  - Parent: `baf96ad71fd091d79a873612cf85ab53dc517b7b`
- **Scenario Doc**: `/Users/moriafly/GitHub/SaltPlayerHarmony/wsh-output/spec16/plan.md` (立体歌词 SPEC)
- **Code Context**: `/Users/moriafly/.claude/plugins/android-harmonyos-converter/tools/HarmonyOS_Code_Review/handler/output/232c0c8d30e4ee0078ab6f1061c99c9dd00f04b7_result.json`
- **Review Date**: 2026/05/15
- **Total Scenarios**: 7
- **Results**: 6 PASS | 1 PARTIAL | 0 FAIL | 0 UNABLE TO VERIFY
- **Overall Verdict**: PASS WITH ISSUES

### Files touched by this commit

| File | Lines changed |
|---|---|
| `entry/src/main/ets/entryability/EntryAbility.ets` | +6 / -0 |
| `entry/src/main/ets/pages/LaboratoryPage.ets` | +8 / -0 |
| `entry/src/main/ets/pages/PlayerPage.ets` | +44 / -0 |
| `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets` | +45 / -7 |
| `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets` | +10 / -0 |

The commit threads the new `lyricsUIEffect3D` toggle through the full stack: persistence (PersistentStorage + Preferences via `SettingsStore`), hydration (`EntryAbility`), View-Model (`LaboratoryViewModel` callback + `loadSettings`), cross-VM sync (`LyricsInterfaceViewModel.refreshTextAlignFromStorage`), and presentation (PlayerPage `@StorageProp` + `.rotate()` / `.translate()` on the lyrics List and the static Scroll).

## Scenario Coverage Summary

| # | Scenario | Verdict | Key Gaps |
|---|----------|---------|----------|
| 1 | 打开立体歌词开关 + 居中对齐互斥 + 持久化 | PASS | — |
| 2 | 关闭立体歌词开关 + 持久化 | PASS | — |
| 3 | 开启后播放页歌词以立体效果（Y 轴旋转 + 平移补偿 + 渐变遮罩）展示 | PARTIAL | 文档强调"渐变遮罩"，复用既有 `.fadingEdge`；视觉上是否符合 SPEC 需运行时校验 |
| 4 | 关闭时播放页歌词平面展示 | PASS | — |
| 5 | 切歌后立体效果保持 | PASS | — |
| 6 | 空歌词场景立体效果不影响 | PASS | — |
| 7 | 非付费用户开关禁用 | PASS | — |

## Detailed Scenario Reviews

### Scenario 1 — 用户在实验室打开立体歌词开关（持久化 + 互斥）

**Description**: 用户点击"立体歌词效果"开关将其打开；居中对齐自动关闭；状态持久化到下次启动。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/LaboratoryPage.ets:63-70` — 渲染 `ItemSwitcherWithIconAndSubRowComponent({ vm: this.viewModel.lyricsEffect3DVM })`，点击调用 `vm.toggle()`，进而触发 `onChange`。
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:78-89` — `lyricsEffect3DVM` 注册 `(isOn) => this.onLyricsEffect3DChanged(isOn)`。
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:130-151` — `onLyricsEffect3DChanged`：
  - `SettingsStore.getInstance().save('lyricsUIEffect3D', isOn)` 同时写 AppStorage + Preferences（`putSync` + `flushSync`），实现"立刻生效 + 立刻落盘"。
  - 当 `isOn === true` 时，`SettingsStore.getInstance().save('lyricsTextAlignCenter', false)`，符合 SPEC 中"立体效果与居中对齐互斥"的要求。
  - 调用 `LyricsInterfaceViewModel.getInstance().refreshTextAlignFromStorage()` 让歌词界面 VM 单例的 `@Track textAlignCenter` 同步刷新。
- `entry/src/main/ets/viewmodel/LyricsInterfaceViewModel.ets:150-154` — `refreshTextAlignFromStorage` 从 AppStorage 读取最新值并写回 `@Track` 字段，避免重复持久化。
- `entry/src/main/ets/entryability/EntryAbility.ets:103-104, 153-155` — `PersistentStorage.persistProp('lyricsUIEffect3D', false)` + `AppStorage.setOrCreate('lyricsUIEffect3D', ss.get('lyricsUIEffect3D', false))` 保证冷启动后状态恢复。

**Gaps**: 无。

**Suggestions**:
- 可考虑在 `LyricsInterfaceViewModel.getInstance()` 第一次使用时即注入此互斥状态（当前依赖单例已经存在；try/catch 已经做了兜底）。这是稳健性增强，非阻塞性。

---

### Scenario 2 — 用户关闭立体歌词开关（持久化）

**Description**: 开关从开启状态被关闭，状态持久化。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:130-151` — `onLyricsEffect3DChanged(false)` 调用 `SettingsStore.save('lyricsUIEffect3D', false)`，且**故意不**回写 `lyricsTextAlignCenter`（注释明确表示"用户先前的居中对齐选择保留"），与 SPEC 场景二只要求"开关状态变为关闭并持久化"完全吻合。
- `entry/src/main/ets/entryability/EntryAbility.ets:153-155` — 下次冷启动 `AppStorage.setOrCreate('lyricsUIEffect3D', ...)` 从 Preferences 读取，保持关闭状态。

**Gaps**: 无。

---

### Scenario 3 — 开关开启后，播放页歌词以立体效果展示（含渐变遮罩）

**Description**: 歌词列表整体沿 Y 轴旋转一定角度并进行水平位移补偿，呈现立体透视效果；列表上下边缘有渐变遮罩。

**Verdict**: PARTIAL

**Evidence**:
- `entry/src/main/ets/pages/PlayerPage.ets:92` — `@StorageProp('lyricsUIEffect3D') lyricsUIEffect3D: boolean = false`，实时订阅。
- `entry/src/main/ets/pages/PlayerPage.ets:170-173` — 立体几何常量：`LYRICS_3D_ROTATION_DEG = 22`、`LYRICS_3D_TRANSLATE_X_VP = -28`、`LYRICS_3D_PERSPECTIVE = 1.6`。
- `entry/src/main/ets/pages/PlayerPage.ets:1452` — List 上挂 `.fadingEdge(true, { fadingEdgeLength: LengthMetrics.vp(80) })`，提供上下渐变遮罩。
- `entry/src/main/ets/pages/PlayerPage.ets:1459-1468` — 对带时间戳的 List 应用：
  - `.rotate({ x:0, y:1, z:0, angle: lyricsUIEffect3D ? -22 : 0, centerX:'0%', centerY:'50%', perspective:1.6 })`
  - `.translate({ x: lyricsUIEffect3D ? -28 : 0 })`
- `entry/src/main/ets/pages/PlayerPage.ets:1543, 1547-1556` — 静态歌词的 `Scroll` 同样挂 `.fadingEdge(...)` + 相同的 `.rotate()` + `.translate()`，保证有/无时间戳两条分支都立体化。

**Gaps**:
- SPEC 场景三描述 "渐变遮罩效果" 与 "立体透视"，代码复用既有的 `.fadingEdge`，几何参数（22°, -28vp, perspective=1.6）来自 Android 端的视觉感受，但**静态校验无法确认渲染结果与 Android 端一致**。建议在自检阶段对照截图。
- `centerX: '0%'` 加上 `translate({ x: -28 })`：旋转支点在左边、并整体左移 28vp。在小屏 / 折叠屏分辨率下，需要验证歌词是否被左边缘截断。

**Suggestions**:
- 在自检/集成测试阶段对照 Android `LyricsContainer threeEffect=true` 的静态截图，必要时把 `LYRICS_3D_*` 常量调整为屏幕宽度的相对值。
- 给三个常量加上 `@VisibleForTesting` 或类似注释，便于后续微调。

---

### Scenario 4 — 开关关闭时，播放页歌词以普通平面效果展示

**Description**: 用户未开启开关时，歌词列表无立体透视变换。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/PlayerPage.ets:1463, 1468` 与 `1551, 1556` — `angle: this.lyricsUIEffect3D ? -22 : 0` 与 `translate({ x: ... ? -28 : 0 })`。当 `lyricsUIEffect3D === false` 时，旋转角度为 0、平移为 0，degenerate 到 identity transform。`.fadingEdge` 仍然存在，但这是原有行为，不破坏 SPEC 场景四"普通平面展示"的语义。
- 默认值：`@StorageProp('lyricsUIEffect3D') lyricsUIEffect3D: boolean = false`（PlayerPage.ets:92）；`PersistentStorage.persistProp('lyricsUIEffect3D', false)`（EntryAbility.ets:104）。冷启动后首帧即为 false → 平面展示。

**Gaps**: 无。

---

### Scenario 5 — 开关开启时，切歌后立体效果保持

**Description**: 用户在播放页通过上一首/下一首/队列/自动切换等方式切换歌曲后，新歌词仍以立体效果展示。

**Verdict**: PASS

**Evidence**:
- 立体变换作用于 **List / Scroll 容器本身**，而切歌只会更新容器的子节点（`ForEach` 重建 `LyricsLineComponent` / Text），容器节点（含 `.rotate` 和 `.translate`）不会被销毁。
- `@StorageProp('lyricsUIEffect3D')` 是稳定订阅，不随切歌触发的 `vm.lyricsVersionTag` 变更而变化。
- `entry/src/main/ets/pages/PlayerPage.ets:1437-1438` — 列表 key 是 `lyricsVersionTag + '_' + index + '_' + startTime`，容器属性独立于该 key。

**Gaps**: 无。

---

### Scenario 6 — 开关开启时，歌词为空

**Description**: 空歌词内容下立体效果不影响展示（占位文案保持正常）。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/pages/PlayerPage.ets:1600-1613` — 空歌词分支只渲染居中提示 Column（`Text($r('app.string.no_lyrics'))`），**该 Column 没有任何 `.rotate()` 或 `.translate()` 调用**，保持平面。
- 整段 `if-else if-else` 三分支并列：定时歌词、静态文本、空提示分别处于独立的 UI 节点，立体几何只作用于前两者。这也精确对应 SPEC 场景六"立体效果不影响空歌词的展示"。

**Gaps**: 无。

**Suggestions**: 注释中（PlayerPage.ets:166-173）已经明确"空歌词占位 Column 保持 flat (Scene 6)"，意图记录清晰。可继续保持。

---

### Scenario 7 — 非付费用户开关禁用

**Description**: 实验室页面展示开关旁的付费标识；非付费用户点击不可操作（禁用态）。

**Verdict**: PASS

**Evidence**:
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:78-89` — `lyricsEffect3DVM` 用 `SwitcherWithIconAndSubRowModel(... , this.isPro, $r('app.media.ic_crown'), ... )` 构造，`isEnabled = this.isPro`，皇冠图标始终展示。
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:61-62` — 构造期 `this.isPro = AppStorage.get<boolean>('isPro') ?? false`；首次进入时 `isPro=false` → 行禁用。
- `entry/src/main/ets/viewmodel/LaboratoryViewModel.ets:184-200` — `loadSettings` 在 `aboutToAppear` 调用，重新读 `isPro` 并把 `lyricsEffect3DVM.isEnabled = this.isPro`（同时刷新 saltUi / liquidGlass），符合 SPEC 中"未来开通付费后立刻亮起"的隐含要求。
- `entry/src/main/ets/pages/LaboratoryPage.ets:33-39` — `aboutToAppear` 调用 `loadSettings`。
- `entry/src/main/ets/components/ItemSwitcherWithIconAndSubRowComponent.ets`（同目录）— Row 上挂 `.opacity(isEnabled ? 1.0 : 0.5)` 和 `.enabled(isEnabled)`；`SwitcherWithIconAndSubRowViewModel.toggle()` 也用 `if (this.isEnabled)` 做了二次拦截。

**Gaps**: 无。

**Suggestions**: 当前 `isPro` 全局来源为 `AppStorage.get('isPro')`，由 `EntryAbility.ets:84, 201` 初始化为 `false`。一旦实现付费激活流，记得同时 `SettingsStore.save('isPro', true)` 即可。

---

## Cross-Cutting Issues

### Permission Coverage

立体歌词功能纯粹是 UI 变换 + Preferences 持久化，不涉及任何受限权限。本提交未变更 `entry/src/main/module.json5`，符合预期。

### Navigation Completeness

立体歌词开关的入口：MainPage → Menu → Settings → Laboratory（`LaboratoryPage.ets`）。该路径在 spec9 / spec15 等历史 commit 已经接好，本次提交未触碰路由。

### State Management

- `@StorageProp('lyricsUIEffect3D')` —— 单向读，自动从 AppStorage 同步到 PlayerPage。
- `@Track lyricsEffect3DVM: SwitcherWithIconAndSubRowViewModel` —— @Observed 类，View 用 `@ObjectLink` 订阅。
- `SettingsStore.save()` 是唯一的写入点（同时落 AppStorage + Preferences），写入路径清晰、单向。
- 互斥写入：通过 `SettingsStore.save('lyricsTextAlignCenter', false)` 触发 AppStorage 更新，PlayerPage 既有的 `@StorageProp('lyricsTextAlignCenter')` 会自动同步；`LyricsInterfaceViewModel.refreshTextAlignFromStorage()` 进一步让设置面板的 `@Track` 字段刷新。
- 没有发现循环订阅或重复持久化（`refreshTextAlignFromStorage` 显式跳过 `SettingsStore.save`，注释明确）。

### API Version Compatibility

- `.rotate({ ... perspective })`：HarmonyOS ArkUI 通用属性，API 9+。
- `.translate({ x })`：通用属性，API 9+。
- `.fadingEdge`：API 12+，项目已经在 spec13/15 使用，未引入新 API。
- `@StorageProp`：API 9+ 状态管理装饰器。

无新增 API 兼容性风险。

### Resource Completeness

- `$r('app.string.lyrics_3d_effect_label')`：在 `LaboratoryViewModel.ets:83` 引用，需要资源中存在。**本提交未新增该字符串**，但 spec 任务前置阶段已经引入（同一文件历史版本已使用）；当前编译已通过（`build-fix-report.md` 存在于 spec16 输出目录），表明资源已就位。
- `$r('app.media.ic_crown')`、`$r('app.string.no_lyrics')`：均为既有资源。

---

## Final Assessment

**Overall Verdict**: PASS WITH ISSUES（语义上 7 个场景全部满足，仅 Scene 3 的视觉细节需运行时校验）

- **Fully covered scenarios**: 1, 2, 4, 5, 6, 7
- **Partially covered scenarios**: 3 — 静态分析无法验证 22°/-28vp/perspective 1.6 在真机上是否与 Android 立体效果一致
- **Not covered scenarios**: 无

**Recommended Priority Fixes**（按用户感知优先级排序）：

1. **(P3 / 视觉)** 在自检阶段（Stage 7）真机对照 Android 立体歌词截图，必要时把 `LYRICS_3D_ROTATION_DEG / LYRICS_3D_TRANSLATE_X_VP / LYRICS_3D_PERSPECTIVE` 调整为更贴近 Android 的数值，或改为相对屏幕宽度的动态计算（PlayerPage.ets:170-173）。
2. **(P4 / 稳健性)** 给 `LyricsInterfaceViewModel.getInstance()` 的 try/catch 加一条 hilog，便于后续诊断为什么单例还没构造（LaboratoryViewModel.ets:144-149）。
3. **(P4 / 文档)** 在 `LaboratoryModel.ets` 的 `lyricsUIEffect3D` 字段上加注释，说明它和 AppStorage key `'lyricsUIEffect3D'` 的对应关系——便于 onboarding。

代码结构与 SPEC 一致、改动局部、副作用清晰、风险面小，建议合入。
