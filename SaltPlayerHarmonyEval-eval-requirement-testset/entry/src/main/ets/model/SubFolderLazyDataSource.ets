// SubFolderLazyDataSource.ets
// IDataSource implementation for LazyForEach in FolderPathPage subfolder list.

import { SubFolderViewModel } from '../viewmodel/FolderPathViewModel'

export default class SubFolderLazyDataSource implements IDataSource {
  private data: SubFolderViewModel[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number {
    return this.data.length
  }

  getData(index: number): SubFolderViewModel {
    return this.data[index]
  }

  reload(newData: SubFolderViewModel[]): void {
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
