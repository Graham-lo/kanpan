import Foundation
import KanpanCore
import XCTest
@testable import Kanpan

@MainActor
final class OrderFlowInsightsFeedTests: XCTestCase {
  private func page(_ base: String) throws -> OrderFlowInsightsPage {
    let body = """
    {"base":"\(base)","generatedAtMs":1791424800000,"dayStartMs":1791388800000,"tracked":true,"coverageSinceMs":1791420000000,"lastTradeMs":null,"bigUsd":1000,"windows":[],"zones":[]}
    """
    return try JSONDecoder().decode(OrderFlowInsightsPage.self, from: Data(body.utf8))
  }
  private func eventually(_ predicate: () -> Bool) async throws {
    for _ in 0..<100 { if predicate() { return }; try await Task.sleep(for: .milliseconds(10)) }
    XCTFail("Polling state did not settle")
  }
  func testCloseCancelsInFlightResponse() async throws {
    let feed = OrderFlowInsightsFeed()
    var continuation: CheckedContinuation<OrderFlowInsightsFeed.Response, Never>?
    feed.run(symbol: "BTCUSDT", base: "BTC") { _, _ in await withCheckedContinuation { continuation = $0 } }
    try await eventually { continuation != nil }
    feed.run(symbol: nil, base: nil) { _, _ in .init() }
    continuation?.resume(returning: .init(page: try page("BTC")))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(feed.page)
    XCTAssertFalse(feed.loading)
  }
  func testSwitchSymbolRejectsLatePreviousSymbolResponse() async throws {
    let feed = OrderFlowInsightsFeed()
    var continuation: CheckedContinuation<OrderFlowInsightsFeed.Response, Never>?
    feed.run(symbol: "BTCUSDT", base: "BTC") { _, _ in await withCheckedContinuation { continuation = $0 } }
    try await eventually { continuation != nil }
    let eth = try page("ETH")
    feed.run(symbol: "ETHUSDT", base: "ETH") { _, _ in .init(page: eth) }
    try await eventually { feed.page?.base == "ETH" }
    continuation?.resume(returning: .init(page: try page("BTC")))
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertEqual(feed.page?.base, "ETH")
    feed.run(symbol: nil, base: nil) { _, _ in .init() }
  }
  func testRefreshFailurePreservesEvidenceButDisablesCurrentJudgment() async throws {
    let feed = OrderFlowInsightsFeed(pollInterval: .milliseconds(10))
    let btc = try page("BTC")
    var calls = 0
    feed.run(symbol: "BTCUSDT", base: "BTC") { _, _ in
      calls += 1
      return .init(page: calls == 1 ? btc : nil, bars: [])
    }
    try await eventually { calls >= 2 && feed.unavailable }
    XCTAssertEqual(feed.page?.base, "BTC")
    XCTAssertTrue(feed.bars.isEmpty)
    feed.run(symbol: nil, base: nil) { _, _ in .init() }
    let stoppedAt = calls
    try await Task.sleep(for: .milliseconds(40))
    XCTAssertEqual(calls, stoppedAt)
  }
  func testDefaultOpenResetsSelectedBarAndBubbleKeepsExplicitSelection() {
    let model = BigTradeSheetModel()
    model.open(at: 1000)
    XCTAssertEqual(model.focusT, 1000)
    model.close()
    model.open(at: nil)
    XCTAssertNil(model.focusT)
    model.noteCrosshair(t: 2000)
    model.close()
    model.open(at: nil)
    XCTAssertNil(model.focusT)
  }
}
