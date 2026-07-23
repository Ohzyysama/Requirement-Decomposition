// SaltPlayerProPage.ets
// View layer: "Activate Salt Player Pro" page - corresponds to Android OfficialActivateScreen.kt
// Navigation path: MainPage -> Menu -> Settings -> Salt Player Pro
//
// MVVM architecture:
//   View: SaltPlayerProPage (this file)
//   ViewModel: SaltPlayerProViewModel
//   Model: SaltPlayerProModel
//
// Style: HdsNavDestination + MINI title mode, wallpaper-aware background.

import { ReBecomeDialog } from '../components/ReBecomeDialog'
import SaltPlayerProViewModel from '../viewmodel/SaltPlayerProViewModel'
import { ProFeatureItemModel } from '../model/SaltPlayerProModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import { common } from '@kit.AbilityKit';

@Component
export struct SaltPlayerProPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  // ViewModel instance - provides observable data and handles business logic
  @State viewModel: SaltPlayerProViewModel = new SaltPlayerProViewModel()

  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  aboutToAppear() {
    const context = getContext(this) as common.UIAbilityContext
    this.viewModel.initContext(context)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          if (this.viewModel.isProActivated) {
            // --- Activated State ---
            this.ActivatedCard()
          } else {
            // --- Section: Salt Player Member ---
            this.SectionTitle('Salt Player \u4F1A\u5458')

            // --- Price Card ---
            this.PriceCard()

            // --- Pro Feature Intro Grid ---
            this.ProIntroGrid()

            // --- Section: Member Service Agreement ---
            this.SectionTitle('\u8BDA\u4FE1\u4F1A\u5458\u8BA1\u5212\u670D\u52A1\u8BF4\u660E')

            // --- Service Description Card ---
            this.ServiceDescriptionCard()

            // --- Payment Button ---
            this.PaymentButton()

            // --- Restore Purchase Button ---
            this.RestorePurchaseButton()
          }

          // Bottom spacer for MiniPlayer
          Blank()
            .height(MiniPlayerDefaults.TOTAL_HEIGHT)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
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
          mainTitle: '\u6FC0\u6D3B Salt Player Pro',
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
    .overlay(this.viewModel.showReBecomeDialog ? this.ReBecomeDialogOverlay() : undefined)
  }

  // ========== Activated Card (shown when Pro is active) ==========
  @Builder
  ActivatedCard() {
    Column() {
      Image($r('app.media.ic_crown'))
        .width(64)
        .height(64)
        .objectFit(ImageFit.Contain)
        .margin({ top: 32, bottom: 16 })

      Text($r('app.string.pro_activated'))
        .fontSize(24)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Bolder)
        .margin({ bottom: 8 })

      Text('Salt Player Pro \u5DF2\u6FC0\u6D3B\uFF0C\u4EAB\u53D7\u5168\u90E8 Pro \u529F\u80FD')
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })

      // --- Pro Feature Intro Grid (still shown for reference) ---
      this.ProIntroGrid()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
  }

  // ========== Section Title ==========
  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  // ========== Price Card ==========
  @Builder
  PriceCard() {
    Column() {
      Column() {
        // Price text provided by ViewModel
        Text(this.viewModel.priceText)
          .fontSize(28)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Bolder)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, top: 16, right: 16, bottom: 16 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Pro Intro Feature Grid ==========
  @Builder
  ProIntroGrid() {
    Column() {
      // Feature data provided by ViewModel
      ForEach(this.viewModel.proFeatures, (row: ProFeatureItemModel[]) => {
        Row() {
          ForEach(row, (item: ProFeatureItemModel) => {
            this.FeatureCard(item)
          }, (item: ProFeatureItemModel) => item.title)
        }
        .width('100%')
      }, (row: ProFeatureItemModel[], index: number) => index.toString())
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 2, bottom: 2 })
  }

  // ========== Feature Card ==========
  @Builder
  FeatureCard(item: ProFeatureItemModel) {
    Row() {
      Image(item.icon)
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)

      Column() {
        Text(item.title)
          .fontSize(13)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.subtitle)
          .fontSize(11)
          .fontColor($r('app.color.salt_color_sub_text'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })
      .layoutWeight(1)
    }
    .layoutWeight(1)
    .padding({ left: 16, top: 12, right: 16, bottom: 12 })
    .margin({ left: 6, top: 6, right: 6, bottom: 6 })
    .borderRadius(12)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('app.color.salt_color_sub_background'))
    .alignItems(VerticalAlign.Center)
  }

  // ========== Service Description Card ==========
  @Builder
  ServiceDescriptionCard() {
    Column() {
      // Description text
      Text('Salt Player \u4F1A\u5458\u4E3A\u8BDA\u4FE1\u4ED8\u6B3E\u6FC0\u6D3B\uFF0C\u5373\u51ED\u8BDA\u4FE1\u8D2D\u4E70\uFF0C\u4E0D\u8BBE\u7F6E\u68C0\u6D4B\uFF0C\u4E5F\u4E0D\u7ED1\u5B9A\u4EFB\u4F55\u8D26\u53F7\u7CFB\u7EDF\uFF0C\u66F4\u591A\u5185\u5BB9\u8BF7\u67E5\u770B\u300ASalt Player \u4F1A\u5458\u670D\u52A1\u534F\u8BAE\u300B')
        .fontSize(13)
        .fontColor($r('app.color.salt_color_sub_text'))
        .lineHeight(20)
        .padding({ left: 16, right: 16, top: 16, bottom: 12 })

      // Agreement link with external icon
      Row() {
        Text('\u300ASalt Player \u4F1A\u5458\u670D\u52A1\u534F\u8BAE\u300B')
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)

        Image($r('app.media.ic_open_in_new'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.salt_color_sub_text'))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        // View delegates to ViewModel for opening agreement
        this.viewModel.openServiceAgreement()
      })

      // Checkbox for agreeing to service agreement
      Row() {
        Image(this.viewModel.agreeMemberService ? $r('app.media.ic_item_check') : $r('app.media.ic_item_uncheck'))
          .width(28)
          .height(28)
          .margin({ right: 8 })

        Text('\u9605\u8BFB\u5E76\u540C\u610F\u300ASalt Player \u4F1A\u5458\u670D\u52A1\u534F\u8BAE\u300B')
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .onClick(() => {
        // View delegates toggle to ViewModel
        this.viewModel.toggleAgreement()
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

  // ========== Payment Button ==========
  @Builder
  PaymentButton() {
    Column() {
      Text(this.viewModel.paymentButtonText)
        .fontSize(16)
        .fontColor(this.viewModel.agreeMemberService ? Color.White : $r('app.color.salt_color_sub_text'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.viewModel.agreeMemberService
      ? $r('app.color.salt_color_high_light')
      : $r('app.color.salt_color_sub_background'))
    .margin({ top: 6, bottom: 8 })
    .enabled(this.viewModel.agreeMemberService && !this.viewModel.isLoading)
    .onClick(() => {
      // View delegates payment to ViewModel
      this.viewModel.handlePayment()
    })
  }

  // ========== Restore Purchase Button ==========
  @Builder
  RestorePurchaseButton() {
    Column() {
      Text($r('app.string.restore_purchase'))
        .fontSize(16)
        .fontColor(this.viewModel.agreeMemberService ? Color.White : $r('app.color.salt_color_sub_text'))
        .fontWeight(FontWeight.Medium)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(12)
    .backgroundColor(this.viewModel.agreeMemberService
      ? $r('app.color.salt_color_high_light')
      : $r('app.color.salt_color_sub_background'))
    .margin({ top: 6, bottom: 8 })
    .enabled(this.viewModel.agreeMemberService && !this.viewModel.isLoading)
    .onClick(() => {
      // View delegates restore purchase to ViewModel
      this.viewModel.handleRestorePurchase()
    })
  }

  // ========== Re-activate Link (legacy) ==========
  @Builder
  ReActivateLink() {
    Text('\u66FE\u8D2D\u4E70\u8FC7\u8BDA\u4FE1\u4F1A\u5458\uFF1F')
      .fontSize(13)
      .fontColor($r('app.color.salt_color_sub_text'))
      .opacity(this.viewModel.agreeMemberService ? 1.0 : 0.5)
      .decoration({ type: TextDecorationType.Underline, color: $r('app.color.salt_color_sub_text') })
      .textAlign(TextAlign.Center)
      .width('100%')
      .padding({ top: 8, bottom: 16 })
      .enabled(this.viewModel.agreeMemberService)
      .onClick(() => {
        // View delegates to ViewModel for showing re-activate dialog
        this.viewModel.showReActivateDialog()
      })
  }

  // ========== ReBecomeDialog Overlay ==========
  @Builder
  ReBecomeDialogOverlay() {
    ReBecomeDialog({
      onDismiss: () => {
        this.viewModel.dismissReActivateDialog()
      },
      onActivate: () => {
        this.viewModel.handleReActivate()
      }
    })
  }
}
