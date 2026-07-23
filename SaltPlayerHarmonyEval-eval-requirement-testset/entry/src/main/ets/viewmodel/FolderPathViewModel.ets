// FolderPathViewModel.ets
// ViewModel layer: provides data and logic for FolderPathPage (View).
// Bridges the Model layer (SubFolderModel, SongItemModel) with the View layer,
// exposing observable state variables and methods for folder path browsing.

import { SubFolderData } from '../model/SubFolderModel'
import { SongInfoData } from '../model/SongItemModel'
import { SongItemViewModel, SongItemViewModelOptions } from './SongItemViewModel'
import { ScanningDataSource, ScannedSongData } from '../model/ScanningModel'
import SongLazyDataSource from '../model/SongLazyDataSource'
import SubFolderLazyDataSource from '../model/SubFolderLazyDataSource'
import { BlockedFolderDataSource } from '../model/BlockedFolderModel'

// Observable ViewModel for a single subfolder item
@Observed
export class SubFolderViewModel {
  @Track public name: string = ''
  @Track public path: string = ''

  constructor(name: string = '', path: string = '') {
    this.name = name
    this.path = path
  }

  // Load data from Model
  updateFromModel(model: SubFolderData): void {
    this.name = model.name
    this.path = model.path
  }

  // Export current state back to Model data
  toModel(): SubFolderData {
    return {
      name: this.name,
      path: this.path
    }
  }
}

// Page-level ViewModel for FolderPathPage
@Observed
export class FolderPathViewModel {
  // Page title and path (received via navigation params)
  @Track public title: string = ''
  @Track public folderPath: string = ''

  // Subfolder list - corresponds to Android FolderPathViewModel.folders
  @Track public folders: SubFolderViewModel[] = []
  @Track public folderDataSource: SubFolderLazyDataSource = new SubFolderLazyDataSource()

  // Song list - corresponds to Android FolderPathViewModel.songs
  @Track public songList: SongInfoData[] = []
  @Track public songDataSource: SongLazyDataSource = new SongLazyDataSource()

  // Global "show cover in song list" preference, seeded from AppStorage so
  // first render reflects the persisted value. The Page bridges live
  // AppStorage updates into this field via setDisplaySongCoverInList.
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)

  // spec21 — Global "在列表中显示歌曲文件名" preference, seeded from AppStorage
  // so first render reflects the persisted value. The Page bridges live
  // AppStorage updates into this field via setDisplaySongFileNameInList.
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)

  // spec22 — Global "在列表中显示添加下一首播放" preference, seeded from AppStorage
  // so first render reflects the persisted value. The Page bridges live
  // AppStorage updates into this field via setDisplayAddToPlayNextInList.
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // Forward AppStorage 'displaySongCover' writes from the Page-layer bridge.
  // FolderPathPage uses LazyForEach over songDataSource and builds each row
  // via createSongItemViewModel, so flipping this @Track field causes the
  // builder body to re-run and the new showCover value to propagate.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the song list under a folder path re-renders when
  // the user toggles the setting elsewhere.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the song list under a folder path re-renders when
  // the user toggles the setting elsewhere.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

  // Initialize page data based on navigation params
  initializeWithParams(params: Record<string, string>): void {
    if (params) {
      this.folderPath = params['path'] || ''
      this.title = params['title'] || ''
    }
    this.loadData()
  }

  // Load folder data based on current path.
  // Scans the cached song list to find:
  // 1. Direct child songs (fileUri starts with folderPath/ and has no further /)
  // 2. Subfolders (paths with additional segments between folderPath and the song file)
  private loadData(): void {
    if (this.folderPath.length === 0) {
      this.folders = []
      this.songList = []
      return
    }

    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const prefix = this.folderPath + '/'
    const subFolderSet = new Map<string, string>() // path -> name
    const directSongs: SongInfoData[] = []

    for (const s of scanned) {
      const uri = s.fileUri
      if (uri.length === 0 || !uri.startsWith(prefix)) continue

      const remaining = uri.substring(prefix.length)
      const slashIdx = remaining.indexOf('/')

      if (slashIdx < 0) {
        // Direct child song (no more path segments)
        directSongs.push({
          id: s.id,
          title: s.title,
          artist: s.artist,
          album: s.album,
          subTitle: s.artist.length > 0 ? s.artist : s.displayName,
          coverUri: s.coverUri ?? '',
          valid: true,
          quality: s.quality,
          fileUri: s.fileUri,
          duration: s.duration,
          bitrate: s.bitrate,
          sampleRate: s.sampleRate,
          channels: s.channels,
          bits: s.bitsPerSample,
          size: s.size,
          path: s.path,
          albumArtist: s.albumArtist,
          dateAdded: s.dateAdded,
          dateModified: s.dateModified
        })
      } else {
        // Song is in a subfolder - extract the immediate subfolder name
        const subFolderName = remaining.substring(0, slashIdx)
        const subFolderPath = prefix + subFolderName
        if (!subFolderSet.has(subFolderPath)) {
          let decodedName = subFolderName
          try {
            decodedName = decodeURIComponent(subFolderName)
          } catch (e) {
            // Use raw name if decode fails
          }
          subFolderSet.set(subFolderPath, decodedName)
        }
      }
    }

    // Filter out blocked subfolders
    const blockedPaths: string[] = BlockedFolderDataSource.loadBlockedFolderPaths()
    if (blockedPaths.length > 0) {
      subFolderSet.forEach((_name: string, path: string) => {
        for (const blocked of blockedPaths) {
          if (blocked.length > 0 &&
            (path === blocked || path.startsWith(blocked + '/'))) {
            subFolderSet.delete(path)
            break
          }
        }
      })
    }

    // Build subfolder ViewModels sorted by name
    const folderArray: SubFolderViewModel[] = []
    subFolderSet.forEach((name: string, path: string) => {
      folderArray.push(new SubFolderViewModel(name, path))
    })
    folderArray.sort((a: SubFolderViewModel, b: SubFolderViewModel): number => {
      return a.name.localeCompare(b.name)
    })

    this.folders = folderArray
    this.folderDataSource.reload(folderArray)
    this.songList = directSongs
    this.songDataSource.reload(directSongs)
  }

  // Create SongItemViewModel from SongInfoData for display
  createSongItemViewModel(song: SongInfoData, options?: SongItemViewModelOptions): SongItemViewModel {
    return SongItemViewModel.create(song, options)
  }

  // Handle back navigation
  handleBack(navPathStack: NavPathStack): void {
    navPathStack.pop()
  }

  // Handle subfolder navigation.
  // If the target subfolder is a leaf (has direct songs and no further subfolders),
  // navigate to FolderContentPage to show the song list (same as clicking a music
  // folder directly from the main folder tab). Otherwise, continue browsing with
  // FolderPathPage.
  handleSubFolderClick(folder: SubFolderViewModel, navPathStack: NavPathStack): void {
    if (this.isLeafMusicFolder(folder.path)) {
      navPathStack.pushPath({
        name: 'FolderContentPage',
        param: {
          'folderPath': folder.path,
          'folderName': folder.name
        } as Record<string, string>
      })
    } else {
      navPathStack.pushPath({
        name: 'FolderPathPage',
        param: {
          'path': folder.path,
          'title': folder.name
        } as Record<string, string>
      })
    }
  }

  // Determine if a folder is a "leaf" music folder:
  // It contains at least one direct child song and no subdirectories with songs.
  private isLeafMusicFolder(path: string): boolean {
    const scanned: ScannedSongData[] = ScanningDataSource.getScannedSongs()
    const prefix = path + '/'
    let hasDirectSong = false
    let hasSubFolder = false
    for (const s of scanned) {
      const uri = s.fileUri
      if (uri.length === 0 || !uri.startsWith(prefix)) continue
      const remaining = uri.substring(prefix.length)
      if (remaining.indexOf('/') < 0) {
        hasDirectSong = true
      } else {
        hasSubFolder = true
      }
      if (hasSubFolder && hasDirectSong) break
    }
    return hasDirectSong && !hasSubFolder
  }

  // Handle song item click
  handleSongClick(song: SongInfoData): void {
    // TODO: Play this song
    console.info('TODO: play song ' + song.title)
  }

  // Handle song menu click
  handleSongMenuClick(song: SongInfoData): void {
    // TODO: Show song menu
    console.info('TODO: show song menu for ' + song.title)
  }
}

// 文件夹路径：层级导航状态。
