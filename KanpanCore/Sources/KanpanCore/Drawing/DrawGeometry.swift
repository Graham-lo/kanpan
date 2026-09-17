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
  public var tint: DrawTint = .line
}

/// 这一笔用哪个颜色画。
///
/// 绝大多数画线只有一个颜色——用户在样式里挑的那个（`.line`）。「多空持仓框」是例外：
/// 盈利那半边和亏损那半边必须一眼分得出来，它们跟着**图表的涨跌色**走，
/// 而不是跟着这条线自己的颜色，不然一个红框一个红框，谁是止损看不出来。
public enum DrawTint: Sendable, Equatable { case line, up, down }

/// 一块填充区。
public struct DrawFill: Sendable {
  public var points: [DrawPixel]
  public var tint: DrawTint = .line
  public init(points: [DrawPixel], tint: DrawTint = .line) { self.points = points; self.tint = tint }
}

public struct DrawLabel: Sendable {
  public var point: DrawPixel
  public var text: String
  public var tint: DrawTint = .line
  public init(point: DrawPixel, text: String, tint: DrawTint = .line) {
    self.point = point; self.text = text; self.tint = tint
  }
}

public struct DrawGeometry: Sendable {
  public var segments: [DrawSegment] = []
  public var fills: [DrawFill] = []
  public var handles: [DrawPixel] = []
  public var labels: [DrawLabel] = []
  /// 只有一块填充区时的老写法。多块的（持仓框）走 `fills`。
  public var polygon: [DrawPixel] {
    get { fills.first?.points ?? [] }
    set { fills = newValue.isEmpty ? [] : [DrawFill(points: newValue)] }
  }
  public func hit(x: Double, y: Double, handleRadius: Double = Chart.hitHandlePt) -> Drawing.Part? {
    if let nearest = handles.enumerated().min(by: {
      hypot($0.element.x - x, $0.element.y - y) < hypot($1.element.x - x, $1.element.y - y)
    }), hypot(nearest.element.x - x, nearest.element.y - y) < handleRadius {
      return Drawing.Part.anchor(nearest.offset)
    }
    if segments.contains(where: { distSeg(x, y, $0.a.x, $0.a.y, $0.b.x, $0.b.y) < Chart.hitLinePt }) { return .body }
    // Closed shapes can be selected inside their fill; ordinary swipes still pan until selected.
    for fill in fills where fill.points.count >= 3 {
      let poly = fill.points
      var inside = false
      var j = poly.count - 1
      for i in poly.indices {
        let a = poly[i], b = poly[j]
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
///
/// `decimals` 是**价格轴当前的小数位**（`ChartState.decimals`）。图上这些标签写的都是
/// 价格，价格轴右边写着 `77017.10`，标签上却是 `%.8g` 跑出来的 `77017.099999999`，
/// 同一个数在同一屏上两种写法，读起来像两回事（§2E6）。传 nil 就退回原来的 `%.8g`，
/// 单测和命中测试不关心标签，不用为它编一个小数位。
public func drawingGeometry(_ d: Drawing, bounds r: DrawBounds,
                            xOf: (Double) -> Double, yOf: (Double) -> Double,
                            decimals: Int? = nil) -> DrawGeometry {
  var g = DrawGeometry()
  /// 价格照坐标轴写。没给小数位就按老样子来。
  func price(_ v: Double) -> String {
    guard let decimals else { return String(format: "%.8g", v) }
    return fmtNum(v, decimals)
  }
  func signedPrice(_ v: Double) -> String { (v < 0 ? "-" : "+") + price(abs(v)) }
  /// 涨跌幅。基准价是 0 或不是数时给一个破折号，不写成 `nan%`。
  func percent(_ from: Double, _ to: Double) -> String {
    guard from != 0, from.isFinite, to.isFinite else { return "—" }
    return String(format: "%+.2f%%", (to - from) / abs(from) * 100)
  }
  /// 一段时长。分钟级的别写成「0.0 小时」，跨月的也别写成「1680.0 小时」。
  func span(_ ms: Double) -> String {
    let minutes = abs(ms) / 60_000
    if minutes < 90 { return String(format: "%.0f 分钟", minutes) }
    let hours = minutes / 60
    if hours < 48 { return String(format: "%.1f 小时", hours) }
    return String(format: "%.1f 天", hours / 24)
  }
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
  /// 依次连起来。形态类（XABCD / 头肩 / 艾略特）都是一条折线加几个字母，走这一支。
  func polyline(_ ps: [DrawPixel]) {
    for i in 1 ..< max(ps.count, 1) { line(ps[i - 1], ps[i]) }
  }
  /// 在每个端点上压一个记号：形态图上「这是 B 点」比线本身还重要。
  func marks(_ ps: [DrawPixel], _ names: [String]) {
    for (i, p) in ps.enumerated() where i < names.count {
      g.labels.append(DrawLabel(point: DrawPixel(p.x, p.y - 5), text: names[i]))
    }
  }
  /// 箭头尖。用一块三角填充画，因为描边的两笔在细线宽下几乎看不出方向。
  func arrowHead(at tip: DrawPixel, from tail: DrawPixel, size: Double = 9) {
    let dx = tip.x - tail.x, dy = tip.y - tail.y
    let len = (dx * dx + dy * dy).squareRoot()
    guard len > 1e-6 else { return }
    let ux = dx / len, uy = dy / len, w = size * 0.42
    g.fills.append(DrawFill(points: [
      tip,
      DrawPixel(tip.x - ux * size - uy * w, tip.y - uy * size + ux * w),
      DrawPixel(tip.x - ux * size + uy * w, tip.y - uy * size - ux * w),
    ]))
  }
  /// 一个闭合多边形：填充 + 描边。椭圆、三角形、旗标、箭头标记都用它。
  func shape(_ ps: [DrawPixel], tint: DrawTint = .line) {
    guard ps.count >= 3 else { return }
    g.fills.append(DrawFill(points: ps, tint: tint))
    for i in ps.indices { g.segments.append(DrawSegment(a: ps[i], b: ps[(i + 1) % ps.count], tint: tint)) }
  }
  /// 平行通道的公共算法：A→B 是基线，C 决定偏移量。返回 (基线向量, 偏移系数)。
  func offsetChannel(_ a: DrawPixel, _ b: DrawPixel, _ c: DrawPixel) -> (dx: Double, dy: Double, f: Double)? {
    let dx = b.x - a.x, dy = b.y - a.y
    let len = dx * dx + dy * dy
    guard len > 1e-9 else { return nil }
    return (dx, dy, ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len)
  }
  switch d.kind {
  case .hline:
    line(DrawPixel(r.left, a.y), DrawPixel(r.right, a.y)); g.handles = []
    g.labels = [DrawLabel(point: DrawPixel(r.right - 4, a.y - 4), text: price(d.a.p))]
  case .vline:
    line(DrawPixel(a.x, r.top), DrawPixel(a.x, r.bottom)); g.handles = []
  case .hray:
    line(a, DrawPixel(a.x + 1, a.y), to: .infinity)
    g.labels = [DrawLabel(point: DrawPixel(r.right - 4, a.y - 4), text: price(d.a.p))]
  case .trend: line(a, b)
  case .ray: line(a, b, to: .infinity)
  case .extended: line(a, b, from: -.infinity, to: .infinity)
  case .rectangle:
    let c = DrawPixel(b.x, a.y), e = DrawPixel(a.x, b.y)
    g.polygon = [a, c, b, e]
    line(a, c); line(c, b); line(b, e); line(e, a)
  case .measure:
    // 「测量」是两点之间的一条线加一句读数，不是一个框（§2E4）。
    //
    // 原来它和矩形走同一支：四条边围出一个矩形，`filled` 还能给它填个底。可量的是
    // 「从 A 到 B 涨了多少、花了多久」——一根对角线；围出来的那个框既不是结构也不是
    // 区间，填上底之后更像是在图上圈了一块地，把底下的 K 线整段盖住。现在只连 A→B，
    // 读数压在终点上方，量完抬眼就能看见，K 线一根不挡。
    line(a, b)
    g.polygon = []
    let delta = d.points[1].p - d.a.p
    let pct = d.a.p != 0 ? String(format: "%+.2f%%", delta / abs(d.a.p) * 100) : "—"
    g.labels = [DrawLabel(point: DrawPixel(b.x, b.y - 6),
                          text: signedPrice(delta) + " · " + pct + " · " + span(abs(d.points[1].t - d.a.t)))]
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
      let value = d.points[1].p + (d.a.p - d.points[1].p) * level
      let y = yOf(value)
      guard y.isFinite else { continue }
      line(DrawPixel(min(a.x, b.x), y), DrawPixel(max(a.x, b.x), y))
      g.labels.append(DrawLabel(point: DrawPixel(max(a.x, b.x), y - 3),
                                text: String(format: "%.3g", level) + " · " + price(value)))
    }

  case .regression:
    // 中心线是落笔那一刻拟合好的（见 `Drawing.fittedRegression`），这里只是把它和
    // 上下两条边画出来。和平行通道的区别只有一个：回归通道**不往两头无限延伸**——
    // 它描述的是被圈起来的那一段行情，延伸出去的部分没有数据支持。
    let c = pts[2], dx = b.x - a.x, dy = b.y - a.y
    let len = dx * dx + dy * dy
    guard len > 1e-9 else { return g }
    let f = ((c.x - a.x) * -dy + (c.y - a.y) * dx) / len
    let u = DrawPixel(a.x - dy * f, a.y + dx * f), v = DrawPixel(b.x - dy * f, b.y + dx * f)
    // 上下两条边对中心线对称，所以另一侧是 -f。
    let u2 = DrawPixel(a.x + dy * f, a.y - dx * f), v2 = DrawPixel(b.x + dy * f, b.y - dx * f)
    g.fills = [DrawFill(points: [u, v, v2, u2])]
    line(a, b); line(u, v); line(u2, v2)

  case .position:
    // 三点：① 入场 ② 目标 ③ 止损。目标在入场上方就是做多，在下方就是做空——
    // 不额外做一个「多 / 空」开关，用户画出来的方向就是答案。
    let c = pts[2]
    let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
    let entry = d.a.p, target = d.points[1].p, stop = d.points[2].p
    func box(_ yTop: Double, _ yBottom: Double, _ tint: DrawTint) {
      let poly = [DrawPixel(x0, yTop), DrawPixel(x1, yTop), DrawPixel(x1, yBottom), DrawPixel(x0, yBottom)]
      g.fills.append(DrawFill(points: poly, tint: tint))
      for i in poly.indices {
        g.segments.append(DrawSegment(a: poly[i], b: poly[(i + 1) % poly.count], tint: tint))
      }
    }
    box(a.y, b.y, .up)      // 入场 → 目标：赚的那一半
    box(a.y, c.y, .down)    // 入场 → 止损：亏的那一半
    g.segments.append(DrawSegment(a: DrawPixel(x0, a.y), b: DrawPixel(x1, a.y)))
    let gain = abs(target - entry), risk = abs(entry - stop)
    let ratio = risk > 0 ? String(format: "%.2f", gain / risk) : "—"
    g.labels = [
      DrawLabel(point: DrawPixel(x1, min(a.y, b.y) - 4), text: "目标 " + percent(entry, target), tint: .up),
      DrawLabel(point: DrawPixel(x1, max(a.y, c.y) + 12), text: "止损 " + percent(entry, stop), tint: .down),
      DrawLabel(point: DrawPixel(x1, a.y - 4), text: "盈亏比 " + ratio),
    ]

  case .fibExtension:
    // 三点：A → B 是被量的那一段，C 是从哪儿开始往外投。刻度值 = C + (B − A) × 比例。
    let c = pts[2]
    line(a, b); line(b, c)
    let move = d.points[1].p - d.a.p
    for level in d.levels {
      let value = d.points[2].p + move * level
      let y = yOf(value)
      guard y.isFinite else { continue }
      line(DrawPixel(c.x, y), DrawPixel(r.right, y))
      g.labels.append(DrawLabel(point: DrawPixel(r.right - 4, y - 3),
                                text: String(format: "%.3g", level) + " · " + price(value)))
    }

  case .priceRange:
    // 只认两个价，不认时间：它量的是「这一档到那一档有多远」，横着铺满整张图。
    let top = min(a.y, b.y), bottom = max(a.y, b.y)
    g.polygon = [DrawPixel(r.left, top), DrawPixel(r.right, top),
                 DrawPixel(r.right, bottom), DrawPixel(r.left, bottom)]
    line(DrawPixel(r.left, a.y), DrawPixel(r.right, a.y))
    line(DrawPixel(r.left, b.y), DrawPixel(r.right, b.y))
    let delta = d.points[1].p - d.a.p
    g.labels = [DrawLabel(point: DrawPixel(r.right - 4, top - 4),
                          text: signedPrice(delta) + " · " + percent(d.a.p, d.points[1].p))]

  case .dateRange:
    // 对称的另一半：只认两个时间，竖着铺满整张图。
    let left = min(a.x, b.x), right = max(a.x, b.x)
    g.polygon = [DrawPixel(left, r.top), DrawPixel(right, r.top),
                 DrawPixel(right, r.bottom), DrawPixel(left, r.bottom)]
    line(DrawPixel(a.x, r.top), DrawPixel(a.x, r.bottom))
    line(DrawPixel(b.x, r.top), DrawPixel(b.x, r.bottom))
    g.labels = [DrawLabel(point: DrawPixel(right, r.top + 14), text: span(d.points[1].t - d.a.t))]

  case .note:
    // 一个点加一句话。没有线可画，标签就是它本身；空着的时候给一句占位，
    // 不然刚点下去图上什么都没有，用户会以为没画上。
    g.labels = [DrawLabel(point: DrawPixel(a.x, a.y - 4), text: d.text.isEmpty ? "点这里写字" : d.text)]

  // ---------------------------------------------------------------- 线条

  case .crossLine:
    // 一个点上的横竖两条。十字线是「这一根、这个价」的书签，不是可拖的十字光标。
    line(DrawPixel(r.left, a.y), DrawPixel(r.right, a.y))
    line(DrawPixel(a.x, r.top), DrawPixel(a.x, r.bottom))
    g.labels = [DrawLabel(point: DrawPixel(r.right - 4, a.y - 4), text: price(d.a.p))]

  case .arrowLine:
    line(a, b)
    arrowHead(at: b, from: a)

  // ---------------------------------------------------------------- 通道

  case .pitchfork:
    // 安德鲁斯分叉：A 是柄的起点，B / C 是另外两个枢轴。中线从 A 指向 BC 的中点，
    // 上下两条平行线分别穿过 B 和 C；三条都往右延伸，因为它是拿来看后面走势的。
    let c = pts[2]
    let mid = DrawPixel((b.x + c.x) / 2, (b.y + c.y) / 2)
    line(b, c)
    line(a, mid, to: .infinity)
    let dx = mid.x - a.x, dy = mid.y - a.y
    line(b, DrawPixel(b.x + dx, b.y + dy), to: .infinity)
    line(c, DrawPixel(c.x + dx, c.y + dy), to: .infinity)
    if d.filled {
      g.fills = [DrawFill(points: [b, DrawPixel(b.x + dx, b.y + dy), DrawPixel(c.x + dx, c.y + dy), c])]
    }

  case .fibChannel:
    // 平行通道加刻度：0 是基线 A→B，1 是过 C 的那条平行线，中间按比例插值。
    guard let ch = offsetChannel(a, b, pts[2]) else { return g }
    for level in d.levels {
      let ox = -ch.dy * ch.f * level, oy = ch.dx * ch.f * level
      line(DrawPixel(a.x + ox, a.y + oy), DrawPixel(b.x + ox, b.y + oy), from: -.infinity, to: .infinity)
      g.labels.append(DrawLabel(point: DrawPixel(b.x + ox, b.y + oy - 3), text: String(format: "%.3g", level)))
    }
    if d.filled {
      let ox = -ch.dy * ch.f, oy = ch.dx * ch.f
      g.fills = [DrawFill(points: [a, b, DrawPixel(b.x + ox, b.y + oy), DrawPixel(a.x + ox, a.y + oy)])]
    }

  // ---------------------------------------------------------------- 几何

  case .ellipse:
    // 两点是外接矩形的对角。用 48 段折线近似：命中判定本来就按多边形算，
    // 画出来在 1px 以内也看不出是折线。
    let cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2
    let rx = abs(b.x - a.x) / 2, ry = abs(b.y - a.y) / 2
    guard rx > 0.5, ry > 0.5 else { return g }
    let ring = (0 ..< 48).map { i -> DrawPixel in
      let t = Double(i) / 48 * 2 * .pi
      return DrawPixel(cx + rx * cos(t), cy + ry * sin(t))
    }
    shape(ring)

  case .triangle:
    shape([a, b, pts[2]])

  case .curve:
    // 二次贝塞尔：A 起、C 控、B 止。同样切成折线。
    let c = pts[2]
    let ps = (0 ... 32).map { i -> DrawPixel in
      let t = Double(i) / 32, u = 1 - t
      return DrawPixel(u * u * a.x + 2 * u * t * c.x + t * t * b.x,
                       u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
    polyline(ps)

  case .datePriceRange:
    // 价格区间和日期区间合成一个框：一次说清「这段时间里走了多少」。
    let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
    let y0 = min(a.y, b.y), y1 = max(a.y, b.y)
    let corners = [DrawPixel(x0, y0), DrawPixel(x1, y0), DrawPixel(x1, y1), DrawPixel(x0, y1)]
    g.polygon = corners
    for i in corners.indices { line(corners[i], corners[(i + 1) % corners.count]) }
    let delta = d.points[1].p - d.a.p
    g.labels = [
      DrawLabel(point: DrawPixel(x1, y0 - 4),
                text: signedPrice(delta) + " · " + percent(d.a.p, d.points[1].p)),
      DrawLabel(point: DrawPixel(x1, y1 + 12), text: span(d.points[1].t - d.a.t)),
    ]

  // ---------------------------------------------------------------- 斐波那契

  case .fibTimeZone:
    // A→B 是一个「时间单位」，刻度是它的倍数，画成一排竖线。价格完全不参与。
    let unit = d.points[1].t - d.a.t
    guard abs(unit) > 0 else { return g }
    for level in d.levels {
      let x = xOf(d.a.t + unit * level)
      guard x.isFinite else { continue }
      line(DrawPixel(x, r.top), DrawPixel(x, r.bottom))
      g.labels.append(DrawLabel(point: DrawPixel(x, r.top + 14), text: String(format: "%.3g", level)))
    }

  case .fibFan:
    // 从 A 出发的一束射线，穿过 A→B 那个框右边上按比例分出来的点。
    for level in d.levels {
      let through = DrawPixel(b.x, a.y + (b.y - a.y) * level)
      line(a, through, to: .infinity)
      g.labels.append(DrawLabel(point: DrawPixel(b.x, through.y - 3), text: String(format: "%.3g", level)))
    }
    line(a, b)

  // ---------------------------------------------------------------- 江恩

  case .gannBox:
    // 一个框，横竖都按同一组比例切格。江恩看的是「价格和时间按同样的份数走」。
    let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
    let y0 = min(a.y, b.y), y1 = max(a.y, b.y)
    let corners = [DrawPixel(x0, y0), DrawPixel(x1, y0), DrawPixel(x1, y1), DrawPixel(x0, y1)]
    g.polygon = corners
    for i in corners.indices { line(corners[i], corners[(i + 1) % corners.count]) }
    for level in d.levels {
      let x = x0 + (x1 - x0) * level, y = y0 + (y1 - y0) * level
      line(DrawPixel(x, y0), DrawPixel(x, y1))
      line(DrawPixel(x0, y), DrawPixel(x1, y))
    }

  case .gannFan:
    // 一束从 A 出发的射线，斜率是 A→B 这个框的对角线斜率乘上倍数（1×1、1×2、2×1…）。
    let dx = b.x - a.x, dy = b.y - a.y
    guard abs(dx) > 1e-6 else { return g }
    for level in d.levels {
      line(a, DrawPixel(b.x, a.y + dy * level), to: .infinity)
    }
    line(a, b)

  // ---------------------------------------------------------------- 形态

  case .xabcd:
    polyline(pts); marks(pts, ["X", "A", "B", "C", "D"])
    if d.filled, pts.count >= 5 {
      g.fills = [DrawFill(points: [pts[0], pts[1], pts[2]]), DrawFill(points: [pts[2], pts[3], pts[4]])]
    }
  case .abcd:
    polyline(pts); marks(pts, ["A", "B", "C", "D"])
  case .headShoulders:
    polyline(pts); marks(pts, ["", "左肩", "", "头", "", "右肩", ""])
    // 颈线：第 2 和第 6 个点（两个谷）连起来往两头延伸，这才是形态的判定线。
    if pts.count >= 7 { line(pts[2], pts[4], from: -.infinity, to: .infinity) }
  case .elliottImpulse:
    polyline(pts); marks(pts, ["0", "1", "2", "3", "4", "5"])
  case .elliottCorrection:
    polyline(pts); marks(pts, ["0", "A", "B", "C"])

  // ---------------------------------------------------------------- 标注

  case .callout:
    // A 是要指的那个点，B 是气泡落在哪儿。指引线从气泡指回 A，箭头在 A 那头。
    line(b, a)
    arrowHead(at: a, from: b, size: 8)
    g.labels = [DrawLabel(point: DrawPixel(b.x, b.y - 4), text: d.text.isEmpty ? "点这里写字" : d.text)]

  case .priceLabel:
    // 只标一个价。和「文字标注」的区别是它写的不是人话，是那一点的价——
    // 价格会跟着端点走，不会因为拖过位置就说谎。
    g.labels = [DrawLabel(point: DrawPixel(a.x, a.y - 4), text: price(d.a.p))]

  case .flag:
    // 一根旗杆加一面小旗，钉在某一根 K 线上。旗面朝右，不遮住它自己站的那一根。
    line(DrawPixel(a.x, a.y), DrawPixel(a.x, a.y - 22))
    shape([DrawPixel(a.x, a.y - 22), DrawPixel(a.x + 16, a.y - 18), DrawPixel(a.x, a.y - 14)])
    if !d.text.isEmpty { g.labels = [DrawLabel(point: DrawPixel(a.x + 18, a.y - 12), text: d.text)] }

  case .markerUp:
    // 一个朝上的三角，钉在点的下方——它标的是「从这里往上」。
    shape([DrawPixel(a.x, a.y), DrawPixel(a.x - 6, a.y + 12), DrawPixel(a.x + 6, a.y + 12)], tint: .up)
  case .markerDown:
    shape([DrawPixel(a.x, a.y), DrawPixel(a.x - 6, a.y - 12), DrawPixel(a.x + 6, a.y - 12)], tint: .down)
  }
  return g
}
