// FxActivityPage.ets - Audio effects settings page (View layer)
// Refactored to MVVM pattern: View layer only handles UI rendering.
// All business logic and state are managed by FxActivityViewModel.
// Data structures and data operations are in FxActivityModel / AutoEqData (Model layer).

import { ParametricEQ } from '../model/AutoEqPresetData'
import FxActivityViewModel from '../viewmodel/FxActivityViewModel'
import { BasicScreen } from '../components/BasicScreen'

interface CircleToggleParams {
  isOn: boolean
  onChange: (value: boolean) => void
}

@Component
export struct FxActivityPage {
  private navPathStack: NavPathStack = new NavPathStack()
  // View binds to ViewModel: all state managed through ViewModel
  @State vm: FxActivityViewModel = new FxActivityViewModel()

  // Canvas rendering context (View-only concern for rendering pipeline)
  private settings: RenderingContextSettings = new RenderingContextSettings(true)
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings)

  build() {
    NavDestination() {
      BasicScreen() {
      Stack({ alignContent: Alignment.Top }) {
        // ===== Layer 1: Background image =====
        Column() {
          Image($r('app.media.bg_audio_fx'))
            .width('100%')
            .height(this.vm.bgHeight)
            .objectFit(ImageFit.Cover)
            .opacity(0.7)
        }
        .width('100%')

        // Dark gradient overlay
        Column()
          .width('100%')
          .height(this.vm.bgHeight)
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0], ['#cc000000', 0.7], ['#ff121212', 1]]
          })

        // ===== Layer 2: All content =====
        Column() {
          // Title bar
          this.TitleBar()

          // ===== Main content area =====
          if (this.vm.currentTab === 0) {
            this.ChartSection()
            this.AutoEqListContent()
          } else {
            this.AudioFxV3Content()
          }

          // ===== Bottom divider =====
          Row()
            .width('90%')
            .height(0.5)
            .backgroundColor('#33ffffff')

          // ===== Bottom tab bar =====
          this.BottomTabBar()
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#ff121212')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const w = newValue.width as number
        this.vm.updateBgHeight(w)
      })
      }
    }
    .hideTitleBar(true)
    .onWillAppear(() => {
      AppStorage.setOrCreate('hideBottomBar', true)
    })
    .onWillDisappear(() => {
      AppStorage.setOrCreate('hideBottomBar', false)
    })
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ===== Title bar =====
  @Builder
  TitleBar() {
    Row() {
      Image($r('app.media.ic_arrow_back'))
        .width(24).height(24)
        .fillColor('#ffffffff')
        .onClick(() => {
          this.navPathStack.pop()
        })

      Column() {
        Text('SALT PLAYER V4')
          .fontSize(10)
          .fontStyle(FontStyle.Italic)
          .fontColor('#99ffffff')
        Text('AUDIOFX')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontStyle(FontStyle.Italic)
          .fontColor('#ffffffff')
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      Image($r('app.media.ic_more_vert'))
        .width(24).height(24)
        .fillColor('#ffffffff')
        .onClick(() => {
          this.vm.openIntroSheet()
        })
        .bindSheet($$this.vm.showIntroSheet, this.IntroSheetContent(), {
          height: SheetSize.FIT_CONTENT,
          backgroundColor: '#ff1e1e1e',
          blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
          showClose: false
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 16 })
  }

  // ===== Chart section =====
  @Builder
  ChartSection() {
    Column() {
      // Current preset name
      Text(this.vm.currentEq.name)
        .fontSize(16)
        .fontColor('#ffffffff')
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ top: 4 })

      // Frequency response chart Canvas + Preamp overlay
      Stack({ alignContent: Alignment.BottomEnd }) {
        Canvas(this.ctx)
          .width('100%')
          .height(130)
          .backgroundColor('#00000000')
          .onReady(() => {
            this.vm.setChartReady()
            this.vm.drawChart(this.ctx)
          })

        // Preamp and author info overlay
        Column() {
          Text(this.vm.getPreampText())
            .fontSize(10)
            .fontColor('#ff4caf50')
            .textAlign(TextAlign.End)
          Text(this.vm.getAuthorText())
            .fontSize(10)
            .fontColor('#66ffffff')
            .textAlign(TextAlign.End)
        }
        .alignItems(HorizontalAlign.End)
        .padding({ right: 16, bottom: 4 })
      }
      .width('100%')
      .height(130)
    }
    .width('100%')
  }

  // ===== AutoEQ preset list =====
  @Builder
  AutoEqListContent() {
    Column() {
      Row()
        .width('90%')
        .height(0.5)
        .backgroundColor('#33ffffff')

      List() {
        ForEach(this.vm.getAllPresets(), (preset: ParametricEQ, index: number) => {
          ListItem() {
            Column() {
              Row() {
                Image(this.vm.getPresetBandIcon(preset))
                  .width(18)
                  .height(18)
                  .fillColor('#ffffffff')
                  .objectFit(ImageFit.Contain)
                  .margin({ left: 16 })

                Column() {
                  Text(preset.name)
                    .fontSize(14)
                    .fontColor('#ffffffff')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    if (preset.tag !== '') {
                      Text(` ${preset.tag} `)
                        .fontSize(9)
                        .fontColor('#ccffffff')
                        .backgroundColor('#33ffffff')
                        .borderRadius(2)
                        .padding({ left: 3, right: 3, top: 1, bottom: 1 })
                    }
                    Text(preset.tag !== '' ? `  ${preset.author}` : preset.author)
                      .fontSize(9)
                      .fontColor('#99ffffff')
                  }
                  .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 10 })
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height(50)
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                // View calls ViewModel method on user interaction
                this.vm.selectPreset(preset)
                this.vm.drawChart(this.ctx)
              })

              Row()
                .width('100%')
                .height(0.5)
                .backgroundColor('#1affffff')
                .margin({ left: 48 })
            }
          }
        }, (preset: ParametricEQ, index: number) => `${index}_${preset.name}`)
      }
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)
    }
    .layoutWeight(1)
    .width('100%')
  }

  // ===== Intro bottom sheet =====
  @Builder
  IntroSheetContent() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor('#66ffffff')
        .margin({ top: 12, bottom: 16 })

      Text('使用 PEAKEQ 参数均衡器，避免固定频段（图形）均衡器难以补偿落在两个频段之间的窄缺口和峰值的问题，还原来自 AutoEq 库等精确参数，为你带来完美听感，建议配合耳机使用。')
        .fontSize(14)
        .fontColor('#ff000000')
        .lineHeight(22)
        .padding({ left: 16, right: 16, bottom: 24 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  // ===== V3 audio effects tab content =====
  @Builder
  AudioFxV3Content() {
    Scroll() {
      Column() {
        Blank().height(100)

        // MAX Audio Acoustics
        Column() {
          Row() {
            Text('MAX Audio 声学调音')
              .fontSize(16)
              .fontColor('#ffffffff')
              .layoutWeight(1)
            this.CircleToggle({
              isOn: this.vm.maxAudioAcoustics,
              onChange: (v: boolean) => {
                this.vm.toggleMaxAudioAcoustics(v)
              }
            } as CircleToggleParams)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('90%')
        .backgroundColor('#ff1e1e1e')
        .borderRadius(12)

        Blank().height(16)

        // DX8 Reverb
        Column() {
          Row() {
            Text('V3 混响')
              .fontSize(16)
              .fontColor('#ffffffff')
              .layoutWeight(1)
            this.CircleToggle({
              isOn: this.vm.dx8Reverb,
              onChange: (v: boolean) => {
                this.vm.toggleDx8Reverb(v)
              }
            } as CircleToggleParams)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
        }
        .width('90%')
        .backgroundColor('#ff1e1e1e')
        .borderRadius(12)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  // ===== Bottom tab bar =====
  @Builder
  BottomTabBar() {
    Row() {
      // AUDIOFX Tab
      Row() {
        Image($r('app.media.ic_salt_player_audio_fx'))
          .width(24).height(24)
          .fillColor(this.vm.currentTab === 0 ? '#ffffffff' : '#66ffffff')
        if (this.vm.currentTab === 0) {
          Text('AUDIOFX')
            .fontSize(14)
            .fontColor('#ffffffff')
            .margin({ left: 6 })
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .height('100%')
      .onClick(() => {
        this.vm.switchToAudioFxTab()
      })

      // V3 Effects Tab
      Row() {
        Image($r('app.media.ic_audio_wave'))
          .width(24).height(24)
          .fillColor(this.vm.currentTab === 1 ? '#ffffffff' : '#66ffffff')
        if (this.vm.currentTab === 1) {
          Text('V3 音效')
            .fontSize(14)
            .fontColor('#ffffffff')
            .margin({ left: 6 })
        }
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .height('100%')
      .onClick(() => {
        this.vm.switchToV3Tab()
      })
    }
    .width('100%')
    .height(56)
    .backgroundColor('#00000000')
  }

  // ===== Custom circle toggle (shared UI component) =====
  @Builder
  CircleToggle(params: CircleToggleParams) {
    Row() {
      Stack() {
        Row()
          .width(42)
          .height(26)
          .borderRadius(13)
          .backgroundColor(params.isOn ? '#ff448aff' : '#33ffffff')

        Row()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor('#ffffffff')
          .margin({ left: params.isOn ? 19 : 3 })
      }
      .width(42)
      .height(26)
      .alignContent(Alignment.Start)
    }
    .onClick(() => {
      params.onChange(!params.isOn)
    })
  }
}
