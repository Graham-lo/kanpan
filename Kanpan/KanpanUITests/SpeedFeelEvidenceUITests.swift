import XCTest

// ============================================================ 体感快取证（2026-10-07）
//
// 网慢的时候不让人干等着空白：
// 1. 冷切到一只没有快照的品种——不留上一只的 K 线，图区先出一条 24h 价位的细线 / 淡带，
//    顶上一道细的进度条；顶栏六格里还在路上的那几格是骨架条，不是「—」。
// 2. 对比里增 / 减一只——旧的那几条线一直在，不先清空再一起重画。
//
// 截图按帧连拍落到 `KANPAN_EVIDENCE_DIR`（不给就 /tmp/kp-burst），挑能说明问题的那几帧进验收目录。
@MainActor
final class SpeedFeelEvidenceUITests: KanpanUICase {
  private let profile = UUID().uuidString
  /// 首屏照常快快起来；从这一刻起每笔 HTTP 多等 `slowMillis`（DEBUG 钩子 `KANPAN_TEST_NET_SLOW`），
  /// 冷切、加对比都落在慢网里。
  private lazy var slowFrom = Date().addingTimeInterval(25)
  private let slowMillis = 12000

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_ROUTE_POLICY": "direct",
               "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT",
               "KANPAN_TEST_NET_SLOW": "\(Int(slowFrom.timeIntervalSince1970)):\(slowMillis)"]
    if name.contains("Compare") {
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1h"
      env["KANPAN_TEST_COMPARE_SYMBOLS"] = "binance/usd_m/ETHUSDT,binance/usd_m/SOLUSDT"
    } else {
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1h"
    }
    return env
  }

  private static let outDir: URL = {
    let raw = ProcessInfo.processInfo.environment["KANPAN_EVIDENCE_DIR"] ?? "/tmp/kp-burst"
    return URL(fileURLWithPath: raw, isDirectory: true)
  }()

  /// 等到慢网开始（首屏是在快网里起来的）。
  private func waitForSlowNetwork() {
    let left = slowFrom.timeIntervalSinceNow
    if left > 0 { _ = waitUntil(timeout: left + 1) { Date() > self.slowFrom.addingTimeInterval(0.5) } }
  }

  private func save(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  private func note(_ text: String) {
    print("体感取证|" + text)
    let a = XCTAttachment(string: text); a.name = "体感取证"; a.lifetime = .keepAlways; add(a)
  }

  /// 冷切：先搜一只量出第一行的位置，换个词后一打完字就点那个位置——不给列表预热留时间，
  /// 这样切过去的那一只手里确实没有快照。
  func testColdSwitchShowsPlaceholderAndSkeleton() throws {
    XCTAssertTrue(waitForLiveChart(), "图没起来")
    waitForSlowNetwork()
    XCTAssertTrue(app.openSymbolSearch(), "打不开搜索")
    let query = app.textFields[Ids.searchQuery]
    XCTAssertTrue(query.waitForExistence(timeout: Self.short))
    query.typeText("SOLUSDT")
    let probe = app.descendants(matching: .any)["symbols.row." + testInstrumentKey("SOLUSDT")]
    XCTAssertTrue(probe.waitForExistence(timeout: Self.long), "搜索结果里没有 SOLUSDT")
    let rowCenter = CGPoint(x: probe.frame.midX, y: probe.frame.midY)
    query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7))
    let target = ProcessInfo.processInfo.environment["KANPAN_EVIDENCE_COLD"] ?? "AVAXUSDT"
    query.typeText(target)
    app.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: rowCenter.x, dy: rowCenter.y)).tap()
    let t0 = Date()
    for i in 0..<20 {
      save(String(format: "冷切-%02d-%.0fms", i, Date().timeIntervalSince(t0) * 1000))
    }
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["symbol"] as? String ?? "").hasSuffix(target) && (self.chartInfo()["bars"] as? Int ?? 0) > 0
    }, "没换到 \(target)")
    save("冷切-到齐")
  }

  /// 对比：两只画齐以后再加一只、再减一只，期间已经画着的线一条都不许掉。
  func testCompareKeepsOldLinesWhileAdding() throws {
    XCTAssertTrue(waitUntil(timeout: 90) { (self.chartInfo()["compareReady"] as? Int ?? 0) == 2 }, "对比两条没齐")
    save("对比-两只")
    waitForSlowNetwork()
    app.buttons[Ids.topCompare].tap()
    let query = app.textFields[Ids.searchQuery]
    XCTAssertTrue(query.waitForExistence(timeout: 10), "顶栏加号没开出对比搜索页")
    query.tap(); query.typeText("DOGEUSDT")
    let mark = app.buttons["compare.toggle." + testInstrumentKey("DOGEUSDT")]
    XCTAssertTrue(mark.waitForExistence(timeout: 20), "搜「DOGEUSDT」没出那一行")
    mark.tap()
    var floor = Int.max, seen = 0
    // 搜索页盖着图时读不到诊断，只在图露出来以后取样。
    func sample() -> Int {
      guard let ready = chartInfo()["compareReady"] as? Int else { return -1 }
      floor = min(floor, ready); seen = max(seen, ready)
      return ready
    }
    app.buttons["compare.done"].tap()
    let t0 = Date()
    for i in 0..<10 {
      let ready = sample()
      save(String(format: "对比加一只-%02d-%.0fms-已画%d", i, Date().timeIntervalSince(t0) * 1000, ready))
    }
    note("加一只期间已画条数最少 \(floor)、最多 \(seen)")
    XCTAssertGreaterThanOrEqual(floor, 2, "加一只时旧线被清掉了")
    XCTAssertTrue(waitUntil(timeout: 60) { (self.chartInfo()["compareReady"] as? Int ?? 0) == 3 }, "第三只没画上")
    save("对比-三只到齐")

    // 减一只：剩下两条原地不动，不清空重画。
    app.buttons[Ids.topCompare].tap()
    let remove = app.buttons["compare.remove." + testInstrumentKey("SOLUSDT")]
    XCTAssertTrue(remove.waitForExistence(timeout: 10), "对比搜索页上没有 SOL 的移除")
    remove.tap()
    app.buttons["compare.done"].tap()
    floor = Int.max; seen = 0
    for i in 0..<6 {
      let ready = sample()
      save(String(format: "对比减一只-%02d-已画%d", i, ready))
    }
    note("减一只之后已画条数最少 \(floor)、最多 \(seen)")
    XCTAssertEqual(floor, 2, "减一只时剩下的线被清掉了")
  }
}
