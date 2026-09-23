import KanpanCore
import Foundation

/// 连续扫图（§10.1）：从自选某个分类、或某个板块的品种列表走进图表时，把**那一刻**
/// 那张列表的顺序冻结下来，之后在顶栏价格区左右横滑就能一只接一只看过去。
///
/// 这份名单是纯值：谁在第几个、下一只是谁、到没到头，全在这儿算，不碰行情、不碰视图。
/// 冻结之后列表自己再怎么重排（涨跌一跳，按涨跌幅排的那张表每秒都在换顺序）都不影响
/// 手里这一趟——横滑要的是「接着刚才那张表往下看」，不是「按现在的排名往下看」。
///
/// **当前是第几只按传进来的品种现查**，不在这儿存下标。人在图上还有别的换品种的路
/// （顶栏放大镜搜索、深链），那些路不冻结名单；走过之后手里这只可能已经不在名单里了，
/// 现查就自然退化成「这一趟结束了」，不会拿一个对不上的下标去猜下一只。
struct ScanList: Equatable, Sendable {
  /// 冻结时那张列表的顺序（已去重、统一大写）。
  let symbols: [String]

  init(_ symbols: [String]) {
    var seen = Set<String>()
    var out: [String] = []
    for raw in symbols {
      let key = InstrumentID.canonical(raw)
      guard !key.isEmpty, seen.insert(key).inserted else { continue }
      out.append(key)
    }
    self.symbols = out
  }

  /// 一只以下的名单没有「下一只」可言，等于没冻结。
  var isScannable: Bool { symbols.count > 1 }

  func index(of symbol: String) -> Int? {
    symbols.firstIndex(of: InstrumentID.canonical(symbol))
  }

  /// 前后各一只（到头的那一侧没有）。扫图时先把它们的顶栏数据和快照预取回来，
  /// 滑过去那一刻就有数。名单里没有这只（搜索进来的）就是空的。
  func neighbors(of symbol: String) -> [String] {
    guard isScannable, let here = index(of: symbol) else { return [] }
    return [here + 1, here - 1].filter { symbols.indices.contains($0) }.map { symbols[$0] }
  }

  /// 从 `symbol` 往某个方向走一只。到头不循环。
  func step(from symbol: String, _ direction: ScanDirection) -> ScanStep {
    guard isScannable, let here = index(of: symbol) else { return .unavailable }
    let next = direction == .next ? here + 1 : here - 1
    guard symbols.indices.contains(next) else { return .edge }
    return .move(symbols[next])
  }
}

/// 横滑的方向。向左翻页 = 往名单后面走（下一只），和列表从上往下读是同一个顺序。
enum ScanDirection: Equatable, Sendable { case previous, next }

/// 走一只的结果。
enum ScanStep: Equatable, Sendable {
  /// 没有名单可扫（搜索进来的、名单只有一只、手里这只已经不在名单里）。
  /// 什么都不做，也**不**给触感——那会让人以为自己滑错了方向。
  case unavailable
  /// 名单到头了。不循环，给一下轻触感，不弹任何文字。
  case edge
  /// 换到这一只。
  case move(String)
}
