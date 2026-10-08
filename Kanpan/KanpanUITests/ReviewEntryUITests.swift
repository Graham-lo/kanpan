import XCTest

/// 进复盘 / 记一笔的入口收拢（审查 U6）。
///
/// 原来四条路：顶栏那颗（记号还是借来的「指标」折线）、图表设置「记一笔」、复盘本右上角
/// 「+」、复盘本空态那行「还没有记录 · 记一笔」。现在顶栏那颗换成专属的复盘本记号、只负责
/// 进复盘本；「记一笔」只留图表设置与复盘本「+」两处；空态只是一行字。
///
/// 2026-09-27 底栏四格：顶栏那颗复盘撤了，复盘本改从底栏「我的」→「复盘本」进（`me.review`），
/// 待判定的角标跟着挪到「我的」那一格上（`bottom.me.badge`，0 条不画）。「记一笔」两处不变。
@MainActor
final class ReviewEntryUITests: KanpanUICase {
  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": profile] }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  private func shot(_ name: String) {
    try? FileManager.default.createDirectory(atPath: "/tmp/kanpan-laneg-shots", withIntermediateDirectories: true)
    try? XCUIScreen.main.screenshot().pngRepresentation
      .write(to: URL(fileURLWithPath: "/tmp/kanpan-laneg-shots/\(name).png"))
  }

  func testRecordLivesInChartSettingsAndBookPlusOnly() throws {
    // 顶栏不再有复盘那颗；全新档案没有待判定，「我的」那一格也不画角标。
    XCTAssertTrue(app.buttons[Ids.intervalChart].waitForExistence(timeout: Self.long), "行情页没出来")
    XCTAssertFalse(app.buttons["top.review"].exists, "顶栏还挂着「复盘」那颗")
    XCTAssertFalse(app.descendants(matching: .any)[Ids.bottomMeBadge].firstMatch.exists,
                   "全新档案没有待判定，「我的」上不该有角标")

    // 2026-09-28 顶栏方案 B：「记一笔」到了顶栏，图表设置里那一行撤了；2026-10-08 起它在顶栏「⋯」菜单里。
    XCTAssertNotNil(app.topMenuItem(Ids.topNote, timeout: Self.short), "顶栏「⋯」菜单里没有「记一笔」")
    app.closeTopMenu()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons[Ids.topNote].exists }, "「⋯」菜单收不起来")
    app.buttons[Ids.intervalChart].tap()
    XCTAssertTrue(app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: Self.short), "图表设置没开出来")
    XCTAssertFalse(app.buttons["chart.record"].exists, "图表设置里还留着「记一笔」")
    XCTAssertTrue(app.closeChartPanel(), "图表设置收不起来")

    // 「我的 › 复盘本」只进复盘本。
    openMe()
    let entry = app.buttons[Ids.meReview]
    XCTAssertTrue(entry.waitForExistence(timeout: Self.short), "「我的」页上没有「复盘本」")
    XCTAssertTrue(entry.label.hasPrefix("复盘本"), "「复盘本」那一块念出来是「\(entry.label)」")
    shot("U6-我的-复盘本入口")
    entry.tap()
    XCTAssertTrue(app.buttons["review.back"].waitForExistence(timeout: Self.long), "「复盘本」没开出复盘本")
    let all = app.buttons["review.chip.all"]
    if all.waitForExistence(timeout: Self.short) { all.tap() }
    // 2026-10-08 走查：一条观点都没有时，空态是「还没有观点 · 在图上记一笔」加一颗「去记一笔」
    // ——空页本身就是第一次记一笔最顺手的地方，这里破例给一个入口。
    let empty = app.descendants(matching: .any)["review.empty"]
    XCTAssertTrue(empty.waitForExistence(timeout: Self.long), "全新档案的复盘本没有空态那行字")
    XCTAssertEqual(empty.label, "还没有观点 · 在图上记一笔", "空态那行字是「\(empty.label)」")
    XCTAssertTrue(app.buttons["review.empty.note"].exists, "「观点」空态下没有「去记一笔」")
    shot("U6-复盘本空态")

    // 复盘本「+」照旧开取景卡。
    let plus = app.buttons["review.capture"]
    XCTAssertTrue(plus.waitForExistence(timeout: Self.short), "复盘本右上角没有「+」")
    plus.tap()
    XCTAssertTrue(app.buttons["记下"].waitForExistence(timeout: Self.long), "点「+」没开出取景卡")
    shot("U6-复盘本加号-取景卡")
  }
}
