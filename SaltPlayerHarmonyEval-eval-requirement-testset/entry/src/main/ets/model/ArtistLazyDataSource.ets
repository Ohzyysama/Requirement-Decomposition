// ArtistLazyDataSource.ets
// IDataSource implementation for LazyForEach in MainPage artist list.
// Wraps an ArtistItemViewModel[] array and notifies the framework when data changes,
// so only visible list items are rendered (lazy loading).

import { ArtistItemViewModel } from '../viewmodel/ArtistItemViewModel'

export default class ArtistLazyDataSource implements IDataSource {
  private data: ArtistItemViewModel[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): ArtistItemViewModel {
    return this.data[index]
  }

  getAll(): ArtistItemViewModel[] {
    return this.data
  }

  reload(newData: ArtistItemViewModel[]): void {
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
