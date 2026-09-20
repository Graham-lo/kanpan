import XCTest

// ============================================================ 连续扫图 与 看细节（§10.1）
//
// 两件事都只有在真机 / 模拟器上才验得了：一件是手势（顶栏价格区横滑），另一件是
// 「换完档之后视野落在哪儿」——后者要图真的量出宽度、真的把那一段数据取回来。
// 纯算术那一半（名单怎么走、进哪一档、铺多宽、切回哪儿）在 `Kanpan/Scan` 那个包里
// 用 swift-testing 守着，这儿只验它们接到界面上之后人看到的样子。

@MainActor
final class ScanAndDetailZoomUITests: KanpanUICase {

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
  private func symbolOnChart() -> String { chartInfo()["symbol"] as? String ?? "" }

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
    let row = app.buttons["favorites.open." + symbol]
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

  // ------------------------------------------------------------ 看细节

  /// 4h 上选一根 →「看细节」→ 15m 把那一根铺满一屏 → 切回 4h 回到原来的视野。
  func testDetailZoomSpreadsOneCandleAndComesBack() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    app.tapIntervalChip("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChip("4h")].isSelected },
                  "没切到 4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                  "4h 上没等到 K 线")

    let before = chartInfo()
    let beforeTo = before["to"] as? Double ?? 0
    let beforeSpan = before["span"] as? Double ?? 0
    XCTAssertGreaterThan(beforeSpan, 0, "读不到 4h 的视野")

    selectACandle()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "点图没选中一根")

    let detail = app.buttons["chart.detailZoom"]
    expectExists(detail, Self.short, "十字线选中了一根，周期条行尾却没有「看细节」")
    shot("05-看细节-十字线选中一根")

    detail.tap()
    // 4h 的下一档是能把这根切成十几根的 15m（见 `DetailZoom.finer(than:)`）。
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChip("15m")].isSelected },
                  "「看细节」没进 15m")
    let fine = Double(15 * 60 * 1000)
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      guard let span = self.chartInfo()["span"] as? Double else { return false }
      // 一根 4h = 16 根 15m，两头各留半根 → 17 根。
      return abs(span - 17 * fine) < fine
    }, "15m 的视野不是「刚好那一根」：span=\(String(describing: chartInfo()["span"]))")
    // 钻下去就停在历史上了：行尾那颗「最新」得露面，否则人回不去（也说明
    // 程序摆的这一下视野没报上去）。
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "看细节停在历史上，周期条行尾却没有「最新」")
    shot("06-看细节-15m 铺开那一根")

    // 切回 4h：回到钻下去之前的那个视野，而不是 4h 的最新一屏。
    app.tapIntervalChip("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChip("4h")].isSelected },
                  "没切回 4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      guard let to = self.chartInfo()["to"] as? Double,
            let span = self.chartInfo()["span"] as? Double else { return false }
      return abs(to - beforeTo) < beforeSpan * 0.05 && abs(span - beforeSpan) < beforeSpan * 0.05
    }, "切回 4h 没回到原来的视野：to=\(String(describing: chartInfo()["to"])) 原 to=\(beforeTo)")
    shot("07-看细节-切回 4h 回到原视野")
  }

  // ------------------------------------------------------------ 三套皮肤

  /// 「看细节」在三套皮肤下都得像周期条自家的东西，而不是贴上去的一块。
  /// 这条只负责把它在三套皮肤下各画一张（人看），顺带守住「它真的在」。
  func testDetailButtonLooksAtHomeInEverySkin() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    app.tapIntervalChip("4h")
    for (skin, name) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      setSkin(skin)
      XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                    "\(name)：回到行情页没等到 K 线")
      if chartInfo()["crosshair"] as? Bool != true { selectACandle() }
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                    "\(name)：点图没选中一根")
      expectExists(app.buttons["chart.detailZoom"], Self.short, "\(name)：周期条上没有「看细节」")
      shot("08-看细节-\(name)皮肤")
      // 收掉十字线，下一轮从干净的状态开始。
      selectACandle()
      _ = waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false }
    }
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
