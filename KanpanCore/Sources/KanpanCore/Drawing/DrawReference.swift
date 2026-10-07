import Foundation

/// 画线列表里那一行「距现价」：一条线的代表价，和它离最新价有多远。
///
/// **代表价 = 线上离最新价最近的那个价位。** 每一种线都有：
///
/// - 能长出提醒的那几种（水平线、趋势线、射线、通道、矩形、回撤……）照 `AlertGeometry`
///   摊出来的线取——和提醒、自选页量距离是同一份几何。每条线取它在**最新那根 K 线的时刻**
///   上的价：趋势线就是投影到那一刻的 y；那一刻落在线段外（线没开延长）就取离它最近的端点。
///   摊出好几条的（通道两边、矩形上下沿、回撤每一级）取离最新价最近的那条。
/// - 其余（垂直线、文字、形态、区间、计算型工具……）取锚点里离最新价最近的那个价。
public extension Drawing {
  /// 最新那根 K 线在 `t`（毫秒）、最新价 `latest` 时，这条线的代表价；一个可用的价都没有就是 `nil`。
  func referencePrice(at t: Double, latest: Double) -> Double? {
    var candidates: [Double] = []
    if let lines = AlertGeometry.lines(for: self) {
      for line in lines {
        if let p = line.price(at: t) { candidates.append(p); continue }
        // 那一刻落在线段外：取时间上离它最近的那个端点。
        let sorted = line.points.sorted { $0.t < $1.t }
        guard let first = sorted.first, let last = sorted.last else { continue }
        candidates.append(t <= first.t ? first.p : last.p)
      }
    }
    if candidates.isEmpty { candidates = points.map(\.p) }
    let finite = candidates.filter { $0.isFinite }
    guard latest.isFinite else { return finite.first }
    return finite.min { abs($0 - latest) < abs($1 - latest) }
  }

  /// 代表价离最新价多远（%）：线在价上方为正、下方为负。算不出来是 `nil`。
  func distancePercent(at t: Double, latest: Double) -> Double? {
    guard latest.isFinite, latest != 0, let p = referencePrice(at: t, latest: latest) else { return nil }
    let pct = (p / latest - 1) * 100
    return pct.isFinite ? pct : nil
  }
}
