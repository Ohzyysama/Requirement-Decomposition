// ArtistItemComponent.ets
// View layer: Artist list item component for Salt Player
// Corresponds to Android ArtistItem composable in ArtistScreen.kt
// Shows: circular cover image | artist name + song count
//
// MVVM: This View uses @ObjectLink to bind to ArtistItemViewModel.
// The ViewModel provides all display data and logic.
// The View only handles UI rendering and delegates events upward.

import { ArtistItemViewModel, ArtistInfoData } from '../viewmodel/ArtistItemViewModel';
import { ImageKnifeComponent } from '@ohos/imageknifepro';

// Re-export for backward compatibility with existing code that imports ArtistInfo
export type ArtistInfo = ArtistInfoData;

@Component
export struct ArtistItemComponent {
  @ObjectLink artistVM: ArtistItemViewModel;
  onItemClick: () => void = () => {};

  aboutToAppear(): void {
    this.artistVM.loadCoverIfNeeded();
  }

  build() {
    // Android ArtistItem: Row with padding(16.dp, 8.dp), verticalAlignment = CenterVertically
    Row() {
      // Artist cover image - circular via Stack clip
      Stack() {
        ImageKnifeComponent({ imageKnifeOption: this.artistVM.coverOption })
          .width(50)
          .height(50)
      }
      .width(50)
      .height(50)
      .borderRadius(25)
      .clip(true)

      // Android: Spacer(width = 12.dp)
      // Then Column with artist name and song count
      Column() {
        // Artist name - Android: SaltTheme.textStyles.main, maxLines=1, ellipsis
        // When name is blank, opacity is 0.35 and shows "未知艺术家"
        Text(this.artistVM.hasName ? this.artistVM.name : $r('app.string.unknown_artist'))
          .fontSize(16)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .opacity(this.artistVM.nameOpacity)

        // Song count - Android: SaltTheme.textStyles.sub, "%d 首"
        Text(this.artistVM.songCountText)
          .fontSize(14)
          .fontColor($r('app.color.colorSubTextForeground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onItemClick();
    })
  }
}
