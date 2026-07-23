// CreditsPage.ets
// View layer for CreditsPage - responsible for UI presentation and user interaction.
// Uses HDS HdsNavDestination for full HarmonyOS OS6 native styling.
//
// MVVM Architecture:
//   View (this file) -> ViewModel (CreditsViewModel.ets) -> Model (CreditsModel.ets)

import CreditsViewModel from '../viewmodel/CreditsViewModel';
import { CreditsSectionModel } from '../model/CreditsModel';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct CreditsPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  // View binds to ViewModel data
  @State viewModel: CreditsViewModel = new CreditsViewModel()

  build() {
    HdsNavDestination() {
      Column() {
        // Credits scroll area -- auto-scroll, no user interaction
        Scroll(this.scroller) {
          Column() {
            // Top blank: credits start completely off-screen.
            Blank().height(this.viewModel.contentAreaHeight)

            // Render all credits sections from ViewModel
            ForEach(this.viewModel.sections, (section: CreditsSectionModel, index: number) => {
              if (index > 0) {
                Blank().height(24)
              }
              this.TitleText(section.title)
              ForEach(section.names, (name: string, nameIndex: number) => {
                this.ParagraphText(name)
              }, (name: string, nameIndex: number) => `${index}_${nameIndex}_${name}`)
            }, (_section: CreditsSectionModel, index: number) => `section_${index}`)

            Blank().height(24)
            // Copyright
            this.TitleText(this.viewModel.copyrightText)

            // Bottom area: fills the visually-visible space between the
            // floating HdsNavDestination title bar and the MiniPlayer.
            Column() {
              if (this.viewModel.projectInitiationResource !== undefined) {
                Text(this.viewModel.projectInitiationResource)
                  .fontSize(16)
                  .fontColor($r('app.color.salt_color_icon_foreground'))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .padding({ left: 16, right: 16 })
              }
            }
            .width('100%')
            .height(Math.max(0,
              this.viewModel.contentAreaHeight - MiniPlayerDefaults.TOTAL_HEIGHT))
            .justifyContent(FlexAlign.Center)

            // Bottom padding: pushes the Column above into the visible area
            // instead of leaving it under the MiniPlayer.
            Blank().height(MiniPlayerDefaults.TOTAL_HEIGHT)
          }
          .width('100%')
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            // View delegates layout measurement to ViewModel
            this.viewModel.updateTotalScrollHeight(newArea.height as number)
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .enableScrollInteraction(false)
        .onAreaChange((_oldValue: Area, newValue: Area) => {
          // View delegates layout measurement to ViewModel
          this.viewModel.updateContentAreaHeight(newValue.height as number)
        })
        .onAppear(() => {
          // Delay to let layout settle, then start auto-scroll using ViewModel-calculated values
          setTimeout(() => {
            const scrollDistance = this.viewModel.getScrollDistance()
            const duration = this.viewModel.getScrollDuration()
            this.scroller.scrollTo({
              xOffset: 0,
              yOffset: scrollDistance > 0 ? scrollDistance : 99999,
              animation: { duration: duration, curve: Curve.Linear }
            })
          }, this.viewModel.getScrollDelay())
        })
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
          mainTitle: $r('app.string.credits'),
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

  @Builder TitleText(text: ResourceStr) {
    Text(text)
      .fontSize(13)
      .fontColor($r('app.color.salt_color_sub_text'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .lineHeight(26)
      .padding({ left: 16, right: 16 })
      .margin({ top: 8, bottom: 4 })
  }

  @Builder ParagraphText(text: string) {
    Text(text)
      .fontSize(16)
      .fontColor($r('app.color.salt_color_icon_foreground'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .lineHeight(32)
      .padding({ left: 16, right: 16 })
      .margin({ top: 4, bottom: 4 })
  }
}

// 致谢页。
