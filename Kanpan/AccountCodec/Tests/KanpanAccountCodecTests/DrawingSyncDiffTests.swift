import Foundation
import Testing
import KanpanCore
@testable import KanpanAccount
@testable import KanpanAccountCodec

/// 画线按脏品种增量记账（`DrawingSyncDiff`）：记出来的账必须和整份记一模一样，只是少编很多条。
@MainActor @Suite("画线按脏品种增量记账") struct DrawingSyncDiffTests {
  private let device = UUID()
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }
  private func drawing(_ id: String, price: Double = 100) -> Drawing {
    Drawing(id: id, kind: .trend, points: [DrawPoint(t: 1, p: price), DrawPoint(t: 2, p: price + 10)])
  }
  private func symbol(_ i: Int) -> String { "binance/usd_m/S\(i)USDT" }
  private func archive(symbols: Int, perSymbol: Int) -> DrawArchive {
    var value = DrawArchive()
    for s in 0..<symbols { value[symbol(s)] = (0..<perSymbol).map { drawing("d\(s)-\($0)", price: Double(100 + $0)) } }
    return value
  }
  private func full(_ archive: DrawArchive) throws -> SyncCaptureBatch { try DrawingSyncDiff().batch(archive) }
  private func record(_ batch: SyncCaptureBatch, into store: SyncStore) throws {
    try store.capture(batch.withDeletions(against: store.archive.local.values), device: device, owning: PersonalSyncCodec.ownedKeys)
  }
  /// 队列里每条操作的「对象 + 动作 + 字段」，按顺序（操作号、时间戳不算）。
  private func ledger(_ store: SyncStore) -> [String] {
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    return store.archive.operations.map { op in
      "\(op.collection):\(op.objectId)|\(op.action)|" + String(decoding: (try? encoder.encode(op.fields)) ?? Data(), as: UTF8.self)
    }.sorted()
  }

  /// 一串典型编辑（改一条、加一条、删一条、清空一个品种、改工具偏好、新开一个品种），
  /// 每一步整份记和增量记产生的操作与 `local` 都一样。
  @Test func incrementalRecordsExactlyWhatAFullCaptureRecords() throws {
    let wholeStore = try SyncStore(directory: temp()), deltaStore = try SyncStore(directory: temp())
    var current = archive(symbols: 5, perSymbol: 4)
    var diff = DrawingSyncDiff()
    try record(full(current), into: wholeStore)
    try record(diff.batch(current), into: deltaStore); diff.captured(current)
    #expect(ledger(wholeStore) == ledger(deltaStore))

    let edits: [(inout DrawArchive) -> Void] = [
      { $0[self.symbol(1)][2] = self.drawing("d1-2", price: 999) },
      { $0[self.symbol(3)].append(self.drawing("new")) },
      { $0[self.symbol(0)].removeFirst() },
      { $0[self.symbol(4)] = [] },
      { $0.preferences.magnet.toggle() },
      { $0[self.symbol(9)] = [self.drawing("fresh")] },
      { _ in },
    ]
    for edit in edits {
      edit(&current)
      try record(full(current), into: wholeStore)
      let batch = try diff.batch(current)
      try record(batch, into: deltaStore); diff.captured(current)
      #expect(ledger(wholeStore) == ledger(deltaStore))
      #expect(wholeStore.archive.local == deltaStore.archive.local)
    }
  }

  /// 只编改过的那一桶；工具偏好没动就不带。
  @Test func onlyTheDirtyBucketIsEncoded() throws {
    var current = archive(symbols: 20, perSymbol: 50)
    var diff = DrawingSyncDiff(); diff.captured(current)
    current[symbol(7)][0] = drawing("d7-0", price: 1)
    let batch = try diff.batch(current)
    #expect(batch.objects.count == 50)
    #expect(batch.objects.allSatisfy { PersonalSyncCodec.instrument($0) == InstrumentID.canonical(symbol(7)) })
    #expect(try diff.batch(diff.baseline!).objects.isEmpty)
  }

  /// 别的品种上本机解不出来的那条云端画线（更新版本客户端画的新工具），增量记账不会顺手把它记成删除。
  /// 整份记会——这是增量顺带修掉的一个误删面：只剩用户真去动那个品种时才会推删除。
  @Test func anUndecodableCloudDrawingOnAnotherSymbolIsLeftAlone() throws {
    let store = try SyncStore(directory: temp())
    var current = archive(symbols: 2, perSymbol: 1)
    var diff = DrawingSyncDiff()
    try record(diff.batch(current), into: store); diff.captured(current)
    var alien = SyncObject(collection: "drawings", id: InstrumentID.canonical(symbol(1)) + "/alien")
    alien.body = ["kind": .string("fromTheFuture")]
    #expect(try SyncOverlayProbe.decodes(alien) == false)
    // 云端那份进了 `local`（回执 / 拉取都这么写）。
    var archiveValue = store.archive; archiveValue.local[alien.key] = alien
    let staged = archiveValue
    try store.transaction { $0 = staged }
    current[symbol(0)].append(drawing("another"))
    try record(diff.batch(current), into: store)
    #expect(store.archive.local[alien.key]?.deleted == false)
    // 对照：整份记会把它记成删除。
    try record(full(current), into: store)
    #expect(store.archive.local[alien.key]?.deleted == true)
  }

  /// 云端装进来：装之前正是基线就挪到装之后那份；不是（有没记上的改动）就清空、下次整份对。
  @Test func rebaseFollowsAnApplyOnlyFromTheBaseline() throws {
    let before = archive(symbols: 2, perSymbol: 2)
    var after = before; after[symbol(5)] = [drawing("cloud")]
    var diff = DrawingSyncDiff(); diff.captured(before)
    diff.rebase(from: before, to: after)
    #expect(diff.baseline == after)
    var edited = before; edited[symbol(0)] = []
    diff.captured(before)
    diff.rebase(from: edited, to: after)
    #expect(diff.baseline == nil)
    diff.captured(before)
    diff.rebase(from: edited, to: edited)
    #expect(diff.baseline == before)
  }

  /// 20 个品种 × 50 条：整份记与只动一个品种的增量记，编出来的字节与耗时。
  @Test func measureFullVersusIncremental() throws {
    let base = archive(symbols: 20, perSymbol: 50)
    var edited = base; edited[symbol(3)][10] = drawing("d3-10", price: 42)
    var diff = DrawingSyncDiff(); diff.captured(base)
    let encoder = JSONEncoder()
    func time(_ work: () throws -> Void) rethrows -> Double {
      let start = ContinuousClock.now
      for _ in 0..<20 { try work() }
      let d = ContinuousClock.now - start
      return (Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15) / 20
    }
    var fullBytes = 0, deltaBytes = 0
    let fullMs = try time { fullBytes = try encoder.encode(full(edited).objects).count }
    let deltaMs = try time { deltaBytes = try encoder.encode(diff.batch(edited).objects).count }
    // 连记账一起（编码 + 推删除 + 逐条跟 `local` 比）：主线程上抬手那一下实际花的。
    let wholeStore = try SyncStore(directory: temp()), deltaStore = try SyncStore(directory: temp())
    try record(full(base), into: wholeStore); try record(full(base), into: deltaStore)
    let fullCaptureMs = try time { try record(full(edited), into: wholeStore) }
    let deltaCaptureMs = try time { try record(diff.batch(edited), into: deltaStore) }
    #expect(ledger(wholeStore) == ledger(deltaStore))
    print("[DrawingSyncDiff] 20×50 画线，改一条：编码 整份 \(fullBytes) B / \(String(format: "%.2f", fullMs)) ms，增量 \(deltaBytes) B / \(String(format: "%.2f", deltaMs)) ms；连记账 整份 \(String(format: "%.2f", fullCaptureMs)) ms，增量 \(String(format: "%.2f", deltaCaptureMs)) ms")
    #expect(deltaBytes * 10 < fullBytes)
  }
}

/// 测试里问一句「这条对象本机解得出来吗」。
enum SyncOverlayProbe {
  static func decodes(_ object: SyncObject) throws -> Bool {
    var probe = DrawArchive()
    SyncOverlay.drawings([object], onto: &probe)
    return !probe.bySymbol.isEmpty
  }
}
