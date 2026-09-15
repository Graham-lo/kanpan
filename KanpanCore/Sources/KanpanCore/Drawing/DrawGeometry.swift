import Foundation

public struct DrawBounds: Sendable {
  public var left, top, right, bottom: Double
  public init(left: Double, top: Double, right: Double, bottom: Double) {
    self.left = left; self.top = top; self.right = right; self.bottom = bottom
  }
  public func contains(_ p: DrawPixel) -> Bool { p.x >= left && p.x <= right && p.y >= top && p.y <= bottom }
}
public struct DrawPixel: Sendable, Equatable {
  public var x, y: Double
  public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}
public struct DrawSegment: Sendable {
  public var a, b: DrawPixel
}
public struct DrawGeometry: Sendable {
  public var segments: [DrawSegment] = []
  public var polygon: [DrawPixel] = []
  public var handles: [DrawPixel] = []
  public var labels: [(point: DrawPixel, text: String)] = []
  public func hit(x: Double, y: Double, handleRadius: Double = Chart.hitHandlePt) -> Drawing.Part? {
    if let nearest = handles.enumerated().min(by: {
      hypot($0.element.x - x, $0.element.y - y) < hypot($1.element.x - x, $1.element.y - y)
    }), hypot(nearest.element.x - x, nearest.element.y - y) < handleRadius {
      return [Drawing.Part.a, .b, .c][min(nearest.offset, 2)]
    }
    if segments.contains(where: { distSeg(x, y, $0.a.x, $0.a.y, $0.b.x, $0.b.y) < Chart.hitLinePt }) { return .body }
    // Closed shapes can be selected inside their fill; ordinary swipes still pan until selected.
    if polygon.count >= 3 {
      var inside = false
      var j = polygon.count - 1
      for i in polygon.indices {
        let a = polygon[i], b = polygon[j]
        if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        j = i
      }
      if inside { return .body }
    }
    return nil
  }
}

/// One geometry source for normal rendering, selected rendering, previews and hit testing.
/// Infinite lines/rays are clipped parametrically, without arbitrary extension lengths.
public func drawingGeometry(_ d: Drawing, bounds r: DrawBounds,
                            xOf: (Double) -> Double, yOf: (Double) -> Double) -> DrawGeometry {
  var g = DrawGeometry()
  guard d.isValid, !d.hidden else { return g }
  let pts = d.points.map { DrawPixel(xOf($0.t), yOf($0.p)) }
  guard pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return g }
  let a = pts[0]
  let b = pts.count > 1 ? pts[1] : a
  g.handles = pts
  func line(_ a: DrawPixel, _ b: DrawPixel, from: Double = 0, to: Double = 1) {
    let dx = b.x - a.x, dy = b.y - a.y
    var lo = from, hi = to
    for (origin, delta, lower, upper) in [(a.x, dx, r.left, r.right), (a.y, dy, r.top, r.bottom)] {
      if abs(delta) < 1e-12 { if origin < lower || origin > upper { return } }
      else {
        let t1 = (lower - origin) / delta, t2 = (upper - origin) / delta
        lo = max(lo, min(t1, t2)); hi = min(hi, max(t1, t2))
      }
    }
    guard lo <= hi, lo.isFinite, hi.isFinite else { return }
    g.segments.append(DrawSegment(a: DrawPixel(a.x + lo * dx, a.y + lo * dy), b: DrawPixel(a.x + hi * dx, a.y + hi * dy)))
  }
  switch d.kind {
  case .hline:
    line(DrawPixel(r.left, a.y), DrawPixel(r.right, a.y)); g.handles = []
    g.labels = [(DrawPixel(r.right - 4, a.y - 4), String(format: "%.8g", d.a.p))]
  case .vline:
    line(DrawPixel(a.x, r.top), DrawPixel(a.x, r.bottom)); g.handles = []
  case .hray:
    line(a, DrawPixel(a.x + 1, a.y), to: .infinity)
    g.labels = [(DrawPixel(r.right - 4, a.y - 4), String(format: "%.8g", d.a.p))]
  case .trend: line(a, b)
  case .ray: line(a, b, to: .infinity)
  case .extended: line(a, b, from: -.infinity, to: .infinity)
  case .rectangle, .measure:
    let c = DrawPixel(b.x, a.y), e = DrawPixel(a.x, b.y)
    g.polygon = [a, c, b, e]
    line(a, c); line(c, b); line(b, e); line(e, a)
    if d.kind == .measure {
      let delta = d.points[1].p - d.a.p
      let pct = d.a.p != 0 ? String(format: "%+.2f%%", delta / abs(d.a.p) * 100) : "—"
      let hours = abs(d.points[1].t - d.a.t) / 3_600_000
      g.labels = [(DrawPixel(max(a.x, b.x), min(a.y, b.y) - 6), String(format: "%+.8g", delta) + " · " + pct + " · " + String(format: "%.1f 小时", hours))]
    }
  case .channel:
    let c = pts[2], dx = b.x - a.x, dy = b.y - a.y
    let len = dx * dx + dy * dy
    guard len > 1e-9 else { return g }
    let f = ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len
    let u = DrawPixel(a.x - dy * f, a.y + dx * f), v = DrawPixel(b.x - dy * f, b.y + dx * f)
    let corners = [DrawPixel(r.left, r.top), DrawPixel(r.right, r.top), DrawPixel(r.right, r.bottom), DrawPixel(r.left, r.bottom)]
    let projections = corners.map { (($0.x - a.x) * dx + ($0.y - a.y) * dy) / len }
    let low = projections.min() ?? 0, high = projections.max() ?? 1
    let first = DrawPixel(a.x + dx * low, a.y + dy * low), last = DrawPixel(a.x + dx * high, a.y + dy * high)
    g.polygon = [first, last, DrawPixel(last.x - dy * f, last.y + dx * f), DrawPixel(first.x - dy * f, first.y + dx * f)]
    line(a, b, from: -.infinity, to: .infinity)
    line(u, v, from: -.infinity, to: .infinity)
    line(DrawPixel((a.x + u.x) / 2, (a.y + u.y) / 2), DrawPixel((b.x + v.x) / 2, (b.y + v.y) / 2), from: -.infinity, to: .infinity)
  case .fibonacci:
    line(a, b)
    for level in d.levels {
      // Retracement: 0 is the end of the measured move; 1 is its origin.
      let price = d.points[1].p + (d.a.p - d.points[1].p) * level
      let y = yOf(price)
      guard y.isFinite else { continue }
      line(DrawPixel(min(a.x, b.x), y), DrawPixel(max(a.x, b.x), y))
      g.labels.append((DrawPixel(max(a.x, b.x), y - 3), String(format: "%.3g · %.8g", level, price)))
    }
  }
  return g
}
