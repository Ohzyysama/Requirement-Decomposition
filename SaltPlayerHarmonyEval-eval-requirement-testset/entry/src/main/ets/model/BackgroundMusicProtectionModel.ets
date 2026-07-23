// BackgroundMusicProtectionModel.ets
// Model layer for BackgroundMusicProtectionPage - defines the core data structures
// for background music protection check items and sections.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

/**
 * Represents a single protection check item with a title and description.
 */
export class ProtectItemModel {
  public title: string;
  public description: string;

  constructor(title: string, description: string) {
    this.title = title;
    this.description = description;
  }
}

/**
 * Represents a section of protection items with a section title.
 */
export class ProtectionSectionModel {
  public sectionTitle: string | Resource;
  public items: ProtectItemModel[];
  public tipText: string;

  constructor(sectionTitle: string | Resource, items: ProtectItemModel[], tipText: string = '') {
    this.sectionTitle = sectionTitle;
    this.items = items;
    this.tipText = tipText;
  }
}

/**
 * Provides the default data for the Background Music Protection page.
 * Data source that supplies raw model data to the ViewModel.
 */
export class BackgroundMusicProtectionDataSource {
  /**
   * Returns the readable check items section.
   */
  static getReadableCheckItems(sectionTitle: Resource): ProtectionSectionModel {
    return new ProtectionSectionModel(
      sectionTitle,
      [
        new ProtectItemModel(
          'MIUI auto-start permission',
          'Long press the app icon on the desktop to open the menu, tap "App Info", find "Permission Related" section, and enable the "Auto-start" switch. Enabling auto-start helps the app run stably in the background (detection applies to MIUI 10 to 14)'
        )
      ]
    );
  }

  /**
   * Returns the readable check items section with Chinese text.
   */
  static getReadableCheckItemsCN(sectionTitle: Resource): ProtectionSectionModel {
    return new ProtectionSectionModel(
      sectionTitle,
      [
        new ProtectItemModel(
          '\u5728 MIUI \u4e0a\u7684\u81ea\u542f\u52a8\u6743\u9650',
          '\u5728\u684c\u9762\u4e0a\u957f\u6309\u672c\u8f6f\u4ef6\u56fe\u6807\u5f39\u51fa\u9009\u62e9\u83dc\u5355\uff0c\u70b9\u51fb\u201c\u5e94\u7528\u4fe1\u606f\u201d\u9009\u9879\uff0c\u627e\u5230\u201c\u6743\u9650\u76f8\u5173\u201d\u5206\u7c7b\u9879\u5c0f\u6807\u9898\uff0c\u5f00\u542f\u540d\u4e3a\u201c\u81ea\u542f\u52a8\u201d\u7684\u5f00\u5173\u3002\u6253\u5f00\u81ea\u542f\u52a8\u6743\u9650\u6709\u52a9\u4e8e\u8f6f\u4ef6\u5728\u540e\u53f0\u7a33\u5b9a\u8fd0\u884c\uff08\u68c0\u6d4b\u9002\u7528\u4e8e MIUI 10 \u81f3 14\uff09'
        )
      ]
    );
  }

  /**
   * Returns the self-check items section.
   */
  static getSelfCheckItems(sectionTitle: Resource): ProtectionSectionModel {
    return new ProtectionSectionModel(
      sectionTitle,
      [
        new ProtectItemModel(
          '\u672c\u8f6f\u4ef6\u8fc7\u9ad8\u7684\u6027\u80fd\u6d88\u8017',
          '\u6570\u5b57\u4fe1\u53f7\u5904\u7406\u3001\u500d\u6570\u529f\u80fd\u3001\u8fc7\u9ad8\u7684\u91c7\u6837\u3001\u9ad8\u6e05\u56fe\u7247\u7b49\u4e00\u4e9b\u52a8\u6001\u6548\u679c\u4f1a\u4f7f\u5f97\u8f6f\u4ef6\u5728\u540e\u53f0\u7684\u5360\u7528\u63d0\u9ad8\uff0c\u5173\u95ed\u4e00\u4e9b\u8bbe\u7f6e\u4f1a\u6709\u52a9\u4e8e\u540e\u53f0\u5b58\u6d3b'
        ),
        new ProtectItemModel(
          '\u60ac\u6d6e\u7a97\u6743\u9650',
          '\u6253\u5f00\u60ac\u6d6e\u7a97\u6743\u9650\u6709\u52a9\u4e8e\u8f6f\u4ef6\u5728\u540e\u53f0\u7a33\u5b9a\u8fd0\u884c'
        ),
        new ProtectItemModel(
          '\u81ea\u542f\u52a8\u6743\u9650',
          '\u6253\u5f00\u81ea\u542f\u52a8\u6743\u9650\u6709\u52a9\u4e8e\u8f6f\u4ef6\u5728\u540e\u53f0\u7a33\u5b9a\u8fd0\u884c'
        ),
        new ProtectItemModel(
          '\u524d\u53f0\u901a\u77e5\u6743\u9650',
          '\u68c0\u67e5\u662f\u5426\u5f00\u542f\u4e86\u524d\u53f0\u901a\u77e5\u6743\u9650'
        ),
        new ProtectItemModel(
          '\u540e\u53f0\u52a0\u9501',
          '\u957f\u6309\u540e\u53f0\u591a\u4efb\u52a1\u754c\u9762\u672c\u8f6f\u4ef6\u5361\u7247\u5e76\u52a0\u9501\uff08\u4e0d\u540c\u7cfb\u7edf\u53ef\u80fd\u64cd\u4f5c\u65b9\u5f0f\u4e0d\u4e00\u81f4\uff09'
        ),
        new ProtectItemModel(
          'MIUI \u7701\u7535\u7b56\u7565',
          '\u5728\u672c\u8f6f\u4ef6\u5e94\u7528\u4fe1\u606f\u4e2d\u5c06\u7701\u7535\u7b56\u7565\u6539\u6210\u65e0\u9650\u5236'
        ),
        new ProtectItemModel(
          '\u66f4\u6539\u7cfb\u7edf\u76f8\u5173\u7701\u7535\u7b56\u7565',
          '\u672c\u8f6f\u4ef6\u53ef\u80fd\u4e0d\u5728\u5b9a\u5236\u7cfb\u7edf\u7684\u767d\u540d\u5355\u4e2d\uff0c\u5f53\u5e94\u7528\u4e00\u4e9b\u7701\u7535\u7b56\u7565\u65f6\uff0c\u8f6f\u4ef6\u5f88\u53ef\u80fd\u88ab\u7cfb\u7edf\u7ec8\u6b62\uff0c\u5982\u5f00\u542f\u7701\u7535\u6a21\u5f0f\u3001\u7535\u6c60\u4f18\u5316\u7b49'
        ),
        new ProtectItemModel(
          '\u88ab\u6e38\u620f\u4e2d\u5fc3\u7ec8\u6b62',
          '\u82e5\u6253\u5f00\u6e38\u620f\u4e2d\u5fc3\u8f6f\u4ef6\u505c\u6b62\u540e\u53f0\u64ad\u653e\uff0c\u8bf7\u5728\u76f8\u5173\u6e38\u620f\u8bbe\u7f6e\u7ed9\u4e88\u672c\u8f6f\u4ef6\u767d\u540d\u5355'
        ),
        new ProtectItemModel(
          '\u88ab\u7cfb\u7edf\u7ba1\u5bb6\u7ec8\u6b62',
          '\u7cfb\u7edf\u7ba1\u5bb6\u6e05\u7406\u540e\u53f0\u8fdb\u7a0b\u53ef\u80fd\u4f1a\u7ec8\u6b62\u672c\u8f6f\u4ef6\u540e\u53f0\u64ad\u653e'
        ),
        new ProtectItemModel(
          'Xposed \u6a21\u5757\u540e\u53f0\u9650\u5236',
          '\u68c0\u67e5\u662f\u5426\u6709\u4f7f\u7528\u62e5\u6709\u7cfb\u7edf\u63a7\u5236\u7684\u7a0b\u5e8f\uff0c\u68c0\u67e5\u662f\u5426\u9000\u51fa\u672c\u8f6f\u4ef6\u540e\u4f1a\u6740\u6b7b\u540e\u53f0\u97f3\u4e50\u64ad\u653e'
        ),
        new ProtectItemModel(
          'MusicService \u88ab\u7981\u7528',
          '\u68c0\u67e5\u662f\u5426\u6709\u4f7f\u7528\u62e5\u6709\u7cfb\u7edf\u63a7\u5236\u7684\u7a0b\u5e8f\uff0c\u68c0\u67e5\u662f\u5426\u7981\u7528\u4e86\u672c\u8f6f\u4ef6\u97f3\u4e50\u670d\u52a1 MusicService'
        )
      ]
    );
  }

  /**
   * Returns the cautious suggestions section.
   */
  static getCautiousSuggestions(): ProtectionSectionModel {
    return new ProtectionSectionModel(
      '\u8c28\u614e\u5efa\u8bae',
      [
        new ProtectItemModel(
          '\u8fd8\u539f\u6912\u76d0\u97f3\u4e50\u97f3\u9891\u8f93\u51fa\u8bbe\u7f6e',
          '\u4e0d\u5408\u9002\u7684\u97f3\u9891\u8f93\u51fa\u9009\u9879\u53ef\u80fd\u4f1a\u9020\u6210\u5f02\u5e38'
        ),
        new ProtectItemModel(
          '\u26a0\ufe0f\u5173\u95ed MIUI \u4f18\u5316',
          'MIUI \u4f18\u5316\u53ef\u80fd\u5bfc\u81f4\u8f6f\u4ef6\u540e\u53f0\u66f4\u5bb9\u6613\u88ab\u6740\u6b7b\uff08\u26a0\ufe0f\u4ec5\u53ef\u80fd\uff0c\u6b64\u9009\u9879\u66f4\u6539\u540e\u53ef\u80fd\u65e0\u6cd5\u8fd8\u539f\uff0c\u8c28\u614e\u9009\u62e9\uff09'
        ),
        new ProtectItemModel(
          '\u5176\u4ed6\u60c5\u51b5',
          '\u82e5\u4f9d\u65e7\u65e0\u6cd5\u89e3\u51b3\u95ee\u9898\uff0c\u8bf7\u53d6\u5f97\u8054\u7cfb'
        )
      ],
      '\u82e5\u4e0a\u65b9\u65e0\u6cd5\u89e3\u51b3\u95ee\u9898\uff0c\u53ef\u4ee5\u68c0\u67e5\u662f\u5426\u662f\u7531\u4e8e\u672c\u8f6f\u4ef6\u81ea\u8eab\u7684\u5d29\u6e83\uff0c\u53ef\u901a\u8fc7\u5806\u6808\u6355\u83b7\u7b49\u4e00\u4e9b\u7b2c\u4e09\u65b9\u5d29\u6e83\u68c0\u6d4b\u8f6f\u4ef6\uff0c\u8bf7\u8054\u7cfb\u5f00\u53d1\u4eba\u5458\uff0c\u6b64\u5916\u4ee5\u4e0b\u7ed9\u51fa\u4e00\u4e9b\u5efa\u8bae\u6216\u64cd\u4f5c\u53ef\u80fd\u6709\u52a9\u4e8e\u95ee\u9898\u89e3\u51b3'
    );
  }
}

// 后台播放能力检测与自启动权限引导。
