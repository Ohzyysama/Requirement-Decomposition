// AlbumContentLazyDataSource.ets
// IDataSource for LazyForEach in AlbumContentPage song list.
// Flattens disc groups into a flat list of group headers + song items
// so that a single LazyForEach can render both disc headers and songs.

import { SongInfoData } from './SongItemModel'
import { DiscSongGroupData } from './AlbumContentModel'

// Flat item: either a disc group header (divider + optional disc label) or a song
export interface AlbumSongFlatItem {
  isGroupHeader: boolean
  disc: number
  songCount: number
  discDuration: string
  song: SongInfoData | undefined
}

export default class AlbumContentLazyDataSource implements IDataSource {
  private data: AlbumSongFlatItem[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): AlbumSongFlatItem {
    return this.data[index]
  }

  // Build flattened list from disc song groups
  reloadFromGroups(groups: DiscSongGroupData[]): void {
    const items: AlbumSongFlatItem[] = []
    for (const group of groups) {
      items.push({
        isGroupHeader: true,
        disc: group.disc,
        songCount: group.songs.length,
        discDuration: group.discDuration,
        song: undefined
      })
      for (const song of group.songs) {
        items.push({
          isGroupHeader: false,
          disc: 0,
          songCount: 0,
          discDuration: '',
          song: song
        })
      }
    }
    this.data = items
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener)
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener)
    if (index >= 0) {
      this.listeners.splice(index, 1)
    }
  }
}
