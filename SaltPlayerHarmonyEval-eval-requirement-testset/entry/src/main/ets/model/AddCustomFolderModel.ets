// AddCustomFolderModel.ets
// Model layer: defines data structures for Add Custom Folder dialog

// Enum representing the type of action a dialog menu item triggers
export enum DialogMenuActionType {
  NATIVE_FILE_MANAGER = 0,
  USB_DISK = 1,
  OPEN_URL = 2
}

// Data model for the tech support link item
export class TechSupportItem {
  public text: string;
  public url: string;

  constructor(text: string, url: string) {
    this.text = text;
    this.url = url;
  }
}

// 添加自定义扫描文件夹：选定目录加入扫描范围。
