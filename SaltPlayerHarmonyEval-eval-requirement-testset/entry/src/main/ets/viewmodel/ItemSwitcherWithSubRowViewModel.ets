// ItemSwitcherWithSubRowViewModel.ets
// ViewModel layer: provides data and logic for ItemSwitcherWithSubRowComponent (View).
// Bridges the Model layer data with the View layer, exposing state variables and methods.

import ItemSwitcherWithSubRowModel from '../model/ItemSwitcherWithSubRowModel'

@Observed
export default class ItemSwitcherWithSubRowViewModel {
  @Track public isOn: boolean = false
  @Track public isEnabled: boolean = true
  @Track public text: ResourceStr = ''
  @Track public sub: ResourceStr = ''

  constructor(text: ResourceStr = '', sub: ResourceStr = '', isOn: boolean = false, isEnabled: boolean = true) {
    this.text = text
    this.sub = sub
    this.isOn = isOn
    this.isEnabled = isEnabled
  }

  // Load state from Model data
  updateFromModel(model: ItemSwitcherWithSubRowModel): void {
    this.text = model.text
    this.sub = model.sub
    this.isOn = model.isOn
    this.isEnabled = model.isEnabled
  }

  // Export current state back to Model
  toModel(): ItemSwitcherWithSubRowModel {
    return new ItemSwitcherWithSubRowModel(this.text, this.sub, this.isOn, this.isEnabled)
  }

  // Toggle the switch on/off. Returns the new value.
  toggle(): boolean {
    if (this.isEnabled) {
      this.isOn = !this.isOn
    }
    return this.isOn
  }

  // Directly set the switch value
  setIsOn(value: boolean): void {
    this.isOn = value
  }

  // Get the text color based on enabled state
  getTextColor(): Resource {
    return this.isEnabled ? $r('app.color.salt_color_icon_foreground') : $r('app.color.salt_color_sub_text')
  }

  // Get the row opacity based on enabled state
  getRowOpacity(): number {
    return this.isEnabled ? 1.0 : 0.5
  }
}
