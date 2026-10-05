import Foundation
import KanpanCore

/// 搜索页的「对比模式」（2026-10-05，照 TradingView 手机版）。
///
/// 对比原来是「分析」面板里的一节：「添加对比」开品种整页挑一只、挑完就关；要加三只得开三趟面板。
/// 现在入口是顶栏那颗加号，开的就是搜索页本身，只是换了一副行尾：
///
/// - 页顶一条「正在对比」，把集合里的（最多三只）摆成小块，每块一个 × 直接拿掉；
/// - 每一行行尾一颗 ＋，点了加进集合、页面不关，接着挑下一只；已经在集合里的那一行是选中态，
///   再点一下就拿掉；满三只时别的行的 ＋ 退成禁用色，点了说一句「最多对比 3 个品种」；
/// - 主图那只自己那一行整行禁用（拿自己和自己比没有意义）；
/// - 排序与普通搜索一模一样，但不记搜索历史、不换主图。
///
/// 这里只是判定（纯值、可测）：集合本身仍是 `Prefs.compareSymbols`，加和减由宿主经 `PrefsStore`
/// 走原来那条落盘 + 同步的路（`Prefs.addCompareSymbol`）。
struct CompareSearchMode: Equatable {
  /// 持久的对比集合（`Prefs.compareSymbols`，规范键，按加入顺序）。
  var keys: [String]
  /// 主图那只（规范键）。
  var current: String

  init(keys: [String], current: String) {
    self.keys = keys
    self.current = InstrumentID.canonical(current)
  }

  /// 满三只了没有（按持久集合数，和 `Prefs.addCompareSymbol` 同一条口径）。
  var isFull: Bool { keys.count >= Prefs.maxCompareSymbols }

  /// 一行的行尾长什么样。
  enum RowState: Equatable {
    /// 可以加：＋。
    case add
    /// 已经在集合里：选中态，点了拿掉。
    case added
    /// 满了：＋ 退成禁用色，点了只说一句为什么。
    case full
    /// 主图那只：整行禁用。
    case main
  }

  func state(for symbol: String) -> RowState {
    let key = InstrumentID.canonical(symbol)
    if key == current { return .main }
    if keys.contains(key) { return .added }
    return isFull ? .full : .add
  }

  /// 点了一行（或行尾那颗）之后该做的事。
  enum Action: Equatable {
    case add(String)
    case remove(String)
    /// 满了：不改集合，只提示「最多对比 3 个品种」。
    case rejectFull
    /// 主图那只：什么都不做。
    case none
  }

  func action(for symbol: String) -> Action {
    let key = InstrumentID.canonical(symbol)
    switch state(for: key) {
    case .add: return .add(key)
    case .added: return .remove(key)
    case .full: return .rejectFull
    case .main: return .none
    }
  }

  /// 满了时那一句（顶栏加号、行尾 ＋ 共用）。
  static let fullNotice = "最多对比 \(Prefs.maxCompareSymbols) 个品种"
}
