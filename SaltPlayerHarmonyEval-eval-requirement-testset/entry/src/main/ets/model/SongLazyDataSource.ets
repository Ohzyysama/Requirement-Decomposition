// SongLazyDataSource.ets
// IDataSource implementation for LazyForEach in MainPage song list.
// Wraps a SongInfoData[] array and notifies the framework when data changes,
// so only visible list items are rendered (lazy loading).

import { SongInfoData } from './SongItemModel'

export default class SongLazyDataSource implements IDataSource {
  private data: SongInfoData[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): SongInfoData {
    return this.data[index]
  }

  // Get underlying array (for ViewModel operations that need direct access)
  getAll(): SongInfoData[] {
    return this.data
  }

  // Replace entire dataset — used on sort, refresh, scan complete.
  // The corresponding LazyForEach keyGenerator embeds scanVersion so that
  // every refresh produces fresh keys and the framework rebuilds every
  // SongItemComponent — onDataReloaded alone is not enough because stable
  // song.id keys cause LazyForEach to reuse existing items even when the
  // underlying SongInfoData has been mutated (e.g. by a quality backfill).
  reload(newData: SongInfoData[]): void {
    this.data = newData
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  // Move an item from one index to another — used for drag reorder
  move(fromIndex: number, toIndex: number): void {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 ||
      fromIndex >= this.data.length || toIndex >= this.data.length) {
      return
    }
    const moved = this.data.splice(fromIndex, 1)
    this.data.splice(toIndex, 0, moved[0])
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataMove(fromIndex, toIndex)
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
