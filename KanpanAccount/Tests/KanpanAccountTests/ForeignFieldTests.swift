import Foundation
import Testing
@testable import KanpanAccount

// MARK: - 认不出来的字段不许当成「被删了」

/// 2026-09-19 在模拟器上抓到的那个死循环：云端那条画线上带着一个 `created`
/// （`Drawing` 里根本没有这个属性，服务端却留着它的值规则——和 `styleID` 一样是
/// 只活在线上的老键），而 `SyncStore.stage` 把「先前有、这次没有」的键一律翻译成
/// 「删掉这个字段」。于是用户随便改一下那条线的样式，发上去的 fields 里就多一个
/// `created: null`，服务端的 null 白名单不收它，**整条操作** 400 被隔离；
/// `retryRejected` 拿同样两份重新差分，差出一模一样的 null 再被拒一次。
/// 那个账号从此每轮全量同步换一次跨洋 400，这个对象后面的每一次编辑一起卡死。
///
/// 底下四条钉的是修法本身：**一个客户端只替它认识的字段说话**。认不出来的字段
/// 既不改也不删，原样留在对象上；用户清掉一个自己的字段，照旧发 null。
@MainActor @Suite("外来字段不当成删除") struct ForeignFieldTests {
  private func temp() throws -> URL {
    let p = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: p, withIntermediateDirectories: true); return p
  }

  /// 这一版客户端替 `drawings` 说的话：真实的那张表由 app 侧
  /// `PersonalSyncCodec.ownedKeys` 从编码器派生，`KanpanAccount` 自己不认识业务字段。
  private let owned = ["drawings": Set(["symbol", "market", "venue", "anchors", "kind",
                                        "color", "lineWidth", "dash", "filled", "locked",
                                        "hidden", "levels", "text"])]

  /// 云端那份被拉进 `local` 之后，客户端下一次记账**不许**替 `created` 说话。
  ///
  /// 两句都要成立，缺一不可：操作里没有那个 null（不然照样 400），
  /// 而且 `local` 那份**还留着这个键**——带回这一步要是省了，下一次差分
  /// 会差出同一个 null，兜一圈回到原地。
  @Test("云端带着的陌生字段既不发 null，也不从记账里掉出去")
  func aForeignKeyIsNeitherDeletedNorLost() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    var cloud = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/a")
    cloud.body = ["symbol": .string("BTCUSDT"), "color": .string("#ff0000"),
                  "created": .number(1_726_000_000_000)]
    cloud.revision = 4
    server.seed(cloud)
    try store.receive(server.page(["drawings"]))

    // 用户改了一下颜色。客户端发得出去的 body 里从来没有 `created`。
    var edited = cloud
    edited.body.removeValue(forKey: "created")
    edited.body["color"] = .string("#00ff00")
    try store.capture(edited, device: device, owning: owned)

    let fields = try #require(store.archive.operations.last?.fields)
    #expect(fields["created"] == nil, "认不出来的 `created` 被当成「删掉这个字段」发上去了：\(fields)")
    #expect(fields["color"] == .string("#00ff00"))
    #expect(store.archive.local[cloud.key]?.body["created"] == .number(1_726_000_000_000),
            "外来键没带回记账里，下一次差分还会再差出一个 null")
  }

  /// 反面：用户清掉的是**自己的**字段，那就是真的删除，照旧发 null。
  /// 这条要是绿不了，修完的代价就是「画线的颜色恢复默认再也同步不上去」。
  @Test("清掉自己的字段照旧是一个 null")
  func clearingAnOwnedFieldStillTombstones() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    var cloud = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/a")
    cloud.body = ["symbol": .string("BTCUSDT"), "color": .string("#ff0000"),
                  "created": .number(1_726_000_000_000)]
    cloud.revision = 4
    server.seed(cloud)
    try store.receive(server.page(["drawings"]))

    var edited = cloud
    edited.body.removeValue(forKey: "created")
    edited.body.removeValue(forKey: "color")   // 用户把颜色恢复成默认
    try store.capture(edited, device: device, owning: owned)

    let fields = try #require(store.archive.operations.last?.fields)
    #expect(fields["color"] == JSONValue.null, "自己的字段被清掉时必须发字段墓碑：\(fields)")
    #expect(fields["created"] == nil)
  }

  /// `retryRejected` 是差分的另一个入口，而且是最容易踩到外来字段的那个：
  /// 它明摆着把**云端那份**放回 `local` 再重新差分。补推的那条操作里同样不许有外来 null，
  /// 否则「被拒 → 重试 → 再被拒」这个循环还在。
  @Test("补推被拒操作时重新差出来的那条也不带外来 null")
  func retryRebuildsTheOperationWithoutTheForeignNull() throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    var cloud = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/a")
    cloud.body = ["symbol": .string("BTCUSDT"), "color": .string("#ff0000"),
                  "created": .number(1_726_000_000_000)]
    cloud.revision = 4
    server.seed(cloud)
    try store.receive(server.page(["drawings"]))

    // 先制造一条被隔离的操作：这一版还没带表，发出去的就是当年那条带 null 的。
    var edited = cloud
    edited.body.removeValue(forKey: "created")
    edited.body["color"] = .string("#00ff00")
    try store.capture(edited, device: device)
    let doomed = try #require(store.archive.operations.last)
    #expect(doomed.fields["created"] == JSONValue.null, "这一步就是在复现那条会被 400 的操作")
    try store.quarantine(doomed.id, reason: "invalid_operation")
    #expect(store.archive.operations.isEmpty)

    // 服务端那边没变，本机的值也没变——补推走的是现做的差分，这次带上表。
    try store.retryRejected(device: device, owning: owned)

    let rebuilt = try #require(store.archive.operations.last)
    #expect(rebuilt.fields["created"] == nil, "补推的那条又差出了同一个外来 null：\(rebuilt.fields)")
    #expect(rebuilt.fields["color"] == .string("#00ff00"))
    #expect(store.archive.local[cloud.key]?.body["created"] == .number(1_726_000_000_000))
  }

  /// 用户看到的那个现象真的没了：一整轮全量同步跑完，队列空、隔离区空，
  /// 改的颜色落到了云端，而云端那个谁也不认识的 `created` 一个字没动。
  ///
  /// 假服务端这儿按 `Backend/kanpan-api/src/sync_validation.rs` 的 null 白名单顶回来：
  /// 只有 `color` / `groupId` / `text` 和 settings、drawingPreferences 的嵌套路径收 null。
  /// 服务端**没改**，也不该改——放开白名单等于放任老客户端把它只是不认识的字段抹掉。
  @Test("整轮全量同步跑完，没有一条被隔离，云端的老字段还在")
  func aFullRoundTripLeavesNothingQuarantined() async throws {
    let root = try temp(); defer { try? FileManager.default.removeItem(at: root) }
    let store = try SyncStore(directory: root), server = FakeSyncServer(), device = UUID()
    server.refuse = { op in
      for (path, value) in op.fields where value == .null {
        let parts = path.split(separator: "/")
        let top = parts.count == 1 && ["color", "groupId", "text"].contains(String(parts[0]))
        let nested = (op.collection == "settings" && parts.count >= 2)
          || (op.collection == "drawingPreferences" && parts.count == 2)
        if !top && !nested { return "invalid_operation" }
      }
      return nil
    }
    var cloud = SyncObject(collection: "drawings", id: "binance/usd_m/BTCUSDT/a")
    cloud.body = ["symbol": .string("BTCUSDT"), "color": .string("#ff0000"),
                  "created": .number(1_726_000_000_000)]
    cloud.revision = 4
    server.seed(cloud)
    try store.receive(server.page(["drawings"]))

    var edited = cloud
    edited.body.removeValue(forKey: "created")
    edited.body["color"] = .string("#00ff00")
    try store.capture(edited, device: device, owning: owned)

    try await engine(over: server, store, device: device, owning: owned).fullThenLeftovers("binance/usd_m/BTCUSDT/")

    #expect(store.archive.rejected.isEmpty, "还有操作卡在隔离区：\(store.archive.rejected.map(\.reason))")
    #expect(store.archive.operations.isEmpty)
    #expect(server.objects[cloud.key]?.body["color"] == .string("#00ff00"))
    #expect(server.objects[cloud.key]?.body["created"] == .number(1_726_000_000_000),
            "客户端把一个它只是不认识的字段抹掉了")
  }
}
