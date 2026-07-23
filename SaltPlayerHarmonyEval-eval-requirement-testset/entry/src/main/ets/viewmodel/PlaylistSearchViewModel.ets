// PlaylistSearchViewModel.ets
// ViewModel layer: data and business logic for the in-playlist search page.
// Mirrors the relevant slice of PlaylistContentViewModel (multi-select / sort /
// remove-from-this-playlist) + SearchAllSongsViewModel (keyword filter / song
// menu state). Used by PlaylistSearchPage.

import { SongInfoData } from '../model/SongItemModel'
import { PlaylistContentDataSource } from '../model/PlaylistContentModel'
import { SongLazySort } from '../model/SongSortModel'
import { MusicDatabase, PlaylistSortState } from '../model/MusicDatabase'
import { QueueSongModel } from '../model/PlayQueueModel'
import AudioPlayerService from '../model/AudioPlayerService'
import { shareSongFile } from '../model/ShareUtil'
import { common } from '@kit.AbilityKit'

function bumpPlaylistVersion(): void {
  const v: number = AppStorage.get<number>('playlistVersion') ?? 0
  AppStorage.setOrCreate<number>('playlistVersion', v + 1)
}

// Router params for the page. Kept co-located with the VM so callers can
// import the params + VM together.
export interface PlaylistSearchRouterParams {
  playlistId: string
  playlistName: string
  playlistSongCount: number
}

// Translate the Playlist.trackSort column value into a SongLazySort.* constant.
// Mirrors the helper in PlaylistContentViewModel — column 0 means "按添加到歌单
// 的时间" (PLAYLIST_ADD_TIME), column < 0 means "自定义" (NONE). All other values
// are stored as SongLazySort constants directly.
function trackSortColumnToLazySort(col: number): number {
  if (col < 0) return SongLazySort.NONE
  return col === 0 ? SongLazySort.PLAYLIST_ADD_TIME : col
}

function lazySortToTrackSortColumn(sort: number): number {
  return sort === SongLazySort.NONE ? -1 : sort
}

@Observed
export default class PlaylistSearchViewModel {
  // ========== Playlist identity ==========
  @Track public playlistId: string = ''
  @Track public playlistName: string = ''
  @Track public playlistSongCount: number = 0

  // ========== Search state ==========
  @Track public keyword: string = ''
  @Track public hasResults: boolean = false
  @Track public searchResults: SongInfoData[] = []

  // Raw snapshot — every song currently in the playlist. Filtered by keyword
  // on demand. Stays outside the @Track layer because the view never renders
  // it directly; only searchResults drives the list.
  private playlistSongs: SongInfoData[] = []

  // ========== Sort state ==========
  @Track public songLazySort: number = SongLazySort.PLAYLIST_ADD_TIME
  @Track public descending: boolean = false
  private sortResolved: boolean = false

  // ========== Display state ==========
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // ========== Playback + selection ==========
  @Track public currentSongId: string = ''
  @Track public multiChoiceMode: boolean = false
  @Track private checkedIds: Set<string> = new Set()
  // Parallel pick-order list (spec5 S6-style) so multi-select → add-to-playlist
  // preserves the first-picked → top ordering.
  @Track private checkedOrder: string[] = []

  // ========== Song menu state ==========
  @Track public menuTargetSong: SongInfoData | null = null

  // Lottie animation id (consumed by the page's empty-state Canvas).
  @Track public readonly LOTTIE_ANIM_NAME: string = 'lottie_empty_playlist_search'

  // ========== Initialization ==========
  initFromParams(params: PlaylistSearchRouterParams): void {
    this.playlistId = params.playlistId ?? ''
    this.playlistName = params.playlistName ?? ''
    this.playlistSongCount = params.playlistSongCount ?? 0
  }

  async loadPlaylistSnapshot(): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) {
      this.playlistSongs = []
      this.playlistSongCount = 0
      this.recomputeResults()
      return
    }
    // Resolve per-playlist sort preference once. Writing sort later goes
    // through MusicDatabase.setPlaylistSort so playlist detail picks it up.
    if (!this.sortResolved) {
      const state: PlaylistSortState = await MusicDatabase.getPlaylistSort(this.playlistId)
      this.songLazySort = trackSortColumnToLazySort(state.sortType)
      this.descending = state.descending
      this.sortResolved = true
    }
    const loaded: SongInfoData[] = await PlaylistContentDataSource.loadPlaylistSongs(this.playlistId)
    this.playlistSongs = loaded
    this.playlistSongCount = loaded.length
    this.recomputeResults()
  }

  getSearchPlaceholder(): string {
    return `在 ${this.playlistSongCount} 首歌曲中搜索`
  }

  // ========== Search ==========
  performSearch(query: string): void {
    this.keyword = query
    this.recomputeResults()
  }

  clearSearch(): void {
    this.keyword = ''
    this.recomputeResults()
  }

  // Filter playlist snapshot by keyword, then apply the current sort.
  // Spec2 step 3 requires file-name match — include SongInfoData.path so the
  // "add then search by file name" case (S2) hits even when title/artist don't.
  private recomputeResults(): void {
    const q = this.keyword.trim().toLowerCase()
    let base: SongInfoData[]
    if (q.length === 0) {
      base = []
    } else {
      base = this.playlistSongs.filter((s: SongInfoData): boolean => {
        const title = (s.title ?? '').toLowerCase()
        const artist = (s.artist ?? '').toLowerCase()
        const album = (s.album ?? '').toLowerCase()
        const path = (s.path ?? '').toLowerCase()
        return title.includes(q) || artist.includes(q) || album.includes(q) || path.includes(q)
      })
    }
    // Re-sort via SongLazySort.sortSongs so the ordering matches playlist
    // detail. Reassign to a new array so @Track fires.
    this.searchResults = SongLazySort.sortSongs(base, this.songLazySort)
    this.hasResults = this.searchResults.length > 0
  }

  // ========== Sort ==========
  changeSortType(sort: number): void {
    this.songLazySort = sort
    // Persist so re-opening playlist detail reflects the user's choice.
    if (this.playlistId && this.playlistId.length > 0) {
      MusicDatabase.setPlaylistSort(this.playlistId,
        lazySortToTrackSortColumn(sort), this.descending)
    }
    this.recomputeResults()
  }

  // Drag-reorder entry point for custom sort (NONE) on the search page.
  // `fromIndex` / `toIndex` are positions within the visible `searchResults`
  // (filtered subset). The matched-song positions in the full playlist snapshot
  // are preserved — only the contents of those positions are shuffled to reflect
  // the new relative order of the filtered rows. Unrelated songs stay put.
  // Persists the full new order so PlaylistContentPage reflects it on back-nav.
  moveSongInResults(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 ||
      fromIndex >= this.searchResults.length ||
      toIndex >= this.searchResults.length) {
      return
    }
    const nextResults: SongInfoData[] = this.searchResults.slice()
    const moved: SongInfoData[] = nextResults.splice(fromIndex, 1)
    nextResults.splice(toIndex, 0, moved[0])
    this.searchResults = nextResults

    // Map back to the full playlist snapshot. Collect the absolute indices
    // of every currently-matched song in `playlistSongs`, then overwrite those
    // slots with `nextResults` in order.
    const matchedIdSet = new Set<string>(nextResults.map((s: SongInfoData) => s.id))
    const matchedIndices: number[] = []
    for (let i = 0; i < this.playlistSongs.length; i++) {
      if (matchedIdSet.has(this.playlistSongs[i].id)) {
        matchedIndices.push(i)
      }
    }
    if (matchedIndices.length !== nextResults.length) {
      // Snapshot drifted (e.g. a live add/remove between search + drag) —
      // bail out of the persistence step rather than shuffling rows in
      // positions we don't own. The VM is back in a consistent state via
      // the searchResults reassignment above.
      return
    }
    const newPlaylistSongs: SongInfoData[] = this.playlistSongs.slice()
    for (let k = 0; k < matchedIndices.length; k++) {
      newPlaylistSongs[matchedIndices[k]] = nextResults[k]
    }
    this.playlistSongs = newPlaylistSongs

    if (this.playlistId && this.playlistId.length > 0) {
      const orderedIds: string[] = newPlaylistSongs.map((s: SongInfoData) => s.id)
      MusicDatabase.updatePlaylistTrackOrders(this.playlistId, orderedIds)
    }
  }

  updateDisplaySetting(key: string, value: boolean): void {
    if (key === 'displaySongCoverInList') {
      this.displaySongCoverInList = value
    } else if (key === 'displaySongFileNameInList') {
      this.displaySongFileNameInList = value
    } else if (key === 'displayAddToPlayNextInList') {
      this.displayAddToPlayNextInList = value
    }
  }

  // Forward AppStorage 'displaySongCover' writes from the Page-layer bridge
  // (@StorageProp('displaySongCover') @Watch(handler) -> handler calls this)
  // so the search result list re-renders when the setting is toggled.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the in-playlist search result list re-renders when
  // the user toggles the setting elsewhere.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the in-playlist search result list re-renders when
  // the user toggles the setting elsewhere.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

  // ========== Refresh hook ==========
  // Called by the page when the shared 'playlistVersion' AppStorage key bumps
  // (S2/S3 triggered elsewhere while the search page is on top of the stack).
  async refreshFromDb(): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) return
    const loaded: SongInfoData[] = await PlaylistContentDataSource.loadPlaylistSongs(this.playlistId)
    this.playlistSongs = loaded
    this.playlistSongCount = loaded.length
    this.recomputeResults()
  }

  // ========== Playback ==========
  isSongCurrent(songId: string): boolean {
    return songId === this.currentSongId
  }

  playSong(song: SongInfoData): void {
    // Build the queue from the current filtered+sorted results — the user
    // expects the played queue to reflect what they see on screen.
    const queue: QueueSongModel[] = this.searchResults.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === song.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album,
      song.subTitle, song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  shufflePlayResults(): void {
    if (this.searchResults.length === 0) return
    const shuffled: SongInfoData[] = this.searchResults.slice()
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1))
      const t = shuffled[i]
      shuffled[i] = shuffled[j]
      shuffled[j] = t
    }
    const first = shuffled[0]
    const queue: QueueSongModel[] = shuffled.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    AudioPlayerService.getInstance().setQueue(queue, 0)
  }

  // ========== Song menu ==========
  openSongMenu(song: SongInfoData): void {
    this.menuTargetSong = song
  }

  closeSongMenu(): void {
    this.menuTargetSong = null
  }

  shareSong(context: common.UIAbilityContext): void {
    if (this.menuTargetSong) {
      shareSongFile(context, this.menuTargetSong.title, this.menuTargetSong.fileUri)
    }
  }

  // ========== Multi-choice ==========
  enterMultiChoiceMode(): void {
    this.checkedIds = new Set()
    this.checkedOrder = []
    this.multiChoiceMode = true
  }

  exitMultiChoiceMode(): void {
    this.multiChoiceMode = false
    this.checkedIds = new Set()
    this.checkedOrder = []
  }

  isChecked(songId: string): boolean {
    return this.checkedIds.has(songId)
  }

  setChecked(songId: string, checked: boolean): void {
    if (checked) {
      this.checkedIds.add(songId)
      if (this.checkedOrder.indexOf(songId) < 0) {
        this.checkedOrder = this.checkedOrder.concat([songId])
      }
    } else {
      this.checkedIds.delete(songId)
      this.checkedOrder = this.checkedOrder.filter((id: string) => id !== songId)
    }
    this.checkedIds = new Set(this.checkedIds)
  }

  toggleSelectAll(): void {
    if (this.checkedIds.size === this.searchResults.length) {
      this.checkedIds = new Set()
      this.checkedOrder = []
    } else {
      this.checkedIds = new Set(this.searchResults.map((s: SongInfoData) => s.id))
      this.checkedOrder = this.searchResults.map((s: SongInfoData) => s.id)
    }
  }

  checkedCount(): number {
    return this.checkedIds.size
  }

  getCheckedCountText(): string {
    return `已选 ${this.checkedIds.size}`
  }

  getSelectAllLabel(): string {
    return this.checkedIds.size === this.searchResults.length && this.searchResults.length > 0 ? '取消全选' : '全选'
  }

  getSelectedSongIdsInOrder(): string[] {
    return this.checkedOrder.filter((id: string) => this.checkedIds.has(id)).slice()
  }

  getSongCountText(): string {
    return `${this.searchResults.length}`
  }

  // ========== Remove-from-this-playlist (S3) ==========
  async removeSongFromPlaylist(songId: string): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) return
    if (!songId || songId.length === 0) return
    await MusicDatabase.deletePlaylistTracks(this.playlistId, [songId])
    this.playlistSongs = this.playlistSongs.filter((s: SongInfoData) => s.id !== songId)
    this.playlistSongCount = this.playlistSongs.length
    this.recomputeResults()
    // Bump the shared version bus so PlaylistContentPage (still on the back
    // stack) refreshes on pop, and any open AddToPlaylist picker reloads.
    bumpPlaylistVersion()
  }

  async removeCheckedFromPlaylist(): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) return
    const ids: string[] = Array.from(this.checkedIds)
    if (ids.length === 0) return
    const idSet = new Set<string>(ids)
    await MusicDatabase.deletePlaylistTracks(this.playlistId, ids)
    this.playlistSongs = this.playlistSongs.filter((s: SongInfoData) => !idSet.has(s.id))
    this.playlistSongCount = this.playlistSongs.length
    this.recomputeResults()
    this.checkedIds = new Set()
    this.checkedOrder = []
    bumpPlaylistVersion()
  }

  // ========== Remove-from-library (single + bulk) ==========
  // Single-song variant — parity with MainPage.songMenuBuilder onRemoveFromLibrary.
  // Deletes the track row by path, handles side-effects (removes from playlists /
  // play-queue / recent list), prunes the local snapshot, and bumps
  // playlistVersion so PlaylistContentPage under the stack refreshes on pop.
  async removeSongFromLibrary(song: SongInfoData): Promise<void> {
    if (!song) return
    if (!song.path || song.path.length === 0) return
    const ok: boolean = await MusicDatabase.deleteTrackByPath(song.path)
    if (!ok) return
    this.playlistSongs = this.playlistSongs.filter((s: SongInfoData) => s.id !== song.id)
    this.playlistSongCount = this.playlistSongs.length
    this.recomputeResults()
    await MusicDatabase.handleSongRemovedFromLibrary(song.id, song.fileUri)
    bumpPlaylistVersion()
  }

  // Bulk variant — parity with MainPageViewModel.removeSelectedFromLibrary.
  async removeCheckedFromLibrary(): Promise<void> {
    const ids: string[] = Array.from(this.checkedIds)
    if (ids.length === 0) return
    const paths: string[] = []
    const fileUris: string[] = []
    for (const id of ids) {
      const song = this.playlistSongs.find((s: SongInfoData) => s.id === id)
      if (song && song.path && song.path.length > 0) {
        paths.push(song.path)
      }
      if (song && song.fileUri && song.fileUri.length > 0) {
        fileUris.push(song.fileUri)
      }
    }
    await MusicDatabase.deleteTracksByPaths(paths)
    const checkedSet = new Set<string>(ids)
    this.playlistSongs = this.playlistSongs.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.playlistSongCount = this.playlistSongs.length
    this.recomputeResults()
    this.checkedIds = new Set()
    this.checkedOrder = []
    await MusicDatabase.handleSongsRemovedFromLibrary(ids, fileUris)
    bumpPlaylistVersion()
  }

  // ========== Play-selected-queue (multi-choice bottom bar) ==========
  // Parity with MainPageViewModel.playSelectedQueue / FolderContentPageViewModel.
  // Builds a queue from checked songs preserving the on-screen (filtered +
  // sorted) order and hands it to AudioPlayerService.
  playSelectedQueue(): void {
    if (this.checkedIds.size === 0) return
    // Preserve the on-screen order: walk searchResults, include those that are
    // checked. This mirrors MainPageViewModel which filters songList by
    // checkedMap, so the played queue matches what the user sees.
    const selected: SongInfoData[] = this.searchResults.filter((s: SongInfoData) =>
      this.checkedIds.has(s.id))
    if (selected.length === 0) return
    const queue: QueueSongModel[] = selected.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const first = selected[0]
    this.currentSongId = first.id
    AudioPlayerService.getInstance().setQueue(queue, 0)
  }

}

// 歌单内搜索：维护搜索关键字与过滤结果。
