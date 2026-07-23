// MusicLibraryPage.ets
// View layer: Music Library page for Salt Player - corresponds to Android MusicLibraryScreen.kt
// Uses HDS HdsNavDestination for full HarmonyOS OS6 native styling:
//   - MINI title mode with system back button
//   - Dynamic blur title bar bound to the content scroller
//   - Search entry rendered as a titleBar menu icon (no custom top-bar row)
// MVVM: This View uses MusicLibraryViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating business logic and chart drawing to the ViewModel.

import { MusicLibraryViewModel } from '../viewmodel/MusicLibraryViewModel'
import { PieEntryData, MusicLibraryData, MusicLibraryDataSource } from '../model/MusicLibraryModel'
import { SearchAllSongsRouterParams } from '../model/SearchAllSongsModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct MusicLibraryPage {
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  // ViewModel keeps chart drawing + gesture handling state. The displayed
  // statistics live as plain @State on the View so re-renders are guaranteed —
  // @State + @Observed/@Track did not propagate inner mutations on this build,
  // which left the page frozen at the constructor defaults (all zeros).
  @State viewModel: MusicLibraryViewModel = new MusicLibraryViewModel()
  @State totalSize: string = '0.00 B'
  @State hqCount: string = '0'
  @State sqCount: string = '0'
  @State hiResCount: string = '0'
  @State othersCount: string = '0'
  @State hasPieData: boolean = false
  @State validCount: number = 0
  @StorageProp('isSystemDark') @Watch('onDarkModeChanged') isSystemDark: boolean = false
  // Re-fetch statistics when a scan or refresh bumps scanVersion so counts and
  // pie chart stay in sync without requiring a page reopen.
  @StorageLink('scanVersion') @Watch('reload') scanVersion: number = 0
  // Current playing state, propagated to SearchAllSongsPage so its mini-player
  // header reflects what the user is hearing — same contract as MainPage's
  // search entry.
  @StorageProp('currentSongTitle') currentSongTitle: string = ''
  @StorageProp('currentSongArtist') currentSongArtist: string = ''
  @StorageProp('isPlaying') isPlaying: boolean = false

  // Pie chart canvas settings (View-owned, as they are pure UI resources)
  private pieCanvasSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private pieCanvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.pieCanvasSettings)
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  aboutToAppear(): void {
    this.updateValueLineColor()
    // Set up the ViewModel's redraw callback to trigger canvas repaint
    this.viewModel.onRequestRedraw = () => {
      this.drawChart()
    }
    this.reload()
  }

  // Load current library statistics from RDB into the ViewModel. Called on
  // appear and whenever scanVersion changes. Errors are logged rather than
  // swallowed so a failed RDB read doesn't leave stale UI without a trace.
  private reload(): void {
    MusicLibraryDataSource.loadMusicLibraryData().then((data: MusicLibraryData) => {
      this.viewModel.loadData(data)
      this.totalSize = data.totalSize
      this.hqCount = data.hqCount
      this.sqCount = data.sqCount
      this.hiResCount = data.hiResCount
      this.othersCount = data.othersCount
      this.hasPieData = data.pieEntries.length > 0
      this.validCount = this.viewModel.validCount
      this.drawChart()
    }).catch((e: Error) => {
      hilog.error(0, 'MusicLibraryPage', `loadMusicLibraryData failed: ${e?.message ?? e}`)
    })
  }

  private updateValueLineColor(): void {
    this.viewModel.valueLineColor = this.isSystemDark ? '#ebeef1' : '#1e1715'
  }

  private onDarkModeChanged(): void {
    this.updateValueLineColor()
    this.drawChart()
  }

  aboutToDisappear(): void {
    this.viewModel.stopDeceleration()
  }

  private drawChart(): void {
    this.viewModel.drawPieChart(this.pieCanvasContext)
  }

  private openSearch(): void {
    this.navPathStack.pushPath({
      name: 'SearchAllSongsPage',
      param: {
        validCount: this.validCount,
        currentSongTitle: this.currentSongTitle,
        currentSongArtist: this.currentSongArtist,
        isPlaying: this.isPlaying
      } as SearchAllSongsRouterParams
    })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.PieChartSection()

          // Quality statistics card — rendered inline, not via @Builder.
          // @Builder captures string params at the call site, which prevents
          // @State reads threaded through that chain from ever re-subscribing
          // on reload (diagnosed and fixed previously in commit 2f89b62). The
          // labels are static Resource/string literals, but every `value` must
          // be a direct @State read inside build().
          Column() {
            Column() {
              Text($r('app.string.size'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.totalSize)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16, right: 16 })

            Column() {
              Text('HQ')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.hqCount)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16, right: 16 })

            Column() {
              Text('SQ')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.sqCount)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16, right: 16 })

            Column() {
              Text('Hi-Res')
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.hiResCount)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider()
              .strokeWidth(0.5)
              .color($r('sys.color.comp_divider'))
              .margin({ left: 16, right: 16 })

            Column() {
              Text($r('app.string.others'))
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
              Text(this.othersCount)
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.font_primary'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }
          .width('100%')
          .borderRadius(20)
          .clip(true)
          .backgroundColor(this.mainPageWallpaperPath.length > 0
        ? $r('app.color.colorItemBackgroundHalfTransparency')
        : $r('sys.color.comp_background_list_card'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .contentEndOffset(MiniPlayerDefaults.TOTAL_HEIGHT)
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.music_library'),
        },
        menu: {
          value: [
            {
              content: {
                icon: $r('app.media.ic_search'),
                label: $r('app.string.search'),
                action: () => {
                  this.openSearch()
                },
              },
            },
          ],
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ======================== Pie Chart Card ========================
  @Builder
  PieChartSection() {
    if (this.hasPieData) {
      Column() {
        Canvas(this.pieCanvasContext)
          .width('100%')
          .aspectRatio(1)
          .margin({ top: 8 })
          .onReady(() => {
            this.drawChart()
          })
          .gesture(
            GestureGroup(GestureMode.Exclusive,
              PanGesture({ fingers: 1, distance: 8 })
                .onActionStart((event: GestureEvent) => {
                  const finger = event.fingerList[0]
                  this.viewModel.handlePanStart(finger.localX, finger.localY)
                })
                .onActionUpdate((event: GestureEvent) => {
                  const finger = event.fingerList[0]
                  this.viewModel.handlePanUpdate(finger.localX, finger.localY)
                })
                .onActionEnd(() => {
                  this.viewModel.handlePanEnd()
                }),
              TapGesture({ count: 1 })
                .onAction((event: GestureEvent) => {
                  const finger = event.fingerList[0]
                  this.viewModel.handleTap(finger.localX, finger.localY)
                })
            )
          )

        Row() {
          ForEach(this.viewModel.pieEntries, (entry: PieEntryData, _index: number) => {
            Row() {
              Circle()
                .width(8)
                .height(8)
                .fill(entry.color)
                .margin({ right: 6 })

              Text(entry.label)
                .fontSize(12)
                .fontColor($r('sys.color.font_secondary'))
            }
            .alignItems(VerticalAlign.Center)
            .margin({ right: 14 })
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16, bottom: 14, top: 4 })
      }
      .width('100%')
      .borderRadius(20)
      .clip(true)
      .backgroundColor(this.mainPageWallpaperPath.length > 0
        ? $r('app.color.colorItemBackgroundHalfTransparency')
        : $r('sys.color.comp_background_list_card'))
      .margin({ bottom: 12 })
    }
  }

  // ======================== Quality Stats Row ========================
  // No @Builder helper here by design. The Quality section is rendered inline
  // inside build() because @Builder captures string params at the call site,
  // which prevents @State reads threaded through that chain from re-subscribing
  // on reload — see commit 2f89b62 for the full diagnosis.
}
