import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

/// A6.12：所有设置项持久化，键 `kanpan.prefs.v2`。
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
    p.candleKind = .heikin
    p.gridChoice = .off
    p.bodyChoice = .hollowUp
    p.lastLine = false
    p.showDrawings = false
    p.sinceChange = true
    p.viewAnchor = .left
    p.priceBias = .up
    return p
  }

  @Test("改完全部 → 杀 app → 重开逐项相等")
  func 往返() {
    let want = Self.mutated()
    #expect(want != Prefs.defaults)
    let back = PrefsCodec.decode(PrefsCodec.encode(want))
    #expect(back == want)
  }

  @Test("「图表」那几项逐个往返，不是靠整体相等蒙过去")
  func 图表往返() {
    let back = PrefsCodec.decode(PrefsCodec.encode(Self.mutated()))
    #expect(back.candleKind == .heikin)
    #expect(back.gridChoice == .off)
    #expect(back.bodyChoice == .hollowUp)
    #expect(back.lastLine == false)
    #expect(back.showDrawings == false)
    #expect(back.sinceChange)
    #expect(back.viewAnchor == .left)
    #expect(back.priceBias == .up)
  }

  @Test("落在 UserDefaults 的键就是 kanpan.prefs.v2")
  @MainActor
  func 键名() {
    #expect(PrefsCodec.key == "kanpan.prefs.v2")
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0.redUp = true }
    #expect(box.keys == ["kanpan.prefs.v2"])
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
    store.update { $0.magnet = false }            // Current default
    #expect(box.keys.isEmpty)
    store.update { $0.magnet = true }
    #expect(box.keys == ["kanpan.prefs.v2"])
  }

  @Test("恢复默认把键抹掉")
  @MainActor
  func 恢复默认() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0 = Self.mutated() }
    store.resetToDefaults()
    #expect(store.prefs == .defaults)
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs == .defaults)
  }

  @Test("JSON 里存的是 rawValue，人能读，不是交错数组")
  func 可读的JSON() throws {
    var p = Prefs.defaults
    p.params = [.ma: [7, 25, 99]]
    p.subHeights = [.macd: .large]
    let obj = try #require(
      try JSONSerialization.jsonObject(with: PrefsCodec.encode(p)) as? [String: Any])
    #expect(obj["v"] as? Int == 2)
    #expect(obj["interval"] as? String == "1h")
    #expect(obj["subs"] as? [String] == ["VOL", "OI", "MACD"])
    #expect((obj["params"] as? [String: [Int]])?["MA"] == [7, 25, 99])
    #expect((obj["subHeights"] as? [String: String])?["MACD"] == "large")
    // 「图表」那几项也是 rawValue，不是枚举的序号
    #expect(obj["candleKind"] as? String == "candle")
    #expect(obj["gridChoice"] as? String == "off")
    #expect(obj["viewAnchor"] as? String == "right")
    #expect(obj["priceBias"] as? String == "center")
    #expect(obj["lastLine"] as? Bool == true)
  }
}

/// A6.13：改默认值要升版本号；旧存档缺的项取**新默认**，不整体覆盖。
@Suite("版本与合并")
struct PrefsVersionTests {

  @Test("不读取旧原型存档")
  @MainActor
  func noLegacyPreferences() {
    let old = #"{"v":1,"styleID":"dense","priceMode":"linear"}"#.data(using: .utf8)!
    let box = InMemoryPrefsStorage(["kanpan.prefs.v1": old])
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs == .defaults)
    #expect(PrefsCodec.decode(old) == .defaults)
  }
}
