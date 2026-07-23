// ItemSwitcherWithIconAndSubRowComponent.ets
// Reusable switcher row with icon and subtitle: icon + title/subtitle on the left, toggle on the right.
// Clicking anywhere on the row toggles the switch.
// Uses RippleWrapper for radial shadow press effect.
// Refactored to MVVM: View layer consumes SwitcherWithIconAndSubRowViewModel.

import { RippleWrapper } from './RippleWrapper'
import SwitcherWithIconAndSubRowViewModel from '../viewmodel/SwitcherWithIconAndSubRowViewModel'

@Component
export struct ItemSwitcherWithIconAndSubRowComponent {
  @ObjectLink vm: SwitcherWithIconAndSubRowViewModel

  build() {
    RippleWrapper({
      onAction: () => {
        this.vm.toggle()
      }
    }) {
      Row() {
        Image(this.vm.iconRes)
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .margin({ left: 14 })

        Column() {
          Text(this.vm.text)
            .fontSize(16)
            .fontColor(this.vm.isEnabled ? $r('app.color.salt_color_icon_foreground') : $r('app.color.salt_color_sub_text'))

          Text(this.vm.sub)
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 8, top: 10, bottom: 10 })

        Toggle({ type: ToggleType.Switch, isOn: this.vm.isOn })
          .selectedColor($r('app.color.salt_color_high_light'))
          .margin({ right: 12 })
          .hitTestBehavior(HitTestMode.None)
      }
      .opacity(this.vm.isEnabled ? 1.0 : 0.5)
      .enabled(this.vm.isEnabled)
      .width('100%')
      .constraintSize({ minHeight: 49 })
      .alignItems(VerticalAlign.Center)
    }
  }
}
