// RippleWrapperViewModel.ets
// ViewModel layer: provides observable ripple animation state and touch handling logic
// Bridges the View and Model layers per MVVM architecture

import RippleWrapperModel from '../model/RippleWrapperModel'

@Observed
export default class RippleWrapperViewModel {
  @Track public rippleX: number = 0
  @Track public rippleY: number = 0
  @Track public rippleScale: number = 0
  @Track public rippleOpacity: number = 0
  @Track public rowHeight: number = 49

  // Callback to notify parent when the action (click) occurs
  @Track public onAction: () => void = () => {
  }

  constructor(model?: RippleWrapperModel, onAction?: () => void) {
    if (model) {
      this.updateFromModel(model)
    }
    if (onAction) {
      this.onAction = onAction
    }
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: RippleWrapperModel): void {
    this.rippleX = model.rippleX
    this.rippleY = model.rippleY
    this.rippleScale = model.rippleScale
    this.rippleOpacity = model.rippleOpacity
    this.rowHeight = model.rowHeight
  }

  // Handle touch down: set ripple origin and start expand animation
  handleTouchDown(touchX: number, touchY: number): void {
    this.rippleX = touchX
    this.rippleY = touchY
    this.rippleScale = 0
    this.rippleOpacity = 1
  }

  // Set the ripple scale to the expanded target value (called inside animateTo)
  expandRipple(): void {
    this.rippleScale = 1000
  }

  // Fade out the ripple (called inside animateTo)
  fadeOutRipple(): void {
    this.rippleOpacity = 0
  }

  // Handle the click action
  handleAction(): void {
    this.onAction()
  }
}
