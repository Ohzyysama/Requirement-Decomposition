// FolderPathPage.ets
// View layer: Folder path browsing page for Salt Player.
// MVVM: This View uses FolderPathViewModel for data and logic.
//       The View only handles UI rendering and user interaction,
//       delegating all business logic and data management to the ViewModel.
// Corresponds to Android FolderPathScreen.kt
// Displays subfolders and songs within a specific file system path (e.g., /storage/emulated/0)
// Navigation: MainPage (folder tab) -> click SD card item -> FolderPathPage
// Also supports recursive navigation: FolderPathPage -> click subfolder -> FolderPathPage

import { SongItemComponent, SongInfo } from '../components/SongItemComponent'
import { FolderPathViewModel, SubFolderViewModel } from '../viewmodel/FolderPathViewModel'
import { SongInfoData } from '../model/SongItemModel'
import { BasicScreen } from '../components/BasicScreen'

@Component
export struct FolderPathPage {
  // ViewModel instance: contains all page data and business logic
  @State viewModel: FolderPathViewModel = new FolderPathViewModel()
  @StorageProp('mainPageWallpaperPath') private mainPageWallpaperPath: string = ''

  // Bridge the persisted "show cover in song list" setting into the VM so
  // mounted lists refresh live when the user toggles the setting from
  // Settings → UI. Default `true` matches the persisted default seeded in
  // EntryAbility.onCreate; AppStorage overwrites it synchronously on first
  // read and fires @Watch on every subsequent write.
  @StorageProp('displaySongCover') @Watch('onDisplaySongCoverChanged') storedDisplaySongCover: boolean = true

  // spec21 — Bridge the persisted "在列表中显示歌曲文件名" setting into the VM
  // so the song list under this folder path refreshes live when the user
  // toggles it from Settings → UI. Default `false` matches the persistProp seed.
  @StorageProp('displaySongFileName') @Watch('onDisplaySongFileNameChanged') storedDisplaySongFileName: boolean = false

  // spec22 — Bridge the persisted "在列表中显示添加下一首播放" setting into the VM
  // so the song list under this folder path refreshes live when the user
  // toggles it from Settings → UI. Default `true` matches the persistProp seed.
  @StorageProp('displayAddToPlayNext') @Watch('onDisplayAddToPlayNextChanged') storedDisplayAddToPlayNext: boolean = true

  // List scroller
  private listScroller: Scroller = new Scroller()
  private navPathStack: NavPathStack = new NavPathStack()

  onDisplaySongCoverChanged(): void {
    this.viewModel.setDisplaySongCoverInList(this.storedDisplaySongCover)
  }

  // spec21 — Forward AppStorage 'displaySongFileName' writes into the VM.
  onDisplaySongFileNameChanged(): void {
    this.viewModel.setDisplaySongFileNameInList(this.storedDisplaySongFileName)
  }

  // spec22 — Forward AppStorage 'displayAddToPlayNext' writes into the VM.
  onDisplayAddToPlayNextChanged(): void {
    this.viewModel.setDisplayAddToPlayNextInList(this.storedDisplayAddToPlayNext)
  }

  build() {
    NavDestination() {
      BasicScreen() {
      Column() {
        // ======================== Title Bar ========================
        // Matches Android BasicScreenBox: ScreenTitleBar with back button and title
        // Structure: Row with back arrow (left) + title text (center-aligned)
        this.TitleBarBuilder()

        // ======================== Content Area ========================
        // Matches Android SongLazyColumn with folder header items
        // Folders are displayed first, then songs
        List({ scroller: this.listScroller }) {
          // Subfolder items as header (lazy)
          LazyForEach(this.viewModel.folderDataSource, (folder: SubFolderViewModel) => {
            ListItem() {
              this.SubFolderItemBuilder(folder)
            }
          }, (folder: SubFolderViewModel) => folder.path)

          // Song items (lazy)
          LazyForEach(this.viewModel.songDataSource, (song: SongInfo) => {
            ListItem() {
              SongItemComponent({
                viewModel: this.viewModel.createSongItemViewModel(song, {
                  isCurrent: false,
                  showCover: this.viewModel.displaySongCoverInList,
                  displayFileName: this.viewModel.displaySongFileNameInList,
                  displayAddToPlayNext: this.viewModel.displayAddToPlayNextInList,
                  onItemClickAction: () => {
                    this.viewModel.handleSongClick(song)
                  },
                  onMenuClickAction: () => {
                    this.viewModel.handleSongMenuClick(song)
                  }
                })
              })
            }
          }, (song: SongInfo) => song.id)
        }
        .width('100%')
        .layoutWeight(1)
        .contentEndOffset(96)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.mainPageWallpaperPath.length > 0 ? Color.Transparent : $r('app.color.colorPageBackground'))
      .backgroundImage(this.mainPageWallpaperPath.length > 0 ? this.mainPageWallpaperPath : undefined)
      .backgroundImageSize(this.mainPageWallpaperPath.length > 0 ? ImageSize.Cover : ImageSize.Auto)
      }
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.navPathStack = context.pathStack
      // Retrieve params and delegate initialization to ViewModel
      const params = context.pathInfo.param as Record<string, string>
      this.viewModel.initializeWithParams(params)
    })
  }

  // ======================== Title Bar Builder ========================
  // Matches Android ScreenTitleBar: back icon (ImageView) + centered title (TextView)
  // From view.xml: back arrow at [0,63][147,210], title at [147,112][933,161]
  // 3x density conversion: back icon area ~49x49vp, title text at ~49vp from left
  @Builder
  TitleBarBuilder() {
    Row() {
      // Back button - matches Android ImageView with content-desc "return"
      // bounds [0,63][147,210] -> 49x49vp clickable area
      Image($r('app.media.ic_arrow_back'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.salt_color_icon_foreground'))
        .onClick(() => {
          this.viewModel.handleBack(this.navPathStack)
        })
        .accessibilityText($r('app.string.back'))
        .margin({ left: 12 })

      // Title text - matches Android TextView
      // Centered in the title bar area
      Text(this.viewModel.title)
        .fontSize(18)
        .fontColor($r('app.color.salt_color_icon_foreground'))
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .margin({ right: 36 })
    }
    .width('100%')
    .height(49)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 0, right: 0 })
  }

  // ======================== SubFolder Item Builder ========================
  // Matches Android FolderPathScreen.FolderItem:
  // Row with folder icon (ic_ui_folder, 24dp, tint=text) + folder name + right padding
  // Wrapped in rounded corner card with subBackground color
  @Builder
  SubFolderItemBuilder(folder: SubFolderViewModel) {
    Row() {
      // Left padding
      Blank().width(16)

      // Folder icon - Android: painterResource(R.drawable.ic_ui_folder), size 24.dp, tint = SaltTheme.colors.text
      Image($r('app.media.ic_ui_folder'))
        .width(24)
        .height(24)
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.salt_color_icon_foreground'))

      // Spacer 12dp
      Blank().width(12)

      // Folder name - Android: Text(text = folder.name, maxLines = 2)
      Column() {
        Text(folder.name)
          .fontSize(15)
          .fontColor($r('app.color.salt_color_icon_foreground'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 12, bottom: 12 })

      // Right padding
      Blank().width(16)
    }
    .constraintSize({ minHeight: 56 })
    .borderRadius(12)
    .backgroundColor($r('app.color.salt_color_bottom_page_background'))
    .alignItems(VerticalAlign.Center)
    .clip(true)
    .margin({ left: 16, right: 16, top: 6, bottom: 6 })
    .onClick(() => {
      // Navigate recursively to another FolderPathPage for the subfolder
      this.viewModel.handleSubFolderClick(folder, this.navPathStack)
    })
  }
}

// 文件夹层级路径浏览：按目录层级展开。
