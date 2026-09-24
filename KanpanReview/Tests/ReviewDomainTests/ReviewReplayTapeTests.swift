import Foundation
import KanpanCore
import XCTest
import ReviewDomain

/// 回放增量追加与落图记号筛选的缓存（第 25 项）。前面几条锁行为，最后两条量数：
/// 同一台模拟器上把「原来每一拍做的事」和「现在每一拍做的事」各跑一遍，打印出来。
final class ReviewReplayTapeTests: XCTestCase {
  private let step: Int64 = 60_000

  private func bars(_ n: Int, from t0: Int64 = 1_700_000_000_000) -> [Bar] {
    (0..<n).map { i in
      let p = 100 + sin(Double(i) / 7) * 5
      return Bar(openTime: t0 + Int64(i) * step, open: p, high: p + 1, low: p - 1, close: p + 0.5, volume: 10 + Double(i % 13))
    }
  }

  private func snapshot(_ n: Int) throws -> Data {
    try JSONEncoder().encode((0..<n).map { Drawing(id: "d\($0)", kind: .hline, a: DrawPoint(t: 0, p: Double($0))) })
  }

  func testSteppingForwardAppendsOneBarSoTheChartCanUpdateOnlyTheTail() {
    var tape = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: bars(300), drawingSnapshot: nil)
    let first = tape.series(through: 99)
    XCTAssertEqual(first.count, 100)
    let next = tape.series(through: 100)
    XCTAssertEqual(next.count, 101)
    // 图表走增量的判据：新序列正好是上一条后面长了一根。
    XCTAssertTrue(next.isOneBarAfter(first))
    // 内容和整段重建的一模一样。
    XCTAssertEqual(next, BarSeries(symbol: "BTCUSDT", interval: .m1, bars: Array(bars(300).prefix(101))))
    XCTAssertEqual(tape.rebuilds, 1)
  }

  func testStayingPutReturnsTheSameRevisionAndSteppingBackRebuilds() {
    var tape = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: bars(300), drawingSnapshot: nil)
    let a = tape.series(through: 150)
    let b = tape.series(through: 150)
    XCTAssertEqual(a.revision, b.revision, "原地不动：同一个修订戳，图表整帧跳过")
    let back = tape.series(through: 149)
    XCTAssertEqual(back.count, 150)
    XCTAssertEqual(tape.rebuilds, 2)
  }

  func testPagingForwardKeepsThePrefixAndPagingBackwardRebuilds() {
    let all = bars(600)
    var tape = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: Array(all.prefix(300)), drawingSnapshot: nil)
    let before = tape.series(through: 299)
    // 往后翻一页：开头没变，已经喂过的那一段仍是前缀，下一拍接着追加。
    tape.replace(bars: Array(all.prefix(600)))
    let after = tape.series(through: 300)
    XCTAssertTrue(after.isOneBarAfter(before))
    XCTAssertEqual(tape.rebuilds, 1)
    // 往前补历史：下标整体挪了，必须重建。
    tape.replace(bars: bars(100, from: all[0].openTime - 100 * step) + all)
    let shifted = tape.series(through: 400)
    XCTAssertEqual(shifted.count, 401)
    XCTAssertEqual(shifted.firstTime, all[0].openTime - 100 * step)
    XCTAssertEqual(tape.rebuilds, 2)
  }

  func testTheDrawingSnapshotIsDecodedOnce() throws {
    var tape = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: bars(10), drawingSnapshot: try snapshot(3))
    XCTAssertEqual(tape.drawings().count, 3)
    XCTAssertEqual(tape.drawings().count, 3)
    XCTAssertEqual(tape.decodes, 1)
    var broken = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: bars(10), drawingSnapshot: Data("oops".utf8))
    XCTAssertEqual(broken.drawings(), [])
    XCTAssertEqual(broken.drawings(), [])
    XCTAssertEqual(broken.decodes, 1)
  }

  private func record(_ symbol: String, interval: String = "1h", venue: String = "binance") -> ReviewRecord {
    var range = ReviewRange(symbol: symbol, interval: interval, start: 0, end: 180_000, bars: 3)
    range.venue = venue
    return ReviewRecord(draft: ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: 1_000_000))
  }

  func testMarkFilterAnswersFromCacheUntilRecordsOrTheChartChange() {
    var records = (0..<30).map { record($0 % 3 == 0 ? "BTCUSDT" : "ETHUSDT") }
    var filter = ReviewMarkFilter()
    XCTAssertEqual(filter.marks(records, venue: "binance", symbol: "BTCUSDT", interval: "1h").count, 10)
    XCTAssertEqual(filter.marks(records, venue: "binance", symbol: "BTCUSDT", interval: "1h").count, 10)
    XCTAssertEqual(filter.misses, 1, "记录与图都没变：不再重筛")
    // 内容一样的另一份拷贝也认得出来。
    let copy = records.map { $0 }
    XCTAssertEqual(filter.marks(copy, venue: "binance", symbol: "BTCUSDT", interval: "1h").count, 10)
    XCTAssertEqual(filter.misses, 1)
    // 换周期、换品种、改了一条记录，都要重筛。
    XCTAssertEqual(filter.marks(records, venue: "binance", symbol: "BTCUSDT", interval: "1m").count, 0)
    XCTAssertEqual(filter.marks(records, venue: "binance", symbol: "ETHUSDT", interval: "1h").count, 20)
    records[1].voided = true
    XCTAssertEqual(filter.marks(records, venue: "binance", symbol: "ETHUSDT", interval: "1h").count, 19)
    XCTAssertEqual(filter.misses, 4)
    // 最多 50 条。
    let many = (0..<80).map { _ in record("BTCUSDT") }
    XCTAssertEqual(filter.marks(many, venue: "binance", symbol: "BTCUSDT", interval: "1h").count, ReviewMarkFilter.limit)
  }

  // MARK: - 量数

  private func milliseconds(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
  }

  /// 100 拍回放（2000 根历史、从第 1500 根往后推、记录带 20 条画线快照）：
  /// 原来每一拍整段摊一次 `BarSeries` + 解一次快照，现在追加一根 + 快照解一次。
  /// 这只是桥这一侧的账；图表那一侧省下的（整套指标重算 → 只算末根）见提交说明里的另一组数。
  func testMeasureHundredReplaySteps() throws {
    let history = bars(2000)
    let data = try snapshot(20)
    var beforeSink = 0
    let before = milliseconds {
      for cursor in 1500..<1600 {
        let series = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: Array(history.prefix(cursor + 1)))
        let drawings = (try? JSONDecoder().decode([Drawing].self, from: data)) ?? []
        beforeSink &+= series.count &+ drawings.count
      }
    }
    var tape = ReviewReplayTape(symbol: "BTCUSDT", interval: .m1, bars: history, drawingSnapshot: data)
    var afterSink = 0
    let after = milliseconds {
      for cursor in 1500..<1600 {
        let series = tape.series(through: cursor)
        afterSink &+= series.count &+ tape.drawings().count
      }
    }
    XCTAssertEqual(beforeSink, afterSink)
    print("[量数] 回放 100 拍（桥侧）：原来 \(String(format: "%.2f", before)) ms → 现在 \(String(format: "%.2f", after)) ms；整段重建 \(tape.rebuilds) 次、快照解 \(tape.decodes) 次")
  }

  /// 一次落图重画要筛的记号：300 条记录，原来每一帧都筛，现在记录与图没变就直接给答案。
  func testMeasureOneOverlayDrawFilter() {
    let records = (0..<300).map { record($0 % 4 == 0 ? "BTCUSDT" : "ETHUSDT") }
    var beforeSink = 0
    let before = milliseconds {
      for _ in 0..<120 {
        beforeSink &+= records.filter { $0.paints(venue: "binance", symbol: "BTCUSDT", interval: "1h") }.prefix(50).count
      }
    }
    var filter = ReviewMarkFilter()
    var afterSink = 0
    let after = milliseconds {
      for _ in 0..<120 { afterSink &+= filter.marks(records, venue: "binance", symbol: "BTCUSDT", interval: "1h").count }
    }
    XCTAssertEqual(beforeSink, afterSink)
    print("[量数] 落图记号筛选（300 条记录，120 帧 ≈ 拖图一秒）：原来 \(String(format: "%.3f", before)) ms（每帧 \(String(format: "%.4f", before / 120)) ms）→ 现在 \(String(format: "%.3f", after)) ms（每帧 \(String(format: "%.4f", after / 120)) ms）；重筛 \(filter.misses) 次")
  }
}
