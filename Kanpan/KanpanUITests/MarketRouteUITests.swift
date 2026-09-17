import XCTest

// ============================================================ 行情线路（设置）
//
// 设置页里的「行情线路」两档：直连 / 网关，出厂默认直连，没有「自动」。
// 选了哪条就走哪条。它存在 `Prefs.routePolicy` 里：登录了随账号同步，没登录就记在
// 本机的访客档案里——所以这里给用例一份自己的持久档案，杀掉重开还能读回来，
// 又不会碰到这台真机上真实用户的设置。

@MainActor
final class MarketRouteUITests: KanpanUICase {

  /// 一份只属于这次运行的 Prefs 档案：杀掉重开还能读回「网关」，又不碰真实用户的设置。
  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": profile] }

  private func route(_ title: String) -> XCUIElement { app.buttons["settings.routePolicy.\(title)"] }

  private func openSettings() {
    app.buttons[Ids.bottomSettings].tap()
    expectExists(route("直连"), Self.short, "设置页里没有「行情线路」的「直连」")
    expectExists(route("网关"), Self.short, "设置页里没有「行情线路」的「网关」")
    XCTAssertFalse(app.buttons["settings.routePolicy.自动"].exists, "「自动」档应该已经没有了")
  }

  /// 两档都在、出厂是「直连」；点「网关」立刻选中；杀掉重开还是「网关」；再点回「直连」。
  func testRoutePolicyRowSwitchesAndPersists() {
    openSettings()
    XCTAssertTrue(route("直连").isSelected, "出厂默认应该是「直连」")
    XCTAssertFalse(route("网关").isSelected, "出厂时「网关」不该亮着")
    route("网关").tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("网关").isSelected }, "点了「网关」没选中")
    XCTAssertFalse(route("直连").isSelected, "「网关」选中后「直连」还亮着")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "行情线路-网关"; shot.lifetime = .keepAlways
    add(shot)

    app.terminate()
    app.launch()
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: Self.long), "重开后没见到主界面")
    openSettings()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("网关").isSelected }, "重开后「行情线路」没记住「网关」")
    route("直连").tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { route("直连").isSelected }, "点回「直连」没选中")
    leaveSettings()
  }

  /// 「直连」下 OKX 永远不会被启用，所以只要图活着、有最新一根，就是币安直连真的通了。
  /// 这条要真网络：这台真机上的网络本来就能直连币安，用例守的就是这一点。
  /// 出厂就是直连，不用去设置里点——用例守的正是「什么都不设就走直连」。
  func testDirectRouteGetsLiveBinanceChart() {
    openSettings()
    XCTAssertTrue(route("直连").isSelected, "出厂默认应该是「直连」")
    leaveSettings()
    XCTAssertTrue(waitForLiveChart(), "「直连」下 \(Self.long)s 内没等到币安的 K 线")
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "直连-币安K线"; shot.lifetime = .keepAlways
    add(shot)
  }
}
