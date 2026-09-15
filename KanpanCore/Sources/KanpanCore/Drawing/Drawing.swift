import Foundation

/// 画线模型；兼容第一版水平线与趋势线存档。
///
/// 端点存的是**时间 + 价格**，不是像素——缩放、换周期、切对数轴之后线还在原来的
/// 位置上。命中判定的三个阈值（手柄 12、线身 9、水平线 9）照抄原型。

/// 一个端点。
public struct DrawPoint: Sendable, Equatable, Codable {
  /// 毫秒时间戳。
  public var t: Double
  /// 价格。
  public var p: Double

  public init(t: Double, p: Double) {
    self.t = t
    self.p = p
  }
}

public struct Drawing: Sendable, Equatable, Identifiable, Codable {
  public enum Kind: String, Sendable, Codable, CaseIterable, Identifiable {
    case hline, trend, ray, hray, extended, vline, rectangle, channel, fibonacci, measure
    public var id: String { rawValue }
    public var title: String {
      switch self {
      case .hline: "水平线"
      case .trend: "趋势线"
      case .ray: "射线"
      case .hray: "水平射线"
      case .extended: "直线"
      case .vline: "垂直线"
      case .rectangle: "矩形"
      case .channel: "平行通道"
      case .fibonacci: "斐波那契回撤"
      case .measure: "价时测量"
      }
    }
    public var shortTitle: String {
      switch self { case .fibonacci: "回撤"; case .channel: "通道"; case .measure: "测量"; default: title }
    }
    public var pointCount: Int {
      switch self {
      case .hline, .vline, .hray: 1
      case .channel: 3
      default: 2
      }
    }
    public var group: String {
      switch self {
      case .hline, .trend, .ray, .hray, .extended, .vline: "线条"
      case .rectangle, .channel: "区域"
      case .fibonacci: "斐波那契"
      case .measure: "测量"
      }
    }
  }
  public enum Part: String, Sendable, Equatable { case a, b, c, body }
  public enum Dash: String, Sendable, Codable, CaseIterable {
    case solid, dashed, dotted
    public var title: String {
      switch self { case .solid: "实线"; case .dashed: "虚线"; case .dotted: "点线" }
    }
  }
  public var id: String
  public var kind: Kind
  /// Only time and price are persisted. Pixel geometry is derived for each viewport.
  public var points: [DrawPoint]
  public var color: Hex?
  public var lineWidth: Double = 1.3
  public var dash: Dash = .solid
  public var filled = true
  public var locked = false
  public var hidden = false
  public var levels: [Double] = [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
  public var a: DrawPoint {
    get { points.first ?? DrawPoint(t: 0, p: 0) }
    set { if points.isEmpty { points = [newValue] } else { points[0] = newValue } }
  }
  public var b: DrawPoint? {
    get { points.count > 1 ? points[1] : nil }
    set {
      if let newValue { if points.count > 1 { points[1] = newValue } else { points.append(newValue) } }
      else if points.count > 1 { points.removeSubrange(1...) }
    }
  }
  public init(id: String = Drawing.newID(), kind: Kind, a: DrawPoint, b: DrawPoint? = nil, color: Hex? = nil) {
    self.id = id; self.kind = kind; self.points = [a] + (b.map { [$0] } ?? []); self.color = color
  }
  public init(id: String = Drawing.newID(), kind: Kind, points: [DrawPoint]) {
    self.id = id; self.kind = kind; self.points = points
  }
  public static func newID() -> String { "d" + UUID().uuidString }
  public var prices: [Double] { points.map(\.p) }
  public var isValid: Bool {
    points.count == kind.pointCount && points.allSatisfy { $0.t.isFinite && $0.p.isFinite }
      && lineWidth.isFinite && (0.5...6).contains(lineWidth)
      && levels.count <= 24 && levels.allSatisfy { $0.isFinite && abs($0) <= 10 }
  }
  private enum CodingKeys: String, CodingKey {
    case id, kind, points, a, b, color, lineWidth, dash, filled, locked, hidden, levels
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    kind = try c.decode(Kind.self, forKey: .kind)
    if let pts = try c.decodeIfPresent([DrawPoint].self, forKey: .points) { points = pts }
    else {
      points = [try c.decode(DrawPoint.self, forKey: .a)]
      if let b = try c.decodeIfPresent(DrawPoint.self, forKey: .b) { points.append(b) }
    }
    color = try c.decodeIfPresent(Hex.self, forKey: .color)
    lineWidth = try c.decodeIfPresent(Double.self, forKey: .lineWidth) ?? 1.3
    dash = try c.decodeIfPresent(Dash.self, forKey: .dash) ?? .solid
    filled = try c.decodeIfPresent(Bool.self, forKey: .filled) ?? true
    locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    levels = try c.decodeIfPresent([Double].self, forKey: .levels) ?? [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "Invalid drawing") }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(points, forKey: .points)
    try c.encodeIfPresent(color, forKey: .color); try c.encode(lineWidth, forKey: .lineWidth)
    try c.encode(dash, forKey: .dash); try c.encode(filled, forKey: .filled)
    try c.encode(locked, forKey: .locked); try c.encode(hidden, forKey: .hidden); try c.encode(levels, forKey: .levels)
  }
}

/// 命中结果。
public struct DrawHit: Sendable, Equatable {
  public init(id: String, part: Drawing.Part) { self.id = id; self.part = part }
  public var id: String
  public var part: Drawing.Part
}

/// 点到线段的距离（原型 `distSeg`）。
public func distSeg(_ px: Double, _ py: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
  let dx = x2 - x1, dy = y2 - y1
  let len = dx * dx + dy * dy
  var t = len != 0 ? ((px - x1) * dx + (py - y1) * dy) / len : 0
  t = max(0, min(1, t))
  return ((px - (x1 + t * dx)) * (px - (x1 + t * dx)) + (py - (y1 + t * dy)) * (py - (y1 + t * dy))).squareRoot()
}

/// 画线集合的命中判定。从最后一条往前找——后画的在上面。
///
/// `xOf` / `yOf` 由调用方给：时间→x、价格→y，Core 不知道 pane 长什么样。
public func hitDraw(
  _ draws: [Drawing], px: Double, py: Double,
  xOf: (Double) -> Double, yOf: (Double) -> Double
) -> DrawHit? {
  for d in draws.reversed() where !d.hidden {
    if d.kind == .hline {
      if abs(yOf(d.a.p) - py) < Chart.hitLinePt { return DrawHit(id: d.id, part: .body) }
      continue
    }
    let geometry = drawingGeometry(d, bounds: DrawBounds(left: -1e9, top: -1e9, right: 1e9, bottom: 1e9), xOf: xOf, yOf: yOf)
    if let part = geometry.hit(x: px, y: py) { return DrawHit(id: d.id, part: part) }
  }
  return nil
}

/// 画线的编辑状态：待落的第二点、选中项、当前工具。
public struct DrawingStore: Sendable, Equatable {
  public typealias Tool = Drawing.Kind

  public var items: [Drawing] = []
  public var selected: String?
  /// 趋势线落了第一点、还差第二点。
  public var anchors: [DrawPoint] = []
  public var pending: DrawPoint? {
    get { anchors.first }
    set { anchors = newValue.map { [$0] } ?? [] }
  }
  public var tool: Tool?
  /// 吸附到 K 线中心。
  public var magnet = true

  public init() {}

  /// 落一个点。趋势线要落两次。
  public mutating func place(_ pt: DrawPoint, id: String = Drawing.newID()) {
    guard let tool else { return }
    anchors.append(pt)
    if anchors.count == tool.pointCount {
      items.append(Drawing(id: id, kind: tool, points: anchors))
      anchors = []; self.tool = nil
    }
  }

  public mutating func removeSelected() {
    guard let sel = selected else { return }
    items.removeAll { $0.id == sel }
    selected = nil
  }

  public mutating func clear() {
    items = []
    selected = nil
    pending = nil
  }

  /// 拖动：`part` 决定动哪一端，`body` 两端一起走。
  public mutating func move(id: String, part: Drawing.Part, from start: Drawing, dt: Double, dp: Double) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    guard !items[i].locked else { return }
    let index: Int? = switch part { case .a: 0; case .b: 1; case .c: 2; case .body: nil }
    for j in items[i].points.indices where (index == nil || j == index) && start.points.indices.contains(j) {
      items[i].points[j] = DrawPoint(t: start.points[j].t + dt, p: start.points[j].p + dp)
    }
  }

  /// 所有画线端点的价格，喂给 `priceRange`。
  public var prices: [Double] { items.flatMap(\.prices) }
}
