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
    // ---- 第二批高级工具（2026-09-18）。加在末尾，老存档里没有它们，解码不受影响。
    case position, regression, fibExtension, priceRange, dateRange, note
    // ---- 全量对齐 TradingView 的工具面板（2026-09-18）。同样加在末尾。
    //
    // 口径：TV 那张面板逐项过一遍，默认全接；只剔掉手机上真的用不了的。剔掉的是
    // **点数不定、要一路自由手绘**的那四种——多边线、路径、画笔、荧光笔：它们靠鼠标
    // 连点 / 拖出来，手指在一块 390pt 宽的图上既点不准也收不了尾，而且一条线要存几百
    // 个点，同步和存档的量级跟别的工具不是一回事。点数固定的一律接进来了，形态类
    // （XABCD、ABCD、头肩、艾略特）只是点多，不是不可控。
    case crossLine, arrowLine
    case pitchfork, fibChannel
    case ellipse, triangle, curve, datePriceRange
    case fibTimeZone, fibFan
    case gannBox, gannFan
    case xabcd, abcd, headShoulders, elliottImpulse, elliottCorrection
    case callout, priceLabel, flag, markerUp, markerDown
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
      case .position: "多空持仓框"
      case .regression: "回归通道"
      case .fibExtension: "斐波那契扩展"
      case .priceRange: "价格区间"
      case .dateRange: "日期区间"
      case .note: "文字标注"
      case .crossLine: "十字线"
      case .arrowLine: "箭头"
      case .pitchfork: "安德鲁斯分叉"
      case .fibChannel: "斐波那契通道"
      case .ellipse: "椭圆"
      case .triangle: "三角形"
      case .curve: "曲线"
      case .datePriceRange: "日期价格区间"
      case .fibTimeZone: "斐波那契时区"
      case .fibFan: "斐波那契扇形"
      case .gannBox: "江恩箱"
      case .gannFan: "江恩扇形"
      case .xabcd: "XABCD 形态"
      case .abcd: "ABCD 形态"
      case .headShoulders: "头肩形态"
      case .elliottImpulse: "艾略特推动浪"
      case .elliottCorrection: "艾略特调整浪"
      case .callout: "气泡标注"
      case .priceLabel: "价格标签"
      case .flag: "旗标"
      case .markerUp: "向上箭头"
      case .markerDown: "向下箭头"
      }
    }
    public var shortTitle: String {
      switch self {
      case .fibonacci: "回撤"
      case .channel: "通道"
      case .measure: "测量"
      case .position: "持仓框"
      case .regression: "回归"
      case .fibExtension: "扩展"
      case .priceRange: "价区"
      case .dateRange: "日区"
      case .note: "文字"
      case .pitchfork: "分叉"
      case .fibChannel: "斐通道"
      case .datePriceRange: "价时区"
      case .fibTimeZone: "时区"
      case .fibFan: "扇形"
      case .gannBox: "江恩箱"
      case .gannFan: "江恩扇"
      case .xabcd: "XABCD"
      case .abcd: "ABCD"
      case .headShoulders: "头肩"
      case .elliottImpulse: "推动浪"
      case .elliottCorrection: "调整浪"
      case .callout: "气泡"
      case .priceLabel: "价签"
      case .markerUp: "上箭头"
      case .markerDown: "下箭头"
      default: title
      }
    }
    /// 存几个点。
    public var pointCount: Int {
      switch self {
      case .hline, .vline, .hray, .note, .crossLine, .priceLabel, .flag, .markerUp, .markerDown: 1
      case .channel, .regression, .position, .fibExtension, .pitchfork, .fibChannel, .triangle, .curve: 3
      case .abcd, .elliottCorrection: 4
      case .xabcd: 5
      case .elliottImpulse: 6
      case .headShoulders: 7
      default: 2
      }
    }
    /// 要在图上点几下。
    ///
    /// 绝大多数工具点几下就存几个点，只有「回归通道」是例外：用户只圈起止两点，
    /// 第三点（通道的宽度）是拿区间里的 K 线做最小二乘算出来的，不该也让用户去比划。
    /// 落点在 `ChartView+Drawing.placeDrawPoint` 里按这个数收口，回归那一步紧接着
    /// 由 `Drawing.fittedRegression(from:series:)` 把两点补成三点。
    public var placeCount: Int { self == .regression ? 2 : pointCount }
    /// 这把工具的出厂刻度。回撤是「退回去多少」，扩展是「再走出去多少」，两套数不一样。
    public var defaultLevels: [Double] {
      switch self {
      case .fibExtension: [0, 0.382, 0.618, 1, 1.618, 2.618]
      case .fibTimeZone: [0, 1, 2, 3, 5, 8]
      case .fibFan: [0.382, 0.5, 0.618]
      case .gannBox: [0.25, 0.382, 0.5, 0.618, 0.75]
      // 江恩扇的「刻度」是斜率倍数：1×1 是 1，1×2 是 2，2×1 是 0.5，以此类推。
      case .gannFan: [0.25, 0.333, 0.5, 1, 2, 3, 4]
      default: [0, 0.236, 0.382, 0.5, 0.618, 0.786, 1]
      }
    }
    /// 吃不吃 `levels`（样式表里那一栏刻度只对它们开）。
    public var usesLevels: Bool {
      switch self {
      case .fibonacci, .fibExtension, .fibChannel, .fibTimeZone, .fibFan, .gannBox, .gannFan: true
      default: false
      }
    }
    /// 画出来是「一块面」的那几种——样式表里的「背景填充」开关只对它们露出来。
    ///
    /// 「测量」不在里面：它的底色**就是结论**（涨=绿、跌=红），关掉底只剩四条边，
    /// 读不出方向，所以那个框恒亮、不给开关。注释从前写的是「测量已经不是一个框，
    /// 是两点之间的一条线」——那一版早就被推翻了（见 `DrawGeometry` 里 `.measure`
    /// 那段），现在它就是一个框。
    public var usesFill: Bool {
      switch self {
      case .rectangle, .channel, .regression, .position, .priceRange, .dateRange,
           .ellipse, .triangle, .datePriceRange, .gannBox, .pitchfork, .fibChannel,
           .xabcd, .callout, .flag, .markerUp, .markerDown: true
      default: false
      }
    }
    /// 带不带一段文字（`Drawing.text`）。目前只有「文字标注」。
    public var usesText: Bool { self == .note || self == .callout || self == .flag }
    public var group: String {
      switch self {
      case .hline, .trend, .ray, .hray, .extended, .vline, .crossLine, .arrowLine: "线条"
      case .channel, .regression, .pitchfork: "通道"
      case .rectangle, .ellipse, .triangle, .curve: "几何"
      case .priceRange, .dateRange, .datePriceRange: "区间"
      case .fibonacci, .fibExtension, .fibChannel, .fibTimeZone, .fibFan: "斐波那契"
      case .gannBox, .gannFan: "江恩"
      case .xabcd, .abcd, .headShoulders, .elliottImpulse, .elliottCorrection: "形态"
      case .measure, .position: "测量"
      case .note, .callout, .priceLabel, .flag, .markerUp, .markerDown: "标注"
      }
    }
    /// 分类在「绘图」面板那条标签上的排列顺序：由粗到细、由线到标注。
    public static let groups = ["线条", "通道", "几何", "区间", "斐波那契", "江恩", "形态", "测量", "标注"]
  }

  /// 拖的是哪一个端点；`body` 是整条一起走。
  ///
  /// 原来只有 `a / b / c`——那时候最多三个点。形态类（XABCD 五点、艾略特推动浪六点、
  /// 头肩七点）进来之后不够用了：拖不动的端点等于画错了只能删掉重画。这里补到八个，
  /// 名字继续用字母，`index` / `anchor(_:)` 负责和 `points` 的下标互转，
  /// 三处 `switch part` 全改成问 `index`，以后再加点数只要动这一行。
  public enum Part: String, Sendable, Equatable, CaseIterable {
    case a, b, c, d, e, f, g, h, body
    public static let anchors: [Part] = [.a, .b, .c, .d, .e, .f, .g, .h]
    /// 在 `points` 里的下标；`body` 没有下标。
    public var index: Int? { Part.anchors.firstIndex(of: self) }
    public static func anchor(_ i: Int) -> Part { anchors[min(max(i, 0), anchors.count - 1)] }
  }
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
  /// 「文字标注」写的那句话。别的工具一律空串。
  ///
  /// 上限 60 个字符：它是图上的一行小字，不是备忘录；再长也只会糊在 K 线上。
  public var text: String = ""
  public static let textLimit = 60
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
    self.id = id; self.kind = kind; self.points = points; self.levels = kind.defaultLevels
  }
  public static func newID() -> String { "d" + UUID().uuidString }
  public var prices: [Double] { points.map(\.p) }
  public var isValid: Bool {
    points.count == kind.pointCount && points.allSatisfy { $0.t.isFinite && $0.p.isFinite }
      && lineWidth.isFinite && (0.5...6).contains(lineWidth)
      && levels.count <= 24 && levels.allSatisfy { $0.isFinite && abs($0) <= 10 }
      && text.count <= Self.textLimit
  }
  private enum CodingKeys: String, CodingKey {
    case id, kind, points, a, b, color, lineWidth, dash, filled, locked, hidden, levels, text
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
    levels = try c.decodeIfPresent([Double].self, forKey: .levels) ?? kind.defaultLevels
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    guard isValid else { throw DecodingError.dataCorruptedError(forKey: .points, in: c, debugDescription: "Invalid drawing") }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(points, forKey: .points)
    try c.encodeIfPresent(color, forKey: .color); try c.encode(lineWidth, forKey: .lineWidth)
    try c.encode(dash, forKey: .dash); try c.encode(filled, forKey: .filled)
    try c.encode(locked, forKey: .locked); try c.encode(hidden, forKey: .hidden); try c.encode(levels, forKey: .levels)
    if !text.isEmpty { try c.encode(text, forKey: .text) }
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
    let index = part.index
    for j in items[i].points.indices where (index == nil || j == index) && start.points.indices.contains(j) {
      items[i].points[j] = DrawPoint(t: start.points[j].t + dt, p: start.points[j].p + dp)
    }
  }

  /// 所有画线端点的价格，喂给 `priceRange`。
  public var prices: [Double] { items.flatMap(\.prices) }
}
