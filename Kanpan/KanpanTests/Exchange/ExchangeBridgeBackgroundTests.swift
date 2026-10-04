import Foundation
import KanpanCore
import ReviewData
import ReviewDomain
import Testing
@testable import Kanpan

// 深度审查 E 线 · 待核实五（后台刷新拉起、没有界面时新回合当轮上传）与 R13（桥层移除失败）的回归用例。

/// 后台那一轮交给上传通道的回合。
@MainActor final class UploadRecorder {
  private(set) var batches: [[TradeRound]] = []
  func take(_ rounds: [TradeRound]) { batches.append(rounds) }
}

/// 一座用内存 Keychain、临时目录、假 provider 装起来的交易所桥。
@MainActor struct BridgeHarness {
  typealias F = ExchangeFixture
  let keychain = MemoryKeychain()
  let store: ExchangeCredentialStore
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("exchange-bridge-\(UUID().uuidString)", isDirectory: true)
  let provider = HookedExchangeProvider()
  var stateURL: URL { directory.appendingPathComponent("state.json") }
  var roundsURL: URL { directory.appendingPathComponent("rounds.json") }

  init() throws {
    store = ExchangeCredentialStore(service: "kanpan.exchange.bridge.\(UUID().uuidString)", io: keychain.io)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  /// 已经接入（Keychain 里有 Key 与元数据），从没拉过。
  func connectKey() throws {
    try store.save(credentials: ExchangeCredentials(apiKey: "key-1234WXYZ", secret: "s3cr3t"),
                   status: .init(keySuffix: "WXYZ", connectedAt: F.t0, backfillFrom: F.t0 - F.day,
                                 watermark: nil, lastAttemptAt: nil))
  }

  /// 本机回合档已经记在某个账号名下（上次在前台接入时记的）。
  func ownRounds(by owner: String) throws {
    let data = try JSONEncoder().encode(ExchangeRoundsOwnership.File(owner: owner, rounds: []))
    try data.write(to: roundsURL)
  }

  /// 交易所那头有一个开了又平掉的回合。
  func tradeOnce() {
    var batch = ExchangeAccountBatch()
    batch.fills = [ExchangeAccountSyncTests.fill("1", F.t0, .buy, "0.1"),
                   ExchangeAccountSyncTests.fill("2", F.t0 + 60_000, .sell, "0.1", pnl: "1")]
    provider.batch = batch
  }

  /// `currentProfile` 是账号桥装着的档案：后台拉起时还没人装，是空串。
  func bridge(currentProfile: String = "", uplink: ExchangeReviewUplink?) -> ExchangeReviewBridge {
    let provider = provider
    return ExchangeReviewBridge(store: store, stateURL: stateURL, roundsURL: roundsURL,
                                makeProvider: { _ in provider },
                                currentProfile: { currentProfile },
                                headlessUplink: { uplink })
  }

  func tearDown() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("审查 E · 后台刷新拉起时的回合上传（待核实五）", .serialized)
@MainActor
struct ExchangeBridgeBackgroundTests {
  @Test("待核实五 没有界面（复盘本为 nil）、账号桥还没装档案：按问到的那个人照常拉，新回合这一轮就传上去")
  func headlessPullUploadsNewRounds() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey(); try h.ownRounds(by: "u-a"); h.tradeOnce()
    let recorder = UploadRecorder()
    let bridge = h.bridge(uplink: ExchangeReviewUplink(profile: "u-a", upload: { recorder.take($0) }))

    await bridge.backgroundPull()

    // 从前 `currentProfile` 是空串时，记在 u-a 名下的回合判成「属主不对」，连拉都不拉。
    #expect(h.provider.fetches.count == 1)
    #expect(!bridge.rounds.isEmpty)
    #expect(recorder.batches.count == 1)
    #expect(recorder.batches.first == bridge.rounds)
    // 回合档还记在原来那个人名下，没被这一轮改掉。
    let file = try #require(ExchangeRoundsOwnership.decode(Data(contentsOf: h.roundsURL)))
    #expect(file.owner == "u-a")
    #expect(file.rounds == bridge.rounds)
  }

  @Test("待核实五 后台问到的是另一个人：这批回合不归他——不拉、也不传")
  func headlessPullSkipsOtherOwner() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey(); try h.ownRounds(by: "u-a"); h.tradeOnce()
    let recorder = UploadRecorder()
    let bridge = h.bridge(uplink: ExchangeReviewUplink(profile: "u-b", upload: { recorder.take($0) }))

    await bridge.backgroundPull()

    #expect(h.provider.fetches.isEmpty)
    #expect(recorder.batches.isEmpty)
  }

  @Test("待核实五 没登录 / 钥匙串读不动（没有上传通道）：照常拉、回合落本机，只是这一轮不传")
  func headlessPullWithoutUplinkStillPulls() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey(); try h.ownRounds(by: "u-a"); h.tradeOnce()
    let bridge = h.bridge(uplink: ExchangeReviewUplink(profile: "u-a", upload: nil))

    await bridge.backgroundPull()

    #expect(h.provider.fetches.count == 1)
    #expect(!bridge.rounds.isEmpty)
  }

  @Test("待核实五 没接入交易所：不去问账号、不拉")
  func headlessPullNotConnected() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    h.tradeOnce()
    let asked = UploadRecorder()
    let provider = h.provider
    let bridge = ExchangeReviewBridge(store: h.store, stateURL: h.stateURL, roundsURL: h.roundsURL,
                                      makeProvider: { _ in provider }, currentProfile: { "" },
                                      headlessUplink: { asked.take([]); return nil })
    await bridge.backgroundPull()
    #expect(asked.batches.isEmpty)
    #expect(h.provider.fetches.isEmpty)
  }

  @Test("待核实五 上传通道走的是复盘本同一条路：POST 交易回合，传完的标记落在档案目录的 trades-v1.json 里，回前台不再重传")
  func signedInUplinkMarksUploaded() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("exchange-uplink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let calls = TransportLog()
    let client = ScorebookClient { path, method, _, key in
      await calls.record(path: path, method: method, key: key)
      return Data(#"{"data":{"records":[]}}"#.utf8)
    }
    let rounds = ExchangeAuditOwnershipTests.someRounds()
    #expect(!rounds.isEmpty)
    let uplink = ExchangeReviewUplink.signedIn(profile: "u-a", directory: directory, client: client)
    #expect(uplink.profile == "u-a")

    await uplink.upload?(rounds)

    let sent = await calls.entries
    #expect(sent.count == 1)
    #expect(sent.first?.path == "v1/native-review/trades")
    #expect(sent.first?.method == "POST")
    #expect(sent.first?.key != nil)
    // 回前台时复盘本另开一份同目录的档：读到的是「都传过了」。
    let reopened = TradeReviewStore(directory: directory)
    #expect(TradeUploadPlan.pending(rounds, uploaded: reopened.archive.uploaded,
                                    rejected: reopened.archive.rejected).isEmpty)
  }
}

/// 假上传通道记下的请求。
actor TransportLog {
  struct Entry: Sendable { var path: String; var method: String; var key: UUID? }
  private(set) var entries: [Entry] = []
  func record(path: String, method: String, key: UUID?) { entries.append(.init(path: path, method: method, key: key)) }
}

@Suite("审查 E · 桥层移除交易所 Key（R13）", .serialized)
@MainActor
struct ExchangeBridgeDisconnectTests {
  @Test("R13 移除时 Key 删不掉：桥留在已接入、给一行红字；Key 与元数据都还在，下次启动也照实是已接入")
  func keyDeleteFailureKeepsConnected() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey()
    let bridge = h.bridge(uplink: nil)
    await bridge.backgroundPull()  // 先把状态从 Keychain 读进来
    #expect(bridge.connected)
    h.keychain.failDeletes("credentials")

    await bridge.disconnect()

    #expect(bridge.connected)
    #expect(bridge.lastFailure != nil)
    #expect(try h.store.loadCredentials() != nil)
    #expect(try h.store.loadStatus() != nil)
  }

  @Test("R13 Key 删掉了、元数据删不掉：桥照实留在已接入并给红字；再移除一次收干净")
  func statusDeleteFailureThenRetry() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey()
    let bridge = h.bridge(uplink: nil)
    await bridge.backgroundPull()
    h.keychain.failDeletes("status")

    await bridge.disconnect()
    #expect(bridge.connected)
    #expect(bridge.lastFailure != nil)
    #expect(try h.store.loadCredentials() == nil)

    h.keychain.allowDeletes("status")
    await bridge.disconnect()
    #expect(!bridge.connected)
    #expect(bridge.lastFailure == nil)
  }

  @Test("R13 正常移除：桥回到未接入、没有红字")
  func cleanDisconnect() async throws {
    let h = try BridgeHarness(); defer { h.tearDown() }
    try h.connectKey()
    let bridge = h.bridge(uplink: nil)
    await bridge.backgroundPull()
    #expect(bridge.connected)
    await bridge.disconnect()
    #expect(!bridge.connected)
    #expect(bridge.lastFailure == nil)
    #expect(try h.store.loadCredentials() == nil)
  }
}
