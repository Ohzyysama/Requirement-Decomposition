// SaltPlayerProViewModel.ets
// ViewModel layer: provides observable data and logic for the SaltPlayerProPage view
// Bridges the View and Model layers per MVVM architecture

import { ProFeatureItemModel, PaymentAction, SaltPlayerProDataSource, PurchaseResultCallback } from '../model/SaltPlayerProModel'
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { iap } from '@kit.IAPKit';

@Observed
export default class SaltPlayerProViewModel {
  // Agreement checkbox state - tracked for UI updates
  @Track public agreeMemberService: boolean = false

  // Re-become member dialog visibility state
  @Track public showReBecomeDialog: boolean = false

  // The last executed payment action
  @Track public lastAction: PaymentAction = PaymentAction.NONE

  // Pro feature items loaded from Model (6 rows x 2 columns)
  @Track public proFeatures: ProFeatureItemModel[][] = []

  // Price text provided by Model
  @Track public priceText: string = ''

  // Payment button text provided by Model
  @Track public paymentButtonText: string = ''

  // Whether Pro is already activated
  @Track public isProActivated: boolean = false

  // Product info from IAP (for dynamic price)
  @Track public productInfo: string = ''

  // Loading state
  @Track public isLoading: boolean = false

  constructor() {
    this.loadData()
    this.isProActivated = SaltPlayerProDataSource.isProActivated()
  }

  // Initialize with context — must be called before any IAP operation
  initContext(context: common.UIAbilityContext): void {
    SaltPlayerProDataSource.initContext(context)
    this.queryEnvironmentAndProduct()
  }

  // Load static data from Model layer
  private loadData(): void {
    this.proFeatures = SaltPlayerProDataSource.loadProFeatures()
    this.priceText = SaltPlayerProDataSource.getPrice()
    this.paymentButtonText = SaltPlayerProDataSource.getPaymentButtonText()
  }

  // Query environment status and product info on page appear
  private async queryEnvironmentAndProduct(): Promise<void> {
    this.isLoading = true
    const envCode = await SaltPlayerProDataSource.queryEnvironmentStatus()
    if (envCode !== 0) {
      this.isLoading = false
      if (envCode === iap.IAPErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        promptAction.openToast({ message: '请登录华为账号后重试', duration: 2000 })
      } else if (envCode === iap.IAPErrorCode.SYSTEM_ERROR) {
        promptAction.openToast({ message: 'IAP 系统错误，请检查应用签名配置', duration: 3000 })
      } else {
        promptAction.openToast({ message: `环境检测失败 [${envCode}]`, duration: 3000 })
      }
      return
    }
    // queryProducts may fail with 1001860002 due to AGC config/sync issues,
    // but createPurchase can still succeed because the cashier has its own product lookup.
    // Do not block the purchase button if queryProducts fails.
    const product = await SaltPlayerProDataSource.queryProductInfo()
    if (product) {
      this.priceText = product.localPrice ?? SaltPlayerProDataSource.getPrice()
      this.paymentButtonText = product.localPrice ? `${product.localPrice} \u8D2D\u4E70\u6FC0\u6D3B` : SaltPlayerProDataSource.getPaymentButtonText()
      this.productInfo = product.name ?? ''
    }
    // Also check if already purchased
    const hasPro = await SaltPlayerProDataSource.queryPurchases()
    if (hasPro) {
      this.isProActivated = true
    }
    this.isLoading = false
  }

  // Toggle the agreement checkbox
  toggleAgreement(): void {
    this.agreeMemberService = !this.agreeMemberService
  }

  // Check if payment is allowed (agreement must be checked)
  isPaymentEnabled(): boolean {
    return this.agreeMemberService
  }

  // Handle payment button click
  handlePayment(): void {
    if (!this.agreeMemberService) {
      return
    }
    if (this.isProActivated) {
      promptAction.openToast({ message: $r('app.string.already_purchased'), duration: 2000 })
      return
    }
    this.isLoading = true
    this.lastAction = PaymentAction.PURCHASE
    SaltPlayerProDataSource.createPurchase({
      onSuccess: () => {
        this.isProActivated = true
        this.isLoading = false
      },
      onFailure: (_message, isAlreadyOwned) => {
        if (isAlreadyOwned) {
          this.isProActivated = true
        }
        this.isLoading = false
      }
    })
  }

  // Handle restore purchase button click
  handleRestorePurchase(): void {
    if (!this.agreeMemberService) {
      return
    }
    this.isLoading = true
    this.lastAction = PaymentAction.RESTORE_PURCHASE
    SaltPlayerProDataSource.restorePurchase({
      onSuccess: () => {
        this.isProActivated = true
        this.isLoading = false
      },
      onFailure: (_message, isAlreadyOwned) => {
        if (isAlreadyOwned) {
          this.isProActivated = true
        }
        this.isLoading = false
      }
    })
  }

  // Show the re-become member dialog
  showReActivateDialog(): void {
    if (this.agreeMemberService) {
      this.showReBecomeDialog = true
    }
  }

  // Dismiss the re-become member dialog
  dismissReActivateDialog(): void {
    this.showReBecomeDialog = false
  }

  // Handle re-activate confirmation (legacy dialog path)
  handleReActivate(): void {
    this.showReBecomeDialog = false
    this.handleRestorePurchase()
  }

  // Open the service agreement
  openServiceAgreement(): void {
    SaltPlayerProDataSource.openAgreement()
  }

  // Refresh Pro status from AppStorage
  refreshProStatus(): void {
    this.isProActivated = SaltPlayerProDataSource.isProActivated()
  }
}

// Pro：状态页与解锁。
