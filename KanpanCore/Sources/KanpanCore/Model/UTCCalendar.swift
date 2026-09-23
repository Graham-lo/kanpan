import Foundation

/// 月线 / 年线按 UTC 日历走的那几步，全项目只有这一份。
///
/// 等距周期加减 `stepMs` 就够了；月线、年线的长度随月份与闰年变，只能按日历加。
/// 以前复盘桥（`ReviewChartBridge.closeTime` / `shifted`）、对比线（`compareAdjacent`）、
/// 复盘契约（`ReviewInterval.barsBetween`）各自现造一个 UTC 公历，写法还不一样
/// （一处按「是不是年线」分支、一处按「是不是月线」分支），审查 2026-09-24 §2 收成这里。
///
/// 语义跟 Foundation `Calendar.date(byAdding:)` 一致：1 月 31 日加一个月落到 2 月最后一天，
/// 时分秒原样保留。
public enum UTCCalendar {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
  }()

  /// 毫秒时间戳往后（负数往前）挪 `months` 个日历月。
  public static func adding(months: Int, to ms: Int64) -> Int64 {
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    guard let moved = calendar.date(byAdding: .month, value: months, to: date) else { return ms }
    return Int64((moved.timeIntervalSince1970 * 1000).rounded())
  }

  /// `[start, end)` 里装得下几个完整的日历月：最大的 n 使 `adding(n, start) <= end`。
  public static func wholeMonths(from start: Int64, to end: Int64) -> Int64 {
    func index(_ ms: Int64) -> Int {
      let parts = calendar.dateComponents([.year, .month], from: Date(timeIntervalSince1970: Double(ms) / 1000))
      return (parts.year ?? 0) * 12 + (parts.month ?? 0)
    }
    var n = index(end) - index(start)
    while adding(months: n, to: start) > end { n -= 1 }
    while adding(months: n + 1, to: start) <= end { n += 1 }
    return Int64(n)
  }
}

extension Interval {
  /// 从 `time` 往后（`bars` 为负就往前）走 `bars` 根的开盘时间。
  /// 等距周期按 `stepMs`；月线按日历月、年线按十二个日历月。
  public func advancing(_ time: Int64, by bars: Int) -> Int64 {
    switch self {
    case .mo1: UTCCalendar.adding(months: bars, to: time)
    case .y1: UTCCalendar.adding(months: 12 * bars, to: time)
    default: time + Int64(bars) * stepMs
    }
  }
}
