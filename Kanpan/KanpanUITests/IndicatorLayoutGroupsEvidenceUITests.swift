import UIKit
import XCTest

// ============================================================ 阶段 2 取证：指标按周期分组记忆
//
// 2026-09-27 方案「我的 · 自动复盘 · 周期分组指标」§4（`docs/方案-我的-自动复盘-周期分组指标-2026-09-27.md`）：
// 周期分三组（分钟 / 小时 / 日），三组起初共用一份，在哪一组里改了就只有那一组分叉，
// 分叉那一下浮一句「××周期的指标现在单独记」，每组只说一次。
//
// 这条用例照着交易员的路走一遍：1h 加一个副图 → 切到 1d（不受影响）→ 回 1h（还在）→
// 4h（同组，一样）→ 小时组再改一项（不再说那句话）→ 指标页底部「恢复这一组的默认」。
// 截图落到 `docs/acceptance/指标按周期分组-2026-09-27/<机型>-<步骤>.png`。
@MainActor
final class IndicatorLayoutGroupsEvidenceUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    // 出厂那六档（带 1日）：UI 用例沙盒默认钉的那组没有 1d。
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w"]
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/指标按周期分组-2026-09-27", isDirectory: true)

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  private var deviceTag: String {
    switch Int(app.windows.firstMatch.frame.width.rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
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

  /// 切周期，并在图第一次报出新周期的那一刻读副图——那一刻就该已经是新组那份（同一帧重算）。
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
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「指标」没开出指标页")
    let button = app.buttons[Ids.indicatorSwitch(raw)]
    expectExists(button, Self.short, "指标页里没有 \(raw) 的开关")
    scrollPanel(to: button)
    button.tap()
  }

  func testEachIntervalGroupRemembersItsOwnIndicators() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")
    let born = switchInterval("1h")
    XCTAssertFalse(born.isEmpty, "出厂就该有副图")
    XCTAssertFalse(born.contains("KDJ"))

    // 一、1h 加 KDJ：小时组分叉，说一次。
    toggle("KDJ")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs.contains("KDJ") }, "1h 上开了 KDJ 图上没有：\(subs)")
    XCTAssertTrue(toast(containing: "小时周期的指标现在单独记").waitForExistence(timeout: Self.short),
                  "小时组第一次分叉没说那句话")
    shot("1-1小时加KDJ-提示")
    let hourSubs = subs

    // 二、切到 1d：日组还是共用那份，第一帧就是。
    let dayFirst = switchInterval("1d")
    XCTAssertEqual(dayFirst, born, "切到 1d 的第一帧副图不是日组那份（闪了一下小时组的？）")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs == born })
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    shot("2-切到1日不受影响")

    // 三、回 1h：刚才那份还在；4h 同组，一样。
    XCTAssertEqual(switchInterval("1h"), hourSubs, "回到 1h，KDJ 不在了")
    XCTAssertEqual(switchInterval("4h"), hourSubs, "4h 和 1h 同组，副图该一样")
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    shot("3-回到小时组还在")

    // 四、小时组再改一项：不再说那句话。
    toggle("KDJ")
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.subs.contains("KDJ") })
    XCTAssertFalse(toast(containing: "现在单独记").waitForExistence(timeout: 2), "同一组第二次改又说了一遍")

    // 五、指标页底部「恢复这一组的默认」：小时组回到出厂，日组不动。
    toggle("RSI")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs.contains("RSI") })
    let reset = app.buttons["indicator.resetGroup"]
    scrollPanel(to: reset)
    expectExists(reset, Self.short, "指标页底部没有「恢复这一组的默认」")
    shot("4-指标页底部恢复这一组的默认")
    reset.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.subs == born }, "恢复之后副图不是出厂那份：\(subs)")
    XCTAssertTrue(toast(containing: "已恢复这一组的默认").waitForExistence(timeout: Self.short))
    shot("5-恢复之后")
    XCTAssertEqual(switchInterval("1d"), born)
  }
}
