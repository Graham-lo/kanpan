import UIKit
import XCTest

// ============================================================ 指标布局跟人走（2026-10-03）
//
// 09-27 的「周期分组指标」拆掉了（删除前代码在 tag before-remove-interval-indicator-groups-2026-10-03）：
// 指标布局一人一份，任何周期都一样。这条用例照交易员的路走：1h 加一个副图 → 切 1d、4h、5m 都还在、
// 第一帧就是、不弹任何「单独记」→ 指标页底部「恢复默认指标」→ 换周期仍是出厂那份。
// 截图落到 `docs/acceptance/指标跟人走-2026-10-03/<机型>-<步骤>.png`。
@MainActor
final class IndicatorLayoutPersonWideUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    // 出厂那六档（带 1日）：UI 用例沙盒默认钉的那组没有 1d。
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w"]
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/指标跟人走-2026-10-03", isDirectory: true)

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private func shot(_ step: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-\(step)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
  }

  private var subs: [String] { chartInfo()["subs"] as? [String] ?? [] }

  private func toast(containing text: String) -> XCUIElement {
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  /// 切周期，并在图第一次报出新周期的那一刻读副图——那一刻就该是这个人的那一份。
  private func switchInterval(_ raw: String) -> [String] {
    app.closeOpenPanel()
    app.tapIntervalChip(raw)
    var first: [String]?
    XCTAssertTrue(waitUntil(timeout: Self.long, poll: 0.05) {
      let info = self.chartInfo()
      guard info["interval"] as? String == raw else { return false }
      first = info["subs"] as? [String]
      return true
    }, "点了 \(raw) 图没换过去：\(chartInfo()["interval"] ?? "?")")
    return first ?? []
  }

  private func scrollPanel(to element: XCUIElement) {
    let content = app.scrollViews["panel.content"]
    guard content.waitForExistence(timeout: Self.short) else { return }
    for _ in 0..<14 {
      if element.exists, element.isHittable { return }
      let up = !element.exists || element.frame.midY > content.frame.midY
      content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.3))
        .press(forDuration: 0.1, thenDragTo: content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.3 : 0.7)))
    }
  }

  private func toggle(_ raw: String) {
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    let button = app.buttons[Ids.indicatorSwitch(raw)]
    expectExists(button, Self.short, "指标页里没有 \(raw) 的开关")
    scrollPanel(to: button)
    button.tap()
  }

  func testIndicatorLayoutIsTheSameOnEveryInterval() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    let born = switchInterval("1h")
    XCTAssertFalse(born.isEmpty, "出厂就该有副图")
    XCTAssertFalse(born.contains("KDJ"))

    // 一、1h 加 KDJ。
    toggle("KDJ")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs.contains("KDJ") }, "1h 上开了 KDJ 图上没有：\(subs)")
    shot("1-1小时加KDJ")
    let mine = subs

    // 二、换到任何周期都是这一份，第一帧就是，不说任何话。
    for raw in ["1d", "4h", "5m"] {
      XCTAssertEqual(switchInterval(raw), mine, "切到 \(raw) 指标变了（周期分组残留？）")
    }
    XCTAssertFalse(toast(containing: "单独记").waitForExistence(timeout: 1), "还在说「……现在单独记」")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    shot("2-切到5分还是那份")

    // 三、指标页底部「恢复默认指标」：回到出厂，换周期仍是出厂那份。
    let reset = app.buttons["indicator.reset"]
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    scrollPanel(to: reset)
    expectExists(reset, Self.short, "指标页底部没有「恢复默认指标」")
    shot("3-指标页底部恢复默认指标")
    reset.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs == born }, "恢复之后副图不是出厂那份：\(subs)")
    XCTAssertTrue(toast(containing: "已恢复默认指标").waitForExistence(timeout: Self.short))
    shot("4-恢复之后")
    XCTAssertEqual(switchInterval("1d"), born)
  }
}
