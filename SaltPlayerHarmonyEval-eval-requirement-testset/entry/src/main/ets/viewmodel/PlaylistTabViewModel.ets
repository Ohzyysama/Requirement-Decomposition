// PlaylistTabViewModel.ets
// ViewModel layer: provides data and logic for PlaylistTabComponent (View).
// Bridges the Model layer (PlaylistModel) with the View layer, exposing
// state variables and methods for playlist list display, menu operations,
// edit dialog, and delete dialog.

import PlaylistModel, { PlaylistDataSource } from '../model/PlaylistModel'

// Observable array type for PlaylistItemViewModel, enabling ForEach to detect changes
@Observed
export class PlaylistItemViewModelArray extends Array<PlaylistItemViewModel> {
}

// ViewModel for a single playlist item displayed in the list
@Observed
export class PlaylistItemViewModel {
  @Track public id: string = ''
  @Track public name: string = ''
  @Track public count: number = 0
  // Song id to source the cover from (most recently added song; matches the
  // top row of the playlist detail page under PLAYLIST_ADD_TIME sort). The
  // view looks this id up in CoverCacheDb to lazy-load the JPEG.
  @Track public coverSongId: string = ''

  constructor(id: string = '', name: string = '', count: number = 0, coverSongId: string = '') {
    this.id = id
    this.name = name
    this.count = count
    this.coverSongId = coverSongId
  }

  // Load data from Model
  updateFromModel(model: PlaylistModel): void {
    this.id = model.id
    this.name = model.name
    this.count = model.count
    this.coverSongId = model.coverSongId
  }

  // Export current state back to Model
  toModel(): PlaylistModel {
    return new PlaylistModel(this.id, this.name, this.count, this.coverSongId)
  }

  // Whether this item has a song to source a cover from. The actual JPEG may
  // still be missing from CoverCacheDb at render time; ImageKnife shows the
  // placeholder in that case and swaps once the cover file is ensured.
  hasCover(): boolean {
    return this.coverSongId.length > 0
  }

  // Get display text for song count
  getSongCountText(): string {
    return `${this.count} \u9996`
  }
}

// Main ViewModel for the PlaylistTab component
@Observed
export default class PlaylistTabViewModel {
  // Playlist items data
  @Track public playlistItems: PlaylistItemViewModelArray = new PlaylistItemViewModelArray()

  // Playlist item menu dialog state
  @Track public showPlaylistMenu: boolean = false
  @Track public menuTargetPlaylist: PlaylistItemViewModel = new PlaylistItemViewModel()

  // Edit name dialog state
  @Track public showEditDialog: boolean = false
  @Track public editPlaylistName: string = ''

  // Delete confirmation dialog state
  @Track public showDeleteDialog: boolean = false

  // Callbacks for parent component interaction
  @Track public onPlaylistClickAction: (playlistId: string) => void = () => {
  }
  @Track public onNewPlaylistAction: (name: string) => void = () => {
  }
  @Track public onImportPlaylistAction: () => void = () => {
  }
  @Track public onUpdatePlaylistNameAction: (playlistId: string, newName: string) => void = () => {
  }
  @Track public onDeletePlaylistAction: (playlistId: string) => void = () => {
  }
  @Track public onExportPlaylistAction: (playlistId: string) => void = () => {
  }

  constructor() {
  }

  // Load playlist list from Model array
  loadPlaylists(models: PlaylistModel[]): void {
    this.playlistItems = new PlaylistItemViewModelArray()
    for (const model of models) {
      const item = new PlaylistItemViewModel()
      item.updateFromModel(model)
      this.playlistItems.push(item)
    }
  }

  // Check if the playlist list is empty
  isEmpty(): boolean {
    return this.playlistItems.length === 0
  }

  // --- Menu operations ---

  // Open the playlist item menu for a specific playlist
  openPlaylistMenu(playlist: PlaylistItemViewModel): void {
    this.menuTargetPlaylist = playlist
    this.showPlaylistMenu = true
  }

  // Close the playlist item menu
  closePlaylistMenu(): void {
    this.showPlaylistMenu = false
  }

  // --- Edit name dialog operations ---

  // Open the edit name dialog with the current target playlist name
  openEditDialog(): void {
    this.showPlaylistMenu = false
    this.editPlaylistName = this.menuTargetPlaylist.name
    this.showEditDialog = true
  }

  // Update the edit playlist name as user types
  updateEditPlaylistName(value: string): void {
    this.editPlaylistName = value
  }

  // Forward the raw (untrimmed) name to the host so it can run validation and
  // toast for Scenarios 1/2. Always flip showEditDialog so the VM state mirrors
  // the actual UI (EditPlaylistDialog's Confirm already closes the dialog in
  // the View layer). The DB write + list refresh run in the host callback —
  // mirrors the NewPlaylist path.
  handleConfirmEdit(): void {
    this.onUpdatePlaylistNameAction(this.menuTargetPlaylist.id, this.editPlaylistName)
    this.showEditDialog = false
  }

  // Close the edit dialog
  closeEditDialog(): void {
    this.showEditDialog = false
  }

  // --- Delete dialog operations ---

  // Open the delete confirmation dialog
  openDeleteDialog(): void {
    this.showPlaylistMenu = false
    this.showDeleteDialog = true
  }

  // Forward the delete request to the host (MainPageViewModel) so the DB write
  // + list refresh live on a single seam. Always flip showDeleteDialog so the
  // VM state mirrors the actual UI (DeletePlaylistDialog's Confirm already
  // closes the dialog in the View layer). Spec18 scenario 2 (cancel) is
  // handled in the View layer and never reaches this VM method.
  handleConfirmDelete(): void {
    this.onDeletePlaylistAction(this.menuTargetPlaylist.id)
    this.showDeleteDialog = false
  }

  // Close the delete dialog
  closeDeleteDialog(): void {
    this.showDeleteDialog = false
  }

  // --- Export operation ---

  // Handle export: delegate to Model layer
  handleExport(): void {
    this.showPlaylistMenu = false
    PlaylistDataSource.exportPlaylist(this.menuTargetPlaylist.id)
    this.onExportPlaylistAction(this.menuTargetPlaylist.id)
  }

  // --- Click operation ---

  // Handle playlist item click
  handlePlaylistClick(playlistId: string): void {
    this.onPlaylistClickAction(playlistId)
  }

  // Reorder the playlist list — used by the playlist tab's drag-reorder gesture
  // (long-press + pan). Reassigns `playlistItems` so @Track picks up the change,
  // then fire-and-forget persists the new 0..n-1 playlistOrder indexes so the
  // next loadPlaylistsFromDb() returns rows in this sequence (mirrors Android
  // PlaylistViewModel.reorder → saveIndex).
  movePlaylist(fromIndex: number, toIndex: number): void {
    const items = this.playlistItems
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 ||
      fromIndex >= items.length || toIndex >= items.length) {
      return
    }
    const reordered: PlaylistItemViewModel[] = []
    for (let i = 0; i < items.length; i++) {
      reordered.push(items[i])
    }
    const moved: PlaylistItemViewModel[] = reordered.splice(fromIndex, 1)
    reordered.splice(toIndex, 0, moved[0])

    const next = new PlaylistItemViewModelArray()
    for (const r of reordered) {
      next.push(r)
    }
    this.playlistItems = next

    const orderedIds: string[] = []
    for (const r of reordered) orderedIds.push(r.id)
    PlaylistDataSource.reorderPlaylists(orderedIds).catch((e: Error) => {
      console.warn(`PlaylistTabViewModel.movePlaylist persist failed: ${e.message}`)
    })
  }
}

// 创建歌单入口：createPlaylist 在写库前再次校验歌单名非空并去重。

// 歌单管理：renamePlaylist 与 deletePlaylist 更新列表并持久化排序。

// 歌单排序：拖动调整歌单顺序并持久化。
