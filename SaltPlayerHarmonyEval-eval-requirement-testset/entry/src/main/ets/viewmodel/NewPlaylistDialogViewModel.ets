// NewPlaylistDialogViewModel.ets
// ViewModel layer: manages state and logic for the NewPlaylistDialog view
// Bridges the View and Model layers per MVVM architecture

import { NewPlaylistData, NewPlaylistDataSource } from '../model/NewPlaylistModel'

@Observed
export default class NewPlaylistDialogViewModel {
  // The playlist name entered by the user (bound to TextInput in View)
  @Track public playlistName: string = ''

  // Title text resource for the dialog
  @Track public titleResource: Resource = $r('app.string.new_playlist')

  // Placeholder text resource for the input field
  @Track public placeholderResource: Resource = $r('app.string.enter_the_playlist_name_here')

  // Cancel button text resource
  @Track public cancelTextResource: Resource = $r('app.string.cancel')

  // Confirm button text resource
  @Track public confirmTextResource: Resource = $r('app.string.confirm')

  // Callback to execute when user confirms creating a new playlist
  // This delegates to the parent component or service layer
  @Track public onConfirmAction: (name: string) => void = () => {}

  // Callback to execute when user cancels the dialog
  @Track public onCancelAction: () => void = () => {}

  constructor(onConfirm?: (name: string) => void, onCancel?: () => void) {
    if (onConfirm) {
      this.onConfirmAction = onConfirm
    }
    if (onCancel) {
      this.onCancelAction = onCancel
    }
  }

  // Update the playlist name as user types
  updatePlaylistName(value: string): void {
    this.playlistName = value
  }

  // Check whether the confirm button should be enabled
  isConfirmEnabled(): boolean {
    return NewPlaylistDataSource.isValidName(this.playlistName)
  }

  // Handle confirm button click: always forward the raw name to the host.
  // Validation + DB persistence + toast are the host's responsibility so that
  // Scenario 1 (empty) and Scenario 2 (too-long) can display their toasts
  // before the dialog closes. The Model no longer runs as a side effect here.
  handleConfirm(): void {
    this.onConfirmAction(this.playlistName)
  }

  // Handle cancel button click
  handleCancel(): void {
    this.onCancelAction()
  }

  // Reset the dialog state (e.g., when dialog is reopened)
  reset(): void {
    this.playlistName = ''
  }
}
