import { PlaylistItemViewModel } from './PlaylistTabViewModel'
import { MainPageDataSource } from '../model/MainPageModel'
import PlaylistModel from '../model/PlaylistModel'
import { NewPlaylistDataSource } from '../model/NewPlaylistModel'
import { MusicDatabase, InsertPlaylistTracksResult } from '../model/MusicDatabase'

@Observed
export default class AddToPlaylistDialogViewModel {
  @Track public playlists: PlaylistItemViewModel[] = []
  @Track public songId: string = ''
  // Ordered list of song ids captured at the moment the dialog opened (multi-
  // select). Pick order matters: the first-picked id must end up with the
  // largest PlaylistTrack.addedTime per spec5 S2/S6.
  @Track public selectedSongIds: string[] = []

  onPlaylistSelected: (playlistId: string, playlistName: string) => void = () => {}
  onDismiss: () => void = () => {}

  constructor(songId?: string,
    onPlaylistSelected?: (playlistId: string, playlistName: string) => void,
    onDismiss?: () => void,
    selectedSongIds?: string[]) {
    if (songId) {
      this.songId = songId
    }
    if (selectedSongIds && selectedSongIds.length > 0) {
      // Defensive copy so later mutations in the caller don't affect us.
      this.selectedSongIds = selectedSongIds.slice()
    } else if (songId && songId.length > 0) {
      // Single-song menu entry — fall back to a 1-element array so the commit
      // path is unified.
      this.selectedSongIds = [songId]
    }
    if (onPlaylistSelected) {
      this.onPlaylistSelected = onPlaylistSelected
    }
    if (onDismiss) {
      this.onDismiss = onDismiss
    }
    // Load from DB so the sheet reflects the current persistent playlist state
    // (Scenario 3: newly-created playlist appears at the top).
    this.reloadPlaylists()
  }

  // Legacy sync load — retained so an empty stub list renders immediately
  // until the async DB load resolves. No longer the primary source.
  loadPlaylists(): void {
    const models: PlaylistModel[] = MainPageDataSource.loadDefaultPlaylists()
    this.playlists = models.map((model: PlaylistModel) => {
      return new PlaylistItemViewModel(model.id, model.name, model.count, model.coverSongId)
    })
  }

  // Re-read the playlist list from the DB and rebuild the sheet's items so
  // a newly-created playlist appears immediately after addNewPlaylist resolves.
  async reloadPlaylists(): Promise<void> {
    const models: PlaylistModel[] = await MainPageDataSource.loadPlaylistsFromDb()
    this.playlists = models.map((model: PlaylistModel) => {
      return new PlaylistItemViewModel(model.id, model.name, model.count, model.coverSongId)
    })
  }

  handlePlaylistClick(playlist: PlaylistItemViewModel): void {
    this.onPlaylistSelected(playlist.id, playlist.name)
  }

  // Persist the pending add into the DB for the selected target playlist.
  // Returns the number of NEW rows inserted (duplicates count as 0 but we
  // still fire the "已添加到歌单" toast per spec S9). Always bumps the shared
  // playlistVersion AppStorage key so surfaces listening via @StorageLink
  // (MainPage Playlist tab, PlaylistContentPage) refresh on their own.
  async commitAddToPlaylist(playlistId: string): Promise<number> {
    if (!playlistId || playlistId.length === 0) return 0
    const ids: string[] = this.selectedSongIds.length > 0
      ? this.selectedSongIds.slice()
      : (this.songId.length > 0 ? [this.songId] : [])
    if (ids.length === 0) return 0
    const result: InsertPlaylistTracksResult = await MusicDatabase.insertPlaylistTracks(
      playlistId, ids, Date.now(), false)
    // The dialog component renders from its own @State playlists list, not
    // viewModel.playlists, so the previous reloadPlaylists() call here was a
    // wasted DB round-trip on the post-add hot path. The shared
    // 'playlistVersion' bump below already triggers the component's
    // @StorageProp watcher to re-read playlists for the song-count badge.
    const v: number = AppStorage.get<number>('playlistVersion') ?? 0
    AppStorage.setOrCreate<number>('playlistVersion', v + 1)
    return result.insertedCount
  }

  // Persist a new playlist via the shared NewPlaylistDataSource then refresh
  // the sheet's list. Returns the created PlaylistModel on success (null on
  // validation/DB failure) so the caller can notify the parent MainPage VM
  // to reload the playlist tab as well.
  async addNewPlaylist(name: string): Promise<PlaylistModel | null> {
    const model = await NewPlaylistDataSource.createPlaylist(name)
    if (model) {
      await this.reloadPlaylists()
    }
    return model
  }
}
