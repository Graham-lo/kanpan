import Foundation

/// 「分析」面板里的四节。rawValue 就是 `Prefs.analysisUsage` 里的键名（随账号同步，三端一致，**不要改名**）。
enum AnalysisSection: String, CaseIterable {
  case draw, orderFlow, indicators, compare
}

/// 「分析」面板四节怎么排：按这个人自己用得多少排，机制和画线条（`DrawingToolRank`）同一套。
///
/// 2026-10-08 用户：「主力订单流、大单列表和爆仓放在分析的靠后位置，我认为应该放到画线下面，
/// 重要的常用的应该有位置权重……完全可以结合起来动态调整位置」。所以：
///
/// - 出厂顺序 `defaultOrder`：画线 → 主力订单流 → 指标 → 对比（订单流出厂就在画线正下方）；
/// - 每在某一节里做一次实事（开始画线、拨开关、点进参数、加对比……）给那一节 +1（`counted`），
///   次数记在 `Prefs.analysisUsage`，用得多的往上排；总数过 `decayCeiling` 整体减半，量的是「最近常用」；
/// - 面板打开那一刻定一次顺序，开着期间不重排（`IndicatorPage` 里冻结）——不然拨一下开关，节就在手指底下跳。
///
/// 不给用户设置「固定哪个在上」（能自动的不做成设置）。
enum AnalysisSectionRank {
  /// 一次都没用过的节按这个顺序补位，新人第一次打开看到的就是它。
  static let defaultOrder: [AnalysisSection] = [.draw, .orderFlow, .indicators, .compare]
  /// 四节次数加起来超过它就整体减半（整数除法，减成 0 的删掉）。
  static let decayCeiling = 256

  /// 四节从上到下的顺序，一个不少。
  ///
  /// - 用过的按次数从多到少；次数一样按 `defaultOrder`。
  /// - 没用过的按 `defaultOrder` 补齐。
  static func order(usage: [String: Int]) -> [AnalysisSection] {
    let used = defaultOrder.enumerated()
      .compactMap { at, s -> (AnalysisSection, Int, Int)? in
        guard let n = usage[s.rawValue], n > 0 else { return nil }
        return (s, n, at)
      }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
      .map(\.0)
    var order = used
    for s in defaultOrder where !order.contains(s) { order.append(s) }
    return order
  }

  /// 在 `s` 那一节里做了一次事之后的次数表。认不出的键顺手丢掉，表里最多四个键。
  static func counted(_ usage: [String: Int], _ s: AnalysisSection) -> [String: Int] {
    var next = usage.filter { AnalysisSection(rawValue: $0.key) != nil && $0.value > 0 }
    next[s.rawValue, default: 0] += 1
    if next.values.reduce(0, +) > decayCeiling {
      next = next.mapValues { $0 / 2 }.filter { $0.value > 0 }
    }
    return next
  }
}
