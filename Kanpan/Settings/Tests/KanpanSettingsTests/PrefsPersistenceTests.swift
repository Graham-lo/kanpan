import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

/// A6.12：所有设置项持久化，键 `kanpan.prefs.v1`。
@Suite("持久化")
struct PrefsPersistenceTests {

  /// 把每一项都改成「不是默认」的样子，用来验往返。
  static func mutated() -> Prefs {
    var p = Prefs.defaults
    p.interval = .m15
    p.quickIntervals = [.m3, .m30, .h2, .h12, .w1, .mo1, .y1]
    p.theme = .dark
    p.styleID = "needle"
    p.redUp = true
    p.priceMode = .log
    p.magnet = false
    p.countdown = false
    p.keepAwake = false
    p.launchSnapshot = false
    p.timeZone = .exchange
    p.overlays = [.boll, .ema]
    p.subs = [.atr, .vol, .kdj]
    p.params = [.ma: [10, 30, 120], .macd: [8, 21, 5], .atr: [7]]
    p.subHeights = [.atr: .large, .vol: .small]
    p.apiHost = "fapi.example.com"
    return p
  }

  @Test("改完全部 → 杀 app → 重开逐项相等")
  func 往返() {
    let want = Self.mutated()
    #expect(want != Prefs.defaults)
    let back = PrefsCodec.decode(PrefsCodec.encode(want))
    #expect(back == want)
  }

  @Test("落在 UserDefaults 的键就是 kanpan.prefs.v1")
  @MainActor
  func 键名() {
    #expect(PrefsCodec.key == "kanpan.prefs.v1")
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0.redUp = true }
    #expect(box.keys == ["kanpan.prefs.v1"])
  }

  @Test("重开一个 store 读回同一份")
  @MainActor
  func 重开() {
    let box = InMemoryPrefsStorage()
    let a = PrefsStore(storage: box, cache: UnavailableMarketCache())
    a.update { $0 = Self.mutated() }
    let b = PrefsStore(storage: box, cache: UnavailableMarketCache())
    #expect(b.prefs == Self.mutated())
  }

  @Test("没真改动就不落盘")
  @MainActor
  func 空改不写() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0.magnet = true }            // 本来就是 true
    #expect(box.keys.isEmpty)
    store.update { $0.magnet = false }
    #expect(box.keys == ["kanpan.prefs.v1"])
  }

  @Test("恢复默认把键抹掉")
  @MainActor
  func 恢复默认() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0 = Self.mutated() }
    store.resetToDefaults()
    #expect(store.prefs == .defaults)
    #expect(box.keys.isEmpty)
  }

  @Test("JSON 里存的是 rawValue，人能读，不是交错数组")
  func 可读的JSON() throws {
    var p = Prefs.defaults
    p.params = [.ma: [7, 25, 99]]
    p.subHeights = [.macd: .large]
    let obj = try #require(
      try JSONSerialization.jsonObject(with: PrefsCodec.encode(p)) as? [String: Any])
    #expect(obj["v"] as? Int == 1)
    #expect(obj["interval"] as? String == "1h")
    #expect(obj["subs"] as? [String] == ["MACD", "RSI"])
    #expect((obj["params"] as? [String: [Int]])?["MA"] == [7, 25, 99])
    #expect((obj["subHeights"] as? [String: String])?["MACD"] == "large")
  }
}

/// A6.13：改默认值要升版本号；旧存档缺的项取**新默认**，不整体覆盖。
@Suite("版本与合并")
struct PrefsVersionTests {

  @Test("历史键从新到旧排，v1 时没有历史键")
  func 历史键() {
    #expect(PrefsCodec.legacyKeys(version: 1) == [])
    #expect(PrefsCodec.legacyKeys(version: 2) == ["kanpan.prefs.v1"])
    #expect(PrefsCodec.legacyKeys(version: 4)
            == ["kanpan.prefs.v3", "kanpan.prefs.v2", "kanpan.prefs.v1"])
    #expect(PrefsCodec.key(version: 3) == "kanpan.prefs.v3")
  }

  @Test("旧存档只带了两项：这两项照旧，其余取新默认")
  func 缺项取新默认() throws {
    // 假装这是 v1 存档，那会儿还没有「本根倒计时」「启动快照」「API 域名」这些字段。
    let old = #"{"v":1,"styleID":"bone","redUp":true}"#.data(using: .utf8)!
    let merged = PrefsCodec.decode(old)

    #expect(merged.styleID == "bone")                    // 存档里有的，留着
    #expect(merged.redUp)                                // 存档里有的，留着
    #expect(merged.countdown == Prefs.defaults.countdown) // 存档里没有的，取新默认
    #expect(merged.launchSnapshot == Prefs.defaults.launchSnapshot)
    #expect(merged.apiHost == Prefs.defaults.apiHost)
    #expect(merged.subs == Prefs.defaults.subs)
    #expect(merged.interval == Prefs.defaults.interval)
    #expect(merged.quickIntervals == Prefs.defaults.quickIntervals)
    // 只是「没覆盖到」，不是「整体作废」——除了那两项，其余与全新安装完全一致。
    var expected = Prefs.defaults
    expected.styleID = "bone"
    expected.redUp = true
    #expect(merged == expected)
  }

  @Test("升版本号后，当前键没有就回落到旧键读，读到的照样并进新默认")
  @MainActor
  func 跳版本号回落() {
    let box = InMemoryPrefsStorage(["kanpan.prefs.v1": #"{"v":1,"styleID":"dense"}"#.data(using: .utf8)!])
    // 模拟「默认值改了 → version 升到 2」：当前键 v2 还没写过。
    let loaded = PrefsStore.load(from: box,
                                 key: PrefsCodec.key(version: 2),
                                 legacyKeys: PrefsCodec.legacyKeys(version: 2))
    #expect(loaded.styleID == "dense")
    #expect(loaded.subs == Prefs.defaults.subs)
    #expect(loaded.priceMode == Prefs.defaults.priceMode)
  }

  @Test("未来版本的存档也照并，不当成坏档丢掉")
  func 未来版本() {
    let future = #"{"v":99,"magnet":false,"未来字段":"随便"}"#.data(using: .utf8)!
    let merged = PrefsCodec.decode(future)
    #expect(merged.magnet == false)
    #expect(merged.styleID == Prefs.defaults.styleID)
  }
}
