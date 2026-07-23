// TabletModeModel.ets
// Model layer: data structure for tablet mode settings
// Represents the raw data for tablet mode keyboard shortcut settings

export default class TabletModeModel {
  public spaceBarPlayOrPause: boolean = true

  constructor(spaceBarPlayOrPause: boolean = true) {
    this.spaceBarPlayOrPause = spaceBarPlayOrPause
  }
}

// 平板模式：空格键控制播放/暂停。

// 空格键播放对齐。
