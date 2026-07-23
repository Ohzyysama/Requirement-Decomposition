// BlockedFoldersPage.ets
// View layer - Page Component: Blocked Folders page for Salt Player
// Corresponds to Android BlockedFoldersScreen.kt
// Accessed from MediaSourcePage "被屏蔽的文件夹" (Blocked Folders) option
//
// MVVM Architecture:
// - View (this page): Responsible for UI layout, composing child components, and navigation.
//   Does NOT contain any business logic. All user actions are delegated to the ViewModel.
// - ViewModel (BlockedFoldersViewModel): Provides page data and handles business logic.
//   Uses @Observed + @Track for precise UI updates.
// - Model (BlockedFolderModel + BlockedFolderDataSource): Pure data structures and data access.
//
// Style: HdsNavDestination + MINI title mode, wallpaper-aware background.

import lottie, { AnimationItem } from '@ohos/lottie'
import { BlockedFolderRemoveDialog } from '../components/BlockedFolderRemoveDialog'
import { BlockedFolderItemComponent } from '../components/BlockedFolderItemComponent'
import BlockedFoldersViewModel from '../viewmodel/BlockedFoldersViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
} from '@kit.UIDesignKit'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'

@Component
export struct BlockedFoldersPage {
  // View binds to ViewModel: @State enables observation of the @Observed ViewModel
  // ViewModel is the single source of truth for all page state
  @State viewModel: BlockedFoldersViewModel = new BlockedFoldersViewModel()

  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()

  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // Lottie animation for empty state (UI-only concern, stays in View)
  private lottieRenderingSettings: RenderingContextSettings = new RenderingContextSettings(true)
  private lottieCanvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.lottieRenderingSettings)
  private lottieAnimItem: AnimationItem | null = null

  // Remove confirmation dialog controller
  // Dialog receives ViewModel via @Link for data binding
  private removeDialogController: CustomDialogController = new CustomDialogController({
    builder: BlockedFolderRemoveDialog({
      viewModel: this.viewModel,
      onConfirm: () => {
        // View delegates confirm action to ViewModel
        this.viewModel.confirmRemoveFolder()
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true
  })

  aboutToDisappear(): void {
    lottie.destroy(this.viewModel.LOTTIE_ANIM_NAME)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          if (this.viewModel.blockedFolders.length === 0) {
            // Empty state: NoneBox equivalent (shared component, no ViewModel dependency)
            this.NoneBox()
          } else {
            // Blocked folders list using business component
            List() {
              ForEach(this.viewModel.blockedFolders, (path: string) => {
                ListItem() {
                  // Business component: receives ViewModel via @Link and path via @Prop
                  BlockedFolderItemComponent({
                    viewModel: this.viewModel,
                    path: path,
                    onRemoveClick: () => {
                      this.removeDialogController.open()
                    }
                  })
                }
              }, (path: string) => path)
            }
            .width('100%')
            .layoutWeight(1)
            .contentEndOffset(96)
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }

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
          mainTitle: $r('app.string.blocked_folders'),
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
      // View requests ViewModel to load data when page is ready
      this.viewModel.loadBlockedFolders()
    })
  }

  // ======================== Empty State (NoneBox) ========================
  // This is a shared-style @Builder: no ViewModel dependency (except animation name), purely UI presentation
  // Uses Lottie animation for empty state, matching SearchAllSongsPage pattern
  @Builder
  NoneBox() {
    Column() {
      Canvas(this.lottieCanvasCtx)
        .width(100)
        .height(100)
        .opacity(0.75)
        .onReady(() => {
          this.lottieAnimItem = lottie.loadAnimation({
            container: this.lottieCanvasCtx,
            renderer: 'canvas',
            loop: true,
            autoplay: true,
            name: this.viewModel.LOTTIE_ANIM_NAME,
            path: 'lottie_empty.json'
          })
          if (this.lottieAnimItem) {
            this.lottieAnimItem.setSpeed(0.5)
          }
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// 隐藏文件夹管理：查看并移除黑名单文件夹。
