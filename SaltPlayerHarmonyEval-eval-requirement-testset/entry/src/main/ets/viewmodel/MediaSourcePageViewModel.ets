// MediaSourcePageViewModel.ets
// ViewModel layer: provides observable data and business logic for MediaSourcePage
// Bridges the View and Model layers per MVVM architecture.
// The View calls ViewModel methods for all user interactions.
// The ViewModel reads/writes data through the Model layer.

import {
  UserMediaSourceInfo,
  MediaSourceDataSource,
  MediaSourceType
} from '../model/MediaSourceModel'
import SwitcherRowViewModel from './SwitcherRowViewModel'
import SwitcherRowModel from '../model/SwitcherRowModel'
import { common } from '@kit.AbilityKit'

@Observed
export default class MediaSourcePageViewModel {
  // Toggle VMs for switcher rows
  @Track public useAndroidMediaStoreVM: SwitcherRowViewModel = new SwitcherRowViewModel()
  @Track public doNotScanBelow60sVM: SwitcherRowViewModel = new SwitcherRowViewModel()

  // Custom folders list
  @Track public customFolders: UserMediaSourceInfo[] = []

  // Dialog visibility states
  @Track public showScanningDialog: boolean = false
  @Track public showAddCustomFolderDialog: boolean = false
  @Track public showRemoveDialog: boolean = false

  // Target folder for removal confirmation
  @Track public removeTarget: UserMediaSourceInfo | null = null

  // Whether the READ_IMAGEVIDEO permission has been granted
  @Track public permissionGranted: boolean = false

  // Context reference for permission requests
  @Track private context: Context | null = null

  constructor() {
    this.initializeData()
  }

  // Set the context
  setContext(context: Context): void {
    this.context = context
  }

  // Initialize data from Model layer
  private initializeData(): void {
    // Load custom folders from data source
    this.customFolders = MediaSourceDataSource.loadCustomFolders()

    // Initialize "Use Android Media Store" toggle
    const useMediaStoreModel = new SwitcherRowModel(
      MediaSourceDataSource.loadUseAndroidMediaStore(),
      true,
      $r('app.string.use_android_media_store')
    )
    this.useAndroidMediaStoreVM = new SwitcherRowViewModel(useMediaStoreModel, (val: boolean) => {
      MediaSourceDataSource.persistUseAndroidMediaStore(val)
    })

    // Initialize "Do not scan audio below 60 seconds" toggle
    const doNotScanModel = new SwitcherRowModel(
      MediaSourceDataSource.loadDoNotScanBelow60s(),
      true,
      $r('app.string.do_not_scan_audio_below_60_seconds')
    )
    this.doNotScanBelow60sVM = new SwitcherRowViewModel(doNotScanModel, (val: boolean) => {
      MediaSourceDataSource.persistDoNotScanBelow60s(val)
    })
  }

  // Permission check is no longer needed - folder picker grants access
  // Kept as no-op for API compatibility
  async requestPermission(): Promise<boolean> {
    return true
  }

  // Start a music scanning operation
  // Checks permission first, then opens the scanning dialog
  async openScanningDialog(): Promise<void> {
    // Request permission if not granted
    if (!this.permissionGranted) {
      const granted = await this.requestPermission()
      if (!granted) {
        return
      }
    }
    this.showScanningDialog = true
  }

  // Close the scanning dialog
  closeScanningDialog(): void {
    this.showScanningDialog = false
  }

  // Open the "Add Custom Folder" sheet dialog
  openAddCustomFolderDialog(): void {
    this.showAddCustomFolderDialog = true
  }

  // Close the "Add Custom Folder" sheet dialog
  closeAddCustomFolderDialog(): void {
    this.showAddCustomFolderDialog = false
  }

  // Request removal of a custom folder (show confirmation)
  requestRemoveFolder(item: UserMediaSourceInfo): void {
    this.removeTarget = item
    this.showRemoveDialog = true
  }

  // Confirm removal of a custom folder
  confirmRemoveFolder(): void {
    if (this.removeTarget) {
      MediaSourceDataSource.removeCustomFolder(this.removeTarget.id)
      // Remove from local list
      this.customFolders = this.customFolders.filter(
        (f: UserMediaSourceInfo) => f.id !== this.removeTarget!.id
      )
      this.removeTarget = null
      this.showRemoveDialog = false
    }
  }

  // Cancel removal
  cancelRemoveFolder(): void {
    this.removeTarget = null
    this.showRemoveDialog = false
  }

  // Handle native file manager selection callback
  handleNativeFileManagerResult(): void {
    this.showAddCustomFolderDialog = false
  }

  // Handle USB disk selection callback
  handleUsbDiskResult(): void {
    this.showAddCustomFolderDialog = false
  }

  // Open external storage permission settings
  openExternalStorageSettings(): void {
    MediaSourceDataSource.openExternalStoragePermissionSettings()
  }

  // Get the icon resource for a given media source type
  getMediaSourceIcon(type: number): Resource {
    return MediaSourceDataSource.getMediaSourceIcon(type)
  }

  // Check if a media source item is removable (non-ANDROID_MEDIA_STORE types)
  isRemovable(item: UserMediaSourceInfo): boolean {
    return item.type !== MediaSourceType.ANDROID_MEDIA_STORE
  }

  // Get the context
  getContext(): Context | null {
    return this.context
  }
}
