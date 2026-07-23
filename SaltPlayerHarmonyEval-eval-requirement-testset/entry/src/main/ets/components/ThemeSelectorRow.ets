// ThemeSelectorRow.ets
// Reusable 3-option theme selector (Follow System / Light / Dark).
//
// Self-contained: binds to AppStorage('selectedTheme') directly and persists
// writes via SettingsStore — no ViewModel prop required so it can be dropped
// onto any settings page. The inner ThemeOptionComponent is shared.

import { ConfigurationConstant } from '@kit.AbilityKit'
import { MainMenuDataSource, ThemeMode } from '../model/MainMenuModel'
import SettingsStore from '../model/SettingsStore'

@Component
export struct ThemeSelectorRow {
  @StorageLink('selectedTheme') selectedTheme: number = 0

  private onSelect(theme: number): void {
    if (this.selectedTheme !== theme) {
      this.selectedTheme = theme
      SettingsStore.getInstance().save('selectedTheme', theme)
    }
    const colorMode: ConfigurationConstant.ColorMode =
      MainMenuDataSource.getColorModeForTheme(theme as ThemeMode)
    this.getUIContext().getHostContext()!.getApplicationContext().setColorMode(colorMode)
  }

  build() {
    Row({ space: 10 }) {
      Column() {
        ThemeOptionComponent({
          iconRes: $r('app.media.ic_harmony'),
          text: $r('app.string.follow_system'),
          selected: this.selectedTheme === 0,
          iconWidth: 77,
          iconHeight: 16,
          onSelect: () => this.onSelect(0),
        })
      }.layoutWeight(1)

      Column() {
        ThemeOptionComponent({
          iconRes: $r('app.media.ic_light'),
          text: $r('app.string.light'),
          selected: this.selectedTheme === 1,
          onSelect: () => this.onSelect(1),
        })
      }.layoutWeight(1)

      Column() {
        ThemeOptionComponent({
          iconRes: $r('app.media.ic_dark'),
          text: $r('app.string.dark'),
          selected: this.selectedTheme === 2,
          onSelect: () => this.onSelect(2),
        })
      }.layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 14, bottom: 4 })
    .justifyContent(FlexAlign.Start)
  }
}

@Component
export struct ThemeOptionComponent {
  @Prop selected: boolean = false
  iconRes: Resource = $r('app.media.ic_harmony')
  text: Resource = $r('app.string.app_name')
  iconWidth: number = 24
  iconHeight: number = 24
  onSelect: () => void = () => {}

  build() {
    Column() {
      Row() {
        Image(this.iconRes)
          .width(this.iconWidth)
          .height(this.iconHeight)
          .objectFit(ImageFit.Contain)
          .fillColor(this.selected ? $r('sys.color.brand') : $r('sys.color.icon_secondary'))
      }
      .width('100%')
      .height(24)
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 4 })

      Text(this.text)
        .fontSize(12)
        .fontColor(this.selected ? $r('sys.color.brand') : $r('sys.color.icon_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
        .marqueeOptions({
          loop: 1,
          start: true,
          step: 3,
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 6, right: 6, top: 10, bottom: 10 })
    .borderRadius(12)
    .borderWidth(1)
    .borderColor(this.selected ? $r('sys.color.brand') : $r('sys.color.comp_divider'))
    .backgroundColor(this.selected ? $r('app.color.salt_color_button_background') : Color.Transparent)
    .clip(true)
    .onClick(() => {
      this.onSelect()
    })
  }
}
