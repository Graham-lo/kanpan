import XCTest

/// 图表设置面板的头一层要一屏放得下（审查 U4 / U5）。
///
/// 原来这一页十七八行、要滚三屏，一调就不再动的开关和每天都碰的挤在一起。现在头一层
/// 只留这张图的动作、画法、实时价格线、盘口、价格轴，其余收进最后一行
/// 「更多设置」推进去的那一层；「‹」从里层回来不关面板。
///
/// 2026-09-27 底栏四格：「对比」整节和「指标」那一行搬进了指标页（周期条行尾「指标」直达），
/// 头一层只剩 这张图 · K 线 · 显示 · 价格轴 四组。
@MainActor final class ChartPanelLayoutUITests: XCTestCase {
  private var app: XCUIApplication!
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch()
    let chartTab = app.buttons["bottom.chart"]
    if chartTab.waitForExistence(timeout: 5), !canvas.exists { chartTab.tap() }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30), "K 线画布没出来")
  }

  override func tearDown() async throws {
    guard app.state != .notRunning, app.state != .unknown else { return }
    app.terminate()
  }

  private func shot(_ name: String) {
    try? FileManager.default.createDirectory(atPath: "/tmp/kanpan-laneg-shots", withIntermediateDirectories: true)
    try? XCUIScreen.main.screenshot().pngRepresentation
      .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/\(name).png"))
  }

  func testFirstLayerFitsOneScreenAndMoreIsPushed() throws {
    let entry = app.buttons["interval.chart"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "周期条尾巴上没有图表设置入口")
    entry.tap()
    let more = app.buttons["chart.more"]
    XCTAssertTrue(more.waitForExistence(timeout: 8), "头一层最后没有「更多设置」")
    shot("U4-图表设置-头一层-半屏")
    // 面板先以半屏停着；往上拉到整屏后，不滚内容就看得见最后一行：
    // 它的框整个落在窗口里，而且点得到。原来十九行，整屏也要再滚一屏多。
    // 面板内容只滚自己（`presentationContentInteraction(.scrolls)`），改尺寸要拖把手。
    let header = app.staticTexts["panel.header"].frame
    let root = app.coordinate(withNormalizedOffset: .zero)
    root.withOffset(CGVector(dx: header.midX, dy: header.midY))
      .press(forDuration: 0.1, thenDragTo: root.withOffset(CGVector(dx: header.midX, dy: 40)))
    let window = app.windows.firstMatch.frame
    let fits = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      window.contains(more.frame) }, object: nil)], timeout: 5) == .completed
    XCTAssertTrue(fits, "拉到整屏后「更多设置」仍在屏幕外，头一层还要滚：\(more.frame) / \(window)")
    XCTAssertTrue(more.isHittable, "「更多设置」点不到")
    // 头一层四组：这张图 · K 线 · 显示 · 价格轴（2026-09-27）。
    for title in ["这张图", "K 线", "显示", "价格轴"] {
      XCTAssertTrue(app.staticTexts[title].exists, "头一层少了「\(title)」这一组")
    }
    for id in ["chart.record", "chart.share", "chart.lastLine", "chart.depth", "chart.priceMode.线性", "chart.priceMode.对数", "chart.priceMode.百分比"] {
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 不在头一层")
    }
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "chart.candleKind.")).firstMatch.exists,
                  "头一层没有「画法」分段")
    // 「指标」那一行和「对比」整节已经搬进指标页，这一页不该再有。
    for id in ["chart.indicators", "compare.add", "compare.clear"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 还在图表设置里")
    }
    // 低频开关不在头一层。
    for id in ["chart.allowMainInversion", "chart.allowSubInversion", "chart.countdown", "chart.sinceChange"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 还在头一层")
    }
    shot("U4-图表设置-头一层-整屏")

    more.tap()
    let flip = app.buttons["chart.allowMainInversion"]
    XCTAssertTrue(flip.waitForExistence(timeout: 8), "「更多设置」没推进去")
    for id in ["chart.countdown", "chart.sinceChange", "chart.crossPrice.收盘价"] {
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 不在「更多设置」里")
    }
    shot("U4-图表设置-更多设置")

    // 「‹」回头一层，面板还开着；再点一次才收。
    app.buttons["panel.done"].tap()
    XCTAssertTrue(more.waitForExistence(timeout: 5), "从「更多设置」退回来没回到头一层")
    app.buttons["panel.done"].tap()
    XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: more)],
                                 timeout: 8) == .completed, "头一层的「‹」没收面板")
  }
}
