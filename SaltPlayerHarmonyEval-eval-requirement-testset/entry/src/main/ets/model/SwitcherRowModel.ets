// SwitcherRowModel.ets
// Model layer: data structure for a switcher row item

export default class SwitcherRowModel {
  public isOn: boolean = false
  public isEnabled: boolean = true
  public text: Resource = $r('app.string.app_name')

  constructor(isOn: boolean = false, isEnabled: boolean = true, text: Resource = $r('app.string.app_name')) {
    this.isOn = isOn
    this.isEnabled = isEnabled
    this.text = text
  }
}
