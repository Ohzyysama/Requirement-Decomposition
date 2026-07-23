// MiniPlayerContainer.ets
// Encapsulates the morph mini-player ↔ full-screen player transition
// and the fixed glass-morphism blur-pill background.

import { PlayerPage } from '../PlayerPage'
import { MiniPlayerComponent } from '../../components/MiniPlayerComponent'
import MainPageViewModel from '../../viewmodel/MainPageViewModel'
import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit'
import deviceInfo from '@ohos.deviceInfo'

@Component
export struct MiniPlayerContainer {
  @ObjectLink vm: MainPageViewModel
  @StorageProp('hideBottomBar') hideBottomBar: boolean = false
  // Navigation callbacks injected by MainPage so the full-screen player can
  // push AlbumContentPage / ArtistContentPage onto the host's NavPathStack
  // when the user taps the "出自专辑" / "参与创作的艺术家" rows in the info panel.
  onNavigateToAlbum: (albumTitle: string) => void = () => {}
  onNavigateToArtist: (artistName: string) => void = () => {}

  private morphContainerHeight(): number {
    const sh = this.vm.mainScreenHeight
    const barH = MiniPlayerDefaults.BAR_HEIGHT
    if (sh <= barH) {
      return barH
    }
    const progress = Math.max(0, Math.min(1, this.vm.playerProgress))
    return barH + (sh - barH) * progress
  }

  private morphBorderRadius(): number {
    const p = Math.max(0, Math.min(1, this.vm.playerProgress))
    if (p < 0.9) {
      return 28
    } else {
      const t = (p - 0.9) / 0.1
      return 28 * (1 - t) * (1 - t)
    }
  }

  private morphPaddingHorizontal(): number {
    const p = Math.max(0, Math.min(1, this.vm.playerProgress))
    return 16 * Math.pow(1 - p, 1.8)
  }

  private morphPaddingBottom(): number {
    const p = Math.max(0, Math.min(1, this.vm.playerProgress))
    return MiniPlayerDefaults.BOTTOM_MARGIN * Math.pow(1 - p, 1.8)
  }

  private playerPageOpacity(): number {
    return Math.min(1, Math.max(0, this.vm.playerProgress * 10))
  }

  @Builder
  materialBackground() {
    if (deviceInfo.distributionOSApiVersion >= 60100) {
      HdsTabs()
        .width('100%')
        .height('100%')
        .barOverlap(true)
        .vertical(false)
        .barPosition(BarPosition.End)
        .barHeight(56)
        .barFloatingStyle({
          // 注意：barWidth 不支持百分比（如 '100%'），会导致布局偏移
          // 必须使用具体数值，这里用屏幕宽度 - 32vp 来匹配 MiniPlayer 条宽度
          barWidth: {
            smallWidth: Math.max(0, this.vm.mainScreenWidth - 32),
            mediumWidth: Math.max(0, this.vm.mainScreenWidth - 32),
            largeWidth: Math.max(0, this.vm.mainScreenWidth - 32)
          },
          barBottomMargin: 28,
          systemMaterialEffect: {
            materialType: hdsMaterial.MaterialType.ADAPTIVE,
            materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
          }
        })
    } else {
      Stack()
        .width('calc(100% - 32vp)')
        .height(MiniPlayerDefaults.BAR_HEIGHT)
        .margin({ bottom: MiniPlayerDefaults.BOTTOM_MARGIN })
        .borderRadius(28)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR)
        .backgroundColor($r('app.color.salt_color_floating_material_overlay'))
        .align(Alignment.Bottom)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.materialBackground()

      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.Top }) {
          if (this.vm.playerProgress < 0.1) {
            Stack()
              .width('100%')
              .height('100%')
              .borderRadius(this.morphBorderRadius())
              .border({
                width: 0.5,
                color: $r('app.color.salt_color_floating_material_stroke')
              })
              .hitTestBehavior(HitTestMode.Transparent)
          }

          if (this.vm.showPlayer || this.vm.isPlayerSwiping || this.vm.playerProgress > 0.001) {
            PlayerPage({
              onClose: () => {
                this.vm.closePlayerAnimated((params: AnimateParam, cb: () => void) => {
                  this.getUIContext().animateTo(params, cb)
                })
              },
              onDismissDrag: (progress: number) => {
                this.vm.playerProgress = progress
              },
              onDismissCancel: () => {
                this.vm.bouncePlayerProgressOpen((params: AnimateParam, cb: () => void) => {
                  this.getUIContext().animateTo(params, cb)
                })
              },
              onShowSongMenu: () => {
                this.vm.openSongMenuById(this.vm.currentSongId)
              },
              onNavigateToAlbum: (albumTitle: string) => {
                this.onNavigateToAlbum(albumTitle)
              },
              onNavigateToArtist: (artistName: string) => {
                this.onNavigateToArtist(artistName)
              },
              initialShowQueue: this.vm.initialShowQueue
            })
              .width(this.vm.mainScreenWidth > 0 ? this.vm.mainScreenWidth : '100%')
              .height(this.vm.mainScreenHeight > 0 ? this.vm.mainScreenHeight : '100%')
              .opacity(this.playerPageOpacity())
              .hitTestBehavior(this.vm.playerProgress > 0.1
                ? HitTestMode.Default : HitTestMode.None)
          }

          if (!this.hideBottomBar && this.vm.playerProgress < 0.1) {
            MiniPlayerComponent({
              viewModel: this.vm.miniPlayerVM
            })
              .position({ x: 0, y: 0 })
              .opacity(Math.max(0, 1 - this.vm.playerProgress * 10))
          }
        }
        .width('100%')
        .height(this.morphContainerHeight())
        .borderRadius(this.morphBorderRadius())
        .clip(true)
        .gesture(
          PanGesture({ direction: PanDirection.Vertical, distance: 5 })
            .onActionStart(() => {
              this.vm.handleMorphPullStart()
            })
            .onActionUpdate((event: GestureEvent) => {
              this.vm.handleMorphPullUpdate(event.offsetY)
            })
            .onActionEnd((event: GestureEvent) => {
              this.vm.handleMorphPullEnd(event.offsetY, event.velocityY,
                (params: AnimateParam, cb: () => void) => {
                  this.getUIContext().animateTo(params, cb)
                })
            })
            .onActionCancel(() => {
              this.vm.handleMorphPullEnd(0, 0,
                (params: AnimateParam, cb: () => void) => {
                  this.getUIContext().animateTo(params, cb)
                })
            })
        )
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.morphPaddingHorizontal(),
        right: this.morphPaddingHorizontal(),
        bottom: this.morphPaddingBottom()
      })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .hitTestBehavior(HitTestMode.Transparent)
    .width('100%')
    .height('100%')
  }
}

// ======================== MiniPlayer Defaults ========================
// Mirrors Compose's XXXDefaults pattern: layout constants live alongside
// the component that consumes them, discoverable via MiniPlayerDefaults.XX.

export class MiniPlayerDefaults {
  /** Height of the mini player pill itself. */
  static readonly BAR_HEIGHT: number = 56

  /** Distance from the bottom of the screen to the bottom of the pill. */
  static readonly BOTTOM_MARGIN: number = 28

  /** Total space the mini player occupies from the bottom of the screen. */
  static readonly TOTAL_HEIGHT: number = MiniPlayerDefaults.BAR_HEIGHT + MiniPlayerDefaults.BOTTOM_MARGIN // 84
}
