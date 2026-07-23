// MediaSourcePage.ets
// View layer (Page component): Media source settings page for Salt Player
// Corresponds to Android MediaSourceScreen.kt
// Accessed from main menu "扫描音乐" (Scan Music) option
//
// MVVM architecture:
// - View: this file (pure UI rendering, no business logic)
// - ViewModel: MediaSourcePageViewModel (all state, logic, data orchestration)
// - Model: MediaSourceModel (data structures and data source operations)
//
// The View binds to the ViewModel for all state and delegates user interactions
// to ViewModel methods. It does NOT contain business logic or data operations.

import { common } from '@kit.AbilityKit'
import { ScanningDialogComponent } from '../components/ScanningDialogComponent'
import MediaSourcePageViewModel from '../viewmodel/MediaSourcePageViewModel'
import { ScanningDataSource, RescanResult } from '../model/ScanningModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixIcon,
  IconSize,
  SuffixArrow,
  SuffixSwitch,
} from '@kit.UIDesignKit'
import { ImageModifier } from '@kit.ArkUI'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import { promptAction } from '@kit.ArkUI'

// Image modifier that overrides HDS PrefixIcon's default tint with a custom fill color.
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
export struct MediaSourcePage {
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false
  // ViewModel: all page state and logic are managed here
  @State viewModel: MediaSourcePageViewModel = new MediaSourcePageViewModel()
  @State isRescanning: boolean = false

  private navPathStack: NavPathStack = new NavPathStack()
  private scrollScroller: Scroller = new Scroller()

  // Scanning dialog controller
  private scanningDialogController: CustomDialogController = new CustomDialogController({
    builder: ScanningDialogComponent({
      context: this.viewModel.getContext() || undefined,
      onDismiss: () => {
        this.scanningDialogController.close()
        this.viewModel.closeScanningDialog()
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  build() {
    HdsNavDestination() {
      Scroll(this.scrollScroller) {
        Column() {
          // ---- Scan button group ----
          List() {
            ListItem() {
              HdsListItemCard({
                prefixItem: new PrefixIcon({
                  iconSize: IconSize.SYSTEM_ICON,
                  iconValue: {
                    image: $r('app.media.ic_scan'),
                    modifier: new IconFillColorModifier($r('app.color.salt_color_high_light')),
                  },
                }),
                textItem: {
                  primaryText: { text: $r('app.string.start_scan') },
                },
                cardPrefixMargin: 4,
                cardSuffixMargin: 4,
                cardBackgroundColor: Color.Transparent,
                onClick: (): void => {
                  this.handleStartScan()
                },
              })
            }

            ListItem() {
              HdsListItemCard({
                textItem: {
                  primaryText: { text: $r('app.string.rescan_all') },
                },
                cardPrefixMargin: 4,
                cardSuffixMargin: 4,
                cardBackgroundColor: Color.Transparent,
                onClick: (): void => {
                  this.handleRescan()
                },
              })
            }
          }
          .width('100%')
          .height('auto')
          .padding({ top: 4, bottom: 4 })
          .borderRadius(20)
          .clip(true)
          .divider({
            strokeWidth: 0.5,
            color: $r('sys.color.comp_divider'),
            startMargin: 16,
            endMargin: 16,
          })
          .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
          .margin({ bottom: 12 })

          // ---- Settings group ----
          List({ space: 0 }) {
            ListItem() {
              HdsListItemCard({
                textItem: {
                  primaryText: { text: this.viewModel.doNotScanBelow60sVM.text },
                },
                suffixItem: new SuffixSwitch({
                  isCheck: this.viewModel.doNotScanBelow60sVM.isOn,
                  onChange: (val: boolean) => {
                    if (this.viewModel.doNotScanBelow60sVM.isOn !== val) {
                      this.viewModel.doNotScanBelow60sVM.toggle()
                    }
                  }
                }),
                cardPrefixMargin: 4,
                cardSuffixMargin: 4,
                cardBackgroundColor: Color.Transparent,
                enable: this.viewModel.doNotScanBelow60sVM.isEnabled,
              })
            }

            ListItem() {
              HdsListItemCard({
                textItem: {
                  primaryText: { text: $r('app.string.blocked_folders') },
                },
                suffixItem: new SuffixArrow({
                  color: $r('sys.color.icon_tertiary'),
                }),
                cardPrefixMargin: 4,
                cardSuffixMargin: 4,
                cardBackgroundColor: Color.Transparent,
                onClick: (): void => {
                  this.navPathStack.pushPath({ name: 'BlockedFoldersPage' })
                },
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
          .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
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
          mainTitle: $r('app.string.media_source'),
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scrollScroller])
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      // Pass context to ViewModel for permission and scanning operations
      try {
        const uiContext = this.getUIContext()
        const hostContext = uiContext.getHostContext()
        if (hostContext) {
          this.viewModel.setContext(hostContext as common.UIAbilityContext)
        }
      } catch (_e) {
        // Context not available yet
      }
    })
  }

  // Handle "Start Scan" button click - directly open scanning dialog
  private handleStartScan(): void {
    // Ensure context is set
    if (!this.viewModel.getContext()) {
      try {
        const uiContext = this.getUIContext()
        const hostContext = uiContext.getHostContext()
        if (hostContext) {
          this.viewModel.setContext(hostContext as common.UIAbilityContext)
        }
      } catch (_e) {
        // fallback
      }
    }

    // Directly open scanning dialog - permission is requested inside the scan flow
    this.viewModel.showScanningDialog = true
    this.scanningDialogController = new CustomDialogController({
      builder: ScanningDialogComponent({
        context: this.viewModel.getContext() || undefined,
        onDismiss: () => {
          this.scanningDialogController.close()
          this.viewModel.closeScanningDialog()
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true
    })
    this.scanningDialogController.open()
  }

  // Handle "Rescan" button click - re-read metadata for all existing tracks
  private handleRescan(): void {
    if (this.isRescanning) {
      return
    }

    AlertDialog.show({
      title: $r('app.string.rescan_all'),
      message: '重新读取所有歌曲的元数据标签（包括 ReplayGain 等），不删除歌曲',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => { /* do nothing */ }
      },
      secondaryButton: {
        value: '确认',
        action: () => {
          this.doRescan()
        }
      }
    })
  }

  private async doRescan(): Promise<void> {
    this.isRescanning = true

    const context = this.viewModel.getContext()
    if (!context) {
      promptAction.showToast({ message: 'Context not available' })
      this.isRescanning = false
      return
    }

    promptAction.showToast({ message: '开始重新扫描...' })

    try {
      const result: RescanResult = await ScanningDataSource.rescanAllTracks(
        context,
        (msg: string) => { console.info('[Rescan] ' + msg) }
      )
      promptAction.showToast({
        message: `重新扫描完成：${result.updated} 首已更新，${result.failed} 首失败，${result.removed} 首已移除`
      })
    } catch (err) {
      promptAction.showToast({
        message: '重新扫描失败：' + (err as Error).message
      })
    } finally {
      this.isRescanning = false
    }
  }
}

// 媒体源页：配置扫描来源。
