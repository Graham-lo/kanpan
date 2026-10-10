import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// 指标布局一人一份、不分周期（2026-10-03）上线长什么样：老键 overlays / subs / params /
/// subHeightOverrides / candleKind / priceMode 就是全部。老客户端（09-27~10-02）写的
/// `indicatorLayouts/<minute|hour|day>` 2026-10-10 三端退役：不发、不收、不认领（不发 null），
/// 云端残留由服务端 `strip_retired` 洗掉。删除前的代码在 tag `sync-fields-before-retire-2026-10-10`。
@Suite("指标布局跟人走 · 同步")
struct IndicatorLayoutSyncTests {
  private func edited() -> Prefs {
    var p = Prefs.defaults
    p.interval = .h1
    p.subs = [.kdj]; p.params[.ma] = [7, 25]; p.candleKind = .heikin; p.subHeightOverrides = [.kdj: 1.3]
    return p
  }

  @Test("发出去：老键就是这一份，不发 indicatorLayouts/<组>，ownedKeys 里也没有它们")
  func wireShape() throws {
    let body = try PersonalSyncCodec.settings(edited()).body
    #expect(body["subs"] == .array([.string("KDJ")]))
    #expect(body["candleKind"] == .string("heikin"))
    #expect(body["params/MA"] == .array([.number(7), .number(25)]))
    #expect(!body.keys.contains { $0.hasPrefix("indicatorLayouts") })
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    #expect(!owned.contains { $0.hasPrefix("indicatorLayouts") }, "退役的键不认领，不对它发 null")
  }

  @Test("另一台收下来：停在哪个周期都是这一份")
  func applyFromCloud() throws {
    let a = edited()
    for iv in [Interval.m5, .d1, .w1] {
      var local = Prefs.defaults
      local.interval = iv
      var b = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: local)
      b.interval = iv
      #expect(b.indicatorLayout == a.indicatorLayout, "\(iv)")
    }
  }

  @Test("老客户端留在云端的分叉：整条忽略，布局就是老键那一份；再发出去也不带它们")
  func oldClientForksAreIgnored() throws {
    var object = try PersonalSyncCodec.settings(edited())
    object.body["indicatorLayouts/hour"] = .object(["subs": .array([.string("RSI")])])
    object.body["indicatorLayouts/day"] = .object(["overlays": .array([.string("BOLL")])])
    var local = Prefs.defaults
    local.interval = .h4
    let merged = try PersonalSyncCodec.apply(object, to: local)
    #expect(merged.indicatorLayout == edited().indicatorLayout)
    let out = try PersonalSyncCodec.settings(merged).body
    #expect(out["subs"] == .array([.string("KDJ")]))
    #expect(!out.keys.contains { $0.hasPrefix("indicatorLayouts") })
  }

  @Test("复盘的图表快照带着指标布局一起存、一起读回")
  func snapshotKeepsLayout() throws {
    let a = edited()
    let back = try PersonalSyncCodec.snapshotPrefs(try PersonalSyncCodec.snapshot(a))
    #expect(back.indicatorLayout == a.indicatorLayout)
  }
}
