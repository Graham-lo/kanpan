import Foundation

/// 复盘（§2F / §2G）那几处标签的文案。
///
/// 这一摊本来散在三个地方各写一遍：图上那条选区标签在 `ReviewRangeOverlay` 里现造
/// `DateFormatter`（认设备时区）、目标价按「最多 6 位、能省就省」写，复盘本里又是
/// `.number.precision(.fractionLength(0...8))` 加 `Text(Date, style: .date)`。
/// 于是同一根 K 线在轴上、在选区标签上、在复盘本里能写出三个时刻，
/// 同一口价能写出三种小数位（审查 B-07 / B-08，复核项 5）。
///
/// 现在只有这一份：时间一律按**图表那一档时区**（`TZOffset`，偏移在被格式化的那一刻现问，
/// 所以跨夏令时的历史不会整段平移），价格一律按**品种自己的小数位**
/// （`SymbolInfo.pricePrecision`；实在拿不到才 `priceDecimalsFallback`）。
///
/// 放在 KanpanCore 是为了**同一个函数**同时被 UIKit 那层手绘的 overlay、SwiftUI 的
/// 复盘本、以及用例驱动——测的就是屏上那一行，不是「另一个长得一样的格式化器」。
public enum ReviewLabels {
  /// 图上那条选区标签：`120 根 · 1/5 08:00 – 1/6 08:00`。
  public static func range(bars: Int, start: Int64, end: Int64, offsetMinutes: TZOffset) -> String {
    "\(bars) 根 · \(dayTime(ms: start, offsetMinutes: offsetMinutes))"
      + " – \(dayTime(ms: end, offsetMinutes: offsetMinutes))"
  }

  /// 目标 / 失效那一行：`目标 76800.00`。小数位由品种说。
  public static func price(_ title: String, value: Double, decimals: Int) -> String {
    title + " " + price(value, decimals: decimals)
  }

  /// 一口价。`decimals` 给 `nil` 表示品种表里问不到，那就按这口价自己猜——
  /// 写死 2 位会把 0.0000004 摆成 `0.00`。
  public static func price(_ value: Double, decimals: Int?) -> String {
    guard value.isFinite else { return "--" }
    return fmtPrice(value, decimals: decimals ?? priceDecimalsFallback(value))
  }

  /// 列表里那种短时间：`9/20 14:03`。
  public static func dayTime(ms: Int64, offsetMinutes: TZOffset) -> String {
    fmtDayTime(ms: Double(ms), offsetMinutes: offsetMinutes)
  }

  /// 要带年份的那种完整时间（到期、回放头部）：`2026-09-20 14:03`。
  public static func full(ms: Int64, offsetMinutes: TZOffset) -> String {
    fmtFull(ms: Double(ms), offsetMinutes: offsetMinutes)
  }
}
