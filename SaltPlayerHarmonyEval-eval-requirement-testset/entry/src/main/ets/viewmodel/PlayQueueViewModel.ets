// PlayQueueViewModel.ets
// ViewModel layer: provides data and logic for PlayQueueComponent (View).
// Bridges the Model layer (PlayQueueModel) with the View layer, exposing
// state variables and methods for queue display, song interaction, and play mode.

import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import ClearPlayQueueDialogViewModel from './ClearPlayQueueDialogViewModel'
import PlayQueueLazyDataSource from '../model/PlayQueueLazyDataSource'
import { image } from '@kit.ImageKit'

// Observable ViewModel for a single song item in the queue
@Observed
export class QueueSongItemViewModel {
  @Track public id: string = ''
  @Track public title: string = ''
  @Track public artist: string = ''
  @Track public album: string = ''
  @Track public subTitle: string = ''

  constructor(id: string = '', title: string = '', artist: string = '',
    album: string = '', subTitle: string = '') {
    this.id = id
    this.title = title
    this.artist = artist
    this.album = album
    this.subTitle = subTitle
  }

  // Load data from Model
  updateFromModel(model: QueueSongModel): void {
    this.id = model.id
    this.title = model.title
    this.artist = model.artist
    this.album = model.album
    this.subTitle = model.subTitle
  }

  // Export current state back to Model
  toModel(): QueueSongModel {
    return new QueueSongModel(this.id, this.title, this.artist, this.album, this.subTitle)
  }
}

// Main ViewModel for the PlayQueueComponent
@Observed
export default class PlayQueueViewModel {
  // Queue song items for display, backed by a LazyDataSource so the View
  // can render with LazyForEach and avoid materializing 1000+ ListItems.
  public songs: PlayQueueLazyDataSource = new PlayQueueLazyDataSource()

  // Current song information
  @Track public currentSongId: string = ''
  @Track public currentSongTitle: string = ''
  @Track public currentSongArtist: string = ''
  @Track public coverPixelMap: image.PixelMap | undefined = undefined

  // Queue index display text (e.g. "1 / 12")
  @Track public queueIndex: string = '1 / 1'

  // Current play mode
  @Track public playMode: string = PlayModeConstants.RANDOM

  // Whether the pager is currently being dragged (disables list scroll)
  @Track public pagerDragging: boolean = false

  // Flowing light state — when active, queue uses transparent background and dynamic foreground color
  @Track public flowingLightActive: boolean = false
  @Track public foregroundColor: string = ''
  @Track public isLightMode: boolean = true
  // Color filter matrix for tinting SVG icons in queue (synced from PlayerPageViewModel)
  @Track public iconColorFilter: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]

  // Pressed song id for highlight effect (View-only auxiliary state)
  @Track public pressedSongId: string = ''

  // ClearPlayQueueDialog ViewModel
  @Track public clearDialogViewModel: ClearPlayQueueDialogViewModel = new ClearPlayQueueDialogViewModel()

  // Callbacks to delegate actions to the parent/service layer
  @Track public onSongClickAction: (songId: string) => void = () => {}
  @Track public onRemoveSongAction: (songId: string) => void = () => {}
  @Track public onClearQueueAction: () => void = () => {}
  @Track public onPlayModeClickAction: () => void = () => {}
  @Track public onDismissAction: () => void = () => {}
  @Track public onListAtTopAction: (atTop: boolean) => void = () => {}
  // Notifies when a touch starts/ends inside the queue song list (used by
  // the parent pager to decide whether a swipe-down should dismiss the page)
  @Track public onListTouchAction: (inList: boolean) => void = () => {}
  // Callback wired by the View to scroll the list to the current song
  public onScrollToCurrentSongAction: () => void = () => {}

  constructor() {
    // Wire up clear dialog confirm to clear queue action
    this.clearDialogViewModel.onConfirmAction = () => {
      this.onClearQueueAction()
    }
  }

  // Load songs from Model array
  loadSongs(models: QueueSongModel[]): void {
    const items: QueueSongItemViewModel[] = []
    for (const model of models) {
      const item = new QueueSongItemViewModel()
      item.updateFromModel(model)
      items.push(item)
    }
    this.songs.reload(items)
  }

  // Update songs from QueueSongInfo-compatible data (for backward compatibility with PlayerPage)
  updateSongs(songDataList: QueueSongModel[]): void {
    this.loadSongs(songDataList)
  }

  // Handle song item click
  handleSongClick(songId: string): void {
    this.onSongClickAction(songId)
  }

  // Handle remove song from queue
  handleRemoveSong(songId: string): void {
    this.onRemoveSongAction(songId)
  }

  // Remove a single song by id. The DataSource emits onDataDelete so
  // LazyForEach removes only the affected item without rebuilding the list.
  removeSong(songId: string): void {
    this.songs.removeById(songId)
  }

  // Clear the entire queue in one batched notification — avoids the
  // O(n) cost of destroying 1000+ ListItem components individually.
  clearSongs(): void {
    this.songs.clear()
  }

  // Handle dismiss (swipe down to return to player)
  handleDismiss(): void {
    this.onDismissAction()
  }

  // Handle play mode chip click
  handlePlayModeClick(): void {
    this.onPlayModeClickAction()
  }

  // Handle list scroll position changes
  handleListAtTop(atTop: boolean): void {
    this.onListAtTopAction(atTop)
  }

  // Handle touch inside / leaving the queue song list
  handleListTouch(inList: boolean): void {
    this.onListTouchAction(inList)
  }

  // Handle song item press state for highlight effect
  handleSongPress(songId: string): void {
    this.pressedSongId = songId
  }

  // Handle song item release state
  handleSongRelease(): void {
    this.pressedSongId = ''
  }

  // Get play mode display text
  getPlayModeText(): string {
    switch (this.playMode) {
      case PlayModeConstants.CIRCLE:
        return '列表循环播放模式'
      case PlayModeConstants.REPEAT_ONE:
        return '单曲循环播放模式'
      case PlayModeConstants.RANDOM:
      default:
        return '随机播放模式'
    }
  }

  // Check if a song is the currently playing song
  isCurrentSong(songId: string): boolean {
    return songId === this.currentSongId
  }

  // Check if a song is currently pressed
  isPressedSong(songId: string): boolean {
    return songId === this.pressedSongId
  }

  // Check if a song should be highlighted (current or pressed)
  shouldHighlightSong(songId: string): boolean {
    return this.isCurrentSong(songId) || this.isPressedSong(songId)
  }

  // Get the index of the currently playing song within the songs array.
  // Returns -1 if the current song is not present in the queue.
  getCurrentSongIndex(): number {
    if (this.currentSongId.length === 0) {
      return -1
    }
    return this.songs.indexOfId(this.currentSongId)
  }

  // Request the View to scroll the list to the currently playing song.
  // No-op if the View hasn't wired up onScrollToCurrentSongAction yet.
  scrollToCurrentSong(): void {
    this.onScrollToCurrentSongAction()
  }

  // Get the current song subtitle display text
  getCurrentSongSubtitle(): string {
    return this.currentSongArtist + ' - ' + this.currentSongTitle
  }
}
