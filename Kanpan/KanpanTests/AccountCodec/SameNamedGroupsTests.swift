import Foundation
import Testing
@testable import KanpanAccount
@testable import Kanpan

/// 分类的身份是**名字**：同一个人手上不许出现两个「加密」。
///
/// 用户 2026-09-24 报的现象：手机换了包名（全新安装、访客状态）→ 访客那份默认自选建出了
/// 「加密」「美股」（id 是 `createGroup` 现场随机的）→ 登录老账号 → 自选页的分类条上
/// 两个「加密」、两个「美股」。
///
/// 机制分两段，这一组各钉一段：
/// - **登录合并**（`SymbolPrefs.absorb(guest:)`）以前按 id 并分类，同名不同 id 就成了两份；
/// - 更要命的是**全新安装**：登录那一刻账号目录是空的，云端的分类要等登录后第一次全量拉取
///   才到，合并那一步根本看不见它们——访客那两类被当成导入推上云端，拉回来的云端分类再按
///   对象 id 整张重建（`SyncOverlay.symbols(rebuiltFrom:)`），两份一起摆上分类条，而且
///   推上云之后别的设备也跟着看到四格。所以重建那一层也得按名字并，并且推删除让云端自愈。
@MainActor @Suite("同名分类并成一个") struct SameNamedGroupsTests {
  private let device = UUID()
  private let btc = "binance/usd_m/BTCUSDT", sol = "binance/usd_m/SOLUSDT"
  private let aapl = "binance/usd_m/AAPLUSDT", tsla = "binance/usd_m/TSLAUSDT"
  private let collections: Set<String> = ["favorites", "groups"]

  private func store() throws -> SyncStore {
    try SyncStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("same-named-" + UUID().uuidString))
  }
  /// 另一台设备早就推上云端的那份：「加密」「美股」各一类。
  private var account: SymbolPrefs {
    SymbolPrefs(favorites: [btc, aapl],
                groups: [FavoriteGroup(id: "K-crypto", name: "加密"), FavoriteGroup(id: "K-stock", name: "美股")],
                groupForSymbol: [btc: "K-crypto", aapl: "K-stock"])
  }
  /// 这台新装的手机在访客状态下攒的：同样两类，id 是现场随机的。
  private var guest: SymbolPrefs {
    SymbolPrefs(favorites: [sol, tsla],
                groups: [FavoriteGroup(id: "B-crypto", name: "加密"), FavoriteGroup(id: "B-stock", name: "美股")],
                groupForSymbol: [sol: "B-crypto", tsla: "B-stock"])
  }
  private func live(_ sync: SyncStore) -> [SyncObject] {
    sync.archive.local.values.filter { collections.contains($0.collection) }
  }
  private func names(_ prefs: SymbolPrefs) -> [String] { prefs.groups.map(\.name) }
  private func members(_ prefs: SymbolPrefs, _ name: String) -> Set<String> {
    guard let id = prefs.groups.first(where: { $0.name == name })?.id else { return [] }
    return Set(prefs.favorites(in: id))
  }

  // ---------------------------------------------------------------- 登录合并

  /// 账号目录里已经有「加密」「美股」（这台机器登过这个号）：访客的同名类并进去，
  /// 留账号那边的 id 与位置，访客那一类里的成员改挂到账号那一类上；访客独有的类接在后面。
  @Test func loginAbsorbsGuestCategoriesIntoSameNamedAccountOnes() {
    var mine = account
    var visitor = guest
    visitor.groups.append(FavoriteGroup(id: "B-venue", name: "Coinbase"))
    visitor.favorites.append("coinbase/spot/BTC-USD"); visitor.groupForSymbol["coinbase/spot/BTC-USD"] = "B-venue"
    mine.absorb(guest: visitor)
    #expect(mine.groups.map(\.id) == ["K-crypto", "K-stock", "B-venue"])
    #expect(names(mine) == ["加密", "美股", "Coinbase"])
    #expect(members(mine, "加密") == [btc, sol])
    #expect(members(mine, "美股") == [aapl, tsla])
    #expect(mine.favorites == [btc, aapl, sol, tsla, "coinbase/spot/BTC-USD"])
  }

  // ---------------------------------------------------------------- 全新安装 → 登录 → 第一次全量

  /// 用户那一跑的整条机制：全新安装（账号目录空）→ 访客两类当成导入记进队列 →
  /// 第一次全量把云端那两类拉下来 → 整张重建。重建出来的分类条上每个名字只能有一格，
  /// 四只自选一只不少，而且记账那一步要推两条删除把多余的两个分组对象从云端删掉。
  @Test func freshInstallLoginThenFirstPullKeepsOneCategoryPerName() throws {
    let sync = try store()
    // prepare(user)：账号目录是空的，合并出来就是访客那份。
    var merged = SymbolPrefs()
    merged.absorb(guest: guest)
    let imported = PersonalSyncCodec.guestImport(merged: PersonalSyncCodec.symbols(merged),
                                                 guest: PersonalSyncCodec.symbols(guest),
                                                 accountBefore: [], adopted: [])
    try sync.capture(imported, device: device, importing: UUID(), owning: PersonalSyncCodec.ownedKeys)
    // 第一次全量：云端那份到了。
    let cloud = PersonalSyncCodec.symbols(account).map { value -> SyncObject in var v = value; v.revision = 1; return v }
    try sync.receive(SyncPage(objects: cloud, next: nil, cursor: 1, serverTime: 0))

    let rebuilt = SyncOverlay.symbols(rebuiltFrom: live(sync), keeping: SymbolPrefs())
    #expect(names(rebuilt) == ["加密", "美股"], "分类条：\(names(rebuilt))")
    #expect(Set(rebuilt.favorites) == [btc, aapl, sol, tsla])
    #expect(members(rebuilt, "加密") == [btc, sol])
    #expect(members(rebuilt, "美股") == [aapl, tsla])

    // 留下的是同名里 id 最小的那个（`K-…` < `B-…` 不成立：`B` 在前，所以留访客那两个）。
    #expect(rebuilt.groups.map(\.id) == ["B-crypto", "B-stock"])
    #expect(SyncOverlay.mergedGroups(in: live(sync)) == ["K-crypto": "B-crypto", "K-stock": "B-stock"])

    // 记账（`captureSymbols` 那一条路）：多余的两个分组推删除，挂在它们上面的自选改挂过去。
    let batch = SyncCaptureBatch(objects: PersonalSyncCodec.symbols(rebuilt), owns: { collections.contains($0.collection) })
    let before = Set(sync.archive.operations.map(\.id))
    try sync.capture(batch.withDeletions(against: sync.archive.local.values), device: device, owning: PersonalSyncCodec.ownedKeys)
    let fresh = sync.archive.operations.filter { !before.contains($0.id) }
    #expect(Set(fresh.filter { $0.action == "delete" }.map(\.key)) == ["groups:K-crypto", "groups:K-stock"])
    let moved = fresh.filter { $0.collection == "favorites" && $0.fields["groupId"] != nil }
    #expect(Dictionary(uniqueKeysWithValues: moved.map { ($0.objectId, $0.fields["groupId"]) })
            == [btc: .string("B-crypto"), aapl: .string("B-stock")])
    // 推完之后本机的 `local` 再重建，仍然是那两格——删除不会把刚并好的东西再弄丢。
    let settled = SyncOverlay.symbols(rebuiltFrom: live(sync), keeping: SymbolPrefs())
    #expect(settled.groups == rebuilt.groups)
    #expect(settled.groupForSymbol == rebuilt.groupForSymbol)
    #expect(SyncOverlay.mergedGroups(in: live(sync)).isEmpty)
  }

  // ---------------------------------------------------------------- 多设备收敛

  /// 留哪一个不能看「这台设备上谁排在前面」：`order` 是每台设备按自己的顺序重新编的，
  /// 两台看到的不一样就会各删对方的那个，最后两个都没了。只认 id（不可变）：
  /// 同一组同名对象，不管以什么顺序、带什么 `order` 到达，每台设备都留同一个。
  @Test func everyDeviceKeepsTheSameIDWhateverTheOrder() {
    func object(_ id: String, _ name: String, order: Double) -> SyncObject {
      var v = SyncObject(collection: "groups", id: id); v.body = ["name": .string(name), "order": .number(order)]; return v
    }
    let phone = [object("K-crypto", "加密", order: 0), object("K-stock", "美股", order: 1),
                 object("B-crypto", "加密", order: 2), object("B-stock", "美股", order: 3)]
    let tablet = [object("B-stock", "美股", order: 0), object("B-crypto", "加密", order: 1),
                  object("K-stock", "美股", order: 5), object("K-crypto", "加密", order: 4)]
    let a = SyncOverlay.symbols(rebuiltFrom: phone, keeping: SymbolPrefs())
    let b = SyncOverlay.symbols(rebuiltFrom: tablet.reversed(), keeping: SymbolPrefs())
    #expect(Set(a.groups.map(\.id)) == ["B-crypto", "B-stock"])
    #expect(Set(b.groups.map(\.id)) == Set(a.groups.map(\.id)))
    #expect(SyncOverlay.mergedGroups(in: phone) == SyncOverlay.mergedGroups(in: tablet))
    // 位置：并出来的那一格站在同名里排得最靠前的那个位置上。
    #expect(names(a) == ["加密", "美股"])
    #expect(names(b) == ["美股", "加密"])
  }

  // ---------------------------------------------------------------- 不只预设分类

  /// 用户自己当年建的非预设分类照同一条规则：名字一样（首尾空白不算）就是同一类。
  @Test func userMadeSameNamedCategoriesMergeToo() {
    let prefs = SymbolPrefs(favorites: [btc, sol, aapl],
                            groups: [FavoriteGroup(id: "g2", name: "短线"), FavoriteGroup(id: "g9", name: "长线"),
                                     FavoriteGroup(id: "g1", name: " 短线 ")],
                            groupForSymbol: [btc: "g2", sol: "g1", aapl: "g9"])
    #expect(prefs.groups.map(\.id) == ["g1", "g9"])
    #expect(prefs.groupForSymbol == [btc: "g1", sol: "g1", aapl: "g9"])
    // 不同名的不碰。
    let distinct = SymbolPrefs(groups: [FavoriteGroup(id: "a", name: "加密"), FavoriteGroup(id: "b", name: "美股")])
    #expect(distinct.groups.map(\.id) == ["a", "b"])
  }

  // ---------------------------------------------------------------- 手机上已经重复的那份

  /// 用户手机上的 `symbols.json` 已经是四格了：读进来就并好，成员与「停在哪一类」一并改挂。
  @Test func duplicatesAlreadyOnDiskAreHealedOnRead() throws {
    let raw = Data(#"""
    {"favorites":["binance/usd_m/BTCUSDT","binance/usd_m/SOLUSDT","binance/usd_m/AAPLUSDT","binance/usd_m/TSLAUSDT"],
     "groups":[{"id":"K-crypto","name":"加密"},{"id":"K-stock","name":"美股"},{"id":"B-crypto","name":"加密"},{"id":"B-stock","name":"美股"}],
     "groupForSymbol":{"binance/usd_m/BTCUSDT":"K-crypto","binance/usd_m/SOLUSDT":"B-crypto",
                       "binance/usd_m/AAPLUSDT":"K-stock","binance/usd_m/TSLAUSDT":"B-stock"},
     "selectedGroupID":"K-stock"}
    """#.utf8)
    let prefs = try JSONDecoder().decode(SymbolPrefs.self, from: raw)
    #expect(prefs.groups.map(\.id) == ["B-crypto", "B-stock"])
    #expect(names(prefs) == ["加密", "美股"])
    #expect(members(prefs, "加密") == [btc, sol])
    #expect(members(prefs, "美股") == [aapl, tsla])
    #expect(prefs.legacySelectedGroup == "B-stock")
  }

  /// 启动前向对账（逐条补）补回来一个同名分组时也不许出第二格。
  @Test func patchingInASameNamedGroupMergesIt() {
    var prefs = account
    var stray = SyncObject(collection: "groups", id: "B-crypto")
    stray.body = ["name": .string("加密"), "order": .number(2)]
    var member = PersonalSyncCodec.symbols(SymbolPrefs(favorites: [sol], groups: [FavoriteGroup(id: "B-crypto", name: "加密")],
                                                       groupForSymbol: [sol: "B-crypto"]))
      .first { $0.collection == "favorites" }!
    member.body["order"] = .number(2)
    SyncOverlay.symbols([stray, member], patching: &prefs)
    #expect(names(prefs) == ["加密", "美股"])
    #expect(members(prefs, "加密") == [btc, sol])
  }
}
