import Foundation
import KanpanCore

/// 外部指标（主动买卖、多空比、基差）的「换走前记一份」（体感 2026-10-07）。
///
/// 和持仓量的 `oiMemo` 同一个办法：按「品种|周期」留着最近 24 份，换回来、扫回来时同步摆上，
/// 副图不先空一下再等一次往返。尾巴照常由 `MarketModel.loadMetrics` 补。
struct MetricMemoBook {
  struct Row {
    var points: [OIPoint]
    var region: (from: Int64, to: Int64)?
  }

  static let limit = 24

  private(set) var rows: [String: [IndicatorID: Row]] = [:]
  private(set) var order: [String] = []

  static func key(_ symbol: String, _ interval: Interval) -> String { symbol + "|" + interval.rawValue }

  /// 只记有点的那几份；一份都没有就不占位。
  mutating func remember(symbol: String, interval: Interval, points: [IndicatorID: [OIPoint]],
                         regions: [IndicatorID: (from: Int64, to: Int64)]) {
    var entry: [IndicatorID: Row] = [:]
    for (id, list) in points where !list.isEmpty { entry[id] = Row(points: list, region: regions[id]) }
    guard !entry.isEmpty else { return }
    let key = Self.key(symbol, interval)
    rows[key] = entry
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > Self.limit { rows[order.removeFirst()] = nil }
  }

  func entry(symbol: String, interval: Interval) -> [IndicatorID: Row]? { rows[Self.key(symbol, interval)] }

  mutating func forget() { rows = [:]; order = [] }

  /// 图还没报视野时先按这一屏开取：最右 200 根，再多一根给还没收的那根。
  static func defaultWindow(lastTime: Int64, step: Int64) -> ViewWindow {
    ViewWindow(from: Double(lastTime - 200 * step), to: Double(lastTime + step))
  }
}
