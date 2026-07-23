// RippleWrapper.ets
// View layer: Generic ripple shadow wrapper component following MVVM architecture.
// Wraps any content and provides a radial shadow effect expanding from the touch point on press.
// Internally delegates ripple animation state and touch logic to RippleWrapperViewModel.
// Usage: RippleWrapper({ onAction: () => { ... } }) { Row() { ... } }

import RippleWrapperViewModel from '../viewmodel/RippleWrapperViewModel'
import RippleWrapperModel from '../model/RippleWrapperModel'

@Component
export struct RippleWrapper {
  @BuilderParam content: () => void = this.defaultContent
  onAction: () => void = () => {}
  rowHeight: number = 49

  // ViewModel manages ripple animation state and touch handling logic
  @State private vm: RippleWrapperViewModel = new RippleWrapperViewModel()

  @Builder
  defaultContent() {
  }

  aboutToAppear(): void {
    const model = new RippleWrapperModel(this.rowHeight)
    this.vm = new RippleWrapperViewModel(model, this.onAction)
  }

  build() {
    Stack() {
      // Radial shadow layer - uses fixed size + scale to avoid affecting Stack layout
      Column()
        .width(1)
        .height(1)
        .scale({ x: this.vm.rippleScale, y: this.vm.rippleScale })
        .position({
          x: this.vm.rippleX,
          y: this.vm.rippleY
        })
        .radialGradient({
          center: ['50%', '50%'],
          radius: '50%',
          colors: [
            ['#1A000000', 0.0],
            ['#0D000000', 0.5],
            ['#00000000', 1.0]
          ]
        })
        .borderRadius('50%')
        .opacity(this.vm.rippleOpacity)
        .hitTestBehavior(HitTestMode.None)

      this.content()
    }
    .width('100%')
    .constraintSize({ minHeight: this.vm.rowHeight })
    .clip(true)
    .onClick(() => {
      this.vm.handleAction()
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        const touch = event.touches[0]
        this.vm.handleTouchDown(touch.x, touch.y)
        animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
          this.vm.expandRipple()
        })
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
          this.vm.fadeOutRipple()
        })
      }
    })
  }
}

// 调整空行，无功能变更。

// 顺手整理空行，无功能变更。

// 整理空行，无功能变更。
