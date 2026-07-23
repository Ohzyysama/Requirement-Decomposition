// DevViewModel.ets
// ViewModel layer for DevPage - provides data and services for the Dev page View.
// ViewModel acts as the bridge between Model and View:
//   - Exposes observable data for the View to bind to
//   - Provides methods for the View to call when user interactions occur
//   - Retrieves data from Model layer and transforms it for presentation

import {
  DevInfoItemModel,
  DevControlItemModel,
  DevToggleItemModel,
  DevDataSource
} from '../model/DevModel'
import { AgreementModel } from '../model/AgreementModel'
import { common } from '@kit.AbilityKit'

@Observed
export default class DevViewModel {
  // ========== Monitor toggles ==========
  @Track public devMonitorOn: boolean = false;
  @Track public devMonitorSub: string | undefined = '1.0.0';

  // ========== Control toggles ==========
  @Track public lyricsDraggingEffectEnd: boolean = true;

  // ========== Data lists (rendered via ForEach in the View) ==========
  @Track private deviceInfoItems: DevInfoItemModel[] = [];
  @Track private softwareInfoItems: DevInfoItemModel[] = [];
  @Track private controlItems: DevControlItemModel[] = [];
  @Track private bottomItems: string[] = [];

  constructor() {
    this.loadData();
  }

  /**
   * Loads all data from the Model layer.
   */
  private loadData(): void {
    // Load toggle states from model defaults
    const devMonitorToggle: DevToggleItemModel = DevDataSource.getDevMonitorToggle();
    this.devMonitorOn = devMonitorToggle.isOn;
    this.devMonitorSub = devMonitorToggle.sub;

    const lyricsDraggingToggle: DevToggleItemModel = DevDataSource.getLyricsDraggingToggle();
    this.lyricsDraggingEffectEnd = lyricsDraggingToggle.isOn;

    // Load info lists from model
    this.deviceInfoItems = DevDataSource.getDeviceInfoItems();
    this.softwareInfoItems = DevDataSource.getSoftwareInfoItems();
    this.controlItems = DevDataSource.getControlItems();
    this.bottomItems = DevDataSource.getBottomItems();
  }

  // ========== Getters for list data ==========

  getDeviceInfoItems(): DevInfoItemModel[] {
    return this.deviceInfoItems;
  }

  getSoftwareInfoItems(): DevInfoItemModel[] {
    return this.softwareInfoItems;
  }

  getControlItems(): DevControlItemModel[] {
    return this.controlItems;
  }

  getBottomItems(): string[] {
    return this.bottomItems;
  }

  // ========== Action handlers ==========

  /**
   * Handles Dev Monitor toggle change.
   */
  toggleDevMonitor(isOn: boolean): void {
    this.devMonitorOn = isOn;
    console.info('Dev Monitor toggled: ' + isOn);
  }

  /**
   * Handles Lyrics Dragging Effect End toggle change.
   */
  toggleLyricsDraggingEffectEnd(isOn: boolean): void {
    this.lyricsDraggingEffectEnd = isOn;
    console.info('LYRICS_UI_USER_DRAGGING_EFFECT_END toggled: ' + isOn);
  }

  /**
   * Handles clickable item action (e.g., control items, bottom items).
   * Matching is by the exact title text in DevDataSource.getControlItems
   * so the Model stays the single source of truth for labels.
   */
  handleClickableItemAction(text: string, context?: common.UIAbilityContext): void {
    if (text === '测试取消同意用户协议和隐私政策' && context) {
      AgreementModel.clearAgreed(context)
      return
    }
    console.info('TODO: ' + text + ' clicked');
  }

  /**
   * Handles navigation back.
   */
  navigateBack(navPathStack: NavPathStack): void {
    navPathStack.pop();
  }
}
