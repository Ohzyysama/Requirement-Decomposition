// FolderMenuDialogViewModel.ets
// ViewModel layer: provides data and logic for the FolderMenuDialogComponent view
// Bridges the View and Model layers per MVVM architecture

import FolderMenuModel, { FolderMenuDataSource } from '../model/FolderMenuModel'

@Observed
export default class FolderMenuDialogViewModel {
  // The folder name displayed as dialog title
  @Track public folderName: string = ''

  // The folder path displayed in the path info section (decoded for display)
  @Track public folderPath: string = ''

  // Raw folder path (URI-encoded) used for hide operations
  @Track public rawFolderPath: string = ''

  // Update the ViewModel from a Model instance
  updateFromModel(model: FolderMenuModel): void {
    this.updateFolder(model.folderName, model.folderPath)
  }

  // Update the ViewModel with folder name and path directly
  // folderPath is stored as-is (raw URI) for hideFolder operations;
  // a decoded version is exposed for display.
  updateFolder(folderName: string, folderPath: string): void {
    this.folderName = folderName
    this.rawFolderPath = folderPath
    try {
      this.folderPath = decodeURIComponent(folderPath)
    } catch (e) {
      this.folderPath = folderPath
    }
  }

  // Handle the hide folder action
  // Called by the View when user taps the hide option
  hideFolder(): void {
    FolderMenuDataSource.hideFolder(this.rawFolderPath)
  }
}
