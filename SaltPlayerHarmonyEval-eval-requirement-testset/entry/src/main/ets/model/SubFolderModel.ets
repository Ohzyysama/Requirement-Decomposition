// SubFolderModel.ets
// Model layer: Pure data structure for a subfolder item.
// Represents a filesystem directory that may contain music files.
// Used by FolderPathPage to display subfolder navigation items.

export interface SubFolderData {
  name: string
  path: string
}
