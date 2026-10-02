import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// 指标布局一人一份、不分周期（2026-10-03）上线长什么样：老键 overlays / subs / params /
/// subHeightOverrides / candleKind / priceMode 就是全部；老客户端（09-27~10-02）写的
/// `indicatorLayouts/<minute|hour|day>` 收下来按当前周期取那一份、收拢，推送时对它们发 null。
@Suite("指标布局跟人走 · 同步")
struct IndicatorLayoutSyncTests {
  private func edited() -> Prefs {
    var p = Prefs.defaults
    p.interval = .h1
    p.subs = [.kdj]; p.params[.ma] = [7, 25]; p.candleKind = .heikin; p.subHeightOverrides = [.kdj: 1.3]
    return p
  }

  @Test("发出去：老键就是这一份，不发 indicatorLayouts/<组>；三条组路径仍在 ownedKeys 里（好对残留发 null）")
  func wireShape() throws {
    let body = try PersonalSyncCodec.settings(edited()).body
    #expect(body["subs"] == .array([.string("KDJ")]))
    #expect(body["candleKind"] == .string("heikin"))
    #expect(body["params/MA"] == .array([.number(7), .number(25)]))
    #expect(!body.keys.contains { $0.hasPrefix("indicatorLayouts") })
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    for group in ["minute", "hour", "day"] { #expect(owned.contains("indicatorLayouts/" + group), "\(group)") }
  }

  @Test("另一台收下来：停在哪个周期都是这一份")
  func applyFromCloud() throws {
    let a = edited()
    for iv in [Interval.m5, .d1, .w1] {
      var local = Prefs.defaults
      local.interval = iv
      var b = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: local)
      let before = b
      b.interval = iv
      b.settleIndicatorLayouts(after: before)
      #expect(b.indicatorLayout == a.indicatorLayout, "\(iv)")
    }
  }

  @Test("老客户端留在云端的分叉：取当前周期那组，本机只剩一份；再发出去时那几条路径不在 body 里（由 ownedKeys 发 null）")
  func oldClientForksCollapse() throws {
    var object = try PersonalSyncCodec.settings(.defaults)
    object.body["indicatorLayouts/hour"] = .object(["subs": .array([.string("RSI")])])
    object.body["indicatorLayouts/day"] = .object(["overlays": .array([.string("BOLL")])])
    var local = Prefs.defaults
    local.interval = .h4
    let merged = try PersonalSyncCodec.apply(object, to: local)
    #expect(merged.subs == [.rsi])
    #expect(merged.overlays == Prefs.defaults.overlays, "日线组的分叉丢掉")
    #expect(merged.indicatorLayouts == IndicatorLayoutMemory())
    let out = try PersonalSyncCodec.settings(merged).body
    #expect(out["subs"] == .array([.string("RSI")]))
    #expect(!out.keys.contains { $0.hasPrefix("indicatorLayouts") })
  }

  @Test("复盘的图表快照带着指标布局一起存、一起读回")
  func snapshotKeepsLayout() throws {
    let a = edited()
    let back = try PersonalSyncCodec.snapshotPrefs(try PersonalSyncCodec.snapshot(a))
    #expect(back.indicatorLayout == a.indicatorLayout)
  }
}
