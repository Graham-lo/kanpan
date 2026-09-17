import Foundation

/// 周期：14 档，与原型 `app.js` 的 `ALL_PERIODS` 一一对应（不加 8h）。
public enum Interval: String, CaseIterable, Sendable, Codable {
  case m1 = "1m", m3 = "3m", m5 = "5m", m15 = "15m", m30 = "30m"
  case h1 = "1h", h2 = "2h", h4 = "4h", h6 = "6h", h12 = "12h"
  case d1 = "1d", w1 = "1w", mo1 = "1M", y1 = "1y"

  /// 币安 `fapi/v1/klines` 的 interval。`1y` 币安没有（传过去是 `-1120 Invalid
  /// interval`），所以返回 nil，改按 `source` 拉 1M 再自己聚（§4.2）。
  public var api: String? { self == .y1 ? nil : rawValue }

  /// 真正去网上拉哪一档。只有 1y 是聚出来的。
  public var source: Interval { self == .y1 ? .mo1 : self }

  /// 周期毫秒。1M / 1y 用名义步长（30 天 / 365 天）——真实 openTime 不等距，映射一律走
  /// `BarSeries.index(atTime:)` 的二分，不用 `t0 + i*step`（§4.2）。
  public var stepMs: Int64 {
    switch self {
    case .m1: 60_000
    case .m3: 3 * 60_000
    case .m5: 5 * 60_000
    case .m15: 15 * 60_000
    case .m30: 30 * 60_000
    case .h1: 3_600_000
    case .h2: 2 * 3_600_000
    case .h4: 4 * 3_600_000
    case .h6: 6 * 3_600_000
    case .h12: 12 * 3_600_000
    case .d1: 86_400_000
    case .w1: 7 * 86_400_000
    case .mo1: 30 * 86_400_000
    case .y1: 365 * 86_400_000
    }
  }

  /// 1M（月长不等）和 1y（闰年）不等距；1w 是周一 00:00 UTC，等距。
  public var isIrregular: Bool { self == .mo1 || self == .y1 }

  public var display: String {
    switch self {
    case .m1: "1 分钟"
    case .m3: "3 分钟"
    case .m5: "5 分钟"
    case .m15: "15 分钟"
    case .m30: "30 分钟"
    case .h1: "1 小时"
    case .h2: "2 小时"
    case .h4: "4 小时"
    case .h6: "6 小时"
    case .h12: "12 小时"
    case .d1: "1 天"
    case .w1: "1 周"
    case .mo1: "1 月"
    case .y1: "1 年"
    }
  }

  /// 周期条第一行的常用档（原型 `QUICK`）。
  ///
  /// 原来是六档。周期条右端曾经排着「更多 / 画线 / 记 / 图表」四颗药丸，占掉小二百点，
  /// 留给周期的只有半屏，六档都摆不全。画线和记一笔收进「图表」那一页之后右端只剩两颗，
  /// 用户随即提出「现在周期这一行就只剩下更多和图表，可以展示更多的周期了」——
  /// 于是补上 30m。七档是竖屏一行排得下的上限——第八档只能藏进滑动里，
  /// 排不下的等于没展示。1w 仍然在「更多」那一页里。
  public static let quick: [Interval] = [.m1, .m5, .m15, .m30, .h1, .h4, .d1]

  /// 持仓量历史的原生 period。1m/3m 比 5m 还细，用 5m 对齐；> 1d 的没有原生档，
  /// 返回 nil，由调用方把 5m 源按桶取最后一条聚上去（§4.5）。
  public var oiPeriod: String? {
    switch self {
    case .m1, .m3, .m5: "5m"
    case .m15: "15m"
    case .m30: "30m"
    case .h1: "1h"
    case .h2: "2h"
    case .h4: "4h"
    case .h6: "6h"
    case .h12: "12h"
    case .d1: "1d"
    case .w1, .mo1, .y1: nil
    }
  }
}
