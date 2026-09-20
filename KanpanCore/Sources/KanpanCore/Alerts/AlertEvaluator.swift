import Foundation

/// 判一条提醒这一根 K 线响不响。
///
/// 前台（`AlertWatcher`）和服务端各跑一份，规则必须一样，所以规则写在这儿、
/// 两边照着同一段文字实现：
///
/// 1. 这条提醒还在等（`status == .active`）；
/// 2. 这一根的开盘时刻不早于 `armedAt`——挪过线之后 `armedAt` 重置成现在，
///    历史 K 线不会把刚挪好的线当场判成已触发；
/// 3. 线在这一刻有价（落在线外、那一头又没延长的，不算）；
/// 4. 这一根的最低 ≤ 线价 ≤ 最高。
///
/// `condition == .close` 本轮**前台不判**：收盘确认要等这一根真的收了才算数，
/// 前台看到的最后一根一直在动，判早了就是误报。它只进模型与白名单，真正响它的是
/// 服务端那一侧（方案第 10 节）。
public enum AlertEvaluator {
  /// 一根 K 线里提醒关心的那三个数。
  public struct Bar: Sendable, Equatable {
    /// 开盘时刻（毫秒）。线在这一刻的价就是这一根拿去比的价。
    public var openTime: Double
    public var high: Double
    public var low: Double
    public init(openTime: Double, high: Double, low: Double) {
      self.openTime = openTime; self.high = high; self.low = low
    }
  }

  /// 响了的话，响在哪条线、哪个价上。
  public struct Hit: Sendable, Equatable {
    /// `alert.lines` 里的下标。
    public var line: Int
    /// 线在这一刻的价（不是现价；现价由调用方另外带）。
    public var price: Double
    public init(line: Int, price: Double) {
      self.line = line; self.price = price
    }
  }

  public static func hit(_ alert: Alert, bar: Bar) -> Hit? {
    guard alert.status == .active, alert.condition == .touch else { return nil }
    guard bar.openTime >= alert.armedAt else { return nil }
    guard bar.high.isFinite, bar.low.isFinite else { return nil }
    let lo = min(bar.low, bar.high), hi = max(bar.low, bar.high)
    for (i, line) in alert.lines.enumerated() {
      guard let p = line.price(at: bar.openTime), p.isFinite else { continue }
      if p >= lo, p <= hi { return Hit(line: i, price: p) }
    }
    return nil
  }

  public static func fires(_ alert: Alert, bar: Bar) -> Bool { hit(alert, bar: bar) != nil }

  /// 现价离这条提醒最近的那条线有多远，按比例（0.008 就是 0.8%）。
  ///
  /// 自选页的「离提醒线最近」用它。取不到价（线在别的时间段上、两端又不延）的
  /// 那些线跳过；一条都取不到就返回 nil，那一行不显示副标题、排在最后。
  public static func distance(from price: Double, to alert: Alert, at t: Double) -> Double? {
    guard alert.isActive, price > 0, price.isFinite else { return nil }
    var best: Double?
    for line in alert.lines {
      guard let p = line.price(at: t), p.isFinite else { continue }
      let d = abs(p - price) / price
      if best == nil || d < best! { best = d }
    }
    return best
  }

  /// 一组提醒里离现价最近的那个距离。
  public static func nearestDistance(from price: Double, among alerts: [Alert], at t: Double) -> Double? {
    alerts.compactMap { distance(from: price, to: $0, at: t) }.min()
  }
}
