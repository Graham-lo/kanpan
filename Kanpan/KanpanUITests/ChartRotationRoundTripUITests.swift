import XCTest

/// 第五轮审查 A.5 用例 10：**完整转屏往返**。
///
/// 报告给的序列是「三副图自定义比例 ＋ Y 变换 ＋ 根宽 ＋ 历史 T ＋ 一条线；
/// draw → landscape → portrait，600ms 内再入」，要断言的是「数量／顺序／归一化比例／
/// 根宽／t,p 不丢；旧释放不改变新锁；无面板遗留」。
///
/// 已有的 `ChartFoundationUITests.testCompactChartStylesAndRotation` 只转了一圈看阳线画法
/// 还在；`ChartLayoutPersistenceUITests` 转的是冷启动那条路。两条都没把「布局的五样东西
/// 一起带过去再带回来」量一遍，也没碰「转回去之后立刻再横过来」这个时序——
/// 而**旧的方向锁释放晚于新锁申请**正是这类页面最容易出的那个 bug：
/// 人刚横过来，上一程的释放才落地，屏幕自己转回竖的。
@MainActor final class ChartRotationRoundTripUITests: XCTestCase {
  private var app: XCUIApplication!
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30), "K 线画布没出来")
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 },
                  "K 线没拿到数据：\(info())")
  }

  override func tearDown() async throws {
    guard app.state != .notRunning, app.state != .unknown else { return }
    XCUIDevice.shared.orientation = .portrait
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    app.terminate()
  }

  private func info() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }

  private func wait(seconds: Double = 20, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name
    a.lifetime = .keepAlways; add(a)
  }

  /// 每块副图占整屏的比例。**归一化**是这条用例的重点：横屏竖屏高度不一样，
  /// 能比的只有比例，不是像素。
  private func ratios(_ snapshot: [String: Any]) throws -> [String: Double] {
    let height = try XCTUnwrap(snapshot["height"] as? Double)
    XCTAssertGreaterThan(height, 0)
    let panes = try XCTUnwrap(snapshot["panes"] as? [[String: Any]])
    var out: [String: Double] = ["MAIN": try XCTUnwrap(snapshot["mainH"] as? Double) / height]
    for pane in panes {
      out[try XCTUnwrap(pane["id"] as? String)] = try XCTUnwrap(pane["h"] as? Double) / height
    }
    return out
  }

  /// 每条线的锚点。画线存的是「时间 + 价格」，转屏一个字都不该动。
  private func anchors(_ snapshot: [String: Any]) throws -> [[[String: Double]]] {
    try XCTUnwrap(snapshot["drawingAnchors"] as? [[[String: Double]]])
  }

  /// 一根 K 线有多长（毫秒）。`to` 的容差按它来——比毫秒没有意义。
  private func step(_ snapshot: [String: Any]) throws -> Double {
    let span = try XCTUnwrap(snapshot["span"] as? Double)
    let plotW = try XCTUnwrap(snapshot["plotW"] as? Double)
    let spacing = try XCTUnwrap(snapshot["spacing"] as? Double)
    return span * spacing / plotW
  }

  private func isLandscape() -> Bool { canvas.exists && canvas.frame.width > canvas.frame.height }

  /// 等待条件里用的那一份：不抛，读不到就当 0。
  private func ratio(_ id: String) -> Double { ((try? ratios(info())) ?? [:])[id] ?? 0 }

  /// 开画线工具面板。和 `ChartFoundationUITests.openDrawTools` 一样允许再点一下：
  /// 合成事件偶尔丢一下，重试不换点，真打不开照样红。
  private func openDrawTools() {
    for _ in 0..<2 {
      app.buttons["draw.tools"].tap()
      if app.buttons["draw.sheet.done"].waitForExistence(timeout: 5) { return }
    }
    XCTFail("点了两下「工具」，画线工具面板都没上来")
  }

  // ---------------------------------------------------------------- 用例

  func testFullRotationRoundTripKeepsLayoutAndDrawings() throws {
    let origin = canvas.coordinate(withNormalizedOffset: .zero)

    // ① 三副图，把其中一条分隔线拖开，做出一份「自定义比例」。
    let start = info()
    XCTAssertEqual((start["subs"] as? [String])?.count, 3, "这条用例要的是三副图：\(start)")
    let grip = app.otherElements["chart.resize.VOL"]
    XCTAssertTrue(grip.waitForExistence(timeout: 5), "没找到 VOL 的分隔线把手")
    let gripPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: grip.frame.midX, dy: grip.frame.midY))
    let volBefore = try XCTUnwrap(ratios(start)["VOL"])
    gripPoint.press(forDuration: 0.05, thenDragTo: gripPoint.withOffset(CGVector(dx: 0, dy: 32)))
    XCTAssertTrue(wait(seconds: 5) { self.ratio("VOL") > volBefore + 0.01 },
                  "分隔线没拖动，这一跑等于没自定义过比例：\(info())")

    // ② 历史 T：往右拖，离开「最新」；等惯性停稳。
    let pan = origin.withOffset(CGVector(dx: 70, dy: 170))
    pan.press(forDuration: 0.05, thenDragTo: pan.withOffset(CGVector(dx: 170, dy: 0)))
    XCTAssertTrue(wait(seconds: 10) {
      (self.info()["to"] as? Double ?? .infinity) < (start["to"] as? Double ?? 0)
    }, "没拖成历史视野：\(info())")
    var previous = info()["to"] as? Double
    XCTAssertTrue(wait(seconds: 10) {
      let now = self.info()["to"] as? Double
      defer { previous = now }
      return now == previous
    }, "惯性一直没停")

    // ③ 根宽：捏一下。
    let beforePinch = try XCTUnwrap(info()["spacing"] as? Double)
    canvas.pinch(withScale: 1.6, velocity: 1)
    XCTAssertTrue(wait(seconds: 6) { (self.info()["spacing"] as? Double ?? 0) > beforePinch + 0.1 },
                  "捏合没改到根宽：\(info())")

    // ④ Y 变换：在价格轴上竖着拖一把，纵向进入手动。
    let width = try XCTUnwrap(info()["plotW"] as? Double)
    let axis = origin.withOffset(CGVector(dx: width + 20, dy: 140))
    axis.press(forDuration: 0.05, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -85)))
    XCTAssertTrue(wait(seconds: 6) { abs((self.info()["zoomY"] as? Double ?? 1) - 1) > 0.05 },
                  "价格轴没拖出手动纵轴：\(info())")

    // ⑤ 一条线。画线入口自己会横过去，这里用「横过去再按竖屏回来」那条常规路。
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 8), "工具面板里没有趋势线")
    app.buttons["draw.tool.trend"].tap()
    let canvasOrigin = canvas.coordinate(withNormalizedOffset: .zero)
    canvasOrigin.withOffset(CGVector(dx: 90, dy: 120)).tap()
    canvasOrigin.withOffset(CGVector(dx: 230, dy: 200)).tap()
    XCTAssertTrue(wait(seconds: 8) { self.info()["drawingCount"] as? Int == 1 },
                  "趋势线没画上：\(info())")
    app.buttons["draw.finish"].tap()
    XCTAssertTrue(wait(seconds: 8) { !self.app.buttons["draw.finish"].exists }, "没退出画线态")

    let before = info()
    let ratiosBefore = try ratios(before)
    let anchorsBefore = try anchors(before)
    XCTAssertEqual(anchorsBefore.count, 1)
    shot("转屏往返-出发时的竖屏")

    // ---------------------------------------------------------------- 转一圈

    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(seconds: 10) { self.isLandscape() }, "没转成横屏")
    shot("转屏往返-横屏")
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(wait(seconds: 10) { !self.isLandscape() }, "没转回竖屏")

    // **600ms 内再入。** 上一程的方向锁这时多半还在释放路上；新锁必须压得住它，
    // 不然用户刚横过来屏幕自己就转回去了。
    Thread.sleep(forTimeInterval: 0.4)
    XCTAssertTrue(app.tapDrawEntry(), "没点到底栏的「画线」")
    XCTAssertTrue(wait(seconds: 10) { self.isLandscape() }, "600ms 内再入没横过来")
    // 横着待满一秒半：旧锁的释放要是会动新锁，这一秒半里它就会自己转回去。
    let deadline = Date().addingTimeInterval(1.5)
    while Date() < deadline {
      XCTAssertTrue(isLandscape(), "旧的方向释放把刚立起来的新锁掀了：屏幕自己转回竖屏")
      Thread.sleep(forTimeInterval: 0.25)
    }
    shot("转屏往返-快速再入")

    let exit = app.buttons["land.exit"]
    XCTAssertTrue(exit.waitForExistence(timeout: 10), "横屏没有回竖屏的出口")
    exit.tap()
    XCTAssertTrue(wait(seconds: 10) { !self.isLandscape() }, "按「竖屏」没回来")
    if app.buttons["draw.finish"].waitForExistence(timeout: 5) { app.buttons["draw.finish"].tap() }
    XCTAssertTrue(wait(seconds: 8) { !self.app.buttons["draw.finish"].exists })

    // ---------------------------------------------------------------- 回来之后

    let after = info()
    XCTAssertEqual(after["subs"] as? [String], before["subs"] as? [String], "副图的数量或顺序变了")
    let ratiosAfter = try ratios(after)
    for (id, want) in ratiosBefore {
      XCTAssertEqual(try XCTUnwrap(ratiosAfter[id]), want, accuracy: 0.02, "\(id) 的归一化比例没带回来")
    }
    XCTAssertEqual(try XCTUnwrap(after["spacing"] as? Double),
                   try XCTUnwrap(before["spacing"] as? Double), accuracy: 0.2, "根宽丢了")
    XCTAssertEqual(try XCTUnwrap(after["to"] as? Double),
                   try XCTUnwrap(before["to"] as? Double), accuracy: try step(before),
                   "历史右缘漂了不止一根")
    XCTAssertEqual(try XCTUnwrap(after["zoomY"] as? Double),
                   try XCTUnwrap(before["zoomY"] as? Double), accuracy: 0.01, "手动纵轴的倍率丢了")
    XCTAssertEqual(try XCTUnwrap(after["centerY"] as? Double),
                   try XCTUnwrap(before["centerY"] as? Double), accuracy: 0.02, "手动纵轴的中心漂了")
    XCTAssertEqual(after["mode"] as? String, before["mode"] as? String)
    XCTAssertEqual(after["inverted"] as? Bool, before["inverted"] as? Bool)

    let anchorsAfter = try anchors(after)
    XCTAssertEqual(anchorsAfter.count, anchorsBefore.count, "线的条数变了")
    for (i, points) in anchorsBefore.enumerated() {
      XCTAssertEqual(anchorsAfter[i].count, points.count)
      for (j, p) in points.enumerated() {
        XCTAssertEqual(try XCTUnwrap(anchorsAfter[i][j]["t"]), try XCTUnwrap(p["t"]), accuracy: 1,
                       "第 \(i) 条线第 \(j) 个锚点的时间变了")
        XCTAssertEqual(try XCTUnwrap(anchorsAfter[i][j]["p"]), try XCTUnwrap(p["p"]), accuracy: 1e-6,
                       "第 \(i) 条线第 \(j) 个锚点的价格变了")
      }
    }
    XCTAssertEqual(after["drawingIDs"] as? [String], before["drawingIDs"] as? [String])

    // 无面板遗留：转了两圈之后，屏幕上不许还压着半屏面板、工具卡片或横屏工具栏。
    XCTAssertFalse(app.staticTexts["panel.header"].exists, "回来之后还压着一张半屏面板")
    XCTAssertFalse(app.buttons["draw.sheet.done"].exists, "画线工具面板没收走")
    XCTAssertFalse(app.buttons["land.exit"].exists, "竖屏里还留着横屏工具栏")
    XCTAssertTrue(app.buttons["interval.chart"].isHittable, "回到竖屏之后周期条该照常能点")
    shot("转屏往返-回到竖屏")
  }
}
