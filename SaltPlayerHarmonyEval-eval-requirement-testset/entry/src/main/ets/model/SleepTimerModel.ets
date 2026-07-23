// SleepTimerModel.ets
// Model layer: data structure and data operations for sleep timer
// Corresponds to Android SleepTimerDialog.kt business logic

// Sleep timer state machine
export enum SleepTimerState {
  NULL = 0,                  // No timer running
  TICK = 1,                  // Main countdown active
  TICK_UNTIL_SONG_END = 2,   // Auto-extend phase: counting down remaining song time
  ERROR_END = 3              // Auto-extend cancelled (user paused/skipped)
}

// Data class representing the sleep timer configuration
export class SleepTimerConfig {
  public minutes: number = 15
  public autoExtend: boolean = true
}

// Constants for sleep timer constraints
export class SleepTimerConstants {
  static readonly MIN_MINUTES: number = 1
  static readonly MAX_MINUTES: number = 120
  static readonly DEFAULT_MINUTES: number = 15
  static readonly SLIDER_STEP: number = 1
}

// Data access operations for sleep timer (no longer used directly -- ViewModel calls SleepTimerService)
export class SleepTimerDataSource {
  static startSleepTimer(_config: SleepTimerConfig): void {
    // Delegated to SleepTimerService.getInstance().start() via ViewModel
  }

  static cancelSleepTimer(): void {
    // Delegated to SleepTimerService.getInstance().cancel() via ViewModel
  }
}
