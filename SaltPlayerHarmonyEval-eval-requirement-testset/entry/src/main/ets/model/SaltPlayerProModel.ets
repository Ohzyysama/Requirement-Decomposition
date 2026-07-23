// SaltPlayerProModel.ets
// Model layer: data structures and data operations for Salt Player Pro page
// Corresponds to the Android OfficialActivateScreen.kt business logic

import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { PurchaseData, PurchaseOrderPayload, FinishStatus } from '../utils/IapDataModel';
import { JWSUtil } from '../utils/JWSUtil';
import SettingsStore from './SettingsStore';

const TAG: string = 'SaltPlayerProModel';
const PRO_PRODUCT_ID: string = 'Pro';

// Feature intro item data structure
export class ProFeatureItemModel {
  public icon: Resource
  public title: string
  public subtitle: string

  constructor(icon: Resource, title: string, subtitle: string) {
    this.icon = icon
    this.title = title
    this.subtitle = subtitle
  }
}

// Enum representing the possible payment actions
export enum PaymentAction {
  NONE,
  PURCHASE,
  RESTORE_PURCHASE
}

// Callback interface for purchase result
export interface PurchaseResultCallback {
  onSuccess: () => void
  onFailure: (message: string, isAlreadyOwned: boolean) => void
}

// Data access operations for Salt Player Pro membership
export class SaltPlayerProDataSource {
  private static context: common.UIAbilityContext | undefined = undefined

  static initContext(ctx: common.UIAbilityContext): void {
    SaltPlayerProDataSource.context = ctx
  }

  // Get the price amount string
  static getPrice(): string {
    return '\uFFE519.00'
  }

  // Get the payment button text
  static getPaymentButtonText(): string {
    return '\u8D2D\u4E70\u6FC0\u6D3B'
  }

  // Get the agreement URL
  static getAgreementUrl(): string {
    return 'https://moriafly.xyz/salt-player/salt-player-pro/'
  }

  // Load pro feature items (6 rows x 2 columns grid)
  static loadProFeatures(): ProFeatureItemModel[][] {
    return [
      [
        new ProFeatureItemModel($r('app.media.ic_pro_lyrics'), '\u60AC\u6D6E\u7A97\u72B6\u6001\u680F\u6B4C\u8BCD', '\u968F\u65F6\u770B\u6B4C\u8BCD'),
        new ProFeatureItemModel($r('app.media.ic_pro_wallpaper'), '\u4E3B\u754C\u9762\u58C1\u7EB8', '\u8FD9\u6B21\uFF0C\u6362\u4E2A\u597D\u770B\u7684')
      ],
      [
        new ProFeatureItemModel($r('app.media.ic_pro_bit'), '\u6D6E\u70B9\u652F\u6301', '\u6D6E\u70B9\u6BD4\u7279\u89E3\u7801'),
        new ProFeatureItemModel($r('app.media.ic_pro_android'), 'Salt UI \u6750\u8D28', '\u9AD8\u7EA7\u611F\u58C1\u7EB8\u6548\u679C')
      ],
      [
        new ProFeatureItemModel($r('app.media.ic_pro_back'), '\u5012\u653E\u6A21\u5F0F', '\u8F7B\u677E\u5A31\u4E50\u4E00\u4E0B'),
        new ProFeatureItemModel($r('app.media.ic_pro_wave'), '\u53C2\u6570\u5747\u8861', '\u81EA\u5B9A\u4E49\u53C2\u6570\u5747\u8861\u5668')
      ],
      [
        new ProFeatureItemModel($r('app.media.ic_pro_speed'), '\u6297\u952F\u9F7F\u8FC7\u6EE4', '\u53D8\u901F\u964D\u4F4E\u566A\u97F3'),
        new ProFeatureItemModel($r('app.media.ic_pro_audio'), '\u97F3\u9891\u76F4\u51FA', 'Direct \u8F93\u51FA\u6A21\u5F0F')
      ],
      [
        new ProFeatureItemModel($r('app.media.ic_song_quality_hi_res'), '\u81EA\u5B9A\u4E49\u5C0F\u91D1\u6807', '\u9009\u62E9\u559C\u6B22\u7684 HR \u6807\u5FD7'),
        new ProFeatureItemModel($r('app.media.ic_pro_car'), '\u8F66\u673A\u64AD\u653E\u754C\u9762', '\u66F4\u9002\u5408\u8F66\u4E3B')
      ],
      [
        new ProFeatureItemModel($r('app.media.ic_pro_3d'), '\u7ACB\u4F53\u6B4C\u8BCD\u6548\u679C', '\u6A2A\u5C4F\u6B4C\u8BCD\u66F4\u7F8E'),
        new ProFeatureItemModel($r('app.media.ic_pro_color'), '\u52A8\u6001\u989C\u8272\u4E3B\u9898', '\u4E3B\u9898\u7CFB\u7EDF\u58C1\u7EB8\u67D3\u8272')
      ]
    ]
  }

  // Open agreement URL in browser
  static openAgreement(): void {
    console.info('SaltPlayerProModel: opening agreement URL - https://moriafly.xyz/salt-player/salt-player-pro/')
  }

  // Activate Pro persistently
  static activatePro(): void {
    SettingsStore.getInstance().save('isPro', true)
    console.info(TAG, 'Pro activated and persisted')
  }

  // Check if Pro is already activated
  static isProActivated(): boolean {
    return AppStorage.get<boolean>('isPro') ?? false
  }

  // Query IAP environment status
  static async queryEnvironmentStatus(): Promise<number> {
    if (!SaltPlayerProDataSource.context) {
      console.error(TAG, 'Context not initialized')
      return -1
    }
    return new Promise<number>((resolve) => {
      iap.queryEnvironmentStatus(SaltPlayerProDataSource.context!).then(() => {
        console.info(TAG, 'Succeeded in querying environment status.')
        resolve(0)
      }).catch((err: BusinessError) => {
        console.error(TAG, `Failed to query environment status. Code is ${err.code}, message is ${err.message}`)
        resolve(err.code)
      })
    })
  }

  // Query product info from IAP
  static async queryProductInfo(): Promise<iap.Product | undefined> {
    if (!SaltPlayerProDataSource.context) {
      console.error(TAG, 'Context not initialized')
      return undefined
    }
    return new Promise<iap.Product | undefined>((resolve) => {
      const queryProductParam: iap.QueryProductsParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [PRO_PRODUCT_ID]
      }
      iap.queryProducts(SaltPlayerProDataSource.context!, queryProductParam).then((result) => {
        console.info(TAG, 'Succeeded in querying products.')
        if (result && result.length > 0) {
          resolve(result[0])
        } else {
          resolve(undefined)
        }
      }).catch((err: BusinessError) => {
        console.error(TAG, `Failed to query products. Code is ${err.code}, message is ${err.message}`)
        promptAction.openToast({ message: `查询商品失败 [${err.code}] ${err.message}`, duration: 3000 })
        resolve(undefined)
      })
    })
  }

  // Query current entitlements (for restore purchase / startup check)
  static async queryPurchases(): Promise<boolean> {
    if (!SaltPlayerProDataSource.context) {
      console.error(TAG, 'Context not initialized')
      return false
    }
    return new Promise<boolean>((resolve) => {
      const param: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.NONCONSUMABLE,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT
      }
      iap.queryPurchases(SaltPlayerProDataSource.context!, param).then((res: iap.QueryPurchaseResult) => {
        console.info(TAG, 'Succeeded in querying purchases.')
        const purchaseDataList: string[] = res.purchaseDataList
        if (!purchaseDataList || purchaseDataList.length <= 0) {
          resolve(false)
          return
        }
        let hasPro = false
        for (let i = 0; i < purchaseDataList.length; i++) {
          const isProProduct = SaltPlayerProDataSource.dealPurchaseData(purchaseDataList[i])
          if (isProProduct) {
            hasPro = true
          }
        }
        if (hasPro) {
          SaltPlayerProDataSource.activatePro()
        }
        resolve(hasPro)
      }).catch((err: BusinessError) => {
        console.error(TAG, `Failed to query purchases. Code is ${err.code}, message is ${err.message}`)
        resolve(false)
      })
    })
  }

  // Create purchase (buy Pro)
  static async createPurchase(callback: PurchaseResultCallback): Promise<void> {
    if (!SaltPlayerProDataSource.context) {
      callback.onFailure('Context not initialized', false)
      return
    }
    try {
      const createPurchaseParam: iap.PurchaseParameter = {
        productId: PRO_PRODUCT_ID,
        productType: iap.ProductType.NONCONSUMABLE,
        developerPayload: 'Pro_purchase'
      }
      iap.createPurchase(SaltPlayerProDataSource.context!, createPurchaseParam).then((result) => {
        console.info(TAG, 'Succeeded in creating purchase.')
        promptAction.openToast({ message: $r('app.string.purchase_success'), duration: 2000 })
        SaltPlayerProDataSource.dealPurchaseData(result.purchaseData)
        SaltPlayerProDataSource.activatePro()
        callback.onSuccess()
      }).catch((err: BusinessError) => {
        console.error(TAG, `Failed to create purchase. Code is ${err.code}, message is ${err.message}`)
        const isAlreadyOwned = (err.code === iap.IAPErrorCode.PRODUCT_OWNED)
        const isSystemError = (err.code === iap.IAPErrorCode.SYSTEM_ERROR)

        if (isAlreadyOwned) {
          // Already purchased, activate Pro anyway
          SaltPlayerProDataSource.activatePro()
          promptAction.openToast({ message: '已拥有该商品，Pro 已激活', duration: 2000 })
          callback.onFailure(err.message, true)
          return
        }

        if (isSystemError) {
          // 1001860001: system internal error — may indicate an unfinished purchase
          // Per IAP standard process: query unfinished purchases and finish them
          promptAction.openToast({ message: `系统错误 [${err.code}]，正在检查已购订单...`, duration: 2000 })
          SaltPlayerProDataSource.queryPurchases().then((hasPro) => {
            if (hasPro) {
              promptAction.openToast({ message: '检测到已购订单，Pro 已激活', duration: 2000 })
              callback.onSuccess()
            } else {
              promptAction.openToast({ message: `购买失败 [${err.code}] 请检查签名和商品配置`, duration: 4000 })
              callback.onFailure(err.message, false)
            }
          }).catch((_e: Error) => {
            promptAction.openToast({ message: `购买失败 [${err.code}] 请检查签名、client_id 和商品配置`, duration: 4000 })
            callback.onFailure(err.message, false)
          })
          return
        }

        promptAction.openToast({ message: `购买失败 [${err.code}] ${err.message}`, duration: 3000 })
        callback.onFailure(err.message, false)
      })
    } catch (err) {
      const e: BusinessError = err as BusinessError
      console.error(TAG, `Failed to create purchase. Code is ${e.code}, message is ${e.message}`)
      callback.onFailure(e.message, false)
    }
  }

  // Restore purchase: query current entitlements and activate if found
  static async restorePurchase(callback: PurchaseResultCallback): Promise<void> {
    if (!SaltPlayerProDataSource.context) {
      callback.onFailure('Context not initialized', false)
      return
    }
    const hasPro = await SaltPlayerProDataSource.queryPurchases()
    if (hasPro) {
      promptAction.openToast({ message: $r('app.string.pro_activated'), duration: 2000 })
      callback.onSuccess()
    } else {
      // Try to buy again: if already owned, error callback will report already owned
      await SaltPlayerProDataSource.createPurchase({
        onSuccess: () => callback.onSuccess(),
        onFailure: (msg, isAlreadyOwned) => {
          if (isAlreadyOwned) {
            SaltPlayerProDataSource.activatePro()
            promptAction.openToast({ message: $r('app.string.pro_activated'), duration: 2000 })
            callback.onSuccess()
          } else {
            callback.onFailure(msg, false)
          }
        }
      })
    }
  }

  // Process purchase data: decode JWS, verify, finish purchase if needed
  private static dealPurchaseData(purchaseData: string): boolean {
    try {
      const data = JSON.parse(purchaseData) as PurchaseData
      const jwsPurchaseOrder = data.jwsPurchaseOrder
      if (!jwsPurchaseOrder) {
        console.error(TAG, 'dealPurchaseData, jwsPurchaseOrder invalid')
        return false
      }
      const purchaseOrderStr = JWSUtil.decodeJwsObj(jwsPurchaseOrder)
      const purchaseOrderPayload = JSON.parse(purchaseOrderStr) as PurchaseOrderPayload
      if (!purchaseOrderPayload) {
        return false
      }
      const isProProduct = purchaseOrderPayload.productId === PRO_PRODUCT_ID
      // Skip revoked/refunded orders per IAP best practice
      if (isProProduct && purchaseOrderPayload.purchaseOrderRevocationReasonCode) {
        console.info(TAG, 'Purchase order revoked, skip finishing. reasonCode=' + purchaseOrderPayload.purchaseOrderRevocationReasonCode)
        return isProProduct
      }
      if (isProProduct && purchaseOrderPayload.finishStatus !== FinishStatus.FINISHED) {
        SaltPlayerProDataSource.finishPurchase(purchaseOrderPayload)
      }
      return isProProduct
    } catch (e) {
      console.error(TAG, 'dealPurchaseData json error')
      return false
    }
  }

  // Confirm delivery (finishPurchase)
  private static finishPurchase(purchaseOrder: PurchaseOrderPayload): void {
    if (!SaltPlayerProDataSource.context) {
      console.error(TAG, 'finishPurchase but context is empty')
      return
    }
    if (purchaseOrder.productType === undefined || purchaseOrder.productType === null) {
      console.error(TAG, 'finishPurchase but productType is empty')
      return
    }
    const finishPurchaseParam: iap.FinishPurchaseParameter = {
      productType: purchaseOrder.productType,
      purchaseToken: purchaseOrder.purchaseToken,
      purchaseOrderId: purchaseOrder.purchaseOrderId
    }
    iap.finishPurchase(SaltPlayerProDataSource.context!, finishPurchaseParam).then(() => {
      console.info(TAG, 'Succeeded in finishing purchase.')
    }).catch((err: BusinessError) => {
      console.error(TAG, `Failed to finish purchase. Code is ${err.code}, message is ${err.message}`)
    })
  }
}

// Pro：跟踪 Pro 订阅状态。

// Pro 功能门控：对车机/高级音效等能力按 Pro 解锁。

// Pro 状态对齐。
