// DeleteSongDialogViewModel.ets
// ViewModel layer: manages state and logic for the DeleteSongDialog view
// Bridges the View and Model layers per MVVM architecture
// Note: "Remove from library" only removes the song record from the app's database,
// it does NOT delete the original audio file from the file system.
//
// MVVM architecture:
//   View: DeleteSongDialog
//   ViewModel: DeleteSongDialogViewModel (this file)
//   Model: DeleteSongModel

import { DeleteSongInfo, DeleteSongAction, DeleteSongDataSource } from '../model/DeleteSongModel'

@Observed
export default class DeleteSongDialogViewModel {
  // Song title to display in the dialog content
  @Track public songTitle: string = ''

  @Track public titleResource: Resource = $r('app.string.remove_from_library')

  // Cancel button text resource
  @Track public cancelTextResource: Resource = $r('app.string.cancel')

  // Confirm button text resource
  @Track public confirmTextResource: Resource = $r('app.string.confirm')

  // The last executed action, can be observed by the View if needed
  @Track public lastAction: DeleteSongAction = DeleteSongAction.NONE

  // Callback to execute when user confirms removal
  // This delegates to the Model/service layer via the parent component
  @Track public onConfirmAction: () => void = () => {}

  // Initialize the ViewModel with song information
  initWithSongInfo(songInfo: DeleteSongInfo): void {
    this.songTitle = songInfo.songTitle
  }

  // Build the confirmation message text
  getConfirmMessage(): string {
    return `从音乐库中移除 ${this.songTitle} 吗?`
  }

  // Handle confirm button click: delegate removal to the Model layer
  handleConfirm(): void {
    this.lastAction = DeleteSongAction.CONFIRM
    DeleteSongDataSource.removeFromLibrary(this.songTitle, this.onConfirmAction)
  }

  // Handle cancel button click
  handleCancel(): void {
    this.lastAction = DeleteSongAction.CANCEL
  }
}
