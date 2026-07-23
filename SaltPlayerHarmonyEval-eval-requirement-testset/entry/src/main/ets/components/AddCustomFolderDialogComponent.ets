// AddCustomFolderDialogComponent.ets
// View layer: "Add Custom Folder" bottom sheet dialog for Salt Player
// Corresponds to Android AddCustomFolderDialog.kt (com.salt.music.ui.screen.mediasource)
// Displayed as a bindSheet when user taps "添加自定义文件夹" on MediaSourcePage
// Contains: native file manager option, USB disk option, and a tech support link
//
// MVVM architecture:
// - View: this file (UI rendering only)
// - ViewModel: AddCustomFolderDialogViewModel (data and business logic)
// - Model: AddCustomFolderModel (data structures)

import { AddCustomFolderDialogViewModel } from '../viewmodel/AddCustomFolderDialogViewModel';
import { DialogMenuActionType, TechSupportItem } from '../model/AddCustomFolderModel';

@Component
export struct AddCustomFolderDialogComponent {
  onNativeFileManager: () => void = () => {};
  onUsbDisk: () => void = () => {};
  // ViewModel: manages data and business logic for this dialog
  @State viewModel: AddCustomFolderDialogViewModel =
    new AddCustomFolderDialogViewModel(() => {}, () => {});

  aboutToAppear(): void {
    // Initialize ViewModel with callbacks from parent
    this.viewModel = new AddCustomFolderDialogViewModel(
      this.onNativeFileManager,
      this.onUsbDisk
    );
  }

  build() {
    Column() {
      // ========== Dialog Title: "添加自定义文件夹" ==========
      Text($r('app.string.add_custom_folder'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 8, top: 20, bottom: 12 })

      // ========== Rounded section: file manager options ==========
      Column() {
        // Item: Native File Manager
        Row() {
          Image($r('app.media.ic_ui_folder'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.salt_color_icon_foreground'))

          Text($r('app.string.native_file_manager'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .opacity(0.8)
            .layoutWeight(1)
            .margin({ left: 12 })

          Image($r('app.media.ic_chevron_right'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.colorSubTextForeground'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          // Delegate to ViewModel
          this.viewModel.handleFolderOptionClick(DialogMenuActionType.NATIVE_FILE_MANAGER);
        })

        // Tip text from ViewModel
        Text(this.viewModel.tipText)
          .fontSize(11)
          .fontColor($r('app.color.colorSubTextForeground'))
          .opacity(0.7)
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 4 })

        // Item: USB Disk
        Row() {
          Image($r('app.media.ic_ui_folder'))
            .width(24)
            .height(24)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.salt_color_icon_foreground'))

          Text($r('app.string.usb_disk'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .opacity(0.8)
            .layoutWeight(1)
            .margin({ left: 12 })

          Image($r('app.media.ic_chevron_right'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.colorSubTextForeground'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          // Delegate to ViewModel
          this.viewModel.handleFolderOptionClick(DialogMenuActionType.USB_DISK);
        })
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor($r('app.color.colorPageBackground'))

      // ========== Section title: "技术支持" ==========
      Text($r('app.string.technical_support'))
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.colorSubTextForeground'))
        .padding({ left: 8, top: 25, bottom: 11 })
        .width('100%')

      // ========== Rounded section: tech support links ==========
      Column() {
        ForEach(this.viewModel.techSupportItems, (item: TechSupportItem) => {
          Row() {
            Text(item.text)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.salt_color_icon_foreground'))
              .opacity(0.8)
              .layoutWeight(1)

            Image($r('app.media.ic_open_in_new'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.colorSubTextForeground'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            // Delegate to ViewModel
            this.viewModel.handleTechSupportClick(item);
          })
        }, (item: TechSupportItem) => item.url)
      }
      .width('100%')
      .padding({ top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor($r('app.color.colorPageBackground'))

      // Bottom spacer
      Row().height(24)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
