// SleepTimerDialogComponent.ets
// View layer: bottom sheet component for sleep timer settings and countdown display
// Corresponds to Android SleepTimerDialog.kt
// Shows setup view (slider + start) or countdown view (timer + stop) based on timer state

import SleepTimerDialogViewModel from '../viewmodel/SleepTimerDialogViewModel'
import { promptAction } from '@kit.ArkUI'

@Component
export struct SleepTimerDialogComponent {
  onStart: (minutes: number, autoExtend: boolean) => void = () => {}
  onDismiss: () => void = () => {}

  @State viewModel: SleepTimerDialogViewModel = new SleepTimerDialogViewModel()
  @StorageProp('navBarHeight') navBarHeight: number = 28
  @StorageProp('isSystemDark') isSystemDark: boolean = false
  private countdownRefreshId: number = -1

  aboutToAppear(): void {
    this.viewModel.syncFromService()
    if (this.viewModel.isCountdownActive) {
      this.startCountdownRefresh()
    }
  }

  aboutToDisappear(): void {
    this.stopCountdownRefresh()
  }

  private startCountdownRefresh(): void {
    if (this.countdownRefreshId !== -1) {
      return
    }
    this.countdownRefreshId = setInterval(() => {
      this.viewModel.syncFromService()
      if (!this.viewModel.isCountdownActive) {
        this.stopCountdownRefresh()
      }
    }, 1000)
  }

  private stopCountdownRefresh(): void {
    if (this.countdownRefreshId !== -1) {
      clearInterval(this.countdownRefreshId)
      this.countdownRefreshId = -1
    }
  }

  build() {
    Column() {
      // Dialog title
      Text($r('app.string.sleep_timer'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .width('100%')
        .padding({ left: 14, right: 14, top: 14, bottom: 14 })

      // Main content card
      Column() {
        if (this.viewModel.isCountdownActive) {
          // ==================== COUNTDOWN VIEW ====================

          // Large countdown text
          Text(this.viewModel.countdownText)
            .fontSize(56)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ top: 40, bottom: 40 })

          // Stop button
          Button($r('app.string.stop'))
            .type(ButtonType.Capsule)
            .width('90%')
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.salt_color_high_light'))
            .margin({ bottom: 16 })
            .onClick(() => {
              this.viewModel.stopTimer()
              this.stopCountdownRefresh()
              try {
                promptAction.showToast({ message: '睡眠定时已停止' })
              } catch (_e) {
                // ignore
              }
            })

          // Divider
          Divider()
            .color($r('app.color.colorDividerBackground'))
            .width('100%')

          // Safety tips
          Text($r('app.string.dialog_sleep_timer_tips'))
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 14 })

        } else {
          // ==================== SETUP VIEW ====================

          // Duration row: "时长" label + "N 分钟" value
          Row() {
            Text($r('app.string.duration'))
              .fontSize(16)
              .fontColor($r('app.color.salt_color_icon_foreground'))

            Blank()

            Text(`${this.viewModel.sleepMinutes} 分钟`)
              .fontSize(16)
              .fontColor($r('app.color.salt_color_sub_text'))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10 })

          // Duration slider (1~120 minutes)
          Slider({
            value: this.viewModel.sleepMinutes,
            min: this.viewModel.getMinMinutes(),
            max: this.viewModel.getMaxMinutes(),
            step: this.viewModel.getSliderStep()
          })
            .blockColor($r('app.color.salt_color_high_light'))
            .trackColor('#e0e0e0')
            .selectedColor($r('app.color.salt_color_high_light'))
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 12 })
            .onChange((value: number) => {
              this.viewModel.updateSleepMinutes(value)
            })

          // Start button
          Button($r('app.string.start'))
            .type(ButtonType.Capsule)
            .width('90%')
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.salt_color_high_light'))
            .margin({ bottom: 16 })
            .onClick(() => {
              const config = this.viewModel.startTimer()
              this.onStart(config.minutes, config.autoExtend)
              this.startCountdownRefresh()
            })

          // Divider
          Divider()
            .color($r('app.color.colorDividerBackground'))
            .width('100%')

          // Auto-extend toggle row
          Row() {
            Text($r('app.string.automatically_extend_to_the_end_of_the_whole_song'))
              .fontSize(16)
              .fontColor($r('app.color.salt_color_icon_foreground'))
              .layoutWeight(1)
              .margin({ right: 12 })

            Toggle({ type: ToggleType.Switch, isOn: this.viewModel.autoExtend })
              .selectedColor($r('app.color.salt_color_high_light'))
              .switchPointColor(Color.White)
              .onChange((isOn: boolean) => {
                this.viewModel.setAutoExtend(isOn)
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 12, bottom: 4 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.viewModel.toggleAutoExtend()
          })

          // Auto-extend description text
          Text($r('app.string.automatically_extend_to_the_end_of_the_whole_song_intro'))
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .width('100%')
            .padding({ left: 14, right: 14, top: 4, bottom: 12 })

          // Divider
          Divider()
            .color($r('app.color.colorDividerBackground'))
            .width('100%')

          // Safety tips
          Text($r('app.string.dialog_sleep_timer_tips'))
            .fontSize(12)
            .fontColor($r('app.color.salt_color_sub_text'))
            .width('100%')
            .padding({ left: 14, right: 14, top: 12, bottom: 14 })
        }
      }
      .width('100%')
      .borderRadius(12)
      .backgroundColor(this.isSystemDark ? $r('app.color.salt_color_sub_background') : $r('app.color.salt_color_white'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 + this.navBarHeight })
  }
}
