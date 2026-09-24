import XCTest

// M5 A5.8：自选加、删、拖排序，杀掉 app 重开之后都还在。
//
// 不走 `KANPAN_INSTALL_USER_FAVORITES` 那条手动工具（它写的是这台设备上用户正式的自选），
// 而是给这一趟一个独立的持久化档案（`KANPAN_PERSISTENCE_PROFILE` 是一个裸 UUID，
// app 才会给它单开一棵目录）：自选落盘走的是和正式包同一条账号目录下的 `symbols.json`，
// 只是换了一个档案目录，跑完不碰任何真数据。
//
// 必须同时给 `KANPAN_ACCOUNT_API_URL`：测试档里没有它时 app 不建账号桥
// （`MainScreen` 那条 DEBUG 岔路），自选只落在 `MemoryPrefsStorage` 里，
// 重开必然全丢——那测的是内存仓，不是用户手上那条落盘路径。给了它，
// 访客照样走 `accounts/tests/<uuid>/<访客批次>/symbols.json`；这一趟不登录、
// 不建账号，接口地址只是让桥建起来。
@MainActor
final class FavoritesSurviveRestartUITests: KanpanUICase {

  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_ACCOUNT_API_URL": "https://kanpan.107-174-172-10.sslip.io"]
  }

  private func row(_ symbol: String) -> XCUIElement { app.buttons["favorites.open." + testInstrumentKey(symbol)] }

  private func addFavorite(_ symbol: String) {
    app.buttons["favorites.add"].tap()
    let query = app.textFields[Ids.searchQuery]
    XCTAssertTrue(query.waitForExistence(timeout: Self.long), "自选页的「加」没开出搜索页")
    query.tap()
    query.typeText(symbol)
    let star = app.buttons["symbols.star." + testInstrumentKey(symbol)]
    XCTAssertTrue(star.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行")
    if star.label == "加入自选" { star.tap() }
    XCTAssertTrue(waitUntil(timeout: 5) { star.label != "加入自选" }, "\(symbol) 的星没点亮")
    app.buttons["search.cancel"].tap()
    XCTAssertTrue(row(symbol).waitForExistence(timeout: Self.long), "加完 \(symbol) 自选页上没有它")
  }

  func testAddRemoveReorderSurviveRestart() throws {
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    for symbol in ["ETHUSDT", "SOLUSDT", "DOGEUSDT"] { addFavorite(symbol) }

    // 删：左滑出「取消自选」再点（右滑 2026-09-24 起不响应，见 4f400127）
    let sol = row("SOLUSDT")
    sol.swipeLeft()
    let remove = app.buttons["取消自选"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5), "左滑没出「取消自选」")
    remove.tap()
    XCTAssertTrue(waitUntil(timeout: 5) { !sol.exists }, "SOLUSDT 删不掉")

    // 排：长按下面那一行拖到上面那一行的位置
    let eth = row("ETHUSDT"), doge = row("DOGEUSDT")
    let ethOnTop = eth.frame.minY < doge.frame.minY
    let (upper, lower) = ethOnTop ? (eth, doge) : (doge, eth)
    let upperY = upper.frame.minY
    let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: lower.frame.midX, dy: lower.frame.midY)).press(
      forDuration: 1, thenDragTo: origin.withOffset(CGVector(dx: upper.frame.midX, dy: upper.frame.minY)),
      withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(waitUntil(timeout: 5) { lower.frame.minY < upper.frame.minY }, "长按拖动没改动顺序")
    let first = ethOnTop ? "DOGEUSDT" : "ETHUSDT", second = ethOnTop ? "ETHUSDT" : "DOGEUSDT"
    XCTAssertLessThan(lower.frame.minY, upperY + 1)
    shot("自选-加删排之后")

    // 落盘有一拍防抖；给它时间再杀
    _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: 3)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.openFavorites(), "重开之后进不了自选页")
    XCTAssertTrue(row(first).waitForExistence(timeout: Self.long), "重开之后 \(first) 不在自选里")
    XCTAssertTrue(row(second).exists, "重开之后 \(second) 不在自选里")
    XCTAssertFalse(row("SOLUSDT").exists, "删掉的 SOLUSDT 重开之后又回来了")
    XCTAssertLessThan(row(first).frame.minY, row(second).frame.minY, "重开之后拖出来的顺序没保住")
    shot("自选-重开之后")
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
