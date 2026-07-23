// FxActivityViewModel.ets
// ViewModel layer: provides data and logic for FxActivityPage (View).
// Bridges the Model layer data with the View layer, exposing state variables and methods.
// View calls ViewModel methods on user interaction; ViewModel delegates to Model for data operations.

import { ParametricEQ, EqItem, getBandIcon } from '../model/AutoEqPresetData'
import { FxChartConfig, FxActivityDataSource } from '../model/FxActivityModel'

@Observed
export default class FxActivityViewModel {
  // Current active tab index: 0 = AUDIOFX (AutoEQ), 1 = V3 Effects
  @Track public currentTab: number = 0

  // Currently selected EQ preset — initial value from AppStorage so that
  // Spec14 音频信息 dialog can read the live FX V4 preset name. Falls back
  // to the first preset when AppStorage has no saved name or the saved
  // name does not match any preset.
  @Track public currentEq: ParametricEQ = FxActivityViewModel.loadInitialEq()

  // V3 effect toggle states
  @Track public maxAudioAcoustics: boolean = true
  // V3 reverb (DX8) — initial value mirrored from AppStorage for Spec14.
  @Track public dx8Reverb: boolean = AppStorage.get<boolean>('v3ReverbEnabled') ?? false

  // Select the initial EQ preset by name (AppStorage key 'fxPresetName'),
  // falling back to the first preset if no match is found.
  private static loadInitialEq(): ParametricEQ {
    const presets: ParametricEQ[] = FxActivityDataSource.loadPresets()
    const savedName: string | undefined = AppStorage.get<string>('fxPresetName')
    if (savedName && savedName.length > 0) {
      for (let i = 0; i < presets.length; i++) {
        if (presets[i].name === savedName) {
          return presets[i]
        }
      }
    }
    return presets[0]
  }

  // Whether to show the intro bottom sheet
  @Track public showIntroSheet: boolean = false

  // Dynamically computed background image height
  @Track public bgHeight: number = 240

  // Whether the canvas chart is ready
  @Track public chartReady: boolean = false

  // All EQ presets (loaded from Model)
  @Track private allPresets: ParametricEQ[] = FxActivityDataSource.loadPresets()

  // Get all presets for the View to render
  getAllPresets(): ParametricEQ[] {
    return this.allPresets
  }

  // Switch to AUDIOFX tab
  switchToAudioFxTab(): void {
    this.currentTab = 0
  }

  // Switch to V3 Effects tab
  switchToV3Tab(): void {
    this.currentTab = 1
  }

  // Select an EQ preset and apply it. Also mirror the preset name to
  // AppStorage so the Spec14 音频信息 dialog's SALT PLAYER AUDIOFX V4 row
  // reflects the live selection.
  selectPreset(preset: ParametricEQ): void {
    this.currentEq = preset
    AppStorage.setOrCreate<string>('fxPresetName', preset.name)
    FxActivityDataSource.applyEqPreset(preset)
  }

  // Toggle MAX Audio Acoustics
  toggleMaxAudioAcoustics(enabled: boolean): void {
    this.maxAudioAcoustics = enabled
    FxActivityDataSource.setMaxAudioAcoustics(enabled)
  }

  // Toggle DX8 Reverb. Also mirror the flag to AppStorage so the Spec14
  // 音频信息 dialog's "V3 混响" row reflects the live state.
  toggleDx8Reverb(enabled: boolean): void {
    this.dx8Reverb = enabled
    AppStorage.setOrCreate<boolean>('v3ReverbEnabled', enabled)
    FxActivityDataSource.setDx8Reverb(enabled)
  }

  // Show intro sheet
  openIntroSheet(): void {
    this.showIntroSheet = true
  }

  // Update background height based on area width
  updateBgHeight(width: number): void {
    if (width > 0) {
      this.bgHeight = width * 2 / 3
    }
  }

  // Mark chart as ready
  setChartReady(): void {
    this.chartReady = true
  }

  // Get the band icon for a preset
  getPresetBandIcon(preset: ParametricEQ): Resource {
    return getBandIcon(preset.band)
  }

  // Get formatted preamp text
  getPreampText(): string {
    return `Preamp ${this.currentEq.Preamp.toFixed(1)} dB`
  }

  // Get author text
  getAuthorText(): string {
    return `By ${this.currentEq.author}`
  }

  // ===== Chart Drawing Methods =====

  // Main chart draw method
  drawChart(ctx: CanvasRenderingContext2D): void {
    if (!this.chartReady) {
      return
    }
    const w: number = ctx.width
    const h: number = ctx.height
    if (w <= 0 || h <= 0) {
      return
    }

    const padLeft = FxChartConfig.PAD_LEFT
    const padRight = FxChartConfig.PAD_RIGHT
    const padTop = FxChartConfig.PAD_TOP
    const padBottom = FxChartConfig.PAD_BOTTOM
    const cw: number = w - padLeft - padRight
    const ch: number = h - padTop - padBottom

    const xMin = FxChartConfig.X_MIN
    const xMax = FxChartConfig.X_MAX
    const yMin = FxChartConfig.Y_MIN
    const yMax = FxChartConfig.Y_MAX
    const xRange: number = xMax - xMin
    const yRange: number = yMax - yMin

    const toCanvasX = (logF: number): number => {
      return padLeft + ((logF - xMin) / xRange) * cw
    }
    const toCanvasY = (gain: number): number => {
      return padTop + ((yMax - gain) / yRange) * ch
    }

    // 1. Clear canvas
    ctx.clearRect(0, 0, w, h)

    // 2. Draw grid
    this.drawGrid(ctx, padLeft, padTop, cw, ch, toCanvasX, toCanvasY)

    // 3. Draw 0dB reference line (blue)
    ctx.beginPath()
    ctx.strokeStyle = 'rgba(68, 138, 255, 0.72)'
    ctx.lineWidth = 1
    const y0db: number = toCanvasY(0)
    ctx.moveTo(padLeft, y0db)
    ctx.lineTo(padLeft + cw, y0db)
    ctx.stroke()

    // 4. Draw Preamp reference line (green)
    const preamp: number = this.currentEq.Preamp
    if (preamp >= yMin && preamp <= yMax) {
      ctx.beginPath()
      ctx.strokeStyle = 'rgba(76, 175, 80, 0.8)'
      ctx.lineWidth = 1
      ctx.setLineDash([4, 4])
      const yPreamp: number = toCanvasY(preamp)
      ctx.moveTo(padLeft, yPreamp)
      ctx.lineTo(padLeft + cw, yPreamp)
      ctx.stroke()
      ctx.setLineDash([])
    }

    // 5. Draw EQ curve
    this.drawEqCurve(ctx, padLeft, padTop, cw, ch, toCanvasX, toCanvasY, xMin, xMax)
  }

  // Draw grid and axis labels
  private drawGrid(
    ctx: CanvasRenderingContext2D,
    padLeft: number, padTop: number,
    cw: number, ch: number,
    toCanvasX: (logF: number) => number,
    toCanvasY: (gain: number) => number
  ): void {
    const freqLines = FxChartConfig.FREQ_LINES
    const freqLabels = FxChartConfig.FREQ_LABELS

    ctx.lineWidth = 0.5
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)'
    ctx.font = '9px sans-serif'
    ctx.fillStyle = 'rgba(255, 220, 100, 0.72)'

    for (let i = 0; i < freqLines.length; i++) {
      const logF: number = freqLines[i][1]
      const cx: number = toCanvasX(logF)

      ctx.beginPath()
      ctx.moveTo(cx, padTop)
      ctx.lineTo(cx, padTop + ch)
      ctx.stroke()

      ctx.textAlign = 'center'
      ctx.fillText(freqLabels[i], cx, padTop + ch + 14)
    }

    const gainLines = FxChartConfig.GAIN_LINES
    ctx.font = '9px sans-serif'
    ctx.fillStyle = 'rgba(255, 255, 255, 0.5)'
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.08)'

    for (let i = 0; i < gainLines.length; i++) {
      const g: number = gainLines[i]
      const cy: number = toCanvasY(g)

      if (g !== 0) {
        ctx.beginPath()
        ctx.moveTo(padLeft, cy)
        ctx.lineTo(padLeft + cw, cy)
        ctx.stroke()
      }

      ctx.textAlign = 'right'
      ctx.fillText(`${g}`, padLeft - 4, cy + 3)
    }

    ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)'
    ctx.lineWidth = 0.5
    ctx.beginPath()
    ctx.moveTo(padLeft, padTop)
    ctx.lineTo(padLeft + cw, padTop)
    ctx.lineTo(padLeft + cw, padTop + ch)
    ctx.lineTo(padLeft, padTop + ch)
    ctx.closePath()
    ctx.stroke()
  }

  // Draw EQ frequency response curve
  private drawEqCurve(
    ctx: CanvasRenderingContext2D,
    padLeft: number, padTop: number,
    cw: number, ch: number,
    toCanvasX: (logF: number) => number,
    toCanvasY: (gain: number) => number,
    xMin: number, xMax: number
  ): void {
    const items: EqItem[] = this.currentEq.items
    if (items.length === 0) {
      return
    }

    const sorted: EqItem[] = FxActivityDataSource.sortEqItemsByFrequency(items)

    const points: number[][] = []
    for (let i = 0; i < sorted.length; i++) {
      const logF: number = Math.log10(sorted[i].Fc)
      if (logF < xMin || logF > xMax) {
        continue
      }
      points.push([toCanvasX(logF), toCanvasY(sorted[i].Gain)])
    }

    if (points.length < 2) {
      if (points.length === 1) {
        ctx.beginPath()
        ctx.fillStyle = 'rgba(255, 255, 255, 0.9)'
        ctx.arc(points[0][0], points[0][1], 3, 0, Math.PI * 2)
        ctx.fill()
      }
      return
    }

    // Draw curve fill (semi-transparent area)
    const y0: number = toCanvasY(0)
    ctx.beginPath()
    ctx.moveTo(points[0][0], y0)
    ctx.lineTo(points[0][0], points[0][1])

    for (let i = 0; i < points.length - 1; i++) {
      const x0: number = points[i][0]
      const y_0: number = points[i][1]
      const x1: number = points[i + 1][0]
      const y1: number = points[i + 1][1]
      const cpx: number = (x0 + x1) / 2
      ctx.bezierCurveTo(cpx, y_0, cpx, y1, x1, y1)
    }

    ctx.lineTo(points[points.length - 1][0], y0)
    ctx.closePath()
    ctx.fillStyle = 'rgba(68, 138, 255, 0.15)'
    ctx.fill()

    // Draw curve stroke
    ctx.beginPath()
    ctx.moveTo(points[0][0], points[0][1])
    for (let i = 0; i < points.length - 1; i++) {
      const x0: number = points[i][0]
      const y_0: number = points[i][1]
      const x1: number = points[i + 1][0]
      const y1: number = points[i + 1][1]
      const cpx: number = (x0 + x1) / 2
      ctx.bezierCurveTo(cpx, y_0, cpx, y1, x1, y1)
    }
    ctx.strokeStyle = 'rgba(68, 138, 255, 0.9)'
    ctx.lineWidth = 2
    ctx.stroke()

    // Draw data points
    ctx.fillStyle = '#ffffffff'
    for (let i = 0; i < points.length; i++) {
      ctx.beginPath()
      ctx.arc(points[i][0], points[i][1], 2.5, 0, Math.PI * 2)
      ctx.fill()
    }
  }
}
