// SoundEffectDialogComponent.ets
// View layer: Bottom sheet component for sound effect settings.
// Corresponds to Android SoundEffectDialog.kt
// Content: speed selector, DSP effect items (MAX Audio, System Equalizer, AUDIOFX V4), compressor toggle.
// Follows MVVM pattern: View delegates all logic to SoundEffectDialogViewModel.

import { RippleWrapper } from './RippleWrapper'
import { ItemSwitcherWithSubRowComponent } from './ItemSwitcherWithSubRowComponent'
import { SpeedLevelItem } from '../model/SoundEffectModel'
import SoundEffectDialogViewModel from '../viewmodel/SoundEffectDialogViewModel'

@Component
export struct SoundEffectDialogComponent {
  onDismiss: () => void = () => {}

  // ViewModel instance: encapsulates all state and business logic
  @State viewModel: SoundEffectDialogViewModel = new SoundEffectDialogViewModel()
  @StorageProp('navBarHeight') navBarHeight: number = 28
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  build() {
    Column() {
      Column() {
        // Speed selector (horizontal scroll)
        Scroll() {
          Row({ space: 8 }) {
            Blank().width(4)
            ForEach(this.viewModel.getSpeedLevels(), (item: SpeedLevelItem) => {
              SoundEffectSpeedItem({
                label: item.label,
                selected: this.viewModel.isSpeedSelected(item.value),
                onSelect: () => {
                  // Delegate speed selection to ViewModel
                  this.viewModel.selectSpeed(item.value)
                }
              })
            }, (item: SpeedLevelItem) => item.value.toString())
            Blank().width(4)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ top: 8, bottom: 8 })

        // MAX Audio concert hall atmosphere
        // this.DspEffectItemBuilder(
        //   $r('app.media.ic_concert_hall_atmosphere'),
        //   $r('app.string.max_audio_concert_hall_atmosphere'),
        //   'MAX Audio Atmos',
        //   $r('app.color.salt_color_icon_foreground'),
        //   () => {
        //     // Delegate to ViewModel
        //     this.viewModel.onConcertHallAtmosphereClick()
        //   }
        // )

        // System equalizer
        // this.DspEffectItemBuilder(
        //   $r('app.media.ic_harmony'),
        //   $r('app.string.system_equalizer'),
        //   'HarmonyOS Audio Effect',
        //   '#3D8EFF',
        //   () => {
        //     // Delegate to ViewModel; dismiss dialog if needed
        //     const shouldDismiss = this.viewModel.onSystemEqualizerClick()
        //     if (shouldDismiss) {
        //       this.onDismiss()
        //     }
        //   }
        // )

        // SALT PLAYER AUDIOFX V4
        // this.DspEffectItemBuilder(
        //   $r('app.media.ic_audio_wave'),
        //   'SALT PLAYER AUDIOFX V4',
        //   'Default EQ / V3 Effect',
        //   $r('app.color.salt_color_icon_foreground'),
        //   () => {
        //     // Delegate to ViewModel
        //     this.viewModel.onAudioFxV4Click()
        //   }
        // )

        // Compressor toggle
        // ItemSwitcherWithSubRowComponent({
        //   text: $r('app.string.compressor'),
        //   sub: $r('app.string.compressor_tip'),
        //   isOn: this.viewModel.compressorEnabled,
        //   onChange: (value: boolean) => {
        //     // Delegate compressor toggle to ViewModel
        //     this.viewModel.setCompressorEnabled(value)
        //   }
        // })

        // DSP tips
        // Text($r('app.string.audio_effect_dialog_tips'))
        //   .fontSize(12)
        //   .fontColor($r('app.color.salt_color_sub_text'))
        //   .padding({ left: 14, right: 14, top: 8, bottom: 12 })
        //   .width('100%')
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.salt_color_white'))
      .clip(true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 + this.navBarHeight })
  }

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
}

@Component
struct SoundEffectSpeedItem {
  @Prop selected: boolean = false
  label: string = ''
  onSelect: () => void = () => {}
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  build() {
    Column() {
      Text(this.label)
        .fontSize(12)
        .fontColor(this.selected ? Color.White : $r('app.color.salt_color_sub_text'))
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height(42)
    .padding({ left: 6, right: 6 })
    .borderRadius(8)
    .backgroundColor(this.selected ? $r('app.color.salt_color_high_light')
      : (this.isSystemDark ? $r('app.color.salt_color_white') : $r('app.color.colorPageBackground')))
    .onClick(() => {
      this.onSelect()
    })
  }
}

// 播放速度选择对话框：高亮当前速度档位并回调应用所选速度。
