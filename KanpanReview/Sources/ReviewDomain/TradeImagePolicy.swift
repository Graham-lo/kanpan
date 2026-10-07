import CoreGraphics
import Foundation
import KanpanCore

/// 复盘本缩略图哪些落盘、落盘时用什么名字（体感优化 2026-10-07）。
///
/// 只存**画完就不会再变**的那几张：已平仓、而且图上最后一根也已经收线。持仓中的单子、
/// 刚平仓（窗口右端还在往后长）的单子每次照样现画——存了就是一张过期图。
/// 只存缩略图（列表行那一格），详情页的大图一页一张，画一次不心疼，存起来却占地方。
public enum TradeImagePolicy {
  /// 宽度小于它的是缩略图（和宿主出 JPEG / PNG 的分界同一个数）。
  public static let thumbnailMaxWidth: CGFloat = 160
  /// 盘上那份的版本：图的画法改了就换一个，旧的自然淘汰。
  public static let version = "v1"

  /// 这张图画完以后还会不会变。
  public static func isFinal(_ round: TradeRound, spec: TradeChartSpec?, now: Int64) -> Bool {
    guard !round.isOpen, let closedAt = round.closedAt else { return false }
    if let spec, let interval = Interval(rawValue: spec.interval), spec.end > spec.start {
      return interval.advancing(spec.end, by: 1) <= now
    }
    // 没有服务端那份：窗口右端是「平仓后留白」，还没走完时会跟着现在往后长。
    let settled = ReviewChartInterval.window(openedAt: round.openedAt, closedAt: closedAt, now: .max)
    return settled.interval.advancing(settled.end, by: 1) <= now
  }

  public static func persists(_ round: TradeRound, spec: TradeChartSpec?, size: CGSize, now: Int64) -> Bool {
    size.width < thumbnailMaxWidth && isFinal(round, spec: spec, now: now)
  }

  /// 盘上那张的名字：回合 id + 版本 + 尺寸 + 服务端那份窗口 + 画法（深浅、涨跌色、时区…）。
  /// 换了皮肤或涨跌色，旧图不会被拿出来冒充。
  public static func diskKey(_ round: TradeRound, spec: TradeChartSpec?, size: CGSize, style: String) -> String {
    let window = spec.map { "\($0.interval):\($0.start)-\($0.end)" } ?? "auto"
    return [version, round.id, String(round.updatedAt), "\(Int(size.width))x\(Int(size.height))", window, style]
      .joined(separator: "|")
  }
}
