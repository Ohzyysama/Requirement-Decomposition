import { SongInfoData } from './SongItemModel'
import { MusicDatabase } from './MusicDatabase'

export interface PlaylistContentRouterParams {
  playlistId: string
  playlistName: string
  playlistSongCount: number
}

export class PlaylistContentDataSource {
  // Thin wrapper around MusicDatabase.getPlaylistSongInfos — the heavy lifting
  // (slim SELECT, cached column indices, single-pass build) lives in the
  // database layer so the result-set can be materialised into SongInfoData
  // without an intermediate PlaylistTrackRow pass. Returns [] on DB-miss or
  // when the playlist is empty. Propagates PlaylistTrack.addedTime via
  // playlistAddedTime so the VM can sort by SongLazySort.PLAYLIST_ADD_TIME.
  static async loadPlaylistSongs(playlistId: string): Promise<SongInfoData[]> {
    if (!playlistId || playlistId.length === 0) return []
    return MusicDatabase.getPlaylistSongInfos(playlistId)
  }
}
