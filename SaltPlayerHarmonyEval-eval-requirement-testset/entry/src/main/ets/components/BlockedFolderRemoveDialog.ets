// BlockedFolderRemoveDialog.ets
// View layer - Business Component: Confirmation dialog for removing a blocked folder
// Corresponds to Android YesNoDialog used in BlockedFoldersScreen
//
// MVVM: This dialog is a business component that binds to the ViewModel via @Link.
// - It reads `viewModel.removePath` to display the folder path being removed
// - The confirm action delegates to the ViewModel through the onConfirm callback
// - The View (parent page) is responsible for connecting the callback to ViewModel.confirmRemoveFolder()

import BlockedFoldersViewModel from '../viewmodel/BlockedFoldersViewModel'

@CustomDialog
export struct BlockedFolderRemoveDialog {
  controller: CustomDialogController
  // View binds to ViewModel: the folder path to display comes from ViewModel
  @Link viewModel: BlockedFoldersViewModel
  // Callback to ViewModel's confirmRemoveFolder method, provided by the parent View
  onConfirm: () => void = () => {}

  private static decodePath(path: string): string {
    try {
      return decodeURIComponent(path)
    } catch (e) {
      return path
    }
  }

  build() {
    Column() {
      // Dialog title - "移除"
      Text($r('app.string.remove'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 8 })

      // Dialog content - folder path from ViewModel, decoded for display
      Text(BlockedFolderRemoveDialog.decodePath(this.viewModel.removePath))
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 16 })
        .wordBreak(WordBreak.BREAK_ALL)

      // Button row - Cancel (left, outline) and Confirm (right, highlight filled)
      Row() {
        // Cancel button - outline style, gray text
        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor($r('app.color.salt_color_sub_text'))
          .backgroundColor($r('app.color.salt_color_sub_background'))
          .borderRadius(20)
          .layoutWeight(1)
          .height(42)
          .onClick(() => {
            this.controller.close()
          })

        // Spacer between buttons
        Blank()
          .width(16)

        // Confirm button - filled highlight
        Button($r('app.string.confirm'))
          .type(ButtonType.Normal)
          .fontSize(15)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(20)
          .layoutWeight(1)
          .height(42)
          .onClick(() => {
            // Delegate confirm action to ViewModel via callback
            this.onConfirm()
            this.controller.close()
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 8, bottom: 24 })
    }
    .backgroundColor($r('app.color.salt_color_dialog_background'))
    .borderRadius(16)
    .margin({ left: 24, right: 24 })
  }
}
