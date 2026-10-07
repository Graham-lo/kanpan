import Testing
@testable import ReviewUI

// ============================================================ 复盘本打开停在哪一面（2026-10-08 走查）
//
// 「观点」一条都没有、「交易」有回合 → 直接翻到交易那面；两面都有（或都没有）→ 留在上次用的那面。

@MainActor @Suite("复盘本：「观点 · 交易」开在哪一面")
struct ReviewSegmentChoiceTests {
  typealias S = TradeReviewFeature.Segment

  @Test("观点空、交易有 → 交易；不论上次停在哪")
  func emptyViewsJumpToTrades() {
    #expect(TradeReviewFeature.preferredSegment(current: .views, viewsEmpty: true, tradesEmpty: false) == .trades)
    #expect(TradeReviewFeature.preferredSegment(current: .trades, viewsEmpty: true, tradesEmpty: false) == .trades)
  }

  @Test("两面都有、两面都空、只有观点 → 留在上次那面")
  func otherwiseKeepLast() {
    for current in [S.views, .trades] {
      #expect(TradeReviewFeature.preferredSegment(current: current, viewsEmpty: false, tradesEmpty: false) == current)
      #expect(TradeReviewFeature.preferredSegment(current: current, viewsEmpty: true, tradesEmpty: true) == current)
      #expect(TradeReviewFeature.preferredSegment(current: current, viewsEmpty: false, tradesEmpty: true) == current)
    }
  }

  @Test("全新档案：没有观点也没有回合，settle 不动，停在观点")
  func freshFeatureStaysOnViews() {
    let feature = ReviewFeature()
    #expect(feature.viewsEmpty)
    feature.settleSegment()
    #expect(feature.trades.segment == .views)
    feature.trades.segment = .trades
    feature.settleSegment()
    #expect(feature.trades.segment == .trades, "两面都空时人自己点的那面不该被改回去")
  }

  @Test("没接线就没有「去记一笔」；接上了点一下会走宿主那条路")
  func noteOnChartHook() {
    let feature = ReviewFeature()
    #expect(feature.onNoteOnChart == nil)
    var fired = 0
    feature.onNoteOnChart = { fired += 1 }
    feature.onNoteOnChart?()
    #expect(fired == 1)
  }
}
