// CarKitPage.ets
// View layer: Car Kit settings page for Salt Player
// Refactored to MVVM architecture:
//   - View (this file): UI rendering and user interaction, delegates logic to ViewModel
//   - ViewModel (CarKitViewModel): observable state and business logic
//   - Model (CarKitModel): pure data structure
// Reuses existing MVVM components:
//   - ItemSwitcherWithIconAndSubRowComponent for Card 1 (icon + title + subtitle + toggle)
//   - ItemSwitcherWithSubRowComponent for Card 2 (title + subtitle + toggle)

import CarKitViewModel from '../viewmodel/CarKitViewModel'
import { ItemSwitcherWithIconAndSubRowComponent } from '../components/ItemSwitcherWithIconAndSubRowComponent'
import { ItemSwitcherWithSubRowComponent } from '../components/ItemSwitcherWithSubRowComponent'
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct CarKitPage {
  private navPathStack: NavPathStack = new NavPathStack()

  // ViewModel: single source of truth for all page state and logic
  @State vm: CarKitViewModel = new CarKitViewModel()

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ========== Title Bar ==========
        this.TitleBar()

        // ========== Scrollable Content ==========
        Scroll() {
          Column() {
            // --- Card 1: Playback Screen for Car (icon + title + subtitle + toggle) ---
            Column() {
              ItemSwitcherWithIconAndSubRowComponent({ vm: this.vm.playbackScreenVM })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .margin({ top: 7, bottom: 14 })
            .clip(true)

            // --- Card 2: Car Bluetooth Lyrics (title + subtitle + toggle) ---
            Column() {
              ItemSwitcherWithSubRowComponent({
                isOn: this.vm.carBluetoothLyricsIsOn,
                text: $r('app.string.car_bluetooth_lyrics'),
                sub: $r('app.string.car_bluetooth_lyrics_intro'),
                onChange: (isOn: boolean) => {
                  this.vm.onCarBluetoothLyricsChanged(isOn)
                }
              })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .margin({ bottom: 14 })
            .clip(true)

            // --- Card 3: vivo Jovi InCar lyrics (title + toggle) ---
            Column() {
              Row() {
                Text('vivo 智能车载（Jovi InCar）歌词')
                  .fontSize(16)
                  .fontColor($r('app.color.salt_color_icon_foreground'))
                  .fontWeight(FontWeight.Normal)
                  .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.vm.vivoJoviInCarLyricsIsOn })
                  .selectedColor('#FF448AFF')
                  .switchPointColor('#FFFFFFFF')
                  .onChange((isOn: boolean) => {
                    this.vm.onVivoJoviInCarLyricsChanged(isOn)
                  })
              }
              .width('100%')
              .height(49)
              .alignItems(VerticalAlign.Center)
              .padding({ left: 14, right: 10 })
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor($r('app.color.salt_color_white'))
            .margin({ bottom: 14 })
            .clip(true)

            // --- Section Title: Third-party car support ---
            this.ThirdPartySectionTitle()

            // --- Card 4: Dudu Auto + Official Website ---
            this.DuduAutoCard()
          }
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

  // ========== Title Bar Builder ==========
  @Builder
  TitleBar() {
    Row() {
      // Back button with larger clickable area (matching Android 49x49dp touch target)
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
        this.navPathStack.pop()
      })
      .accessibilityText('返回')

      // Title text - centered
      Text($r('app.string.car_kit'))
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Medium)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      // Spacer to balance back button for centering
      Row()
        .width(49)
        .height(49)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
  }

  // ========== Section Title: Third-party car support ==========
  @Builder
  ThirdPartySectionTitle() {
    Text('第三方车载支持')
      .fontSize(12)
      .fontColor($r('app.color.salt_color_sub_text'))
      .width('100%')
      .padding({ left: 14, top: 14, bottom: 10 })
  }

  // ========== Card 4: Dudu Auto + Official Website ==========
  @Builder
  DuduAutoCard() {
    Column() {
      // Dudu Auto row
      Row() {
        // Dudu Auto icon (colorful, not tinted)
        Image($r('app.media.ic_dudu_auto'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .margin({ left: 4, right: 12 })

        // Text
        Text('Dudu Auto')
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Normal)
      }
      .width('100%')
      .height(49)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })

      // Divider
      Divider()
        .width('100%')
        .height(0.5)
        .color($r('app.color.salt_color_sub_text'))
        .opacity(0.2)
        .margin({ left: 14, right: 14 })

      // Official website row (clickable, opens URL via ViewModel)
      Row() {
        Text($r('app.string.official_website'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .fontWeight(FontWeight.Normal)
          .layoutWeight(1)

        // Link arrow icon
        Image($r('app.media.ic_open_in_new'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.salt_color_sub_text'))
          .margin({ right: 4 })
      }
      .width('100%')
      .height(49)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 14, right: 10 })
      .onClick(() => {
        // Delegate to ViewModel for business logic
        this.vm.openDuduAutoWebsite()
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 14 })
    .clip(true)
  }
}

// 车机页：蓝牙歌词与 Jovi InCar 开关。
