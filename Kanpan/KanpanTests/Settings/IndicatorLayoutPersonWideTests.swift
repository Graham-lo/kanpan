import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import Kanpan

/// 指标布局一人一份、不分周期（2026-10-03）：任何周期改了指标、参数、副图顺序与高度、画法，
/// 换到任何周期都是同一份。老档里 09-27~10-02 周期分组留下的 `indicatorLayouts` 2026-10-10 起读时忽略。
@Suite("指标布局跟人走")
@MainActor
struct IndicatorLayoutPersonWideTests {

  private func makeStore(_ seed: Prefs? = nil) -> (PrefsStore, InMemoryPrefsStorage) {
    let archive = InMemoryPrefsStorage()
    if let seed { archive.setPrefsData(PrefsCodec.encode(seed), forKey: PrefsCodec.key) }
    return (PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage()), archive)
  }

  private func json(_ prefs: Prefs) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: PrefsCodec.encode(prefs)) as? [String: Any])
  }

  @Test("1 小时换了指标、参数、副图顺序与高度、画法，切到 30 分、4 小时、日线、周线都是同一份")
  func layoutFollowsThePersonAcrossIntervals() {
    let (store, _) = makeStore()
    store.update { $0.interval = .h1 }
    store.update {
      $0.overlays = [.boll]
      $0.subs = [.kdj, .macd, .vol]
      $0.params[.macd] = [10, 20, 7]
      $0.subHeightOverrides = [.macd: 1.6, .vol: 0.6]
      $0.candleKind = .heikin
    }
    let want = store.prefs.indicatorLayout
    for iv in [Interval.m30, .h4, .d1, .w1, .m1, .h1] {
      store.update { $0.interval = iv }
      #expect(store.prefs.indicatorLayout == want, "\(iv)")
    }
    #expect(store.notice == nil, "不再有「……现在单独记」")
  }

  @Test("换周期只记 interval 脏，指标一项不动")
  func intervalSwitchOnlyDirtiesInterval() {
    let (store, _) = makeStore()
    store.update { $0.subs = [.rsi] }
    let before = store.prefs
    store.update { $0.interval = .d1 }
    #expect(Prefs.changedStampedFields(from: before, to: store.prefs) == ["interval"])
    #expect(store.prefs.subs == [.rsi])
  }

  @Test("开满时换下一个：照旧说「已换下」并能撤销")
  func toggleSwapStillNotifiesAndUndoes() throws {
    var seed = Prefs.defaults
    seed.subs = [.vol, .oi, .macd, .rsi]
    let (store, _) = makeStore(seed)
    store.toggleIndicator(.kdj)
    #expect(store.prefs.subs.contains(.kdj))
    #expect(store.notice?.contains("已换下") == true)
    let undo = try #require(store.noticeUndo)
    undo()
    #expect(store.prefs.subs == seed.subs)
  }

  @Test("存档：老键就是那一份，不再写 indicatorLayouts；读回来一模一样")
  func archiveRoundTrip() throws {
    let (store, archive) = makeStore()
    store.update { $0.interval = .h1; $0.subs = [.kdj] }
    store.update { $0.interval = .d1; $0.overlays = [.boll] }
    let object = try json(store.prefs)
    #expect(object["subs"] as? [String] == ["KDJ"])
    #expect(object["overlays"] as? [String] == ["BOLL"])
    #expect(object["indicatorLayouts"] == nil, "2026-10-10 退役，不再写")
    let restarted = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: InMemoryPrefsStorage())
    #expect(restarted.prefs == store.prefs)
  }

  @Test("老档带着周期分叉（indicatorLayouts）：整键忽略，布局就是老键那一份，其余字段照读")
  func oldForkedArchiveIgnoresForks() throws {
    let raw: [String: Any] = [
      "v": 3, "interval": "1h", "subs": ["VOL"], "candleKind": "line",
      "indicatorLayouts": ["hour": ["subs": ["RSI"], "subHeightOverrides": ["RSI": 1.4]], "day": ["overlays": ["EMA"]]],
    ]
    let prefs = PrefsCodec.decode(try JSONSerialization.data(withJSONObject: raw))
    #expect(prefs.subs == [.vol])
    #expect(prefs.subHeightOverrides[.rsi] == nil)
    #expect(prefs.candleKind == .line)
    #expect(prefs.interval == .h1)
    #expect(prefs.overlays == Prefs.defaults.overlays)
  }

  @Test("老档（没有 indicatorLayouts）照旧读老键那一份")
  func legacyArchiveReadsTopLevel() throws {
    let old: [String: Any] = ["v": 3, "interval": "1d", "overlays": ["EMA"], "subs": ["VOL", "RSI"], "priceMode": "linear"]
    let prefs = PrefsCodec.decode(try JSONSerialization.data(withJSONObject: old))
    #expect(prefs.overlays == [.ema])
    #expect(prefs.subs == [.vol, .rsi])
    #expect(prefs.priceMode == .linear)
  }

  @Test("云端落地（老客户端写的分叉）：分叉忽略，本机就是老键那一份，换周期不变")
  func applySyncedIgnoresForks() throws {
    let (store, _) = makeStore()
    store.update { $0.interval = .h4 }
    let raw: [String: Any] = ["v": 3, "interval": "4h", "subs": ["VOL", "MACD"], "indicatorLayouts": ["hour": ["subs": ["KDJ"]]]]
    store.applySynced(PrefsCodec.decode(try JSONSerialization.data(withJSONObject: raw)))
    #expect(store.prefs.subs == [.vol, .macd])
    store.update { $0.interval = .m5 }
    #expect(store.prefs.subs == [.vol, .macd])
  }

  @Test("恢复默认指标：整份回出厂、可撤销；已经是出厂时什么都不做")
  func resetToFactory() throws {
    let (store, _) = makeStore()
    store.update { $0.overlays = [.ema]; $0.subHeightOverrides[.macd] = 1.4 }
    let edited = store.prefs.indicatorLayout
    store.resetIndicatorLayout()
    #expect(store.prefs.indicatorLayout == .factory)
    #expect(store.notice == "已恢复默认指标")
    let undo = try #require(store.noticeUndo)
    undo()
    #expect(store.prefs.indicatorLayout == edited)
    store.resetIndicatorLayout()
    store.clearNotice()
    let before = store.prefs
    store.resetIndicatorLayout()
    #expect(store.prefs == before)
    #expect(store.notice == nil)
  }

  @Test("SettingsWire：拍平路径取第一段（params/MA → params）")
  func wirePathMapsBack() {
    #expect(SettingsWire.fields(for: "params/MA") == ["params"])
  }
}
