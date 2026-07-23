// IapDataModel.ets
// Data models for HarmonyOS IAP Kit integration
// Based on official demo: https://gitcode.com/HarmonyOS_Samples/iapkit-sample-clientdemo-arkts

/**
 * Purchase result data
 * JSON string returned by createPurchase / queryPurchases
 */
export interface PurchaseData {
  /** Product type: 0-consumable, 1-non-consumable, 2-auto-renewable, 3-non-renewable */
  type: number;
  /** JWS-encoded purchase order info (consumable/non-consumable/non-renewable) */
  jwsPurchaseOrder?: string;
  /** JWS-encoded subscription group status (auto-renewable only) */
  jwsSubscriptionStatus?: string;
}

/**
 * Purchase order payload — decoded from jwsPurchaseOrder
 */
export interface PurchaseOrderPayload {
  /** Application ID (max 128 chars) */
  applicationId: string;
  /** Product ID (max 256 chars) */
  productId: string;
  /** Product type: 0-consumable, 1-non-consumable, 2-auto-renewable, 3-non-renewable */
  productType: number;
  /** Purchase order ID (max 64 chars) */
  purchaseOrderId: string;
  /** Purchase token (max 512 chars) */
  purchaseToken: string;
  /** Purchase timestamp (ms) */
  purchaseTime: number;
  /** JWS signature timestamp (ms) */
  signedTime: number;
  /** User country/region code */
  countryCode: string;
  /** Product price */
  price: number;
  /** Currency code (e.g. CNY, USD) */
  currency: string;
  /** Environment: Sandbox or Production */
  environment: string;
  /** Delivery status: 1-delivered, 2-undelivered */
  finishStatus: FinishStatus;
  /** Whether finishPurchase is needed */
  needFinish: boolean;
  /** Developer payload */
  developerPayload?: string;
  /** Revocation reason code, empty means success */
  purchaseOrderRevocationReasonCode?: string;
  /** Offer ID (max 256 chars) */
  offerId?: string;
  /** Subscription ID (max 64 chars) */
  subscriptionId?: string;
  /** Subscription group generation ID (max 512 chars) */
  subGroupGenerationId?: string;
}

/** Delivery status enum */
export enum FinishStatus {
  /** Delivered */
  FINISHED = '1',
  /** Undelivered */
  UNFINISHED = '2'
}

/**
 * Subscription group status payload — decoded from jwsSubscriptionStatus
 */
export interface SubGroupStatusPayload {
  environment: string;
  applicationId: string;
  packageName: string;
  subGroupId: string;
  lastSubscriptionStatus?: SubscriptionStatus;
  historySubscriptionStatusList?: SubscriptionStatus[];
}

export interface SubscriptionStatus {
  subGroupGenerationId: string;
  subscriptionId: string;
  purchaseToken: string;
  status: SubStatus;
  expiresTime: number;
  lastPurchaseOrder?: PurchaseOrderPayload;
  renewalInfo?: SubRenewalInfo;
}

export interface SubRenewalInfo {
  productId: string;
}

export enum SubStatus {
  ACTIVE = '1',
  EXPIRED = '2',
  CHARGE_ATTEMPT = '3',
  REVOKED = '5'
}

// 内购集成：Pro 商品购买数据。
