# 需求代码定位测试集 —— 标准答案（人类可读版）

> 机器可读版见 `ground-truth.json`。任务方向：**给定一个 commit + 一条 AR 需求描述 → 定位该 AR 关联的真实代码**（文件 + 符号 + 行号）。
> 标准答案对齐 **15-SR / 77-AR 方案**（见 `../requirements/SR-AR-mapping.md`）。

## 统计
- 用例数：**174**（简单层 77 + 难例层 77 + 复杂层 20）
- **简单层 L01-L77**：每个 commit = 1 段 AR 真实实现 + 1 段通用干扰。
- **难例层 H01-H77**：每个 commit = 1 段 AR 真实实现 + **5 段干扰**（其中 **3 段是其它 AR 的真实代码**，已标注来源 AR；2 段通用无关代码），目标实现位置打乱。
- **复杂层 X01-X20**：四类复杂场景 —— 同文件多段实现（2 正例）/ 跨文件实现（2 正例分布 2 个文件）/ 跨 SR 同语义强干扰 / 大候选集（1 正例 + 9 干扰）。
- 粒度：文件 + 符号 + 行号区间。每个干扰标 `source`：`generic` 或来源 AR 编号（如 `AR-03-04`）。

## 简单层 L01-L77

| 用例 | AR | 需求描述 | commit | 标准答案（AR 关联代码） | 干扰（通用） |
|------|----|----------|--------|--------------------------|--------------|
| L01 | AR-01-01 | 播放/暂停/上一曲/下一曲控制 | `9996bb33` | `model/AudioPlayerService.ets`·`resolveTransportIndexA`·L2019-2031 | `model/AudioPlayerService.ets`·`parseHexColorA`·L2033-2043 |
| L02 | AR-01-02 | 播放模式切换（列表循环/单曲循环/随机） | `0457fdcc` | `model/AudioPlayerService.ets`·`nextPlayModeA`·L2045-2054 | `model/AudioPlayerService.ets`·`dedupeKeepOrderA`·L2056-2068 |
| L03 | AR-01-03 | 播放队列查看/清空/移除 | `b1d9ecf2` | `model/PlayQueueModel.ets`·`removeFromQueueA`·L40-52 | `model/PlayQueueModel.ets`·`simpleStringHashA`·L54-62 |
| L04 | AR-01-04 | 播放速度调节 | `c6f9c87c` | `model/SoundEffectModel.ets`·`clampPlaybackSpeedA`·L91-102 | `model/SoundEffectModel.ets`·`formatByteSizeA`·L104-114 |
| L05 | AR-01-05 | 进度拖动与跳转 | `5ffacef5` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA`·L2070-2083 | `model/AudioPlayerService.ets`·`isLeapYearA`·L2085-2094 |
| L06 | AR-01-06 | 睡眠定时（设置时长+自动延长至本曲结束） | `802f1ff1` | `model/SleepTimerService.ets`·`computeSleepStopTimeA`·L179-189 | `model/SleepTimerService.ets`·`camelToKebabA`·L191-203 |
| L07 | AR-01-07 | 播放页展示专辑封面 | `0599fa2b` | `model/CurrentSongCoverController.ets`·`resolveCoverUriA`·L153-162 | `model/CurrentSongCoverController.ets`·`formatSecondsClockA`·L164-172 |
| L08 | AR-01-08 | 播放页快捷操作入口 | `ae602bd2` | `viewmodel/PlayerPageViewModel.ets`·`buildQuickActionsA`·L1322-1331 | `viewmodel/PlayerPageViewModel.ets`·`greatestCommonDivisorA`·L1333-1343 |
| L09 | AR-02-01 | 音频扫描入库 | `11ab2f46` | `model/ScanningModel.ets`·`collectScannedAudioB`·L1149-1163 | `model/ScanningModel.ets`·`formatBytesB1`·L1165-1175 |
| L10 | AR-02-02 | 重新扫描刷新媒体库 | `1a7b3157` | `model/ScanningModel.ets`·`diffRescanResultB`·L1177-1197 | `model/ScanningModel.ets`·`celsiusToFahrenheitB2`·L1199-1207 |
| L11 | AR-02-03 | 扫描屏蔽文件夹 | `47d64f3c` | `model/BlockedFolderModel.ets`·`isPathBlockedB`·L92-105 | `model/BlockedFolderModel.ets`·`medianOfArrayB3`·L107-118 |
| L12 | AR-02-04 | 过滤60秒以下短音频 | `615ff4c6` | `model/ScanningModel.ets`·`filterShortAudioB`·L1209-1221 | `model/ScanningModel.ets`·`isLeapYearB4`·L1223-1232 |
| L13 | AR-03-01 | 歌曲列表项展示（封面/音质/歌名/艺术家） | `a910f485` | `viewmodel/SongItemViewModel.ets`·`buildSongItemViewB`·L246-260 | `viewmodel/SongItemViewModel.ets`·`hexToRgbB5`·L262-272 |
| L14 | AR-03-02 | 歌曲列表搜索 | `84fa2fcf` | `model/SearchAllSongsModel.ets`·`searchAllSongsB`·L62-77 | `model/SearchAllSongsModel.ets`·`euclideanDistanceB6`·L79-84 |
| L15 | AR-03-03 | 歌曲列表多维排序 | `c9852817` | `model/SongSortModel.ets`·`sortSongsByFieldB`·L187-202 | `model/SongSortModel.ets`·`chunkArrayB7`·L204-212 |
| L16 | AR-03-04 | 歌曲列表ABC快速索引 | `ec17b085` | `model/RightABCModel.ets`·`buildSongAbcIndexB`·L23-37 | `model/RightABCModel.ets`·`greatestCommonDivisorB8`·L39-49 |
| L17 | AR-03-05 | 歌曲随机播放全部 | `87b78c0e` | `viewmodel/MainPageViewModel.ets`·`shuffleAllSongsB`·L1686-1696 | `viewmodel/MainPageViewModel.ets`·`formatClockB9`·L1698-1706 |
| L18 | AR-03-06 | 歌曲多选操作 | `3267123d` | `viewmodel/MainPageViewModel.ets`·`toggleSongSelectionB`·L1708-1721 | `viewmodel/MainPageViewModel.ets`·`camelToKebabB10`·L1723-1735 |
| L19 | AR-03-07 | 歌曲更多操作菜单 | `03c4f083` | `model/SongMenuModel.ets`·`buildSongMenuItemsB`·L79-91 | `model/SongMenuModel.ets`·`capitalizeWordsB11`·L93-105 |
| L20 | AR-03-08 | 歌曲信息详情展示 | `7e726afe` | `model/SongInformationModel.ets`·`buildSongInfoRowsB`·L63-76 | `model/SongInformationModel.ets`·`isPrimeNumberB12`·L78-89 |
| L21 | AR-04-01 | 加载内嵌/独立LRC歌词（解析[mm:ss.xx]时间标签） | `c9f60e60` | `model/LyricsModel.ets`·`parseLrcLinesC`·L980-996 | `model/LyricsModel.ets`·`humanizeBytesC`·L998-1010 |
| L22 | AR-04-02 | 歌词同步滚动（按当前毫秒定位当前行） | `38684a0a` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC`·L283-299 | `viewmodel/LyricsViewModel.ets`·`debounceCallC`·L301-315 |
| L23 | AR-04-03 | 卡拉OK逐字歌词（按字时间计算高亮进度） | `d42d83c7` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC`·L60-77 | `model/KaraokeRenderDecision.ets`·`toCamelCaseC`·L79-89 |
| L24 | AR-04-04 | 歌词翻译显示切换 | `9bde689b` | `viewmodel/LyricsViewModel.ets`·`mergeTranslationLinesC`·L317-330 | `viewmodel/LyricsViewModel.ets`·`formatClockC`·L332-340 |
| L25 | AR-04-05 | 播放页迷你歌词 | `e4b0d3ec` | `model/MiniLyricsController.ets`·`pickMiniLyricWindowC`·L207-216 | `model/MiniLyricsController.ets`·`dedupeKeepOrderC`·L218-230 |
| L26 | AR-04-06 | 歌词设置（字体大小/对齐/模糊半径，做范围约束） | `16e801f7` | `model/LyricsSettingsModel.ets`·`clampLyricsSettingsC`·L32-39 | `model/LyricsSettingsModel.ets`·`greatestCommonDivisorC`·L41-51 |
| L27 | AR-05-01 | 专辑列表项展示 | `4dd5c5c2` | `viewmodel/AlbumTabViewModel.ets`·`buildAlbumSubtitleC`·L145-157 | `viewmodel/AlbumTabViewModel.ets`·`isPalindromeC`·L159-172 |
| L28 | AR-05-02 | 专辑列表ABC快速索引 | `d49a27af` | `model/AlbumModel.ets`·`albumIndexKeyC`·L37-47 | `model/AlbumModel.ets`·`averageRoundedC`·L49-58 |
| L29 | AR-05-03 | 专辑列表设置（排序维度/列数 2-4 约束） | `7f3382fd` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC`·L21-29 | `model/AlbumListSettingsModel.ets`·`binarySearchIndexC`·L31-46 |
| L30 | AR-05-04 | 专辑详情头部展示（汇总歌曲数/总时长） | `109b65b7` | `viewmodel/AlbumContentViewModel.ets`·`summarizeAlbumHeaderC`·L335-346 | `viewmodel/AlbumContentViewModel.ets`·`countWordsC`·L348-357 |
| L31 | AR-05-05 | 专辑详情曲目列表（按碟号/曲目号排序） | `7bcf94ae` | `model/AlbumContentModel.ets`·`sortAlbumTracksC`·L139-152 | `model/AlbumContentModel.ets`·`groupByPrefixC`·L154-165 |
| L32 | AR-05-06 | 专辑详情参与创作艺术家区块（统计各艺术家歌曲数） | `2623f76d` | `model/AlbumContentModel.ets`·`rankAlbumArtistsC`·L167-179 | `model/AlbumContentModel.ets`·`splitCamelWordsC`·L181-197 |
| L33 | AR-06-01 | 艺术家列表项展示（头像/名/歌曲数） | `bd35061e` | `viewmodel/ArtistItemViewModel.ets`·`buildArtistItemD`·L115-126 | `viewmodel/ArtistItemViewModel.ets`·`formatByteSizeD`·L128-142 |
| L34 | AR-06-02 | 艺术家列表ABC快速索引 | `0fed1305` | `model/ArtistModel.ets`·`groupArtistsByLetterD`·L24-40 | `model/ArtistModel.ets`·`averageOfValuesD`·L42-53 |
| L35 | AR-06-03 | 艺术家详情头部展示 | `c6e23b09` | `viewmodel/ArtistContentViewModel.ets`·`buildArtistHeaderD`·L358-370 | `viewmodel/ArtistContentViewModel.ets`·`parseHexColorD`·L372-385 |
| L36 | AR-06-04 | 艺术家详情歌曲列表（可折叠，限制展示数量） | `394b6351` | `model/ArtistContentModel.ets`·`collapseArtistSongsD`·L140-154 | `model/ArtistContentModel.ets`·`isLeapYearD`·L156-168 |
| L37 | AR-06-05 | 艺术家详情专辑区块 | `1318be22` | `model/ArtistContentModel.ets`·`buildArtistAlbumSectionD`·L170-185 | `model/ArtistContentModel.ets`·`formatSecondsD`·L187-195 |
| L38 | AR-07-01 | 文件夹列表展示 | `d2f873a3` | `model/FolderModel.ets`·`buildFolderItemD`·L26-42 | `model/FolderModel.ets`·`countCharFrequencyD`·L44-53 |
| L39 | AR-07-02 | 文件夹列表搜索歌曲 | `4823e083` | `viewmodel/FolderContentPageViewModel.ets`·`searchFolderSongsD`·L411-425 | `viewmodel/FolderContentPageViewModel.ets`·`camelToKebabD`·L427-439 |
| L40 | AR-07-03 | 隐藏指定文件夹 | `11495015` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD`·L120-134 | `model/BlockedFolderModel.ets`·`dedupeIntArrayD`·L136-148 |
| L41 | AR-07-04 | 文件夹详情歌曲列表项展示 | `0422df29` | `model/FolderContentPageModel.ets`·`buildFolderSongRowsD`·L126-140 | `model/FolderContentPageModel.ets`·`binarySearchIndexD`·L142-158 |
| L42 | AR-07-05 | 文件夹详情歌曲列表排序 | `c9c62d54` | `model/FolderContentPageModel.ets`·`sortFolderSongsD`·L160-176 | `model/FolderContentPageModel.ets`·`transposeMatrixD`·L178-193 |
| L43 | AR-07-06 | 文件夹详情ABC快速索引 | `662b3fb1` | `model/RightABCModel.ets`·`folderAbcIndexD`·L51-66 | `model/RightABCModel.ets`·`commonPrefixLengthD`·L68-79 |
| L44 | AR-07-07 | 文件夹详情随机播放全部 | `627ba353` | `viewmodel/FolderContentViewModel.ets`·`shuffleFolderQueueD`·L68-81 | `viewmodel/FolderContentViewModel.ets`·`greatestCommonDivisorD`·L83-93 |
| L45 | AR-07-08 | 文件夹详情多选操作 | `9cbad921` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD`·L195-211 | `model/FolderContentPageModel.ets`·`padLeftZeroD`·L213-220 |
| L46 | AR-07-09 | 文件夹详情歌曲更多菜单 | `9a102fb8` | `model/FolderMenuModel.ets`·`buildFolderMenuItemsD`·L30-44 | `model/FolderMenuModel.ets`·`parseQueryStringD`·L46-59 |
| L47 | AR-07-10 | 文件夹详情歌曲信息详情 | `6feb2cc4` | `model/SongInformationModel.ets`·`buildFolderSongInfoD`·L91-108 | `model/SongInformationModel.ets`·`isPalindromeD`·L110-123 |
| L48 | AR-08-01 | 创建歌单（名称去空白非空校验、查重） | `525419c7` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE`·L100-112 | `model/NewPlaylistModel.ets`·`formatDurationLabelE`·L114-122 |
| L49 | AR-08-02 | 重命名歌单 | `7835a670` | `model/PlaylistModel.ets`·`renamePlaylistByIdE`·L93-104 | `model/PlaylistModel.ets`·`computeCartTotalE`·L106-114 |
| L50 | AR-08-03 | 删除歌单 | `6aec6c27` | `model/PlaylistModel.ets`·`deletePlaylistByIdE`·L116-126 | `model/PlaylistModel.ets`·`isLeapYearE`·L128-137 |
| L51 | AR-08-04 | 歌曲加入/移出歌单（去重、维护顺序） | `a65e55a2` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE`·L1813-1831 | `model/MusicDatabase.ets`·`countCharFrequencyE`·L1833-1842 |
| L52 | AR-08-05 | 歌单导入/导出（序列化为文本行） | `3a6b76c0` | `model/ImportPlaylistModel.ets`·`serializePlaylistLinesE`·L169-180 | `model/ImportPlaylistModel.ets`·`celsiusToFahrenheitE`·L182-190 |
| L53 | AR-08-06 | 歌单排序 | `ca00bd21` | `model/PlaylistModel.ets`·`sortPlaylistsE`·L139-152 | `model/PlaylistModel.ets`·`isBalancedBracketsE`·L154-169 |
| L54 | AR-09-01 | 音乐库音质分布与容量统计（按音质分组累加大小/数量） | `76d6a251` | `model/MusicLibraryModel.ets`·`summarizeLibraryQualityE`·L226-240 | `model/MusicLibraryModel.ets`·`averageOfNumbersE`·L242-252 |
| L55 | AR-09-02 | 音乐库搜索 | `441fb8bf` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE`·L86-101 | `model/SearchAllSongsModel.ets`·`decimalToBinaryE`·L103-115 |
| L56 | AR-10-01 | 播放次数统计（累加并取 TopN） | `b22810e6` | `model/StatisticsModel.ets`·`topPlayedSongsE`·L74-88 | `model/StatisticsModel.ets`·`reverseWordOrderE`·L90-100 |
| L57 | AR-11-01 | 桌面歌词开关（AVSession 元数据上屏，做开关状态机） | `b863f05c` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF`·L401-416 | `model/DesktopLyricsAVSessionController.ets`·`haversineDistanceF`·L418-428 |
| L58 | AR-11-02 | 锁定/解锁桌面歌词 | `2f4cd293` | `model/DesktopLyricsAVSessionController.ets`·`toggleDesktopLyricsLockF`·L430-440 | `model/DesktopLyricsAVSessionController.ets`·`humanReadableBytesF`·L442-453 |
| L59 | AR-11-03 | 悬浮窗状态栏歌词（按宽度截断单行） | `1c2beb5e` | `model/FloatingStatusBarLyricsController.ets`·`truncateStatusBarLyricF`·L247-259 | `model/FloatingStatusBarLyricsController.ets`·`luhnChecksumValidF`·L261-280 |
| L60 | AR-11-04 | 通知栏歌词 | `7e39b609` | `model/NotificationLyricController.ets`·`buildNotificationLyricTextF`·L110-123 | `model/NotificationLyricController.ets`·`djb2HashF`·L125-133 |
| L61 | AR-12-01 | 主题模式（系统/浅色/深色解析为实际深浅） | `783d1e20` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF`·L52-64 | `model/UserInterfaceModel.ets`·`isLeapYearF`·L66-75 |
| L62 | AR-12-02 | 列表显示歌曲封面开关 | `ff970e84` | `viewmodel/UserInterfaceViewModel.ets`·`applyShowSongCoverF`·L279-292 | `viewmodel/UserInterfaceViewModel.ets`·`celsiusToFahrenheitF`·L294-298 |
| L63 | AR-12-03 | 主页/播放页壁纸 | `bcd0e4ec` | `viewmodel/MainWallpaperViewModel.ets`·`pickWallpaperSourceF`·L146-160 | `viewmodel/MainWallpaperViewModel.ets`·`fibonacciSeriesF`·L162-174 |
| L64 | AR-12-04 | 圆形播放封面（按角度计算旋转） | `13d2e8bd` | `model/UserInterfaceModel.ets`·`advanceCircleCoverAngleF`·L77-89 | `model/UserInterfaceModel.ets`·`sieveOfPrimesF`·L91-113 |
| L65 | AR-12-05 | 流光效果（按相位生成渐变色值） | `22ad26d3` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF`·L165-177 | `model/FlowingLightModel.ets`·`reverseWordOrderF`·L179-189 |
| L66 | AR-12-06 | 播放时保持屏幕常亮 | `db591147` | `model/ScreenWakeModel.ets`·`shouldKeepScreenOnF`·L62-74 | `model/ScreenWakeModel.ets`·`populationStdDevF`·L76-92 |
| L67 | AR-12-07 | 沉浸模式（隐藏系统栏与控制面板的状态切换） | `5313d7cb` | `model/SystemBarModel.ets`·`computeImmersiveBarStateF`·L150-159 | `model/SystemBarModel.ets`·`romanToIntegerF`·L161-173 |
| L68 | AR-13-01 | 音频焦点（请求/丢失焦点的状态切换与暂停决策） | `dcde98df` | `model/AudioOutputModel.ets`·`resolveFocusActionG`·L121-136 | `model/AudioOutputModel.ets`·`parseHexColorG`·L138-148 |
| L69 | AR-13-02 | 音量平衡（左右声道增益，-1..1 映射） | `7eef552c` | `model/AudioOutputModel.ets`·`computeChannelGainsG`·L150-163 | `model/AudioOutputModel.ets`·`dedupeKeepOrderG`·L165-177 |
| L70 | AR-13-03 | 播放暂停淡入淡出（按时长插值音量包络） | `d1a7de2e` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG`·L2096-2106 | `model/AudioPlayerService.ets`·`simpleStringHashG`·L2108-2116 |
| L71 | AR-13-04 | DSP数字信号处理（多段增益叠加并限幅） | `a262e0fa` | `model/SoundEffectModel.ets`·`mixBandGainsG`·L116-131 | `model/SoundEffectModel.ets`·`formatByteSizeG`·L133-143 |
| L72 | AR-14-01 | 启动自动打开播放页 | `c2d181d8` | `model/LaboratoryModel.ets`·`shouldOpenPlayerOnLaunchG`·L35-44 | `model/LaboratoryModel.ets`·`isLeapYearG`·L46-55 |
| L73 | AR-14-02 | 立体歌词（按深度计算缩放透明度） | `534195ed` | `model/LaboratoryModel.ets`·`computeLyricDepthStyleG`·L57-71 | `model/LaboratoryModel.ets`·`camelToKebabG`·L73-85 |
| L74 | AR-15-01 | 帮助与FAQ（关键字过滤问答列表） | `0d316022` | `model/HelpAndFeedbackModel.ets`·`filterFaqByKeywordG`·L51-66 | `model/HelpAndFeedbackModel.ets`·`formatSecondsClockG`·L68-76 |
| L75 | AR-15-02 | 用户反馈（内容长度与联系方式校验） | `b5ca1085` | `model/HelpAndFeedbackModel.ets`·`validateFeedbackG`·L78-95 | `model/HelpAndFeedbackModel.ets`·`greatestCommonDivisorG`·L97-107 |
| L76 | AR-15-03 | 关于与版本/检查更新（语义版本号比较） | `b43297cd` | `model/AboutModel.ets`·`compareSemverG`·L102-118 | `model/AboutModel.ets`·`isPalindromeG`·L120-133 |
| L77 | AR-15-04 | 开源致谢（按名称排序去重许可证列表） | `68d50eb1` | `model/CreditsModel.ets`·`sortDedupeLicensesG`·L149-162 | `model/CreditsModel.ets`·`splitDurationPartsG`·L164-172 |

## 难例层 H01-H77（多干扰 + 跨 AR 干扰）

| 用例 | AR | commit | 标准答案（AR 关联代码） | 干扰数 | 跨 AR 干扰来源 |
|------|----|--------|--------------------------|--------|----------------|
| H01 | AR-01-01 | `e88ea122` | `model/AudioPlayerService.ets`·`resolveTransportIndexA_H1`·L2180-2192 | 5 | AR-01-02, AR-01-03, AR-01-04 |
| H02 | AR-01-02 | `4d414ee8` | `model/AudioPlayerService.ets`·`nextPlayModeA_H2`·L2244-2253 | 5 | AR-01-04, AR-01-05, AR-01-03 |
| H03 | AR-01-03 | `4201f499` | `model/PlayQueueModel.ets`·`removeFromQueueA_H3`·L99-111 | 5 | AR-01-06, AR-01-04, AR-01-05 |
| H04 | AR-01-04 | `681cdb5b` | `model/SoundEffectModel.ets`·`clampPlaybackSpeedA_H4`·L170-181 | 5 | AR-01-05, AR-01-06, AR-01-07 |
| H05 | AR-01-05 | `1aab41ab` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA_H5`·L2279-2292 | 5 | AR-01-06, AR-01-07, AR-01-08 |
| H06 | AR-01-06 | `880bb854` | `model/SleepTimerService.ets`·`computeSleepStopTimeA_H6`·L205-215 | 5 | AR-01-07, AR-01-08, AR-02-01 |
| H07 | AR-01-07 | `3d8678e2` | `model/CurrentSongCoverController.ets`·`resolveCoverUriA_H7`·L247-256 | 5 | AR-01-08, AR-02-01, AR-02-02 |
| H08 | AR-01-08 | `ce590ecd` | `viewmodel/PlayerPageViewModel.ets`·`buildQuickActionsA_H8`·L1404-1413 | 5 | AR-02-02, AR-02-03, AR-02-01 |
| H09 | AR-02-01 | `d48c4ccb` | `model/ScanningModel.ets`·`collectScannedAudioB_H9`·L1268-1282 | 5 | AR-01-08, AR-01-06, AR-01-07 |
| H10 | AR-02-02 | `73a864f3` | `model/ScanningModel.ets`·`diffRescanResultB_H10`·L1331-1351 | 5 | AR-01-07, AR-01-08, AR-03-01 |
| H11 | AR-02-03 | `a95e2adb` | `model/BlockedFolderModel.ets`·`isPathBlockedB_H11`·L162-175 | 5 | AR-01-08, AR-03-01, AR-03-02 |
| H12 | AR-02-04 | `ffb0a575` | `model/ScanningModel.ets`·`filterShortAudioB_H12`·L1391-1403 | 5 | AR-03-01, AR-03-02, AR-03-03 |
| H13 | AR-03-01 | `002c1896` | `viewmodel/SongItemViewModel.ets`·`buildSongItemViewB_H13`·L325-339 | 5 | AR-01-06, AR-01-07, AR-01-08 |
| H14 | AR-03-02 | `abac771b` | `model/SearchAllSongsModel.ets`·`searchAllSongsB_H14`·L166-181 | 5 | AR-01-08, AR-02-01, AR-01-07 |
| H15 | AR-03-03 | `86063731` | `model/SongSortModel.ets`·`sortSongsByFieldB_H15`·L258-273 | 5 | AR-02-02, AR-01-08, AR-02-01 |
| H16 | AR-03-04 | `ce87d31f` | `model/RightABCModel.ets`·`buildSongAbcIndexB_H16`·L105-119 | 5 | AR-02-01, AR-02-02, AR-02-03 |
| H17 | AR-03-05 | `f2a76d98` | `viewmodel/MainPageViewModel.ets`·`shuffleAllSongsB_H17`·L1751-1761 | 5 | AR-02-02, AR-02-03, AR-02-04 |
| H18 | AR-03-06 | `30bafbe8` | `viewmodel/MainPageViewModel.ets`·`toggleSongSelectionB_H18`·L1828-1841 | 5 | AR-02-03, AR-02-04, AR-04-01 |
| H19 | AR-03-07 | `56159dda` | `model/SongMenuModel.ets`·`buildSongMenuItemsB_H19`·L184-196 | 5 | AR-02-04, AR-04-01, AR-04-02 |
| H20 | AR-03-08 | `af11348a` | `model/SongInformationModel.ets`·`buildSongInfoRowsB_H20`·L192-205 | 5 | AR-04-02, AR-04-03, AR-04-01 |
| H21 | AR-04-01 | `1508637f` | `model/LyricsModel.ets`·`parseLrcLinesC_H21`·L1055-1071 | 5 | AR-03-06, AR-03-04, AR-03-05 |
| H22 | AR-04-02 | `6318174a` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC_H22`·L364-380 | 5 | AR-03-05, AR-03-06, AR-03-07 |
| H23 | AR-04-03 | `1cce447d` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC_H23`·L105-122 | 5 | AR-03-06, AR-03-07, AR-03-08 |
| H24 | AR-04-04 | `66ff3b42` | `viewmodel/LyricsViewModel.ets`·`mergeTranslationLinesC_H24`·L423-436 | 5 | AR-03-07, AR-03-08, AR-05-01 |
| H25 | AR-04-05 | `90f5d7be` | `model/MiniLyricsController.ets`·`pickMiniLyricWindowC_H25`·L300-309 | 5 | AR-03-08, AR-05-01, AR-05-02 |
| H26 | AR-04-06 | `919b9774` | `model/LyricsSettingsModel.ets`·`clampLyricsSettingsC_H26`·L101-108 | 5 | AR-05-02, AR-05-03, AR-05-01 |
| H27 | AR-05-01 | `d14d1bc3` | `viewmodel/AlbumTabViewModel.ets`·`buildAlbumSubtitleC_H27`·L217-229 | 5 | AR-04-04, AR-04-02, AR-04-03 |
| H28 | AR-05-02 | `4328de4c` | `model/AlbumModel.ets`·`albumIndexKeyC_H28`·L88-98 | 5 | AR-04-03, AR-04-04, AR-04-05 |
| H29 | AR-05-03 | `228d76eb` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC_H29`·L61-69 | 5 | AR-04-04, AR-04-05, AR-04-06 |
| H30 | AR-05-04 | `d30b67bd` | `viewmodel/AlbumContentViewModel.ets`·`summarizeAlbumHeaderC_H30`·L359-370 | 5 | AR-04-05, AR-04-06, AR-06-01 |
| H31 | AR-05-05 | `4a3b29ef` | `model/AlbumContentModel.ets`·`sortAlbumTracksC_H31`·L273-286 | 5 | AR-04-06, AR-06-01, AR-06-02 |
| H32 | AR-05-06 | `efa29167` | `model/AlbumContentModel.ets`·`rankAlbumArtistsC_H32`·L349-361 | 5 | AR-06-02, AR-06-03, AR-06-01 |
| H33 | AR-06-01 | `7fa77d26` | `viewmodel/ArtistItemViewModel.ets`·`buildArtistItemD_H33`·L187-198 | 5 | AR-05-05, AR-05-03, AR-05-04 |
| H34 | AR-06-02 | `8854212b` | `model/ArtistModel.ets`·`groupArtistsByLetterD_H34`·L84-100 | 5 | AR-05-04, AR-05-05, AR-05-06 |
| H35 | AR-06-03 | `842c54fb` | `viewmodel/ArtistContentViewModel.ets`·`buildArtistHeaderD_H35`·L397-409 | 5 | AR-05-05, AR-05-06, AR-07-01 |
| H36 | AR-06-04 | `54a04aea` | `model/ArtistContentModel.ets`·`collapseArtistSongsD_H36`·L197-211 | 5 | AR-05-06, AR-07-01, AR-07-02 |
| H37 | AR-06-05 | `f354b231` | `model/ArtistContentModel.ets`·`buildArtistAlbumSectionD_H37`·L357-372 | 5 | AR-07-01, AR-07-02, AR-07-03 |
| H38 | AR-07-01 | `c477daf6` | `model/FolderModel.ets`·`buildFolderItemD_H38`·L111-127 | 5 | AR-05-04, AR-05-05, AR-05-03 |
| H39 | AR-07-02 | `9fb3bf93` | `viewmodel/FolderContentPageViewModel.ets`·`searchFolderSongsD_H39`·L487-501 | 5 | AR-05-06, AR-05-04, AR-05-05 |
| H40 | AR-07-03 | `0127c510` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD_H40`·L267-281 | 5 | AR-05-05, AR-05-06, AR-06-01 |
| H41 | AR-07-04 | `e975522f` | `model/FolderContentPageModel.ets`·`buildFolderSongRowsD_H41`·L235-249 | 5 | AR-05-06, AR-06-01, AR-06-02 |
| H42 | AR-07-05 | `26c1dca4` | `model/FolderContentPageModel.ets`·`sortFolderSongsD_H42`·L313-329 | 5 | AR-06-01, AR-06-02, AR-06-03 |
| H43 | AR-07-06 | `e8c7c227` | `model/RightABCModel.ets`·`folderAbcIndexD_H43`·L243-258 | 5 | AR-06-02, AR-06-03, AR-06-04 |
| H44 | AR-07-07 | `ea0b8071` | `viewmodel/FolderContentViewModel.ets`·`shuffleFolderQueueD_H44`·L152-165 | 5 | AR-06-04, AR-06-05, AR-06-03 |
| H45 | AR-07-08 | `5450b4d6` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD_H45`·L445-461 | 5 | AR-08-01, AR-06-04, AR-06-05 |
| H46 | AR-07-09 | `9d45d4ca` | `model/FolderMenuModel.ets`·`buildFolderMenuItemsD_H46`·L86-100 | 5 | AR-06-05, AR-08-01, AR-08-02 |
| H47 | AR-07-10 | `68db2c88` | `model/SongInformationModel.ets`·`buildFolderSongInfoD_H47`·L235-252 | 5 | AR-08-01, AR-08-02, AR-08-03 |
| H48 | AR-08-01 | `1e34dbb9` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE_H48`·L124-136 | 5 | AR-07-06, AR-07-07, AR-07-08 |
| H49 | AR-08-02 | `b6f83e06` | `model/PlaylistModel.ets`·`renamePlaylistByIdE_H49`·L242-253 | 5 | AR-07-07, AR-07-08, AR-07-09 |
| H50 | AR-08-03 | `c3e6315a` | `model/PlaylistModel.ets`·`deletePlaylistByIdE_H50`·L311-321 | 5 | AR-07-09, AR-07-10, AR-07-08 |
| H51 | AR-08-04 | `14979046` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE_H51`·L1887-1905 | 5 | AR-09-01, AR-07-09, AR-07-10 |
| H52 | AR-08-05 | `9b1e27c1` | `model/ImportPlaylistModel.ets`·`serializePlaylistLinesE_H52`·L221-232 | 5 | AR-07-10, AR-09-01, AR-09-02 |
| H53 | AR-08-06 | `ce0bffea` | `model/PlaylistModel.ets`·`sortPlaylistsE_H53`·L355-368 | 5 | AR-09-01, AR-09-02, AR-10-01 |
| H54 | AR-09-01 | `fd868d88` | `model/MusicLibraryModel.ets`·`summarizeLibraryQualityE_H54`·L254-268 | 5 | AR-08-06, AR-10-01, AR-11-01 |
| H55 | AR-09-02 | `f6f48d1c` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE_H55`·L263-278 | 5 | AR-10-01, AR-11-01, AR-11-02 |
| H56 | AR-10-01 | `b2b7c83a` | `model/StatisticsModel.ets`·`topPlayedSongsE_H56`·L153-167 | 5 | AR-11-02, AR-11-03, AR-11-01 |
| H57 | AR-11-01 | `7c2723e4` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF_H57`·L505-520 | 5 | AR-10-01, AR-09-01, AR-09-02 |
| H58 | AR-11-02 | `d5c84a92` | `model/DesktopLyricsAVSessionController.ets`·`toggleDesktopLyricsLockF_H58`·L586-596 | 5 | AR-09-02, AR-10-01, AR-12-01 |
| H59 | AR-11-03 | `298c155f` | `model/FloatingStatusBarLyricsController.ets`·`truncateStatusBarLyricF_H59`·L293-305 | 5 | AR-10-01, AR-12-01, AR-12-02 |
| H60 | AR-11-04 | `35555f5e` | `model/NotificationLyricController.ets`·`buildNotificationLyricTextF_H60`·L135-148 | 5 | AR-12-01, AR-12-02, AR-12-03 |
| H61 | AR-12-01 | `3280782f` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF_H61`·L185-197 | 5 | AR-09-02, AR-10-01, AR-11-01 |
| H62 | AR-12-02 | `9558a357` | `viewmodel/UserInterfaceViewModel.ets`·`applyShowSongCoverF_H62`·L367-380 | 5 | AR-11-01, AR-11-02, AR-10-01 |
| H63 | AR-12-03 | `27da8fbd` | `viewmodel/MainWallpaperViewModel.ets`·`pickWallpaperSourceF_H63`·L226-240 | 5 | AR-11-03, AR-11-01, AR-11-02 |
| H64 | AR-12-04 | `64f18717` | `model/UserInterfaceModel.ets`·`advanceCircleCoverAngleF_H64`·L229-241 | 5 | AR-11-02, AR-11-03, AR-11-04 |
| H65 | AR-12-05 | `5792a2e0` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF_H65`·L205-217 | 5 | AR-11-03, AR-11-04, AR-13-01 |
| H66 | AR-12-06 | `0293fa3f` | `model/ScreenWakeModel.ets`·`shouldKeepScreenOnF_H66`·L94-106 | 5 | AR-11-04, AR-13-01, AR-13-02 |
| H67 | AR-12-07 | `323c3643` | `model/SystemBarModel.ets`·`computeImmersiveBarStateF_H67`·L245-254 | 5 | AR-13-01, AR-13-02, AR-13-03 |
| H68 | AR-13-01 | `1aebf4c4` | `model/AudioOutputModel.ets`·`resolveFocusActionG_H68`·L228-243 | 5 | AR-12-06, AR-12-07, AR-12-05 |
| H69 | AR-13-02 | `0190384b` | `model/AudioOutputModel.ets`·`computeChannelGainsG_H69`·L292-305 | 5 | AR-14-01, AR-12-06, AR-12-07 |
| H70 | AR-13-03 | `b03cb1aa` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG_H70`·L2365-2375 | 5 | AR-12-07, AR-14-01, AR-14-02 |
| H71 | AR-13-04 | `1b5b2932` | `model/SoundEffectModel.ets`·`mixBandGainsG_H71`·L235-250 | 5 | AR-14-01, AR-14-02, AR-15-01 |
| H72 | AR-14-01 | `fab3121e` | `model/LaboratoryModel.ets`·`shouldOpenPlayerOnLaunchG_H72`·L87-96 | 5 | AR-13-04, AR-15-01, AR-15-02 |
| H73 | AR-14-02 | `a36a9d65` | `model/LaboratoryModel.ets`·`computeLyricDepthStyleG_H73`·L251-265 | 5 | AR-15-01, AR-15-02, AR-15-03 |
| H74 | AR-15-01 | `e17bf040` | `model/HelpAndFeedbackModel.ets`·`filterFaqByKeywordG_H74`·L163-178 | 5 | AR-14-01, AR-14-02, AR-13-04 |
| H75 | AR-15-02 | `771b3ac3` | `model/HelpAndFeedbackModel.ets`·`validateFeedbackG_H75`·L239-256 | 5 | AR-15-01, AR-14-01, AR-14-02 |
| H76 | AR-15-03 | `932b2980` | `model/AboutModel.ets`·`compareSemverG_H76`·L157-173 | 5 | AR-14-02, AR-15-01, AR-15-02 |
| H77 | AR-15-04 | `cc00a1e8` | `model/CreditsModel.ets`·`sortDedupeLicensesG_H77`·L188-201 | 5 | AR-15-01, AR-15-02, AR-15-03 |

## 复杂层 X01-X20（多段实现 / 跨文件 / 跨SR干扰 / 大候选集）

| 用例 | 场景 | AR | commit | 标准答案（可能多段） | 干扰数 | 跨 AR 干扰来源 |
|------|------|----|--------|----------------------|--------|----------------|
| X01 | 同文件多段实现 | AR-01-01 | `0fdc6545` | `model/AudioPlayerService.ets`·`resolveTransportIndexA_X1`·L2441-2453<br>`model/AudioPlayerService.ets`·`resolveResumeIndexX_X1`·L2455-2468 | 3 | AR-01-03, AR-01-02 |
| X02 | 同文件多段实现 | AR-01-06 | `37ccbec1` | `model/SleepTimerService.ets`·`formatSleepRemainX_X2`·L277-289<br>`model/SleepTimerService.ets`·`computeSleepStopTimeA_X2`·L329-339 | 3 | AR-01-05, AR-01-07 |
| X03 | 同文件多段实现 | AR-02-01 | `67783335` | `model/ScanningModel.ets`·`collectScannedAudioB_X3`·L1487-1501<br>`model/ScanningModel.ets`·`countAudioByDirX_X3`·L1503-1520 | 3 | AR-02-02, AR-02-04 |
| X04 | 同文件多段实现 | AR-04-02 | `05bd8b33` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC_X4`·L554-570<br>`viewmodel/LyricsViewModel.ets`·`lyricScrollOffsetX_X4`·L572-586 | 3 | AR-04-01, AR-04-03 |
| X05 | 同文件多段实现 | AR-08-01 | `cf029b17` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE_X5`·L209-221<br>`model/NewPlaylistModel.ets`·`normalizePlaylistNameX_X5`·L223-237 | 3 | AR-08-02, AR-08-04 |
| X06 | 同文件多段实现 | AR-13-03 | `da23476d` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG_X6`·L2512-2522<br>`model/AudioPlayerService.ets`·`buildFadeStepsX_X6`·L2524-2533 | 3 | AR-13-04, AR-13-01 |
| X07 | 跨文件实现 | AR-01-05 | `a6fecebe` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA_X7`·L2580-2593<br>`viewmodel/PlayerPageViewModel.ets`·`dragPercentToMsX_X7`·L1445-1458 | 4 | AR-01-01, AR-01-07 |
| X08 | 跨文件实现 | AR-03-02 | `4a4f8a90` | `model/SearchAllSongsModel.ets`·`searchAllSongsB_X8`·L292-307<br>`viewmodel/MainPageViewModel.ets`·`searchHighlightRangesX_X8`·L1917-1935 | 4 | AR-03-03, AR-09-02 |
| X09 | 跨文件实现 | AR-05-03 | `e5ddc3cc` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC_X9`·L117-125<br>`viewmodel/AlbumTabViewModel.ets`·`albumGridTemplateX_X9`·L293-307 | 4 | AR-12-02, AR-05-01 |
| X10 | 跨文件实现 | AR-07-03 | `c61d0094` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD_X10`·L354-368<br>`model/FolderModel.ets`·`applyHiddenFoldersX_X10`·L157-173 | 4 | AR-02-03, AR-07-01 |
| X11 | 跨文件实现 | AR-12-01 | `25112608` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF_X11`·L308-320<br>`viewmodel/UserInterfaceViewModel.ets`·`resolveColorModeX_X11`·L398-407 | 4 | AR-12-06, AR-12-03 |
| X12 | 跨文件实现 | AR-11-01 | `567c15cd` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF_X12`·L645-660<br>`viewmodel/LyricsViewModel.ets`·`desktopLyricsStateX_X12`·L609-618 | 4 | AR-11-02, AR-04-05 |
| X13 | 跨SR同语义干扰 | AR-03-04 | `44acac93` | `model/RightABCModel.ets`·`buildSongAbcIndexB_X13`·L301-315 | 5 | AR-07-06, AR-05-02, AR-06-02 |
| X14 | 跨SR同语义干扰 | AR-09-02 | `dc1b78a9` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE_X14`·L326-341 | 5 | AR-03-02, AR-07-02, AR-09-01 |
| X15 | 跨SR同语义干扰 | AR-07-05 | `294c78c8` | `model/FolderContentPageModel.ets`·`sortFolderSongsD_X15`·L536-552 | 5 | AR-07-06, AR-03-03, AR-08-06 |
| X16 | 跨SR同语义干扰 | AR-07-08 | `68accb1f` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD_X16`·L586-602 | 5 | AR-03-06, AR-07-09, AR-03-07 |
| X17 | 大候选集 | AR-01-02 | `c6c88204` | `model/AudioPlayerService.ets`·`nextPlayModeA_X17`·L2712-2721 | 9 | AR-01-01, AR-01-03, AR-01-04, AR-01-05, AR-01-06, AR-03-05, AR-07-07 |
| X18 | 大候选集 | AR-04-03 | `d20a871f` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC_X18`·L252-269 | 9 | AR-04-05, AR-04-06, AR-11-03, AR-11-04, AR-04-01, AR-04-02, AR-04-04 |
| X19 | 大候选集 | AR-08-04 | `dd72ceb8` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE_X19`·L1984-2002 | 9 | AR-10-01, AR-08-01, AR-08-02, AR-08-03, AR-08-05, AR-08-06, AR-03-07 |
| X20 | 大候选集 | AR-12-05 | `700e56a3` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF_X20`·L283-295 | 9 | AR-12-01, AR-12-02, AR-12-03, AR-12-04, AR-12-06, AR-12-07, AR-14-02 |

> 难例/复杂层每个干扰的精确位置与来源见标准答案的 `distractors[].{symbol,start_line,end_line,source}`。
> `source` 为 `generic`（通用无关代码）或某 AR 编号（该段是那个 AR 的真实代码，作为强干扰）。
> 复杂层 `multi`/`xfile` 场景有 **2 段正例**，须全部找到才算找全（按召回计）。
