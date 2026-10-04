import Foundation
import KanpanCore
import KanpanNetwork
import Testing
@testable import Kanpan

// 深度审查 E 线 · 交易所账户（R1–R22）的回归用例。每一条都对着一个已经修掉的现象：
// 改回旧写法，这里对应的那条就会红。

// MARK: - 测试替身

/// 内存版 Keychain：能指定某一项写不进去 / 删不掉，模拟系统 Keychain 造不出来的半截失败。
final class MemoryKeychain: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String: Data] = [:]
  private var failingWrites: Set<String> = []
  private var failingDeletes: Set<String> = []

  func failWrites(_ account: String) { lock.withLock { _ = failingWrites.insert(account) } }
  func failDeletes(_ account: String) { lock.withLock { _ = failingDeletes.insert(account) } }

  var io: ExchangeKeychainIO {
    ExchangeKeychainIO(
      read: { [self] service, account in
        lock.withLock { items[service + "|" + account] }
      },
      write: { [self] data, service, account in
        try lock.withLock {
          if failingWrites.contains(account) { throw ExchangeAccountError.keychain }
          items[service + "|" + account] = data
        }
      },
      delete: { [self] service, account in
        try lock.withLock {
          if failingDeletes.contains(account) { throw ExchangeAccountError.keychain }
          items[service + "|" + account] = nil
        }
      })
  }
}

/// 拉取时能插一段动作（模拟拉的过程中被断开、被换 Key）的 provider。
final class HookedExchangeProvider: ExchangeAccountProvider, @unchecked Sendable {
  let venue = "binance"
  let market = "usd_m"
  private let lock = NSLock()
  private var calls: [(Int64, Int64)] = []
  private var storedBatch = ExchangeAccountBatch()
  private var storedHook: (@Sendable () throws -> Void)?

  var batch: ExchangeAccountBatch {
    get { lock.withLock { storedBatch } }
    set { lock.withLock { storedBatch = newValue } }
  }

  var hook: (@Sendable () throws -> Void)? {
    get { lock.withLock { storedHook } }
    set { lock.withLock { storedHook = newValue } }
  }

  var fetches: [(Int64, Int64)] { lock.withLock { calls } }

  func verifyReadOnly() async throws {}

  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch {
    let (hook, batch) = lock.withLock { () -> ((@Sendable () throws -> Void)?, ExchangeAccountBatch) in
      calls.append((from, to)); return (storedHook, storedBatch)
    }
    try hook?()
    return batch
  }
}

// MARK: - 签名与请求（R1）

@Suite("审查 E · 币安签名与请求")
struct ExchangeAuditSigningTests {
  typealias F = ExchangeFixture

  @Test("R1 非 ASCII 代号先按 UTF-8 百分号转义再签名：签的就是发出去的那一串")
  func nonASCIISymbolIsEscapedBeforeSigning() throws {
    let signer = BinanceRequestSigner(secret: "test-secret")
    let query = signer.signedQuery([("symbol", "币安人生USDT")], timestamp: 1, recvWindow: 10_000)
    let parts = query.components(separatedBy: "&signature=")
    #expect(parts.count == 2)
    #expect(parts[0] == "symbol=%E5%B8%81%E5%AE%89%E4%BA%BA%E7%94%9FUSDT&recvWindow=10000&timestamp=1")
    #expect(parts[1] == signer.signature(for: parts[0]))
    // 交给 URL 之后不会被再转义一遍。
    let url = try #require(URL(string: "https://fapi.binance.com/fapi/v1/userTrades?" + query))
    #expect(url.query(percentEncoded: true) == query)
  }

  @Test("R1 只放行 RFC 3986 非保留字符：空格、加号、斜杠、带音标的字母都转义")
  func escapeOnlyKeepsUnreservedASCII() {
    #expect(BinanceRequestSigner.escape("Az09-._~") == "Az09-._~")
    #expect(BinanceRequestSigner.escape("a b+c/é") == "a%20b%2Bc%2F%C3%A9")
    #expect(BinanceRequestSigner.escape("币") == "%E5%B8%81")
  }

  @Test("R1 账户请求里的中文代号：线上的查询串是转义过的，签名覆盖的正是它")
  func accountRequestSignsTheWireQuery() async throws {
    let http = MockExchangeHTTP()
    let now = F.t0 + 2 * F.day
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(now)}"#)
    http.onJSON("/fapi/v2/positionRisk", #"""
    [{"symbol":"币安人生USDT","positionAmt":"100","markPrice":"0.5","leverage":"5","positionSide":"BOTH",
      "updateTime":\#(F.t0)}]
    """#)
    http.on("/fapi/v1/income", F.serveIncome([]))
    http.onJSON("/fapi/v1/userTrades", "[]")
    _ = try await F.account(http, clock: ExchangeTestClock(now)).fetch(from: F.t0, to: now)

    let request = try #require(http.requests(to: "/fapi/v1/userTrades").first)
    let wire = try #require(request.url?.query(percentEncoded: true))
    #expect(wire.hasPrefix("symbol=%E5%B8%81%E5%AE%89%E4%BA%BA%E7%94%9FUSDT&startTime="))
    let parts = wire.components(separatedBy: "&signature=")
    #expect(parts.count == 2)
    #expect(parts[1] == BinanceRequestSigner(secret: "test-secret").signature(for: parts[0]))
    #expect(MockExchangeHTTP.query(request)["symbol"] == "币安人生USDT")
  }
}

// MARK: - 只读判定（R5）

@Suite("审查 E · 只读 Key 判定")
struct ExchangeAuditRestrictionTests {
  typealias F = ExchangeFixture
  typealias Restrictions = BinanceFuturesAccount.Restrictions

  /// 一把标准只读 Key 的返回，再按 `overrides` 改：值为 nil 表示这个字段不回。
  static func restrictions(_ overrides: [String: Bool?] = [:]) throws -> Restrictions {
    var dict: [String: Any] = [
      "ipRestrict": true, "createTime": 1_698_645_219_000,
      "enableReading": true, "enableWithdrawals": false, "enableInternalTransfer": false,
      "permitsUniversalTransfer": false, "enableSpotAndMarginTrading": false, "enableFutures": false,
      "enableMargin": false, "enableVanillaOptions": false, "enablePortfolioMarginTrading": false,
      "enableFixApiTrade": false,
    ]
    for (key, value) in overrides { dict[key] = value.map { $0 as Any } }
    let data = try JSONSerialization.data(withJSONObject: dict)
    return try JSONDecoder().decode(Restrictions.self, from: data)
  }

  static let moneyFields = ["enableWithdrawals", "enableInternalTransfer", "permitsUniversalTransfer",
                            "enableSpotAndMarginTrading", "enableFutures"]
  static let optionalFields = ["enableMargin", "enableVanillaOptions", "enablePortfolioMarginTrading",
                               "enableFixApiTrade"]

  @Test("R5 标准只读 Key 收下")
  func readOnlyKeyPasses() throws {
    #expect(try Self.restrictions().isReadOnly)
  }

  @Test("R5 能动钱、能下单的五项：缺字段当开着，写 true 也拒", arguments: ExchangeAuditRestrictionTests.moneyFields)
  func moneyFieldMustBeExplicitlyFalse(field: String) throws {
    #expect(try !Self.restrictions([field: nil]).isReadOnly)
    #expect(try !Self.restrictions([field: true]).isReadOnly)
  }

  @Test("R5 enableReading 必须明明白白是 true")
  func readingMustBeOn() throws {
    #expect(try !Self.restrictions(["enableReading": false]).isReadOnly)
    #expect(try !Self.restrictions(["enableReading": nil]).isReadOnly)
  }

  @Test("R5 杠杆 / 期权 / 统一账户 / FIX 下单：不回不算，回了 true 照样拒", arguments: ExchangeAuditRestrictionTests.optionalFields)
  func optionalFieldsRejectOnlyWhenTrue(field: String) throws {
    #expect(try Self.restrictions([field: nil]).isReadOnly)
    #expect(try !Self.restrictions([field: true]).isReadOnly)
  }

  @Test("R5 返回里少了 enableWithdrawals：接入被拒，也不再去探合约账户")
  func missingWithdrawalsFieldIsRejected() async throws {
    let http = MockExchangeHTTP()
    http.onJSON("/sapi/v1/account/apiRestrictions",
                F.readOnlyRestrictions.replacingOccurrences(of: #""enableWithdrawals":false,"#, with: ""))
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    await #expect(throws: ExchangeAccountError.notReadOnly) {
      try await F.account(http, clock: ExchangeTestClock(F.t0)).verifyReadOnly()
    }
    #expect(http.requests(to: "/fapi/v2/positionRisk").isEmpty)
  }
}

// MARK: - 一轮拉取的顺序与截止点（R2 / R6 / R10）

@Suite("审查 E · 一轮拉取的截止点与窗口")
struct ExchangeAuditFetchTests {
  typealias F = ExchangeFixture

  static func heldPosition(symbol: String = "BTCUSDT", amount: String = "0.1", updateTime: Int64) -> String {
    #"[{"symbol":"\#(symbol)","positionAmt":"\#(amount)","markPrice":"60000","leverage":"10","#
      + #""positionSide":"BOTH","updateTime":\#(updateTime)}]"#
  }

  @Test("R2/R6 先对时、再拿持仓快照，资金流水与成交都只拉到快照时刻；asOf 取交易所时间与仓位变动时间较晚的那个")
  func snapshotFirstAndCutAtAsOf() async throws {
    let http = MockExchangeHTTP()
    let from = F.t0
    let server = F.t0 + 20 * F.day
    let positionUpdated = server + 2_000
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(server)}"#)
    http.onJSON("/fapi/v2/positionRisk", Self.heldPosition(updateTime: positionUpdated))
    http.on("/fapi/v1/income", F.serveIncome([]))
    // 一笔在窗口里（零手续费开仓，流水里没有它），一笔在快照之后：后者留给下一轮。
    let open = from + F.day
    let late = positionUpdated + 1
    http.on("/fapi/v1/userTrades", F.serveTrades([
      (1, open, F.trade(id: 1, time: open, side: "BUY", price: "60000", qty: "0.1")),
      (2, late, F.trade(id: 2, time: late, side: "BUY", price: "60000", qty: "0.1")),
    ]))
    // 手机时间慢 5 秒，`to` 只当提示。
    let clock = ExchangeTestClock(server - 5_000)
    let batch = try await F.account(http, clock: clock).fetch(from: from, to: clock.now)

    #expect(batch.asOf == positionUpdated)
    #expect(batch.fills.map(\.id) == ["1"])
    let paths = http.requests.compactMap { $0.url?.path }
    let time = try #require(paths.firstIndex(of: "/fapi/v1/time"))
    let positions = try #require(paths.firstIndex(of: "/fapi/v2/positionRisk"))
    let income = try #require(paths.firstIndex(of: "/fapi/v1/income"))
    let trades = try #require(paths.firstIndex(of: "/fapi/v1/userTrades"))
    #expect(time < positions && positions < income && income < trades)
    let ends = (http.requests(to: "/fapi/v1/income") + http.requests(to: "/fapi/v1/userTrades"))
      .compactMap { MockExchangeHTTP.query($0)["endTime"].flatMap(Int64.init) }
    #expect(!ends.isEmpty)
    #expect(ends.allSatisfy { $0 <= positionUpdated })
    #expect(ends.max() == positionUpdated)
  }

  @Test("R2 仓位变动时间早于交易所此刻：asOf 就是交易所此刻，不是手机时间")
  func asOfFallsBackToServerTime() async throws {
    let http = MockExchangeHTTP()
    let server = F.t0 + 3 * F.day
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(server)}"#)
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    http.on("/fapi/v1/income", F.serveIncome([]))
    // 手机时间快了两小时。
    let clock = ExchangeTestClock(server + 2 * 3_600_000)
    let batch = try await F.account(http, clock: clock).fetch(from: F.t0, to: clock.now)
    #expect(batch.asOf == server)
    let ends = http.requests(to: "/fapi/v1/income").compactMap { MockExchangeHTTP.query($0)["endTime"].flatMap(Int64.init) }
    #expect(ends.max() == server)
  }

  @Test("R10 持着仓的品种：开仓那笔零手续费、流水里没有它，也照样每个窗口都拉到")
  func heldSymbolScansEveryWindow() async throws {
    let http = MockExchangeHTTP()
    let from = F.t0
    let server = F.t0 + 20 * F.day
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(server)}"#)
    http.onJSON("/fapi/v2/positionRisk", Self.heldPosition(updateTime: from + F.day))
    http.on("/fapi/v1/income", F.serveIncome([]))
    let open = from + F.day
    http.on("/fapi/v1/userTrades", F.serveTrades([
      (7, open, F.trade(id: 7, time: open, side: "BUY", price: "60000", qty: "0.1")),
    ]))
    let batch = try await F.account(http, clock: ExchangeTestClock(server)).fetch(from: from, to: server)
    #expect(batch.fills.map(\.id) == ["7"])
    let starts = Set(http.requests(to: "/fapi/v1/userTrades")
      .compactMap { MockExchangeHTTP.query($0)["startTime"].flatMap(Int64.init) })
    #expect(starts == [from, from + 7 * F.day, from + 14 * F.day])
  }

  @Test("R10 USDC 本位品种：零手续费开仓、只在平仓那周有流水，开仓那周也拉到")
  func usdcSymbolScansEveryWindow() async throws {
    let http = MockExchangeHTTP()
    let from = F.t0
    let server = F.t0 + 20 * F.day
    let open = from + F.day
    let close = from + 15 * F.day
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(server)}"#)
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    http.on("/fapi/v1/income", F.serveIncome([
      (close, F.income(tranId: 1, time: close, type: "REALIZED_PNL", amount: "5", symbol: "ETHUSDC")),
    ]))
    http.on("/fapi/v1/userTrades", F.serveTrades([
      (1, open, F.trade(id: 1, time: open, side: "BUY", price: "2500", qty: "1", symbol: "ETHUSDC")),
      (2, close, F.trade(id: 2, time: close, side: "SELL", price: "2505", qty: "1", pnl: "5", symbol: "ETHUSDC")),
    ]))
    let batch = try await F.account(http, clock: ExchangeTestClock(server)).fetch(from: from, to: server)
    #expect(batch.fills.map(\.id) == ["1", "2"])
    #expect(http.requests(to: "/fapi/v1/userTrades").allSatisfy { MockExchangeHTTP.query($0)["symbol"] == "ETHUSDC" })
  }

  @Test("自成交：同一个成交 id 的买、卖两条都收下，不按 id 去重丢掉一边")
  func selfTradeKeepsBothSides() async throws {
    let http = MockExchangeHTTP()
    let server = F.t0 + 2 * F.day
    let t = F.t0 + F.day
    http.onJSON("/fapi/v1/time", #"{"serverTime":\#(server)}"#)
    http.onJSON("/fapi/v2/positionRisk", F.flatPositions)
    http.on("/fapi/v1/income", F.serveIncome([
      (t, F.income(tranId: 1, time: t, type: "COMMISSION", amount: "-0.1")),
    ]))
    http.on("/fapi/v1/userTrades", F.serveTrades([
      (5, t, F.trade(id: 5, time: t, side: "BUY", price: "60000", qty: "0.1")),
      (5, t, F.trade(id: 5, time: t, side: "SELL", price: "60000", qty: "0.1")),
    ]))
    let batch = try await F.account(http, clock: ExchangeTestClock(server)).fetch(from: F.t0, to: server)
    #expect(batch.fills.map(\.id) == ["5", "5"])
    #expect(Set(batch.fills.map(\.side)) == [.buy, .sell])
  }

  @Test("时间二分：整页挤在同一毫秒才改用 fromId，二分出来的每一段都不重不漏")
  func splitHalvesWithoutOverlap() throws {
    let (left, right) = try #require(BinanceFuturesAccount.split(10...21))
    #expect(left == 10...15 && right == 16...21)
    #expect(BinanceFuturesAccount.split(7...7) == nil)
    let (a, b) = try #require(BinanceFuturesAccount.split(7...8))
    #expect(a == 7...7 && b == 8...8)
  }
}

// MARK: - 同步：水位、中间状态、拉取期间断开（R3 / R6 / R15）

@Suite("审查 E · 同步的水位与中间状态", .serialized)
struct ExchangeAuditSyncTests {
  typealias F = ExchangeFixture
  static let hour: Int64 = 3_600_000

  struct Harness {
    let keychain = MemoryKeychain()
    let store: ExchangeCredentialStore
    let stateURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("exchange-audit-\(UUID().uuidString).json")
    let clock = ExchangeTestClock(F.t0)
    let provider = HookedExchangeProvider()
    let sink = RoundSink()

    init() {
      store = ExchangeCredentialStore(service: "kanpan.exchange.audit.\(UUID().uuidString)", io: keychain.io)
    }

    func sync(discardState: Bool = false, afterRounds: (@Sendable () throws -> Void)? = nil) -> ExchangeAccountSync {
      let provider = provider, sink = sink
      return ExchangeAccountSync(venue: "binance", market: "usd_m", store: store, stateURL: stateURL,
                                 clock: clock.closure, discardState: discardState,
                                 makeProvider: { _ in provider },
                                 onRounds: { rounds in
                                   await sink.take(rounds)
                                   try? afterRounds?()
                                 })
    }

    var stateExists: Bool { FileManager.default.fileExists(atPath: stateURL.path) }

    func state() throws -> ExchangeAccountSync.State {
      try JSONDecoder().decode(ExchangeAccountSync.State.self, from: Data(contentsOf: stateURL))
    }

    func tearDown() { try? FileManager.default.removeItem(at: stateURL) }
  }

  /// 接入、拉第一轮（落下中间状态与水位 = t0），返回发动机。
  static func connectedAndPulled(_ h: Harness) async throws -> ExchangeAccountSync {
    let sync = h.sync()
    try await sync.connect(apiKey: "key-1234", secret: "secret")
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.stateExists)
    return sync
  }

  @Test("R6 水位记交易所给的截止时刻，不记手机时间；下一轮从它往前一小时拉")
  func watermarkUsesExchangeAsOf() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = h.sync()
    try await sync.connect(apiKey: "key-1234", secret: "secret")
    // 手机时间快了两小时。
    h.provider.batch.asOf = F.t0 - 2 * Self.hour
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(try h.store.loadStatus()?.watermark == F.t0 - 2 * Self.hour)
    #expect(try h.state().watermark == F.t0 - 2 * Self.hour)

    h.clock.advance(10 * 60_000)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 - 3 * Self.hour)
  }

  @Test("R3 中间状态文件没了：水位跟着作废，从「此刻 − 90 天」重拼，不再从旧水位接一个空账本")
  func missingStateForcesBackfill() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = try await Self.connectedAndPulled(h)
    h.clock.advance(F.day)
    try FileManager.default.removeItem(at: h.stateURL)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 + F.day - ExchangeAccountSync.backfillMs)
    #expect(try h.state().watermark == F.t0 + F.day)
  }

  @Test("R3 中间状态文件坏了：同样从回溯起点重拼")
  func corruptStateForcesBackfill() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = try await Self.connectedAndPulled(h)
    h.clock.advance(F.day)
    try Data("garbage".utf8).write(to: h.stateURL)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 + F.day - ExchangeAccountSync.backfillMs)
  }

  @Test("R3 旧版只存账本：Keychain 里有水位就接着用；没有水位就重拼")
  func legacyBareBuilder() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = try await Self.connectedAndPulled(h)
    try JSONEncoder().encode(h.state().builder).write(to: h.stateURL)

    h.clock.advance(10 * 60_000)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 - ExchangeAccountSync.overlapMs)
    // 落回去的是新格式。
    #expect(try h.state().watermark == F.t0 + 10 * 60_000)

    try JSONEncoder().encode(h.state().builder).write(to: h.stateURL)
    var status = try #require(try h.store.loadStatus())
    status.watermark = nil
    try h.store.saveStatus(status)
    h.clock.advance(F.day)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 + 10 * 60_000 + F.day - ExchangeAccountSync.backfillMs)
  }

  @Test("R3 回合档丢了（discardState）：发动机一建就把中间状态作废，下一轮重拼")
  func discardStateDropsTheBuilder() async throws {
    let h = Harness()
    defer { h.tearDown() }
    _ = try await Self.connectedAndPulled(h)
    let fresh = h.sync(discardState: true)
    #expect(!h.stateExists)
    h.clock.advance(10 * 60_000)
    #expect(await fresh.pullIfDue() == .pulled(rounds: 0))
    #expect(h.provider.fetches.last?.0 == F.t0 + 10 * 60_000 - ExchangeAccountSync.backfillMs)
  }

  static func openFillBatch() -> ExchangeAccountBatch {
    var batch = ExchangeAccountBatch()
    batch.fills = [ExchangeAccountSyncTests.fill("1", F.t0 - F.day, .buy, "0.1")]
    batch.positions = [PositionKey(symbol: "BTCUSDT", positionSide: .both): Decimal(string: "0.1")!]
    return batch
  }

  @Test("R15 拉的过程中被断开：这一批整个作废，不交回合、不落中间状态与水位")
  func disconnectDuringFetch() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = h.sync()
    try await sync.connect(apiKey: "key-1234", secret: "secret")
    h.provider.batch = Self.openFillBatch()
    let store = h.store
    h.provider.hook = { try store.removeAll() }
    #expect(await sync.pullIfDue() == .notConnected)
    #expect(await h.sink.batches.isEmpty)
    #expect(!h.stateExists)
  }

  @Test("R15 拉的过程中换了一把 Key：旧 Key 的这一批不交、不写到新连接的水位上")
  func reconnectDuringFetch() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = h.sync()
    try await sync.connect(apiKey: "key-1234", secret: "secret")
    h.provider.batch = Self.openFillBatch()
    let store = h.store
    h.provider.hook = {
      try store.save(credentials: ExchangeCredentials(apiKey: "key-9999", secret: "other"),
                     status: .init(keySuffix: "9999", connectedAt: F.t0 + 1, backfillFrom: F.t0 - 1,
                                   watermark: nil, lastAttemptAt: nil))
    }
    #expect(await sync.pullIfDue() == .notConnected)
    #expect(await h.sink.batches.isEmpty)
    #expect(!h.stateExists)
    #expect(try h.store.loadStatus()?.keySuffix == "9999")
    #expect(try h.store.loadStatus()?.watermark == nil)
  }

  @Test("R15 交回合的时候被断开：回合已经交了（至少一次），但中间状态与水位不写回去")
  func disconnectDuringDelivery() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let store = h.store
    let sync = h.sync(afterRounds: { try store.removeAll() })
    try await sync.connect(apiKey: "key-1234", secret: "secret")
    h.provider.batch = Self.openFillBatch()
    #expect(await sync.pullIfDue() == .notConnected)
    #expect(await h.sink.batches.count == 1)
    #expect(!h.stateExists)
    #expect(try h.store.loadStatus() == nil)
  }
}

// MARK: - Keychain 两项同生同灭（R14）

@Suite("审查 E · 本机凭据的半截失败")
struct ExchangeAuditCredentialTests {
  static let credentials = ExchangeCredentials(apiKey: "key-1234WXYZ", secret: "s3cr3t")
  static let status = ExchangeCredentialStore.Status(keySuffix: "WXYZ", connectedAt: 1, backfillFrom: 0,
                                                     watermark: nil, lastAttemptAt: nil)

  @Test("R14 元数据写不进去：刚写的 Key 删回去再抛错，不留「显示没接、其实存着」的半截")
  func saveRollsBackWhenStatusWriteFails() throws {
    let keychain = MemoryKeychain()
    keychain.failWrites("status")
    let store = ExchangeCredentialStore(service: "audit", io: keychain.io)
    #expect(throws: ExchangeAccountError.keychain) {
      try store.save(credentials: Self.credentials, status: Self.status)
    }
    #expect(try store.loadCredentials() == nil)
    #expect(try store.loadStatus() == nil)
  }

  @Test("R14 Key 写不进去：什么都没写")
  func saveFailsCleanlyWhenCredentialsWriteFails() throws {
    let keychain = MemoryKeychain()
    keychain.failWrites("credentials")
    let store = ExchangeCredentialStore(service: "audit", io: keychain.io)
    #expect(throws: ExchangeAccountError.keychain) {
      try store.save(credentials: Self.credentials, status: Self.status)
    }
    #expect(try store.loadCredentials() == nil)
    #expect(try store.loadStatus() == nil)
  }

  @Test("R14 断开时 Key 删不掉：另一项照删，并照实抛错（界面说没断开）")
  func removeAllTriesBothAndReportsFailure() throws {
    let keychain = MemoryKeychain()
    let store = ExchangeCredentialStore(service: "audit", io: keychain.io)
    try store.save(credentials: Self.credentials, status: Self.status)
    keychain.failDeletes("credentials")
    #expect(throws: ExchangeAccountError.keychain) { try store.removeAll() }
    #expect(try store.loadStatus() == nil)
    #expect(try store.loadCredentials() == Self.credentials)
  }
}

// MARK: - 回合属主（R9）与界面日期（R16）

@Suite("审查 E · 本机回合的属主")
struct ExchangeAuditOwnershipTests {
  static func someRounds() -> [TradeRound] {
    var builder = RoundBuilder(venue: "binance", market: "usd_m", accountTag: "primary")
    return builder.ingest(fills: [
      ExchangeAccountSyncTests.fill("1", ExchangeFixture.t0, .buy, "0.1"),
      ExchangeAccountSyncTests.fill("2", ExchangeFixture.t0 + 60_000, .sell, "0.1", pnl: "1"),
    ], funding: [], context: .init(currentPositions: [:]))
  }

  @Test("R9 属主就是此刻的人：照常显示")
  func ownerSeesRounds() {
    let rounds = Self.someRounds()
    #expect(!rounds.isEmpty)
    let view = ExchangeRoundsOwnership.view(rounds, owner: "u-A", profile: "u-A")
    #expect(view == .init(rounds: rounds, claim: nil, hidden: false))
  }

  @Test("R9 老文件（无属主）或访客时接入的：第一个登录的账号认领")
  func firstLoginClaims() {
    let rounds = Self.someRounds()
    #expect(ExchangeRoundsOwnership.view(rounds, owner: nil, profile: "u-A")
            == .init(rounds: rounds, claim: "u-A", hidden: false))
    #expect(ExchangeRoundsOwnership.view(rounds, owner: "local/guest-1", profile: "u-A")
            == .init(rounds: rounds, claim: "u-A", hidden: false))
    // 还是访客：照常显示，不认领。
    #expect(ExchangeRoundsOwnership.view(rounds, owner: nil, profile: "local/guest-1")
            == .init(rounds: rounds, claim: nil, hidden: false))
  }

  @Test("R9 换成另一个账号、或退登成访客：前一个人的回合不显示（也就不会被传进别人的账号）")
  func otherProfileIsHidden() {
    let rounds = Self.someRounds()
    let expected = ExchangeRoundsOwnership.Visible(rounds: [], claim: nil, hidden: true)
    #expect(ExchangeRoundsOwnership.view(rounds, owner: "u-A", profile: "u-B") == expected)
    #expect(ExchangeRoundsOwnership.view(rounds, owner: "u-A", profile: "local/guest-1") == expected)
    #expect(ExchangeRoundsOwnership.view(rounds, owner: "u-A", profile: "") == expected)
  }

  @Test("R9 回合档：新格式带属主；老格式（光一个数组）读成无属主；坏文件读成 nil")
  func fileDecoding() throws {
    let rounds = Self.someRounds()
    let file = ExchangeRoundsOwnership.File(owner: "u-A", rounds: rounds)
    let current = try JSONEncoder().encode(file)
    let legacy = try JSONEncoder().encode(rounds)
    #expect(ExchangeRoundsOwnership.decode(current) == file)
    #expect(ExchangeRoundsOwnership.decode(legacy) == .init(owner: nil, rounds: rounds))
    #expect(ExchangeRoundsOwnership.decode(Data("nope".utf8)) == nil)
  }

  @Test("R16 接入页的日期按上海时间：UTC 9 月 30 日 17 点在上海已经是 10 月 1 日")
  @MainActor
  func accountPageDayIsShanghai() {
    // 2026-09-30 17:00 UTC。
    #expect(ExchangeAccountPage.day(1_790_787_600_000) == "2026-10-01")
    #expect(ExchangeAccountPage.day(ExchangeFixture.t0) == "2026-09-01")
  }
}
