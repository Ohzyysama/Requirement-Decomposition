// AudioOutputInfoDialogComponent.ets
// View layer: bottom sheet dialog showing detailed audio output information.
// Matches Android SaltBridgeDialog layout exactly.
// Each section has ONE circular icon with connecting lines between sections.
// Text uses inline bold-title + regular-value pattern (CommonText style).
//
// All displayed values come from AudioInfoDialogViewModel @Track properties —
// the view only reads VM fields and renders them, no business logic here.

import AudioInfoDialogViewModel from '../viewmodel/AudioInfoDialogViewModel'

@Component
export struct AudioOutputInfoDialogComponent {
  onDismiss: () => void = () => {}
  @ObjectLink viewModel: AudioInfoDialogViewModel

  @StorageProp('navBarHeight') navBarHeight: number = 28
  @StorageProp('isSystemDark') isSystemDark: boolean = false

  // 4x5 color matrix that tints black PNG icons to the target foreground color.
  // Dark mode: offset shifts black (0,0,0) to white (255,255,255).
  // Light mode: identity matrix — black icons stay black on white background.
  // For SVG icons, fillColor handles the tinting; the identity matrix is a no-op.
  getIconColorFilter(): number[] {
    if (this.isSystemDark) {
      return [0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0, 0, 0, 0, 255, 0, 0, 0, 1, 0]
    } else {
      return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
    }
  }

  getFg(): string {
    return this.isSystemDark ? '#ffffffff' : '#ff050f19'
  }

  getSubFg(): string {
    return this.isSystemDark ? '#80ffffff' : '#80050f19'
  }

  getInfoFg(): string {
    return this.isSystemDark ? '#bbffffff' : '#bb050f19'
  }

  getSubBg(): string {
    return this.isSystemDark ? '#33ffffff' : '#15050f19'
  }

  getLineColor(): string {
    return this.isSystemDark ? '#80ffffff' : '#80050f19'
  }

  getHighlight(): string {
    return this.isSystemDark ? '#FF448AFF' : '#FF0A59F7'
  }

  // Build the SRC (重采样) section's item list. "状态" is always present;
  // "品质" appears only when SRC is enabled (SPEC 3.4).
  private buildSrcItems(): BridgeTextItem[] {
    const items: BridgeTextItem[] = [
      { label: '状态', value: this.viewModel.srcStatusText }
    ]
    if (this.viewModel.srcQualityVisible) {
      items.push({ label: '品质', value: this.viewModel.srcQualityText })
    }
    return items
  }

  build() {
    Column() {
      Text('输出')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getFg())
        .width('100%')
        .padding({ left: 16, top: 12, bottom: 4 })

      Scroll() {
        Column() {
          // ==== 源音频信息 ====
          this.BridgeItem({
            iconRes: $r('app.media.ic_audio_file'),
            iconPadding: 9,
            title: '源音频信息',
            topLink: false,
            bottomLink: true,
            items: [
              { label: '路径', value: this.viewModel.pathText }
            ]
          })

          // ==== SALT CORE ====
          this.BridgeItem({
            iconRes: $r('app.media.ic_salt_core'),
            iconPadding: 9,
            title: 'SALT CORE',
            topLink: true,
            bottomLink: true,
            items: [
              { label: '当前版本', value: this.viewModel.coreVersionText },
              { label: '音频会话标识', value: this.viewModel.coreSessionIdText },
              { label: '数字信号输出（DSP）浮点支持', value: this.viewModel.coreDspFloatText },
              { label: '初始化采样率', value: this.viewModel.coreInitSampleRateText },
              { label: '系统推荐输出采样率', value: this.viewModel.coreRecommendedSampleRateText },
              { label: '使用系统媒体解码器', value: this.viewModel.coreUseSystemCodecText }
            ]
          })

          // ==== 流通道信息 ====
          this.BridgeItem({
            iconRes: $r('app.media.ic_audio_stream'),
            iconPadding: 10,
            title: '流通道信息',
            topLink: true,
            bottomLink: true,
            items: [
              { label: '采样率', value: this.viewModel.streamSampleRateText },
              { label: '比特率', value: this.viewModel.streamBitrateText }
            ]
          })

          // ==== 重采样（SRC）====
          this.BridgeItem({
            iconRes: $r('app.media.ic_src'),
            iconPadding: 10,
            title: '重采样\n（SRC）',
            topLink: true,
            bottomLink: true,
            items: this.buildSrcItems()
          })

          // ==== 数字信号处理（DSP）====
          this.BridgeItem({
            iconRes: $r('app.media.ic_dsp'),
            iconPadding: 10,
            title: '数字信号\n处理（DSP）',
            topLink: true,
            bottomLink: true,
            items: [
              { label: 'SALT PLAYER AUDIOFX V4', value: this.viewModel.dspFxNameText, clickable: true },
              { label: 'V3 混响', value: this.viewModel.dspV3ReverbText }
            ]
          })

          // ==== 数字信号输出 ====
          this.BridgeItem({
            iconRes: $r('app.media.ic_pcm'),
            iconPadding: 10,
            title: '数字信号\n输出',
            topLink: true,
            bottomLink: false,
            items: [
              { label: '音频输出模式', value: this.viewModel.outputModeText },
              { label: '平均延迟', value: this.viewModel.outputLatencyText },
              { label: '通道数', value: this.viewModel.outputChannelsText },
              { label: '采样率', value: this.viewModel.outputSampleRateText }
            ]
          })
        }
        .width('100%')
        .padding({ bottom: this.navBarHeight + 20 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  BridgeItem(params: BridgeItemParams) {
    Row() {
      // Left title column (weight 2)
      Column() {
        Text(params.title)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getFg())
          .textAlign(TextAlign.End)
          .width('100%')
      }
      .layoutWeight(2)

      // Center icon column with connecting lines
      Column() {
        // Top connecting line
        Column()
          .width(0.75)
          .height(40)
          .backgroundColor(params.topLink ? this.getSubFg() : Color.Transparent)

        // Circular icon
        Stack() {
          Image(params.iconRes)
            .width(48 - params.iconPadding * 2)
            .height(48 - params.iconPadding * 2)
            .fillColor(this.getFg())
            .colorFilter(this.getIconColorFilter())
            .objectFit(ImageFit.Contain)
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.isSystemDark ? '#ff000000' : '#ffffffff')
        .border({ width: 0.5, color: this.getSubFg(), style: BorderStyle.Solid })
        .alignContent(Alignment.Center)

        // Bottom connecting line
        Column()
          .width(0.75)
          .height(40)
          .backgroundColor(params.bottomLink ? this.getSubFg() : Color.Transparent)
      }
      .width(48)
      .margin({ left: 12, right: 12 })
      .alignItems(HorizontalAlign.Center)

      // Right content column (weight 5)
      Column() {
        ForEach(params.items, (item: BridgeTextItem, index: number) => {
          this.CommonText({ label: item.label, value: item.value, clickable: item.clickable })
        }, (item: BridgeTextItem, index: number) => index.toString())
      }
      .layoutWeight(5)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .margin({ top: params.topLink ? -18 : 0 })
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }

  @Builder
  CommonText(params: CommonTextParams) {
    Text() {
      Span(params.label)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getFg())
      Span(' ')
        .fontSize(13)
      Span(params.value)
        .fontSize(13)
        .fontColor(params.clickable ? this.getHighlight() : this.getSubFg())
        .decoration(params.clickable
          ? { type: TextDecorationType.Underline, color: this.getHighlight() }
          : { type: TextDecorationType.None })
    }
    .padding({ top: 2, bottom: 2 })
  }
}

interface BridgeTextItem {
  label: string
  value: string
  clickable?: boolean
}

interface CommonTextParams {
  label: string
  value: string
  clickable?: boolean
}

interface BridgeItemParams {
  iconRes: Resource
  iconPadding: number
  title: string
  topLink: boolean
  bottomLink: boolean
  items: BridgeTextItem[]
}
