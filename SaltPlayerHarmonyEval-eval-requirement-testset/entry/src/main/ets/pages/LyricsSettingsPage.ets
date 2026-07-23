// LyricsSettingsPage.ets
// View layer (MVVM): Lyrics settings page for Salt Player.
// Corresponds to Android LyricsSettingsScreen.kt.
// Navigation path: MainPage -> Menu -> Settings -> Lyrics
// Style: HdsNavDestination + MINI title mode, matching UserInterfacePage.

import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import LyricsSettingsViewModel from '../viewmodel/LyricsSettingsViewModel'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  PrefixIcon,
  IconSize,
  SuffixArrow,
  SuffixSwitch,
} from '@kit.UIDesignKit'
import { ImageModifier } from '@kit.ArkUI'

// Image modifier that overrides HDS PrefixIcon's default tint with a custom fill color.
class IconFillColorModifier extends ImageModifier {
  private fillColorValue: ResourceColor

  constructor(fillColor: ResourceColor) {
    super()
    this.fillColorValue = fillColor
  }

  applyNormalAttribute(instance: ImageAttribute): void {
    instance.fillColor(this.fillColorValue)
  }
}

@Component
export struct LyricsSettingsPage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @StorageProp('hideStatusBar') hideStatusBar: boolean = false
  @StorageProp('immersionMode') immersionMode: boolean = false

  // Desktop-lyrics switch states bound straight to AppStorage. The system
  // overlay's lock / close gestures land in the controller, which writes
  // these AppStorage keys (DesktopLyricsAVSessionController.stateCb /
  // handleExternalClose); EntryAbility seeds + PersistentStorage-persists
  // them. Binding the SuffixSwitch.isCheck here makes the toggles re-read
  // reliably on any external flip — the nested @Observed/@Track →
  // HdsListItemCard rebuild path proved unreliable under API 23 strict mode.
  @StorageProp('desktopLyrics') desktopLyricsOn: boolean = false
  @StorageProp('lockDesktopLyrics') lockDesktopLyricsOn: boolean = false

  // Single ViewModel instance that holds all page state and business logic
  @State vm: LyricsSettingsViewModel = new LyricsSettingsViewModel()

  // spec27 — one-shot teardown of the lock-changed listener registered
  // by the VM in initFromModel. aboutToDisappear is the documented
  // ArkUI one-shot disposal callback (not a live-sync init), aligned
  // with the project's rule that lifecycle callbacks are acceptable
  // only for setup/teardown.
  aboutToDisappear(): void {
    this.vm.dispose()
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Scroll(this.scroller) {
          Column() {
            // --- 1. Lyrics Interface ---
            this.LyricsInterfaceSection()

            // --- 2. Floating Window Status Bar Lyrics (Pro) ---
            this.FloatingWindowSection()

            // --- 3. Desktop Lyrics ---
            this.SectionTitle($r('app.string.desktop_lyrics'))
            this.DesktopLyricsSection()

            // --- 4. Notification Bar Lyrics ---
            this.NotificationBarLyricsSection()

            // --- 5. Status Bar Lyrics ---
            this.SectionTitle($r('app.string.status_bar_lyrics'))
            this.StatusBarLyricsSection()

            // --- 6. Xposed Status Bar Lyrics ---
            this.SectionTitle($r('app.string.xposed_status_bar_lyrics'))
            this.XposedStatusBarLyricsSection()
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 16, bottom: 16 + MiniPlayerDefaults.TOTAL_HEIGHT })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // Xposed Lyric-Getter confirmation dialog
        if (this.vm.showXposedLyricGetterDialog) {
          this.XposedLyricGetterDialog()
        }
      }
      .width('100%')
      .height('100%')
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.lyrics'),
        },
      },
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
    .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
    .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
    })
  }

  // ========== Section Title ==========
  @Builder
  SectionTitle(text: Resource) {
    Text(text)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.font_secondary'))
      .width('100%')
      .padding({ left: 12, top: 20, bottom: 8 })
  }

  // ========== 1. Lyrics Interface Navigation Item ==========
  @Builder
  LyricsInterfaceSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.lyrics_screen') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.navPathStack.pushPath({ name: 'LyricsInterfacePage' })
            },
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 16,
        endMargin: 16,
      })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== 2. Floating Window Status Bar Lyrics ==========
  @Builder
  FloatingWindowSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.floating_window_status_bar_lyrics') },
              secondaryText: { text: $r('app.string.floating_window_status_bar_lyrics_info') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.navPathStack.pushPath({ name: 'FloatingWindowStatusBarLyricsPage' })
            },
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== 3. Desktop Lyrics Section ==========
  @Builder
  DesktopLyricsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.desktopLyricsVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.desktopLyricsOn,
              onChange: (val: boolean) => {
                if (this.desktopLyricsOn !== val) {
                  this.vm.onDesktopLyricsChanged(val).catch((e: Error) => {
                    console.warn('LyricsSettingsPage.onDesktopLyricsChanged: ' + e.message)
                  })
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: true,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.lockDesktopLyricsVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.lockDesktopLyricsOn,
              onChange: (val: boolean) => {
                if (this.lockDesktopLyricsOn !== val) {
                  this.vm.setLockDesktopLyrics(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.desktopLyricsOn,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 16,
        endMargin: 16,
      })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== 4. Notification Bar Lyrics Section ==========
  @Builder
  NotificationBarLyricsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.notificationBarLyricsVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.notificationBarLyricsVM.isOn,
              onChange: (val: boolean) => {
                if (this.vm.notificationBarLyricsVM.isOn !== val) {
                  this.vm.notificationBarLyricsVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.notificationBarLyricsVM.isEnabled,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== 5. Status Bar Lyrics Section ==========
  @Builder
  StatusBarLyricsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.system_level_status_bar_lyrics') },
              secondaryText: { text: $r('app.string.status_bar_lyrics_intro') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.systemLevelStatusBarLyrics,
              onChange: (val: boolean) => {
                if (this.vm.systemLevelStatusBarLyrics !== val) {
                  this.vm.onSystemLevelStatusBarLyricsChanged(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.status_bar_lyrics_not_show_translation') },
              secondaryText: { text: $r('app.string.status_bar_lyrics_not_show_translation_info') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.statusBarLyricsNotShowTranslation,
              onChange: (val: boolean) => {
                if (this.vm.statusBarLyricsNotShowTranslation !== val) {
                  this.vm.onStatusBarLyricsNotShowTranslationChanged(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 16,
        endMargin: 16,
      })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== 6. Xposed Status Bar Lyrics Section ==========
  @Builder
  XposedStatusBarLyricsSection() {
    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.xposed_status_bar_lyrics') },
              secondaryText: { text: 'Block-Network/StatusBarLyric' },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.xposedStatusBarLyrics,
              onChange: (val: boolean) => {
                if (this.vm.xposedStatusBarLyrics !== val) {
                  this.vm.onXposedStatusBarLyricsChanged(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: 'Xposed Lyric-Getter (API 6)' },
              secondaryText: { text: 'xiaowine/Lyric-Getter' },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.xposedLyricGetter,
              onChange: (val: boolean) => {
                if (this.vm.xposedLyricGetter !== val) {
                  this.vm.onXposedLyricGetterToggleRequested(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ top: 4, bottom: 4 })
      .divider({
        strokeWidth: 0.5,
        color: $r('sys.color.comp_divider'),
        startMargin: 16,
        endMargin: 16,
      })
    }
    .width('100%')
    .borderRadius(20)
    .clip(true)
    .backgroundColor(this.mainPageWallpaperPath.length > 0 ? $r('app.color.colorItemBackgroundHalfTransparency') : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Xposed Lyric-Getter Confirmation Dialog ==========
  @Builder
  XposedLyricGetterDialog() {
    Column() {
      Column() {
        Text('Xposed Lyric-Getter')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .margin({ bottom: 12 })

        Text($r('app.string.xposed_lyric_getter_tip'))
          .fontSize(14)
          .fontColor($r('app.color.salt_color_sub_text'))
          .margin({ bottom: 24 })

        Row() {
          Button($r('app.string.cancel'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_icon_foreground'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.vm.cancelXposedLyricGetterDialog()
            })

          Button($r('app.string.confirm'))
            .fontSize(14)
            .fontColor($r('app.color.salt_color_high_light'))
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .onClick(() => {
              this.vm.confirmXposedLyricGetter()
            })
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .borderRadius(16)
      .backgroundColor($r('app.color.salt_color_white'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
    .onClick(() => {
      this.vm.dismissXposedLyricGetterDialog()
    })
  }
}

// 锁定桌面歌词开关依赖桌面歌词开关，桌面歌词关闭时该项禁用。
