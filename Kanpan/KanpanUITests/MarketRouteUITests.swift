import XCTest

// ============================================================ 行情线路（设置）
//
// 设置面板里的「行情线路」三档：自动 / 直连 / 网关。它是给「自己网络本来就能
// 直连币安、却被自动探测误判到 OKX」的机器留的手动开关，存在 `UserDefaults.standard`
// 的 `market.routePolicy` 里，不走测试用的 Prefs 档案——所以这条用例最后停在
// 「直连」上，就是让这台真机之后真的按直连走。

@MainActor
final class MarketRouteUITests: KanpanUICase {

  private func route(_ title: String) -> XCUIElement { app.buttons["settings.routePolicy.\(title)"] }

  private func openSettings() {
    app.buttons[Ids.bottomSettings].tap()
    expectExists(route("自动"), Self.short, "设置面板里没有「行情线路」的「自动」")
    expectExists(route("直连"), Self.short, "设置面板里没有「行情线路」的「直连」")
    expectExists(route("网关"), Self.short, "设置面板里没有「行情线路」的「网关」")
  }

  /// 三档都在；点「直连」立刻选中；杀掉重开还是「直连」。
  func testRoutePolicyRowSwitchesAndPersists() {
    openSettings()
    route("直连").tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("直连").isSelected }, "点了「直连」没选中")
    XCTAssertFalse(route("自动").isSelected, "「直连」选中后「自动」还亮着")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "行情线路-直连"; shot.lifetime = .keepAlways
    add(shot)

    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons[Ids.symbolButton].waitForExistence(timeout: Self.long), "重开后没见到主界面")
    openSettings()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("直连").isSelected }, "重开后「行情线路」没记住「直连」")
    dismissSheet(until: route("直连"))
  }

  /// 「直连」下 OKX 永远不会被启用，所以只要图活着、有最新一根，就是币安直连真的通了。
  /// 这条要真网络：这台真机上的网络本来就能直连币安，用例守的就是这一点。
  func testDirectRouteGetsLiveBinanceChart() {
    openSettings()
    route("直连").tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("直连").isSelected }, "点了「直连」没选中")
    dismissSheet(until: route("直连"))
    XCTAssertTrue(waitForLiveChart(), "「直连」下 \(Self.long)s 内没等到币安的 K 线")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "直连-币安K线"; shot.lifetime = .keepAlways
    add(shot)
  }
}
