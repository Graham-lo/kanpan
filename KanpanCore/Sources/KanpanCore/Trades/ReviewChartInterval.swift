import Foundation

/// 交易复盘自动截图的周期与时间窗（协议 4.3）。
///
/// 周期按持仓时长挑：几分钟的短线看 5 分钟线才看得清进出，拿了两周的仓看 4 小时线才装得下。
/// 服务端算 `result.chart` 用的是同一张表（`Backend/kanpan-api` 里照这里实现），
/// 结果没回来之前客户端也能用它先把图画出来。
public enum ReviewChartInterval {
  /// ≤4h → 5m，≤2d → 1h，≤14d → 4h，否则 1d。边界含等号。
  public static func forHolding(_ holdingMs: Int64) -> Interval {
    switch holdingMs {
    case ...(4 * 3_600_000): .m5
    case ...(2 * 86_400_000): .h1
    case ...(14 * 86_400_000): .h4
    default: .d1
    }
  }

  public struct Window: Sendable, Hashable {
    public let interval: Interval
    public let start: Int64
    public let end: Int64
  }

  /// 图的时间窗：前后各留 `max(10 根, 持仓时长的四分之一)`，对齐到周期，右端不越过 `now`。
  /// 持仓中的回合按「开到现在」算。
  public static func window(openedAt: Int64, closedAt: Int64?, now: Int64) -> Window {
    let close = closedAt ?? now
    let holding = max(0, close - openedAt)
    let interval = forHolding(holding)
    let step = interval.stepMs
    let pad = max(10 * step, holding / 4)
    let start = floorTo(openedAt - pad, step)
    let end = min(ceilTo(close + pad, step), floorTo(now, step))
    return Window(interval: interval, start: start, end: max(end, start))
  }

  static func floorTo(_ t: Int64, _ step: Int64) -> Int64 {
    let r = t % step
    return r >= 0 ? t - r : t - r - step
  }

  static func ceilTo(_ t: Int64, _ step: Int64) -> Int64 {
    let f = floorTo(t, step)
    return f == t ? t : f + step
  }
}
