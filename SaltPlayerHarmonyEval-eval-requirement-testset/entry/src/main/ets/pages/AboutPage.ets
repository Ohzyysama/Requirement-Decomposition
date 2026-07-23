// AboutPage.ets
// View layer for AboutPage - responsible for UI presentation and user interaction.
// Uses HDS HdsNavDestination + HdsListItemCard for full HarmonyOS OS6 native styling.
//
// MVVM Architecture:
//   View (this file) -> ViewModel (AboutViewModel.ets) -> Model (AboutModel.ets)

import AboutViewModel from '../viewmodel/AboutViewModel';
import { AboutMenuItemModel } from '../model/AboutModel';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixArrow,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct AboutPage {
  private navPathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  // View binds to ViewModel data
  @State viewModel: AboutViewModel = new AboutViewModel();

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // ========== App Logo Section ==========
          this.AppLogoSection()

          // ========== Registration Number Card ==========
          this.RegistrationNumberCard()

          // ========== Menu Items Card ==========
          this.MenuItemsCard()

          // ========== Customer Service Card ==========
          this.CustomerServiceCard()

          // ========== Copyright Text ==========
          this.CopyrightSection()
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
          mainTitle: $r('app.string.about'),
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

  // ======================== App Logo Section ========================
  // Displays app icon, app name (double-click navigates to DevPage), and version text.
  @Builder
  AppLogoSection() {
    Column() {
      // App icon
      Column() {
        Image($r('app.media.ic_salt_player'))
          .width(32)
          .height(32)
          .fillColor(this.viewModel.iconColor)
          .objectFit(ImageFit.Contain)
      }
      .width(56)
      .height(56)
      .borderRadius(12)
      .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : Color.White)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Blank().height(14)

      // App name — double-tap navigates to DevPage (developer entry).
      Text(this.viewModel.appName)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .textAlign(TextAlign.Center)
        .gesture(
          TapGesture({ count: 2 })
            .onAction(() => {
              this.viewModel.navigateToDevPage(this.navPathStack)
            })
        )

      Blank().height(4)
      Text(this.viewModel.versionText)
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .textAlign(TextAlign.Center)

      Blank().height(16)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 4, bottom: 12 })
  }

  // ======================== Registration Number Card ========================
  // Displays app registration number. Click navigates to registration website.
  @Builder
  RegistrationNumberCard() {
    List({ space: 0 }) {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: $r('app.string.app_registration_number') },
            secondaryText: { text: this.viewModel.registrationNumber },
          },
          suffixItem: new SuffixArrow({
            color: $r('sys.color.icon_tertiary'),
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          onClick: () => {
            this.viewModel.navigateToRegistration(this.navPathStack)
          },
        })
      }
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ======================== Menu Items Card ========================
  // Iterates over menu items from ViewModel.
  @Builder
  MenuItemsCard() {
    List({ space: 0 }) {
      ForEach(this.viewModel.getMenuItems(), (item: AboutMenuItemModel) => {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: item.title },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: () => {
              this.viewModel.navigateToMenuItem(this.navPathStack, item)
            },
          })
        }
      })
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
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ======================== Customer Service Card ========================
  // Displays customer service email from ViewModel.
  @Builder
  CustomerServiceCard() {
    List({ space: 0 }) {
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: '客服邮箱' },
            secondaryText: { text: this.viewModel.customerServiceEmail },
          },
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
        })
      }
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ======================== Copyright Section ========================
  // Displays copyright text from ViewModel.
  @Builder
  CopyrightSection() {
    Text(this.viewModel.copyrightText)
      .fontSize(11)
      .fontColor($r('app.color.salt_color_sub_text'))
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ left: 14, right: 14, top: 24, bottom: 24 })
  }
}

// 关于页：版本信息展示。
