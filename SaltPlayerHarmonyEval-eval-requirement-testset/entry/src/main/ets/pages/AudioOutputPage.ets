// AudioOutputPage.ets
// View layer: Audio Output settings page for Salt Player
// Follows MVVM architecture: only contains UI rendering logic.
// All state and business logic is delegated to AudioOutputViewModel.
//
// Style: HdsNavDestination + MINI title mode, wallpaper-aware background.

import { RippleWrapper } from '../components/RippleWrapper'
import { promptAction } from '@kit.ArkUI'
import AudioOutputViewModel from '../viewmodel/AudioOutputViewModel'
import { SpeedLevelModel, AudioOutputModeModel } from '../model/AudioOutputModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixSwitch,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct AudioOutputPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  // ViewModel: single source of truth for all page state and logic
  @State vm: AudioOutputViewModel = new AudioOutputViewModel()

  // @StorageLink triggers PersistentStorage auto-persistence on write
  @StorageLink('audioFocusEnabled') audioFocusEnabled: boolean = true

  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  aboutToAppear(): void {
    this.vm.initFadeInOutVM()
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // --- Audio Output Section ---
          this.SectionTitle($r('app.string.audio_output'))
          this.AudioOutputTogglesCard()

          // --- DSP Section ---
          this.SectionTitle($r('app.string.dsp'))
          this.DspCard()

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
          mainTitle: $r('app.string.audio_output'),
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
  SectionTitle(title: Resource) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  // ========== Audio Output Toggles Card ==========
  @Builder
  AudioOutputTogglesCard() {
    List({ space: 0 }) {
      // Audio Focus toggle
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: $r('app.string.audio_focus') },
            secondaryText: { text: $r('app.string.audio_focus_intro') },
          },
          suffixItem: new SuffixSwitch({
            isCheck: this.audioFocusEnabled,
            onChange: (value: boolean) => {
              console.info('[AudioFocus] Page.onChange: @StorageLink before = ' + this.audioFocusEnabled +
                ', setting to = ' + value)
              this.audioFocusEnabled = value
              console.info('[AudioFocus] Page.onChange: @StorageLink after = ' + this.audioFocusEnabled +
                ', AppStorage = ' + AppStorage.get<boolean>('audioFocusEnabled'))
              this.vm.setAudioFocusEnabled(value)
            }
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
        })
      }

      // Volume Balance toggle
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: $r('app.string.volume_balance') },
            secondaryText: { text: $r('app.string.volume_balance_tip') },
          },
          suffixItem: new SuffixSwitch({
            isCheck: this.vm.volumeBalanceEnabled,
            onChange: (value: boolean) => {
              this.vm.setVolumeBalanceEnabled(value)
            }
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
        })
      }

      // Fade in/out toggle
      ListItem() {
        HdsListItemCard({
          textItem: {
            primaryText: { text: this.vm.fadeInOutVM.text },
          },
          suffixItem: new SuffixSwitch({
            isCheck: this.vm.fadeInOutVM.isOn,
            onChange: (_value: boolean) => {
              this.vm.fadeInOutVM.toggle()
            }
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          enable: this.vm.fadeInOutVM.isEnabled,
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
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Audio Output Mode Card ==========
  @Builder
  AudioOutputModeCard() {
    Column() {
      ForEach(this.vm.outputModes, (item: AudioOutputModeModel, index: number) => {
        if (index > 0) {
          Blank().height(15)
        }
        AudioOutputModeItemComponent({
          title: item.title,
          subtitle: item.subtitle,
          selected: this.vm.selectedOutputMode === item.mode,
          onSelect: () => {
            this.vm.setSelectedOutputMode(item.mode)
          }
        })
      }, (item: AudioOutputModeModel) => item.mode)
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .margin({ bottom: 12 })
  }

  // ========== Audio Output Freq Card ==========
  @Builder
  AudioOutputFreqCard() {
    Column() {
      // Sample rate range info
      Column() {
        Text($r('app.string.sample_rate_range_supported_by_audio_track_of_this_system'))
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))

        Text(this.vm.getSampleRateRangeText())
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })

      // Divider
      Divider()
        .color($r('app.color.colorDividerBackground'))
        .width('100%')

      // Audio output freq selector
      RippleWrapper({
        onAction: () => {
          // TODO: Show frequency selection popup
          console.info('TODO: Show audio output frequency selection popup')
        }
      }) {
        Row() {
          Text($r('app.string.audio_output_freq'))
            .fontSize(16)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .layoutWeight(1)

          Text(this.vm.getAudioOutputFreqText())
            .fontSize(14)
            .fontColor($r('app.color.salt_color_sub_text'))

          Image($r('app.media.ic_arrow_drop_down'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.salt_color_sub_text'))
            .margin({ left: 4 })
        }
        .width('100%')
        .height(49)
        .alignItems(VerticalAlign.Center)
        .padding({ left: 14, right: 14 })
      }

      // Divider
      Divider()
        .color($r('app.color.colorDividerBackground'))
        .width('100%')

      // Force change device freq toggle
      HdsListItemCard({
        textItem: {
          primaryText: { text: $r('app.string.change_device_freq') },
          secondaryText: { text: $r('app.string.change_device_freq_intro') },
        },
        suffixItem: new SuffixSwitch({
          isCheck: this.vm.changeDeviceFreqEnabled,
          onChange: (value: boolean) => {
            if (value) {
              // Show warning dialog before enabling
              AlertDialog.show({
                title: $r('app.string.change_device_freq'),
                message: $r('app.string.change_device_freq_intro'),
                autoCancel: true,
                primaryButton: {
                  value: '取消',
                  action: () => {
                    // Cancel - do nothing
                  }
                },
                secondaryButton: {
                  value: '确认',
                  action: () => {
                    this.vm.setChangeDeviceFreqEnabled(true)
                  }
                }
              })
            } else {
              this.vm.setChangeDeviceFreqEnabled(false)
            }
          }
        }),
        cardPrefixMargin: 4,
        cardSuffixMargin: 4,
        cardBackgroundColor: Color.Transparent,
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

  // ========== DSP Card ==========
  @Builder
  DspCard() {
    Column() {
      // Speed selector (horizontal scroll)
      Scroll() {
        Row({ space: 8 }) {
          Blank().width(4)
          ForEach(this.vm.speedLevels, (item: SpeedLevelModel) => {
            SpeedItemComponent({
              label: item.label,
              selected: this.vm.isSpeedSelected(item.value),
              onSelect: () => {
                this.vm.setCurrentSpeed(item.value)
              }
            })
          }, (item: SpeedLevelModel) => item.value.toString())
          Blank().width(4)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ top: 8, bottom: 8 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== DSP Effect Item Builder ==========
  @Builder
  DspEffectItemBuilder(icon: Resource, title: ResourceStr, subtitle: string,
    iconColor: ResourceColor, onItemClick: () => void) {
    RippleWrapper({
      rowHeight: 52,
      onAction: onItemClick
    }) {
      Row() {
        Row() {
          Image(icon)
            .width(26)
            .height(26)
            .objectFit(ImageFit.Contain)
            .fillColor(iconColor)
        }
        .width(42)
        .height(42)
        .justifyContent(FlexAlign.Center)
        .margin({ right: 12 })

        Column() {
          Text(title)
            .fontSize(16)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.salt_color_sub_text'))
      }
      .width('100%')
      .height(52)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })
    }
  }

  // ========== Audio Decoding Card ==========
  @Builder
  AudioDecodingCard() {
    Column() {
      RippleWrapper({
        onAction: () => {
          // TODO: Navigate to Audio Decoding page - target page not yet implemented
          console.info('TODO: navigate to AudioDecoding settings page')
        }
      }) {
        Row() {
          Text($r('app.string.audio_decoding'))
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
      }
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

// ========== Audio Output Mode Item Component (with built-in ripple) ==========
@Component
struct AudioOutputModeItemComponent {
  @Prop selected: boolean = false
  title: string = ''
  subtitle: string = ''
  onSelect: () => void = () => {
  }

  @State private rippleX: number = 0
  @State private rippleY: number = 0
  @State private rippleScale: number = 0
  @State private rippleOpacity: number = 0

  build() {
    Stack() {
      Column()
        .width(1)
        .height(1)
        .scale({ x: this.rippleScale, y: this.rippleScale })
        .position({ x: this.rippleX, y: this.rippleY })
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            ['#1A000000', 0.0],
            ['#0D000000', 0.5],
            ['#00000000', 1.0]
          ]
        })
        .borderRadius('50%')
        .opacity(this.rippleOpacity)
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.selected ? $r('app.color.salt_color_high_light') : $r('app.color.salt_color_sub_text'))

        Text(this.subtitle)
          .fontSize(12)
          .fontColor(this.selected ? $r('app.color.salt_color_high_light') : $r('app.color.salt_color_sub_text'))
          .margin({ top: 2 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ top: 10, bottom: 10 })
    .borderRadius(8)
    .border({
      width: 1,
      color: this.selected ? $r('app.color.salt_color_high_light') : $r('app.color.colorSubTextForeground')
    })
    .clip(true)
    .onClick(() => {
      this.onSelect()
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        const touch = event.touches[0]
        this.rippleX = touch.x
        this.rippleY = touch.y
        this.rippleScale = 0
        this.rippleOpacity = 1
        animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
          this.rippleScale = 1000
        })
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
          this.rippleOpacity = 0
        })
      }
    })
  }
}

// ========== Speed Item Component (with built-in ripple) ==========
@Component
struct SpeedItemComponent {
  @Prop selected: boolean = false
  label: string = ''
  onSelect: () => void = () => {
  }

  @State private rippleX: number = 0
  @State private rippleY: number = 0
  @State private rippleScale: number = 0
  @State private rippleOpacity: number = 0

  build() {
    Stack() {
      Column()
        .width(1)
        .height(1)
        .scale({ x: this.rippleScale, y: this.rippleScale })
        .position({ x: this.rippleX, y: this.rippleY })
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            ['#1A000000', 0.0],
            ['#0D000000', 0.5],
            ['#00000000', 1.0]
          ]
        })
        .borderRadius('50%')
        .opacity(this.rippleOpacity)
        .hitTestBehavior(HitTestMode.None)

      Column() {
        Text(this.label)
          .fontSize(12)
          .fontColor(this.selected ? Color.White : $r('app.color.salt_color_sub_text'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .height(42)
    .padding({ left: 6, right: 6 })
    .borderRadius(8)
    .backgroundColor(this.selected ? $r('app.color.salt_color_high_light') : $r('app.color.colorPageBackground'))
    .clip(true)
    .onClick(() => {
      this.onSelect()
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        const touch = event.touches[0]
        this.rippleX = touch.x
        this.rippleY = touch.y
        this.rippleScale = 0
        this.rippleOpacity = 1
        animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
          this.rippleScale = 1000
        })
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
          this.rippleOpacity = 0
        })
      }
    })
  }
}
