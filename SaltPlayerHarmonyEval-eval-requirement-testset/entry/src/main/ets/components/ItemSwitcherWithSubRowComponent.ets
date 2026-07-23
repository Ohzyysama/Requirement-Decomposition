// ItemSwitcherWithSubRowComponent.ets
// View layer: Reusable switcher row component with subtitle.
// Title + subtitle on the left, toggle switch on the right.
// Clicking anywhere on the row toggles the switch, matching Android's whole-row clickable behavior.
// Uses RippleWrapper for radial shadow press effect.
// Follows MVVM pattern: View delegates toggle logic to ViewModel.

import { RippleWrapper } from './RippleWrapper'
import ItemSwitcherWithSubRowViewModel from '../viewmodel/ItemSwitcherWithSubRowViewModel'

@Component
export struct ItemSwitcherWithSubRowComponent {
  @Prop isOn: boolean = false
  @Prop isEnabled: boolean = true
  text: ResourceStr = ''
  sub: ResourceStr = ''
  onChange: (val: boolean) => void = () => {
  }
  // ViewModel instance: created internally from the props provided by the parent.
  // The ViewModel encapsulates the toggle logic and derived display state.
  private viewModel: ItemSwitcherWithSubRowViewModel = new ItemSwitcherWithSubRowViewModel()

  aboutToAppear(): void {
    this.viewModel = new ItemSwitcherWithSubRowViewModel(this.text, this.sub, this.isOn, this.isEnabled)
  }

  build() {
    RippleWrapper({
      onAction: () => {
        if (this.isEnabled) {
          // Delegate toggle logic to ViewModel
          this.viewModel.setIsOn(!this.isOn)
          this.isOn = this.viewModel.isOn
          this.onChange(this.isOn)
        }
      }
    }) {
      Row() {
        Column() {
          Text(this.text)
            .fontSize(16)
            .fontColor(this.isEnabled ? $r('app.color.salt_color_icon_foreground') :
              $r('app.color.salt_color_sub_text'))

          Text(this.sub)
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, top: 10, bottom: 10 })

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .selectedColor($r('app.color.salt_color_high_light'))
          .margin({ right: 12 })
          .hitTestBehavior(HitTestMode.None)
      }
      .opacity(this.isEnabled ? 1.0 : 0.5)
      .enabled(this.isEnabled)
      .width('100%')
      .constraintSize({ minHeight: 49 })
      .alignItems(VerticalAlign.Center)
    }
  }
}
