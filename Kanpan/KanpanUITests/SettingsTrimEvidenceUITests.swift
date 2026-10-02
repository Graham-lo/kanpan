import UIKit
import XCTest

// ============================================================ 收设置项（2026-09-28）取证
//
// 收设置项 A–H 之后剩下的两张设置页（「我的 › 设置」与图表设置）在三套皮肤下长什么样，
// 以及 A 组「全 app 时间一律上海 UTC+8、日线边界仍是 UTC 0」在十字线读数上的实证。
//
// - 三套皮肤（浅色）各拍「我的 › 设置」上 / 下两屏、图表设置一张，落到
//   附件 `<机型>-<页>-<皮肤>`（从 xcresult 导出到 `docs/acceptance/收设置项-2026-09-28/`）；同时量一遍两页上看得见的
//   按钮、开关的命中区，比 44pt 小的写进「取证」附件（不在这里判失败——系统返回键之类不归我们管）。
// - 时间口径：app 以 `TZ=America/New_York` 启动（设备时区故意不是上海），1 小时线上十字线落在
//   最新一根，读数的时刻必须是这一根开盘时刻的上海时间；换到日线，读数必须是「某日 08:00」
//   ——UTC 0 点开盘、上海时间写出来就是 08:00。
@MainActor
final class SettingsTrimEvidenceUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w",
     "TZ": "America/New_York"]
  }

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
  }

  /// 此刻屏上看得见、点得到的按钮与开关里，命中区两边都不到 44pt 的。
  private func smallTargets(_ page: String) {
    let window = app.windows.firstMatch.frame
    var small: [String] = []
    for query in [app.buttons, app.switches] {
      for element in query.allElementsBoundByIndex where element.exists && element.isHittable {
        let f = element.frame
        guard window.intersects(f), f.width > 0, f.height > 0 else { continue }
        if f.height < 44 && f.width < 44 {
          small.append("\(element.identifier.isEmpty ? element.label : element.identifier) \(Int(f.width))×\(Int(f.height))")
        }
      }
    }
    note("命中区|\(page)|" + (small.isEmpty ? "全部 ≥ 44" : small.joined(separator: "；")))
  }

  // ------------------------------------------------------------ 1. 两张设置页 × 三套皮肤

  func testSettingsPagesAcrossSkins() throws {
    for (skin, tag) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      applySkinFromMe(skin, tag)

      // 我的 › 设置：上半屏、滚到底再一屏。
      app.buttons["me.settings"].tap()
      let card = app.buttons["display.theme." + skin]
      XCTAssertTrue(card.waitForExistence(timeout: Self.short), "\(tag)：设置页没开出来")
      for gone in ["display.ambient", "settings.changeBasis", "settings.keepAwake", "settings.clearCache",
                   "settings.magnet", "alerts.watchMove.threshold"] {
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: gone).firstMatch.exists,
                       "\(tag)：设置页上还有 \(gone)")
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.6))
      shot("我的设置-上", tag)
      smallTargets("我的设置-上-\(tag)")
      for _ in 0..<4 { app.swipeUp() }
      RunLoop.main.run(until: Date().addingTimeInterval(0.6))
      shot("我的设置-下", tag)
      smallTargets("我的设置-下-\(tag)")
      let back = app.navigationBars.buttons.firstMatch
      XCTAssertTrue(back.waitForExistence(timeout: Self.short), "\(tag)：设置页没有返回")
      back.tap()
      XCTAssertTrue(app.buttons["me.settings"].waitForExistence(timeout: Self.short), "\(tag)：没退回「我的」")

      // 图表设置（周期条行尾那颗记号）。
      app.buttons["bottom.chart"].tap()
      XCTAssertTrue(waitForLiveChart(), "\(tag)：图没活")
      let entry = app.buttons["interval.chart"]
      XCTAssertTrue(entry.waitForExistence(timeout: Self.short), "\(tag)：周期条上没有图表设置入口")
      entry.tap()
      let header = app.staticTexts["panel.header"]
      XCTAssertTrue(header.waitForExistence(timeout: Self.short), "\(tag)：图表设置没开出来")
      for gone in ["chart.more", "chart.lastLine"] {
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: gone).firstMatch.exists,
                       "\(tag)：图表设置里还有 \(gone)")
      }
      RunLoop.main.run(until: Date().addingTimeInterval(0.8))
      shot("图表设置", tag)
      smallTargets("图表设置-\(tag)")
      app.closeChartPanel()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !header.exists }, "\(tag)：图表设置收不起来")
    }
  }

  // ------------------------------------------------------------ 2. 十字线读数：上海时间、日线 UTC 0

  func testCrosshairReadsShanghaiTimeAndDailyOpensAtUTCMidnight() throws {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let newYork = TimeZone(identifier: "America/New_York")!
    func stamp(_ date: Date, _ zone: TimeZone) -> String {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd HH:mm"
      return f.string(from: date)
    }

    // 1 小时线。
    try pick(interval: "1h")
    let hourRead = try crosshairOnLatest(step: 3600)
    let hourOpen = hourRead.open
    note("时间口径|1h|读数「\(hourRead.text)」|这一根开盘 上海 \(stamp(hourOpen, shanghai)) · 纽约 \(stamp(hourOpen, newYork))")
    XCTAssertEqual(hourRead.text, stamp(hourOpen, shanghai), "1 小时线十字线读数不是上海时间")
    XCTAssertNotEqual(hourRead.text, stamp(hourOpen, newYork), "读数跟着设备时区（纽约）走了")
    shot("十字线-1时-上海时间", "青苔")
    dismissCrosshair()

    // 日线：UTC 0 点开盘 → 上海 08:00。
    try pick(interval: "1d")
    let dayRead = try crosshairOnLatest(step: 86_400)
    note("时间口径|1d|读数「\(dayRead.text)」|这一根开盘 UTC \(stamp(dayRead.open, TimeZone(identifier: "UTC")!))")
    XCTAssertTrue(dayRead.text.hasSuffix(" 08:00"), "日线读数不是 08:00（UTC 0 点）：\(dayRead.text)")
    XCTAssertEqual(dayRead.text, stamp(dayRead.open, shanghai), "日线开盘不是 UTC 0 点")
    shot("十字线-日线-UTC0开盘", "青苔")
    dismissCrosshair()
  }

  private func pick(interval: String) throws {
    let chip = app.buttons["interval.chip.\(interval)"]
    XCTAssertTrue(chip.waitForExistence(timeout: Self.short), "周期条上没有 \(interval)")
    chip.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["interval"] as? String) == interval && (self.chartInfo()["bars"] as? Int ?? 0) > 0
    } || waitForLiveChart(), "换到 \(interval) 之后图没活")
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
  }

  /// 点在最右一根附近出十字线，读头部那块开高低收的第一行；按 `crossIndex` 与 `bars` 算这一根的开盘时刻。
  private func crosshairOnLatest(step: TimeInterval) throws -> (text: String, open: Date) {
    let canvas = app.otherElements["chart.canvas"]
    let info = chartInfo()
    let plotW = try XCTUnwrap(info["plotW"] as? Double)
    let mainH = try XCTUnwrap(info["mainH"] as? Double)
    let height = try XCTUnwrap(info["height"] as? Double)
    let scale = canvas.frame.height / max(1, height)
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * scale - 6, dy: mainH * scale * 0.5)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true }, "十字线没出来")
    let label = app.staticTexts["chart.topOHLC"]
    XCTAssertTrue(label.waitForExistence(timeout: Self.short), "头部没有十字线读数")
    let now = Date()
    let after = chartInfo()
    let bars = try XCTUnwrap(after["bars"] as? Int)
    let index = try XCTUnwrap(after["crossIndex"] as? Int)
    let latestOpen = floor(now.timeIntervalSince1970 / step) * step
    let open = Date(timeIntervalSince1970: latestOpen - Double(bars - 1 - index) * step)
    let text = String(label.label.split(separator: "\n").first ?? "")
    note("十字线|bars \(bars)|index \(index)|\(label.label.replacingOccurrences(of: "\n", with: " / "))")
    return (text, open)
  }

  private func dismissCrosshair() {
    let canvas = app.otherElements["chart.canvas"]
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).tap()
    _ = waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false }
  }

  /// 「我的 › 设置」里换皮肤、落到浅色，再退回「我的」根页（同 `MeAndFourTabsEvidenceUITests`）。
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
    let back = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: Self.short), "\(tag)：设置页没有返回", file: file, line: line)
    back.tap()
    XCTAssertTrue(app.buttons["me.settings"].waitForExistence(timeout: Self.short), "\(tag)：没退回「我的」", file: file, line: line)
  }
}
