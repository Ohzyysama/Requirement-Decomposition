import { LyricsLine } from '../model/LyricsModel'
import { KaraokeRenderDecision } from '../model/KaraokeRenderDecision'
import { RectShape, PathShape } from '@kit.ArkUI'

@Component
export struct LyricsLineComponent {
  // Spec13: lyrics-view blur. Two ArkUI primitives are involved.
  //
  // .blur() is unusable on a Text node: the gaussian works on the analytical
  // glyph and at any radius strong enough to be perceived as blur the thin
  // strokes drop below the visibility threshold — the text is gone. We tried
  // every ladder from Android-port 1.5/3.0/4.5/6.0 down to uniform 1.0vp,
  // including .renderGroup(true) which on this ArkUI build does not save the
  // text (uniform 1.5vp + renderGroup still erased every non-current row).
  // BLUR_VP stays at 0 to keep .blur() effectively a no-op.
  //
  // The frosted look the user asked for is delivered by .textShadow() — a
  // stack of gaussian-blurred copies of the glyph painted *behind* the crisp
  // text. The text on top stays readable; the stacked shadows underneath
  // composite into a thick frosted body matching the on-device reference
  // (left half of 20260518173419_1_165.jpg), where non-current rows show a
  // wide soft halo with strokes bleeding into each other.
  //
  // The stack uses three radii — wide+faint, medium, tight+dense — because
  // a single big-radius shadow draws a faint ring, while three stacked at
  // increasing density build up a smooth gaussian-like falloff. See
  // blurTextShadow() for the assembled descriptor.
  private static readonly BLUR_VP: number = 0
  private static readonly TEXT_SHADOW_OUTER_VP: number = 14
  private static readonly TEXT_SHADOW_MID_VP: number = 9
  private static readonly TEXT_SHADOW_INNER_VP: number = 5
  // Dim baked into the shadow alphas instead of into the component .opacity
  // multiplier — the previous high alphas (0.8/0.95/1.0) read as visibly
  // darker than the 0.3-alpha crisp text in the no-blur path, even with
  // Text.opacity = 0.3, suggesting ArkUI does not fully multiply .opacity
  // through textShadow on this build. With these alphas, the src-over
  // composite at a stroke peak = 1 − (1−0.08)(1−0.12)(1−0.15) ≈ 0.31,
  // which lands directly in the no-blur 0.3 brightness band regardless of
  // how .opacity is propagated.
  private static readonly TEXT_SHADOW_OUTER_ALPHA: number = 0.08
  private static readonly TEXT_SHADOW_MID_ALPHA: number = 0.12
  private static readonly TEXT_SHADOW_INNER_ALPHA: number = 0.15

  @ObjectLink line: LyricsLine
  @Prop @Watch('onIsCurrentChanged') isCurrent: boolean = false
  // Spec17: promoted to @Prop @Watch so external toggles trigger the
  // 300ms reveal/hide tween below. Defaults to false so a freshly-spawned
  // component with no override stays collapsed.
  @Prop @Watch('onShowTranslationChanged') showTranslation: boolean = false
  @Prop textSize: number = 20
  @Prop fontWeightValue: number = 600
  @Prop textAlignCenter: boolean = false
  @Prop themeColor: string = '#ff050f19'
  @Prop karaokeStrategyIndex: number = 0
  @Prop hasAnyKaraokeInDoc: boolean = false
  @Prop @Watch('onCurrentTimeMsChanged') currentTimeMs: number = 0
  // Spec13: lyrics-view blur inputs.
  // blurEnabled: global toggle from settings (AppStorage 'lyricsBlur').
  // lineDistance: |index - currentLineIndex|, or 0 when no current line.
  // suppressBlur: true while user is dragging/scrolling the lyrics list.
  @Prop @Watch('onBlurEnabledChanged') blurEnabled: boolean = false
  @Prop lineDistance: number = 0
  @Prop @Watch('onSuppressBlurChanged') suppressBlur: boolean = false
  @Prop effect3D: boolean = false
  onLineClick: () => void = () => {}

  @State private mainOpacity: number = 0.3
  @State private subOpacity: number = 0.2
  @State private scaleValue: number = 0.95

  // Spec17: translation row reveal/hide animation state. translationVisible
  // drives the height (undefined for measured natural height, 0 for collapsed),
  // translationOpacity drives the fade in/out. Both are tweened together by a
  // single animateTo in onShowTranslationChanged. The actual rendered opacity
  // is subOpacity * translationOpacity (dim level × show factor).
  @State private translationVisible: boolean = false
  @State private translationOpacity: number = 0

  // Karaoke wipe layout cache. The background Text's controller exposes the
  // rendered line geometry via getLayoutManager(); we cache it as flat number
  // arrays so the per-tick clip-path build is allocation-light. Bumping
  // karaokeLayoutVersion re-triggers the clipShape rebuild after a re-measure.
  @State private karaokeLayoutVersion: number = 0
  private bgTextController: TextController = new TextController()
  private karaokeLineRanges: number[] = []  // flat [startIdx, endIdx] pairs
  private karaokeLineRects: number[] = []   // flat [left, top, width, height] quads, vp units

  // currentTimeMs only ticks every ~200ms (player advanceProgress cadence), so
  // driving the wipe directly off it produces visible per-character snapping.
  // smoothedTimeMs is a 60fps interpolation toward currentTimeMs that the
  // karaoke render reads instead, giving a continuously-sliding wipe.
  @State private smoothedTimeMs: number = 0
  private smoothInterpStartMs: number = 0
  private smoothInterpStartTime: number = 0
  private smoothInterpTargetMs: number = 0
  private smoothInterpHandle: number = -1

  // Spec13: when the lyrics-view blur toggle is on, non-current lines get a
  // uniform blur applied via .blur(). ArkUI's blur fades thin text strokes
  // hard, so the legacy 0.3 alpha (designed for sharp dim-only text) pushes
  // blurred lines below the perceptual threshold — they vanish even though
  // the blur radius is small. Raise the non-current alpha when blur is
  // enabled so the blur itself, not the alpha, does the de-emphasis. The
  // current line and the no-blur path keep their original values.
  private targetMainOpacity(): number {
    if (this.isCurrent) return 1.0
    // No-blur path: crisp text dimmed via .opacity(0.3). Blur path: the
    // dim is already baked into the shadow alphas (cumulative ~0.31 — see
    // TEXT_SHADOW_*_ALPHA), so .opacity stays at 1.0 to avoid a double-
    // dimming that would push the row below the no-blur brightness band.
    // When the user is manually scrolling (suppressBlur), non-current rows
    // should look "not yet played" rather than "already played", so we fall
    // back to the no-blur opacity values.
    return (this.blurEnabled && !this.suppressBlur) ? 1.0 : 0.3
  }

  private targetSubOpacity(): number {
    if (this.isCurrent) return 0.7
    return (this.blurEnabled && !this.suppressBlur) ? 1.0 : 0.2
  }

  aboutToAppear(): void {
    this.mainOpacity = this.targetMainOpacity()
    this.subOpacity = this.targetSubOpacity()
    this.scaleValue = this.isCurrent ? 1.0 : 0.95
    this.smoothedTimeMs = this.currentTimeMs
    // Spec17: initialize translation visibility without animation so newly
    // spawned items don't tween from 0 on first paint.
    const shouldShow = this.showTranslation && this.line.subText.length > 0
    this.translationVisible = shouldShow
    this.translationOpacity = shouldShow ? 1 : 0
  }

  aboutToDisappear(): void {
    this.cancelSmoothInterp()
  }

  onIsCurrentChanged(): void {
    animateTo({ duration: 600, curve: Curve.FastOutSlowIn }, () => {
      this.mainOpacity = this.targetMainOpacity()
      this.subOpacity = this.targetSubOpacity()
      this.scaleValue = this.isCurrent ? 1.0 : 0.95
    })
    if (!this.isCurrent) {
      // No need to keep interpolating for a line that's no longer being sung.
      this.cancelSmoothInterp()
      this.smoothedTimeMs = this.currentTimeMs
    }
  }

  // Spec13: when the blur toggle flips mid-display (user opens settings and
  // toggles 歌词视图模糊 without leaving the page), animate the non-current
  // lines' alpha to the new target so the visible-after-blur state takes
  // effect immediately. The current line is unaffected (its alpha is 1.0
  // regardless of blur).
  onBlurEnabledChanged(): void {
    if (this.isCurrent) return
    animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
      this.mainOpacity = this.targetMainOpacity()
      this.subOpacity = this.targetSubOpacity()
    })
  }

  onSuppressBlurChanged(): void {
    if (this.isCurrent) return
    // Direct assignment — no animation. textShadow / fontColor react to
    // suppressBlur instantly, so opacity must keep in sync to avoid a
    // transient fully-opaque-solid-text flash before the tween finishes.
    this.mainOpacity = this.targetMainOpacity()
    this.subOpacity = this.targetSubOpacity()
  }

  // Spec17: translation row reveal/hide tween. 300ms FastOutSlowIn matches the
  // immersion-mode bottom-bar collapse already used elsewhere in PlayerPage,
  // so the toggle reads as part of the same motion language. Driven by the
  // @Prop @Watch chain — flipping the parent's showTranslation prop reaches
  // here on the next frame and animates both height (via translationVisible)
  // and opacity together.
  onShowTranslationChanged(): void {
    const shouldShow = this.showTranslation && this.line.subText.length > 0
    animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
      this.translationVisible = shouldShow
      this.translationOpacity = shouldShow ? 1 : 0
    })
  }

  // currentTimeMs arrives in chunky 200ms steps. We pull the path target along
  // smoothly using a frame-paced interval so the wipe slides continuously
  // between ticks. Big jumps (seek, song change) snap directly — interpolating
  // a 30-second seek would look like a slow scan.
  onCurrentTimeMsChanged(): void {
    const target = this.currentTimeMs
    if (!this.isCurrent) {
      this.smoothedTimeMs = target
      return
    }
    const diff = Math.abs(target - this.smoothedTimeMs)
    if (diff > 500 || diff < 1) {
      this.cancelSmoothInterp()
      this.smoothedTimeMs = target
      return
    }
    this.smoothInterpStartMs = this.smoothedTimeMs
    this.smoothInterpStartTime = Date.now()
    this.smoothInterpTargetMs = target
    if (this.smoothInterpHandle !== -1) {
      return  // existing tick will pick up the new target
    }
    this.smoothInterpHandle = setInterval(() => this.tickSmoothInterp(), 16)
  }

  private tickSmoothInterp(): void {
    const elapsed = Date.now() - this.smoothInterpStartTime
    const duration = 200
    if (elapsed >= duration) {
      this.smoothedTimeMs = this.smoothInterpTargetMs
      this.cancelSmoothInterp()
      return
    }
    const t = elapsed / duration
    this.smoothedTimeMs =
      this.smoothInterpStartMs + (this.smoothInterpTargetMs - this.smoothInterpStartMs) * t
  }

  private cancelSmoothInterp(): void {
    if (this.smoothInterpHandle !== -1) {
      clearInterval(this.smoothInterpHandle)
      this.smoothInterpHandle = -1
    }
  }

  // Compute [0..1] progress through the line based on the smoothed playhead.
  private computeLineProgress(): number {
    const span = Math.max(1, this.line.endTime - this.line.startTime)
    const elapsed = this.smoothedTimeMs - this.line.startTime
    if (elapsed <= 0) {
      return 0
    }
    if (elapsed >= span) {
      return 1
    }
    return elapsed / span
  }

  // Compute [0..1] cursor progress for a line with per-cell timestamps.
  // Uses the cell boundaries to determine precise character-level position.
  private computeCellProgress(): number {
    const cells = this.line.cells
    if (cells.length === 0) {
      return this.computeLineProgress()
    }
    const t = this.smoothedTimeMs
    if (t <= cells[0].startTime) {
      return 0
    }
    const lastCell = cells[cells.length - 1]
    if (t >= lastCell.endTime) {
      return 1
    }

    // Build cumulative character lengths for mapping cell time → text position
    let totalChars = 0
    for (let i = 0; i < cells.length; i++) {
      totalChars += Array.from(cells[i].text).length
    }
    if (totalChars === 0) {
      return 0
    }

    let charsBefore = 0
    for (let i = 0; i < cells.length; i++) {
      const cell = cells[i]
      const cellChars = Array.from(cell.text).length
      if (t < cell.startTime) {
        return charsBefore / totalChars
      }
      if (t >= cell.startTime && t < cell.endTime) {
        const cellDuration = Math.max(1, cell.endTime - cell.startTime)
        const cellProgress = (t - cell.startTime) / cellDuration
        return (charsBefore + cellProgress * cellChars) / totalChars
      }
      charsBefore += cellChars
    }
    return 1
  }

  // Extract RGB from themeColor and return a version with the given alpha (0-255).
  private colorWithAlpha(alpha: number): string {
    const hex = this.themeColor.startsWith('#') ? this.themeColor.substring(1) : this.themeColor
    const a = Math.round(alpha).toString(16).padStart(2, '0')
    if (hex.length === 8) {
      return '#' + a + hex.substring(2)
    }
    return '#' + a + hex
  }

  private computeKaraokePosition(): number {
    const hasCells = this.line.cells.length > 0
    const progress = hasCells ? this.computeCellProgress() : this.computeLineProgress()
    const totalChars = Array.from(this.line.mainText).length
    return Math.max(0, Math.min(totalChars, progress * totalChars))
  }

  // Fraction [0..1] of the current line that should be rendered in the sung
  // (dark) color. Used as a fallback before line-metrics are available, when
  // we still clip horizontally with a simple RectShape.
  private computeKaraokeWipeFraction(): number {
    const totalChars = Array.from(this.line.mainText).length
    if (totalChars === 0) {
      return 0
    }
    return Math.max(0, Math.min(1, this.computeKaraokePosition() / totalChars))
  }

  // Pull line-by-line layout geometry from the background Text controller and
  // cache it for use by buildKaraokeClipCommands(). LineMetrics values come
  // through the Text controller in the same coordinate space the component
  // is laid out in — vp — so we feed them straight into PathShape commands
  // without unit conversion. Vertical position is computed as a cumulative
  // sum of preceding line heights instead of trusting LineMetrics.topHeight,
  // whose semantics ("Height from the top to the current line") is ambiguous
  // about whether the current line is included.
  private refreshKaraokeLayout(): void {
    try {
      const mgr = this.bgTextController.getLayoutManager()
      if (!mgr) {
        return
      }
      const count = mgr.getLineCount()
      const ranges: number[] = []
      const rects: number[] = []
      let yCursor = 0
      for (let i = 0; i < count; i++) {
        const m = mgr.getLineMetrics(i)
        ranges.push(m.startIndex, m.endIndex)
        rects.push(m.left, yCursor, m.width, m.height)
        yCursor += m.height
      }
      this.karaokeLineRanges = ranges
      this.karaokeLineRects = rects
      this.karaokeLayoutVersion += 1
    } catch (_e) {
      // Layout not yet ready on this frame; skip — onAreaChange will fire
      // again after the next measure pass.
    }
  }

  // Convert the code-point–based karaoke playhead position into a UTF-16
  // code-unit index so it can be compared against LineMetrics start/endIndex
  // values, which are also code-unit indices. charOffset lets callers shift
  // the playhead by N code-points; layered render uses this to draw clip
  // paths that lead/trail the true playhead by ±0.5 char to fake a soft edge.
  private karaokePlayheadCodeUnit(charOffset: number): number {
    const text = this.line.mainText
    const codeUnits = text.length
    const codePoints = Array.from(text).length
    if (codePoints === 0) {
      return 0
    }
    const ratio = codeUnits / codePoints
    return (this.computeKaraokePosition() + charOffset) * ratio
  }

  // Build a multi-rectangle SVG path that covers, in reading order:
  //   • every visual line whose characters are fully behind (playhead+charOffset), and
  //   • the leading slice of the visual line that boundary is currently in.
  // The charOffset parameter is what makes the layered soft-edge work: each
  // dark layer feeds in a slightly different offset, so the clip boundary is
  // shifted ±0.5 char and the partially-overlapping layers composite into a
  // smooth dark→light gradient at the playhead instead of a hard cut.
  private buildKaraokeClipCommands(charOffset: number): string {
    const ranges = this.karaokeLineRanges
    const rects = this.karaokeLineRects
    if (ranges.length === 0 || rects.length === 0) {
      return ''
    }
    const charPos = this.karaokePlayheadCodeUnit(charOffset)
    if (charPos <= 0) {
      return 'M0 0 Z'
    }

    let cmd = ''
    const lineCount = ranges.length / 2
    for (let i = 0; i < lineCount; i++) {
      const startIdx = ranges[i * 2]
      const endIdx = ranges[i * 2 + 1]
      const left = rects[i * 4]
      const top = rects[i * 4 + 1]
      const width = rects[i * 4 + 2]
      const height = rects[i * 4 + 3]

      if (charPos >= endIdx) {
        // Visual line fully behind playhead — paint the entire row dark.
        const right = left + width
        const bottom = top + height
        cmd += `M${left} ${top} L${right} ${top} L${right} ${bottom} L${left} ${bottom} Z `
      } else if (charPos > startIdx) {
        // Visual line currently being sung — clip up to the per-character
        // fraction inside this row, which yields the intra-character wipe.
        const charsInLine = Math.max(1, endIdx - startIdx)
        const frac = (charPos - startIdx) / charsInLine
        const xEnd = left + width * frac
        const bottom = top + height
        cmd += `M${left} ${top} L${xEnd} ${top} L${xEnd} ${bottom} L${left} ${bottom} Z`
        break
      } else {
        // Reached a visual line the playhead has not entered — nothing to add
        // here, and by reading-order monotonicity, nothing for later rows either.
        break
      }
    }
    return cmd
  }

  // One dark Text overlay for the karaoke wipe. layerOpacity sets how strong
  // this layer composites on top of whatever's already drawn; charOffset shifts
  // the clip boundary in code-points relative to the true playhead. The hard-
  // edge layer uses charOffset = -0.5 so it stops half a character before the
  // playhead, leaving room for the gradient strip to fade in seamlessly.
  @Builder
  private KaraokeDarkLayer(layerOpacity: number, charOffset: number) {
    Text(this.line.mainText)
      .fontSize(this.textSize)
      .fontWeight(this.fontWeightValue)
      .fontColor(this.colorWithAlpha(255))
      .textAlign(this.textAlignCenter ? TextAlign.Center : TextAlign.Start)
      .width('100%')
      .wordBreak(WordBreak.BREAK_WORD)
      .opacity(layerOpacity)
      // Read karaokeLayoutVersion here so ArkUI re-evaluates this selector
      // (and rebuilds the path commands) every time refreshKaraokeLayout
      // fires after onAreaChange. smoothedTimeMs is implicitly read through
      // buildKaraokeClipCommands → computeKaraokePosition.
      .clipShape((this.karaokeLayoutVersion >= 0 && this.karaokeLineRanges.length > 0)
        ? new PathShape({ commands: this.buildKaraokeClipCommands(charOffset) })
        : new RectShape({
            width: `${Math.max(0, Math.min(1,
              this.computeKaraokeWipeFraction() +
                charOffset / Math.max(1, Array.from(this.line.mainText).length))) * 100}%`,
            height: '100%'
          }))
  }

  // Spec13: effective blur radius for this line. BLUR_VP is 0 in this build
  // (see comment), so this is a no-op hook kept in place for the future when
  // ArkUI can render text-under-blur usably.
  private effectiveBlurRadius(): number {
    if (!this.blurEnabled) return 0
    if (this.suppressBlur) return 0
    if (this.isCurrent) return 0
    return LyricsLineComponent.BLUR_VP
  }

  // Spec13: when the blur toggle is on, non-current lines paint nothing
  // for their text fill — only the textShadow stack renders. That removes
  // the sharp central glyph the user pointed out as the difference between
  // the on-device reference (defocused blobs) and the previous build (sharp
  // text with halo). The translucent fill returns to the row's normal color
  // whenever the toggle is off, the row is the current line, or the user
  // is actively scrolling.
  private effectiveFontColor(): ResourceColor {
    if (this.blurEnabled && !this.suppressBlur && !this.isCurrent) {
      return '#00000000'
    }
    return this.themeColor
  }

  // Spec13: textShadow descriptor for the frosted body applied to every
  // non-current line while the blur toggle is on. Active path returns three
  // stacked gaussian copies (wide+faint, medium, tight+dense). With the
  // fill transparent (see effectiveFontColor), the src-over composition of
  // these three IS the visible glyph — a pure gaussian smear with no sharp
  // core. Inactive path returns a single transparent zero-radius shadow so
  // the current line / disabled / scrolling states paint nothing (ArkUI's
  // textShadow attribute does not accept undefined).
  private blurTextShadow(): ShadowOptions[] {
    const active = this.blurEnabled && !this.suppressBlur && !this.isCurrent
    if (!active) {
      return [{ radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 }]
    }
    const outerAlpha = Math.round(LyricsLineComponent.TEXT_SHADOW_OUTER_ALPHA * 255)
    const midAlpha = Math.round(LyricsLineComponent.TEXT_SHADOW_MID_ALPHA * 255)
    const innerAlpha = Math.round(LyricsLineComponent.TEXT_SHADOW_INNER_ALPHA * 255)
    return [
      {
        radius: LyricsLineComponent.TEXT_SHADOW_OUTER_VP,
        color: this.colorWithAlpha(outerAlpha),
        offsetX: 0,
        offsetY: 0
      },
      {
        radius: LyricsLineComponent.TEXT_SHADOW_MID_VP,
        color: this.colorWithAlpha(midAlpha),
        offsetX: 0,
        offsetY: 0
      },
      {
        radius: LyricsLineComponent.TEXT_SHADOW_INNER_VP,
        color: this.colorWithAlpha(innerAlpha),
        offsetX: 0,
        offsetY: 0
      }
    ]
  }

  build() {
    Column() {
      if (KaraokeRenderDecision.shouldRenderPerWord(
        this.karaokeStrategyIndex, this.line, this.hasAnyKaraokeInDoc)) {
        // Karaoke per-word render: stack the line twice and clip the dark
        // (sung) layer horizontally to the playback fraction. Because both
        // layers lay out identically, the clip boundary slides smoothly across
        // characters — the character under the playhead is part-dark/part-light.
        if (this.isCurrent) {
          Stack({ alignContent: this.textAlignCenter ? Alignment.Top : Alignment.TopStart }) {
            // Background: full line in unsung (light) color — owns the
            // controller so we can read per-line layout for the clip path.
            Text(this.line.mainText, { controller: this.bgTextController })
              .fontSize(this.textSize)
              .fontWeight(this.fontWeightValue)
              .fontColor(this.colorWithAlpha(77))
              .textAlign(this.textAlignCenter ? TextAlign.Center : TextAlign.Start)
              .width('100%')
              .wordBreak(WordBreak.BREAK_WORD)
              .onAreaChange(() => this.refreshKaraokeLayout())

            // 16 stacked dark Text layers, drawn back-to-front from widest +
            // lightest (offset +0.1 char, opacity 1/16) to narrowest + fully
            // opaque (offset −0.1 char, opacity 1.0). Opacities follow
            // a_i = 1/(N − i + 1), which makes the cumulative src-over coverage
            // strictly linear in the number of layers covering a given x.
            // The offset range is 0.2 char wide so the transition band stays
            // tight (≈5vp on a 24vp char), and with 16 layers each step is
            // ~0.3vp ≈ 1px on a 3x display — well below the perceptual
            // threshold for Mach banding.
            // Each layer uses its own reading-order PathShape clip, so the
            // wipe respects line wrapping — no other visual rows are touched.
            this.KaraokeDarkLayer(0.0625, 0.100)
            this.KaraokeDarkLayer(0.0667, 0.087)
            this.KaraokeDarkLayer(0.0714, 0.073)
            this.KaraokeDarkLayer(0.0769, 0.060)
            this.KaraokeDarkLayer(0.0833, 0.047)
            this.KaraokeDarkLayer(0.0909, 0.033)
            this.KaraokeDarkLayer(0.1000, 0.020)
            this.KaraokeDarkLayer(0.1111, 0.007)
            this.KaraokeDarkLayer(0.1250, -0.007)
            this.KaraokeDarkLayer(0.1429, -0.020)
            this.KaraokeDarkLayer(0.1667, -0.033)
            this.KaraokeDarkLayer(0.2000, -0.047)
            this.KaraokeDarkLayer(0.2500, -0.060)
            this.KaraokeDarkLayer(0.3333, -0.073)
            this.KaraokeDarkLayer(0.5000, -0.087)
            this.KaraokeDarkLayer(1.0000, -0.100)
          }
          .width('100%')
          // Karaoke branch: the sung/unsung split already encodes dimming.
          // Multiplying by mainOpacity here would compound during the
          // 0.3→1.0 transition and cause a visible dim-flash on the new current line.
          .opacity(1.0)
        } else {
          // Non-current lines: when blur is off, plain dim text; when blur
          // is on, transparent fill + textShadow stack — see blurTextShadow()
          // and effectiveFontColor().
          Text(this.line.mainText)
            .fontSize(this.textSize)
            .fontWeight(this.fontWeightValue)
            .fontColor(this.effectiveFontColor())
            .textAlign(this.textAlignCenter ? TextAlign.Center : TextAlign.Start)
            .width('100%')
            .wordBreak(WordBreak.BREAK_WORD)
            .opacity(this.mainOpacity)
            .textShadow(this.blurTextShadow())
        }
      } else {
        // Whole-line render (legacy path)
        Text(this.line.mainText)
          .fontSize(this.textSize)
          .fontWeight(this.fontWeightValue)
          .fontColor(this.effectiveFontColor())
          .textAlign(this.textAlignCenter ? TextAlign.Center : TextAlign.Start)
          .width('100%')
          .wordBreak(WordBreak.BREAK_WORD)
          .opacity(this.mainOpacity)
          .textShadow(this.blurTextShadow())
      }

      // Translation text — always whole-line. Spec17: rendered inside a
      // Column wrapper whose height collapses to 0 and opacity fades to 0
      // when the translation toggle is off, producing a 300ms reveal/hide
      // animation driven by onShowTranslationChanged. The `if` guard stays
      // on `subText.length > 0` so lines without translation never render
      // a placeholder row. The outer wrapper uses `clip(true)` so the height
      // collapse hides the inner Text instead of overflowing.
      if (this.line.subText.length > 0) {
        Column() {
          Text(this.line.subText)
            .fontSize(this.textSize * 0.8)
            .fontWeight(this.fontWeightValue)
            .fontColor(this.effectiveFontColor())
            .textAlign(this.textAlignCenter ? TextAlign.Center : TextAlign.Start)
            .width('100%')
            .margin({ top: this.textSize * 0.25 })
            .wordBreak(WordBreak.BREAK_WORD)
            .opacity(this.subOpacity * this.translationOpacity)
            .textShadow(this.blurTextShadow())
        }
        .width('100%')
        .clip(true)
        .height(this.translationVisible ? undefined : 0)
        .animation({ duration: 300, curve: Curve.FastOutSlowIn })
      }
    }
    .width('100%')
    .padding({
      top: this.textSize * 0.45,
      bottom: this.textSize * 0.45
    })
    .alignItems(this.textAlignCenter ? HorizontalAlign.Center : HorizontalAlign.Start)
    .scale({
      x: this.scaleValue,
      y: this.scaleValue,
      centerX: this.textAlignCenter ? '50%' : '0%',
      centerY: '50%'
    })
    // .blur() is a no-op in this build (BLUR_VP=0). The frosted look is
    // delivered by .textShadow() on each Text node — see blurTextShadow().
    .blur(this.effectiveBlurRadius())
    .onClick(() => {
      this.onLineClick()
    })
  }
}

// 卡拉OK逐字：按字时间戳渲染单行歌词的逐字着色。
