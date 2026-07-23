// SongInformationPage.ets
// View layer: Song information bottom sheet component.
// MVVM: This View uses SongInformationViewModel for all data and display logic.
//       The View only handles UI rendering and user interaction,
//       delegating business logic and data formatting to the ViewModel.
//
// Corresponds to Android SongInformationDialog.kt
// Displays song metadata: title, artist, album, album artist, media source, play count,
// duration, bitrate, sample rate, bit depth, size, format, path, codec, copyright,
// add time, date modified.
// Accessed via: Song more-options menu -> "Song Info"

import { SongInfo } from '../components/SongItemComponent'
import { SongInformationViewModel } from '../viewmodel/SongInformationViewModel'

@Component
export struct SongInformationComponent {
  // Accept raw SongInfo from parent (backward-compatible prop interface).
  // The component internally creates and manages its ViewModel.
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

  // ViewModel instance: manages display state and business logic.
  @State viewModel: SongInformationViewModel = new SongInformationViewModel()

  // Cached unknown text resource string for display fallback
  private unknownText: string = ''

  aboutToAppear(): void {
    // Resolve resource string for "unknown" fallback text
    this.unknownText = getContext(this).resourceManager.getStringSync($r('app.string.unknown'))
    // Populate ViewModel from Model data
    this.viewModel.updateFromModel(this.songInfo)
  }

  build() {
    Scroll() {
      Column() {
        // ========== Title: Song Info ==========
        Text($r('app.string.song_info'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 12 })

        // ========== Section 1: Album Artwork ==========
        // TODO: Album Artwork - temporarily hidden, uncomment after implementation
        // this.AlbumArtworkSection()

        // ========== Section 2: Basic Info (title, artist, album, album artist) ==========
        this.BasicInfoSection()

        // ========== Section 3: Media & Technical Info ==========
        this.MediaInfoSection()

        // Bottom padding
        Blank().height(32)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .nestedScroll({
      scrollForward: NestedScrollMode.PARENT_FIRST,
      scrollBackward: NestedScrollMode.SELF_FIRST
    })
  }

  // ======================== Section 1: Album Artwork ========================
  @Builder
  AlbumArtworkSection() {
    Column() {
      Row() {
        Text($r('app.string.album_artwork'))
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .layoutWeight(1)

        Image($r('app.media.ic_chevron_right'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.salt_color_sub_text'))
          .objectFit(ImageFit.Contain)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 16, bottom: 16 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        // Delegate click handling to ViewModel
        this.viewModel.handleAlbumArtworkClick()
      })
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 8 })
    .clip(true)
  }

  // ======================== Section 2: Basic Info ========================
  @Builder
  BasicInfoSection() {
    Column() {
      this.ItemValue($r('app.string.title'), this.viewModel.getDisplayTitle())
      this.ItemValue($r('app.string.artist'), this.viewModel.getDisplayArtist())
      this.ItemValue($r('app.string.album'), this.viewModel.getDisplayAlbum())
      this.ItemValue($r('app.string.album_artist'), this.viewModel.getDisplayAlbumArtist(this.unknownText))
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 8 })
    .clip(true)
  }

  // ======================== Section 3: Media & Technical Info ========================
  @Builder
  MediaInfoSection() {
    Column() {
      this.ItemValue($r('app.string.duration'), this.viewModel.getDisplayDuration())

      this.ItemValue($r('app.string.bitrate'), this.viewModel.getDisplayBitrate(this.unknownText))

      if (this.viewModel.hasChannels()) {
        this.ItemValue($r('app.string.channels'), this.viewModel.getDisplayChannels())
      }

      if (this.viewModel.hasSampleRate()) {
        this.ItemValue($r('app.string.sample_rate'), this.viewModel.getDisplaySampleRate())
      }

      if (this.viewModel.hasBitDepth()) {
        this.ItemValue($r('app.string.bit_depth'), this.viewModel.getDisplayBitDepth())
      }

      this.ItemValue($r('app.string.size'), this.viewModel.getDisplaySize())

      this.ItemValue($r('app.string.format'), this.viewModel.getDisplayFormat(this.unknownText))

      this.ItemValue($r('app.string.path'), this.viewModel.getDisplayPath(this.unknownText))

      this.ItemValue($r('app.string.codec'), this.viewModel.getDisplayCodec(this.unknownText))

      this.ItemValue($r('app.string.copyright'), this.viewModel.getDisplayCopyright(this.unknownText))

      this.ItemValue($r('app.string.add_time'), this.viewModel.getDisplayAddTime())

      this.ItemValue($r('app.string.date_modified'), this.viewModel.getDisplayDateModified())
    }
    .width('100%')
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_white'))
    .margin({ bottom: 8 })
    .clip(true)
  }

  // ======================== ItemValue Builder ========================
  // Matches Android SaltUI ItemValue: label text on top (small, gray), value text below (larger, dark)
  @Builder
  ItemValue(label: Resource, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.salt_color_sub_text'))

      Text(value)
        .fontSize(15)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
  }
}

// 歌曲信息：展示路径/比特率/采样率/声道/位深/大小/时长等详情。
