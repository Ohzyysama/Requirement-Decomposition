// ArtistContentLazyDataSource.ets
// IDataSource implementations for LazyForEach in ArtistContentPage.
// ArtistSongLazyDataSource: wraps SongItemViewModel[] for the song list.
// ArtistAlbumLazyDataSource: wraps AlbumItemViewModel[] for the album list.

import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import { AlbumItemViewModel } from '../viewmodel/ArtistContentViewModel'

export class ArtistSongLazyDataSource implements IDataSource {
  private data: SongItemViewModel[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): SongItemViewModel {
    return this.data[index]
  }

  getAll(): SongItemViewModel[] {
    return this.data
  }

  reload(newData: SongItemViewModel[]): void {
    this.data = newData
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

export class ArtistAlbumLazyDataSource implements IDataSource {
  private data: AlbumItemViewModel[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): AlbumItemViewModel {
    return this.data[index]
  }

  getAll(): AlbumItemViewModel[] {
    return this.data
  }

  reload(newData: AlbumItemViewModel[]): void {
    this.data = newData
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
