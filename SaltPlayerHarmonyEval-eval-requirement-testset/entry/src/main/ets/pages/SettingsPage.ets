// SettingsPage.ets
// View layer: Settings page for Salt Player - corresponds to Android SettingsScreen.kt
// Uses HDS HdsNavDestination + HdsListItemCard for full HarmonyOS OS6 native styling:
//   - Collapsing large title (MODAL mode)
//   - Dynamic blur title bar bound to the content scroller
//   - System-native back button and spacing
//
// MVVM Architecture:
//   - View: this file (SettingsPage.ets) - UI layout and user interaction
//   - ViewModel: SettingsViewModel.ets - observable state and business logic
//   - Model: SettingsModel.ets - raw data structures

import SettingsViewModel from '../viewmodel/SettingsViewModel'
import { SettingsItemModel } from '../model/SettingsModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixIcon,
  PrefixCustomBuilder,
  IconSize,
  SuffixArrow,
} from '@kit.UIDesignKit'
import { ImageModifier } from '@kit.ArkUI'

// Image modifier that overrides HDS PrefixIcon's default tint with a custom fill color.
// Needed for SVG icons whose original color (e.g. brand green) should be preserved
// instead of being recolored by the HDS list-card system tint.
class IconFillColorModifier extends ImageModifier {
  private fillColorValue: ResourceColor

  constructor(fillColor: ResourceColor) {
    super()
    this.fillColorValue = fillColor
  }

  applyNormalAttribute(instance: ImageAttribute): void {
    instance.fillColor(this.fillColorValue)
  }
}

@Component
export struct SettingsPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // ViewModel: single source of truth for this page
  @State viewModel: SettingsViewModel = new SettingsViewModel()

  aboutToAppear(): void {
    // Refresh Pro status when page is shown
    this.viewModel.refreshProStatus()
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // --- Salt Player Pro Card ---
          this.ProCard()

          // --- Main Settings Items Group ---
          this.SettingsGroup()

          // --- Salt Player for Windows Card ---
          this.WindowsCard()
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
          mainTitle: $r('app.string.settings'),
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

  // ========== Salt Player Pro Card ==========
  @Builder
  ProPrefixIcon() {
    Image(this.viewModel.proEntry.icon)
      .width(24)
      .height(24)
      .objectFit(ImageFit.Contain)
  }

  @Builder
  ProCard() {
    List() {
      ListItem() {
        HdsListItemCard({
          prefixItem: new PrefixCustomBuilder(() => {
            this.ProPrefixIcon()
          }),
          textItem: {
            primaryText: { text: this.viewModel.proEntry.text },
            secondaryText: { text: this.viewModel.getProSubtitleRes() },
          },
          suffixItem: new SuffixArrow({
            color: $r('sys.color.icon_tertiary'),
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          onClick: (): void => {
            this.viewModel.onProCardClick(this.navPathStack)
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

  // ========== Main Settings Items Group ==========
  @Builder
  SettingsGroup() {
    List({ space: 0 }) {
      ForEach(this.viewModel.settingsItems, (item: SettingsItemModel) => {
        ListItem() {
          HdsListItemCard({
            prefixItem: new PrefixIcon({
              iconSize: IconSize.SYSTEM_ICON,
              iconValue: {
                image: item.icon,
                modifier: item.iconFillColor !== undefined
                  ? new IconFillColorModifier(item.iconFillColor)
                  : undefined,
              },
            }),
            textItem: {
              primaryText: { text: item.text },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.viewModel.onSettingsItemClick(this.navPathStack, item)
            },
          })
        }
      }, (item: SettingsItemModel) => item.route)
    }
    .width('100%')
    .height('auto')
    .padding({ top: 4, bottom: 4 })
    .divider({
      strokeWidth: 0.5,
      color: $r('sys.color.comp_divider'),
      startMargin: 52,
      endMargin: 16,
    })
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Salt Player for Windows Card ==========
  @Builder
  WindowsCard() {
    List() {
      ListItem() {
        HdsListItemCard({
          prefixItem: new PrefixIcon({
            iconSize: IconSize.SYSTEM_ICON,
            iconValue: {
              image: $r('app.media.ic_windows'),
            },
          }),
          textItem: {
            primaryText: { text: 'Salt Player for Windows' },
          },
          suffixItem: new SuffixArrow({
            color: $r('sys.color.icon_tertiary'),
          }),
          cardPrefixMargin: 4,
          cardSuffixMargin: 4,
          cardBackgroundColor: Color.Transparent,
          onClick: (): void => {
            this.viewModel.onWindowsCardClick(this.navPathStack)
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
}
