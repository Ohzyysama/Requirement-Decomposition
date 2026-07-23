// TabletModeViewModel.ets
// ViewModel layer: provides observable data and business logic for Tablet Mode settings page
// Bridges the View and Model layers per MVVM architecture

import TabletModeModel from '../model/TabletModeModel'

@Observed
export default class TabletModeViewModel {
  @Track public spaceBarPlayOrPause: boolean = true

  constructor(model?: TabletModeModel) {
    if (model) {
      this.updateFromModel(model)
    }
  }

  // Update ViewModel properties from Model data
  updateFromModel(model: TabletModeModel): void {
    this.spaceBarPlayOrPause = model.spaceBarPlayOrPause
  }

  // Export current ViewModel state to Model
  toModel(): TabletModeModel {
    return new TabletModeModel(this.spaceBarPlayOrPause)
  }

  // Toggle the space bar play/pause setting
  toggleSpaceBarPlayOrPause(): void {
    this.spaceBarPlayOrPause = !this.spaceBarPlayOrPause
    console.info('Space bar play/pause toggled: ' + this.spaceBarPlayOrPause)
  }

  // Set the space bar play/pause setting to a specific value
  setSpaceBarPlayOrPause(isOn: boolean): void {
    this.spaceBarPlayOrPause = isOn
    console.info('Space bar play/pause toggled: ' + isOn)
  }
}

// 平板模式：空格键开关状态。
