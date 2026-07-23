// AccessibilityModel.ets
// Model layer: data structure for accessibility settings
// Represents the raw data for display size scaling and system font following

export default class AccessibilityModel {
  public displaySizeScale: number = 1.0
  public followSystemFontScale: boolean = false

  constructor(displaySizeScale: number = 1.0, followSystemFontScale: boolean = false) {
    this.displaySizeScale = displaySizeScale
    this.followSystemFontScale = followSystemFontScale
  }
}

// 显示缩放：调整界面显示尺寸缩放比例。

// 跟随系统字体大小：随系统字体缩放调整文字。

// 无障碍对齐：显示缩放。
