import XCTest
import KanpanAccount
import ReviewData

/// 找相似轮询（审查 P2-2）：退避封顶 30 秒、有进展回到基准、总时长用完就停在可重试。
final class ReviewPollScheduleTests: XCTestCase {
  func testBacksOffToThirtySecondsWithoutProgress() {
    var s = ReviewPollSchedule()
    var waits: [Double] = []
    var elapsed = 0.0
    for _ in 0..<7 {
      let w = s.next(checked: 5, elapsed: elapsed)!
      waits.append(w); elapsed += w
    }
    XCTAssertEqual(waits, [2, 4, 8, 16, 30, 30, 30])
  }

  func testProgressResetsToBase() {
    var s = ReviewPollSchedule()
    XCTAssertEqual(s.next(checked: 1, elapsed: 0), 2)
    XCTAssertEqual(s.next(checked: 1, elapsed: 2), 4)
    XCTAssertEqual(s.next(checked: 1, elapsed: 6), 8)
    XCTAssertEqual(s.next(checked: 40, elapsed: 14), 2, "进度动了，该勤快地刷")
    XCTAssertEqual(s.next(checked: 40, elapsed: 16), 4)
    XCTAssertEqual(s.next(checked: nil, elapsed: 20), 8, "没报进度不算进展")
  }

  func testStopsAtBudgetAndLastWaitIsClipped() {
    var s = ReviewPollSchedule(base: 2, ceiling: 30, budget: 600)
    XCTAssertEqual(s.next(checked: nil, elapsed: 595), 2)
    XCTAssertEqual(s.next(checked: nil, elapsed: 598), 2, "最后一次只睡到总时长为止")
    XCTAssertNil(s.next(checked: nil, elapsed: 600))
    XCTAssertNil(s.next(checked: 99, elapsed: 700))
  }

  func testTotalWaitNeverExceedsBudget() {
    var s = ReviewPollSchedule()
    var elapsed = 0.0, polls = 0
    while let w = s.next(checked: 0, elapsed: elapsed) { elapsed += w; polls += 1 }
    XCTAssertEqual(elapsed, 600, accuracy: 0.001)
    XCTAssertLessThan(polls, 30, "卡住的任务十分钟里只该问二十来次，不是三百次")
  }

  func testTimeoutIsRetryableNotAFailure() {
    let e = ReviewPollSchedule.timedOut
    XCTAssertEqual(e.reviewErrorCode, "search_timeout")
    XCTAssertEqual(e.errorDescription, "查找用时太长，已先停下，请稍后重试")
  }

  func testWhichErrorsKeepPolling() {
    XCTAssertTrue(ReviewPollSchedule.keepsPolling(after: URLError(.timedOut)))
    XCTAssertTrue(ReviewPollSchedule.keepsPolling(after: ScorebookError.http(503, "")))
    XCTAssertTrue(ReviewPollSchedule.keepsPolling(after: AccountError.http(502, "")))
    XCTAssertTrue(ReviewPollSchedule.keepsPolling(after: AccountError.http(429, "")))
    XCTAssertTrue(ReviewPollSchedule.keepsPolling(after: AccountError.unavailable))
    XCTAssertFalse(ReviewPollSchedule.keepsPolling(after: AccountError.reauthenticationRequired))
    XCTAssertFalse(ReviewPollSchedule.keepsPolling(after: AccountError.http(401, "")))
    XCTAssertFalse(ReviewPollSchedule.keepsPolling(after: ScorebookError.http(404, "not_found")))
    XCTAssertFalse(ReviewPollSchedule.keepsPolling(after: CancellationError()))
  }
}
