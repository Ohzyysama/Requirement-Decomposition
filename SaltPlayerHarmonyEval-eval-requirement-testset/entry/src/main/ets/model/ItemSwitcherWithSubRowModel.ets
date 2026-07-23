// ItemSwitcherWithSubRowModel.ets
// Model layer: pure data structure for a switcher row with subtitle.
// Defines the raw data without any UI or ViewModel logic.

export default class ItemSwitcherWithSubRowModel {
  public text: ResourceStr = ''
  public sub: ResourceStr = ''
  public isOn: boolean = false
  public isEnabled: boolean = true

  constructor(text: ResourceStr = '', sub: ResourceStr = '', isOn: boolean = false, isEnabled: boolean = true) {
    this.text = text
    this.sub = sub
    this.isOn = isOn
    this.isEnabled = isEnabled
  }
}
