// ClearPlayQueueDialogViewModel.ets
// ViewModel layer: manages state and logic for the ClearPlayQueueDialog view
// Bridges the View and Model layers per MVVM architecture

@Observed
export default class ClearPlayQueueDialogViewModel {
  // Callback to execute when user confirms clearing the queue
  // This delegates to the Model/service layer via the parent component
  @Track public onConfirmAction: () => void = () => {}

  // Handle confirm button click: execute the clear queue action
  handleConfirm(): void {
    this.onConfirmAction()
  }
}
