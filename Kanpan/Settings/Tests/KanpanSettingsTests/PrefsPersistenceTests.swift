import Testing
import Foundation
import KanpanCore
import KanpanData
@testable import KanpanSettings

/// A6.12：所有设置项持久化，键 `kanpan.prefs.v2`。
@Suite("持久化")
struct PrefsPersistenceTests {

  /// 一次用户改动落盘之后，柜子里该有的那三格。
  ///
  /// 偏好本身是那一份要随人走的值；另两格是这一轮补的「本地这一侧的标识」：
  /// 脏字段集（还没推上去的是哪几项）和哨兵（本地这份为什么读不到）。
  /// **三格同一步写完**——落本地和记标识不许分成两次，中间被杀就会丢标识。
  static let oneSave = ["kanpan.prefs.v2", "kanpan.settings.sentinel.v1", "kanpan.settings.stamp.v1"]

  /// 把每一项都改成「不是默认」的样子，用来验往返。
  static func mutated() -> Prefs {
    var p = Prefs.defaults
    p.interval = .m15
    // 六档＝上限（`Prefs.maxQuick`）。多喂一档的话读回来会被截掉，往返自然不相等——
    // 那是截断规则在起作用，不是持久化丢了东西。
    p.quickIntervals = [.m3, .m30, .h2, .h12, .w1, .mo1]
    p.theme = .dark
    p.redUp = false
    p.priceMode = .log
    p.magnet = false
    p.countdown = false
    p.keepAwake = false
    p.launchSnapshot = false
    p.timeZone = .exchange
    p.overlays = [.boll, .ema]
    // 这里从前摆的是 `.atr`，2026-09-22 它退役了（面板上没有，读存档时会被滤掉），
    // 拿它当「改过的样子」就永远读不回来。换成同样在副图的动向指标。
    p.subs = [.dmi, .vol, .kdj]
    p.params = [.ma: [10, 30, 120], .macd: [8, 21, 5], .dmi: [7]]
    p.subHeights = [.dmi: .large, .vol: .small]
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
  /// 但**内存里那一份必须当场就变**——用户捏完可能下一帧就换周期换品种。
  ///
  /// 那 400ms 现在只是「手势进行中的降采样」，**不是保存时机**。保存时机只有一个：
  /// 手指离开屏幕（`interactionEnded`）。用户的原话是「用户手离开的瞬间就应该做同步
  /// 做持久保存啊」。
  @Test("捏的过程中不写盘，手一松立刻落盘")
  @MainActor
  func 手一松就落盘() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    for w in stride(from: 4.0, to: 12.0, by: 0.25) { viewport.userIsZooming(to: w) }
    #expect(box.keys.isEmpty)                  // 手指还在捏，一个字节都没写
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    viewport.interactionEnded()                // 手抬起来
    #expect(box.keys == Self.oneSave)
    #expect(store.prefs.barSpacing == 11.75)
    #expect(PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs.barSpacing == 11.75)
  }

  /// 用户要的那条：「缩放了，立马切换新周期缩放也要同步」。切周期 / 切品种时
  /// 图问的是 `ChartViewport.barSpacing`，它不等任何定时器。
  @Test("捏完立刻换周期换品种：内存里那份根宽当场就是新的，不用等落盘")
  @MainActor
  func 根宽立刻跟人走() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    #expect(viewport.barSpacing == AICoinBehavior.initialSpacing)   // 冷启动从存档起步
    viewport.userIsZooming(to: 9.5)
    #expect(viewport.barSpacing == 9.5)        // 手还没抬，换品种读到的已经是 9.5
    #expect(box.keys.isEmpty)                  // 盘上还没写
    #expect(store.prefs.barSpacing == AICoinBehavior.initialSpacing)
    viewport.userIsZooming(to: 20)             // 再捏一下，还是当场生效
    #expect(viewport.barSpacing == 20)
    viewport.userIsZooming(to: 9_999)          // 越界的也先夹再生效
    #expect(viewport.barSpacing == AICoinBehavior.maximumSpacing)
  }

  /// **换属主才作废，同属主晚到要保留。**
  ///
  /// 冷启动 → 图先按出厂宽度开张 → 用户马上捏一下 → 300ms 后 `account.restore()`
  /// 才把这个人自己的档案读回来。这一下到货**不能**把他刚捏的那份扔掉：那是同一个人
  /// 自己的档案晚到了，不是换了个人。
  @Test("同一个人的档案晚到：手上没落盘的那一捏要保住")
  @MainActor
  func 档案晚到保住这一捏() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    viewport.userIsZooming(to: 2.0)            // 用户捏小了，还没抬手
    viewport.adopt(barSpacing: 7.0, reason: .sameProfile)
    #expect(viewport.barSpacing == 2.0)        // 用户刚做的那一下赢
    #expect(store.prefs.barSpacing == 2.0)     // 而且当场落了盘，不再欠着
  }

  @Test("真的换了个人：手上没落盘的那一捏必须作废，不许写到新属主头上")
  @MainActor
  func 换属主那一捏作废() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    viewport.userIsZooming(to: 2.0)
    viewport.adopt(barSpacing: 7.0, reason: .ownerSwitched)
    #expect(viewport.barSpacing == 7.0)
    #expect(box.keys.isEmpty)                  // 上一个人欠的那次没落到新档案上
    viewport.interactionEnded()                // 再抬一次手也不该把它翻出来
    #expect(box.keys.isEmpty)
  }

  /// 「换档案」这件事本身也要把图叫起来重画一次，否则图会一直停在出厂宽度上，
  /// 然后把那个宽度当成用户意图报回来、反过来盖掉档案里对的那份（杀法甲）。
  @Test("每到一次货，adoptToken 都要跳一格")
  @MainActor
  func 到货要叫图重量() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    let viewport = ChartViewport(owner: store)
    let before = viewport.adoptToken
    viewport.adopt(barSpacing: 2.0, reason: .sameProfile)
    #expect(viewport.adoptToken == before + 1)
    viewport.adopt(barSpacing: 2.0, reason: .ownerSwitched)
    #expect(viewport.adoptToken == before + 2)
  }

  /// 本机那份和云端那份谁说了算。规则写在 `ChartLayoutReconcile` 里。
  @Test("本机与云端对账：没基线只播种、不一样以本机为准、一样就什么都不做")
  func 本地云端对账() {
    var mine = Prefs.defaults; mine.barSpacing = 2.0
    var theirs = Prefs.defaults; theirs.barSpacing = 7.0
    #expect(ChartLayoutReconcile.decide(onDisk: mine, baseline: nil) == .seed)
    #expect(ChartLayoutReconcile.decide(onDisk: mine, baseline: theirs) == .recapture)
    #expect(ChartLayoutReconcile.decide(onDisk: mine, baseline: mine) == .agree)
  }

  @Test("翻转不节流：一次双击就落一次盘，重复报不重复写")
  @MainActor
  func 翻转立刻落盘() {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.noteInversion(main: true, subs: [.macd])
    #expect(store.prefs.mainInverted)
    #expect(store.prefs.subInverted == [.macd])
    #expect(box.keys == Self.oneSave)
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
    #expect(box.keys == Self.oneSave)
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
    #expect(box.keys == Self.oneSave)
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

/// 退役指标（`IndicatorID.retired`）在存档里还在，但读回来不该再挂到图上。
@Suite("退役的指标读回来就不挂了")
struct RetiredIndicatorTests {

  @Test("老存档里的随机强弱与真实波幅不再进副图")
  func retiredSubsAreDropped() {
    var p = Prefs.defaults
    p.subs = [.vol, .kdj]
    var obj = try! JSONSerialization.jsonObject(with: PrefsCodec.encode(p)) as! [String: Any]
    // 直接改存档里的那串，模拟一台 2026-09-22 之前就选好了这两把的设备。
    obj["subs"] = ["SRSI", "VOL", "ATR"]
    let back = PrefsCodec.decode(try! JSONSerialization.data(withJSONObject: obj))
    #expect(back.subs == [.vol], "退役的两把还挂着：\(back.subs.map(\.rawValue))")
    // 枚举里 case 没删，所以它们的 rawValue 照样解得出来——这是「不删只退役」的前提。
    #expect(IndicatorID(rawValue: "SRSI") == .srsi)
    #expect(IndicatorID(rawValue: "ATR") == .atr)
  }

  @Test("退役的不在面板清单上")
  func retiredAreOffThePanel() {
    #expect(!IndicatorID.palette.contains(.srsi))
    #expect(!IndicatorID.palette.contains(.atr))
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
