// AlbumListSettingsDialogComponent.ets
// View layer: UI component for album list settings dialog.
// Uses AlbumListSettingsViewModel for data and logic, following MVVM pattern.
// Re-exports AlbumSortType from Model for backward compatibility.

import AlbumListSettingsViewModel from '../viewmodel/AlbumListSettingsViewModel'
import { AlbumSortType } from '../model/AlbumListSettingsModel'

export { AlbumSortType } from '../model/AlbumListSettingsModel'

// Shared UI component (no ViewModel dependency): renders a single check row item.
@Component
struct ItemCheckRow {
  @Prop isChecked: boolean = false
  label: ResourceStr = ''
  onItemClick: () => void = () => {}

  build() {
    Row() {
      if (this.isChecked) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(22)
          .fontColor([$r('app.color.salt_color_high_light')])
          .margin({ left: 14 })
      } else {
        SymbolGlyph($r('sys.symbol.circle'))
          .fontSize(22)
          .fontColor([$r('app.color.salt_color_high_light')])
          .margin({ left: 14 })
      }

      Text(this.label)
        .fontSize(16)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .margin({ left: 12 })
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onItemClick()
    })
  }
}

@Component
export struct AlbumListSettingsDialogComponent {
  // View binds to ViewModel via @ObjectLink for two-way observation.
  @ObjectLink viewModel: AlbumListSettingsViewModel
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  // Callbacks to notify parent component of changes (View -> parent communication via events).
  onSortTypeChange: (sortType: number) => void = () => {
  }
  onMinColumnsChange: (columns: number) => void = () => {
  }

  build() {
    Column() {
      // ========== Dialog Title ==========
      Text($r('app.string.album_list_settings'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 8, top: 20, bottom: 12 })

      // ========== Sort Section ==========
      Text($r('app.string.sort'))
        .fontSize(13)
        .fontColor($r('app.color.colorSubTextForeground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 8, top: 16, bottom: 8 })

      Column() {
        ItemCheckRow({
          isChecked: this.viewModel.isSortTypeSelected(AlbumSortType.TITLE),
          label: $r('app.string.title'),
          onItemClick: () => {
            this.viewModel.changeSortType(AlbumSortType.TITLE)
            this.onSortTypeChange(AlbumSortType.TITLE)
          }
        })

        ItemCheckRow({
          isChecked: this.viewModel.isSortTypeSelected(AlbumSortType.YEAR),
          label: $r('app.string.year'),
          onItemClick: () => {
            this.viewModel.changeSortType(AlbumSortType.YEAR)
            this.onSortTypeChange(AlbumSortType.YEAR)
          }
        })

        ItemCheckRow({
          isChecked: this.viewModel.isSortTypeSelected(AlbumSortType.COUNT),
          label: $r('app.string.count'),
          onItemClick: () => {
            this.viewModel.changeSortType(AlbumSortType.COUNT)
            this.onSortTypeChange(AlbumSortType.COUNT)
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorPageBackground'))

      // ========== Minimum Columns Section (with fade + slide transition) ==========
      if (this.viewModel.isMinimumColumnsVisible()) {
        Column() {
          Text($r('app.string.minimum_number_of_columns'))
            .fontSize(13)
            .fontColor($r('app.color.colorSubTextForeground'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: 8, top: 16, bottom: 8 })

          Column() {
            ItemCheckRow({
              isChecked: this.viewModel.isColumnCountSelected(2),
              label: '2',
              onItemClick: () => {
                this.viewModel.changeMinimumColumns(2)
                this.onMinColumnsChange(2)
              }
            })

            ItemCheckRow({
              isChecked: this.viewModel.isColumnCountSelected(3),
              label: '3',
              onItemClick: () => {
                this.viewModel.changeMinimumColumns(3)
                this.onMinColumnsChange(3)
              }
            })

            ItemCheckRow({
              isChecked: this.viewModel.isColumnCountSelected(4),
              label: '4',
              onItemClick: () => {
                this.viewModel.changeMinimumColumns(4)
                this.onMinColumnsChange(4)
              }
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorPageBackground'))
        }
        .width('100%')
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseInOut })
            .combine(TransitionEffect.translate({ y: -20 }).animation({ duration: 250, curve: Curve.EaseInOut }))
        )
      }

      // Bottom spacer
      Row()
        .height(24)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
