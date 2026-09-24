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
// - 结束：累计成交 ≥ 消失掉的名义（首次名义 − 结束时剩下的）× 0.8 记「已成交」，否则「已撤销」（理由见 `OrderFlowDefaults.filledRatio`）。
// - 历史：结束的大单留在图上，24 小时、最多 500 条（`OrderFlowDefaults.retentionMs / maxEndedOrders`）；
//   还挂着的永远不删。
// - 落盘：`OrderFlowJournal`，一只品种一份小文件（KanpanData 管读写），切回来、进程重启历史还在；不同步。
// - 簿断了：没就绪的那本簿这一拍不参与（它的单既不新增也不结束）；断开超过 2 分钟，它还挂着的单
//   按最后一次看到的时刻结束（`staleMs`）。
//
// 交易所帧由 KanpanNetwork 的适配器解成 `DepthMessage` 喂进来，连接、快照拉取、节流与落盘由
// KanpanData 的 OrderFlowFeed 管。图表与 app 只看得到 `OrderFlowSnapshot`。

/// 一条大单。
public struct BigOrder: Sendable, Equatable, Identifiable, Codable {
  public enum Status: String, Sendable, Codable { case live, filled, cancelled }

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
  /// 出现以来打到这一侧这个桶的主动成交（美元，各家合计）。
  public var filledNotional: Double
  /// 这一单所属产品此刻的门槛（画厚度用）。
  public var threshold: Double

  public init(venueID: String, exchange: String, product: OrderFlowProduct, side: BookSide, bucket: Int64,
              price: Double, firstSeenMs: Int64, endMs: Int64? = nil, status: Status = .live,
              initialNotional: Double, notional: Double, filledNotional: Double = 0, threshold: Double) {
    self.venueID = venueID; self.exchange = exchange; self.product = product; self.side = side
    self.bucket = bucket; self.price = price; self.firstSeenMs = firstSeenMs; self.endMs = endMs
    self.status = status; self.initialNotional = initialNotional; self.notional = notional
    self.filledNotional = filledNotional; self.threshold = threshold
  }

  public var id: String { "\(venueID)|\(side.rawValue)|\(bucket)|\(firstSeenMs)" }
  public var isLive: Bool { status == .live }
  /// 成交 / 首次名义，封顶 1（各家成交都记进来，可能超过挂单本身）。
  public var fillRatio: Double {
    initialNotional > 0 ? min(1, max(0, filledNotional / initialNotional)) : 0
  }

  // 落盘用短键：500 条约 75 KB。
  enum CodingKeys: String, CodingKey {
    case venueID = "v", exchange = "x", product = "p", side = "s", bucket = "b", price = "px"
    case firstSeenMs = "f", endMs = "e", status = "st", initialNotional = "n0", notional = "n"
    case filledNotional = "fl", threshold = "t"
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

/// 主力订单流对外唯一的值：这只品种此刻的大单（还挂着的 + 24 小时内结束的）。
public struct OrderFlowSnapshot: Sendable, Equatable {
  public enum Phase: Sendable, Equatable { case loading, ready }
  public var symbol: String
  public var phase: Phase
  /// 按出现时刻升序（同价位的单按时间先后叠）。
  public var orders: [BigOrder]
  public var asOfMs: Int64
  public var thresholds: OrderFlowThresholds
  public var venues: [OrderFlowVenueStatus]

  public init(symbol: String, phase: Phase, orders: [BigOrder], asOfMs: Int64,
              thresholds: OrderFlowThresholds = OrderFlowThresholds(), venues: [OrderFlowVenueStatus] = []) {
    self.symbol = symbol; self.phase = phase; self.orders = orders; self.asOfMs = asOfMs
    self.thresholds = thresholds; self.venues = venues
  }

  public static func loading(_ symbol: String, asOfMs: Int64 = 0) -> OrderFlowSnapshot {
    OrderFlowSnapshot(symbol: symbol, phase: .loading, orders: [], asOfMs: asOfMs)
  }

  /// 除时间戳外内容相同（用来判断要不要再发一帧）。
  public func sameContent(as other: OrderFlowSnapshot) -> Bool {
    symbol == other.symbol && phase == other.phase && orders == other.orders
      && thresholds == other.thresholds && venues == other.venues
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
  private var venueSeen: [String: Int64] = [:]
  private var startedMs: Int64?
  /// 读回来的那份，步长还不知道（等前一日收盘）时先放着。
  private var pendingJournal: OrderFlowJournal?

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
      orders.removeAll(); candidates.removeAll(); ending.removeAll(); lastSeen.removeAll()
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
    if orders.count != before { journalDirty = true }
  }

  private mutating func restoreIfPossible() {
    guard let journal = pendingJournal, let scheme else { return }
    pendingJournal = nil
    guard abs(journal.step - scheme.step) <= scheme.step * 1e-9 else { return }
    orders = journal.orders.sorted(by: Self.chronological)
    for order in orders where order.isLive { lastSeen[order.id] = journal.savedAtMs }
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

  public func journal(nowMs: Int64) -> OrderFlowJournal? {
    guard let scheme else { return nil }
    return OrderFlowJournal(symbol: symbol, step: scheme.step, savedAtMs: nowMs, orders: orders)
  }

  public mutating func markJournalSaved() { journalDirty = false }

  // MARK: - 评估

  /// 按此刻各本簿算一轮：确认出现 / 消失、结束判定、过期清理，出一帧。
  public mutating func evaluate(nowMs: Int64) -> OrderFlowSnapshot {
    guard let scheme else { return .loading(symbol, asOfMs: nowMs) }
    if startedMs == nil { startedMs = nowMs }
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
          lastSeen[oid] = nowMs
          ending[oid] = nil
        } else {
          var pending = ending[oid] ?? Pending(firstMs: nowMs, remaining: map[key]?.notional ?? 0)
          pending.samples += 1
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

  /// 跌破退出线：消失掉的那部分名义里成交够八成算已成交，否则已撤销。`remaining` 是跌破那一拍桶里还剩的。
  private mutating func end(_ i: Int, atMs: Int64, remaining: Double) {
    let order = orders[i]
    let vanished = max(0, order.initialNotional - max(0, remaining))
    orders[i].status = vanished > 0 && order.filledNotional >= vanished * OrderFlowDefaults.filledRatio
      ? .filled : .cancelled
    orders[i].endMs = max(order.firstSeenMs, atMs)
    lastSeen[order.id] = nil
    journalDirty = true
  }

  /// 簿断开太久（或这一轮根本没订到那本簿，例如交割合约换季了），它还挂着的单按最后一次看到时结束。
  private mutating func expireStale(nowMs: Int64) {
    guard let started = startedMs, nowMs - started >= Self.staleMs else { return }
    for i in orders.indices where orders[i].isLive {
      let seen = venueSeen[orders[i].venueID] ?? started
      guard nowMs - seen >= Self.staleMs else { continue }
      let oid = orders[i].id
      end(i, atMs: lastSeen[oid] ?? orders[i].firstSeenMs, remaining: orders[i].notional)
      ending[oid] = nil
    }
  }

  /// 24 小时以前结束的删掉；结束的超过 500 条就删结束得最早的。还挂着的一条不删。删了返回 true。
  private mutating func prune(nowMs: Int64) -> Bool {
    let cutoff = nowMs - OrderFlowDefaults.retentionMs
    let before = orders.count
    orders.removeAll { !$0.isLive && ($0.endMs ?? $0.firstSeenMs) < cutoff }
    let ended = orders.filter { !$0.isLive }
    let excess = ended.count - OrderFlowDefaults.maxEndedOrders
    if excess > 0 {
      let drop = Set(ended.sorted { ($0.endMs ?? 0) < ($1.endMs ?? 0) }.prefix(excess).map(\.id))
      orders.removeAll { drop.contains($0.id) }
    }
    if orders.count != before {
      journalDirty = true
      let alive = Set(orders.map(\.id))
      ending = ending.filter { alive.contains($0.key) }
      lastSeen = lastSeen.filter { alive.contains($0.key) }
    }
    return orders.count != before
  }
}
