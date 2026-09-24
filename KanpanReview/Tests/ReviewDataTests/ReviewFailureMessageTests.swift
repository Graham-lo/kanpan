import XCTest
import ReviewData

/// 给人看的那句话。找相似任务停在服务端（取消 / 没搜完）不是「服务端坏了」，
/// 原来中文塞进了错误码那一格，落到 503 那条兜底，说成「服务端暂时不可用，稍后自动重试」。
final class ReviewFailureMessageTests: XCTestCase {
  func testSearchStopsAreNotServerOutages() {
    XCTAssertEqual(ScorebookError.http(503, "search_cancelled").errorDescription, "这次查找已取消")
    XCTAssertEqual(ScorebookError.http(503, "search_incomplete").errorDescription, "行情暂不完整，请稍后重试")
    XCTAssertEqual(ScorebookError.http(503, "").errorDescription, "服务端暂时不可用，稍后自动重试")
  }
  func testSignedOutSaysLogIn() {
    XCTAssertEqual(ScorebookError.signedOut.errorDescription, "登录后才能同步复盘")
  }
  /// 服务端原文一个字都不回显：中文、大写都会被 `code(for:)` 丢掉。
  func testServerTextIsNeverEchoed() {
    XCTAssertEqual(ReviewFailure.code(for: ScorebookError.http(500, "行情暂不完整")), "")
    XCTAssertEqual(ReviewFailure.code(for: ScorebookError.http(422, "record_voided")), "record_voided")
  }
}
