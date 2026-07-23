// SwitcherWithIconAndSubRowViewModel.ets
// ViewModel layer: provides observable data and toggle logic for a switcher row with icon and subtitle
// Bridges the View and Model layers per MVVM architecture

import SwitcherWithIconAndSubRowModel from '../model/SwitcherWithIconAndSubRowModel'

@Observed
export default class SwitcherWithIconAndSubRowViewModel {
  @Track public isOn: boolean = false
  @Track public isEnabled: boolean = true
  @Track public iconRes: Resource = $r('app.media.ic_crown')
  @Track public text: ResourceStr = ''
  @Track public sub: ResourceStr = ''

  // Callback to notify parent when the toggle value changes
  @Track public onChange: (val: boolean) => void = () => {
  }

  constructor(model?: SwitcherWithIconAndSubRowModel, onChange?: (val: boolean) => void) {
    if (model) {
      this.updateFromModel(model)
    }
    if (onChange) {
      this.onChange = onChange
    }
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: SwitcherWithIconAndSubRowModel): void {
    this.isOn = model.isOn
    this.isEnabled = model.isEnabled
    this.iconRes = model.iconRes
    this.text = model.text
    this.sub = model.sub
  }

  // Toggle the switch state; only effective when enabled
  toggle(): void {
    if (this.isEnabled) {
      this.isOn = !this.isOn
      this.onChange(this.isOn)
    }
  }
}
