// ReBecomeDialogViewModel.ets
// ViewModel layer: provides data and logic for the ReBecomeDialog view
// Bridges the View and Model layers per MVVM architecture

import { ReBecomeAction, ReBecomeDataSource } from '../model/ReBecomeModel'

@Observed
export default class ReBecomeDialogViewModel {
  // The last executed action, can be observed by the View if needed
  @Track public lastAction: ReBecomeAction = ReBecomeAction.NONE

  // Dialog description text provided to the View
  @Track public descriptionText: string =
    '若曾购买过 Salt Player/糖醋音乐诚信会员，那么可以重新激活会员\n（本软件诚信经营，不设置相关检测）'

  // Dialog title text provided to the View
  @Track public titleText: string = '重新激活'

  // Cancel button text provided to the View
  @Track public cancelText: string = '我不曾购买'

  // Handle the activate member action
  // Called by the View when user taps the "activate" button
  handleActivate(): void {
    this.lastAction = ReBecomeAction.ACTIVATE
    ReBecomeDataSource.activateMember()
  }

  // Handle the dismiss action
  // Called by the View when user taps the "cancel" button or overlay
  handleDismiss(): void {
    this.lastAction = ReBecomeAction.DISMISS
  }
}
