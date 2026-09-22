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
