import Foundation
import Testing
@testable import KanpanAccount

/// 只扣 `v1/sync/operations` 这一趟的假服务器。请求一到就往 `arrivals` 里报一声，
/// 测试拿它当「A 的推送已经挂在网络上了」的信号——不靠 sleep 去猜它什么时候到。
final class SyncGateProtocol: URLProtocol {
  static let server = StubServer()
  static let gate = ResponseGate()
  nonisolated(unsafe) static var arrivals: AsyncStream<String>.Continuation?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let path = request.url?.path ?? ""
    SyncGateProtocol.server.record(.init(path: path, body: request.uploaded))
    SyncGateProtocol.arrivals?.yield(path)
    if path.hasSuffix("/v1/sync/operations") { SyncGateProtocol.gate.waitUntilOpen() }
    switch SyncGateProtocol.server.answer(path) {
    case .success(let (status, data)):
      let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    case .failure(let error):
      client?.urlProtocol(self, didFailWithError: error)
    }
  }
  override func stopLoading() {}
}

/// B.10 BT-21：A 的推送挂住 → 切到 B → A 的回执这时才到。B 的存档不许收到 A 的 ACK。
///
/// 两道门各测一遍：
/// 1. 客户端那道——换人时 `accept` 让刷新协调者换代，挂在网络上的那趟回来时代数对不上，
///    直接抛 `CancellationError`，调用方拿不到 A 的回执；
/// 2. 存档那道——就算有人把 A 的回执原样递给 B 的 `SyncStore.acknowledge`，B 的存档
///    （内存里和盘上）一个字节都不动。这道门是这一轮补上的：从前 `acknowledge` 不看
///    `operationId` 是不是自己发的，A 的对象会被写进 B 的 `objects` / `local`。
@MainActor @Suite("B.10 BT-21 迟到的回执不串户", .serialized)
struct StaleAckTests {
  private let alice = AccountUser(id: UUID(uuidString: "0A0A0A0A-1111-4C0A-9E2D-0A1B2C3D4E5F")!, email: "alice")
  private let bob = AccountUser(id: UUID(uuidString: "0B0B0B0B-2222-4C0A-9E2D-0A1B2C3D4E5F")!, email: "bob")

  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func makeClient(_ vault: StubVault) throws -> AccountClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyncGateProtocol.self]
    return try AccountClient(baseURL: URL(string: "https://" + ClientHardeningTests.host)!, vault: vault,
                             session: URLSession(configuration: configuration))
  }
  private func tokens(_ user: AccountUser, access: String) -> AccountTokens {
    AccountTokens(user: user, sessionId: UUID(), accessToken: access, refreshToken: "refresh-" + access,
                  expiresAt: 900_000, serverTime: 0)
  }
  private func envelope(_ response: SyncPushResponse) throws -> String {
    let inner = try JSONEncoder().encode(response)
    return #"{"data":"# + String(decoding: inner, as: UTF8.self) + "}"
  }
  /// 存档里和串户有关的那几块，按键排好序编码成一个可以直接比的值。
  private func fingerprint(_ a: SyncArchive) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(a)
  }

  @Test("A 推送挂住时切到 B，A 迟到的回执既到不了调用方，也进不了 B 的存档")
  func lateAckFromAIsNotAppliedToB() async throws {
    SyncGateProtocol.server.reset(); SyncGateProtocol.gate.close()
    let (arrivals, sink) = AsyncStream<String>.makeStream()
    SyncGateProtocol.arrivals = sink
    defer { SyncGateProtocol.gate.open(); SyncGateProtocol.arrivals = nil; sink.finish() }
    let rootA = try temp(), rootB = try temp()
    defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }

    let client = try makeClient(StubVault(nil))
    try await client.accept(tokens(alice, access: "access-a"), device: AccountDevice(name: "phone"))

    // A 记下一条画线并发出去。
    let storeA = try SyncStore(directory: rootA); let device = UUID()
    var lineA = SyncObject(collection: "drawings", id: "BTCUSDT/alice-line"); lineA.body["color"] = .string("red")
    try storeA.capture(lineA, device: device)
    let opA = try #require(storeA.archive.operations.first)
    try storeA.markSent([opA.id])
    lineA.revision = 7
    let lateAck = SyncPushResponse(results: [SyncResult(operationId: opA.id, object: lineA, cursor: 7)],
                                   serverTime: Int64(Date().timeIntervalSince1970 * 1000))
    SyncGateProtocol.server.route("/v1/sync/operations", 200, try envelope(lateAck))
    let payload = try JSONEncoder().encode(SyncPushRequest([opA]))
    let push = Task { () async throws -> SyncPushResponse in
      try await client.request("v1/sync/operations", method: "POST", body: payload, key: opA.id)
    }
    // 等到这趟真的挂在闸门上了。
    for await path in arrivals where path.hasSuffix("/v1/sync/operations") { break }

    // 切到 B：同一个客户端换人，B 有自己的存档目录和自己的一条待发操作。
    try await client.accept(tokens(bob, access: "access-b"), device: AccountDevice(name: "phone"))
    #expect(await client.savedUser()?.id == bob.id)
    let storeB = try SyncStore(directory: rootB)
    var lineB = SyncObject(collection: "drawings", id: "BTCUSDT/bob-line"); lineB.body["color"] = .string("blue")
    try storeB.capture(lineB, device: device)
    let opB = try #require(storeB.archive.operations.first)
    try storeB.markSent([opB.id])
    await storeB.flush()
    let before = try fingerprint(storeB.archive)
    let writesBefore = storeB.writeCount

    // A 的回执这时才到。
    SyncGateProtocol.gate.open()
    let delivered = await push.result
    switch delivered {
    case .success: Issue.record("换过人之后，A 那趟挂着的推送不许把回执交到调用方手上")
    case .failure(let error): #expect(error is CancellationError, "应当按「代数对不上」丢弃，而不是别的错误：\(error)")
    }

    // 第二道门：即使有人把 A 的回执原样递给了 B 的存档，B 也一个字节都不收。
    try storeB.acknowledge(lateAck)
    #expect(try fingerprint(storeB.archive) == before, "B 的存档不许因为 A 的回执变一个字节")
    #expect(storeB.archive.objects[lineA.key] == nil)
    #expect(storeB.archive.local[lineA.key] == nil)
    #expect(storeB.archive.operations.map(\.id) == [opB.id], "B 自己那条待发操作原样留着")
    #expect(storeB.archive.sent == [opB.id])
    await storeB.flush()
    #expect(storeB.writeCount == writesBefore, "一条都不是自己的回执不该触发写盘")
    let reopenedB = try SyncStore(directory: rootB)
    #expect(try fingerprint(reopenedB.archive) == before, "盘上的 B 存档也没被 A 的回执碰过")

    // 这份回执对 A 自己的存档仍然有效：门只拦别人的，不拦自己的。
    try storeA.acknowledge(lateAck)
    #expect(storeA.archive.operations.isEmpty)
    #expect(storeA.archive.objects[lineA.key]?.revision == 7)
  }

  @Test("一份回执里混着自己的和别人的操作：只认自己那几条")
  func mixedAckOnlyAppliesOwnResults() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root); let device = UUID()
    var mine = SyncObject(collection: "favorites", id: "mine"); mine.body["symbol"] = .string("BTCUSDT")
    try store.capture(mine, device: device)
    let op = try #require(store.archive.operations.first); try store.markSent([op.id])
    mine.revision = 3
    var foreign = SyncObject(collection: "favorites", id: "foreign"); foreign.body["symbol"] = .string("ETHUSDT"); foreign.revision = 9
    try store.acknowledge(SyncPushResponse(results: [
      SyncResult(operationId: UUID(), object: foreign, cursor: 9),
      SyncResult(operationId: op.id, object: mine, cursor: 3),
    ], serverTime: 0))
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.objects[mine.key]?.revision == 3)
    #expect(store.archive.objects[foreign.key] == nil, "别人的那条不许混进来")
    #expect(store.archive.local[foreign.key] == nil)
  }
}
