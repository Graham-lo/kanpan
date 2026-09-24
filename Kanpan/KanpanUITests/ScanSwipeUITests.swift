import XCTest

// ============================================================ 连续扫图（§10.1）与十字线上的「提醒我」
//
// 扫图是手势（顶栏价格区横滑），只有在真机 / 模拟器上才验得了；名单怎么走那一半纯算术
// 在 KanpanTests 的 Scan 组里用 swift-testing 守着，这儿只验它接到界面上之后人看到的样子。
//
// 2026-09-25 起十字线开着时周期条那一行只剩一颗「涨到 / 跌到 X 提醒我」（原来的
// 上一根 / 下一根 / 按此价画线 / 看细节整套撤了），这儿顺带在三套皮肤下各看它一眼。

@MainActor
final class ScanSwipeUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT"]
  }

  // ------------------------------------------------------------ 取证

  /// 截一张图：既进 xcresult（失败时有据可查），也落到 `/tmp/kanpan-s/` 下给人看。
  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-s", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  /// 图上这只的代号。诊断里报的是完整品种 key（`binance/usd_m/BTCUSDT`），这里只比代号。
  private func symbolOnChart() -> String {
    (chartInfo()["symbol"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
  }

  /// 顶栏价格区横滑一下。左滑 = 名单里的下一只。
  private func swipePrice(next: Bool) {
    // 价格区是个无障碍容器（`children: .contain`），不一定落在 otherElements 里，
    // 所以按 identifier 从整棵树上取。
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    XCTAssertTrue(quote.waitForExistence(timeout: Self.short), "顶栏价格区不在")
    let start = CGVector(dx: next ? 0.85 : 0.15, dy: 0.5)
    let end = CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)
    quote.coordinate(withNormalizedOffset: start)
      .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: end))
  }

  /// 从自选页点一行进图。顺带把「这一趟的名单」冻结下来。
  private func openFromFavorites(_ symbol: String) {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let row = app.buttons["favorites.open." + testInstrumentKey(symbol)]
    expectExists(row, Self.long, "自选页上没有 \(symbol) 这一行")
    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == symbol },
                  "点了 \(symbol) 没进它的图（现在是 \(symbolOnChart())）")
  }

  // ------------------------------------------------------------ 连续扫图

  /// 从自选分类进图 → 横滑换下一只 / 上一只 → 到头不循环 → 离开标签页名单作废。
  func testScanSwipesThroughTheFrozenFavoritesOrder() {
    openFromFavorites("BTCUSDT")
    shot("01-扫图-从自选进来的第一只")

    swipePrice(next: true)
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "ETHUSDT" },
                  "价格区左滑没换到名单里的下一只（现在是 \(symbolOnChart())）")
    shot("02-扫图-横滑到下一只")

    swipePrice(next: false)
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.symbolOnChart() == "BTCUSDT" },
                  "右滑没回到上一只（现在是 \(symbolOnChart())）")

    // 到头：名单第一只上再往回滑，停在原地，不循环到最后一只。
    swipePrice(next: false)
    XCTAssertFalse(waitUntil(timeout: 3) { self.symbolOnChart() != "BTCUSDT" },
                   "名单到头了还换了品种（现在是 \(symbolOnChart())）—— 不许循环")
    shot("03-扫图-到头不循环")

    // 离开这张表再回来：名单作废，横滑什么都不发生。
    // 标签栏这两下走 `tapButton`：合成事件偶尔会丢一下（见 `UITestSupport`），
    // 丢了就照同一个点再打一下，不挪位置。
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomFavorites], Self.long) {
      self.app.buttons["favorites.more"].exists
    }, "点「自选」没进自选页")
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomChart], Self.long) {
      self.app.buttons[Ids.intervalChart].exists
    }, "点「图表」没回行情页")
    swipePrice(next: true)
    XCTAssertFalse(waitUntil(timeout: 3) { self.symbolOnChart() != "BTCUSDT" },
                   "从底栏离开再回来，名单该清了，横滑却还在换品种")
    shot("04-扫图-离开再回来名单已清")
  }

  // ------------------------------------------------------------ 十字线上的「提醒我」

  /// 选中一根 → 周期条那一行换成「涨到 / 跌到 X 提醒我」→ 点它：十字线收掉、弹出「新建提醒」，
  /// 价格框里就是十字线那口价。三套皮肤各截一张药丸。
  func testCrosshairAlertChipOpensTheNewAlertSheetInEverySkin() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    for (skin, name) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      setSkin(skin)
      XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                    "\(name)：回到行情页没等到 K 线")
      if chartInfo()["crosshair"] as? Bool != true { selectACandle() }
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                    "\(name)：点图没选中一根")
      let chip = app.buttons["chart.crosshair.alert"]
      expectExists(chip, Self.short, "\(name)：十字线开着，周期条那一行却没有「提醒我」")
      XCTAssertTrue(chip.label.hasSuffix("提醒我")
                      && (chip.label.hasPrefix("涨到") || chip.label.hasPrefix("跌到") || chip.label.hasPrefix("在")),
                    "\(name)：药丸上没说哪个价：\(chip.label)")
      shot("08-提醒我-\(name)皮肤")
      // 收掉十字线，下一轮从干净的状态开始。
      selectACandle()
      _ = waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false }
    }

    // 最后一套上点一下药丸：十字线收掉，新建页带着那口价弹出来。
    selectACandle()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "点图没选中一根")
    let chip = app.buttons["chart.crosshair.alert"]
    expectExists(chip, Self.short, "十字线开着却没有「提醒我」")
    chip.tap()
    let price = app.textFields["alerts.new.price"]
    expectExists(price, Self.long, "点了「提醒我」没弹出新建提醒")
    XCTAssertFalse((price.value as? String ?? "").isEmpty, "新建页的价格框没带上十字线那口价")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false },
                  "点了药丸十字线还钉在图上")
    shot("09-提醒我-弹出新建提醒")
  }

  /// 图区靠右点一下（离最新近，细档不用补太多历史）。再点一下是收掉十字线。
  private func selectACandle() {
    let mainH = chartInfo()["mainH"] as? Double ?? 300
    let plotW = chartInfo()["plotW"] as? Double ?? 300
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * 0.8, dy: min(130, mainH / 2))).tap()
  }

  /// 换一套皮肤，再回行情页。皮肤卡的 id 是 `display.theme.<sage|terra|classic>`。
  private func setSkin(_ skin: String) {
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomSettings], Self.long) {
      self.app.buttons["display.theme.sage"].exists
    }, "点「设置」没进设置页")
    let card = app.buttons["display.theme." + skin]
    expectExists(card, Self.long, "设置页上没有皮肤卡 \(skin)")
    if (card.value as? String) != "已选" { card.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (card.value as? String) == "已选" },
                  "皮肤没切到 \(skin)")
    XCTAssertTrue(tapButton(app.buttons[Ids.bottomChart], Self.long) {
      self.app.buttons[Ids.intervalChart].exists
    }, "点「图表」没回行情页")
  }
}
