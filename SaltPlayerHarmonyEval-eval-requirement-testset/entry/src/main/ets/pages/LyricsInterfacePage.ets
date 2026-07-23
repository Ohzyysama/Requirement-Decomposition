// LyricsInterfacePage.ets
// Page layer (View): lyrics interface settings page (text size / center align /
// font weight / karaoke compatibility strategy).
// Navigation path: LyricsSettingsPage -> "歌词界面" navigation item
// Style: HdsNavDestination + MINI title mode, matching UserInterfacePage.

import LyricsInterfaceViewModel from '../viewmodel/LyricsInterfaceViewModel'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixCustomBuilder,
  SuffixArrow,
  SuffixSwitch,
} from '@kit.UIDesignKit'

interface SliderItemParams {
  text: Resource
  value: number
  min: number
  max: number
  step: number
  onValueChange: (val: number) => void
  onValueChangeFinished?: () => void
}

@Component
export struct LyricsInterfacePage {
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  @State viewModel: LyricsInterfaceViewModel = LyricsInterfaceViewModel.getInstance()
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  // Reload settings from storage every time the page appears, so cross-ability
  // restarts or out-of-process state changes (e.g. AppStorage / Preferences drift)
  // are reconciled before the user sees the karaoke strategy display.
  aboutToAppear(): void {
    this.viewModel.loadSettings()
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.AppearanceSection()
          this.KaraokeSection()
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
          mainTitle: $r('app.string.lyrics_screen'),
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

  // ========== Appearance: text size + center align + font weight ==========
  @Builder
  AppearanceSection() {
    Column() {
      // Text size — sliders live outside HdsListItemCard since the kit
      // doesn't ship a slider variant; visuals match the surrounding card
      // cluster via shared background + dividers.
      this.SliderItem({
        text: $r('app.string.lyrics_view_text_size'),
        value: this.viewModel.pendingTextSize,
        min: this.viewModel.textSizeMin,
        max: this.viewModel.textSizeMax,
        step: this.viewModel.getSliderStep(this.viewModel.textSizeMin, this.viewModel.textSizeMax,
          this.viewModel.textSizeSteps),
        onValueChange: (val: number) => { this.viewModel.updateTextSize(val) },
        onValueChangeFinished: () => { this.viewModel.saveTextSize() }
      })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Center align — HDS switch row
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.lyrics_view_text_align_center') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.viewModel.textAlignCenter,
              onChange: (val: boolean) => {
                if (this.viewModel.textAlignCenter !== val) {
                  this.viewModel.updateTextAlignCenter(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
      }
      .width('100%')
      .height('auto')

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Font weight slider
      this.SliderItem({
        text: $r('app.string.font_weight'),
        value: this.viewModel.pendingFontWeight,
        min: this.viewModel.fontWeightMin,
        max: this.viewModel.fontWeightMax,
        step: this.viewModel.getSliderStep(this.viewModel.fontWeightMin, this.viewModel.fontWeightMax,
          this.viewModel.fontWeightSteps),
        onValueChange: (val: number) => { this.viewModel.updateFontWeight(val) },
        onValueChangeFinished: () => { this.viewModel.saveFontWeight() }
      })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Lyrics view blur — persisted via LyricsInterfaceViewModel.updateBlur.
      // Switch is shown but disabled on devices below the supported API level.
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.lyrics_view_blur') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.viewModel.blur,
              onChange: (val: boolean) => {
                this.viewModel.updateBlur(val)
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.viewModel.isBlurSupported,
          })
        }
      }
      .width('100%')
      .height('auto')

      // Hint shown when the device API level is below the supported floor
      // (Spec13 scenario 7). Mirrors the disabled state of the switch above.
      if (!this.viewModel.isBlurSupported) {
        Text($r('app.string.lyrics_view_blur_min_api_hint'))
          .fontSize(12)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      }

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Hide lyrics screen control panel switch (no longer Pro-gated).
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.hide_lyrics_screen_control_panel') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.viewModel.hideControlPanel,
              onChange: (val: boolean) => {
                this.viewModel.updateHideControlPanel(val)
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
      }
      .width('100%')
      .height('auto')
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Karaoke compatibility strategy popup row ==========
  @Builder
  KaraokeSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.karaoke_lyrics_animation_compatibility_strategy') },
              secondaryText: { text: this.viewModel.getKaraokeStrategyText() },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
            .bindMenu(this.KaraokeStrategyMenu)
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Karaoke strategy menu ==========
  @Builder
  KaraokeStrategyMenu() {
    Column() {
      ForEach(this.viewModel.karaokeStrategyOptions, (option: string, index: number) => {
        Row() {
          Text(option)
            .fontSize(16)
            .fontColor(index === this.viewModel.karaokeCompatStrategyIndex
              ? $r('sys.color.font_emphasize')
              : $r('sys.color.font_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .backgroundColor(index === this.viewModel.karaokeCompatStrategyIndex
          ? $r('sys.color.comp_background_secondary')
          : Color.Transparent)
        .onClick(() => {
          this.viewModel.updateKaraokeStrategy(index)
        })
      }, (option: string, index: number) => `${index}_${option}`)
    }
    .width(180)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
  }

  // ========== Pro crown prefix icon (24×24, brand asset) ==========
  // Rendered as a PrefixCustomBuilder on Pro-gated rows for non-Pro users.
  // Mirrors LyricsInterfaceDialogComponent.SwitcherItem's showProIcon branch
  // (which renders app.media.ic_crown at 24×24) and the Android source
  // (LyricsInterfaceScreen.kt sets iconPainter = R.drawable.ic_crown).
  // PrefixCustomBuilder keeps the SVG at its native fill colors rather than
  // applying the HDS system icon tint, which would flatten the crown.
  @Builder
  ProCrownPrefix() {
    Image($r('app.media.ic_crown'))
      .width(24)
      .height(24)
      .objectFit(ImageFit.Contain)
  }

  // ========== Slider item (custom — kit has no slider widget) ==========
  @Builder
  SliderItem($$: SliderItemParams) {
    Column() {
      Row() {
        Text($$.text)
          .fontSize(16)
          .fontColor($r('sys.color.font_primary'))
          .layoutWeight(1)

        Text($$.value.toString())
          .fontSize(14)
          .fontColor($r('sys.color.font_secondary'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 4 })
      .alignItems(VerticalAlign.Center)

      Slider({
        value: $$.value,
        min: $$.min,
        max: $$.max,
        step: $$.step,
        style: SliderStyle.OutSet
      })
        .blockColor($r('sys.color.font_emphasize'))
        .trackColor($r('sys.color.comp_background_tertiary'))
        .selectedColor($r('sys.color.font_emphasize'))
        .showSteps(false)
        .showTips(true)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .onChange((val: number, mode: SliderChangeMode) => {
          $$.onValueChange(val)
          if ((mode === SliderChangeMode.End || mode === SliderChangeMode.Click) &&
            $$.onValueChangeFinished) {
            $$.onValueChangeFinished()
          }
        })
    }
    .width('100%')
  }
}
