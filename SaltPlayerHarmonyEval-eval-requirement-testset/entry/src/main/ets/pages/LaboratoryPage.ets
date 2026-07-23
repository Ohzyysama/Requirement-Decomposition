// LaboratoryPage.ets
// View layer: Laboratory (experimental) settings page for Salt Player.
// Follows MVVM architecture:
//   - View (this file): UI rendering and user interaction
//   - ViewModel (LaboratoryViewModel): observable state and business logic
//   - Model (LaboratoryModel): raw data structure
// Navigation path: MainPage -> Menu -> Settings -> Laboratory
// Style: HdsNavDestination + MINI title mode, matching UserInterfacePage.

import LaboratoryViewModel from '../viewmodel/LaboratoryViewModel'
import LaboratoryModel from '../model/LaboratoryModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixIcon,
  IconSize,
  SuffixSwitch,
} from '@kit.UIDesignKit'
import { ImageModifier } from '@kit.ArkUI'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

// Image modifier that overrides HDS PrefixIcon's default tint with a custom fill color.
class IconFillColorModifier extends ImageModifier {
  private fillColorValue: ResourceColor
  constructor(fillColor: ResourceColor) {
    super()
    this.fillColorValue = fillColor
  }
  applyNormalAttribute(instance: ImageAttribute): void {
    instance.fillColor(this.fillColorValue)
  }
}

@Component
export struct LaboratoryPage {
  // ViewModel: single source of truth for all page state.
  @State viewModel: LaboratoryViewModel = new LaboratoryViewModel(new LaboratoryModel())

  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  aboutToAppear(): void {
    this.viewModel.loadSettings()
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // --- Large centered title: Laboratory ---
          this.LargeTitle()

          // --- Section 1: Playback ---
          this.SectionTitle($r('app.string.playback_screen'))
          this.PlaybackSection()

          // --- Section 2: Lyrics ---
          this.SectionTitle($r('app.string.lyrics'))
          this.LyricsSection()


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
          mainTitle: $r('app.string.laboratory'),
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

  // ========== Large Title Section ==========
  @Builder
  LargeTitle() {
    Column() {
      Text($r('app.string.laboratory'))
        .fontSize(24)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Bold)
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 42, bottom: 21 })

      Text($r('app.string.laboratory_intro'))
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ left: 14, right: 14 })
        .margin({ bottom: 49 })
    }
  }

  // ========== Playback Section ==========
  @Builder
  PlaybackSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.viewModel.autoOpenPlaybackVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.viewModel.autoOpenPlaybackVM.isOn,
              onChange: (val: boolean) => {
                if (this.viewModel.autoOpenPlaybackVM.isOn !== val) {
                  this.viewModel.autoOpenPlaybackVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.viewModel.autoOpenPlaybackVM.isEnabled,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Lyrics Section ==========
  @Builder
  LyricsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            prefixItem: new PrefixIcon({
              iconSize: IconSize.SYSTEM_ICON,
              iconValue: {
                image: $r('app.media.ic_crown'),
                modifier: new IconFillColorModifier('#FFB800'),
              },
            }),
            textItem: {
              primaryText: { text: this.viewModel.lyricsEffect3DVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.viewModel.lyricsEffect3DVM.isOn,
              onChange: (val: boolean) => {
                if (this.viewModel.lyricsEffect3DVM.isOn !== val) {
                  this.viewModel.lyricsEffect3DVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.viewModel.lyricsEffect3DVM.isEnabled,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }


}

// 实验室页：实验功能开关。
