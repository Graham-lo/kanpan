import UIKit
import XCTest

// ============================================================ 画线条只露常用的几把（2026-10-05）
//
// 用户：「底下的画线工具只展示少量常用的，根据用户的使用频率智能展示即可，不然全部撑满了，
// 体验不好，把其它功能都遮盖了。」
//
// 以交易员的身份走：新装（没用过任何工具）打开画线——竖屏条上正好四把（趋势线、水平线、
// 斐波那契回撤、平行通道），横屏画线台底条正好五把（再加价时测量）；其余工具只在「全部工具」
// 面板里。从面板里挑一把条上没有的，它当场顶掉最后一格，手上拿着的东西条上看得见。
//
// 截图除了进 xcresult，也直接落一份 PNG 到验收目录（文件名带机型），见 `shot`。

@MainActor
final class DrawingToolBarUITests: KanpanUICase {

  private static let palette = [
    "hline", "trend", "vline", "channel", "fibonacci", "fibExtension", "measure", "note",
    "anchoredVWAP", "fixedVolumeProfile", "anchoredVolumeProfile", "position",
  ]

  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": UUID().uuidString] }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/画线条常用工具-2026-10-05", isDirectory: true)

  /// 机型短名：「16Pro」「17ProMax」。
  private var deviceTag: String {
    let model = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
    return model.replacingOccurrences(of: "iPhone ", with: "").replacingOccurrences(of: " ", with: "")
  }

  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(deviceTag)-\(name).png"))
  }

  /// 条上此刻摆着哪几把（按面板顺序列出 id，不是条上的左右顺序）。
  private func onBar() -> [String] { Self.palette.filter { app.buttons["draw." + $0].exists } }

  /// 从「全部工具」面板挑一把。
  private func pickFromPanel(_ kind: String) {
    app.buttons["draw.tools"].tap()
    let tile = app.buttons["draw.tool." + kind]
    expectExists(tile, Self.short, "「全部工具」没开出面板")
    tile.tap()
    expectGone(tile, Self.short, "挑完工具面板没收起来")
  }

  /// 竖屏：新装正好四把，挑一把条上没有的，它顶掉最后一格。
  func testPortraitBarShowsFourAndHeldReplacesLast() {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没进到竖屏画线栏")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onBar().count == 4 }, "竖屏条上摆了 \(onBar())")
    XCTAssertEqual(Set(onBar()), ["trend", "hline", "fibonacci", "channel"], "新装的四把不对：\(onBar())")
    // 四把从左到右：趋势线、水平线、斐波那契回撤、平行通道。
    let xs = ["trend", "hline", "fibonacci", "channel"].map { app.buttons["draw." + $0].frame.minX }
    XCTAssertEqual(xs, xs.sorted(), "四把的左右顺序不是按出厂偏好排的：\(xs)")
    XCTAssertTrue(app.buttons["draw.tools"].isHittable && app.buttons["draw.finish"].isHittable,
                  "「全部工具」或「完成」被挤得点不到")
    shot("竖屏画线条")

    pickFromPanel("position")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["draw.position"].exists },
                  "从面板挑了多空持仓框，条上没出现它")
    XCTAssertEqual(Set(onBar()), ["trend", "hline", "fibonacci", "position"], "该顶掉最后一格（平行通道）：\(onBar())")
    XCTAssertGreaterThan(app.buttons["draw.position"].frame.minX, app.buttons["draw.fibonacci"].frame.minX,
                         "挑来的那把没落在最后一格")
  }

  /// 横屏画线台：新装正好五把、一排摆得下不滚，挑一把条上没有的，它顶掉最后一格。
  func testLandscapeDockShowsFiveAndHeldReplacesLast() {
    XCTAssertTrue(app.tapDrawEntry(), "分析面板里没有「画线」")
    expectExists(app.descendants(matching: .any).matching(identifier: Ids.landscapeSymbol).firstMatch,
                 Self.long, "点「画线」没横过去")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onBar().count == 5 }, "横屏条上摆了 \(onBar())")
    XCTAssertEqual(Set(onBar()), ["trend", "hline", "fibonacci", "channel", "measure"], "新装的五把不对：\(onBar())")
    for id in onBar() {
      XCTAssertTrue(app.buttons["draw." + id].isHittable, "「\(id)」摆在条上却点不到（被挤出去了）")
    }
    shot("横屏画线台")

    pickFromPanel("note")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["draw.note"].exists },
                  "从面板挑了文字标注，条上没出现它")
    XCTAssertEqual(Set(onBar()), ["trend", "hline", "fibonacci", "channel", "note"], "该顶掉最后一格（价时测量）：\(onBar())")

    app.buttons[Ids.drawFinish].tap()
    expectExists(app.buttons[Ids.bottomMe], Self.long, "点「完成」没自己转回竖屏")
  }
}
