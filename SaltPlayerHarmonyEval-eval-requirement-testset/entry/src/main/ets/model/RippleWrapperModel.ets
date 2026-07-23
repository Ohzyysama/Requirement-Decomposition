// RippleWrapperModel.ets
// Model layer: data structure for ripple wrapper configuration and state

export default class RippleWrapperModel {
  public rippleX: number = 0
  public rippleY: number = 0
  public rippleScale: number = 0
  public rippleOpacity: number = 0
  public rowHeight: number = 49

  constructor(rowHeight: number = 49) {
    this.rowHeight = rowHeight
  }
}
