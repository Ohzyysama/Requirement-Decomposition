// StartupAndBackendModel.ets
// Model layer: data structure for startup and backend settings
// Represents the raw data for auto playback toggle state
// Corresponds to Android Config.AUTO_PLAYBACK stored in MMKV

export default class StartupAndBackendModel {
  public autoPlayback: boolean = false

  constructor(autoPlayback: boolean = false) {
    this.autoPlayback = autoPlayback
  }
}

// 启动与后台：配置启动行为与后台播放选项。
