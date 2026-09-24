import XCTest

/// 静置看一分钟行情，宿主页跟着推送重算了多少遍（审查 21 的验收口径）。
///
/// 和 `DrawingDragRenderCostUITests` 一样本身不判数：它只负责把「打开 BTCUSDT 1h、
/// 等推送 live、手不碰屏幕放 60 秒」稳定地做一遍。DEBUG 包看到 `KANPAN_FRAME_PROBE_IDLE`
/// 就在 live 之后让 `FrameProbe` 采那么多秒（`IdleFrameProbe`），报告落在 app 沙盒的
/// `Diagnostics/frames/`、标签「静置行情」，`bodies` 里就是 `MainScreen` 等视图各被求值了几次。
/// 改宿主的订阅方式前后各跑一遍、把两份报告摆在一起比。
@MainActor final class LiveTickBodyCountUITests: XCTestCase {
  func testIdleLiveMinute() throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1h"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_ROUTE_POLICY"] = "direct"
    app.launchEnvironment["KANPAN_FRAME_PROBE_IDLE"] = "60"
    app.launch()
    let source = app.staticTexts["market.source"]
    let live = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in source.exists && (source.value as? String) == "live" }, object: nil)
    XCTAssertEqual(XCTWaiter.wait(for: [live], timeout: 60), .completed, "60 秒内没等到推送 live")
    // 探针在 live 之后先静置 2 秒再采 60 秒，多等几秒让它自己停、存盘。
    Thread.sleep(forTimeInterval: 66)
    app.terminate()
  }
}
