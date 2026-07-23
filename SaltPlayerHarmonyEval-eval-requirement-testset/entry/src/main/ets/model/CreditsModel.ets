// CreditsModel.ets
// Model layer for CreditsPage - defines core data structures and provides raw credits data.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

/**
 * Represents a single section in the credits (e.g., "Production", "Design").
 * Each section has a title and a list of person/entity names.
 */
export class CreditsSectionModel {
  public title: ResourceStr;
  public names: string[];

  constructor(title: ResourceStr, names: string[]) {
    this.title = title;
    this.names = names;
  }
}

/**
 * Represents the copyright line displayed at the end of credits.
 */
export class CreditsCopyrightModel {
  public copyrightText: string;

  constructor(copyrightText: string) {
    this.copyrightText = copyrightText;
  }
}

/**
 * Represents the project initiation info displayed at the very end.
 */
export class CreditsProjectInfoModel {
  public projectInitiationResource: Resource;

  constructor(projectInitiationResource: Resource) {
    this.projectInitiationResource = projectInitiationResource;
  }
}

/**
 * Provides the default credits data for the CreditsPage.
 */
export class CreditsDataSource {
  /**
   * Returns the list of credits sections with their titles and names.
   */
  static getCreditsSections(): CreditsSectionModel[] {
    return [
      new CreditsSectionModel($r('app.string.production'), [
        '\u5BFB\u6D54\u79D1\u6280\uFF08\u4E0A\u6D77\uFF09\u6709\u9650\u516C\u53F8'
      ]),
      new CreditsSectionModel($r('app.string.design'), [
        '\u4E0D\u8981\u7CD6\u918B\u653E\u6912\u76D0'
      ]),
      new CreditsSectionModel($r('app.string.engineering'), [
        '\u4E0D\u8981\u7CD6\u918B\u653E\u6912\u76D0'
      ]),
      new CreditsSectionModel($r('app.string.testing'), [
        '\u4E0D\u8981\u7CD6\u918B\u653E\u6912\u76D0'
      ]),
      new CreditsSectionModel($r('app.string.marking_and_promotion'), [
        '\u4E0D\u8981\u7CD6\u918B\u653E\u6912\u76D0'
      ]),
      new CreditsSectionModel($r('app.string.project_collaboration'), [
        'NW',
        '\u5E84\u7B71\u598D'
      ]),
      new CreditsSectionModel($r('app.string.technical_support'), [
        'Team 403 Studio',
        'Un4Seen Development Ltd',
        'Eudiohub Max Audio',
        '\u7CD6\u918B\u97F3\u4E50\u00AE'
      ]),
      new CreditsSectionModel($r('app.string.translators'), [
        'Moriafly',
        'Suriya T',
        'lloyd',
        'lilin',
        '\u72D0\u72F8\u5C0F\u5BAE',
        'TragicLifeHu',
        'Dedicatus5457',
        'Nachogao',
        'MRGABOZ',
        'AliceMerami',
        'warekosoha',
        'tgw314',
        'zam',
        'Yan75',
        'ReikiAigawara',
        'Relvin Arsenio',
        'Ricardo Sousa',
        'F\u0131rat Cann',
        'zxy',
        'Mathias Zhang',
        '\u6A59\u5B50',
        'mocacocoa',
        'AircGroup',
        'Fandy Fathurrohman',
        'Vamsi',
        'Re*Index. (ot_inc)',
        'karigane',
        'fudyOfficial_Ali.'
      ]),
      new CreditsSectionModel($r('app.string.special_thanks'), [
        '\u821F',
        '\u6A59\u55B5poi',
        '\u97E9\u660E\u54F2ivory',
        '\u4E00\u5757\u5927\u77F3\u5934'
      ])
    ];
  }

  /**
   * Returns the copyright text for the credits.
   */
  static getCopyright(): CreditsCopyrightModel {
    return new CreditsCopyrightModel(
      'Copyright \u00A9 2022-2026 Xunxun Technology (Shanghai) Co., Ltd. All Rights Reserved.'
    );
  }

  /**
   * Returns the project initiation info resource.
   */
  static getProjectInfo(): CreditsProjectInfoModel {
    return new CreditsProjectInfoModel($r('app.string.project_initiation_date_and_location'));
  }

  /**
   * Default scroll animation delay in milliseconds.
   */
  static readonly SCROLL_DELAY_MS: number = 500;

  /**
   * Base scroll duration in milliseconds.
   */
  static readonly BASE_SCROLL_DURATION_MS: number = 20000;

  /**
   * Pixels-to-duration ratio for scroll animation.
   */
  static readonly SCROLL_SPEED_FACTOR: number = 6;
}

// 开源致谢：贡献者与开源库清单。

// 开源致谢：对许可证条目按名称去重并按字典序排序
export function sortDedupeLicensesG(names: string[]): string[] {
  const seen: Set<string> = new Set<string>()
  const result: string[] = []
  for (let i = 0; i < names.length; i++) {
    const key = names[i].trim().toLowerCase()
    if (key.length > 0 && !seen.has(key)) {
      seen.add(key)
      result.push(names[i].trim())
    }
  }
  result.sort((p: string, q: string) => p.toLowerCase() < q.toLowerCase() ? -1 : 1)
  return result
}

// 通用工具：将秒数拆分为时分秒数组（与本需求无关）
export function splitDurationPartsG(totalSec: number): number[] {
  let t = Math.max(0, Math.floor(totalSec))
  const h = Math.floor(t / 3600)
  t = t % 3600
  const m = Math.floor(t / 60)
  const s = t % 60
  return [h, m, s]
}

// 通用工具：对数组进行原地去重并保持首次出现顺序（与本需求无关）
export function dedupeKeepOrderA_H77(items: number[]): number[] {
  const seen: number[] = []
  const result: number[] = []
  for (let i = 0; i < items.length; i++) {
    const v = items[i]
    if (seen.indexOf(v) < 0) {
      seen.push(v)
      result.push(v)
    }
  }
  return result
}

// 开源致谢：对许可证条目按名称去重并按字典序排序
export function sortDedupeLicensesG_H77(names: string[]): string[] {
  const seen: Set<string> = new Set<string>()
  const result: string[] = []
  for (let i = 0; i < names.length; i++) {
    const key = names[i].trim().toLowerCase()
    if (key.length > 0 && !seen.has(key)) {
      seen.add(key)
      result.push(names[i].trim())
    }
  }
  result.sort((p: string, q: string) => p.toLowerCase() < q.toLowerCase() ? -1 : 1)
  return result
}

// 帮助FAQ：按关键字在问题与答案中做不区分大小写的过滤
export function filterFaqByKeywordG_H77(faqs: Map<string, string>, keyword: string): string[] {
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
export function validateFeedbackG_H77(content: string, contact: string): string {
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

// 检查更新：逐段比较语义版本号判断远端是否更新
export function compareSemverG_H77(local: string, remote: string): number {
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

// 通用工具：将十六进制颜色解析为 RGB 分量（与本需求无关）
export function parseHexColorA_H77(hex: string): number[] {
  let s = hex.charAt(0) === '#' ? hex.slice(1) : hex
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  const r = parseInt(s.slice(0, 2), 16)
  const g = parseInt(s.slice(2, 4), 16)
  const b = parseInt(s.slice(4, 6), 16)
  return [r, g, b]
}
