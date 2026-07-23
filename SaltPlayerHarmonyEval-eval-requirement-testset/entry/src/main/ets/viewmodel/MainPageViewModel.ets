// MainPageViewModel.ets
// ViewModel layer: provides observable state and business logic for MainPage (View).
// Bridges the Model layer (MainPageModel) with the View layer.
// The View only reads state and calls methods on this ViewModel.

import {
  SongInfoData,
  createDefaultSongInfoData,
  AlbumInfoData,
  ArtistInfoData,
  MainTabType,
  MainPageDataSource,
  LoadAllResult
} from '../model/MainPageModel'
import { SDCardInfo, FolderInfo } from '../model/FolderModel'
import { SongLazySort } from '../model/SongSortModel'
import { compareStr } from '../utils/SortUtils'
import MiniPlayerViewModel from './MiniPlayerViewModel'
import { ArtistItemViewModel } from './ArtistItemViewModel'
import PlaylistTabViewModel from './PlaylistTabViewModel'
import AlbumListSettingsViewModel from './AlbumListSettingsViewModel'
import { AlbumSortType } from '../model/AlbumListSettingsModel'
import PlaylistModel, { PlaylistDataSource } from '../model/PlaylistModel'
import { NewPlaylistDataSource, PlaylistValidation } from '../model/NewPlaylistModel'
import { ImportPlaylistDataSource } from '../model/ImportPlaylistModel'
import { promptAction } from '@kit.ArkUI'
import { PlaylistContentDataSource } from '../model/PlaylistContentModel'
import { shareSongFile } from '../model/ShareUtil'
import { common } from '@kit.AbilityKit'
import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import AudioPlayerService from '../model/AudioPlayerService'
import ScreenWakeViewModel from './ScreenWakeViewModel'
import SystemBarModel from '../model/SystemBarModel'
import { FlowingLightThemeResolver, FlowingLightMode } from '../model/FlowingLightModel'
import { MusicDatabase, PlaylistSortState } from '../model/MusicDatabase'
import { trackSortColumnToLazySort } from './PlaylistContentViewModel'
import SongLazyDataSource from '../model/SongLazyDataSource'
import AlbumLazyDataSource, { AlbumYearLazyDataSource } from '../model/AlbumLazyDataSource'
import ArtistLazyDataSource from '../model/ArtistLazyDataSource'
import { curves } from '@kit.ArkUI'
import SettingsStore from '../model/SettingsStore'
import { ScanningDataSource, RefreshResult } from '../model/ScanningModel'
import { picker } from '@kit.CoreFileKit'
import { fileIo } from '@kit.CoreFileKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

@Observed
export default class MainPageViewModel {
  // ========== Song Tab Data ==========
  private unsortedSongList: SongInfoData[] = []
  @Track public songList: SongInfoData[] = []
  @Track public songDataSource: SongLazyDataSource = new SongLazyDataSource()
  @Track public currentSongId: string = ''

  // ========== Multi-choice Mode ==========
  @Track public multiChoiceMode: boolean = false
  @Track public checkedMap: Record<string, boolean> = {}
  @Track public checkedCount: number = 0
  // Parallel pick-order list: the FIRST entry is the FIRST-picked id. Used
  // when committing a multi-select add-to-playlist so spec5 S2/S6 hold —
  // the first-picked song must end up on top of the target playlist (i.e.
  // get the largest PlaylistTrack.addedTime). checkedMap remains the source
  // of truth for membership/count; this list tracks order only.
  @Track public checkedOrder: string[] = []

  // ========== Sort State ==========
  @Track public songLazySort: number = (AppStorage.get<number>('songLazySort') ?? SongLazySort.TITLE)
  @Track public showRightABC: boolean = SongLazySort.shouldShowRightABC(AppStorage.get<number>('songLazySort') ?? SongLazySort.TITLE)

  // ========== Alphabet Index Cache (for O(1) scrollToChar) ==========
  private songAlphabetIndexMap: Map<string, number> = new Map()
  private artistAlphabetIndexMap: Map<string, number> = new Map()

  // ========== Tab State ==========
  @Track public currentTab: string = MainTabType.SONG

  // ========== Album Tab Data ==========
  @Track public albumList: AlbumInfoData[] = []
  @Track public albumDataSource: AlbumLazyDataSource = new AlbumLazyDataSource()
  @Track public albumYearDataSource: AlbumYearLazyDataSource = new AlbumYearLazyDataSource()
  @Track public albumSortedMap: Map<string, AlbumInfoData[]> = new Map()
  @Track public showAlbumListSettings: boolean = false

  // ========== Artist Tab Data ==========
  @Track public artistList: ArtistItemViewModel[] = []
  @Track public artistDataSource: ArtistLazyDataSource = new ArtistLazyDataSource()

  // ========== Folder Tab Data ==========
  @Track public sdCards: SDCardInfo[] = []
  @Track public folderList: FolderInfo[] = []

  // ========== Song Display Settings ==========
  // displaySongCoverInList is seeded from the persisted AppStorage key so the
  // very first frame after construction reflects the user's choice. Pages
  // bridge live AppStorage updates into this field via setDisplaySongCoverInList.
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)
  // spec21 — seeded from the persisted AppStorage key so the very first frame
  // after construction reflects the user's choice. The MainPage @StorageProp
  // bridge forwards live updates through setDisplaySongFileNameInList.
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // ========== Playlist Tab ==========
  @Track public showPlaylistPopupMenu: boolean = false
  @Track public showNewPlaylistDialog: boolean = false
  @Track public newPlaylistName: string = ''

  // ========== Refresh State ==========
  @Track public isRefreshing: boolean = false

  // ========== Data Loading State ==========
  // true until the first database load (or scanVersion update) completes,
  // so the UI can show a loading indicator instead of the "scan music" empty state.
  @Track public isDataLoading: boolean = true

  // ========== Sort Dialog ==========
  @Track public showSortDialog: boolean = false

  // ========== Drawer State ==========
  @Track public isDrawerOpen: boolean = false
  @Track public drawerOffset: number = 0

  // ========== Player Overlay State ==========
  @Track public showPlayer: boolean = false
  @Track public initialShowQueue: boolean = false
  @Track public playerSwipeOffset: number = 0
  @Track public isPlayerSwiping: boolean = false

  // ========== Gesture State (Apple Music style) ==========
  // Negative vp when user is pulling the mini player pill upward; 0 otherwise.
  // Drives the pill's translate(y) during drag for rubber-band feedback.
  @Track public miniPullOffsetY: number = 0

  // ========== Morph Container Geometry ==========
  // Screen dims in vp, measured from MainPage's root via onAreaChange.
  // Both drive the pill→fullscreen interpolation in MainPage.
  @Track public mainScreenWidth: number = 0

  // Snapshot of playerProgress at pan-start; pan-update adds delta so the
  // finger follows 1:1 in vp space regardless of where the gesture started.
  private morphPullStartProgress: number = 0
  // When the morph pull starts on the queue page (inside the fully-open
  // player), the inner pager owns the gesture — swipe-down must return to
  // the player page, not close the overlay. We suppress this pull until the
  // next start by flagging it here.
  private morphPullSuppressed: boolean = false

  // ========== Song Menu Dialog ==========
  @Track public showSongSheet: boolean = false  // Controls whether sheet is visible
  @Track public showSongMenu: boolean = false   // Show menu or info inside sheet
  @Track public showSongInfo: boolean = false
  // Pending navigation to execute after sheet fully dismisses
  @Track public songMenuTarget: SongInfoData = createDefaultSongInfoData()

  // ========== Sub ViewModels ==========
  @Track public miniPlayerVM: MiniPlayerViewModel = new MiniPlayerViewModel()
  @Track public albumListSettingsVM: AlbumListSettingsViewModel = new AlbumListSettingsViewModel(
    (AppStorage.get<number>('albumSortType') ?? AlbumSortType.TITLE),
    (AppStorage.get<number>('albumMinColumns') ?? 2)
  )
  @Track public playlistTabViewModel: PlaylistTabViewModel = new PlaylistTabViewModel()

  // ========== Constants ==========
  @Track public readonly sidebarWidthVp: number = 200

  // ========== Private Touch Gesture State (non-observable) ==========
  @Track public mainScreenHeight: number = 0
  @Track private touchStartX: number = 0
  @Track private touchStartY: number = 0
  @Track private drawerOffsetAtTouchStart: number = 0
  @Track private isHorizontalDrag: boolean = false
  @Track private isDirectionLocked: boolean = false
  // Blocks all onClick that fires AFTER a drawer-swipe TouchType.Up.
  // When a horizontal drawer drag is detected, this flag is set to true so that
  // the subsequent onClick on song / artist / album / folder items (or sidebar
  // menu items) is suppressed.  Reset on the next TouchType.Down, not on Up,
  // because onClick fires after Up.
  @Track public blockClickAfterSwipe: boolean = false
  @Track private playerTouchStartY: number = 0
  @Track private playerTouchStartX: number = 0
  @Track private playerSwipeDirectionLocked: boolean = false
  @Track private miniPlayerHorizontalSwipe: boolean = false

  // ========== Initialization ==========
  // Lightweight init: only restores UI state and sets up callbacks.
  // Does NOT load song/album/artist data — that is done by refreshSongList()
  // which is triggered by scanVersion change or called from aboutToAppear when cache is ready.
  initialize(): void {
    // Restore current song id from persisted AppStorage
    const persistedSongId = AppStorage.get('currentSongId') as string
    if (persistedSongId && persistedSongId.length > 0) {
      this.currentSongId = persistedSongId
    }

    // Initialize PlaylistTabViewModel
    this.playlistTabViewModel.loadPlaylists(MainPageDataSource.loadDefaultPlaylists())
    // Populate playlist tab from the DB on startup so rows created in prior
    // sessions show up immediately (fire-and-forget — the list updates
    // reactively once the async load resolves).
    this.reloadPlaylists()
    this.playlistTabViewModel.onPlaylistClickAction = (_playlistId: string) => {
    }
    this.playlistTabViewModel.onNewPlaylistAction = (name: string) => {
      this.addPlaylist(name)
    }
    this.playlistTabViewModel.onImportPlaylistAction = () => {
      console.info('TODO: importPlaylist - business logic not yet implemented')
    }
    this.playlistTabViewModel.onUpdatePlaylistNameAction = (playlistId: string, newName: string) => {
      this.renamePlaylist(playlistId, newName)
    }
    this.playlistTabViewModel.onDeletePlaylistAction = (playlistId: string) => {
      this.deletePlaylist(playlistId)
    }
    this.playlistTabViewModel.onExportPlaylistAction = (playlistId: string) => {
      console.info(`TODO: exportPlaylist id:${playlistId} - business logic not yet implemented`)
    }
  }

  // Refresh all data after scanning completes or on initial load.
  // Uses single-pass loadAll() to avoid iterating the song list 5 times.
  refreshSongList(): void {
    const data: LoadAllResult = MainPageDataSource.loadAll()

    // Reorder freshly-loaded songs to match the user's persisted drag order
    // (custom sort). Without this, app restart resets unsortedSongList to DB
    // order and the user's drag-reorder is lost — even when songLazySort
    // restores to NONE, songList = unsortedSongList = DB order, not the order
    // the user dragged into place.
    this.unsortedSongList = this.applyCustomSongOrder(data.songs)
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
    this.rebuildSongAlphabetIndex()
    this.albumList = data.albums
    this.sortAndGroupAlbums()

    // Update existing ArtistItemViewModel objects in-place so that ForEach-reused
    // components (bound via @ObjectLink) see the @Track property changes.
    // Creating new VMs would leave stale @ObjectLink references until tab switch.
    const freshMap = new Map<string, ArtistInfoData>()
    for (const a of data.artists) {
      freshMap.set(a.id, a)
    }
    // Update existing VMs and collect survivors
    const updatedList: ArtistItemViewModel[] = []
    for (const existing of this.artistList) {
      const fresh = freshMap.get(existing.id)
      if (fresh) {
        existing.count = fresh.count
        existing.songCountText = `${fresh.count} 首`
        existing.coverUri = fresh.coverUri
        existing.hasCoverUri = fresh.coverUri.length > 0
        existing.coverSongId = fresh.coverSongId ?? ''
        freshMap.delete(existing.id)
        updatedList.push(existing)
      }
    }
    // Add newly appeared artists
    freshMap.forEach((a: ArtistInfoData) => {
      updatedList.push(ArtistItemViewModel.fromPlainObject(a))
    })
    const artistCache = new Map<string, string>()
    updatedList.sort((a: ArtistItemViewModel, b: ArtistItemViewModel): number => {
      return compareStr(a.name, b.name, artistCache)
    })
    this.artistList = updatedList
    this.artistDataSource.reload(updatedList)
    this.rebuildArtistAlphabetIndex()

    this.sdCards = data.sdCards
    this.folderList = data.folders
    // Database load completed — allow empty state to show "scan music" if truly empty
    this.isDataLoading = false
  }

  // Refresh only folder-related data (e.g., after hiding a folder)
  refreshFolderList(): void {
    this.sdCards = MainPageDataSource.loadDefaultSDCards()
    this.folderList = MainPageDataSource.loadDefaultFolders()
  }

  // Initialize MiniPlayerViewModel with callbacks
  initMiniPlayer(
    currentSongTitle: string,
    currentSongArtist: string,
    isPlaying: boolean,
    onPlayPause: () => void,
    onQueueClick: () => void,
    onMiniPlayerClick: () => void,
    onTouchEvent: (event: TouchEvent) => void
  ): void {
    this.miniPlayerVM.currentSongTitle = currentSongTitle
    this.miniPlayerVM.currentSongArtist = currentSongArtist
    this.miniPlayerVM.isPlaying = isPlaying
    this.miniPlayerVM.onPlayPauseClick = onPlayPause
    this.miniPlayerVM.onQueueClick = onQueueClick
    this.miniPlayerVM.onMiniPlayerClick = onMiniPlayerClick
    this.miniPlayerVM.onTouchEvent = onTouchEvent
    // Subscribe to the central cover controller here (not in constructor),
    // because `this.miniPlayerVM` is now the proxied @Observed object —
    // the arrow function captures the proxy `this`, making @Track work.
    this.miniPlayerVM.subscribeToController()
    // Same pattern for lyrics — proxy `this` must be captured to trigger
    // @Track rerender on currentLyricLine / hasLyrics updates.
    this.miniPlayerVM.subscribeToLyricsController()
  }

  // Sync StorageLink data to MiniPlayerViewModel
  syncMiniPlayerData(title: string, artist: string, isPlaying: boolean,
    songId?: string, coverUri?: string): void {
    this.miniPlayerVM.currentSongTitle = title
    this.miniPlayerVM.currentSongArtist = artist
    this.miniPlayerVM.isPlaying = isPlaying
    if (songId !== undefined) {
      this.currentSongId = songId
      if (coverUri !== undefined) {
        this.miniPlayerVM.updateCover(songId, coverUri)
      }
    }
  }

  // ========== Tab Navigation ==========
  switchTab(tab: string): void {
    this.currentTab = tab
  }

  // Get the title resource based on current tab
  getTitleResource(): Resource {
    switch (this.currentTab) {
      case MainTabType.ALBUM:
        return $r('app.string.albums')
      case MainTabType.ARTIST:
        return $r('app.string.artists')
      case MainTabType.FOLDER:
        return $r('app.string.folders')
      case MainTabType.PLAYLIST:
        return $r('app.string.playlists')
      case MainTabType.SONG:
      default:
        return $r('app.string.songs')
    }
  }

  // ========== Song Operations ==========
  playSong(songId: string, title: string, artist: string, fileUri?: string): void {
    this.currentSongId = songId
    // Build queue from current song list
    const queue: QueueSongModel[] = this.songList.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === songId)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  randomPlay(): void {
    if (this.songList.length === 0) {
      return
    }
    // Build queue from current song list (same order)
    const queue: QueueSongModel[] = this.songList.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    // Pick a random start index
    const randomIndex = Math.floor(Math.random() * this.songList.length)
    const picked = this.songList[randomIndex]
    this.currentSongId = picked.id
    // Set queue starting from the random index, and switch to random play mode
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(PlayModeConstants.RANDOM)
    service.setQueue(queue, randomIndex)
  }

  // ========== Sort Operations ==========
  changeSongSort(sort: number): void {
    this.songLazySort = sort
    this.showRightABC = SongLazySort.shouldShowRightABC(sort)
    SettingsStore.getInstance().save('songLazySort', sort)
    if (sort === SongLazySort.NONE) {
      // Custom sort: restore the persisted custom order from unsortedSongList
      // (which moveSong keeps in sync with each drag-reorder). Without this,
      // switching from custom → another sort → back to custom would leave the
      // list in the previous sort's order instead of the user's drag order.
      this.songList = this.unsortedSongList.slice()
      this.songDataSource.reload(this.songList)
      this.rebuildSongAlphabetIndex()
      return
    }
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, sort)
    this.songDataSource.reload(this.songList)
    this.rebuildSongAlphabetIndex()
  }

  // Move a song from one index to another in the list (used for custom sort drag reorder)
  moveSong(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 ||
      fromIndex >= this.songList.length || toIndex >= this.songList.length) {
      return
    }
    this.songDataSource.move(fromIndex, toIndex)
    this.songList = this.songDataSource.getAll()
    this.unsortedSongList = this.songList.slice()
    this.rebuildSongAlphabetIndex()
    // Persist the new custom order so it survives app restart. Without this,
    // refreshSongList() on next boot reloads songs in DB order and the user's
    // drag-reorder is silently lost.
    this.saveCustomSongOrder()
  }

  // Persist the current unsortedSongList order as a JSON-stringified id array
  // under settings key 'customSongOrder'. Called from every drag-reorder so
  // the order survives app restart.
  private saveCustomSongOrder(): void {
    const ids: string[] = this.unsortedSongList.map((s: SongInfoData): string => s.id)
    SettingsStore.getInstance().save('customSongOrder', JSON.stringify(ids))
  }

  // Reorder freshly-loaded songs by the persisted custom drag order.
  // - Songs whose id is present in the saved order come first, in saved-order
  //   sequence (stable wrt duplicates).
  // - Songs not in the saved order (newly scanned tracks since the last drag)
  //   are appended in DB order at the end.
  // Returns the input unchanged when no saved order exists or it fails to
  // parse, so first-launch behavior is unaffected.
  private applyCustomSongOrder(songs: SongInfoData[]): SongInfoData[] {
    if (songs.length === 0) return songs
    const raw = SettingsStore.getInstance().get('customSongOrder', '') as string
    if (!raw || raw.length === 0) return songs
    let savedIds: string[]
    try {
      const parsed = JSON.parse(raw) as Object
      if (!Array.isArray(parsed)) return songs
      savedIds = parsed as string[]
    } catch (_e) {
      return songs
    }
    if (savedIds.length === 0) return songs

    const idToSong = new Map<string, SongInfoData>()
    for (const s of songs) {
      idToSong.set(s.id, s)
    }
    const result: SongInfoData[] = []
    const placed = new Set<string>()
    for (const id of savedIds) {
      const song = idToSong.get(id)
      if (song && !placed.has(id)) {
        result.push(song)
        placed.add(id)
      }
    }
    // Append any newly-scanned songs (not in saved order) at the end, in DB order.
    for (const s of songs) {
      if (!placed.has(s.id)) {
        result.push(s)
      }
    }
    return result
  }

  // Sort and group albums based on current albumListSettingsVM.albumSortType
  sortAndGroupAlbums(): void {
    const sortType = this.albumListSettingsVM.albumSortType
    const albums = [...this.albumList]

    if (sortType === AlbumSortType.YEAR) {
      // Sort by year descending, then group by year
      albums.sort((a: AlbumInfoData, b: AlbumInfoData): number => b.year - a.year)
      const map = new Map<string, AlbumInfoData[]>()
      for (const album of albums) {
        const key = album.year > 0 ? album.year.toString() : '0'
        const group = map.get(key)
        if (group) {
          group.push(album)
        } else {
          map.set(key, [album])
        }
      }
      this.albumSortedMap = map
    } else if (sortType === AlbumSortType.COUNT) {
      // Sort by count descending, single group
      albums.sort((a: AlbumInfoData, b: AlbumInfoData): number => b.count - a.count)
      const map = new Map<string, AlbumInfoData[]>()
      map.set('', albums)
      this.albumSortedMap = map
    } else {
      // TITLE: sort by title, single group (use compareStr for consistency with song title sorting)
      const cache = new Map<string, string>()
      albums.sort((a: AlbumInfoData, b: AlbumInfoData): number => {
        return compareStr(a.title, b.title, cache)
      })
      const map = new Map<string, AlbumInfoData[]>()
      map.set('', albums)
      this.albumSortedMap = map
    }

    // Also update the flat albumList to match sorted order
    const sorted: AlbumInfoData[] = []
    this.albumSortedMap.forEach((group: AlbumInfoData[]) => {
      for (const album of group) {
        sorted.push(album)
      }
    })
    this.albumList = sorted
    this.albumDataSource.reload(sorted)
    this.albumYearDataSource.reloadFromMap(this.albumSortedMap)
  }

  changeDisplaySetting(key: string, value: boolean): void {
    if (key === 'displaySongCoverInList') {
      this.displaySongCoverInList = value
    } else if (key === 'displaySongFileNameInList') {
      this.displaySongFileNameInList = value
    } else if (key === 'displayAddToPlayNextInList') {
      this.displayAddToPlayNextInList = value
    }
  }

  // Forward AppStorage 'displaySongCover' writes from the Page-layer bridge
  // (@StorageProp('displaySongCover') @Watch(handler) -> handler calls this).
  // Mounted song-list pages re-render via @Track when this field flips.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge (MainPage @StorageProp('displaySongFileName') -> watch ->
  // this setter). The Song-tab LazyForEach rebuilds each SongItemViewModel on
  // every render with options.displayFileName = this.displaySongFileNameInList,
  // so flipping this @Track field is sufficient to re-render the list.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge into this VM. The Song-tab LazyForEach rebuilds each
  // SongItemViewModel on every render with options.displayAddToPlayNext =
  // this.displayAddToPlayNextInList, so flipping this @Track field is
  // sufficient to re-render the list.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

  // ========== Multi-choice Operations ==========
  // Throttle guard: prevents rapid enter/exit toggling from queuing overlapping
  // render cycles (each toggle re-creates SongItemViewModel for all visible items).
  private multiChoiceToggleTime: number = 0
  private static readonly MULTI_CHOICE_THROTTLE_MS: number = 300

  enterMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < MainPageViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = true
  }

  exitMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < MainPageViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = false
    this.checkedMap = {}
    this.checkedCount = 0
    this.checkedOrder = []
  }

  toggleSelectAll(): void {
    if (this.checkedCount === this.songList.length) {
      this.checkedMap = {}
      this.checkedOrder = []
    } else {
      const newMap: Record<string, boolean> = {}
      const newOrder: string[] = []
      this.songList.forEach((song: SongInfoData) => {
        newMap[song.id] = true
        newOrder.push(song.id)
      })
      this.checkedMap = newMap
      this.checkedOrder = newOrder
    }
    this.updateCheckedCount()
  }

  updateSongChecked(songId: string, checked: boolean): void {
    const newMap: Record<string, boolean> = {}
    const keys = Object.keys(this.checkedMap)
    for (const key of keys) {
      newMap[key] = this.checkedMap[key]
    }
    newMap[songId] = checked
    this.checkedMap = newMap
    // Keep checkedOrder in sync with the membership change.
    if (checked) {
      if (this.checkedOrder.indexOf(songId) < 0) {
        this.checkedOrder = this.checkedOrder.concat([songId])
      }
    } else {
      this.checkedOrder = this.checkedOrder.filter((id: string) => id !== songId)
    }
    this.updateCheckedCount()
  }

  // Return the pick-order snapshot for the current multi-select. Only ids
  // still present in checkedMap are emitted, so stale entries from earlier
  // toggles are skipped.
  getSelectedSongIdsInOrder(): string[] {
    return this.checkedOrder.filter((id: string) => this.checkedMap[id] === true).slice()
  }

  private updateCheckedCount(): void {
    let count = 0
    const keys = Object.keys(this.checkedMap)
    for (const key of keys) {
      if (this.checkedMap[key]) {
        count++
      }
    }
    this.checkedCount = count
  }

  async removeSelectedFromLibrary(): Promise<void> {
    const checkedIds = Object.keys(this.checkedMap).filter((key: string) => this.checkedMap[key])
    if (checkedIds.length === 0) return
    // Build an id→song map ONCE, then look up each checked id in O(1).
    // The previous for/find loop was O(N²) — for a 2000-song multi-select on
    // a 2000-song library it ran ~4M comparisons synchronously inside the
    // click handler, which dominated the post-confirm stall.
    const idToSong = new Map<string, SongInfoData>()
    for (const s of this.unsortedSongList) {
      idToSong.set(s.id, s)
    }
    const paths: string[] = []
    const fileUris: string[] = []
    for (const id of checkedIds) {
      const song = idToSong.get(id)
      if (!song) continue
      if (song.path && song.path.length > 0) paths.push(song.path)
      if (song.fileUri && song.fileUri.length > 0) fileUris.push(song.fileUri)
    }
    await MusicDatabase.deleteTracksByPaths(paths)
    const checkedSet = new Set(checkedIds)
    this.unsortedSongList = this.unsortedSongList.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
    this.rebuildSongAlphabetIndex()
    this.exitMultiChoiceMode()
    await MusicDatabase.handleSongsRemovedFromLibrary(checkedIds, fileUris)
  }

  removeSongFromListById(songId: string): void {
    this.unsortedSongList = this.unsortedSongList.filter((s: SongInfoData) => s.id !== songId)
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
    this.rebuildSongAlphabetIndex()
  }

  addSelectedToPlaylist(): void {
    console.info('TODO: add to playlist - not yet implemented')
  }

  playSelectedQueue(): void {
    // Build queue from checked songs, preserving songList order
    const selected = this.songList.filter((song: SongInfoData) => this.checkedMap[song.id] === true)
    if (selected.length === 0) {
      return
    }
    const queue: QueueSongModel[] = selected.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const first = selected[0]
    this.currentSongId = first.id
    AudioPlayerService.getInstance().setQueue(queue, 0)
    this.exitMultiChoiceMode()
  }

  // ========== Song Menu Operations ==========
  openSongMenu(song: SongInfoData): void {
    this.songMenuTarget = song
    this.showSongMenu = true
    this.showSongInfo = false
    this.showSongSheet = true
  }

  /**
   * Open song menu by song ID — looks up the full SongInfoData from songList.
   * Used by PlayerPage where only the current song ID is known.
   */
  openSongMenuById(songId: string): void {
    const song = this.songList.find((s: SongInfoData) => s.id === songId)
    if (song) {
      this.openSongMenu(song)
    }
  }

  closeSongMenu(): void {
    this.showSongMenu = false
    this.showSongSheet = false
  }

  openSongInfo(): void {
    this.showSongMenu = false
    this.showSongInfo = true
    this.showSongSheet = true
  }

  closeSongInfo(): void {
    this.showSongInfo = false
    this.showSongSheet = false
  }

  shareSong(context: common.UIAbilityContext): void {
    shareSongFile(context, this.songMenuTarget.title, this.songMenuTarget.fileUri)
  }

  // ========== Drawer Operations ==========
  handleDrawerTouch(event: TouchEvent, animateTo: (params: AnimateParam, callback: () => void) => void): void {
    if (this.multiChoiceMode) {
      return
    }
    const touch = event.touches[0]
    if (!touch) {
      return
    }
    switch (event.type) {
      case TouchType.Down:
        this.touchStartX = touch.x
        this.touchStartY = touch.y
        this.drawerOffsetAtTouchStart = this.drawerOffset
        this.isHorizontalDrag = false
        this.isDirectionLocked = false
        this.blockClickAfterSwipe = false
        break

      case TouchType.Move:
        if (!this.isDirectionLocked) {
          const dx = Math.abs(touch.x - this.touchStartX)
          const dy = Math.abs(touch.y - this.touchStartY)
          if (dx > 10 || dy > 10) {
            this.isDirectionLocked = true
            this.isHorizontalDrag = dx > dy
            if (this.isHorizontalDrag) {
              this.blockClickAfterSwipe = true
              this.touchStartX = touch.x
              this.drawerOffsetAtTouchStart = this.drawerOffset
            }
          }
        }
        if (this.isHorizontalDrag) {
          const offsetX = touch.x - this.touchStartX
          let newOffset = this.drawerOffsetAtTouchStart + offsetX
          if (newOffset < 0) {
            newOffset = 0
          }
          if (newOffset > this.sidebarWidthVp) {
            newOffset = this.sidebarWidthVp
          }
          this.drawerOffset = newOffset
        }
        break

      case TouchType.Up:
      case TouchType.Cancel:
        if (this.isHorizontalDrag) {
          if (this.drawerOffset > this.sidebarWidthVp * 0.5) {
            this.openDrawer(animateTo)
          } else {
            this.closeDrawer(animateTo)
          }
        }
        this.isHorizontalDrag = false
        this.isDirectionLocked = false
        break
    }
  }

  openDrawer(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.drawerOffset = this.sidebarWidthVp
      this.isDrawerOpen = true
    })
  }

  closeDrawer(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.drawerOffset = 0
      this.isDrawerOpen = false
    })
  }

  toggleDrawer(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    if (this.isDrawerOpen) {
      this.closeDrawer(animateTo)
    } else {
      this.openDrawer(animateTo)
    }
  }

  // ========== Mini Player Touch — Horizontal prev/next + Tap-to-open ==========
  // Vertical drag is handled separately by PanGesture (see handleMiniPullUpdate
  // / handleMiniPullEnd below). This touch handler only covers horizontal swipe
  // and taps, so it doesn't fight the PanGesture for vertical motion.
  handleMiniPlayerTouch(
    event: TouchEvent,
    animateTo: (params: AnimateParam, callback: () => void) => void
  ): void {
    switch (event.type) {
      case TouchType.Down: {
        const touch = event.touches[0]
        if (!touch) {
          return
        }
        this.playerTouchStartY = touch.y
        this.playerTouchStartX = touch.x
        this.playerSwipeDirectionLocked = false
        this.miniPlayerHorizontalSwipe = false
        break
      }

      case TouchType.Move: {
        const touch = event.touches[0]
        if (!touch) {
          return
        }
        const deltaY = this.playerTouchStartY - touch.y
        const deltaX = touch.x - this.playerTouchStartX
        const absDx = Math.abs(deltaX)
        const absDy = Math.abs(deltaY)
        if (!this.playerSwipeDirectionLocked) {
          if (absDx > 10 && absDx > absDy) {
            // Horizontal: prev/next swipe — handled here.
            this.playerSwipeDirectionLocked = true
            this.miniPlayerHorizontalSwipe = true
            this.playerTouchStartX = touch.x
          } else if (absDy > 5 && absDy > absDx) {
            // Vertical: PanGesture owns this. Lock to suppress tap-open on release.
            this.playerSwipeDirectionLocked = true
            this.miniPlayerHorizontalSwipe = false
          }
        }
        if (this.miniPlayerHorizontalSwipe) {
          this.miniPlayerVM.swipeOffsetX = touch.x - this.playerTouchStartX
        }
        break
      }

      case TouchType.Up:
      case TouchType.Cancel: {
        if (this.miniPlayerHorizontalSwipe) {
          const swipeThreshold = 80
          if (this.miniPlayerVM.swipeOffsetX > swipeThreshold) {
            this.triggerMiniPlayerSwipe(true, animateTo)
          } else if (this.miniPlayerVM.swipeOffsetX < -swipeThreshold) {
            this.triggerMiniPlayerSwipe(false, animateTo)
          } else {
            animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
              this.miniPlayerVM.swipeOffsetX = 0
            })
          }
          this.miniPlayerHorizontalSwipe = false
        } else if (!this.playerSwipeDirectionLocked && event.type === TouchType.Up) {
          // Pure tap on mini player → open with spring.
          this.openPlayerAnimated(animateTo)
        } else if (this.playerSwipeDirectionLocked && !this.miniPlayerHorizontalSwipe && event.type === TouchType.Up) {
          // Direction was locked to vertical but movement was too small to be a real swipe.
          // Treat as a tap so the player still opens on a light tap.
          // Use changedTouches if available (Up phase often has empty touches array).
          const upTouch = event.changedTouches[0] ?? event.touches[0]
          if (upTouch) {
            const totalDy = Math.abs(this.playerTouchStartY - upTouch.y)
            const totalDx = Math.abs(this.playerTouchStartX - upTouch.x)
            if (totalDy < 12 && totalDx < 12) {
              this.openPlayerAnimated(animateTo)
            }
          }
        }
        this.playerSwipeDirectionLocked = false
        break
      }
    }
  }

  // ========== Mini Player Vertical Pan (pull-up to open, Apple-Music style) ==========
  // Rubber-band damping: diminishing returns past threshold so the pill resists
  // infinite drag but still follows the finger obviously.
  private rubberBand(raw: number, threshold: number): number {
    const abs = Math.abs(raw)
    if (abs <= threshold) {
      return raw
    }
    const excess = abs - threshold
    const damped = threshold + excess * 0.35
    return raw < 0 ? -damped : damped
  }

  // Called from MiniPlayer PanGesture.onActionUpdate (vertical axis).
  // Only responds to upward drag (negative offsetY); downward is ignored so
  // the pill doesn't sink below its resting position.
  handleMiniPullUpdate(offsetY: number): void {
    const upward = offsetY < 0 ? offsetY : 0
    this.miniPullOffsetY = this.rubberBand(upward, 60)
  }

  // Called from MiniPlayer PanGesture.onActionEnd. Flick up (fast velocity) or
  // drag past the decision threshold → open with a velocity-seeded spring.
  // Otherwise snap the pill back to rest.
  handleMiniPullEnd(
    offsetY: number,
    velocityY: number,
    animateTo: (params: AnimateParam, callback: () => void) => void
  ): void {
    const upOffset = offsetY < 0 ? -offsetY : 0
    // velocityY is vp/s; upward drag = negative, flip for readability
    const upVelocity = -velocityY
    const shouldOpen = upVelocity > 400 || upOffset > 40
    if (shouldOpen) {
      // Normalize to progress velocity (0..1 space). Full-open equivalent
      // "distance" is ~200vp of pull, so dividing velocity by 200 gives
      // progress-velocity roughly in units/second.
      const springVel = Math.min(Math.max(upVelocity / 200, 0), 10)
      this.openPlayerWithVelocity(springVel, animateTo)
    } else {
      animateTo({ curve: curves.springMotion(0.4, 0.95) }, () => {
        this.miniPullOffsetY = 0
      })
    }
  }

  // Animate song info out, switch song, then animate back in
  private triggerMiniPlayerSwipe(
    isPrevious: boolean,
    animateTo: (params: AnimateParam, callback: () => void) => void
  ): void {
    const slideDistance = 250
    const slideOut = isPrevious ? slideDistance : -slideDistance
    animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
      this.miniPlayerVM.swipeOffsetX = slideOut
    })
    setTimeout(() => {
      const service = AudioPlayerService.getInstance()
      if (isPrevious) {
        service.skipPrevious()
      } else {
        service.skipNext()
      }
      // Update AppStorage so mini player UI refreshes even when PlayerPage hasn't been opened
      // (onSongChanged callback is only registered by PlayerPageViewModel)
      const queue = service.getQueue()
      const idx = service.getCurrentIndex()
      if (idx >= 0 && idx < queue.length) {
        const song = queue[idx]
        // Song metadata is now pushed to AppStorage by AudioPlayerService.notifySongChanged
      }
      this.miniPlayerVM.swipeOffsetX = -slideOut
      animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.miniPlayerVM.swipeOffsetX = 0
      })
    }, 160)
  }

  // ========== Player Operations ==========

  // Resolve the player's effective light/dark theme and update status bar content color.
  private applyPlayerStatusBarColor(): void {
    const flowingLightMode: number =
      (AppStorage.get('flowingLightMode') as number) ?? FlowingLightMode.FOLLOW_UI
    const isSystemDark: boolean = (AppStorage.get('isSystemDark') as boolean) ?? false
    const isLightFlowing: boolean = FlowingLightThemeResolver.resolve(flowingLightMode, isSystemDark)
    SystemBarModel.getInstance().setStatusBarContentColor(isLightFlowing)
  }

  // ========== Player Expand Progress (Android BottomSheet-style transition) ==========
  // Driven progress field: 0 = mini player, 1 = player fully expanded.
  // Updated directly inside animateTo (and by swipe gesture) so ArkUI tracks
  // it as a direct dependency of the build method. Computed-from-method
  // approaches don't reliably establish reactivity through indirection.
  @Track public playerProgress: number = 0

  // Player page opacity — Android formula: (-16 * offset + 16).coerceAtMost(1)
  // where offset = 1 - progress. Steep fade only in the last ~6% of the range,
  // so the player page is mostly opaque while animating and fades quickly at the end.
  getPlayerPageAlpha(): number {
    const offset = 1 - this.playerProgress
    const v = -16 * offset + 16
    return v < 0 ? 0 : (v > 1 ? 1 : v)
  }

  // Mini player opacity — Android formula: (16 * offset - 15).coerceAtLeast(0)
  // Inverse steep fade: mini player is fully visible except in the last ~6% near
  // fully-expanded state, where it quickly fades out.
  getMiniPlayerAlpha(): number {
    const offset = 1 - this.playerProgress
    const v = 16 * offset - 15
    return v < 0 ? 0 : (v > 1 ? 1 : v)
  }

  // Mini player Y translate — steps up -128vp once progress crosses 0.5 so the
  // bar "floats up" off-screen as the player takes over. Matches Android step.
  getMiniPlayerTranslateY(): number {
    return this.playerProgress > 0.5 ? -128 : 0
  }

  closePlayer(): void {
    this.showPlayer = false
    AppStorage.setOrCreate('showPlayerOverlay', false)
    this.initialShowQueue = false
    this.isPlayerSwiping = false
    this.playerSwipeOffset = 0
    this.playerProgress = 0
    // Reset player page tracking so next open starts on player (not queue)
    AppStorage.setOrCreate('playerCurrentPage', 0)
    // Notify screen wake controller that player is no longer visible
    ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(false)
    // Restore status bar content color to match app theme
    SystemBarModel.getInstance().restoreToAppTheme()
  }

  // Animated close — uses a velocity-0 interpolating spring for a tight,
  // iOS-feeling release. 328=stiffness, 36=damping match system defaults.
  closePlayerAnimated(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    this.animGeneration++
    const myGen = this.animGeneration

    // Reset player page tracking so next open starts on player (not queue)
    AppStorage.setOrCreate('playerCurrentPage', 0)
    AppStorage.setOrCreate('showPlayerOverlay', false)
    // Notify PlayerPage to reset its dismissOffset so the close animation
    // is driven only by the morph container, avoiding visual conflict.
    AppStorage.setOrCreate('playerDismissReset', Date.now())

    // Transition from current progress to closed. Keep playerProgress at its
    // current value so the spring animation starts from wherever the user
    // released, rather than jumping back to fully-open first.
    this.showPlayer = false
    this.isPlayerSwiping = true
    this.playerSwipeOffset = this.mainScreenHeight

    animateTo({
      curve: curves.interpolatingSpring(0, 1, 328, 36),
      onFinish: () => {
        if (myGen !== this.animGeneration) return
        this.isPlayerSwiping = false
        this.playerSwipeOffset = 0
        this.playerProgress = 0
        this.initialShowQueue = false
        ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(false)
        SystemBarModel.getInstance().restoreToAppTheme()
      }
    }, () => {
      if (myGen !== this.animGeneration) return
      this.playerSwipeOffset = 0
      this.playerProgress = 0
    })
  }

  openPlayerWithQueue(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    this.animGeneration++
    const myGen = this.animGeneration

    this.initialShowQueue = true
    this.isPlayerSwiping = true
    this.playerSwipeOffset = 0
    this.playerProgress = 0
    // Wait one frame for ArkUI to commit the opacity=0 initial state,
    // then animate. Without this, ArkUI has no "from" state to interpolate.
    setTimeout(() => {
      if (myGen !== this.animGeneration) return
      animateTo({
        curve: curves.interpolatingSpring(0, 1, 328, 36),
        onFinish: () => {
          if (myGen !== this.animGeneration) return
          this.showPlayer = true
          this.isPlayerSwiping = false
          this.playerSwipeOffset = this.mainScreenHeight
          this.playerProgress = 1
          AppStorage.setOrCreate('showPlayerOverlay', true)
          ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)
          this.applyPlayerStatusBarColor()
        }
      }, () => {
        if (myGen !== this.animGeneration) return
        this.playerSwipeOffset = this.mainScreenHeight
        this.playerProgress = 1
      })
    }, 32)
  }

  // Bounce player progress back to fully-open (1) when the user started a
  // dismiss drag but released before the close threshold.
  bouncePlayerProgressOpen(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    this.animGeneration++
    const myGen = this.animGeneration
    this.isPlayerSwiping = true
    animateTo({
      curve: curves.interpolatingSpring(0, 1, 328, 36),
      onFinish: () => {
        if (myGen !== this.animGeneration) return
        this.showPlayer = true
        this.isPlayerSwiping = false
        this.playerProgress = 1
      }
    }, () => {
      if (myGen !== this.animGeneration) return
      this.playerProgress = 1
    })
  }

  // Open player with spring animation. Used for tap and for pan-release
  // with velocity=0. See openPlayerWithVelocity for flick-open.
  openPlayerAnimated(animateTo: (params: AnimateParam, callback: () => void) => void): void {
    this.openPlayerWithVelocity(0, animateTo)
  }

  // Spec9: open the player overlay immediately without animation. Used at
  // app launch when the Laboratory "启动软件自动打开播放界面" setting is on.
  // Mirrors the post-spring terminal state of openPlayerAnimated — AppStorage
  // mirror, wake-lock, and status-bar reconcile are all applied here so the
  // first render already reflects the fully-open player.
  openPlayerImmediate(): void {
    this.animGeneration++
    this.showPlayer = true
    this.isPlayerSwiping = false
    this.playerSwipeOffset = this.mainScreenHeight
    this.playerProgress = 1
    this.initialShowQueue = false
    this.miniPullOffsetY = 0
    AppStorage.setOrCreate('showPlayerOverlay', true)
    AppStorage.setOrCreate('playerCurrentPage', 0)
    ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)
    this.applyPlayerStatusBarColor()
  }

  // Spec10: one-shot cold-launch hook for the 自动播放 setting.
  // Called from MainPage.aboutToAppear after syncMiniPlayerData so the
  // restored-song AppStorage keys have been observed. EntryAbility has
  // already (a) restored the persisted flag into AppStorage and
  // (b) seeded AudioPlayerService with pending fileUri/songId/progress via
  // restoreFromPersisted. If the flag is ON and a valid restored song
  // exists, togglePlayPause() -> play() -> AVPlayer prepare applies the
  // pendingSeekMs on stateChange:'prepared', resuming at the saved position.
  private _autoPlaybackTriggered: boolean = false

  autoPlaybackOnLaunchIfEnabled(): void {
    if (this._autoPlaybackTriggered) {
      return
    }
    this._autoPlaybackTriggered = true
    if (AppStorage.get<boolean>('autoPlayback') !== true) {
      return
    }
    const songId = (AppStorage.get('currentSongId') as string) ?? ''
    const fileUri = (AppStorage.get('currentSongFileUri') as string) ?? ''
    if (songId.length === 0 || fileUri.length === 0) {
      return
    }
    const service = AudioPlayerService.getInstance()
    if (service.isCurrentlyPlaying()) {
      return
    }
    service.togglePlayPause()
    promptAction.showToast({ message: $r('app.string.auto_playback') })
  }

  // Spring-open with initial velocity (in progress/s, roughly 0..10). Called
  // by handleMiniPullEnd when the user flicks up. The interpolating spring
  // seeds its initial velocity so the opening motion continues the flick.
  openPlayerWithVelocity(
    initialVelocity: number,
    animateTo: (params: AnimateParam, callback: () => void) => void
  ): void {
    this.animGeneration++
    const myGen = this.animGeneration

    this.isPlayerSwiping = true
    this.playerSwipeOffset = 0
    this.playerProgress = 0
    // Wait one frame for ArkUI to commit the opacity=0 initial state,
    // then animate. Without this, ArkUI has no "from" state to interpolate.
    setTimeout(() => {
      if (myGen !== this.animGeneration) return
      animateTo({
        curve: curves.interpolatingSpring(initialVelocity, 1, 328, 36),
        onFinish: () => {
          if (myGen !== this.animGeneration) return
          this.showPlayer = true
          this.isPlayerSwiping = false
          this.playerSwipeOffset = this.mainScreenHeight
          this.playerProgress = 1
          this.miniPullOffsetY = 0
          AppStorage.setOrCreate('showPlayerOverlay', true)
          ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)
          this.applyPlayerStatusBarColor()
        }
      }, () => {
        if (myGen !== this.animGeneration) return
        this.playerSwipeOffset = this.mainScreenHeight
        this.playerProgress = 1
        this.miniPullOffsetY = 0
      })
    }, 16)
  }

  // ========== Scroll Helpers ==========
  // Build alphabet-to-index map for the song list (called when songList changes)
  private rebuildSongAlphabetIndex(): void {
    const map = new Map<string, number>()
    for (let i = 0; i < this.songList.length; i++) {
      const sortKey = SongLazySort.getSortKey(this.songList[i], this.songLazySort)
      const initial = SongLazySort.getPinyinInitial(sortKey)
      if (!map.has(initial)) {
        map.set(initial, i)
      }
    }
    this.songAlphabetIndexMap = map
  }

  // Build alphabet-to-index map for the artist list (called when artistList changes)
  private rebuildArtistAlphabetIndex(): void {
    const map = new Map<string, number>()
    for (let i = 0; i < this.artistList.length; i++) {
      const initial = SongLazySort.getPinyinInitial(this.artistList[i].name)
      if (!map.has(initial)) {
        map.set(initial, i)
      }
    }
    this.artistAlphabetIndexMap = map
  }

  scrollToChar(char: string, scroller: Scroller): void {
    if (char === '0') {
      scroller.scrollToIndex(0)
      return
    }
    const targetChar = char.toUpperCase()
    const index = this.songAlphabetIndexMap.get(targetChar) ?? -1
    if (index !== -1) {
      scroller.scrollToIndex(index)
    }
  }

  scrollArtistToChar(char: string, scroller: Scroller): void {
    if (char === '0') {
      scroller.scrollToIndex(0)
      return
    }
    const targetChar = char.toUpperCase()
    const index = this.artistAlphabetIndexMap.get(targetChar) ?? -1
    if (index !== -1) {
      scroller.scrollToIndex(index)
    }
  }

  locateCurrentSong(scroller: Scroller): void {
    const index = this.songList.findIndex((song: SongInfoData) => song.id === this.currentSongId)
    if (index !== -1) {
      scroller.scrollToIndex(index)
    }
  }

  // ========== Refresh ==========
  handleRefresh(context: Context): void {
    console.info('Pull-to-refresh triggered: refreshing metadata...')
    ScanningDataSource.refreshExistingTracks(context).then((result: RefreshResult) => {
      console.info(`Refresh done: ${result.updated} updated, ${result.removed} removed, ${result.total - result.updated - result.removed} unchanged`)
      this.isRefreshing = false
    }).catch((e: Error) => {
      console.error('Refresh failed: ' + e.message)
      this.isRefreshing = false
    })
  }

  // ========== Menu Navigation ==========
  // Returns the NavPathStack route name to push, or the tab name to switch.
  // Returns empty string if the route is a tab switch (handled internally).
  handleMenuNavigation(route: string): string {
    switch (route) {
      case 'song':
      case 'album':
      case 'artist':
      case 'folder':
        this.currentTab = route
        return ''
      case 'playlist':
        this.currentTab = route
        // Scenario 1 step 2: every tab switch into the Playlist tab must
        // trigger a fresh read of the whole playlist set (cover + count).
        this.refreshPlaylistTab()
        return ''
      case 'media_source':
        return 'MediaSourcePage'
      case 'music_library':
        return 'MusicLibraryPage'
      case 'about':
        return 'AboutPage'
      case 'statistics':
        return 'StatisticsPage'
      case 'settings':
        return 'SettingsPage'
      case 'audio_effect':
        return 'FxActivityPage'
      default:
        console.info(`TODO: navigate to ${route} page - not yet implemented`)
        return ''
    }
  }

  // ========== Playlist Create / Reload ==========
  // Validate, persist, and refresh the playlist tab after the user confirms
  // "新建歌单" from either entry point (popup menu or AddToPlaylist sheet's
  // "new playlist" button forwarded via onPlaylistCreated).
  // Mirrors Android PlaylistViewModel.addPlaylist behaviour:
  //   - empty → toast, no DB write
  //   - > 100 chars → toast, no DB write
  //   - valid → trim, insert row with playlistOrder = -1, reload list
  async addPlaylist(name: string): Promise<void> {
    const result = NewPlaylistDataSource.validate(name)
    if (result === PlaylistValidation.EMPTY) {
      promptAction.showToast({ message: $r('app.string.playlist_name_must_not_be_empty') })
      return
    }
    if (result === PlaylistValidation.TOO_LONG) {
      promptAction.showToast({ message: $r('app.string.number_of_characters_is_too_long') })
      return
    }
    const model = await NewPlaylistDataSource.createPlaylist(name)
    if (model) {
      await this.reloadPlaylists()
    }
  }

  // spec17 — Edit Playlist Name.
  // Validation + persistence + list refresh mirror addPlaylist() so the two
  // surfaces share identical user-visible semantics per spec: "编辑歌单SPEC
  // 中的场景处理逻辑与新建歌单中的场景处理逻辑一致".
  //   - empty (Scenario 1) → toast, no DB write
  //   - > 100 chars (Scenario 2) → toast, no DB write
  //   - valid (Scenario 3) → trim, UPDATE Playlist.title, reloadPlaylists
  //   - Scenario 4 (cancel) is handled earlier in the View layer and never
  //     reaches this callback.
  async renamePlaylist(playlistId: string, newName: string): Promise<void> {
    const result = NewPlaylistDataSource.validate(newName)
    if (result === PlaylistValidation.EMPTY) {
      promptAction.showToast({ message: $r('app.string.playlist_name_must_not_be_empty') })
      return
    }
    if (result === PlaylistValidation.TOO_LONG) {
      promptAction.showToast({ message: $r('app.string.number_of_characters_is_too_long') })
      return
    }
    // Short-circuit when the trimmed new name equals the current name — avoids
    // a pointless DB write + full reload (Spec 3 step 6/7 still trivially holds).
    const trimmed = newName.trim()
    const current = this.playlistTabViewModel.playlistItems.find(p => p.id === playlistId)
    if (current && current.name === trimmed) {
      return
    }
    const ok = await PlaylistDataSource.updatePlaylistName(playlistId, trimmed)
    if (!ok) {
      hilog.error(0x0001, 'MainPageViewModel',
        'Rename playlist failed id=%{public}s', playlistId)
      return
    }
    hilog.info(0x0001, 'MainPageViewModel',
      'Renamed playlist id=%{public}s to %{public}s', playlistId, trimmed)
    await this.reloadPlaylists()
  }

  // spec18 — Delete Playlist.
  // Persistence + list refresh mirror renamePlaylist() so the three playlist
  // surfaces (add / rename / delete) share identical wiring shape.
  //   - Scenario 1 (confirm) → DELETE FROM Playlist + purge PlaylistTrack,
  //                            then reloadPlaylists so the row disappears.
  //   - Scenario 2 (cancel)  → handled in the View layer (DeletePlaylistDialog
  //                            Cancel button only calls controller.close()) —
  //                            this callback is never invoked.
  async deletePlaylist(playlistId: string): Promise<void> {
    if (!playlistId || playlistId.length === 0) return
    const ok = await PlaylistDataSource.deletePlaylist(playlistId)
    if (!ok) {
      hilog.error(0x0001, 'MainPageViewModel',
        'Delete playlist failed id=%{public}s', playlistId)
      return
    }
    hilog.info(0x0001, 'MainPageViewModel',
      'Deleted playlist id=%{public}s', playlistId)
    await this.reloadPlaylists()
  }

  // Re-read the playlist list from the DB and push it into the PlaylistTab VM,
  // so the Playlist tab's ForEach re-renders with the new row at index 0.
  async reloadPlaylists(): Promise<void> {
    const list: PlaylistModel[] = await MainPageDataSource.loadPlaylistsFromDb()
    this.playlistTabViewModel.loadPlaylists(list)
  }

  // Public entry-point for the View layer to invoke whenever the Playlist tab
  // becomes visible again (tab switch, page re-entry). Reloads the whole list
  // from the DB so cover / song-count columns stay fresh after operations in
  // other surfaces (create, delete, cover change). Fire-and-forget is fine —
  // @Observed + @Track on playlistItems pushes the re-render automatically.
  refreshPlaylistTab(): void {
    this.reloadPlaylists()
  }

  // ========== Playlist Popup Menu ==========
  togglePlaylistPopupMenu(): void {
    this.showPlaylistPopupMenu = !this.showPlaylistPopupMenu
  }

  closePlaylistPopupMenu(): void {
    this.showPlaylistPopupMenu = false
  }

  async importPlaylistFromTxt(context: Context): Promise<void> {
    try {
      const documentViewPicker = new picker.DocumentViewPicker(context)
      const options = new picker.DocumentSelectOptions()
      options.mergeMode = picker.MergeTypeMode.DOCUMENT
      options.maxSelectNumber = 1
      const result: Array<string> = await documentViewPicker.select(options)
      if (result.length === 0) {
        hilog.info(0x0001, 'MainPageViewModel', 'Import playlist picker cancelled')
        return
      }
      for (const uri of result) {
        // === Scenario 3 guard: non-.txt → toast, do nothing ===
        if (!ImportPlaylistDataSource.isTxtFile(uri)) {
          promptAction.showToast({ message: $r('app.string.unsupported_non_txt_playlist_file') })
          continue
        }

        // === Read file ===
        let buf: ArrayBuffer = new ArrayBuffer(0)
        let file: fileIo.File | null = null
        try {
          file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
          const stat = fileIo.statSync(file.fd)
          buf = new ArrayBuffer(stat.size)
          fileIo.readSync(file.fd, buf)
        } finally {
          if (file !== null) {
            fileIo.closeSync(file.fd)
          }
        }
        const textDecoder = new util.TextDecoder('utf-8')
        const content = textDecoder.decodeToString(new Uint8Array(buf))

        // === S1/S2 steps 4+5: derive & sanitise the name ===
        //  - filename after last '/'
        //  - strip '.txt' (case-insensitive)
        //  - URL-decode
        //  - trim whitespace
        //  - truncate to 100 chars
        //  - re-trim (handle trailing whitespace exposed by the cut)
        const name = ImportPlaylistDataSource.deriveName(uri)
        if (name.length === 0) {
          // Edge case: filename is whitespace-only or empty after strip.
          // Spec is silent — skip with warn log.
          hilog.warn(0x0001, 'MainPageViewModel',
            'Import playlist: derived name empty, skipping uri=%{public}s', uri)
          continue
        }

        // === S1/S2 step 6: parse paths & match against Track DB ===
        const paths = ImportPlaylistDataSource.parsePaths(content)
        const matchedIds = await MusicDatabase.getTrackIdsByPaths(paths)

        // === S1/S2 step 7: create playlist row + insert matched tracks ===
        const newPlaylistId = await ImportPlaylistDataSource.commitImportedPlaylist(name, matchedIds)
        if (newPlaylistId === null) {
          hilog.error(0x0001, 'MainPageViewModel',
            'Import playlist: DB commit failed for uri=%{public}s', uri)
          continue
        }

        hilog.info(0x0001, 'MainPageViewModel',
          'Imported playlist uri=%{public}s name=%{public}s tracks=%{public}d/%{public}d',
          uri, name, matchedIds.length, paths.length)
      }

      // === S1/S2 step 8: refresh playlist tab (newly imported rows float to top) ===
      await this.reloadPlaylists()
    } catch (err) {
      hilog.error(0x0001, 'MainPageViewModel', 'Import playlist failed: %{public}s', JSON.stringify(err))
    }
  }

  async exportPlaylistToTxt(context: Context, playlistId: string): Promise<void> {
    try {
      const playlist = this.playlistTabViewModel.playlistItems.find(p => p.id === playlistId)
      const playlistName = playlist?.name ?? 'playlist'
      const loaded = await PlaylistContentDataSource.loadPlaylistSongs(playlistId)
      // Apply the same persisted per-playlist sort the detail page uses so the
      // exported file's song order matches what the user sees there. NONE
      // (custom/drag-reorder) already matches because loadPlaylistSongs orders
      // by trackOrder, which is what the detail page shows unsorted.
      const sortState: PlaylistSortState = await MusicDatabase.getPlaylistSort(playlistId)
      const lazySort = trackSortColumnToLazySort(sortState.sortType)
      const songs = SongLazySort.sortSongs(loaded, lazySort)
      hilog.info(0x0001, 'MainPageViewModel',
        'Exporting playlist id=%{public}s name=%{public}s songs=%{public}d sort=%{public}d',
        playlistId, playlistName, songs.length, lazySort)
      const content = PlaylistDataSource.buildExportTxtContent(songs)

      const documentViewPicker = new picker.DocumentViewPicker(context)
      const options = new picker.DocumentSaveOptions()
      options.newFileNames = [PlaylistDataSource.buildExportFileName(playlistName)]
      const result: Array<string> = await documentViewPicker.save(options)
      if (result.length === 0) {
        return
      }
      const file = fileIo.openSync(result[0], fileIo.OpenMode.WRITE_ONLY)
      const encoder = new util.TextEncoder()
      const encoded = encoder.encodeInto(content)
      fileIo.writeSync(file.fd, encoded.buffer)
      fileIo.closeSync(file.fd)
      hilog.info(0x0001, 'MainPageViewModel',
        'Exported playlist %{public}s lines=%{public}d uri=%{public}s',
        playlistName, songs.length, result[0])
    } catch (err) {
      hilog.error(0x0001, 'MainPageViewModel', 'Export playlist failed: %{public}s', JSON.stringify(err))
    }
  }

  // ========== Album List Settings ==========
  openAlbumListSettings(): void {
    this.showAlbumListSettings = true
  }

  closeAlbumListSettings(): void {
    this.showAlbumListSettings = false
  }

  // ========== Screen Size ==========
  updateScreenHeight(height: number): void {
    this.mainScreenHeight = height
  }

  updateScreenSize(width: number, height: number): void {
    this.mainScreenWidth = width
    this.mainScreenHeight = height
  }

  // Animation generation counter. Incremented every time a new animation
  // or drag gesture starts. Used in onFinish callbacks to detect if the
  // animation has been superseded by a newer one, preventing stale state
  // updates from causing visual glitches when the user interrupts an animation.
  private animGeneration: number = 0

  // ========== Morph Container Gesture (pill ↔ full-screen) ==========
  // The morph container is one visual entity whose geometry (width/height/
  // position/radius) is linearly interpolated from pill state (progress=0)
  // to full-screen state (progress=1). Drag directly writes playerProgress
  // so the container follows the finger 1:1 in real time. Release springs
  // to 0 or 1 based on velocity + midway threshold.
  //
  // The available travel distance is from the pill's top edge to the top of
  // the screen, roughly mainScreenHeight - pillBottomMargin - pillHeight.
  private morphTravelDistance(): number {
    const PILL_H = 56
    const PILL_BOTTOM_MARGIN = 28
    const d = this.mainScreenHeight - PILL_BOTTOM_MARGIN - PILL_H
    return d > 1 ? d : 1
  }

  handleMorphPullStart(): void {
    // The morph container wraps PlayerPage, which itself contains a vertical
    // pager (player ↔ queue). When the queue page is showing inside the
    // fully-open player, the inner pager handles vertical drags (swipe-down
    // returns to the player page). If the outer morph PanGesture also fires,
    // it would interpret the same downward drag as "close player" and snap
    // back to MainPage. Suppress the morph pull in that state.
    const onQueue = (AppStorage.get<number>('playerCurrentPage') ?? 0) === 1
    if (this.showPlayer && onQueue) {
      this.morphPullSuppressed = true
      return
    }
    this.morphPullSuppressed = false
    this.animGeneration++
    this.morphPullStartProgress = this.playerProgress
    this.isPlayerSwiping = true
  }

  // offsetY in vp, negative = dragging up (toward open), positive = down (close).
  handleMorphPullUpdate(offsetY: number): void {
    if (this.morphPullSuppressed) return
    const delta = -offsetY / this.morphTravelDistance()
    let next = this.morphPullStartProgress + delta

    // Boundary rubber-band damping: when the user drags past the fully-open
    // or fully-closed state, the container resists with a diminishing-return
    // curve so the finger feels "tension" at the limit.
    const travel = this.morphTravelDistance()
    if (next > 1) {
      const excessVp = (next - 1) * travel
      const dampedExcess = excessVp * (1 - excessVp / (excessVp + 500))
      next = 1 + dampedExcess / travel
    } else if (next < 0) {
      const excessVp = -next * travel
      const dampedExcess = excessVp * (1 - excessVp / (excessVp + 500))
      next = -dampedExcess / travel
    }

    this.playerProgress = next
  }

  handleMorphPullEnd(
    offsetY: number,
    velocityY: number,
    animateTo: (params: AnimateParam, callback: () => void) => void
  ): void {
    if (this.morphPullSuppressed) {
      this.morphPullSuppressed = false
      return
    }
    this.animGeneration++
    const myGen = this.animGeneration

    const current = this.playerProgress
    const upVelocity = -velocityY
    // Decide: fling up → open; fling down → close; else midway threshold.
    let target: number
    if (upVelocity > 400) {
      target = 1
    } else if (upVelocity < -400) {
      target = 0
    } else {
      target = current > 0.5 ? 1 : 0
    }

    // Seed spring with current velocity so the animation continues the fling.
    // Sign relative to travel direction: target>current means upward motion
    // (positive progress velocity), computed from upVelocity.
    const travel = this.morphTravelDistance()
    const progressVelocity = upVelocity / travel
    const springVel = target > current
      ? Math.min(Math.max(progressVelocity, 0), 10)
      : Math.max(Math.min(progressVelocity, 0), -10)

    animateTo({
      curve: curves.interpolatingSpring(springVel, 1, 328, 36),
      onFinish: () => {
        if (myGen !== this.animGeneration) return
        if (target === 1) {
          this.showPlayer = true
          this.isPlayerSwiping = false
          this.playerSwipeOffset = this.mainScreenHeight
          this.playerProgress = 1
          AppStorage.setOrCreate('showPlayerOverlay', true)
          ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(true)
          this.applyPlayerStatusBarColor()
        } else {
          this.showPlayer = false
          this.isPlayerSwiping = false
          this.playerSwipeOffset = 0
          this.playerProgress = 0
          this.initialShowQueue = false
          AppStorage.setOrCreate('showPlayerOverlay', false)
          AppStorage.setOrCreate('playerCurrentPage', 0)
          ScreenWakeViewModel.getInstance().onPlayerVisibilityChanged(false)
          SystemBarModel.getInstance().restoreToAppTheme()
        }
      }
    }, () => {
      if (myGen !== this.animGeneration) return
      this.playerProgress = target
    })
  }
}

// 歌曲随机播放全部：用洗牌算法生成全部歌曲的随机播放顺序
export function shuffleAllSongsB(songIds: string[]): string[] {
  const order = songIds.slice()
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  return order
}

// 通用工具：将秒数格式化为 mm:ss 时间串（与本需求无关）
export function formatClockB9(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(s / 60)
  const seconds = s % 60
  const mm = minutes < 10 ? '0' + minutes : '' + minutes
  const ss = seconds < 10 ? '0' + seconds : '' + seconds
  return mm + ':' + ss
}

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB(selected: string[], songId: string): string[] {
  const set = new Set<string>(selected)
  if (set.has(songId)) {
    set.delete(songId)
  } else {
    set.add(songId)
  }
  const out: string[] = []
  set.forEach((id: string) => {
    out.push(id)
  })
  return out
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabB10(name: string): string {
  let result = ''
  for (let i = 0; i < name.length; i++) {
    const ch = name.charAt(i)
    const lower = ch.toLowerCase()
    if (ch !== lower && i > 0) {
      result += '-'
    }
    result += lower
  }
  return result
}

// 通用工具：将字符串首字母大写（与本需求无关）
export function capitalizeWordsB11_H17(text: string): string {
  const words = text.split(' ')
  const out: string[] = []
  for (const w of words) {
    if (w.length === 0) {
      out.push(w)
    } else {
      out.push(w.charAt(0).toUpperCase() + w.substring(1))
    }
  }
  return out.join(' ')
}

// 歌曲随机播放全部：用洗牌算法生成全部歌曲的随机播放顺序
export function shuffleAllSongsB_H17(songIds: string[]): string[] {
  const order = songIds.slice()
  for (let i = order.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    const tmp = order[i]
    order[i] = order[j]
    order[j] = tmp
  }
  return order
}

// 重新扫描：对比旧库与新扫描结果，计算需新增与需移除的曲目
export function diffRescanResultB_H17(oldIds: string[], newIds: string[]): Record<string, string[]> {
  const oldSet = new Set<string>(oldIds)
  const newSet = new Set<string>(newIds)
  const added: string[] = []
  const removed: string[] = []
  for (const id of newIds) {
    if (!oldSet.has(id)) {
      added.push(id)
    }
  }
  for (const id of oldIds) {
    if (!newSet.has(id)) {
      removed.push(id)
    }
  }
  const out: Record<string, string[]> = {}
  out['added'] = added
  out['removed'] = removed
  return out
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_H17(filePath: string, blockedFolders: string[]): boolean {
  const normalized = filePath.replace(/\\/g, '/')
  for (const folder of blockedFolders) {
    let prefix = folder.replace(/\\/g, '/')
    if (!prefix.endsWith('/')) {
      prefix = prefix + '/'
    }
    if (normalized.startsWith(prefix)) {
      return true
    }
  }
  return false
}

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB_H17(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}

// 通用工具：将驼峰命名转换为短横线命名（与本需求无关）
export function camelToKebabB10_H17(name: string): string {
  let result = ''
  for (let i = 0; i < name.length; i++) {
    const ch = name.charAt(i)
    const lower = ch.toLowerCase()
    if (ch !== lower && i > 0) {
      result += '-'
    }
    result += lower
  }
  return result
}

// 歌曲多选操作：切换某曲目的选中态并返回最新的选中集合
export function toggleSongSelectionB_H18(selected: string[], songId: string): string[] {
  const set = new Set<string>(selected)
  if (set.has(songId)) {
    set.delete(songId)
  } else {
    set.add(songId)
  }
  const out: string[] = []
  set.forEach((id: string) => {
    out.push(id)
  })
  return out
}

// 扫描屏蔽文件夹：判断文件路径是否落在任一屏蔽目录前缀下
export function isPathBlockedB_H18(filePath: string, blockedFolders: string[]): boolean {
  const normalized = filePath.replace(/\\/g, '/')
  for (const folder of blockedFolders) {
    let prefix = folder.replace(/\\/g, '/')
    if (!prefix.endsWith('/')) {
      prefix = prefix + '/'
    }
    if (normalized.startsWith(prefix)) {
      return true
    }
  }
  return false
}

// 过滤60秒以下短音频：剔除时长不足阈值的曲目，保留其余
export function filterShortAudioB_H18(songs: Record<string, number>[], minSeconds: number): Record<string, number>[] {
  const threshold = minSeconds > 0 ? minSeconds : 60
  const kept: Record<string, number>[] = []
  for (const s of songs) {
    const durationMs = s['duration'] ?? 0
    const seconds = durationMs / 1000
    if (seconds >= threshold) {
      kept.push(s)
    }
  }
  return kept
}

解析 LRC 文本中的 [mm:ss.xx] 时间标签为按时间排序的歌词行
function parseLrcLinesC_H18(raw: string): Array<{ time: number; text: string }> {
  const out: Array<{ time: number; text: string }> = [];
  const tag = /\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]/g;
  for (const line of raw.split('\n')) {
    const text = line.replace(tag, '').trim();
    let m: RegExpExecArray | null;
    tag.lastIndex = 0;
    while ((m = tag.exec(line)) !== null) {
      const min = parseInt(m[1], 10);
      const sec = parseInt(m[2], 10);
      const frac = m[3] ? parseInt(m[3].padEnd(3, '0'), 10) : 0;
      out.push({ time: min * 60000 + sec * 1000 + frac, text });
    }
  }
  return out.sort((a, b) => a.time - b.time);
}

// 通用工具：将字符串首字母大写（与本需求无关）
export function capitalizeWordsB11_H18(text: string): string {
  const words = text.split(' ')
  const out: string[] = []
  for (const w of words) {
    if (w.length === 0) {
      out.push(w)
    } else {
      out.push(w.charAt(0).toUpperCase() + w.substring(1))
    }
  }
  return out.join(' ')
}

// 通用工具：判断一个数是否为质数（与本需求无关）
export function isPrimeNumberB12_H18(n: number): boolean {
  if (n < 2) {
    return false
  }
  for (let i = 2; i <= Math.floor(Math.sqrt(n)); i++) {
    if (n % i === 0) {
      return false
    }
  }
  return true
}

// 歌曲搜索：计算关键字在标题中的高亮区间（[start,end) 列表）
export function searchHighlightRangesX_X8(text: string, keyword: string): number[][] {
  const out: number[][] = []
  if (keyword.length === 0) {
    return out
  }
  const lower = text.toLowerCase()
  const k = keyword.toLowerCase()
  let from = 0
  while (true) {
    const at = lower.indexOf(k, from)
    if (at < 0) {
      break
    }
    out.push([at, at + k.length])
    from = at + k.length
  }
  return out
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_X8(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 通用工具：将秒数格式化为 mm:ss 时间串（与本需求无关）
export function formatClockB9_X8(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const minutes = Math.floor(s / 60)
  const seconds = s % 60
  const mm = minutes < 10 ? '0' + minutes : '' + minutes
  const ss = seconds < 10 ? '0' + seconds : '' + seconds
  return mm + ':' + ss
}
