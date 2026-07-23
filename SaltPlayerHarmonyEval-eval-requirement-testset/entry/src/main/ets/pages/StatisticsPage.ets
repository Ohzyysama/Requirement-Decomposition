// StatisticsPage.ets
// View layer: Statistics page for Salt Player - HDS styled.
// Shows listening music rank (top 100 most played songs)
// MVVM: This View uses StatisticsViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating business logic (data loading, play actions) to the ViewModel.
//
// Uses HDS HdsNavDestination for full HarmonyOS OS6 native styling.

import lottie, { AnimationItem } from '@ohos/lottie'
import { promptAction } from '@kit.ArkUI'
import { StatisticsViewModel } from '../viewmodel/StatisticsViewModel'
import { StatisticsSongData } from '../model/StatisticsModel'
import { SONG_QUALITY_NORMAL, SONG_QUALITY_HQ, SONG_QUALITY_SQ, SONG_QUALITY_HI_RES } from '../model/SongItemModel'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct StatisticsPage {
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  // ViewModel instance - manages all data and business logic for this page
  @State viewModel: StatisticsViewModel = new StatisticsViewModel()

  // Reactive live-refresh triggers — scanVersion bumps when the library changes
  // (song removal, scan), playCountVersion bumps when a play crosses the
  // spec21 increment threshold. Either one reloads the Top 100 list.
  @StorageLink('scanVersion') @Watch('onDataChanged') scanVersion: number = 0
  @StorageLink('playCountVersion') @Watch('onDataChanged') playCountVersion: number = 0
  // Mirror of the global currentSongId so the highlight auto-updates when the
  // player advances through the queue without requiring a page reopen.
  @StorageLink('currentSongId') @Watch('onCurrentSongIdChanged') currentSongId: string = ''

  private listScroller: Scroller = new Scroller()
  private navPathStack: NavPathStack = new NavPathStack()

  onDataChanged(): void {
    this.viewModel.loadStatisticsData()
  }

  onCurrentSongIdChanged(): void {
    this.viewModel.currentSongId = this.currentSongId
  }

  // Lottie animation (View-only concern: animation rendering)
  private lottieRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private lottieCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lottieRenderingSettings)
  private lottieAnimItem: AnimationItem | null = null
  private readonly LOTTIE_ANIM_NAME: string = 'lottie_empty_statistics'

  aboutToAppear(): void {
    // Seed the current song id into the VM so the first render highlights correctly.
    this.viewModel.currentSongId = this.currentSongId
    // Delegate data loading to ViewModel (fire-and-forget — the VM flips isLoading).
    this.viewModel.loadStatisticsData()
  }

  aboutToDisappear(): void {
    lottie.destroy(this.LOTTIE_ANIM_NAME)
  }

  build() {
    HdsNavDestination() {
      Stack() {
        if (this.viewModel.isLoading) {
          // Loading state
          Column() {
          }
          .width('100%')
          .height('100%')
        } else if (this.viewModel.isEmpty) {
          // Empty state - Lottie animation centered
          this.NoneBox()
        } else {
          // Song ranking list
          this.SongRankList()
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.statistics'),
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.listScroller])
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ======================== None Box (Empty State) ========================
  @Builder
  NoneBox() {
    Column() {
      Canvas(this.lottieCanvasCtx)
        .width(100)
        .height(100)
        .opacity(0.75)
        .onReady(() => {
          this.lottieAnimItem = lottie.loadAnimation({
            container: this.lottieCanvasCtx,
            renderer: 'canvas',
            loop: true,
            autoplay: true,
            name: this.LOTTIE_ANIM_NAME,
            path: 'lottie_empty.json'
          })
          if (this.lottieAnimItem) {
            this.lottieAnimItem.setSpeed(0.5)
          }
        })
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // ======================== Song Rank List ========================
  @Builder
  SongRankList() {
    List({ scroller: this.listScroller }) {
      ForEach(this.viewModel.statisticsSongs, (item: StatisticsSongData, index: number) => {
        ListItem() {
          Row() {
            // Song item area (cover + title + artist) — clickable to play
            Row() {
              // Song cover — Track.coverUri is a raw extraction key, not a
              // displayable Image src. Resolve via CoverCacheDb / extractor
              // through ImageKnife, mirroring SongItemComponent.
              StatisticsCoverImage({
                songId: item.song.id,
                fileUri: item.song.fileUri ?? '',
                dateModified: item.song.dateModified ?? 0,
                fileSize: item.song.size ?? 0
              })

              // Song title and artist
              Column() {
                Text(item.song.title)
                  .fontSize(15)
                  .fontColor(this.viewModel.isSongCurrent(item.song.id) ? $r('app.color.salt_color_high_light') :
                    (item.song.valid ? $r('app.color.salt_color_icon_foreground') : $r('app.color.invalid')))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Row() {
                  if (item.song.quality === SONG_QUALITY_HQ) {
                    Image($r('app.media.bq_song_tag_hq'))
                      .width(16)
                      .height(10)
                      .borderRadius(2)
                      .objectFit(ImageFit.Cover)
                  } else if (item.song.quality === SONG_QUALITY_SQ) {
                    Image($r('app.media.bq_song_tag_sq'))
                      .width(16)
                      .height(10)
                      .borderRadius(2)
                      .objectFit(ImageFit.Cover)
                  } else if (item.song.quality === SONG_QUALITY_HI_RES) {
                    Image($r('app.media.ic_song_quality_hi_res'))
                      .width(16)
                      .height(10)
                      .borderRadius(2)
                      .objectFit(ImageFit.Cover)
                  }
                  Text(item.song.subTitle || item.song.artist)
                    .fontSize(12)
                    .fontColor(this.viewModel.isSongCurrent(item.song.id) ? $r('app.color.salt_color_high_light') :
                      (item.song.valid ? $r('app.color.colorSubTextForeground') : $r('app.color.invalid')))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ left: item.song.quality === SONG_QUALITY_NORMAL ? 0 : 4 })
                }
                .margin({ top: 1 })
                .alignItems(VerticalAlign.Center)
              }
              .layoutWeight(1)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12, right: 8 })
            }
            .layoutWeight(1)
            .height('100%')
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              // Delegate play action to ViewModel
              this.viewModel.playSong(item.song)
            })

            // Add to play next button (+)
            Stack({ alignContent: Alignment.Start }) {
              Image($r('app.media.ic_add_small_tinted'))
                .width(14)
                .height(14)
                .borderRadius(7)
                .backgroundColor('#80FFFFFF')
                .fillColor($r('app.color.colorSubIconForeground'))
                .padding(1)
                .margin({ left: 21 })
                .objectFit(ImageFit.Contain)
            }
            .width(48)
            .height('100%')
            .onClick(() => {
              this.viewModel.addToPlayNext(item.song)
              promptAction.showToast({ message: $r('app.string.successfully_added_to_next_play') })
            })
            .accessibilityText('下一首播放')

            // Right side: play count
            Column() {
              Text(`${item.playedTimes}`)
                .fontSize(12)
                .fontColor($r('app.color.colorSubTextForeground'))
                .textAlign(TextAlign.Center)
                .width(48)
            }
            .width(48)
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ right: 8 })
          }
          .width('100%')
          .height(72)
          .alignItems(VerticalAlign.Center)
        }
      }, (item: StatisticsSongData) => item.song.id)
    }
    .width('100%')
    .height('100%')
    .divider({ strokeWidth: 0 })
    .contentEndOffset(MiniPlayerDefaults.TOTAL_HEIGHT)
  }
}

// Per-row cover loader: hits the JPEG cache first, then falls back to async
// RDB → audio-file extraction. Same pipeline as SongItemComponent so
// statistics rows show the same artwork as the rest of the app.
@Component
struct StatisticsCoverImage {
  @Prop @Watch('onSongIdChanged') songId: string = ''
  @Prop fileUri: string = ''
  @Prop dateModified: number = 0
  @Prop fileSize: number = 0
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()

  private loadedSongId: string = ''

  aboutToAppear(): void {
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover
    this.loadCover()
  }

  aboutToRecycle(): void {
    this.loadedSongId = ''
  }

  onSongIdChanged(): void {
    if (this.songId !== this.loadedSongId) {
      this.loadCover()
    }
  }

  private loadCover(): void {
    const songId = this.songId
    this.loadedSongId = songId
    if (!songId || songId.length === 0) return

    const uri = CoverCacheDb.getCoverFileUri(songId)
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri
      return
    }

    const capturedId = songId
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (this.loadedSongId !== capturedId) return
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri
        return
      }
      if (this.fileUri.length === 0) return
      return CoverArtExtractor.extractAndCache(songId, this.fileUri,
        this.dateModified, this.fileSize)
    }).then(() => {
      if (this.loadedSongId !== capturedId) return
      const u = CoverCacheDb.getCoverFileUri(songId)
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Stack() {
      ImageKnifeComponent({ imageKnifeOption: this.coverOption })
        .width(50)
        .height(50)
    }
    .width(50)
    .height(50)
    .borderRadius(4)
    .clip(true)
    .margin({ left: 16 })
    .backgroundColor($r('app.color.salt_color_song_cover'))
  }
}
