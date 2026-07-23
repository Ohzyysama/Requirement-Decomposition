// FxActivityModel.ets
// Model layer: pure data structures and data operations for the FxActivity (AudioFX) page.
// Defines chart configuration, V3 effect settings, and data source operations.
// No UI or ViewModel logic. Reuses ParametricEQ/EqItem from AutoEqData.

import { ParametricEQ, EqItem, getAllAutoEq } from './AutoEqPresetData'

// Chart drawing configuration constants
export class FxChartConfig {
  static readonly PAD_LEFT: number = 28
  static readonly PAD_RIGHT: number = 16
  static readonly PAD_TOP: number = 12
  static readonly PAD_BOTTOM: number = 24
  static readonly X_MIN: number = 1.301   // log10(20)
  static readonly X_MAX: number = 4.301   // log10(20000)
  static readonly Y_MIN: number = -15
  static readonly Y_MAX: number = 15
  static readonly CHART_HEIGHT: number = 130

  // Frequency reference lines for X-axis grid
  static readonly FREQ_LINES: number[][] = [
    [20, 1.301], [100, 2.0], [200, 2.301],
    [1000, 3.0], [2000, 3.301], [10000, 4.0]
  ]
  static readonly FREQ_LABELS: string[] = ['20', '100 Hz', '200', '1000 Hz', '2000', '10000 Hz']

  // Gain reference lines for Y-axis grid
  static readonly GAIN_LINES: number[] = [-10, -5, 0, 5, 10]
}

// V3 audio effect setting item data
export class V3EffectItem {
  public title: string
  public enabled: boolean

  constructor(title: string, enabled: boolean) {
    this.title = title
    this.enabled = enabled
  }
}

// Data source for FxActivity data operations
export class FxActivityDataSource {
  // Load all AutoEQ presets
  static loadPresets(): ParametricEQ[] {
    return getAllAutoEq()
  }

  // Apply selected EQ preset to audio engine
  static applyEqPreset(preset: ParametricEQ): void {
    console.info(`FxActivityModel: applying EQ preset ${preset.name}`)
    // TODO: Implement actual EQ preset application via HarmonyOS audio framework
  }

  // Toggle MAX Audio Acoustics
  static setMaxAudioAcoustics(enabled: boolean): void {
    console.info(`FxActivityModel: MAX Audio Acoustics enabled = ${enabled}`)
    // TODO: Implement actual MAX Audio toggle
  }

  // Toggle DX8 Reverb
  static setDx8Reverb(enabled: boolean): void {
    console.info(`FxActivityModel: DX8 Reverb enabled = ${enabled}`)
    // TODO: Implement actual DX8 reverb toggle
  }

  // Sort EQ items by frequency (matching Android sortedBy { it.Fc })
  static sortEqItemsByFrequency(items: EqItem[]): EqItem[] {
    return items.slice().sort((a: EqItem, b: EqItem) => a.Fc - b.Fc)
  }

  // Convert frequency to log10 canvas X coordinate
  static toCanvasX(logF: number, padLeft: number, cw: number, xMin: number, xRange: number): number {
    return padLeft + ((logF - xMin) / xRange) * cw
  }

  // Convert gain dB to canvas Y coordinate (inverted: up is positive)
  static toCanvasY(gain: number, padTop: number, ch: number, yMax: number, yRange: number): number {
    return padTop + ((yMax - gain) / yRange) * ch
  }
}

// Intro text constant
export class FxIntroContent {
  static readonly INTRO_TEXT: string =
    'PEAKEQ Parametric Equalizer avoids the problem of fixed-band (graphic) equalizers where narrow dips and peaks falling between two bands are difficult to compensate. Restores precise parameters from the AutoEq library and other sources for perfect listening experience. Recommended for use with headphones.'
}

// 参数均衡器：应用 AutoEQ 预设到各频段，实时调节频响。

// 频响曲线：以对数频率轴绘制均衡器频响曲线可视化。
