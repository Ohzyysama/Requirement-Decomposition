// WindowsPlatformPage.ets
// View layer: Salt Player for Windows promotion page - corresponds to Android
// WindowsPlatformScreen.kt. Uses HDS HdsNavDestination for full HarmonyOS
// OS6 native styling: MINI title mode with system back button, dynamic blur
// bound to the content scroller, and HdsListItemCard rows for links.
//
// MVVM Architecture:
//   View (this file) -> ViewModel (WindowsPlatformViewModel.ets) -> Model (WindowsPlatformModel.ets)
// Accessed via: MainPage -> Menu -> Settings -> "Salt Player for Windows" card

import { common } from '@kit.AbilityKit'
import WindowsPlatformViewModel from '../viewmodel/WindowsPlatformViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixCustomBuilder,
  SuffixArrow,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct WindowsPlatformPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // ViewModel: single source of truth for this page
  @State viewModel: WindowsPlatformViewModel = new WindowsPlatformViewModel()

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.LargeTitleSection()
          this.PromotionalImageSection()
          this.OfficialWebsiteSection()
          this.DownloadTitleSection()
          this.MicrosoftStoreSection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 16 })
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
          mainTitle: '',
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

  // ======================== Large Title Section ========================
  // Android: ItemOuterLargeTitle — title + subtitle centered above the promo image.
  // Kept as inline hero text (not title-bar title) so it scrolls away naturally,
  // matching the Android page structure.
  @Builder
  LargeTitleSection() {
    Column() {
      Text(this.viewModel.brandingTitle)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 20 })

      Text(this.viewModel.brandingSubtitle)
        .fontSize(14)
        .fontColor($r('sys.color.font_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 12 })
    }
    .width('100%')
    .margin({ bottom: 20 })
  }

  // ======================== Promotional Image Section ========================
  @Builder
  PromotionalImageSection() {
    Column() {
      Image(this.viewModel.promotionalImageResource)
        .width('100%')
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .margin({ bottom: 12 })
  }

  // ======================== Official Website Section ========================
  // Same HDS recipe as SettingsPage: PrefixIcon(SYSTEM_ICON) + SuffixArrow
  // tinted tertiary. No prefix icon on this row — the website link is purely
  // text + arrow. HDS handles sizing, vertical alignment, and ripple.
  @Builder
  OfficialWebsiteSection() {
    List() {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: this.viewModel.officialWebsiteItem?.title ?? '' },
          },
          suffixItem: new SuffixArrow({
            color: $r('sys.color.icon_tertiary'),
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          onClick: (): void => {
            let context = getContext(this) as common.UIAbilityContext
            this.viewModel.openOfficialWebsite(context)
          },
        })
      }
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ======================== Download Section Title ========================
  // Matches the UserInterfacePage.SectionTitle pattern: 13sp Medium, secondary
  // color, left-padded 12vp, top 20 / bottom 8. Keeps group headers visually
  // consistent across settings-style pages.
  @Builder
  DownloadTitleSection() {
    if (this.viewModel.downloadSectionTitle) {
      Text(this.viewModel.downloadSectionTitle)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.font_secondary'))
        .width('100%')
        .padding({ left: 12, top: 20, bottom: 8 })
    }
  }

  // ======================== Microsoft Store Section ========================
  // Prefix uses PrefixCustomBuilder with a fixed 24×24 Image — NOT a wrapper
  // with `height('100%')`, which has no parent constraint in HDS slots and
  // expands the whole row. Fixed pixel sizing lets HdsListItemCard size the
  // row normally while we render the multi-colored Microsoft Store SVG at
  // its brand fills. PrefixIcon would tint all four squares with a single
  // system color, which is the wrong look for a brand logo.
  @Builder
  MicrosoftStoreSection() {
    List() {
      ListItem() {
        HdsListItemCard({
          prefixItem: new PrefixCustomBuilder(() => {
            this.BrandPrefixIcon()
          }),
          textItem: {
            primaryText: { text: this.viewModel.microsoftStoreItem?.title ?? '' },
          },
          suffixItem: new SuffixArrow({
            color: $r('sys.color.icon_tertiary'),
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          onClick: (): void => {
            let context = getContext(this) as common.UIAbilityContext
            this.viewModel.openMicrosoftStore(context)
          },
        })
      }
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
  }

  // Fixed-size 24×24 brand icon. Kept parameter-less so @State reads
  // (this.viewModel.microsoftStoreItem) subscribe correctly — passing
  // the resource as an @Builder param would capture it at call-site and
  // miss later ViewModel updates.
  @Builder
  BrandPrefixIcon() {
    Image(this.viewModel.microsoftStoreItem?.iconResource)
      .width(24)
      .height(24)
      .objectFit(ImageFit.Contain)
  }
}

// Windows 跨平台入口。
