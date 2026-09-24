import Foundation
import Testing
import KanpanCore
@testable import KanpanAccount
@testable import Kanpan

/// 同步对象落到本地模型上（`SyncOverlay`）——启动前向对账和 `applyPending` 共用的那一份。
@MainActor @Suite("同步对象落到本地档案") struct SyncOverlayTests {
  private let device = UUID()
  private let btc = "binance/usd_m/BTCUSDT"

  private func drawing(_ id: String, price: Double = 100) -> Drawing {
    Drawing(id: id, kind: .trend, points: [DrawPoint(t: 1, p: price), DrawPoint(t: 2, p: price + 10)])
  }
  private func objects(_ archive: DrawArchive) throws -> [String: SyncObject] {
    Dictionary(uniqueKeysWithValues: try PersonalSyncCodec.drawings(archive).map { ($0.id, $0) })
  }

  /// 删 → 移除；活 → 就地替换或追加；别的品种一根不动。
  @Test func drawingsReplaceAppendAndRemove() throws {
    var local = DrawArchive()
    local[btc] = [drawing("a"), drawing("b")]
    local["binance/usd_m/ETHUSDT"] = [drawing("e")]
    var cloud = DrawArchive()
    cloud[btc] = [drawing("a", price: 200), drawing("c")]
    let o = try objects(cloud)
    var gone = try #require(try objects(local)[btc + "/b"]); gone.deleted = true
    SyncOverlay.drawings([o[btc + "/a"]!, o[btc + "/c"]!, gone], onto: &local)
    #expect(local[btc].map(\.id) == ["a", "c"])
    #expect(local[btc].first?.points.first?.p == 200)
    #expect(local["binance/usd_m/ETHUSDT"].map(\.id) == ["e"])
  }

  /// 解不开的画线、解不开的工具偏好都跳过，别的照常落地。
  /// 从前 `applyPending` 里工具偏好解不开是整批抛——一份坏数据就让这台设备什么都装不进来。
  @Test func undecodableObjectsAreSkippedNotThrown() throws {
    var local = DrawArchive(); local[btc] = [drawing("a")]
    var broken = SyncObject(collection: "drawings", id: btc + "/x"); broken.body["kind"] = .string("toolFromTheFuture")
    var tools = SyncObject(collection: "drawingPreferences", id: "tools"); tools.body["styles"] = .string("not-a-dictionary")
    let before = local.preferences
    var cloud = DrawArchive(); cloud[btc] = [drawing("b")]
    SyncOverlay.drawings([broken, tools] + (try PersonalSyncCodec.drawings(cloud)).filter { $0.collection == "drawings" }, onto: &local)
    #expect(local[btc].map(\.id) == ["a", "b"])
    #expect(local.preferences == before)
  }

  /// 提醒：删 → 移除；活 → 按 id 覆盖。
  @Test func alertsReplaceAndRemove() throws {
    let a = Alert(kind: .price, symbol: btc, armedAt: 1, title: "BTC 到 100", created: 1)
    let b = Alert(kind: .price, symbol: btc, armedAt: 2, title: "BTC 到 110", created: 2)
    var local = AlertArchive(alerts: [a, b])
    var moved = a; moved.title = "BTC 到 120"
    let wire = try PersonalSyncCodec.alerts([moved, b])
    var removed = try #require(wire.first { $0.id.hasSuffix(b.id) }); removed.deleted = true
    SyncOverlay.alerts([try #require(wire.first { $0.id.hasSuffix(a.id) }), removed], onto: &local)
    #expect(local.alerts.map(\.id) == [a.id])
    #expect(local.alerts.first?.title == "BTC 到 120")
  }

  /// 自选整张重建：顺序按 `order`，分组归属跟着云端，「最近」「常看」按本机的留着。
  @Test func symbolsRebuildKeepsLocalOnlyFields() {
    var mine = SymbolPrefs(favorites: ["binance/usd_m/DOGEUSDT"])
    mine.recents = ["binance/usd_m/SOLUSDT"]
    let cloud = SymbolPrefs(favorites: [btc, "binance/usd_m/ETHUSDT"], groups: [FavoriteGroup(id: "g", name: "主力")],
                            groupForSymbol: [btc: "g"])
    let rebuilt = SyncOverlay.symbols(rebuiltFrom: PersonalSyncCodec.symbols(cloud).reversed(), keeping: mine)
    #expect(rebuilt.favorites == cloud.favorites)
    #expect(rebuilt.groups == cloud.groups)
    #expect(rebuilt.groupForSymbol == [btc: "g"])
    #expect(rebuilt.recents == mine.recents)
  }

  /// 逐条补（启动对账）：只动给了的那几条，按 `order` 插回原位，删的就删。
  @Test func symbolsPatchInsertsAtOrderAndRemoves() {
    var disk = SymbolPrefs(favorites: [btc, "binance/usd_m/SOLUSDT"])
    let wanted = SymbolPrefs(favorites: [btc, "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
    let eth = PersonalSyncCodec.symbols(wanted).first { $0.collection == "favorites" && $0.id.hasSuffix("ETHUSDT") }!
    var sol = PersonalSyncCodec.symbols(wanted).first { $0.collection == "favorites" && $0.id.hasSuffix("SOLUSDT") }!
    SyncOverlay.symbols([eth], patching: &disk)
    #expect(disk.favorites == wanted.favorites)
    sol.deleted = true
    SyncOverlay.symbols([sol], patching: &disk)
    #expect(disk.favorites == [btc, "binance/usd_m/ETHUSDT"])
  }

  /// 设置：没有对象、或者对象是墓碑，返回 nil（不动本地）；有就按字段合并，本地脏的留本地。
  @Test func settingsMergeKeepsDirtyFields() throws {
    #expect(try SyncOverlay.settings(nil, onto: .defaults, keeping: []) == nil)
    var cloud = Prefs.defaults; cloud.skin = .classic; cloud.theme = .light
    var dead = try PersonalSyncCodec.settings(cloud); dead.deleted = true
    #expect(try SyncOverlay.settings(dead, onto: .defaults, keeping: []) == nil)
    var mine = Prefs.defaults; mine.theme = .dark
    let merged = try #require(try SyncOverlay.settings(PersonalSyncCodec.settings(cloud), onto: mine, keeping: ["theme"]))
    #expect(merged.skin == .classic)
    #expect(merged.theme == .dark)
  }

  /// 启动前向对账整条走一遍：真的 `SyncStore` 挑、`SyncOverlay` 落。
  /// 云端墓碑删掉盘上的旧线；本机撤销过删除（待发 restore）的那条不被墓碑带走。
  @Test func startupCorrectionsThroughTheOverlay() throws {
    let sync = try SyncStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("overlay-" + UUID().uuidString))
    var disk = DrawArchive(); disk[btc] = [drawing("gone"), drawing("undo"), drawing("keep")]
    let wire = try objects(disk)
    var gone = wire[btc + "/gone"]!; gone.revision = 3
    var undo = wire[btc + "/undo"]!; undo.revision = 3
    try sync.receive(SyncPage(objects: [gone, undo], next: nil, cursor: 3, serverTime: 0))
    undo.deleted = true; try sync.capture(undo, device: device)
    undo.deleted = false; try sync.capture(undo, device: device)
    gone.deleted = true; gone.revision = 5
    var undoTomb = undo; undoTomb.deleted = true; undoTomb.revision = 5
    try sync.receive(SyncPage(objects: [gone, undoTomb], next: nil, cursor: 5, serverTime: 0))
    SyncOverlay.drawings(sync.startupCorrections(in: ["drawings", "drawingPreferences"], onDisk: try PersonalSyncCodec.drawings(disk)), onto: &disk)
    #expect(disk[btc].map(\.id).sorted() == ["keep", "undo"])
  }
}
