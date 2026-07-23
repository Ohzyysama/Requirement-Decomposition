// SettingsStore.ets
// Singleton utility for immediate settings persistence via Preferences API.
// PersistentStorage is unreliable on some devices — this ensures settings
// are written to disk reliably.
//
// Usage pattern:
//   save()     — called by ViewModels on every setting change (writes + flushSync to disk)
//   flush()    — called by EntryAbility.onBackground()/onDestroy() as batch safety net
//   get()      — called by EntryAbility.onCreate() to restore settings on startup

import { preferences } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'

const SETTINGS_PREFS = 'settings_state'

export default class SettingsStore {
  private static instance: SettingsStore | undefined = undefined
  private store: preferences.Preferences | undefined = undefined

  private constructor() {
  }

  static getInstance(): SettingsStore {
    if (!SettingsStore.instance) {
      SettingsStore.instance = new SettingsStore()
    }
    return SettingsStore.instance
  }

  // Initialize with context — must be called in EntryAbility.onCreate()
  init(context: Context): void {
    try {
      this.store = preferences.getPreferencesSync(context, { name: SETTINGS_PREFS })
    } catch (_e) {
      // initialization failed
    }
  }

  // Save a setting to AppStorage (immediate UI update) and Preferences.
  // Writes immediately to disk via flushSync() so data survives process kill
  // (e.g. DevEco Studio Build & Run) even when onBackground() never fires.
  save(key: string, value: number | boolean | string): void {
    AppStorage.setOrCreate(key, value)
    if (this.store) {
      try {
        this.store.putSync(key, value)
        this.store.flushSync()
      } catch (_e) {
        // write failed
      }
    }
  }

  // Flush all pending writes to disk. Call from EntryAbility.onBackground().
  flush(): void {
    if (this.store) {
      try {
        this.store.flushSync()
      } catch (_e) {
        // flush failed
      }
    }
  }

  // Read a setting from Preferences (used in EntryAbility.onCreate for restoration)
  get(key: string, defaultValue: number | boolean | string): number | boolean | string {
    if (this.store) {
      try {
        return this.store.getSync(key, defaultValue) as number | boolean | string
      } catch (_e) {
        // read failed
      }
    }
    return defaultValue
  }
}

// 设置持久化：save 写入 AppStorage 与 Preferences 并 flush。
