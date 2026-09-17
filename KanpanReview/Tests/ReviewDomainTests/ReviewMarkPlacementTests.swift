import XCTest
import ReviewDomain

/// 记号落图的归属规则（§2F3 / §3.7 #40）。
///
/// 这条规则以前只写在 `RangeOverlayView.draw` 的那行 `filter` 里，而且只比了品种。
/// 现在规则搬进 `ReviewRecord.paints(symbol:interval:)`，这个文件就是它的锁：
/// 图层那边怎么重构，都不许让 BTC 的框画到 ETH 上、1 小时的框画到 1 分钟上。
final class ReviewMarkPlacementTests: XCTestCase {
  func testMarkPaintsOnlyOnItsOwnSymbolAndInterval() {
    let record = ReviewRecord(draft: makeDraft(symbol: "BTCUSDT", interval: "1h"))

    XCTAssertTrue(record.paints(symbol: "BTCUSDT", interval: "1h"), "自己这张图上必须画")
    XCTAssertFalse(record.paints(symbol: "ETHUSDT", interval: "1h"), "BTC 记的不能画到 ETH 图上")
    XCTAssertFalse(record.paints(symbol: "BTCUSDT", interval: "1m"), "1h 记的不能画到 1m 图上")
    XCTAssertFalse(record.paints(symbol: "BTCUSDT", interval: "4h"), "1h 记的不能画到 4h 图上")
  }

  func testVoidedMarkNeverPaints() {
    var record = ReviewRecord(draft: makeDraft(symbol: "BTCUSDT", interval: "1h"))
    record.voided = true
    XCTAssertFalse(record.paints(symbol: "BTCUSDT", interval: "1h"), "作废之后就不该再占着图")
  }

  private func makeDraft(symbol: String, interval: String) -> ReviewDraft {
    ReviewDraft(range: ReviewRange(symbol: symbol, interval: interval, start: 0, end: 10_800_000, bars: 3),
                reference: 100, high: 110, low: 90, now: 14_400_000)
  }
}
