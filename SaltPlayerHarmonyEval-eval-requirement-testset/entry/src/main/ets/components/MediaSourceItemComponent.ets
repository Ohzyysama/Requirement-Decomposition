// MediaSourceItemComponent.ets
// View layer: Business component for rendering a single media source item row
// Displays folder icon, name, path, and optional remove button.
// Binds to parent ViewModel data via @Prop for item data and callback.
// This is a business component (not shared) as it depends on project-specific data types.

import { UserMediaSourceInfo, MediaSourceType } from '../model/MediaSourceModel'
import MediaSourcePageViewModel from '../viewmodel/MediaSourcePageViewModel'

@Component
export struct MediaSourceItemComponent {
  @Prop item: UserMediaSourceInfo = new UserMediaSourceInfo()
  @ObjectLink viewModel: MediaSourcePageViewModel

  build() {
    Row() {
      // Folder icon
      Image(this.viewModel.getMediaSourceIcon(this.item.type))
        .width(24)
        .height(24)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .margin({ left: 16 })

      // Name and path
      Column() {
        Text(this.item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.item.sub)
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      // Remove button (only for removable types)
      if (this.viewModel.isRemovable(this.item)) {
        Image($r('app.media.ic_cancel'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.salt_color_icon_foreground'))
          .margin({ right: 16 })
          .onClick(() => {
            this.viewModel.requestRemoveFolder(this.item)
          })
          .accessibilityText('移除')
      }
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
  }
}
