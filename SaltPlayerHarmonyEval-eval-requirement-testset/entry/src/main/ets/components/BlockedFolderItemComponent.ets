// BlockedFolderItemComponent.ets
// View layer - Business Component: displays a single blocked folder item
// This is a business component because it uses ViewModel data (through @Link).
//
// MVVM: Receives the ViewModel from the parent page via @Link.
// User interaction (remove button click) calls ViewModel methods.
// This component cannot function without the ViewModel, hence it is a business component.

import BlockedFoldersViewModel from '../viewmodel/BlockedFoldersViewModel'

@Component
export struct BlockedFolderItemComponent {
  // Bind to parent's ViewModel via @Link for two-way synchronization
  @Link viewModel: BlockedFoldersViewModel

  // The folder path to display (passed from ForEach in the parent page)
  @Prop path: string = ''

  // Callback to open the remove confirmation dialog (provided by parent page)
  onRemoveClick: () => void = () => {}

  private static decodePath(path: string): string {
    try {
      return decodeURIComponent(path)
    } catch (e) {
      return path
    }
  }

  build() {
    Row() {
      // Folder icon with highlight color
      Image($r('app.media.ic_folder'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.salt_color_high_light'))
        .margin({ left: 16 })

      // Path text - decode URI for display, no maxLines limit so long paths can be fully displayed
      Column() {
        Text(BlockedFolderItemComponent.decodePath(this.path))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .wordBreak(WordBreak.BREAK_ALL)
      }
      .layoutWeight(1)
      .margin({ left: 16 })
      .padding({ top: 16, bottom: 16 })

      // Remove button (cancel icon)
      Image($r('app.media.ic_cancel'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .margin({ left: 16, right: 16 })
        .onClick(() => {
          // View calls ViewModel method to set removal target
          this.viewModel.selectFolderForRemoval(this.path)
          // Notify parent to open the dialog
          this.onRemoveClick()
        })
        .accessibilityText('移除')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
