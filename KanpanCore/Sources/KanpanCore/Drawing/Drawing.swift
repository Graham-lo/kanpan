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
    // ---- 计算型工具（2026-09-20）：形状不由锚点几何决定，由锚点圈住的 K 线算出来。
    // 同样加在末尾，老存档里没有它们，解码不受影响。
    case anchoredVWAP, fixedVolumeProfile, anchoredVolumeProfile
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
      // 名字就叫「VWAP」：TV 那把叫「锚定 VWAP」，可这里的 VWAP 本来就只有锚定这一种
      // （没有「当日 VWAP」那种指标版），前面两个字对用户不传达任何信息。
      case .anchoredVWAP: "VWAP"
      case .fixedVolumeProfile: "区间成交量分布"
      case .anchoredVolumeProfile: "锚定成交量分布"
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
      case .fixedVolumeProfile: "区间量分布"
      case .anchoredVolumeProfile: "锚定量分布"
      default: title
      }
    }
    /// 存几个点。
    public var pointCount: Int {
      switch self {
      case .hline, .vline, .hray, .note, .crossLine, .priceLabel, .flag, .markerUp, .markerDown,
           .anchoredVWAP, .anchoredVolumeProfile: 1
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
    /// 形状要拿 K 线算出来的那几把——几何函数必须拿到 `BarSeries` 才画得出东西。
    ///
    /// 别的工具画什么完全由锚点的 (t, p) 决定，缩放一下只是换个像素位置；这三把的锚点
    /// 只说「从哪一根算到哪一根」，线在哪、柱子多长得先把那一段 K 线扫一遍。所以几何、
    /// 绘制、命中三处都按它分流：拿不到序列时只出手柄，不画一条假的形状出来。
    public var isComputed: Bool {
      self == .anchoredVWAP || self == .fixedVolumeProfile || self == .anchoredVolumeProfile
    }
    /// 带不带一段文字（`Drawing.text`）。目前只有「文字标注」。
    public var usesText: Bool { self == .note || self == .callout || self == .flag }

    /// 「绘图」面板上摆出来的那 12 把。
    ///
    /// 枚举里的 41 种一个都没删：老存档、云端已有的线、下面那张「换一种画法」的表
    /// 都还要认它们，删一个 case 等于把用户画过的那些线在解码时悄悄丢掉
    /// （`DrawArchive.init(from:)` 遇到不认识的 kind 就是丢）。面板上摆什么是另一回事。
    ///
    /// 2026-09-22 用户定的：「有些华而不实的用的少的其实没必要实现」。41 把是照
    /// TradingView 全量接进来的，其中江恩、艾略特、XABCD、头肩、分叉、斐波那契扇形/时区、
    /// 椭圆、三角形、曲线这些，在手机上画得出来也没人画；矩形被他点名去掉。剩下的
    /// 射线 / 水平射线 / 直线 / 箭头 / 十字线 / 价格区间 / 日期区间 / 气泡 / 旗标 / 价格标签
    /// 不是没用，而是和主工具形状一样、只差一处画法——它们退到样式表里去换（见 `swaps`），
    /// 不再在面板上各占一格。
    ///
    /// 顺序就是面板上从左到右、从上到下的顺序：先四把日常画的线，再两把斐波那契，
    /// 然后测量与标注，最后三把要拿 K 线算的和一把持仓框。
    public static let palette: [Kind] = [
      .hline, .trend, .vline, .channel,
      .fibonacci, .fibExtension, .measure, .note,
      .anchoredVWAP, .fixedVolumeProfile, .anchoredVolumeProfile, .position,
    ]

    /// 样式表里的「换一种画法」。
    ///
    /// 同一族里形状一模一样，差的只是往哪边延伸、端点画不画箭头。做成面板上的独立格子，
    /// 用户得先认识「射线」「直线」「水平射线」三个名字才知道点哪个；做成画完之后在样式表里
    /// 换一下，他是看着图上那条线做决定的，不用先学名字。
    ///
    /// 一族只给一排，不拆成「延伸」和「端点」两排：拆开之后选了箭头就没有延伸可言，
    /// 两排会互相把对方的选中项顶掉，而且换一下就有一排凭空消失。
    ///
    /// **同一族里 `pointCount` 必须相同**：`Drawing.isValid` 要求点数和 kind 对得上，
    /// 换完点数不对，`DrawingController.update` 会把这次修改整条丢掉，而且不报错
    /// （见 `ChartView+Drawing.updateDrawing` 那句 `guard item.isValid`）。
    /// `swapsKeepTheirPointCount` 守这条。
    public var swaps: [KindSwap] {
      switch self {
      case .hline, .hray:
        [KindSwap(title: "画法", options: [.init("整条", .hline), .init("向右", .hray)])]
      case .trend, .ray, .extended, .arrowLine:
        [KindSwap(title: "画法", options: [
          .init("线段", .trend), .init("向右延伸", .ray),
          .init("两端延伸", .extended), .init("箭头", .arrowLine),
        ])]
      case .vline, .crossLine:
        [KindSwap(title: "画法", options: [.init("垂直线", .vline), .init("十字线", .crossLine)])]
      default: []
      }
    }
  }

  /// 样式表里一排「换一种画法」的按钮。
  public struct KindSwap: Sendable, Equatable, Identifiable {
    public struct Option: Sendable, Equatable, Identifiable {
      public let label: String
      public let kind: Kind
      public var id: String { kind.rawValue }
      public init(_ label: String, _ kind: Kind) {
        self.label = label
        self.kind = kind
      }
    }
    public let title: String
    public let options: [Option]
    public var id: String { title }
    public init(title: String, options: [Option]) {
      self.title = title
      self.options = options
    }
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
  ///
  /// **60 是排版上限，不是线协议上限。** 数的是 Swift `Character`（字素簇），
  /// 服务端只能按 UTF-8 字节数卡——两者换不出同一个数（11 个家庭组合 emoji 是
  /// 11 个 `Character`、275 字节）。所以服务端那条线是「宽松的防滥用上限」，
  /// 由这里说了算多长才好看；别拿字节数反过来把这个 60 改小。
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
    // 带文字的工具（`kind.usesText`：文字标注 / 标注框 / 旗标）**总是**写 `text`，空就写 `""`。
    //
    // 从前是「空就整个省略这个键」，而同步那一层是拿前后两份 body 做差分的
    // （`SyncStore.stage`）：一个先前有、现在没有的键会被翻译成 `text: null`，
    // 意思是「删掉这个字段」。服务端的 null 白名单里没有 `drawings.text`，
    // 于是「把标注文字清空」——一个再普通不过的动作——会让整条操作 400 被顶回来，
    // 隔离之后云端那份旧文字还会被写回来，用户删掉的字又冒出来了。
    // 空字符串本来就是个合法值，照原样发上去，差分那一层就不会再去发明一个 null。
    //
    // 不带文字的工具（线、通道、斐波那契……）`text` 恒为空、用户也改不到它，继续省略：
    // 给每一条线都塞一个 `"text":""` 只会让存档和线上白白多一个字段和一份字段时间戳。
    // `|| !text.isEmpty` 是给老存档兜底——真有非空文字就别在重新编码时弄丢。
    if kind.usesText || !text.isEmpty { try c.encode(text, forKey: .text) }
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
