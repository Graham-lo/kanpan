import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import Kanpan

/// 指标按周期分组记忆（2026-09-27，方案 §4）：三组、继承直到分叉、跨组同一帧重算、老档迁移。
@Suite("指标按周期分组记忆")
@MainActor
struct IndicatorLayoutGroupsTests {

  private func makeStore(_ seed: Prefs? = nil) -> (PrefsStore, InMemoryPrefsStorage) {
    let archive = InMemoryPrefsStorage()
    if let seed { archive.setPrefsData(PrefsCodec.encode(seed), forKey: PrefsCodec.key) }
    return (PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage()), archive)
  }

  private func json(_ prefs: Prefs) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: PrefsCodec.encode(prefs)) as? [String: Any])
  }

  // MARK: - 分组

  @Test("十四档周期各归各组：分钟 1m…30m、小时 1h…12h、日 1d 起")
  func everyIntervalHasAGroup() {
    let minute: [Interval] = [.m1, .m3, .m5, .m15, .m30]
    let hour: [Interval] = [.h1, .h2, .h4, .h6, .h12]
    let day: [Interval] = [.d1, .w1, .mo1, .y1]
    #expect(Set(minute + hour + day) == Set(Interval.allCases))
    #expect(minute.allSatisfy { $0.layoutGroup == .minute })
    #expect(hour.allSatisfy { $0.layoutGroup == .hour })
    #expect(day.allSatisfy { $0.layoutGroup == .day })
  }

  // MARK: - 迁移

  @Test("老档案（没有 indicatorLayouts）读进来三组共用档里那一份，谁也没分叉")
  func oldArchiveBecomesTheSharedSource() throws {
    let old: [String: Any] = [
      "v": 3, "interval": "1d",
      "overlays": ["EMA"], "subs": ["VOL", "RSI"], "params": ["EMA": [9, 21]],
      "hiddenOutputs": ["RSI": [0]], "subHeightOverrides": ["RSI": 1.5],
      "candleKind": "heikin", "priceMode": "linear",
    ]
    let archive = InMemoryPrefsStorage()
    archive.setPrefsData(try JSONSerialization.data(withJSONObject: old), forKey: PrefsCodec.key)
    let store = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage())
    let book = store.prefs.layoutBook
    #expect(book.forks.isEmpty)
    #expect(book.shared.overlays == [.ema])
    #expect(book.shared.subs == [.vol, .rsi])
    #expect(book.shared.params[.ema] == [9, 21])
    #expect(book.shared.subHeightOverrides[.rsi] == 1.5)
    #expect(book.shared.candleKind == .heikin)
    #expect(book.shared.priceMode == .linear)
    // 三组都是它：换到哪一组都一样，也不会说任何话。
    for iv in [Interval.m5, .h4, .w1] {
      store.update { $0.interval = iv }
      #expect(store.prefs.indicatorLayout == book.shared)
    }
    #expect(store.notice == nil)
    #expect(store.prefs.layoutBook.forks.isEmpty)
  }

  @Test("出厂与没分叉的人：存档里 indicatorLayouts 是空表，老键照旧是那一份")
  func untouchedArchiveLooksLikeBefore() throws {
    let object = try json(.defaults)
    #expect((object["indicatorLayouts"] as? [String: Any])?.isEmpty == true)
    #expect(object["subs"] as? [String] == AICoinBehavior.subpanels.map(\.rawValue))
  }

  // MARK: - 分叉

  @Test("在一组里改一项，那一组分叉并说一次；别的组仍共用；回来还在")
  func editingForksOnlyThatGroup() {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    let shared = store.prefs.indicatorLayout
    store.toggleIndicator(.kdj)   // 副图满三个：换下 VOL，同时小时组分叉
    #expect(store.prefs.subs.contains(.kdj))
    #expect(store.prefs.isLayoutForked(.hour))
    #expect(!store.prefs.isLayoutForked(.minute) && !store.prefs.isLayoutForked(.day))
    #expect(store.notice?.contains("小时周期的指标现在单独记") == true)
    #expect(store.notice?.contains("已换下") == true)
    store.clearNotice()

    // 跨组：同一次 update 里顶层就换成日组（共用）那份。
    store.update { $0.interval = .d1 }
    #expect(store.prefs.indicatorLayout == shared)
    #expect(!store.prefs.subs.contains(.kdj))
    // 回小时组：刚才那份还在。
    store.update { $0.interval = .h4 }
    #expect(store.prefs.subs.contains(.kdj))
    #expect(store.notice == nil)

    // 同一组再改：不再说。
    store.update { $0.candleKind = .line }
    #expect(store.notice == nil)
    #expect(store.prefs.layoutBook.forks[.hour]?.candleKind == .line)
    #expect(store.prefs.layoutBook.shared == shared)

    // 日组第一次改：日组分叉，说日组那句。
    store.update { $0.interval = .w1 }
    store.update { $0.priceMode = .linear }
    #expect(store.notice == "日线及以上的指标现在单独记")
    #expect(store.prefs.isLayoutForked(.day))
    #expect(store.prefs.layoutBook.forks[.day]?.subs == shared.subs)
    // 分钟组还是那份共用的。
    store.update { $0.interval = .m15 }
    #expect(store.prefs.indicatorLayout == shared)
    #expect(!store.prefs.isLayoutForked(.minute))
  }

  @Test("分钟组的那句话")
  func minuteNotice() {
    let (store, _) = makeStore()
    store.update { $0.interval = .m5 }
    store.update { $0.params[.ma] = [7, 25] }
    #expect(store.notice == "分钟周期的指标现在单独记")
  }

  @Test("同组内换周期什么都不变，只有 interval 记脏")
  func sameGroupSwitchChangesNothing() {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    store.toggleIndicator(.rsi)
    let layout = store.prefs.indicatorLayout
    let before = store.prefs
    var next = before
    next.interval = .h12
    next.settleIndicatorLayouts(after: before)
    #expect(Prefs.changedStampedFields(from: before, to: next) == ["interval"])
    store.update { $0.interval = .h12 }
    #expect(store.prefs.indicatorLayout == layout)
  }

  @Test("跨组换周期只记 interval 脏，布局在同一次赋值里换好")
  func crossGroupSwitchIsOneAssignment() {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    store.update { $0.subs = [.rsi] }   // 小时组分叉
    var seen: [Prefs] = []
    store.onChange = { seen.append($0) }
    let before = store.prefs
    store.update { $0.interval = .d1 }
    #expect(seen.count == 1)
    #expect(seen.first?.interval == .d1)
    #expect(seen.first?.subs == AICoinBehavior.subpanels)   // 落下来的那一份已经是日组的
    #expect(Prefs.changedStampedFields(from: before, to: store.prefs) == ["interval"])
  }

  @Test("没真改（改了又改回同一个值）不分叉")
  func noOpEditDoesNotFork() {
    let (store, _) = makeStore()
    store.update { $0.subs = $0.subs }
    store.update { $0.overlays.append(.ema); $0.overlays.removeLast() }
    #expect(store.prefs.layoutBook.forks.isEmpty)
    #expect(store.notice == nil)
  }

  @Test("皮肤、网格、指标配色、订单流开关这些不属于分组布局，改了不分叉")
  func nonLayoutEditsDoNotFork() {
    let (store, _) = makeStore()
    store.update { $0.skin = .terra; $0.depth = true }
    store.update { $0.indicatorColors[.ma] = [0: Hex("#ff0000")] }
    store.toggleIndicator(.orderFlow)
    #expect(store.prefs.layoutBook.forks.isEmpty)
    #expect(store.notice == nil)
  }

  // MARK: - 落盘

  @Test("老键写共用那份，分叉那组写进 indicatorLayouts；读回来一模一样")
  func archiveRoundTrip() throws {
    let (store, archive) = makeStore()
    store.update { $0.interval = .h1 }
    store.update { $0.subs = [.kdj] }
    store.update { $0.interval = .d1 }
    store.update { $0.overlays = [.boll] }
    let object = try json(store.prefs)
    #expect(object["subs"] as? [String] == AICoinBehavior.subpanels.map(\.rawValue))
    let groups = try #require(object["indicatorLayouts"] as? [String: Any])
    #expect(Set(groups.keys) == ["hour", "day"])
    #expect((groups["hour"] as? [String: Any])?["subs"] as? [String] == ["KDJ"])
    #expect((groups["day"] as? [String: Any])?["overlays"] as? [String] == ["BOLL"])
    // 冷启动读回来：同一份。
    let restarted = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage())
    #expect(restarted.prefs == store.prefs)
    #expect(PrefsCodec.decode(PrefsCodec.encode(store.prefs)) == store.prefs)
  }

  @Test("半截的分叉档：缺的项跟共用那份走；null 的组当没分叉")
  func partialForkFallsBackToShared() throws {
    let raw: [String: Any] = [
      "v": 3, "interval": "1h", "subs": ["VOL"], "candleKind": "line",
      "indicatorLayouts": ["hour": ["subs": ["RSI"]], "day": NSNull()],
    ]
    let prefs = PrefsCodec.decode(try JSONSerialization.data(withJSONObject: raw))
    #expect(prefs.subs == [.rsi])
    #expect(prefs.candleKind == .line)
    #expect(prefs.isLayoutForked(.hour))
    #expect(!prefs.isLayoutForked(.day))
  }

  @Test("直接改顶层字段（没分叉的老写法）照旧写进老键，读回来相等")
  func legacyDirectWritesStillRoundTrip() {
    var p = Prefs.defaults
    p.subs = [.rsi, .kdj]
    p.priceMode = .percent
    p.params[.ema] = [5, 10]
    let back = PrefsCodec.decode(PrefsCodec.encode(p))
    #expect(back == p)
    #expect(back.layoutBook.forks.isEmpty)
  }

  // MARK: - 恢复这一组的默认

  @Test("恢复这一组的默认：只动当前组；已分叉的组回出厂，没分叉的组以出厂分叉出去")
  func resetCurrentGroup() {
    let (store, _) = makeStore()
    // 先让共用那份不是出厂：模拟老档案里带着自己的指标。
    store.useStorage(InMemoryPrefsStorage(), prefs: {
      var p = Prefs.defaults; p.subs = [.rsi]; p.overlays = [.ema]; return p
    }(), arrival: .sameProfile)
    let shared = store.prefs.indicatorLayout
    store.update { $0.interval = .h1 }
    store.update { $0.subs = [.kdj] }       // 小时组分叉
    store.clearNotice()
    store.resetIndicatorLayoutForCurrentGroup()
    #expect(store.prefs.indicatorLayout == .factory)
    #expect(store.notice == "已恢复这一组的默认")
    let undo = store.noticeUndo
    #expect(store.prefs.layoutBook.shared == shared)

    // 撤销：回到分叉时的那份。
    undo?()
    #expect(store.prefs.subs == [.kdj])

    // 日组没分叉：点它就以出厂分叉出去，别的组仍是原共用那份。
    store.update { $0.interval = .d1 }
    store.clearNotice()
    store.resetIndicatorLayoutForCurrentGroup()
    #expect(store.prefs.indicatorLayout == .factory)
    #expect(store.notice == "日线及以上的指标现在单独记")
    store.update { $0.interval = .m1 }
    #expect(store.prefs.indicatorLayout == shared)

    // 已经是出厂：什么都不做。
    store.update { $0.interval = .d1 }
    store.clearNotice()
    let before = store.prefs
    store.resetIndicatorLayoutForCurrentGroup()
    #expect(store.prefs == before)
    #expect(store.notice == nil)
  }

  @Test("恢复出厂把三组并回一份")
  func factoryResetMergesGroups() {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    store.update { $0.subs = [.kdj] }
    store.resetToDefaults()
    #expect(store.prefs.layoutBook.forks.isEmpty)
  }

  // MARK: - 云端落地与撤销

  @Test("云端落地：本地脏着 interval，云端的分组照收、按本地周期投影")
  func applySyncedProjectsWithLocalInterval() {
    let (store, _) = makeStore()
    store.update { $0.interval = .d1 }                  // interval 脏
    var remote = Prefs.defaults
    remote.interval = .h1
    remote.subs = [.rsi]
    remote.settleIndicatorLayouts(after: Prefs.defaults)   // 远端：小时组分叉成 RSI
    #expect(remote.isLayoutForked(.hour))
    store.applySynced(remote)
    #expect(store.prefs.interval == .d1)
    #expect(store.prefs.subs == AICoinBehavior.subpanels)
    store.update { $0.interval = .h2 }
    #expect(store.prefs.subs == [.rsi])
  }

  @Test("撤销分叉那一下：分组回到没分叉的样子")
  func undoTheForkingToggle() throws {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    store.toggleIndicator(.kdj)
    let undo = try #require(store.noticeUndo)
    undo()
    #expect(store.prefs.layoutBook.forks.isEmpty)
    #expect(store.prefs.subs == AICoinBehavior.subpanels)
  }

  @Test("SettingsWire：indicatorLayouts/<组> 映回 indicatorLayouts 这个字段")
  func wirePathMapsBack() {
    #expect(SettingsWire.fields(for: "indicatorLayouts/hour") == ["indicatorLayouts"])
  }
}
