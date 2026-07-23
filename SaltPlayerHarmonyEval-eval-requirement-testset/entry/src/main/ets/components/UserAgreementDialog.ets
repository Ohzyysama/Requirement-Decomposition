// UserAgreementDialog.ets
// View layer: Full-screen first-launch user-agreement gate.
//
// Presented by MainPage when AgreementModel.hasAgreed() returns false.
// The dialog blocks the entire app (mounted as a top-layer Stack overlay
// inside MainPage.build()) and offers four actions:
//   - Tap "软件使用条例" link: open the terms URL in the system browser
//   - Tap "隐私政策" link: open the privacy URL in the system browser
//   - Tap "拒绝": exit the app via the same code path as ExitAppDialog
//   - Tap "同意": persist agreement, hide the dialog, continue app init
//
// Links open in the system browser (startAbility with
// ohos.want.action.viewData + entity.system.browsable) rather than the
// in-app WebPage because the agreement overlay is the top layer of
// MainPage's Stack — an in-app WebPage push would render underneath and
// appear frozen. External browser also matches the compliance expectation
// that the URL and origin be visible in the chrome.
//
// Styling follows the HDS 6.1 card idiom used elsewhere in the app:
//   - sys.color.comp_background_list_card for the card surface
//   - 20vp corner radius
//   - Primary action button tinted with salt_color_high_light (app accent)
// The body text uses inline Span clicks for the two agreement links,
// keeping the run-flow readable while still color-differentiating the
// tappable areas from ordinary text.

import { common, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { ExitAppDataSource } from '../model/ExitAppModel'
import {
  AgreementModel,
  TERMS_OF_USE_URL,
  PRIVACY_POLICY_URL,
} from '../model/AgreementModel'

@Component
export struct UserAgreementDialog {
  // Supplied by parent (MainPage). Flipping it to false hides the overlay.
  @Link showDialog: boolean

  // Launch the terms/privacy URLs in the system browser instead of the
  // in-app WebPage. The in-app WebPage would render underneath the
  // agreement overlay (the overlay is the top layer of MainPage's Stack),
  // so the user would see the tap do nothing. A system browser is also
  // what compliance reviewers typically expect for these links because
  // the URL and origin are clearly visible in the chrome.
  private onLinkClick(url: string): void {
    const context = getContext(this) as common.UIAbilityContext
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: url,
      entities: ['entity.system.browsable'],
      type: 'text/html',
    }
    context.startAbility(want).catch((e: Error) => {
      hilog.error(0, 'UserAgreementDialog', `startAbility(${url}) failed: ${e?.message ?? e}`)
    })
  }

  private onAgree(): void {
    const context = getContext(this) as common.UIAbilityContext
    AgreementModel.setAgreed(context).then(() => {
      this.showDialog = false
    })
  }

  private onDisagree(): void {
    // Reject = exit the app. Use the same saveState + terminate path the
    // ExitAppDialog uses so we don't leave the AudioPlayerService running.
    ExitAppDataSource.exitApp()
  }

  build() {
    // Full-screen scrim + centered card. The scrim has an empty onClick so
    // taps on the dim area are absorbed rather than falling through to
    // MainPage content behind. Do NOT put hitTestBehavior(Block) on the
    // outer Stack — Block on a parent blocks ALL its children from hit
    // testing (ArkUI rule: "自身响应触摸测试，但阻塞子节点..."), which would
    // freeze every button and link inside the dialog.
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#99000000')
        .onClick(() => {
          // absorb taps on the dim area; do not dismiss the dialog —
          // user must explicitly choose 同意 or 拒绝
        })

      Column() {
        // Title
        Text($r('app.string.user_agreement_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.font_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 24, bottom: 16 })

        // Body with two inline clickable link spans
        Text() {
          Span($r('app.string.user_agreement_intro'))
            .fontColor($r('sys.color.font_primary'))

          Span($r('app.string.terms_of_use'))
            .fontColor($r('app.color.salt_color_high_light'))
            .onClick(() => {
              this.onLinkClick(TERMS_OF_USE_URL)
            })

          Span($r('app.string.user_agreement_and'))
            .fontColor($r('sys.color.font_primary'))

          Span($r('app.string.privacy_policy'))
            .fontColor($r('app.color.salt_color_high_light'))
            .onClick(() => {
              this.onLinkClick(PRIVACY_POLICY_URL)
            })

          Span($r('app.string.user_agreement_outro'))
            .fontColor($r('sys.color.font_primary'))
        }
        .fontSize(14)
        .lineHeight(22)
        .width('100%')
        .textAlign(TextAlign.Start)
        .padding({ left: 20, right: 20 })
        .margin({ bottom: 24 })

        // Action buttons row
        Row() {
          // Disagree -> exit
          Button($r('app.string.disagree'))
            .fontSize(15)
            .fontColor($r('sys.color.font_primary'))
            .backgroundColor($r('app.color.colorItemBackground'))
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .onClick(() => {
              this.onDisagree()
            })

          // Agree -> persist + dismiss
          Button($r('app.string.agree'))
            .fontSize(15)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium)
            .backgroundColor($r('app.color.salt_color_high_light'))
            .height(44)
            .layoutWeight(1)
            .borderRadius(22)
            .margin({ left: 12 })
            .onClick(() => {
              this.onAgree()
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 20 })
      }
      .width('86%')
      .borderRadius(20)
      .clip(true)
      .backgroundColor($r('sys.color.comp_background_list_card'))
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
  }
}

// 重命名内部变量，行为不变。
