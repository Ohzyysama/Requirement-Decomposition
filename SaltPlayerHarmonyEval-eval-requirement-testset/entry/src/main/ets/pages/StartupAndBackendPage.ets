// StartupAndBackendPage.ets
// View layer: Startup & Backend settings page (MVVM).
// Style: HdsNavDestination + MINI title mode, matching UserInterfacePage.
//
// Section layout:
//   - Section title  启动与后台  (app.string.startup_and_backend)
//   - Rounded-card List with one row:
//       - HdsListItemCard(primary=自动播放, suffix=SuffixSwitch bound to VM)

import StartupAndBackendViewModel from '../viewmodel/StartupAndBackendViewModel'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixSwitch,
} from '@kit.UIDesignKit'

@Component
export struct StartupAndBackendPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  @State vm: StartupAndBackendViewModel = new StartupAndBackendViewModel()

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.StartupAndBackendSection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 + MiniPlayerDefaults.TOTAL_HEIGHT })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.startup_and_backend'),
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

  // ========== Section Title ==========
  @Builder
  SectionTitle(text: Resource) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  // ========== Startup & Backend Section ==========
  @Builder
  StartupAndBackendSection() {
    this.SectionTitle($r('app.string.startup_and_backend'))

    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.auto_playback') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.autoPlayback,
              onChange: (val: boolean) => {
                if (this.vm.autoPlayback !== val) {
                  this.vm.setAutoPlayback(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 16,
        endMargin: 16,
      })
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
