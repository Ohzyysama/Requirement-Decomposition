// SongItemComponent.ets
// View layer: Standard song list item component for Salt Player.
// MVVM: This View uses SongItemViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating business logic to the ViewModel.
//
// Cover loading: uses ImageKnifeComponent with file URI from CoverCacheDb.

import { promptAction } from '@kit.ArkUI'
import { SongItemViewModel } from '../viewmodel/SongItemViewModel'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'
import {
  SONG_QUALITY_HQ,
  SONG_QUALITY_SQ,
  SONG_QUALITY_HI_RES,
  SONG_QUALITY_NORMAL
} from '../model/SongItemModel'

// Re-export SongInfoData as SongInfo for backward compatibility with all consuming pages
export { SongInfoData as SongInfo } from '../model/SongItemModel'

@Component
export struct SongItemComponent {
  @Prop @Watch('onViewModelChanged') viewModel: SongItemViewModel = new SongItemViewModel()
  @State coverOption: ImageKnifeOption = new ImageKnifeOption()
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  // The songId for which the current cover was loaded (or is loading).
  // Prevents re-loading when only isCurrent or other display props changed.
  private loadedSongId: string = ''

  aboutToAppear(): void {
    this.coverOption.placeholderSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.errorSrc = $r('app.media.ic_song_cover_v5')
    this.coverOption.objectFit = ImageFit.Cover
    this.loadCover()
  }

  // Reset when the component is recycled by LazyForEach
  aboutToRecycle(): void {
    this.loadedSongId = ''
  }

  // Called by @Watch whenever the viewModel prop changes.
  // Only triggers a cover reload if the song itself changed.
  onViewModelChanged(): void {
    if (this.viewModel.id !== this.loadedSongId) {
      this.loadCover()
    }
  }

  loadCover(): void {
    const songId = this.viewModel.id
    this.loadedSongId = songId

    if (!songId || songId.length === 0) return

    // 1. Sync file check — JPEG already on disk
    const uri = CoverCacheDb.getCoverFileUri(songId)
    if (uri.length > 0) {
      this.coverOption.loadSrc = uri
      return
    }

    // 2. Async: RDB file export → extract from audio file → set file URI
    const capturedId = songId
    CoverCacheDb.ensureCoverFile(songId).then((fileUri: string) => {
      if (this.loadedSongId !== capturedId) return
      if (fileUri.length > 0) {
        this.coverOption.loadSrc = fileUri
        return
      }
      const fileUriForExtract = this.viewModel.fileUri ?? ''
      if (fileUriForExtract.length === 0) return
      return CoverArtExtractor.extractAndCache(songId, fileUriForExtract,
        this.viewModel.dateModified ?? 0, this.viewModel.size ?? 0)
    }).then(() => {
      if (this.loadedSongId !== capturedId) return
      const u = CoverCacheDb.getCoverFileUri(songId)
      if (u.length > 0) {
        this.coverOption.loadSrc = u
      }
    }).catch((_e: Error) => { /* swallow */ })
  }

  build() {
    Row() {
      Row() {
        if (this.viewModel.showTrackNumber) {
          Text(this.viewModel.getTrackNumberText())
            .width(50)
            .textAlign(TextAlign.Center)
            .fontSize(15)
            .fontColor(this.viewModel.isCurrent ? $r('app.color.salt_color_high_light') :
              $r('app.color.colorSubTextForeground'))
            .margin({ left: 16 })
        } else if (this.viewModel.showCover) {
          Stack() {
            ImageKnifeComponent({ imageKnifeOption: this.coverOption })
              .width(50)
              .height(50)
          }
          .width(50)
          .height(50)
          .borderRadius(4)
          .clip(true)
          .margin({ left: 16 })
          .backgroundColor($r('app.color.salt_color_song_cover'))
        }

        Column() {
          Text(this.viewModel.getDisplayTitle())
            .fontSize(15)
            .fontColor(this.viewModel.isCurrent ? $r('app.color.salt_color_high_light') :
              (this.viewModel.valid ? $r('app.color.salt_color_icon_foreground') : $r('app.color.invalid')))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row() {
            if (this.viewModel.quality === SONG_QUALITY_HQ) {
              Image($r('app.media.bq_song_tag_hq'))
                .width(16)
                .height(10)
                .borderRadius(2)
                .objectFit(ImageFit.Cover)
            } else if (this.viewModel.quality === SONG_QUALITY_SQ) {
              Image($r('app.media.bq_song_tag_sq'))
                .width(16)
                .height(10)
                .borderRadius(2)
                .objectFit(ImageFit.Cover)
            } else if (this.viewModel.quality === SONG_QUALITY_HI_RES) {
              Image($r('app.media.ic_song_quality_hi_res'))
                .width(16)
                .height(10)
                .borderRadius(2)
                .objectFit(ImageFit.Cover)
            }
            Text(this.viewModel.getSubTitleText())
              .fontSize(12)
              .fontColor(this.viewModel.isCurrent ? $r('app.color.salt_color_high_light') :
                (this.viewModel.valid ? $r('app.color.colorSubTextForeground') : $r('app.color.invalid')))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ left: this.viewModel.quality === SONG_QUALITY_NORMAL ? 0 : 4 })
          }
          .margin({ top: 1 })
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: this.viewModel.hasLeftContent() ? 12 : 16, right: 8 })
      }
      .layoutWeight(1)
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.viewModel.handleItemClick()
      })
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.viewModel.handleItemLongClick()
          })
      )

      if (this.viewModel.multiChoiceMode) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.viewModel.checked) {
            Image($r('app.media.ic_item_check'))
              .width(22.5)
              .height(22.5)
              .fillColor($r('app.color.salt_color_high_light'))
          } else {
            Stack() {
            }
            .width(18)
            .height(18)
            .borderRadius(9)
            .border({ width: 1.5, color: $r('app.color.colorSubTextForeground') })
          }
        }
        .width(48)
        .height('100%')
          .onClick(() => {
            this.viewModel.handleCheckedChange(!this.viewModel.checked)
          })
      } else {
        if (this.viewModel.displayAddToPlayNext) {
          Stack({ alignContent: Alignment.Start }) {
            Image($r('app.media.ic_add_small_tinted'))
              .width(13)
              .height(13)
              .borderRadius(6)
              .backgroundColor(this.isSystemDark ? '#10FFFFFF' : '#80FFFFFF')
              .fillColor($r('app.color.colorSubIconForeground'))
              .padding(2)
              .margin({ left: 21 })
              .objectFit(ImageFit.Contain)
          }
          .width(48)
          .height('100%')
          .onClick(() => {
            this.viewModel.handleAddToPlayNext()
            promptAction.showToast({ message: $r('app.string.successfully_added_to_next_play') })
          })
          .accessibilityText('下一首播放')
        }

        Image($r('app.media.ic_more_vert'))
          .width(48)
          .height('100%')
          .padding({ left: 10, right: 18, top: 22, bottom: 22 })
          .fillColor($r('app.color.colorSubTextForeground'))
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.viewModel.handleMenuClick()
          })
          .accessibilityText('菜单')
      }
    }
    .width('100%')
    .height(72)
    .alignItems(VerticalAlign.Center)
  }
}
