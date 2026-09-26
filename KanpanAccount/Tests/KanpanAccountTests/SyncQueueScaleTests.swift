import Foundation
import Testing
@testable import KanpanAccount

/// 压测 2026-09-26：待发队列上万条时，回执入账、拉取、启动对账、批量记账不能是 O(n²)。
///
/// 这几处改成「先建索引、再逐条查」之后，**行为必须和从前逐条扫一模一样**——
/// 所以判据不是计时，是拿从前那份逐条处理的写法当参照，在随机存档上逐字段比。
/// 规模那一半只验「推得空、分批数对」，不断言耗时（机器负载不同，计时断言会抖）。
@MainActor @Suite("同步队列的规模：索引化之后与逐条处理逐字段一致") struct SyncQueueScaleTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent("kanpan-scale-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }

  /// 可复现的随机数（SplitMix64）。
  private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  // MARK: - 参照：从前逐条处理的回执入账（2026-09-26 之前 `SyncStore.acknowledge` 的原文）

  private static func referenceAcknowledge(_ archive: SyncArchive, _ response: SyncPushResponse) -> SyncArchive {
    var a = archive
    let pending = Set(a.operations.map(\.id))
    let mine = response.results.filter { pending.contains($0.operationId) }
    guard !mine.isEmpty else { return a }
    for result in mine {
      let acked = a.operations.first { $0.id == result.operationId }
      a.objects[result.object.key] = result.object
      a.operations.removeAll { $0.id == result.operationId }; a.sent.remove(result.operationId)
      for index in a.operations.indices where a.operations[index].dependsOn == result.operationId {
        a.operations[index].dependsOn = acked?.dependsOn
      }
      let generationIsMine = acked?.action == "restore"
      for index in a.operations.indices where !a.sent.contains(a.operations[index].id) && a.operations[index].key == result.object.key {
        if a.operations[index].action == "restore" {
          a.operations[index].baseRevision = result.object.revision
          a.operations[index].generation = result.object.generation
        } else if generationIsMine {
          a.operations[index].generation = result.object.generation
        }
      }
      if let local = a.local[result.object.key], local.body == result.object.body, local.deleted == result.object.deleted {
        a.rejected.removeAll { $0.key == result.object.key }
      }
      if !a.holdsLocal(result.object.collection, result.object.id) {
        if SyncStore.differs(a.local[result.object.key], result.object) { a.unapplied?.insert(result.object.collection) }
        a.shelve(before: result.object)
        a.local[result.object.key] = result.object
      }
    }
    return a
  }

  // MARK: - 随机存档

  private static let ids = (0..<6).map { "binance/usd_m/BTCUSDT/\($0)" }

  private static func object(_ id: String, _ rng: inout Seeded) -> SyncObject {
    var o = SyncObject(collection: "drawings", id: id)
    o.body = ["v": .number(Double(Int.random(in: 0..<3, using: &rng)))]
    o.deleted = Int.random(in: 0..<5, using: &rng) == 0
    o.revision = Int64.random(in: 0..<6, using: &rng)
    o.generation = Int64.random(in: 0..<3, using: &rng)
    return o
  }

  private static func randomArchive(_ rng: inout Seeded) -> SyncArchive {
    var a = SyncArchive()
    for id in ids {
      if Bool.random(using: &rng) { let o = object(id, &rng); a.objects[o.key] = o }
      if Int.random(in: 0..<4, using: &rng) > 0 { let o = object(id, &rng); a.local[o.key] = o }
      if Int.random(in: 0..<5, using: &rng) == 0 {
        a.shelved["drawings:" + id] = ShelvedObject(collection: "drawings", id: id,
                                                    object: Bool.random(using: &rng) ? object(id, &rng) : nil)
      }
    }
    let actions = ["patch", "patch", "patch", "delete", "restore"]
    for _ in 0..<Int.random(in: 0..<40, using: &rng) {
      let id = ids.randomElement(using: &rng)!
      var dependsOn = a.operations.last { $0.objectId == id }?.id
      if Int.random(in: 0..<8, using: &rng) == 0 { dependsOn = a.operations.randomElement(using: &rng)?.id }
      let op = SyncOperation(collection: "drawings", objectId: id, deviceId: UUID(),
        baseRevision: Int64.random(in: 0..<6, using: &rng), generation: Int64.random(in: 0..<3, using: &rng),
        timestamp: 1, logical: 1, action: actions.randomElement(using: &rng)!,
        fields: ["v": .number(1)], importBatch: nil, dependsOn: dependsOn)
      a.operations.append(op)
      if Int.random(in: 0..<3, using: &rng) == 0 { a.sent.insert(op.id) }
    }
    for id in ids where Int.random(in: 0..<5, using: &rng) == 0 {
      let op = SyncOperation(collection: "drawings", objectId: id, deviceId: UUID(), baseRevision: 0, generation: 0,
                             timestamp: 1, logical: 1, action: "patch", fields: [:], importBatch: nil)
      a.rejected.append(RejectedOperation(operation: op, reason: "invalid_operation", at: 0, intent: object(id, &rng)))
    }
    a.unapplied = Int.random(in: 0..<4, using: &rng) == 0 ? nil : []
    return a
  }

  private static func randomResponse(_ a: SyncArchive, _ rng: inout Seeded) -> SyncPushResponse {
    var picked = a.operations.filter { _ in Int.random(in: 0..<3, using: &rng) > 0 }
    if Bool.random(using: &rng) { picked.shuffle(using: &rng) }
    if let again = picked.randomElement(using: &rng), Int.random(in: 0..<4, using: &rng) == 0 { picked.append(again) }
    var results: [SyncResult] = picked.map { op in
      var object = object(Int.random(in: 0..<10, using: &rng) == 0 ? ids.randomElement(using: &rng)! : op.objectId, &rng)
      // 一部分回执的内容和本机一样，好走到「拒绝记录了结」那条路。
      if Bool.random(using: &rng), let local = a.local[object.key] { object.body = local.body; object.deleted = local.deleted }
      return SyncResult(operationId: op.id, object: object, cursor: 1, droppedFields: nil)
    }
    if Int.random(in: 0..<4, using: &rng) == 0 {
      results.append(SyncResult(operationId: UUID(), object: object(ids[0], &rng), cursor: 1, droppedFields: nil))
    }
    return SyncPushResponse(results: results, serverTime: 0)
  }

  private static func encoded<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return try encoder.encode(value)
  }

  /// 除了 `offset`（两边各自拿「现在」算）之外逐字段相等。
  private static func expectSame(_ got: SyncArchive, _ want: SyncArchive, trial: Int) throws {
    #expect(try encoded(got.operations) == encoded(want.operations), "trial \(trial): operations")
    #expect(got.sent == want.sent, "trial \(trial): sent")
    #expect(got.objects == want.objects, "trial \(trial): objects")
    #expect(got.local == want.local, "trial \(trial): local")
    #expect(try encoded(got.rejected) == encoded(want.rejected), "trial \(trial): rejected")
    #expect(got.shelved == want.shelved, "trial \(trial): shelved")
    #expect(got.unapplied == want.unapplied, "trial \(trial): unapplied")
  }

  @Test func indexedAcknowledgeMatchesSequentialReference() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root)
    var rng = Seeded(state: 20260926)
    for trial in 0..<600 {
      let archive = Self.randomArchive(&rng)
      let response = Self.randomResponse(archive, &rng)
      try store.transaction { $0 = archive }
      try store.acknowledge(response)
      try Self.expectSame(store.archive, Self.referenceAcknowledge(archive, response), trial: trial)
    }
    await store.flush()
  }

  /// 批量记账查的是一次建好的前驱表，逐个记账往回扫队列：两条路记出来的依赖链、动作、字段、版本一模一样。
  @Test func batchCaptureMatchesOneByOneCapture() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    var rng = Seeded(state: 7)
    for trial in 0..<150 {
      let archive = Self.randomArchive(&rng)
      var values: [SyncObject] = []
      for _ in 0..<Int.random(in: 2..<14, using: &rng) {
        var o = Self.object(Self.ids.randomElement(using: &rng)!, &rng)
        o.body["v"] = .number(Double(Int.random(in: 0..<9, using: &rng)))
        values.append(o)
      }
      let device = UUID()
      let batched = try SyncStore(directory: root.appendingPathComponent("b\(trial)"))
      try batched.transaction { $0 = archive }
      try batched.capture(values, device: device)
      let single = try SyncStore(directory: root.appendingPathComponent("s\(trial)"))
      try single.transaction { $0 = archive }
      for value in values { try single.capture(value, device: device) }
      let got = batched.archive.operations, want = single.archive.operations
      #expect(got.count == want.count, "trial \(trial)")
      // 新记的那几条 id 各自是新 UUID：按位置换算成「前驱是第几条」再比。
      func shape(_ ops: [SyncOperation]) -> [String] {
        let index = Dictionary(ops.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { a, _ in a })
        return ops.map { op in
          let parent = op.dependsOn.map { index[$0].map(String.init) ?? "gone" } ?? "-"
          return "\(op.key)|\(op.action)|\(op.baseRevision)|\(op.generation)|\(parent)|\(op.fields)"
        }
      }
      #expect(shape(got) == shape(want), "trial \(trial)")
      #expect(batched.archive.local == single.archive.local, "trial \(trial)")
      #expect(batched.archive.shelved == single.archive.shelved, "trial \(trial)")
    }
  }

  // MARK: - 规模

  private func line(_ symbol: Int, _ n: Int, _ v: Int) -> SyncObject {
    var o = SyncObject(collection: "drawings", id: "binance/usd_m/S\(symbol)USDT/\(n)")
    o.body = ["symbol": .string("S\(symbol)USDT"), "text": .string("v\(v)"), "p0": .number(Double(v))]
    return o
  }

  /// 离线攒 6000 条（1500 条线各改四次、分布在 50 个品种上）：启动对账、拉取、推空都要走得完，
  /// 推空按每批 100 条走（依赖链不许把分批切碎）。修前 Debug 下这一条要跑十几秒。
  @Test func sixThousandPendingOperationsDrain() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    let transport = ServerTransport(server)
    let count = 6000, lines = count / 4
    for v in 0..<4 { try store.capture((0..<lines).map { line($0 % 50, $0, v) }, device: device) }
    #expect(store.archive.operations.count == count)
    // 每条线四条操作连成一条链。
    #expect(store.archive.operations.filter { $0.dependsOn != nil }.count == count - lines)

    // 启动对账：盘上一条都没有 → 本机说了算的 1500 条全要补回去。
    #expect(store.startupCorrections(in: ["drawings"], onDisk: []).count == lines)

    // 拉回一页别的对象：队列里的对象一个都不许被云端那份盖掉，其余的进 `local`。
    var page: [SyncObject] = (0..<lines).map { var o = line($0 % 50, $0 + lines, 9); o.revision = 1; return o }
    var clash = line(0, 0, 99); clash.revision = 7; page.append(clash)
    try store.receive(SyncPage(objects: page, next: nil, cursor: 1, serverTime: 0))
    #expect(store.archive.local[clash.key]?.body["text"] == .string("v3"))
    #expect(store.archive.local.count == lines * 2)

    let outcome = try await SyncEngine(store: store, transport: transport, device: device).run(.push)
    #expect(store.archive.operations.isEmpty)
    #expect(store.archive.sent.isEmpty)
    #expect(outcome.batches.count == count / 100)
    #expect(server.objects.filter { $0.value.body["text"] == .string("v3") }.count == lines)
    await store.flush()
  }
}
