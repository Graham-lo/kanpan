import UIKit
import XCTest

// ============================================================ 阶段 1 取证：四格底栏 · 我的 · 行尾「分析」（画线与指标并列）
//
// 2026-09-27 方案「我的 · 自动复盘 · 周期分组指标」§1 的验收（`docs/方案-我的-自动复盘-周期分组指标-2026-09-27.md`）：
//
// 1. **周期条宽度**：出厂六档（5分 30分 1时 4时 1日 1周）满钉时，行尾三件
//    （更多 ▾ · 分析 · 图表设置）排得下，不缩字、不截字。读的是周期排
//    `interval.quick` 在 DEBUG 包里挂的读数（实际分到的宽度 − 六档字宽与内距，见 `IntervalBar.layoutReport`），
//    外加几何：三件都在页边距以内、互不重叠、各自的命中区够 44。
//    2026-09-27 这里是四件（画线夹在指标与图表设置之间，16 Pro 只剩 1.2pt、两颗记号命中区叠 10pt）；
//    09-28 用户定画线和指标并列归到一个大类：行尾那格「指标」改名「分析」，行尾回到三件，
//    分析面板四节 画线 · 指标 · 对比 · 主力订单流（画线那一行 `indicator.draw`）。
//    10-02 行尾那颗「最新」药丸按用户要求删了，最挤的一屏就是出厂态本身。
// 2. **截图**：浅色下青苔 / 陶土 / 经典三套皮肤，各拍「我的」、行情页、分析面板三张（文件名仍叫「指标」），
//    落到 `docs/acceptance/我的与四格底栏-2026-09-27/<机型>-<页>-<皮肤>.png`。
//    机型从窗口宽认（402 = iPhone 16 Pro、440 = iPhone 17 Pro Max），同一份用例两台各跑一遍。
//
// 模拟器进程和 xcodebuild 在同一个文件系统上，写绝对路径就是写进仓库（`SemanticColorEvidenceUITests` 同一个做法）。
@MainActor
final class MeAndFourTabsEvidenceUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    // 出厂那六档：UI 用例的沙盒默认钉的是另一组（带 1分 / 15分，见 `PrefsStore.uiTestQuick`）。
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w"]
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/我的与四格底栏-2026-09-27", isDirectory: true)

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

  private func note(_ line: String) {
    print("取证|" + line)
    let a = XCTAttachment(string: line); a.name = "取证"; a.lifetime = .keepAlways; add(a)
  }

  private func shot(_ page: String, _ skin: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let name = "\(deviceTag)-\(page)-\(skin)"
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    do { try screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png")) }
    catch { note("落盘失败|\(name)|\(error)") }
  }

  // ------------------------------------------------------------ 1. 周期条宽度

  func testIntervalBarFitsSix() throws {
    XCTAssertTrue(waitForLiveChart(), "图没活")

    let quick = app.otherElements["interval.quick"]
    XCTAssertTrue(quick.waitForExistence(timeout: Self.short), "周期排不在")
    let report = (quick.value as? String) ?? ""
    note("周期条|\(deviceTag)|\(report)")
    let slack = report.split(separator: " ").dropFirst().first.flatMap { Double($0) }
    XCTAssertNotNil(slack, "读不到周期排的余量：\(report)")
    XCTAssertGreaterThanOrEqual(slack ?? -1, 0, "六档 + 行尾三件排不下：\(report)")
    // 出厂六档在两台上都用不着收格子内距（2pt 原样）：收内距是留给用户钉出特别宽的组合时的退路。
    XCTAssertTrue(report.contains("内距 2.00"), "出厂六档就开始收格子内距了：\(report)")

    // 六档每一颗都在、字没被截（标签是完整的周期名）。
    for raw in ["5m", "30m", "1h", "4h", "1d", "1w"] {
      let chip = app.buttons["interval.chip.\(raw)"]
      XCTAssertTrue(chip.exists, "少了 \(raw) 那一档")
      note("档|\(raw)|\(chip.frame)")
    }

    let window = app.windows.firstMatch.frame
    let chart = app.buttons["interval.chart"]
    let indicators = app.buttons["interval.indicators"], more = app.buttons["interval.more"]
    XCTAssertFalse(app.buttons["interval.draw"].exists, "周期条行尾不该再有画线")
    note("行尾|更多 \(more.frame)|分析 \(indicators.frame)|图表设置 \(chart.frame)|窗口 \(window.width)")
    // 顺序：更多 · 分析 · 图表设置，命中区两两不叠。
    XCTAssertEqual(indicators.label, "分析", "行尾那格不叫「分析」")
    XCTAssertLessThanOrEqual(more.frame.maxX, indicators.frame.minX + 0.5, "「更多」和「分析」叠了")
    XCTAssertLessThanOrEqual(indicators.frame.maxX, chart.frame.minX + 0.5, "「分析」和图表设置叠了")
    // 命中区不小于 44。
    for (name, b) in [("更多", more), ("分析", indicators), ("图表设置", chart)] {
      XCTAssertGreaterThanOrEqual(b.frame.width, 43.5, "\(name)的命中区不到 44：\(b.frame)")
      XCTAssertGreaterThanOrEqual(b.frame.height, 43.5, "\(name)的命中区不到 44：\(b.frame)")
    }
    // 图表设置那颗的右缘不出窗口。
    XCTAssertLessThanOrEqual(chart.frame.maxX, window.maxX + 0.5, "图表设置被挤出屏：\(chart.frame)")
    shot("周期条最挤", "青苔")
  }

  // ------------------------------------------------------------ 2. 三皮肤截图

  func testShotsAcrossSkins() throws {
    for (skin, tag) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      applySkinFromMe(skin, tag)
      // 「我的」根页。
      let me = app.descendants(matching: .any).matching(identifier: "me.page").firstMatch
      XCTAssertTrue(me.waitForExistence(timeout: Self.short), "\(tag)：没回到「我的」")
      for id in ["me.account", "me.review", "me.alerts", "me.friends", "me.exchange", "me.settings"] {
        XCTAssertTrue(app.buttons[id].exists, "\(tag)：「我的」上没有 \(id)")
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.5))
      shot("我的", tag)

      // 行情页。
      app.buttons["bottom.chart"].tap()
      XCTAssertTrue(waitForLiveChart(), "\(tag)：图没活")
      RunLoop.main.run(until: Date().addingTimeInterval(1.0))
      shot("行情", tag)

      // 分析面板（周期条行尾「分析」直达）：四节 画线 · 指标 · 对比 · 主力订单流，画线在最上面。
      app.buttons["interval.indicators"].tap()
      XCTAssertTrue(app.buttons["indicator.switch.RSI"].waitForExistence(timeout: Self.short), "\(tag)：分析面板没开出来")
      XCTAssertEqual(app.staticTexts["panel.header"].label, "分析", "\(tag)：面板标题不是「分析」")
      let draw = app.buttons["indicator.draw"]
      XCTAssertTrue(draw.exists && draw.isEnabled, "\(tag)：分析面板第一节没有能点的「画线」")
      XCTAssertLessThan(draw.frame.maxY, app.buttons["indicator.switch.RSI"].frame.minY, "\(tag)：「画线」不在指标之上")
      RunLoop.main.run(until: Date().addingTimeInterval(0.8))
      shot("分析", tag)
      // 往下滚到「主力订单流」那节，再拍一张下半页（「对比」2026-10-05 起在顶栏，这一页不该再有）。
      let orderFlow = app.buttons["indicator.switch.ORDERFLOW"]
      let window = app.windows.firstMatch
      for _ in 0..<8 where !(orderFlow.exists && orderFlow.isHittable) {
        // 在面板内容区里往上拖（不碰把手，免得把面板本身拉高 / 收起）。
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
          .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
      }
      XCTAssertFalse(app.buttons["compare.add"].exists, "\(tag)：分析面板里还有「对比」节（应在顶栏）")
      XCTAssertTrue(orderFlow.exists, "\(tag)：分析面板没有「主力订单流」节")
      RunLoop.main.run(until: Date().addingTimeInterval(0.6))
      shot("分析下半", tag)
      dismissSheet(until: app.buttons["indicator.switch.RSI"])
    }
  }

  /// 「我的 › 设置」里换皮肤、落到浅色，再退回「我的」根页。
  private func applySkinFromMe(_ skin: String, _ tag: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    app.buttons["bottom.me"].tap()
    let settings = app.buttons["me.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: Self.short), "\(tag)：「我的」上没有设置", file: file, line: line)
    settings.tap()
    let card = app.buttons["display.theme." + skin]
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "\(tag)：设置页上没有皮肤卡", file: file, line: line)
    for _ in 0..<3 {
      if (card.value as? String) == "已选" { break }
      if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
      else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
      if waitUntil(timeout: Self.short, { (card.value as? String) == "已选" }) { break }
    }
    XCTAssertEqual(card.value as? String, "已选", "\(tag)：皮肤没换到 \(skin)", file: file, line: line)
    let light = app.buttons["display.mode.浅色"]
    XCTAssertTrue(light.waitForExistence(timeout: Self.short), "\(tag)：没有深浅档", file: file, line: line)
    if !light.isSelected { light.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { light.isSelected }, "\(tag)：没落在浅色", file: file, line: line)
    // 系统返回：设置是「我的」栈里推进来的一层。
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: Self.short), "\(tag)：设置页没有返回", file: file, line: line)
    back.tap()
    XCTAssertTrue(app.buttons["me.settings"].waitForExistence(timeout: Self.short), "\(tag)：没退回「我的」", file: file, line: line)
  }
}
