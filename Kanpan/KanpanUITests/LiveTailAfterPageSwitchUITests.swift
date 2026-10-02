import XCTest

// ============================================================ 切页回来，新 K 线还在屏上
//
// 2026-10-02 用户在手机网页版上看 XAUUSDT 30m：价格线和顶栏在跳，最新那根 K 线却没画——
// 视野停在离开那一刻，离开期间开出来的那根落在右缘外。iOS 换页时图会整个拆掉重建、把离开前的
// 视野装回去，看着像同一个洞；实测没有——切回图表时 `MainScreen` 见「离开前在最新」就
// `scrollToLatest`，右缘跟着推到新的末根。这条用例把它钉住，免得以后改切页逻辑时漏掉。
//
// 照人的用法走一遍：1m 图跟着最新 → 切到自选 → 等过一个分钟边界 → 切回图表，
// 末根必须完整落在图区里。
final class LiveTailAfterPageSwitchUITests: KanpanUICase {
  func testBarOpenedWhileAwayIsOnScreenWhenBack() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活起来")
    app.tapIntervalChip("1m")
    XCTAssertTrue(waitUntil(timeout: Self.long, poll: 0.5) {
      (self.chartInfo()["bars"] as? Int ?? 0) > 0 && self.chartAtLatest()
    }, "1m 图没跟着最新")
    // 离开时离下一个分钟边界至少留 5s，免得边界压在切页动画中间。
    func secondsIntoMinute() -> Double { Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60) }
    while secondsIntoMinute() > 50 { Thread.sleep(forTimeInterval: 1) }
    let before = chartInfo()
    let beforeTo = before["to"] as? Double ?? 0
    XCTAssertTrue(app.openFavorites(), "没进自选页")
    Thread.sleep(forTimeInterval: 60 - secondsIntoMinute() + 6)
    app.buttons[Ids.bottomChart].tap()
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long))
    Thread.sleep(forTimeInterval: 2)
    let after = chartInfo()
    let gap = after["latestRightGap"] as? Double ?? -.infinity
    let spacing = after["spacing"] as? Double ?? 0
    let afterTo = after["to"] as? Double ?? 0
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "切页回来"
    shot.lifetime = .keepAlways
    add(shot)
    XCTAssertGreaterThan(afterTo, beforeTo, "离开期间没开出新 K 线，或者视野没往后推（前 \(before) / 后 \(after)）")
    XCTAssertGreaterThanOrEqual(gap, -spacing / 2, "末根落在右缘外：latestRightGap=\(gap) spacing=\(spacing)")
  }
}
