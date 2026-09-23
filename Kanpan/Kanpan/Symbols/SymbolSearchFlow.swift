/// 「搜索页 ⇄ 品种整页」这两段路（审查 16.4）。
///
/// 行情页顶栏的放大镜和自选页的搜索框开的是同一张搜索页，搜到的比一屏多时那行
/// 「查看全部 N 个品种」再把人送进品种整页；整页那颗返回要**原路退回搜索页**
/// （查询词留着），而不是一路退到底。以前两边各写一套三四个布尔量：
/// 行情页等搜索页真正收完（`onDismiss`）才开整页，自选页却在同一拍里一关一开，
/// 返回搜索页时两边又都是同一拍一关一开——这正是 UIKit「上一张还在退场就要求
/// 呈现下一张」会被吞掉的形状。现在两边共用这一个状态机，换页一律等上一张退完。
///
/// 用法：`$flow.searchShown` / `$flow.allShown` 绑到两层呈现上，两层的 `onDismiss`
/// 各自调 `searchDismissed()` / `allDismissed()`；其余动作是下面几个具名方法。
struct SymbolSearchFlow: Equatable, Sendable {
  /// 搜索页开着。绑到呈现上：系统下滑关掉时会写回 false。
  var searchShown = false
  /// 品种整页开着。
  var allShown = false
  /// 品种整页是从搜索页「查看全部」进来的：它那颗返回要退回搜索页。
  private(set) var allFromSearch = false
  /// 上一张退完之后要接着开的那一张。
  private var next: Page?

  enum Page: Equatable, Sendable { case search, all }

  /// 任何一张开着（或正要开）。行情页据此暂停图表渲染、不抢焦点。
  var isActive: Bool { searchShown || allShown || next != nil }

  /// 放大镜 / 搜索框。已经开着就什么都不做。
  mutating func openSearch() {
    guard !searchShown else { return }
    allShown = false; allFromSearch = false; next = nil
    searchShown = true
  }

  /// 搜索页里点了「查看全部」：先收搜索页，等它退完（`searchDismissed`）再开整页。
  mutating func showAllFromSearch() {
    guard searchShown else { return }
    next = .all
    searchShown = false
  }

  /// 搜索页那一层退场完毕（呈现的 `onDismiss`）。
  mutating func searchDismissed() {
    guard next == .all else { return }
    next = nil
    allFromSearch = true
    allShown = true
  }

  /// 品种整页那颗返回。返回 true 表示调用方该把查询词清掉（不是原路退回搜索页的那一趟）。
  @discardableResult
  mutating func closeAll() -> Bool {
    allShown = false
    guard allFromSearch else { return true }
    allFromSearch = false
    next = .search
    return false
  }

  /// 品种整页那一层退场完毕。系统下滑关掉整页也走这儿——这时没有「原路退回」这回事。
  mutating func allDismissed() {
    if next == .search {
      next = nil
      searchShown = true
    } else {
      allFromSearch = false
    }
  }

  /// 挑中了品种、换了账号、点了外链：人已经走到别处去了，两张都收、后路作废。
  mutating func reset() {
    searchShown = false; allShown = false; allFromSearch = false; next = nil
  }
}
