import Foundation
import KanpanCore

// ============================================================ 桌面快捷入口
//
// 长按桌面图标弹出来的那几格（方案第 3 节第三件）：**最近看过的 3 个品种 + 搜索**。
//
// 为什么是「最近看过」而不是「自选」：自选可能有几十个，挑哪三个都得有个理由，
// 而「刚才在看的那个」不用讲理由——人合上手机再点开，十有八九还是它。
//
// 几条定好的：
//
// · **标题就是品种名**（BTC），没有副标题。副标题那一格只能塞状态
//   （「+2.3%」「行情实时」之类），那是工程字段，界面上不许有
//   （记忆 kanpan-no-engineering-status-fields）；何况桌面那一格是系统渲染的，
//   我们更新不了，摆上去就是一个永远停在上次的假数字。
// · **图标用系统符号**。品种徽章（`CoinBadge`）是现画的 SwiftUI 图形，
//   而 `UIApplicationShortcutIcon` 只收资源目录里的图或 SF Symbol，递不进去。
// · **点下去只化成一条深链**交给 `DeepLinkRouter`，不另开跳转路径（方案第 1 节）。
//
// 这一层是纯的：算出该摆哪几格，以及点下去对应哪个品种。真的去写
// `UIApplication.shared.shortcutItems`、真的接住那一下，在 `HomeShortcutsBridge`
// （那边吃 UIKit，进不了这个测试壳）。

/// 桌面上的一格。
struct HomeShortcut: Equatable, Sendable {
  /// 系统回传时认的那个 type。
  var type: String
  /// 那一格上写的字。
  var title: String
  /// SF Symbol 名。
  var icon: String
  /// 这一格对应的品种（搜索那一格没有）。
  var symbol: String?
}

enum HomeShortcuts {
  /// 最近看过摆几格。加上「搜索」那一格正好四格——iOS 长按菜单最多给四格，
  /// 再多系统自己会截掉。
  static let limit = 3

  static let symbolType = "com.mdd.kanpan.shortcut.symbol"
  static let searchType = "com.mdd.kanpan.shortcut.search"
  /// `userInfo` 里放品种代号的那个键。
  static let symbolKey = "symbol"

  /// 算出该摆哪几格。`recents` 是最近看过（新的在前，见 `SymbolPrefs.recents`）。
  static func build(recents: [String]) -> [HomeShortcut] {
    var seen = Set<String>()
    var out: [HomeShortcut] = []
    for raw in recents {
      let symbol = SymbolPrefs.key(raw)
      guard !symbol.isEmpty, seen.insert(symbol).inserted else { continue }
      out.append(HomeShortcut(type: symbolType,
                              title: SymbolInfo.placeholder(symbol: symbol).base,
                              icon: "chart.line.uptrend.xyaxis",
                              symbol: symbol))
      if out.count == limit { break }
    }
    // 搜索永远在最后一格：它是「我要找别的」，排在最近看过后面才顺手。
    out.append(HomeShortcut(type: searchType, title: "搜索", icon: "magnifyingglass", symbol: nil))
    return out
  }

  // ---------------------------------------------------------------- 装到系统上

  /// 谁真的去写 `UIApplication.shared.shortcutItems`。app 启动时由
  /// `HomeShortcutsBridge.install()` 装上；单测里装一个假的就能看到摆了哪几格。
  ///
  /// 这一层不直接碰 `UIApplication`：摆格子的决定是纯值，单测换一个假的
  /// `apply` 就看得到结果，不用真去改主屏快捷方式。
  @MainActor static var apply: (([HomeShortcut]) -> Void)?

  /// 上一次摆上去的。没变就不再写一遍——`shortcutItems` 的每次赋值都是一趟
  /// 跨进程调用，而调它的地方（`SymbolPickerModel.commit()`）是每次加自选、
  /// 每次换品种都会走的。
  @MainActor private static var applied: [HomeShortcut]?

  /// 最近看过变了，重排桌面那几格。
  @MainActor static func refresh(recents: [String]) {
    let items = build(recents: recents)
    guard applied != items else { return }
    applied = items
    apply?(items)
  }

  /// 测试用：把「已经摆过」的记号清掉。
  @MainActor static func reset() { applied = nil }
}
