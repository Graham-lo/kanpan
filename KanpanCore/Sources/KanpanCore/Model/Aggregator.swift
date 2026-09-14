import Foundation

/// 把细周期 K 线按自然桶聚成粗周期（§4.2）。
///
/// 为什么要有它：币安 `fapi/v1/klines` 只到 `1M`，**没有 `1y`**（传 `1y` 回
/// `-1120 Invalid interval`），年线只能客户端自己合。同一套分桶顺手也用来
/// 从 1d 合 1w / 1M——切周期时目标周期还没到货，先拿手头的数据聚一份糊上去，
/// 免得白板（§7 切周期）。
///
/// 规矩：`open` 取桶内第一根的 open，`close` 取最后一根的 close，`high`/`low`
/// 取极值，`volume` 求和，`openTime` 取**桶的起点**（不是桶内第一根的时间）。
/// 当年/当月没走完的那根照样聚出来，它跟普通末根一样会随 WS 跳。
public enum Aggregator {
  /// 桶起点：把时间戳压到所在周期的自然边界（UTC）。
  ///
  /// - 周：ISO 周一 00:00。1970-01-01 是周四，所以要先挪 4 天再取整。
  /// - 月 / 年：走日历，月长和闰年不能用除法糊。
  public static func bucketStart(ms: Int64, interval: Interval) -> Int64 {
    let day: Int64 = 86_400_000
    switch interval {
    case .w1:
      return floorDiv(ms - 4 * day, 7 * day) * (7 * day) + 4 * day
    case .mo1:
      let p = DateParts(ms: Double(ms), offsetMinutes: 0)
      return utcMs(year: p.year, month: p.month, day: 1)
    case .y1:
      let p = DateParts(ms: Double(ms), offsetMinutes: 0)
      return utcMs(year: p.year, month: 1, day: 1)
    default:
      // 等距周期：币安的边界就是从纪元起整除，1d 也在其中（UTC 00:00）。
      return floorDiv(ms, interval.stepMs) * interval.stepMs
    }
  }

  /// 分桶聚合。`series` 必须按时间升序。
  ///
  /// 只能从细往粗聚：源周期的名义步长比目标大就聚不出来（拿 1d 是变不出 1h 的），
  /// 这种情况原样返回一份贴了目标周期标签的空序列，让调用方去拉网络。
  public static func bucket(series: BarSeries, into interval: Interval) -> BarSeries {
    var out = BarSeries(
      symbol: series.symbol, interval: interval, t0: 0, step: interval.stepMs,
      open: [], high: [], low: [], close: [], volume: [],
      openTime: [])
    guard series.count > 0, series.step <= interval.stepMs else { return out }

    var bars: [Bar] = []
    bars.reserveCapacity(series.count / 4 + 1)
    var curStart: Int64 = 0
    for i in 0..<series.count {
      let t = series.time(at: i)
      let s = bucketStart(ms: t, interval: interval)
      if bars.isEmpty || s != curStart {
        curStart = s
        bars.append(Bar(
          openTime: s, open: series.open[i], high: series.high[i],
          low: series.low[i], close: series.close[i], volume: series.volume[i]))
      } else {
        let j = bars.count - 1
        bars[j].high = max(bars[j].high, series.high[i])
        bars[j].low = min(bars[j].low, series.low[i])
        bars[j].close = series.close[i]
        bars[j].volume += series.volume[i]
      }
    }

    out = BarSeries(
      symbol: series.symbol, interval: interval,
      t0: bars[0].openTime, step: interval.stepMs,
      open: bars.map(\.open), high: bars.map(\.high), low: bars.map(\.low),
      close: bars.map(\.close), volume: bars.map(\.volume),
      // 不等距周期必须带表；等距周期也带上，因为聚出来中间可能缺桶（停牌、数据洞）。
      openTime: bars.map(\.openTime))
    return out
  }

  // ------------------------------------------------------------ 日历小工具

  /// 向下取整的整除（Swift 的 `/` 是朝零截断，负时间戳上会错一桶）。
  static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
  }

  /// 年月日（UTC 00:00）→ 毫秒。Howard Hinnant 的 days_from_civil。
  public static func utcMs(year: Int, month: Int, day: Int) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = month > 2 ? month - 3 : month + 9
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    let days = era * 146_097 + doe - 719_468
    return Int64(days) * 86_400_000
  }
}
