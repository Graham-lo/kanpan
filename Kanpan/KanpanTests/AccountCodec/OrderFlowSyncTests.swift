import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// 主力订单流改过的门槛整张表是**一个**同步键（不拍平成 `orderFlowOverrides/<base>`）：
/// 拍平之后的路径是动态的，`ownedKeys` 数不全，用户「恢复默认」拿掉一只时那一下就发不出去——
/// 云端那只永远删不掉，下一轮同步又被带回来。整张表一个键，删一只就是整张表换新值。
@Suite("主力订单流 · 同步")
struct OrderFlowSyncTests {
  @Test("整张表一个键，四个开关各一个键，全在 ownedKeys 里")
  func wireShape() throws {
    var prefs = Prefs.defaults
    prefs.setOrderFlowOverride(OrderFlowOverride(spot: 2_000_000, step: 50), for: "BTC")
    prefs.orderFlowShowFilled = false
    let body = try PersonalSyncCodec.settings(prefs).body
    guard case .object(let table) = body["orderFlowOverrides"], case .object(let btc) = table["BTC"] else {
      Issue.record("orderFlowOverrides 不是一个对象：\(String(describing: body["orderFlowOverrides"]))"); return
    }
    #expect(btc["spot"] == .number(2_000_000) && btc["step"] == .number(50) && btc["usdtPerp"] == nil)
    #expect(!body.keys.contains { $0.hasPrefix("orderFlowOverrides/") })
    #expect(body["orderFlowShowFilled"] == .bool(false) && body["orderFlowSpot"] == .bool(true))
    #expect(body["orderFlowFilledBid"] == nil && body["orderFlowCancelledAsk"] == nil, "六合四之前的旧键不再上线")
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    for key in ["orderFlowOverrides", "orderFlowSpot", "orderFlowContract", "orderFlowShowFilled",
                "orderFlowShowCancelled"] {
      #expect(owned.contains(key), "\(key)")
    }
  }

  @Test("另一台改的门槛与开关收下来原样生效；恢复默认（拿掉一只）也能同步过来")
  func applyFromCloud() throws {
    var a = Prefs.defaults
    a.setOrderFlowOverride(OrderFlowOverride(usdtPerp: 8_000_000), for: "ETH")
    a.setOrderFlowOverride(OrderFlowOverride(spot: 500_000), for: "SOL")
    a.orderFlowShowCancelled = false
    let b = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: .defaults)
    #expect(b.orderFlowOverrides == a.orderFlowOverrides && b.orderFlowDisplay == a.orderFlowDisplay)

    a.setOrderFlowOverride(nil, for: "SOL")
    let c = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: b)
    #expect(c.orderFlowOverrides == ["ETH": OrderFlowOverride(usdtPerp: 8_000_000)])
  }
}
