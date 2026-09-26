import Foundation
import Testing
@testable import KanpanAccount

/// 压测 2026-09-26：推到一半断线 / 被顶下线 / 5xx / 限流交替着来，队列最后必须推空、
/// 每个对象落在用户最后一改上；两台设备交替改同一字段上千次最后收敛；
/// 整份拉回几千条大画线加一份 MB 级设置，一次装进存档。
///
/// 判据全是结构性的（推空了没有、云端和两台本机是不是同一份、有没有被当成坏操作隔离），不计时。
@MainActor @Suite("同步结账：断线、顶号、5xx 交替与双机收敛") struct SyncSettlementStressTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent("kanpan-settle-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }

  /// 「服务端已经落库、回执没到手」：先让服务端真的推进去，再把连接掐断。
  @MainActor final class FlakyTransport: SyncTransport {
    enum Fault { case afterCommit, beforeCommit(Int, String), none }
    let inner: ServerTransport
    var faults: [Fault] = []
    private(set) var committedThenDropped = 0
    init(_ inner: ServerTransport) { self.inner = inner }
    func push(_ body: Data, key: UUID) async throws -> SyncPushResponse {
      let fault = faults.isEmpty ? .none : faults.removeFirst()
      switch fault {
      case .none: return try await inner.push(body, key: key)
      case .beforeCommit(let code, let reason): throw AccountError.http(code, reason)
      case .afterCommit:
        _ = try await inner.push(body, key: key)
        committedThenDropped += 1
        throw URLError(.networkConnectionLost)
      }
    }
    func bootstrap(collection: String, prefix: String?, after: String?) async throws -> SyncPage {
      try await inner.bootstrap(collection: collection, prefix: prefix, after: after)
    }
  }

  private func line(_ n: Int, _ v: Int) -> SyncObject {
    var o = SyncObject(collection: "drawings", id: "binance/usd_m/S\(n % 20)USDT/\(n)")
    o.body = ["symbol": .string("S\(n % 20)USDT"), "text": .string("v\(v)")]; return o
  }

  /// 300 条线各改 10 次（3000 条），推送时每几批就插一种故障；中间用户还在接着改。
  @Test func interleavedFaultsStillSettleOnTheLastEdit() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let transport = FlakyTransport(ServerTransport(server))
    let engine = SyncEngine(store: store, transport: transport, device: device)
    let lines = 300
    var last: [String: Int] = [:]
    func edit(_ v: Int) throws {
      try store.capture((0..<lines).map { line($0, v) }, device: device)
      for n in 0..<lines { last[line(n, v).key] = v }
    }
    for v in 0..<6 { try edit(v) }
    let cycle: [FlakyTransport.Fault] = [
      .none, .afterCommit, .none, .beforeCommit(503, "unavailable"), .afterCommit, .afterCommit,
      .beforeCommit(401, "session_replaced"), .none, .beforeCommit(429, "rate_limited"), .afterCommit,
    ]
    var rounds = 0, failures = 0, v = 6
    while !store.archive.operations.isEmpty || v < 10 {
      rounds += 1
      #expect(rounds < 400, "推不空")
      if rounds >= 400 { break }
      if transport.faults.isEmpty { transport.faults = cycle }
      do { try await engine.run(.push) } catch { failures += 1 }
      // 断线之间用户还在改：已经发出去（`sent`）的那几条原样重发，新改的排在后面。
      if rounds % 3 == 0, v < 10 { try edit(v); v += 1 }
    }
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.sent.isEmpty)
    #expect(store.archive.rejected.isEmpty, "不许有操作被当成坏的隔离：\(store.archive.rejected.map(\.reason))")
    #expect(transport.committedThenDropped > 0 && failures > 0)
    for (key, value) in last {
      #expect(server.objects[key]?.body["text"] == .string("v\(value)"), "\(key)")
      #expect(store.archive.local[key]?.body["text"] == .string("v\(value)"), "\(key)")
    }
    print("SETTLE rounds=\(rounds) failures=\(failures) committedThenDropped=\(transport.committedThenDropped)")
    await store.flush()
  }

  /// 两台设备交替改同一个设置字段 1000 次，推 / 拉的先后随机；最后各跑两轮全量，
  /// 两台本机和云端必须是同一份，而且值是某一次真实写入的值。
  @Test func twoDevicesAlternatingOneFieldConverge() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    struct Side { let store: SyncStore; let engine: SyncEngine; let device: UUID }
    func side(_ name: String) throws -> Side {
      let dir = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      let store = try SyncStore(directory: dir), device = UUID()
      return Side(store: store, engine: SyncEngine(store: store, transport: ServerTransport(server), device: device), device: device)
    }
    let a = try side("a"), b = try side("b")
    var written = Set<Double>()
    var rng = SystemRandomNumberGenerator()
    func write(_ s: Side, _ value: Double) throws {
      // 用户眼前那一版：本机 `appliedLocal` 叠上这次改的字段。
      var chart = s.store.archive.appliedLocal["settings:chart"] ?? SyncObject(collection: "settings", id: "chart")
      chart.body["barSpacing"] = .number(value)
      chart.body["other\(Int(value) % 3)"] = .number(value)
      chart.deleted = false
      try s.store.capture(chart, device: s.device)
      written.insert(value)
    }
    for i in 0..<1000 {
      let s = i % 2 == 0 ? a : b
      try write(s, Double(i))
      switch Int.random(in: 0..<4, using: &rng) {
      case 0: try await s.engine.run(.push)
      case 1: try await s.engine.run(.full(drawingsPrefix: nil))
      case 2: try await (i % 2 == 0 ? b : a).engine.run(.full(drawingsPrefix: nil))
      default: break   // 攒着不推
      }
      // 全量拉回来的那批要「装进本机」：这里没有正式文件，装就是把底稿作废。
      for side in [a, b] where side.store.needsApply { try side.store.markApplied(at: 0) }
    }
    for _ in 0..<2 {
      for side in [a, b] {
        try await side.engine.run(.full(drawingsPrefix: nil))
        if side.store.needsApply { try side.store.markApplied(at: 0) }
      }
    }
    let cloud = try #require(server.objects["settings:chart"])
    for side in [a, b] {
      #expect(side.store.archive.operations.isEmpty)
      #expect(side.store.archive.local["settings:chart"]?.body == cloud.body)
    }
    guard case .number(let final)? = cloud.body["barSpacing"] else { Issue.record("没有 barSpacing"); return }
    #expect(written.contains(final))
    print("CONVERGE final=\(final) revision=\(cloud.revision)")
  }

  /// 整份拉回：3000 条画线（每条 100 个锚点）+ 一份 1 MB 的设置，分页 500。
  /// 全部进 `objects` 与 `local`，存档写盘后重读逐项一致。
  @Test func hugeBootstrapLandsWhole() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let server = FakeSyncServer()
    for n in 0..<3000 {
      var o = SyncObject(collection: "drawings", id: "binance/usd_m/S\(n % 40)USDT/\(n)")
      o.body = ["symbol": .string("S\(n % 40)USDT"),
                "points": .array((0..<100).map { .array([.number(Double($0)), .number(1.0e308 / Double($0 + 1))]) })]
      o.revision = 3
      server.seed(o)
    }
    var chart = SyncObject(collection: "settings", id: "chart")
    chart.body = ["blob": .string(String(repeating: "长", count: 350_000))]   // UTF-8 约 1 MB
    chart.revision = 1
    server.seed(chart)
    let transport = ServerTransport(server)
    let store = try SyncStore(directory: root), device = UUID()
    let engine = SyncEngine(store: store, transport: transport, device: device)
    let clock = ContinuousClock.now
    try await engine.run(.full(drawingsPrefix: ""))
    await store.flush()
    let elapsed = clock.duration(to: .now)
    #expect(store.archive.objects.count == 3001)
    #expect(store.archive.local.count == 3001)
    let reread = try #require(try SyncStore.readArchive(directory: root))
    #expect(reread.local.count == 3001)
    #expect(reread.local["settings:chart"] == chart)
    print("BOOTSTRAP 3001 objects elapsed=\(elapsed) bytes=\(store.bytesWritten) writes=\(store.writeCount)")
  }
}
