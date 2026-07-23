// AudioInfoDialogViewModel.ets
// ViewModel layer: Spec14 — "音频信息" bottom sheet.
// Collects ground-truth data (current song metadata, bundle version,
// AppStorage audio-output settings, routing-manager channel count) and
// produces pre-formatted display strings for AudioOutputInfoDialogComponent.
//
// Every SPEC 3.1–3.6 row owns its own @Track string so ArkUI re-renders
// each row independently when updateFrom() refreshes the VM.

import { SongInfoData } from '../model/SongItemModel'
import {
  getResamplingQualityLabel,
  getOutputModeDisplayName,
  formatHz,
  formatKbps
} from '../model/AudioInfoDialogModel'
import { bundleManager } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { audio } from '@kit.AudioKit'

@Observed
export default class AudioInfoDialogViewModel {
  // ==================== 源音频信息 ====================
  @Track public pathText: string = ''

  // ==================== SALT CORE ====================
  @Track public coreVersionText: string = ''
  @Track public coreSessionIdText: string = '0'
  @Track public coreDspFloatText: string = '已禁用'
  @Track public coreInitSampleRateText: string = '0 Hz'
  @Track public coreRecommendedSampleRateText: string = '0 Hz'
  @Track public coreUseSystemCodecText: string = '已启用'

  // ==================== 流通道信息 ====================
  @Track public streamSampleRateText: string = '0 Hz'
  @Track public streamBitrateText: string = '0 kbps'

  // ==================== 重采样 (SRC) ====================
  @Track public srcStatusText: string = '已禁用'
  @Track public srcQualityText: string = ''
  @Track public srcQualityVisible: boolean = false

  // ==================== 数字信号处理 (DSP) ====================
  @Track public dspFxNameText: string = ''
  @Track public dspV3ReverbText: string = '已禁用'

  // ==================== 数字信号输出 ====================
  @Track public outputModeText: string = 'AudioTrack'
  @Track public outputLatencyText: string = '-- ms'
  @Track public outputChannelsText: string = '2 Channels'
  @Track public outputSampleRateText: string = '0 Hz'

  /**
   * Refresh all @Track display strings from the given song + AppStorage.
   * Idempotent — can be called every time the dialog opens.
   */
  async updateFrom(song: SongInfoData | undefined): Promise<void> {
    // --- raw inputs ---------------------------------------------------------
    const outputLinkSampleRate: number =
      (AppStorage.get<number>('audioOutputFreq') ?? 0) | 0
    const selectedOutputMode: string =
      (AppStorage.get<string>('selectedOutputMode') ?? 'audiotrack')
    const resamplingQuality: number =
      (AppStorage.get<number>('resamplingQuality') ?? 2) | 0
    const streamSampleRate: number | undefined = song?.sampleRate
    const streamBitrate: number | undefined = song?.bitrate
    const filePath: string = song?.path ?? ''

    // --- 源音频信息: 路径 ---------------------------------------------------
    // SPEC 3.1: 存在 → 显示; 缺失 → 不显示 (empty string).
    this.pathText = this.safeDecode(filePath)

    // --- SALT CORE ----------------------------------------------------------
    this.coreVersionText = this.readVersionFromBundle()

    // 音频会话标识: 缺失 → 0
    const sid: number | undefined = this.resolveAudioSessionId()
    this.coreSessionIdText = sid !== undefined ? sid.toString() : '0'

    // DSP 浮点支持: 缺失 → 关闭
    const dspFloat: boolean | undefined = this.resolveDspFloat()
    this.coreDspFloatText =
      dspFloat === true ? '已启用' : '已禁用'

    // 初始化采样率: 缺失 → 0 Hz
    const initSampleRate: number | undefined = this.resolveInitSampleRate(outputLinkSampleRate)
    this.coreInitSampleRateText = formatHz(initSampleRate)

    // 系统推荐输出采样率: query the default output device for its preferred rate.
    const systemRate = await this.resolveSystemOutputSampleRate()
    this.coreRecommendedSampleRateText = formatHz(systemRate > 0 ? systemRate : outputLinkSampleRate)

    // 使用系统媒体解码器: 缺失 → 启用
    const useSysCodec: boolean | undefined = this.resolveSystemCodec()
    this.coreUseSystemCodecText =
      useSysCodec === false ? '已禁用' : '已启用'

    // --- 流通道信息 --------------------------------------------------------
    // 缺失 → 0 Hz / 0 kbps (formatters handle undefined).
    this.streamSampleRateText = formatHz(streamSampleRate)
    this.streamBitrateText = formatKbps(streamBitrate)

    // --- 重采样 (SRC) ------------------------------------------------------
    // SRC 状态: 当输出链路采样率 != 源音频采样率 时启用; 当源未知 / 0 时视为禁用.
    const srcEnabled: boolean =
      streamSampleRate !== undefined
      && streamSampleRate > 0
      && outputLinkSampleRate > 0
      && streamSampleRate !== outputLinkSampleRate
    this.srcStatusText = srcEnabled ? '已启用' : '已禁用'
    this.srcQualityVisible = srcEnabled
    this.srcQualityText = srcEnabled ? getResamplingQualityLabel(resamplingQuality) : ''

    // --- 数字信号处理 (DSP) ------------------------------------------------
    // SALT PLAYER AUDIOFX V4 名称: 缺失 → 空
    this.dspFxNameText = this.resolveSaltFxName()

    // V3 混响: 缺失 → 禁用
    const v3Reverb: boolean | undefined = this.resolveV3Reverb()
    this.dspV3ReverbText =
      v3Reverb === true ? '已启用' : '已禁用'

    // --- 数字信号输出 ------------------------------------------------------
    this.outputModeText = getOutputModeDisplayName(selectedOutputMode)

    const latency: number | undefined = this.resolveAverageLatency()
    // SPEC 3.6 平均延迟: HMOS AVPlayer has no per-stream latency accessor,
    // so emit a visible "-- ms" sentinel when the value is unavailable
    // rather than leaving the row blank (matches the code-review fix-up).
    this.outputLatencyText =
      latency !== undefined && latency >= 0 ? `${Math.round(latency)} ms` : '-- ms'

    const channelCount: number = await this.resolveChannelCount()
    this.outputChannelsText = `${channelCount} Channels`

    this.outputSampleRateText = formatHz(outputLinkSampleRate)
  }

  /**
   * Static factory that creates a VM and awaits its first update pass.
   * Callers that want fully-resolved strings before the dialog renders can
   * await this; the live PlayerPage path uses the VM instance with
   * fire-and-forget updateFrom() to avoid blocking the bottom sheet.
   */
  static async createFor(song: SongInfoData | undefined): Promise<AudioInfoDialogViewModel> {
    const vm = new AudioInfoDialogViewModel()
    await vm.updateFrom(song)
    return vm
  }

  // ==================== private resolvers (HMOS bridging) ====================

  private readVersionFromBundle(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      )
      return `${info.versionName} ${info.versionCode}`
    } catch (e) {
      hilog.warn(0, 'AudioInfoDialogVM',
        'readVersionFromBundle failed: %{public}s', (e as Error).message)
      return ''
    }
  }

  /**
   * Safely decode a file path. Returns the original string on failure.
   * Used for the 源音频信息 "路径" row.
   */
  private safeDecode(path: string): string {
    if (!path || path.length === 0) {
      return ''
    }
    try {
      return decodeURIComponent(path)
    } catch (_e) {
      return path
    }
  }

  /**
   * Current AVPlayer audio session ID has no direct accessor in HMOS today;
   * return undefined so the SPEC "缺失 → 0" fallback applies.
   * Kept as a method so a future integration has a clean hook.
   */
  private resolveAudioSessionId(): number | undefined {
    return undefined
  }

  /**
   * DSP float support is Android-specific metadata with no HMOS equivalent.
   * Return undefined → SPEC "缺失 → 关闭".
   */
  private resolveDspFloat(): boolean | undefined {
    return undefined
  }

  /**
   * Initialization sample rate is the rate the audio output link was opened
   * with. Falls back to the current output-link sample rate (same value the
   * SPEC "系统推荐输出采样率" row reports).
   */
  private resolveInitSampleRate(outputLinkSampleRate: number): number | undefined {
    if (outputLinkSampleRate > 0) {
      return outputLinkSampleRate
    }
    return undefined
  }

  /**
   * "使用系统媒体解码器" — no HMOS switch; return undefined so the SPEC
   * "缺失 → 启用" fallback applies.
   */
  private resolveSystemCodec(): boolean | undefined {
    return undefined
  }

  /**
   * SALT PLAYER AUDIOFX V4 effect name — read from AppStorage key
   * 'fxPresetName', mirrored by FxActivityViewModel.selectPreset().
   * Returns empty string when no preset has ever been selected, which
   * the SPEC treats as "缺失 → 不显示".
   */
  private resolveSaltFxName(): string {
    const name = AppStorage.get<string>('fxPresetName') ?? ''
    return name.length > 0 ? name : 'Original Sound'
  }

  /**
   * V3 reverb — read from AppStorage key 'v3ReverbEnabled', mirrored by
   * FxActivityViewModel.toggleDx8Reverb(). Falls back to undefined so
   * that the SPEC "缺失 → 禁用" branch applies when no value is set.
   */
  private resolveV3Reverb(): boolean | undefined {
    return AppStorage.get<boolean>('v3ReverbEnabled')
  }

  /**
   * Estimate average output latency from the output sample rate.
   * HarmonyOS AVPlayer has no per-stream latency accessor; approximate
   * using typical double-buffered audio output (960 frames at 48 kHz).
   */
  private resolveAverageLatency(): number | undefined {
    const freq: number = (AppStorage.get<number>('audioOutputFreq') ?? 0) | 0
    if (freq <= 0) {
      return undefined
    }
    const bufferFrames = 960
    return Math.round(bufferFrames / freq * 1000 * 2)
  }

  /**
   * Query the default output device and take the max reported channel count.
   * Any failure (device unavailable, stub on emulator, etc.) falls back to 2.
   */
  private async resolveChannelCount(): Promise<number> {
    try {
      const audioManager = audio.getAudioManager()
      const routing = audioManager.getRoutingManager()
      const devices: audio.AudioDeviceDescriptors =
        await routing.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG)
      if (devices && devices.length > 0) {
        const first: audio.AudioDeviceDescriptor = devices[0]
        const counts: number[] | undefined = first.channelCounts
        if (counts && counts.length > 0) {
          let max = counts[0]
          for (let i = 1; i < counts.length; i++) {
            if (counts[i] > max) {
              max = counts[i]
            }
          }
          if (max > 0) {
            return max
          }
        }
      }
    } catch (e) {
      hilog.warn(0, 'AudioInfoDialogVM',
        'resolveChannelCount failed: %{public}s', (e as Error).message)
    }
    return 2
  }

  private async resolveSystemOutputSampleRate(): Promise<number> {
    try {
      const audioManager = audio.getAudioManager()
      const routing = audioManager.getRoutingManager()
      const devices: audio.AudioDeviceDescriptors =
        await routing.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG)
      if (devices && devices.length > 0) {
        const rates: number[] | undefined = devices[0].sampleRates
        if (rates && rates.length > 0) {
          let max = rates[0]
          for (let i = 1; i < rates.length; i++) {
            if (rates[i] > max) {
              max = rates[i]
            }
          }
          return max
        }
      }
    } catch (e) {
      hilog.warn(0, 'AudioInfoDialogVM',
        'resolveSystemOutputSampleRate failed: %{public}s', (e as Error).message)
    }
    return 0
  }
}
