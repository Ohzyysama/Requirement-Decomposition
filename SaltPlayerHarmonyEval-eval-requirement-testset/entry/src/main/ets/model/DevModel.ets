// DevModel.ets
// Model layer for DevPage - defines the core data structures for the Developer page.
// Model layer is responsible for data structure definition and data management,
// and does not interact with the UI directly.

import { deviceInfo } from '@kit.BasicServicesKit'

/**
 * Represents a key-value information item (e.g., device info, software info).
 */
export class DevInfoItemModel {
  public label: string;
  public value: string;

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/**
 * Represents a clickable control item in the Control section.
 */
export class DevControlItemModel {
  public text: string;

  constructor(text: string) {
    this.text = text;
  }
}

/**
 * Represents a toggle item with optional subtitle.
 */
export class DevToggleItemModel {
  public text: string;
  public isOn: boolean;
  public sub: string | undefined;

  constructor(text: string, isOn: boolean, sub: string | undefined) {
    this.text = text;
    this.isOn = isOn;
    this.sub = sub;
  }
}

/**
 * Provides the default data for the Dev page from the data source layer.
 */
export class DevDataSource {
  /**
   * Returns device information items by querying deviceInfo APIs.
   */
  static getDeviceInfoItems(): DevInfoItemModel[] {
    return [
      new DevInfoItemModel('品牌', deviceInfo.brand),
      new DevInfoItemModel('制造商', deviceInfo.manufacture),
      new DevInfoItemModel('model', deviceInfo.productModel),
      new DevInfoItemModel('rom.i.name', deviceInfo.brand),
      new DevInfoItemModel('rom.i.ver', deviceInfo.displayVersion),
      new DevInfoItemModel('HarmonyOS 版本', deviceInfo.osFullName)
    ];
  }

  /**
   * Returns software information items.
   */
  static getSoftwareInfoItems(): DevInfoItemModel[] {
    return [
      new DevInfoItemModel('app.n', '-'),
      new DevInfoItemModel('app.build', '-'),
      new DevInfoItemModel('is debug', '-'),
      new DevInfoItemModel('dex.crc', '-'),
      new DevInfoItemModel('name.md5', '-'),
      new DevInfoItemModel('audio', '-'),
      new DevInfoItemModel('fx', '-'),
      new DevInfoItemModel('MT20250407', '-')
    ];
  }

  /**
   * Returns control action items.
   */
  static getControlItems(): DevControlItemModel[] {
    return [
      new DevControlItemModel('dev - stopSelf'),
      new DevControlItemModel('dev - stop MusicService'),
      new DevControlItemModel('BassPlayer - stop'),
      new DevControlItemModel('测试取消同意用户协议和隐私政策')
    ];
  }

  /**
   * Returns the default toggle state for Dev Monitor.
   */
  static getDevMonitorToggle(): DevToggleItemModel {
    return new DevToggleItemModel('Dev Monitor', false, '1.0.0');
  }

  /**
   * Returns the default toggle state for Lyrics Dragging Effect End.
   */
  static getLyricsDraggingToggle(): DevToggleItemModel {
    return new DevToggleItemModel('LYRICS_UI_USER_DRAGGING_EFFECT_END', true, undefined);
  }

  /**
   * Returns bottom clickable items.
   */
  static getBottomItems(): string[] {
    return ['TestScreen', '安全防护'];
  }
}
