import Foundation

/// 周期：14 档，与原型 `app.js` 的 `ALL_PERIODS` 一一对应（不加 8h）。
public enum Interval: String, CaseIterable, Sendable, Codable {
  case m1 = "1m", m3 = "3m", m5 = "5m", m15 = "15m", m30 = "30m"
  case h1 = "1h", h2 = "2h", h4 = "4h", h6 = "6h", h12 = "12h"
  case d1 = "1d", w1 = "1w", mo1 = "1M", y1 = "1y"

  // 真正去网上拉哪一档、哪些周期要自己聚，是各家交易所的事，不在周期本身上：
  // 见 KanpanNetwork 的 `ProviderCapabilities.source(for:)`（§4.2）。

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
  /// 六档 → 七档 → 五档 → 现在的六档，也就是上限（`Prefs.maxQuick`）本身。
  ///
  /// 前两次是「一行还能塞下几颗」的算术：周期条右端从「更多 / 画线 / 记 / 图表」
  /// 减到「更多 / 图表」，腾出的位置就补给了周期。收到五档那一次是按「真正天天点的
  /// 就这几档」定的，但条上因此少一档、行尾又留着一个恒定宽的空槽，出厂第一屏读起来
  /// 是「几颗药丸 + 一段八十来点的空白」。2026-09-21 用户看了截图直接定：
  /// **出厂就把六格放满 `5m 30m 1h 4h 1d 1w`**，各档等宽铺开、彼此隔开。
  ///
  /// 六档是排版负责的那个上限（见 `IntervalBar`），所以出厂 = 满钉，不留「还能再钉一档」
  /// 的余量：想换成别的档在「更多」网格里取一钉一，一取一钉都是一下。
  ///
  /// 1m / 15m 这些没被钉住的档一档没少，都在「更多」那张网格里，点一下就切过去，
  /// 并且会在条上以一颗虚线的临时 chip 出现；想常驻就在网格里按一下图钉。
  public static let quick: [Interval] = [.m5, .m30, .h1, .h4, .d1, .w1]

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
