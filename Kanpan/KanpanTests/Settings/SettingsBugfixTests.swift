import Testing
import Foundation
import KanpanCore
@testable import Kanpan

/// 2026-09-26「设置项各种莫名其妙的 bug」那一轮的回归用例。每条对应一个根因，
/// 名字里写的是用户看得见的那个症状。
@Suite("设置项回归 · 2026-09-26")
struct SettingsBugfixTests {

  private func decode(_ json: String) -> Prefs { PrefsCodec.decode(json.data(using: .utf8)) }

  // MARK: 1 · 常用行的出厂迁移只对老档做一次

  @Test("v3 档里亲手钉成老出厂那串，读回来原样不动")
  func 新档不迁移() {
    let p = decode(#"{"v":3,"quickIntervals":["5m","30m","1h","4h","1d"]}"#)
    #expect(p.quickIntervals == [.m5, .m30, .h1, .h4, .d1])
  }

  @Test("v2 老档里躺着上一版出厂的五档 / 七档，换成新默认")
  func 老档迁移() {
    #expect(decode(#"{"v":2,"quickIntervals":["5m","30m","1h","4h","1d"]}"#).quickIntervals == Interval.quick)
    // 七档那一版：截到六档之前就得认出来，否则 prefix 之后谁也认不得了。
    #expect(decode(#"{"v":2,"quickIntervals":["1m","5m","15m","30m","1h","4h","1d"]}"#).quickIntervals == Interval.quick)
    // 老档里不是出厂那串的，一个字不动。
    #expect(decode(#"{"v":2,"quickIntervals":["5m","1h","1d"]}"#).quickIntervals == [.m5, .h1, .d1])
  }

  @Test("没写版本的（同步体、手写档）按当前版本读，不迁移")
  func 无版本不迁移() {
    #expect(decode(#"{"quickIntervals":["5m","30m","1h","4h","1d"]}"#).quickIntervals == [.m5, .m30, .h1, .h4, .d1])
    // 同步体里的红涨是某台设备上用户自己选的：不带版本号，不能被「一律绿涨」的第 4 版迁移改掉。
    #expect(decode(#"{"redUp":true}"#).redUp == true)
  }

  @Test("编出去写当前版本（4）；字段级往返（keeping）不再把用户的选择改回默认")
  func 往返不迁移() throws {
    var mine = Prefs.defaults
    mine.quickIntervals = [.m5, .m30, .h1, .h4, .d1]
    let data = try #require(PrefsCodec.encoded(mine))
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(obj["v"] as? Int == PrefsCodec.version)
    #expect(PrefsCodec.version == 4)
    #expect(PrefsCodec.decode(data).quickIntervals == mine.quickIntervals)
    let merged = Prefs.keeping(["quickIntervals"], of: mine, over: .defaults)
    #expect(merged.quickIntervals == mine.quickIntervals)
    // 版本升了，柜子的键没换：老用户的存档照样读得到。
    #expect(PrefsCodec.key == "kanpan.prefs.v2")
  }

  // MARK: 3 · 恢复默认留住本机线路

  @Test("恢复默认：线路（deviceOnly）留着，返回的改动集不含它，下游按换属主接")
  @MainActor
  func 恢复默认留线路() {
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    store.update { $0.routePolicy = .gateway; $0.redUp = true; $0.depth = true }
    var arrivals: [ChartLayoutArrival] = []
    store.onAdopt = { _, why in arrivals.append(why) }
    let changed = store.resetToDefaults()
    #expect(store.prefs.routePolicy == .gateway)
    #expect(store.prefs.redUp == Prefs.defaults.redUp)
    #expect(store.prefs.depth == Prefs.defaults.depth)
    #expect(!changed.contains("routePolicy"))
    #expect(changed.contains("redUp"))
    #expect(arrivals == [.ownerSwitched])
    // 已经是出厂的样子：什么都不做，也不惊动下游。
    #expect(store.resetToDefaults().isEmpty)
    #expect(arrivals == [.ownerSwitched])
  }

  // MARK: 5 · 撤销只还原那一下改到的字段

  @Test("换下副图的撤销：只还原副图，撤销窗口里别处的改动留着，不按换属主通知")
  @MainActor
  func 撤销只动自己的字段() throws {
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    store.update { $0.subs = [.vol, .macd, .kdj, .oi] }   // 成交量不占名额，这是开满
    let subsBefore = store.prefs.subs
    var arrivals: [ChartLayoutArrival] = []
    store.onAdopt = { _, why in arrivals.append(why) }
    store.toggleIndicator(.rsi)                       // 满三个 → 换下一个，带「撤销」
    #expect(store.prefs.subs != subsBefore)
    let undo = try #require(store.noticeUndo)
    store.update { $0.redUp.toggle() }                // 撤销窗口里改了别的
    let redUpAfter = store.prefs.redUp
    undo()
    #expect(store.prefs.subs == subsBefore)
    #expect(store.prefs.redUp == redUpAfter)
    #expect(store.notice == nil)
    #expect(!arrivals.contains(.ownerSwitched))
  }

  @Test("恢复默认的撤销：还原被改掉的那些字段；根宽在里面才按同一个人通知图")
  @MainActor
  func 恢复默认撤销() {
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    store.update { $0.redUp = false; $0.barSpacing = Prefs.clampSpacing(Prefs.defaults.barSpacing + 3) }
    let before = store.prefs
    let changed = store.resetToDefaults()
    var arrivals: [ChartLayoutArrival] = []
    store.onAdopt = { _, why in arrivals.append(why) }
    store.restore(changed, from: before)
    #expect(store.prefs == before)
    #expect(arrivals == [.sameProfile])
    // 空集 / 已经一致：不动。
    store.restore([], from: .defaults)
    store.restore(changed, from: before)
    #expect(store.prefs == before)
    #expect(arrivals == [.sameProfile])
  }

  // MARK: 6 · 7 · 指标编辑页的保存

  @Test("没改就保存：参数、隐藏项、配色都不留「等于默认」的副本")
  func 原样保存不写副本() {
    for id in IndicatorID.allCases {
      var p = Prefs.defaults
      IndicatorDraft(id: id, prefs: p).save(into: &p)
      #expect(p == .defaults, "\(id)")
    }
  }

  @Test("改回默认值也写回出厂的样子")
  func 改回默认() {
    var p = Prefs.defaults
    p.params[.rsi] = [9]
    p.indicatorColors[.ma] = [0: "#FF0000"]
    var d = IndicatorDraft(id: .rsi, prefs: p)
    d.params = IndicatorID.rsi.defaultParams
    d.save(into: &p)
    var m = IndicatorDraft(id: .ma, prefs: p)
    m.colors = [:]
    m.save(into: &p)
    #expect(p == .defaults)
  }

  @Test("RSI 上下限与指标「输出」开关收掉之后：老档里的这几个键读进来被忽略，不影响别的字段")
  func RSI与输出收掉() throws {
    let old = #"{"v":3,"rsiUpper":80,"rsiLower":20,"hiddenOutputs":{"MA":[0,2]},"params":{"RSI":[9]}}"#
    let p = PrefsCodec.decode(Data(old.utf8))
    #expect(p.params[.rsi]?.first == 9)
    let text = String(data: try #require(PrefsCodec.encoded(p)), encoding: .utf8) ?? ""
    for key in ["rsiUpper", "rsiLower", "hiddenOutputs"] { #expect(!text.contains(key), "\(key) 不该再写进档里") }
  }

  // MARK: 10 · 编码不写空档、不写非有限数

  @Test("非有限数编码前就夹回来，编得出、读回来都是有限值")
  func 非有限数() throws {
    var p = Prefs.defaults
    p.barSpacing = .nan
    p.portraitHeight = .infinity
    p.subHeightOverrides = [.macd: .nan, .vol: 5]
    let data = try #require(PrefsCodec.encoded(p))
    #expect(!data.isEmpty)
    let back = PrefsCodec.decode(data)
    #expect(back.barSpacing.isFinite && back.portraitHeight.isFinite)
    #expect(back.subHeightOverrides[.macd] == nil)
    #expect(back.subHeightOverrides[.vol] == 2)
    #expect(back.portraitHeight <= 1)
  }

  @Test("落盘永远不写空 Data：带非有限数的改动照样存得下、读得回")
  @MainActor
  func 不写空档() throws {
    let box = InMemoryPrefsStorage()
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    store.update { $0.redUp = false; $0.barSpacing = .nan }
    let data = try #require(box.prefsData(forKey: PrefsCodec.key))
    #expect(!data.isEmpty)
    let reread = PrefsStore(storage: box, cache: UnavailableMarketCache()).prefs
    #expect(reread.redUp == false)
    #expect(reread.barSpacing.isFinite)
  }

  // MARK: 11 · 解码校验

  @Test("竖屏图高夹到 0.1…1，和服务端校验同一个范围")
  func 竖屏图高() {
    #expect(decode(#"{"portraitHeight":0}"#).portraitHeight == 0.1)
    #expect(decode(#"{"portraitHeight":7}"#).portraitHeight == 1)
    #expect(decode(#"{"portraitHeight":0.62}"#).portraitHeight == 0.62)
    #expect(Prefs.clampPortraitHeight(.nan) == Prefs.defaults.portraitHeight)
  }

  @Test("上次用的画线工具：认不出的退回空，认得的留着")
  func 画线工具() {
    #expect(decode(#"{"lastDrawTool":"laser"}"#).lastDrawTool == "")
    #expect(decode(#"{"lastDrawTool":"gannFan"}"#).lastDrawTool == "gannFan")
    #expect(decode(#"{"lastDrawTool":""}"#).lastDrawTool == "")
  }

  @Test("画线工具次数：认不出的工具、负数、非整数一项一项丢，好的留着；编码写得回来")
  func 画线工具次数() throws {
    let p = decode(#"{"drawToolUsage":{"trend":5,"laser":3,"hline":-2,"note":1.5,"measure":"7","fibonacci":0,"position":2}}"#)
    #expect(p.drawToolUsage == ["trend": 5, "position": 2])
    #expect(decode(#"{"drawToolUsage":"trend"}"#).drawToolUsage == [:])
    #expect(decode(#"{"drawToolUsage":{"trend":500000}}"#).drawToolUsage == ["trend": 100_000])
    #expect(Prefs.defaults.drawToolUsage.isEmpty)
    var q = Prefs.defaults
    q.drawToolUsage = ["channel": 3, "bogus": 9]
    let back = decode(String(decoding: PrefsCodec.encode(q), as: UTF8.self))
    #expect(back.drawToolUsage == ["channel": 3])
  }

  @Test("收设置项 G：自选排序 / 迷你走势、板块排序的老键读进来即丢，旁边的键照常认")
  func 收设置项G老键() {
    let old = decode(#"{"favoritesSort":"volume","favoritesAscending":true,"favoritesAmount":true,"favoritesSparkline":true,"sectorSort":"volume","sectorWindow":"d5","favoritesGroup":"g1"}"#)
    #expect(old.sectorWindow == .d5)
    #expect(old.favoritesGroup == "g1")
    let obj = (try? JSONSerialization.jsonObject(with: PrefsCodec.encode(old))) as? [String: Any] ?? [:]
    for key in ["favoritesSort", "favoritesAscending", "favoritesAmount", "favoritesSparkline", "sectorSort"] {
      #expect(obj[key] == nil, "\(key) 不再写出去")
      #expect(!Prefs.syncedFieldNames.contains(key), "\(key) 不再随账号同步")
    }
  }

  // MARK: 2 · 图认偏好那一侧的翻转

  @Test("翻转：第一次挂上不认（图自己的为准）；快照没变不认；快照变了认")
  func 翻转认不认() {
    let a = ChartInversion(main: false, subs: [])
    let b = ChartInversion(main: true, subs: [.macd])
    #expect(!ChartInversion.adopt(a, last: nil))
    #expect(!ChartInversion.adopt(a, last: a))
    #expect(ChartInversion.adopt(b, last: a))
    #expect(ChartInversion.adopt(a, last: b))
    #expect(ChartInversion.adopt(ChartInversion(main: false, subs: [.macd]), last: a))
  }
}

// MARK: 12 · 涨跌色进首帧镜像

@Suite("设置项回归 · 涨跌色镜像", .serialized)
struct SettingsRedUpMirrorTests {
  static let box = UserDefaults(suiteName: "kanpan.tests.settings-redup-mirror")!

  @Test("改涨跌色就同步进首帧镜像")
  @MainActor
  func 涨跌色镜像() {
    LaunchMirror.$override.withValue(Self.box) {
      Self.box.removeObject(forKey: LaunchThemeMirror.redUpKey)
      let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
      store.update { $0.redUp = !Prefs.defaults.redUp }
      #expect(LaunchThemeMirror.redUp == !Prefs.defaults.redUp)
      store.update { $0.redUp = Prefs.defaults.redUp }
      #expect(LaunchThemeMirror.redUp == Prefs.defaults.redUp)
      Self.box.removeObject(forKey: LaunchThemeMirror.redUpKey)
    }
  }
}
