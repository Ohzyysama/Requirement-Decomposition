// ScanningDialogViewModel.ets
// ViewModel layer: provides data and logic for the ScanningDialogComponent view
// Bridges the View and Model layers per MVVM architecture
// Orchestrates the real scanning process using ScanningDataSource
//
// Singleton: scan state lives across dialog dismiss / re-open AND across the
// page leaving — but a scan in progress is *canceled* (not paused) when the
// user dismisses the dialog by tapping outside, or when the app closes. All
// URIs authorized during this scan are revoked so the songs revert to the
// unauthorized state, matching the pre-scan situation.

import {
  ScanningDataSource,
  ScannedSongData,
  ScanResult,
  ScanLogCallback,
  ScanCanceledError,
  revokeFilePermissions
} from '../model/ScanningModel'
import { BlockedFolderDataSource } from '../model/BlockedFolderModel'
import { MediaSourceDataSource } from '../model/MediaSourceModel'

@Observed
export default class ScanningDialogViewModel {
  // Singleton instance — the View resolves the same VM each time the dialog
  // mounts, so cancel/cleanup state is consistent regardless of which page
  // owns the controller.
  private static _instance: ScanningDialogViewModel | null = null
  static getInstance(): ScanningDialogViewModel {
    if (!ScanningDialogViewModel._instance) {
      ScanningDialogViewModel._instance = new ScanningDialogViewModel()
    }
    return ScanningDialogViewModel._instance
  }

  // Whether scanning is currently in progress - drives UI state
  @Track public scanning: boolean = false
  // Accumulated scanning log text displayed in the scroll area (newest at top)
  @Track public scanningLog: string = ''
  // Current scan progress percentage (0-100)
  @Track public scanProgress: number = 0

  // Callback to notify the View to auto-scroll (UI concern handled by View)
  @Track private onLogUpdated: (() => void) | null = null

  // Cancellation flag: set by cancelScanning() (dialog dismiss / app close).
  // The pause checker observes it after wake and throws ScanCanceledError so
  // the metadata-extraction loop and the persist gate exit early.
  @Track private canceled: boolean = false

  // While a scan is mid-batch, pauseResolver lets cancelScanning unblock the
  // loop so it can reach the next checkpoint and observe the cancel flag.
  private pauseResolver: (() => void) | null = null

  // Context for accessing system APIs
  @Track private context: Context | null = null

  // Scan result
  @Track private scanResult: ScanResult | null = null

  // URIs authorized by the in-flight scan. Revoked on cancel; cleared on
  // successful persistence. Always mirrored to recovery preferences so a
  // process kill still leaves a record we can clean up next launch.
  private grantedUris: string[] = []

  // Log throttling: buffer messages and flush to UI periodically
  private logBuffer: string[] = []
  private logFlushPending: boolean = false
  private logFlushIntervalMs: number = 200

  // Set the context for the scanning operation
  setContext(context: Context): void {
    this.context = context
  }

  // Start the scanning process. Called by the View in aboutToAppear.
  // If a previous scan was canceled by the dialog being dismissed, the VM is
  // already in the "fresh" state (cancelScanning resets it) so we always start
  // a new scan when the user re-opens the dialog.
  startScanning(onLogUpdatedCallback?: () => void): void {
    this.onLogUpdated = onLogUpdatedCallback ?? null

    // If a scan is somehow still running (e.g. dialog re-mounts before the
    // canceled scan loop exits), do not start a second one — just attach the
    // log callback so the existing run can finish/cancel cleanly.
    if (this.scanning) {
      this.notifyLogUpdated()
      return
    }

    // Fresh scan: reset state
    this.scanning = true
    this.scanningLog = ''
    this.scanProgress = 0
    this.canceled = false
    this.pauseResolver = null
    this.grantedUris = []

    // Add the start scan log entry
    this.appendLog('Start scan ' + ScanningDataSource.formatDate(new Date()))
    this.scanProgress = 5

    // Launch the actual scan if context is available
    if (this.context) {
      this.requestPermissionsAndScan(this.context)
    } else {
      this.appendLog('Error: Context not available')
      this.scanning = false
    }
  }

  // DocumentViewPicker handles authorization through user file selection,
  // so no upfront permission request is needed.
  private async requestPermissionsAndScan(context: Context): Promise<void> {
    await this.executeScan(context)
  }

  // Pause checker passed to performScan. It resolves immediately while no
  // cancel is pending. If the scan was canceled while inside this checker
  // (e.g. cancelScanning ran while we were waiting), it throws so the caller
  // can short-circuit. The pauseResolver field lets cancelScanning unblock
  // the loop without leaking a never-resolved promise.
  private waitWhilePaused = async (): Promise<void> => {
    if (this.canceled) {
      throw new ScanCanceledError()
    }
    // No "paused" mode in this version — the only reason to wait here is so
    // cancelScanning has a chokepoint to interrupt at. If a cancel raced in
    // before the loop reached this checkpoint we'll throw immediately above.
  }

  // Track granted URIs and persist for crash-recovery.
  private onGrantedUris = (newUris: string[]): void => {
    this.grantedUris = newUris.slice()
    if (this.context) {
      ScanningDataSource.writePendingGrants(this.context, this.grantedUris)
        .catch((e: Error) => {
          console.warn('[Scan] writePendingGrants failed: ' + e.message)
        })
    }
  }

  // Execute the real scanning process asynchronously
  private async executeScan(context: Context): Promise<void> {
    try {
      // Load scan configuration
      const skipBelow60s = MediaSourceDataSource.loadDoNotScanBelow60s()
      const blockedFolders = BlockedFolderDataSource.loadBlockedFolderPaths()

      this.scanProgress = 10

      // Create log callback that always appends; the dialog re-opening picks
      // up the latest log via the singleton, so we never drop messages.
      const logCallback: ScanLogCallback = (message: string) => {
        this.appendLog(message)
      }

      // Perform the actual scan with cooperative cancel support
      const result = await ScanningDataSource.performScan(
        context,
        false, // allowCache = false for manual scan
        skipBelow60s,
        blockedFolders,
        [],    // empty = use default directories
        logCallback,
        this.waitWhilePaused,
        this.onGrantedUris
      )

      this.scanResult = result
      this.scanProgress = 90

      // Log incremental scan info
      if (result.skippedDuplicate > 0) {
        this.appendLog(`Skipped ${result.skippedDuplicate} duplicates (already in library)`)
      }

      // Last cancel checkpoint before committing to RDB. If user dismissed the
      // dialog right as the metadata loop ended, throw out here and revoke.
      await this.waitWhilePaused()

      // Persist scan results to RDB (also refreshes cache and notifies UI)
      this.appendLog(`Saving ${result.totalAfterFilter} new songs to database...`)
      await ScanningDataSource.persistScanResults(result, context, (message: string) => {
        this.appendLog(message)
      })
      this.scanProgress = 100

      // Revoke permissions for files that were authorized but not written to DB
      // (filtered by duration, blocked folders, or metadata failure). Without
      // this, DocumentViewPicker won't show them on the next scan.
      const persistedUriSet = new Set<string>(
        result.songs.map((s: ScannedSongData): string => s.fileUri))
      const filteredOutUris = this.grantedUris.filter((uri: string): boolean => !persistedUriSet.has(uri))
      if (filteredOutUris.length > 0) {
        this.appendLog(`Revoking permissions for ${filteredOutUris.length} filtered-out files...`)
        try {
          await revokeFilePermissions(filteredOutUris)
        } catch (e) {
          console.warn('[Scan] revokeFilePermissions for filtered-out failed: ' + (e as Error).message)
        }
      }

      // Add the end scan log entry
      this.appendLog('End scan ' + ScanningDataSource.formatDate(new Date()))
      this.forceFlushLog()
      this.scanning = false

      // Scan succeeded — drop the pending-grants record so recovery on next
      // launch does not revoke songs that are now legitimately in the library.
      this.grantedUris = []
      await ScanningDataSource.clearPendingGrants(context)

    } catch (err) {
      if (err instanceof ScanCanceledError) {
        // Cancellation path: revoke any URIs persisted during this scan and
        // reset state so the next dialog open starts cleanly.
        this.appendLog('Scan canceled - reverting authorized songs')
        this.forceFlushLog()
        await this.revokeAndReset(context)
        return
      }
      const errorMessage = (err as Error).message || 'Unknown error'
      this.appendLog(`Scan error: ${errorMessage}`)
      this.forceFlushLog()
      this.scanning = false
    }
  }

  // Revoke all URIs granted by the in-flight scan and reset VM state.
  // Safe to call even when grantedUris is empty (e.g. cancel before picker
  // returned anything).
  private async revokeAndReset(context: Context | null): Promise<void> {
    const toRevoke = this.grantedUris
    this.grantedUris = []
    if (toRevoke.length > 0) {
      try {
        await revokeFilePermissions(toRevoke)
      } catch (e) {
        console.warn('[Scan] revokeFilePermissions failed: ' + (e as Error).message)
      }
    }
    if (context) {
      await ScanningDataSource.clearPendingGrants(context)
    }
    this.scanning = false
    this.scanningLog = ''
    this.scanProgress = 0
    this.scanResult = null
    this.canceled = false
    this.pauseResolver = null
    this.onLogUpdated = null
  }

  // Append a log message with throttling to reduce UI re-renders.
  // Messages are buffered and flushed to the @Track property at most every 200ms.
  private appendLog(message: string): void {
    this.logBuffer.push(message)
    if (!this.logFlushPending) {
      this.logFlushPending = true
      setTimeout(() => {
        this.flushLog()
      }, this.logFlushIntervalMs)
    }
  }

  // Flush buffered log messages to the @Track scanningLog property (single UI update)
  private flushLog(): void {
    this.logFlushPending = false
    if (this.logBuffer.length === 0) {
      return
    }
    // Newest messages at top: reverse the buffer so latest message is first
    const newMessages = this.logBuffer.reverse().join('\n')
    this.logBuffer = []
    if (this.scanningLog.length > 0) {
      this.scanningLog = newMessages + '\n' + this.scanningLog
    } else {
      this.scanningLog = newMessages
    }
    // Cap log to ~50 lines to prevent unbounded string growth
    const lines = this.scanningLog.split('\n')
    if (lines.length > 50) {
      this.scanningLog = lines.slice(0, 50).join('\n')
    }
    this.notifyLogUpdated()
  }

  // Force flush any remaining buffered logs (called when scanning ends)
  private forceFlushLog(): void {
    this.logFlushPending = false
    if (this.logBuffer.length === 0) {
      return
    }
    const newMessages = this.logBuffer.reverse().join('\n')
    this.logBuffer = []
    if (this.scanningLog.length > 0) {
      this.scanningLog = newMessages + '\n' + this.scanningLog
    } else {
      this.scanningLog = newMessages
    }
    this.notifyLogUpdated()
  }

  // Notify the View that log has been updated
  private notifyLogUpdated(): void {
    if (this.onLogUpdated) {
      this.onLogUpdated()
    }
  }

  // Cancel the in-flight scan. Sets the cancel flag, unblocks any pause
  // checkpoint the loop is waiting at, and (synchronously) hides the dialog
  // state. The actual revoke runs in the executeScan catch handler so it
  // happens after the loop has fully exited.
  cancelScanning(): void {
    if (!this.scanning) return
    this.canceled = true
    if (this.pauseResolver) {
      const resolver = this.pauseResolver
      this.pauseResolver = null
      resolver()
    }
    this.onLogUpdated = null
  }

  // Backwards-compatible aliases. Old call sites (the dialog component's
  // aboutToDisappear, EntryAbility's window-stage-destroy hook) keep working
  // without coordinating an edit, and now route to cancel-on-dismiss.
  pauseScanning(): void {
    this.cancelScanning()
  }

  stopScanning(): void {
    this.cancelScanning()
  }

  // Handle the confirm button click
  // Returns true if the dialog should be closed, false if scanning is still in progress
  handleConfirm(): boolean {
    if (this.scanning) {
      // Scanning in progress, do not close
      return false
    }
    // Scan finished — clear any residual state so the next "Start Scan" begins fresh.
    this.onLogUpdated = null
    this.scanningLog = ''
    this.scanProgress = 0
    this.scanResult = null
    this.canceled = false
    this.pauseResolver = null
    return true
  }
}

// 扫描对话框：展示扫描进度并提供取消按钮。
