import Foundation

// 主力订单流 · 本地簿。
//
// 逐行移植 send-tradfi `crates/bit-orderbook-book/src/lib.rs`（bootstrap :108、apply :232、
// replace_from_stream_snapshot :300、begin_resync :345、fail_sequence）。三家交易所的序号
// 规则都在 `DepthSequenceModel` 里；簿本身与交易所无关，由 KanpanNetwork 的适配器把各家帧
// 解成 `BookSnapshot` / `BookDelta`。原项目用 Decimal，这里用 Double：同一个价格字符串解出来
// 的 Double 恒等，作字典键安全。

public enum BookSide: String, Sendable, Hashable, Codable { case bid, ask }

public struct BookLevel: Sendable, Equatable {
  public var price: Double
  public var quantity: Double
  public init(price: Double, quantity: Double) { self.price = price; self.quantity = quantity }
}

/// 快照与增量怎样接续。对应原项目 `DepthSequenceModel`。
public enum DepthSequenceModel: Sendable, Equatable {
  /// 现货 U/u：第一条要覆盖 L+1，之后每条覆盖 prev+1，不许带 pu。
  case rangeOverlap
  /// U 本位永续 U/u/pu：第一条要覆盖 L，之后 pu == prev。
  case previousFinalOverlap
  /// seqId/prevSeqId：第一条 pu == L，之后 pu == prev。
  case previousFinalExact
  /// 整条连接一个递增序号：每条 first == final == prev+1，不带 pu。
  case strictIncrementing
}

public struct BookSnapshot: Sendable, Equatable {
  public var lastUpdateID: Int64
  /// 请求的每侧档数；返回档数到了这个数就说明快照被截断（SnapshotLimited）。
  public var requestedLevels: Int
  public var bids: [BookLevel]
  public var asks: [BookLevel]
  public var eventTimeMs: Int64?
  /// 连接代号，由订单流模型在收下时盖上；旧连接的迟到包据此挡掉。
  public var connection: Int
  public init(lastUpdateID: Int64, requestedLevels: Int, bids: [BookLevel], asks: [BookLevel],
              eventTimeMs: Int64? = nil, connection: Int = 0) {
    self.lastUpdateID = lastUpdateID; self.requestedLevels = requestedLevels
    self.bids = bids; self.asks = asks; self.eventTimeMs = eventTimeMs; self.connection = connection
  }
}

public struct BookDelta: Sendable, Equatable {
  public var firstUpdateID: Int64
  public var finalUpdateID: Int64
  public var previousFinalUpdateID: Int64?
  public var bids: [BookLevel]
  public var asks: [BookLevel]
  public var eventTimeMs: Int64
  public var connection: Int
  public init(firstUpdateID: Int64, finalUpdateID: Int64, previousFinalUpdateID: Int64?,
              bids: [BookLevel] = [], asks: [BookLevel] = [], eventTimeMs: Int64 = 0, connection: Int = 0) {
    self.firstUpdateID = firstUpdateID; self.finalUpdateID = finalUpdateID
    self.previousFinalUpdateID = previousFinalUpdateID
    self.bids = bids; self.asks = asks; self.eventTimeMs = eventTimeMs; self.connection = connection
  }
}

public enum BookQuality: Sendable, Equatable { case bootstrapping, ready, resyncing, gapped }

public struct BookCoverage: Sendable, Equatable {
  public enum State: Sendable, Equatable { case unknown, fullSnapshot, snapshotLimited }
  public var state: State = .unknown
  public var requestedLevels = 0
  public var snapshotBidLevels = 0
  public var snapshotAskLevels = 0
  /// 快照里最低的买价 / 最高的卖价：被截断时，这两个价以外的簿是未知的。
  public var bidFloor: Double?
  public var askCeiling: Double?
  public init() {}
}

/// 簿的世代：同一连接上每重建一次 +1，换连接归零。对应原项目确定性的 book_epoch。
public struct BookEpoch: Sendable, Hashable {
  public var connection: Int
  public var generation: Int
}

public enum BookError: Error, Sendable, Equatable {
  case staleConnection(expected: Int, actual: Int)
  case snapshotDoesNotOverlap(snapshot: Int64, first: Int64, final: Int64)
  case sequenceGap(previous: Int64, first: Int64, final: Int64, advertised: Int64?)
  case missingPreviousFinalUpdateID
  case unexpectedPreviousFinalUpdateID
  case missingLocalSequence
  case invalidSnapshotCoverage
  case regressedStreamSnapshot(previous: Int64, snapshot: Int64)
  case invalidMaximumDistance
  case emptySide(BookSide)
  case notReady(BookQuality)
  case crossed(bestBid: Double, bestAsk: Double)
}

public enum BootstrapOutcome: Sendable, Equatable {
  case ready(appliedEvents: Int)
  case waitingForOverlap
}

public enum ApplyOutcome: Sendable, Equatable { case applied, duplicateIgnored }

/// 一侧的价位表，顺手缓存最优价：只有删掉的正是最优价那一档时才整表重算，别的增删都是 O(1)。
struct BookSideLevels: Sendable {
  let isBid: Bool
  private(set) var levels: [Double: Double] = [:]
  /// 快照被截断时，覆盖范围以外、快照之后被增量推成 0、又在保留区间以内的价位：本地「知道那里是空的」。
  /// 覆盖范围以外推成正数的不记——收下了就在 `levels` 里（`knows` 看得见），因为在保留区间外没收就不知道。
  ///
  /// 原来凡是增量推过的价（含推成正数、含保留区间外被拒收的）一律记进来，只有重新同步才清：
  /// 快照永远截断的那几家（币安 1000 档、OKX 400 档）一条连接跑几天，它随「出现过的不同价位」只涨不落；
  /// 被拒收的远价还被当成「知道、是 0」。现在它最多是保留区间里的价位格数，裁远处时一起裁。
  private(set) var touched: Set<Double> = []
  private var best: Double?
  private var bestStale = false

  init(isBid: Bool) { self.isBid = isBid }

  mutating func set(_ price: Double, _ quantity: Double) {
    if quantity == 0 {
      if levels.removeValue(forKey: price) != nil, price == best { bestStale = true }
      return
    }
    levels[price] = quantity
    if bestStale { return }
    if let current = best {
      if isBid ? price > current : price < current { best = price }
    } else {
      best = price
    }
  }

  mutating func touch(_ price: Double) { touched.insert(price) }
  mutating func forget(_ price: Double) { touched.remove(price) }

  /// 保留区间挪了：区间以外那些「知道是空的」价位不再记（回到「不知道」，偏保守）。
  mutating func pruneTouched(keepingFrom floor: Double, to ceiling: Double) {
    guard !touched.isEmpty else { return }
    var far: [Double] = []
    for price in touched where price < floor || price > ceiling { far.append(price) }
    for price in far { touched.remove(price) }
  }

  mutating func removeAll() {
    levels.removeAll(keepingCapacity: true); touched.removeAll(); best = nil; bestStale = false
  }

  /// 一批不是最优价的价位整批删掉（裁远处用）。最优价不在里面，缓存不用动。
  mutating func remove(_ prices: [Double]) {
    for price in prices { levels.removeValue(forKey: price); touched.remove(price) }
  }

  mutating func bestPrice() -> Double? {
    if bestStale {
      best = isBid ? levels.keys.max() : levels.keys.min()
      bestStale = false
    }
    return best
  }

  var isEmpty: Bool { levels.isEmpty }
}

public struct LocalBook: Sendable {
  public let sequenceModel: DepthSequenceModel
  public private(set) var connection: Int
  public private(set) var epoch: BookEpoch
  public private(set) var quality: BookQuality = .bootstrapping
  public private(set) var lastUpdateID: Int64?
  public private(set) var coverage = BookCoverage()
  public private(set) var sourceEventTimeMs: Int64?
  public private(set) var lastError: BookError?
  var bids = BookSideLevels(isBid: true)
  var asks = BookSideLevels(isBid: false)
  /// 只留中间价两侧这么远（bps）以内的价位；nil 不裁（原样照搬原项目时的行为）。
  ///
  /// 审查第 36 项：增量式的簿随增量一直长，有的交易所首帧就下发整本簿（BTC 现货数万档），而订单流只看
  /// 中间价 ±10% 以内；不裁的话表越长越大，每 500 ms 的评估和最优价重算都要扫整张表。
  /// 主力订单流取扫描半径的两倍：现价走出一倍半径之前，扫描窗里的价位都还在。
  public var retainBps: Double?
  /// 上一次裁剪时算出来的保留区间（含两侧最优价）。增量里落在区间外的新价位不收，删单照删。
  private var retained: (floor: Double, ceiling: Double)?

  public init(sequenceModel: DepthSequenceModel, connection: Int = 0) {
    self.sequenceModel = sequenceModel
    self.connection = connection
    self.epoch = BookEpoch(connection: connection, generation: 0)
  }

  public var levelCount: Int { bids.levels.count + asks.levels.count }

  public func quantity(at price: Double, side: BookSide) -> Double {
    (side == .bid ? bids.levels[price] : asks.levels[price]) ?? 0
  }

  // MARK: 快照 + 缓冲增量（REST 快照那一路）

  @discardableResult
  public mutating func bootstrap(_ snapshot: BookSnapshot, buffered: [BookDelta]) throws(BookError) -> BootstrapOutcome {
    try validateIdentity(snapshot.connection)
    quality = .bootstrapping
    lastUpdateID = snapshot.lastUpdateID
    if snapshot.requestedLevels <= 0 || snapshot.bids.count > snapshot.requestedLevels
      || snapshot.asks.count > snapshot.requestedLevels {
      try failSequence(.invalidSnapshotCoverage)
    }
    coverage = Self.coverage(of: snapshot)
    bids.removeAll(); asks.removeAll()
    retained = nil
    Self.write(snapshot.bids, into: &bids)
    Self.write(snapshot.asks, into: &asks)
    sourceEventTimeMs = snapshot.eventTimeMs
    try validateNotCrossed()
    trimFarLevels()

    let L = snapshot.lastUpdateID
    let firstIndex: Int? = switch sequenceModel {
    case .rangeOverlap, .strictIncrementing, .previousFinalExact:
      buffered.firstIndex { $0.finalUpdateID > L }
    case .previousFinalOverlap:
      buffered.firstIndex { $0.finalUpdateID >= L }
    }
    guard let firstIndex else { return .waitingForOverlap }

    let first = buffered[firstIndex]
    try validateIdentity(first.connection)
    let noOverlap = BookError.snapshotDoesNotOverlap(snapshot: L, first: first.firstUpdateID, final: first.finalUpdateID)
    switch sequenceModel {
    case .rangeOverlap:
      if first.previousFinalUpdateID != nil { try failSequence(.unexpectedPreviousFinalUpdateID) }
      let required = L &+ 1
      if first.firstUpdateID > required || first.finalUpdateID < required { try failSequence(noOverlap) }
    case .previousFinalOverlap:
      if first.previousFinalUpdateID == nil { try failSequence(.missingPreviousFinalUpdateID) }
      if first.firstUpdateID > L || first.finalUpdateID < L { try failSequence(noOverlap) }
    case .previousFinalExact:
      if first.previousFinalUpdateID != L { try failSequence(noOverlap) }
    case .strictIncrementing:
      if first.previousFinalUpdateID != nil || first.finalUpdateID != L &+ 1 { try failSequence(noOverlap) }
    }
    applyLevels(first)
    lastUpdateID = first.finalUpdateID
    quality = .ready
    lastError = nil
    try validateNotCrossed()

    var applied = 1
    for event in buffered[(firstIndex + 1)...] {
      if try apply(event) == .applied { applied += 1 }
    }
    return .ready(appliedEvents: applied)
  }

  // MARK: 增量

  @discardableResult
  public mutating func apply(_ delta: BookDelta) throws(BookError) -> ApplyOutcome {
    guard quality == .ready else { throw .notReady(quality) }
    try validateIdentity(delta.connection)
    guard let previous = lastUpdateID else { throw .missingLocalSequence }
    if delta.finalUpdateID <= previous { return .duplicateIgnored }
    let gap = BookError.sequenceGap(previous: previous, first: delta.firstUpdateID,
                                    final: delta.finalUpdateID, advertised: delta.previousFinalUpdateID)
    switch sequenceModel {
    case .rangeOverlap:
      if delta.previousFinalUpdateID != nil { try failSequence(.unexpectedPreviousFinalUpdateID) }
      let required = previous &+ 1
      if delta.firstUpdateID > required || delta.finalUpdateID < required {
        try failSequence(.sequenceGap(previous: previous, first: delta.firstUpdateID,
                                      final: delta.finalUpdateID, advertised: nil))
      }
    case .previousFinalOverlap, .previousFinalExact:
      if delta.previousFinalUpdateID != previous { try failSequence(gap) }
    case .strictIncrementing:
      if delta.previousFinalUpdateID != nil || delta.firstUpdateID != previous &+ 1
        || delta.finalUpdateID != delta.firstUpdateID {
        try failSequence(gap)
      }
    }
    applyLevels(delta)
    lastUpdateID = delta.finalUpdateID
    try validateNotCrossed()
    return .applied
  }

  // MARK: 流内权威快照（快照随增量流一起下发的那几家的 snapshot 帧）

  public mutating func replaceFromStreamSnapshot(_ snapshot: BookSnapshot) throws(BookError) {
    try validateIdentity(snapshot.connection)
    if let previous = lastUpdateID, snapshot.lastUpdateID < previous {
      try failSequence(.regressedStreamSnapshot(previous: previous, snapshot: snapshot.lastUpdateID))
    }
    if snapshot.requestedLevels <= 0 || snapshot.bids.count > snapshot.requestedLevels
      || snapshot.asks.count > snapshot.requestedLevels {
      try failSequence(.invalidSnapshotCoverage)
    }
    beginResync(connection: snapshot.connection)
    coverage = Self.coverage(of: snapshot)
    Self.write(snapshot.bids, into: &bids)
    Self.write(snapshot.asks, into: &asks)
    lastUpdateID = snapshot.lastUpdateID
    sourceEventTimeMs = snapshot.eventTimeMs
    quality = .ready
    lastError = nil
    try validateNotCrossed()
    trimFarLevels()
  }

  public mutating func beginResync(connection newConnection: Int) {
    let generation = newConnection == connection ? epoch.generation &+ 1 : 0
    connection = newConnection
    epoch = BookEpoch(connection: newConnection, generation: generation)
    quality = .resyncing
    lastUpdateID = nil
    bids.removeAll(); asks.removeAll()
    retained = nil
    coverage = BookCoverage()
    sourceEventTimeMs = nil
  }

  /// 原项目的 fail_sequence：清簿、置 Gapped、世代 +1，并把错误原样抛出。
  public mutating func failSequence(_ error: BookError) throws(BookError) -> Never {
    markGapped(error)
    throw error
  }

  public mutating func markGapped(_ error: BookError) {
    epoch.generation &+= 1
    quality = .gapped
    lastUpdateID = nil
    bids.removeAll(); asks.removeAll()
    retained = nil
    coverage = BookCoverage()
    sourceEventTimeMs = nil
    lastError = error
  }

  // MARK: 视图

  public mutating func bestBid() -> Double? { bids.bestPrice() }
  public mutating func bestAsk() -> Double? { asks.bestPrice() }

  /// 每侧最优的前 n 档（买降序、卖升序）。
  public func view(levels n: Int) -> (bids: [BookLevel], asks: [BookLevel]) {
    let b = bids.levels.sorted { $0.key > $1.key }.prefix(n).map { BookLevel(price: $0.key, quantity: $0.value) }
    let a = asks.levels.sorted { $0.key < $1.key }.prefix(n).map { BookLevel(price: $0.key, quantity: $0.value) }
    return (Array(b), Array(a))
  }

  /// 中间价两侧 `bps` 以内的全部价位，不截档数。对应原项目 view_within_distance。
  public mutating func viewWithinDistance(_ bps: Double) throws(BookError) -> (mid: Double, bids: [BookLevel], asks: [BookLevel]) {
    guard bps.isFinite, bps > 0 else { throw .invalidMaximumDistance }
    guard let bestBid = bids.bestPrice() else { throw .emptySide(.bid) }
    guard let bestAsk = asks.bestPrice() else { throw .emptySide(.ask) }
    let mid = (bestBid + bestAsk) / 2
    let fraction = bps / 10_000
    let floor = mid * (1 - fraction), ceiling = mid * (1 + fraction)
    let b = bids.levels.filter { $0.key >= floor }.sorted { $0.key > $1.key }
      .map { BookLevel(price: $0.key, quantity: $0.value) }
    let a = asks.levels.filter { $0.key <= ceiling }.sorted { $0.key < $1.key }
      .map { BookLevel(price: $0.key, quantity: $0.value) }
    return (mid, b, a)
  }

  /// 中间价两侧 `bps` 以内的每一档，逐档回调、不排序（主力订单流每 500 ms 走一遍，省掉排序）。
  /// 返回中间价；任一侧为空、`bps` 非法时不回调、返回 nil。设了 `retainBps` 时顺手把保留区间以外的价位裁掉
  /// （同一遍扫描里记下、扫完再删），保留区间也跟着这一拍的中间价挪。
  @discardableResult
  public mutating func forEachLevel(withinBps bps: Double, _ body: (BookSide, Double, Double) -> Void) -> Double? {
    guard bps.isFinite, bps > 0, let bestBid = bids.bestPrice(), let bestAsk = asks.bestPrice() else { return nil }
    let mid = (bestBid + bestAsk) / 2
    let fraction = bps / 10_000
    let floor = mid * (1 - fraction), ceiling = mid * (1 + fraction)
    let keep = retainedBand(mid: mid, bestBid: bestBid, bestAsk: bestAsk)
    var farBids: [Double] = [], farAsks: [Double] = []
    for (price, quantity) in bids.levels {
      if price >= floor { body(.bid, price, quantity) } else if let keep, price < keep.floor { farBids.append(price) }
    }
    for (price, quantity) in asks.levels {
      if price <= ceiling { body(.ask, price, quantity) } else if let keep, price > keep.ceiling { farAsks.append(price) }
    }
    bids.remove(farBids); asks.remove(farAsks)
    if let keep {
      bids.pruneTouched(keepingFrom: keep.floor, to: keep.ceiling)
      asks.pruneTouched(keepingFrom: keep.floor, to: keep.ceiling)
    }
    retained = keep
    return mid
  }

  /// 同一份簿内容（世代、质量、序号、各价位）——对应原项目 deterministic_state_hash 的比较用途。
  public func sameState(as other: LocalBook) -> Bool {
    epoch == other.epoch && quality == other.quality && lastUpdateID == other.lastUpdateID
      && bids.levels == other.bids.levels && asks.levels == other.asks.levels
  }

  // MARK: 内部

  private func validateIdentity(_ actual: Int) throws(BookError) {
    if actual != connection { throw .staleConnection(expected: connection, actual: actual) }
  }

  private mutating func applyLevels(_ delta: BookDelta) {
    Self.write(delta.bids, into: &bids, within: retained)
    Self.write(delta.asks, into: &asks, within: retained)
    if bidsLimited, let floor = coverage.bidFloor {
      Self.noteBeyondCoverage(delta.bids, into: &bids, beyond: { $0 < floor }, within: retained)
    }
    if asksLimited, let ceiling = coverage.askCeiling {
      Self.noteBeyondCoverage(delta.asks, into: &asks, beyond: { $0 > ceiling }, within: retained)
    }
    sourceEventTimeMs = delta.eventTimeMs
  }

  /// 快照这一侧回的档数够到要的数：可能被截断，最远那一档以外不算知道。
  private var bidsLimited: Bool { coverage.requestedLevels > 0 && coverage.snapshotBidLevels >= coverage.requestedLevels }
  private var asksLimited: Bool { coverage.requestedLevels > 0 && coverage.snapshotAskLevels >= coverage.requestedLevels }

  /// 这一档本地知不知道。快照被截断时（币安 REST 只给 1000 档，BTC 现货合起来才盘口两侧 0.3%），
  /// 快照最远一档以外的价位本地并不知道有没有——只有增量推来、还在表里的，或推成 0、在保留区间以内的才知道
  /// （推来的正数在保留区间外被拒收，仍是不知道）；
  /// 覆盖范围以内「表里没有」就是没有。快照完整（回的档数不到要的数、或流里整本推来）整侧都知道。
  /// 主力订单流靠它区分「墙没了」和「墙在快照盖不到的地方」：重启后读回来的、离盘口 2%–10% 的单
  /// 不能因为新快照没盖到就判成撤单。
  public func knows(_ side: BookSide, price: Double) -> Bool {
    switch side {
    case .bid:
      guard bidsLimited, let floor = coverage.bidFloor else { return true }
      return price >= floor || bids.levels[price] != nil || bids.touched.contains(price)
    case .ask:
      guard asksLimited, let ceiling = coverage.askCeiling else { return true }
      return price <= ceiling || asks.levels[price] != nil || asks.touched.contains(price)
    }
  }

  /// 覆盖范围以外的增量档记账（见 `BookSideLevels.touched`）：推成 0、在保留区间以内的记成「知道是空的」；
  /// 推成正数的不记（收下了看 `levels`，没收下就是不知道），之前记过的一并忘掉；覆盖范围以内的本来就知道，不记。
  private static func noteBeyondCoverage(_ levels: [BookLevel], into side: inout BookSideLevels,
                                         beyond: (Double) -> Bool,
                                         within band: (floor: Double, ceiling: Double)?) {
    for level in levels where valid(level) && beyond(level.price) {
      let inBand = band.map { level.price >= $0.floor && level.price <= $0.ceiling } ?? true
      if level.quantity == 0, inBand { side.touch(level.price) } else { side.forget(level.price) }
    }
  }

  private static func valid(_ level: BookLevel) -> Bool {
    level.price.isFinite && level.price > 0 && level.quantity.isFinite && level.quantity >= 0
  }

  /// `within` 给了时，区间以外的新价位不收（删单 quantity == 0 照删）。
  private static func write(_ levels: [BookLevel], into side: inout BookSideLevels,
                            within band: (floor: Double, ceiling: Double)? = nil) {
    for level in levels where level.price.isFinite && level.price > 0 && level.quantity.isFinite && level.quantity >= 0 {
      if let band, level.quantity > 0, level.price < band.floor || level.price > band.ceiling { continue }
      side.set(level.price, level.quantity)
    }
  }

  /// 按这一刻的中间价算保留区间；两侧最优价永远在区间里（价差大得离谱时也不裁掉最优价）。
  private func retainedBand(mid: Double, bestBid: Double, bestAsk: Double) -> (floor: Double, ceiling: Double)? {
    guard let bps = retainBps, bps.isFinite, bps > 0 else { return nil }
    let fraction = bps / 10_000
    return (min(mid * (1 - fraction), bestBid), max(mid * (1 + fraction), bestAsk))
  }

  /// 整本快照写进来之后裁一次远处（首帧整本下发的那种）。
  private mutating func trimFarLevels() {
    guard retainBps != nil, let bestBid = bids.bestPrice(), let bestAsk = asks.bestPrice(),
          let keep = retainedBand(mid: (bestBid + bestAsk) / 2, bestBid: bestBid, bestAsk: bestAsk) else { return }
    bids.remove(bids.levels.keys.filter { $0 < keep.floor })
    asks.remove(asks.levels.keys.filter { $0 > keep.ceiling })
    bids.pruneTouched(keepingFrom: keep.floor, to: keep.ceiling)
    asks.pruneTouched(keepingFrom: keep.floor, to: keep.ceiling)
    retained = keep
  }

  private mutating func validateNotCrossed() throws(BookError) {
    if let bid = bids.bestPrice(), let ask = asks.bestPrice(), bid >= ask {
      try failSequence(.crossed(bestBid: bid, bestAsk: ask))
    }
  }

  private static func coverage(of snapshot: BookSnapshot) -> BookCoverage {
    var c = BookCoverage()
    c.state = snapshot.bids.count < snapshot.requestedLevels && snapshot.asks.count < snapshot.requestedLevels
      ? .fullSnapshot : .snapshotLimited
    c.requestedLevels = snapshot.requestedLevels
    c.snapshotBidLevels = snapshot.bids.count
    c.snapshotAskLevels = snapshot.asks.count
    c.bidFloor = snapshot.bids.map(\.price).min()
    c.askCeiling = snapshot.asks.map(\.price).max()
    return c
  }
}
