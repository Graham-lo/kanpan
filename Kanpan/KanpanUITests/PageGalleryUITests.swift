import UIKit
import XCTest

// ============================================================ 页面总览：把 app 各页走一遍、逐页截图
//
// 不是验收用例，是「给人看现在长什么样」的工具：按用户真实会走的路径，把四格底栏、
// 行情页上的各块面板与弹层、「我的」下面每一页、复盘本与交易回放、提醒、横屏画线台
// 各拍一张，落到 `KANPAN_GALLERY_DIR`（默认 /tmp/kanpan-gallery/<机型>/），
// 文件名带两位序号，按走的顺序排。
//
// 每一步都是「尽力而为」：某一页没开出来只记一行、跳过，不让后面的页跟着断。
// 复盘本走交易所夹具（同 `TradeReplayWalkthroughUITests`），不碰真账户。
//
// 平时不跑（不进界面矩阵），要截图时点名：
//   ONLY_TESTING=KanpanUITests/PageGalleryUITests ONLY_DEVICE="iPhone 17 Pro Max" bash Tools/ui-test.sh
@MainActor
final class PageGalleryUITests: KanpanUICase {
  private let profile = UUID().uuidString
  private var index = 0

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile,
     "KANPAN_TEST_QUICK": "5m,30m,1h,4h,1d,1w",
     "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT,XRPUSDT,DOGEUSDT,SUIUSDT,NVDAUSDT,XAUUSDT",
     "KANPAN_EXCHANGE_FIXTURE": "1",
     "KANPAN_EXCHANGE_FIXTURE_KEY": "DEMOREADONLY7C31"]
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
    continueAfterFailure = true
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  private var deviceTag: String {
    switch Int(min(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height).rounded()) {
    case 402: "iPhone16Pro"
    case 440: "iPhone17ProMax"
    case 430: "iPhone15ProMax"
    case let w: "宽\(w)"
    }
  }

  private lazy var outDir: URL = {
    let base = ProcessInfo.processInfo.environment["KANPAN_GALLERY_DIR"] ?? "/tmp/kanpan-gallery"
    return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(deviceTag, isDirectory: true)
  }()

  private func note(_ line: String) {
    print("总览|" + line)
    let a = XCTAttachment(string: line); a.name = "总览"; a.lifetime = .keepAlways; add(a)
  }

  private func settle(_ seconds: TimeInterval = 0.8) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  }

  private func shot(_ page: String) {
    index += 1
    let screenshot = XCUIScreen.main.screenshot()
    let name = String(format: "%02d-", index) + page
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    do { try screenshot.pngRepresentation.write(to: outDir.appendingPathComponent(name + ".png")) }
    catch { note("落盘失败|\(name)|\(error)") }
    note("拍|\(name)")
  }

  private func any(_ id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  /// 一步走不通只记下来，不打断后面。
  private func step(_ what: String, _ body: () -> Bool) {
    if !body() { note("跳过|\(what)") }
  }

  private func backToChart() {
    app.closeOpenPanel()
    let tab = app.buttons[Ids.bottomChart]
    if tab.waitForExistence(timeout: 5) { tab.tap() }
    _ = app.buttons[Ids.intervalChart].waitForExistence(timeout: 8)
  }

  private func systemBack() {
    let back = app.navigationBars.buttons.firstMatch
    if back.waitForExistence(timeout: 3) { back.tap() }
    settle(0.6)
  }

  // ------------------------------------------------------------ 走一遍

  func testTourEveryPage() throws {
    _ = waitForLiveChart()
    settle(1.5)
    shot("行情页")

    // 十字线 + 「创建提醒」药丸。
    step("十字线") {
      guard let mainH = chartInfo()["mainH"] as? Double, let plotW = chartInfo()["plotW"] as? Double else { return false }
      let canvas = app.otherElements["chart.canvas"]
      let scale = canvas.frame.height / max(1, chartInfo()["height"] as? Double ?? canvas.frame.height)
      canvas.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: plotW * scale * 0.8, dy: mainH * scale * 0.7)).tap()
      guard waitUntil(timeout: 8, { self.chartInfo()["crosshair"] as? Bool == true }) else { return false }
      settle(0.5); shot("行情页-十字线")
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { return false }
      chip.tap()
      guard app.textFields["alerts.new.price"].waitForExistence(timeout: 8) else { return false }
      settle(); shot("创建提醒")
      // 真建一条，后面「全部预警」拍出来的是有内容的列表，不是空态。
      let create = app.buttons["alerts.new.create"]
      if create.exists { create.tap(); settle(1.2) }
      app.closeOpenPanel()
      if app.textFields["alerts.new.price"].exists { systemBack() }
      if app.textFields["alerts.new.price"].exists {
        app.windows.firstMatch.swipeDown(velocity: .fast)
      }
      return true
    }
    backToChart()

    step("周期更多") {
      app.buttons[Ids.intervalMore].tap()
      guard app.buttons["period.row.1m"].waitForExistence(timeout: 8) else { return false }
      settle(0.6); shot("周期-更多弹层")
      let region = app.otherElements["PopoverDismissRegion"].firstMatch
      if region.exists { region.tap() } else { app.buttons[Ids.intervalMore].tap() }
      settle(0.6)
      return true
    }
    backToChart()

    step("分析面板") {
      guard app.openIndicatorPage() else { return false }
      settle(); shot("分析面板")
      let orderFlow = app.buttons["indicator.switch.ORDERFLOW"]
      let window = app.windows.firstMatch
      for _ in 0..<8 where !(orderFlow.exists && orderFlow.isHittable) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
          .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)))
      }
      settle(0.6); shot("分析面板-下半")
      return true
    }
    backToChart()

    step("指标参数") {
      openIndicatorEditor()
      settle(); shot("指标参数编辑")
      app.windows.firstMatch.swipeDown(velocity: .fast)
      return true
    }
    backToChart()

    step("图表设置") {
      app.buttons[Ids.intervalChart].tap()
      guard app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: 8) else { return false }
      settle(); shot("图表设置")
      _ = app.closeChartPanel()
      return true
    }
    backToChart()

    step("搜索") {
      guard app.openSymbolSearch() else { return false }
      settle(1.2); shot("搜索-空")
      let q = app.textFields[Ids.searchQuery]
      q.typeText("SOL")
      settle(1.5); shot("搜索-SOL")
      let all = app.buttons[Ids.searchAll]
      q.tap(); q.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "USD")
      if all.waitForExistence(timeout: 8) {
        all.tap()
        if app.textFields[Ids.symbolsQuery].waitForExistence(timeout: 8) { settle(1.5); shot("品种整页") }
        let back = app.buttons[Ids.symbolsBack]
        if back.exists { back.tap(); settle(0.6) }
      }
      let cancel = app.buttons["search.cancel"]
      if cancel.exists { cancel.tap() }
      return true
    }
    backToChart()

    // 横屏画线台。
    step("画线") {
      guard app.tapDrawEntry() else { return false }
      guard app.landscapeMarker.waitForExistence(timeout: 15) else { return false }
      settle(1.5); shot("横屏画线台")
      let tools = app.buttons["draw.tools"]
      if tools.exists { tools.tap(); settle(0.8); shot("横屏画线台-工具") ; app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); settle(0.5) }
      let exit = app.buttons[Ids.landscapeExit]
      if exit.exists { exit.tap() }
      let finish = app.buttons["draw.finish"]
      if finish.exists { finish.tap() }
      XCUIDevice.shared.orientation = .portrait
      settle(1.5)
      if app.landscapeMarker.exists {
        if exit.exists { exit.tap() }
        settle(1.0)
      }
      return true
    }
    XCUIDevice.shared.orientation = .portrait
    backToChart()

    // 底栏其余三格。
    step("自选") {
      guard app.openFavorites() else { return false }
      let crypto = app.buttons["favorites.group.加密"]
      if crypto.waitForExistence(timeout: 5) { crypto.tap() }
      settle(2.0); shot("自选")
      let more = app.buttons["favorites.more"]
      if more.exists { more.tap(); settle(0.8); shot("自选-更多菜单"); app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap(); settle(0.5) }
      return true
    }

    step("板块") {
      app.buttons[Ids.bottomSectors].tap()
      guard app.otherElements["sector.page"].waitForExistence(timeout: 15) else { return false }
      let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
      _ = waitUntil(timeout: 20) { row.exists }
      settle(1.5); shot("板块分类")
      let us = app.buttons["sector.market.us"]
      if us.exists { us.tap(); settle(1.5); shot("板块分类-美股") }
      let crypto = app.buttons["sector.market.crypto"]
      if crypto.exists { crypto.tap(); settle(1.0) }
      if row.exists {
        row.tap()
        if app.buttons["sector.list.back"].waitForExistence(timeout: 10) {
          settle(1.5); shot("板块-品种列表")
          app.buttons["sector.list.back"].tap(); settle(0.6)
        }
      }
      return true
    }

    step("我的") {
      guard app.openMePage() else { return false }
      _ = waitUntil(timeout: 15) { self.app.buttons[Ids.meReview].label.contains("笔") }
      settle(1.0); shot("我的")
      return true
    }

    step("账号") {
      guard app.openAccountFromMe() else { return false }
      settle(); shot("我的-账号")
      return true
    }

    step("复盘本") {
      guard app.openReviewBookFromMe() else { return false }
      settle(2.0); shot("复盘本")
      let trades = app.buttons["review.segment.交易"]
      if trades.waitForExistence(timeout: 5) {
        trades.tap(); settle(1.5); shot("复盘本-交易")
        let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
        if btc.firstMatch.waitForExistence(timeout: 15) {
          btc.element(boundBy: btc.count >= 2 ? 1 : 0).tap()
          if app.navigationBars["交易详情"].waitForExistence(timeout: 8) {
            settle(1.5); shot("交易详情")
            let disc = app.buttons["trade.detail.replay"]
            if disc.waitForExistence(timeout: 5) {
              disc.tap()
              if app.buttons["暂停"].waitForExistence(timeout: 20) {
                settle(6.0); shot("交易回放")
              }
              let exit = app.buttons["退出"]
              if exit.exists { exit.tap() } else { systemBack() }
              settle(1.0)
            }
            if app.navigationBars["交易详情"].exists { app.navigationBars["交易详情"].buttons.firstMatch.tap(); settle(0.6) }
          }
        }
      }
      let back = app.buttons["review.back"]
      if back.exists { back.tap(); settle(0.6) }
      return true
    }

    step("全部预警") {
      guard app.tapMeRow(Ids.meAlerts) else { return false }
      guard any("alerts.page").waitForExistence(timeout: 10) else { return false }
      settle(); shot("我的-全部预警")
      return true
    }

    step("朋友") {
      guard app.openFriendsFromMe() else { return false }
      settle(); shot("我的-朋友与收件箱")
      return true
    }

    step("交易所") {
      guard app.tapMeRow(Ids.meExchange) else { return false }
      guard any("me.exchange.page").waitForExistence(timeout: 10) else { return false }
      settle(); shot("我的-交易所")
      return true
    }

    step("设置") {
      guard app.openSettingsFromMe() else { return false }
      settle(); shot("我的-设置")
      return true
    }

    // 其余两套皮肤 + 深色下的行情页。
    for (skin, tag) in [("terra", "陶土"), ("classic", "经典")] {
      step("皮肤\(tag)") {
        guard app.openSettingsFromMe() else { return false }
        let card = app.buttons["display.theme." + skin]
        guard card.waitForExistence(timeout: 8) else { return false }
        for _ in 0..<4 where !card.isHittable { app.swipeDown() }
        card.tap()
        _ = waitUntil(timeout: Self.short) { (card.value as? String) == "已选" }
        leaveSettings()
        _ = waitForLiveChart()
        settle(1.5); shot("行情页-\(tag)")
        return true
      }
    }
    step("深色") {
      guard app.openSettingsFromMe() else { return false }
      let sage = app.buttons["display.theme.sage"]
      if sage.waitForExistence(timeout: 8) { sage.tap(); settle(0.5) }
      let dark = app.buttons["display.mode.深色"]
      guard dark.waitForExistence(timeout: 8) else { return false }
      dark.tap(); settle(0.8)
      leaveSettings()
      _ = waitForLiveChart()
      settle(1.5); shot("行情页-青苔深色")
      if app.openFavorites() {
        let crypto = app.buttons["favorites.group.加密"]
        if crypto.waitForExistence(timeout: 5) { crypto.tap() }
        settle(1.5); shot("自选-青苔深色")
      }
      if app.openMePage() { settle(1.0); shot("我的-青苔深色") }
      return true
    }
  }
}
