import Foundation
import Testing
@testable import KanpanAccount

/// 启动前向对账挑哪几份（`SyncStore.startupCorrections`）。
///
/// 这一步从前是 `prepare` 里「墓碑循环 + 前向对账循环」两段，规则写成「有待发的 `restore`
/// 才不删」；现在收成一条：云端墓碑算数，除非本机说了算（`holdsLocal`）。下面几条把两种写法
/// 净效果相同的那几个角落钉住。
@MainActor @Suite("启动前向对账：挑哪几份") struct StartupCorrectionsTests {
  private let device = UUID()
  private func store() throws -> SyncStore {
    try SyncStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("startup-" + UUID().uuidString))
  }
  private func line(_ id: String, color: String = "amber", revision: Int64 = 4, deleted: Bool = false) -> SyncObject {
    var o = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/" + id)
    o.body["color"] = .string(color); o.revision = revision; o.deleted = deleted
    return o
  }

  /// 别的设备删掉、本机没碰过的那条：墓碑要落到盘上（盘上还挂着它）。
  @Test func aCloudTombstoneIsReplayed() throws {
    let sync = try store()
    try sync.receive(SyncPage(objects: [line("gone", deleted: true)], next: nil, cursor: 4, serverTime: 0))
    let out = sync.startupCorrections(in: ["drawings"], onDisk: [line("gone")])
    #expect(out.map(\.id) == ["binance/usd_m/BTCUSDT/gone"])
    #expect(out.first?.deleted == true)
  }

  /// 别的集合的墓碑不混进来。
  @Test func otherCollectionsStayOut() throws {
    let sync = try store()
    var alert = SyncObject(collection: "alerts", id: "binance/usd_m/BTCUSDT/a"); alert.deleted = true; alert.revision = 2
    try sync.receive(SyncPage(objects: [alert], next: nil, cursor: 2, serverTime: 0))
    #expect(sync.startupCorrections(in: ["drawings"], onDisk: []).isEmpty)
    #expect(sync.startupCorrections(in: ["alerts"], onDisk: []).map(\.collection) == ["alerts"])
  }

  /// 本机先删后撤销（待发 `restore`）：墓碑不算数，盘上那条跟上本机的活值。
  /// 老写法是「有 restore 才不删」，这里由 `holdsLocal` 覆盖——同一个结果。
  @Test func aPendingRestoreBeatsTheTombstone() throws {
    let sync = try store()
    try sync.receive(SyncPage(objects: [line("undo")], next: nil, cursor: 4, serverTime: 0))
    var mine = line("undo"); mine.deleted = true; try sync.capture(mine, device: device)
    mine.deleted = false; mine.body["color"] = .string("blue"); try sync.capture(mine, device: device)
    #expect(sync.archive.operations.map(\.action) == ["delete", "restore"])
    // 云端那边另有设备把它删了——拉回来的墓碑不许盖掉本机的 restore。
    try sync.receive(SyncPage(objects: [line("undo", revision: 6, deleted: true)], next: nil, cursor: 6, serverTime: 0))
    let out = sync.startupCorrections(in: ["drawings"], onDisk: [line("undo")])
    #expect(out.count == 1)
    #expect(out.first?.deleted == false)
    #expect(out.first?.body["color"] == .string("blue"))
    // 盘上已经是本机这一版：什么都不用补，墓碑也不来捣乱。
    #expect(sync.startupCorrections(in: ["drawings"], onDisk: [mine]).isEmpty)
  }

  /// 云端删了、本机又改了它（待发 patch，没有 restore）：老写法先删、再由前向对账把本机的活值
  /// 补回来，净效果是「在，而且是本机那一版」；新写法一步给出同一个结果。
  @Test func aPendingPatchOnATombstonedObjectKeepsTheLocalValue() throws {
    let sync = try store()
    try sync.receive(SyncPage(objects: [line("edit")], next: nil, cursor: 4, serverTime: 0))
    let mine = line("edit", color: "green"); try sync.capture(mine, device: device)
    try sync.receive(SyncPage(objects: [line("edit", revision: 6, deleted: true)], next: nil, cursor: 6, serverTime: 0))
    #expect(sync.archive.holdsLocal("drawings", mine.id))
    #expect(sync.startupCorrections(in: ["drawings"], onDisk: [mine]).isEmpty)
    let stale = sync.startupCorrections(in: ["drawings"], onDisk: [line("edit")])
    #expect(stale.map(\.deleted) == [false])
    #expect(stale.first?.body["color"] == .string("green"))
  }

  /// 云端的活值一个都不碰：只向前补本机说了算的，别拿存档去回滚盘上的东西。
  @Test func liveCloudValuesAreNeverReplayed() throws {
    let sync = try store()
    try sync.receive(SyncPage(objects: [line("cloud", color: "red")], next: nil, cursor: 4, serverTime: 0))
    #expect(sync.startupCorrections(in: ["drawings"], onDisk: [line("cloud", color: "blue")]).isEmpty)
    #expect(sync.startupCorrections(in: ["drawings"], onDisk: []).isEmpty)
  }
}
