// DevPage.ets
// Developer page for Salt Player (View layer - MVVM architecture)
// Corresponds to Android DevScreen.kt
// Navigation path: MainPage -> Menu -> About -> Double-tap app name
// Shows developer controls, device info, and software info
//
// View layer responsibilities:
//   - UI layout and rendering
//   - User interaction event delegation to ViewModel
//   - Data binding from ViewModel to UI components

import DevViewModel from '../viewmodel/DevViewModel'
import { DevInfoItemModel, DevControlItemModel } from '../model/DevModel'
import { BasicScreen } from '../components/BasicScreen'
import { common } from '@kit.AbilityKit'

@Component
export struct DevPage {
  private navPathStack: NavPathStack = new NavPathStack()

  // View binds ViewModel data: single @State ViewModel instance drives all UI
  @State viewModel: DevViewModel = new DevViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        this.TitleBar()

        Scroll() {
          Column() {
            // ========== 开发者报告 ==========
            this.ClickableItem('开发者报告')

            // ========== Monitor ==========
            this.SectionTitle('Monitor')
            Column() {
              this.ToggleItem('Dev Monitor', this.viewModel.devMonitorOn,
                this.viewModel.devMonitorSub, (isOn: boolean) => {
                  this.viewModel.toggleDevMonitor(isOn)
                })
            }
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== Control ==========
            this.SectionTitle('Control')
            Column() {
              ForEach(this.viewModel.getControlItems(), (item: DevControlItemModel, index: number) => {
                if (index > 0) {
                  this.ItemDivider()
                }
                this.ClickableItemInCard(item.text)
              }, (item: DevControlItemModel) => item.text)
              this.ItemDivider()
              this.ToggleItem('LYRICS_UI_USER_DRAGGING_EFFECT_END',
                this.viewModel.lyricsDraggingEffectEnd, undefined, (isOn: boolean) => {
                  this.viewModel.toggleLyricsDraggingEffectEnd(isOn)
                })
            }
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== 设备信息 ==========
            this.SectionTitle('设备信息')
            Column() {
              ForEach(this.viewModel.getDeviceInfoItems(), (item: DevInfoItemModel, index: number) => {
                if (index > 0) {
                  this.ItemDivider()
                }
                this.InfoItem(item.label, item.value)
              }, (item: DevInfoItemModel) => item.label)
            }
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== 软件信息 ==========
            this.SectionTitle('软件信息')
            Column() {
              ForEach(this.viewModel.getSoftwareInfoItems(), (item: DevInfoItemModel, index: number) => {
                if (index > 0) {
                  this.ItemDivider()
                }
                this.InfoItem(item.label, item.value)
              }, (item: DevInfoItemModel) => item.label)
            }
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .clip(true)

            // ========== Bottom items ==========
            Blank().height(10)
            ForEach(this.viewModel.getBottomItems(), (item: string) => {
              this.ClickableItem(item)
            }, (item: string) => item)
            Blank().height(20)
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

  // ========== Builders (shared UI components) ==========

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
        this.viewModel.navigateBack(this.navPathStack)
      })
      .accessibilityText('返回')

      Text('\uD83D\uDC9D Moriafly')
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
  SectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor($r('app.color.salt_color_sub_text'))
      .width('100%')
      .padding({ left: 14, top: 18, bottom: 8 })
  }

  @Builder
  InfoItem(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.salt_color_sub_text'))
      Text(value)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
  }

  @Builder
  ClickableItem(text: string) {
    Row() {
      Text(text)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.salt_color_sub_text'))
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 10 })
    .onClick(() => {
      this.viewModel.handleClickableItemAction(text, getContext(this) as common.UIAbilityContext)
    })
  }

  @Builder
  ClickableItemInCard(text: string) {
    Row() {
      Text(text)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.salt_color_sub_text'))
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .onClick(() => {
      this.viewModel.handleClickableItemAction(text, getContext(this) as common.UIAbilityContext)
    })
  }

  @Builder
  ToggleItem(text: string, isOn: boolean, sub: string | undefined, onChange: (isOn: boolean) => void) {
    Row() {
      Column() {
        Text(text)
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
        if (sub) {
          Text(sub)
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .onChange(onChange)
        .selectedColor($r('app.color.salt_color_icon_foreground'))
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
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

// 开发者页入口（关于页双击进入）。

// 开发者调试设置。
