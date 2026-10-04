import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 审查 A 线：「慢半拍再发」的那几摊预取（扫图邻居、列表露面行、换品种后补热其余周期）
/// 进后台、关图时要一起收掉；列表那一批要问最后露面的那一屏。
@MainActor
@Suite("慢半拍的预取跟着前后台收")
struct PrefetchLifecycleTests {
  @Test("扫图邻居的预取挂着时进后台，就地收掉")
  func backgroundCancelsNeighborPrefetch() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    model.prefetchNeighbors(["ETHUSDT", "SOLUSDT"])
    #expect(model.prefetchInFlight, "前台扫图时邻居预取应该已经排上")
    model.enterBackground()
    #expect(!model.prefetchInFlight, "进后台了，睡醒还会去拉邻居的 K 线快照")
  }

  @Test("列表露面行的预取挂着时关图，就地收掉；关图后再露面也不再排")
  func stopCancelsListPrefetch() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    model.prefetchListStats(["ETHUSDT"])
    #expect(model.prefetchInFlight)
    model.stop()
    #expect(!model.prefetchInFlight, "关图之后列表那一摊还挂着")
  }

  @Test("后台露面的行不攒着等回前台捎带")
  func backgroundDoesNotHoardListRows() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    model.enterBackground()
    model.prefetchListStats(["ETHUSDT"])
    #expect(!model.prefetchInFlight)
    model.enterForeground()
    model.stop()
  }

  @Test("一路滑过几十行：这一批问的是最后露面的那一屏，不是滚过去的头几行")
  func listBatchIsTheLastScreen() {
    let rows = (0..<40).map { "S\($0)USDT" }
    let pending = MarketModel.enqueueListStats([], rows)
    let batch = MarketModel.listStatsBatch(pending)
    #expect(batch.count == MarketModel.listStatsLimit)
    #expect(batch == Array(rows.suffix(MarketModel.listStatsLimit)))
  }

  @Test("同一行又露面：挪到队尾，不在原位占着")
  func reappearingRowMovesToTail() {
    let pending = MarketModel.enqueueListStats(["A", "B", "C"], ["A", "", "D"])
    #expect(pending == ["B", "C", "A", "D"])
  }
}

/// 审查 A 线：交易所答不出代号、图上已经翻成下架之后，迟到的目录查询不许把它翻回「交易中」。
@MainActor
@Suite("下架判定不被迟到的品种信息盖掉")
struct RejectionStickinessTests {
  @Test("同一只：图上已下架，目录回来的「交易中」照样留下架")
  func lateCatalogRowKeepsRejection() {
    let current = SymbolInfo.placeholder(symbol: "BTCUSDT", status: .delisted)
    var found = SymbolInfo.placeholder(symbol: "BTCUSDT", status: .tradable)
    found.pricePrecision = 2
    let merged = MarketModel.keepingRejection(found, over: current)
    #expect(merged.status == .delisted)
    #expect(merged.pricePrecision == 2, "其余字段照目录那一行")
  }

  @Test("不是同一只、或者本来就没被拒：目录说什么就是什么")
  func otherwiseCatalogWins() {
    let rejected = SymbolInfo.placeholder(symbol: "ETHUSDT", status: .delisted)
    let found = SymbolInfo.placeholder(symbol: "BTCUSDT", status: .tradable)
    #expect(MarketModel.keepingRejection(found, over: rejected).status == .tradable)
    let live = SymbolInfo.placeholder(symbol: "BTCUSDT", status: .tradable)
    let halted = SymbolInfo.placeholder(symbol: "BTCUSDT", status: .halted)
    #expect(MarketModel.keepingRejection(halted, over: live).status == .halted)
  }
}

/// 审查 A 线：网关线路（没有标记价流）结算一到就重拉费率表，不再按八小时瞎滚一分半。
@MainActor
@Suite("结算到点就续费率表")
struct FundingRolloverTests {
  @Test("离结算还有十分钟：十分钟加翻表余量之后问")
  func waitsUntilSettlementPlusLag() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let next = Int64((now.timeIntervalSince1970 + 600) * 1000)
    let wait = MarketModel.fundingRolloverDelay(nextMs: next, now: now)
    #expect(wait == .milliseconds(Int64((600 + MarketModel.fundingRolloverLag) * 1000)))
  }

  @Test("结算早就过了、或者远得离谱：不排")
  func pastOrAbsurdIsSkipped() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let past = Int64((now.timeIntervalSince1970 - 60) * 1000)
    #expect(MarketModel.fundingRolloverDelay(nextMs: past, now: now) == nil)
    let far = Int64((now.timeIntervalSince1970 + HeaderStats.fundingPeriod * 5) * 1000)
    #expect(MarketModel.fundingRolloverDelay(nextMs: far, now: now) == nil)
  }
}
