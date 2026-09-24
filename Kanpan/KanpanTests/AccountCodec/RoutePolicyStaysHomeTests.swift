import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

// MARK: - 行情线路那两档留在自己的设备上

/// **一台手机选了网关，不该把另一台手机也搬到网关上去。**
///
/// 2026-09-19 按 GPT Pro 第二轮审查 B7 改的：`routePolicy` 从 `.synced` 改成
/// `.deviceOnly`（`PrefsFieldPlan.table`）。改之前那条路是这样的——
/// A 在自己的网络里点了「网关」，这个字段被编码上传；B 本来是直连、这个字段还干净，
/// 于是 B 拉到云端那份之后存档里就成了网关，而 B 从头到尾没碰过线路那两档。
///
/// 产品规则没变：出厂默认直连、只有直连 / 网关两档、手动选、没有任何自动切换。
/// 变的只有一件事——**这个选择不再跨设备覆盖**。
///
/// 这一组是在 codec 这一层把那件事钉死：发的时候不带它、收的时候不认它、
/// 换档案的时候保住它。表层的归类由 `PrefsFieldPlanTests.routePolicyStaysOnThisDevice` 守。
@Suite("线路那两档留在这台设备上")
struct RoutePolicyStaysHomeTests {

  /// A 选网关、B 直连，各自同步一轮，谁也不改谁。
  @Test("两台设备各走各的线路，同步一轮之后还是各走各的")
  func twoProfilesKeepTheirOwnRoute() throws {
    // A：自己的网络里走网关，顺手改了皮肤（皮肤是真的跟着人走的，拿来当对照）。
    var a = Prefs.defaults
    a.routePolicy = .gateway
    a.skin = .terra
    // B：还是直连，这个字段干净。
    var b = Prefs.defaults
    b.routePolicy = .direct

    // A 推上去的那份里压根没有线路。
    let uploaded = try PersonalSyncCodec.settings(a)
    #expect(uploaded.body["routePolicy"] == nil, "新客户端不再把线路发上去")
    #expect(uploaded.body["skin"] == .string("terra"), "真的跟着人走的那些照旧发")

    // B 收下 A 那份：皮肤跟过来，线路纹丝不动。
    let bAfter = try PersonalSyncCodec.apply(uploaded, to: b)
    #expect(bAfter.routePolicy == .direct, "B 没碰过线路，同步一轮之后不该变成网关")
    #expect(bAfter.skin == .terra)

    // 反过来也一样：B 推上去的那份不会把 A 拽回直连。
    let aAfter = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(bAfter), to: a)
    #expect(aAfter.routePolicy == .gateway, "A 选的网关不被 B 那份盖掉")
  }

  /// 云端那份是**老客户端**传上去的，带着 `routePolicy`（服务端仍然认这个键，
  /// 见 `PrefsFieldPlan.wireOnlyKeys`）。新客户端读到它也不改自己的选择。
  @Test("云端那份带着老客户端发上来的 routePolicy，也改不动这台设备")
  func aLegacyCloudObjectDoesNotMoveThisDevice() throws {
    var legacy = try PersonalSyncCodec.settings(.defaults)
    legacy.body["routePolicy"] = .string("gateway")

    var mine = Prefs.defaults
    mine.routePolicy = .direct
    #expect(try PersonalSyncCodec.apply(legacy, to: mine).routePolicy == .direct,
            "这台手机在直连上，云端那份老键不该把它搬去网关")

    mine.routePolicy = .gateway
    legacy.body["routePolicy"] = .string("direct")
    #expect(try PersonalSyncCodec.apply(legacy, to: mine).routePolicy == .gateway,
            "反过来同样：这台手机在网关上，老键也拽不回直连")

    // 而且这个客户端**不替它说话**：差分时不会发一条 `routePolicy: null` 上去。
    // 服务端收不了这种 null，整条操作 400，那个账号的队列就堵死了——
    // `drawings.created` 那一出（提交 c8b7dbd）就是这么来的。
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    #expect(!owned.contains("routePolicy"), "不发它，也不提议删它，原样留在云端那个对象上")
  }

  /// 换档案（登录 / 退登 / 切账号 / 升级后第一次装进档案）：线路留在这台设备上。
  ///
  /// 这条同时是**迁移**那一条：升级之后第一次把档案装进来，走的就是
  /// `keepDeviceFields`，这台机器当前选的那一档必须原样留着，不重置成出厂直连。
  @Test("登录、退登、切账号都不动这台设备已经选好的线路")
  func switchingProfilesKeepsThisDevicesRoute() {
    var onThisPhone = Prefs.defaults
    onThisPhone.routePolicy = .gateway

    // 新档案：云端那份（或者访客档案）里线路是直连、皮肤是陶土。
    var incoming = Prefs.defaults
    incoming.routePolicy = .direct
    incoming.skin = .terra
    PersonalSyncCodec.keepDeviceFields(onThisPhone, in: &incoming)

    #expect(incoming.routePolicy == .gateway, "换档案不许把这台设备当前的选择重置掉")
    #expect(incoming.skin == .terra, "跟着人走的那些照旧由新档案说了算")
  }
}
