import AddToPlaylistDialogViewModel from '../viewmodel/AddToPlaylistDialogViewModel'
import { PlaylistItemViewModel } from '../viewmodel/PlaylistTabViewModel'
import { NewPlaylistDialogComponent } from './NewPlaylistDialogComponent'
import PlaylistModel from '../model/PlaylistModel'
import { MainPageDataSource } from '../model/MainPageModel'
import { NewPlaylistDataSource, PlaylistValidation } from '../model/NewPlaylistModel'
import { promptAction } from '@kit.ArkUI'
import { CoverCacheDb } from '../model/CoverCacheDb'
import { CoverArtExtractor } from '../model/CoverArtExtractor'
import { ImageKnifeComponent, ImageKnifeOption } from '@ohos/imageknifepro'

// Per-row cover for the add-to-playlist sheet. Same lazy-load pattern as the
// PlaylistTab but sized at 44dp to match the sheet's compact rows. Keeping
// this local (not shared) keeps the sheet self-contained and avoids wiring a
// new shared file just for two call sites.
@Component
struct AddToPlaylistRowCover {
  @Prop @Watch('onCoverSongIdChanged') coverSongId: string = ''
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

  onCoverSongIdChanged(): void {
    if (this.coverSongId !== this.loadedCoverKey) {
      this.loadCover()
    }
  }

  loadCover(): void {
    const songId = this.coverSongId
    this.loadedCoverKey = songId
    if (!songId || songId.length === 0) return
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
    Stack() {
      ImageKnifeComponent({ imageKnifeOption: this.coverOption })
        .width(44)
        .height(44)
    }
    .width(44)
    .height(44)
  }
}

@CustomDialog
export struct AddToPlaylistDialogComponent {
  // Declared for @CustomDialog framework compatibility, but NOT relied on for
  // self-close. In this codebase the auto-wired `this.controller` has proven
  // undefined inside deferred callbacks (setTimeout / .then) when the dialog
  // is opened through nested setTimeout builders from song-menu sheets —
  // `this.controller.close()` crashed with TypeError: Cannot read property
  // close of undefined. Self-close now routes through `onDismiss`, which the
  // host page fulfils with its own `addToPlaylistDialogController?.close()`.
  controller: CustomDialogController

  // Component-owned @State for the rendered list. Previously we relied on
  // @State viewModel: @Observed VM with @Track playlists inside; under the
  // @CustomDialog + aboutToAppear-reassignment path ArkTS V1 lost the
  // observation chain between the freshly-constructed VM and the component's
  // state proxy, so the async DB load that populated vm.playlists never
  // triggered a rebuild — the list rendered empty until another reload path
  // (e.g. addNewPlaylist) fired after the proxy was fully wired. Holding the
  // rendered items directly as @State on the component sidesteps the race.
  @State playlists: PlaylistItemViewModel[] = []

  private viewModel: AddToPlaylistDialogViewModel = new AddToPlaylistDialogViewModel()

  // Spec6 S3: if this picker is open while a song is removed from a playlist
  // (via the playlist detail page or any other surface), the song-count badge
  // next to each playlist must reflect the new count. The removers bump
  // 'playlistVersion' after their DB write — watch it and reload.
  @StorageProp('playlistVersion') @Watch('onPlaylistVersionChanged') playlistVersion: number = 0

  songId: string = ''
  // Ordered list of song ids for the multi-select call sites. Falls back to
  // [songId] internally when empty — the single-song menu entry keeps passing
  // songId alone.
  selectedSongIds: string[] = []
  onPlaylistSelected: (playlistId: string, playlistName: string) => void = () => {}
  // Close-the-sheet callback. The host page passes `() => controller?.close()`
  // pointing at its OWN addToPlaylistDialogController field — bypassing the
  // unreliable @CustomDialog `this.controller` auto-wire (see controller doc
  // comment above). Fired after a successful pick so the sheet auto-dismisses.
  onDismiss: () => void = () => {}
  // Fired after a successful DB insert of a new playlist. Lets the parent
  // (MainPage) refresh its PlaylistTab VM so Scenario 3 step 6 still holds
  // when the dialog is opened from the song menu / multi-choice bar.
  onPlaylistCreated: (model: PlaylistModel) => void = () => {}

  private newPlaylistDialogController: CustomDialogController = new CustomDialogController({
    builder: NewPlaylistDialogComponent({})
  })

  aboutToAppear(): void {
    this.viewModel = new AddToPlaylistDialogViewModel(
      this.songId,
      this.onPlaylistSelected,
      this.onDismiss,
      this.selectedSongIds
    )
    // Kick off the DB load AFTER the component's @State has been wired, so the
    // eventual assignment to this.playlists triggers the rebuild. Fire-and-
    // forget is fine; reloadItems writes to the component's @State directly.
    this.reloadItems()
  }

  onPlaylistVersionChanged(): void {
    this.reloadItems()
  }

  private async reloadItems(): Promise<void> {
    const models: PlaylistModel[] = await MainPageDataSource.loadPlaylistsFromDb()
    this.playlists = models.map((model: PlaylistModel) => {
      return new PlaylistItemViewModel(model.id, model.name, model.count, model.coverSongId)
    })
  }

  build() {
    Column() {
      Text($r('app.string.add_to_playlist'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 14, right: 14, top: 14, bottom: 12 })

      List() {
        ForEach(this.playlists, (item: PlaylistItemViewModel) => {
          ListItem() {
            Row() {
              // Playlist cover — lazy-loaded via CoverCacheDb, same pattern as
              // the main playlist tab. Renders the default placeholder until
              // the JPEG is ensured on disk.
              Stack() {
                AddToPlaylistRowCover({ coverSongId: item.coverSongId })
              }
              .width(44)
              .height(44)
              .borderRadius(6)
              .clip(true)

              Column() {
                Text(item.name)
                  .fontSize(14)
                  .fontColor($r('app.color.salt_color_icon_foreground'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                Text(item.getSongCountText())
                  .fontSize(12)
                  .fontColor($r('app.color.colorSubTextForeground'))
                  .maxLines(1)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .margin({ left: 12 })
              .alignItems(HorizontalAlign.Start)
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .height(60)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              const playlistId = item.id
              const playlistName = item.name
              // Persist first; after the commit resolves, re-render the
              // component's own list so the tapped row's song count visibly
              // bumps (+1) before the dialog auto-dismisses — the @Watch on
              // playlistVersion also fires a reload, but it's fire-and-forget
              // and can race past the 100ms close timer below. Then fire the
              // host's onPlaylistSelected (toast) and close the sheet. Mirrors
              // the Android AddToPlaylistDialog which calls onAfterAdded after
              // a short delay (Scenario 10: dialog closes on successful pick).
              this.viewModel.commitAddToPlaylist(playlistId).then(() => {
                // The explicit reloadItems() that used to run here was redundant
                // — commitAddToPlaylist bumps 'playlistVersion' which fires
                // onPlaylistVersionChanged → reloadItems() automatically. On
                // a 2000-song multi-select add this saved an extra full-list
                // playlist read between commit and dismiss, which the user
                // perceived as the dialog hanging for several seconds.
                setTimeout(() => {
                  this.viewModel.onPlaylistSelected(playlistId, playlistName)
                  // Close via host-supplied callback. Do NOT use
                  // this.controller.close() here — the auto-wired controller
                  // field resolves to undefined inside this deferred
                  // setTimeout + .then chain under the nested-setTimeout open
                  // path used by song-menu sheets, crashing with TypeError.
                  this.onDismiss()
                }, 100)
              })
            })
          }
          // Key includes count so ForEach re-renders a row when its song-count
          // changes after commitAddToPlaylist — keying on id alone caused
          // ArkUI to reuse the existing ListItem with the old count closure,
          // which is why the +1 only showed after closing and reopening the
          // dialog.
        }, (item: PlaylistItemViewModel) => `${item.id}_${item.count}`)
      }
      .width('100%')
      .layoutWeight(1)

      Row() {
        Button($r('app.string.new_playlist'))
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.salt_color_high_light'))
          .borderRadius(21)
          .onClick(() => {
            this.newPlaylistDialogController = new CustomDialogController({
              builder: NewPlaylistDialogComponent({
                onConfirm: (name: string) => {
                  // Validate up-front so Scenario 1/2 show their toast and we
                  // skip the DB write entirely — the dialog itself has already
                  // closed on this tick, so the toast surfaces on top of the
                  // AddToPlaylist sheet.
                  const result = NewPlaylistDataSource.validate(name)
                  if (result === PlaylistValidation.EMPTY) {
                    promptAction.showToast({
                      message: $r('app.string.playlist_name_must_not_be_empty')
                    })
                    return
                  }
                  if (result === PlaylistValidation.TOO_LONG) {
                    promptAction.showToast({
                      message: $r('app.string.number_of_characters_is_too_long')
                    })
                    return
                  }
                  this.viewModel.addNewPlaylist(name).then((created: PlaylistModel | null) => {
                    if (created) {
                      // Refresh our own rendered list so the new playlist
                      // shows up in the sheet immediately, and let the parent
                      // refresh its PlaylistTab list too.
                      this.reloadItems()
                      this.onPlaylistCreated(created)
                    }
                  })
                }
              }),
              alignment: DialogAlignment.Center,
              customStyle: true,
              maskColor: '#80000000'
            })
            this.newPlaylistDialogController.open()
          })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 14 })
    }
    .width('78%')
    .constraintSize({ maxHeight: '70%' })
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_sub_background'))
    .clip(true)
  }
}
