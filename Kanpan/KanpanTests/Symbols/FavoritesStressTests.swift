import Foundation
import Testing
import KanpanAccount

@testable import Kanpan

/// 自选 · 压测：几百只自选、几十个分类，随机拖排序、批量删再撤销、五秒撤销窗口里删分类 / 换账号，
/// 以及这一整份档案过落盘和同步编码的往返。
///
/// 判据全是结构性的（排列不变、归属不变、逐字段相等、撤销后一只不差），不按墙钟断言；
/// 耗时和「拖一下要发几条同步操作」只打印出来给报告用。
@Suite("自选 · 压测", .serialized)
@MainActor
struct FavoritesStressTests {

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

  private static func symbol(_ i: Int) -> String { "binance/usd_m/C\(i)USDT" }

  /// `count` 只自选分进 `groups` 个分类（随机分，没有落单的）。
  private func large(count: Int, groups: Int, rng: inout Seeded) throws -> SymbolPrefs {
    var prefs = SymbolPrefs(favorites: (0..<count).map(Self.symbol))
    #expect(prefs.favorites.count == count)
    var ids: [String] = []
    for g in 0..<groups {
      let id = prefs.createGroup("组\(g)")
      ids.append(try #require(id))
    }
    for s in prefs.favorites { prefs.assign(s, to: ids.randomElement(using: &rng)) }
    #expect(prefs.groups.count == groups)
    #expect(prefs.groupForSymbol.count == count)
    return prefs
  }

  private func randomIndexSet(upTo n: Int, rng: inout Seeded) -> IndexSet {
    var set = IndexSet()
    for _ in 0..<Int.random(in: 1...min(8, n), using: &rng) { set.insert(Int.random(in: 0..<n, using: &rng)) }
    return set
  }

  /// SwiftUI `move(fromOffsets:toOffset:)` 的参照实现：`moveVisible` 只能改动可见那几只的相对顺序。
  private func referenceMove(_ list: [String], _ source: IndexSet, _ destination: Int) -> [String] {
    let moving = source.map { list[$0] }
    var rest = list
    for i in source.sorted(by: >) { rest.remove(at: i) }
    let at = min(max(0, destination - source.filter { $0 < destination }.count), rest.count)
    rest.insert(contentsOf: moving, at: at)
    return rest
  }

  @Test("400 只 × 30 类随机拖 3000 下：始终是同一组品种的排列，分类归属一只不动，分类内拖只动那一类")
  func randomMovesKeepEverything() throws {
    var rng = Seeded(state: 0x5EED_F00D)
    var prefs = try large(count: 400, groups: 30, rng: &rng)
    let members = Set(prefs.favorites), membership = prefs.groupForSymbol
    var visibleMoves = 0
    for step in 0..<3000 {
      let n = prefs.favorites.count
      switch step % 3 {
      case 0:
        prefs.moveFavorites(from: randomIndexSet(upTo: n, rng: &rng), to: Int.random(in: 0...n, using: &rng))
      case 1:
        let a = prefs.favorites.randomElement(using: &rng)!, b = prefs.favorites.randomElement(using: &rng)!
        prefs.moveFavorite(a, onto: b)
      default:
        let group = prefs.groups.randomElement(using: &rng)!.id
        let visible = prefs.favorites(in: group)
        guard visible.count > 1 else { continue }
        let others = prefs.favorites.enumerated().filter { prefs.groupForSymbol[$0.element] != group }
        let source = randomIndexSet(upTo: visible.count, rng: &rng), destination = Int.random(in: 0...visible.count, using: &rng)
        prefs.moveVisible(visible, from: source, to: destination)
        #expect(prefs.favorites(in: group) == referenceMove(visible, source, destination), "第 \(step) 下分类内拖排出来的顺序不对")
        let othersAfter = prefs.favorites.enumerated().filter { prefs.groupForSymbol[$0.element] != group }
        #expect(othersAfter.map(\.offset) == others.map(\.offset) && othersAfter.map(\.element) == others.map(\.element),
                "第 \(step) 下分类内拖动到了别的分类的位置")
        visibleMoves += 1
      }
      #expect(prefs.favorites.count == members.count && Set(prefs.favorites) == members, "第 \(step) 下之后自选不再是原来那组品种")
      #expect(prefs.groupForSymbol == membership, "第 \(step) 下之后分类归属变了")
    }
    #expect(visibleMoves > 500)
  }

  @Test("批量删 1…60 只再撤销，重复 300 轮：每一轮都一字不差地回到删之前")
  func batchRemoveThenRestoreIsExact() throws {
    var rng = Seeded(state: 0xFA11_BACC)
    let original = try large(count: 500, groups: 24, rng: &rng)
    for round in 0..<300 {
      var prefs = original
      let doomed = Array(original.favorites.shuffled(using: &rng).prefix(Int.random(in: 1...60, using: &rng)))
      let snapshots = doomed.compactMap { prefs.snapshot(of: $0) }
      #expect(snapshots.count == doomed.count)
      doomed.forEach { prefs.removeFavorite($0) }
      prefs.restore(snapshots.shuffled(using: &rng))
      #expect(prefs == original, "第 \(round) 轮撤销后和删之前不一样")
    }
  }

  // MARK: - 五秒撤销窗口

  private func model(_ prefs: SymbolPrefs) -> (SymbolPickerModel, MemoryPrefsStorage) {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "stress")
    store.save(prefs)
    return (SymbolPickerModel(store: store), storage)
  }

  @Test("删了几只、五秒内把它们那一类删了、再点撤销：回来的几只和原来的同类伙伴落在同一格，自选页上看得见")
  func undoAfterItsCategoryWasDeletedLandsWithItsSiblings() throws {
    var rng = Seeded(state: 0xDE1E_7E6A)
    let prefs = try large(count: 300, groups: 12, rng: &rng)
    let (m, _) = model(prefs)
    let doomedGroup = prefs.groups[3].id
    m.selectedGroupSource = { doomedGroup }
    let siblings = prefs.favorites(in: doomedGroup)
    try #require(siblings.count > 6)
    let removed = Array(siblings.prefix(4)), stay = Array(siblings.dropFirst(4))
    let snapshots = removed.compactMap { m.favoriteSnapshot($0) }
    removed.forEach { m.removeFavorite($0) }
    // 「…」里的「删除当前分类」：剩下的伙伴被挪去 `group(selected)`。
    m.deleteGroup(doomedGroup)
    let landing = try #require(m.prefs.groupForSymbol[stay[0]])
    #expect(stay.allSatisfy { m.prefs.groupForSymbol[$0] == landing })

    m.restoreFavorites(snapshots)
    #expect(removed.allSatisfy(m.prefs.favorites.contains))
    for s in removed {
      #expect(m.prefs.groupForSymbol[s] == landing, "\(s) 撤销回来没跟伙伴落在同一格（\(m.prefs.groupForSymbol[s] ?? "未分类")）")
    }
    // 有分类在时，分类页只按分类列：没有一只自选可以挂在「未分类」上。
    let orphans = m.prefs.favorites.filter { m.prefs.groupForSymbol[$0] == nil }
    #expect(orphans.isEmpty, "撤销之后有 \(orphans.count) 只自选在分类页上哪一格都找不到")
    // 撤销回来的在原来的全局位置上。
    for snapshot in snapshots { #expect(m.prefs.favorites.firstIndex(of: snapshot.symbol) == snapshot.index) }
  }

  @Test("五秒撤销窗口里换了账号：上一个人的撤销点了也什么都不做，不写进新账号、不推同步")
  func undoAcrossProfileSwitchIsDropped() throws {
    var rng = Seeded(state: 0xACC0_5171)
    let alice = try large(count: 200, groups: 10, rng: &rng)
    let (m, _) = model(alice)
    var pushed = 0
    m.onPrefsChange = { _ in pushed += 1 }
    let doomed = Array(alice.favorites.prefix(30))
    let snapshots = doomed.compactMap { m.favoriteSnapshot($0) }
    doomed.forEach { m.removeFavorite($0) }
    let undo = m.undoable { m.restoreFavorites(snapshots) }

    let bob = SymbolPrefs(favorites: ["binance/usd_m/BTCUSDT"])
    let bobStorage = MemoryPrefsStorage()
    let bobStore = SymbolPrefsStore(storage: bobStorage, key: "bob")
    bobStore.save(bob)
    m.useStorage(bobStore, prefs: bob)
    let before = pushed
    undo()
    #expect(m.prefs == bob)
    #expect(bobStore.load() == bob)
    #expect(pushed == before, "换号之后上一个人的撤销还推了 \(pushed - before) 次同步")

    // 同一份档案里的撤销照常生效（守卫只挡换号，不挡正常撤销）。
    let (m2, _) = model(alice)
    let snap2 = doomed.compactMap { m2.favoriteSnapshot($0) }
    doomed.forEach { m2.removeFavorite($0) }
    let undo2 = m2.undoable { m2.restoreFavorites(snap2) }
    undo2()
    #expect(m2.prefs == alice)
  }

  // MARK: - 落盘与同步编码

  @Test("1500 只 × 60 类：落盘读回、同步编码整张重建都逐字段相等；记下拖一下要发几条同步操作")
  func archiveAndSyncRoundTripAtScale() throws {
    var rng = Seeded(state: 0x0A2C_1B1E)
    var prefs = try large(count: 1500, groups: 60, rng: &rng)
    for i in 0..<10 { prefs.visit(Self.symbol(i)) }

    let clock = ContinuousClock()
    let storage = MemoryPrefsStorage(), store = SymbolPrefsStore(storage: storage, key: "big")
    var bytes = 0
    let saveTime = clock.measure { store.save(prefs) }
    bytes = storage.symbolPrefsData(forKey: "big")?.count ?? 0
    var loaded = SymbolPrefs()
    let readTime = try clock.measure { loaded = try store.read() }
    #expect(loaded == prefs)

    let objects = PersonalSyncCodec.symbols(prefs)
    #expect(objects.count == 1500 + 60)
    let rebuilt = SyncOverlay.symbols(rebuiltFrom: objects, keeping: prefs)
    #expect(rebuilt == prefs, "同步编码整张重建之后和原件不一样")
    // 打乱对象到达的顺序（服务端分页、增量拉取）也重建成同一份。
    #expect(SyncOverlay.symbols(rebuiltFrom: objects.shuffled(using: &rng), keeping: prefs) == prefs)

    // 拖一下（末尾那只拖到最前）/ 删最前那一只 / 末尾加一只：同步层会看到几个对象变了。
    func changed(_ a: SymbolPrefs, _ b: SymbolPrefs) -> Int {
      let before = Dictionary(uniqueKeysWithValues: PersonalSyncCodec.symbols(a).map { ($0.key, $0.body) })
      let after = Dictionary(uniqueKeysWithValues: PersonalSyncCodec.symbols(b).map { ($0.key, $0.body) })
      return Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }.count
    }
    var dragged = prefs; dragged.moveFavorites(from: [1499], to: 0)
    var removedFirst = prefs; removedFirst.removeFavorite(prefs.favorites[0])
    var appended = prefs; appended.addFavorite("binance/usd_m/NEWUSDT", in: prefs.groups[0].id)
    print("FAVORITES-STRESS n=1500 groups=60 bytes=\(bytes) save=\(saveTime) read=\(readTime)"
          + " ops(dragLastToTop)=\(changed(prefs, dragged)) ops(removeFirst)=\(changed(prefs, removedFirst)) ops(append)=\(changed(prefs, appended))")
  }
}
