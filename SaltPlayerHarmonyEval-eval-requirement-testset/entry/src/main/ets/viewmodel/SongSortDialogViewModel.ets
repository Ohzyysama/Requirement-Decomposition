// SongSortDialogViewModel.ets
// ViewModel layer: provides data and logic for SongSortDialogComponent (View).
// Bridges the Model layer data with the View layer, exposing state variables and methods.

import SongSortModel, { SongLazySort, SongSortDisplaySettings } from '../model/SongSortModel'

@Observed
export default class SongSortDialogViewModel {
  @Track public songLazySort: number = SongLazySort.TITLE
  @Track public customizable: boolean = false
  @Track public displaySongCoverInList: boolean = true
  @Track public displaySongFileNameInList: boolean = false
  @Track public displayAddToPlayNextInList: boolean = true

  // Callbacks to communicate with parent
  @Track public onSortClick: (sort: number) => void = () => {}
  @Track public onDisplaySettingChange: (key: string, value: boolean) => void = () => {}

  constructor(
    songLazySort: number = SongLazySort.TITLE,
    customizable: boolean = false,
    displaySongCoverInList: boolean = true,
    displaySongFileNameInList: boolean = false,
    displayAddToPlayNextInList: boolean = true
  ) {
    this.songLazySort = songLazySort
    this.customizable = customizable
    this.displaySongCoverInList = displaySongCoverInList
    this.displaySongFileNameInList = displaySongFileNameInList
    this.displayAddToPlayNextInList = displayAddToPlayNextInList
  }

  // Load state from Model data
  updateFromModel(model: SongSortModel): void {
    this.songLazySort = model.sortType
    this.customizable = model.customizable
    this.displaySongCoverInList = model.displaySettings.displaySongCoverInList
    this.displaySongFileNameInList = model.displaySettings.displaySongFileNameInList
    this.displayAddToPlayNextInList = model.displaySettings.displayAddToPlayNextInList
  }

  // Export current state back to Model
  toModel(): SongSortModel {
    return new SongSortModel(
      this.songLazySort,
      this.customizable,
      new SongSortDisplaySettings(
        this.displaySongCoverInList,
        this.displaySongFileNameInList,
        this.displayAddToPlayNextInList
      )
    )
  }

  // Check if a given sort type is the currently selected one
  isSortTypeSelected(sortType: number): boolean {
    return this.songLazySort === sortType
  }

  // Handle sort selection
  selectSort(sortType: number): void {
    this.songLazySort = sortType
    this.onSortClick(sortType)
  }

  // Handle display setting toggle
  toggleDisplaySetting(key: string, value: boolean): void {
    if (key === 'displaySongCoverInList') {
      this.displaySongCoverInList = value
    } else if (key === 'displaySongFileNameInList') {
      this.displaySongFileNameInList = value
    } else if (key === 'displayAddToPlayNextInList') {
      this.displayAddToPlayNextInList = value
    }
    this.onDisplaySettingChange(key, value)
  }

  // Whether to show the custom sort option
  isCustomSortVisible(): boolean {
    return this.customizable
  }
}
