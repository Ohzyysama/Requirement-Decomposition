// MainWallpaperPage.ets
// View layer: secondary settings page for picking the main screen wallpaper.
// MVVM: UI only; picker/IO logic lives in MainWallpaperViewModel.
// Style: HdsNavDestination + MINI title mode (matches SettingsPage).

import MainWallpaperViewModel from '../viewmodel/MainWallpaperViewModel'
import { ThemeSelectorRow } from '../components/ThemeSelectorRow'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixArrow,
} from '@kit.UIDesignKit'
import { common } from '@kit.AbilityKit'
import { DeleteWallpaperDialog } from '../components/DeleteWallpaperDialog'

@Component
export struct MainWallpaperPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  private deleteDialogController?: CustomDialogController
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  @State vm: MainWallpaperViewModel = new MainWallpaperViewModel()

  @StorageLink('mainPageWallpaperPath') wallpaperPath: string = ''

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          this.SectionTitle($r('app.string.background_color'))
          this.ThemeSection()
          this.SectionTitle($r('app.string.wallpaper_of_main_screen'))
          this.ActionsSection()
          this.InfoSection()
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
          mainTitle: $r('app.string.wallpaper_of_main_screen'),
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
      ThemeSelectorRow()
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
    .padding({ bottom: 10 })
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
