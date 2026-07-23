// AlbumContentViewModel.ets
// ViewModel layer: provides observable state and business logic for AlbumContentPage (View).
// Bridges AlbumContentModel (data) and AlbumContentPage (view).
// The View binds to this ViewModel's @Track properties for UI updates,
// and calls its methods for user interaction handling.

import { SongInfoData, createDefaultSongInfoData } from '../model/SongItemModel'
import AlbumContentLazyDataSource from '../model/AlbumContentLazyDataSource'
import AlbumContentModel, {
  AlbumContentRouterParams,
  DiscSongGroupData,
  AlbumDetailData,
  formatDurationMs
} from '../model/AlbumContentModel'
import { ArtistItemViewModel } from './ArtistItemViewModel'
import ArtistModel from '../model/ArtistModel'
import { shareSongFile } from '../model/ShareUtil'
import { Guqin } from '../model/Guqin'
import { common } from '@kit.AbilityKit'
import AudioPlayerService from '../model/AudioPlayerService'
import { QueueSongModel } from '../model/PlayQueueModel'

// @Observed array subclass for disc song groups — needed so ForEach can properly
// detect changes when the @Track property is reassigned (same pattern as
// SongItemViewModelArray in ArtistContentViewModel).
@Observed
export class DiscSongGroupArray extends Array<DiscSongGroupData> {
}

@Observed
export default class AlbumContentViewModel {
  // ===== Album metadata (from router params) =====
  @Track public albumId: string = ''
  @Track public albumTitle: string = ''
  @Track public albumArtist: string = ''
  @Track public albumCount: number = 0
  @Track public albumYear: number = 0
  @Track public albumCoverUri: string = ''
  @Track public albumDuration: string = ''
  @Track public albumHz: number = 0
  @Track public albumBits: number = 0
  @Track public albumIsHiRes: boolean = false
  @Track public albumCopyright: string = ''

  // ===== Song data =====
  @Track public discSongGroups: DiscSongGroupArray = new DiscSongGroupArray()
  @Track public songDataSource: AlbumContentLazyDataSource = new AlbumContentLazyDataSource()
  @Track public albumSongs: SongInfoData[] = []

  // ===== Participating artists =====
  @Track public participatingArtists: ArtistItemViewModel[] = []

  // ===== Current playing song id =====
  @Track public currentSongId: string = ''

  // spec21 — seeded from the persisted AppStorage key so the very first frame
  // reflects the user's choice. AlbumContentPage forwards live AppStorage
  // updates through setDisplaySongFileNameInList.
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)

  // spec22 — seeded from the persisted AppStorage key so the very first frame
  // reflects the user's choice. AlbumContentPage forwards live AppStorage
  // updates through setDisplayAddToPlayNextInList.
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // ===== Song menu dialog state =====
  @Track public showSongMenuDialog: boolean = false
  @Track public menuSong: SongInfoData = createDefaultSongInfoData()

  // ===== Title bar state =====
  @Track public showTitleInBar: boolean = false

  // ===== Computed display properties (must be @Track for UI usage) =====
  @Track public hasCoverUri: boolean = false
  @Track public hasTitle: boolean = false
  @Track public hasArtist: boolean = false
  @Track public hasCopyright: boolean = false
  @Track public hasParticipatingArtists: boolean = false
  @Track public songCountText: string = '0'
  @Track public yearText: string = '-'
  @Track public durationText: string = ''
  @Track public titleOpacity: number = 0.5
  @Track public artistOpacity: number = 0.5

  // ===== Private helper: update all computed properties =====
  private updateComputedProperties(): void {
    this.hasCoverUri = this.albumCoverUri.length > 0
    this.hasTitle = this.albumTitle.length > 0
    this.hasArtist = this.albumArtist.length > 0
    this.hasCopyright = this.albumCopyright.length > 0
    this.hasParticipatingArtists = this.participatingArtists.length > 0
    this.songCountText = this.albumCount.toString()
    this.yearText = this.albumYear === 0 ? '-' : this.albumYear.toString()
    this.durationText = this.albumDuration.length > 0 ? this.albumDuration : ''
    this.titleOpacity = this.albumTitle.length > 0 ? 1.0 : 0.5
    this.artistOpacity = this.albumArtist.length > 0 ? 1.0 : 0.5
  }

  // ===== Methods =====

  // Initialize from router params
  initFromParams(params: AlbumContentRouterParams): void {
    this.albumId = params.albumId ?? ''
    this.albumTitle = params.albumTitle ?? ''
    this.albumArtist = params.albumArtist ?? ''
    this.albumCount = params.albumCount ?? 0
    this.albumYear = params.albumYear ?? 0
    this.albumCoverUri = params.albumCoverUri ?? ''
    this.albumDuration = params.albumDuration ?? ''
    this.albumHz = params.albumHz ?? 0
    this.albumBits = params.albumBits ?? 0
    this.albumIsHiRes = params.albumIsHiRes ?? false
    this.albumCopyright = params.albumCopyright ?? ''
    // Restore current song id from AppStorage
    const persistedSongId = AppStorage.get('currentSongId') as string
    if (persistedSongId && persistedSongId.length > 0) {
      this.currentSongId = persistedSongId
    }
    this.updateComputedProperties()
  }

  // Load album songs, disc groups, and participating artists from Model
  loadAlbumData(): void {
    // Build params for Model query
    const params: AlbumContentRouterParams = {
      albumId: this.albumId,
      albumTitle: this.albumTitle,
      albumArtist: this.albumArtist,
      albumCount: this.albumCount,
      albumYear: this.albumYear,
      albumCoverUri: this.albumCoverUri,
      albumCoverSongId: '',
      albumDuration: this.albumDuration,
      albumHz: this.albumHz,
      albumBits: this.albumBits,
      albumIsHiRes: this.albumIsHiRes,
      albumCopyright: this.albumCopyright
    }

    // Fetch data from Model layer
    const detail: AlbumDetailData = AlbumContentModel.loadAlbumDetail(params)

    // Update ViewModel state
    this.albumSongs = detail.songs
    const groups = new DiscSongGroupArray()
    for (const g of detail.discGroups) {
      groups.push(g)
    }
    this.discSongGroups = groups
    this.songDataSource.reloadFromGroups(detail.discGroups)
    this.albumDuration = detail.totalDurationText

    // Convert Model artists to ViewModel artists
    this.participatingArtists = detail.artists.map((artist: ArtistModel) => {
      const vm = new ArtistItemViewModel(
        artist.id,
        artist.name,
        artist.count,
        artist.coverUri,
        artist.pinyin,
        artist.coverSongId
      )
      return vm
    })

    // Refresh computed properties after data load
    this.updateComputedProperties()
  }

  // Handle scroll offset change - show title in bar when scrolled past ~200vp
  updateScrollOffset(yOffset: number): void {
    this.showTitleInBar = yOffset > 200
  }

  // Open song menu for a specific song
  openSongMenu(song: SongInfoData): void {
    this.menuSong = song
    this.showSongMenuDialog = true
  }

  // Close song menu dialog
  closeSongMenu(): void {
    this.showSongMenuDialog = false
  }

  removeSongFromListById(songId: string): void {
    this.albumSongs = this.albumSongs.filter((s: SongInfoData) => s.id !== songId)
    // Build a new @Observed DiscSongGroupArray (same pattern as ArtistContentViewModel
    // creating new SongItemViewModelArray) so ForEach detects the change.
    const newGroups = new DiscSongGroupArray()
    for (const group of this.discSongGroups) {
      const filtered = group.songs.filter((s: SongInfoData) => s.id !== songId)
      if (filtered.length > 0) {
        // Recalculate disc duration from remaining songs
        let discDurationMs = 0
        for (const s of filtered) {
          discDurationMs += s.duration ?? 0
        }
        newGroups.push({ disc: group.disc, songs: filtered, discDuration: formatDurationMs(discDurationMs) })
      }
    }
    this.discSongGroups = newGroups
    this.songDataSource.reloadFromGroups(Array.from(newGroups))
    this.albumCount = this.albumSongs.length

    // Recalculate total album duration from remaining songs
    let totalDurationMs = 0
    for (const s of this.albumSongs) {
      totalDurationMs += s.duration ?? 0
    }
    this.albumDuration = formatDurationMs(totalDurationMs)

    // Update participating artists: remove artists that no longer have songs in this album
    const remainingArtistNames = new Set<string>()
    for (const s of this.albumSongs) {
      if (s.artist.length > 0) {
        const splitArtists = Guqin.getArtists(s.artist)
        for (const name of splitArtists) {
          remainingArtistNames.add(name)
        }
      }
    }
    this.participatingArtists = this.participatingArtists.filter(
      (a: ArtistItemViewModel) => remainingArtistNames.has(a.name)
    )

    this.updateComputedProperties()
  }

  // Handle play song action — update global playback state and build queue
  playSong(song: SongInfoData): void {
    this.currentSongId = song.id
    // Build queue from all album songs
    const queue: QueueSongModel[] = this.albumSongs.map((s: SongInfoData): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === song.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  // Handle add song to play next
  addToPlayNext(song: SongInfoData): void {
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Handle add to playlist
  addToPlaylist(): void {
    // TODO: Implement add to playlist logic
    console.info('TODO: Add to playlist')
  }

  // Handle play next from menu
  playNext(): void {
    this.addToPlayNext(this.menuSong)
  }

  // Handle share song
  shareSong(context: common.UIAbilityContext): void {
    shareSongFile(context, this.menuSong.title, this.menuSong.fileUri)
  }

  // Handle navigate to artist
  navigateToArtist(): void {
    // TODO: Navigate to artist page
    console.info('TODO: Navigate to artist')
  }

  // Handle show album cover big image
  showAlbumCoverBigImage(): void {
    // TODO: Show big image dialog
    console.info('TODO: Show album cover big image')
  }

  // Handle music tag edit
  editMusicTag(): void {
    // TODO: Open music tag editor
    console.info('TODO: Music tag edit')
  }

  // Handle Hearusy Spectrum
  openHearusySpectrum(): void {
    // TODO: Open Hearusy Spectrum
    console.info('TODO: Hearusy Spectrum')
  }

  // Handle Emo Scroll
  openEmoScroll(): void {
    // TODO: Open Emo Scroll
    console.info('TODO: Emo Scroll')
  }

  // Handle show song info
  showSongInfo(): void {
    // TODO: Show song info
    console.info('TODO: Song info')
  }

  // Handle copy text
  copyText(): void {
    // TODO: Copy song text
    console.info('TODO: Copy text')
  }

  // Check if a song is currently playing
  isSongCurrent(songId: string): boolean {
    return songId === this.currentSongId
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge so the album track list re-renders when the user toggles
  // the setting elsewhere. LazyForEach rebuilds each SongItemViewModel on
  // every render with options.displayFileName sourced from this @Track field,
  // so a simple reassignment is enough.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge so the album track list re-renders when the user toggles
  // the setting. LazyForEach rebuilds each SongItemViewModel on every render
  // with options.displayAddToPlayNext sourced from this @Track field, so a
  // simple reassignment is enough.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
  }
}

// 专辑详情：加载指定专辑的曲目并支持播放全部。

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC(durations: number[]): string {
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

统计文本中各单词出现次数
function countWordsC(text: string): Map<string, number> {
  const counts = new Map<string, number>();
  const words = text.toLowerCase().split(/\s+/).filter(w => w.length > 0);
  for (const w of words) {
    const prev = counts.get(w) ?? 0;
    counts.set(w, prev + 1);
  }
  return counts;
}

汇总专辑曲目数量与总时长并格式化为头部摘要文本
function summarizeAlbumHeaderC_H30(durations: number[]): string {
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

为迷你歌词选取当前行及其后一行作为两行预览窗口
function pickMiniLyricWindowC_H30(lines: string[], activeIndex: number): string[] {
  if (lines.length === 0) return ['', ''];
  let idx = activeIndex;
  if (idx < 0) idx = 0;
  if (idx > lines.length - 1) idx = lines.length - 1;
  const current = lines[idx];
  const next = idx + 1 < lines.length ? lines[idx + 1] : '';
  return [current, next];
}

将字体大小与模糊半径夹取到允许范围并规范对齐取值
function clampLyricsSettingsC_H30(fontSize: number, blurRadius: number, align: string): { fontSize: number; blurRadius: number; align: string } {
  const fs = Math.min(36, Math.max(12, Math.round(fontSize)));
  const blur = Math.min(20, Math.max(0, Math.round(blurRadius)));
  const allowed = ['left', 'center', 'right'];
  const safeAlign = allowed.indexOf(align) >= 0 ? align : 'center';
  return { fontSize: fs, blurRadius: blur, align: safeAlign };
}

构建单个艺术家列表项的展示数据：头像首字母、名称、歌曲数文案。
function buildArtistItemD_H30(name: string, cover: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const trimmed = name.trim();
  const display = trimmed.length === 0 ? '未知艺术家' : trimmed;
  const initial = display.charAt(0).toUpperCase();
  item.set('name', display);
  item.set('avatar', cover.length > 0 ? cover : initial);
  const count = songCount < 0 ? 0 : songCount;
  item.set('subtitle', count + ' 首歌曲');
  return item;
}

将扁平键值对按前缀分组为嵌套映射
function groupByPrefixC_H30(keys: string[], sep: string): Map<string, string[]> {
  const groups = new Map<string, string[]>();
  for (const key of keys) {
    const idx = key.indexOf(sep);
    const prefix = idx >= 0 ? key.slice(0, idx) : key;
    const bucket = groups.get(prefix) ?? [];
    bucket.push(key);
    groups.set(prefix, bucket);
  }
  return groups;
}

将驼峰命名拆分为以空格分隔的词序列
function splitCamelWordsC_H30(identifier: string): string[] {
  const words: string[] = [];
  let current = '';
  for (const ch of identifier) {
    if (ch >= 'A' && ch <= 'Z' && current.length > 0) {
      words.push(current);
      current = ch;
    } else {
      current += ch;
    }
  }
  if (current.length > 0) {
    words.push(current);
  }
  return words;
}
