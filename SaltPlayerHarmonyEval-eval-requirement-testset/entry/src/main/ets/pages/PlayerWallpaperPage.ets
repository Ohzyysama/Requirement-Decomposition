// PlayerWallpaperPage.ets
// View layer: secondary settings page for picking the player screen wallpaper.
// MVVM: UI only; picker/IO logic lives in PlayerWallpaperViewModel.
// Style: HdsNavDestination + MINI title mode (matches MainWallpaperPage).

import { ThemeOptionComponent } from '../components/ThemeSelectorRow'
import UserInterfaceViewModel from '../viewmodel/UserInterfaceViewModel'
import PlayerWallpaperViewModel from '../viewmodel/PlayerWallpaperViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixArrow,
} from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { DeleteWallpaperDialog } from '../components/DeleteWallpaperDialog'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct PlayerWallpaperPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  private deleteDialogController?: CustomDialogController
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // PlayerWallpaperViewModel owns picker/IO; UserInterfaceViewModel is reused
  // ONLY for the flowing-light theme radio row (reads/writes 'flowingLightMode').
  @State vm: PlayerWallpaperViewModel = new PlayerWallpaperViewModel()
  @State uiVM: UserInterfaceViewModel = new UserInterfaceViewModel()

  // Live binding to the persisted wallpaper path — used to gate the
  // conditional "Delete" row. Mirrors MainWallpaperPage exactly.
  @StorageLink('playerScreenBgCover') wallpaperPath: string = ''

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.SectionTitle($r('app.string.background_color'))
          this.ThemeSection()
          this.SectionTitle($r('app.string.wallpaper_of_player_screen'))
          this.ActionsSection()
          this.InfoSection()
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
          mainTitle: $r('app.string.wallpaper_of_player_screen'),
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

  @Builder
  SectionTitle(text: Resource) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  @Builder
  ThemeSection() {
    Column() {
      // Light / Dark / Follow UI — mirrors PlaybackScreenSection in UserInterfacePage
      Row({ space: 10 }) {
        Column() {
          ThemeOptionComponent({
            iconRes: $r('app.media.ic_light'),
            text: $r('app.string.player_theme_light'),
            selected: this.uiVM.isFlowingLightModeSelected(1),
            onSelect: () => {
              this.uiVM.selectFlowingLightMode(1)
            },
          })
        }.layoutWeight(1)

        Column() {
          ThemeOptionComponent({
            iconRes: $r('app.media.ic_dark'),
            text: $r('app.string.player_theme_dark'),
            selected: this.uiVM.isFlowingLightModeSelected(2),
            onSelect: () => {
              this.uiVM.selectFlowingLightMode(2)
            },
          })
        }.layoutWeight(1)

        Column() {
          ThemeOptionComponent({
            iconRes: $r('app.media.ic_harmony'),
            text: $r('app.string.follow_user_interface'),
            selected: this.uiVM.isFlowingLightModeSelected(0),
            iconWidth: 77,
            iconHeight: 16,
            onSelect: () => {
              this.uiVM.selectFlowingLightMode(0)
            },
          })
        }.layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 10 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  @Builder
  ActionsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.select_image') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: !this.vm.busy,
            onClick: (): void => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
              this.vm.selectImage(ctx)
            },
          })
        }
        if (this.wallpaperPath.length > 0) {
          ListItem() {
            HdsListItemCard({
              textItem: {
                primaryText: { text: $r('app.string.delete_current_image') },
              },
              cardPrefixMargin: 4,
              cardSuffixMargin: 4,
              cardBackgroundColor: Color.Transparent,
              enable: !this.vm.busy,
              onClick: (): void => {
                const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext
                this.deleteDialogController = new CustomDialogController({
                  builder: DeleteWallpaperDialog({
                    controller: this.deleteDialogController as CustomDialogController,
                    onConfirm: (): void => {
                      this.vm.removeWallpaper(ctx)
                    },
                  }),
                  alignment: DialogAlignment.Center,
                  customStyle: true,
                  maskColor: '#80000000',
                  openAnimation: { duration: 0 },
                  closeAnimation: { duration: 0 },
                })
                this.deleteDialogController.open()
              },
            })
          }
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
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  @Builder
  InfoSection() {
    Text($r('app.string.wallpaper_of_main_interface_info'))
      .fontSize(13)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
  }
}
