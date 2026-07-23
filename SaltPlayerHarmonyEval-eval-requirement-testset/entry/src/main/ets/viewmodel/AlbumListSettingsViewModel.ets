// AlbumListSettingsViewModel.ets
// ViewModel layer: provides data and logic for AlbumListSettingsDialogComponent (View).
// Bridges the Model layer data with the View layer, exposing state variables and methods.

import AlbumListSettingsModel, { AlbumSortType } from '../model/AlbumListSettingsModel'

@Observed
export default class AlbumListSettingsViewModel {
  @Track public albumSortType: number = AlbumSortType.TITLE
  @Track public minimumColumns: number = 2

  constructor(sortType: number = AlbumSortType.TITLE, minimumColumns: number = 2) {
    this.albumSortType = sortType
    this.minimumColumns = minimumColumns
  }

  // Load settings from Model data
  updateFromModel(model: AlbumListSettingsModel): void {
    this.albumSortType = model.sortType
    this.minimumColumns = model.minimumColumns
  }

  // Export current state back to Model
  toModel(): AlbumListSettingsModel {
    return new AlbumListSettingsModel(this.albumSortType, this.minimumColumns)
  }

  // Change sort type
  changeSortType(sortType: number): void {
    this.albumSortType = sortType
  }

  // Change minimum columns
  changeMinimumColumns(columns: number): void {
    this.minimumColumns = columns
  }

  // Whether to show the minimum columns section (hidden when sort type is YEAR)
  isMinimumColumnsVisible(): boolean {
    return this.albumSortType !== AlbumSortType.YEAR
  }

  // Check if a given sort type is the currently selected one
  isSortTypeSelected(sortType: number): boolean {
    return this.albumSortType === sortType
  }

  // Check if a given column count is the currently selected one
  isColumnCountSelected(columns: number): boolean {
    return this.minimumColumns === columns
  }
}
