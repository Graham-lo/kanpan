import Foundation
import KanpanCore

/// 品种 key 与按主序列 openTime 对齐的行情。nil 表示缺根，不能用邻根补齐。
public struct CompareSeries: Sendable, Equatable {
  public var key: String
  public var name: String
  public var color: Hex
  public var open: [Double?]
  public var close: [Double?]

  public init(key: String, name: String, color: Hex, open: [Double?], close: [Double?]) {
    self.key = key; self.name = name; self.color = color
    self.open = open; self.close = close
  }

  public func percent(at index: Int, baseIndex: Int) -> Double? {
    guard open.indices.contains(baseIndex), close.indices.contains(index),
      let base = open[baseIndex], base.isFinite, base > 0,
      let price = close[index], price.isFinite, price > 0 else { return nil }
    let value = (price / base - 1) * 100
    return value.isFinite ? value : nil
  }

  /// 这条线自己的 0% 基准：从主品种的基准根 `start` 起往后（到 `end` 为止）第一根有开盘价的。
  ///
  /// 从前每条线都死认主品种那一根当基准：那一根上这只比价品种恰好缺根（还没上市、
  /// 停牌、数据没到）时整条线一个点都画不出来，图例也一路「—」，视野右边明明全有数据。
  /// 「相对于视野里第一根有数据的那根」才是对比 K 线的本意——主品种的 0% 也是这么取的。
  public func baseIndex(from start: Int, through end: Int) -> Int? {
    var i = max(0, start)
    let last = min(end, open.count - 1)
    while i <= last {
      if let value = open[i], value.isFinite, value > 0 { return i }
      i += 1
    }
    return nil
  }
}

extension ChartState {
  public var effectivePriceMode: PriceMode { percentAxis ? .percent : price.mode }

  public func compareBaseIndex(view: ViewWindow? = nil) -> Int {
    guard !series.isEmpty else { return 0 }
    return series.index(atTime: (view ?? self.view).from)
  }

  public func compareBase(view: ViewWindow? = nil) -> Double {
    guard !series.isEmpty else { return 1 }
    let value = series.open[compareBaseIndex(view: view)]
    return value.isFinite && value > 0 ? value : 1
  }

  public static func comparePercentLabel(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    if abs(value) < 0.005 { return "0%" }
    return (value > 0 ? "+" : "") + toFixed(value, 2) + "%"
  }
}
