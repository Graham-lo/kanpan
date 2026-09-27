import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// 指标按周期分组记忆（2026-09-27）上线长什么样：老键是三组共用的那份（老客户端照旧读写），
/// 分了叉的组各一条 `indicatorLayouts/<minute|hour|day>`，值是整组布局；`null` = 那一组回到共用。
@Suite("指标按周期分组 · 同步")
struct IndicatorLayoutSyncTests {
  /// 小时组、日组各分了叉的一份（当前停在 1h）。
  private func forked() -> Prefs {
    var p = Prefs.defaults
    p.interval = .h1
    var book = p.layoutBook
    var hour = book.shared
    hour.subs = [.kdj]; hour.params[.ma] = [7, 25]; hour.candleKind = .heikin
    var day = book.shared
    day.overlays = [.boll]; day.priceMode = .log
    book.forks[.hour] = hour
    book.forks[.day] = day
    p.adopt(book)
    return p
  }

  @Test("发出去：老键是共用那份，分叉的组各一条 indicatorLayouts/<组>，七项全在；三条路径都在 ownedKeys 里")
  func wireShape() throws {
    let body = try PersonalSyncCodec.settings(forked()).body
    #expect(body["subs"] == .array(AICoinBehavior.subpanels.map { .string($0.rawValue) }), "老键写共用那份，不是当前组的")
    #expect(body["indicatorLayouts"] == nil, "整包不上线，只拍一层到组")
    guard case .object(let hour) = body["indicatorLayouts/hour"] else {
      Issue.record("indicatorLayouts/hour 不是对象：\(String(describing: body["indicatorLayouts/hour"]))"); return
    }
    #expect(Set(hour.keys) == ["overlays", "subs", "params", "hiddenOutputs", "subHeightOverrides", "candleKind", "priceMode"])
    #expect(hour["subs"] == .array([.string("KDJ")]))
    #expect(hour["candleKind"] == .string("heikin"))
    #expect(body["indicatorLayouts/day"] != nil)
    #expect(body["indicatorLayouts/minute"] == nil, "没分叉的组不发")
    #expect(!body.keys.contains { $0.hasPrefix("indicatorLayouts/") && $0.split(separator: "/").count > 2 })
    let owned = try #require(PersonalSyncCodec.ownedKeys["settings"])
    for group in ["minute", "hour", "day"] { #expect(owned.contains("indicatorLayouts/" + group), "\(group)") }
  }

  @Test("另一台收下来：三组原样，按它自己停的周期投影")
  func applyFromCloud() throws {
    let a = forked()
    var local = Prefs.defaults
    local.interval = .d1
    let b = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: local)
    #expect(b.layoutBook == a.layoutBook)
    #expect(b.interval == .h1, "interval 本来就随账号同步")
    // 停在别的周期上的那台：投影出来的是那一组的。
    var c = try PersonalSyncCodec.apply(try PersonalSyncCodec.settings(a), to: .defaults)
    let before = c
    c.interval = .w1
    c.settleIndicatorLayouts(after: before)
    #expect(c.overlays == [.boll] && c.priceMode == .log)
  }

  @Test("老客户端改了老键：共用那份跟着变，已分叉的组不受牵连")
  func oldClientEditsTheSharedLayout() throws {
    let mine = forked()
    var object = try PersonalSyncCodec.settings(mine)
    object.body["subs"] = .array([.string("RSI")])   // 老客户端只认老键
    let merged = try PersonalSyncCodec.apply(object, to: mine)
    #expect(merged.layoutBook.shared.subs == [.rsi])
    #expect(merged.layoutBook.forks[.hour]?.subs == [.kdj])
    #expect(merged.layoutBook.forks[.day]?.subs == AICoinBehavior.subpanels)
    #expect(merged.layoutBook.layout(for: .minute).subs == [.rsi], "没分叉的分钟组跟着共用那份走")
  }

  @Test("null 是「那一组回到共用」：云端的墓碑落地后本机那一组也并回去")
  func nullMergesTheGroupBack() throws {
    let mine = forked()
    var object = try PersonalSyncCodec.settings(mine)
    object.body["indicatorLayouts/hour"] = .null
    let merged = try PersonalSyncCodec.apply(object, to: mine)
    #expect(!merged.isLayoutForked(.hour))
    #expect(merged.isLayoutForked(.day))
    #expect(merged.subs == AICoinBehavior.subpanels, "停在 1h：并回之后看到的是共用那份")
  }

  @Test("复盘的图表快照带着分组一起存、一起读回")
  func snapshotKeepsGroups() throws {
    let a = forked()
    let back = try PersonalSyncCodec.snapshotPrefs(try PersonalSyncCodec.snapshot(a))
    #expect(back.layoutBook == a.layoutBook)
    #expect(back.indicatorLayout == a.indicatorLayout)
  }
}
