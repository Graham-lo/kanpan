import XCTest

/// 「按我的习惯自动调整」（`Habits`）端到端：开关、「已学到的」页、清除；
/// 以及打开品种时的周期跟着习惯走、周期条钉住项不动、关掉后回到出厂行为。
///
/// `KANPAN_TEST_HABIT_SCALE=100`：停留时长放大一百倍记账，几秒的停留就算够学的量。
@MainActor
final class HabitLearningUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_HABIT_SCALE": "100"]
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/个性化学习-2026-09-28", isDirectory: true)

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  // ------------------------------------------------------------ 小工具

  private var habitSwitch: XCUIElement { app.buttons["settings.habits"] }
  private var learnedRow: XCUIElement { app.descendants(matching: .any)["settings.habits.learned"] }

  private func row(_ symbol: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
  }

  private func open(_ symbol: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页", file: file, line: line)
    let query = app.textFields[Ids.searchQuery]
    query.tap()
    query.typeText(symbol)
    let hit = row(symbol)
    XCTAssertTrue(hit.waitForExistence(timeout: Self.long), "搜 \(symbol) 没出那一行", file: file, line: line)
    hit.tap()
    XCTAssertTrue(waitUntil(timeout: 45) { self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) },
                  "点了 \(symbol) 图上没换过去：\(chartInfo())", file: file, line: line)
  }

  private func selected(_ raw: String) -> Bool { app.buttons[Ids.intervalChip(raw)].isSelected }

  private func pick(_ raw: String, file: StaticString = #filePath, line: UInt = #line) {
    app.tapIntervalChip(raw)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.selected(raw) }, "周期没落到 \(raw)", file: file, line: line)
  }

  /// 周期条上摆着的钉住项（按出现的先后）。
  private func pinnedChips() -> [String] {
    Ids.quickIntervals.filter { app.buttons[Ids.intervalChip($0)].exists }
  }

  private func dwell(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  }

  /// 设置页往下翻到「通用」那两行。
  private func revealHabitSwitch(file: StaticString = #filePath, line: UInt = #line) {
    openSettingsPage(file: file, line: line)
    XCTAssertTrue(habitSwitch.waitForExistence(timeout: Self.short), "设置页上没有「按我的习惯自动调整」",
                  file: file, line: line)
    for _ in 0..<6 where !habitSwitch.isHittable { app.swipeUp() }
    XCTAssertTrue(habitSwitch.isHittable, "「按我的习惯自动调整」翻不出来", file: file, line: line)
  }

  private func setHabits(_ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
    revealHabitSwitch(file: file, line: line)
    let want = on ? "开" : "关"
    if (habitSwitch.value as? String) != want { habitSwitch.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.habitSwitch.value as? String) == want },
                  "开关没切到「\(want)」", file: file, line: line)
  }

  private func shot(_ page: String, _ skin: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "iPhone17ProMax-\(page)-\(skin)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
  }

  // ------------------------------------------------------------ ① 开关 · 已学到的 · 清除

  func testSwitchDefaultsOnAndClearEmptiesTheList() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    // 先喂一点：在 ETH 上 4 时停一会儿，再换走，那一段就记上账了。
    open("ETHUSDT")
    pick("4h")
    dwell(8)
    open("SOLUSDT")

    revealHabitSwitch()
    XCTAssertEqual(habitSwitch.value as? String, "开", "出厂应当开着")
    XCTAssertTrue(learnedRow.waitForExistence(timeout: Self.short), "开着却没有「已学到的」")
    learnedRow.tap()
    let page = app.descendants(matching: .any)["habits.learned.page"]
    XCTAssertTrue(page.waitForExistence(timeout: Self.short), "「已学到的」页没推出来")
    let learned = app.descendants(matching: .any)["habits.learned.interval." + testInstrumentKey("ETHUSDT")]
    XCTAssertTrue(learned.waitForExistence(timeout: Self.short), "ETH 的 4 时没学进来\n\(app.debugDescription)")

    let clear = app.buttons["habits.clear"]
    XCTAssertTrue(clear.waitForExistence(timeout: Self.short), "没有「清除已学到的」")
    clear.tap()
    let confirm = app.buttons["habits.clear.confirm"].firstMatch
    XCTAssertTrue(confirm.waitForExistence(timeout: Self.short), "清除没弹确认")
    confirm.tap()
    XCTAssertTrue(app.descendants(matching: .any)["habits.learned.empty"].waitForExistence(timeout: Self.short),
                  "清除之后列表不空")
    XCTAssertFalse(learned.exists, "清除之后 ETH 那一行还在")
  }

  // ------------------------------------------------------------ ② 周期跟着习惯走 · 关掉回出厂

  func testOpeningIntervalFollowsTheHabitAndPinsStay() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    let pinsBefore = pinnedChips()
    XCTAssertFalse(pinsBefore.isEmpty, "周期条上没有钉住项")

    // ETH 上停在 4 时。
    open("ETHUSDT")
    pick("4h")
    dwell(8)
    // 换到 SOL，手动切 1 时。
    open("SOLUSDT")
    pick("1h")
    dwell(1)
    // 回到 ETH：应当直接是 4 时。
    open("ETHUSDT")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.selected("4h") },
                  "回到 ETH 没按习惯落在 4 时：\(chartInfo())")
    XCTAssertEqual(pinnedChips(), pinsBefore, "周期条钉住项被改了")

    // 关掉开关 → 出厂行为：打开品种沿用当前周期。
    setHabits(false)
    XCTAssertFalse(learnedRow.exists, "关掉之后「已学到的」还在")
    leaveSettings()
    open("SOLUSDT")
    pick("1h")
    dwell(4)
    open("ETHUSDT")
    dwell(1)
    XCTAssertTrue(selected("1h"), "关掉之后 ETH 仍然被改成了别的周期：\(chartInfo())")
    XCTAssertEqual(pinnedChips(), pinsBefore, "周期条钉住项被改了")
  }

  // ------------------------------------------------------------ 三套皮肤取证

  func testEvidenceThreeSkins() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    open("ETHUSDT")
    pick("4h")
    dwell(8)
    open("SOLUSDT")
    pick("1h")
    dwell(4)
    open("BTCUSDT")

    for skin in ["sage", "terra", "classic"] {
      openSettingsPage()
      let card = app.buttons["display.theme." + skin]
      XCTAssertTrue(card.waitForExistence(timeout: Self.short), "设置页上没有皮肤卡 \(skin)")
      for _ in 0..<3 where (card.value as? String) != "已选" {
        card.tap()
        _ = waitUntil(timeout: Self.short) { (card.value as? String) == "已选" }
      }
      XCTAssertEqual(card.value as? String, "已选", "皮肤没换到 \(skin)")
      for _ in 0..<6 where !(habitSwitch.exists && habitSwitch.isHittable && learnedRow.isHittable) { app.swipeUp() }
      XCTAssertTrue(learnedRow.isHittable, "「已学到的」翻不出来")
      dwell(0.6)
      shot("设置通用", skin)
      learnedRow.tap()
      XCTAssertTrue(app.descendants(matching: .any)["habits.learned.page"].waitForExistence(timeout: Self.short),
                    "「已学到的」页没推出来")
      dwell(0.6)
      shot("已学到的", skin)
      // 退回设置根，再回图表；下一轮从头进。
      app.navigationBars.buttons.firstMatch.tap()
      leaveSettings()
    }
  }
}
