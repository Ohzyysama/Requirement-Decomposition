// MediaSourceModel.ets
// Model layer: data structures and data operations for media source management
// This layer defines the core data and data access logic.
// It does not interact with UI directly, and only provides data to the ViewModel.

import SettingsStore from './SettingsStore'

// Media source type enumeration
export enum MediaSourceType {
  ANDROID_MEDIA_STORE = 0,
  DOCUMENT_FILE = 1,
  USB_STORAGE = 2
}

// Data model for a user-configured media source (custom folder)
export class UserMediaSourceInfo {
  public id: string = ''
  public type: number = 0 // 0 = ANDROID_MEDIA_STORE, 1 = DOCUMENT_FILE, 2 = USB_STORAGE
  public name: string = ''
  public sub: string = ''

  constructor(id: string = '', type: number = 0, name: string = '', sub: string = '') {
    this.id = id
    this.type = type
    this.name = name
    this.sub = sub
  }
}

// Data access operations for media sources
// Responsible for data persistence, retrieval, and triggering backend operations
export class MediaSourceDataSource {
  // In-memory storage for preferences (replaces mock data)
  private static useAndroidMediaStore: boolean = false
  private static doNotScanBelow60s: boolean = (AppStorage.get<boolean>('doNotScanBelow60s') ?? false)
  private static customFolderList: UserMediaSourceInfo[] = []

  // Load custom folders from persistent storage
  static loadCustomFolders(): UserMediaSourceInfo[] {
    return MediaSourceDataSource.customFolderList.slice()
  }

  // Persist the removal of a custom folder
  static removeCustomFolder(id: string): void {
    MediaSourceDataSource.customFolderList =
      MediaSourceDataSource.customFolderList.filter((f: UserMediaSourceInfo) => f.id !== id)
  }

  // Add a new custom folder
  static addCustomFolder(folder: UserMediaSourceInfo): void {
    MediaSourceDataSource.customFolderList.push(folder)
  }

  // Load user preference: whether to use Android media store
  static loadUseAndroidMediaStore(): boolean {
    return MediaSourceDataSource.useAndroidMediaStore
  }

  // Persist user preference: whether to use Android media store
  static persistUseAndroidMediaStore(value: boolean): void {
    MediaSourceDataSource.useAndroidMediaStore = value
  }

  // Load user preference: whether to skip audio below 60 seconds
  static loadDoNotScanBelow60s(): boolean {
    return MediaSourceDataSource.doNotScanBelow60s
  }

  // Persist user preference: whether to skip audio below 60 seconds
  static persistDoNotScanBelow60s(value: boolean): void {
    MediaSourceDataSource.doNotScanBelow60s = value
    SettingsStore.getInstance().save('doNotScanBelow60s', value)
  }

  // Get the appropriate icon resource based on media source type
  static getMediaSourceIcon(type: number): Resource {
    if (type === MediaSourceType.ANDROID_MEDIA_STORE) {
      return $r('app.media.ic_media_router')
    } else if (type === MediaSourceType.USB_STORAGE) {
      return $r('app.media.ic_usb_storage')
    } else {
      return $r('app.media.ic_ui_folder')
    }
  }

  // Open system external storage permission settings
  static openExternalStoragePermissionSettings(): void {
    console.info('MediaSourceDataSource: open external storage permission settings')
  }
}

// 媒体源配置：在 Android MediaStore / 文档 / USB 之间选择媒体来源。

// 媒体源对齐。
