// UserInterfacePage.ets
// View layer: User Interface settings page for Salt Player (MVVM architecture).
// Corresponds to Android UserInterfaceScreen.kt.
// Uses HDS HdsNavDestination + HdsListItemCard for full HarmonyOS OS6 native styling.
//
// MVVM structure:
//   - View (this file): UI layout only; binds to ViewModel via @State.
//   - ViewModel (UserInterfaceViewModel.ets): observable state + business logic.
//   - Model (UserInterfaceModel.ets): pure data definitions.

import UserInterfaceViewModel from '../viewmodel/UserInterfaceViewModel'
import ScreenWakeViewModel from '../viewmodel/ScreenWakeViewModel'
import { MiniPlayerDefaults } from './main/MiniPlayerContainer'
import { ThemeSelectorRow, ThemeOptionComponent } from '../components/ThemeSelectorRow'
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode,
  HdsListItemCard,
  SuffixArrow,
  SuffixSwitch,
} from '@kit.UIDesignKit'

interface ThemeOptionParams {
  iconRes: Resource
  text: Resource
  selected: boolean
  onSelect: () => void
  iconWidth?: number
  iconHeight?: number
}

@Component
export struct UserInterfacePage {
  private navPathStack: NavPathStack = new NavPathStack()
  private scroller: Scroller = new Scroller()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''
  @StorageProp('statusBarHeight') statusBarHeight: number = 0

  // Single ViewModel instance that holds all page state and business logic
  @State vm: UserInterfaceViewModel = new UserInterfaceViewModel()

  // Global theme state synced via AppStorage for bidirectional synchronization
  @StorageLink('selectedTheme') @Watch('onSelectedThemeChanged') selectedTheme: number = 0

  // Mirrors the 'playerKeepScreenOn' AppStorage key so that external writes
  // (e.g. from the Music Info Panel on PlayerPage) are forwarded to the
  // nested SwitcherRowViewModel while this page is mounted. Without this,
  // the Settings switch would only re-read AppStorage at page construction
  // and would not reflect a live toggle from elsewhere.
  @StorageLink('playerKeepScreenOn') playerKeepScreenOn: boolean = false

  // Source of truth for the 沉浸模式 switch. Kept in sync with writes coming
  // from the player page (long-press / panel button) so the switch reflects
  // live changes while this page is mounted, and local flips propagate back
  // through vm.setImmersionMode → AppStorage.
  @StorageLink('immersionMode') immersionMode: boolean = false

  // Mirrors 'circlePlaybackCover' so the switch reflects AppStorage state live.
  // Writes flow through vm.circlePlaybackCoverVM.toggle(), whose callback
  // persists via SettingsStore and updates AppStorage, then @StorageLink echoes
  // back to `isCheck`.
  @StorageLink('circlePlaybackCover') circlePlaybackCover: boolean = false

  // Mirrors 'irregularCoverAllowed' so the switch reflects AppStorage state live.
  // Writes flow through vm.irregularCoverAllowedVM.toggle(), whose callback
  // persists via SettingsStore and updates AppStorage, then @StorageLink echoes
  // back to `isCheck`. PlayerPage binds the same key via @StorageProp.
  @StorageLink('irregularCoverAllowed') irregularCoverAllowed: boolean = true

  // Mirrors AppStorage('hideStatusBar') so the switch reflects live changes
  // (including cold-start re-hydration performed by EntryAbility) and so the
  // ViewModel callback's write round-trips back into isCheck without a page
  // reconstruction. Writer is vm.hideStatusBarVM.toggle(), which persists via
  // SettingsStore and reconciles the status bar through SystemBarModel.
  @StorageLink('hideStatusBar') hideStatusBar: boolean = false

  // Watch callback: sync AppStorage theme changes into the ViewModel
  onSelectedThemeChanged(): void {
    this.vm.syncThemeFromAppStorage(this.selectedTheme)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column() {
          // Section 1: User Interface (theme selector + lyrics nav)
          this.UserInterfaceSection()

          // Section 2: Playback Screen (flowing light + switches)
          this.PlaybackScreenSection()

          // Section 3: Song List
          this.SongListSection()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 + MiniPlayerDefaults.TOTAL_HEIGHT })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .padding({ top: (this.hideStatusBar || this.immersionMode) ? this.statusBarHeight : 0 })
    .titleBar({
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: true,
      content: {
        title: {
          mainTitle: $r('app.string.user_interface'),
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

  // ========== Section 1: User Interface ==========
  @Builder
  UserInterfaceSection() {
    this.SectionTitle($r('app.string.user_interface'))

    Column() {
      // Theme selector row (Follow System / Light / Dark) — reusable component
      ThemeSelectorRow()

      // List block for the remaining nav rows
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.wallpaper_of_main_screen') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.navPathStack.pushPath({ name: 'MainWallpaperPage' })
            },
          })
        }
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
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.immersion_mode') },
              secondaryText: { text: $r('app.string.immersion_mode_explain') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.immersionMode,
              onChange: (val: boolean) => {
                if (this.immersionMode !== val) {
                  this.vm.setImmersionMode(val)
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
              primaryText: { text: $r('app.string.hide_status_bar') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.hideStatusBar,
              onChange: (val: boolean) => {
                if (this.hideStatusBar !== val) {
                  this.vm.hideStatusBarVM.toggle()
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
      .padding({ bottom: 4 })
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
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Section 2: Playback Screen ==========
  @Builder
  PlaybackScreenSection() {
    this.SectionTitle($r('app.string.playback_screen'))

    Column() {
      // Flowing light selector row
      Row({ space: 10 }) {
        Column() {
          this.ThemeOption({
            iconRes: $r('app.media.ic_light'),
            text: $r('app.string.player_theme_light'),
            selected: this.vm.isFlowingLightModeSelected(1),
            onSelect: () => {
              this.vm.selectFlowingLightMode(1)
            }
          })
        }.layoutWeight(1)

        Column() {
          this.ThemeOption({
            iconRes: $r('app.media.ic_dark'),
            text: $r('app.string.player_theme_dark'),
            selected: this.vm.isFlowingLightModeSelected(2),
            onSelect: () => {
              this.vm.selectFlowingLightMode(2)
            }
          })
        }.layoutWeight(1)

        Column() {
          this.ThemeOption({
            iconRes: $r('app.media.ic_harmony'),
            text: $r('app.string.follow_user_interface'),
            selected: this.vm.isFlowingLightModeSelected(0),
            iconWidth: 77,
            iconHeight: 16,
            onSelect: () => {
              this.vm.selectFlowingLightMode(0)
            }
          })
        }.layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 14, bottom: 4 })
      .justifyContent(FlexAlign.Start)

      // List block for the switch rows (player screen wallpaper + toggles)
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.wallpaper_of_player_screen') },
            },
            suffixItem: new SuffixArrow({
              color: $r('sys.color.icon_tertiary'),
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            onClick: (): void => {
              this.navPathStack.pushPath({ name: 'PlayerWallpaperPage' })
            },
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.playerKeepScreenOnVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.playerKeepScreenOn,
              onChange: (val: boolean) => {
                if (this.playerKeepScreenOn !== val) {
                  ScreenWakeViewModel.getInstance().onSettingChanged(val)
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.playerKeepScreenOnVM.isEnabled,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.miniLyricsInPlayerVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.miniLyricsInPlayerVM.isOn,
              onChange: (val: boolean) => {
                if (this.vm.miniLyricsInPlayerVM.isOn !== val) {
                  this.vm.miniLyricsInPlayerVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.miniLyricsInPlayerVM.isEnabled,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.circle_playback_cover') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.circlePlaybackCover,
              onChange: (val: boolean) => {
                if (this.circlePlaybackCover !== val) {
                  this.vm.circlePlaybackCoverVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
          })
        }
        // "Allow Irregular Cover" row. Android reference
        // (UserInterfaceScreen.kt:264-272) disables this switch whenever
        // `circlePlaybackCover` is on. We mirror that by binding `enable` to
        // the negation of the AppStorage-backed `circlePlaybackCover` flag, so
        // the disabled state is always live-consistent with the circle switch
        // even on cold start.
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: this.vm.irregularCoverAllowedVM.text },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.irregularCoverAllowed,
              onChange: (val: boolean) => {
                if (this.irregularCoverAllowed !== val) {
                  this.vm.irregularCoverAllowedVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: !this.circlePlaybackCover && this.vm.irregularCoverAllowedVM.isEnabled,
          })
        }
      }
      .width('100%')
      .height('auto')
      .padding({ bottom: 4 })
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
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Section 3: Song List ==========
  @Builder
  SongListSection() {
    this.SectionTitle($r('app.string.song_list'))

    Column() {
      List({ space: 0 }) {
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.display_song_cover_in_list') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.displaySongCoverVM.isOn,
              onChange: (val: boolean) => {
                if (this.vm.displaySongCoverVM.isOn !== val) {
                  this.vm.displaySongCoverVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.displaySongCoverVM.isEnabled,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.display_song_file_name_in_list') },
              secondaryText: { text: $r('app.string.display_song_file_name_in_list_intro') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.displaySongFileNameVM.isOn,
              onChange: (val: boolean) => {
                if (this.vm.displaySongFileNameVM.isOn !== val) {
                  this.vm.displaySongFileNameVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.displaySongFileNameVM.isEnabled,
          })
        }
        ListItem() {
          HdsListItemCard({
            textItem: {
              primaryText: { text: $r('app.string.display_add_to_play_next_in_list') },
            },
            suffixItem: new SuffixSwitch({
              isCheck: this.vm.displayAddToPlayNextVM.isOn,
              onChange: (val: boolean) => {
                if (this.vm.displayAddToPlayNextVM.isOn !== val) {
                  this.vm.displayAddToPlayNextVM.toggle()
                }
              }
            }),
            cardPrefixMargin: 4,
            cardSuffixMargin: 4,
            cardBackgroundColor: Color.Transparent,
            enable: this.vm.displayAddToPlayNextVM.isEnabled,
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
    .backgroundColor(this.mainPageWallpaperPath.length > 0
      ? $r('app.color.colorItemBackgroundHalfTransparency')
      : $r('sys.color.comp_background_list_card'))
    .margin({ bottom: 12 })
  }

  // ========== Single Theme Option ==========
  @Builder
  ThemeOption($$: ThemeOptionParams) {
    ThemeOptionComponent({
      iconRes: $$.iconRes,
      text: $$.text,
      selected: $$.selected,
      iconWidth: $$.iconWidth ?? 24,
      iconHeight: $$.iconHeight ?? 24,
      onSelect: () => {
        $$.onSelect()
      }
    })
  }
}

// 在列表中显示歌曲封面：开关切换后即时刷新所有歌曲列表的封面显示。
