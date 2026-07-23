// MainMenuComponent.ets
// View layer: UI component for the side drawer menu
// Uses MainMenuViewModel for data and logic per MVVM architecture
// Corresponds to Android MainMenuUI.kt - the push sidebar content
// Contains: MiniControlUI (top icons row) + navigation menu items

import { ExitAppDialog } from './ExitAppDialog'
import MainMenuViewModel from '../viewmodel/MainMenuViewModel'
import { MenuItemData, ThemeOptionData } from '../model/MainMenuModel'
import SettingsStore from '../model/SettingsStore'

@Component
export struct MainMenuComponent {
  // Callback when a menu item is clicked, passes route string
  onMenuItemClick: (route: string) => void = () => {}
  // Callback to close the menu (collapse drawer)
  onCloseMenu: () => void = () => {}

  // ViewModel instance - manages UI state and business logic
  @State viewModel: MainMenuViewModel = new MainMenuViewModel()
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''

  // Current selected theme (0=FollowSystem, 1=Light, 2=Dark) - synced globally via AppStorage
  @StorageLink('selectedTheme') selectedTheme: number = 0

  // Scroller for the menu scroll area
  private menuScroller: Scroller = new Scroller()

  // Menu item press effect styles
  @Styles
  menuItemNormal() {
    .backgroundColor(Color.Transparent)
  }

  @Styles
  menuItemPressed() {
    .backgroundColor('#0A000000')
  }

  // Exit app dialog - business logic is handled by ExitAppDialogViewModel inside ExitAppDialog
  private exitDialogController: CustomDialogController = new CustomDialogController({
    builder: ExitAppDialog(),
    alignment: DialogAlignment.Center,
    customStyle: true,
    maskColor: '#99000000'
  })

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        // ========== Scrollable content ==========
        Scroll(this.menuScroller) {
          Column() {
            // Top Icon Row card (fixed height, theme panel is overlay)
            Row() {
              Image($r('app.media.ic_exit_app'))
                .layoutWeight(1)
                .height(56)
                .padding(16)
                .fillColor('#ffff5951')
                .objectFit(ImageFit.Contain)
                .onClick(() => {
                  this.exitDialogController.open()
                })
                .accessibilityText($r('app.string.exit_app'))

              Image($r('app.media.ic_light'))
                .layoutWeight(1)
                .height(56)
                .padding(16)
                .fillColor('#ffffc551')
                .objectFit(ImageFit.Contain)
                .rotate({ angle: this.viewModel.themeIconRotation })
                .onClick(() => {
                  // View calls ViewModel method to toggle theme panel with animation
                  this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
                    this.viewModel.toggleThemePanel()
                  })
                })
                .accessibilityText($r('app.string.user_interface'))

              // Image($r('app.media.ic_audio_effect'))
              //   .layoutWeight(1)
              //   .height(56)
              //   .padding(16.5)
              //   .fillColor($r('app.color.salt_color_high_light'))
              //   .objectFit(ImageFit.Contain)
              //   .onClick(() => {
              //     this.onMenuItemClick('audio_effect')
              //     this.onCloseMenu()
              //   })
              //   .accessibilityText($r('app.string.audio_effect'))
            }
            .width('100%')
            .height(56)
            .borderRadius(this.viewModel.showThemePanel ?
              { topLeft: 12, topRight: 12, bottomLeft: 0, bottomRight: 0 } : 12)
            .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_white'))
            .margin({ top: 8, bottom: this.viewModel.showThemePanel ? 0 : 8 })

            // ========== Main Navigation Group ==========
            Column() {
              ForEach(this.viewModel.mainNavItems, (item: MenuItemData) => {
                this.MenuItemRow(item)
              }, (item: MenuItemData) => item.route)
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_white'))
            .margin({
              top: this.viewModel.showThemePanel ? this.viewModel.themePanelHeight + 8 : 8,
              bottom: 8
            })
            .clip(true)

            // ========== Utilities and Settings Group ==========
            Column() {
              ForEach(this.viewModel.utilNavItems, (item: MenuItemData) => {
                this.MenuItemRow(item)
              }, (item: MenuItemData) => item.route)
            }
            .width('100%')
            .borderRadius(12)
            .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_white'))
            .margin({ top: 8, bottom: 81 })
            .clip(true)
          }
          .width('100%')
        }
        .scrollable(this.viewModel.showThemePanel ? ScrollDirection.None : ScrollDirection.Vertical)
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // ========== Theme Panel Overlay (not in scroll, doesn't affect layout) ==========
        if (this.viewModel.showThemePanel) {
          Column() {
            this.ThemePanelContent()
          }
          .width('100%')
          .borderRadius({ bottomLeft: 12, bottomRight: 12 })
          .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_white'))
          .margin({ top: 8 + 56 }) // icon row top margin + icon row height
          .clip(true)
          .onAreaChange((_oldValue: Area, newValue: Area) => {
            // View delegates height tracking to ViewModel
            this.viewModel.updateThemePanelHeight(newValue.height as number)
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.statusBarHeight })
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
  }


  // ======================== Theme Panel Content ========================
  // Renders theme options from ViewModel data, delegates selection logic to ViewModel
  @Builder
  ThemePanelContent() {
    Column({ space: 8 }) {
      ForEach(this.viewModel.themeOptions, (option: ThemeOptionData) => {
        this.ThemeOptionItem(
          option.icon,
          option.title,
          this.viewModel.isThemeSelected(option.mode, this.selectedTheme),
          () => {
            // Update global theme via AppStorage and persist immediately
            this.selectedTheme = option.mode
            SettingsStore.getInstance().save('selectedTheme', option.mode)
            // Apply color mode via ViewModel's Model layer mapping
            this.getUIContext().getHostContext()!.getApplicationContext()
              .setColorMode(this.viewModel.getColorModeForTheme(option.mode))
            // Close theme panel with animation via ViewModel
            this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
              this.viewModel.closeThemePanel()
            })
          },
          option.iconWidth,
          option.iconHeight
        )
      }, (option: ThemeOptionData) => option.mode.toString())
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 6, bottom: 16 })
    .transition(TransitionEffect.opacity(0)
      .combine(TransitionEffect.translate({ y: -40 }))
      .animation({ duration: 300, curve: Curve.EaseOut }))
  }

  // ======================== Theme Option Item ========================
  // Shared UI builder - no business logic, purely presentational
  @Builder
  ThemeOptionItem(icon: Resource, title: Resource, selected: boolean, onClick: () => void,
    iconWidth: number = 24, iconHeight: number = 24) {
    Row() {
      Image(icon)
        .width(iconWidth)
        .height(iconHeight)
        .fillColor(selected ? $r('app.color.salt_color_high_light') : $r('app.color.salt_color_sub_text'))

      Blank()
        .width(8)

      Text(title)
        .fontSize(12)
        .fontColor(selected ? $r('app.color.salt_color_high_light') : $r('app.color.salt_color_sub_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .borderRadius(8)
    .border({
      width: 1,
      color: selected ? $r('app.color.salt_color_high_light') : $r('app.color.salt_color_stroke')
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick()
    })
  }

  // ======================== Menu Item Row ========================
  // Shared UI builder - no business logic, purely presentational
  @Builder
  MenuItemRow(item: MenuItemData) {
    Row() {
      Image(item.icon)
        .width(24)
        .height(24)
        .padding(item.iconPadding)
        .fillColor(item.iconColor)

      Blank()
        .width(12)

      Text(item.text)
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ minHeight: 56 })
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({
      normal: this.menuItemNormal,
      pressed: this.menuItemPressed
    })
    .onClick(() => {
      this.onMenuItemClick(item.route)
      this.onCloseMenu()
    })
  }
}
