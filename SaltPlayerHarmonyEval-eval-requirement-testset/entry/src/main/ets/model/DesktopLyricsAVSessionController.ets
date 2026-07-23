// DesktopLyricsAVSessionController.ets
// Owns the integration with HarmonyOS AVSession desktop-lyrics APIs
// (since API 23). Replaces the prior self-rendered floating window.
//
// Responsibilities:
//   - Cache isDesktopLyricSupported() once per process; no-op if false.
//   - Apply the master toggle (AppStorage 'desktopLyrics') by calling
//     enableDesktopLyric + setDesktopLyricVisible in lockstep with a
//     locally tracked state machine. The system constraint enforced
//     here: every setDesktopLyricVisible(true) must be paired with a
//     prior setDesktopLyricVisible(false) — we never re-call true while
//     already visible.
//   - Apply the lock toggle (AppStorage 'lockDesktopLyrics') via
//     setDesktopLyricState({isLocked}).
//   - Push the raw LRC payload to AVMetadata.lyric via
//     AudioPlayerService.setDesktopLyricsLrc on every song change after
//     the new song's lyrics have been parsed.
//   - Register on*Changed system callbacks and mirror external state
//     changes (user dismisses overlay via system gesture, system flips
//     lock) back into AppStorage so the Settings page UI stays in sync.

import { avSession as AVSessionManager } from '@kit.AVSessionKit'
import { BusinessError } from '@kit.BasicServicesKit'
import AudioPlayerService from './AudioPlayerService'
import { MiniLyricsController, MiniLyricsListener } from './MiniLyricsController'
import { QueueSongModel } from './PlayQueueModel'
import SettingsStore from './SettingsStore'
import { MediaCardDesktopLyricsButtonController } from './MediaCardDesktopLyricsButtonController'

export class DesktopLyricsAVSessionController {
  private static instance: DesktopLyricsAVSessionController | null = null

  private initialized: boolean = false
  // null = not yet probed; true/false = probe result cached.
  private supported: boolean | null = null

  // Locally tracked system overlay state — used to enforce the
  // "every visible(true) paired with a visible(false)" contract and
  // to skip redundant lock / enable calls.
  private enabled: boolean = false
  private visible: boolean = false
  private locked: boolean = false

  // Guard set while our own setEnabled() is executing. The
  // onDesktopLyricVisibilityChanged callback uses this to distinguish a
  // system echo of our own setDesktopLyricVisible(false) call (must be
  // ignored) from a user-driven close gesture on the system overlay
  // (must be propagated back to the Settings page master toggle).
  private inSetEnabled: boolean = false

  // Last LRC payload pushed to AVMetadata.lyric. Tracked here to skip
  // redundant setAVMetadata calls when the same LRC fires more than
  // once (e.g. multiple MiniLyricsListener callbacks per song load).
  private lastPushedLrc: string = ''

  private songChangedListener: (song: QueueSongModel) => void = (): void => {}
  private lyricsListener: MiniLyricsListener =
    (_id: string, _line: string, _hasLyrics: boolean): void => {}
  // Invoked from MediaCardDesktopLyricsButtonController.requestCloseFloatingWindow
  // when the user taps the close action from the media card / notification.
  // Mirrors the Settings page OFF path without going through the VM.
  private mediaCardCloseListener: () => void = (): void => {
    this.setEnabled(false).catch((e: Error) => {
      console.warn('DesktopLyricsAVSessionController.mediaCardCloseListener: '
        + e.message)
    })
  }

  private visibilityCb: ((v: boolean) => void) | null = null
  private stateCb: ((s: AVSessionManager.DesktopLyricState) => void) | null = null

  static getInstance(): DesktopLyricsAVSessionController {
    if (!DesktopLyricsAVSessionController.instance) {
      DesktopLyricsAVSessionController.instance =
        new DesktopLyricsAVSessionController()
    }
    return DesktopLyricsAVSessionController.instance
  }

  // Idempotent. Called from EntryAbility.onCreate after
  // AudioPlayerService.initContext() and MiniLyricsController.init().
  init(): void {
    if (this.initialized) {
      return
    }
    this.initialized = true

    // Push raw LRC into AVMetadata.lyric whenever the lyric document
    // for the currently playing song changes. Fires on every mini-lyric
    // notify; the dedupe inside maybePushLrc() skips no-ops.
    this.lyricsListener =
      (_songId: string, _line: string, _hasLyrics: boolean): void => {
        this.maybePushLrc()
      }
    MiniLyricsController.getInstance().addListener(this.lyricsListener)

    // Song change → clear last pushed marker so an empty-LRC->non-empty
    // transition for the same content hash still flushes through, and
    // proactively push (the document might already be loaded for the
    // restored song on cold start).
    this.songChangedListener = (_song: QueueSongModel): void => {
      this.maybePushLrc()
    }
    AudioPlayerService.getInstance()
      .addOnSongChangedListener(this.songChangedListener)

    MediaCardDesktopLyricsButtonController.getInstance()
      .addCloseListener(this.mediaCardCloseListener)

    // Cold-start auto-enable: if the user had the master toggle ON
    // when the app was last killed, restore the overlay. Probes
    // support lazily; no-op on unsupported devices.
    //
    // The AVSession is created asynchronously by AudioPlayerService.initContext;
    // by the time this init() runs the createAVSession Promise has been
    // kicked off but typically has not resolved yet. Going through
    // addSessionReadyListener guarantees setEnabled(true) is only called
    // after `getSession()` will return a live handle — otherwise the
    // setEnabled(true) call would silently bail at the `if (!session)` guard
    // and the overlay would never come up despite the persisted master toggle.
    const master: boolean = AppStorage.get<boolean>('desktopLyrics') ?? false
    if (master) {
      AudioPlayerService.getInstance().addSessionReadyListener((): void => {
        this.setEnabled(true).catch((e: Error) => {
          console.warn('DesktopLyricsAVSessionController.init auto-enable: '
            + e.message)
        })
      })
    }
  }

  // Master toggle entry point — called from the Settings page VM when
  // the user flips "桌面歌词" and on cold-start auto-restore in init().
  async setEnabled(on: boolean): Promise<void> {
    if (!await this.ensureSupported()) {
      return
    }
    const session = AudioPlayerService.getInstance().getSession()
    if (!session) {
      return
    }
    // Mark the whole transition as internally driven so the
    // onDesktopLyricVisibilityChanged callback we registered earlier
    // does not interpret our own setDesktopLyricVisible(false) call
    // as a user close gesture on the system overlay.
    this.inSetEnabled = true
    try {
      if (on) {
        if (!this.enabled) {
          try {
            await session.enableDesktopLyric(true)
            this.enabled = true
          } catch (err) {
            console.warn('DesktopLyricsAVSessionController.enable(true): '
              + (err as BusinessError).message)
            return
          }
          this.registerCallbacks(session)
        }
        // The system defaults the overlay to hidden after enable; this
        // is our first user-intent visible(true). The guard inside
        // setVisible() prevents double-true calls (matches the API
        // contract: every visible(true) paired with a prior visible(false)).
        await this.setVisible(true)
        const wantLocked: boolean =
          AppStorage.get<boolean>('lockDesktopLyrics') ?? false
        await this.applyLockInternal(session, wantLocked)
        // Push the current LRC so the overlay has content on first show.
        this.maybePushLrc()
      } else {
        if (this.enabled) {
          await this.setVisible(false)
          try {
            await session.enableDesktopLyric(false)
            this.enabled = false
            this.visible = false
            this.locked = false
          } catch (err) {
            console.warn('DesktopLyricsAVSessionController.enable(false): '
              + (err as BusinessError).message)
          }
          this.unregisterCallbacks(session)
        }
        // Drop the AVMetadata.lyric override so the system overlay (and
        // any other surfaces consuming the lyric field) stop showing
        // stale content for this session.
        this.lastPushedLrc = ''
        AudioPlayerService.getInstance().setDesktopLyricsLrc('')
      }
    } finally {
      this.inSetEnabled = false
    }
  }

  // Lock toggle entry point — called from the Settings page VM. No-op
  // when the overlay is not currently enabled (the API rejects
  // setDesktopLyricState before enableDesktopLyric).
  async setLocked(locked: boolean): Promise<void> {
    if (!await this.ensureSupported()) {
      return
    }
    if (!this.enabled) {
      // Persist the intent so the next setEnabled(true) honors it.
      // (Settings VM already wrote to SettingsStore — nothing to do.)
      return
    }
    const session = AudioPlayerService.getInstance().getSession()
    if (!session) {
      return
    }
    await this.applyLockInternal(session, locked)
  }

  destroy(): void {
    if (this.enabled) {
      // Best-effort teardown; the system session is being torn down so
      // we don't await results.
      this.setEnabled(false).catch((_e: Error) => { /* swallow */ })
    }
    try {
      MiniLyricsController.getInstance().removeListener(this.lyricsListener)
    } catch (_e) { /* swallow */ }
    try {
      AudioPlayerService.getInstance()
        .removeOnSongChangedListener(this.songChangedListener)
    } catch (_e) { /* swallow */ }
    try {
      MediaCardDesktopLyricsButtonController.getInstance()
        .removeCloseListener(this.mediaCardCloseListener)
    } catch (_e) { /* swallow */ }
    this.initialized = false
  }

  // ---- internals ----

  private async ensureSupported(): Promise<boolean> {
    if (this.supported !== null) {
      return this.supported
    }
    try {
      this.supported = await AVSessionManager.isDesktopLyricSupported()
    } catch (err) {
      // Per spec wording, callers should treat the throw as unsupported.
      console.warn('isDesktopLyricSupported failed: '
        + (err as BusinessError).message)
      this.supported = false
    }
    return this.supported
  }

  // Enforces the "every visible(true) paired with a prior visible(false)"
  // API contract by tracking local visible state and skipping calls
  // that would violate it. External visibility changes (system gestures)
  // are mirrored into `this.visible` via the onVisibilityChanged
  // callback, so the next user-intent show/hide picks up the right state.
  private async setVisible(visible: boolean): Promise<void> {
    if (visible === this.visible) {
      return
    }
    const session = AudioPlayerService.getInstance().getSession()
    if (!session) {
      return
    }
    try {
      await session.setDesktopLyricVisible(visible)
      this.visible = visible
    } catch (err) {
      console.warn('setDesktopLyricVisible(' + visible + '): '
        + (err as BusinessError).message)
    }
  }

  private async applyLockInternal(session: AVSessionManager.AVSession,
                                  locked: boolean): Promise<void> {
    if (locked === this.locked) {
      return
    }
    try {
      await session.setDesktopLyricState({ isLocked: locked })
      this.locked = locked
    } catch (err) {
      console.warn('setDesktopLyricState(isLocked=' + locked + '): '
        + (err as BusinessError).message)
    }
  }

  private registerCallbacks(session: AVSessionManager.AVSession): void {
    if (this.visibilityCb || this.stateCb) {
      return
    }
    try {
      this.visibilityCb = (v: boolean): void => {
        // Mirror external visibility change so our local state stays
        // truthful — the next user-intent setVisible call honours the
        // visible(true)-paired-with-false contract regardless of who
        // hid the overlay last.
        const wasVisible = this.visible
        this.visible = v
        // If the overlay just disappeared while master is on AND we are
        // not currently inside our own setEnabled() flow, the user must
        // have dismissed it via the system overlay's close action. Treat
        // that as a master OFF: tear down the system enable, persist the
        // flag, and notify the Settings VM so the 桌面歌词 SwitcherRow
        // flips back without requiring a page navigation.
        if (!v && wasVisible && this.enabled && !this.inSetEnabled) {
          this.handleExternalClose().catch((e: Error) => {
            console.warn('DesktopLyricsAVSessionController.externalClose: '
              + e.message)
          })
        }
      }
      session.onDesktopLyricVisibilityChanged(this.visibilityCb)
    } catch (err) {
      console.warn('onDesktopLyricVisibilityChanged register: '
        + (err as BusinessError).message)
      this.visibilityCb = null
    }
    try {
      this.stateCb = (st: AVSessionManager.DesktopLyricState): void => {
        if (this.locked === st.isLocked) {
          return
        }
        this.locked = st.isLocked
        // The user tapped lock/unlock on the system overlay. Mirror the
        // new state into AppStorage (and persist it) so the Settings
        // page's @StorageProp('lockDesktopLyrics') re-reads and the
        // 锁定歌词 switch flips to match — and so future setLocked()
        // comparisons and the next cold start see the right value.
        SettingsStore.getInstance().save('lockDesktopLyrics', st.isLocked)
        AppStorage.setOrCreate<boolean>('lockDesktopLyrics', st.isLocked)
      }
      session.onDesktopLyricStateChanged(this.stateCb)
    } catch (err) {
      console.warn('onDesktopLyricStateChanged register: '
        + (err as BusinessError).message)
      this.stateCb = null
    }
  }

  private unregisterCallbacks(session: AVSessionManager.AVSession): void {
    try {
      if (this.visibilityCb) {
        session.offDesktopLyricVisibilityChanged(this.visibilityCb)
      }
    } catch (_e) { /* swallow */ }
    try {
      if (this.stateCb) {
        session.offDesktopLyricStateChanged(this.stateCb)
      }
    } catch (_e) { /* swallow */ }
    this.visibilityCb = null
    this.stateCb = null
  }

  // Invoked from visibilityCb when the system reports the overlay was
  // hidden without our request — i.e. the user tapped close on the
  // system desktop-lyrics overlay. Mirrors the Settings page OFF path
  // (persist + tear down + drop AVMetadata.lyric). Writing 'desktopLyrics'
  // and 'lockDesktopLyrics' into AppStorage makes the Settings page's
  // @StorageProp-bound 桌面歌词 / 锁定歌词 switches flip back to OFF in
  // real time — the overlay is gone, so the lock state is meaningless and
  // is cleared so re-enabling starts from a clean slate.
  private async handleExternalClose(): Promise<void> {
    const session = AudioPlayerService.getInstance().getSession()
    if (session && this.enabled) {
      try {
        await session.enableDesktopLyric(false)
      } catch (err) {
        console.warn('DesktopLyricsAVSessionController.externalClose enable(false): '
          + (err as BusinessError).message)
      }
      this.unregisterCallbacks(session)
    }
    this.enabled = false
    this.visible = false
    this.locked = false
    this.lastPushedLrc = ''
    AudioPlayerService.getInstance().setDesktopLyricsLrc('')
    SettingsStore.getInstance().save('desktopLyrics', false)
    AppStorage.setOrCreate<boolean>('desktopLyrics', false)
    SettingsStore.getInstance().save('lockDesktopLyrics', false)
    AppStorage.setOrCreate<boolean>('lockDesktopLyrics', false)
  }

  private maybePushLrc(): void {
    const lrc: string = MiniLyricsController.getInstance().getCurrentDisplayLrc()
    if (lrc === this.lastPushedLrc) {
      return
    }
    this.lastPushedLrc = lrc
    AudioPlayerService.getInstance().setDesktopLyricsLrc(lrc)
  }
}

export default DesktopLyricsAVSessionController

// 锁定桌面歌词：锁定后悬浮歌词固定位置、触摸穿透并隐藏控制面板，锁定状态持久化。

// 桌面歌词开关：通过 AVSession 开启/关闭系统桌面歌词悬浮显示。

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}

// 计算两个经纬度坐标之间的球面近似距离（米）
function haversineDistanceF(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const toRad = (d: number): number => d * Math.PI / 180
  const R = 6371000
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) * Math.sin(dLon / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return R * c
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 将字节数格式化为带单位的可读字符串
function humanReadableBytesF(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value = value / 1024
    i++
  }
  const rounded = Math.round(value * 100) / 100
  return rounded.toString() + ' ' + units[i]
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H57(playEvents: number[], topN: number): Array<Record<string, number>> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < playEvents.length; i++) {
    const id: number = playEvents[i];
    const prev: number = counts.has(id) ? (counts.get(id) as number) : 0;
    counts.set(id, prev + 1);
  }
  const ranked: Array<Record<string, number>> = [];
  counts.forEach((cnt: number, id: number): void => {
    ranked.push({ songId: id, plays: cnt });
  });
  ranked.sort((a: Record<string, number>, b: Record<string, number>): number => b.plays - a.plays);
  return ranked.slice(0, Math.max(0, topN));
}

// 将字节数格式化为带单位的可读字符串
function humanReadableBytesF_H57(bytes: number): string {
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB']
  let value = bytes
  let i = 0
  while (value >= 1024 && i < units.length - 1) {
    value = value / 1024
    i++
  }
  const rounded = Math.round(value * 100) / 100
  return rounded.toString() + ' ' + units[i]
}

// 校验信用卡号是否通过 Luhn 校验
function luhnChecksumValidF_H57(digits: string): boolean {
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48
    if (d < 0 || d > 9) {
      return false
    }
    if (alt) {
      d = d * 2
      if (d > 9) {
        d = d - 9
      }
    }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_H57(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}

// 按音质标签分组累加文件数量与字节大小
function summarizeLibraryQualityE_H57(tracks: Array<Record<string, string | number>>): Map<string, Record<string, number>> {
  const stats: Map<string, Record<string, number>> = new Map<string, Record<string, number>>();
  for (let i = 0; i < tracks.length; i++) {
    const q: string = tracks[i].quality as string;
    const size: number = tracks[i].size as number;
    if (!stats.has(q)) {
      stats.set(q, { count: 0, bytes: 0 });
    }
    const bucket: Record<string, number> = stats.get(q) as Record<string, number>;
    bucket.count += 1;
    bucket.bytes += size;
  }
  return stats;
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_H57(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 校验信用卡号是否通过 Luhn 校验
function luhnChecksumValidF_H58(digits: string): boolean {
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48
    if (d < 0 || d > 9) {
      return false
    }
    if (alt) {
      d = d * 2
      if (d > 9) {
        d = d - 9
      }
    }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}

// 计算字符串的简单 32 位哈希（djb2 变体）
function djb2HashF_H58(input: string): number {
  let hash = 5381
  for (let i = 0; i < input.length; i++) {
    hash = ((hash << 5) + hash) + input.charCodeAt(i)
    hash = hash & 0xFFFFFFFF
  }
  return hash >>> 0
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_H58(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 在音乐库中按关键字匹配标题或艺术家，忽略大小写
function searchLibraryTracksE_H58(library: Array<Record<string, string>>, keyword: string): Array<Record<string, string>> {
  const key: string = keyword.trim().toLowerCase();
  if (key.length === 0) {
    return library.slice();
  }
  const hits: Array<Record<string, string>> = [];
  for (let i = 0; i < library.length; i++) {
    const title: string = (library[i].title !== undefined ? library[i].title : '').toLowerCase();
    const artist: string = (library[i].artist !== undefined ? library[i].artist : '').toLowerCase();
    if (title.indexOf(key) >= 0 || artist.indexOf(key) >= 0) {
      hits.push(library[i]);
    }
  }
  return hits;
}

// 累加每首歌的播放次数并取播放最多的前 N 首
function topPlayedSongsE_H58(playEvents: number[], topN: number): Array<Record<string, number>> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < playEvents.length; i++) {
    const id: number = playEvents[i];
    const prev: number = counts.has(id) ? (counts.get(id) as number) : 0;
    counts.set(id, prev + 1);
  }
  const ranked: Array<Record<string, number>> = [];
  counts.forEach((cnt: number, id: number): void => {
    ranked.push({ songId: id, plays: cnt });
  });
  ranked.sort((a: Record<string, number>, b: Record<string, number>): number => b.plays - a.plays);
  return ranked.slice(0, Math.max(0, topN));
}

// 主题模式解析：0=跟随系统/1=浅色/2=深色，跟随系统时回退到系统当前深浅
function resolveEffectiveThemeF_H58(selectedTheme: number, systemIsDark: boolean): string {
  if (selectedTheme === 1) {
    return 'light'
  }
  if (selectedTheme === 2) {
    return 'dark'
  }
  if (selectedTheme === 0) {
    return systemIsDark ? 'dark' : 'light'
  }
  return systemIsDark ? 'dark' : 'light'
}

// 桌面歌词开关状态机：在 关闭/请求中/已上屏 间流转，仅当元数据就绪才允许上屏
function transitionDesktopLyricsStateF_X12(current: string, action: string, metadataReady: boolean): string {
  const order: string[] = ['off', 'requesting', 'shown']
  if (action === 'disable') {
    return 'off'
  }
  if (action === 'enable') {
    if (current === 'off') {
      return 'requesting'
    }
    if (current === 'requesting' && metadataReady) {
      return 'shown'
    }
  }
  return order.indexOf(current) >= 0 ? current : 'off'
}

// 切换桌面歌词锁定状态：锁定时屏蔽拖动与点击交互，仅保留显示
function toggleDesktopLyricsLockF_X12(locked: boolean): Map<string, boolean> {
  const next = !locked
  const result = new Map<string, boolean>()
  result.set('locked', next)
  result.set('draggable', !next)
  result.set('clickThrough', next)
  result.set('showHandle', !next)
  result.set('persisted', true)
  return result
}

// 校验信用卡号是否通过 Luhn 校验
function luhnChecksumValidF_X12(digits: string): boolean {
  let sum = 0
  let alt = false
  for (let i = digits.length - 1; i >= 0; i--) {
    let d = digits.charCodeAt(i) - 48
    if (d < 0 || d > 9) {
      return false
    }
    if (alt) {
      d = d * 2
      if (d > 9) {
        d = d - 9
      }
    }
    sum += d
    alt = !alt
  }
  return sum % 10 === 0
}
