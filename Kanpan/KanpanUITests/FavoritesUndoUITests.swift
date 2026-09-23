import XCTest

// ============================================================ 自选删除可撤销（P3-4）+ 三套皮肤
//
// 「取消自选」以前是一下就没、没有回头路的动作：手滑删掉一只，只能自己去搜回来、
// 再摆回它原来那一类、重新钉上。所以移除之后底下出来一条「已移除 · 撤销」（停 5 秒），
// 撤销走的是正常的写入通道（`SymbolPickerModel.restoreFavorites`），
// 位置、分类、钉住状态一起回来，也就跟着同步上去。
//
// 这一条是全 app 里**唯一**允许的那种底部横条（带动作的才留，纯报喜的一律删掉，见 P3-8）。
//
// 顺带在这儿把三套皮肤的首屏各截一张：皮肤是全局的，改了周期条槽位、十字线那一行
// 之后三套都得看一眼。

@MainActor
final class FavoritesUndoUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT"]
  }

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-p3", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  // ------------------------------------------------------------ 已移除 · 撤销

  func testRemovingAFavoriteOffersUndoAndPutsTheRowBack() {
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    let eth = app.buttons["favorites.open.ETHUSDT"]
    XCTAssertTrue(eth.waitForExistence(timeout: Self.long), "自选页上没有 ETHUSDT")
    let before = rowOrder()
    XCTAssertEqual(before.count, 3, "三只自选没都摆出来：\(before)")

    eth.swipeLeft()
    let remove = app.buttons["删除"]
    XCTAssertTrue(remove.waitForExistence(timeout: Self.short), "右滑没露出「删除」")
    remove.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !eth.exists }, "点了「删除」那一行还在")

    let undo = app.buttons["toast.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.short),
                  "移除之后底下没有「已移除 · 撤销」那一条")
    XCTAssertTrue(app.staticTexts["已移除"].exists, "那一条上写的不是「已移除」")
    shot("11-自选-已移除撤销")

    undo.tap()
    XCTAssertTrue(eth.waitForExistence(timeout: Self.short), "点了「撤销」自选没回来")
    XCTAssertEqual(rowOrder(), before, "撤销之后那一行没回到原来的位置")
    shot("12-自选-撤销之后回到原来那一行")
  }

  // ------------------------------------------------------------ 设置里的两件事也能撤（P2.7）
  //
  // 以前设置页说话走的是它自己的 `PanelToast`，和自选页那条不是一回事；现在全 app 只有
  // `ToastCenter` 那一条。这两条量的是：设置页上说的话出现在同一条上、带着同一颗「撤销」。

  func testClearingTheCacheCanBeUndone() {
    let clear = openSettingsRow("settings.clearCache")
    clear.tap()
    let undo = app.buttons["toast.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.short), "清缓存之后底下没有「撤销」")
    XCTAssertTrue(app.staticTexts["已清缓存"].exists, "那一条上写的不是「已清缓存」")
    shot("13-设置-已清缓存撤销")
    undo.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !undo.exists }, "点了「撤销」提示没收起来")
  }

  func testRestoringDefaultsCanBeUndone() {
    let reset = openSettingsRow("settings.reset")
    reset.tap()
    let undo = app.buttons["toast.undo"]
    XCTAssertTrue(undo.waitForExistence(timeout: Self.short), "恢复默认之后底下没有「撤销」")
    XCTAssertTrue(app.staticTexts["已恢复默认"].exists, "那一条上写的不是「已恢复默认」")
    shot("14-设置-已恢复默认撤销")
    undo.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !undo.exists }, "点了「撤销」提示没收起来")
  }

  private func openSettingsRow(_ id: String) -> XCUIElement {
    let tab = app.buttons["bottom.settings"]
    XCTAssertTrue(tab.waitForExistence(timeout: Self.long), "标签栏上没有「设置」")
    tab.tap()
    let row = app.descendants(matching: .any).matching(identifier: id).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: Self.long), "设置页上没有 \(id)")
    for _ in 0..<4 where !row.isHittable { app.swipeUp() }
    return row
  }

  /// 三行此刻从上到下的顺序。
  private func rowOrder() -> [String] {
    ["BTCUSDT", "ETHUSDT", "SOLUSDT"].compactMap { symbol -> (String, CGFloat)? in
      guard let snap = try? app.buttons["favorites.open.\(symbol)"].snapshot() else { return nil }
      return (symbol, snap.frame.minY)
    }
    .sorted { $0.1 < $1.1 }
    .map(\.0)
  }

  // ------------------------------------------------------------ 三套皮肤的首屏

  func testHomeLooksRightInEverySkin() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    for (skin, name) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      setSkin(skin)
      XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                    "\(name)：回到行情页没等到 K 线")
      shot("13-首屏-\(name)")
    }
  }

  /// 换一套皮肤再回行情页。皮肤卡的 id 是 `display.theme.<sage|terra|classic>`。
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
