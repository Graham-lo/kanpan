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
    prefs.smartMarketRoute = false
    prefs.compactValues = true; prefs.adaptiveIndicators = true
    prefs.rsiUpper = 80; prefs.rsiLower = 20
    prefs.hiddenOutputs = [.ma: [0, 2], .kdj: [2], .macd: [1, 2]]
    prefs.subHeightOverrides = [.vol: 0.73, .rsi: 1.42]
    prefs.subs = [.vol, .oi, .macd, .kdj, .rsi]
    #expect(PrefsCodec.decode(PrefsCodec.encode(prefs)) == prefs)
    let restored = PrefsCodec.decode(PrefsCodec.encode(prefs))
    #expect(restored.chartOptions.dataDisplay == .follow)
    #expect(restored.chartOptions.allowSubInversion)
    #expect(restored.chartOptions.portraitHeight == 0.9)
  }
}
