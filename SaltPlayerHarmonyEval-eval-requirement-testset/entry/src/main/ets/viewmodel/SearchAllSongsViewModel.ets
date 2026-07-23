// SearchAllSongsViewModel.ets
// ViewModel layer: provides data and business logic for SearchAllSongsPage (View).
// Bridges the Model layer (SearchAllSongsModel) with the View layer.
// Exposes observable state variables and methods for search functionality.
//
// Scenario 2 fix: parity with the song-page list — added shuffle, sort and
// multi-select capabilities. Mirrors the equivalent surface in
// MainPageViewModel so the search-result list behaves the same as the
// song-page list (Android `SongLazyColumn` includes `RandomPlay`,
// `RightIcons` for sort, and `multiChoiceMode` toggle).

import { SongInfoData } from '../model/SongItemModel'
import { SearchAllSongsModel } from '../model/SearchAllSongsModel'
import { SongItemViewModel } from './SongItemViewModel'
import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import AudioPlayerService from '../model/AudioPlayerService'
import { shareSongFile } from '../model/ShareUtil'
import { common } from '@kit.AbilityKit'
import { SongLazySort } from '../model/SongSortModel'
import { MusicDatabase } from '../model/MusicDatabase'

@Observed
export class SearchAllSongsViewModel {
  // Search state
  @Track public keyword: string = ''
  @Track public searchResults: SongInfoData[] = []
  // Unsorted snapshot — `searchResults` is the sorted view that the UI binds to.
  // Kept separate so toggling sort modes does not require re-running the search.
  private unsortedSearchResults: SongInfoData[] = []
  @Track public validCount: number = 1

  // Song menu state
  @Track public showSongMenu: boolean = false
  @Track public songMenuTarget: SongInfoData | null = null

  // Sort state — mirrors MainPageViewModel.songLazySort for parity with the song page
  @Track public songLazySort: number = (AppStorage.get<number>('songLazySort') ?? SongLazySort.TITLE)
  @Track public showSortDialog: boolean = false

  // Multi-choice state — mirrors MainPageViewModel multi-choice surface
  @Track public multiChoiceMode: boolean = false
  @Track public checkedMap: Record<string, boolean> = {}
  @Track public checkedCount: number = 0
  // Parallel pick-order list: the FIRST entry is the FIRST-picked id, used when
  // committing add-to-playlist so the first-picked song lands on top.
  @Track public checkedOrder: string[] = []

  // Throttle to prevent rapid enter/exit of multi-choice mode
  private multiChoiceToggleTime: number = 0
  private static readonly MULTI_CHOICE_THROTTLE_MS: number = 300

  // Lottie animation configuration (referenced in @Builder method)
  @Track public readonly LOTTIE_ANIM_NAME: string = 'lottie_empty'

  // Global "show cover in song list" preference, seeded from AppStorage so
  // first render reflects the persisted value. SearchAllSongsPage bridges
  // live AppStorage updates into this field via setDisplaySongCoverInList.
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)

  // spec21 — Global "在列表中显示歌曲文件名" preference, seeded from AppStorage so
  // first render reflects the persisted value. The Page bridges live AppStorage
  // updates into this field via setDisplaySongFileNameInList; the search list
  // uses non-lazy ForEach, so a @Track flip rebuilds each row through
  // createSongItemViewModel.
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)

  // spec22 — Global "在列表中显示添加下一首播放" preference, seeded from AppStorage
  // so the first frame reflects the user's choice. The Page bridges live
  // AppStorage updates into this field via setDisplayAddToPlayNextInList; the
  // search list uses non-lazy ForEach, so a @Track flip rebuilds each row
  // through createSongItemViewModel.
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // Forward AppStorage 'displaySongCover' writes from the Page-layer bridge.
  // The search list uses non-lazy ForEach, so flipping this @Track field is
  // enough: the builder body re-runs and createSongItemViewModel rebuilds
  // each row with the new showCover value.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the search result list re-renders when the user
  // toggles the setting elsewhere.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the search result list re-renders when the user
  // toggles the setting elsewhere.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

  // Initialize from router params
  initFromParams(params: Record<string, Object>): void {
    if (params && params['validCount'] !== undefined) {
      this.validCount = params['validCount'] as number
    }
  }

  // Get placeholder text for search input
  getSearchPlaceholder(): string {
    return `在 ${this.validCount} 首歌曲中搜索`
  }

  // Whether search results exist (for controlling empty state display)
  @Track public hasResults: boolean = false

  // Perform search - delegates to Model layer, then applies the current sort
  performSearch(query: string): void {
    this.keyword = query
    const raw = SearchAllSongsModel.searchSongs(query)
    this.unsortedSearchResults = raw
    this.searchResults = SongLazySort.sortSongs(raw, this.songLazySort)
    this.hasResults = this.searchResults.length > 0
    // Switching the result set invalidates any prior multi-select state.
    if (this.multiChoiceMode) {
      this.exitMultiChoiceMode()
    }
  }

  // Clear search input and results
  clearSearch(): void {
    this.keyword = ''
    this.unsortedSearchResults = []
    this.searchResults = []
    this.hasResults = false
    if (this.multiChoiceMode) {
      this.exitMultiChoiceMode()
    }
  }

  // Play a song from search results: add to queue and play immediately
  playSong(song: SongInfoData): void {
    const queue: QueueSongModel[] = this.searchResults.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === song.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  // Add song to play next
  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Open song menu
  openSongMenu(song: SongInfoData): void {
    this.songMenuTarget = song
    this.showSongMenu = true
  }

  // Close song menu
  closeSongMenu(): void {
    this.showSongMenu = false
  }

  // Remove song from search results by ID
  removeSongFromListById(songId: string): void {
    this.unsortedSearchResults = this.unsortedSearchResults.filter((s: SongInfoData) => s.id !== songId)
    this.searchResults = this.searchResults.filter((s: SongInfoData) => s.id !== songId)
    this.hasResults = this.searchResults.length > 0
  }

  // Share song
  shareSong(context: common.UIAbilityContext): void {
    if (this.songMenuTarget) {
      shareSongFile(context, this.songMenuTarget.title, this.songMenuTarget.fileUri)
    }
  }

  // ========== Random Play ==========
  // Random-plays the current (sorted) result list. Mirrors MainPageViewModel.randomPlay.
  randomPlay(): void {
    if (this.searchResults.length === 0) {
      return
    }
    const queue: QueueSongModel[] = this.searchResults.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const randomIndex = Math.floor(Math.random() * this.searchResults.length)
    const picked = this.searchResults[randomIndex]
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(PlayModeConstants.RANDOM)
    service.setQueue(queue, randomIndex)
  }

  // ========== Sort ==========
  changeSongSort(sort: number): void {
    this.songLazySort = sort
    // Search results don't support custom (NONE) ordering — fall back to title.
    const effective = sort === SongLazySort.NONE ? SongLazySort.TITLE : sort
    this.searchResults = SongLazySort.sortSongs(this.unsortedSearchResults, effective)
  }

  // ========== Multi-choice Operations ==========
  enterMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < SearchAllSongsViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = true
  }

  exitMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < SearchAllSongsViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = false
    this.checkedMap = {}
    this.checkedCount = 0
    this.checkedOrder = []
  }

  toggleSelectAll(): void {
    if (this.checkedCount === this.searchResults.length) {
      this.checkedMap = {}
      this.checkedOrder = []
    } else {
      const newMap: Record<string, boolean> = {}
      const newOrder: string[] = []
      this.searchResults.forEach((song: SongInfoData) => {
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
    if (checked) {
      if (this.checkedOrder.indexOf(songId) < 0) {
        this.checkedOrder = this.checkedOrder.concat([songId])
      }
    } else {
      this.checkedOrder = this.checkedOrder.filter((id: string) => id !== songId)
    }
    this.updateCheckedCount()
  }

  // Pick-order snapshot for the current multi-select. Skips ids that have
  // since been unchecked.
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

  // Remove all currently-checked songs from the music library, then exit
  // multi-choice mode. Mirrors MainPageViewModel.removeSelectedFromLibrary.
  async removeSelectedFromLibrary(): Promise<void> {
    const checkedIds = Object.keys(this.checkedMap).filter((key: string) => this.checkedMap[key])
    if (checkedIds.length === 0) return
    // O(1) id→song lookup via Map — see MainPageViewModel.removeSelectedFromLibrary
    // for the rationale (eliminates the O(N²) for/find that dominated the click-handler stall).
    const idToSong = new Map<string, SongInfoData>()
    for (const s of this.unsortedSearchResults) {
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
    this.unsortedSearchResults = this.unsortedSearchResults.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.searchResults = this.searchResults.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.hasResults = this.searchResults.length > 0
    this.exitMultiChoiceMode()
    await MusicDatabase.handleSongsRemovedFromLibrary(checkedIds, fileUris)
  }

  // Play the multi-selected songs as a queue, in the order they appear in
  // the (sorted) result list.
  playSelectedQueue(): void {
    const selected = this.searchResults.filter((song: SongInfoData) => this.checkedMap[song.id] === true)
    if (selected.length === 0) {
      return
    }
    const queue: QueueSongModel[] = selected.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const first = selected[0]
    AudioPlayerService.getInstance().setQueue(queue, 0)
    this.exitMultiChoiceMode()
  }

  // Create a SongItemViewModel for a given search result song
  createSongItemViewModel(song: SongInfoData, currentSongId: string, isPlaying: boolean): SongItemViewModel {
    return SongItemViewModel.create(song, {
      isCurrent: song.id === currentSongId,
      showCover: this.displaySongCoverInList,
      displayFileName: this.displaySongFileNameInList,
      multiChoiceMode: this.multiChoiceMode,
      checked: this.checkedMap[song.id] === true,
      displayAddToPlayNext: this.displayAddToPlayNextInList,
      onItemClickAction: () => {
        if (this.multiChoiceMode) {
          // In multi-choice mode, tapping a row toggles its check state.
          const next = !(this.checkedMap[song.id] === true)
          this.updateSongChecked(song.id, next)
          return
        }
        if (song.id === currentSongId && isPlaying) {
          // Already playing this song - no action needed in search page
          return
        }
        this.playSong(song)
      },
      onItemLongClickAction: () => {
        // Long-press in normal mode opens the song menu (parity with song-tab).
        if (!this.multiChoiceMode) {
          this.openSongMenu(song)
        }
      },
      onMenuClickAction: () => {
        this.openSongMenu(song)
      },
      onAddToPlayNextAction: () => {
        this.addToPlayNext(song)
      },
      onCheckedChangeAction: (checked: boolean) => {
        this.updateSongChecked(song.id, checked)
      }
    })
  }
}
