import Foundation

/// 一条提醒。
///
/// 这是**线上那份对象的身体**：字段名、取值范围、可空与否，都按
/// `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 表 2.2 一字不差地来，服务端
/// （`Backend/kanpan-api/src/sync_validation.rs`）按同一张表逐字段卡，改这里的任何
/// 一个名字都要两边一起改，否则整条操作会被拒、队列跟着堵。
///
/// `id` 是**本地 id**，不进身体：上行时它被拼进对象 id（`binance/usd_m/<代号>/<id>`），
/// 由 `PersonalSyncCodec` 负责拆装，和画线那一套完全一样。
public struct Alert: Sendable, Equatable, Codable, Identifiable {
  /// 这条提醒是怎么来的。
  ///
  /// - `drawing`：画完线那一下问一句建出来的；`lines` 是那条线摊平的几何。
  /// - `price`：提醒总表右上「新建」建出来的裸价格提醒。目标价挂成一条两端都延的
  ///   水平线（`lines` 只有一个点），所以判定和画线提醒走的是同一套几何、同一份规则，
  ///   两侧评估器（`AlertEvaluator` / 服务端 `alerts.rs`）都认它。
  /// - `reviewDue`：复盘待办到期。由复盘记录生成（`ReviewDueAlerts`），`dueAt` 是记录的
  ///   到期时刻、`reviewID` 是记录 id、`lines` 为空；服务端到点把它置成 `fired` 并推送，
  ///   本机另排一条本地通知当双保险。记录判完 / 作废 / 删掉之后自动清掉。
  ///
  /// 自选五分钟波动不在这里：它不是一条条提醒对象，是 `settings/chart` 里的开关与阈值
  /// （`watchMoveAlert` / `watchMoveThreshold`），判定在 `WatchMove` / 服务端 `watch_move.rs`。
  /// 规格见 docs/待办交接-Codex-2026-09-22.md P3.1。
  public enum Kind: String, Sendable, Codable, CaseIterable {
    case drawing, price, reviewDue
  }

  /// 怎么算「穿过」。
  ///
  /// - `touch`：这一根的最高最低夹住了线（出厂值）。盘中就算。
  /// - `close`：这一根**真的收了**（币安 kline 帧的 `k.x`），而且上一根的收盘价与
  ///   这一根的收盘价分在线的两侧（正好收在线上也算穿过）才响。盘中来回穿不算。
  ///   两侧都判：前台 `AlertEvaluator`、服务端 `alerts.rs`。切换的口子在提醒列表那一行上。
  public enum Condition: String, Sendable, Codable, CaseIterable {
    case touch, close
    public var title: String { self == .touch ? "碰到" : "收盘穿过" }
  }

  public enum Status: String, Sendable, Codable, CaseIterable {
    case active, fired, paused
    public var title: String {
      switch self { case .active: "生效中"; case .fired: "已触发"; case .paused: "已暂停" }
    }
  }

  /// 本地 id。上行时拼进对象 id，不进身体。
  public var id: String
  public var kind: Kind
  public var symbol: String
  /// 目前只有一个市场，服务端按整串卡死 `binance/usd_m`。
  public var market: String
  /// `kind == .drawing` 时必有，且非空（服务端会卡）。
  public var drawingID: String?
  /// 摊平之后的几条线。画线的形状（通道两条边、回撤每一级一条）到这儿已经不见了，
  /// 剩下的只是「一串点 + 两端延不延」，前台和服务端拿同一份几何判。
  public var lines: [AlertLine]
  public var condition: Condition
  /// 从这个时刻起才算数（毫秒）。线被挪动之后要重置成「现在」，否则挪过去的那一刻
  /// 就被历史 K 线判成触发了。
  public var armedAt: Double
  /// `true` 时只响一次；关闭后按现有再次提醒规则重新布防。
  public var once: Bool
  public var status: Status
  public var firedAt: Double?
  public var firedPrice: Double?
  /// `kind == .reviewDue` 用的到点时刻（毫秒）。
  public var dueAt: Double?
  public var reviewID: String?
  /// 通知正文的第一句，客户端生成的中文（「BTC 触到你画的趋势线」）。
  /// 服务端只负责原样发出去，不认识中文也不该去拼。
  public var title: String
  public var created: Double

  public init(id: String = Alert.newID(), kind: Kind = .drawing, symbol: String,
              market: String = Alert.market, drawingID: String? = nil,
              lines: [AlertLine] = [], condition: Condition = .touch,
              armedAt: Double, once: Bool = true, status: Status = .active,
              firedAt: Double? = nil, firedPrice: Double? = nil,
              dueAt: Double? = nil, reviewID: String? = nil,
              title: String, created: Double) {
    self.id = id; self.kind = kind; self.symbol = InstrumentID.canonical(symbol.contains("/") ? symbol : market + "/" + symbol); self.market = InstrumentID(self.symbol).marketKey
    self.drawingID = drawingID; self.lines = lines; self.condition = condition
    self.armedAt = armedAt; self.once = once; self.status = status
    self.firedAt = firedAt; self.firedPrice = firedPrice
    self.dueAt = dueAt; self.reviewID = reviewID; self.title = title; self.created = created
  }

  // ---------------------------------------------------------------- 线协议

  private enum CodingKeys: String, CodingKey {
    case id, kind, symbol, market, drawingID, lines, condition, armedAt, once
    case status, firedAt, firedPrice, dueAt, reviewID, title, created
  }

  /// **可空的那五个永远写出来，空就写 null**，不许省略。
  ///
  /// 理由和画线那条 `text` 一模一样（见 `PersonalSyncCodec.drawings` 的注释）：
  /// `SyncStore.stage` 是拿前后两份 body 逐键做差分的，一个「先前有、现在没有」的键会被
  /// 翻译成删除。省略和 null 在这儿不是一回事——省略会让「用户把触发记录清掉」这种改动
  /// 时有时无。服务端的 null 白名单正好放行这五个（`drawingID` / `firedAt` /
  /// `firedPrice` / `dueAt` / `reviewID`），别的键一个 null 都不许发。
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(kind, forKey: .kind)
    try c.encode(InstrumentID(symbol).symbol, forKey: .symbol)
    try c.encode(market, forKey: .market)
    try c.encode(drawingID, forKey: .drawingID)
    try c.encode(lines, forKey: .lines)
    try c.encode(condition, forKey: .condition)
    try c.encode(armedAt, forKey: .armedAt)
    try c.encode(once, forKey: .once)
    try c.encode(status, forKey: .status)
    try c.encode(firedAt, forKey: .firedAt)
    try c.encode(firedPrice, forKey: .firedPrice)
    try c.encode(dueAt, forKey: .dueAt)
    try c.encode(reviewID, forKey: .reviewID)
    try c.encode(title, forKey: .title)
    try c.encode(created, forKey: .created)
  }

  /// 解码一律给得起兜底：从云端换下来的那份可能是别的版本写的，少一个键不该整条读不出来。
  /// 认不得的 `kind` / `condition` / `status` 退回出厂值，而不是把整条提醒丢掉。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? Alert.newID()
    kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) .flatMap { $0 } ?? .drawing
    symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ""
    market = try c.decodeIfPresent(String.self, forKey: .market) ?? Alert.market
    symbol = InstrumentID.canonical(symbol.contains("/") ? symbol : market + "/" + symbol)
    drawingID = try c.decodeIfPresent(String.self, forKey: .drawingID)
    lines = try c.decodeIfPresent([AlertLine].self, forKey: .lines) ?? []
    condition = (try? c.decodeIfPresent(Condition.self, forKey: .condition)).flatMap { $0 } ?? .touch
    armedAt = try c.decodeIfPresent(Double.self, forKey: .armedAt) ?? 0
    once = try c.decodeIfPresent(Bool.self, forKey: .once) ?? true
    status = (try? c.decodeIfPresent(Status.self, forKey: .status)).flatMap { $0 } ?? .active
    firedAt = try c.decodeIfPresent(Double.self, forKey: .firedAt)
    firedPrice = try c.decodeIfPresent(Double.self, forKey: .firedPrice)
    dueAt = try c.decodeIfPresent(Double.self, forKey: .dueAt)
    reviewID = try c.decodeIfPresent(String.self, forKey: .reviewID)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    created = try c.decodeIfPresent(Double.self, forKey: .created) ?? 0
  }

  public static let market = "binance/usd_m"
  public static func newID() -> String { "a" + UUID().uuidString }

  /// 还在等的那些。列表的排序、前台评估、自选页的「离提醒线最近」都只看这一种。
  public var isActive: Bool { status == .active }

  /// 通知正文那句话。图上那条线用「触到你画的<线名>」，裸价格用「到了 <价>」。
  ///
  /// 代号只取 base（`BTCUSDT` → `BTC`）：通知栏一行字很短，后面那个 `USDT`
  /// 对用户不传达任何东西。别家带分隔的代号写全（`BTC/USD`），见 `name(of:)`。
  public static func title(symbol: String, drawingKind: Drawing.Kind) -> String {
    "\(name(of: symbol)) \(titleMarker)\(drawingKind.title)"
  }

  /// 整句里「线名」前面那一截。列表要的是线名，通知要的是整句，两边共用这一个记号，
  /// 免得哪天改了文案，列表那边悄悄开始显示空白。
  public static let titleMarker = "触到你画的"

  /// 这条提醒挂在哪一种线上（「水平线」「趋势线」…）。裸价格提醒没有，返回 nil。
  ///
  /// 线种不在同步字段里——协议那 15 个名字是和服务端对死的，不能为了列表多加一个。
  /// 它本来就已经在 `title` 里了，这儿把它取回来，而不是再存一份可能对不上的。
  public var lineName: String? {
    guard let range = title.range(of: Alert.titleMarker) else { return nil }
    let name = String(title[range.upperBound...])
    return name.isEmpty ? nil : Self.legacyLineNames[name] ?? name
  }

  /// 2026-09-23 之前线名跟样式表按钮不是一个叫法。老提醒的 `title` 是同步字段、原样留着，
  /// 显示时换成现在的名字，免得列表里同一种线出现两个名字。
  static let legacyLineNames = ["射线": "向右延伸", "水平射线": "向右延伸", "直线": "两端延伸"]

  /// 裸价格提醒那一条水平线的价。别的种类返回 nil。
  public var targetPrice: Double? {
    guard kind == .price else { return nil }
    return lines.first?.points.first?.p
  }

  /// 建一条裸价格提醒。目标价挂成一条两端都延的水平线——和画线里的水平线摊出来的
  /// 几何一模一样，评估器与服务端不需要为它多认一种形状。
  ///
  /// 方向不存：它由建的那一刻的现价决定（高于现价就是「涨到」、低于就是「跌到」），
  /// 只体现在标题里。判定按 `touch`：价格走到那条线上就响，从哪边来都一样。
  public static func price(symbol: String, target: Double, current: Double?, label: String,
                           now: Double) -> Alert {
    let line = AlertLine(points: [DrawPoint(t: now, p: target)], extendLeft: true, extendRight: true)
    return Alert(kind: .price, symbol: symbol, lines: [line], condition: .touch, armedAt: now,
                 title: priceTitle(symbol: symbol, target: target, current: current, label: label),
                 created: now)
  }

  /// 「BTC 涨到 65,000」/「BTC 跌到 60,000」。`label` 是调用方按品种精度排好的价。
  /// 现价取不到时不猜方向，写「到了」。
  public static func priceTitle(symbol: String, target: Double, current: Double?, label: String) -> String {
    let verb: String
    if let current, current.isFinite, current > 0 { verb = target >= current ? "涨到" : "跌到" } else { verb = "到了" }
    return "\(name(of: symbol)) \(verb) \(label)"
  }

  public static func base(of symbol: String) -> String {
    SymbolInfo.placeholder(symbol: symbol).base
  }

  /// 提醒文案里写给人看的品种名。币安那种连写的代号只写基础币（`BTCUSDT` → `BTC`）；
  /// 代号本身带分隔的（别家现货 `coinbase/spot/BTC-USD`）写成 `BTC/USD`——和自选行同一条
  /// 规矩，只写「BTC」就和币安那只 BTC 永续的提醒分不出来了。绝不露完整品种 key。
  public static func name(of symbol: String) -> String {
    let id = InstrumentID(symbol)
    return id.symbol.contains("-") ? id.display : base(of: symbol)
  }
}

/// 摊平之后的一条线：一串点，两端延不延。
///
/// 三个键就是三个键——服务端对 `lines` 里的每个元素要求**恰好** `points` /
/// `extendLeft` / `extendRight`，多一个少一个整条操作被拒。同理点只有 `t` / `p`，
/// 所以这里直接复用 `DrawPoint`（它的 Codable 正好只有这两个键）。
public struct AlertLine: Sendable, Equatable, Codable {
  public var points: [DrawPoint]
  public var extendLeft: Bool
  public var extendRight: Bool

  public init(points: [DrawPoint], extendLeft: Bool = false, extendRight: Bool = false) {
    self.points = points; self.extendLeft = extendLeft; self.extendRight = extendRight
  }

  /// 这条线在某个时刻的价格；这个时刻落在线外（而且那一头没延长）时返回 nil。
  ///
  /// 中间按相邻两点线性插值，两端按最靠边的那一段的斜率外推。一个点的线
  /// （水平线、水平射线、十字线）就是一条水平线，延到哪算到哪。
  public func price(at t: Double) -> Double? {
    let pts = points.sorted { $0.t < $1.t }
    guard let first = pts.first, let last = pts.last else { return nil }
    if pts.count == 1 {
      if t < first.t { return extendLeft ? first.p : nil }
      if t > first.t { return extendRight ? first.p : nil }
      return first.p
    }
    if t < first.t {
      guard extendLeft else { return nil }
      return extrapolate(from: pts[1], through: pts[0], at: t)
    }
    if t > last.t {
      guard extendRight else { return nil }
      return extrapolate(from: pts[pts.count - 2], through: last, at: t)
    }
    for i in 0..<(pts.count - 1) {
      let a = pts[i], b = pts[i + 1]
      guard t >= a.t, t <= b.t else { continue }
      let span = b.t - a.t
      // 两点同一时刻：那是一段竖直的边，价格取不出唯一值，按靠后那个点算。
      guard span > 0 else { return b.p }
      return a.p + (b.p - a.p) * (t - a.t) / span
    }
    return last.p
  }

  private func extrapolate(from a: DrawPoint, through b: DrawPoint, at t: Double) -> Double {
    let span = b.t - a.t
    guard span != 0 else { return b.p }
    return b.p + (b.p - a.p) * (t - b.t) / span
  }

  /// 这条线在某个时刻横跨的价格区间；插值取不到就是 nil。
  /// 现在只有一个点的结果，留着给「一根 K 线横跨好几段」的以后用。
  public func priceRange(at t: Double) -> ClosedRange<Double>? {
    guard let p = price(at: t) else { return nil }
    return p...p
  }
}
