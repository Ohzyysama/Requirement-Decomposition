// FolderMenuDialogComponent.ets
// View layer: dialog component for folder context menu actions
// Corresponds to Android FolderMenuDialog.kt
// Shows folder path info and "hide folder" option
// Uses FolderMenuDialogViewModel for data binding per MVVM architecture

import FolderMenuDialogViewModel from '../viewmodel/FolderMenuDialogViewModel'

@Component
export struct FolderMenuDialogComponent {
  @ObjectLink viewModel: FolderMenuDialogViewModel
  onDismiss: () => void = () => {}
  onHideFolder: () => void = () => {}
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  build() {
    Column() {
      // Dialog title - folder name (matches sort dialog title style)
      Text(this.viewModel.folderName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 8, top: 20, bottom: 12 })

      // Rounded content area - matches Android RoundedColumn
      Column() {
        // Path info - matches Android ItemValue(text="路径", sub=path)
        Column() {
          Text($r('app.string.path'))
            .fontSize(12)
            .fontColor($r('app.color.colorSubTextForeground'))

          Text(this.viewModel.folderPath)
            .fontSize(16)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .wordBreak(WordBreak.BREAK_ALL)
            .margin({ top: 2 })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)

        // Hide folder option - matches Android DialogItem
        Row() {
          Image($r('app.media.ic_hide'))
            .width(22)
            .height(22)
            .objectFit(ImageFit.Contain)

          Text($r('app.string.hide'))
            .fontSize(15)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .margin({ left: 16 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onHideFolder()
        })
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.salt_color_dialog_background'))
      .clip(true)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }
}
