// LyricsInterfaceDialogComponent.ets
// View layer (Business Component): lyrics interface settings dialog component.
// MVVM role: Business component that receives ViewModel from the parent Page via @ObjectLink.
// It binds ViewModel data to UI and delegates user actions to ViewModel methods.
// Corresponds to Android LyricsInterfaceScreenContent function.
// Navigation path: LyricsSettingsPage -> "lyrics interface" navigation item
// Note: mini player is globally controlled by MainPage, not added here separately

import LyricsInterfaceViewModel from '../viewmodel/LyricsInterfaceViewModel'

// Builder parameter interface definitions
interface SliderItemParams {
  text: Resource
  sub: string
  value: number
  min: number
  max: number
  step: number
  onValueChange: (val: number) => void
  onValueChangeFinished?: () => void
}

interface SwitcherItemParams {
  text: Resource
  sub?: Resource | string
  state: boolean
  enabled?: boolean
  onChange: (val: boolean) => void
  showProIcon?: boolean
}

interface PopupItemParams {
  text: Resource
  sub: string
}

@Component
export struct LyricsInterfaceDialogComponent {
  // ========== ViewModel (received from parent Page via @ObjectLink) ==========
  @ObjectLink viewModel: LyricsInterfaceViewModel
  @Prop sourceTag: string = ''

  // Callback function for navigation (provided by the parent Page)
  onDismiss: () => void = () => {
  }

  build() {
    Column() {
      // ========== Title bar ==========
      this.TitleBar()

      // ========== Scrollable content area ==========
      Scroll() {
        Column() {
          // Group 1: text size, center align, font weight, blur
          this.SettingsGroup1()

          // Group 2: karaoke strategy
          this.SettingsGroup2()

          // Lyrics source info
          this.SourceInfoGroup()

          // Group 3: hide control panel (PRO feature) — Spec15
          this.SettingsGroup3()
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .backgroundColor($r('app.color.colorPageBackground'))
  }

  // ========== Title bar ==========
  @Builder
  TitleBar() {
    Row() {
      Text('歌词设置')
        .fontSize(20)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Bold)
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14 })
  }

  // ========== Settings group 1 ==========
  @Builder
  SettingsGroup1() {
    Column() {
      // Lyrics view text size - Slider
      this.SliderItem({
        text: $r('app.string.lyrics_view_text_size'),
        sub: this.viewModel.pendingTextSize.toString(),
        value: this.viewModel.pendingTextSize,
        min: this.viewModel.textSizeMin,
        max: this.viewModel.textSizeMax,
        step: this.viewModel.getSliderStep(this.viewModel.textSizeMin, this.viewModel.textSizeMax,
          this.viewModel.textSizeSteps),
        onValueChange: (val: number) => {
          this.viewModel.updateTextSize(val)
        },
        onValueChangeFinished: () => {
          this.viewModel.saveTextSize()
        }
      })

      // Lyrics view text center alignment - Toggle
      this.SwitcherItem({
        text: $r('app.string.lyrics_view_text_align_center'),
        state: this.viewModel.textAlignCenter,
        enabled: true,
        onChange: (val: boolean) => {
          this.viewModel.updateTextAlignCenter(val)
        }
      })

      // Font weight - Slider
      this.SliderItem({
        text: $r('app.string.font_weight'),
        sub: this.viewModel.pendingFontWeight.toString(),
        value: this.viewModel.pendingFontWeight,
        min: this.viewModel.fontWeightMin,
        max: this.viewModel.fontWeightMax,
        step: this.viewModel.getSliderStep(this.viewModel.fontWeightMin, this.viewModel.fontWeightMax,
          this.viewModel.fontWeightSteps),
        onValueChange: (val: number) => {
          this.viewModel.updateFontWeight(val)
        },
        onValueChangeFinished: () => {
          this.viewModel.saveFontWeight()
        }
      })

      // Lyrics view blur - Toggle
      // this.SwitcherItem({
      //   text: $r('app.string.lyrics_view_blur'),
      //   sub: '仅支持 Android 12 及更新系统版本',
      //   state: this.viewModel.blur,
      //   enabled: true,
      //   onChange: (val: boolean) => {
      //     this.viewModel.updateBlur(val)
      //   }
      // })

    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ top: 7 })
    .clip(true)
  }

  // ========== Lyrics source info group ==========
  @Builder
  SourceInfoGroup() {
    if (this.sourceTag.length > 0) {
      Column() {
        Column() {
          Text('歌词来源')
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
          Text(this.sourceTag)
            .fontSize(16)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 14, right: 14, top: 10, bottom: 14 })
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor($r('app.color.salt_color_white'))
      .margin({ top: 14 })
      .clip(true)
    }
  }

  // ========== Settings group 2 (karaoke strategy) ==========
  @Builder
  SettingsGroup2() {
    Column() {
      // Karaoke lyrics animation compatibility strategy - Popup selector
      this.PopupItem({
        text: $r('app.string.karaoke_lyrics_animation_compatibility_strategy'),
        sub: this.viewModel.getKaraokeStrategyText()
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ top: 14 })
    .clip(true)
  }

  // ========== Settings group 3 (hide control panel - PRO feature) ==========
  @Builder
  SettingsGroup3() {
    Column() {
      // Hide lyrics interface control panel - Toggle
      this.SwitcherItem({
        text: $r('app.string.hide_lyrics_screen_control_panel'),
        state: this.viewModel.hideControlPanel,
        enabled: true,
        showProIcon: false,
        onChange: (val: boolean) => {
          this.viewModel.updateHideControlPanel(val)
        }
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ top: 14 })
    .clip(true)
  }

  // ========== Slider component ==========
  @Builder
  SliderItem($$: SliderItemParams) {
    Column() {
      // Title row
      Row() {
        Text($$.text)
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)
          .padding({ left: 14 })

        Text($$.sub)
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))
          .padding({ right: 14 })
      }
      .width('100%')
      .height(40)
      .alignItems(VerticalAlign.Center)

      // Slider component
      Slider({
        value: $$.value,
        min: $$.min,
        max: $$.max,
        step: $$.step,
        style: SliderStyle.OutSet
      })
        .blockColor($r('app.color.salt_color_high_light'))
        .trackColor($r('app.color.salt_color_sub_background'))
        .selectedColor($r('app.color.salt_color_high_light'))
        .showSteps(false)
        .showTips(true)
        .width('100%')
        .padding({ left: 14, right: 14 })
        .onChange((value: number, mode: SliderChangeMode) => {
          $$.onValueChange(value)
          if ((mode === SliderChangeMode.End || mode === SliderChangeMode.Click) &&
            $$.onValueChangeFinished) {
            $$.onValueChangeFinished()
          }
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  // ========== Switcher component (with Toggle) ==========
  @Builder
  SwitcherItem($$: SwitcherItemParams) {
    Row() {
      // PRO crown icon (if needed)
      if ($$.showProIcon) {
        Image($r('app.media.ic_crown'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .margin({ left: 14, right: 8 })
      }

      // Text column
      Column() {
        Text($$.text)
          .fontSize(16)
          .fontColor($$.enabled === false ? $r('app.color.salt_color_sub_text') :
          $r('app.color.salt_color_icon_foreground'))

        if ($$.sub) {
          Text($$.sub)
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ left: $$.showProIcon ? 0 : 14, top: 10, bottom: 10 })

      // Toggle switch
      Toggle({ type: ToggleType.Switch, isOn: $$.state })
        .selectedColor($r('app.color.salt_color_high_light'))
        .switchPointColor(Color.White)
        .margin({ right: 14 })
        .onChange((isOn: boolean) => {
          if ($$.enabled !== false) {
            $$.onChange(isOn)
          }
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 49 })
    .alignItems(VerticalAlign.Center)
    .opacity($$.enabled === false ? 0.5 : 1.0)
  }

  // ========== Popup selector component (using bindMenu with custom builder) ==========
  @Builder
  PopupItem($$: PopupItemParams) {
    Row() {
      Text($$.text)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .layoutWeight(1)
        .padding({ left: 14, top: 14, bottom: 14 })
        .maxLines(2)

      Row() {
        Text($$.sub)
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))
        Image($r('app.media.ic_arrow_drop_down'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.salt_color_sub_text'))
          .margin({ left: 2 })
      }
      .alignItems(VerticalAlign.Center)
      .padding({ right: 14 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .bindMenu(this.KaraokeStrategyMenu)
  }

  @Builder
  KaraokeStrategyMenu() {
    Column() {
      ForEach(this.viewModel.karaokeStrategyOptions, (option: string, index: number) => {
        Row() {
          Text(option)
            .fontSize(16)
            .fontColor(index === this.viewModel.karaokeCompatStrategyIndex
              ? $r('app.color.salt_color_high_light')
              : $r('app.color.salt_color_icon_foreground'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .backgroundColor(index === this.viewModel.karaokeCompatStrategyIndex
          ? $r('app.color.salt_color_sub_background')
          : Color.Transparent)
        .onClick(() => {
          this.viewModel.updateKaraokeStrategy(index)
        })
      }, (option: string, index: number) => `${index}_${option}`)
    }
    .width(180)
    .backgroundColor($r('app.color.salt_color_white'))
  }
}
