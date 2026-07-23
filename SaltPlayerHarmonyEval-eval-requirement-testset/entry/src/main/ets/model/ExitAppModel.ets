// ExitAppModel.ets
// Model layer: data structure and data operations for exit app actions
// Corresponds to Android ExitAppDialog.kt business logic

import AudioPlayerService from './AudioPlayerService'
import { common } from '@kit.AbilityKit'

// Enum representing the possible exit actions
export enum ExitAppAction {
  NONE,
  EXIT_APP,
  RETURN_TO_DESKTOP
}

// Data access operations for exit app
export class ExitAppDataSource {
  // Execute the exit app action
  // Android: App.exitApp() → finishAll → savePosition → stopService → killProcess
  static exitApp(): void {
    const service: AudioPlayerService = AudioPlayerService.getInstance()
    service.pause()
    service.saveStateBeforeExit()
    service.terminateApp()
  }

  // Execute the return to desktop action
  // Android: activity?.finish() — returns to desktop, music keeps playing
  static returnToDesktop(): void {
    const service: AudioPlayerService = AudioPlayerService.getInstance()
    const context: common.UIAbilityContext | null = service.getContext()
    if (context) {
      context.moveAbilityToBackground().catch((err: Error) => {
        console.error('ExitAppModel: returnToDesktop failed - ' + err.message)
      })
    }
  }
}
