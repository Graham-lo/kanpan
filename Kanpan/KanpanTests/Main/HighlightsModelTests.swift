import Foundation
import Testing
import KanpanCore
@testable import Kanpan

// 「盘口要点」半页的状态：换品种清旧、首页带进来的那一条落地、价位展开 / 收起与带子。

@Suite("盘口要点：半页状态")
@MainActor struct HighlightsModelTests {
  private let wall = HighlightLevel(id: "lv-1", low: 82_609, high: 82_940, side: .bid, distPct: 0.08,
                                    wallUsd: 463_000_000, wallHeldMs: 8 * 3_600_000, tests: 27)
  private let eaten = HighlightEvent(id: "ev-1", t: .wallEaten, atMs: 1_791_606_780_000, price: 82_899,
                                     usd: 20_400_000, side: "ask", distPct: 0.07)

  private func page(_ base: String, levels: [HighlightLevel]? = nil) -> HighlightsPage {
    HighlightsPage(base: base, generatedAtMs: 1_791_606_780_000, tracked: true,
                   flow: .init(rows: [FlowRow(w: .h1, netUsd: 30_400_000, pxPct: 0.06, oiPct: 0.08)]),
                   levels: levels ?? [wall], events: [eaten])
  }

  private final class Count { var n = 0 }

  /// 跑一轮轮询：第一份答复落进模型就收掉任务（第二轮在 60 秒的睡眠里，等不到）。
  private func pollOnce(_ model: HighlightsModel, base: String, answer: HighlightsPage?) async {
    let count = Count()
    let task = Task { await model.poll(base: base) { _ in count.n += 1; return answer } }
    var spins = 0
    while count.n == 0, spins < 1_000 { await Task.yield(); spins += 1 }
    for _ in 0..<20 { await Task.yield() }
    task.cancel()
    await task.value
  }

  @Test func levelToggleDrawsAndClearsBand() async {
    let model = HighlightsModel()
    await pollOnce(model, base: "BTC", answer: page("BTC"))
    #expect(model.page?.base == "BTC")
    model.toggle(level: wall)
    #expect(model.expanded == "lv-1")
    #expect(model.band?.kind == .price(low: 82_609, high: 82_940))
    #expect(model.band?.label == "买区 463M")
    model.toggle(level: wall)
    #expect(model.expanded == nil && model.band == nil)
  }

  @Test func switchingBaseClearsAndClosesUnlessPending() async {
    let model = HighlightsModel()
    await pollOnce(model, base: "BTC", answer: page("BTC"))
    model.open = true
    model.toggle(level: wall)
    await pollOnce(model, base: "ETH", answer: page("ETH", levels: []))
    #expect(model.open == false)
    #expect(model.band == nil && model.expanded == nil)

    // 首页点进来：到了这只的答复就展开那一条、画带子、升起半页。
    model.expect(base: "SOL", focusID: "lv-1", autoOpen: true)
    await pollOnce(model, base: "SOL", answer: page("SOL"))
    #expect(model.open)
    #expect(model.expanded == "lv-1")
    #expect(model.scrollTarget == "lv-1")
    #expect(model.band?.sourceID == "lv-1")
  }

  @Test func failedRoundKeepsOldPageAsStale() async {
    let model = HighlightsModel()
    await pollOnce(model, base: "BTC", answer: page("BTC"))
    #expect(!model.stale)
    await pollOnce(model, base: "BTC", answer: nil)
    #expect(model.page != nil)
    #expect(model.stale)
    #expect(model.stoppedAtMs == 1_791_606_780_000)
  }

  @Test func eventBandIsAPriceLineWithShortLabel() {
    let band = HighlightsModel.band(for: eaten, scale: 1, decimals: 1)
    #expect(band?.kind == .price(low: 82_899, high: 82_899))
    #expect(band?.label.contains("·") == false)
    let span = HighlightEvent(id: "ev-2", t: .flowBurst, fromMs: 1_000, toMs: 61_000, netUsd: 12_000_000)
    #expect(HighlightsModel.band(for: span, scale: 1, decimals: 1)?.kind == .span(from: 1_000, to: 61_000))
  }
}
