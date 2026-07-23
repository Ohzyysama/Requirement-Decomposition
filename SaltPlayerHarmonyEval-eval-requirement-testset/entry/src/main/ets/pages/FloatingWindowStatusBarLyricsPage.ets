// FloatingWindowStatusBarLyricsPage.ets
// View layer: Floating window status bar lyrics settings page for Salt Player.
// Corresponds to Android custom status bar lyrics settings.
// Navigation path: LyricsSettingsPage -> Floating Window Status Bar Lyrics
// Style: HdsNavDestination + MINI title mode.
//
// MVVM: page renders ViewModel state. The ViewModel persists every change and
// coordinates the floating-window permission probe + window controller calls.
// The page itself never writes to SettingsStore directly.

import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import FloatingWindowStatusBarLyricsViewModel from '../viewmodel/FloatingWindowStatusBarLyricsViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
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
}

@Component
export struct FloatingWindowStatusBarLyricsPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // Single source of state — ViewModel owns persisted values, action handlers,
  // and the floating-window-permission grant listener.
  @State vm: FloatingWindowStatusBarLyricsViewModel =
    new FloatingWindowStatusBarLyricsViewModel()

  // ---- Color picker dialog state (UI-only, not persisted) ----
  @State showColorPickerDialog: boolean = false
  @State pendingColor: number = 0xFF0470E6

  // Predefined color palette for the color picker (ARGB ints)
  private colorPalette: number[] = [
    0xFF0470E6, 0xFFFFFFFF, 0xFFE3F9FD, 0xFF3D3B4F, 0xFF000000,
    0xFFFA8C35, 0xFF955539, 0xFF057748, 0xFFBE002F, 0xFF177CB0,
    0xFF808080,
  ]

  aboutToDisappear(): void {
    this.vm.destroy()
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Scroll(this.scroller) {
          Column() {
            // --- Toggle Section ---
            this.ToggleSection()

            // --- Position Section ---
            this.SectionTitle($r('app.string.position'))
            this.PositionSection()

            // --- Style Section ---
            this.SectionTitle($r('app.string.size'))
            this.StyleSection()

            // --- Info Tip Section ---
            this.InfoTipSection()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 + MiniPlayerDefaults.TOTAL_HEIGHT })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // Color picker dialog overlay
        if (this.showColorPickerDialog) {
          this.ColorPickerDialogOverlay()
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.floating_window_status_bar_lyrics'),
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
  SectionTitle(text: Resource) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  // ========== Toggle Section ==========
  @Builder
  ToggleSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.floating_window_status_bar_lyrics') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.master,
              onChange: (val: boolean) => {
                if (this.vm.master !== val) {
                  this.vm.onMasterToggleChanged(val).catch((e: Error) => {
                    console.warn('FloatingWindowStatusBarLyricsPage master: '
                      + e.message)
                  })
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
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Position Section (sliders) ==========
  @Builder
  PositionSection() {
    Column() {
      // Left-right position slider
      this.SliderItem({
        text: $r('app.string.left_and_right_position'),
        value: this.vm.leftRightPercent,
        min: this.vm.LR_MIN,
        max: this.vm.LR_MAX,
        step: 1,
        onValueChange: (val: number) => { this.vm.onLeftRightPercentChanged(val) }
      })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Up-down position slider
      this.SliderItem({
        text: $r('app.string.up_and_down_position'),
        value: this.vm.upDownPx,
        min: this.vm.UD_MIN,
        max: this.vm.UD_MAX,
        step: 1,
        onValueChange: (val: number) => { this.vm.onUpDownPxChanged(val) }
      })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Width slider
      this.SliderItem({
        text: $r('app.string.width'),
        value: this.vm.widthDp,
        min: this.vm.W_MIN,
        max: this.vm.W_MAX,
        step: 1,
        onValueChange: (val: number) => { this.vm.onWidthDpChanged(val) }
      })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Style Section (size + color + toggles) ==========
  @Builder
  StyleSection() {
    Column() {
      // Size slider
      this.SliderItem({
        text: $r('app.string.size'),
        value: this.vm.fontSizeDp,
        min: this.vm.F_MIN,
        max: this.vm.F_MAX,
        step: 0.5,
        onValueChange: (val: number) => { this.vm.onFontSizeDpChanged(val) }
      })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Choose color nav row
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.choose_color') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.pendingColor = this.vm.color
              this.showColorPickerDialog = true
            },
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Lyrics text center-aligned switch
      // Per spec25: toggle-ON means text is centered within widthDp; OFF means
      // left-aligned (the lyrics_text_left_aligned* string keys are retained for
      // resource stability, but the switch semantically means "center align").
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.lyrics_text_left_aligned') },
              secondaryText: { text: $r('app.string.lyrics_text_left_aligned_info') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.centerAlign,
              onChange: (val: boolean) => {
                if (this.vm.centerAlign !== val) {
                  this.vm.onCenterAlignChanged(val)
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
      .padding({ top: 4, bottom: 4 })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Status bar lyrics not show translation switch
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.status_bar_lyrics_not_show_translation') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.notShowTranslation,
              onChange: (val: boolean) => {
                if (this.vm.notShowTranslation !== val) {
                  this.vm.onNotShowTranslationChanged(val)
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
      .padding({ top: 4, bottom: 4 })

      Divider()
        .strokeWidth(0.5)
        .color($r('sys.color.comp_divider'))
        .margin({ left: 16, right: 16 })

      // Hide on playback screen switch
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.hide_on_playback_screen') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.hideOnPlayer,
              onChange: (val: boolean) => {
                if (this.vm.hideOnPlayer !== val) {
                  this.vm.onHideOnPlayerChanged(val)
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
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Info Tip Section ==========
  @Builder
  InfoTipSection() {
    Column() {
      Row() {
        // Warning icon
        Image($r('app.media.ic_warning'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.warning_icon_color'))
          .margin({ right: 12 })

        // Tip text
        Text($r('app.string.floating_window_status_bar_lyrics_tip'))
          .fontSize(15)
          .fontColor($r('app.color.colorTextForeground'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.warning_background'))
    .margin({ bottom: 14 })
    .clip(true)
  }

  // ========== Color Picker Dialog Overlay ==========
  @Builder
  ColorPickerDialogOverlay() {
    Column() {
      Column() {
        Text($r('app.string.choose_color'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ bottom: 16 })

        // Horizontal scrollable color circles
        Scroll() {
          Row({ space: 12 }) {
            ForEach(this.colorPalette, (color: number, index: number) => {
              Stack() {
                Circle()
                  .width(40)
                  .height(40)
                  .fill(color)
                  .stroke(this.pendingColor === color
                    ? $r('app.color.salt_color_high_light')
                    : $r('app.color.colorSubTextForeground'))
                  .strokeWidth(this.pendingColor === color ? 2 : 0.5)
              }
              .width(44)
              .height(44)
              .onClick(() => {
                this.pendingColor = color
              })
            }, (index: number) => index.toString())
          }
          .padding({ left: 8, right: 8 })
        }
        .scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Horizontal)
        .margin({ bottom: 24 })

        Row() {
          Button($r('app.string.cancel'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.showColorPickerDialog = false
            })

          Button($r('app.string.confirm'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_high_light'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.vm.onColorChanged(this.pendingColor)
              this.showColorPickerDialog = false
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.salt_color_white'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.showColorPickerDialog = false
    })
  }

  // ========== Slider item ==========
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
        .onChange((val: number, _mode: SliderChangeMode) => {
          $$.onValueChange(val)
        })
    }
    .width('100%')
  }
}
