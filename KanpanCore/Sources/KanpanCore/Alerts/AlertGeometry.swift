import Foundation

/// 把图上那条线摊平成「提醒认得的几条线」。
///
/// 提醒这边不认识画线的种类，只认识 `AlertLine`：一串 (t, p) 加上两端延不延。
/// 摊平这一步把通道的两条边、矩形的上下沿、回撤的每一级各摊成一条，之后
/// 前台评估、服务端评估、自选页量距离用的都是同一份几何。
///
/// **不支持的种类返回 nil**，调用方据此决定「画完不弹确认卡」——垂直线、成交量
/// 分布、文字标注这些要么没有「价格穿过」的含义，要么形状根本不由锚点决定。
/// 几何一律照 `DrawGeometry` 里同一种的画法来，图上看到的线和会响的线必须是同一条。
public enum AlertGeometry {
  /// 能长出提醒的那些种类（方案表 2.2）。
  static let supportedKinds: Set<Drawing.Kind> = [
    .hline, .hray, .trend, .ray, .extended, .arrowLine, .crossLine,
    .channel, .rectangle, .fibonacci,
  ]

  public static func supports(_ kind: Drawing.Kind) -> Bool { supportedKinds.contains(kind) }

  public static func lines(for drawing: Drawing) -> [AlertLine]? {
    guard supports(drawing.kind) else { return nil }
    let pts = drawing.points
    guard let a = pts.first else { return nil }

    switch drawing.kind {
    // 一个点的水平线：两端都延，任何时刻都是那个价。
    case .hline:
      return [AlertLine(points: [a], extendLeft: true, extendRight: true)]
    // 十字线只取水平那一条；竖直那条是「某一刻」，不是「某个价」。
    case .crossLine:
      return [AlertLine(points: [a], extendLeft: true, extendRight: true)]
    // 水平射线只往右走。
    case .hray:
      return [AlertLine(points: [a], extendRight: true)]
    case .trend, .arrowLine:
      guard let b = pts.dropFirst().first else { return nil }
      return [AlertLine(points: [a, b])]
    case .ray:
      guard let b = pts.dropFirst().first else { return nil }
      return [AlertLine(points: [a, b], extendRight: true)]
    case .extended:
      guard let b = pts.dropFirst().first else { return nil }
      return [AlertLine(points: [a, b], extendLeft: true, extendRight: true)]
    // 矩形只有上下两条横边会被价格穿过；左右两条竖边是时间，不是价。
    case .rectangle:
      guard let b = pts.dropFirst().first else { return nil }
      let t0 = min(a.t, b.t), t1 = max(a.t, b.t)
      let top = max(a.p, b.p), bottom = min(a.p, b.p)
      return [
        AlertLine(points: [DrawPoint(t: t0, p: top), DrawPoint(t: t1, p: top)]),
        AlertLine(points: [DrawPoint(t: t0, p: bottom), DrawPoint(t: t1, p: bottom)]),
      ]
    // 通道两条边都两端无限延：基准边过 a→b，另一条平行地过 c。
    case .channel:
      guard pts.count >= 3 else { return nil }
      let b = pts[1], c = pts[2]
      let d = DrawPoint(t: c.t + (b.t - a.t), p: c.p + (b.p - a.p))
      return [
        AlertLine(points: [a, b], extendLeft: true, extendRight: true),
        AlertLine(points: [c, d], extendLeft: true, extendRight: true),
      ]
    // 回撤每一级一条横线，只在两个锚点之间那一段；0 是这一段行情的终点、1 是起点。
    case .fibonacci:
      guard let b = pts.dropFirst().first else { return nil }
      let t0 = min(a.t, b.t), t1 = max(a.t, b.t)
      let lines = drawing.levels.compactMap { level -> AlertLine? in
        let value = b.p + (a.p - b.p) * level
        guard value.isFinite else { return nil }
        return AlertLine(points: [DrawPoint(t: t0, p: value), DrawPoint(t: t1, p: value)])
      }
      return lines.isEmpty ? nil : Array(lines.prefix(maxLines))
    default:
      return nil
    }
  }

  /// 一条提醒最多摊成几条线。服务端卡的是 32（`sync_validation.rs`），这边先按同一个
  /// 数收口，免得一张刻度开满的回撤把整条操作顶成被拒。
  static let maxLines = 32
}
