// StatisticsViewModel.ets
// ViewModel layer: provides data and business logic for StatisticsPage (View).
// Bridges the Model layer (StatisticsModel, SongItemModel) with the View layer.
// Handles data loading, state management, and user interaction logic.

import { StatisticsSongData, StatisticsDataSource } from '../model/StatisticsModel'
import { SongInfoData } from '../model/SongItemModel'
import { QueueSongModel } from '../model/PlayQueueModel'
import AudioPlayerService from '../model/AudioPlayerService'

// Observable ViewModel for the Statistics page
@Observed
export class StatisticsViewModel {
  // Statistics song list data - loaded from data source
  @Track public statisticsSongs: StatisticsSongData[] = []

  // Loading state
  @Track public isLoading: boolean = true

  // Current playing song ID (used to highlight the currently playing song)
  @Track public currentSongId: string = ''

  // Whether the song list is empty (manually maintained when statisticsSongs changes)
  @Track public isEmpty: boolean = true

  // Load statistics data from the data source (MusicDatabase.getListenMusicRankTop100)
  async loadStatisticsData(): Promise<void> {
    this.isLoading = true
    const list: StatisticsSongData[] = await StatisticsDataSource.loadTop100()
    this.statisticsSongs = list
    this.isEmpty = list.length === 0
    this.isLoading = false
  }

  // Handle add-to-play-next action (delegates to music service)
  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album,
      song.subTitle, song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Get the title color for a song based on whether it is currently playing and valid
  isSongCurrent(songId: string): boolean {
    return songId === this.currentSongId
  }

  // Handle play music action - play the clicked song with the ranked list
  playSong(song: SongInfoData): void {
    this.currentSongId = song.id
    const songs: SongInfoData[] = this.statisticsSongs.map(
      (item: StatisticsSongData): SongInfoData => item.song)
    const queue: QueueSongModel[] = songs.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === song.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  // Get the song list as SongInfoData array for playback
  getSongList(): SongInfoData[] {
    return this.statisticsSongs.map((item: StatisticsSongData) => item.song)
  }
}

// 聆听统计：Top100 排行页状态。
