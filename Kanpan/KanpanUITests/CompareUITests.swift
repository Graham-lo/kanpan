import Foundation
import XCTest
import UIKit

@MainActor final class CompareUITests: XCTestCase {
  var app: XCUIApplication!
  let keys = ["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT"]
  var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  /// 本条用例自己注册的隔离账号；收尾时注销，不留在线上（D.7 审读：原来每跑一次留一个号）。
  var createdAccount: (name: String, password: String)?

  override func setUp() {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/BTCUSDT?interval=1m"
  }
  override func tearDown() async throws {
    guard let app else { return }
    if app.state == .runningForeground {
      if (testRun?.failureCount ?? 0) > 0 {
        let a = XCTAttachment(string: app.debugDescription + "\n" + String(describing: info()))
        a.lifetime = .keepAlways; add(a); shot("失败现场")
      }
      app.terminate()
    }
    XCUIDevice.shared.orientation = .portrait
    if let account = createdAccount { await TestAccounts.delete(account.name, password: account.password) }
  }
  func info() -> [String: Any] {
    guard canvas.exists, let text = canvas.value as? String, let bytes = text.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return [:] }
    return value
  }
  func wait(_ seconds: Double = 60, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
  }
  func ready(_ count: Int, interval: String = "1m") {
    XCTAssertTrue(wait(90) {
      let d = self.info()
      return d["interval"] as? String == interval && (d["bars"] as? Int ?? 0) >= 100
        && (d["compareReady"] as? Int ?? 0) == count
    }, "对比未到齐：\(info())")
  }
  func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let state = XCTAttachment(string: String(describing: info()))
    state.name = name + "-读数"; state.lifetime = .keepAlways; add(state)
  }
  /// 对比入口 2026-10-05 起在顶栏（10-08 起是「⋯」菜单里的「添加对比」`top.compare`），点开是搜索页的对比模式：
  /// 顶上「正在对比」一条（`compare.chip.<键>` / `compare.remove.<键>`），每行行尾一颗加号
  /// （`compare.toggle.<键>`，值是 可添加 / 已添加 / 已满 / 主图），「完成」（`compare.done`）收起。
  func openCompare() {
    XCTAssertTrue(app.openTopMenuItem(Ids.topCompare), "顶栏「⋯」菜单里没有「添加对比」")
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: 10), "「⋯ › 添加对比」没开出对比搜索页")
    XCTAssertTrue(app.buttons["compare.done"].exists, "开出来的不是对比模式（右上不是「完成」）")
  }
  /// 在对比搜索页里换一个查询词，返回那一行行尾的加号。
  @discardableResult func find(_ symbol: String) -> XCUIElement {
    let query = app.textFields[Ids.searchQuery]
    query.tap()
    if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
      query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
    query.typeText(symbol)
    let mark = app.buttons["compare.toggle." + testInstrumentKey(symbol)]
    XCTAssertTrue(mark.waitForExistence(timeout: 20), "搜「\(symbol)」没出那一行")
    return mark
  }
  func toggle(_ symbol: String, expect value: String) {
    let mark = find(symbol)
    mark.tap()
    XCTAssertTrue(wait(5) { mark.value as? String == value }, "\(symbol) 点完行尾不是「\(value)」：\(String(describing: mark.value))")
  }
  func doneCompare() {
    let done = app.buttons["compare.done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    XCTAssertTrue(wait(10) { !self.app.textFields[Ids.searchQuery].exists }, "「完成」没收起对比搜索页")
  }
  func chips() -> Int {
    app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "compare.chip.")).count
  }
  /// 图表设置（周期条行尾那颗）：「记一笔」还在这一页。
  func chartPanel() {
    let button = app.buttons["interval.chart"]
    XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
    XCTAssertTrue(app.buttons[Ids.chartPanelMarker].waitForExistence(timeout: 10))
  }
  func closePanel() {
    let done = app.buttons["panel.done"]
    XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
    XCTAssertTrue(wait(10) { !done.exists })
  }
  /// 对比集合满三只时：「⋯」菜单里「添加对比」还在，但是灰的；看完收起菜单。
  func assertTopCompareDisabledWhenFull() {
    let item = app.topMenuItem(Ids.topCompare)
    XCTAssertNotNil(item, "顶栏「⋯」菜单里没有「添加对比」")
    XCTAssertEqual(item?.isEnabled, false, "对比满三只了「⋯ › 添加对比」还点得动")
    app.closeTopMenu()
    XCTAssertTrue(wait(5) { !self.app.buttons[Ids.topCompare].exists }, "「⋯」菜单没收起")
  }
  /// 分析面板「对比」一节里点某只的「移除」（点完面板自己收起）。
  func removeFromPanel(_ key: String) {
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    let remove = app.buttons["compare.remove." + key]
    scrollPanel(to: remove)
    XCTAssertTrue(remove.isHittable, "分析面板里没有 \(key) 的「移除」")
    remove.tap()
    XCTAssertTrue(wait(10) { !remove.exists }, "点「移除」后面板没收起")
  }
  func addCompare(_ symbol: String) {
    openCompare(); toggle(symbol, expect: "已添加"); doneCompare()
  }

  /// 分析面板里的那一行（在下半截，先滚到点得到）。
  func scrollPanel(to element: XCUIElement) {
    let content = app.scrollViews["panel.content"]
    guard content.waitForExistence(timeout: 8) else { return }
    for _ in 0..<14 {
      if element.exists, element.isHittable { return }
      let up = !element.exists || element.frame.midY > content.frame.midY
      content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.7 : 0.3))
        .press(forDuration: 0.1, thenDragTo: content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.3 : 0.7)))
    }
  }

  /// 2026-10-06 用户：「分析里的对比要留」。分析面板「对比」一节 ›「添加对比」开的是「⋯ › 添加对比」
  /// 那同一张对比搜索页；加一只回到图上就有线，面板里多一行带「移除」的、底下一行「清除对比」。
  func testIndicatorPanelAddCompareOpensTheSameSearch() {
    app.launch(); ready(0)
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    let add = app.buttons["compare.add"]
    scrollPanel(to: add)
    XCTAssertTrue(add.isHittable, "分析面板里没有「添加对比」")
    shot("分析面板-对比一节")
    add.tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: 10), "「添加对比」没开出对比搜索页")
    XCTAssertTrue(app.buttons["compare.done"].exists, "开出来的不是对比模式（右上不是「完成」）")
    toggle("ETHUSDT", expect: "已添加")
    doneCompare(); ready(1)
    XCTAssertEqual(info()["compareKeys"] as? [String], [keys[0]])
    XCTAssertTrue(app.openIndicatorPage(), "第二次开不出分析面板")
    let clear = app.buttons["compare.clear"]
    scrollPanel(to: clear)
    XCTAssertTrue(app.buttons["compare.remove." + keys[0]].exists, "面板里没有刚加那只的「移除」")
    shot("分析面板-对比一只")
    clear.tap()
    ready(0)
    XCTAssertEqual(info()["compareKeys"] as? [String] ?? [], [])
  }

  /// 「⋯ › 添加对比」→ 对比模式：加两只、图上立刻出线；再加满三只，第四只被拒（行尾「已满」、集合不变、
  /// 提示「最多对比 3 个品种」）；主图那只那一行点不动；重启还在、这时「添加对比」是灰的；
  /// 从分析面板「移除」、行尾那颗、「正在对比」那条的 × 各删一只，最后清空。
  func testPanelCollectionPersistsAndClears() {
    app.launch(); ready(0)
    openCompare()
    XCTAssertFalse(app.descendants(matching: .any)["compare.strip"].exists, "一只都没选时不该有「正在对比」那条")
    toggle("ETHUSDT", expect: "已添加")
    toggle("SOLUSDT", expect: "已添加")
    XCTAssertEqual(chips(), 2, "「正在对比」那条不是两只")
    shot("对比-搜索页两只")
    doneCompare(); ready(2)
    XCTAssertEqual(info()["compareKeys"] as? [String], Array(keys.prefix(2)))
    shot("对比-两条线")

    openCompare()
    XCTAssertEqual(chips(), 2)
    let main = find("BTCUSDT")
    XCTAssertEqual(main.value as? String, "主图", "主图那只那一行不是「主图」")
    toggle("DOGEUSDT", expect: "已添加")
    let fourth = find("XRPUSDT")
    XCTAssertEqual(fourth.value as? String, "已满", "满三只后别的行不是「已满」")
    fourth.tap()
    XCTAssertTrue(app.staticTexts["最多对比 3 个品种"].waitForExistence(timeout: 3), "第四只没给「最多对比 3 个品种」提示")
    XCTAssertEqual(fourth.value as? String, "已满")
    XCTAssertEqual(chips(), 3, "第四只被塞进去了")
    shot("对比-第四只被拒")
    doneCompare(); ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)

    app.terminate(); app.launch(); ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    // 满三只时「⋯ › 添加对比」是灰的（点不进去），删一只走分析面板「对比」一节那行的「移除」。
    assertTopCompareDisabledWhenFull()
    removeFromPanel(keys[2])
    ready(2)
    XCTAssertEqual(info()["compareKeys"] as? [String], Array(keys.prefix(2)))
    openCompare()
    toggle("ETHUSDT", expect: "可添加")
    app.buttons["compare.remove." + keys[1]].tap()
    XCTAssertTrue(wait(5) { self.chips() == 0 })
    doneCompare(); ready(0)
    XCTAssertEqual(info()["percentAxis"] as? Bool, false)
    app.terminate(); app.launch(); ready(0)
  }
  func assertPercentReadout() throws {
    let d = info()
    let base = try XCTUnwrap(d["compareBaseOpen"] as? Double)
    let close = try XCTUnwrap(d["compareMainClose"] as? Double)
    let expected = (close / base - 1) * 100
    let label = abs(expected) < 0.005 ? "0%" : String(format: "%+.2f%%", expected)
    let legend = try XCTUnwrap(d["compareLegend"] as? [[String: String]])
    XCTAssertEqual(legend.first?["label"], label)
    if d["crosshair"] as? Bool == true {
      // 读数跟手指的价位走，不再等于收盘那一档；只验它是百分比口径。
      let axis = try XCTUnwrap(d["crossAxisLabel"] as? String)
      XCTAssertTrue(axis.hasSuffix("%"), "对比时十字线右轴读数不是百分比：\(axis)")
    }
    let ticks = try XCTUnwrap(d["compareTicks"] as? [Double])
    XCTAssertTrue(ticks.contains(0))
  }

  func testIntervalsCrosshairPanLandscapeAndReview() throws {
    app.launchEnvironment["KANPAN_TEST_COMPARE_SYMBOLS"] = keys.joined(separator: ",")
    app.launch(); ready(3)
    // 画线入口 09-28 起是「分析」面板第一节那一行：对比时置灰点不动。看完收面板，后面按图操作。
    XCTAssertTrue(app.openIndicatorPage(), "周期条「分析」没开出分析面板")
    let draw = app.buttons[Ids.indicatorDraw]
    XCTAssertTrue(draw.waitForExistence(timeout: 10), "分析面板第一节没有「画线」")
    XCTAssertFalse(draw.isEnabled, "对比期间分析面板「画线」还点得动")
    app.closeOpenPanel()
    XCTAssertEqual(info()["overlays"] as? [String], [])
    XCTAssertEqual(info()["drawingsVisible"] as? Bool, false)
    shot("BTC-ETH-SOL-DOGE-1m")
    try assertPercentReadout()

    // 十字线：图例按选中那根报、右轴那颗读数跟手指的价位走（「十字线价格」2026-09-28 收成
    // 「选中价位」定值，收设置项 B 组），两边都要是对比的百分比口径。
    let h = try XCTUnwrap(info()["mainH"] as? Double)
    let point = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 170, dy: h * 0.55))
    point.press(forDuration: 0.8)
    XCTAssertTrue(wait(10) { self.info()["crosshair"] as? Bool == true })
    try assertPercentReadout(); shot("对比-十字线")
    point.tap()
    XCTAssertTrue(wait(10) { self.info()["crosshair"] as? Bool == false })
    let before = try XCTUnwrap(info()["compareBaseTime"] as? Double)
    let start = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 110, dy: h * 0.55))
    let end = canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 280, dy: h * 0.55))
    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    XCTAssertTrue(wait(10) { (self.info()["compareBaseTime"] as? Double) != before })
    try assertPercentReadout(); shot("对比-平移重定基点")

    app.buttons["interval.chip.1h"].tap(); ready(3, interval: "1h")
    try assertPercentReadout(); shot("BTC-ETH-SOL-DOGE-1h")
    app.buttons["interval.more"].tap()
    let day = app.buttons["period.row.1d"]
    XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
    ready(3, interval: "1d"); try assertPercentReadout(); shot("BTC-ETH-SOL-DOGE-1d")

    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(15) { self.info()["percentAxis"] as? Bool == false })
    shot("对比-横屏暂退")
    XCUIDevice.shared.orientation = .portrait
    ready(3, interval: "1d")
    shot("对比-竖屏恢复")
    XCTAssertTrue(app.openTopMenuItem(Ids.topNote))  // 顶栏「⋯ › 记一笔」（2026-10-08 收进菜单）
    let dismiss = app.buttons["收起"]
    XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
    XCTAssertEqual(info()["percentAxis"] as? Bool, false)
    XCTAssertEqual(info()["compareKeys"] as? [String], [])
    shot("复盘-不含对比")
    dismiss.tap(); ready(3, interval: "1d")
  }

  func testSyncRestoresCollectionIntoFreshInstallationProfile() {
    let name = "compare_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    let password = "Cmp_" + UUID().uuidString.prefix(8) + "9x"
    app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.43-160-232-253.sslip.io"
    app.launch(); ready(0)
    addCompare("ETHUSDT"); addCompare("SOLUSDT"); addCompare("DOGEUSDT"); ready(3)
    /// 2026-09-27 底栏四格：账号从「我的」顶上那张账号卡推进去。
    func openAccount() {
      XCTAssertTrue(app.openAccountFromMe(), "「我的 › 账号」没推出账号页")
    }
    func credentials() {
      let user = app.textFields["account.email"]
      XCTAssertTrue(user.waitForExistence(timeout: 10)); user.tap(); user.typeText(name)
      let secure = app.secureTextFields["account.password"]
      secure.tap()
      if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
      // XCTest 的 typeText 活动可能记录输入；密码只经本机临时粘贴板传入并立即清空。
      UIPasteboard.general.setItems([["public.utf8-plain-text": password]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(30)])
      defer { UIPasteboard.general.items = [] }
      secure.press(forDuration: 1.1)
      let paste = [app.menuItems["粘贴"], app.menuItems["Paste"], app.buttons["粘贴"], app.buttons["Paste"]]
      XCTAssertTrue(wait(10) { paste.contains { $0.exists && $0.isHittable } })
      paste.first { $0.exists && $0.isHittable }!.tap()
      UIPasteboard.general.items = []
      app.buttons["account.submit"].tap()
      XCTAssertTrue(wait(60) { !self.app.accountView.exists })
    }
    // 先记下再注册：注册成功但回包丢了也能在收尾时删掉。
    createdAccount = (name, password)
    openAccount(); app.buttons["注册"].tap(); credentials()
    // 产品的立即同步入口，待同步消失后才切到全新的本地档案。
    // 注册成功后账号页收起、回到「我的」，要从账号卡重新进账号。
    openAccount()
    let sync = app.buttons["同步"]
    XCTAssertTrue(sync.waitForExistence(timeout: 20)); sync.tap()
    let now = app.buttons["立即同步"]
    XCTAssertTrue(now.waitForExistence(timeout: 20)); now.tap()
    XCTAssertTrue(wait(180) { self.app.staticTexts["已同步"].exists })
    app.terminate()
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch(); ready(0)
    openAccount(); credentials()
    app.buttons["bottom.chart"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    shot("对比-新安装档案登录恢复")
    print("COMPARE_SYNC new profile restored three comparison keys; fixture account deleted in tearDown")
  }

  func testScanningKeepsCollectionAndIgnoresTheMainInstrument() {
    app.launchEnvironment["KANPAN_TEST_COMPARE_SYMBOLS"] = keys.joined(separator: ",")
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = ["BTCUSDT", "ETHUSDT", "SOLUSDT"].map(testInstrumentKey).joined(separator: ",")
    app.launch(); ready(3)
    let originalColors = info()["compareColors"] as? [String]
    app.buttons["bottom.favorites"].tap()
    let row = app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")]
    XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap(); ready(3)
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    XCTAssertTrue(quote.waitForExistence(timeout: 10))
    func swipe(_ next: Bool) {
      quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.85 : 0.15, dy: 0.5))
        .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)))
    }
    swipe(true)
    XCTAssertTrue(wait(30) { self.info()["symbol"] as? String == self.keys[0] })
    ready(2)
    XCTAssertEqual(info()["compareKeys"] as? [String], Array(keys.dropFirst()))
    XCTAssertEqual(info()["compareColors"] as? [String], originalColors.map { Array($0.dropFirst()) })
    // ETH 只是这张图临时忽略；持久集合仍是三只（「⋯ › 添加对比」照样是灰的），
    // 分析面板「对比」一节里 ETH 那行的「移除」仍在。
    assertTopCompareDisabledWhenFull()
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    let ethRemove = app.buttons["compare.remove." + keys[0]]
    scrollPanel(to: ethRemove)
    XCTAssertTrue(ethRemove.exists, "扫到 ETH 后分析面板里 ETH 那行的「移除」没了")
    app.closeOpenPanel()
    shot("对比-扫到ETH忽略自身")
    swipe(false)
    XCTAssertTrue(wait(30) { self.info()["symbol"] as? String == testInstrumentKey("BTCUSDT") })
    ready(3)
    XCTAssertEqual(info()["compareKeys"] as? [String], keys)
    shot("对比-扫回BTC集合保留")
  }

}
