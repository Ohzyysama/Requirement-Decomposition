// ExitAppDialogViewModel.ets
// ViewModel layer: provides data and logic for the ExitAppDialog view
// Bridges the View and Model layers per MVVM architecture

import { ExitAppAction, ExitAppDataSource } from '../model/ExitAppModel'

@Observed
export default class ExitAppDialogViewModel {
  // The last executed action, can be observed by the View if needed
  @Track public lastAction: ExitAppAction = ExitAppAction.NONE

  // Handle the exit app action
  // Called by the View when user taps "exit app" button
  handleExitApp(): void {
    this.lastAction = ExitAppAction.EXIT_APP
    ExitAppDataSource.exitApp()
  }

  // Handle the return to desktop action
  // Called by the View when user taps "return to desktop" button
  handleReturnToDesktop(): void {
    this.lastAction = ExitAppAction.RETURN_TO_DESKTOP
    ExitAppDataSource.returnToDesktop()
  }
}
