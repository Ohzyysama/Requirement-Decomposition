# 需求代码定位 —— 评分模板（AR→代码，双层）

输入 `commit + AR 需求描述`，系统输出「该 AR 关联代码位置（文件/符号/行号）」，填入「系统输出」。
判定（口径见 `README.md`）：文件级 / 符号级 / 行级 IoU；命中任一 `distractors` 记为误报（难例层干扰更多、且含其它 AR 真实代码）。

| 用例 | 层 | AR | commit | 标准答案 | 干扰数 | 系统输出 | 文件✓ | 符号✓ | 行级IoU | 命中干扰? |
|------|----|----|--------|----------|--------|----------|-------|-------|---------|-----------|
| L01 | simple | AR-01-01 | `9996bb33` | `model/AudioPlayerService.ets`·`resolveTransportIndexA`·L2019-2031 | 1 | | | | | |
| L02 | simple | AR-01-02 | `0457fdcc` | `model/AudioPlayerService.ets`·`nextPlayModeA`·L2045-2054 | 1 | | | | | |
| L03 | simple | AR-01-03 | `b1d9ecf2` | `model/PlayQueueModel.ets`·`removeFromQueueA`·L40-52 | 1 | | | | | |
| L04 | simple | AR-01-04 | `c6f9c87c` | `model/SoundEffectModel.ets`·`clampPlaybackSpeedA`·L91-102 | 1 | | | | | |
| L05 | simple | AR-01-05 | `5ffacef5` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA`·L2070-2083 | 1 | | | | | |
| L06 | simple | AR-01-06 | `802f1ff1` | `model/SleepTimerService.ets`·`computeSleepStopTimeA`·L179-189 | 1 | | | | | |
| L07 | simple | AR-01-07 | `0599fa2b` | `model/CurrentSongCoverController.ets`·`resolveCoverUriA`·L153-162 | 1 | | | | | |
| L08 | simple | AR-01-08 | `ae602bd2` | `viewmodel/PlayerPageViewModel.ets`·`buildQuickActionsA`·L1322-1331 | 1 | | | | | |
| L09 | simple | AR-02-01 | `11ab2f46` | `model/ScanningModel.ets`·`collectScannedAudioB`·L1149-1163 | 1 | | | | | |
| L10 | simple | AR-02-02 | `1a7b3157` | `model/ScanningModel.ets`·`diffRescanResultB`·L1177-1197 | 1 | | | | | |
| L11 | simple | AR-02-03 | `47d64f3c` | `model/BlockedFolderModel.ets`·`isPathBlockedB`·L92-105 | 1 | | | | | |
| L12 | simple | AR-02-04 | `615ff4c6` | `model/ScanningModel.ets`·`filterShortAudioB`·L1209-1221 | 1 | | | | | |
| L13 | simple | AR-03-01 | `a910f485` | `viewmodel/SongItemViewModel.ets`·`buildSongItemViewB`·L246-260 | 1 | | | | | |
| L14 | simple | AR-03-02 | `84fa2fcf` | `model/SearchAllSongsModel.ets`·`searchAllSongsB`·L62-77 | 1 | | | | | |
| L15 | simple | AR-03-03 | `c9852817` | `model/SongSortModel.ets`·`sortSongsByFieldB`·L187-202 | 1 | | | | | |
| L16 | simple | AR-03-04 | `ec17b085` | `model/RightABCModel.ets`·`buildSongAbcIndexB`·L23-37 | 1 | | | | | |
| L17 | simple | AR-03-05 | `87b78c0e` | `viewmodel/MainPageViewModel.ets`·`shuffleAllSongsB`·L1686-1696 | 1 | | | | | |
| L18 | simple | AR-03-06 | `3267123d` | `viewmodel/MainPageViewModel.ets`·`toggleSongSelectionB`·L1708-1721 | 1 | | | | | |
| L19 | simple | AR-03-07 | `03c4f083` | `model/SongMenuModel.ets`·`buildSongMenuItemsB`·L79-91 | 1 | | | | | |
| L20 | simple | AR-03-08 | `7e726afe` | `model/SongInformationModel.ets`·`buildSongInfoRowsB`·L63-76 | 1 | | | | | |
| L21 | simple | AR-04-01 | `c9f60e60` | `model/LyricsModel.ets`·`parseLrcLinesC`·L980-996 | 1 | | | | | |
| L22 | simple | AR-04-02 | `38684a0a` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC`·L283-299 | 1 | | | | | |
| L23 | simple | AR-04-03 | `d42d83c7` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC`·L60-77 | 1 | | | | | |
| L24 | simple | AR-04-04 | `9bde689b` | `viewmodel/LyricsViewModel.ets`·`mergeTranslationLinesC`·L317-330 | 1 | | | | | |
| L25 | simple | AR-04-05 | `e4b0d3ec` | `model/MiniLyricsController.ets`·`pickMiniLyricWindowC`·L207-216 | 1 | | | | | |
| L26 | simple | AR-04-06 | `16e801f7` | `model/LyricsSettingsModel.ets`·`clampLyricsSettingsC`·L32-39 | 1 | | | | | |
| L27 | simple | AR-05-01 | `4dd5c5c2` | `viewmodel/AlbumTabViewModel.ets`·`buildAlbumSubtitleC`·L145-157 | 1 | | | | | |
| L28 | simple | AR-05-02 | `d49a27af` | `model/AlbumModel.ets`·`albumIndexKeyC`·L37-47 | 1 | | | | | |
| L29 | simple | AR-05-03 | `7f3382fd` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC`·L21-29 | 1 | | | | | |
| L30 | simple | AR-05-04 | `109b65b7` | `viewmodel/AlbumContentViewModel.ets`·`summarizeAlbumHeaderC`·L335-346 | 1 | | | | | |
| L31 | simple | AR-05-05 | `7bcf94ae` | `model/AlbumContentModel.ets`·`sortAlbumTracksC`·L139-152 | 1 | | | | | |
| L32 | simple | AR-05-06 | `2623f76d` | `model/AlbumContentModel.ets`·`rankAlbumArtistsC`·L167-179 | 1 | | | | | |
| L33 | simple | AR-06-01 | `bd35061e` | `viewmodel/ArtistItemViewModel.ets`·`buildArtistItemD`·L115-126 | 1 | | | | | |
| L34 | simple | AR-06-02 | `0fed1305` | `model/ArtistModel.ets`·`groupArtistsByLetterD`·L24-40 | 1 | | | | | |
| L35 | simple | AR-06-03 | `c6e23b09` | `viewmodel/ArtistContentViewModel.ets`·`buildArtistHeaderD`·L358-370 | 1 | | | | | |
| L36 | simple | AR-06-04 | `394b6351` | `model/ArtistContentModel.ets`·`collapseArtistSongsD`·L140-154 | 1 | | | | | |
| L37 | simple | AR-06-05 | `1318be22` | `model/ArtistContentModel.ets`·`buildArtistAlbumSectionD`·L170-185 | 1 | | | | | |
| L38 | simple | AR-07-01 | `d2f873a3` | `model/FolderModel.ets`·`buildFolderItemD`·L26-42 | 1 | | | | | |
| L39 | simple | AR-07-02 | `4823e083` | `viewmodel/FolderContentPageViewModel.ets`·`searchFolderSongsD`·L411-425 | 1 | | | | | |
| L40 | simple | AR-07-03 | `11495015` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD`·L120-134 | 1 | | | | | |
| L41 | simple | AR-07-04 | `0422df29` | `model/FolderContentPageModel.ets`·`buildFolderSongRowsD`·L126-140 | 1 | | | | | |
| L42 | simple | AR-07-05 | `c9c62d54` | `model/FolderContentPageModel.ets`·`sortFolderSongsD`·L160-176 | 1 | | | | | |
| L43 | simple | AR-07-06 | `662b3fb1` | `model/RightABCModel.ets`·`folderAbcIndexD`·L51-66 | 1 | | | | | |
| L44 | simple | AR-07-07 | `627ba353` | `viewmodel/FolderContentViewModel.ets`·`shuffleFolderQueueD`·L68-81 | 1 | | | | | |
| L45 | simple | AR-07-08 | `9cbad921` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD`·L195-211 | 1 | | | | | |
| L46 | simple | AR-07-09 | `9a102fb8` | `model/FolderMenuModel.ets`·`buildFolderMenuItemsD`·L30-44 | 1 | | | | | |
| L47 | simple | AR-07-10 | `6feb2cc4` | `model/SongInformationModel.ets`·`buildFolderSongInfoD`·L91-108 | 1 | | | | | |
| L48 | simple | AR-08-01 | `525419c7` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE`·L100-112 | 1 | | | | | |
| L49 | simple | AR-08-02 | `7835a670` | `model/PlaylistModel.ets`·`renamePlaylistByIdE`·L93-104 | 1 | | | | | |
| L50 | simple | AR-08-03 | `6aec6c27` | `model/PlaylistModel.ets`·`deletePlaylistByIdE`·L116-126 | 1 | | | | | |
| L51 | simple | AR-08-04 | `a65e55a2` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE`·L1813-1831 | 1 | | | | | |
| L52 | simple | AR-08-05 | `3a6b76c0` | `model/ImportPlaylistModel.ets`·`serializePlaylistLinesE`·L169-180 | 1 | | | | | |
| L53 | simple | AR-08-06 | `ca00bd21` | `model/PlaylistModel.ets`·`sortPlaylistsE`·L139-152 | 1 | | | | | |
| L54 | simple | AR-09-01 | `76d6a251` | `model/MusicLibraryModel.ets`·`summarizeLibraryQualityE`·L226-240 | 1 | | | | | |
| L55 | simple | AR-09-02 | `441fb8bf` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE`·L86-101 | 1 | | | | | |
| L56 | simple | AR-10-01 | `b22810e6` | `model/StatisticsModel.ets`·`topPlayedSongsE`·L74-88 | 1 | | | | | |
| L57 | simple | AR-11-01 | `b863f05c` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF`·L401-416 | 1 | | | | | |
| L58 | simple | AR-11-02 | `2f4cd293` | `model/DesktopLyricsAVSessionController.ets`·`toggleDesktopLyricsLockF`·L430-440 | 1 | | | | | |
| L59 | simple | AR-11-03 | `1c2beb5e` | `model/FloatingStatusBarLyricsController.ets`·`truncateStatusBarLyricF`·L247-259 | 1 | | | | | |
| L60 | simple | AR-11-04 | `7e39b609` | `model/NotificationLyricController.ets`·`buildNotificationLyricTextF`·L110-123 | 1 | | | | | |
| L61 | simple | AR-12-01 | `783d1e20` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF`·L52-64 | 1 | | | | | |
| L62 | simple | AR-12-02 | `ff970e84` | `viewmodel/UserInterfaceViewModel.ets`·`applyShowSongCoverF`·L279-292 | 1 | | | | | |
| L63 | simple | AR-12-03 | `bcd0e4ec` | `viewmodel/MainWallpaperViewModel.ets`·`pickWallpaperSourceF`·L146-160 | 1 | | | | | |
| L64 | simple | AR-12-04 | `13d2e8bd` | `model/UserInterfaceModel.ets`·`advanceCircleCoverAngleF`·L77-89 | 1 | | | | | |
| L65 | simple | AR-12-05 | `22ad26d3` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF`·L165-177 | 1 | | | | | |
| L66 | simple | AR-12-06 | `db591147` | `model/ScreenWakeModel.ets`·`shouldKeepScreenOnF`·L62-74 | 1 | | | | | |
| L67 | simple | AR-12-07 | `5313d7cb` | `model/SystemBarModel.ets`·`computeImmersiveBarStateF`·L150-159 | 1 | | | | | |
| L68 | simple | AR-13-01 | `dcde98df` | `model/AudioOutputModel.ets`·`resolveFocusActionG`·L121-136 | 1 | | | | | |
| L69 | simple | AR-13-02 | `7eef552c` | `model/AudioOutputModel.ets`·`computeChannelGainsG`·L150-163 | 1 | | | | | |
| L70 | simple | AR-13-03 | `d1a7de2e` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG`·L2096-2106 | 1 | | | | | |
| L71 | simple | AR-13-04 | `a262e0fa` | `model/SoundEffectModel.ets`·`mixBandGainsG`·L116-131 | 1 | | | | | |
| L72 | simple | AR-14-01 | `c2d181d8` | `model/LaboratoryModel.ets`·`shouldOpenPlayerOnLaunchG`·L35-44 | 1 | | | | | |
| L73 | simple | AR-14-02 | `534195ed` | `model/LaboratoryModel.ets`·`computeLyricDepthStyleG`·L57-71 | 1 | | | | | |
| L74 | simple | AR-15-01 | `0d316022` | `model/HelpAndFeedbackModel.ets`·`filterFaqByKeywordG`·L51-66 | 1 | | | | | |
| L75 | simple | AR-15-02 | `b5ca1085` | `model/HelpAndFeedbackModel.ets`·`validateFeedbackG`·L78-95 | 1 | | | | | |
| L76 | simple | AR-15-03 | `b43297cd` | `model/AboutModel.ets`·`compareSemverG`·L102-118 | 1 | | | | | |
| L77 | simple | AR-15-04 | `68d50eb1` | `model/CreditsModel.ets`·`sortDedupeLicensesG`·L149-162 | 1 | | | | | |
| H01 | hard | AR-01-01 | `e88ea122` | `model/AudioPlayerService.ets`·`resolveTransportIndexA_H1`·L2180-2192 | 5 | | | | | |
| H02 | hard | AR-01-02 | `4d414ee8` | `model/AudioPlayerService.ets`·`nextPlayModeA_H2`·L2244-2253 | 5 | | | | | |
| H03 | hard | AR-01-03 | `4201f499` | `model/PlayQueueModel.ets`·`removeFromQueueA_H3`·L99-111 | 5 | | | | | |
| H04 | hard | AR-01-04 | `681cdb5b` | `model/SoundEffectModel.ets`·`clampPlaybackSpeedA_H4`·L170-181 | 5 | | | | | |
| H05 | hard | AR-01-05 | `1aab41ab` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA_H5`·L2279-2292 | 5 | | | | | |
| H06 | hard | AR-01-06 | `880bb854` | `model/SleepTimerService.ets`·`computeSleepStopTimeA_H6`·L205-215 | 5 | | | | | |
| H07 | hard | AR-01-07 | `3d8678e2` | `model/CurrentSongCoverController.ets`·`resolveCoverUriA_H7`·L247-256 | 5 | | | | | |
| H08 | hard | AR-01-08 | `ce590ecd` | `viewmodel/PlayerPageViewModel.ets`·`buildQuickActionsA_H8`·L1404-1413 | 5 | | | | | |
| H09 | hard | AR-02-01 | `d48c4ccb` | `model/ScanningModel.ets`·`collectScannedAudioB_H9`·L1268-1282 | 5 | | | | | |
| H10 | hard | AR-02-02 | `73a864f3` | `model/ScanningModel.ets`·`diffRescanResultB_H10`·L1331-1351 | 5 | | | | | |
| H11 | hard | AR-02-03 | `a95e2adb` | `model/BlockedFolderModel.ets`·`isPathBlockedB_H11`·L162-175 | 5 | | | | | |
| H12 | hard | AR-02-04 | `ffb0a575` | `model/ScanningModel.ets`·`filterShortAudioB_H12`·L1391-1403 | 5 | | | | | |
| H13 | hard | AR-03-01 | `002c1896` | `viewmodel/SongItemViewModel.ets`·`buildSongItemViewB_H13`·L325-339 | 5 | | | | | |
| H14 | hard | AR-03-02 | `abac771b` | `model/SearchAllSongsModel.ets`·`searchAllSongsB_H14`·L166-181 | 5 | | | | | |
| H15 | hard | AR-03-03 | `86063731` | `model/SongSortModel.ets`·`sortSongsByFieldB_H15`·L258-273 | 5 | | | | | |
| H16 | hard | AR-03-04 | `ce87d31f` | `model/RightABCModel.ets`·`buildSongAbcIndexB_H16`·L105-119 | 5 | | | | | |
| H17 | hard | AR-03-05 | `f2a76d98` | `viewmodel/MainPageViewModel.ets`·`shuffleAllSongsB_H17`·L1751-1761 | 5 | | | | | |
| H18 | hard | AR-03-06 | `30bafbe8` | `viewmodel/MainPageViewModel.ets`·`toggleSongSelectionB_H18`·L1828-1841 | 5 | | | | | |
| H19 | hard | AR-03-07 | `56159dda` | `model/SongMenuModel.ets`·`buildSongMenuItemsB_H19`·L184-196 | 5 | | | | | |
| H20 | hard | AR-03-08 | `af11348a` | `model/SongInformationModel.ets`·`buildSongInfoRowsB_H20`·L192-205 | 5 | | | | | |
| H21 | hard | AR-04-01 | `1508637f` | `model/LyricsModel.ets`·`parseLrcLinesC_H21`·L1055-1071 | 5 | | | | | |
| H22 | hard | AR-04-02 | `6318174a` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC_H22`·L364-380 | 5 | | | | | |
| H23 | hard | AR-04-03 | `1cce447d` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC_H23`·L105-122 | 5 | | | | | |
| H24 | hard | AR-04-04 | `66ff3b42` | `viewmodel/LyricsViewModel.ets`·`mergeTranslationLinesC_H24`·L423-436 | 5 | | | | | |
| H25 | hard | AR-04-05 | `90f5d7be` | `model/MiniLyricsController.ets`·`pickMiniLyricWindowC_H25`·L300-309 | 5 | | | | | |
| H26 | hard | AR-04-06 | `919b9774` | `model/LyricsSettingsModel.ets`·`clampLyricsSettingsC_H26`·L101-108 | 5 | | | | | |
| H27 | hard | AR-05-01 | `d14d1bc3` | `viewmodel/AlbumTabViewModel.ets`·`buildAlbumSubtitleC_H27`·L217-229 | 5 | | | | | |
| H28 | hard | AR-05-02 | `4328de4c` | `model/AlbumModel.ets`·`albumIndexKeyC_H28`·L88-98 | 5 | | | | | |
| H29 | hard | AR-05-03 | `228d76eb` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC_H29`·L61-69 | 5 | | | | | |
| H30 | hard | AR-05-04 | `d30b67bd` | `viewmodel/AlbumContentViewModel.ets`·`summarizeAlbumHeaderC_H30`·L359-370 | 5 | | | | | |
| H31 | hard | AR-05-05 | `4a3b29ef` | `model/AlbumContentModel.ets`·`sortAlbumTracksC_H31`·L273-286 | 5 | | | | | |
| H32 | hard | AR-05-06 | `efa29167` | `model/AlbumContentModel.ets`·`rankAlbumArtistsC_H32`·L349-361 | 5 | | | | | |
| H33 | hard | AR-06-01 | `7fa77d26` | `viewmodel/ArtistItemViewModel.ets`·`buildArtistItemD_H33`·L187-198 | 5 | | | | | |
| H34 | hard | AR-06-02 | `8854212b` | `model/ArtistModel.ets`·`groupArtistsByLetterD_H34`·L84-100 | 5 | | | | | |
| H35 | hard | AR-06-03 | `842c54fb` | `viewmodel/ArtistContentViewModel.ets`·`buildArtistHeaderD_H35`·L397-409 | 5 | | | | | |
| H36 | hard | AR-06-04 | `54a04aea` | `model/ArtistContentModel.ets`·`collapseArtistSongsD_H36`·L197-211 | 5 | | | | | |
| H37 | hard | AR-06-05 | `f354b231` | `model/ArtistContentModel.ets`·`buildArtistAlbumSectionD_H37`·L357-372 | 5 | | | | | |
| H38 | hard | AR-07-01 | `c477daf6` | `model/FolderModel.ets`·`buildFolderItemD_H38`·L111-127 | 5 | | | | | |
| H39 | hard | AR-07-02 | `9fb3bf93` | `viewmodel/FolderContentPageViewModel.ets`·`searchFolderSongsD_H39`·L487-501 | 5 | | | | | |
| H40 | hard | AR-07-03 | `0127c510` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD_H40`·L267-281 | 5 | | | | | |
| H41 | hard | AR-07-04 | `e975522f` | `model/FolderContentPageModel.ets`·`buildFolderSongRowsD_H41`·L235-249 | 5 | | | | | |
| H42 | hard | AR-07-05 | `26c1dca4` | `model/FolderContentPageModel.ets`·`sortFolderSongsD_H42`·L313-329 | 5 | | | | | |
| H43 | hard | AR-07-06 | `e8c7c227` | `model/RightABCModel.ets`·`folderAbcIndexD_H43`·L243-258 | 5 | | | | | |
| H44 | hard | AR-07-07 | `ea0b8071` | `viewmodel/FolderContentViewModel.ets`·`shuffleFolderQueueD_H44`·L152-165 | 5 | | | | | |
| H45 | hard | AR-07-08 | `5450b4d6` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD_H45`·L445-461 | 5 | | | | | |
| H46 | hard | AR-07-09 | `9d45d4ca` | `model/FolderMenuModel.ets`·`buildFolderMenuItemsD_H46`·L86-100 | 5 | | | | | |
| H47 | hard | AR-07-10 | `68db2c88` | `model/SongInformationModel.ets`·`buildFolderSongInfoD_H47`·L235-252 | 5 | | | | | |
| H48 | hard | AR-08-01 | `1e34dbb9` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE_H48`·L124-136 | 5 | | | | | |
| H49 | hard | AR-08-02 | `b6f83e06` | `model/PlaylistModel.ets`·`renamePlaylistByIdE_H49`·L242-253 | 5 | | | | | |
| H50 | hard | AR-08-03 | `c3e6315a` | `model/PlaylistModel.ets`·`deletePlaylistByIdE_H50`·L311-321 | 5 | | | | | |
| H51 | hard | AR-08-04 | `14979046` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE_H51`·L1887-1905 | 5 | | | | | |
| H52 | hard | AR-08-05 | `9b1e27c1` | `model/ImportPlaylistModel.ets`·`serializePlaylistLinesE_H52`·L221-232 | 5 | | | | | |
| H53 | hard | AR-08-06 | `ce0bffea` | `model/PlaylistModel.ets`·`sortPlaylistsE_H53`·L355-368 | 5 | | | | | |
| H54 | hard | AR-09-01 | `fd868d88` | `model/MusicLibraryModel.ets`·`summarizeLibraryQualityE_H54`·L254-268 | 5 | | | | | |
| H55 | hard | AR-09-02 | `f6f48d1c` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE_H55`·L263-278 | 5 | | | | | |
| H56 | hard | AR-10-01 | `b2b7c83a` | `model/StatisticsModel.ets`·`topPlayedSongsE_H56`·L153-167 | 5 | | | | | |
| H57 | hard | AR-11-01 | `7c2723e4` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF_H57`·L505-520 | 5 | | | | | |
| H58 | hard | AR-11-02 | `d5c84a92` | `model/DesktopLyricsAVSessionController.ets`·`toggleDesktopLyricsLockF_H58`·L586-596 | 5 | | | | | |
| H59 | hard | AR-11-03 | `298c155f` | `model/FloatingStatusBarLyricsController.ets`·`truncateStatusBarLyricF_H59`·L293-305 | 5 | | | | | |
| H60 | hard | AR-11-04 | `35555f5e` | `model/NotificationLyricController.ets`·`buildNotificationLyricTextF_H60`·L135-148 | 5 | | | | | |
| H61 | hard | AR-12-01 | `3280782f` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF_H61`·L185-197 | 5 | | | | | |
| H62 | hard | AR-12-02 | `9558a357` | `viewmodel/UserInterfaceViewModel.ets`·`applyShowSongCoverF_H62`·L367-380 | 5 | | | | | |
| H63 | hard | AR-12-03 | `27da8fbd` | `viewmodel/MainWallpaperViewModel.ets`·`pickWallpaperSourceF_H63`·L226-240 | 5 | | | | | |
| H64 | hard | AR-12-04 | `64f18717` | `model/UserInterfaceModel.ets`·`advanceCircleCoverAngleF_H64`·L229-241 | 5 | | | | | |
| H65 | hard | AR-12-05 | `5792a2e0` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF_H65`·L205-217 | 5 | | | | | |
| H66 | hard | AR-12-06 | `0293fa3f` | `model/ScreenWakeModel.ets`·`shouldKeepScreenOnF_H66`·L94-106 | 5 | | | | | |
| H67 | hard | AR-12-07 | `323c3643` | `model/SystemBarModel.ets`·`computeImmersiveBarStateF_H67`·L245-254 | 5 | | | | | |
| H68 | hard | AR-13-01 | `1aebf4c4` | `model/AudioOutputModel.ets`·`resolveFocusActionG_H68`·L228-243 | 5 | | | | | |
| H69 | hard | AR-13-02 | `0190384b` | `model/AudioOutputModel.ets`·`computeChannelGainsG_H69`·L292-305 | 5 | | | | | |
| H70 | hard | AR-13-03 | `b03cb1aa` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG_H70`·L2365-2375 | 5 | | | | | |
| H71 | hard | AR-13-04 | `1b5b2932` | `model/SoundEffectModel.ets`·`mixBandGainsG_H71`·L235-250 | 5 | | | | | |
| H72 | hard | AR-14-01 | `fab3121e` | `model/LaboratoryModel.ets`·`shouldOpenPlayerOnLaunchG_H72`·L87-96 | 5 | | | | | |
| H73 | hard | AR-14-02 | `a36a9d65` | `model/LaboratoryModel.ets`·`computeLyricDepthStyleG_H73`·L251-265 | 5 | | | | | |
| H74 | hard | AR-15-01 | `e17bf040` | `model/HelpAndFeedbackModel.ets`·`filterFaqByKeywordG_H74`·L163-178 | 5 | | | | | |
| H75 | hard | AR-15-02 | `771b3ac3` | `model/HelpAndFeedbackModel.ets`·`validateFeedbackG_H75`·L239-256 | 5 | | | | | |
| H76 | hard | AR-15-03 | `932b2980` | `model/AboutModel.ets`·`compareSemverG_H76`·L157-173 | 5 | | | | | |
| H77 | hard | AR-15-04 | `cc00a1e8` | `model/CreditsModel.ets`·`sortDedupeLicensesG_H77`·L188-201 | 5 | | | | | |
| X01 | complex | AR-01-01 | `0fdc6545` | `model/AudioPlayerService.ets`·`resolveTransportIndexA_X1`·L2441-2453<br>`model/AudioPlayerService.ets`·`resolveResumeIndexX_X1`·L2455-2468 | 3 | | | | | |
| X02 | complex | AR-01-06 | `37ccbec1` | `model/SleepTimerService.ets`·`formatSleepRemainX_X2`·L277-289<br>`model/SleepTimerService.ets`·`computeSleepStopTimeA_X2`·L329-339 | 3 | | | | | |
| X03 | complex | AR-02-01 | `67783335` | `model/ScanningModel.ets`·`collectScannedAudioB_X3`·L1487-1501<br>`model/ScanningModel.ets`·`countAudioByDirX_X3`·L1503-1520 | 3 | | | | | |
| X04 | complex | AR-04-02 | `05bd8b33` | `viewmodel/LyricsViewModel.ets`·`locateActiveLineC_X4`·L554-570<br>`viewmodel/LyricsViewModel.ets`·`lyricScrollOffsetX_X4`·L572-586 | 3 | | | | | |
| X05 | complex | AR-08-01 | `cf029b17` | `model/NewPlaylistModel.ets`·`validateNewPlaylistNameE_X5`·L209-221<br>`model/NewPlaylistModel.ets`·`normalizePlaylistNameX_X5`·L223-237 | 3 | | | | | |
| X06 | complex | AR-13-03 | `da23476d` | `model/AudioPlayerService.ets`·`buildFadeEnvelopeG_X6`·L2512-2522<br>`model/AudioPlayerService.ets`·`buildFadeStepsX_X6`·L2524-2533 | 3 | | | | | |
| X07 | complex | AR-01-05 | `a6fecebe` | `model/AudioPlayerService.ets`·`seekPositionFromRatioA_X7`·L2580-2593<br>`viewmodel/PlayerPageViewModel.ets`·`dragPercentToMsX_X7`·L1445-1458 | 4 | | | | | |
| X08 | complex | AR-03-02 | `4a4f8a90` | `model/SearchAllSongsModel.ets`·`searchAllSongsB_X8`·L292-307<br>`viewmodel/MainPageViewModel.ets`·`searchHighlightRangesX_X8`·L1917-1935 | 4 | | | | | |
| X09 | complex | AR-05-03 | `e5ddc3cc` | `model/AlbumListSettingsModel.ets`·`normalizeAlbumGridSettingsC_X9`·L117-125<br>`viewmodel/AlbumTabViewModel.ets`·`albumGridTemplateX_X9`·L293-307 | 4 | | | | | |
| X10 | complex | AR-07-03 | `c61d0094` | `model/BlockedFolderModel.ets`·`filterBlockedFoldersD_X10`·L354-368<br>`model/FolderModel.ets`·`applyHiddenFoldersX_X10`·L157-173 | 4 | | | | | |
| X11 | complex | AR-12-01 | `25112608` | `model/UserInterfaceModel.ets`·`resolveEffectiveThemeF_X11`·L308-320<br>`viewmodel/UserInterfaceViewModel.ets`·`resolveColorModeX_X11`·L398-407 | 4 | | | | | |
| X12 | complex | AR-11-01 | `567c15cd` | `model/DesktopLyricsAVSessionController.ets`·`transitionDesktopLyricsStateF_X12`·L645-660<br>`viewmodel/LyricsViewModel.ets`·`desktopLyricsStateX_X12`·L609-618 | 4 | | | | | |
| X13 | complex | AR-03-04 | `44acac93` | `model/RightABCModel.ets`·`buildSongAbcIndexB_X13`·L301-315 | 5 | | | | | |
| X14 | complex | AR-09-02 | `dc1b78a9` | `model/SearchAllSongsModel.ets`·`searchLibraryTracksE_X14`·L326-341 | 5 | | | | | |
| X15 | complex | AR-07-05 | `294c78c8` | `model/FolderContentPageModel.ets`·`sortFolderSongsD_X15`·L536-552 | 5 | | | | | |
| X16 | complex | AR-07-08 | `68accb1f` | `model/FolderContentPageModel.ets`·`toggleFolderSelectionD_X16`·L586-602 | 5 | | | | | |
| X17 | complex | AR-01-02 | `c6c88204` | `model/AudioPlayerService.ets`·`nextPlayModeA_X17`·L2712-2721 | 9 | | | | | |
| X18 | complex | AR-04-03 | `d20a871f` | `model/KaraokeRenderDecision.ets`·`karaokeFillRatioC_X18`·L252-269 | 9 | | | | | |
| X19 | complex | AR-08-04 | `dd72ceb8` | `model/MusicDatabase.ets`·`toggleSongInPlaylistE_X19`·L1984-2002 | 9 | | | | | |
| X20 | complex | AR-12-05 | `700e56a3` | `model/FlowingLightModel.ets`·`flowingLightColorAtPhaseF_X20`·L283-295 | 9 | | | | | |

## 汇总（分层报告）

| 指标 | 简单层(77) | 难例层(77) | 复杂层(20) | 全部(174) |
|------|-----------|-----------|-----------|-----------|
| 文件级准确率 | | | | |
| 符号级准确率 | | | | |
| 行级平均 IoU | | | | |
| 干扰命中率（理想 0） | | | | |
| 跨 AR 干扰被误判为目标 AR 的次数 | — | | | |
| 多段正例召回率（找全 2 段的比例） | — | — | | |
| 综合命中（符号正确且未命中干扰） | | | | |

> 难例层重点考查：在同一 commit/文件中混入其它 AR 的真实代码时，系统能否只挑出目标 AR 的实现而不被同域相似代码带偏。
> 复杂层另考查：多段/跨文件实现的"找全"能力（multi/xfile 场景每用例 2 段正例，全部命中才算找全）、
> 跨 SR 同语义家族（ABC 索引/搜索/排序/多选等）的区分能力、以及大候选集（1 正例 + 9 干扰）下的精确率。
> 标准答案以 `ground-truth.json` 为准。
