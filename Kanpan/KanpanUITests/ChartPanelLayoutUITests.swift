import XCTest

/// 图表设置面板的头一层要一屏放得下（审查 U4 / U5）。
///
/// 原来这一页十七八行、要滚三屏，一调就不再动的开关和每天都碰的挤在一起。后来头一层
/// 只留这张图的动作、画法、实时价格线、盘口、价格轴，其余收进「更多设置」那一层。
///
/// 2026-09-27 底栏四格：「对比」整节和「指标」那一行搬进了指标页（周期条行尾「指标」直达），
/// 头一层只剩 这张图 · K 线 · 显示 · 价格轴 四组。
/// 2026-09-28「收设置项」B 组：「更多设置」那一层和「实时价格线」整个收掉，面板只剩一层，
/// 那些开关都成了定值（见 `Prefs.chartOptions`）。
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

  func testSingleLayerFitsOneScreen() throws {
    let entry = app.buttons["interval.chart"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "周期条尾巴上没有图表设置入口")
    entry.tap()
    let last = app.buttons["chart.priceMode.百分比"]
    XCTAssertTrue(last.waitForExistence(timeout: 8), "最后一组没有「价格轴 · 刻度」")
    shot("U4-图表设置-半屏")
    // 面板以半屏停着，不滚内容就看得见最后一行：它的框整个落在窗口里，而且点得到。
    let window = app.windows.firstMatch.frame
    let fits = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
      window.contains(last.frame) }, object: nil)], timeout: 5) == .completed
    XCTAssertTrue(fits, "「价格轴 · 刻度」在屏幕外，面板还要滚：\(last.frame) / \(window)")
    XCTAssertTrue(last.isHittable, "「价格轴 · 刻度」点不到")
    // 三组：K 线 · 显示 · 价格轴（2026-09-28 顶栏方案 B 起「这张图」整节搬到顶栏）。
    for title in ["K 线", "显示", "价格轴"] {
      XCTAssertTrue(app.staticTexts[title].exists, "面板少了「\(title)」这一组")
    }
    XCTAssertFalse(app.staticTexts["这张图"].exists, "图表设置里还有「这张图」")
    for id in ["chart.record", "chart.share"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 还在面板上")
    }
    for id in ["chart.depth", "chart.priceMode.线性", "chart.priceMode.对数", "chart.priceMode.百分比"] {
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 不在面板上")
    }
    XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "chart.candleKind.")).firstMatch.exists,
                  "面板上没有「画法」分段")
    // 每一格都要够手指点：面板里 44pt 高（HIG）。iOS 26 半屏的浮起面板整张按约 0.96 缩着画，
    // 窗口坐标里量到的是 44 × 0.96 ≈ 42.2，所以按 42 判（再小就是真的不到 44 了）。
    for id in ["chart.depth", "chart.priceMode.线性", "chart.candleKind.蜡烛"] {
      let e = app.buttons[id]
      XCTAssertGreaterThanOrEqual(e.frame.height, 42, "\(id) 命中区不到 44pt：\(e.frame)")
    }
    // 「指标」那一行与「对比」整节在分析面板（「对比」另有顶栏「⋯ › 添加对比」），图表设置这一页不该再有；
    // 「更多设置」和它里面那些开关、「实时价格线」2026-09-28 收掉了，也不许回来。
    for id in ["chart.indicators", "compare.add", "compare.clear", "chart.more", "chart.lastLine",
               "chart.allowMainInversion", "chart.allowSubInversion", "chart.countdown", "chart.sinceChange",
               "chart.gridChoice", "chart.viewAnchor", "chart.priceBias"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 还在图表设置里")
    }
    for prefix in ["chart.bodyChoice.", "chart.dataDisplay.", "chart.crossPrice.", "chart.gridChoice.",
                   "chart.viewAnchor.", "chart.priceBias."] {
      XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.exists,
                     "\(prefix)* 还在图表设置里")
    }
    for text in ["更多设置", "实时价格线", "阳线", "网格"] {
      XCTAssertFalse(app.staticTexts[text].exists, "「\(text)」还在图表设置里")
    }

    // 「完成」一下就收。
    app.buttons["panel.done"].tap()
    XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: last)],
                                 timeout: 8) == .completed, "「完成」没收面板")
  }
}
