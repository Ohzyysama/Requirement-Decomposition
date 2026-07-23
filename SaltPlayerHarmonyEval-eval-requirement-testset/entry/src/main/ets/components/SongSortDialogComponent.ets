// SongSortDialogComponent.ets
// View layer: UI component for song sort dialog.
// Uses SongSortDialogViewModel for state and logic per MVVM architecture.
// Re-exports SongLazySort from Model for backward compatibility with existing consumers.

import SongSortDialogViewModel from '../viewmodel/SongSortDialogViewModel'
import { SongLazySort } from '../model/SongSortModel'

export { SongLazySort } from '../model/SongSortModel'

@Component
export struct SongSortDialogComponent {
  @Prop songLazySort: number = SongLazySort.TITLE
  @Prop customizable: boolean = false
  @Prop displaySongCoverInList: boolean = true
  @Prop displaySongFileNameInList: boolean = false
  @Prop displayAddToPlayNextInList: boolean = true
  @Prop showPlaylistAddTime: boolean = false
  onSortClick: (sort: number) => void = () => {}
  onDisplaySettingChange: (key: string, value: boolean) => void = () => {}

  @State private vm: SongSortDialogViewModel = new SongSortDialogViewModel()
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  aboutToAppear(): void {
    this.syncPropsToViewModel()
  }

  // Sync @Prop values into ViewModel when they change from parent
  private syncPropsToViewModel(): void {
    this.vm.songLazySort = this.songLazySort
    this.vm.customizable = this.customizable
    this.vm.displaySongCoverInList = this.displaySongCoverInList
    this.vm.displaySongFileNameInList = this.displaySongFileNameInList
    this.vm.displayAddToPlayNextInList = this.displayAddToPlayNextInList
    this.vm.onSortClick = this.onSortClick
    this.vm.onDisplaySettingChange = this.onDisplaySettingChange
  }

  build() {
    Column() {
      // ========== Dialog Title ==========
      Text($r('app.string.sort'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 8, top: 20, bottom: 12 })

      // ========== Sort Options (RoundedColumn) ==========
      Column() {
        if (this.vm.isCustomSortVisible()) {
          this.SortItem(SongLazySort.NONE, $r('app.string.custom'))
        }

        // 2-column grid — each row is a Row with two equal-weight items
        this.SortRow(SongLazySort.TITLE, $r('app.string.title'),
          SongLazySort.FILE_NAME, $r('app.string.file_name'))
        this.SortRow(SongLazySort.ALBUM, $r('app.string.sort_album_track'),
          SongLazySort.ARTIST, $r('app.string.sort_artist_album'))
        this.SortRow(SongLazySort.SIZE, $r('app.string.size'),
          SongLazySort.YEAR, $r('app.string.year'))
        this.SortRow(SongLazySort.FOLDER, $r('app.string.sort_folder_title'),
          -1, undefined)

        // Full-width sort options
        this.SortItem(SongLazySort.DURATION, $r('app.string.sort_by_duration'))
        this.SortItem(SongLazySort.DURATION_DESC, $r('app.string.sort_by_duration_desc'))
        this.SortItem(SongLazySort.DATE_MODIFIED, $r('app.string.date_modified'))
        this.SortItem(SongLazySort.ADD_TIME, $r('app.string.add_time'))
        this.SortItem(SongLazySort.DATE_MODIFIED_DESC, $r('app.string.date_modified_desc'))
        this.SortItem(SongLazySort.ADD_TIME_DESC, $r('app.string.add_time_desc'))

        if (this.showPlaylistAddTime) {
          this.SortItem(SongLazySort.PLAYLIST_ADD_TIME, $r('app.string.playlist_add_time'))
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorPageBackground'))

      // Spacer
      Row().height(12)

      // ========== Song List Settings ==========
      Column() {
        this.SettingsSwitchItem(
          $r('app.string.display_song_cover_in_list'), undefined,
          this.vm.displaySongCoverInList,
          (checked: boolean) => { this.vm.toggleDisplaySetting('displaySongCoverInList', checked) }
        )
        this.SettingsSwitchItem(
          $r('app.string.display_song_file_name_in_list'),
          $r('app.string.display_song_file_name_in_list_intro'),
          this.vm.displaySongFileNameInList,
          (checked: boolean) => { this.vm.toggleDisplaySetting('displaySongFileNameInList', checked) }
        )
        this.SettingsSwitchItem(
          $r('app.string.display_add_to_play_next_in_list'), undefined,
          this.vm.displayAddToPlayNextInList,
          (checked: boolean) => { this.vm.toggleDisplaySetting('displayAddToPlayNextInList', checked) }
        )
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor($r('app.color.colorPageBackground'))

      // Bottom spacer
      Row().height(24)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SortItem(sortType: number, text: ResourceStr) {
    Text(text)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.vm.songLazySort === sortType
        ? $r('app.color.salt_color_high_light')
        : $r('app.color.salt_color_icon_foreground'))
      .opacity(this.vm.songLazySort === sortType ? 1.0 : 0.8)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => { this.vm.selectSort(sortType) })
  }

  @Builder
  SortRow(leftType: number, leftText: ResourceStr,
    rightType: number, rightText: ResourceStr | undefined) {
    Row() {
      Text(leftText)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.vm.songLazySort === leftType
          ? $r('app.color.salt_color_high_light')
          : $r('app.color.salt_color_icon_foreground'))
        .opacity(this.vm.songLazySort === leftType ? 1.0 : 0.8)
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .layoutWeight(1)
        .onClick(() => { this.vm.selectSort(leftType) })

      if (rightText !== undefined && rightType >= 0) {
        Text(rightText)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.vm.songLazySort === rightType
            ? $r('app.color.salt_color_high_light')
            : $r('app.color.salt_color_icon_foreground'))
          .opacity(this.vm.songLazySort === rightType ? 1.0 : 0.8)
          .textAlign(TextAlign.Start)
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .layoutWeight(1)
          .onClick(() => { this.vm.selectSort(rightType) })
      } else {
        Text('').layoutWeight(1)
      }
    }
    .width('100%')
  }

  @Builder
  SettingsSwitchItem(text: ResourceStr, sub: ResourceStr | undefined, state: boolean,
    onChange: (isChecked: boolean) => void) {
    Row() {
      Column() {
        Text(text)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .opacity(0.8)
          .textAlign(TextAlign.Start)
        if (sub !== undefined) {
          Text(sub)
            .fontSize(11)
            .fontColor($r('app.color.colorSubTextForeground'))
            .margin({ top: 4 })
            .opacity(0.7)
            .textAlign(TextAlign.Start)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: state })
        .width(48)
        .height(26)
        .selectedColor($r('app.color.salt_color_high_light'))
        .onChange((isOn: boolean) => { onChange(isOn) })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }
}
