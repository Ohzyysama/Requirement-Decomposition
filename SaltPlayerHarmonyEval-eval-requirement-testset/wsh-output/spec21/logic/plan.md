# SPEC21 — 在列表中显示歌曲文件名 实现计划

## 0. Spec 概览

设置 → 用户界面 → 歌曲列表，新增（已存在 UI 但渲染未接通）"在列表中显示歌曲文件名" 开关，默认关闭。
- 关闭：歌曲列表主文本显示元数据 `title`（含已有的 `.format` 后缀逻辑，行为不变）。
- 打开：歌曲列表主文本显示该曲实际存储路径最后一段（含扩展名），如 `/storage/music/周杰伦 - 晴天.flac` → 显示 `周杰伦 - 晴天.flac`。
- 设置持久化；打开/关闭对所有已挂载的歌曲列表（歌曲页 / 歌单详情 / 专辑详情 / 艺术家详情 / 文件夹详情 / 文件夹路径 / 全局搜索 / 歌单内搜索）即时生效。

## 1. 现状盘点（Ground Truth）

仓库已经把开关的"上半部分"接好了，但渲染端 `SongItemComponent` 的主文本仍然只看 `title`：

- 持久化 + AppStorage 引导：`entry/src/main/ets/entryability/EntryAbility.ets`
  - L95：`PersistentStorage.persistProp('displaySongFileName', false)`
  - L147：`AppStorage.setOrCreate('displaySongFileName', ss.get('displaySongFileName', false) as boolean)`
- 设置页 UI：`entry/src/main/ets/pages/UserInterfacePage.ets` L423-442 已包含开关，绑定 `vm.displaySongFileNameVM`。
- 设置写入：`entry/src/main/ets/viewmodel/UserInterfaceViewModel.ets` L121-124
  - 回调写 `AppStorage.setOrCreate<boolean>('displaySongFileName', val)` + `SettingsStore.save`。
- Model 默认值：`entry/src/main/ets/model/UserInterfaceModel.ets` L26-27（false）。
- 排序对话框已经透传该 flag（仅做"互斥置灰文件名相关排序"用途，与本 spec 不冲突）：
  - `entry/src/main/ets/viewmodel/MainPageViewModel.ets` L98、L517-518
  - `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets` L53、L156-157
  - `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets` L49、L314-315
  - `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets` L66、L209-210
  - `entry/src/main/ets/viewmodel/SongSortDialogViewModel.ets` L12 ……
  - `entry/src/main/ets/components/SongSortDialogComponent.ets` L16、L97
- 渲染端：`entry/src/main/ets/components/SongItemComponent.ets` L114 调用 `viewModel.getDisplayTitle()`
  - `entry/src/main/ets/viewmodel/SongItemViewModel.ets` L109-114 当前只接 `title`/`format`。

**关键空缺 / Gap**

1. `SongItemViewModel` 既没有 `displayFileName` 标志位，也拿不到文件名所需的 `path` 用来推导显示文本（路径字段是 `SongInfoData.path`，目前已从 DB / 扫描入库，URI 形态，带 `file://` 前缀，可能 URL 编码）。`getDisplayTitle()` 完全忽略 `path`。
2. `SongItemComponent` 使用方在各页面 (`MainPage`, `AlbumContentPage`, `ArtistContentPage`, `FolderContentPage`, `FolderPathPage`, `PlaylistContentPage`, `PlaylistSearchPage`, `SearchAllSongsPage`) 通过 `SongItemViewModel.create(song, {...})` 工厂构造时，options 没有 `displaySongFileName` 字段。
3. `MainPage` 已有 `displaySongCover` → VM 的 `@StorageProp` + `@Watch` 桥，但没有同款 `displaySongFileName` 桥；ArtistContent/Album/FolderContent/Playlist 等同款桥也缺位（除排序对话框互斥逻辑外，没有把 `displaySongFileName` 推到 SongItem）。
4. Artist 页面缓存了 `SongItemViewModel` 实例（`ArtistContentViewModel.songs`），需要在桥更新时 walk + `reload`，沿用 `setDisplaySongCoverInList` 的成熟模板。
5. 部分页面（AlbumContentPage、FolderPathPage、ArtistContentPage、SearchAllSongsPage、PlaylistSearchPage、PlaylistContentPage、FolderContentPage）当前在 `SongItemViewModel.create` 的 options 没有透传 `displaySongCoverInList`、`displaySongFileNameInList`、`displayAddToPlayNextInList` 中本 spec 真正需要的 `displaySongFileName`；本 spec 只新增 `displayFileName` 维度，其他维度保留各自现状（不在本 spec 范围）。

## 2. MVVM 角色边界

- **Model**：`SongInfoData` 已有 `path`（URI 形态，来自扫描入库写入 DB）。本 spec 无需改 schema。新增一个纯函数工具 `fileNameFromPath(path: string)`：从 `path` 最末段提取文件名（含扩展名），并尽力 `decodeURIComponent` 以正确显示中文。该工具放在 `SongItemModel.ets` 中作为模块级 helper（与 `SongInfoData` 同文件），避免引入新文件。
- **ViewModel (SongItemViewModel)**：新增 `@Track public displayFileName: boolean = false`，由各 List 页 ViewModel 创建时传入。修改 `getDisplayTitle()`：
  - 若 `displayFileName === true` 且 `path` 非空：返回 `fileNameFromPath(path)`。
  - 否则保留现有 `${title}.${format.toLowerCase()}` / 纯 `title` 行为。
  - `path` 为空（保护性）时回退 `title`。
- **ViewModel (各 List 页 VM)**：每个挂载歌曲列表的 ViewModel 持有一个 `@Track public displaySongFileNameInList: boolean`（多数页面已有，作为同步 sort dialog 用途的字段），并补齐 `setDisplaySongFileNameInList(value)` 方法，作为唯一 writer/通知点。
  - `MainPageViewModel`：补 setter；`displaySongFileNameInList` 字段已在 L98，但当前默认 `false`，将其按 `AlbumContent` 模式改为从 AppStorage 拉初值 `AppStorage.get<boolean>('displaySongFileName') ?? false`。
  - `AlbumContentViewModel`、`ArtistContentViewModel`、`FolderContentPageViewModel`（已有字段，确认/补齐 setter）、`FolderPathViewModel`、`PlaylistContentViewModel`（已有字段，补齐 setter）、`PlaylistSearchViewModel`（已有字段，补齐 setter）、`SearchAllSongsViewModel`：统一加：
    ```
    @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)
    setDisplaySongFileNameInList(value: boolean): void {
      if (this.displaySongFileNameInList === value) return
      this.displaySongFileNameInList = value
      // 仅 ArtistContentViewModel 需要额外 walk + reload，对齐其 setDisplaySongCoverInList 实现
    }
    ```
  - `ArtistContentViewModel.setDisplaySongFileNameInList` 需要 walk `this.songs` 写每个 SongItemViewModel 的 `displayFileName`，并 `this.songDataSource.reload(Array.from(this.songs))`，沿用现有 `setDisplaySongCoverInList`（L199-206）的成熟模板。
  - `ArtistContentViewModel.loadArtistData` 内构造 SongItemViewModel 时（L165-172），同步赋 `vm.displayFileName = this.displaySongFileNameInList`，保证首屏正确。
- **Page**：每个挂载歌曲列表的页面 (View) 增加 `@StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged') storedDisplaySongFileName: boolean = false`，并在 watch 回调里转发到 ViewModel。这一层是"Page 桥"，与 `displaySongCover` 现有桥成对存在，不引入新的 owner，不在 Page 直接操作业务状态。
- **DataSource**：现有 `SongLazyDataSource` / `AlbumContentLazyDataSource` / `FolderContentLazyDataSource` 等不动；当显示偏好变化时 LazyForEach 会因 `SongItemViewModel` 重建（每次 `LazyForEach` 重渲染都 `SongItemViewModel.create(song, {...})`）而自然刷新；Artist 页因缓存 VM 实例需要显式 reload，已由 setter walk 处理。
- **OS 系统设置侧 owner（@StorageProp / SettingsStore）**：保持 `UserInterfaceViewModel.displaySongFileNameVM` 回调内的"AppStorage 写 + SettingsStore.save"为唯一持久化路径，不在任何 Page / List VM 直接调用 SettingsStore，对齐 `displaySongCover` 体例。

owner 边界明确：写者 = `UserInterfaceViewModel` 回调；读者 = AppStorage('displaySongFileName')；中继 = 各页面 @StorageProp + Watch；下游 = ListVM `setDisplaySongFileNameInList` → 透传给 `SongItemViewModel.displayFileName` → `SongItemComponent` 读取。

不重复持久化、不引入镜像状态、不依赖 `aboutToAppear` 做实时同步、不把渲染开关下沉到 Model。

## 3. 文件名提取约定

`fileNameFromPath(path: string): string`：
- 若 `path` 为空，返回 ''（调用方据此回退到 title）。
- 取 `path.lastIndexOf('/')` 之后的子串；若无 `/` 直接整串。
- 对结果尝试 `decodeURIComponent`；失败（如包含残缺 % 序列）则返回原文。
- 不再去扩展名（spec 场景四要求"完整显示，不去除扩展名部分"）。

## 4. 触达文件清单

实际改动文件：

1. `entry/src/main/ets/model/SongItemModel.ets`
   - 新增导出 `export function fileNameFromPath(path?: string | undefined | null): string`。
2. `entry/src/main/ets/viewmodel/SongItemViewModel.ets`
   - 新增 `@Track public displayFileName: boolean = false`。
   - `getDisplayTitle()`：按 §2 规则切换。
   - `SongItemViewModelOptions` 增加可选 `displayFileName?: boolean`。
   - 静态 `create()` 内透传 `options.displayFileName`。
3. `entry/src/main/ets/viewmodel/MainPageViewModel.ets`
   - `displaySongFileNameInList` 初值改为 `(AppStorage.get<boolean>('displaySongFileName') ?? false)`。
   - 新增 `setDisplaySongFileNameInList(value: boolean)`（与 `setDisplaySongCoverInList` 同体例）。
4. `entry/src/main/ets/pages/main/MainPage.ets`
   - 新增 `@StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged') storedDisplaySongFileName: boolean = false` 与 `onDisplaySongFileNameChanged()`，调用 `this.vm.setDisplaySongFileNameInList(...)`。
   - 在 L1174 `SongItemViewModel.create` 的 options 内补 `displayFileName: this.vm.displaySongFileNameInList`。
5. `entry/src/main/ets/viewmodel/AlbumContentViewModel.ets`
   - 新增 `@Track displaySongFileNameInList` + setter（参考 `displaySongCoverInList` 模板）。
6. `entry/src/main/ets/pages/AlbumContentPage.ets`
   - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
   - L137 `SongItemViewModel.create` options 内补 `displayFileName: this.viewModel.displaySongFileNameInList`。
7. `entry/src/main/ets/viewmodel/ArtistContentViewModel.ets`
   - 新增字段 + `setDisplaySongFileNameInList`（walk songs + reload，对齐 L199-206 现有 `setDisplaySongCoverInList`）。
   - `loadArtistData` 内构造 `SongItemViewModel` 时同步 `vm.displayFileName = this.displaySongFileNameInList`。
8. `entry/src/main/ets/pages/ArtistContentPage.ets`
   - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
   - L155 `SongItemViewModel.create` options 内补 `displayFileName: this.viewModel.displaySongFileNameInList`。
9. `entry/src/main/ets/viewmodel/FolderContentPageViewModel.ets`
   - 字段已存在，将默认改为 `AppStorage.get<boolean>('displaySongFileName') ?? false`，新增 `setDisplaySongFileNameInList`。
10. `entry/src/main/ets/pages/FolderContentPage.ets`
    - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
    - L337 `SongItemViewModel.create` options 内补 `displayFileName`.
11. `entry/src/main/ets/viewmodel/FolderPathViewModel.ets`
    - 新增字段 + setter；在 `createSongItemViewModel` 内补 `options.displayFileName` 默认。
12. `entry/src/main/ets/pages/FolderPathPage.ets`
    - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
    - L60 `SongItemComponent` 调用处 options 补 `displayFileName: this.viewModel.displaySongFileNameInList`。
13. `entry/src/main/ets/viewmodel/PlaylistContentViewModel.ets`
    - 字段已存在；新增 `setDisplaySongFileNameInList`。
14. `entry/src/main/ets/pages/PlaylistContentPage.ets`
    - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
    - L183 `SongItemViewModel.create` options 内补 `displayFileName`.
15. `entry/src/main/ets/viewmodel/PlaylistSearchViewModel.ets`
    - 字段已存在；新增 `setDisplaySongFileNameInList`。
16. `entry/src/main/ets/pages/PlaylistSearchPage.ets`
    - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。
    - L189 `SongItemViewModel.create` options 内补 `displayFileName`.
17. `entry/src/main/ets/viewmodel/SearchAllSongsViewModel.ets`
    - 新增 `displaySongFileNameInList` + `setDisplaySongFileNameInList`；`createSongItemViewModel`（L294-）内补 `displayFileName: this.displaySongFileNameInList`。
18. `entry/src/main/ets/pages/SearchAllSongsPage.ets`
    - 新增 `@StorageProp('displaySongFileName')` + watch + 转发。

不动文件（确认不需要改）：

- `UserInterfaceViewModel.ets` / `UserInterfaceModel.ets`：开关 UI + 持久化已就绪。
- `UserInterfacePage.ets`：开关 UI 已就绪。
- `EntryAbility.ets`：`displaySongFileName` 的 `persistProp` 与 AppStorage 引导已就绪。
- `SongSortDialogComponent.ets` / `SongSortDialogViewModel.ets`：本 spec 不涉及排序联动。
- `PlayQueueComponent.ets` / `PlayQueueViewModel.ets`：spec 范围只到"歌曲列表"，不含播放队列；保持当前显示 title 行为。
- `SongInformationPage.ets` / `MiniPlayerComponent.ets`：详情页和迷你播放器不在 spec 范围。

## 5. 场景级闭环验证

- **场景一（默认关）**：`displaySongFileName` 初值 `false`（EntryAbility + Model + 各 VM 默认值一致），`SongItemViewModel.displayFileName=false`，`getDisplayTitle()` 走原逻辑 → 显示 title。
- **场景二（打开 → 实时切到文件名）**：
  1. UserInterfacePage 中 `vm.displaySongFileNameVM.toggle()` → 回调 `AppStorage.setOrCreate('displaySongFileName', true)` + `SettingsStore.save`。
  2. 任意已挂载的歌曲列表页（包含 MainPage 的歌曲 Tab、Playlist 详情、Album 详情、Artist 详情、Folder 详情、FolderPath、SearchAllSongs、PlaylistSearch）在 `@StorageProp` watch 中收到通知 → `setDisplaySongFileNameInList(true)`。
  3. 由于 List VM 中 `displaySongFileNameInList` 是 `@Track`，且 LazyForEach 每次 itemBuilder 都重新调用 `SongItemViewModel.create(song, { ..., displayFileName: this.vm.displaySongFileNameInList })`，列表 item 立即重建并显示文件名。
  4. Artist 页因为缓存 VM 实例，setter walk + `songDataSource.reload(Array.from(this.songs))` 触发 LazyDataSource onDataReloaded，所有可见 row 重渲染。
- **场景三（关闭 → 实时切回 title）**：与场景二对偶，AppStorage 写 false → 所有桥同步 → `getDisplayTitle()` 回到 `${title}.${format}` 或 `title`。
- **场景四（文件名规则）**：`fileNameFromPath(path)` 取最后一段 + decodeURIComponent；扩展名保留。

冷启动一致性：
- `EntryAbility.onCreate`：`persistProp('displaySongFileName', false)` → AppStorage 立即有值；`onAbilityCreate` 同步把 `SettingsStore` 中的值（如果用户调过设置就是上一次值）再写一次 AppStorage（L147）。
- 各 ListVM 字段初值从 `AppStorage.get<boolean>('displaySongFileName')` 拉取，因此 ViewModel 构造时已经拿到最新值；首屏渲染就是用户上次选择。

## 6. 失败模式与防护

- `path` 字段在历史扫描数据中可能为空：`fileNameFromPath('')` 返回 ''；`getDisplayTitle()` 检测到空串时回退到 `title` 路径，避免出现"主文本空白"。
- `path` 是 URI（`file:///...`）：`decodeURIComponent` 失败时直接返回原段；不阻断 UI。
- 同一 song.id 在 LazyForEach 中可能复用：本 spec 不动 LazyForEach key 策略，因为 `SongItemViewModel.create` 每次都重新构造 VM 并把最新 `displayFileName` 写入；`SongItemComponent` 已通过 `@Prop @Watch('onViewModelChanged')` 接收 VM 替换，主文本会随 VM 重建而刷新。
- Artist 页缓存 VM 的特殊路径，已用 walk + reload 兜底。
- 不引入 `aboutToAppear` 兜底（避免一次性 lifecycle 误用为实时同步路径）。

## 7. 不在本 spec 范围（明确划界）

- 不修改播放队列、Mini 播放器、详情页主标题（这些 spec 没要求）。
- 不引入针对 `format` 的扩展名解析变化；现有 `${title}.${format}` 行为在关闭状态保持不变。
- 不做按文件名搜索/排序的语义改动；排序对话框对 `displaySongFileNameInList` 的现有用法（影响标题排序与文件名排序互斥置灰）由现有代码沿用，不在本 spec 内重写。
- 不变更 DB schema。
