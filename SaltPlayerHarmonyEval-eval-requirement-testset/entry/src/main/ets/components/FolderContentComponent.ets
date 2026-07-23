// FolderContentComponent.ets
// View layer: Folder list content component for Salt Player
// Corresponds to Android FolderScreen.kt - FolderScreenContent composable
// Displays SD card items and folder items with right ABC index
//
// MVVM Architecture:
//   View: FolderContentComponent (this file) - only UI rendering and user interaction
//   ViewModel: FolderContentViewModel - dialog state management, scroll logic
//   Model: FolderModel (SDCardInfo, FolderInfo) - pure data structures

import RightABCModel from '../model/RightABCModel'
import { FolderMenuDialogComponent } from './FolderMenuDialogComponent'
import { HideFolderDialog } from './HideFolderDialog'
import { SDCardInfo, FolderInfo } from '../model/FolderModel'
import { FolderContentViewModel } from '../viewmodel/FolderContentViewModel'
import { vibrator } from '@kit.SensorServiceKit'
import { MiniPlayerDefaults } from '../pages/main/MiniPlayerContainer'

// Re-export model types so existing consumers can import from this file
export { SDCardInfo, FolderInfo } from '../model/FolderModel'

@Component
export struct FolderContentComponent {
  // Data from parent (read-only via @Prop)
  @Prop sdCards: SDCardInfo[] = []
  @Prop folders: FolderInfo[] = []

  // Callbacks for parent component navigation
  onSDCardClick: (path: string) => void = () => {}
  onFolderClick: (folderPath: string) => void = () => {}
  onFolderMenuClick: (folder: FolderInfo) => void = () => {}
  onHideFolderConfirmed: () => void = () => {}

  // ViewModel: manages dialog state and business logic
  @State viewModel: FolderContentViewModel = new FolderContentViewModel()

  // Sheet binding requires a direct @State boolean for $$ two-way binding
  @State showFolderMenu: boolean = false
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''

  // Scroller for the list
  private listScroller: Scroller = new Scroller()
  // Hide folder confirmation dialog controller (created on-demand)
  private hideFolderDialogController?: CustomDialogController
  @State private alphabetSelected: number = 0
  @State private alphabetPopupLetter: string = ''
  @State private alphabetPopupVisible: boolean = false

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // Main scrollable content
      List({ scroller: this.listScroller }) {
        // SD Card items
        ForEach(this.sdCards, (sdCard: SDCardInfo) => {
          ListItem() {
            this.SDCardItemBuilder(sdCard)
          }
        }, (sdCard: SDCardInfo) => sdCard.path)

        // Folder items
        ForEach(this.folders, (folder: FolderInfo) => {
          ListItem() {
            this.FolderItemBuilder(folder)
          }
        }, (folder: FolderInfo) => folder.id)
      }
      .width('100%')
      .height('100%')
      .contentEndOffset(96)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      // Right ABC index
      if (this.folders.length > 0) {
        Row() {
          if (this.alphabetPopupVisible) {
            Stack() {
              Text(this.alphabetPopupLetter)
                .fontSize(32)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.salt_color_high_light'))
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor($r('app.color.salt_color_sub_background'))
            .alignContent(Alignment.Center)
          }

          AlphabetIndexer({ arrayValue: new RightABCModel().alphabetArray, selected: $$this.alphabetSelected })
            .onSelect((index: number) => {
              const char = new RightABCModel().alphabetArray[index]
              this.scrollToChar(char)
              this.alphabetPopupLetter = char
              this.alphabetPopupVisible = true
              vibrator.startVibration({ type: 'time', duration: 20 }, { id: 0, usage: 'touch' })
            })
            .selectedColor($r('app.color.colorSubTextForeground'))
            .selectedBackgroundColor(Color.Transparent)
            .usingPopup(false)
            .autoCollapse(false)
            .selectedFont({ size: 10, weight: FontWeight.Bold })
            .font({ size: 10 })
            .itemSize(15)
            .alignStyle(IndexerAlign.Left)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.alphabetPopupVisible = false
              }
            })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .height('100%')
        .offset({ x: 3 })
        .padding({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showFolderMenu, this.folderMenuBuilder(), {
      detents: ['60%', SheetSize.LARGE],
      dragBar: false,
      showClose: false,
      backgroundColor: this.isSystemDark ? $r('app.color.salt_color_dialog_background') : $r('app.color.salt_color_sub_background'),
      onDisappear: () => {
        this.showFolderMenu = false
        this.viewModel.closeFolderMenu()
      }
    })
  }

  // ======================== SD Card Item ========================
  // Matches Android SDCardItem: RoundedColumn > Item with icon, text, sub
  // Uses ic_storage icon, rounded corner card background
  @Builder
  SDCardItemBuilder(sdCard: SDCardInfo) {
    Column() {
      Column() {
        Row() {
          // Storage icon - 24dp matching Android Item composable
          Image($r('app.media.ic_storage'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.salt_color_icon_foreground'))

          // Text content
          Column() {
            Text(sdCard.name)
              .fontSize(15)
              .fontColor($r('app.color.salt_color_icon_foreground'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(sdCard.usedSize.length > 0 ?
              `${sdCard.path}\n${sdCard.usedSize} / ${sdCard.totalSize}` : sdCard.path)
              .fontSize(12)
              .fontColor($r('app.color.colorSubTextForeground'))
              .maxLines(2)
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 12, bottom: 12 })
          .margin({ left: 12 })

          // Right chevron arrow
          Image($r('app.media.ic_chevron_right'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.colorSubTextForeground'))
            .objectFit(ImageFit.Contain)
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_bottom_page_background'))
      .clip(true)
      .onClick(() => {
        this.onSDCardClick(sdCard.path)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  // ======================== Folder Item ========================
  // Matches Android FolderItem: Row with folder icon, name, count, and 3-dot menu
  @Builder
  FolderItemBuilder(folder: FolderInfo) {
    Column() {
      Row() {
        // Left padding
        Blank().width(16)

        // Folder icon - Android: ic_ui_folder, 24.dp, tint = SaltTheme.colors.text
        Image($r('app.media.ic_ui_folder'))
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.salt_color_icon_foreground'))

        // Spacer 12dp
        Blank().width(12)

        // Text content
        Column() {
          Text(folder.name)
            .fontSize(15)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Blank().height(2)

          Text(`${folder.count} 首`)
            .fontSize(13)
            .fontColor($r('app.color.colorSubTextForeground'))
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 12, bottom: 12 })

        // Spacer 12dp
        Blank().width(12)

        // 3-dot menu icon - Android: ic_more_vert, 56.dp, tint = text.copy(alpha = 0.75f)
        Image($r('app.media.ic_more_vert'))
          .width(56)
          .height(56)
          .padding(18)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .opacity(0.75)
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            // Delegate to ViewModel to manage dialog state
            this.viewModel.openFolderMenu(folder)
            this.showFolderMenu = true
          })
          .accessibilityText('菜单')
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('app.color.salt_color_bottom_page_background'))
      .alignItems(VerticalAlign.Center)
      .clip(true)
      .onClick(() => {
        this.onFolderClick(folder.path)
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  // ======================== Folder Menu Builder ========================
  @Builder
  folderMenuBuilder() {
    FolderMenuDialogComponent({
      viewModel: this.viewModel.folderMenuDialogViewModel,
      onDismiss: () => {
        this.viewModel.closeFolderMenu()
      },
      onHideFolder: () => {
        // Close menu sheet first, then show confirmation dialog
        this.showFolderMenu = false
        this.viewModel.closeFolderMenu()
        this.showHideConfirmDialog()
      }
    })
  }

  // ======================== Hide Folder Confirmation Dialog ========================
  private showHideConfirmDialog(): void {
    const folderPath = this.viewModel.folderMenuDialogViewModel.folderPath
    setTimeout(() => {
      this.hideFolderDialogController = new CustomDialogController({
        builder: HideFolderDialog({
          folderPath: folderPath,
          onConfirm: () => {
            this.viewModel.folderMenuDialogViewModel.hideFolder()
            this.onHideFolderConfirmed()
          }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true,
        maskColor: '#80000000',
        openAnimation: { duration: 0 },
        closeAnimation: { duration: 0 }
      })
      this.hideFolderDialogController.open()
    }, 50)
  }

  // ======================== Scroll to Character ========================
  private scrollToChar(char: string): void {
    const targetIndex = this.viewModel.getScrollIndexForChar(char, this.sdCards.length, this.folders)
    if (targetIndex >= 0) {
      this.listScroller.scrollToIndex(targetIndex)
    }
  }
}
