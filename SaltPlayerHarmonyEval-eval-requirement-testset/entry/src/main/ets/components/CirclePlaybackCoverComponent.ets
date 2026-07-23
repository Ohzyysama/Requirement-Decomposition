// CirclePlaybackCoverComponent.ets
// View layer: renders the playback cover as a rotating circle.
//
// Self-contained cover management: subscribes to CurrentSongCoverController
// for cover updates. Observes:
//   - CurrentSongCoverController    → cover PixelMap changes
//   - AppStorage('isPlaying')       → pause / resume rotation
//   - AppStorage('currentSongId')   → 250ms reset to angle 0 on song change

import { AnimatorResult } from '@kit.ArkUI'
import { image } from '@kit.ImageKit'
import { CurrentSongCoverController, CurrentCoverListener } from '../model/CurrentSongCoverController'

@Component
export struct CirclePlaybackCoverComponent {
  onLongPress: () => void = () => {}
  forceCircle: boolean = false

  @StorageProp('isPlaying') @Watch('onPlayStateChanged') isPlayingProp: boolean = false
  @StorageProp('currentSongId') @Watch('onSongChanged') songId: string = ''

  @State private coverPixelMap: image.PixelMap | undefined = undefined
  @State private rotationDeg: number = 0
  private anim: AnimatorResult | null = null
  private baseAngle: number = 0
  private isResetting: boolean = false
  private coverListener: CurrentCoverListener = (_songId, pm) => {
    this.coverPixelMap = pm
  }

  private static readonly ROTATION_DURATION_MS: number = 25_000
  private static readonly RESET_DURATION_MS: number = 250

  aboutToAppear(): void {
    CurrentSongCoverController.getInstance().addListener(this.coverListener)
    this.createAnimator()
    this.syncRotationState()
  }

  aboutToDisappear(): void {
    CurrentSongCoverController.getInstance().removeListener(this.coverListener)
    this.destroyAnimator()
  }

  private createAnimator(): void {
    this.anim = this.getUIContext().createAnimator({
      duration: CirclePlaybackCoverComponent.ROTATION_DURATION_MS,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: 360,
    })
    this.anim.onFrame = (value: number) => {
      if (!this.isResetting) {
        this.rotationDeg = (value + this.baseAngle) % 360
      }
    }
  }

  private destroyAnimator(): void {
    if (this.anim) {
      this.anim.onFrame = (_v: number) => {}
      this.anim.cancel()
      this.anim = null
    }
  }

  private syncRotationState(): void {
    if (this.isResetting) {
      return
    }
    if (this.isPlayingProp) {
      this.destroyAnimator()
      this.createAnimator()
      this.anim?.play()
    } else {
      this.baseAngle = this.rotationDeg
      this.anim?.pause()
    }
  }

  onPlayStateChanged(): void {
    this.syncRotationState()
  }

  onSongChanged(): void {
    // Scenes 4 / 5: smooth 250ms return to 0, then (conditionally) restart
    // from 0. Driven by animateTo so the animator can be destroyed + recreated
    // cleanly instead of fighting its own infinite progress.
    this.isResetting = true
    this.anim?.pause()
    const ctx = this.getUIContext()
    ctx.animateTo({
      duration: CirclePlaybackCoverComponent.RESET_DURATION_MS,
      curve: Curve.Linear,
      onFinish: () => {
        this.isResetting = false
        this.baseAngle = 0
        this.rotationDeg = 0
        // Recreate so the animator's internal progress aligns with angle 0.
        this.destroyAnimator()
        this.createAnimator()
        if (this.isPlayingProp) {
          this.anim?.play()
        }
      },
    }, () => {
      this.rotationDeg = 0
    })
  }

  build() {
    Column() {
      if (this.coverPixelMap) {
        Stack() {
          Image(this.coverPixelMap)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius({
              topLeft: 9999,
              topRight: 9999,
              bottomLeft: 9999,
              bottomRight: 9999,
            })
            .clip(true)
            .rotate({ angle: this.rotationDeg })
            .shadow({
              radius: 30,
              color: '#0d000000',
              offsetX: 0,
              offsetY: 6,
            })
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  this.onLongPress()
                })
            )
        }
        .width('100%')
        .aspectRatio(1)
      }
    }
    .width('85%')
    .aspectRatio(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// 圆形播放封面：播放时每25秒匀速旋转一圈，暂停保持角度，切歌回归0度。
