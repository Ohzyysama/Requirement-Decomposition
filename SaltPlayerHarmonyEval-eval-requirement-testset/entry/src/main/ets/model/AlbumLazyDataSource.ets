// AlbumLazyDataSource.ets
// IDataSource implementations for LazyForEach in album list.
// AlbumLazyDataSource: wraps AlbumInfoData[] for Grid mode (title/count sort).
// AlbumYearLazyDataSource: wraps a flattened year-header + album list for year-sorted List mode.

import { AlbumInfoData } from './MainPageModel'

export default class AlbumLazyDataSource implements IDataSource {
  private data: AlbumInfoData[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): AlbumInfoData {
    return this.data[index]
  }

  getAll(): AlbumInfoData[] {
    return this.data
  }

  reload(newData: AlbumInfoData[]): void {
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

// Flat item for year-sorted lazy list: either a year header or an album entry
export interface AlbumYearFlatItem {
  isHeader: boolean
  year: string
  album: AlbumInfoData | undefined
}

export class AlbumYearLazyDataSource implements IDataSource {
  private data: AlbumYearFlatItem[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): AlbumYearFlatItem {
    return this.data[index]
  }

  // Build flattened list from year-grouped map
  reloadFromMap(map: Map<string, AlbumInfoData[]>): void {
    const items: AlbumYearFlatItem[] = []
    map.forEach((albums: AlbumInfoData[], year: string) => {
      items.push({ isHeader: true, year: year, album: undefined })
      for (const album of albums) {
        items.push({ isHeader: false, year: year, album: album })
      }
    })
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
