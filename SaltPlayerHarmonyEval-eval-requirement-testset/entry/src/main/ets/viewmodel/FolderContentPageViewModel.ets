// FolderContentPageViewModel.ets
// ViewModel layer: manages state and business logic for FolderContentPage (View).
// Bridges the Model layer (FolderContentPageModel) with the View layer.
//
// MVVM Architecture:
//   View: FolderContentPage - pure UI rendering and user interaction
//   ViewModel: FolderContentPageViewModel (this file) - observable state, business logic
//   Model: FolderContentPageModel - raw data structures and data access
//
// The ViewModel exposes @Track-decorated properties that the View binds to.
// The View calls ViewModel methods to handle user actions; the ViewModel
// updates its state and the View automatically re-renders.

import { SongInfoData, createDefaultSongInfoData } from '../model/SongItemModel'
import { SongLazySort } from '../model/SongSortModel'
import AudioPlayerService from '../model/AudioPlayerService'
import { MusicDatabase } from '../model/MusicDatabase'
import SongLazyDataSource from '../model/SongLazyDataSource'

import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'

import {
  FolderContentParams,
  MultiChoiceAction,
  FolderSongDisplaySettings,
  FolderContentDataSource
} from '../model/FolderContentPageModel'
import SettingsStore from '../model/SettingsStore'

@Observed
export default class FolderContentPageViewModel {
  // ==================== Folder Info ====================
  @Track public folderPath: string = ''
  @Track public folderName: string = ''
  // ==================== Song List ====================
  private unsortedSongList: SongInfoData[] = []
  @Track public songList: SongInfoData[] = []
  @Track public songDataSource: SongLazyDataSource = new SongLazyDataSource()
  // ==================== Current Playing Song ====================
  @Track public currentSongId: string = '1'
  // ==================== Multi-Choice Mode ====================
  @Track public multiChoiceMode: boolean = false
  @Track public checkedMap: Record<string, boolean> = {}
  @Track public checkedCount: number = 0
  // Parallel pick-order list for spec5 S6 (multi-select add-to-playlist
  // preserves pick order). See MainPageViewModel.checkedOrder for rationale.
  @Track public checkedOrder: string[] = []
  // ==================== Sort State ====================
  @Track public songLazySort: number = (AppStorage.get<number>('folderSongLazySort') ?? SongLazySort.TITLE)
  @Track public showRightABC: boolean = SongLazySort.shouldShowRightABC(AppStorage.get<number>('folderSongLazySort') ?? SongLazySort.TITLE)
  // ==================== Display Settings ====================
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)
  // ==================== Dialog Visibility ====================
  @Track public showSortDialog: boolean = false
  @Track public showSongMenu: boolean = false
  // ==================== Song Menu Target ====================
  @Track public songMenuTarget: SongInfoData = createDefaultSongInfoData()

  // ==================== Initialization ====================

  // Initialize from navigation params
  initFromParams(params: FolderContentParams): void {
    this.folderPath = params.folderPath || ''
    this.folderName = params.folderName || ''
  }

  // Load songs for the current folder from the Model layer
  loadSongs(): void {
    this.unsortedSongList = FolderContentDataSource.loadSongsForFolder(this.folderPath)
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
  }

  // ==================== Song Playback ====================

  // Play a song from the list
  playSong(song: SongInfoData): void {
    this.currentSongId = song.id
    // Build queue from all folder songs
    const queue: QueueSongModel[] = this.songList.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === song.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Check if a given song is the currently playing song
  isCurrentSong(songId: string): boolean {
    return songId === this.currentSongId
  }

  // Shuffle play all songs
  randomPlayAll(): void {
    if (this.songList.length === 0) {
      return
    }
    const queue: QueueSongModel[] = this.songList.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const randomIndex = Math.floor(Math.random() * this.songList.length)
    const picked = this.songList[randomIndex]
    this.currentSongId = picked.id
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(PlayModeConstants.RANDOM)
    service.setQueue(queue, randomIndex)
  }

  // ==================== Song Menu ====================

  // Open the song menu dialog for a specific song
  openSongMenu(song: SongInfoData): void {
    this.songMenuTarget = song
    this.showSongMenu = true
  }

  // Close the song menu dialog
  closeSongMenu(): void {
    this.showSongMenu = false
  }

  // ==================== Sort ====================

  // Open the sort dialog
  openSortDialog(): void {
    this.showSortDialog = true
  }

  // Close the sort dialog
  closeSortDialog(): void {
    this.showSortDialog = false
  }

  // Change the sort type and update Right ABC visibility
  changeSortType(sort: number): void {
    this.songLazySort = sort
    this.showRightABC = FolderContentDataSource.shouldShowRightABC(sort)
    SettingsStore.getInstance().save('folderSongLazySort', sort)
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, sort)
    this.songDataSource.reload(this.songList)
  }

  // Update a display setting
  updateDisplaySetting(key: string, value: boolean): void {
    if (key === 'displaySongCoverInList') {
      this.displaySongCoverInList = value
    } else if (key === 'displaySongFileNameInList') {
      this.displaySongFileNameInList = value
    } else if (key === 'displayAddToPlayNextInList') {
      this.displayAddToPlayNextInList = value
    }
  }

  // Forward AppStorage 'displaySongCover' writes from the Page-layer bridge
  // (@StorageProp('displaySongCover') @Watch(handler) -> handler calls this).
  // Mounted lists re-render via @Track when this field flips.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the folder song list re-renders when the user toggles
  // the setting elsewhere. LazyForEach rebuilds each SongItemViewModel on
  // every render with options.displayFileName sourced from this @Track field.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the folder song list re-renders when the user toggles
  // the setting. LazyForEach rebuilds each SongItemViewModel on every render
  // with options.displayAddToPlayNext sourced from this @Track field.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }

  // ==================== Multi-Choice Mode ====================
  // Throttle guard: prevents rapid enter/exit toggling from queuing overlapping
  // render cycles (each toggle re-creates SongItemViewModel for all visible items).
  private multiChoiceToggleTime: number = 0
  private static readonly MULTI_CHOICE_THROTTLE_MS: number = 300

  // Enter multi-choice mode
  enterMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < FolderContentPageViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = true
  }

  // Exit multi-choice mode and clear selection
  exitMultiChoiceMode(): void {
    const now = Date.now()
    if (now - this.multiChoiceToggleTime < FolderContentPageViewModel.MULTI_CHOICE_THROTTLE_MS) {
      return
    }
    this.multiChoiceToggleTime = now
    this.multiChoiceMode = false
    this.checkedMap = {}
    this.checkedCount = 0
    this.checkedOrder = []
  }

  // Toggle the checked state of a song
  toggleSongChecked(songId: string, checked: boolean): void {
    const newMap: Record<string, boolean> = {}
    const keys = Object.keys(this.checkedMap)
    for (const key of keys) {
      newMap[key] = this.checkedMap[key]
    }
    newMap[songId] = checked
    this.checkedMap = newMap
    // Keep checkedOrder in sync with the membership change.
    if (checked) {
      if (this.checkedOrder.indexOf(songId) < 0) {
        this.checkedOrder = this.checkedOrder.concat([songId])
      }
    } else {
      this.checkedOrder = this.checkedOrder.filter((id: string) => id !== songId)
    }
    this.checkedCount = FolderContentDataSource.countChecked(this.checkedMap)
  }

  // Select all songs
  selectAllSongs(): void {
    const newMap: Record<string, boolean> = {}
    const newOrder: string[] = []
    this.songList.forEach((song: SongInfoData) => {
      newMap[song.id] = true
      newOrder.push(song.id)
    })
    this.checkedMap = newMap
    this.checkedOrder = newOrder
    this.checkedCount = this.songList.length
  }

  // Deselect all songs
  deselectAllSongs(): void {
    this.checkedMap = {}
    this.checkedOrder = []
    this.checkedCount = 0
  }

  // Return the pick-order snapshot for multi-select add-to-playlist. See
  // MainPageViewModel.getSelectedSongIdsInOrder for rationale.
  getSelectedSongIdsInOrder(): string[] {
    return this.checkedOrder.filter((id: string) => this.checkedMap[id] === true).slice()
  }

  // Toggle select all / deselect all
  toggleSelectAll(): void {
    if (this.isAllSelected()) {
      this.deselectAllSongs()
    } else {
      this.selectAllSongs()
    }
  }

  // Check if all songs are selected
  isAllSelected(): boolean {
    return this.checkedCount === this.songList.length
  }

  // Get the select all / deselect all button label
  getSelectAllLabel(): string {
    return this.isAllSelected() ? '\u53D6\u6D88\u5168\u9009' : '\u5168\u9009'
  }

  // Get the checked count display text
  getCheckedCountText(): string {
    return `\u5DF2\u9009\u4E2D ${this.checkedCount} \u9879`
  }

  // Whether multi-choice actions are enabled (at least one selected)
  isMultiChoiceActionEnabled(): boolean {
    return this.checkedCount > 0
  }

  // Handle multi-choice action
  handleMultiChoiceAction(action: MultiChoiceAction): void {
    if (this.checkedCount <= 0) {
      return
    }
    switch (action) {
      case MultiChoiceAction.REMOVE_FROM_LIBRARY:
        break
      case MultiChoiceAction.ADD_TO_PLAYLIST:
        // TODO: Implement add to playlist dialog
        console.info('TODO: add to playlist - not yet implemented')
        break
      case MultiChoiceAction.PLAY_SELECTED_QUEUE:
        this.playSelectedQueue()
        break
    }
  }

  async removeSelectedFromLibrary(): Promise<void> {
    const checkedIds = Object.keys(this.checkedMap).filter((key: string) => this.checkedMap[key])
    if (checkedIds.length === 0) return
    // O(1) id→song lookup via Map — see MainPageViewModel.removeSelectedFromLibrary
    // for the rationale (eliminates the O(N²) for/find that dominated the click-handler stall).
    const idToSong = new Map<string, SongInfoData>()
    for (const s of this.unsortedSongList) {
      idToSong.set(s.id, s)
    }
    const paths: string[] = []
    const fileUris: string[] = []
    for (const id of checkedIds) {
      const song = idToSong.get(id)
      if (!song) continue
      if (song.path && song.path.length > 0) paths.push(song.path)
      if (song.fileUri && song.fileUri.length > 0) fileUris.push(song.fileUri)
    }
    await MusicDatabase.deleteTracksByPaths(paths)
    const checkedSet = new Set(checkedIds)
    this.unsortedSongList = this.unsortedSongList.filter((s: SongInfoData) => !checkedSet.has(s.id))
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
    this.exitMultiChoiceMode()
    await MusicDatabase.handleSongsRemovedFromLibrary(checkedIds, fileUris)
  }

  removeSongFromListById(songId: string): void {
    this.unsortedSongList = this.unsortedSongList.filter((s: SongInfoData) => s.id !== songId)
    this.songList = SongLazySort.sortSongs(this.unsortedSongList, this.songLazySort)
    this.songDataSource.reload(this.songList)
  }

  // Play selected songs as a new queue
  playSelectedQueue(): void {
    const selected = this.songList.filter((song: SongInfoData) => this.checkedMap[song.id] === true)
    if (selected.length === 0) {
      return
    }
    const queue: QueueSongModel[] = selected.map((song: SongInfoData): QueueSongModel => {
      return new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
        song.fileUri ?? '', song.coverUri)
    })
    const first = selected[0]
    this.currentSongId = first.id
    AudioPlayerService.getInstance().setQueue(queue, 0)
    this.exitMultiChoiceMode()

  }

  // ==================== Scroll Logic ====================

  // Get the index to scroll to for a given character (pinyin-based)
  getScrollIndexForChar(char: string): number {
    if (char === '0') {
      return 0
    }
    const targetChar = char.toUpperCase()
    return this.songList.findIndex((song: SongInfoData) => {
      const sortKey = SongLazySort.getSortKey(song, this.songLazySort)
      const initial = SongLazySort.getPinyinInitial(sortKey)
      if (targetChar === '#') {
        return initial === '#'
      }
      return initial === targetChar
    })
  }

  // Find the index of the currently playing song in the song list
  findCurrentSongIndex(): number {
    return FolderContentDataSource.findSongIndex(this.songList, this.currentSongId)
  }

  // ==================== Song Count ====================

  // Get the number of songs
  getSongCount(): number {
    return this.songList.length
  }

  // Get song count as display string
  getSongCountText(): string {
    return this.songList.length.toString()
  }

  // Whether the song list is empty
  isSongListEmpty(): boolean {
    return this.songList.length === 0
  }

  // Whether to show the right ABC index
  shouldShowRightABC(): boolean {
    return this.showRightABC && !this.isSongListEmpty()
  }

  // Whether to show the locate current song button
  shouldShowLocateButton(): boolean {
    return !this.isSongListEmpty() && !this.multiChoiceMode
  }
}

对文件夹内歌曲名做大小写不敏感的关键词过滤，空关键词返回全部。
function searchFolderSongsD(songs: string[], keyword: string): string[] {
  const query = keyword.trim().toLowerCase();
  if (query.length === 0) {
    return songs.slice(0);
  }
  const matched: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const name = songs[i].toLowerCase();
    if (name.indexOf(query) >= 0) {
      matched.push(songs[i]);
    }
  }
  return matched;
}

将驼峰命名字符串转换为短横线连接的形式。
function camelToKebabD(input: string): string {
  let result = '';
  for (let i = 0; i < input.length; i++) {
    const ch = input.charAt(i);
    const lower = ch.toLowerCase();
    if (ch !== lower && i > 0) {
      result = result + '-';
    }
    result = result + lower;
  }
  return result;
}

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H39(trackArtists: string[]): Array<{ name: string; count: number }> {
  const tally = new Map<string, number>();
  for (const raw of trackArtists) {
    const name = raw.trim();
    if (name.length === 0) continue;
    tally.set(name, (tally.get(name) ?? 0) + 1);
  }
  const result: Array<{ name: string; count: number }> = [];
  tally.forEach((count, name) => result.push({ name, count }));
  result.sort((a, b) => b.count - a.count || a.name.localeCompare(b.name));
  return result;
}

对整型数组做去重并保持原有顺序。
function dedupeIntArrayD_H39(values: number[]): number[] {
  const seen = new Set<number>();
  const result: number[] = [];
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (!seen.has(v)) {
      seen.add(v);
      result.push(v);
    }
  }
  return result;
}

在有序数组中用二分查找定位目标值的下标。
function binarySearchIndexD_H39(sorted: number[], target: number): number {
  let low = 0;
  let high = sorted.length - 1;
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    if (sorted[mid] === target) {
      return mid;
    }
    if (sorted[mid] < target) {
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return -1;
}

对文件夹内歌曲名做大小写不敏感的关键词过滤，空关键词返回全部。
function searchFolderSongsD_H39(songs: string[], keyword: string): string[] {
  const query = keyword.trim().toLowerCase();
  if (query.length === 0) {
    return songs.slice(0);
  }
  const matched: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    const name = songs[i].toLowerCase();
    if (name.indexOf(query) >= 0) {
      matched.push(songs[i]);
    }
  }
  return matched;
}

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC_H39(durations: number[]): string {
  const count = durations.length;
  let totalSec = 0;
  for (const d of durations) {
    if (d > 0) totalSec += d;
  }
  const minutes = Math.floor(totalSec / 60);
  const seconds = totalSec % 60;
  const ss = seconds < 10 ? '0' + seconds : String(seconds);
  return count + ' 首歌曲 · ' + minutes + ':' + ss;
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H39(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
  const copy = tracks.slice();
  copy.sort((a, b) => {
    if (a.disc !== b.disc) {
      return a.disc - b.disc;
    }
    if (a.track !== b.track) {
      return a.track - b.track;
    }
    return a.title.localeCompare(b.title);
  });
  return copy;
}
