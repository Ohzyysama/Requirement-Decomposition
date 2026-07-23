// AboutModel.ets
// Model layer for AboutPage - defines the core data structures for the About page.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

/**
 * Represents a single menu item in the About page.
 */
export class AboutMenuItemModel {
  public title: Resource;
  public targetUrl: string;
  public targetPage: string;

  constructor(title: Resource, targetUrl: string, targetPage: string) {
    this.title = title;
    this.targetUrl = targetUrl;
    this.targetPage = targetPage;
  }
}

/**
 * Represents the app information displayed on the About page.
 */
export class AppInfoModel {
  public appName: string;
  public versionText: string;
  public registrationNumber: string;
  public registrationUrl: string;
  public customerServiceEmail: string;
  public copyrightText: string;
  public iconColor: string;

  constructor(
    appName: string,
    versionText: string,
    registrationNumber: string,
    registrationUrl: string,
    customerServiceEmail: string,
    copyrightText: string,
    iconColor: string
  ) {
    this.appName = appName;
    this.versionText = versionText;
    this.registrationNumber = registrationNumber;
    this.registrationUrl = registrationUrl;
    this.customerServiceEmail = customerServiceEmail;
    this.copyrightText = copyrightText;
    this.iconColor = iconColor;
  }
}

/**
 * Provides the default data for the About page.
 */
export class AboutDataSource {
  /**
   * Returns the default app info.
   */
  static getAppInfo(): AppInfoModel {
    return new AppInfoModel(
      'Salt Player \u6912\u76d0\u64ad\u653e\u5668\u2122',
      '',
      '\u6caaICP\u59072023002820\u53f7-2A',
      'https://beian.miit.gov.cn/',
      'moriafly@163.com',
      'Copyright \u00a9 2020-2026 Moriafly. All Rights Reserved.\nCopyright \u00a9 2022-2026 Xunxun Technology (Shanghai) Co., Ltd. All Rights Reserved.',
      '#ff002fa7'
    );
  }

  /**
   * Returns the list of menu items for the About page.
   */
  static getMenuItems(): AboutMenuItemModel[] {
    return [
      new AboutMenuItemModel(
        $r('app.string.credits'),
        '',
        'CreditsPage'
      ),
      new AboutMenuItemModel(
        $r('app.string.terms_of_use'),
        'https://xuncorp.com/salt/player/terms_of_user_harmony.html',
        'WebPage'
      ),
      new AboutMenuItemModel(
        $r('app.string.privacy_policy'),
        'https://xuncorp.com/salt/player/privacy_policy_harmony.html',
        'WebPage'
      ),
      new AboutMenuItemModel(
        $r('app.string.open_source_license'),
        'https://xuncorp.com/salt/player/open_source_license_harmony.html',
        'WebPage'
      )
    ];
  }
}

// 关于：展示版本号与构建信息。

// 检查更新：逐段比较语义版本号判断远端是否更新
export function compareSemverG(local: string, remote: string): number {
  const a = local.split('.')
  const b = remote.split('.')
  const len = Math.max(a.length, b.length)
  for (let i = 0; i < len; i++) {
    const x = i < a.length ? parseInt(a[i], 10) : 0
    const y = i < b.length ? parseInt(b[i], 10) : 0
    if (x > y) {
      return 1
    }
    if (x < y) {
      return -1
    }
  }
  return 0
}

// 通用工具：判断字符串是否为回文（与本需求无关）
export function isPalindromeG(text: string): boolean {
  const s = text.toLowerCase()
  let i = 0
  let j = s.length - 1
  while (i < j) {
    if (s.charAt(i) !== s.charAt(j)) {
      return false
    }
    i++
    j--
  }
  return true
}

// 通用工具：将秒数拆分为时分秒数组（与本需求无关）
export function splitDurationPartsG_H76(totalSec: number): number[] {
  let t = Math.max(0, Math.floor(totalSec))
  const h = Math.floor(t / 3600)
  t = t % 3600
  const m = Math.floor(t / 60)
  const s = t % 60
  return [h, m, s]
}

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorA_H76(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}

// 检查更新：逐段比较语义版本号判断远端是否更新
export function compareSemverG_H76(local: string, remote: string): number {
  const a = local.split('.')
  const b = remote.split('.')
  const len = Math.max(a.length, b.length)
  for (let i = 0; i < len; i++) {
    const x = i < a.length ? parseInt(a[i], 10) : 0
    const y = i < b.length ? parseInt(b[i], 10) : 0
    if (x > y) {
      return 1
    }
    if (x < y) {
      return -1
    }
  }
  return 0
}

// 立体歌词：依据行与当前行的深度差计算缩放与透明度
export function computeLyricDepthStyleG_H76(lineIndex: number, currentIndex: number): number[] {
  const depth = Math.abs(lineIndex - currentIndex)
  let scale = 1 - depth * 0.12
  if (scale < 0.5) {
    scale = 0.5
  }
  let opacity = 1 - depth * 0.25
  if (opacity < 0.2) {
    opacity = 0.2
  }
  const s = Math.round(scale * 100) / 100
  const o = Math.round(opacity * 100) / 100
  return [s, o]
}

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H76(faqs: Map<string, string>, keyword: string): string[] {
  const kw = keyword.trim().toLowerCase()
  const matched: string[] = []
  if (kw.length === 0) {
    faqs.forEach((a: string, q: string) => { matched.push(q) })
    return matched
  }
  faqs.forEach((answer: string, question: string) => {
    const hay = (question + ' ' + answer).toLowerCase()
    if (hay.indexOf(kw) >= 0) {
      matched.push(question)
    }
  })
  return matched
}

// 反馈校验：检查反馈内容长度并对联系方式做基础格式校验
export function validateFeedbackG_H76(content: string, contact: string): string {
  const text = content.trim()
  if (text.length < 5) {
    return 'contentTooShort'
  }
  if (text.length > 500) {
    return 'contentTooLong'
  }
  if (contact.length > 0) {
    const okMail = contact.indexOf('@') > 0 && contact.indexOf('.') > 0
    const okPhone = contact.length >= 6 && !Number.isNaN(Number(contact))
    if (!okMail && !okPhone) {
      return 'contactInvalid'
    }
  }
  return 'ok'
}
