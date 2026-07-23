import { SongInfoData } from '../model/SongItemModel'
import { PlaylistContentRouterParams, PlaylistContentDataSource } from '../model/PlaylistContentModel'
import { SongLazySort } from '../model/SongSortModel'
import { MusicDatabase, PlaylistSortState } from '../model/MusicDatabase'
import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import AudioPlayerService from '../model/AudioPlayerService'
import SongLazyDataSource from '../model/SongLazyDataSource'

// Translate the Playlist.trackSort column value into a SongLazySort.* constant.
// The column defaults to 0 for newly-created rows — per spec5 S7 that must
// mean "添加到歌单的时间" (PLAYLIST_ADD_TIME). SongLazySort.NONE shares the
// value 0 with that default, so "user explicitly picked custom" is stored as
// -1 instead to keep the two cases distinguishable across app restarts.
// All other non-zero values are stored as the SongLazySort constant directly.
export function trackSortColumnToLazySort(col: number): number {
  if (col < 0) return SongLazySort.NONE
  return col === 0 ? SongLazySort.PLAYLIST_ADD_TIME : col
}

function lazySortToTrackSortColumn(sort: number): number {
  return sort === SongLazySort.NONE ? -1 : sort
}

@Observed
export default class PlaylistContentViewModel {
  @Track public playlistId: string = ''
  @Track public playlistName: string = ''
  @Track public songCount: number = 0
  @Track public songs: SongInfoData[] = []
  // LazyForEach data source — kept in sync with `songs` on every reassignment.
  // PlaylistContentPage uses LazyForEach over this so 2000+ song playlists
  // render only the visible window instead of building every SongItemComponent
  // up front (which made entering a large playlist stall for several seconds).
  @Track public songDataSource: SongLazyDataSource = new SongLazyDataSource()
  @Track public currentSongId: string = ''
  @Track public menuTargetSong: SongInfoData | null = null

  // Raw unsorted songs (as returned by the DB). Kept so changeSortType can
  // re-run SongLazySort.sortSongs without re-querying the database.
  private unsortedSongs: SongInfoData[] = []

  // Per-playlist sort preference. Populated from the Playlist.trackSort column
  // on the first loadSongs call (S7/S8). Defaults to PLAYLIST_ADD_TIME while
  // the async resolveSort call is in flight.
  @Track public songLazySort: number = SongLazySort.PLAYLIST_ADD_TIME
  @Track public descending: boolean = false
  private sortResolved: boolean = false
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  @Track public multiChoiceMode: boolean = false
  @Track private checkedIds: Set<string> = new Set()
  // Parallel pick-order list (spec5 S6-style behaviour for PlaylistContentPage
  // multi-select → add-to-playlist). The first entry is the first-picked id.
  @Track private checkedOrder: string[] = []

  initFromParams(params: PlaylistContentRouterParams): void {
    this.playlistId = params.playlistId ?? ''
    this.playlistName = params.playlistName ?? ''
    this.songCount = params.playlistSongCount ?? 0
  }

  async loadSongs(): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) {
      this.unsortedSongs = []
      this.songs = []
      this.songDataSource.reload(this.songs)
      this.songCount = 0
      return
    }
    // Issue both DB reads in parallel. Previously the per-playlist sort
    // preference (small single-row read) blocked the song-list query (the
    // dominant ~2000-row read), so entering a large playlist serialised
    // both round-trips before the user saw anything.
    const sortPromise: Promise<PlaylistSortState | null> = this.sortResolved
      ? Promise.resolve(null)
      : MusicDatabase.getPlaylistSort(this.playlistId)
    const songsPromise: Promise<SongInfoData[]> =
      PlaylistContentDataSource.loadPlaylistSongs(this.playlistId)
    const sortState: PlaylistSortState | null = await sortPromise
    if (sortState !== null) {
      this.songLazySort = trackSortColumnToLazySort(sortState.sortType)
      this.descending = sortState.descending
      this.sortResolved = true
    }
    const loaded: SongInfoData[] = await songsPromise
    this.unsortedSongs = loaded
    this.songs = SongLazySort.sortSongs(loaded, this.songLazySort)
    this.songDataSource.reload(this.songs)
    this.songCount = loaded.length
  }

  isEmpty(): boolean {
    return this.songs.length === 0
  }

  isSongCurrent(songId: string): boolean {
    return songId === this.currentSongId
  }

  locateCurrentSong(scroller: Scroller): void {
    const index = this.songs.findIndex((song: SongInfoData) => song.id === this.currentSongId)
    if (index !== -1) {
      scroller.scrollToIndex(index)
    }
  }

  openSongMenu(song: SongInfoData): void {
    this.menuTargetSong = song
  }

  closeSongMenu(): void {
    this.menuTargetSong = null
  }

  playSong(song: SongInfoData): void {
    this.currentSongId = song.id
    const queue: QueueSongModel[] = this.songs.map((s: SongInfoData): QueueSongModel => {
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

  // Shuffle-play the whole playlist. Picks a random start index, switches the
  // player into RANDOM mode, and hands the full queue to AudioPlayerService —
  // parity with MainPageViewModel.randomPlay().
  shufflePlay(): void {
    if (this.songs.length === 0) return
    const queue: QueueSongModel[] = this.songs.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const randomIndex = Math.floor(Math.random() * this.songs.length)
    const picked = this.songs[randomIndex]
    this.currentSongId = picked.id
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(PlayModeConstants.RANDOM)
    service.setQueue(queue, randomIndex)
  }

  // Build a queue from the currently-checked songs (preserving on-screen
  // order) and hand it to AudioPlayerService — parity with
  // MainPageViewModel.playSelectedQueue().
  playSelectedQueue(): void {
    if (this.checkedIds.size === 0) return
    const selected: SongInfoData[] = this.songs.filter((s: SongInfoData) =>
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

  // Remove a single song from the music library. Deletes by path, removes it
  // from every playlist / queue / recents (via handleSongRemovedFromLibrary),
  // prunes the local snapshot, and bumps playlistVersion so sibling surfaces
  // refresh. Parity with MainPage songMenuBuilder.onRemoveFromLibrary.
  async removeSongFromLibrary(song: SongInfoData): Promise<void> {
    if (!song) return
    if (!song.path || song.path.length === 0) return
    const ok: boolean = await MusicDatabase.deleteTrackByPath(song.path)
    if (!ok) return
    this.unsortedSongs = this.unsortedSongs.filter((s: SongInfoData) => s.id !== song.id)
    this.songs = this.songs.filter((s: SongInfoData) => s.id !== song.id)
    this.songDataSource.reload(this.songs)
    this.songCount = this.songs.length
    await MusicDatabase.handleSongRemovedFromLibrary(song.id, song.fileUri)
    const v: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', v + 1)
  }

  // Bulk remove-from-library across the current multi-select. Parity with
  // MainPageViewModel.removeSelectedFromLibrary().
  async removeCheckedFromLibrary(): Promise<void> {
    const ids: string[] = Array.from(this.checkedIds)
    if (ids.length === 0) return
    const paths: string[] = []
    const fileUris: string[] = []
    for (const id of ids) {
      const song = this.unsortedSongs.find((s: SongInfoData) => s.id === id)
      if (song && song.path && song.path.length > 0) {
        paths.push(song.path)
      }
      if (song && song.fileUri && song.fileUri.length > 0) {
        fileUris.push(song.fileUri)
      }
    }
    await MusicDatabase.deleteTracksByPaths(paths)
    const checkedSet = new Set<string>(ids)
    this.unsortedSongs = this.unsortedSongs.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.songs = this.songs.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.songDataSource.reload(this.songs)
    this.songCount = this.songs.length
    this.checkedIds = new Set()
    this.checkedOrder = []
    await MusicDatabase.handleSongsRemovedFromLibrary(ids, fileUris)
    const v: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', v + 1)
  }

  changeSortType(sort: number): void {
    this.songLazySort = sort
    // Persist the choice against THIS playlist's row so switching sort in
    // playlist A doesn't leak into playlist B (S8). Fire-and-forget: the
    // write is idempotent and failure is non-fatal.
    if (this.playlistId && this.playlistId.length > 0) {
      MusicDatabase.setPlaylistSort(this.playlistId,
        lazySortToTrackSortColumn(sort), this.descending)
    }
    if (sort === SongLazySort.NONE) {
      // Custom sort: keep the current display order (persisted trackOrder)
      // so drag-reorder results survive toggling the sort dialog.
      this.songs = this.unsortedSongs.slice()
      this.songDataSource.reload(this.songs)
      return
    }
    // Re-sort the in-memory snapshot and reassign the @Track array so ArkUI
    // diffs the LazyForEach and refreshes the list without re-hitting the DB.
    this.songs = SongLazySort.sortSongs(this.unsortedSongs, sort)
    this.songDataSource.reload(this.songs)
  }

  // Move a song from one index to another within the visible list — used by
  // the playlist detail page's drag-reorder (long-press + pan) when the user
  // has picked the custom sort. Persists the new order to PlaylistTrack.trackOrder
  // so the next loadSongs() returns rows in this sequence.
  moveSong(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 ||
      fromIndex >= this.songs.length || toIndex >= this.songs.length) {
      return
    }
    const next: SongInfoData[] = this.songs.slice()
    const moved: SongInfoData[] = next.splice(fromIndex, 1)
    next.splice(toIndex, 0, moved[0])
    this.songs = next
    this.unsortedSongs = next.slice()
    this.songDataSource.reload(this.songs)
    if (this.playlistId && this.playlistId.length > 0) {
      const orderedIds: string[] = next.map((s: SongInfoData) => s.id)
      MusicDatabase.updatePlaylistTrackOrders(this.playlistId, orderedIds)
    }
  }

  // Re-read the playlist songs from the DB. Called by the View when the
  // shared 'playlistVersion' AppStorage key bumps (S12 — song-count and cover
  // stay consistent across all surfaces after any add).
  async refreshFromDb(): Promise<void> {
    // Force a re-read without toggling sortResolved so user's sort sticks.
    if (!this.playlistId || this.playlistId.length === 0) return
    const loaded: SongInfoData[] = await PlaylistContentDataSource.loadPlaylistSongs(this.playlistId)
    this.unsortedSongs = loaded
    this.songs = SongLazySort.sortSongs(loaded, this.songLazySort)
    this.songDataSource.reload(this.songs)
    this.songCount = loaded.length
  }

  // Remove a single song from this playlist (spec6 S1). Optimistically trims
  // the in-memory state, then persists and bumps the shared 'playlistVersion'
  // bus so MainPage Playlist tab + any open AddToPlaylist picker reload.
  async removeSongFromPlaylist(songId: string): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) return
    if (!songId || songId.length === 0) return
    await MusicDatabase.deletePlaylistTracks(this.playlistId, [songId])
    // Trim both the unsorted snapshot and the displayed list. Reassign so
    // @Track sees a new reference and ArkUI re-renders.
    this.unsortedSongs = this.unsortedSongs.filter((s: SongInfoData) => s.id !== songId)
    this.songs = this.songs.filter((s: SongInfoData) => s.id !== songId)
    this.songDataSource.reload(this.songs)
    this.songCount = this.songs.length
    // Bump version so other surfaces (MainPage Playlist tab, AddToPlaylist
    // picker if open) reload. Our own @Watch will re-enter refreshFromDb but
    // that is harmless and self-consistent.
    const v: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', v + 1)
  }

  // Remove the currently-checked songs from this playlist (spec6 S2). Snapshot
  // the id list first so the view's exitMultiChoiceMode can clear the set
  // without racing the DB write.
  async removeCheckedFromPlaylist(): Promise<void> {
    if (!this.playlistId || this.playlistId.length === 0) return
    const ids: string[] = Array.from(this.checkedIds)
    if (ids.length === 0) return
    const idSet = new Set<string>(ids)
    await MusicDatabase.deletePlaylistTracks(this.playlistId, ids)
    this.unsortedSongs = this.unsortedSongs.filter((s: SongInfoData) => !idSet.has(s.id))
    this.songs = this.songs.filter((s: SongInfoData) => !idSet.has(s.id))
    this.songDataSource.reload(this.songs)
    this.songCount = this.songs.length
    // Keep VM-local selection state consistent even if the caller forgets to
    // call exitMultiChoiceMode after us.
    this.checkedIds = new Set()
    this.checkedOrder = []
    const v: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', v + 1)
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
  // so the list re-renders when the setting is toggled elsewhere.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the playlist track list re-renders when the user
  // toggles the setting elsewhere.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the playlist track list re-renders when the user
  // toggles the setting elsewhere.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

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
    if (this.checkedIds.size === this.songs.length) {
      this.checkedIds = new Set()
      this.checkedOrder = []
    } else {
      this.checkedIds = new Set(this.songs.map(s => s.id))
      this.checkedOrder = this.songs.map((s: SongInfoData) => s.id)
    }
  }

  // Return the pick-order snapshot for multi-select add-to-playlist.
  getSelectedSongIdsInOrder(): string[] {
    return this.checkedOrder.filter((id: string) => this.checkedIds.has(id)).slice()
  }

  getSelectAllLabel(): string {
    return this.checkedIds.size === this.songs.length ? '取消全选' : '全选'
  }

  checkedCount(): number {
    return this.checkedIds.size
  }

  getCheckedCountText(): string {
    return `已选 ${this.checkedIds.size}`
  }

  getSongCountText(): string {
    return `${this.songCount}`
  }
}
