import Testing
import Foundation
import KanpanCore
import KanpanData
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
    p.redUp = false
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
    p.routePolicy = .gateway
    p.candleKind = .heikin
    p.gridChoice = .off
    p.bodyChoice = .hollowUp
    p.lastLine = false
    p.showDrawings = false
    p.sinceChange = true
    p.viewAnchor = .left
    p.priceBias = .up
    p.barSpacing = 9.5
    p.mainInverted = true
    p.subInverted = [.vol]
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

  /// 用户报的那件事：「缩小了 K 线让它显示更多的 K 线，回到自选点另一个品种，
  /// 并没有缩小到我需要的大小」。根宽是人的习惯，不是品种的属性，所以它得跟设置一起活着。
  @Test("根宽和上下翻转跨 app 重启都在")
  func 图表习惯往返() {
    let back = PrefsCodec.decode(PrefsCodec.encode(Self.mutated()))
    #expect(back.barSpacing == 9.5)
    #expect(back.mainInverted)
    #expect(back.subInverted == [.vol])
  }

  @Test("没存过根宽的老存档退回出厂 4pt，不是 0")
  func 老存档没有根宽() {
    var p = Prefs.defaults
    p.redUp = false
    // 把 barSpacing 那个键从 JSON 里抠掉，模拟这轮改动之前存下来的档案。
    var obj = try! JSONSerialization.jsonObject(with: PrefsCodec.encode(p)) as! [String: Any]
    obj.removeValue(forKey: "barSpacing")
    let data = try! JSONSerialization.data(withJSONObject: obj)
    #expect(PrefsCodec.decode(data).barSpacing == AICoinBehavior.initialSpacing)
  }

  @Test("离谱的根宽存不进去：读回来一定夹在上下限之间")
  func 根宽夹紧() {
    #expect(Prefs.clampSpacing(0) == AICoinBehavior.minimumSpacing)
    #expect(Prefs.clampSpacing(9_999) == AICoinBehavior.maximumSpacing)
    #expect(Prefs.clampSpacing(.nan) == AICoinBehavior.initialSpacing)
    var p = Prefs.defaults
    p.barSpacing = 1_000                       // 绕过 store，直接往档案里写一个越界值
    #expect(PrefsCodec.decode(PrefsCodec.encode(p)).barSpacing == AICoinBehavior.maximumSpacing)
  }

  /// 双指缩放时根宽每帧都在变，每帧写一次 `UserDefaults` 不行；
  /// 但**内存里那一份必须当场就变**——用户捏完可能下一秒就换周期换品种。
  /// 所以 `liveBarSpacing` 立刻跟上，落盘等手停下来。
  @Test("根宽写入是节流的：连报一串只在停下之后落一次盘")
  @MainActor
  func 根宽节流() async {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    for w in stride(from: 4.0, to: 12.0, by: 0.25) { store.noteBarSpacing(w) }
    #expect(box.keys.isEmpty)                  // 手指还在捏，一个字节都没写
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    store.flushBarSpacing()                    // 等价于「手抬起来 / 切后台」
    #expect(box.keys == ["kanpan.prefs.v2"])
    #expect(store.prefs.barSpacing == 11.75)
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs.barSpacing == 11.75)
  }

  /// 用户要的那条：「缩放了，立马切换新周期缩放也要同步」。切周期 / 切品种时
  /// 图问的是 `liveBarSpacing`，它不等定时器——节流只管盘，不管读。
  @Test("捏完立刻换周期换品种：内存里那份根宽当场就是新的，不用等落盘")
  @MainActor
  func 根宽立刻跟人走() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    #expect(store.liveBarSpacing == AICoinBehavior.initialSpacing)   // 冷启动从存档起步
    store.noteBarSpacing(9.5)
    #expect(store.liveBarSpacing == 9.5)       // 手还没抬，换品种读到的已经是 9.5
    #expect(box.keys.isEmpty)                  // 盘上还没写
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    store.noteBarSpacing(20)                   // 再捏一下，还是当场生效
    #expect(store.liveBarSpacing == 20)
    store.noteBarSpacing(9_999)                // 越界的也先夹再生效
    #expect(store.liveBarSpacing == AICoinBehavior.maximumSpacing)
  }

  @Test("恢复出厂 / 换账号：内存里那份根宽也认新档案，欠着的那次作废")
  @MainActor
  func 根宽跟着档案换() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.noteBarSpacing(9.5); store.flushBarSpacing()
    #expect(store.liveBarSpacing == 9.5)
    store.noteBarSpacing(12)                   // 这一次还欠着
    store.resetToDefaults()
    #expect(store.liveBarSpacing == AICoinBehavior.initialSpacing)
    store.flushBarSpacing()                    // 上一份档案欠的那次不能再落下来
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
  }

  @Test("翻转不节流：一次双击就落一次盘，重复报不重复写")
  @MainActor
  func 翻转立刻落盘() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.noteInversion(main: true, subs: [.macd])
    #expect(store.prefs.mainInverted)
    #expect(store.prefs.subInverted == [.macd])
    #expect(box.keys == ["kanpan.prefs.v2"])
    let snapshot = store.prefs
    store.noteInversion(main: true, subs: [.macd])
    #expect(store.prefs == snapshot)
  }

  @Test("落在 UserDefaults 的键就是 kanpan.prefs.v2")
  @MainActor
  func 键名() {
    #expect(PrefsCodec.key == "kanpan.prefs.v2")
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0.redUp = false }
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
