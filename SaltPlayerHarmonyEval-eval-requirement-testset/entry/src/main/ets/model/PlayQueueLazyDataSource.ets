// PlayQueueLazyDataSource.ets
// IDataSource implementation for LazyForEach in PlayQueueComponent.
// Wraps a QueueSongItemViewModel[] array so only visible list items are
// rendered, avoiding the O(n) destruction cost when clearing 1000+ items.

import { QueueSongItemViewModel } from '../viewmodel/PlayQueueViewModel'

export default class PlayQueueLazyDataSource implements IDataSource {
  private data: QueueSongItemViewModel[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): QueueSongItemViewModel {
    return this.data[index]
  }

  getAll(): QueueSongItemViewModel[] {
    return this.data
  }

  // Replace entire dataset — used on initial load, sort, queue rebuild
  reload(newData: QueueSongItemViewModel[]): void {
    this.data = newData
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  // Clear all items in one batched notification — much cheaper than
  // dispatching N onDataDelete calls or rebuilding via reload.
  clear(): void {
    if (this.data.length === 0) {
      return
    }
    this.data = []
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded()
    })
  }

  // Remove a single item by id; emits onDataDelete so the framework can
  // animate just the removed item without rebuilding the whole list.
  removeById(songId: string): void {
    let removedIndex = -1
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i].id === songId) {
        removedIndex = i
        break
      }
    }
    if (removedIndex < 0) {
      return
    }
    this.data.splice(removedIndex, 1)
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(removedIndex)
    })
  }

  indexOfId(songId: string): number {
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i].id === songId) {
        return i
      }
    }
    return -1
  }

  // Insert an item at a specific index; emits onDataAdd so LazyForEach
  // inserts a single ListItem without rebuilding the list.
  insertAt(index: number, item: QueueSongItemViewModel): void {
    const safeIndex = Math.max(0, Math.min(index, this.data.length))
    this.data.splice(safeIndex, 0, item)
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(safeIndex)
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
