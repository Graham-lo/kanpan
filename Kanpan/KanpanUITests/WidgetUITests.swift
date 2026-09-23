import XCTest

/// 桌面小组件（P3.2）：app 刷到行情就把自选写进 App Group 快照，小组件只读它。
///
/// 这条用例像人一样走一遍：开 app（自选四只、真行情）→ 回桌面 → 长按进编辑 →
/// 从小组件库里把 Hkline 的小号「自选」和中号「品种」各加一块 → 截图。
/// 系统桌面的按钮文案随系统语言变，所以每一步都中英两种都认。
@MainActor final class WidgetUITests: XCTestCase {
  private let shots = URL(fileURLWithPath: "/tmp/kanpan-c", isDirectory: true)
  private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
  }

  func testBothSizesSitOnTheHomeScreen() throws {
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["bottom.chart"].waitForExistence(timeout: 30), "app 没起来")
    // 等报价簿出第一批价（快照在第一批价到时立刻写）；再留一会儿给 1 小时收盘价那一口。
    _ = app.staticTexts["不存在"].waitForExistence(timeout: 20)
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))

    addWidget(page: 0)
    shoot("P3.2-桌面-小号自选")
    addWidget(page: 1)
    shoot("P3.2-桌面-两种尺寸")
  }

  // ------------------------------------------------------------ 桌面操作

  /// 桌面按钮的文案常带前导空格（「 添加小组件」），按包含匹配。
  private func first(_ query: XCUIElementQuery, _ labels: [String]) -> XCUIElement? {
    for label in labels {
      let e = query[label]
      if e.exists { return e }
      let loose = query.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
      if loose.exists { return loose }
    }
    return nil
  }

  private func waitFirst(_ query: XCUIElementQuery, _ labels: [String], timeout: TimeInterval = 10) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let e = first(query, labels) { return e }
      RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    } while Date() < deadline
    return nil
  }

  private func dump(_ step: String) {
    let a = XCTAttachment(string: springboard.debugDescription)
    a.name = "springboard-" + step
    a.lifetime = .keepAlways
    add(a)
  }

  /// 进编辑 → 小组件库 → 搜 Hkline → 翻到第 `page` 页（0 = 小号自选，1 = 中号品种）→ 加上 → 完成。
  private func addWidget(page: Int) {
    // 长按桌面空白处进编辑态。
    let blank = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
    blank.press(forDuration: 1.6)
    var edit = waitFirst(springboard.buttons, ["Edit", "编辑"], timeout: 5)
    if edit == nil {
      // 有的系统长按空白直接出「添加小组件」那颗 +。
      edit = first(springboard.buttons, ["Add Widget", "添加小组件", "Add"])
    }
    guard let edit else { dump("no-edit"); XCTFail("桌面没进编辑态"); return }
    edit.tap()
    if let add = waitFirst(springboard.buttons, ["Add Widget", "添加小组件"], timeout: 5) {
      add.tap()
    }
    guard let search = waitFirst(springboard.searchFields, ["Search Widgets", "搜索小组件"], timeout: 10)
      ?? (springboard.searchFields.firstMatch.waitForExistence(timeout: 3) ? springboard.searchFields.firstMatch : nil)
    else { dump("no-gallery"); XCTFail("小组件库没打开"); return }
    search.tap()
    search.typeText("Hkline")
    guard let cell = waitFirst(springboard.cells, ["Hkline"], timeout: 10)
      ?? waitFirst(springboard.buttons, ["Hkline"], timeout: 2)
      ?? waitFirst(springboard.staticTexts, ["Hkline"], timeout: 2)
    else { dump("no-hkline"); XCTFail("小组件库里搜不到 Hkline"); return }
    cell.tap()
    _ = waitFirst(springboard.buttons, ["Add Widget", "添加小组件"], timeout: 10)
    for _ in 0..<page {
      // 在尺寸预览上横滑翻页（整屏横滑会被桌面自己吃掉）。
      let preview = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Hkline,'")).firstMatch
      if preview.exists { preview.swipeLeft() } else { springboard.swipeLeft() }
      RunLoop.current.run(until: Date().addingTimeInterval(1.2))
    }
    dump("gallery-page-\(page)")
    guard let add = waitFirst(springboard.buttons, ["Add Widget", "添加小组件"], timeout: 5)
    else { dump("no-add"); XCTFail("没有「添加小组件」"); return }
    add.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    if let done = waitFirst(springboard.buttons, ["Done", "完成"], timeout: 5) { done.tap() }
    // 小组件第一次上桌面要跑一次时间线（可能要自己取价），留几秒。
    RunLoop.current.run(until: Date().addingTimeInterval(6))
  }

  private func shoot(_ name: String) {
    let shot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: shot)
    a.name = name
    a.lifetime = .keepAlways
    add(a)
    try? shot.pngRepresentation.write(to: shots.appendingPathComponent(name + ".png"))
  }
}
