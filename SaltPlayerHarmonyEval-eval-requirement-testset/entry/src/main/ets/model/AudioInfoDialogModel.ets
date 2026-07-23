// AudioInfoDialogModel.ets
// Model layer: pure data + constants for the Audio Output Info dialog (spec14).
// Contains no UI, no ViewModel logic, no ArkUI decorators.
// Houses the SRC quality label table, output mode display name mapping, and
// Hz/kbps formatting helpers used by AudioInfoDialogViewModel.

// Resampling (SRC) quality labels. Array index maps to the persisted
// integer `resamplingQuality` value written in EntryAbility (default = 2).
// Values outside this array's range fall back to "未知" via
// getResamplingQualityLabel.
export const RESAMPLING_QUALITY_LABELS: string[] = [
  'LINEAR',        // 0
  '8 POINT SINC',  // 1
  '16 POINT SINC', // 2
  '32 POINT SINC', // 3
  '64 POINT SINC'  // 4
]

/**
 * Resolve the display label for a resampling quality integer.
 * Returns '未知' for undefined / negative / out-of-range values — matches
 * the SPEC rule "品质 映射：LINEAR/8/16/32/64 POINT SINC/未知".
 */
export function getResamplingQualityLabel(q: number | undefined): string {
  if (q === undefined || q === null) {
    return '未知'
  }
  if (q < 0 || q >= RESAMPLING_QUALITY_LABELS.length) {
    return '未知'
  }
  return RESAMPLING_QUALITY_LABELS[q]
}

/**
 * Resolve the display name for an audio output mode string.
 * SPEC 3.6: DIRECT / AudioTrack / OpenSL ES / AAudio.
 * Undefined / empty / unknown → AudioTrack (spec "未初始化 → AudioTrack").
 */
export function getOutputModeDisplayName(mode: string | undefined): string {
  if (mode === undefined || mode === null || mode.length === 0) {
    return 'AudioTrack'
  }
  switch (mode) {
    case 'direct':
      return 'DIRECT'
    case 'audiotrack':
      return 'AudioTrack'
    case 'opensl':
      return 'OpenSL ES'
    case 'aaudio':
      return 'AAudio'
    default:
      return 'AudioTrack'
  }
}

/**
 * Format a hertz value. Missing / <=0 → "0 Hz" per SPEC缺失规则.
 */
export function formatHz(v: number | undefined): string {
  if (v === undefined || v === null || !isFinite(v) || v <= 0) {
    return '0 Hz'
  }
  return `${Math.round(v)} Hz`
}

/**
 * Format a kbps value. The input is raw bits/sec from song metadata
 * (same convention as AudioInfoModel.bitrate). Missing / <=0 → "0 kbps".
 */
export function formatKbps(v: number | undefined): string {
  if (v === undefined || v === null || !isFinite(v) || v <= 0) {
    return '0 kbps'
  }
  const kbps = v / 1000
  return `${kbps % 1 === 0 ? kbps.toFixed(0) : kbps.toFixed(6)} kbps`
}

/**
 * Pure DTO capturing every raw field fed into AudioInfoDialogViewModel.
 * The VM converts this snapshot into user-facing strings using the formatters
 * above and the SPEC-defined missing-value fallbacks.
 */
export class AudioInfoSnapshot {
  public filePath: string = ''
  public appVersion: string = ''
  public audioSessionId: number | undefined = undefined
  public dspFloatSupported: boolean | undefined = undefined
  public initSampleRate: number | undefined = undefined
  public recommendedSampleRate: number = 0
  public useSystemCodec: boolean | undefined = undefined
  public streamSampleRate: number | undefined = undefined
  public streamBitrate: number | undefined = undefined
  public outputLinkSampleRate: number = 0
  public resamplingQuality: number = 2
  public saltAudioFxName: string = ''
  public v3ReverbEnabled: boolean | undefined = undefined
  public outputMode: string = 'audiotrack'
  public averageLatencyMs: number | undefined = undefined
  public channelCount: number = 2
}
