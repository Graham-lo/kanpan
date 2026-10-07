import Foundation
import KanpanCore
import Testing
import UIKit

@testable import Kanpan

/// 体感整改（2026-10-07）· 冷切到一只品种之后「还在路上」的那几样：
/// 顶栏六格画骨架而不是「—」，图区摆占位图而不是空白，真到了 / 确定不来了就撤掉。
@MainActor
@Suite("在路上：顶栏骨架与占位图")
struct ArrivalBoardTests {
  private func ticker(_ symbol: String, last: Double, low: Double, high: Double) -> Ticker {
    Ticker(symbol: symbol, last: last, changePercent: 1, high: high, low: low, quoteVolume: 1_000)
  }

  @Test("骨架只给「值还没有、它等的那样还在路上」的格子（六格与价、涨跌）；真没有的照旧是破折号")
  func skeletonOnlyWhilePending() {
    let all = ArrivalBoard.HeaderPending.all
    for cell in ArrivalBoard.HeaderCell.allCases {
      #expect(ArrivalBoard.showsSkeleton(cell, hasValue: false, pending: all, hasPrice: false))
      #expect(!ArrivalBoard.showsSkeleton(cell, hasValue: true, pending: all, hasPrice: false), "有值就画值")
      #expect(!ArrivalBoard.showsSkeleton(cell, hasValue: false, pending: [], hasPrice: false), "不在路上就是破折号")
    }
    // 持仓量到了（这家答了空）：仓那格回破折号，费率还在等。
    let rest: ArrivalBoard.HeaderPending = [.meta, .funding, .ticker]
    #expect(!ArrivalBoard.showsSkeleton(.openInterest, hasValue: false, pending: rest, hasPrice: false))
    #expect(ArrivalBoard.showsSkeleton(.funding, hasValue: false, pending: rest, hasPrice: false))
    #expect(ArrivalBoard.showsSkeleton(.settlement, hasValue: false, pending: rest, hasPrice: false))
    // 市值：供应量已到但价还没到，照样在路上；价也有了就不再等。
    #expect(ArrivalBoard.showsSkeleton(.marketCap, hasValue: false, pending: [.ticker], hasPrice: false))
    #expect(!ArrivalBoard.showsSkeleton(.marketCap, hasValue: false, pending: [.ticker], hasPrice: true))
    // 逐笔成交先给了价、24h 统计还没到：涨跌那行与「额」是骨架；统计到了就各回各的。
    #expect(ArrivalBoard.showsSkeleton(.change, hasValue: false, pending: [.ticker], hasPrice: true))
    #expect(!ArrivalBoard.showsSkeleton(.price, hasValue: true, pending: [.ticker], hasPrice: true))
    #expect(!ArrivalBoard.showsSkeleton(.change, hasValue: false, pending: [.openInterest, .meta, .funding], hasPrice: true))
  }

  @Test("要等的几样里，这家没有的、手里已经垫上的先划掉")
  func headerWaitDropsWhatNeverComesOrIsSeeded() {
    let all = ArrivalBoard.HeaderPending.all
    #expect(MarketModel.headerWait(all, hasOpenInterestSource: true, hasFunding: true, statsReachable: true,
                                   hasOpenInterest: false, hasMeta: false, hasFundingRate: false, hasTicker: false) == all)
    // 现货：没有持仓量、没有费率——那两样不会来，不许挂骨架。
    #expect(MarketModel.headerWait(all, hasOpenInterestSource: false, hasFunding: false, statsReachable: true,
                                   hasOpenInterest: false, hasMeta: false, hasFundingRate: false, hasTicker: false)
            == [.meta, .ticker])
    // 后端一台都没有：持仓量与供应量都不会来。
    #expect(MarketModel.headerWait(all, hasOpenInterestSource: true, hasFunding: true, statsReachable: false,
                                   hasOpenInterest: false, hasMeta: false, hasFundingRate: false, hasTicker: false)
            == [.funding, .ticker])
    // 缓存里垫上了的不算在路上。
    #expect(MarketModel.headerWait(all, hasOpenInterestSource: true, hasFunding: true, statsReachable: true,
                                   hasOpenInterest: true, hasMeta: true, hasFundingRate: true, hasTicker: true) == [])
  }

  @Test("冷切到一只：顶栏那几样贴在新品种的键上，旧键查不到；到了就划掉")
  func coldSwitchPublishesPendingForTheNewKey() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    model.switchTo(symbol: "ZROUSDT")
    let key = model.symbol
    let pending = ArrivalBoard.live.header(for: key)
    #expect(pending.contains(.ticker), "24h 统计还没到，额那格该是骨架")
    #expect(ArrivalBoard.live.header(for: InstrumentID.canonical("BTCUSDT")) == [], "上一只的键认领不到")
    model.arrived(.all)
    #expect(ArrivalBoard.live.header(for: key) == [])
    model.stop()
  }

  @Test("冷切到没快照的品种：老 K 线不留，占位图按报价簿那口价摆；序列一到就撤")
  func coldSwitchWithoutSnapshotShowsPlaceholder() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    let key = InstrumentID.canonical("ZROUSDT")
    let q = ticker(key, last: 2.5, low: 2.0, high: 3.0)
    model.seedQuote = { sym in sym == key ? q : nil }
    model.switchTo(symbol: "ZROUSDT")
    #expect(model.series == nil, "上一只的 K 线不能顶着新品种的名字留着")
    let p = ArrivalBoard.live.chartPlaceholder(for: key)
    #expect(p == ArrivalBoard.ChartPlaceholder(instrument: key, last: 2.5, low: 2.0, high: 3.0))
    model.stop()
  }

  @Test("占位图的规则：有序列 / 留着上一档 / 历史拉不下来都不摆；报价不是这一只的不用")
  func placeholderRules() {
    let key = InstrumentID.canonical("ETHUSDT")
    let q = ticker(key, last: 3000, low: 2900, high: 3100)
    #expect(MarketModel.chartPlaceholder(symbol: key, hasSeries: true, holdsFrame: false, failed: false, quote: q) == nil)
    #expect(MarketModel.chartPlaceholder(symbol: key, hasSeries: false, holdsFrame: true, failed: false, quote: q) == nil)
    #expect(MarketModel.chartPlaceholder(symbol: key, hasSeries: false, holdsFrame: false, failed: true, quote: q) == nil)
    let other = ticker(InstrumentID.canonical("BTCUSDT"), last: 60000, low: 59000, high: 61000)
    #expect(MarketModel.chartPlaceholder(symbol: key, hasSeries: false, holdsFrame: false, failed: false, quote: other)
            == ArrivalBoard.ChartPlaceholder(instrument: key, last: nil, low: nil, high: nil),
            "别的品种的价不许画到这一只的占位图上")
    let bad = ticker(key, last: 3000, low: 3100, high: 2900)
    let flipped = MarketModel.chartPlaceholder(symbol: key, hasSeries: false, holdsFrame: false, failed: false, quote: bad)
    #expect(flipped?.last == 3000 && flipped?.low == nil && flipped?.high == nil, "上下颠倒的区间不画")
  }

  @Test("占位图几何：区间上下留白，最新价按区间位置落；只有价就摆正中")
  func placeholderGeometry() {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
    let full = ChartPlaceholderView.geometry(
      for: .init(instrument: "k", last: 3100, low: 2900, high: 3100), in: rect)
    #expect(full.band == CGRect(x: 0, y: 20, width: 300, height: 60))
    #expect(full.lineY == 20, "最新价贴着 24h 高点")
    let mid = ChartPlaceholderView.geometry(for: .init(instrument: "k", last: 5, low: nil, high: nil), in: rect)
    #expect(mid.band == nil && mid.lineY == 50)
    let none = ChartPlaceholderView.geometry(for: .init(instrument: "k", last: nil, low: nil, high: nil), in: rect)
    #expect(none.band == nil && none.lineY == nil, "什么价都没有：只剩顶上那条进度条")
  }

  @Test("图表宿主：空图时照公告板摆占位，有图或公告板撤了就收")
  func chartBoxFollowsBoard() async {
    // 自己那一块板：别的用例里的行情模型也会往 `ArrivalBoard.live` 上贴。
    let board = ArrivalBoard()
    let box = ChartBox(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
    box.board = board
    board.setChart(.init(instrument: "k", last: 1, low: 0.5, high: 2))
    box.syncPlaceholder(enabled: true)
    #expect(!box.placeholderView.isHidden)
    box.syncPlaceholder(enabled: false)
    #expect(box.placeholderView.isHidden, "复盘那几张图不摆")
    box.syncPlaceholder(enabled: true)
    #expect(!box.placeholderView.isHidden)
    board.setChart(nil)
    for _ in 0..<50 where !box.placeholderView.isHidden { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(box.placeholderView.isHidden, "公告板撤了，占位图自己收")
  }
}
