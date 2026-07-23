// SongMenuDialogComponent.ets
// View layer: Song menu bottom sheet content
// Corresponds to Android SongMenuDialog.kt
// Displays song info header and a list of action items (add to playlist, play next, share, etc.)
// Used as content for bindSheet in MainPage.
//
// MVVM architecture:
//   View: SongMenuDialogComponent (this file)
//   ViewModel: SongMenuDialogViewModel
//   Model: SongMenuModel

import { SongInfo } from './SongItemComponent'
import { promptAction } from '@kit.ArkUI'
import SongMenuDialogViewModel from '../viewmodel/SongMenuDialogViewModel'
import { SongMenuAction } from '../model/SongMenuModel'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'
import { ArtistItemComponent } from './ArtistItemComponent'
import { ArtistItemViewModel } from '../viewmodel/ArtistItemViewModel'

@Component
export struct SongMenuDialogComponent {
  // The song to show the menu for
  @Prop songInfo: SongInfo = {
    id: '',
    title: '',
    artist: '',
    album: '',
    subTitle: '',
    coverUri: '',
    valid: true,
    quality: 0
  }

  // Callbacks for menu actions - passed through to the ViewModel
  onDismiss: () => void = () => {}
  onAddToPlaylist: () => void = () => {}
  onPlayNext: () => void = () => {}
  onShare: () => void = () => {}
  onArtistClick: (artistName: string) => void = () => {}
  onAlbumClick: () => void = () => {}
  onMusicTagEdit: () => void = () => {}
  onHearusySpectrum: () => void = () => {}
  onEmoScroll: () => void = () => {}
  onSongInfo: () => void = () => {}
  onRemoveFromLibrary: () => void = () => {}
  onRemoveFromPlaylist: () => void = () => {}
  showRemoveFromPlaylist: boolean = false
  onCopyText: () => void = () => {}

  // ViewModel instance - manages state and business logic
  @State private viewModel: SongMenuDialogViewModel = new SongMenuDialogViewModel()
  @State private coverOption: ImageKnifeOption = new ImageKnifeOption()
  @State private menuContentHeight: number = 0
  @StorageProp('navBarHeight') navBarHeight: number = 28
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  aboutToAppear(): void {
    // Initialize ViewModel from the songInfo prop
    this.viewModel.initWithSongInfo(this.songInfo)

    // Set up cover option
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover

    // Load cover art
    this.loadCover()

    // Wire up all callbacks from parent to the ViewModel
    this.viewModel.onDismiss = this.onDismiss
    this.viewModel.onAddToPlaylist = this.onAddToPlaylist
    this.viewModel.onPlayNext = this.onPlayNext
    this.viewModel.onShare = this.onShare
    this.viewModel.onArtistClick = this.onArtistClick
    this.viewModel.onAlbumClick = this.onAlbumClick
    this.viewModel.onMusicTagEdit = this.onMusicTagEdit
    this.viewModel.onHearusySpectrum = this.onHearusySpectrum
    this.viewModel.onEmoScroll = this.onEmoScroll
    this.viewModel.onSongInfo = this.onSongInfo
    this.viewModel.onRemoveFromLibrary = this.onRemoveFromLibrary
    this.viewModel.onRemoveFromPlaylist = this.onRemoveFromPlaylist
    this.viewModel.onCopyText = this.onCopyText
  }

  loadCover(): void {
    const songId = this.viewModel.songId
    if (!songId || songId.length === 0) return

    const uri = CoverCacheDb.getCoverFileUri(songId)
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri
      return
    }

    const capturedId = songId
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri
        return
      }
      return CoverArtExtractor.extractAndCache(songId, songId)
    }).then(() => {
      const u = CoverCacheDb.getCoverFileUri(capturedId)
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Column() {
      if (this.viewModel.showArtistSelection) {
        // ===== Artist Selection List =====
        // Same left padding as menu items' background box (16 outer + 0 inner = 16)
        Column() {
          Text($r('app.string.participating_artists'))
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .padding({ left: 16, right: 16, top: 16, bottom: 4 })
            .width('100%')

          ForEach(this.viewModel.artistViewModels, (artist: ArtistItemViewModel) => {
            ArtistItemComponent({
              artistVM: artist,
              onItemClick: () => {
                this.viewModel.selectArtist(artist.name)
              }
            })
          }, (artist: ArtistItemViewModel) => artist.id)
        }
        .width('100%')
        .constraintSize({ minHeight: this.menuContentHeight })
        .margin({ top: 12, bottom: 16 })
      } else {
      // ===== Song Info Header (RoundedColumn) =====
      Column() {
        this.SongInfoHeader()
      }
      .width('100%')
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorItemBackground'))
      .borderRadius(12)
      .margin({ top: 12 })
      .clip(true)

      // ===== Menu Items (RoundedColumn) =====
      Column() {
        // Add to playlist
        this.DialogMenuItemTinted($r('app.media.ic_add'),
          $r('app.string.add_to_playlist'), $r('app.color.salt_color_high_light'), () => {
            this.viewModel.handleAction(SongMenuAction.ADD_TO_PLAYLIST)
          })

        // Play next
        this.DialogMenuItemTinted($r('app.media.ic_playlist_add_24'),
          $r('app.string.next_play'), $r('app.color.salt_color_high_light'), () => {
            this.viewModel.handleAction(SongMenuAction.PLAY_NEXT)
            promptAction.showToast({ message: $r('app.string.successfully_added_to_next_play') })
          })

        // Share
        this.DialogMenuItem($r('app.media.ic_share'),
          $r('app.string.share'), () => {
            this.viewModel.handleAction(SongMenuAction.SHARE)
          })

        // Artist
        this.DialogMenuItemWithDynamicText($r('app.media.ic_artist'),
          this.viewModel.getArtistDisplayText(), () => {
            this.viewModel.handleAction(SongMenuAction.ARTIST_CLICK)
          })

        // Album
        this.DialogMenuItemWithDynamicText($r('app.media.ic_album_24'),
          this.viewModel.getAlbumDisplayText(), () => {
            this.viewModel.handleAction(SongMenuAction.ALBUM_CLICK)
          })

        // Music tag editing
        // this.DialogMenuItem($r('app.media.ic_edit'),
        //   $r('app.string.use_music_tag_app_editing'), () => {
        //     this.viewModel.handleAction(SongMenuAction.MUSIC_TAG_EDIT)
        //   })

        // Hearusy Spectrum
        // this.DialogMenuItemWithDynamicText($r('app.media.ic_hearusy_spectrum'),
        //   'Hearusy Spectrum...', () => {
        //     this.viewModel.handleAction(SongMenuAction.HEARUSY_SPECTRUM)
        //   })

        // Emo Scroll
        // this.DialogMenuItemWithDynamicText($r('app.media.ic_app_emo_scroll'),
        //   '\u4F7F\u7528\u5FC3\u4E8B\u5377\u8F74\u8BB0\u5F55\u542C\u6B4C\u5FC3\u60C5...', () => {
        //     this.viewModel.handleAction(SongMenuAction.EMO_SCROLL)
        //   })

        // Remove from playlist (only shown in playlist context)
        if (this.showRemoveFromPlaylist) {
          this.DialogMenuItemWithDynamicText($r('app.media.ic_remove'),
            '从此歌单中移除', () => {
              this.viewModel.handleAction(SongMenuAction.REMOVE_FROM_PLAYLIST)
            })
        }

        // Song info
        this.DialogMenuItemTinted($r('app.media.ic_info'),
          $r('app.string.song_info'), $r('app.color.colorSubIconForeground'), () => {
            this.viewModel.handleAction(SongMenuAction.SONG_INFO)
          })

        // Remove from library
        this.DialogMenuItem($r('app.media.ic_remove'),
          $r('app.string.remove_from_library'), () => {
            this.viewModel.handleAction(SongMenuAction.REMOVE_FROM_LIBRARY)
          })
      }
      .width('100%')
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.colorItemBackground'))
      .borderRadius(12)
      .margin({ top: 8, bottom: 16 })
      .clip(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        // Capture rendered menu height so the artist-selection list matches it
        // (header height fixed at 72, plus 8px gap between header and menu)
        this.menuContentHeight = 72 + 8 + (newValue.height as number)
      })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: this.navBarHeight })
  }

  @Builder
  SongInfoHeader() {
    Row() {
      // Song cover image
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.coverOption })
          .width(44)
          .height(44)
      }
      .width(44)
      .height(44)
      .borderRadius(6)
      .clip(true)
      .margin({ left: 16, top: 14, bottom: 14 })

      // Song title and subtitle
      Column() {
        Text(this.viewModel.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.viewModel.subTitle)
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 12, right: 8 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)

      // Copy text button
      Image($r('app.media.ic_copy'))
        .width(22)
        .height(22)
        .fillColor($r('app.color.salt_color_high_light'))
        .objectFit(ImageFit.Contain)
        .margin({ right: 16 })
        .onClick(() => {
          this.viewModel.handleAction(SongMenuAction.COPY_TEXT)
        })
        .accessibilityText('\u590D\u5236\u6587\u672C')
    }
    .width('100%')
    .height(72)
    .alignItems(VerticalAlign.Center)
  }

  // ===== Dialog Menu Item with Resource string =====
  @Builder
  DialogMenuItem(icon: Resource, text: Resource, onClick: () => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)

      Text(text)
        .fontSize(14)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick()
    })
  }

  // ===== Dialog Menu Item with tinted icon =====
  @Builder
  DialogMenuItemTinted(icon: Resource, text: Resource, tintColor: ResourceColor, onClick: () => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)
        .fillColor(tintColor)

      Text(text)
        .fontSize(14)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick()
    })
  }

  // ===== Dialog Menu Item with dynamic text string =====
  @Builder
  DialogMenuItemWithDynamicText(icon: Resource, text: string, onClick: () => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .objectFit(ImageFit.Contain)

      Text(text)
        .fontSize(14)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16 })
        .layoutWeight(1)
    }
    .width('100%')
    .height(40)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      onClick()
    })
  }

}
