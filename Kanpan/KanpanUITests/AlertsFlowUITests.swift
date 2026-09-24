import XCTest

/// 提醒走一遍用户真的会走的那条路：
/// 画一条水平线 → 选中栏上那句「跌到 X 叫我」 → 点一下 → 线右端多一枚铃铛 →
/// 图上点一根 → 十字线那颗「创建提醒」→ 创建提醒页 → 右上「全部预警」→ 总表。
///
/// 2026-09-25 起设置里不再有「提醒」那一行：建提醒只从图上那颗药丸进，已有的提醒在
/// 新建页右上「全部预警」里管（深链 `hkline://alerts` / 点通知仍直接开总表）；铃声、
/// 自选波动、通知权限三样设置搬进设置页「通知」一组。
///
/// 2026-09-25 v3：提醒只响一次、响完就从存档里删（没有「再次提醒」）；创建页底下
/// 「当前提醒」只列这只品种还没触发的；总表「全部预警」分「价格提醒」「画线提醒」两段、
/// 按品种分组，每行只有一枚垃圾桶（没有左划、没有「盯一个」、没有条件菜单）。
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
  /// 「触发即删」那条用例开局就要有一条响过的提醒。跑用例的是另一个进程，
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
    // 「已加提醒 · …」只停 1.6 秒，比一次「等空闲 + 查询」还短；用例里让它多停一会儿再查。
    app.launchEnvironment["KANPAN_TEST_TOAST_SECONDS"] = "6"
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

  /// 提醒总表（推进来的那一层，或者深链开的那张表）。
  private var alertsPage: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch
  }

  /// 新建提醒那一页。
  private var newAlertPage: XCUIElement {
    app.descendants(matching: .any).matching(identifier: "alerts.new.page").firstMatch
  }

  /// 把提醒那张表整个收掉：总表是推进来的就先按系统返回退回新建页，再按左上关闭。
  ///
  /// 这一下点空了表就一直盖着，后面点任何别的都会报「not hittable」，所以最多四轮。
  private func closeSheet() {
    for _ in 0..<4 {
      if !alertsPage.exists && !newAlertPage.exists { return }
      let close = app.buttons["panel.done"]
      if close.waitForExistence(timeout: 2), close.isHittable {
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      } else if app.navigationBars.buttons.firstMatch.exists {
        // 推进来的总表：系统返回键回到新建页。
        app.navigationBars.buttons.firstMatch.tap()
      }
      _ = wait(seconds: 5) { !self.alertsPage.exists && !self.newAlertPage.exists }
    }
  }

  /// 回行情页（从设置页、自选页回来）。
  private func backToChart() {
    let chartTab = app.buttons["bottom.chart"]
    if chartTab.waitForExistence(timeout: 5), !canvas.isHittable { chartTab.tap() }
    XCTAssertTrue(canvas.waitForExistence(timeout: 15), "回不到行情页")
  }

  /// 图上点一根：主图靠右、偏下（避开前面画过的那条水平线），等十字线出来。
  private func selectACandle() -> Bool {
    guard let mainH = info()["mainH"] as? Double, let plotW = info()["plotW"] as? Double else { return false }
    let scale = canvas.frame.height / max(1, info()["height"] as? Double ?? canvas.frame.height)
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * scale * 0.8, dy: mainH * scale * 0.78)).tap()
    return wait(seconds: 8) { self.info()["crosshair"] as? Bool == true }
  }

  /// 图上十字线那颗「创建提醒」→ 创建提醒页。点完十字线要收掉。
  @discardableResult
  private func openNewAlertFromChart() -> Bool {
    for _ in 0..<3 {
      if newAlertPage.exists { return true }
      if info()["crosshair"] as? Bool != true, !selectACandle() { continue }
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { continue }
      chip.tap()
      if app.textFields["alerts.new.price"].waitForExistence(timeout: 8) {
        XCTAssertTrue(wait(seconds: 5) { self.info()["crosshair"] as? Bool != true },
                      "点了「创建提醒」十字线还钉在图上")
        return true
      }
    }
    return false
  }

  /// 品种卡右边那口现价跳出来了（不是「—」）。
  private func waitForLivePrice(_ what: String) {
    let last = app.staticTexts["alerts.new.last"]
    XCTAssertTrue(last.waitForExistence(timeout: 8), "\(what)：品种卡上没有现价")
    XCTAssertTrue(wait(seconds: 20) { last.label != "—" && !last.label.isEmpty },
                  "\(what)：品种卡上的现价一直是空的")
  }

  /// 价格下面那行小字：「现价 83,964.6 · 低于现价 4.82%」。
  private var hint: XCUIElement { app.staticTexts["alerts.new.current"] }

  /// 总表：图上药丸 → 新建页 → 右上「全部预警」推进来（系统返回，没有左上关闭）。
  @discardableResult
  private func openAlertsPage() -> Bool {
    backToChart()
    guard openNewAlertFromChart() else { return false }
    let all = app.buttons["alerts.all"]
    guard all.waitForExistence(timeout: 5) else { return false }
    all.tap()
    return alertsPage.waitForExistence(timeout: 8)
  }

  /// 把输入框里的字换成 `text`：点到最右（光标落在末尾），按够退格，再打。
  private func replace(_ field: XCUIElement, with text: String) {
    field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
    let old = (field.value as? String) ?? ""
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
  }

  /// 新建页上按「创建提醒」：表收起、图上浮一句「已加提醒 · …」。
  private func createAndExpectToast(_ what: String) {
    let add = app.buttons["alerts.new.create"]
    XCTAssertTrue(add.waitForExistence(timeout: 5) && add.isEnabled, "\(what)：「创建提醒」按不下去")
    // 主按钮不钉在底部：刚填完地址时键盘盖着它。先收键盘（键盘上方那颗「完成」），
    // 还够不着就往上推一推页面。
    if app.keyboards.firstMatch.exists {
      let done = app.buttons["完成"].firstMatch
      if done.exists { done.tap() } else { app.keyboards.buttons["Done"].firstMatch.tap() }
      _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }
    for _ in 0..<3 where !add.isHittable { newAlertPage.swipeUp() }
    add.tap()
    // 提示画在所有 sheet 之上的那扇小窗里（用例里停 6 秒）：先抓它，再等表收完。
    // 输价就碰价的那条（`KANPAN_TEST_ALERT_TOUCH`）会紧跟着响，「已加提醒」随即被
    // 「BTC 跌到 … · 查看」顶掉——两句认哪句都算说过了。
    let toast = app.staticTexts.matching(NSPredicate(
      format: "label BEGINSWITH %@ OR label MATCHES %@", "已加提醒 · ", "^[A-Z0-9]+ (涨到|跌到) .*")).firstMatch
    XCTAssertTrue(toast.waitForExistence(timeout: 5), "\(what)：建完没说「已加提醒」")
    XCTAssertTrue(newAlertPage.waitForNonExistence(timeout: 8), "\(what)：建完新建页没收起")
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

    // ③ 收起画线栏 → 图上点一根 → 十字线那颗「创建提醒」→ 创建页 → 右上「全部预警」→ 总表。
    let finish = app.buttons["draw.finish"]
    if finish.exists { finish.tap() }
    XCTAssertTrue(wait(seconds: 10) { !self.app.buttons["draw.finish"].exists }, "画线栏收不起来")
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    let all = app.buttons["alerts.all"]
    XCTAssertTrue(all.waitForExistence(timeout: 5), "新建页右上没有「全部预警」")
    XCTAssertEqual(all.label, "全部预警", "右上那颗不带数量，只写「全部预警」")
    // 创建页底下「当前提醒」列着刚挂上的那条画线提醒。
    XCTAssertTrue(app.staticTexts["当前提醒 1"].waitForExistence(timeout: 5),
                  "创建页底下没列出刚挂的那条画线提醒：\(app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label))")
    shot("03-新建页右上的全部预警")
    all.tap()
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 8), "「全部预警」没推进总表")
    XCTAssertTrue(app.navigationBars.staticTexts["全部预警"].waitForExistence(timeout: 5), "总表标题不是「全部预警」")
    XCTAssertFalse(app.buttons["alerts.new"].exists, "总表上不该再有「新建」")
    XCTAssertTrue(app.staticTexts["画线提醒 1"].waitForExistence(timeout: 5),
                  "总表里没有「画线提醒 1」那一段：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts["价格达到"].waitForExistence(timeout: 5),
                  "总表里那一条没写它在等什么：\(app.debugDescription)")
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.symbol").firstMatch.exists,
                  "总表里没有品种段头")
    XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "alerts.condition").firstMatch.exists,
                   "总表行上不该再有条件菜单")
    XCTAssertFalse(app.buttons["alerts.watch"].exists, "总表行上不该再有「盯一个」")
    shot("04-提醒总表")

    // ④ 三套皮肤各看一眼。
    for skin in ["sage", "terra", "classic"] {
      closeSheet()
      let settingsTab = app.buttons["bottom.settings"]
      XCTAssertTrue(settingsTab.waitForExistence(timeout: 8), "标签栏上没有「设置」")
      settingsTab.tap()
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

  /// 触发即删（2026-09-25 v3）：服务端判到价 → 同步换下来一条 `status=fired` →
  /// app 报一次（通知 / 前台提示）之后就把它从存档里删掉，界面上一眼都不露。
  ///
  /// 用例把「同步换下来的那一份」直接摆成开局状态（启动环境 `KANPAN_TEST_ALERT_FIRED`，
  /// 由 `AlertStore.testSeed` 在 DEBUG 下种）：总表是空态、没有「再次提醒」、没有「已触发」；
  /// 创建页底下没有「当前提醒」；去掉种子重开同一份档案，存档里那条确实没了。
  func testAFiredAlertIsDeletedAndHidden() throws {
    // 点通知 / 深链进来的那条路：总表直接以一张表出现，左上有关闭。
    app.open(URL(string: "hkline://alerts")!)
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 10), "hkline://alerts 没开出总表")
    XCTAssertTrue(app.buttons["panel.done"].waitForExistence(timeout: 5), "深链开的总表左上没有关闭")
    let empty = app.descendants(matching: .any).matching(identifier: "alerts.empty").firstMatch
    XCTAssertTrue(empty.waitForExistence(timeout: 8), "响过的那条还列在总表里：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts["暂无预警"].exists, "空态没写「暂无预警」")
    XCTAssertFalse(app.buttons["再次提醒"].exists, "不该再有「再次提醒」")
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已触发")).count, 0,
                   "总表里不该出现「已触发」")
    shot("07-触发即删-总表空态")
    closeSheet()

    // 创建页底下「当前提醒」只列没触发的：一条都没有就整段不出。
    backToChart()
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    waitForLivePrice("触发即删")
    XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "alerts.records").firstMatch.exists,
                   "创建页底下不该列出响过的那条")
    shot("08-触发即删-创建页无记录")
    closeSheet()

    // 存档里真的删了：去掉种子、重开同一份档案，总表还是空的。
    app.terminate()
    app.launchEnvironment.removeValue(forKey: "KANPAN_TEST_ALERT_FIRED")
    app.launch()
    app.open(URL(string: "hkline://alerts")!)
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 15), "重开后 hkline://alerts 没开出总表")
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.empty").firstMatch.waitForExistence(timeout: 8),
                  "重开之后那条响过的提醒又回来了：\(app.debugDescription)")
  }

  // ------------------------------------------------------------ 2026-09-25 从图上加提醒

  /// 换皮肤 + 深浅，停在设置页上。
  private func applySkin(_ skin: String, mode: String) {
    let settingsTab = app.buttons["bottom.settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "标签栏上没有「设置」")
    settingsTab.tap()
    XCTAssertTrue(selectSkin(skin), "没能换到皮肤「\(skin)」")
    let segment = app.buttons["display.mode." + mode]
    XCTAssertTrue(segment.waitForExistence(timeout: 8), "设置页上没有深浅档 \(mode)")
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(wait(seconds: 5) { segment.isSelected }, "深浅没落在 \(mode)")
  }

  /// 设置页往下划，直到「通知」那一组整组露出来（铃声那一行点得着、离底栏有余量）。
  private func scrollToNotificationGroup() {
    let sound = app.buttons["alerts.sound.open"]
    let bottom = app.windows.firstMatch.frame.maxY - 140
    for _ in 0..<8 {
      if sound.exists, sound.isHittable, sound.frame.maxY < bottom { break }
      app.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(sound.exists && sound.isHittable, "设置页划不到「通知」一组的「提醒铃声」")
  }

  /// 设置页「通知」一组（铃声 / 自选波动 / 通知权限都在这儿）→ 图上药丸「创建提醒」→ 创建页
  /// （右上「全部预警」）→ Webhook 打开只填地址 → 创建 → 总表那一行带链接记号、不再有备注、
  /// 行尾一枚垃圾桶 → 回创建页点「当前提醒」那一行进编辑页、按钮是「保存」、地址还在。
  /// 青苔浅、青苔深各走一遍。
  func testNotificationSettingsComposeAndListScreens() throws {
    for (mode, tag) in [("浅色", "青苔浅"), ("深色", "青苔深")] {
      applySkin("sage", mode: mode)
      XCTAssertTrue(app.staticTexts["通知"].waitForExistence(timeout: 8), "设置页里没有「通知」一组")
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch.exists,
                     "设置页里不该再有「提醒」那一行")
      XCTAssertFalse(app.staticTexts["提醒与朋友"].exists, "「提醒与朋友」分组标题该没了")
      scrollToNotificationGroup()
      XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.watchMove").firstMatch.exists,
                    "「通知」一组里没有「自选波动」")
      shot("设置-通知组-" + tag)

      backToChart()
      XCTAssertTrue(selectACandle(), "\(tag)：点图没选中一根")
      let pill = app.buttons["chart.crosshair.alert"]
      XCTAssertTrue(pill.waitForExistence(timeout: 5), "\(tag)：十字线开着，周期条那一行却没有「创建提醒」")
      XCTAssertEqual(pill.label, "创建提醒", "\(tag)：药丸上的字不对")
      shot("图上-十字线创建提醒-" + tag)
      XCTAssertTrue(openNewAlertFromChart(), "\(tag)：「创建提醒」没开出创建页")
      waitForLivePrice(tag)
      XCTAssertTrue(wait(seconds: 10) { self.hint.label.hasPrefix("现价 ") || self.hint.label == "和现价相同" },
                    "\(tag)：价格下面那行没说离现价多远：\(hint.label)")
      let all = app.buttons["alerts.all"]
      XCTAssertTrue(all.waitForExistence(timeout: 5), "\(tag)：创建页右上没有「全部预警」")
      shot("新建提醒-全部预警按钮-" + tag)

      if mode == "浅色" {
        // Webhook 打开：只露出一个地址框和卡片下那行脚注 +「发一条测试」，没有推送内容、没有备注。
        let webhook = app.switches["alerts.new.webhook"]
        XCTAssertTrue(webhook.waitForExistence(timeout: 5), "创建页没有 Webhook 开关")
        webhook.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        let url = app.textFields["alerts.new.webhook.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5), "打开 Webhook 没露出地址框")
        url.tap()
        url.typeText("https://example.com/hook")
        XCTAssertTrue(app.buttons["alerts.new.webhook.test"].waitForExistence(timeout: 5), "没有「发一条测试」")
        XCTAssertTrue(app.staticTexts["触发时向这个地址发一条 JSON"].exists, "Webhook 下面没有脚注")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "alerts.new.webhook.text").firstMatch.exists,
                       "推送内容模板该撤了")
        XCTAssertFalse(app.textFields["alerts.new.note"].exists, "备注该撤了")
        shot("新建提醒-Webhook展开-" + tag)
        createAndExpectToast("带 Webhook")

        XCTAssertTrue(openAlertsPage(), "创建页右上「全部预警」没开出总表")
        let row = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "跌到 ", "涨到 ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "总表里没有那一条：\(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["价格提醒 1"].exists, "总表里没有「价格提醒 1」那一段")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.symbol").firstMatch.exists,
                      "总表那一段没有品种段头")
        XCTAssertTrue(app.buttons["alerts.delete"].exists, "总表那一行尾上没有垃圾桶")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.row.webhook").firstMatch.exists,
                      "总表那一行没有 Webhook 记号")
        XCTAssertFalse(app.staticTexts["alerts.row.note"].exists, "总表那一行不该再写备注")
        shot("总表-Webhook-" + tag)

        // 回到创建页，点「当前提醒」那一行：进同一页，品种只读、按钮换成「保存」，地址还在。
        closeSheet()
        backToChart()
        XCTAssertTrue(openNewAlertFromChart(), "\(tag)：第二次没开出创建页")
        let open = app.buttons["alerts.record.open"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 8), "创建页底下没有可点的那一行")
        for _ in 0..<3 where !open.isHittable { newAlertPage.swipeUp() }
        open.tap()
        let save = app.buttons["alerts.new.create"]
        XCTAssertTrue(save.waitForExistence(timeout: 8), "「编辑」没进编辑页")
        XCTAssertTrue(save.label.contains("保存"), "编辑页的主按钮不是「保存」：\(save.label)")
        XCTAssertFalse(app.textFields["alerts.new.symbol"].exists, "品种不该是输入框")
        XCTAssertEqual(app.textFields["alerts.new.webhook.url"].value as? String, "https://example.com/hook",
                       "编辑页没带上 Webhook 地址")
        shot("编辑提醒-" + tag)
      }
      closeSheet()
    }
  }

  /// v3 验收截图：开局有一条响过的画线提醒（`KANPAN_TEST_ALERT_FIRED`，名字里带 Fired 才种），
  /// 它触发即删、哪儿都不露脸。青苔浅：药丸 → 创建页（没有记录）→ Webhook 展开 → 建一条 →
  /// 再开创建页（「当前提醒 1」、行尾垃圾桶）→ 点行进编辑页 → 截创建页与总表；
  /// 青苔深：再建一条、画一条带提醒的线，截创建页与总表（两段、分品种）；最后按垃圾桶删一条。
  func testComposePageV3ScreensHideFired() throws {
    applySkin("sage", mode: "浅色")
    backToChart()
    XCTAssertTrue(selectACandle(), "点图没选中一根")
    XCTAssertTrue(app.buttons["chart.crosshair.alert"].waitForExistence(timeout: 5), "没有「创建提醒」药丸")
    XCTAssertTrue(openNewAlertFromChart(), "「创建提醒」没开出创建页")
    waitForLivePrice("青苔浅")
    XCTAssertEqual(app.navigationBars.staticTexts.firstMatch.label, "创建提醒")
    XCTAssertTrue(app.staticTexts["alerts.new.symbol"].label == "BTC/USDT", "品种卡上的名字不对")
    XCTAssertTrue(app.staticTexts["币安 · USDT 永续"].exists, "品种卡第二行不对")
    let records = app.descendants(matching: .any).matching(identifier: "alerts.records").firstMatch
    XCTAssertFalse(records.waitForExistence(timeout: 3), "开局那条响过的提醒不该列进「当前提醒」")

    // 价填得离现价远一些：真行情几分钟里碰到了，这条就会被「触发即删」带走，截图就不稳了。
    replace(app.textFields["alerts.new.price"], with: "10000")
    if app.keyboards.firstMatch.exists { app.buttons["完成"].firstMatch.tap() }
    let webhook = app.switches["alerts.new.webhook"]
    XCTAssertTrue(webhook.waitForExistence(timeout: 5), "没有 Webhook 开关")
    webhook.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
    let url = app.textFields["alerts.new.webhook.url"]
    XCTAssertTrue(url.waitForExistence(timeout: 5), "打开 Webhook 没露出地址框")
    let create = app.buttons["alerts.new.create"]
    XCTAssertFalse(create.isEnabled, "地址还空着主按钮就能按")
    url.tap()
    url.typeText("https://example.com/hook")
    XCTAssertTrue(wait(seconds: 3) { create.isEnabled }, "填好地址主按钮还按不下去")
    app.buttons["完成"].firstMatch.tap()
    createAndExpectToast("v3")

    XCTAssertTrue(openNewAlertFromChart(), "第二次没开出创建页")
    waitForLivePrice("青苔浅·第二次")
    let rows = app.descendants(matching: .any).matching(identifier: "alerts.record")
    XCTAssertTrue(wait(seconds: 5) { rows.count == 1 }, "「当前提醒」该只有刚建的那一条：\(rows.count)")
    XCTAssertTrue(app.staticTexts["当前提醒 1"].exists, "记录卡标题不是「当前提醒 1」")
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已触发")).count, 0,
                   "响过的那条不该露脸")
    XCTAssertTrue(app.buttons["alerts.delete"].exists, "行尾没有垃圾桶")
    for _ in 0..<3 where !(rows.element(boundBy: 0).isHittable) { app.swipeUp(velocity: .slow) }
    shot("v3-创建页-青苔浅")

    app.buttons["alerts.record.open"].firstMatch.tap()
    XCTAssertTrue(wait(seconds: 8) { self.app.navigationBars.staticTexts["编辑提醒"].exists }, "点那一行没进编辑页")
    XCTAssertTrue(app.buttons["alerts.new.create"].label.contains("保存"))
    XCTAssertEqual(app.textFields["alerts.new.webhook.url"].value as? String, "https://example.com/hook")
    shot("v3-编辑页-青苔浅")
    closeSheet()

    // 画一条带提醒的线，总表就同时有「价格提醒」「画线提醒」两段。
    XCTAssertTrue(enterDrawing(), "没能进入竖屏画线态")
    XCTAssertTrue(try drawAndAwaitChip(at: 0.3, "v3 画线"), "画完没出提醒胶囊：\(info())")
    chip.tap()
    XCTAssertTrue(wait(seconds: 8) { !self.alerted().isEmpty }, "铃铛没挂上：\(alerted())")
    let finish = app.buttons["draw.finish"]
    if finish.exists { finish.tap() }
    XCTAssertTrue(wait(seconds: 10) { !self.app.buttons["draw.finish"].exists }, "画线栏收不起来")

    XCTAssertTrue(openAlertsPage(), "青苔浅：开不出总表")
    XCTAssertTrue(app.staticTexts["价格提醒 1"].waitForExistence(timeout: 5), "总表没有「价格提醒 1」")
    XCTAssertTrue(app.staticTexts["画线提醒 1"].exists, "总表没有「画线提醒 1」")
    shot("v3-全部预警-青苔浅")
    closeSheet()

    applySkin("sage", mode: "深色")
    backToChart()
    XCTAssertTrue(openNewAlertFromChart(), "青苔深：没开出创建页")
    waitForLivePrice("青苔深")
    replace(app.textFields["alerts.new.price"], with: "12345")
    createAndExpectToast("v3 深色")
    XCTAssertTrue(openNewAlertFromChart(), "青苔深：第二次没开出创建页")
    waitForLivePrice("青苔深·第二次")
    XCTAssertTrue(wait(seconds: 5) { rows.count == 3 }, "青苔深：「当前提醒」该有三条：\(rows.count)")
    shot("v3-创建页-青苔深")
    let all = app.buttons["alerts.all"]
    XCTAssertTrue(all.waitForExistence(timeout: 5), "青苔深：右上没有「全部预警」")
    all.tap()
    XCTAssertTrue(alertsPage.waitForExistence(timeout: 8), "青苔深：「全部预警」没推进总表")
    XCTAssertTrue(app.staticTexts["价格提醒 2"].waitForExistence(timeout: 5), "青苔深：总表没有「价格提醒 2」")
    shot("v3-全部预警-青苔深")

    // 垃圾桶：按一下那一行收走，段头数量跟着减。
    let before = app.descendants(matching: .any).matching(identifier: "alerts.record").count
    app.buttons["alerts.delete"].firstMatch.tap()
    XCTAssertTrue(wait(seconds: 5) {
      self.app.descendants(matching: .any).matching(identifier: "alerts.record").count == before - 1
    }, "按了垃圾桶那一行没收走")
    XCTAssertTrue(app.staticTexts["价格提醒 1"].waitForExistence(timeout: 5), "删完段头数量没跟着减")
    shot("v3-全部预警-删一条后-青苔深")
    closeSheet()
  }

  // ------------------------------------------------------------ P3.1

  /// 设置页「通知」一组。
  private func openNotificationSettings() {
    let settingsTab = app.buttons["bottom.settings"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "标签栏上没有「设置」")
    settingsTab.tap()
    XCTAssertTrue(app.staticTexts["通知"].waitForExistence(timeout: 10), "设置页里没有「通知」一组")
  }

  /// 图上药丸 → 新建页（品种是图上那只、价是十字线那口）→ 改成一个价 →「创建提醒」→
  /// 总表里多一条，价格达到那个价之后响一次，随即从总表里消失（v3 触发即删）。
  ///
  /// 方向不让选：价格下面只有一行「现价 x · 低于现价 y%」。碰价那一段由启动环境
  /// `KANPAN_TEST_ALERT_TOUCH` 喂（真行情一两分钟里未必走到那个价），喂的价走的是和真行情
  /// 同一条路：桶 → 判定 → `markFired` → 总表。
  func testATypedPriceBecomesAnAlertAndFires() throws {
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    let symbol = app.staticTexts["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: 8), "创建页上没有品种卡")
    XCTAssertEqual(symbol.label, "BTC/USDT", "品种没默认成图上那只")
    waitForLivePrice("输价")
    let price = app.textFields["alerts.new.price"]
    XCTAssertTrue(price.waitForExistence(timeout: 5), "没有价格输入框")
    XCTAssertFalse(app.steppers.count > 0, "价格不许用加减步进器")
    XCTAssertFalse((price.value as? String ?? "").isEmpty, "价格框没带上十字线那口价")
    replace(price, with: "12345")
    // 现价和头部同一个写法：BTCUSDT 的 tick 是 0.1，所以一位小数，整数部分带千分位
    // （审查 D3：以前是不插千分位的 `86781.5`，和头部的 `86,781.5` 对不上）。
    XCTAssertTrue(wait(seconds: 10) {
      self.hint.label.range(of: #"^现价 \d{1,3}(,\d{3})+\.\d · 低于现价 [\d.,]+%$"#, options: .regularExpression) != nil
    }, "价格下面那行没按「现价 x · 低于现价 y%」写：\(hint.label)")
    shot("09-新建价格提醒")
    createAndExpectToast("价格提醒")
    // 一挂上就喂两口夹住目标价的价：响一次（「BTC 跌到 …」那句提示已经在 createAndExpectToast
    // 里认过），然后那一条从存档里删掉——总表是空态，没有「已触发」。
    XCTAssertTrue(openAlertsPage(), "新建页右上「全部预警」没开出总表")
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.empty").firstMatch.waitForExistence(timeout: 20),
                  "价格达到之后那一条没从总表里删掉：\(app.debugDescription)")
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12,345")).count, 0,
                   "响过的那条还列在总表里")
    XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已触发")).count, 0,
                   "总表里不该出现「已触发」")
    shot("10-价格提醒响过即删")
  }

  /// v2：品种只读（「进去后品种不可编辑」）、没有 ±% 快捷、没有备注和推送内容模板；
  /// 价格清空时小字说「输入一个价格」、主按钮按不下去。
  func testNewAlertSymbolIsReadOnlyAndPriceIsTheOnlyInput() throws {
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出创建页")
    let symbol = app.staticTexts["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: 8), "创建页上没有品种卡")
    XCTAssertEqual(symbol.label, "BTC/USDT")
    XCTAssertFalse(app.textFields["alerts.new.symbol"].exists, "品种不该能改")
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "alerts.new.nudge")).count, 0,
                   "±% 快捷该撤了")
    XCTAssertFalse(app.textFields["alerts.new.note"].exists, "备注该撤了")
    XCTAssertEqual(app.textFields.count, 1, "页上只该有价格这一个输入框（Webhook 关着）")
    let price = app.textFields["alerts.new.price"]
    replace(price, with: "")
    XCTAssertTrue(wait(seconds: 5) { self.hint.label == "输入一个价格" }, "价格空着小字没说：\(hint.label)")
    XCTAssertFalse(app.buttons["alerts.new.create"].isEnabled, "价格空着主按钮还能按")
    shot("15-创建页-价格空着")
  }

  /// 记一笔（看多，等答案）→ 总表里多一条「BTC 到点了」，写着到期时刻。
  func testARecordedCallShowsUpAsADueAlert() throws {
    let entry = app.buttons[Ids.intervalChart]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "周期行右端没有图表设置那颗")
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
    XCTAssertTrue(openAlertsPage(), "新建页右上「全部预警」没开出总表")
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "alerts.section.reviewDue").firstMatch
                    .waitForExistence(timeout: 10), "总表里没有「复盘到点」那一段：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts["BTC 到点了"].waitForExistence(timeout: 10),
                  "记完一笔总表里没有到点提醒：\(app.debugDescription)")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "到期 ")).count > 0,
                  "到点提醒那一行没写到期时刻")
    shot("11-记一笔之后的到点提醒")
  }

  /// 自选五分钟波动：设置页「通知」一组里那颗开关默认关着，打开、幅度默认 1.5%；
  /// 自选里的 BTC 五分钟涨 2%（启动环境 `KANPAN_TEST_WATCHMOVE` 喂的一段）→ 浮条说出来。
  func testWatchMoveSwitchFiresOnAFavorite() throws {
    openNotificationSettings()
    let toggle = app.descendants(matching: .any).matching(identifier: "alerts.watchMove").firstMatch
    XCTAssertTrue(toggle.waitForExistence(timeout: 8), "设置页「通知」里没有「自选波动提醒」开关")
    XCTAssertFalse(app.textFields["alerts.watchMove.threshold"].exists, "开关默认应当关着")
    toggle.tap()
    let threshold = app.textFields["alerts.watchMove.threshold"]
    XCTAssertTrue(threshold.waitForExistence(timeout: 5), "打开之后没露出幅度")
    XCTAssertEqual(threshold.value as? String, "1.5", "幅度默认不是 1.5")
    shot("12-自选波动开关")
    XCTAssertTrue(app.staticTexts["BTC 五分钟涨 2.00%"].waitForExistence(timeout: 20),
                  "自选里的 BTC 五分钟涨 2% 没响：\(app.debugDescription)")
    shot("13-自选波动响了")
  }
}
