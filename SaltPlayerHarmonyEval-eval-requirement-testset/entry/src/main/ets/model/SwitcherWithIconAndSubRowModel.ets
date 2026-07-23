// SwitcherWithIconAndSubRowModel.ets
// Model layer: data structure for a switcher row with icon and subtitle

export default class SwitcherWithIconAndSubRowModel {
  public isOn: boolean = false
  public isEnabled: boolean = true
  public iconRes: Resource = $r('app.media.ic_crown')
  public text: ResourceStr = ''
  public sub: ResourceStr = ''

  constructor(isOn: boolean = false, isEnabled: boolean = true, iconRes: Resource = $r('app.media.ic_crown'),
    text: ResourceStr = '', sub: ResourceStr = '') {
    this.isOn = isOn
    this.isEnabled = isEnabled
    this.iconRes = iconRes
    this.text = text
    this.sub = sub
  }
}
