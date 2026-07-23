// FloatingStatusBarLyricsWindow.ets
// spec25 — UI content of the system-level floating window. Reads every
// rendered parameter from AppStorage so changes in the Settings page (a
// different ArkTS window) propagate live with no extra IPC. Owns:
//   - main lyric Text + optional sub-line Text
//   - marquee/scroll behaviour when the text overflows the configured width
//   - fade-in/fade-out animation on play/pause
//   - visibility gating against playerPageVisible + hideOnPlayer
//
// MVVM owner: this is the View. No persistence, no system calls, no business
// rules beyond presentation.

@Entry
@Component
struct FloatingStatusBarLyricsWindow {
  @StorageProp('floatingWindowSbLrLine') line: string = ''
  @StorageProp('floatingWindowSbLrSubLine') subLine: string = ''
  @StorageProp('floatingWindowSbLrHasLyrics') hasLyrics: boolean = false
  @StorageProp('floatingWindowSbLrWidthDp') widthDp: number = 150
  @StorageProp('floatingWindowSbLrFontSizeDp') fontSizeDp: number = 14
  @StorageProp('floatingWindowSbLrColor') colorArgb: number = 0xFF0470E6
  @StorageProp('floatingWindowSbLrCenterAlign') centerAlign: boolean = false
  @StorageProp('statusBarLyricsNotShowTranslation') notShowTranslation: boolean = false
  @StorageProp('floatingWindowSbLrHideOnPlayer') hideOnPlayer: boolean = false
  @StorageProp('playerPageVisible') playerPageVisible: boolean = false
  // Spec25 Scenarios 5/6: pause→fade-out, resume→fade-in. The opacity target
  // is held in a local @State that is driven by an explicit animateTo call
  // from the @Watch handler — implicit .animation() bound to an @StorageProp
  // change is not guaranteed to animate (the framework may snap on the first
  // frame). Decoupling target+animation gives deterministic behaviour.
  @StorageProp('isPlaying') @Watch('onIsPlayingChanged') isPlaying: boolean = false
  @State private lyricOpacity: number = 0

  aboutToAppear(): void {
    // Initialize the opacity so cold-start matches the play/pause state.
    this.lyricOpacity = this.isPlaying ? 1 : 0
  }

  private onIsPlayingChanged(): void {
    const target: number = this.isPlaying ? 1 : 0
    if (this.lyricOpacity === target) {
      return
    }
    animateTo({ duration: 300, curve: Curve.EaseInOut }, (): void => {
      this.lyricOpacity = target
    })
  }

  build() {
    Column() {
      if (this.shouldRenderText()) {
        // Wrap in a fade-driven container so play/pause animates opacity
        // on the lyric *text*, not the whole window.
        Column() {
          // Marquee handles both static and overflowing text:
          // when src width <= container width it shows static, otherwise it
          // scrolls. This sidesteps text-measurement APIs that are not
          // universally available across HarmonyOS SDK releases.
          Marquee({
            src: this.line,
            start: this.isPlaying,
            step: 6,
            loop: -1,
            fromStart: false,
          })
            .fontSize(this.fontSizeDp)
            .fontColor(this.colorArgb)
            .width(`${this.widthDp}vp`)

          if (!this.notShowTranslation && this.subLine.length > 0) {
            Text(this.subLine)
              .fontSize(this.fontSizeDp * 0.85)
              .fontColor(this.colorArgb)
              .width(`${this.widthDp}vp`)
              .textAlign(this.centerAlign ? TextAlign.Center : TextAlign.Start)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .opacity(this.lyricOpacity)
      }
    }
    .width(`${this.widthDp}vp`)
    .height('100%')
    .alignItems(this.centerAlign ? HorizontalAlign.Center : HorizontalAlign.Start)
    .visibility(this.isHiddenByPlayer() ? Visibility.Hidden : Visibility.Visible)
  }

  // Spec25 scenarios 2 & 19: lyric text is invisible when no lyrics yet, even
  // though the window exists. Achieved by not rendering the Marquee at all.
  private shouldRenderText(): boolean {
    return this.hasLyrics && this.line.length > 0
  }

  // Spec25 scenarios 16/17: hide while player page is on top when enabled.
  private isHiddenByPlayer(): boolean {
    return this.hideOnPlayer && this.playerPageVisible
  }
}
