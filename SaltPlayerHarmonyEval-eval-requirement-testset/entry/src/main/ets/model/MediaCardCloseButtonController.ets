// MediaCardCloseButtonController.ets
// spec23 — mirrors the "显示关闭按钮" toggle into AVSession extras +
// dispatchSessionEvent. Pushes the current value on init, on every toggle
// flip (called by NotificationViewModel.onCloseButtonChanged), and on every
// song change so a freshly-activated AVSession inherits the latest value.
//
// Pattern-identical to NotificationLyricController:
//   - singleton in the model package
//   - init() called from EntryAbility.onCreate() after
//     AudioPlayerService.initContext(...)
//   - onToggleChanged() poked by the relevant ViewModel after persistence
//   - publish() calls into AudioPlayerService (the sole AVSession toucher)

import AudioPlayerService from './AudioPlayerService'
import { QueueSongModel } from './PlayQueueModel'

export class MediaCardCloseButtonController {
  private static instance: MediaCardCloseButtonController | null = null
  private initialized: boolean = false
  private lastPublished: boolean | null = null
  private songChangedListener: (s: QueueSongModel) => void = (): void => {}

  static getInstance(): MediaCardCloseButtonController {
    if (!MediaCardCloseButtonController.instance) {
      MediaCardCloseButtonController.instance = new MediaCardCloseButtonController()
    }
    return MediaCardCloseButtonController.instance
  }

  // Idempotent init — call once after AudioPlayerService.initContext(...)
  // in EntryAbility.onCreate.
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true

    // Initial publish so the value is in AVSession before the first song plays.
    this.publish()

    this.songChangedListener = (_s: QueueSongModel): void => {
      // Republish on song change because session.setExtras can be a no-op
      // before the session is fully activated; the song-change path is the
      // moment we know the session is fresh.
      this.lastPublished = null
      this.publish()
    }
    AudioPlayerService.getInstance().addOnSongChangedListener(this.songChangedListener)
  }

  // Called by NotificationViewModel.onCloseButtonChanged after the model
  // has persisted the new value.
  onToggleChanged(): void {
    this.publish()
  }

  destroy(): void {
    if (!this.initialized) {
      return
    }
    AudioPlayerService.getInstance().removeOnSongChangedListener(this.songChangedListener)
    this.initialized = false
  }

  private publish(): void {
    const value: boolean = AppStorage.get<boolean>('showCloseButton') ?? true
    if (value === this.lastPublished) {
      return
    }
    this.lastPublished = value
    AudioPlayerService.getInstance().publishCloseButtonExtras(value)
  }
}

export default MediaCardCloseButtonController

// 通知关闭按钮：处理媒体通知关闭动作。
