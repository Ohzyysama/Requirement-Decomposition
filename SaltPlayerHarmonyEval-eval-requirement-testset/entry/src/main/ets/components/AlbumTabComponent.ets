// AlbumTabComponent.ets
// View layer: Album grid view component for Salt Player
// Corresponds to Android AlbumScreen.kt (ui/main/album/AlbumScreen.kt)
// Displays albums in a grid layout with cover, title, and song count
// Includes: AlbumGrid toggle icon (ic_rows) for list settings, RightABC sidebar for quick index
//
// Uses LazyForEach with AlbumLazyDataSource / AlbumYearLazyDataSource for lazy rendering.
// Data processing is delegated to MainPageViewModel.

import RightABCModel from '../model/RightABCModel'
import { SongLazySort } from '../model/SongSortModel'
import { AlbumSortType } from '../model/AlbumListSettingsModel'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { vibrator } from '@kit.SensorServiceKit'
import AlbumLazyDataSource, { AlbumYearLazyDataSource, AlbumYearFlatItem } from '../model/AlbumLazyDataSource'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'
import { MiniPlayerDefaults } from '../pages/main/MiniPlayerContainer'

// Re-export AlbumInfo interface for backward compatibility with existing consumers
// (MainPage.ets, ArtistContentPage.ets, etc.)
export interface AlbumInfo {
  id: string
  title: string
  albumArtist: string
  count: number
  year: number
  coverUri: string
  coverSongId: string
  coverModified: number
  pinyin: string // first character for ABC index
}

const ALBUM_GRID_SIDE_PADDING: number = 8

// Album item component for year-grouped list view (needs @Component for ImageKnife)
@Component
struct AlbumYearListItemComponent {
  @Prop @Watch('onAlbumChanged') album: AlbumInfo = {
    id: '', title: '', albumArtist: '', count: 0, year: 0,
    coverUri: '', coverSongId: '', coverModified: 0, pinyin: ''
  }
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()
  private loadedCoverKey: string = ''

  aboutToAppear(): void {
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover
    this.loadCover()
  }

  aboutToRecycle(): void {
    this.loadedCoverKey = ''
  }

  onAlbumChanged(): void {
    const cacheKey = this.album.coverSongId || this.album.id
    if (cacheKey !== this.loadedCoverKey) {
      this.loadCover()
    }
  }

  loadCover(): void {
    const songId = this.album.coverSongId || this.album.id
    if (songId.length === 0) return
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
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Row({ space: 12 }) {
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.coverOption })
          .width(56)
          .height(56)
      }
      .width(56)
      .height(56)
      .borderRadius(6)
      .clip(true)
      .backgroundColor($r('app.color.salt_color_song_cover'))

      Column() {
        Text(this.album.title.length > 0 ? this.album.title : $r('app.string.unknown_album_title'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.album.title.length > 0 ? 1.0 : 0.35)

        Text(`${this.album.count} \u9996 ${this.album.albumArtist}`)
          .fontSize(11)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
  }
}

@Component
struct AlbumItemCardComponent {
  @Prop @Watch('onAlbumChanged') album: AlbumInfo = {
    id: '', title: '', albumArtist: '', count: 0, year: 0,
    coverUri: '', coverSongId: '', coverModified: 0, pinyin: ''
  }
  onAlbumClick: (albumId: string) => void = () => {}
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()
  private loadedCoverKey: string = ''

  aboutToAppear(): void {
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover
    this.loadCover()
  }

  aboutToRecycle(): void {
    this.loadedCoverKey = ''
  }

  onAlbumChanged(): void {
    const cacheKey = this.album.coverSongId || this.album.id
    if (cacheKey !== this.loadedCoverKey) {
      this.loadCover()
    }
  }

  loadCover(): void {
    const songId = this.album.coverSongId || this.album.id
    if (songId.length === 0) return
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
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Column() {
      // Album cover image
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.coverOption })
          .width('100%')
          .aspectRatio(1)
      }
      .width('100%')
      .aspectRatio(1)
      .borderRadius(8)
      .clip(true)
      .backgroundColor($r('app.color.salt_color_song_cover'))

      // Album title
      Text(this.album.title.length > 0 ? this.album.title : $r('app.string.unknown_album_title'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4 })
        .opacity(this.album.title.length > 0 ? 1.0 : 0.35)

      // Song count and year
      Text(this.getAlbumSubText())
        .fontSize(11)
        .fontColor($r('app.color.colorSubTextForeground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 2 })
    }
    .padding(8)
    .onClick(() => {
      this.onAlbumClick(this.album.id)
    })
  }

  private getAlbumSubText(): string {
    let text = `${this.album.count} \u9996 `;
    if (this.album.year > 0) {
      text += `${this.album.year} `;
    }
    text += this.album.albumArtist;
    return text;
  }
}

@Component
export struct AlbumTabComponent {
  // Data sources for lazy rendering
  albumDataSource: AlbumLazyDataSource = new AlbumLazyDataSource()
  albumYearDataSource: AlbumYearLazyDataSource = new AlbumYearLazyDataSource()

  // Album count for empty state check and ABC index visibility
  @Prop albumCount: number = 0

  // Album sort type from settings
  @Prop albumSortType: number = AlbumSortType.TITLE

  // Minimum number of columns for the album grid (from album list settings)
  @Prop minimumColumns: number = 2

  // Whether data is still loading from the database (suppresses empty state)
  @Prop isDataLoading: boolean = false

  // Callback when an album item is clicked - passes albumId
  onAlbumClick: (albumId: string) => void = () => {
  }

  // Callback to open album list settings dialog
  onSettingsClick: () => void = () => {
  }

  // Callback to navigate to scan music page when album list is empty
  onScanMusicClick: () => void = () => {
  }

  // Grid scroller for scrolling to specific items
  private gridScroller: Scroller = new Scroller()
  @State private alphabetSelected: number = 0
  @State private alphabetPopupLetter: string = ''
  @State private alphabetPopupVisible: boolean = false

  // List scroller for year-sorted mode
  private listScroller: Scroller = new Scroller()

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.albumCount === 0 && !this.isDataLoading) {
        // Empty state - show scan music button
        Column() {
          Button($r('app.string.scan_music'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.salt_color_high_light'))
            .borderRadius(24)
            .onClick(() => {
              this.onScanMusicClick()
            })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 8 })
      } else if (this.albumSortType === AlbumSortType.YEAR) {
        // Year sort: List layout with flattened year headers + album items (lazy)
        List({ scroller: this.listScroller }) {
          LazyForEach(this.albumYearDataSource, (item: AlbumYearFlatItem) => {
            if (item.isHeader) {
              ListItem() {
                Row() {
                  Text(item.year === '0' ? $r('app.string.unknown_album_title') : item.year)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.salt_color_icon_foreground'))
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 4 })
              }
            } else {
              ListItem() {
                AlbumYearListItemComponent({ album: item.album as AlbumInfo })
              }
              .onClick(() => {
                this.onAlbumClick((item.album as AlbumInfo).id)
              })
            }
          }, (item: AlbumYearFlatItem) => {
            if (item.isHeader) {
              return `h_${item.year}`
            }
            const album = item.album as AlbumInfo
            return `a_${album.id}_${album.count}`
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 8, right: 8 })
        .contentEndOffset(96)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      } else {
        // Title/Count sort: Grid layout (lazy)
        Grid(this.gridScroller) {
          LazyForEach(this.albumDataSource, (album: AlbumInfo) => {
            GridItem() {
              AlbumItemCardComponent({
                album: album,
                onAlbumClick: this.onAlbumClick
              })
            }
          }, (album: AlbumInfo) => `${album.id}_${album.count}`)
        }
        .columnsTemplate(this.getColumnsTemplate())
        .columnsGap(0)
        .rowsGap(0)
        .width('100%')
        .height('100%')
        .padding({ left: ALBUM_GRID_SIDE_PADDING, right: ALBUM_GRID_SIDE_PADDING })
        .contentEndOffset(96)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }

      // Right ABC index
      if (this.albumCount > 0) {
        Row() {
          if (this.alphabetPopupVisible) {
            Stack() {
              Text(this.alphabetPopupLetter)
                .fontSize(32)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.salt_color_high_light'))
            }
            .width(56)
            .height(56)
            .borderRadius(28)
            .backgroundColor($r('app.color.salt_color_sub_background'))
            .alignContent(Alignment.Center)
          }

          AlphabetIndexer({ arrayValue: new RightABCModel().alphabetArray, selected: $$this.alphabetSelected })
            .onSelect((index: number) => {
              const char = new RightABCModel().alphabetArray[index]
              this.handleCharSelect(char)
              this.alphabetPopupLetter = char
              this.alphabetPopupVisible = true
              vibrator.startVibration({ type: 'time', duration: 20 }, { id: 0, usage: 'touch' })
            })
            .selectedColor($r('app.color.colorSubTextForeground'))
            .selectedBackgroundColor(Color.Transparent)
            .usingPopup(false)
            .autoCollapse(false)
            .selectedFont({ size: 10, weight: FontWeight.Bold })
            .font({ size: 10 })
            .itemSize(15)
            .alignStyle(IndexerAlign.Left)
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.alphabetPopupVisible = false
              }
            })
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .height('100%')
        .offset({ x: 3 })
        .padding({ bottom: MiniPlayerDefaults.TOTAL_HEIGHT })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }

  // Generate grid columns template directly from @Prop minimumColumns
  // so ArkUI can track the dependency and refresh the Grid layout.
  private getColumnsTemplate(): string {
    const cols = this.minimumColumns > 0 ? this.minimumColumns : 2
    const parts: string[] = []
    for (let i = 0; i < cols; i++) {
      parts.push('1fr')
    }
    return parts.join(' ')
  }

  // Handle ABC character selection - find first album whose title pinyin initial matches
  private handleCharSelect(char: string): void {
    if (char === '0') {
      this.gridScroller.scrollToIndex(0)
      return
    }
    const targetChar = char.toUpperCase()
    const albums = this.albumDataSource.getAll()
    let foundIndex = -1
    for (let i = 0; i < albums.length; i++) {
      const initial = SongLazySort.getPinyinInitial(albums[i].title)
      if (targetChar === '#') {
        if (initial === '#') {
          foundIndex = i
          break
        }
      } else if (initial === targetChar) {
        foundIndex = i
        break
      }
    }
    if (foundIndex !== -1) {
      this.gridScroller.scrollToIndex(foundIndex)
    }
  }
}
