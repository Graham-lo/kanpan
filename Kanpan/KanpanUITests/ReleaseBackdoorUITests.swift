import XCTest

// ============================================================ 审查 C.10 第 1 条
//
// 「Release 不进测试后门」这件事要证两头，这儿是其中一头。
//
// **另一头在 `Kanpan/Symbols/Tests/KanpanSymbolsTests/ReleaseHookScanTests.swift`**：
// 那条用例把 app 与各包里会进 Release 二进制的源码全扫一遍，钉住「每一处读启动环境的
// 地方都在 `#if DEBUG` 里」。那是**静态**的一半——它管得住「有没有第 N 个我没想到的开关」，
// 但它不知道这些开关真开起来会不会生效。
//
// 这条用例管**动态**的那一半：同一个二进制，一次什么都不给，一次把全套开关都给上，
// 逐项比对屏上看得见的差别。两次之间只有环境变量不同，所以凡是变了的，都只可能是
// 那几个开关掀起来的；凡是没变的，就是开关碰不到的地方。
//
// 两条合起来才是完整的证明链：**开关只在 DEBUG 下存在（静态扫描）＋ 开关掀起来
// 正好只影响这些（动态比对）⇒ Release 里这些差别一个都不会发生。**
// 不用「另一个自己也会被裁掉的测试钩子」来自证，这正是报告点名要避开的那种循环。
//
// 这条**不继承 `KanpanUICase`**：那个底座在 `setUp` 里就替所有人把
// `KANPAN_TEST_PROFILE` 和 `KANPAN_CHART_DIAGNOSTICS` 设上了，而这儿要的正是
// 「一个都不设」的那次启动。
final class ReleaseBackdoorUITests: XCTestCase {

  /// 全套开关。名单来自 C.6 那张表，逐个对着写的。
  private static func allHooks() -> [String: String] {
    ["KANPAN_TEST_PROFILE": "1",
     "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString,
     "KANPAN_TEST_FAVORITES": seed.joined(separator: ","),
     "KANPAN_CHART_DIAGNOSTICS": "1",
     "KANPAN_WS_SWEEP": "1",
     "KANPAN_LOG": "1",
     "KANPAN_ACCOUNT_API_URL": "https://kanpan.107-174-172-10.sslip.io"]
  }

  /// 灌进去的自选。故意挑两个**不是出厂默认**的品种：屏上出现它俩，只可能是种子干的。
  private static let seed = ["SOLUSDT", "LINKUSDT"]

  /// 只在 DEBUG 下才该存在的那几个诊断元素（`MainScreen.basePresentation` 的 overlay）。
  private static let diagnosticIDs = ["market.source", "market.network", "layout.diagnostics"]

  override func setUp() async throws { continueAfterFailure = false }

  // ---------------------------------------------------------------- 用例

  func testLaunchHooksAreStrictlyOptIn() throws {
    // ---------- 一、什么都不给
    let bare = launch([:])
    goToChart(bare)
    for id in Self.diagnosticIDs {
      XCTAssertFalse(bare.descendants(matching: .any).matching(identifier: id).firstMatch.exists,
                     "没给任何开关，\(id) 这个诊断字段却在屏上")
    }
    XCTAssertNil(chartInfo(bare)["bars"],
                 "没给 KANPAN_CHART_DIAGNOSTICS，画布却在吐诊断 JSON：\(chartInfo(bare))")
    // 开关不是产品的一部分：不给开关，图照样得起来（拿顶栏品种名当准星，上面已经等过）。
    XCTAssertTrue(bare.otherElements["chart.canvas"].exists, "不给开关，图区就不见了")
    goToFavorites(bare)
    for symbol in Self.seed {
      XCTAssertFalse(bare.buttons["favorites.open." + symbol].waitForExistence(timeout: 3),
                     "没给 KANPAN_TEST_FAVORITES，\(symbol) 却出现在自选里")
    }
    let bareRows = rowCount(bare)
    bare.terminate()

    // ---------- 二、全套开关都给上
    let hooked = launch(Self.allHooks())
    goToChart(hooked)
    for id in Self.diagnosticIDs {
      XCTAssertTrue(hooked.descendants(matching: .any).matching(identifier: id).firstMatch
                      .waitForExistence(timeout: 10),
                    "开关全给了，\(id) 反而没出来——这条用例的两头得都成立才有意义")
    }
    XCTAssertTrue(waitUntil(15) { self.chartInfo(hooked)["bars"] != nil },
                  "开了 KANPAN_CHART_DIAGNOSTICS，画布却没吐诊断 JSON")
    goToFavorites(hooked)
    for symbol in Self.seed {
      XCTAssertTrue(hooked.buttons["favorites.open." + symbol].waitForExistence(timeout: 10),
                    "隔离档案上灌了 \(symbol)，自选里却没有")
    }
    // 两次启动之间自选整个换了一份：种子档案是独立的，不是往用户那份上添几行。
    XCTAssertEqual(rowCount(hooked), Self.seed.count,
                   "隔离档案里的自选不止种子那两行（裸启动时是 \(bareRows) 行）——档案没隔离干净")
    hooked.terminate()
  }

  // ---------------------------------------------------------------- 手脚

  private func launch(_ environment: [String: String]) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment = environment
    app.launch()
    return app
  }

  /// 冷启动可能落在自选页（存档里有自选时就落在那一格），先回行情页。
  private func goToChart(_ app: XCUIApplication) {
    let chartTab = app.buttons[Ids.bottomChart]
    XCTAssertTrue(chartTab.waitForExistence(timeout: 30), "标签栏都没起来")
    if !app.symbolLabel.exists { chartTab.tap() }
    XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: 30), "没等到顶栏品种名")
  }

  private func goToFavorites(_ app: XCUIApplication) {
    let tab = app.buttons[Ids.bottomFavorites]
    XCTAssertTrue(tab.waitForExistence(timeout: 10), "标签栏上没有「自选」")
    tab.tap()
    XCTAssertTrue(app.otherElements["favorites.feed"].waitForExistence(timeout: 10), "自选页没开")
  }

  /// 自选页上有几行。行按 `favorites.open.<代号>` 认。
  private func rowCount(_ app: XCUIApplication) -> Int {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'favorites.open.'")).count
  }

  private func chartInfo(_ app: XCUIApplication) -> [String: Any] {
    let canvas = app.otherElements["chart.canvas"]
    guard canvas.exists, let text = canvas.value as? String, let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
  }

  private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: 0.25)
    }
    return condition()
  }
}
