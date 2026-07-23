// AddCustomFolderDialogViewModel.ets
// ViewModel layer: provides data and handles business logic for AddCustomFolderDialog
//
// Responsibilities:
// - Manage tech support items data (sourced from Model)
// - Provide tip text for UI display
// - Handle user interactions: folder option clicks, tech support link clicks

import { DialogMenuActionType, TechSupportItem } from '../model/AddCustomFolderModel';

@Observed
export class AddCustomFolderDialogViewModel {
  // Tech support links displayed in the dialog
  @Track public techSupportItems: TechSupportItem[] = [];
  // Tip text shown between folder options
  @Track public tipText: string = '如果是车机系统或者其他情况无法启动原生文件管理器，请尝试下面方法';

  // Callbacks for external actions (set by the parent View)
  @Track private onNativeFileManagerCallback: () => void = () => {};
  @Track private onUsbDiskCallback: () => void = () => {};

  constructor(onNativeFileManager: () => void, onUsbDisk: () => void) {
    this.onNativeFileManagerCallback = onNativeFileManager;
    this.onUsbDiskCallback = onUsbDisk;
    this.initData();
  }

  // Initialize model data
  private initData(): void {
    this.techSupportItems = [
      new TechSupportItem(
        '车机 U 盘扫描教程',
        'https://www.bilibili.com/video/BV1ij421S7xE'
      )
    ];
  }

  // Handle folder option click based on action type
  handleFolderOptionClick(actionType: DialogMenuActionType): void {
    switch (actionType) {
      case DialogMenuActionType.NATIVE_FILE_MANAGER:
        this.onNativeFileManagerCallback();
        break;
      case DialogMenuActionType.USB_DISK:
        this.onUsbDiskCallback();
        break;
      default:
        break;
    }
  }

  // Handle tech support link click
  handleTechSupportClick(item: TechSupportItem): void {
    // TODO: Open URL in browser using system ability
    console.info(`TODO: open URL ${item.url} in browser`);
  }
}
