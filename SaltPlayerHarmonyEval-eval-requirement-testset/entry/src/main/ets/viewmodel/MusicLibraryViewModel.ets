// MusicLibraryViewModel.ets
// ViewModel layer: provides data and logic for MusicLibraryPage (View).
// Bridges the Model layer (MusicLibraryModel) with the View layer, exposing
// observable state variables and chart interaction methods.

import {
  PieEntryData,
  VelocitySampleData,
  MusicLibraryData
} from '../model/MusicLibraryModel'

@Observed
export class MusicLibraryViewModel {
  // ===== Observable state properties (for UI binding) =====
  // Initialized to the same defaults `createDefaultMusicLibraryData()` returns so
  // the page renders zeros immediately while the async DB load runs. Initial
  // values were '' before — that produced empty Text() and let the @State
  // wrapping miss the first non-empty assignment from loadData.
  @Track public pieEntries: PieEntryData[] = []
  @Track public totalSize: string = '0.00 B'
  @Track public hqCount: string = '0'
  @Track public sqCount: string = '0'
  @Track public hiResCount: string = '0'
  @Track public othersCount: string = '0'
  // Total valid song count derived from per-tier counters; used by the
  // search entry to populate the SearchAllSongsPage placeholder
  // ("在 N 首歌曲中搜索"). Avoids a second DB query.
  @Track public validCount: number = 0

  // ===== Chart interaction state =====
  // Rotation angle in degrees (0 = 3 o'clock, like MPAndroidChart's rawRotationAngle)
  @Track public chartRotationAngle: number = 270 // default 270 = start from 12 o'clock
  // Selected slice index (-1 = none)
  @Track public highlightedIndex: number = -1
  // Flag to trigger chart redraw
  @Track public chartRedrawTrigger: number = 0

  // ===== MPAndroidChart PieDataSet defaults (constants) =====
  // The API 23 runtime hard-crashes when UI reads any field of an @Observed
  // instance that is not @Track'd ("Illegal usage of not @Track'ed property").
  // A historical note here warned that adding @Track to readonly fields
  // silently broke @Track wiring on an older device; the new runtime
  // requires @Track on every UI-read field regardless, so we accept the
  // trade-off and re-test live updates on touch / fling state.
  @Track public readonly SELECTION_SHIFT: number = 8
  @Track public readonly HOLE_RADIUS_PERCENT: number = 50
  @Track public readonly TRANSPARENT_CIRCLE_RADIUS_PERCENT: number = 55
  @Track public readonly TRANSPARENT_CIRCLE_ALPHA: number = 0.41
  @Track public readonly VALUE_LINE_PART1_OFFSET: number = 0.75
  @Track public readonly VALUE_LINE_PART1_LENGTH: number = 0.3
  @Track public readonly VALUE_LINE_PART2_LENGTH: number = 0.4
  @Track public readonly VALUE_LINE_VARIABLE_LENGTH: boolean = true
  @Track public readonly PIE_COLORS: string[] = ['#0470e6', '#BF0470e6', '#800470e6', '#400470e6']
  @Track public readonly FRICTION_COEF: number = 0.96

  // ===== Internal (non-UI) state for touch/fling tracking =====
  // Plain private fields — touch/canvas state never feeds into the build()
  // tree, so @Track on them was unnecessary and risked the same wiring bug
  // as the readonly fields above.
  private touchStartAngle: number = 0
  private velocitySamples: VelocitySampleData[] = []
  private decelerationVelocity: number = 0
  private decelerationTimerId: number = -1
  private lastFrameTime: number = 0
  private chartCenterX: number = 0
  private chartCenterY: number = 0
  private chartRadius: number = 0

  // Theme-aware text/line color for canvas drawing (resolved by View from $r resource)
  @Track public valueLineColor: string = '#1e1715'

  // Canvas reference for drawing (set by View) — not UI-bound.
  private canvasContext: CanvasRenderingContext2D | null = null

  // Callback for requesting chart redraw — set by View, not bound.
  public onRequestRedraw: () => void = () => {}

  // ===== Initialization =====
  // No constructor: rely on field initializers above. The previous constructor
  // called loadData with the empty defaults before @State had wrapped this
  // instance, which is exactly when @Track setters silently dropped writes —
  // every later loadData() then looked like a no-op to the View.

  // Load data from Model
  loadData(data: MusicLibraryData): void {
    this.pieEntries = data.pieEntries
    this.totalSize = data.totalSize
    this.hqCount = data.hqCount
    this.sqCount = data.sqCount
    this.hiResCount = data.hiResCount
    this.othersCount = data.othersCount
    // Derive total valid count from per-tier strings; default to 0 on parse
    // failure so search entry never shows NaN/undefined.
    const hq = parseInt(data.hqCount, 10)
    const sq = parseInt(data.sqCount, 10)
    const hr = parseInt(data.hiResCount, 10)
    const others = parseInt(data.othersCount, 10)
    const total = (isNaN(hq) ? 0 : hq) + (isNaN(sq) ? 0 : sq) +
      (isNaN(hr) ? 0 : hr) + (isNaN(others) ? 0 : others)
    this.validCount = total
  }

  // Set the canvas context for drawing
  setCanvasContext(ctx: CanvasRenderingContext2D): void {
    this.canvasContext = ctx
  }

  // ===== Touch handling (mirrors PieRadarChartTouchListener) =====

  getAngleForPoint(x: number, y: number): number {
    const dx = x - this.chartCenterX
    const dy = y - this.chartCenterY
    let angle = Math.atan2(dy, dx) * 180 / Math.PI
    return ((angle % 360) + 360) % 360
  }

  private addVelocitySample(angle: number): void {
    const now = Date.now()
    this.velocitySamples = this.velocitySamples.filter(s => now - s.time < 1000)
    this.velocitySamples.push({ time: now, angle: angle })
  }

  private calculateVelocity(): number {
    if (this.velocitySamples.length < 2) {
      return 0
    }
    const first = this.velocitySamples[0]
    const last = this.velocitySamples[this.velocitySamples.length - 1]
    const timeDelta = (last.time - first.time) / 1000
    if (timeDelta < 0.001) {
      return 0
    }
    let angleDelta = last.angle - first.angle
    let clockwise = true
    for (let i = this.velocitySamples.length - 1; i > 0; i--) {
      const diff = this.velocitySamples[i].angle - this.velocitySamples[i - 1].angle
      if (Math.abs(diff) > 0.001) {
        clockwise = diff > 0
        if (Math.abs(diff) > 270) {
          clockwise = !clockwise
        }
        break
      }
    }
    const velocity = Math.abs(angleDelta / timeDelta)
    return clockwise ? velocity : -velocity
  }

  // Handle pan gesture start
  handlePanStart(localX: number, localY: number): void {
    this.stopDeceleration()
    this.touchStartAngle = this.getAngleForPoint(localX, localY) - this.chartRotationAngle
    this.velocitySamples = []
    this.addVelocitySample(this.chartRotationAngle)
  }

  // Handle pan gesture update
  handlePanUpdate(localX: number, localY: number): void {
    this.chartRotationAngle = this.getAngleForPoint(localX, localY) - this.touchStartAngle
    this.addVelocitySample(this.chartRotationAngle)
    this.requestRedraw()
  }

  // Handle pan gesture end
  handlePanEnd(): void {
    const velocity = this.calculateVelocity()
    if (Math.abs(velocity) > 5) {
      this.startDeceleration(velocity)
    }
  }

  // Handle tap on chart for slice highlight
  handleTap(x: number, y: number): void {
    const dx = x - this.chartCenterX
    const dy = y - this.chartCenterY
    const distance = Math.sqrt(dx * dx + dy * dy)
    const baseRadius = this.chartRadius - this.SELECTION_SHIFT
    const holeRadius = baseRadius * this.HOLE_RADIUS_PERCENT / 100

    if (distance < holeRadius || distance > this.chartRadius) {
      if (this.highlightedIndex !== -1) {
        this.highlightedIndex = -1
        this.requestRedraw()
      }
      return
    }

    let tapAngle = this.getAngleForPoint(x, y)
    tapAngle = ((tapAngle - this.chartRotationAngle) % 360 + 360) % 360

    let total = 0
    for (let i = 0; i < this.pieEntries.length; i++) {
      total += this.pieEntries[i].value
    }

    let sliceStart = 0
    for (let i = 0; i < this.pieEntries.length; i++) {
      const sliceSweep = (this.pieEntries[i].value / total) * 360
      if (tapAngle >= sliceStart && tapAngle < sliceStart + sliceSweep) {
        this.highlightedIndex = (this.highlightedIndex === i) ? -1 : i
        this.requestRedraw()
        return
      }
      sliceStart += sliceSweep
    }
  }

  // ===== Fling deceleration =====

  private startDeceleration(velocity: number): void {
    this.stopDeceleration()
    this.decelerationVelocity = velocity
    this.lastFrameTime = Date.now()

    const animate = (): void => {
      const now = Date.now()
      const dt = (now - this.lastFrameTime) / 1000
      this.lastFrameTime = now
      this.decelerationVelocity *= this.FRICTION_COEF
      this.chartRotationAngle += this.decelerationVelocity * dt

      if (Math.abs(this.decelerationVelocity) < 0.5) {
        this.stopDeceleration()
        return
      }
      this.requestRedraw()
      this.decelerationTimerId = setTimeout(animate, 16)
    }
    this.decelerationTimerId = setTimeout(animate, 16)
  }

  stopDeceleration(): void {
    if (this.decelerationTimerId !== -1) {
      clearTimeout(this.decelerationTimerId)
      this.decelerationTimerId = -1
    }
    this.decelerationVelocity = 0
  }

  // ===== Drawing =====

  // Request the View to redraw the chart
  private requestRedraw(): void {
    this.chartRedrawTrigger++
    this.onRequestRedraw()
  }

  // Draw a single donut arc segment
  private drawSlice(ctx: CanvasRenderingContext2D, cx: number, cy: number,
    outerR: number, innerR: number, startAngleRad: number, sweepAngleRad: number, color: string): void {
    ctx.beginPath()
    ctx.arc(cx, cy, outerR, startAngleRad, startAngleRad + sweepAngleRad, false)
    ctx.arc(cx, cy, innerR, startAngleRad + sweepAngleRad, startAngleRad, true)
    ctx.closePath()
    ctx.fillStyle = color
    ctx.fill()
  }

  // Main draw function - follows MPAndroidChart's exact drawing pipeline
  drawPieChart(ctx: CanvasRenderingContext2D): void {
    const width = ctx.width
    const height = ctx.height
    const centerX = width / 2
    const centerY = height / 2
    this.chartCenterX = centerX
    this.chartCenterY = centerY

    const drawAreaRadius = (Math.min(width, height) - 64) / 2
    const fullRadius = drawAreaRadius * 0.75
    this.chartRadius = fullRadius
    const baseRadius = fullRadius - this.SELECTION_SHIFT
    const holeRadius = baseRadius * this.HOLE_RADIUS_PERCENT / 100
    const transparentCircleRadius = baseRadius * this.TRANSPARENT_CIRCLE_RADIUS_PERCENT / 100

    ctx.clearRect(0, 0, width, height)

    let total = 0
    for (let i = 0; i < this.pieEntries.length; i++) {
      total += this.pieEntries[i].value
    }
    if (total === 0) {
      return
    }

    const rotationRad = this.chartRotationAngle * Math.PI / 180

    // Step 1: drawData - draw non-highlighted slices
    let startAngle = rotationRad
    for (let i = 0; i < this.pieEntries.length; i++) {
      const sliceAngle = (this.pieEntries[i].value / total) * 2 * Math.PI
      if (i !== this.highlightedIndex) {
        this.drawSlice(ctx, centerX, centerY, baseRadius, holeRadius,
          startAngle, sliceAngle, this.PIE_COLORS[i % this.PIE_COLORS.length])
      }
      startAngle += sliceAngle
    }

    // Step 2: drawHighlighted - draw selected slice at expanded radius
    if (this.highlightedIndex >= 0 && this.highlightedIndex < this.pieEntries.length) {
      let hlStartAngle = rotationRad
      for (let i = 0; i < this.highlightedIndex; i++) {
        hlStartAngle += (this.pieEntries[i].value / total) * 2 * Math.PI
      }
      const hlSliceAngle = (this.pieEntries[this.highlightedIndex].value / total) * 2 * Math.PI
      this.drawSlice(ctx, centerX, centerY, fullRadius, holeRadius,
        hlStartAngle, hlSliceAngle, this.PIE_COLORS[this.highlightedIndex % this.PIE_COLORS.length])
    }

    // Step 3: drawExtras - hole + transparent circle ring
    if (transparentCircleRadius > holeRadius) {
      ctx.beginPath()
      ctx.arc(centerX, centerY, transparentCircleRadius, 0, 2 * Math.PI, false)
      ctx.arc(centerX, centerY, holeRadius, 0, 2 * Math.PI, true)
      ctx.closePath()
      ctx.fillStyle = `rgba(255, 255, 255, ${this.TRANSPARENT_CIRCLE_ALPHA})`
      ctx.fill()
    }

    // Step 4: drawValues - label lines + percentage text + entry labels
    startAngle = rotationRad
    for (let i = 0; i < this.pieEntries.length; i++) {
      const entry = this.pieEntries[i]
      const sliceAngle = (this.pieEntries[i].value / total) * 2 * Math.PI
      const midAngleRad = startAngle + sliceAngle / 2
      const donutWidth = baseRadius - holeRadius
      const line1Radius = holeRadius + donutWidth * this.VALUE_LINE_PART1_OFFSET
      const pt0x = centerX + line1Radius * Math.cos(midAngleRad)
      const pt0y = centerY + line1Radius * Math.sin(midAngleRad)
      const pt1Radius = baseRadius * (1 + this.VALUE_LINE_PART1_LENGTH)
      const pt1x = centerX + pt1Radius * Math.cos(midAngleRad)
      const pt1y = centerY + pt1Radius * Math.sin(midAngleRad)
      const isRightSide = Math.cos(midAngleRad) > 0.01
      let horizontalLength = baseRadius * this.VALUE_LINE_PART2_LENGTH
      if (this.VALUE_LINE_VARIABLE_LENGTH) {
        horizontalLength *= Math.abs(Math.sin(midAngleRad))
      }
      const pt2x = isRightSide ? pt1x + horizontalLength : pt1x - horizontalLength
      const pt2y = pt1y

      ctx.beginPath()
      ctx.moveTo(pt0x, pt0y)
      ctx.lineTo(pt1x, pt1y)
      ctx.lineTo(pt2x, pt2y)
      ctx.strokeStyle = this.valueLineColor
      ctx.lineWidth = 1
      ctx.stroke()

      const textOffset = 5
      const textX = isRightSide ? pt2x + textOffset : pt2x - textOffset
      ctx.textAlign = isRightSide ? 'left' : 'right'

      const percentage = ((entry.value / total) * 100).toFixed(1) + ' %'
      ctx.font = '10vp sans-serif'
      ctx.fillStyle = this.valueLineColor
      ctx.textBaseline = 'bottom'
      ctx.fillText(percentage, textX, pt2y - 1)

      ctx.textBaseline = 'top'
      ctx.fillText(entry.label, textX, pt2y + 1)

      startAngle += sliceAngle
    }
  }

  // Check if pie chart has data
  hasPieData(): boolean {
    return this.pieEntries.length > 0
  }
}
