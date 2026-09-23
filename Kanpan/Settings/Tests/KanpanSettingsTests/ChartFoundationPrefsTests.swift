import Testing
import KanpanCore
@testable import KanpanSettings

@Suite("指标草稿与图表设置")
struct ChartFoundationPrefsTests {
  @Test("常用指标取消不改原值、保存连同输出和阈值生效")
  func drafts() {
    for id in [IndicatorID.ma, .ema, .vol, .oi, .macd, .kdj, .rsi] {
      var prefs = Prefs()
      let before = prefs
      var draft = IndicatorDraft(id: id, prefs: prefs)
      if !draft.params.isEmpty { draft.params[0] += 1 }
      draft.hidden.insert(0); draft.upper = 80
      #expect(prefs == before)
      draft.save(into: &prefs)
      #expect(prefs.hiddenOutputs[id] == [0])
      if !draft.params.isEmpty { #expect(prefs.params(for: id)[0] == before.params(for: id)[0] + 1) }
      if id == .rsi { #expect(prefs.rsiUpper == 80) }
    }
  }

  @Test("全部新增设置落盘并容错读取")
  func persistence() {
    var prefs = Prefs()
    prefs.portraitHeight = 0.9; prefs.dataDisplay = .follow; prefs.crossPrice = .close
    prefs.allowMainInversion = false; prefs.allowSubInversion = true
    prefs.changeBasis = .shanghaiMidnight
    prefs.adaptiveIndicators = true
    prefs.rsiUpper = 80; prefs.rsiLower = 20
    prefs.hiddenOutputs = [.ma: [0, 2], .kdj: [2], .macd: [1, 2]]
    prefs.subHeightOverrides = [.vol: 0.73, .rsi: 1.42]
    // 副图上限收到三个之后（`Prefs.maxSubs`），读档时多出来的会被裁掉，
    // 所以这儿摆满三个来验往返——摆五个验的就不是「落盘读回一致」，
    // 而是「裁剪」，那件事下面单独验一次。
    prefs.subs = [.vol, .oi, .macd]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
    let restored = PrefsCodec.decode(PrefsCodec.encode(prefs))
    #expect(restored.chartOptions.dataDisplay == .follow)
    #expect(restored.chartOptions.allowSubInversion)
    #expect(restored.chartOptions.portraitHeight == 0.9)
  }

  /// 老存档里攒了五个副图的用户，升级后读回来只留最早的三个，不是整份档案作废。
  @Test("旧存档里超额的副图读回时被裁到三个")
  func clampsLegacySubs() {
    var prefs = Prefs()
    prefs.subs = [.vol, .oi, .macd, .kdj, .rsi]
    let restored = PrefsCodec.decode(PrefsCodec.encode(prefs))
    #expect(restored.subs == [.vol, .oi, .macd])
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
    #expect(PrefsStore(storage: storage).prefs.indicatorColors[.ma]?.isEmpty == true)
    #expect(PrefsStore(storage: storage).prefs.indicatorColors[.ema]?[0] == "#37A78F")
  }
}
