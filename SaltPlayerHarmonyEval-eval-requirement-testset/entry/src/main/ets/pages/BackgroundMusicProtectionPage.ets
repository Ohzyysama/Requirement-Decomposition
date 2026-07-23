// BackgroundMusicProtectionPage.ets
// View layer for BackgroundMusicProtectionPage - responsible for UI presentation
// and user interaction. View layer binds to ViewModel data for dynamic updates
// and delegates user actions to the ViewModel.
// It does not contain any business logic or raw data definitions.
//
// MVVM Architecture:
//   View (this file) -> ViewModel (BackgroundMusicProtectionViewModel.ets)
//                    -> Model (BackgroundMusicProtectionModel.ets)
//
// Background music protection page for Salt Player
// Corresponds to Android BackgroundMusicProtection.kt
// Navigation path: MainPage -> Menu -> Settings -> Help & Feedback -> BackgroundMusicProtectionPage

import BackgroundMusicProtectionViewModel from '../viewmodel/BackgroundMusicProtectionViewModel';
import { ProtectItemModel } from '../model/BackgroundMusicProtectionModel';
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct BackgroundMusicProtectionPage {
  private navPathStack: NavPathStack = new NavPathStack()
  // View binds to ViewModel - single source of truth for this page
  @State viewModel: BackgroundMusicProtectionViewModel = new BackgroundMusicProtectionViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        this.TitleBar()

        Scroll() {
          Column() {
            // ========== Readable Check Items Section ==========
            this.SectionTitle(this.viewModel.readableCheckSection.sectionTitle)

            Column() {
              ForEach(this.viewModel.getReadableCheckItems(), (item: ProtectItemModel, index: number) => {
                this.ProtectItem(item.title, item.description)
              })

              // Refresh button - delegates action to ViewModel
              Row() {
                Text($r('app.string.refresh'))
                  .fontSize(16)
                  .fontColor('#ff1890ff')
                  .fontWeight(FontWeight.Bold)
              }
              .width('100%')
              .height(49)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                // View delegates business logic to ViewModel
                this.viewModel.refreshAutostartDetection()
              })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== Self Check Items Section ==========
            this.SectionTitle(this.viewModel.selfCheckSection.sectionTitle)

            Column() {
              ForEach(this.viewModel.getSelfCheckItems(), (item: ProtectItemModel, index: number) => {
                if (index > 0) {
                  this.ItemDivider()
                }
                this.ProtectItem(item.title, item.description)
              })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== Cautious Suggestions Section ==========
            this.SectionTitle(this.viewModel.cautiousSuggestionSection.sectionTitle)

            Column() {
              // Tip text from ViewModel
              Text(this.viewModel.getCautiousSuggestionTip())
                .fontSize(14)
                .fontColor($r('app.color.salt_color_sub_text'))
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .width('100%')

              ForEach(this.viewModel.getCautiousSuggestionItems(), (item: ProtectItemModel, index: number) => {
                this.ItemDivider()
                this.ProtectItem(item.title, item.description)
              })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)
            .margin({ bottom: 20 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: 14, right: 14 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  @Builder
  TitleBar() {
    Row() {
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.salt_color_icon_foreground'))
      }
      .width(49)
      .height(49)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        // View delegates navigation to ViewModel
        this.viewModel.navigateBack(this.navPathStack)
      })
      .accessibilityText('\u8fd4\u56de')

      Text($r('app.string.background_music_protection'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Blank().width(49)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SectionTitle(title: string | Resource) {
    Text(title)
      .fontSize(12)
      .fontColor($r('app.color.salt_color_sub_text'))
      .width('100%')
      .padding({ left: 14, top: 18, bottom: 8 })
  }

  @Builder
  ProtectItem(title: string, description: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Medium)
      Text(description)
        .fontSize(14)
        .fontColor($r('app.color.salt_color_sub_text'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }

  @Builder
  ItemDivider() {
    Line()
      .width('100%')
      .height(0.5)
      .backgroundColor($r('app.color.salt_color_cutting_line'))
      .margin({ left: 14 })
  }
}

// 后台保护引导页：分厂商指引。
