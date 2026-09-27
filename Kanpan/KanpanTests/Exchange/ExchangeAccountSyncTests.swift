import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 一次拉取只回一份写死的批次，记下每一次调用的时间段。
final class ScriptedProvider: ExchangeAccountProvider, @unchecked Sendable {
  let venue = "binance"
  let market = "usd_m"
  private let lock = NSLock()
  private var calls: [(Int64, Int64)] = []
  var readOnly = true
  var failure: ExchangeAccountError?
  var batch = ExchangeAccountBatch()

  var fetches: [(Int64, Int64)] { lock.withLock { calls } }

  func verifyReadOnly() async throws {
    if !readOnly { throw ExchangeAccountError.notReadOnly }
  }

  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch {
    let (failure, batch) = lock.withLock { () -> (ExchangeAccountError?, ExchangeAccountBatch) in
      calls.append((from, to)); return (self.failure, self.batch)
    }
    if let failure { throw failure }
    return batch
  }
}

@Suite("自动复盘 · 账户同步与本机凭据", .serialized)
struct ExchangeAccountSyncTests {
  typealias F = ExchangeFixture

  /// 每条用例一份自己的 Keychain service 与状态文件，跑完清掉。
  struct Harness {
    let store = ExchangeCredentialStore(service: "kanpan.exchange.tests.\(UUID().uuidString)")
    let stateURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("exchange-tests-\(UUID().uuidString).json")
    let clock = ExchangeTestClock(F.t0)
    let provider = ScriptedProvider()
    let sink = RoundSink()

    func sync() -> ExchangeAccountSync {
      let provider = provider, sink = sink
      return ExchangeAccountSync(venue: "binance", market: "usd_m", store: store, stateURL: stateURL,
                                 clock: clock.closure, makeProvider: { _ in provider },
                                 onRounds: { await sink.take($0) })
    }

    func tearDown() {
      try? store.removeAll()
      try? FileManager.default.removeItem(at: stateURL)
    }
  }

  static func fill(_ id: String, _ time: Int64, _ side: TradeSide, _ qty: String, pnl: String = "0") -> Fill {
    Fill(id: id, orderId: "o\(id)", symbol: "BTCUSDT", time: time, side: side, positionSide: .both,
         price: 60000, qty: Decimal(string: qty)!, commission: Decimal(string: "0.1")!,
         commissionAsset: "USDT", realizedPnl: Decimal(string: pnl)!, maker: false, marginAsset: "USDT")
  }

  @Test("Keychain 往返：存进去读得回来，断开之后全没了")
  func keychainRoundTrip() throws {
    let h = Harness()
    defer { h.tearDown() }
    #expect(try h.store.loadCredentials() == nil)
    let creds = ExchangeCredentials(apiKey: "key-1234WXYZ", secret: "s3cr3t")
    let status = ExchangeCredentialStore.Status(keySuffix: creds.keySuffix, connectedAt: 1, backfillFrom: 0,
                                                watermark: nil, lastAttemptAt: nil)
    try h.store.save(credentials: creds, status: status)
    #expect(try h.store.loadCredentials() == creds)
    #expect(try h.store.loadStatus()?.keySuffix == "WXYZ")
    var next = status
    next.watermark = 42
    try h.store.saveStatus(next)
    #expect(try h.store.loadStatus()?.watermark == 42)
    #expect(try h.store.loadCredentials() == creds)
    try h.store.removeAll()
    #expect(try h.store.loadCredentials() == nil)
    #expect(try h.store.loadStatus() == nil)
  }

  @Test("非只读 Key：接入被拒，Keychain 里什么都没写")
  func nonReadOnlyKeyNeverTouchesKeychain() async throws {
    let h = Harness()
    defer { h.tearDown() }
    h.provider.readOnly = false
    await #expect(throws: ExchangeAccountError.notReadOnly) {
      try await h.sync().connect(apiKey: "key-1234", secret: "secret")
    }
    #expect(try h.store.loadCredentials() == nil)
    #expect(try h.store.loadStatus() == nil)
    await #expect(throws: ExchangeAccountError.missingCredentials) {
      try await h.sync().connect(apiKey: "  ", secret: "secret")
    }
  }

  @Test("第一次回溯 90 天；之后从水位往前留 1 小时增量拉，水位跟着前进；回合交给回调")
  func watermarkAdvances() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = h.sync()
    let status = try await sync.connect(apiKey: "  key-1234\n", secret: "secret ")
    #expect(status.keySuffix == "1234")
    #expect(try h.store.loadCredentials() == ExchangeCredentials(apiKey: "key-1234", secret: "secret"))

    let open = F.t0 - 3 * F.day
    h.provider.batch.fills = [Self.fill("1", open, .buy, "0.1")]
    // 当前还持着这 0.1：窗口起点之前没有旧仓。
    h.provider.batch.positions = [PositionKey(symbol: "BTCUSDT", positionSide: .both): Decimal(string: "0.1")!]
    #expect(await sync.pullIfDue() == .pulled(rounds: 1))
    #expect(h.provider.fetches.last?.0 == F.t0 - ExchangeAccountSync.backfillMs)
    #expect(h.provider.fetches.last?.1 == F.t0)
    #expect(try h.store.loadStatus()?.watermark == F.t0)

    h.clock.advance(10 * 60_000)
    h.provider.batch.fills.append(Self.fill("2", F.t0 + 60_000, .sell, "0.1", pnl: "10"))
    #expect(await sync.pullIfDue() == .pulled(rounds: 1))
    #expect(h.provider.fetches.last?.0 == F.t0 - ExchangeAccountSync.overlapMs)
    #expect(h.provider.fetches.last?.1 == F.t0 + 10 * 60_000)
    #expect(try h.store.loadStatus()?.watermark == F.t0 + 10 * 60_000)

    // 同一批再拉一次：去重吃掉，什么都不交出去，水位照走。
    h.clock.advance(10 * 60_000)
    #expect(await sync.pullIfDue() == .pulled(rounds: 0))
    let batches = await h.sink.batches
    #expect(batches.count == 2)
    #expect(batches[0].first?.status == .open)
    #expect(batches[1].first?.status == .closed)
    #expect(batches[0].first?.id == batches[1].first?.id)
  }

  @Test("前台 5 分钟节流；失败也算一次尝试；断网静默")
  func throttleAndSilentOffline() async throws {
    let h = Harness()
    defer { h.tearDown() }
    let sync = h.sync()
    #expect(await sync.pullIfDue() == .notConnected)
    try await sync.connect(apiKey: "key-1234", secret: "secret")

    h.provider.failure = .offline
    #expect(await sync.pullIfDue() == .offline)
    #expect(h.provider.fetches.count == 1)
    #expect(try h.store.loadStatus()?.watermark == nil)

    h.provider.failure = nil
    h.clock.advance(4 * 60_000)
    #expect(await sync.pullIfDue() == .skipped)
    #expect(h.provider.fetches.count == 1)

    #expect(await sync.pullIfDue(force: true) == .pulled(rounds: 0))
    #expect(h.provider.fetches.count == 2)

    h.clock.advance(5 * 60_000)
    h.provider.failure = .invalidKey
    #expect(await sync.pullIfDue() == .failed(message: ExchangeAccountError.invalidKey.message))

    try await sync.disconnect()
    #expect(await sync.pullIfDue(force: true) == .notConnected)
    #expect(!FileManager.default.fileExists(atPath: h.stateURL.path))
  }
}
