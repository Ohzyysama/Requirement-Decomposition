// WindowsPlatformModel.ets
// Model layer for WindowsPlatformPage - defines the core data structures for the
// Windows Platform promotion page.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

/**
 * Represents a link item displayed on the Windows Platform page.
 * Each link item has a display title, a URL, an optional icon resource,
 * and an arrow icon resource.
 */
export class WindowsPlatformLinkItemModel {
  public title: Resource | string;
  public url: string;
  public iconResource: Resource | null;
  public arrowIconResource: Resource;

  constructor(
    title: Resource | string,
    url: string,
    iconResource: Resource | null,
    arrowIconResource: Resource
  ) {
    this.title = title;
    this.url = url;
    this.iconResource = iconResource;
    this.arrowIconResource = arrowIconResource;
  }
}

/**
 * Represents the branding information displayed at the top of the page.
 */
export class WindowsPlatformBrandingModel {
  public title: string;
  public subtitle: string;
  public promotionalImageResource: Resource;

  constructor(
    title: string,
    subtitle: string,
    promotionalImageResource: Resource
  ) {
    this.title = title;
    this.subtitle = subtitle;
    this.promotionalImageResource = promotionalImageResource;
  }
}

/**
 * Provides the default data for the Windows Platform page.
 */
export class WindowsPlatformDataSource {
  /**
   * Returns the branding information for the page.
   */
  static getBranding(): WindowsPlatformBrandingModel {
    return new WindowsPlatformBrandingModel(
      'Salt Player for Windows',
      '\u6570\u5341\u4e07\u7528\u6237\u9009\u62e9\u7684\u672c\u5730\u97f3\u4e50\u64ad\u653e\u5668\u54c1\u724c',
      $r('app.media.bg_spw')
    );
  }

  /**
   * Returns the official website link item.
   */
  static getOfficialWebsiteItem(): WindowsPlatformLinkItemModel {
    return new WindowsPlatformLinkItemModel(
      $r('app.string.official_website'),
      'https://moriafly.com/program/spw',
      null,
      $r('app.media.ic_open_in_new')
    );
  }

  /**
   * Returns the Microsoft Store download link item.
   */
  static getMicrosoftStoreItem(): WindowsPlatformLinkItemModel {
    return new WindowsPlatformLinkItemModel(
      $r('app.string.download_it_on_microsoft_store'),
      'https://apps.microsoft.com/detail/9P42FQ0WPQXK',
      $r('app.media.ic_microsoft_store'),
      $r('app.media.ic_open_in_new')
    );
  }

  /**
   * Returns the download section title resource.
   */
  static getDownloadSectionTitle(): Resource {
    return $r('app.string.download');
  }
}

// Windows：椒盐音乐 Windows 客户端介绍信息。

// Windows 介绍对齐。
