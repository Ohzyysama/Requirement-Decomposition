// ScanningDialogComponent.ets
// View layer: Scanning dialog component for Salt Player
// Corresponds to Android ScanningDialog.kt (com.salt.music.ui.screen.mediasource)
// Shows scanning progress with log output and a confirm/close button
// Displayed as a dialog overlay when user taps "Start Scan" on MediaSourcePage
//
// MVVM: This View binds to ScanningDialogViewModel for all state and logic.
// The View does NOT contain business logic or data operations.

import ScanningDialogViewModel from '../viewmodel/ScanningDialogViewModel'

@CustomDialog
@Component
export struct ScanningDialogComponent {
  controller?: CustomDialogController
  onDismiss: () => void = () => {}
  context?: Context
  private scroller: Scroller = new Scroller()

  // ViewModel: singleton so the cancel-on-dismiss path can run cleanly even
  // while the dialog instance is being torn down.
  @State viewModel: ScanningDialogViewModel = ScanningDialogViewModel.getInstance()

  aboutToAppear(): void {
    // Pass context to ViewModel for accessing system APIs
    if (this.context) {
      this.viewModel.setContext(this.context)
    }

    // Delegate scanning start to ViewModel, passing auto-scroll callback
    this.viewModel.startScanning(() => {
      setTimeout(() => {
        this.scroller.scrollEdge(Edge.Top)
      }, 50)
    })
  }

  aboutToDisappear(): void {
    // Dialog dismissed (e.g. user tapped outside, or app is closing): cancel
    // the in-flight scan so all URIs authorized this scan are revoked and
    // state is restored to pre-scan. If the scan has already finished this
    // is a no-op.
    this.viewModel.cancelScanning()
  }

  build() {
    Column() {
      // ========== Title row with optional progress indicator ==========
      Stack({ alignContent: Alignment.Center }) {
        // Title text
        Text($r('app.string.scan_music'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .width('100%')
          .padding({ left: 16 })
          .textAlign(TextAlign.Start)

        // Progress indicator shown only during scanning (driven by ViewModel)
        if (this.viewModel.scanning) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color($r('app.color.salt_color_high_light'))
            .position({ x: '100%', y: '50%' })
            .translate({ x: -40, y: -12 })
        }
      }
      .width('100%')
      .height(56)

      // ========== Scanning log area ==========
      Scroll(this.scroller) {
        Text(this.viewModel.scanningLog)
          .fontSize(12)
          .fontColor($r('app.color.colorSubTextForeground'))
          .width('100%')
          .padding({ left: 16, right: 16 })
          .copyOption(CopyOptions.InApp)
      }
      .align(Alignment.TopStart)
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // ========== Confirm button ==========
      // Button appearance is driven by ViewModel scanning state
      Button($r('app.string.confirm'))
        .width('90%')
        .height(48)
        .margin({ bottom: 16, top: 8 })
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.viewModel.scanning ? $r('app.color.colorSubTextForeground') : Color.White)
        .backgroundColor(this.viewModel.scanning ? $r('app.color.salt_color_dialog_background') :
          $r('app.color.salt_color_high_light'))
        .borderRadius(12)
        .onClick(() => {
          // Delegate confirm logic to ViewModel
          const shouldClose = this.viewModel.handleConfirm()
          if (shouldClose) {
            this.onDismiss()
            if (this.controller) {
              this.controller.close()
            }
          }
        })
    }
    .width('80%')
    .height('75%')
    .borderRadius(20)
    .backgroundColor($r('app.color.colorDialogBackground'))
    .clip(true)
  }
}
