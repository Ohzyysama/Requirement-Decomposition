// SwitcherRowViewModel.ets
// ViewModel layer: provides observable data and toggle logic for a switcher row
// Bridges the View and Model layers per MVVM architecture

import SwitcherRowModel from '../model/SwitcherRowModel'

@Observed
export default class SwitcherRowViewModel {
  @Track public isOn: boolean = false
  @Track public isEnabled: boolean = true
  @Track public text: Resource = $r('app.string.app_name')

  // Callback to notify parent when the toggle value changes
  @Track public onChange: (val: boolean) => void = () => {
  }

  constructor(model?: SwitcherRowModel, onChange?: (val: boolean) => void) {
    if (model) {
      this.updateFromModel(model)
    }
    if (onChange) {
      this.onChange = onChange
    }
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: SwitcherRowModel): void {
    this.isOn = model.isOn
    this.isEnabled = model.isEnabled
    this.text = model.text
  }

  // Toggle the switch state; only effective when enabled
  toggle(): void {
    if (this.isEnabled) {
      this.isOn = !this.isOn
      this.onChange(this.isOn)
    }
  }
}
