import Foundation
import Testing
import KanpanCore
@testable import Kanpan

@Suite("指标草稿与图表设置")
struct ChartFoundationPrefsTests {
  @Test("常用指标取消不改原值、保存后参数生效")
  func drafts() {
    for id in [IndicatorID.ma, .ema, .vol, .oi, .macd, .kdj, .rsi] {
      var prefs = Prefs()
      let before = prefs
      var draft = IndicatorDraft(id: id, prefs: prefs)
      if !draft.params.isEmpty { draft.params[0] += 1 }
      #expect(prefs == before)
      draft.save(into: &prefs)
      if !draft.params.isEmpty { #expect(prefs.params(for: id)[0] == before.params(for: id)[0] + 1) }
    }
  }

  @Test("全部新增设置落盘并容错读取")
  func persistence() {
    var prefs = Prefs()
    prefs.subHeightOverrides = [.vol: 0.73, .rsi: 1.42]
    // 副图上限是成交量 + 三个（`Prefs.maxSubs`，成交量不占名额），读档时多出来的会被裁掉，
    // 所以这儿摆满成交量 + 三个来验往返——摆多了验的就不是「落盘读回一致」，
    // 而是「裁剪」，那件事下面单独验一次。
    prefs.subs = [.vol, .oi, .macd, .rsi]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
    let restored = PrefsCodec.decode(PrefsCodec.encode(prefs))
    // 数据展示、十字线价格、翻转许可、指标自适应 2026-09-28 起收成定值（收设置项 B 组）
    #expect(restored.chartOptions.dataDisplay == .top)
    #expect(restored.chartOptions.crossPrice == .selected)
    #expect(restored.chartOptions.allowMainInversion && restored.chartOptions.allowSubInversion)
    #expect(restored.chartOptions.adaptiveIndicators)
    // 竖屏主图占比 2026-10-10 退役（不存、不同步）：图拿的永远是 `ChartOptions` 的出厂值。
    #expect(restored.chartOptions.portraitHeight == ChartOptions().portraitHeight)
  }

  /// 老存档里攒了五个副图的用户，升级后读回来留成交量 + 最早的三个，不是整份档案作废。
  @Test("旧存档里超额的副图读回时被裁到成交量 + 三个")
  func clampsLegacySubs() {
    var prefs = Prefs()
    prefs.subs = [.vol, .oi, .macd, .kdj, .rsi]
    let restored = PrefsCodec.decode(PrefsCodec.encode(prefs))
    #expect(restored.subs == [.vol, .oi, .macd, .kdj])
  }

  /// 网页版推上来的是「成交量 + 最多三个」，四项；原来 `prefix(3)` 会把最后一个丢掉。
  @Test("网页推来的成交量 + 三个读回四项一个不丢")
  func keepsWebVolPlusThree() {
    let json = Data(#"{"subs":["VOL","MACD","RSI","KDJ"]}"#.utf8)
    #expect(PrefsCodec.decode(json).subs == [.vol, .macd, .rsi, .kdj])
  }

  /// 没有成交量的旧档四个副图：照旧截到三个。
  @Test("旧档四个非成交量副图截到三个")
  func clampsFourNonVol() {
    let json = Data(#"{"subs":["OI","MACD","RSI","KDJ"]}"#.utf8)
    #expect(PrefsCodec.decode(json).subs == [.oi, .macd, .rsi])
  }
}

@Suite("MA EMA color persistence")
struct IndicatorColorPersistenceTests {
  @Test @MainActor func cancelSaveRestartAndReset() {
    let storage = InMemoryPrefsStorage()
    let store = PrefsStore(storage: storage)
    var ma = IndicatorDraft(id: .ma, prefs: store.prefs)
    ma.colors[0] = "#4A90E2"; ma.colors[2] = "#E46A76"
    #expect(store.prefs.indicatorColors.isEmpty)
    store.update { ma.save(into: &$0) }
    var ema = IndicatorDraft(id: .ema, prefs: store.prefs)
    ema.colors[0] = "#37A78F"
    store.update { ema.save(into: &$0) }
    let restarted = PrefsStore(storage: storage)
    #expect(restarted.prefs.indicatorColors[.ma]?[0] == "#4A90E2")
    #expect(restarted.prefs.indicatorColors[.ma]?[2] == "#E46A76")
    #expect(restarted.prefs.indicatorColors[.ema]?[0] == "#37A78F")
    var reset = IndicatorDraft(id: .ma, prefs: restarted.prefs); reset.colors = [:]
    restarted.update { reset.save(into: &$0) }
    // 配色清空 = 回到出厂：整项清掉（nil），不留一张「空表」副本（2026-09-26）。
    #expect(PrefsStore(storage: storage).prefs.indicatorColors[.ma] == nil)
    #expect(PrefsStore(storage: storage).prefs.indicatorColors[.ema]?[0] == "#37A78F")
  }
}
