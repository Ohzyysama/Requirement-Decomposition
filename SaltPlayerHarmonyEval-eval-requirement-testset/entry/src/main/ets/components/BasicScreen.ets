// BasicScreen.ets
// Common edge-to-edge screen wrapper — equivalent to Android Salt Player's BasicScreen.
//
// Provides:
//   - Top padding equal to the system status bar height
//   - Background color extending edge-to-edge (under both system bars)
//
// Usage (inside NavDestination or any page):
//   NavDestination() {
//     BasicScreen() {
//       // page content
//     }
//   }

@Component
export struct BasicScreen {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0
  @BuilderParam content: () => void
  bgColor: ResourceColor = $r('app.color.colorPageBackground')

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.statusBarHeight })
    .backgroundColor(this.bgColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

// 统一缩进，无功能变更。
