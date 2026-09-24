import Foundation

// 主力订单流 · 逐单模型（照 CoinAnk「主力大额挂单」）。
//
// 一条大单 = 某家交易所 × 某个产品 × 某一侧 × 某个价格桶（按步长分桶）上的挂单，这一桶的美元名义
// ≥ 该产品的门槛就算。除了门槛没有别的过滤（不看利用率、邻居中位数、单家倍数）。
//
// - 出现 / 消失：各要连续两次评估、首尾相隔 ≥ 300 ms 才算（`OrderFlowDefaults.confirmation*`）。
//   出现要 ≥ 门槛，出现之后跌到门槛 × 0.5 以下才算消失（`OrderFlowDefaults.exitRatio`，退出滞回）。
//   出现时刻记第一次过门槛那一拍，结束时刻记第一次跌破那一拍。
// - 成交：只认同一本簿（同一个 `venueID`）自己的逐笔——打到这一侧这个桶，记进这本簿这个桶上还挂着的
//   那一单（以及正在确认的候选）。别家、别的产品的成交不记：交割、现货、永续之间有基差（季度合约常见
//   0.5–2%，远大于 BTC 100 美元的步长），同一个绝对价位在不同的簿里离现价远近不同；几家同桶都有墙时，
//   跨家记还会把同一笔成交重复算好几次，「已成交」因此偏多。
// - 结束：累计成交 ≥ 消失掉的名义（跌破退出线前最后一拍的名义 − 结束时剩下的）× 0.8 记「已成交」，
//   否则「已撤销」（理由见 `OrderFlowDefaults.filledRatio`）。透明度与读数里的成交比例用同一个分母。
// - 历史：结束的大单留在图上，3 天、最多 2 万条（`OrderFlowDefaults.retentionMs / maxEndedOrders`），
//   超了先挤活得短的；还挂着的永远不删。
// - 服务端历史：kanpan-api 常驻跟踪、存 3 天，取回来的一页由 `mergeHistory` 并进来（规则见那里）。
// - 落盘：`OrderFlowJournal`，一只品种一份小文件（KanpanData 管读写），只存最近 24 小时、最多 5000 条
//   （`journal(nowMs:)`），切回来、进程重启、断网时历史还在；更早的每次向服务端取，不落盘；不同步。
// - 簿断了：没就绪的那本簿这一拍不参与（它的单既不新增也不结束）；断开超过 2 分钟，它还挂着的单
//   按最后一次看到的时刻结束（`staleMs`），状态记「失联结束」（`.lost`）——那一刻之后发生了什么不知道，
//   不能判成撤单。
// - 读回：日志里挂着的单，如果存盘之后已经过了 `staleMs` 才再打开，第一次评估时一律按存盘时刻失联结束；
//   那个桶此刻还过门槛的话，按正常确认当成一条新出现的单（不把缺席的那几个小时画成一直挂着）。
//
// 交易所帧由 KanpanNetwork 的适配器解成 `DepthMessage` 喂进来，连接、快照拉取、节流与落盘由
// KanpanData 的 OrderFlowFeed 管。图表与 app 只看得到 `OrderFlowSnapshot`。

/// 一条大单。
public struct BigOrder: Sendable, Equatable, Identifiable, Codable {
  /// `lost`：簿断开太久（或读回时缺席太久），按最后一次看到的时刻结束——之后是成交还是撤单不知道。
  public enum Status: String, Sendable, Codable { case live, filled, cancelled, lost }

  /// 哪本簿（`OrderFlowVenue.id`）。
  public var venueID: String
  /// 交易所显示名（「币安」）。
  public var exchange: String
  public var product: OrderFlowProduct
  public var side: BookSide
  /// 价格桶号（`BucketScheme.index`）。
  public var bucket: Int64
  /// 桶里名义最大的那一档的价；图上画在这个价上。
  public var price: Double
  public var firstSeenMs: Int64
  public var endMs: Int64?
  public var status: Status
  /// 首次过门槛时的名义（美元）。
  public var initialNotional: Double
  /// 此刻的名义；结束了就是结束前最后一次过门槛时的名义。
  public var notional: Double
  /// 出现以来打到这一侧这个桶的主动成交（美元，只算这本簿自己的逐笔）。
  public var filledNotional: Double
  /// 这一单所属产品此刻的门槛（画厚度用）。
  public var threshold: Double
  /// 结束时消失掉的名义：跌破退出线前最后一拍的名义 − 结束时桶里还剩的。已成交 / 已撤销的判定与
  /// 成交比例都拿它当分母；挂着的单是 nil。旧版日志里没有这一项，读回来按 `notional` 算。
  public var vanishedNotional: Double?

  public init(venueID: String, exchange: String, product: OrderFlowProduct, side: BookSide, bucket: Int64,
              price: Double, firstSeenMs: Int64, endMs: Int64? = nil, status: Status = .live,
              initialNotional: Double, notional: Double, filledNotional: Double = 0, threshold: Double,
              vanishedNotional: Double? = nil) {
    self.venueID = venueID; self.exchange = exchange; self.product = product; self.side = side
    self.bucket = bucket; self.price = price; self.firstSeenMs = firstSeenMs; self.endMs = endMs
    self.status = status; self.initialNotional = initialNotional; self.notional = notional
    self.filledNotional = filledNotional; self.threshold = threshold; self.vanishedNotional = vanishedNotional
  }

  public var id: String { "\(venueID)|\(side.rawValue)|\(bucket)|\(firstSeenMs)" }
  public var isLive: Bool { status == .live }
  /// 成交比例，封顶 1。挂着的单按此刻名义算；已成交 / 已撤销的按消失掉的那部分（`vanishedNotional`）算，
  /// 和结束判定同一个分母——不会出现「成交 38% · 已成交」、块很淡却判已成交这种对不上的读数。
  public var fillRatio: Double {
    let base = status == .live ? notional : (vanishedNotional ?? notional)
    return base > 0 ? min(1, max(0, filledNotional / base)) : 0
  }

  /// 图上这一块长什么样只取决于这几项（审查第 31 项）。名义与成交比例按画法量化：
  /// 高度一格是「门槛 ÷ 8」（封顶 40 格，一格 0.25 pt），透明度按成交比例 5% 一档——
  /// 格内、档内的抖动画出来差不到半个像素，不值得整层重画。
  public struct PixelKey: Sendable, Equatable {
    public var id: String
    public var status: Status
    public var endMs: Int64?
    public var bucket: Int64
    public var price: Double
    public var threshold: Double
    public var heightUnits: Int
    public var fillStep: Int
  }

  /// 高度最多几格（和图表 `orderFlowMaxUnits` 同一个数）。
  public static let maxHeightUnits = 40

  /// 画出来是不是一样（逐项比 `pixelKey` 那几项，但不拼 `id` 字符串：一帧两万条时拼字符串是大头）。
  public static func samePixels(_ a: BigOrder, _ b: BigOrder) -> Bool {
    a.firstSeenMs == b.firstSeenMs && a.bucket == b.bucket && a.side == b.side && a.status == b.status
      && a.endMs == b.endMs && a.price == b.price && a.threshold == b.threshold
      && a.heightUnits == b.heightUnits && a.fillStep == b.fillStep && a.venueID == b.venueID
  }

  private var heightUnits: Int {
    threshold > 0 && notional.isFinite
      ? min(Self.maxHeightUnits, Int((max(0, notional) / (threshold / 8)).rounded())) : 0
  }
  private var fillStep: Int { Int((fillRatio * 20).rounded()) }

  public var pixelKey: PixelKey {
    PixelKey(id: id, status: status, endMs: endMs, bucket: bucket, price: price, threshold: threshold,
             heightUnits: heightUnits, fillStep: fillStep)
  }

  // 落盘用短键：5000 条约 1.1 MB。
  enum CodingKeys: String, CodingKey {
    case venueID = "v", exchange = "x", product = "p", side = "s", bucket = "b", price = "px"
    case firstSeenMs = "f", endMs = "e", status = "st", initialNotional = "n0", notional = "n"
    case filledNotional = "fl", threshold = "t", vanishedNotional = "vn"
  }
}

/// 一本簿此刻在不在线（给诊断、取证用，不上界面）。
public struct OrderFlowVenueStatus: Sendable, Equatable {
  public var label: String
  public var product: OrderFlowProduct
  public var instrument: String
  public var ready: Bool
  public init(label: String, product: OrderFlowProduct, instrument: String, ready: Bool) {
    self.label = label; self.product = product; self.instrument = instrument; self.ready = ready
  }
}

/// 主力订单流对外唯一的值：这只品种此刻的大单（还挂着的 + 3 天内结束的，本机跟踪的与服务端取回的并在一起）。
public struct OrderFlowSnapshot: Sendable, Equatable {
  public enum Phase: Sendable, Equatable { case loading, ready }
  public var symbol: String
  public var phase: Phase
  /// 按出现时刻升序（同价位的单按时间先后叠）。
  public var orders: [BigOrder]
  public var asOfMs: Int64
  public var thresholds: OrderFlowThresholds
  /// 叠用户改过的项之前的门槛与步长（默认表按这只的成交额分档之后的那份；步长只有表里给了才有，
  /// 按收盘推的不算默认）。面板的「恢复默认」与「和默认一样就不存」都拿它比（审查第 30 项）：
  /// app 手里的品种事实没有成交额，自己查表只会落到「成交额不知道」那一档（第三档）。模型本身不知道，由数据层填。
  public var defaults: OrderFlowThresholds
  public var venues: [OrderFlowVenueStatus]

  public init(symbol: String, phase: Phase, orders: [BigOrder], asOfMs: Int64,
              thresholds: OrderFlowThresholds = OrderFlowThresholds(),
              defaults: OrderFlowThresholds = OrderFlowThresholds(), venues: [OrderFlowVenueStatus] = []) {
    self.symbol = symbol; self.phase = phase; self.orders = orders; self.asOfMs = asOfMs
    self.thresholds = thresholds; self.defaults = defaults; self.venues = venues
  }

  public static func loading(_ symbol: String, asOfMs: Int64 = 0) -> OrderFlowSnapshot {
    OrderFlowSnapshot(symbol: symbol, phase: .loading, orders: [], asOfMs: asOfMs)
  }

  /// 画出来一样（用来判断要不要再发一帧、图表要不要重画底图）：每一单只比 `BigOrder.pixelKey`，
  /// 名义与成交比例在同一格、同一档里的抖动不算变化。BTC 十几本簿、现价附近的名义几乎每一拍都在变，
  /// 按精确值比的话图表静止时也要每秒整层重画两次（审查第 31 项）。
  public func sameContent(as other: OrderFlowSnapshot) -> Bool {
    guard symbol == other.symbol, phase == other.phase, thresholds == other.thresholds, defaults == other.defaults,
          venues == other.venues, orders.count == other.orders.count else { return false }
    return zip(orders, other.orders).allSatisfy { BigOrder.samePixels($0, $1) }
  }

  /// 除时间戳外逐字相同（十字线停在某一块上、读数要精确金额时用）。
  public func sameExactContent(as other: OrderFlowSnapshot) -> Bool {
    symbol == other.symbol && phase == other.phase && orders == other.orders
      && thresholds == other.thresholds && defaults == other.defaults && venues == other.venues
  }
}

/// 一笔主动成交：`hitSide` 是被吃掉的那一侧（主动卖吃买单 = .bid）。数量是这本簿的原始单位。
public struct OrderFlowTrade: Sendable, Equatable {
  public var price: Double
  public var quantity: Double
  public var hitSide: BookSide
  public var timeMs: Int64
  public init(price: Double, quantity: Double, hitSide: BookSide, timeMs: Int64) {
    self.price = price; self.quantity = quantity; self.hitSide = hitSide; self.timeMs = timeMs
  }
}

/// 适配器解出来的一条消息。各家都落到这四种上。
public enum DepthMessage: Sendable, Equatable {
  /// 流内权威快照（快照随流下发的那几家）：整本替换，立即就绪。
  case snapshot(BookSnapshot)
  /// 增量；序号按整条连接计的那家，心跳、订阅回执、成交帧也各带一条空增量，用来推进连接级序号。
  case delta(BookDelta)
  case trade(OrderFlowTrade)
  /// 协议层面接不上了（例如 OKX 序号重置），需要重建。
  case reset
}

/// 落盘的那一份：一只品种一个文件，只存大单（簿不存）。
public struct OrderFlowJournal: Sendable, Equatable, Codable {
  public static let currentVersion = 1
  public var version: Int
  public var symbol: String
  /// 存盘时的步长：步长变了桶号就对不上，整份作废。
  public var step: Double
  public var savedAtMs: Int64
  public var orders: [BigOrder]

  public init(symbol: String, step: Double, savedAtMs: Int64, orders: [BigOrder]) {
    self.version = Self.currentVersion; self.symbol = symbol; self.step = step
    self.savedAtMs = savedAtMs; self.orders = orders
  }

  public func encoded() -> Data { (try? JSONEncoder().encode(self)) ?? Data() }

  public static func decode(_ data: Data) -> OrderFlowJournal? {
    guard let journal = try? JSONDecoder().decode(OrderFlowJournal.self, from: data),
          journal.version == currentVersion, journal.step.isFinite, journal.step > 0 else { return nil }
    return journal
  }
}

public struct OrderFlowModel: Sendable {
  public enum Action: Sendable, Equatable {
    case none
    /// 需要一份 REST 快照（币安）。
    case fetchSnapshot
    /// 需要重新订阅以拿到新的流内快照（快照在流里的那几家）。
    case resubscribe
  }

  public static let bufferCapacity = 5_000
  /// 一本簿连续这么久没就绪（断线、没这只合约），它还挂着的单按最后一次看到的时刻结束。
  public static let staleMs: Int64 = 120_000
  /// 服务端说「还挂着」之后这么久内算数（数据层每分钟取一次增量，留一倍多的余量）。
  public static let remoteFreshMs: Int64 = 180_000

  public let symbol: String
  public private(set) var thresholds: OrderFlowThresholds
  public private(set) var scheme: BucketScheme?
  /// 还挂着的 + 已结束的，按出现时刻升序。
  public private(set) var orders: [BigOrder] = []
  /// 大单出现、结束、被清过，还没落盘。
  public private(set) var journalDirty = false

  private var books: [String: VenueBook] = [:]
  private var venueOrder: [String] = []
  private var candidates: [CandidateKey: Candidate] = [:]
  /// 还挂着的单按（簿、侧、桶）到 `orders` 下标的索引：一个键上同一时刻最多挂一单（候选只在没有挂单的桶上起）。
  /// `orders` 结构一变（新增、删、排序、读回）就重建；成交归因和逐本簿更新都走它，不再每笔成交扫全表。
  private var liveIndex: [CandidateKey: Int] = [:]
  private var ending: [String: Pending] = [:]
  private var lastSeen: [String: Int64] = [:]
  /// 挂着期间见过的最大名义（按单 id）；结束判定的分母。读回来的按首次与最后名义取大。
  private var peak: [String: Double] = [:]
  private var venueSeen: [String: Int64] = [:]
  private var startedMs: Int64?
  /// 读回来的那份，步长还不知道（等前一日收盘）时先放着。
  private var pendingJournal: OrderFlowJournal?
  /// 读回了挂着的单：存盘时刻。第一次评估时据此判断缺席是不是超过了 `staleMs`。
  private var restoredAtMs: Int64?
  /// 服务端最近一次说它还挂着的时刻（按单 id）。本机没这本簿、簿没就绪时，靠服务端续命，
  /// 不按「簿断开太久」失联结束；服务端也不再续（断网、它结束了）就照常处理。
  private var remoteSeen: [String: Int64] = [:]
  /// 图上此刻看得见的时间区间：超额挤单时，落在这里面的优先留（往左拖补回来的那一段不被立刻挤掉）。
  private var visibleWindow: ClosedRange<Int64>?

  struct CandidateKey: Hashable, Sendable {
    var venue: String
    var key: BucketKey
  }

  struct Candidate: Sendable {
    var firstMs: Int64
    var samples = 0
    var initial: Double
    var notional: Double
    var price: Double
    var filled = 0.0
  }

  struct Pending: Sendable {
    var firstMs: Int64
    var samples = 0
    /// 第一次跌破那一拍桶里还剩多少（美元）；算「消失了多少」用。
    var remaining: Double
  }

  public init(symbol: String, thresholds: OrderFlowThresholds, restored: OrderFlowJournal? = nil) {
    self.symbol = symbol
    self.thresholds = thresholds
    self.scheme = thresholds.step.flatMap(BucketScheme.init(step:))
    self.pendingJournal = restored
    restoreIfPossible()
  }

  // MARK: - 簿

  /// 加一本簿（同一本加两次无事发生）。
  public mutating func addVenue(_ venue: OrderFlowVenue) {
    guard books[venue.id] == nil else { return }
    books[venue.id] = VenueBook(venue: venue)
    venueOrder.append(venue.id)
  }

  public var venues: [OrderFlowVenue] { venueOrder.compactMap { books[$0]?.venue } }

  public func isReady(_ venueID: String) -> Bool { books[venueID]?.isReady ?? false }

  /// 按簿深标定非币默认门槛用：已拿到首张快照（就绪）的每本簿中间价 ±`bps` 以内两侧美元名义之和，
  /// 以及就绪了几本、一共几本。公式见 `OrderFlowDefaults.calibratedThreshold(depth:)`。
  public mutating func calibrationDepth(withinBps bps: Double = OrderFlowDefaults.calibrationBandBps)
    -> (depth: Double, ready: Int, total: Int) {
    var depth = 0.0, ready = 0
    for id in venueOrder {
      guard var book = books[id], let d = book.depthUSD(withinBps: bps) else { continue }
      books[id] = book
      depth += d; ready += 1
    }
    return (depth, ready, venueOrder.count)
  }

  /// 新连接建立：这本簿换一个连接代号重来。
  public mutating func connectionOpened(_ venueID: String) -> Action {
    books[venueID]?.connectionOpened() ?? .none
  }

  /// 断线：簿不再可信，回到「拉快照中」，重连后再重建。
  public mutating func disconnected(_ venueID: String) {
    _ = books[venueID]?.connectionOpened()
  }

  public mutating func ingest(_ venueID: String, _ message: DepthMessage, nowMs: Int64) -> Action {
    guard let venue = books[venueID]?.venue else { return .none }
    if case .trade(let trade) = message {
      attribute(trade, venueID: venueID, notional: venue.notional)
      return .none
    }
    return books[venueID]?.ingest(message, nowMs: nowMs) ?? .none
  }

  /// REST 快照到了：和已缓冲的增量对序号。
  public mutating func applySnapshot(_ venueID: String, _ snapshot: BookSnapshot, nowMs: Int64) -> Action {
    books[venueID]?.applySnapshot(snapshot, nowMs: nowMs) ?? .none
  }

  /// 成交记进同一本簿这一侧这个桶上还挂着的大单，以及正在确认中的候选。别的簿的成交不记（见文件头）。
  private mutating func attribute(_ trade: OrderFlowTrade, venueID: String, notional: OrderFlowNotional) {
    guard let scheme else { return }
    let usd = notional.usd(price: trade.price, quantity: trade.quantity)
    guard usd > 0 else { return }
    let bucket = scheme.index(of: trade.price)
    let key = CandidateKey(venue: venueID, key: BucketKey(side: trade.hitSide, index: bucket))
    if let i = liveIndex[key], orders[i].isLive { orders[i].filledNotional += usd }
    candidates[key]?.filled += usd
  }

  // MARK: - 设置

  /// 门槛或步长改了（用户在面板里改、或前一日收盘到了算出步长）。
  /// - 步长变了：桶号全变，大单全部清掉。
  /// - 某种产品的门槛变了：首次名义不到新门槛的那几条（挂着的、结束的都算）不再是大单，删掉；
  ///   其余的换成新门槛（画厚度用）。门槛降低时，新达标的从这一刻起按正常确认出现。
  public mutating func setThresholds(_ next: OrderFlowThresholds) {
    let nextScheme = next.step.flatMap(BucketScheme.init(step:))
    thresholds = next
    if nextScheme != scheme {
      scheme = nextScheme
      if !orders.isEmpty { journalDirty = true }
      orders.removeAll(); candidates.removeAll(); ending.removeAll(); lastSeen.removeAll(); peak.removeAll()
      remoteSeen.removeAll()
      restoreIfPossible()
      reindex()
      return
    }
    requalify()
    reindex()
  }

  private mutating func requalify() {
    let before = orders.count
    orders.removeAll { order in
      guard let t = thresholds[order.product] else { return true }
      return order.initialNotional < t
    }
    for i in orders.indices { orders[i].threshold = thresholds[orders[i].product] ?? orders[i].threshold }
    candidates = candidates.filter { key, _ in
      books[key.venue].map { thresholds[$0.venue.product] != nil } ?? false
    }
    let live = Set(orders.map(\.id))
    ending = ending.filter { live.contains($0.key) }
    lastSeen = lastSeen.filter { live.contains($0.key) }
    peak = peak.filter { live.contains($0.key) }
    remoteSeen = remoteSeen.filter { live.contains($0.key) }
    if orders.count != before { journalDirty = true }
  }

  private mutating func restoreIfPossible() {
    guard let journal = pendingJournal, let scheme else { return }
    pendingJournal = nil
    guard abs(journal.step - scheme.step) <= scheme.step * 1e-9 else { return }
    orders = journal.orders.sorted(by: Self.chronological)
    for order in orders where order.isLive {
      lastSeen[order.id] = journal.savedAtMs
      peak[order.id] = max(order.initialNotional, order.notional)
    }
    if orders.contains(where: \.isLive) { restoredAtMs = journal.savedAtMs }
    requalify()
    reindex()
  }

  private mutating func reindex() {
    liveIndex.removeAll(keepingCapacity: true)
    for i in orders.indices where orders[i].isLive {
      liveIndex[CandidateKey(venue: orders[i].venueID, key: BucketKey(side: orders[i].side, index: orders[i].bucket))] = i
    }
  }

  // MARK: - 落盘

  /// 落盘的那一份：挂着的全留；结束的只留最近 24 小时（`journalRetentionMs`），多于 5000 条
  /// （`journalMaxOrders`）按留存同一个次序挑（最近 2 小时内结束的先留，其余活得久的先留）。
  /// 更早的历史每次向服务端取，不落盘。
  public func journal(nowMs: Int64) -> OrderFlowJournal? {
    guard let scheme else { return nil }
    let cutoff = nowMs - OrderFlowDefaults.journalRetentionMs
    var picked = orders.filter { $0.isLive || ($0.endMs ?? $0.firstSeenMs) >= cutoff }
    if picked.count > OrderFlowDefaults.journalMaxOrders {
      let live = picked.count(where: \.isLive)
      let room = max(0, OrderFlowDefaults.journalMaxOrders - live)
      let ended = picked.indices.filter { !picked[$0].isLive }
      let keep = Set(Self.evictionOrder(ended, in: picked, nowMs: nowMs, window: nil).suffix(room))
      picked = picked.indices.compactMap { picked[$0].isLive || keep.contains($0) ? picked[$0] : nil }
    }
    return OrderFlowJournal(symbol: symbol, step: scheme.step, savedAtMs: nowMs, orders: picked)
  }

  public mutating func markJournalSaved() { journalDirty = false }

  // MARK: - 评估

  /// 按此刻各本簿算一轮：确认出现 / 消失、结束判定、过期清理，出一帧。
  public mutating func evaluate(nowMs: Int64) -> OrderFlowSnapshot {
    guard let scheme else { return .loading(symbol, asOfMs: nowMs) }
    if startedMs == nil { startedMs = nowMs }
    if let saved = restoredAtMs {
      restoredAtMs = nil
      if nowMs - saved >= Self.staleMs {
        // 服务端刚说过还挂着的（冷启动时历史比第一次评估先到）不算缺席。
        for i in orders.indices where orders[i].isLive && remoteSeen[orders[i].id] == nil { endLost(i, atMs: saved) }
        reindex()
      }
    }
    var evaluated = Set<String>()
    var touched = Set<CandidateKey>()
    var appended = false
    for id in venueOrder {
      guard var book = books[id], let threshold = thresholds[book.venue.product], threshold > 0 else { continue }
      let map = book.buckets(scheme: scheme, radiusBps: OrderFlowDefaults.scanRadiusBps)
      books[id] = book
      guard let map else { continue }
      evaluated.insert(id)
      venueSeen[id] = nowMs

      // 1. 这本簿上还挂着的单：还在退出线（门槛 × 0.5）上就更新，跌破就开始确认结束。
      let exitLine = threshold * OrderFlowDefaults.exitRatio
      var liveKeys = Set<BucketKey>()
      for (ck, i) in liveIndex where ck.venue == id && orders[i].isLive {
        let key = ck.key
        liveKeys.insert(key)
        let oid = orders[i].id
        if let value = map[key], value.notional >= exitLine {
          orders[i].notional = value.notional
          orders[i].price = value.price
          peak[oid] = max(peak[oid] ?? orders[i].initialNotional, value.notional)
          lastSeen[oid] = nowMs
          ending[oid] = nil
        } else if !book.knows(key.side, price: orders[i].price) {
          // 这一档在快照覆盖范围以外、增量也没推过（币安 1000 档快照只盖盘口两侧 0.3%，重启 / 重连后
          // 2%–10% 外读回来的单全在这里）：看不见不等于没了，既不算消失也不开始确认，等增量推到它再判。
          lastSeen[oid] = nowMs
        } else {
          var pending = ending[oid] ?? Pending(firstMs: nowMs, remaining: 0)
          pending.samples += 1
          pending.remaining = map[key]?.notional ?? 0  // 确认期间还在掉就按最后一拍剩的算
          if Self.confirmed(samples: pending.samples, firstMs: pending.firstMs, nowMs: nowMs) {
            end(i, atMs: pending.firstMs, remaining: pending.remaining)
            ending[oid] = nil
          } else {
            ending[oid] = pending
          }
        }
      }

      // 2. 新过门槛的桶：确认两拍才出现。
      for (key, value) in map where value.notional >= threshold && !liveKeys.contains(key) {
        let ck = CandidateKey(venue: id, key: key)
        touched.insert(ck)
        var c = candidates[ck] ?? Candidate(firstMs: nowMs, initial: value.notional, notional: value.notional,
                                            price: value.price)
        c.samples += 1
        c.notional = value.notional
        c.price = value.price
        if Self.confirmed(samples: c.samples, firstMs: c.firstMs, nowMs: nowMs) {
          let order = BigOrder(venueID: id, exchange: book.venue.label, product: book.venue.product,
                               side: key.side, bucket: key.index, price: c.price, firstSeenMs: c.firstMs,
                               initialNotional: c.initial, notional: c.notional, filledNotional: c.filled,
                               threshold: threshold)
          orders.append(order)
          liveIndex[ck] = orders.count - 1
          appended = true
          lastSeen[order.id] = nowMs
          peak[order.id] = max(c.initial, c.notional)
          candidates[ck] = nil
          journalDirty = true
        } else {
          candidates[ck] = c
        }
      }
    }
    // 这一拍评估过的簿上、没再过门槛的候选作废（「连续」两拍）；没就绪的簿的候选先留着。
    candidates = candidates.filter { touched.contains($0.key) || !evaluated.contains($0.key.venue) }

    expireStale(nowMs: nowMs)
    let pruned = prune(nowMs: nowMs)
    // 只有新增了单才可能乱序（新单的出现时刻记的是候选第一拍，可能早于上一拍刚出现的单）；
    // 结束、删除都不改先后。
    if appended { orders.sort(by: Self.chronological) }
    if appended || pruned { reindex() }

    let statuses = venueOrder.compactMap { id in
      books[id].map { OrderFlowVenueStatus(label: $0.venue.label, product: $0.venue.product,
                                           instrument: $0.venue.instrument, ready: $0.isReady) }
    }
    let phase: OrderFlowSnapshot.Phase = venueSeen.isEmpty && orders.isEmpty ? .loading : .ready
    return OrderFlowSnapshot(symbol: symbol, phase: phase, orders: orders, asOfMs: nowMs,
                             thresholds: thresholds, venues: statuses)
  }

  static func confirmed(samples: Int, firstMs: Int64, nowMs: Int64) -> Bool {
    samples >= OrderFlowDefaults.confirmationSamples && nowMs - firstMs >= OrderFlowDefaults.confirmationMs
  }

  static func chronological(_ a: BigOrder, _ b: BigOrder) -> Bool {
    a.firstSeenMs != b.firstSeenMs ? a.firstSeenMs < b.firstSeenMs : a.id < b.id
  }

  /// 跌破退出线：消失掉的那部分名义里成交够八成算已成交，否则已撤销。`remaining` 是确认结束的最后一拍桶里还剩的。
  ///
  /// 消失掉的 = 挂着期间见过的最大名义（`peak`）− 结束时剩下的。不用首次名义：
  /// 挂出 1M、加到 5M 再撤掉，按首次名义算只要成交 0.8M 就判「已成交」，其实 4M 是撤的。
  /// 也不用「跌破前最后一拍的名义」：线上实测（2026-09-24）一面 340 万的现货墙十几拍里被一点点撤到 52 万，
  /// 最后一拍只差 2 万，27 万零星成交就把它判成了「已成交」；按峰值算消失了 290 万、成交不到一成——是撤的。
  /// 先撤一半再被吃掉剩下的，按这个口径是「已撤销 · 成交 43%」（卡片上写「部分成交」）。
  private mutating func end(_ i: Int, atMs: Int64, remaining: Double) {
    let order = orders[i]
    let top = max(peak[order.id] ?? 0, order.initialNotional, order.notional)
    let vanished = max(0, top - max(0, remaining))
    orders[i].vanishedNotional = vanished
    orders[i].status = vanished > 0 && order.filledNotional >= vanished * OrderFlowDefaults.filledRatio
      ? .filled : .cancelled
    orders[i].endMs = max(order.firstSeenMs, atMs)
    lastSeen[order.id] = nil
    peak[order.id] = nil
    remoteSeen[order.id] = nil
    journalDirty = true
  }

  /// 簿断开太久（或这一轮根本没订到那本簿，例如交割合约换季了），它还挂着的单按最后一次看到时失联结束。
  private mutating func expireStale(nowMs: Int64) {
    guard let started = startedMs, nowMs - started >= Self.staleMs else { return }
    for i in orders.indices where orders[i].isLive {
      if let remote = remoteSeen[orders[i].id], nowMs - remote < Self.remoteFreshMs { continue }
      let seen = venueSeen[orders[i].venueID] ?? started
      guard nowMs - seen >= Self.staleMs else { continue }
      endLost(i, atMs: lastSeen[orders[i].id] ?? orders[i].firstSeenMs)
    }
  }

  /// 失联结束：不判成交 / 撤单，不记消失掉的名义。
  private mutating func endLost(_ i: Int, atMs: Int64) {
    let oid = orders[i].id
    orders[i].status = .lost
    orders[i].endMs = max(orders[i].firstSeenMs, atMs)
    orders[i].vanishedNotional = nil
    lastSeen[oid] = nil
    peak[oid] = nil
    ending[oid] = nil
    remoteSeen[oid] = nil
    journalDirty = true
  }

  /// 3 天以前结束的删掉；结束的超过 2 万条就一次挤到九成（`trimRatio`），先挤活得短的，
  /// 最近 2 小时内结束的、落在图上可视区间里的后挤。还挂着的一条不删。删了返回 true。
  private mutating func prune(nowMs: Int64) -> Bool {
    let cutoff = nowMs - OrderFlowDefaults.retentionMs
    let before = orders.count
    orders.removeAll { !$0.isLive && ($0.endMs ?? $0.firstSeenMs) < cutoff }
    let ended = orders.indices.filter { !orders[$0].isLive }
    if ended.count > OrderFlowDefaults.maxEndedOrders {
      let keep = Int(Double(OrderFlowDefaults.maxEndedOrders) * OrderFlowDefaults.trimRatio)
      let drop = Set(Self.evictionOrder(ended, in: orders, nowMs: nowMs, window: visibleWindow)
        .prefix(ended.count - keep))
      orders = orders.indices.compactMap { drop.contains($0) ? nil : orders[$0] }
    }
    if orders.count != before {
      journalDirty = true
      let alive = Set(orders.lazy.filter(\.isLive).map(\.id))
      ending = ending.filter { alive.contains($0.key) }
      lastSeen = lastSeen.filter { alive.contains($0.key) }
      peak = peak.filter { alive.contains($0.key) }
      remoteSeen = remoteSeen.filter { alive.contains($0.key) }
    }
    return orders.count != before
  }

  /// 结束的单按「先挤谁」排好的下标：最近 `recentKeepMs` 内结束的最后挤，其次是落在可视区间里的，
  /// 同一档里活得短的先挤、再按结束早的先挤。
  static func evictionOrder(_ indices: [Int], in orders: [BigOrder], nowMs: Int64,
                            window: ClosedRange<Int64>?) -> [Int] {
    let recent = nowMs - OrderFlowDefaults.recentKeepMs
    func tier(_ o: BigOrder) -> Int {
      let end = o.endMs ?? nowMs
      if end >= recent { return 2 }
      if let window, o.firstSeenMs <= window.upperBound, end >= window.lowerBound { return 1 }
      return 0
    }
    let keyed = indices.map { i -> (Int, Int, Int64, Int64) in
      let o = orders[i]
      let end = o.endMs ?? nowMs
      return (i, tier(o), end - o.firstSeenMs, end)
    }
    return keyed.sorted { a, b in
      if a.1 != b.1 { return a.1 < b.1 }
      if a.2 != b.2 { return a.2 < b.2 }
      if a.3 != b.3 { return a.3 < b.3 }
      return a.0 < b.0
    }.map(\.0)
  }

  // MARK: - 服务端历史

  /// 并一页服务端历史的结果。
  public enum HistoryMerge: Sendable, Equatable {
    /// 并进来了（可能一条都没变）。
    case merged
    /// 自己的步长还不知道（等前一日收盘），先别并，过会儿再取。
    case pending
    /// 步长和服务端的对不上（用户改过步长，或服务端的还没算出来），桶号没法比，这一页不用。
    case incompatible
  }

  /// 图上此刻看得见的时间区间（超额挤单时这里面的优先留）。
  public mutating func setVisibleWindow(_ window: ClosedRange<Int64>?) { visibleWindow = window }

  /// 把服务端取回来的一页并进来。
  ///
  /// - 换算：服务端的价是每个币的价，乘 `chartScale`（`1000PEPE` 为 1000）换成图上的价，再按本机步长
  ///   重新分桶；门槛换成本机此刻生效的那份。步长（换算后）和本机的对不上就整页不用（`.incompatible`）。
  /// - 门槛：首次名义不到本机门槛的丢掉（用户把门槛调高了）。用户调低了，服务端没有的那些由本机实时跟踪补。
  /// - 同一本簿、同一侧、同一桶、时间区间有重叠的，算同一条，**以服务端为准**；只有本机有的留着。
  /// - 服务端说还挂着：本机也挂着那条就接着本机跟（出现时刻、首次名义取服务端的，已成交、峰值取两边大的，
  ///   此刻名义与价位用本机簿上的——本机簿这一桶还在退出线上就一直这么跟，跌破了由本机照常判结束）；
  ///   本机没有就按服务端的状态挂上，本机簿就绪后由本机接着跟，本机没这本簿就靠服务端每分钟续命
  ///   （`remoteFreshMs`）。本机已经亲眼看到它结束（已成交 / 已撤销）的，留本机的结束，只补出现时刻与成交——
  ///   服务端还挂着多半只是还没刷到库里（挂着的单 15 秒一刷），等它下一次说结束了再以它为准，
  ///   免得图上一会儿挂着一会儿结束来回跳。本机判的是「失联结束」的，以服务端为准。
  /// - 服务端说结束了：重叠的本机那条（挂着的也算）换成服务端的。本机簿上那一桶还过门槛的话，
  ///   本机按正常确认重新出现一条。
  @discardableResult
  public mutating func mergeHistory(_ page: OrderFlowHistoryPage, chartScale: Double, nowMs: Int64) -> HistoryMerge {
    guard let scheme else { return .pending }
    guard let remoteStep = page.thresholds.step, chartScale.isFinite, chartScale > 0,
          abs(remoteStep * chartScale - scheme.step) <= scheme.step * 1e-6 else { return .incompatible }
    var incoming: [BigOrder] = []
    incoming.reserveCapacity(page.orders.count)
    for var order in page.orders {
      guard let threshold = thresholds[order.product], order.initialNotional >= threshold else { continue }
      order.price *= chartScale
      guard order.price.isFinite, order.price > 0 else { continue }
      order.bucket = scheme.index(of: order.price)
      order.threshold = threshold
      incoming.append(order)
    }
    guard !incoming.isEmpty else { return .merged }

    func key(_ o: BigOrder) -> CandidateKey { CandidateKey(venue: o.venueID, key: BucketKey(side: o.side, index: o.bucket)) }
    var byKey: [CandidateKey: [Int]] = [:]
    for i in orders.indices { byKey[key(orders[i]), default: []].append(i) }
    var removed = Set<Int>()
    var claimed = Set<Int>()
    var added: [BigOrder] = []

    // 挂着的先配：先把本机正在跟的那条认领下来，后面同键的结束单就不会把它当成重叠删掉。
    for remote in incoming where remote.isLive {
      let matches = (byKey[key(remote)] ?? []).filter { !removed.contains($0) && !claimed.contains($0)
        && Self.overlaps(orders[$0], remote) }
      if let i = matches.first(where: { orders[$0].isLive }) {
        adopt(i, remote: remote, nowMs: nowMs)
        claimed.insert(i)
        for j in matches where j != i { removed.insert(j) }
      } else if let j = matches.filter({ orders[$0].status == .filled || orders[$0].status == .cancelled })
                  .max(by: { (orders[$0].endMs ?? 0) < (orders[$1].endMs ?? 0) }) {
        // 本机亲眼看到结束了：留本机的结束，只补出现时刻与成交。
        let old = orders[j]
        orders[j].firstSeenMs = min(remote.firstSeenMs, old.endMs ?? remote.firstSeenMs)
        orders[j].initialNotional = remote.initialNotional
        orders[j].filledNotional = max(old.filledNotional, remote.filledNotional)
        claimed.insert(j)
        for k in matches where k != j { removed.insert(k) }
      } else {
        matches.forEach { removed.insert($0) }
        added.append(remote)
        lastSeen[remote.id] = nowMs
        peak[remote.id] = max(remote.initialNotional, remote.notional)
        remoteSeen[remote.id] = nowMs
      }
    }
    for remote in incoming where !remote.isLive {
      for i in byKey[key(remote)] ?? [] where !claimed.contains(i) && Self.overlaps(orders[i], remote) {
        removed.insert(i)
      }
      added.append(remote)
    }

    if !removed.isEmpty { orders = orders.indices.compactMap { removed.contains($0) ? nil : orders[$0] } }
    orders.append(contentsOf: added)
    // 同一条单服务端一页里只会出现一次；几页之间重叠的那一段（增量往前退了 5 分钟）已经按「服务端为准」换掉了。
    orders.sort(by: Self.chronological)
    reindex()
    let alive = Set(orders.lazy.filter(\.isLive).map(\.id))
    ending = ending.filter { alive.contains($0.key) }
    lastSeen = lastSeen.filter { alive.contains($0.key) }
    peak = peak.filter { alive.contains($0.key) }
    remoteSeen = remoteSeen.filter { alive.contains($0.key) }
    // 已经有单挂着的桶上的候选作废（不然两拍后又冒出一条同键的挂单）。
    candidates = candidates.filter { liveIndex[$0.key] == nil }
    journalDirty = true
    _ = prune(nowMs: nowMs)
    reindex()
    return .merged
  }

  /// 同一个键上的两条时间区间有没有重叠（挂着的算到无穷；首尾相接不算）。
  static func overlaps(_ a: BigOrder, _ b: BigOrder) -> Bool {
    let aEnd = a.endMs.map { max($0, a.firstSeenMs + 1) } ?? .max
    let bEnd = b.endMs.map { max($0, b.firstSeenMs + 1) } ?? .max
    return a.firstSeenMs < bEnd && b.firstSeenMs < aEnd
  }

  /// 本机正在跟的这条接上服务端那条：出现时刻、首次名义取服务端的，成交与峰值取两边大的，
  /// 此刻名义与价位仍是本机簿上的。出现时刻一变 id 就变，按单 id 记的几张表跟着换键。
  private mutating func adopt(_ i: Int, remote: BigOrder, nowMs: Int64) {
    let old = orders[i]
    let oldID = old.id
    orders[i].firstSeenMs = remote.firstSeenMs
    orders[i].initialNotional = remote.initialNotional
    orders[i].filledNotional = max(old.filledNotional, remote.filledNotional)
    let newID = orders[i].id
    if newID != oldID {
      lastSeen[newID] = lastSeen.removeValue(forKey: oldID)
      peak[newID] = peak.removeValue(forKey: oldID)
      ending[newID] = ending.removeValue(forKey: oldID)
    }
    peak[newID] = max(peak[newID] ?? 0, remote.initialNotional, remote.notional, old.notional, old.initialNotional)
    if lastSeen[newID] == nil { lastSeen[newID] = nowMs }
    remoteSeen[oldID] = nil
    remoteSeen[newID] = nowMs
  }
}
