// SongMenuDialogViewModel.ets
// ViewModel layer: manages state and logic for the SongMenuDialogComponent view
// Bridges the View and Model layers per MVVM architecture
//
// MVVM architecture:
//   View: SongMenuDialogComponent
//   ViewModel: SongMenuDialogViewModel (this file)
//   Model: SongMenuModel

import { SongMenuInfo, SongMenuAction, SongMenuItemConfig, SongMenuDataSource } from '../model/SongMenuModel'
import { SongInfo } from '../components/SongItemComponent'
import { Guqin } from '../model/Guqin'
import { ArtistItemViewModel } from './ArtistItemViewModel'
import { MainPageDataSource } from '../model/MainPageModel'

@Observed
export default class SongMenuDialogViewModel {
  // Song display properties (from Model)
  @Track public songId: string = ''
  @Track public title: string = ''
  @Track public subTitle: string = ''
  @Track public coverUri: string = ''
  @Track public artist: string = ''
  @Track public album: string = ''
  @Track public artistNames: string[] = []
  @Track public artistViewModels: ArtistItemViewModel[] = []
  @Track public showArtistSelection: boolean = false

  // The last executed action, can be observed by the View
  @Track public lastAction: SongMenuAction = SongMenuAction.NONE

  // Callbacks for menu actions - set by parent component
  @Track public onDismiss: () => void = () => {}
  @Track public onAddToPlaylist: () => void = () => {}
  @Track public onPlayNext: () => void = () => {}
  @Track public onShare: () => void = () => {}
  @Track public onArtistClick: (artistName: string) => void = () => {}
  @Track public onAlbumClick: () => void = () => {}
  @Track public onMusicTagEdit: () => void = () => {}
  @Track public onHearusySpectrum: () => void = () => {}
  @Track public onEmoScroll: () => void = () => {}
  @Track public onSongInfo: () => void = () => {}
  @Track public onRemoveFromLibrary: () => void = () => {}
  @Track public onRemoveFromPlaylist: () => void = () => {}
  @Track public onCopyText: () => void = () => {}

  // Initialize the ViewModel with SongInfo
  initWithSongInfo(songInfo: SongInfo): void {
    let model = new SongMenuInfo(songInfo)
    this.songId = model.id
    this.title = model.title
    this.subTitle = model.subTitle
    this.coverUri = model.coverUri
    this.artist = model.artist
    this.album = model.album
    this.artistNames = Guqin.getArtists(model.artist)
    this.artistViewModels = this.buildArtistViewModels()
    this.showArtistSelection = false
  }

  // Get the display text for artist menu item
  getArtistDisplayText(): string {
    return `\u827A\u672F\u5BB6\uFF1A${this.artist}`
  }

  // Get the display text for album menu item
  getAlbumDisplayText(): string {
    return `\u4E13\u8F91\uFF1A${this.album}`
  }

  // Get the cover image source - fallback to default if empty
  getCoverImageSource(): string | Resource {
    if (this.coverUri !== '') {
      return this.coverUri
    }
    return $r('app.media.ic_song_cover_v5')
  }

  // Handle a menu action: dismiss the dialog first, then execute the action.
  // Exception: SONG_INFO swaps content in-place without dismissing the sheet.
  handleAction(action: SongMenuAction): void {
    this.lastAction = action

    if (action !== SongMenuAction.SONG_INFO && action !== SongMenuAction.ARTIST_CLICK) {
      this.onDismiss()
    }

    switch (action) {
      case SongMenuAction.ADD_TO_PLAYLIST:
        this.onAddToPlaylist()
        break
      case SongMenuAction.PLAY_NEXT:
        SongMenuDataSource.playNext(this.onPlayNext)
        break
      case SongMenuAction.SHARE:
        this.onShare()
        break
      case SongMenuAction.ARTIST_CLICK:
        if (this.artistNames.length <= 1) {
          this.onDismiss()
          this.onArtistClick(this.artistNames.length === 1 ? this.artistNames[0] : this.artist)
        } else {
          this.showArtistSelection = true
        }
        break
      case SongMenuAction.ALBUM_CLICK:
        this.onAlbumClick()
        break
      case SongMenuAction.MUSIC_TAG_EDIT:
        this.onMusicTagEdit()
        break
      case SongMenuAction.HEARUSY_SPECTRUM:
        this.onHearusySpectrum()
        break
      case SongMenuAction.EMO_SCROLL:
        this.onEmoScroll()
        break
      case SongMenuAction.SONG_INFO:
        this.onSongInfo()
        break
      case SongMenuAction.REMOVE_FROM_LIBRARY:
        this.onRemoveFromLibrary()
        break
      case SongMenuAction.REMOVE_FROM_PLAYLIST:
        this.onRemoveFromPlaylist()
        break
      case SongMenuAction.COPY_TEXT:
        this.onCopyText()
        break
      default:
        break
    }
  }

  // Build ArtistItemViewModels for multi-artist selection
  private buildArtistViewModels(): ArtistItemViewModel[] {
    if (this.artistNames.length <= 1) return []
    const allArtists = MainPageDataSource.loadDefaultArtists()
    return this.artistNames.map((name: string) => {
      const info = allArtists.find(a => a.name === name)
      return new ArtistItemViewModel(
        info?.id ?? name,
        name,
        info?.count ?? 0,
        info?.coverUri ?? '',
        '',
        info?.coverSongId ?? this.songId
      )
    })
  }

  // Select a specific artist from the multi-artist list
  selectArtist(artistName: string): void {
    this.showArtistSelection = false
    this.onDismiss()
    this.onArtistClick(artistName)
  }

  // Cancel artist selection and return to the main menu
  cancelArtistSelection(): void {
    this.showArtistSelection = false
  }
}
