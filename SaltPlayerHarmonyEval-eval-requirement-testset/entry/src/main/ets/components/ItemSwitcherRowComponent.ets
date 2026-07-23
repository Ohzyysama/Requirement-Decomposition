// ItemSwitcherRowComponent.ets
// View layer: Reusable switcher row component following MVVM architecture.
// Displays a text label on the left and a toggle switch on the right.
// Clicking anywhere on the row toggles the switch, matching Android's whole-row clickable behavior.
// Uses RippleWrapper for radial shadow press effect.
// Binds to SwitcherRowViewModel via @ObjectLink for observable state management.

import { RippleWrapper } from './RippleWrapper'
import SwitcherRowViewModel from '../viewmodel/SwitcherRowViewModel'

@Component
export struct ItemSwitcherRowComponent {
  @ObjectLink vm: SwitcherRowViewModel

  build() {
    RippleWrapper({
      onAction: () => {
        this.vm.toggle()
      }
    }) {
      Row() {
        Text(this.vm.text)
          .fontSize(16)
          .fontColor(this.vm.isEnabled ? $r('app.color.salt_color_icon_foreground') : $r('app.color.salt_color_sub_text'))
          .layoutWeight(1)
          .margin({ left: 16 })

        Toggle({ type: ToggleType.Switch, isOn: this.vm.isOn })
          .selectedColor($r('app.color.salt_color_high_light'))
          .margin({ right: 12 })
          .hitTestBehavior(HitTestMode.None)
      }
      .opacity(this.vm.isEnabled ? 1.0 : 0.8)
      .enabled(this.vm.isEnabled)
      .width('100%')
      .constraintSize({ minHeight: 49 })
      .alignItems(VerticalAlign.Center)
    }
  }
}
