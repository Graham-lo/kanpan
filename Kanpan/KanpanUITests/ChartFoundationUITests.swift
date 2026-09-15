import XCTest

@MainActor
final class ChartFoundationUITests: XCTestCase {
  var app: XCUIApplication!
  var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    if name.contains("testInstallRequestedFavoritesInUserStore") || name.contains("testUserSession") { return }
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    if name.contains("Drawing") || name.contains("IndicatorColor") || name.contains("CompactChart") || name.contains("ReviewButton") { app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString }
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    if name.contains("ReviewButton") { app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io" }
    app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, String(describing: info()))
  }
  override func tearDown() async throws {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.lifetime = .keepAlways; add(attachment)
    if (testRun?.failureCount ?? 0) > 0 {
      let state = canvas.exists ? String(describing: canvas.value) : "Chart is covered by another page"
      let tree = XCTAttachment(string: app.debugDescription + "\nChart state: " + state); tree.lifetime = .keepAlways; add(tree)
    }
    app.terminate()
  }
  func info() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
  func wait(seconds: Double = 40, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
  }
  func closePanel() {
    let header = app.staticTexts["panel.header"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
    start.press(forDuration: 0.05, thenDragTo: end)
    XCTAssertTrue(wait { !header.exists })
  }
  func selectMain() {
    let h = info()["mainH"] as? Double ?? 300
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: min(130, h / 2))).tap()
  }
  func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  func testReviewButtonDragPersistsInsideMainPane() throws {
    let button = app.buttons["review.record"]
    XCTAssertTrue(button.waitForExistence(timeout: 10))
    let span = try XCTUnwrap(info()["span"] as? Double)
    let target = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 70, dy: 80))
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: target)
    XCTAssertTrue(wait(seconds: 3) { abs(button.frame.midX - target.screenPoint.x) < 8 && abs(button.frame.midY - target.screenPoint.y) < 8 })
    XCTAssertEqual(try XCTUnwrap(info()["span"] as? Double), span, accuracy: 0.001)
    let saved = button.frame
    XCTAssertLessThan(saved.maxY, canvas.frame.minY + (try XCTUnwrap(info()["mainH"] as? Double)))
    shot("记按钮-拖动后主图内")
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(button.waitForExistence(timeout: 30))
    XCTAssertEqual(button.frame.midX, saved.midX, accuracy: 2)
    XCTAssertEqual(button.frame.midY, saved.midY, accuracy: 2)
    let outside = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.95))
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: outside)
    XCTAssertLessThan(button.frame.maxY, canvas.frame.minY + (try XCTUnwrap(info()["mainH"] as? Double)))
    shot("记按钮-副图边界限位")
  }

  func testHeightAndVerticalReachability() throws {
    let original = info()
    app.buttons["interval.chart"].tap()
    let slider = app.sliders["chart.portraitHeight"]
    XCTAssertTrue(slider.waitForExistence(timeout: 5))
    slider.adjust(toNormalizedSliderPosition: 1)
    closePanel()
    XCTAssertTrue(wait(seconds: 3) { (self.info()["portraitHeight"] as? Double ?? 0) > (original["portraitHeight"] as? Double ?? 0) + 0.2 }, String(describing: info()))
    XCTAssertGreaterThan(try XCTUnwrap(info()["mainH"] as? Double), try XCTUnwrap(original["mainH"] as? Double))
    for key in ["from", "span", "plotW", "spacing"] {
      XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double), accuracy: 0.001)
    }
    shot("高度调高-主副图内容")
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    XCTAssertEqual(info()["scrollY"] as? Double, 0)
    shot("高度调高-一屏主副图")
  }

  func testResizeDividerWithinOneScreen() throws {
    let original = info()
    let grip = app.otherElements["chart.resize.VOL"]
    XCTAssertTrue(grip.waitForExistence(timeout: 5))
    let before = try XCTUnwrap(Double(grip.value as? String ?? ""))
    let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: grip.frame.midX, dy: grip.frame.midY))
    from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 35)))
    XCTAssertTrue(wait(seconds: 3) { (Double(grip.value as? String ?? "") ?? 0) > before + 15 }, String(describing: info()))
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    for key in ["from", "span", "plotW", "spacing"] {
      XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double), accuracy: 0.001)
    }
    shot("一屏三副图-手动边界调整")
  }

  func testCrosshairCenterDragAndOutsidePan() throws {
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    selectMain()
    let selected = info()
    let center = origin.withOffset(CGVector(dx: try XCTUnwrap(selected["crossX"] as? Double), dy: try XCTUnwrap(selected["crossY"] as? Double)))
    center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 50, dy: 10)))
    XCTAssertTrue(wait { self.info()["crossIndex"] as? Int != selected["crossIndex"] as? Int })
    XCTAssertEqual(try XCTUnwrap(info()["from"] as? Double), try XCTUnwrap(selected["from"] as? Double), accuracy: 1)
    let away = origin.withOffset(CGVector(dx: 45, dy: 100))
    away.press(forDuration: 0.05, thenDragTo: away.withOffset(CGVector(dx: 100, dy: 0)))
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertLessThan(try XCTUnwrap(info()["from"] as? Double), try XCTUnwrap(selected["from"] as? Double))
    shot("十字中心移线-其它区域拖图")
  }

  func testDragIndicatorTitleReordersCompletePane() throws {
    let original = info()
    let panes = try XCTUnwrap(original["panes"] as? [[String: Any]])
    let y = try XCTUnwrap(panes[0]["y"] as? Double)
    let lastY = try XCTUnwrap(panes[2]["y"] as? Double)
    let lastH = try XCTUnwrap(panes[2]["h"] as? Double)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: (original["plotW"] as? Double ?? 300) / 2, dy: y + (panes[0]["h"] as? Double ?? 80) / 2)).press(forDuration: 0.5,
      thenDragTo: origin.withOffset(CGVector(dx: 150, dy: lastY + lastH / 2)))
    XCTAssertTrue(wait { self.info()["subs"] as? [String] == ["OI", "MACD", "VOL"] }, String(describing: info()))
    XCTAssertEqual(info()["crosshair"] as? Bool, false)
    for key in ["from", "span", "plotW", "spacing", "height"] {
      XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double), accuracy: 0.001)
    }
    shot("区域长按拖动-整块副图换序")
  }

  func testLiveMarketUpdatesWithinSeconds() throws {
    var samples: [[String: Double]] = []
    let start = Date()
    XCTAssertTrue(wait(seconds: 12) {
      let info = self.info()
      guard let close = info["lastClose"] as? Double, let volume = info["lastVolume"] as? Double else { return false }
      if samples.last?["close"] != close || samples.last?["volume"] != volume {
        samples.append(["seconds": Date().timeIntervalSince(start), "close": close, "volume": volume])
      }
      return samples.count >= 5
    }, "12 秒内应至少观测到 5 份不同 OHLCV，不能只靠 5–10 秒 REST 轮询")
    let a = XCTAttachment(string: String(describing: samples)); a.name = "实时行情变化采样"; a.lifetime = .keepAlways; add(a)
    shot("实时行情-持续更新")
  }

  func testHistoricalOIUsesChartPeriod() throws {
    let day = app.buttons["interval.chip.1d"]
    XCTAssertTrue(day.waitForExistence(timeout: 5))
    let quick = app.scrollViews["interval.quick"]
    for _ in 0..<4 {
      if day.isHittable, quick.frame.contains(day.frame) { break }
      quick.swipeLeft()
    }
    day.tap()
    XCTAssertTrue(wait(seconds: 90) {
      self.info()["interval"] as? String == "1d" && self.info()["oiPeriod"] as? String == "1d" &&
      (self.info()["oiTimes"] as? [Double] ?? []).count > 35
    }, String(describing: info()))
    let times = try XCTUnwrap(info()["oiTimes"] as? [Double])
    XCTAssertTrue(times.allSatisfy { $0.truncatingRemainder(dividingBy: 86_400_000) == 0 })
    XCTAssertLessThan(try XCTUnwrap(times.first), Date().timeIntervalSince1970 * 1000 - 30 * 86_400_000)
    shot("日线OI-历史周期对齐")
  }

  func testTradFiSearchAndMarketData() throws {
    for symbol in ["SNDKUSDT", "SKHYUSDT", "MUUSDT"] {
      app.buttons["top.search"].tap()
      let query = app.textFields["symbols.query"]
      XCTAssertTrue(query.waitForExistence(timeout: 5))
      query.tap()
      if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
      }
      query.typeText(symbol)
      let row = app.descendants(matching: .any).matching(identifier: "symbols.row." + symbol).firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: 30), "未找到\(symbol)")
      row.tap()
      XCTAssertTrue(wait(seconds: 45) {
        self.info()["symbol"] as? String == symbol && (self.info()["bars"] as? Int ?? 0) > 20 &&
        (self.info()["lastClose"] as? Double ?? 0) > 0
      }, String(describing: info()))
      shot("TradFi-" + symbol)
    }
  }

  func testFavoritesCategoriesAndNavigation() throws {
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.add"].waitForExistence(timeout: 5))
    favoritesAction("favorites.newGroup")
    let name = app.alerts.textFields["分类名称"]
    XCTAssertTrue(name.waitForExistence(timeout: 5)); name.typeText("半导体")
    app.alerts.buttons["保存"].tap()
    app.buttons["favorites.add"].tap()
    let query = app.textFields["symbols.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("SNDKUSDT")
    let result = app.descendants(matching: .any).matching(identifier: "symbols.row.SNDKUSDT").firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30)); result.tap()
    let row = app.buttons["favorites.open.SNDKUSDT"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    app.buttons["favorites.expand.SNDKUSDT"].tap()
    let move = app.buttons["favorites.move.SNDKUSDT"]
    XCTAssertTrue(move.waitForExistence(timeout: 5))
    move.tap()
    let destination = app.buttons["半导体"]
    XCTAssertTrue(wait { destination.exists && destination.isHittable })
    destination.tap()
    XCTAssertTrue(wait(seconds: 3) { !row.exists })
    app.buttons["favorites.group.半导体"].tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5)); shot("独立自选页-分类与品种")
    row.tap()
    XCTAssertTrue(wait(seconds: 45) { self.info()["symbol"] as? String == "SNDKUSDT" })
    XCTAssertTrue(app.buttons["interval.draw"].exists)
    XCTAssertFalse(app.buttons["bottom.draw"].exists)
  }

  func testColdLaunchFavoritesAndLiveQuotes() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    let price = app.staticTexts["favorites.price.BTCUSDT"]
    let change = app.staticTexts["favorites.change.BTCUSDT"]
    XCTAssertTrue(wait(seconds: 30) { price.exists && price.label != "—" && change.exists && change.label.contains("%") })
    var values = Set<String>()
    XCTAssertTrue(wait(seconds: 15) {
      if price.exists { values.insert(price.label) }
      return values.count >= 2
    }, "自选价格未连续刷新")
    shot("冷启动自选-实时价格与涨跌幅")
    app.buttons["favorites.open.BTCUSDT"].tap()
    XCTAssertTrue(app.buttons["bottom.favorites"].waitForExistence(timeout: 8))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.buttons["bottom.favorites"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["favorites.more"].exists, "普通前后台切换不重置首页")
  }

  func testChangeBasisUpdatesFavorites() throws {
    app.buttons["bottom.settings"].tap()
    let basis = app.buttons["settings.changeBasis"]
    XCTAssertTrue(basis.waitForExistence(timeout: 5)); basis.tap()
    let option = app.buttons["上海8点 / UTC 0点"]
    XCTAssertTrue(wait { option.exists && option.isHittable }); option.tap()
    closePanel()
    app.buttons["bottom.favorites"].tap()
    app.buttons["favorites.add"].tap()
    let query = app.textFields["symbols.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap(); query.typeText("BTCUSDT")
    let result = app.descendants(matching: .any).matching(identifier: "symbols.row.BTCUSDT").firstMatch
    XCTAssertTrue(result.waitForExistence(timeout: 30)); result.tap()
    XCTAssertTrue(app.buttons.containing(.staticText, identifier: "8点涨跌幅").firstMatch.waitForExistence(timeout: 5))
    let change = app.staticTexts["favorites.change.BTCUSDT"]
    XCTAssertTrue(wait(seconds: 40) { change.exists && change.label.contains("%") })
    shot("自选-上海8点统一涨跌幅")
  }

  func testFavoritesBatchEditing() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.edit")
    let btc = app.buttons["favorites.open.BTCUSDT"]
    let sndk = app.buttons["favorites.open.SOLUSDT"]
    let before = btc.frame.minY
    let quote = app.staticTexts["favorites.price.BTCUSDT"]
    var previousFrame = quote.frame
    var stableFrames = 0
    XCTAssertTrue(wait(seconds: 5) {
      let frame = quote.frame
      stableFrames = frame == previousFrame ? stableFrames + 1 : 0
      previousFrame = frame
      return stableFrames >= 2
    }, "等待进入编辑的系统控件布局完成")
    let frozenPrice = quote.label, frozenFrame = quote.frame
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
      XCTAssertEqual(quote.label, frozenPrice, "编辑期间报价冻结，退出后恢复实时")
      XCTAssertEqual(quote.frame, frozenFrame, "编辑右侧报价不能随WS抖动")
    }
    let source = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY))
    source.press(forDuration: 0.6, thenDragTo: source.withOffset(CGVector(dx: 0, dy: sndk.frame.midY - btc.frame.midY + 10)))
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > before + 30 }, "编辑拖动应移动完整品种行")
    app.buttons["favorites.open.BTCUSDT"].tap()
    app.buttons["favorites.open.ETHUSDT"].tap()
    XCTAssertFalse(app.buttons["置顶"].exists)
    app.buttons["favorites.open.BTCUSDT"].tap()
    let remove = app.buttons["删除"]
    XCTAssertTrue(remove.isEnabled); remove.tap()
    XCTAssertFalse(app.buttons["favorites.open.ETHUSDT"].exists)
    XCTAssertTrue(app.buttons["favorites.open.BTCUSDT"].exists)
    XCTAssertTrue(app.buttons["favorites.open.SOLUSDT"].exists)
    favoritesAction("favorites.edit")
    shot("自选-选择与删除")
  }

  func testFavoritesDirectRowReorder() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT"
    app.launch()
    let btc = app.buttons["favorites.open.BTCUSDT"]
    let sol = app.buttons["favorites.open.SOLUSDT"]
    XCTAssertTrue(btc.waitForExistence(timeout: 15))
    XCTAssertTrue(sol.waitForExistence(timeout: 5))
    // Freeze screen coordinates before List rearranges its cells. Drop beyond the
    // last row, allowing the native insertion animation to finish before release.
    let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
    let start = origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY))
    let end = origin.withOffset(CGVector(dx: sol.frame.midX, dy: sol.frame.maxY + 20))
    start.press(forDuration: 1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > sol.frame.minY }, "普通状态长按整行应直接排序")
    shot("自选-无需编辑长按整行排序")
  }

  func testFavoritesRightSwipeRemove() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    let btc = app.buttons["favorites.open.BTCUSDT"]
    XCTAssertTrue(btc.waitForExistence(timeout: 15))
    btc.swipeRight()
    let remove = app.buttons["删除自选"]
    XCTAssertTrue(remove.waitForExistence(timeout: 5))
    XCTAssertTrue(btc.exists, "右滑仅显示操作，不能自动删除")
    remove.tap()
    XCTAssertTrue(wait(seconds: 5) { !btc.exists })
    XCTAssertTrue(app.buttons["favorites.open.ETHUSDT"].exists)
    shot("自选-右滑选择删除")
  }

  /// 仅用户明确要求写入正式自选时单独运行；常规回归保持跳过。
  func testInstallRequestedFavoritesInUserStore() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] == "1")
    app.terminate()
    app.launchEnvironment.removeValue(forKey: "KANPAN_TEST_PROFILE")
    app.launchEnvironment.removeValue(forKey: "KANPAN_TEST_FAVORITES")
    app.launch()
    if !app.buttons["favorites.more"].waitForExistence(timeout: 3) {
      XCTAssertTrue(app.buttons["bottom.favorites"].waitForExistence(timeout: 20))
      app.buttons["bottom.favorites"].tap()
    }
    let groups: [(String, [String])] = [
      ("加密", ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"]),
      ("美股", ["AAPLUSDT", "MSFTUSDT", "NVDAUSDT", "AMZNUSDT", "GOOGLUSDT", "METAUSDT", "TSLAUSDT", "SNDKUSDT", "MUUSDT", "SKHYUSDT", "SKHYNIXUSDT", "MRVLUSDT", "LITEUSDT", "AVGOUSDT", "SOXLUSDT"]),
      ("贵金属", ["XAUUSDT", "XAGUSDT"])
    ]
    for (group, symbols) in groups {
      favoritesAction("favorites.newGroup")
      let name = app.alerts.textFields["分类名称"]
      XCTAssertTrue(name.waitForExistence(timeout: 5)); name.typeText(group)
      app.alerts.buttons["保存"].tap()
      for symbol in symbols {
        if app.buttons["favorites.open." + symbol].exists { continue }
        app.buttons["favorites.add"].tap()
        let query = app.textFields["symbols.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap()
        if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
          query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
        }
        query.typeText(symbol)
        let result = app.descendants(matching: .any).matching(identifier: "symbols.row." + symbol).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30)); result.tap()
        XCTAssertTrue(wait(seconds: 5) { !query.exists }, "添加后应关闭选品页")
        XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 5))
      }
    }
    func group(_ name: String) {
      let chip = app.buttons["favorites.group." + name]
      if !chip.isHittable { app.buttons["favorites.more"].tap() }
      XCTAssertTrue(chip.isHittable); chip.tap()
    }
    group("加密")
    let btc = app.buttons["favorites.open.BTCUSDT"]
    let sol = app.buttons["favorites.open.SOLUSDT"]
    let startY = btc.frame.minY
    let center = btc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.press(forDuration: 0.8, thenDragTo: center.withOffset(CGVector(dx: 0, dy: sol.frame.maxY - btc.frame.midY + 20)))
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > startY + 30 }, "直接拖动品种行应改变排序")
    let crypto = groups[0].1
    let movedOrder = crypto.sorted { app.buttons["favorites.open." + $0].frame.minY < app.buttons["favorites.open." + $1].frame.minY }
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 20), "结束后台进程后应直接恢复自选")
    group("加密")
    let restoredOrder = crypto.sorted { app.buttons["favorites.open." + $0].frame.minY < app.buttons["favorites.open." + $1].frame.minY }
    XCTAssertEqual(restoredOrder, movedOrder, "自定义顺序应在冷启动后完整保留")
    // 验收后恢复BTC排首位，保留用户请求的品种组织。
    let eth = app.buttons["favorites.open.ETHUSDT"]
    let restore = btc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    restore.press(forDuration: 0.8, thenDragTo: eth.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY < eth.frame.minY })
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 20))
    for (name, symbols) in groups {
      group(name)
      for symbol in symbols {
        let row = app.buttons["favorites.open." + symbol]
        for _ in 0..<4 { if row.exists { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(row.exists, "冷启动丢失分类成员：" + name + "/" + symbol)
      }
      shot("正式自选持久化-" + name)
    }
    group("加密")
    shot("正式自选-冷启动二十二品种")
  }

  /// 正式存档验收：保留用户收藏，避免隔离测试页在手机上显示空列表。
  func testUserSessionLatestEdgeAndReentry() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] == "1")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    try verifyLatestEdgeAndReentry()
  }

  func testLatestEdgeAndReentryCompatibility() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    try verifyLatestEdgeAndReentry()
  }

  private func verifyLatestEdgeAndReentry() throws {
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    app.buttons["favorites.open.BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 15))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, String(describing: info()))
    func gap() -> Double { self.info()["latestRightGap"] as? Double ?? 99999 }
    XCTAssertTrue(wait(seconds: 5) { abs(gap()) < 0.5 }, "从列表进入末根应贴绘图区右缘")
    let width = try XCTUnwrap(info()["plotW"] as? Double)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    let right = origin.withOffset(CGVector(dx: width * 0.75, dy: 140))
    let left = origin.withOffset(CGVector(dx: width * 0.3, dy: 140))
    right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertTrue(wait(seconds: 4) { abs(gap()) < 0.5 }, "最新端左滑释放应回位")
    left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertLessThan(gap(), -40, "右滑进入历史，不应回最新")
    right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: -30, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertLessThan(gap(), -20, "历史区左滑不能强制吸回最新")
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.open.BTCUSDT"].waitForExistence(timeout: 5))
    app.buttons["favorites.open.BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    XCTAssertTrue(wait(seconds: 4) { abs(gap()) < 0.5 }, "同品种重进也回到最新右缘")
    shot("默认末根贴右-最新端回弹-历史自由拖动-重进复位")
  }

  func testComfortPalettesAndLayout() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT,SNDKUSDT,XAUUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.close")
    let original = info()
    for (choice, background) in [("light", "#F4F6FD"), ("dark", "#161A3F"), ("paper", "#F4F0E4"), ("night", "#191712")] {
      app.buttons["bottom.settings"].tap()
      let strip = app.scrollViews["display.themes"]
      XCTAssertTrue(strip.waitForExistence(timeout: 5))
      let card = app.buttons["display.theme." + choice]
      for _ in 0..<4 {
        if card.exists && strip.frame.contains(card.frame) { break }
        strip.swipeLeft()
      }
      XCTAssertTrue(card.isHittable)
      card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      XCTAssertFalse(app.buttons["display.still"].exists)
      XCTAssertFalse(app.buttons["display.eyeBreak"].exists)
      closePanel()
      XCTAssertTrue(wait(seconds: 5) { self.info()["background"] as? String == background })
      for key in ["span", "plotW", "spacing", "mainH", "height"] {
        XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double), accuracy: 0.001)
      }
      shot("配色-" + choice + "-图表")
      app.buttons["bottom.favorites"].tap()
      let feed = app.descendants(matching: .any).matching(identifier: "favorites.feed").firstMatch
      XCTAssertTrue(app.buttons["favorites.open.BTCUSDT"].waitForExistence(timeout: 5))
      XCTAssertTrue(wait(seconds: 5) {
        (feed.value as? String)?.contains("background=" + background) == true
      })
      for name in ["加密", "美股", "贵金属"] {
        let tab = app.buttons["favorites.group." + name]
        XCTAssertTrue(tab.exists)
        XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        XCTAssertLessThanOrEqual(tab.frame.maxX, app.buttons["favorites.add"].frame.minX)
      }
      XCTAssertFalse(app.buttons["favorites.search"].exists)
      shot("配色-" + choice + "-自选")
      favoritesAction("favorites.close")
    }
  }

  func testQuickFavoritesAndMarketSectors() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.close")
    app.buttons["top.symbol"].tap()
    for symbol in ["BTCUSDT", "ETHUSDT", "SNDKUSDT"] {
      XCTAssertTrue(app.buttons["quickFavorites.open." + symbol].waitForExistence(timeout: 5))
    }
    XCTAssertFalse(app.scrollViews["favorites.groups"].exists)
    shot("左上角-全部收藏快捷切换")
    app.buttons["quickFavorites.search"].tap()
    XCTAssertTrue(app.textFields["symbols.query"].waitForExistence(timeout: 5))
    app.buttons["symbols.market"].tap()
    let equities = app.buttons["美股"]
    XCTAssertTrue(equities.waitForExistence(timeout: 5)); equities.tap()
    let query = app.textFields["symbols.query"]
    query.tap(); query.typeText("SNDK")
    XCTAssertTrue(app.buttons["symbols.row.SNDKUSDT"].waitForExistence(timeout: 10))
    shot("交易所-美股板块筛选")
    app.buttons["symbols.row.SNDKUSDT"].tap()
    XCTAssertTrue(wait(seconds: 20) { self.info()["symbol"] as? String == "SNDKUSDT" })
  }

  func testLatestQuoteDoesNotRegressAcrossIntervals() throws {
    func quote() -> [String: String] {
      let element = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
      let raw = element.value as? String ?? ""
      return Dictionary(raw.split(separator: ";").compactMap { field in
        let parts = field.split(separator: "=", maxSplits: 1)
        return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
      }, uniquingKeysWith: { _, b in b })
    }
    for symbol in ["BTCUSDT", "SNDKUSDT", "ETHUSDT", "BTCUSDT"] {
      if symbol != "BTCUSDT" || info()["symbol"] as? String != "BTCUSDT" {
        app.buttons["top.search"].tap()
        let query = app.textFields["symbols.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap()
        if let old = query.value as? String, !old.isEmpty { query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        query.typeText(symbol)
        let row = app.buttons["symbols.row." + symbol]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
      }
      XCTAssertTrue(wait(seconds: 20) { quote()["symbol"] == symbol && (Int64(quote()["time"] ?? "0") ?? 0) > 0 })
      var stamp = Int64(quote()["time"] ?? "0") ?? 0
      for interval in ["1m", "1h", "4h", "1h"] {
        let chip = app.buttons["interval.chip." + interval]
        let strip = app.scrollViews["interval.quick"]
        strip.swipeRight()
        for _ in 0..<3 { if chip.exists && strip.frame.contains(chip.frame) { break }; strip.swipeLeft() }
        let previousSpacing = info()["spacing"] as? Double
        chip.tap()
        // Read during the actual transition, before the REST candle request finishes.
        for _ in 0..<3 {
          let value = quote()
          XCTAssertEqual(value["symbol"], symbol)
          let next = Int64(value["time"] ?? "0") ?? 0
          XCTAssertGreaterThanOrEqual(next, stamp)
          XCTAssertGreaterThan(Double(value["last"] ?? "0") ?? 0, 0)
          stamp = next
        }
        XCTAssertTrue(wait(seconds: 20) { self.info()["symbol"] as? String == symbol && self.info()["interval"] as? String == interval })
        if let previousSpacing { XCTAssertEqual(self.info()["spacing"] as? Double ?? 0, previousSpacing, accuracy: 0.02) }
      }
    }
    shot("多品种多周期-报价时序")
  }

  func favoritesAction(_ identifier: String) {
    dismissNotificationBanner()
    app.buttons["favorites.more"].tap()
    let action = app.buttons[identifier]
    XCTAssertTrue(action.waitForExistence(timeout: 4)); action.tap()
    if identifier == "favorites.close" {
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["favorites.more"].exists && self.app.buttons["bottom.settings"].isHittable })
    }
  }

  /// Physical-device notifications can cover the top category bar. Dismiss only
  /// the system banner, without opening it or changing notification preferences.
  private func dismissNotificationBanner() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let banner = springboard.descendants(matching: .any)
      .matching(identifier: "NotificationShortLookView").firstMatch
    for _ in 0..<3 {
      guard banner.exists else { return }
      banner.swipeUp()
    }
    XCTAssertFalse(banner.exists, "系统通知仍遮挡顶部分类栏")
  }

  func testFavoritesCategoryOverflow() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT,XAUUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.buttons["favorites.search"].exists)
    XCTAssertFalse(app.textFields["favorites.query"].exists)
    XCTAssertGreaterThanOrEqual(app.buttons["favorites.group.加密"].frame.height, 44)
    for name in ["观察中的品种", "长期关注", "短线"] {
      favoritesAction("favorites.newGroup")
      let field = app.alerts.textFields.firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 4)); field.typeText(name)
      app.alerts.buttons["保存"].tap()
      XCTAssertTrue(app.buttons["favorites.group." + name].waitForExistence(timeout: 4))
    }
    shot("自选-顶部分类与更多入口")
    dismissNotificationBanner()
    app.buttons["favorites.more"].tap()
    let overflow = app.buttons["favorites.group.观察中的品种"]
    XCTAssertTrue(overflow.waitForExistence(timeout: 4)); overflow.tap()
    XCTAssertTrue(app.buttons["favorites.group.观察中的品种"].isHittable)
    favoritesAction("favorites.close")
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.group.观察中的品种"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    favoritesAction("favorites.edit")
    XCTAssertTrue(app.buttons["全选"].waitForExistence(timeout: 4))
    favoritesAction("favorites.edit")
    app.buttons["favorites.add"].tap()
    XCTAssertTrue(app.textFields["symbols.query"].waitForExistence(timeout: 5))
  }

  func testUserSessionFreshQuotesAndReorder() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] == "1")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    XCTAssertFalse(app.buttons["favorites.group.全部"].exists)
    XCTAssertFalse(app.buttons["favorites.group.默认"].exists)
    XCTAssertFalse(app.buttons["favorites.search"].exists)
    let feed = app.descendants(matching: .any).matching(identifier: "favorites.feed").firstMatch
    let price = app.staticTexts["favorites.price.BTCUSDT"]
    XCTAssertTrue(wait(seconds: 20) { price.exists && price.label != "—" })
    let cold = feed.value as? String ?? ""
    let coldSession = cold.components(separatedBy: ";").first ?? ""
    print("FreshQuotes cold: " + cold)
    var prices = Set<String>()
    XCTAssertTrue(wait(seconds: 15) { prices.insert(price.label); return prices.count > 1 })
    favoritesAction("favorites.close")
    XCTAssertTrue(app.buttons["bottom.favorites"].waitForExistence(timeout: 8))
    let stayUntil = Date().addingTimeInterval(3)
    XCTAssertTrue(wait(seconds: 5) { Date() >= stayUntil })
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 3))
    XCTAssertTrue(price.exists && price.label != "—", "返回自选首帧应直接使用持续订阅的真实报价")
    XCTAssertEqual((feed.value as? String ?? "").components(separatedBy: ";").first, coldSession,
      "前台切页不能重建报价会话")
    print("FreshQuotes return: " + (feed.value as? String ?? ""))
    app.buttons["favorites.open.BTCUSDT"].swipeLeft()
    XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["置顶"].exists)
    app.buttons["favorites.open.BTCUSDT"].swipeRight()
    XCUIDevice.shared.press(.home)
    // 留在后台超过旧连接宽限时间，验证新会话而非旧画面还在。
    let until = Date().addingTimeInterval(7)
    XCTAssertTrue(wait(seconds: 10) { Date() >= until })
    app.activate()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 8))
    XCTAssertTrue(wait(seconds: 20) { price.exists && price.label != "—" && (feed.value as? String ?? "").components(separatedBy: ";").first != coldSession })
    print("FreshQuotes resume: " + (feed.value as? String ?? ""))
    shot("正式自选-前台恢复实时报价")
  }

  func testUserSessionRowReorderAndMove() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] == "1")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    let group = app.buttons["favorites.group.加密"]
    group.tap()
    let btc = app.buttons["favorites.open.BTCUSDT"], doge = app.buttons["favorites.open.DOGEUSDT"]
    let originalY = btc.frame.minY
    let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY)).press(forDuration: 1,
      thenDragTo: origin.withOffset(CGVector(dx: doge.frame.midX, dy: doge.frame.midY)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > originalY + 80 }, "长按普通行拖动应更改顺序")
    let crypto = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"]
    let moved = crypto.sorted { app.buttons["favorites.open." + $0].frame.minY < app.buttons["favorites.open." + $1].frame.minY }
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    group.tap()
    let restored = crypto.sorted { app.buttons["favorites.open." + $0].frame.minY < app.buttons["favorites.open." + $1].frame.minY }
    XCTAssertEqual(restored, moved)
    let eth = app.buttons["favorites.open.ETHUSDT"]
    origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY)).press(forDuration: 1,
      thenDragTo: origin.withOffset(CGVector(dx: eth.frame.midX, dy: eth.frame.minY)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY < eth.frame.minY })
    shot("正式自选-原生长按排序与冷启动持久化")
    btc.swipeLeft()
    let move = app.buttons["移到分类"]
    XCTAssertTrue(move.waitForExistence(timeout: 4)); move.tap()
    let stocks = app.buttons["美股"]
    XCTAssertTrue(stocks.waitForExistence(timeout: 4)); stocks.tap()
    XCTAssertTrue(wait(seconds: 4) { !btc.exists })
    app.buttons["favorites.group.美股"].tap()
    XCTAssertTrue(btc.waitForExistence(timeout: 4))
    btc.swipeLeft(); app.buttons["移到分类"].tap()
    app.buttons["加密"].tap()
    app.buttons["favorites.group.加密"].tap()
    XCTAssertTrue(btc.waitForExistence(timeout: 4))
    shot("正式自选-滑动移到分类")
  }

  func testUserSessionChartInteractions() throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] == "1")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    app.buttons["favorites.open.BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 15))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, String(describing: info()))
    // 顶部搜索区域也只负责收起，不应穿透打开选品页。
    let search = app.buttons["top.search"].frame
    app.buttons["bottom.indicator"].tap()
    XCTAssertTrue(app.staticTexts["panel.header"].waitForExistence(timeout: 5))
    app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: search.midX, dy: search.midY)).tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.staticTexts["panel.header"].exists })
    XCTAssertFalse(app.textFields["symbols.query"].exists)
    try testOutsideTapOnlyDismissesPanel()
    let original = try XCTUnwrap(info()["subs"] as? [String])
    let panes = try XCTUnwrap(info()["panes"] as? [[String: Any]])
    XCTAssertGreaterThanOrEqual(panes.count, 2)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    func center(_ pane: [String: Any]) -> XCUICoordinate {
      origin.withOffset(CGVector(dx: (info()["plotW"] as? Double ?? 300) / 2,
        dy: (pane["y"] as? Double ?? 0) + (pane["h"] as? Double ?? 80) / 2))
    }
    center(panes[0]).press(forDuration: 0.5, thenDragTo: center(panes[panes.count - 1]))
    XCTAssertTrue(wait(seconds: 5) { self.info()["subs"] as? [String] == Array(original.dropFirst()) + [original[0]] })
    shot("正式行情-整个副图区域长按换序")
    let moved = try XCTUnwrap(info()["panes"] as? [[String: Any]])
    center(moved[moved.count - 1]).press(forDuration: 0.5, thenDragTo: center(moved[0]))
    XCTAssertTrue(wait(seconds: 5) { self.info()["subs"] as? [String] == original })
    try testCrosshairCenterDragAndOutsidePan()
    app.buttons["bottom.favorites"].tap()
  }

  func testOutsideTapOnlyDismissesPanel() throws {
    for entry in ["bottom.indicator", "bottom.settings", "interval.chart", "interval.more"] {
      app.buttons[entry].tap()
      let header = app.staticTexts["panel.header"]
      XCTAssertTrue(header.waitForExistence(timeout: 5))
      selectMain()
      XCTAssertTrue(wait(seconds: 5) { !header.exists })
      XCTAssertEqual(info()["crosshair"] as? Bool, false, "首个外部点击只关闭面板：" + entry)
      selectMain()
      XCTAssertTrue(wait(seconds: 3) { self.info()["crosshair"] as? Bool == true })
      selectMain()
      XCTAssertTrue(wait(seconds: 3) { self.info()["crosshair"] as? Bool == false })
    }
    shot("面板外点击-只收起不触发十字线")
  }

  func testFourSubpanelsFitWithoutPageScroll() throws {
    app.buttons["bottom.indicator"].tap()
    let toggle = app.buttons["indicator.switch.RSI"]
    let scroll = app.scrollViews["panel.content"]
    for _ in 0..<5 {
      if toggle.exists, toggle.isHittable, scroll.frame.contains(toggle.frame) { break }
      scroll.swipeUp()
    }
    XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap(); closePanel()
    XCTAssertTrue(wait { (self.info()["subs"] as? [String])?.count == 4 })
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    XCTAssertTrue(app.otherElements["chart.resize.RSI"].isHittable)
    shot("一屏四副图-无需滚动")
  }

  func testDataModesClearHeaderAndSelection() throws {
    app.buttons["interval.chart"].tap()
    app.buttons["顶部"].tap(); closePanel()
    selectMain()
    XCTAssertTrue(app.staticTexts["chart.topOHLC"].waitForExistence(timeout: 8))
    shot("顶部-历史OHLC")
    app.buttons["interval.chart"].tap()
    app.buttons["跟随K线"].tap(); closePanel()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertFalse(app.staticTexts["chart.topOHLC"].exists)
    selectMain()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == true })
    shot("跟随K线-单一容器")
    selectMain()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertFalse(app.staticTexts["chart.topOHLC"].exists)
    shot("关闭十字线-实时头部恢复")
  }

  func testMAParameterCancelAndSaveOutput() throws {
    let original = try XCTUnwrap(info()["ma"] as? [Int])
    app.buttons["bottom.indicator"].tap()
    app.buttons["indicator.edit.MA"].tap()
    let stepper = app.steppers["indicator.param.0"]
    XCTAssertTrue(stepper.waitForExistence(timeout: 5))
    stepper.buttons["indicator.param.0-Increment"].tap()
    app.buttons["取消"].tap(); closePanel()
    XCTAssertEqual(info()["ma"] as? [Int], original)
    app.buttons["bottom.indicator"].tap()
    app.buttons["indicator.edit.MA"].tap()
    let output = app.switches["indicator.output.0"]
    XCTAssertTrue(output.waitForExistence(timeout: 5))
    XCTAssertEqual(output.value as? String, "1")
    // SwiftUI exposes the whole Form row as the switch; hit the visible thumb.
    output.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
    XCTAssertTrue(wait { output.value as? String == "0" })
    shot("MA草稿-输出已关闭")
    app.buttons["保存"].tap(); closePanel()
    XCTAssertTrue(wait { self.info()["hiddenMA"] as? [Int] == [0] })
    shot("MA输出关闭-曲线图例同步")
  }
  func testDeviceHistoricalPanPinchAndManualY() throws {
    let initial = info()
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    let start = origin.withOffset(CGVector(dx: 70, dy: 170))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 180, dy: 0)))
    XCTAssertTrue(wait { (self.info()["to"] as? Double ?? .infinity) < (initial["to"] as? Double ?? 0) })
    // Wait for the finite fling to finish by observing a stable window.
    var previous = info()["to"] as? Double
    XCTAssertTrue(wait {
      let current = self.info()["to"] as? Double
      defer { previous = current }
      return current == previous
    })
    let history = info()
    canvas.pinch(withScale: 1.5, velocity: 1)
    XCTAssertTrue(wait { (self.info()["spacing"] as? Double ?? 0) > (history["spacing"] as? Double ?? 0) + 0.1 })
    XCTAssertLessThan(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(initial["to"] as? Double))
    shot("真机-历史横拖和双指缩放")
    let beforeY = info()
    let width = try XCTUnwrap(beforeY["plotW"] as? Double)
    let axis = origin.withOffset(CGVector(dx: width + 20, dy: 140))
    axis.press(forDuration: 0.05, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -85)))
    XCTAssertTrue(wait { abs((self.info()["zoomY"] as? Double ?? 1) - 1) > 0.05 })
    XCTAssertEqual(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(beforeY["to"] as? Double), accuracy: 0.001)
    let h = try XCTUnwrap(info()["mainH"] as? Double)
    origin.withOffset(CGVector(dx: width + 20, dy: h - 34)).tap()
    XCTAssertTrue(wait { self.info()["zoomY"] as? Double == 1 })
    XCTAssertEqual(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(beforeY["to"] as? Double), accuracy: 0.001)
    shot("真机-A仅恢复自动Y")
  }

}

extension ChartFoundationUITests {
  func testDrawingToolsAndPersistentStyles() throws {
    app.buttons["interval.draw"].tap()
    app.buttons["draw.tools"].tap()
    XCTAssertTrue(app.buttons["draw.tool.ray"].waitForExistence(timeout: 5))
    shot("画线-工具分类")
    app.buttons["draw.tool.ray"].tap()
    var origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    origin.withOffset(CGVector(dx: 240, dy: 160)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["ray"])
    XCTAssertTrue(app.buttons["draw.undo"].isEnabled)
    app.buttons["draw.undo"].tap(); XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 0 })
    app.buttons["draw.redo"].tap(); XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 })
    // Undo removes selection; tap the actual ray after redo.
    origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    XCTAssertTrue(app.buttons["draw.style"].waitForExistence(timeout: 3))
    app.buttons["draw.style"].tap()
    app.buttons["color.#4A90E2"].tap()
    app.buttons["draw.save"].tap()
    XCTAssertTrue(wait { self.info()["drawingColors"] as? [String] == ["#4A90E2"] })
    app.buttons["draw.lock"].tap()
    XCTAssertTrue(wait { self.info()["drawingLocked"] as? [Bool] == [true] })
    let ids = try XCTUnwrap(info()["drawingIDs"] as? [String])
    shot("画线-射线颜色与锁定")
    app.buttons["draw.finish"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids }, String(describing: info()))
    XCTAssertEqual(info()["drawingColors"] as? [String], ["#4A90E2"])
    XCTAssertEqual(info()["drawingLocked"] as? [Bool], [true])
    app.buttons["interval.draw"].tap()
    app.buttons["draw.objects.quick"].tap()
    XCTAssertTrue(app.buttons["draw.object.\(ids[0])"].waitForExistence(timeout: 5))
    shot("画线-重启恢复对象")
    app.buttons["隐藏画线"].tap()
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: 50)).tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
    XCTAssertEqual(info()["crosshair"] as? Bool, false)
    XCTAssertTrue(wait { self.info()["drawingHidden"] as? [Bool] == [true] })
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(seconds: 5) { self.canvas.frame.width > self.canvas.frame.height && self.app.buttons["draw.tools"].isHittable })
    app.buttons["draw.tools"].tap()
    XCTAssertTrue(app.buttons["draw.sheet.done"].waitForExistence(timeout: 5))
    for _ in 0..<8 {
      if app.buttons["draw.tool.ray"].exists && app.buttons["draw.tool.ray"].isHittable { break }
      let list = app.collectionViews.firstMatch
      list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
        thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)),
        withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    XCTAssertTrue(app.buttons["draw.tool.ray"].isHittable)
    app.buttons["draw.sheet.done"].tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists && self.app.buttons["draw.tools"].isHittable })
    let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscapeShot.name = "画线-横屏工具栏"; landscapeShot.lifetime = .keepAlways; add(landscapeShot)
    XCUIDevice.shared.orientation = .portrait
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingHidden"] as? [Bool] == [true] })
    app.buttons["interval.draw"].tap()
    app.buttons["draw.objects.quick"].tap()
    app.buttons["draw.object.\(ids[0])"].tap()
    XCTAssertTrue(app.buttons["draw.copy"].waitForExistence(timeout: 5))
    app.buttons["draw.copy"].tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 })
    app.buttons["draw.delete"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    app.buttons["draw.undo"].tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 })
    app.buttons["draw.redo"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-只删除选中对象并可撤销")
    app.buttons["draw.magnet.quick"].tap()
    app.buttons["draw.continuous.quick"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    XCTAssertEqual(info()["drawingMagnet"] as? Bool, false)
    XCTAssertEqual(info()["drawingContinuous"] as? Bool, true)
  }

  func testIndicatorColorSaveCancelAndRestart() throws {
    func edit(_ id: String, color: String, save: Bool) {
      app.buttons["bottom.indicator"].tap()
      if !app.buttons["indicator.edit.\(id)"].exists { app.buttons["indicator.switch.\(id)"].tap() }
      app.buttons["indicator.edit.\(id)"].tap()
      let swatch = app.buttons["indicator.color.0.\(color)"].firstMatch
      for _ in 0..<5 { if swatch.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(swatch.isHittable); swatch.tap()
      shot("\(id)-独立颜色编辑")
      app.buttons[save ? "保存" : "取消"].tap(); closePanel()
    }
    let original = info()["maColor0"] as? String
    edit("MA", color: "#4A90E2", save: false)
    XCTAssertEqual(info()["maColor0"] as? String, original)
    edit("MA", color: "#4A90E2", save: true)
    XCTAssertTrue(wait { self.info()["maColor0"] as? String == "#4A90E2" })
    edit("EMA", color: "#37A78F", save: true)
    XCTAssertEqual(info()["maColor0"] as? String, "#4A90E2")
    XCTAssertEqual(info()["emaColor0"] as? String, "#37A78F")
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["maColor0"] as? String == "#4A90E2" })
    XCTAssertEqual(info()["emaColor0"] as? String, "#37A78F")
    shot("均线颜色-重启恢复")
  }
}

extension ChartFoundationUITests {
  func testDrawingAllToolsAndFingerTargets() throws {
    app.buttons["interval.draw"].tap()
    app.buttons["draw.magnet.quick"].tap()
    let tools: [(String, Int)] = [("trend", 2), ("hline", 1), ("ray", 2), ("hray", 1),
      ("extended", 2), ("vline", 1), ("rectangle", 2), ("channel", 3), ("fibonacci", 2), ("measure", 2)]
    for (index, tool) in tools.enumerated() {
      app.buttons["draw.tools"].tap()
      XCTAssertTrue(app.buttons["draw.sheet.done"].waitForExistence(timeout: 5))
      let target = app.buttons["draw.tool.\(tool.0)"]
      for _ in 0..<14 {
        if target.exists && target.isHittable { break }
        let list = app.collectionViews.firstMatch
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
          thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
          withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      XCTAssertTrue(target.isHittable, tool.0); target.tap()
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
      let h = try XCTUnwrap(info()["mainH"] as? Double)
      let origin = canvas.coordinate(withNormalizedOffset: .zero)
      let points = [CGVector(dx: 90, dy: h * 0.65), CGVector(dx: 245, dy: h * 0.3), CGVector(dx: 160, dy: h * 0.75)]
      for point in points.prefix(tool.1) { origin.withOffset(point).tap() }
      XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == index + 1 }, tool.0)
      XCTAssertEqual((info()["drawingKinds"] as? [String])?.last, tool.0)
      if index == 0 {
        let before = try XCTUnwrap(info()["drawingAnchors"] as? [[[String: Double]]])
        origin.withOffset(CGVector(dx: 90, dy: h * 0.65 + 17)).press(forDuration: 0.1,
          thenDragTo: origin.withOffset(CGVector(dx: 115, dy: h * 0.65 + 42)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait { (self.info()["drawingAnchors"] as? [[[String: Double]]]) != before })
        let after = try XCTUnwrap(info()["drawingAnchors"] as? [[[String: Double]]])
        XCTAssertEqual(after[0][1], before[0][1], "手指偏离可见把手 17pt 仍应只拖动最近端点")
        app.buttons["draw.undo"].tap()
        XCTAssertTrue(wait { (self.info()["drawingAnchors"] as? [[[String: Double]]]) == before })
      }
    }
    let ids = try XCTUnwrap(info()["drawingIDs"] as? [String])
    app.buttons["draw.finish"].tap()
    app.buttons["interval.draw"].tap()
    app.buttons["draw.objects.quick"].tap()
    let clear = app.buttons["draw.clear"]
    for _ in 0..<10 { if clear.exists && clear.isHittable { break }; app.swipeUp() }
    XCTAssertTrue(clear.isHittable); clear.tap()
    app.buttons["清空画线"].tap()
    app.buttons["draw.sheet.done"].tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 0 })
    app.buttons["draw.undo"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-十种工具与手指端点拖动")
  }

  func testDrawingRectangleChannelAndFibonacci() throws {
    app.buttons["interval.draw"].tap()
    for (index, entry) in [("rectangle", 2), ("channel", 3), ("fibonacci", 2)].enumerated() {
      app.buttons["draw.tools"].tap()
      let target = app.buttons["draw.tool.\(entry.0)"]
      for _ in 0..<8 { if target.exists && target.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(target.isHittable); target.tap()
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
      let h = try XCTUnwrap(info()["mainH"] as? Double)
      let origin = canvas.coordinate(withNormalizedOffset: .zero)
      let points = [CGVector(dx: 90, dy: h * 0.7), CGVector(dx: 245, dy: h * 0.25), CGVector(dx: 160, dy: h * 0.65)]
      for point in points.prefix(entry.1) { origin.withOffset(point).tap() }
      XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == index + 1 }, String(describing: info()))
      XCTAssertEqual((info()["drawingKinds"] as? [String])?.last, entry.0)
      shot("画线-\(entry.0)")
    }
    let ids = info()["drawingIDs"] as? [String]
    app.buttons["draw.finish"].tap()
    app.buttons["interval.chip.4h"].tap()
    XCTAssertTrue(wait { self.info()["interval"] as? String == "4h" })
    XCTAssertEqual(info()["drawingIDs"] as? [String], ids)
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-多工具跨周期与重启")
  }
}

extension ChartFoundationUITests {
  func testCompactChartStylesAndRotation() throws {
    XCTAssertFalse(app.buttons["bottom.style"].exists)
    XCTAssertFalse(app.buttons["bottom.landscape"].exists)
    XCTAssertFalse(app.buttons["chart.expand"].exists)
    shot("手机-简化入口")
    app.buttons["interval.chart"].tap()
    for id in ["aicoin", "pill", "paper", "outline"] {
      let button = app.buttons["style.card.\(id)"]
      XCTAssertTrue(button.waitForExistence(timeout: 5))
      button.tap()
      XCTAssertTrue(button.isSelected)
    }
    XCTAssertFalse(app.buttons["style.card.stout"].exists)
    shot("手机-图表四种精选风格")
    closePanel()
    XCTAssertEqual(info()["style"] as? String, "outline")
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["style"] as? String == "outline" })
    // 用户拿起手机旋转，不需要先点按钮。
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(seconds: 8) { self.canvas.frame.width > self.canvas.frame.height })
    XCTAssertFalse(app.buttons["chart.expand"].isHittable)
    XCTAssertFalse(app.buttons["land.exit"].exists)
    let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscapeShot.name = "手机-自动横屏"; landscapeShot.lifetime = .keepAlways; add(landscapeShot)
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(wait(seconds: 8) { self.canvas.frame.width < self.canvas.frame.height && self.app.buttons["interval.chart"].isHittable })
    XCTAssertEqual(info()["style"] as? String, "outline")
  }
}
