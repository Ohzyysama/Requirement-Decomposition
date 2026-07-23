// ArtistContentViewModel.ets
// ViewModel layer: manages all state and business logic for ArtistContentPage.
// Bridges Model (ArtistContentModel, SongItemModel, AlbumModel) with View (ArtistContentPage).
// Exposes observable state properties and action methods.

import ArtistContentModel, { AlbumInfoData } from '../model/ArtistContentModel'
import { SongInfoData, createDefaultSongInfoData } from '../model/SongItemModel'
import { SongItemViewModel } from './SongItemViewModel'
import AudioPlayerService from '../model/AudioPlayerService'
import { QueueSongModel, PlayModeConstants } from '../model/PlayQueueModel'
import { ArtistSongLazyDataSource, ArtistAlbumLazyDataSource } from '../model/ArtistContentLazyDataSource'
import { ImageKnifeOption } from '@ohos/imageknifepro'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'

// Observable array subclass for album view models (needed for @Observed nesting)
@Observed
export class AlbumItemViewModelArray extends Array<AlbumItemViewModel> {
}

// Observable array subclass for song item view models
@Observed
export class SongItemViewModelArray extends Array<SongItemViewModel> {
}

// ViewModel for a single album item displayed in the artist content page
@Observed
export class AlbumItemViewModel {
  @Track public id: string = ''
  @Track public title: string = ''
  @Track public albumArtist: string = ''
  @Track public count: number = 0
  @Track public year: number = 0
  @Track public coverUri: string = ''
  @Track public coverSongId: string = ''
  @Track public coverModified: number = 0
  @Track public pinyin: string = ''
  @Track public hasTitle: boolean = false
  @Track public hasAlbumArtist: boolean = false
  @Track public hasCoverUri: boolean = false
  @Track public titleOpacity: number = 0.35
  @Track public albumArtistOpacity: number = 0.35
  @Track public songCountText: string = '0 \u9996 '
  @Track public coverOption: ImageKnifeOption = new ImageKnifeOption()
  private loadedCoverKey: string = ''

  loadCoverIfNeeded(): void {
    const songId = this.coverSongId || this.id
    if (songId.length === 0) return
    if (songId === this.loadedCoverKey) return
    this.loadedCoverKey = songId

    const uri = CoverCacheDb.getCoverFileUri(songId)
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri
      return
    }

    const capturedKey = songId
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (this.loadedCoverKey !== capturedKey) return
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri
        return
      }
      return CoverArtExtractor.extractAndCache(songId, songId)
    }).then(() => {
      if (this.loadedCoverKey !== capturedKey) return
      const u = CoverCacheDb.getCoverFileUri(songId)
      if (u.length > 0) { this.coverOption.loadSrc = u }
    }).catch((_e: Error) => { /* swallow */ })
  }

  updateFromModel(data: AlbumInfoData): void {
    this.id = data.id
    this.title = data.title
    this.albumArtist = data.albumArtist
    this.count = data.count
    this.year = data.year
    this.coverUri = data.coverUri
    this.coverSongId = data.coverSongId ?? ''
    this.coverModified = data.coverModified
    this.pinyin = data.pinyin
    this.hasTitle = data.title.length > 0
    this.hasAlbumArtist = data.albumArtist.length > 0
    this.hasCoverUri = data.coverUri.length > 0
    this.titleOpacity = data.title.length > 0 ? 1.0 : 0.35
    this.albumArtistOpacity = data.albumArtist.length > 0 ? 1.0 : 0.35
    this.songCountText = `${data.count} \u9996 `
  }

  static create(data: AlbumInfoData): AlbumItemViewModel {
    const vm = new AlbumItemViewModel()
    vm.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    vm.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    vm.coverOption.objectFit = ImageFit.Cover
    vm.updateFromModel(data)
    return vm
  }
}

// Main ViewModel for the ArtistContentPage
@Observed
export default class ArtistContentViewModel {
  // Artist basic info
  @Track public artistId: string = ''
  @Track public artistName: string = ''
  @Track public artistCoverUri: string = ''

  // Derived display properties
  @Track public hasArtistName: boolean = false
  @Track public artistNameOpacity: number = 0.35
  @Track public hasArtistCoverUri: boolean = false
  @Track public songCountText: string = '0'
  @Track public artistGeometryImageKey: string = 'image-artist-unknown-artist'
  @Track public artistGeometryTextKey: string = 'text-artist-unknown-artist'

  // Song and album data (observable arrays)
  @Track public songs: SongItemViewModelArray = new SongItemViewModelArray()
  @Track public songDataSource: ArtistSongLazyDataSource = new ArtistSongLazyDataSource()
  @Track public albums: AlbumItemViewModelArray = new AlbumItemViewModelArray()
  @Track public albumDataSource: ArtistAlbumLazyDataSource = new ArtistAlbumLazyDataSource()

  // UI state
  @Track public isSongsCollapsed: boolean = false
  @Track public currentSongId: string = ''
  @Track public showTitleInBar: boolean = false

  // Global "show cover in song list" preference, seeded from AppStorage so
  // first-frame render reflects the persisted value. Pages forward live
  // AppStorage updates through setDisplaySongCoverInList.
  @Track public displaySongCoverInList: boolean = (AppStorage.get<boolean>('displaySongCover') ?? true)

  // spec21 — Global "在列表中显示歌曲文件名" preference, seeded from AppStorage
  // so the first frame after construction reflects the user's choice. Pages
  // forward live AppStorage updates through setDisplaySongFileNameInList.
  @Track public displaySongFileNameInList: boolean = (AppStorage.get<boolean>('displaySongFileName') ?? false)

  // spec22 — Global "在列表中显示添加下一首播放" preference, seeded from AppStorage
  // so the first frame after construction reflects the user's choice. Pages
  // forward live AppStorage updates through setDisplayAddToPlayNextInList.
  @Track public displayAddToPlayNextInList: boolean = (AppStorage.get<boolean>('displayAddToPlayNext') ?? true)

  // Song menu dialog state
  @Track public showSongMenu: boolean = false
  @Track public menuSongInfo: SongInfoData = createDefaultSongInfoData()

  // ---- Initialization ----

  // Initialize from router params
  initFromParams(params: Record<string, Object>): void {
    if (params['artistId']) {
      this.artistId = params['artistId'] as string
    }
    if (params['artistName']) {
      this.artistName = params['artistName'] as string
    }
    if (params['artistCoverUri']) {
      this.artistCoverUri = params['artistCoverUri'] as string
    }
    // Restore current song id from AppStorage
    const persistedSongId = AppStorage.get('currentSongId') as string
    if (persistedSongId && persistedSongId.length > 0) {
      this.currentSongId = persistedSongId
    }
    this.updateDerivedProperties()
  }

  // Load artist data from Model layer
  loadArtistData(): void {
    const data = ArtistContentModel.loadArtistContent(this.artistId, this.artistName)

    // Convert Model songs to SongItemViewModels
    const newSongs = new SongItemViewModelArray()
    for (const songData of data.songs) {
      const vm = new SongItemViewModel()
      vm.updateFromModel(songData)
      vm.showCover = this.displaySongCoverInList
      vm.displayFileName = this.displaySongFileNameInList
      vm.displayAddToPlayNext = this.displayAddToPlayNextInList
      vm.isCurrent = songData.id === this.currentSongId
      newSongs.push(vm)
    }
    this.songs = newSongs
    this.songDataSource.reload(Array.from(newSongs))

    // Convert Model albums to AlbumItemViewModels
    const newAlbums = new AlbumItemViewModelArray()
    for (const albumData of data.albums) {
      newAlbums.push(AlbumItemViewModel.create(albumData))
    }
    this.albums = newAlbums
    this.albumDataSource.reload(Array.from(newAlbums))

    this.updateSongCountText()
  }

  // ---- Actions (called from View via event callbacks) ----

  // Toggle song list collapse state
  toggleSongsCollapsed(): void {
    this.isSongsCollapsed = !this.isSongsCollapsed
  }

  // Forward AppStorage 'displaySongCover' updates from the Page-layer bridge.
  // Unlike the other consumer pages, Artist caches long-lived SongItemViewModel
  // instances in this.songs, so we must also walk the cached array and reload
  // the LazyDataSource — otherwise the bound showCover field on each row keeps
  // the value it was assigned in loadArtistData and no re-render occurs.
  setDisplaySongCoverInList(value: boolean): void {
    if (this.displaySongCoverInList === value) return
    this.displaySongCoverInList = value
    for (const vm of this.songs) {
      vm.showCover = value
    }
    this.songDataSource.reload(Array.from(this.songs))
  }

  // spec21 — forward AppStorage 'displaySongFileName' writes from the
  // Page-layer bridge. Like setDisplaySongCoverInList, this VM caches
  // long-lived SongItemViewModel instances in this.songs, so we must walk the
  // cached array and reload the LazyDataSource — otherwise displayFileName on
  // each row keeps the value assigned in loadArtistData and no re-render fires.
  setDisplaySongFileNameInList(value: boolean): void {
    if (this.displaySongFileNameInList === value) return
    this.displaySongFileNameInList = value
    for (const vm of this.songs) {
      vm.displayFileName = value
    }
    this.songDataSource.reload(Array.from(this.songs))
  }

  // spec22 — forward AppStorage 'displayAddToPlayNext' writes from the
  // Page-layer bridge. Like the other display setters, this VM caches
  // long-lived SongItemViewModel instances in this.songs, so we must walk the
  // cached array and reload the LazyDataSource — otherwise displayAddToPlayNext
  // on each row keeps the value assigned in loadArtistData and no re-render fires.
  setDisplayAddToPlayNextInList(value: boolean): void {
    if (this.displayAddToPlayNextInList === value) return
    this.displayAddToPlayNextInList = value
    for (const vm of this.songs) {
      vm.displayAddToPlayNext = value
    }
    this.songDataSource.reload(Array.from(this.songs))
  }

  // Shuffle play all songs
  shufflePlayAll(): void {
    if (this.songs.length === 0) {
      return
    }
    const queue: QueueSongModel[] = this.songs.map((s: SongItemViewModel): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const randomIndex = Math.floor(Math.random() * this.songs.length)
    const picked = this.songs[randomIndex]
    this.currentSongId = picked.id
    for (const sv of this.songs) {
      sv.isCurrent = sv.id === picked.id
    }
    const service = AudioPlayerService.getInstance()
    service.setPlayMode(PlayModeConstants.RANDOM)
    service.setQueue(queue, randomIndex)
  }

  // Play a specific song — build queue from artist songs and play via service
  playSong(songVm: SongItemViewModel): void {
    this.currentSongId = songVm.id
    // Update isCurrent on all song ViewModels
    for (const sv of this.songs) {
      sv.isCurrent = sv.id === songVm.id
    }
    // Build queue from all artist songs
    const queue: QueueSongModel[] = this.songs.map((s: SongItemViewModel): QueueSongModel => {
      return new QueueSongModel(s.id, s.title, s.artist, s.album, s.subTitle,
        s.fileUri ?? '', s.coverUri)
    })
    const startIndex = queue.findIndex((q: QueueSongModel) => q.id === songVm.id)
    AudioPlayerService.getInstance().setQueue(queue, startIndex >= 0 ? startIndex : 0)
  }

  // Add song to play next
  addSongToPlayNext(songVm: SongItemViewModel): void {
    const song = songVm.toModel()
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Play next from menu (uses current menu target song)
  playNextFromMenu(): void {
    const song = this.menuSongInfo
    const queueSong = new QueueSongModel(song.id, song.title, song.artist, song.album, song.subTitle,
      song.fileUri ?? '', song.coverUri)
    AudioPlayerService.getInstance().addToPlayNext(queueSong)
  }

  // Open song menu for a given song
  openSongMenu(songVm: SongItemViewModel): void {
    this.menuSongInfo = songVm.toModel()
    this.showSongMenu = true
  }

  // Close the song menu
  closeSongMenu(): void {
    this.showSongMenu = false
  }

  removeSongFromListById(songId: string): void {
    // Find the removed song's album before filtering
    const removedSong = this.songs.find((s: SongItemViewModel) => s.id === songId)
    const removedAlbum = removedSong ? removedSong.album : ''

    const newSongs = new SongItemViewModelArray()
    for (const s of this.songs) {
      if (s.id !== songId) {
        newSongs.push(s)
      }
    }
    this.songs = newSongs
    this.songDataSource.reload(Array.from(newSongs))
    this.updateSongCountText()

    // Update the album item count for the removed song's album
    if (removedAlbum.length > 0) {
      for (const albumVm of this.albums) {
        if (albumVm.title === removedAlbum) {
          albumVm.count--
          albumVm.songCountText = `${albumVm.count} \u9996 `
          break
        }
      }
    }
  }

  // ---- Private helpers ----

  private updateDerivedProperties(): void {
    this.hasArtistName = this.artistName.length > 0
    this.artistNameOpacity = this.artistName.length > 0 ? 1.0 : 0.35
    this.hasArtistCoverUri = this.artistCoverUri.length > 0

    const geoKey = this.artistId.length > 0
      ? this.artistId
      : (this.artistName.length > 0 ? this.artistName : 'unknown-artist')
    this.artistGeometryImageKey = `image-artist-${geoKey}`
    this.artistGeometryTextKey = `text-artist-${geoKey}`
  }

  private updateSongCountText(): void {
    this.songCountText = `${this.songs.length}`
  }
}

// 艺术家详情：加载指定艺术家的曲目集合。

汇总艺术家详情头部信息：名称、专辑数与歌曲数的副标题文案。
function buildArtistHeaderD(name: string, albumCount: number, songCount: number): Map<string, string> {
  const header = new Map<string, string>();
  const safeName = name.trim().length === 0 ? '未知艺术家' : name.trim();
  const albums = albumCount < 0 ? 0 : albumCount;
  const songs = songCount < 0 ? 0 : songCount;
  header.set('title', safeName);
  const parts: string[] = [];
  parts.push(albums + ' 张专辑');
  parts.push(songs + ' 首歌曲');
  header.set('subtitle', parts.join(' · '));
  return header;
}

将十六进制颜色字符串解析为 RGB 分量数组。
function parseHexColorD(hex: string): number[] {
  let value = hex.trim();
  if (value.charAt(0) === '#') {
    value = value.substring(1);
  }
  if (value.length !== 6) {
    return [0, 0, 0];
  }
  const r = Number.parseInt(value.substring(0, 2), 16);
  const g = Number.parseInt(value.substring(2, 4), 16);
  const b = Number.parseInt(value.substring(4, 6), 16);
  return [r, g, b];
}

将秒数格式化为 mm:ss 时间文本。
function formatSecondsD_H35(totalSeconds: number): string {
  const safe = totalSeconds < 0 ? 0 : Math.floor(totalSeconds);
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  const mm = minutes < 10 ? '0' + minutes : '' + minutes;
  const ss = seconds < 10 ? '0' + seconds : '' + seconds;
  return mm + ':' + ss;
}

汇总艺术家详情头部信息：名称、专辑数与歌曲数的副标题文案。
function buildArtistHeaderD_H35(name: string, albumCount: number, songCount: number): Map<string, string> {
  const header = new Map<string, string>();
  const safeName = name.trim().length === 0 ? '未知艺术家' : name.trim();
  const albums = albumCount < 0 ? 0 : albumCount;
  const songs = songCount < 0 ? 0 : songCount;
  header.set('title', safeName);
  const parts: string[] = [];
  parts.push(albums + ' 张专辑');
  parts.push(songs + ' 首歌曲');
  header.set('subtitle', parts.join(' · '));
  return header;
}

按碟号优先曲目号其次的顺序对专辑曲目排序
function sortAlbumTracksC_H35(tracks: Array<{ disc: number; track: number; title: string }>): Array<{ disc: number; track: number; title: string }> {
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

统计参与专辑创作的各艺术家歌曲数并按数量降序排列
function rankAlbumArtistsC_H35(trackArtists: string[]): Array<{ name: string; count: number }> {
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

由完整路径提取文件夹显示名与歌曲数，构建文件夹列表项。
function buildFolderItemD_H35(path: string, songCount: number): Map<string, string> {
  const item = new Map<string, string>();
  const normalized = path.replace('\\', '/').trim();
  const segments = normalized.split('/');
  let name = '';
  for (let i = segments.length - 1; i >= 0; i--) {
    if (segments[i].length > 0) {
      name = segments[i];
      break;
    }
  }
  item.set('name', name.length === 0 ? '根目录' : name);
  item.set('path', normalized);
  item.set('subtitle', (songCount < 0 ? 0 : songCount) + ' 首');
  return item;
}

判断给定年份是否为闰年。
function isLeapYearD_H35(year: number): boolean {
  if (year <= 0) {
    return false;
  }
  if (year % 400 === 0) {
    return true;
  }
  if (year % 100 === 0) {
    return false;
  }
  return year % 4 === 0;
}
