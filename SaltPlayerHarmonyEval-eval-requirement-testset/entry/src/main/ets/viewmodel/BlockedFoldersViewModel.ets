// BlockedFoldersViewModel.ets
// ViewModel layer: provides data and logic for the BlockedFoldersPage view.
// Bridges the View and Model layers per MVVM architecture.
//
// This ViewModel:
// - Uses @Observed to enable deep observation by @State in the View
// - Uses @Track for property-level UI updates (avoids redundant rendering)
// - Delegates all data persistence to the Model layer
// - Provides methods for View event handlers to call

import BlockedFolderModel, { BlockedFolderDataSource } from '../model/BlockedFolderModel'

@Observed
export default class BlockedFoldersViewModel {
  // Lottie animation name for the empty state (matches SearchAllSongsViewModel pattern).
  // @Track required: API 23 runtime hard-crashes on UI reads of untracked
  // properties on @Observed objects.
  @Track public readonly LOTTIE_ANIM_NAME: string = 'lottie_empty'

  // The list of blocked folder paths displayed in the UI
  @Track public blockedFolders: string[] = []

  // The folder path currently selected for removal (bound to the dialog)
  @Track public removePath: string = ''

  // Load blocked folders from the Model layer
  // Called by the View when the page is ready
  loadBlockedFolders(): void {
    const models: BlockedFolderModel[] = BlockedFolderDataSource.loadBlockedFolders()
    this.blockedFolders = models.map((model: BlockedFolderModel) => model.path)
  }

  // Set the folder path to be removed (called before opening the confirmation dialog)
  // View calls this method when user taps the remove icon on a folder item
  selectFolderForRemoval(path: string): void {
    this.removePath = path
  }

  // Confirm removal of the selected folder
  // Called by the dialog's confirm action through the View's callback
  confirmRemoveFolder(): void {
    // Replace array reference to trigger @Track re-render
    this.blockedFolders = this.blockedFolders.filter((p: string) => p !== this.removePath)
    // Delegate to Model layer for persistence and library rescan
    BlockedFolderDataSource.removeBlockedFolder(this.removePath)
    BlockedFolderDataSource.triggerLibraryRescan()
  }
}
