import XCTest

/// 提醒走一遍用户真的会走的那条路：
/// 画一条水平线 → 选中栏上那句「跌到 X 叫我」 → 点一下 → 线右端多一枚铃铛 →
/// 设置里那一行「提醒」 → 总表。
///
/// 2026-09-23 起画完线什么都不问（原来那句「要不要提醒、六秒后自己消失」撤了），
/// 提醒只在选中一条线时、选中栏左边那颗胶囊上开关。这条用例盯着三件光靠单测证明不了的事：
///
/// 1. **胶囊不盖画布。** 它长在画线栏的选中栏里，不是系统弹窗、也不是浮在图上的卡片
///    （`kanpan-no-floating-controls-over-chart`），换上来时画布一个 pt 都不动。
/// 2. **铃铛真的挂上去了，再点一下又摘掉。** 图那一侧只认 id，诊断里 `drawingAlerted`
///    就是它画了记号的那几条。
/// 3. **不碰就只是线。** 画完不弹任何东西，也不会自己挂上提醒。
///
/// 到价判定在服务端，这儿一个字都不验——客户端压根没有那段代码。
@MainActor final class AlertsFlowUITests: XCTestCase {
  private var app: XCUIApplication!
  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  /// 截图落到这儿，给人看的那一份。
  private let shots = URL(fileURLWithPath: "/tmp/kanpan-c", isDirectory: true)
  /// 「已触发」那条用例开局就要有一条响过的提醒。跑用例的是另一个进程，
  /// 塞不进 app 的沙盒，所以走启动环境这条路（`AlertStore.testSeed`，只在 DEBUG 下编）：
  /// 模拟的是服务端判到价之后、同步换下来的那一份。
  private var needsSeed: Bool { name.contains("Fired") }

  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    if needsSeed { app.launchEnvironment["KANPAN_TEST_ALERT_FIRED"] = "BTCUSDT" }
    // P3.1：输价建的提醒一挂上就喂两口夹住目标价的价（`AlertEngine.feedTestTouch`）；
    // 自选波动开关一打开就往 BTC 上喂一段五分钟涨 2% 的价（`WatchMoveMonitor.injectTestMove`）。
    if name.contains("TypedPrice") { app.launchEnvironment["KANPAN_TEST_ALERT_TOUCH"] = "BTCUSDT" }
    if name.contains("WatchMove") {
      app.launchEnvironment["KANPAN_TEST_WATCHMOVE"] = "BTCUSDT"
      app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    }
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    let chartTab = app.buttons["bottom.chart"]
    if chartTab.waitForExistence(timeout: 5), !canvas.exists { chartTab.tap() }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30), "K 线画布没出来")
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 64 },
                  "K 线没拿到数据：\(info())")
  }

  override func tearDown() async throws {
    guard app.state != .notRunning, app.state != .unknown else { return }
    app.terminate()
  }

  // ------------------------------------------------------------ 小工具

  private func info() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }

  private func ids() -> [String] { (info()["drawingIDs"] as? [String]) ?? [] }
  private func alerted() -> [String] { (info()["drawingAlerted"] as? [String]) ?? [] }

  private func wait(seconds: Double = 20, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  /// 截一张。既进 xcresult（失败时好回看），也落一份 PNG 到 `/tmp/kanpan-c/` 给人翻。
  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot); a.name = name
    a.lifetime = .keepAlways; add(a)
    try? screenshot.pngRepresentation.write(to: shots.appendingPathComponent(name + ".png"))
  }

  /// 主图那一段里的一个点。副图区画不了线，y 按 `mainH` 折算。
  private func point(x: Double, y: Double) throws -> XCUICoordinate {
    let frame = canvas.frame
    let height = try XCTUnwrap(info()["height"] as? Double)
    let mainH = try XCTUnwrap(info()["mainH"] as? Double)
    let scale = frame.height / height
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.width * x, dy: mainH * scale * y))
  }

  /// 进竖屏画线态。机器忙的时候那一趟「横过去再转回来」偶尔会掉一下点击
  /// （方向切换的动画比 `enterDrawingInPortrait()` 里等的 15s 还慢），所以重试三轮；
  /// 已经在画线态里就直接认。
  private func enterDrawing() -> Bool {
    for round in 0..<3 {
      if inPortraitDrawing { return true }
      if app.enterDrawingInPortrait() { return true }
      shot("_进画线态第\(round + 1)轮没成")
      if app.landscapeMarker.exists { app.rotateDrawingToPortraitByHand() }
      XCUIDevice.shared.orientation = .portrait
    }
    return app.buttons["draw.finish"].waitForExistence(timeout: 10) && inPortraitDrawing
  }

  /// 在不在**竖屏**画线栏上。「完成」两个方向都有，横屏顶上还多一颗品种胶囊，
  /// 拿这两个一起判（画线进行中横屏侧栏整条收起，「竖屏」不再能当路标）。
  private var inPortraitDrawing: Bool {
    app.buttons["draw.finish"].exists && !app.landscapeMarker.exists
  }

  /// 落一笔水平线（一下就成，`pointCount == 1`）。
  ///
  /// 先量坐标再点工具，落完笔这儿一个查询都不做，让调用方直接去接胶囊。
  private func tapHorizontal(at y: Double) throws {
    let target = try point(x: 0.5, y: y)
    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "画线栏上没有水平线")
    // chip 住在一条横向 ScrollView 里，XCUI 自己那套可点性判定在这种容器上会抖，
    // 所以按坐标打（`UITestSupport.tapIntervalChip` 同一个理由）。
    chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    target.tap()
  }

  /// 选中栏上那颗提醒胶囊。
  private var chip: XCUIElement { app.buttons["alert.line"] }

  /// 画一笔，等它被选中、胶囊露面。
  ///
  /// 落笔本身偶尔会掉（工具 chip 的那一下被滚动容器吃掉、或者方向切换的动画还没停），
  /// 所以最多试三轮，每轮换一个高度免得两笔叠在一起。
  @discardableResult
  private func drawAndAwaitChip(at y: Double, _ what: String) throws -> Bool {
    for round in 0..<3 {
      let before = ids().count
      try tapHorizontal(at: y + Double(round) * 0.06)
      if wait(seconds: 5, { self.ids().count > before }), chip.waitForExistence(timeout: 5) { return true }
      shot("_\(what)第\(round + 1)轮没出胶囊")
    }
    return false
  }

  /// 提醒总表那张半屏。
  private var alertsPage: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch
  }

  /// 半屏面板收掉。提醒总表是 sheet，收它才能去点设置页上别的行。
  ///
  /// 这一下点空了表就一直盖着，后面点设置页上的任何一行都会报「not hittable」，
  /// 所以最多三轮，每轮先按表头那颗「‹」，按不着就从表头往下拽。
  ///
  /// 2026-09-21 之前这儿很不稳，根因在 app 那一侧：`alerts.page` 原来挂在整张
  /// `PanelSheet` 上，把「‹」自己的 `panel.done` 盖掉了（见 `AlertListPage`）。
  /// 那头改成隐形记号之后，这儿按标识符就能正常找到「‹」。
  private func closeSheet() {
    for _ in 0..<3 {
      if !alertsPage.exists { return }
      let back = app.buttons["panel.done"]
      if back.waitForExistence(timeout: 3) {
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      } else {
        // 兜底按用户的手势来：从表头那一条往下拽。`swipeDown()` 打在正文上
        // 只会滚列表，拽不动这张表。
        alertsPage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
          .press(forDuration: 0.1,
                 thenDragTo: alertsPage.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
      }
      if alertsPage.waitForNonExistence(timeout: 5) { return }
    }
  }

  /// 换到某一套皮肤，并且**确认真的换过去了**再往下走。
  ///
  /// 只 `tap()` 一下不够：这几颗按钮排在一张会随半屏收起而重排的网格上，坐标兜底那一下
  /// 有时候打在隔壁格子里，于是截出来的三张图有两张是同一套皮肤（跑到过 sage 与 terra
  /// 的 PNG 逐字节相同）。选中的那颗 `value` 是「已选」，按这个复核，没换过去就再点一轮。
  private func selectSkin(_ skin: String) -> Bool {
    for _ in 0..<3 {
      let button = app.buttons["display.theme." + skin]
      guard button.waitForExistence(timeout: 8) else { continue }
      if wait(seconds: 8, { button.isHittable }) { button.tap() }
      else { button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
      if wait(seconds: 5, { (self.app.buttons["display.theme." + skin].value as? String) == "已选" }) { return true }
    }
    return false
  }

  /// 设置页上那一行「提醒」点开总表。
  ///
  /// 换皮肤之后整页重画，那一行会有一小段量不出 frame（XCUI 报的是
  /// 「Activation point invalid and no suggested hit points」），所以每一轮都重新
  /// 查一次元素、等它量得出来再按坐标打，最多五轮。
  @discardableResult
  private func openAlertsPage() -> Bool {
    for _ in 0..<5 {
      let row = app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch
      guard row.waitForExistence(timeout: 8) else { continue }
      guard wait(seconds: 5, { row.frame.height > 1 && row.frame.width > 1 }) else { continue }
      row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      if alertsPage.waitForExistence(timeout: 5) { return true }
    }
    return false
  }

  // ------------------------------------------------------------ 主路

  func testDrawingALineOffersAnAlertAndKeepsIt() throws {
    // ① 画一条水平线：它自动选中，选中栏左边就是那句「跌到 / 涨到 X 叫我」。
    XCTAssertTrue(enterDrawing(), "没能进入竖屏画线态")
    let canvasFrame = canvas.frame
    XCTAssertTrue(try drawAndAwaitChip(at: 0.35, "画完出胶囊"), "画完选中之后没有提醒胶囊：\(info())")
    XCTAssertEqual(chip.value as? String, "off", "没点就开了提醒")
    XCTAssertTrue(chip.label.hasSuffix("提醒我") && (chip.label.contains("跌到") || chip.label.contains("涨到")),
                  "胶囊上没说到哪个价会响：\(chip.label)")
    XCTAssertFalse(chip.frame.intersects(canvas.frame), "胶囊压在画布上了：胶囊 \(chip.frame)，画布 \(canvas.frame)")
    XCTAssertEqual(canvas.frame, canvasFrame, "选中栏换上来，画布跟着动了")
    XCTAssertTrue(app.alerts.count == 0, "画完线不许弹系统弹窗")
    XCTAssertFalse(app.otherElements["alert.prompt"].exists, "画完线又问了一句")
    XCTAssertEqual(alerted(), [], "没人点胶囊，铃铛却挂上了")
    shot("01-画完选中出胶囊")

    // ② 点一下开：线右端挂铃铛，胶囊变成「会叫你」。再点一下关，再点一下开。
    let line = try XCTUnwrap(ids().last)
    chip.tap()
    XCTAssertTrue(wait(seconds: 8) { self.alerted() == [line] }, "铃铛没挂上：alerted=\(alerted())，线=\(line)")
    XCTAssertTrue(wait(seconds: 5) { self.chip.value as? String == "on" }, "开了提醒胶囊还是关着的样子")
    shot("02-线上挂了铃铛")
    chip.tap()
    XCTAssertTrue(wait(seconds: 8) { self.alerted().isEmpty }, "再点一下铃铛没摘掉：\(alerted())")
    XCTAssertTrue(wait(seconds: 5) { self.chip.value as? String == "off" }, "关了提醒胶囊还亮着")
    chip.tap()
    XCTAssertTrue(wait(seconds: 8) { self.alerted() == [line] }, "第二次打开铃铛没挂上：\(alerted())")

    // ③ 设置 →「提醒」→ 总表。
    let settingsTab = app.buttons["bottom.settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 8), "标签栏上没有「设置」")
    settingsTab.tap()
    let entry = app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "设置里没有「提醒」这一行")
    shot("03-设置里的提醒入口")
    XCTAssertTrue(openAlertsPage(), "「提醒」没开出总表")
    XCTAssertTrue(app.staticTexts["等它碰到"].waitForExistence(timeout: 5),
                  "总表里那一条没写它在等什么：\(app.debugDescription)")
    shot("04-提醒总表")

    // ④ 条件只在这一页改：触碰时 / 收盘穿过后。
    let condition = app.descendants(matching: .any).matching(identifier: "alerts.condition").firstMatch
    XCTAssertTrue(condition.waitForExistence(timeout: 5), "总表里没有条件开关")

    // ⑤ 三套皮肤各看一眼。
    for skin in ["sage", "terra", "classic"] {
      closeSheet()
      XCTAssertTrue(selectSkin(skin), "没能换到皮肤「\(skin)」")
      XCTAssertTrue(openAlertsPage(), "皮肤「\(skin)」下开不出总表")
      shot("05-提醒总表-" + skin)
    }
  }

  /// 不碰胶囊 = 只画线：画完什么都不弹，过一阵也不会自己挂上提醒。
  func testDrawingALineAsksNothing() throws {
    XCTAssertTrue(enterDrawing(), "没能进入竖屏画线态")
    XCTAssertTrue(try drawAndAwaitChip(at: 0.5, "不碰"), "画完没有选中栏：\(info())")
    let lines = ids()
    XCTAssertFalse(lines.isEmpty, "水平线没画上：\(info())")
    XCTAssertFalse(app.otherElements["alert.prompt"].waitForExistence(timeout: 7), "画完线又问了一句")
    XCTAssertEqual(ids(), lines, "线被带走了")
    XCTAssertEqual(alerted(), [], "没人点胶囊，铃铛却挂上了")
    shot("06-不碰只剩线")
  }

  /// 没有推送时，用户是怎么看见「已经响了」的。
  ///
  /// 现在这台机器上没有 APNs（没开发者会员），所以这条路是：服务端判到价 → 往
  /// `alerts` 集合写一条 `status=fired` → app 回到前台拉一次同步 → 存档里那条变成
  /// 已触发 → 提醒总表上写明「已触发 · 时间」，右边给一颗「再次提醒」。
  ///
  /// 用例把「同步换下来的那一份」直接摆成开局状态（启动环境 `KANPAN_TEST_ALERT_FIRED`，
  /// 由 `AlertStore.testSeed` 在 DEBUG 下种），量的是这一段的**下半截**：
  /// 用户打开提醒总表看得见、按得着。
  func testAFiredAlertIsVisibleAndCanBeRearmed() throws {
    let settingsTab = app.buttons["bottom.settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "标签栏上没有「设置」")
    settingsTab.tap()
    let entry = app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "设置里没有「提醒」这一行")
    entry.tap()
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch.waitForExistence(timeout: 8),
                  "「提醒」没开出总表")
    let rearm = app.buttons["再次提醒"]
    XCTAssertTrue(rearm.waitForExistence(timeout: 8), "响过的那条没有「再次提醒」：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已触发")).count > 0,
                  "总表里没写「已触发」那一行")
    shot("07-已触发与再次提醒")

    // 按下去就重新上膛：那一行回到「等它碰到」，「再次提醒」跟着收掉。
    rearm.tap()
    XCTAssertTrue(wait(seconds: 8) { !self.app.buttons["再次提醒"].exists }, "按了「再次提醒」还挂着那颗按钮")
    XCTAssertTrue(app.staticTexts["等它碰到"].waitForExistence(timeout: 5), "重新上膛之后那一行没回到「等它碰到」")
    shot("08-再次提醒之后重新上膛")
  }

  // ------------------------------------------------------------ P3.1

  /// 设置 →「提醒」总表。
  private func openAlertsFromSettings() {
    let settingsTab = app.buttons["bottom.settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "标签栏上没有「设置」")
    settingsTab.tap()
    XCTAssertTrue(openAlertsPage(), "「提醒」没开出总表")
  }

  /// 总表右上「新建」→ 品种默认图上那只 → 手输一个价 →「加提醒」→ 总表里多一条，
  /// 碰到那个价之后变成「已触发」。
  ///
  /// 方向不让选：页上只有一行「当前 xxx」。碰价那一段由启动环境
  /// `KANPAN_TEST_ALERT_TOUCH` 喂（真行情一两分钟里未必走到那个价），喂的价走的是和真行情
  /// 同一条路：桶 → 判定 → `markFired` → 总表。
  func testATypedPriceBecomesAnAlertAndFires() throws {
    openAlertsFromSettings()
    let create = app.buttons["alerts.new"]
    XCTAssertTrue(create.waitForExistence(timeout: 8), "总表右上没有「新建」")
    create.tap()
    let symbol = app.textFields["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: 8), "「新建」没开出那一页")
    XCTAssertEqual(symbol.value as? String, "BTCUSDT", "品种没默认成图上那只")
    let current = app.staticTexts["alerts.new.current"]
    XCTAssertTrue(wait(seconds: 20) { (current.label).hasPrefix("当前 ") && current.label != "当前 —" },
                  "那一行没写现价：\(current.label)")
    let price = app.textFields["alerts.new.price"]
    XCTAssertTrue(price.waitForExistence(timeout: 5), "没有价格输入框")
    XCTAssertFalse(app.steppers.count > 0, "价格不许用加减步进器")
    price.tap()
    price.typeText("12345")
    shot("09-新建价格提醒")
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isEnabled, "「加提醒」按不下去")
    add.tap()
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 8), "加完没回到总表")
    let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "BTC ", "12345")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 8), "总表里没有这条价格提醒：\(app.debugDescription)")
    XCTAssertTrue(wait(seconds: 20) {
      self.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已触发")).count > 0
    }, "碰到那个价之后没变成「已触发」：\(app.debugDescription)")
    shot("10-价格提醒已触发")
  }

  /// 从行情页出发（开局停在 BTC 的图上）→ 设置 → 提醒 → 新建：品种框里是给人看的代号
  /// `BTCUSDT`，不是内部的 `binance/usd_m/BTCUSDT`；点进框里整串是选中的，直接打「ETH」
  /// 就覆盖成 ETH，认成 ETHUSDT、有现价，建出来的是一条 ETH 的提醒。
  func testNewAlertSymbolFieldShowsTheCodeAndTakesATypedSymbol() throws {
    openAlertsFromSettings()
    let create = app.buttons["alerts.new"]
    XCTAssertTrue(create.waitForExistence(timeout: 8), "总表右上没有「新建」")
    create.tap()
    let symbol = app.textFields["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: 8), "「新建」没开出那一页")
    XCTAssertEqual(symbol.value as? String, "BTCUSDT", "品种框该是代号，不是规范键")
    shot("15-新建提醒-预填代号")
    symbol.tap()
    symbol.typeText("ETH")
    XCTAssertTrue(wait(seconds: 5) { symbol.value as? String == "ETH" },
                  "点进品种框没有整串选中，打完是：\(symbol.value as? String ?? "nil")")
    let current = app.staticTexts["alerts.new.current"]
    XCTAssertTrue(wait(seconds: 20) { current.label.hasPrefix("当前 ") && current.label != "当前 —" },
                  "改成 ETH 之后那一行没写现价：\(current.label)")
    shot("16-新建提醒-改成ETH")
    let price = app.textFields["alerts.new.price"]
    XCTAssertTrue(price.waitForExistence(timeout: 5), "没有价格输入框")
    price.tap()
    price.typeText("12345")
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isEnabled, "「加提醒」按不下去")
    shot("17-新建提醒-ETH填好")
    add.tap()
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 8), "加完没回到总表")
    let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "ETH ", "12345")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 8), "总表里没有这条 ETH 的提醒：\(app.debugDescription)")
    shot("18-总表里的ETH提醒")
  }

  /// P3.3「盯一个」：总表里一条价格提醒 →「盯一个」→ 锁屏上挂出一块实时活动（品种、现价、
  /// 24h 涨跌、离提醒价多少）→ 回 app 跟几拍价再锁屏看它更新 → 删掉提醒，锁屏那块跟着收。
  func testWatchingOneAlertPutsItOnTheLockScreen() throws {
    openAlertsFromSettings()
    let create = app.buttons["alerts.new"]
    XCTAssertTrue(create.waitForExistence(timeout: 8), "总表右上没有「新建」")
    create.tap()
    let current = app.staticTexts["alerts.new.current"]
    XCTAssertTrue(wait(seconds: 20) { current.label.hasPrefix("当前 ") && current.label != "当前 —" },
                  "那一行没写现价：\(current.label)")
    let price = app.textFields["alerts.new.price"]
    XCTAssertTrue(price.waitForExistence(timeout: 5), "没有价格输入框")
    price.tap(); price.typeText("12345")
    app.buttons["alerts.new.create"].tap()
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 8), "加完没回到总表")
    let watch = app.buttons["alerts.watch"]
    XCTAssertTrue(watch.waitForExistence(timeout: 8), "价格提醒那一行没有「盯一个」：\(app.debugDescription)")
    XCTAssertEqual(watch.value as? String, "off")
    watch.tap()
    XCTAssertTrue(wait(seconds: 8) { watch.value as? String == "on" }, "点了「盯一个」没变成「盯着」")
    shot("13-盯一个")

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let card = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "离提醒价")).firstMatch
    lock()
    XCTAssertTrue(card.waitForExistence(timeout: 15), "锁屏上没有那块实时活动：\(springboard.debugDescription)")
    let first = lockScreenPrice(springboard)
    shot("14-锁屏实时活动")
    unlock()
    // 前台跟几拍价（控制器五秒一拍），再锁屏看它换了没有。
    Thread.sleep(forTimeInterval: 14)
    lock()
    XCTAssertTrue(card.waitForExistence(timeout: 15), "第二次锁屏那块不见了")
    let second = lockScreenPrice(springboard)
    shot("15-锁屏价格更新")
    print("P3.3 锁屏价：\(first) → \(second)")
    unlock()

    // 删掉提醒 → 锁屏那块收起。
    let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "BTC ", "12345")).firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 8), "回到 app 总表不见了：\(app.debugDescription)")
    // 按住慢拖 120pt 露出删除砖（快甩会越过「滑到底」门槛直接删，看不到砖）。
    let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: -120, dy: 0)),
               withVelocity: .slow, thenHoldForDuration: 0.3)
    let delete = app.buttons["swipe.delete"]
    XCTAssertTrue(wait(seconds: 5) { delete.exists && delete.frame.width >= 60 }, "左划没划出「删除」")
    delete.tap()
    XCTAssertTrue(row.waitForNonExistence(timeout: 8), "删了行还在")
    lock()
    XCTAssertTrue(card.waitForNonExistence(timeout: 15), "提醒删了，锁屏那块还挂着")
    shot("16-删掉提醒活动收起")
    unlock()
  }

  private func lock() {
    XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
    Thread.sleep(forTimeInterval: 1.5)
    XCUIDevice.shared.press(.home)  // 点亮屏幕，停在锁屏上
    Thread.sleep(forTimeInterval: 2)
  }

  private func unlock() {
    XCUIDevice.shared.press(.home)
    Thread.sleep(forTimeInterval: 1.5)
    app.activate()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "解锁后没回到 app")
  }

  private func lockScreenPrice(_ springboard: XCUIApplication) -> String {
    // 一次快照里挑文字，不逐个元素去取（锁屏在刷新，逐个取会撞上已经换掉的元素）。
    springboard.debugDescription.split(separator: "\n")
      .filter { $0.contains("StaticText") && ($0.contains("USDT") || $0.contains("离提醒价") || $0.contains("%")) }
      .map { line in line.split(separator: "label: ").last.map(String.init) ?? String(line) }
      .joined(separator: " | ")
  }

  /// 记一笔（看多，等答案）→ 总表里多一条「BTC 到点了」，写着到期时刻。
  func testARecordedCallShowsUpAsADueAlert() throws {
    let entry = app.buttons[Ids.intervalChart]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "周期行右端没有「图表」")
    entry.tap()
    let record = app.buttons["chart.record"]
    XCTAssertTrue(record.waitForExistence(timeout: 10), "「图表」面板里没有「记一笔」")
    record.tap()
    let long = app.buttons["看多"]
    XCTAssertTrue(long.waitForExistence(timeout: 10), "取景卡里没有「看多」")
    long.tap()
    let save = app.buttons["记下"]
    XCTAssertTrue(save.waitForExistence(timeout: 5), "取景卡里没有「记下」")
    save.tap()
    XCTAssertTrue(save.waitForNonExistence(timeout: 10), "点了「记下」取景卡没收回去：\(app.debugDescription)")
    openAlertsFromSettings()
    XCTAssertTrue(app.staticTexts["BTC 到点了"].waitForExistence(timeout: 10),
                  "记完一笔总表里没有到点提醒：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "到期 ")).count > 0,
                  "到点提醒那一行没写到期时刻")
    shot("11-记一笔之后的到点提醒")
  }

  /// 自选五分钟波动：总表里那颗开关默认关着，打开、幅度默认 1.5%；
  /// 自选里的 BTC 五分钟涨 2%（启动环境 `KANPAN_TEST_WATCHMOVE` 喂的一段）→ 浮条说出来。
  func testWatchMoveSwitchFiresOnAFavorite() throws {
    openAlertsFromSettings()
    let toggle = app.descendants(matching: .any).matching(identifier: "alerts.watchMove").firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 8), "总表里没有「自选波动提醒」开关")
    XCTAssertFalse(app.textFields["alerts.watchMove.threshold"].exists, "开关默认应当关着")
    toggle.tap()
    let threshold = app.textFields["alerts.watchMove.threshold"]
    XCTAssertTrue(threshold.waitForExistence(timeout: 5), "打开之后没露出幅度")
    XCTAssertEqual(threshold.value as? String, "1.5", "幅度默认不是 1.5")
    shot("12-自选波动开关")
    // 表开着响的，就在表上那条 toast 里说（主 toast 被表压着看不见）。
    XCTAssertTrue(app.staticTexts["BTC 五分钟涨 2.00%"].waitForExistence(timeout: 20),
                  "自选里的 BTC 五分钟涨 2% 没响：\(app.debugDescription)")
    shot("13-自选波动响了")
  }
}
