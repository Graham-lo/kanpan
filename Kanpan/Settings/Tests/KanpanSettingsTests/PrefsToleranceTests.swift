import Testing
import Foundation
import KanpanCore
@testable import KanpanSettings

/// 存档被改坏、被写脏、来自别的版本时，不能崩也不能一屏空白。
@Suite("容错")
struct PrefsToleranceTests {

  private func decode(_ json: String) -> Prefs {
    PrefsCodec.decode(json.data(using: .utf8))
  }

  @Test("没有存档 → 全新安装的默认")
  func 没存档() {
    #expect(PrefsCodec.decode(nil) == .defaults)
    #expect(PrefsCodec.decode(Data()) == .defaults)
  }

  @Test("不是 JSON / 是别的 JSON → 默认，不抛")
  func 坏档() {
    #expect(PrefsCodec.decode("这不是 json".data(using: .utf8)) == .defaults)
    #expect(decode("[1,2,3]") == .defaults)
    #expect(decode("null") == .defaults)
    #expect(decode("{}") == .defaults)
  }

  @Test("字段类型全错 → 逐项退回默认，不是整档作废")
  func 类型不对() {
    let p = decode(#"{"v":"一","interval":42,"magnet":"是","subs":"MACD","styleID":["stout"],"apiHost":7}"#)
    #expect(p == .defaults)
  }

  @Test("认不出来的枚举值 → 那一项取默认")
  func 认不出的枚举() {
    let p = decode(#"""
    {"interval":"8h","styleID":"雷电","theme":"neon","priceMode":"polar","timeZone":"火星"}
    """#)
    #expect(p.interval == .h1)
    #expect(p.style.name == "AICoin")       // 存档里那个 `styleID` 现在整条忽略，造型只有这一套
    #expect(p.theme == .system)
    #expect(p.priceMode == .log)
    #expect(p.timeZone == .local)
  }

  @Test("「图表」那几项：认不出的字面量退回默认，不牵连同一档里别的项")
  func 脏图表枚举() {
    let p = decode(#"""
    {"candleKind":"garbage","gridChoice":"garbage","bodyChoice":"garbage",
     "viewAnchor":"garbage","priceBias":"garbage"}
    """#)
    #expect(p.candleKind == Prefs.defaults.candleKind)
    #expect(p.gridChoice == Prefs.defaults.gridChoice)
    #expect(p.bodyChoice == Prefs.defaults.bodyChoice)
    #expect(p.viewAnchor == Prefs.defaults.viewAnchor)
    #expect(p.priceBias == Prefs.defaults.priceBias)
    #expect(p == .defaults)                 // 全都认不出，等于这几项压根没写过

    // 一个坏的不能把同一档里好的那个带下水
    let q = decode(#"{"gridChoice":"garbage","bodyChoice":"hollowUp"}"#)
    #expect(q.gridChoice == .off)
    #expect(q.bodyChoice == .hollowUp)

    // 旧存档里的 `"style"`（撤掉的「跟随风格」那一档）读成实心——风格表只剩一套，两者等价。
    #expect(decode(#"{"bodyChoice":"style"}"#).bodyChoice == .solid)
  }

  @Test("「图表」的三个开关：类型不对退回默认")
  func 脏图表开关() {
    let p = decode(#"{"lastLine":"开","showDrawings":1,"sinceChange":[true]}"#)
    #expect(p.lastLine == Prefs.defaults.lastLine)
    #expect(p.showDrawings == Prefs.defaults.showDrawings)
    #expect(p.sinceChange == Prefs.defaults.sinceChange)
  }

  @Test("指标：认不出的丢掉、重复的去重、放错位置的剔掉")
  func 脏指标() {
    let p = decode(#"""
    {"overlays":["MA","MA","MACD","超级线"],"subs":["RSI","RSI","MA","KDJ"]}
    """#)
    #expect(p.overlays == [.ma])           // MACD 是副图指标，不能挂主图
    #expect(p.subs == [.rsi, .kdj])
  }

  @Test("旧存档里多出来的副图按顺序截到三个")
  func 副图截断() {
    // 副图上限从七收到三之后，老存档里存着的五个要按原顺序留前三个，不是整包丢掉。
    let p = decode(#"{"subs":["MACD","RSI","KDJ","ATR","VOL"]}"#)
    #expect(p.subs == [.macd, .rsi, .kdj])
    #expect(p.subs.count <= Prefs.maxSubs)
  }

  @Test("参数越界 / 个数不对 → 夹回区间并补齐")
  func 脏参数() {
    let p = decode(#"""
    {"params":{"MA":[0,9999,-3],"MACD":[12],"ATR":[14,14,14],"超级线":[1],"OI":[5]}}
    """#)
    #expect(p.params(for: .ma) == [1, 400, 1])
    #expect(p.params(for: .macd) == [12, 26, 9])   // 缺的两位按默认补
    #expect(p.params(for: .atr) == [14])           // 多出来的截掉
    #expect(p.params(for: .oi) == [])
    #expect(p.params[.rsi] == nil)                 // 没存的就是没存
    #expect(p.params(for: .rsi) == IndicatorID.rsi.defaultParams)
  }

  @Test("副图高度：认不出的档丢掉")
  func 脏高度() {
    let p = decode(#"{"subHeights":{"MACD":"huge","RSI":"large","超级线":"small"}}"#)
    #expect(p.height(for: .macd) == .medium)   // 认不出 → 落回「中」
    #expect(p.height(for: .rsi) == .large)
  }

  @Test("常用行：去重、认不出的丢掉、超过 6 档按从短到长截断、空数组不生效")
  func 脏常用行() {
    // 「8h」这一档不存在（任务书 §1.1 定死不加），当场丢掉；剩下的按周期从短到长排。
    let a = decode(#"{"quickIntervals":["1h","1h","8h","5m"]}"#)
    #expect(a.quickIntervals == [.m5, .h1])
    let b = decode(#"{"quickIntervals":[]}"#)
    #expect(b.quickIntervals == Prefs.defaults.quickIntervals)
    // 十三档进去只留得下六档（`Prefs.maxQuick`，2026-09-21 从 10 收到 6）。
    // 砍之前先按从短到长排一遍：存档里的顺序是历史包袱，照原样 `prefix` 有可能
    // 只剩下 1d 1w 1M 这种全长周期，短周期反而一档不剩。
    let c = decode(#"{"quickIntervals":["1d","1w","1M","1m","3m","5m","15m","30m","1h","2h","4h","6h","12h"]}"#)
    #expect(c.quickIntervals.count == Prefs.maxQuick)
    #expect(c.quickIntervals == [.m1, .m3, .m5, .m15, .m30, .h1])
  }

  @Test("域名：修得好就修，修不好退回默认")
  func 脏域名() {
    #expect(decode(#"{"apiHost":"  HTTPS://Fapi.Example.COM/  "}"#).apiHost == "fapi.example.com")
    #expect(decode(#"{"apiHost":"不是域名"}"#).apiHost == APIHost.default)
    #expect(decode(#"{"apiHost":""}"#).apiHost == APIHost.default)
  }

  @Test("坏档进 store：能起来，而且不会把坏档留在盘上")
  @MainActor
  func 坏档起步() {
    let box = InMemoryPrefsStorage(["kanpan.prefs.v1": "坏了".data(using: .utf8)!])
    let store = PrefsStore(storage: box, cache: UnavailableMarketCache())
    #expect(store.prefs == .defaults)
    store.update { $0.magnet = false }
    #expect(PrefsStore.load(from: box).magnet == false)
  }
}

/// A6.5：参数 0 / 负数 / > 500 拒绝。
@Suite("参数规则")
struct IndicatorParamRuleTests {

  @Test("0、负数、超上限都要有拒绝理由")
  func 非法值() {
    #expect(IndicatorParamRule.reject(0) != nil)
    #expect(IndicatorParamRule.reject(-7) != nil)
    #expect(IndicatorParamRule.reject(501) != nil)
    #expect(IndicatorParamRule.reject(9999) != nil)
    #expect(IndicatorParamRule.reject(401) != nil)   // 原型步进器封顶 400
    #expect(IndicatorParamRule.isValid(1))
    #expect(IndicatorParamRule.isValid(400))
    #expect(IndicatorParamRule.isValid(26))
  }

  @Test("步进器按不出非法值")
  func 步进夹紧() {
    var p = Prefs.defaults
    p.setParam(.ma, at: 0, to: 7)
    for _ in 0..<10 { p.bumpParam(.ma, at: 0, by: -1) }
    #expect(p.params(for: .ma)[0] == 1)            // 不会到 0 或负数
    p.setParam(.ma, at: 0, to: 399)
    for _ in 0..<10 { p.bumpParam(.ma, at: 0, by: 1) }
    #expect(p.params(for: .ma)[0] == 400)
  }

  @Test("越界赋值被夹住；越界下标被忽略")
  func 直接赋值() {
    var p = Prefs.defaults
    p.setParam(.macd, at: 1, to: 100_000)
    #expect(p.params(for: .macd) == [10, 400, 9])
    p.setParam(.macd, at: 9, to: 5)
    #expect(p.params(for: .macd) == [10, 400, 9])
    p.setParam(.oi, at: 0, to: 5)
    #expect(p.params(for: .oi) == [])
  }
}

/// A6.10：自定义 API 域名。
@Suite("API 域名")
struct APIHostTests {

  @Test("默认就是 fapi.binance.com")
  func 默认值() {
    #expect(Prefs.defaults.apiHost == "fapi.binance.com")
  }

  @Test("抄来的地址能normalize")
  func 规范化() {
    #expect(APIHost.normalize("https://FAPI.Binance.com/") == "fapi.binance.com")
    #expect(APIHost.normalize(" wss://x.example.cn//") == "x.example.cn")
    #expect(APIHost.normalize("fapi.binance.com") == "fapi.binance.com")
  }

  @Test("形状不对的都要拒绝，并且不写进设置")
  func 拒绝() {
    for bad in ["", "   ", "localhost", "a b.com", "x.com:443", "x.com/path", ".com", "x..com", "中文.com"] {
      #expect(APIHost.reject(bad) != nil, "\(bad) 本该被拒")
      var p = Prefs.defaults
      #expect(p.setAPIHost(bad) != nil)
      #expect(p.apiHost == APIHost.default)
    }
  }

  @Test("合法域名写得进去，往返后还在")
  func 合法() {
    var p = Prefs.defaults
    #expect(p.setAPIHost(" https://Fapi.Mirror.COM/ ") == nil)
    #expect(p.apiHost == "fapi.mirror.com")
    #expect(PrefsCodec.decode(PrefsCodec.encode(p)).apiHost == "fapi.mirror.com")
  }
}
