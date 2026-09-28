import XCTest
import Darwin
@testable import KanpanCore

// 订单簿压测（2026-09-28）：主力订单流数据层的吞吐、评估、历史合并、落盘与乱序 / 丢包 / 重放。
//
// 数字用 `【订单簿压测】` 前缀打到标准输出，报告（docs/acceptance/订单簿压测-2026-09-28/数据层.md）从这里抄。
// 断言只卡「数量级不对」（预算放得很宽，debug 构建、机器忙时也不会误报）和正确性不变量；
// 真实耗时看打出来的 p50 / p95 / max，不看断言。

// MARK: - 工具

/// 可复现的伪随机（SplitMix64）：同一个种子每次跑出同一串，压测数字可比。
struct StressRNG {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
  mutating func int(_ range: ClosedRange<Int>) -> Int {
    range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
  }
  mutating func double(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
  mutating func chance(_ p: Double) -> Bool { unit() < p }
}

enum Stress {
  static func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

  /// 量一段代码（毫秒）。
  static func ms(_ body: () throws -> Void) rethrows -> Double {
    let t0 = nowNs()
    try body()
    return Double(nowNs() - t0) / 1e6
  }

  /// 进程常驻内存（MB）。
  static func residentMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : .nan
  }

  static func percentiles(_ xs: [Double]) -> (p50: Double, p95: Double, max: Double) {
    guard !xs.isEmpty else { return (0, 0, 0) }
    let s = xs.sorted()
    func at(_ q: Double) -> Double { s[min(s.count - 1, Int((Double(s.count - 1) * q).rounded()))] }
    return (at(0.5), at(0.95), s.last!)
  }

  static func fmt(_ x: Double, _ digits: Int = 3) -> String { String(format: "%.\(digits)f", x) }

  static func report(_ line: String) { print("【订单簿压测】" + line) }

  #if DEBUG
  static let build = "debug"
  #else
  static let build = "release"
  #endif

  /// BTC 的 13 本簿（币安 6、OKX 6、Coinbase 1），序列规则与快照来路照各家实际。
  /// 名义一律按线性 1 倍：压测看的是吞吐，不看币本位换算。
  static func btcVenues() -> [OrderFlowVenue] {
    let specs: [(String, String, OrderFlowProduct, String, DepthSequenceModel, Bool)] = [
      ("binance", "币安", .usdtPerp, "BTCUSDT", .previousFinalOverlap, false),
      ("binance", "币安", .coinPerp, "BTCUSD_PERP", .previousFinalOverlap, false),
      ("binance", "币安", .spot, "BTCUSDT", .rangeOverlap, false),
      ("binance", "币安", .spot, "BTCUSDC", .rangeOverlap, false),
      ("binance", "币安", .delivery, "BTCUSDT_261225", .previousFinalOverlap, false),
      ("binance", "币安", .delivery, "BTCUSDT_270326", .previousFinalOverlap, false),
      ("okx", "OKX", .usdtPerp, "BTC-USDT-SWAP", .previousFinalExact, true),
      ("okx", "OKX", .usdtPerp, "BTC-USDC-SWAP", .previousFinalExact, true),
      ("okx", "OKX", .coinPerp, "BTC-USD-SWAP", .previousFinalExact, true),
      ("okx", "OKX", .spot, "BTC-USDT", .previousFinalExact, true),
      ("okx", "OKX", .spot, "BTC-USDC", .previousFinalExact, true),
      ("okx", "OKX", .delivery, "BTC-USDT-261225", .previousFinalExact, true),
      ("coinbase", "Coinbase", .spot, "BTC-USD", .strictIncrementing, true),
    ]
    return specs.map {
      OrderFlowVenue(exchange: $0.0, label: $0.1, product: $0.2, instrument: $0.3,
                     notional: .linear(multiplier: 1), sequenceModel: $0.4, snapshotInBand: $0.5)
    }
  }
}

/// 一本「真」簿：整数档位（价 = 档 × tick），买侧在中间价档以下、卖侧以上，永远不交叉。
/// 生成快照与增量，并把增量同步记到自己身上——它就是乱序用例里的「地面真值」。
struct SyntheticBook {
  let tick: Double
  let midTick: Int
  var bids: [Int: Double] = [:]
  var asks: [Int: Double] = [:]
  /// 数量分布（币）。
  let qty: ClosedRange<Double>

  init(tick: Double, midTick: Int, levels: Int, qty: ClosedRange<Double>, rng: inout StressRNG) {
    self.tick = tick; self.midTick = midTick; self.qty = qty
    for k in 1...levels {
      bids[midTick - k] = rng.double(qty.lowerBound, qty.upperBound)
      asks[midTick + k] = rng.double(qty.lowerBound, qty.upperBound)
    }
  }

  func price(_ t: Int) -> Double { Double(t) * tick }

  func snapshot(lastUpdateID: Int64, requestedLevels: Int) -> BookSnapshot {
    BookSnapshot(lastUpdateID: lastUpdateID, requestedLevels: requestedLevels,
                 bids: bids.sorted { $0.key > $1.key }.prefix(requestedLevels).map { BookLevel(price: price($0.key), quantity: $0.value) },
                 asks: asks.sorted { $0.key < $1.key }.prefix(requestedLevels).map { BookLevel(price: price($0.key), quantity: $0.value) })
  }

  /// `changes` 档变动：两成删、其余改成新数量；离中间价最远 `reach` 档（可以超出快照覆盖）。
  mutating func changes(_ changes: Int, reach: Int, rng: inout StressRNG) -> (bids: [BookLevel], asks: [BookLevel]) {
    var b: [BookLevel] = [], a: [BookLevel] = []
    b.reserveCapacity(changes / 2 + 1); a.reserveCapacity(changes / 2 + 1)
    for _ in 0..<changes {
      let offset = rng.int(1...reach)
      let q = rng.chance(0.2) ? 0 : rng.double(qty.lowerBound, qty.upperBound)
      if rng.chance(0.5) {
        let t = midTick - offset
        if q == 0 { bids[t] = nil } else { bids[t] = q }
        b.append(BookLevel(price: price(t), quantity: q))
      } else {
        let t = midTick + offset
        if q == 0 { asks[t] = nil } else { asks[t] = q }
        a.append(BookLevel(price: price(t), quantity: q))
      }
    }
    return (b, a)
  }
}

/// 按各家的序列规则给增量编号。
struct SequenceDriver {
  let model: DepthSequenceModel
  var last: Int64

  /// 下一条（接在 `last` 后面）。
  mutating func next(bids: [BookLevel], asks: [BookLevel], connection: Int = 0) -> BookDelta {
    let d: BookDelta
    switch model {
    case .rangeOverlap:
      d = BookDelta(firstUpdateID: last + 1, finalUpdateID: last + 3, previousFinalUpdateID: nil, bids: bids, asks: asks)
      last += 3
    case .previousFinalOverlap:
      d = BookDelta(firstUpdateID: last + 1, finalUpdateID: last + 3, previousFinalUpdateID: last, bids: bids, asks: asks)
      last += 3
    case .previousFinalExact:
      d = BookDelta(firstUpdateID: last + 1, finalUpdateID: last + 1, previousFinalUpdateID: last, bids: bids, asks: asks)
      last += 1
    case .strictIncrementing:
      d = BookDelta(firstUpdateID: last + 1, finalUpdateID: last + 1, previousFinalUpdateID: nil, bids: bids, asks: asks)
      last += 1
    }
    return d
  }

  /// 快照之后能接上它的第一条空增量（REST 那一路缓冲里要有一条够得着快照的）。
  mutating func bridge(after snapshotID: Int64) -> BookDelta {
    switch model {
    case .previousFinalOverlap:
      // 币安合约：U ≤ lastUpdateId ≤ u。
      last = snapshotID + 2
      return BookDelta(firstUpdateID: snapshotID - 1, finalUpdateID: snapshotID + 2, previousFinalUpdateID: snapshotID - 2)
    default:
      last = snapshotID
      return next(bids: [], asks: [])
    }
  }
}

// MARK: - 1. 簿吞吐

final class OrderFlowStressBookTests: XCTestCase {

  /// 13 本 BTC 簿：各 1000 档快照（截断的，照币安 REST），之后每 100 ms 一帧、每本一条 200–500 档变动的增量，600 帧。
  func testThirteenBooksSixHundredFramesOfHeavyDeltas() throws {
    var rng = StressRNG(seed: 0xB00C)
    let venues = Stress.btcVenues()
    var truths: [SyntheticBook] = []
    var drivers: [SequenceDriver] = []
    var books: [VenueBook] = []
    let snapshotID: Int64 = 1_000_000
    let rssBefore = Stress.residentMB()
    for venue in venues {
      let truth = SyntheticBook(tick: 0.1, midTick: 600_000, levels: 1_000, qty: 0.001...3, rng: &rng)
      var driver = SequenceDriver(model: venue.sequenceModel, last: snapshotID)
      var book = VenueBook(venue: venue)
      _ = book.connectionOpened()
      let snap = truth.snapshot(lastUpdateID: snapshotID, requestedLevels: 1_000)
      if venue.snapshotInBand {
        XCTAssertEqual(book.ingest(.snapshot(snap), nowMs: 0), .none)
      } else {
        XCTAssertEqual(book.ingest(.delta(driver.bridge(after: snapshotID)), nowMs: 0), .none)
        XCTAssertEqual(book.applySnapshot(snap, nowMs: 0), .none)
      }
      XCTAssertTrue(book.isReady, venue.id)
      truths.append(truth); drivers.append(driver); books.append(book)
    }
    let levelsBefore = books.reduce(0) { $0 + $1.book.levelCount }

    // 先把 600 帧 × 13 本的增量全生成好，计时只算簿吃增量。
    let frames = 600
    var deltas: [[BookDelta]] = Array(repeating: [], count: frames)
    var changeCount = 0
    for f in 0..<frames {
      for i in venues.indices {
        let n = rng.int(200...500)
        changeCount += n
        let c = truths[i].changes(n, reach: 1_200, rng: &rng)
        deltas[f].append(drivers[i].next(bids: c.bids, asks: c.asks))
      }
    }
    let rssGenerated = Stress.residentMB()

    var frameMs: [Double] = []
    frameMs.reserveCapacity(frames)
    var perDeltaUs: [Double] = []
    perDeltaUs.reserveCapacity(frames * venues.count)
    var notReady = 0
    for f in 0..<frames {
      let t0 = Stress.nowNs()
      for i in venues.indices {
        let d0 = Stress.nowNs()
        if books[i].ingest(.delta(deltas[f][i]), nowMs: Int64(f) * 100) != .none { notReady += 1 }
        perDeltaUs.append(Double(Stress.nowNs() - d0) / 1e3)
      }
      frameMs.append(Double(Stress.nowNs() - t0) / 1e6)
    }
    let levelsAfter = books.reduce(0) { $0 + $1.book.levelCount }
    // 评估那一拍会顺手裁远处：再走一遍扫描，看表长不长。
    let scheme = try XCTUnwrap(BucketScheme(step: 10))
    for i in books.indices { _ = books[i].buckets(scheme: scheme, radiusBps: OrderFlowDefaults.scanRadiusBps) }
    let levelsAfterScan = books.reduce(0) { $0 + $1.book.levelCount }
    let rssAfter = Stress.residentMB()

    XCTAssertEqual(notReady, 0, "连续的增量不该触发任何重拉 / 重订")
    XCTAssertTrue(books.allSatisfy(\.isReady))
    let fp = Stress.percentiles(frameMs), dp = Stress.percentiles(perDeltaUs)
    Stress.report("簿吞吐[\(Stress.build)] 13 本 × 600 帧、每帧每本 200–500 档（共 \(changeCount) 档变动）："
      + "一帧（13 本各一条）p50 \(Stress.fmt(fp.p50)) ms / p95 \(Stress.fmt(fp.p95)) ms / max \(Stress.fmt(fp.max)) ms；"
      + "单条增量 p50 \(Stress.fmt(dp.p50, 1)) µs / p95 \(Stress.fmt(dp.p95, 1)) µs / max \(Stress.fmt(dp.max, 1)) µs")
    Stress.report("簿吞吐[\(Stress.build)] 档数 13 本合计：快照后 \(levelsBefore) → 600 帧后 \(levelsAfter) → 扫描裁剪后 \(levelsAfterScan)；"
      + "常驻内存 起 \(Stress.fmt(rssBefore, 1)) MB / 增量生成后 \(Stress.fmt(rssGenerated, 1)) MB / 跑完 \(Stress.fmt(rssAfter, 1)) MB")
    // 数量级闸：一帧 13 本在 debug 下也该远小于 100 ms（一帧的间隔）。
    XCTAssertLessThan(fp.p95, 100, "13 本一帧吃不完 100 ms：簿更新跟不上推送")
    // 档数不随时间无界增长：reach 1200 档 × 2 侧 × 13 本是上界。
    XCTAssertLessThanOrEqual(levelsAfter, 13 * 2 * 1_200)
  }
}

// MARK: - 2. 模型评估、上限与裁剪

final class OrderFlowStressModelTests: XCTestCase {
  static let step = 10.0
  static let threshold = 1_100_000.0
  static let thresholds = OrderFlowThresholds(spot: threshold, usdtPerp: threshold, coinPerp: threshold,
                                              delivery: threshold, step: step)
  static let t0: Int64 = 1_800_000_000_000

  /// 13 本簿各 2000 档（1 美元一档，BTC 6 万附近 ±1000 美元），每档 0.5–3 个币：10 美元一桶合计约 105 万 ± 14 万，
  /// 门槛 110 万时每本约三分之一的桶过门槛——几百条同时挂着。
  static func readyModel(restored: OrderFlowJournal? = nil, rng: inout StressRNG)
    -> (OrderFlowModel, [SyntheticBook], [SequenceDriver], [OrderFlowVenue]) {
    var model = OrderFlowModel(symbol: "BTCUSDT", thresholds: thresholds, restored: restored)
    let venues = Stress.btcVenues()
    var truths: [SyntheticBook] = [], drivers: [SequenceDriver] = []
    let snapshotID: Int64 = 5_000
    for venue in venues {
      model.addVenue(venue)
      let truth = SyntheticBook(tick: 1, midTick: 60_000, levels: 1_000, qty: 0.5...3, rng: &rng)
      var driver = SequenceDriver(model: venue.sequenceModel, last: snapshotID)
      _ = model.connectionOpened(venue.id)
      // 完整快照（要 5000 档回 1000 档）：整侧都「知道」，读回的单不会卡在覆盖范围外。
      let snap = truth.snapshot(lastUpdateID: snapshotID, requestedLevels: 5_000)
      if venue.snapshotInBand {
        _ = model.ingest(venue.id, .snapshot(snap), nowMs: t0)
      } else {
        _ = model.ingest(venue.id, .delta(driver.bridge(after: snapshotID)), nowMs: t0)
        _ = model.applySnapshot(venue.id, snap, nowMs: t0)
      }
      truths.append(truth); drivers.append(driver)
    }
    return (model, truths, drivers, venues)
  }

  /// 结束了的单若干条，散在 [now − 3 天 + 1 小时, now − 1 分钟]，桶号离现价很远（不和实时的撞键）。
  static func endedOrders(_ count: Int, venues: [OrderFlowVenue], nowMs: Int64, within spanMs: Int64,
                          rng: inout StressRNG) -> [BigOrder] {
    (0..<count).map { k in
      let venue = venues[k % venues.count]
      let end = nowMs - 60_000 - Int64(rng.double(0, Double(spanMs - 3_600_000)))
      let life = Int64(rng.double(1_000, 7_200_000))
      let bucket = Int64(20_000 + rng.int(0...20_000))
      let status: BigOrder.Status = [.filled, .cancelled, .lost][k % 3]
      return BigOrder(venueID: venue.id, exchange: venue.label, product: venue.product, side: k % 2 == 0 ? .bid : .ask,
                      bucket: bucket, price: Double(bucket) * step + 3, firstSeenMs: end - life, endMs: end,
                      status: status, initialNotional: threshold * 1.5, notional: threshold * 0.2,
                      filledNotional: threshold * 0.3, threshold: threshold,
                      vanishedNotional: status == .lost ? nil : threshold * 1.3)
    }
  }

  /// 每 500 ms 一拍，拍间每本吃一条 200–500 档的增量；13 本 × 2000 档、几百条挂着。
  func testEvaluateEveryHalfSecondThirteenBooks() {
    var rng = StressRNG(seed: 0xE7A1)
    var (model, truths, drivers, venues) = Self.readyModel(rng: &rng)
    var evalMs: [Double] = [], ingestMs: [Double] = []
    var live = 0, maxLive = 0
    let ticks = 240  // 2 分钟
    for k in 1...ticks {
      let now = Self.t0 + Int64(k) * 500
      let t = Stress.nowNs()
      for i in venues.indices {
        let c = truths[i].changes(rng.int(200...500), reach: 1_000, rng: &rng)
        XCTAssertEqual(model.ingest(venues[i].id, .delta(drivers[i].next(bids: c.bids, asks: c.asks)), nowMs: now), .none)
      }
      ingestMs.append(Double(Stress.nowNs() - t) / 1e6)
      var frame = OrderFlowSnapshot.loading("x")
      evalMs.append(Stress.ms { frame = model.evaluate(nowMs: now) })
      live = frame.orders.count(where: \.isLive)
      maxLive = max(maxLive, live)
    }
    let ended = model.orders.count - live
    let p = Stress.percentiles(evalMs), q = Stress.percentiles(ingestMs)
    Stress.report("评估[\(Stress.build)] 13 本 × 2000 档、每 500 ms 一拍 × \(ticks) 拍：挂着 \(live) 条（峰值 \(maxLive)）、已结束 \(ended) 条；"
      + "单次 evaluate p50 \(Stress.fmt(p.p50)) ms / p95 \(Stress.fmt(p.p95)) ms / max \(Stress.fmt(p.max)) ms；"
      + "拍间 13 条增量 p50 \(Stress.fmt(q.p50)) ms / p95 \(Stress.fmt(q.p95)) ms")
    XCTAssertGreaterThan(maxLive, 200, "压测场景应有几百条同时挂着")
    XCTAssertLessThan(p.p95, 250, "一次评估吃掉半拍以上")
  }

  /// 满额：3 天、2 万条已结束（不超额，每拍只做过期检查）；再多 2000 条超额（第一拍挤到九成）。
  func testEvaluateAndPruneAtTheCap() {
    var rng = StressRNG(seed: 0xCA9)
    let venues = Stress.btcVenues()
    let savedAt = Self.t0 - 1_000

    // a) 正好 2 万条：稳态每拍的开销（过期扫描、removeAll、帧里带 2 万条）。
    let atCap = Self.endedOrders(OrderFlowDefaults.maxEndedOrders, venues: venues, nowMs: Self.t0,
                                 within: OrderFlowDefaults.retentionMs, rng: &rng)
    var (model, truths, drivers, _) = Self.readyModel(
      restored: OrderFlowJournal(symbol: "BTCUSDT", step: Self.step, savedAtMs: savedAt, orders: atCap), rng: &rng)
    XCTAssertEqual(model.orders.count, OrderFlowDefaults.maxEndedOrders)
    var evalMs: [Double] = [], sameMs: [Double] = []
    var last: OrderFlowSnapshot?
    for k in 1...60 {
      let now = Self.t0 + Int64(k) * 500
      for i in venues.indices {
        let c = truths[i].changes(rng.int(200...500), reach: 1_000, rng: &rng)
        _ = model.ingest(venues[i].id, .delta(drivers[i].next(bids: c.bids, asks: c.asks)), nowMs: now)
      }
      var frame = OrderFlowSnapshot.loading("x")
      evalMs.append(Stress.ms { frame = model.evaluate(nowMs: now) })
      if let last { sameMs.append(Stress.ms { _ = last.sameContent(as: frame) }) }
      last = frame
    }
    let journalMs = Stress.ms { _ = model.journal(nowMs: Self.t0 + 30_000) }
    let p = Stress.percentiles(evalMs), s = Stress.percentiles(sameMs)
    Stress.report("满额[\(Stress.build)] 2 万条已结束 + 13 本实时：evaluate p50 \(Stress.fmt(p.p50)) ms / p95 \(Stress.fmt(p.p95)) ms / max \(Stress.fmt(p.max)) ms；"
      + "出帧去重 sameContent p50 \(Stress.fmt(s.p50)) ms / max \(Stress.fmt(s.max)) ms；从 2 万多条挑落盘那 5000 条 \(Stress.fmt(journalMs)) ms")

    // b) 超额 2000 条：第一拍挤到 1.8 万（先挤活得短的），之后回到稳态。
    let over = Self.endedOrders(OrderFlowDefaults.maxEndedOrders + 2_000, venues: venues, nowMs: Self.t0,
                                within: OrderFlowDefaults.retentionMs, rng: &rng)
    var (m2, t2, d2, _) = Self.readyModel(
      restored: OrderFlowJournal(symbol: "BTCUSDT", step: Self.step, savedAtMs: savedAt, orders: over), rng: &rng)
    var first = OrderFlowSnapshot.loading("x")
    let pruneMs = Stress.ms { first = m2.evaluate(nowMs: Self.t0 + 500) }
    let keep = Int(Double(OrderFlowDefaults.maxEndedOrders) * OrderFlowDefaults.trimRatio)
    XCTAssertEqual(first.orders.count(where: { !$0.isLive }), keep, "超额一次挤到九成")
    XCTAssertEqual(Set(first.orders.map(\.id)).count, first.orders.count, "挤完之后 id 不重复")
    var after: [Double] = []
    for k in 2...21 {
      let now = Self.t0 + Int64(k) * 500
      for i in venues.indices {
        let c = t2[i].changes(rng.int(200...500), reach: 1_000, rng: &rng)
        _ = m2.ingest(venues[i].id, .delta(d2[i].next(bids: c.bids, asks: c.asks)), nowMs: now)
      }
      after.append(Stress.ms { _ = m2.evaluate(nowMs: now) })
    }
    // c) 3 天边界：把钟拨到最老那批过期，一拍里删掉它们。
    let expireAt = Self.t0 + 36 * 3_600_000
    var expireFrame = OrderFlowSnapshot.loading("x")
    let expireMs = Stress.ms { expireFrame = m2.evaluate(nowMs: expireAt) }
    let q = Stress.percentiles(after)
    Stress.report("裁剪[\(Stress.build)] 2.2 万条 → 挤到 \(keep) 条那一拍 evaluate \(Stress.fmt(pruneMs)) ms；之后 20 拍 p50 \(Stress.fmt(q.p50)) ms / max \(Stress.fmt(q.max)) ms；"
      + "钟拨过 36 小时后一拍删掉过期的（剩 \(expireFrame.orders.count) 条）\(Stress.fmt(expireMs)) ms")
    XCTAssertLessThan(pruneMs, 1_000)
    XCTAssertTrue(expireFrame.orders.allSatisfy { $0.isLive || ($0.endMs ?? 0) >= expireAt - OrderFlowDefaults.retentionMs })
  }
}

// MARK: - 4. 服务端历史合并

final class OrderFlowStressHistoryTests: XCTestCase {
  typealias M = OrderFlowStressModelTests

  /// 本机 N 条（结束的 + 挂着的）+ 服务端一页 2065 条：600 条与本机结束的重叠、200 条与本机挂着的是同一条、1265 条新的。
  private func scenario(localEnded: Int, rng: inout StressRNG)
    -> (model: OrderFlowModel, page: OrderFlowHistoryPage, overlappedEnded: Set<String>, adoptedLive: Set<String>) {
    let venues = Stress.btcVenues()
    let now = M.t0
    var local = M.endedOrders(localEnded, venues: venues, nowMs: now, within: OrderFlowDefaults.retentionMs, rng: &rng)
    // 本机挂着的 300 条：桶号 50_000 起，一键一条。
    for k in 0..<300 {
      let venue = venues[k % venues.count]
      local.append(BigOrder(venueID: venue.id, exchange: venue.label, product: venue.product, side: .bid,
                            bucket: Int64(50_000 + k), price: Double(50_000 + k) * M.step, firstSeenMs: now - 600_000,
                            initialNotional: M.threshold * 2, notional: M.threshold * 2, threshold: M.threshold))
    }
    let model = OrderFlowModel(symbol: "BTCUSDT", thresholds: M.thresholds,
                               restored: OrderFlowJournal(symbol: "BTCUSDT", step: M.step, savedAtMs: now - 1_000, orders: local))
    var page: [BigOrder] = []
    var overlappedEnded = Set<String>(), adoptedLive = Set<String>()
    // 600 条与本机结束的重叠（服务端版本：晚 1 秒出现、同时结束、状态可能不同）。只挑最近 24 小时内的。
    let recentEnded = model.orders.filter { !$0.isLive && ($0.endMs ?? 0) >= now - 86_400_000 }
    // 同一个键上本机可能有好几条：只挑键上只有这一条的，免得一条服务端单同时盖掉两条、计数对不上。
    var perKey: [String: Int] = [:]
    for o in model.orders { perKey["\(o.venueID)|\(o.side)|\(o.bucket)", default: 0] += 1 }
    for o in recentEnded where perKey["\(o.venueID)|\(o.side)|\(o.bucket)"] == 1 && page.count < 600 {
      var r = o
      r.firstSeenMs = o.firstSeenMs + 1_000
      r.endMs = max(r.firstSeenMs + 1, o.endMs ?? 0)
      r.status = .cancelled
      page.append(r)
      overlappedEnded.insert(o.id)
    }
    // 200 条与本机挂着的是同一条（服务端更早看到它）。
    for o in model.orders.filter(\.isLive).prefix(200) {
      var r = o
      r.firstSeenMs = o.firstSeenMs - 5_000
      page.append(r)
      adoptedLive.insert(o.id)
    }
    // 1265 条新的：桶号 60_000 起，100 条挂着，其余结束。
    for k in 0..<1_265 {
      let venue = venues[k % venues.count]
      let first = now - Int64(rng.double(120_000, 86_000_000))
      let isLive = k < 100
      page.append(BigOrder(venueID: venue.id, exchange: venue.label, product: venue.product, side: k % 2 == 0 ? .ask : .bid,
                           bucket: Int64(60_000 + k), price: Double(60_000 + k) * M.step, firstSeenMs: first,
                           endMs: isLive ? nil : first + 60_000, status: isLive ? .live : .filled,
                           initialNotional: M.threshold * 1.2, notional: M.threshold, filledNotional: M.threshold,
                           threshold: M.threshold, vanishedNotional: isLive ? nil : M.threshold))
    }
    XCTAssertEqual(page.count, 2_065)
    let p = OrderFlowHistoryPage(base: "BTC", thresholds: M.thresholds, trackedSinceMs: now - 3 * 86_400_000,
                                 fromMs: now - 86_400_000, toMs: now, orders: page)
    return (model, p, overlappedEnded, adoptedLive)
  }

  private func key(_ o: BigOrder) -> String { "\(o.venueID)|\(o.side.rawValue)|\(o.bucket)" }

  private func assertInvariants(_ orders: [BigOrder], _ label: String) {
    XCTAssertEqual(Set(orders.map(\.id)).count, orders.count, "\(label)：有重复 id")
    var liveKeys = Set<String>()
    for o in orders where o.isLive { XCTAssertTrue(liveKeys.insert(key(o)).inserted, "\(label)：同一键上挂着两条 \(key(o))") }
    XCTAssertTrue(zip(orders, orders.dropFirst()).allSatisfy { !OrderFlowModel.chronological($1, $0) }, "\(label)：没按出现时刻排")
  }

  /// 不超额（1.7 万 + 2065）：逐条核对不丢不重；同一页再并一次不变（幂等）。
  func testMergeTwoThousandIntoSeventeenThousandLosesAndDuplicatesNothing() {
    var rng = StressRNG(seed: 0x4157)
    var (model, page, overlapped, adopted) = scenario(localEnded: 17_000, rng: &rng)
    let before = model.orders
    var result = OrderFlowModel.HistoryMerge.pending
    let mergeMs = Stress.ms { result = model.mergeHistory(page, chartScale: 1, nowMs: M.t0) }
    XCTAssertEqual(result, .merged)
    assertInvariants(model.orders, "第一次并")
    let ids = Set(model.orders.map(\.id))
    // 服务端每一条都在（挂着的同一条被本机接着跟，id 换成服务端的出现时刻）。
    for r in page.orders { XCTAssertTrue(ids.contains(r.id), "服务端那条丢了：\(r.id)") }
    // 本机只有的都留着；被服务端覆盖的 600 条换成了服务端版本；挂着的 200 条被接管、没多出一条。
    let untouched = before.filter { !overlapped.contains($0.id) && !adopted.contains($0.id) }
    for o in untouched { XCTAssertTrue(ids.contains(o.id), "本机只有的那条丢了：\(o.id)") }
    for id in overlapped { XCTAssertFalse(ids.contains(id), "重叠的本机版本没被服务端换掉：\(id)") }
    XCTAssertEqual(model.orders.count, before.count - overlapped.count + page.orders.count - adopted.count)
    XCTAssertEqual(model.orders.count(where: \.isLive), 300 + 100)

    // 同一页再并一次（增量那一页往前退 5 分钟，重叠是常态）：一条都不能多。
    let snapshot = model.orders
    let againMs = Stress.ms { _ = model.mergeHistory(page, chartScale: 1, nowMs: M.t0 + 60_000) }
    assertInvariants(model.orders, "第二次并")
    XCTAssertEqual(model.orders.count, snapshot.count, "同一页并两次多出了单")
    XCTAssertEqual(Set(model.orders.map(\.id)), Set(snapshot.map(\.id)))
    Stress.report("历史合并[\(Stress.build)] 本机 17300 条 + 服务端 2065 条：第一次 \(Stress.fmt(mergeMs)) ms、同页再并 \(Stress.fmt(againMs)) ms；"
      + "合并后 \(model.orders.count) 条，逐条核对不丢不重")
  }

  /// 满额（2 万 + 2065）：合并后超额、当场挤到九成；量耗时，并看服务端刚给的最近 2 小时那批有没有被挤掉。
  func testMergeIntoAFullModel() {
    var rng = StressRNG(seed: 0x4158)
    var (model, page, _, _) = scenario(localEnded: 20_000, rng: &rng)
    let mergeMs = Stress.ms { _ = model.mergeHistory(page, chartScale: 1, nowMs: M.t0) }
    assertInvariants(model.orders, "满额合并")
    let ended = model.orders.count(where: { !$0.isLive })
    let recentIDs = Set(page.orders.filter { ($0.endMs ?? M.t0) >= M.t0 - OrderFlowDefaults.recentKeepMs }.map(\.id))
    let ids = Set(model.orders.map(\.id))
    let keptRecent = recentIDs.filter { ids.contains($0) }.count
    Stress.report("历史合并[\(Stress.build)] 满额 20300 + 2065：\(Stress.fmt(mergeMs)) ms，合并后已结束 \(ended) 条（上限 \(OrderFlowDefaults.maxEndedOrders)）；"
      + "服务端最近 2 小时的 \(recentIDs.count) 条留下 \(keptRecent) 条")
    XCTAssertLessThanOrEqual(ended, OrderFlowDefaults.maxEndedOrders)
    XCTAssertEqual(keptRecent, recentIDs.count, "最近 2 小时结束的不该被挤掉")
    XCTAssertLessThan(mergeMs, 2_000)
  }
}

// MARK: - 5. 落盘日志

final class OrderFlowStressJournalTests: XCTestCase {
  typealias M = OrderFlowStressModelTests

  func testJournalOfFiveThousandOrdersAndCorruptFiles() throws {
    var rng = StressRNG(seed: 0x10A)
    let venues = Stress.btcVenues()
    var orders = M.endedOrders(4_800, venues: venues, nowMs: M.t0, within: OrderFlowDefaults.journalRetentionMs, rng: &rng)
    for k in 0..<200 {
      let venue = venues[k % venues.count]
      orders.append(BigOrder(venueID: venue.id, exchange: venue.label, product: venue.product, side: .ask,
                             bucket: Int64(70_000 + k), price: Double(70_000 + k) * M.step + 0.37, firstSeenMs: M.t0 - 900_000,
                             initialNotional: 1_234_567.89, notional: 2_345_678.91, filledNotional: 12_345.6,
                             threshold: M.threshold))
    }
    let model = OrderFlowModel(symbol: "BTCUSDT", thresholds: M.thresholds,
                               restored: OrderFlowJournal(symbol: "BTCUSDT", step: M.step, savedAtMs: M.t0 - 1_000, orders: orders))
    XCTAssertEqual(model.orders.count, 5_000)

    var journal: OrderFlowJournal?
    let pickMs = Stress.ms { journal = model.journal(nowMs: M.t0) }
    let j = try XCTUnwrap(journal)
    XCTAssertEqual(j.orders.count, 5_000)
    var data = Data()
    let encodeMs = Stress.ms { data = j.encoded() }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orderflow-stress-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("BTCUSDT.json")
    let writeMs = try Stress.ms { try data.write(to: file, options: .atomic) }
    var decoded: OrderFlowJournal?
    let readMs = Stress.ms { decoded = (try? Data(contentsOf: file)).flatMap(OrderFlowJournal.decode) }
    XCTAssertEqual(decoded, j, "读回来要逐字相同")
    Stress.report("落盘[\(Stress.build)] 5000 条：挑单 \(Stress.fmt(pickMs)) ms + 编码 \(Stress.fmt(encodeMs)) ms + 原子写 \(Stress.fmt(writeMs)) ms"
      + "（都在订单流 actor 上同步做）；文件 \(data.count / 1024) KB（每条约 \(data.count / 5_000) 字节）；读 + 解码 \(Stress.fmt(readMs)) ms")
    XCTAssertLessThan(data.count, 3 * 1_024 * 1_024, "5000 条的日志不该到几 MB")

    // 坏文件：一律当没有（nil），不崩、不读出半份。
    let half = data.prefix(data.count / 2)
    var wrongVersion = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    wrongVersion["version"] = 2
    var zeroStep = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    zeroStep["step"] = 0
    var oneBadRow = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var rows = try XCTUnwrap(oneBadRow["orders"] as? [[String: Any]])
    rows[17]["st"] = "exploded"
    oneBadRow["orders"] = rows
    var random = Data(count: 4_096)
    for i in random.indices { random[i] = UInt8(truncatingIfNeeded: rng.next()) }
    let cases: [(String, Data)] = [
      ("空文件", Data()), ("截断一半", Data(half)), ("随机字节", random), ("不是对象", Data("[1,2,3]".utf8)),
      ("版本不对", try JSONSerialization.data(withJSONObject: wrongVersion)),
      ("步长为 0", try JSONSerialization.data(withJSONObject: zeroStep)),
      ("一条状态坏了", try JSONSerialization.data(withJSONObject: oneBadRow)),
    ]
    for (name, bytes) in cases { XCTAssertNil(OrderFlowJournal.decode(bytes), "坏文件（\(name)）应当读成 nil") }
    Stress.report("落盘 坏文件 \(cases.count) 种（空 / 截断 / 随机字节 / 非对象 / 版本不对 / 步长 0 / 一条状态坏了）一律读成 nil、不崩；"
      + "注意「一条坏了」也是整份作废（JSONDecoder 整体失败），见报告设计问题")
  }
}

// MARK: - 3. 乱序、丢包、重复、重放、迟到快照

final class OrderFlowStressSequenceTests: XCTestCase {

  /// 按一种序列规则跑 4000 条增量，按概率丢 / 重复 / 前后对调 / 整段重放，REST 那一路快照随机早到或迟到。
  /// 不变量：**簿说自己就绪、序号追到真值的那一刻，内容必须和真值逐档相同**——断档只能表现为「不就绪、要重拉」，
  /// 不能表现为「就绪但数是错的」。
  private func run(_ model: DepthSequenceModel, inBand: Bool, seed: UInt64) -> (gaps: Int, recoveries: Int, checks: Int) {
    var rng = StressRNG(seed: seed)
    let venue = OrderFlowVenue(exchange: "x", label: "x", product: .usdtPerp, instrument: "BTC", notional: .linear(multiplier: 1),
                               sequenceModel: model, snapshotInBand: inBand)
    var truth = SyntheticBook(tick: 0.5, midTick: 120_000, levels: 300, qty: 0.1...5, rng: &rng)
    var driver = SequenceDriver(model: model, last: 10_000)
    var book = VenueBook(venue: venue)
    var gaps = 0, recoveries = 0, checks = 0
    /// 已生成、还没投递的（按生成顺序）。
    var outbox: [BookDelta] = []
    /// 最近投递过的（重放用）。
    var recent: [BookDelta] = []
    /// REST 那一路：要了快照，再过几条增量才到（期间增量照常进缓冲）。
    var snapshotDue: Int?
    var snapshotTakenAt: BookSnapshot?
    // 最近若干条生成出来之后的真值快照（按那一刻的 final 序号），用来造「迟到的快照」。
    var history: [(id: Int64, snapshot: BookSnapshot)] = []

    func full(_ id: Int64) -> BookSnapshot { truth.snapshot(lastUpdateID: id, requestedLevels: 5_000) }

    var action = book.connectionOpened()
    if inBand { action = book.ingest(.snapshot(full(driver.last)), nowMs: 0) } else {
      action = .fetchSnapshot
    }
    if action == .fetchSnapshot { snapshotDue = rng.int(0...3); snapshotTakenAt = full(driver.last) }

    func handle(_ a: OrderFlowModel.Action) {
      switch a {
      case .none: break
      case .fetchSnapshot:
        gaps += 1
        if snapshotDue == nil {
          snapshotDue = rng.int(0...3)
          // 快照在「服务器此刻」取：可能比我们已经收到的新（流落后），也可能旧（我们收得快）。
          let back = rng.int(0...min(3, history.count))
          snapshotTakenAt = back == 0 ? full(driver.last) : history[history.count - back].snapshot
        }
      case .resubscribe:
        gaps += 1
        // 流内快照那家：重订后快照带着最新序号到，之后的增量从它接。
        outbox.removeAll()
        let r = book.ingest(.snapshot(full(driver.last)), nowMs: 0)
        XCTAssertEqual(r, .none)
        recoveries += 1
      }
    }

    for step in 0..<4_000 {
      let c = truth.changes(rng.int(3...25), reach: 300, rng: &rng)
      outbox.append(driver.next(bids: c.bids, asks: c.asks))
      history.append((driver.last, full(driver.last)))
      if history.count > 4 { history.removeFirst() }

      // 投递（带故障）。
      while !outbox.isEmpty {
        var d = outbox.removeFirst()
        if rng.chance(0.004) { continue }                                   // 丢
        if rng.chance(0.004), let next = outbox.first {                    // 对调
          outbox[0] = d; d = next
        }
        var sends = [d]
        if rng.chance(0.006) { sends.append(d) }                            // 重复
        if model == .strictIncrementing, rng.chance(0.004) {                // Coinbase 式整段重放
          sends += recent.suffix(8)
        }
        for s in sends {
          handle(book.ingest(.delta(s), nowMs: Int64(step)))
          recent.append(s); if recent.count > 16 { recent.removeFirst() }
        }
      }
      if let due = snapshotDue {
        if due == 0, let snap = snapshotTakenAt {
          snapshotDue = nil; snapshotTakenAt = nil
          let r = book.applySnapshot(snap, nowMs: Int64(step))
          if r == .none, book.isReady { recoveries += 1 }
          handle(r)
        } else {
          snapshotDue = due - 1
        }
      }
      // 不变量：就绪且追到真值时逐档相同。
      if book.isReady, book.book.lastUpdateID == driver.last, step % 7 == 0 {
        checks += 1
        var lb = book.book
        XCTAssertEqual(lb.levelCount, truth.bids.count + truth.asks.count, "\(model) 第 \(step) 步：档数和真值不同")
        for (t, q) in truth.bids where lb.quantity(at: truth.price(t), side: .bid) != q {
          XCTFail("\(model) 第 \(step) 步：买 \(truth.price(t)) 本地 \(lb.quantity(at: truth.price(t), side: .bid)) ≠ 真值 \(q)"); break
        }
        for (t, q) in truth.asks where lb.quantity(at: truth.price(t), side: .ask) != q {
          XCTFail("\(model) 第 \(step) 步：卖 \(truth.price(t)) 本地 \(lb.quantity(at: truth.price(t), side: .ask)) ≠ 真值 \(q)"); break
        }
        _ = lb.bestBid()
      }
    }
    return (gaps, recoveries, checks)
  }

  func testEverySequenceModelSurvivesDropsDuplicatesSwapsAndReplays() {
    let cases: [(String, DepthSequenceModel, Bool)] = [
      ("币安现货 U/u", .rangeOverlap, false),
      ("币安合约 U/u/pu", .previousFinalOverlap, false),
      ("OKX seqId/prevSeqId", .previousFinalExact, true),
      ("Coinbase sequence_num", .strictIncrementing, true),
    ]
    for (i, c) in cases.enumerated() {
      let r = run(c.1, inBand: c.2, seed: 0x5E0 + UInt64(i))
      Stress.report("乱序 \(c.0)：4000 条里注入丢 / 对调 / 重复\(c.1 == .strictIncrementing ? " / 整段重放" : "")，"
        + "识别出断档 \(r.gaps) 次、重建就绪 \(r.recoveries) 次、就绪时逐档对真值 \(r.checks) 次，全部一致")
      XCTAssertGreaterThan(r.gaps, 5, "\(c.0)：故障注入没有触发任何断档")
      XCTAssertGreaterThan(r.checks, 100, "\(c.0)：就绪时刻太少，核对不充分")
    }
  }
}
