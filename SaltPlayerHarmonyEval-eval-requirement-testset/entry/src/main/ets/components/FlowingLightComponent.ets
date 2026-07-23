// FlowingLightComponent.ets
// View layer: renders the flowing light background effect.
//
// Matches Android FlowingLightView rendering pipeline:
//   1. Draw 3 rotated cover layers with saturation boost
//   2. Draw overlay colors on the same surface
//   3. Apply heavy blur to the combined result
//   4. Display at full screen size
//
// In Android, steps 1-3 happen on a tiny canvas (~44x95px) then scaled 32x.
// In ArkUI, we use large image scale (250%) + heavy blur (150) to approximate
// the same heavily-abstracted gradient effect.
//
// IMPORTANT: Image sources MUST be accessed directly via this.viewModel.coverPixelMap
// (through @ObjectLink → @Track reactivity), NOT passed as @Builder parameters.
// @Builder parameters are passed by value and do NOT trigger re-render when the
// source @Track property changes.

import FlowingLightViewModel from '../viewmodel/FlowingLightViewModel'
import { FlowingLightConfig } from '../model/FlowingLightModel'
import { AnimatorResult } from '@kit.ArkUI'

@Component
export struct FlowingLightComponent {
  @ObjectLink viewModel: FlowingLightViewModel

  // Observe dynamicFlowingLight toggle and playback state from AppStorage
  @StorageProp('dynamicFlowingLight') @Watch('onDynamicFlowingLightChanged')
  dynamicFlowingLight: boolean = true
  @StorageProp('isPlaying') @Watch('onPlayStateChanged') isPlayingProp: boolean = false


  // Explicit animator instances — the only reliable way to play/pause
  // infinite-loop animations in ArkUI.
  // Animator instances created via UIContext.createAnimator (API 11+).
  private anim1: AnimatorResult | null = null
  private anim2: AnimatorResult | null = null
  private anim3: AnimatorResult | null = null

  aboutToAppear(): void {
    this.createAnimators()
    this.syncRotationState()
  }

  aboutToDisappear(): void {
    this.destroyAnimators()
  }

  private createAnimators(): void {
    this.anim1 = this.getUIContext().createAnimator({
      duration: FlowingLightConfig.ROTATION_PERIOD_1,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: 360
    })
    this.anim1.onFrame = (value: number) => {
      this.viewModel.rotation1 = value
    }

    this.anim2 = this.getUIContext().createAnimator({
      duration: FlowingLightConfig.ROTATION_PERIOD_2,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: -360
    })
    this.anim2.onFrame = (value: number) => {
      this.viewModel.rotation2 = value
    }

    this.anim3 = this.getUIContext().createAnimator({
      duration: FlowingLightConfig.ROTATION_PERIOD_3,
      easing: 'linear',
      delay: 0,
      fill: 'none',
      direction: 'normal',
      iterations: -1,
      begin: 0,
      end: -360
    })
    this.anim3.onFrame = (value: number) => {
      this.viewModel.rotation3 = value
    }
  }

  private destroyAnimators(): void {
    if (this.anim1) {
      this.anim1.onFrame = (_value: number) => {}
      this.anim1.cancel()
      this.anim1 = null
    }
    if (this.anim2) {
      this.anim2.onFrame = (_value: number) => {}
      this.anim2.cancel()
      this.anim2 = null
    }
    if (this.anim3) {
      this.anim3.onFrame = (_value: number) => {}
      this.anim3.cancel()
      this.anim3 = null
    }
    this.viewModel.isRotating = false
  }

  // Unified condition: should the flowing light rotate?
  // Rotation runs when:
  //   1. dynamicFlowingLight setting is ON
  //   2. music is currently playing
  // Note: rotation stops automatically when the component is destroyed
  // (aboutToDisappear cancels the animators).
  private shouldRotate(): boolean {
    return this.dynamicFlowingLight && this.isPlayingProp
  }

  // Sync animation state with current conditions without duplicate start/stop
  private syncRotationState(): void {
    const should = this.shouldRotate()
    const isRotating = this.viewModel.isRotating
    if (should && !isRotating) {
      this.viewModel.isRotating = true
      this.anim1?.play()
      this.anim2?.play()
      this.anim3?.play()
    } else if (!should && isRotating) {
      this.viewModel.isRotating = false
      this.anim1?.pause()
      this.anim2?.pause()
      this.anim3?.pause()
    }
  }

  // Toggle changed at runtime (user toggles in Settings while player is open)
  onDynamicFlowingLightChanged(): void {
    this.syncRotationState()
  }

  // Play/pause state changed
  onPlayStateChanged(): void {
    this.syncRotationState()
  }


  build() {
    Stack() {
      // Cross-fade: previous cover (fading out)
      if (this.viewModel.isCrossFading && this.viewModel.previousCoverPixelMap) {
        Stack() {
          Image(this.viewModel.previousCoverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation1 })

          Image(this.viewModel.previousCoverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation2 })
            .translate({ x: '-95%', y: '-70%' })

          Image(this.viewModel.previousCoverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation3 })
            .translate({ x: '-50%', y: '70%' })

          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.viewModel.overlayColor1)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.viewModel.overlayColor2)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .blur(FlowingLightConfig.BLUR_RADIUS)
        .opacity(this.viewModel.previousOpacity)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }

      // Current cover — accessed directly via @ObjectLink for reactivity
      if (this.viewModel.coverPixelMap) {
        Stack() {
          // Layer 1: centered, clockwise rotation
          Image(this.viewModel.coverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation1 })

          // Layer 2: offset top-left, counter-clockwise rotation
          // Android: postTranslate(-0.95f * width, -0.7f * height)
          Image(this.viewModel.coverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation2 })
            .translate({ x: '-95%', y: '-70%' })

          // Layer 3: offset bottom-left, counter-clockwise with extra center rotation
          // Android: postTranslate(-0.5f * width, 0.7f * height) + postRotate(angle, cx, cy)
          Image(this.viewModel.coverPixelMap)
            .width(FlowingLightConfig.IMAGE_SCALE)
            .height(FlowingLightConfig.IMAGE_SCALE)
            .objectFit(ImageFit.Cover)
            .colorFilter(this.viewModel.saturationMatrix)
            .rotate({ angle: this.viewModel.rotation3 })
            .translate({ x: '-50%', y: '70%' })

          // Overlay colors — drawn INSIDE the blur area to match Android's
          // drawAdditionalColors() which paints on the canvas BEFORE blur.
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.viewModel.overlayColor1)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.viewModel.overlayColor2)
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        }
        .width('100%')
        .height('100%')
        .blur(FlowingLightConfig.BLUR_RADIUS)
        .opacity(this.viewModel.currentOpacity)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .opacity(FlowingLightConfig.LAYER_OPACITY)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

// 流光效果：渲染随音乐律动的流光动画。
