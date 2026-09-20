import XCTest

/// 提醒（方案 2.3）走一遍用户真的会走的那条路：
/// 画一条水平线 → 画完那一下问一句 → 「加入提醒」 → 线右端多一枚铃铛 →
/// 设置里那一行「提醒」 → 总表。
///
/// 这条用例盯着三件光靠单测证明不了的事：
///
/// 1. **那句问话不盖画布。** 它长在周期条底下、标签栏上面（横屏是工具栏那一行），
///    不是系统弹窗、也不是浮在图上的卡片（`kanpan-no-floating-controls-over-chart`）。
///    所以这儿量的是它的 frame 和画布的 frame 不相交。
/// 2. **铃铛真的挂上去了。** 图那一侧只认 id，诊断里 `drawingAlerted` 就是它画了记号的那几条。
/// 3. **六秒不动等于「只画线」。** 这一条是方案里写死的默认动作，不能靠人记得去点。
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
      if app.buttons["draw.objects.quick"].exists { return true }
      if app.enterDrawingInPortrait() { return true }
      shot("_进画线态第\(round + 1)轮没成")
      let exit = app.buttons["land.exit"]
      if exit.exists, exit.isHittable { exit.tap() }
      XCUIDevice.shared.orientation = .portrait
    }
    return app.buttons["draw.objects.quick"].waitForExistence(timeout: 10)
  }

  /// 落一笔水平线（一下就成，`pointCount == 1`）。
  ///
  /// **先量坐标再点工具**：量一次画布 frame + 诊断要花一两秒，花在落笔之前就不占
  /// 那句问话只有的 6 秒。落完笔这儿一个查询都不做，让调用方直接去接问话。
  private func tapHorizontal(at y: Double) throws {
    let target = try point(x: 0.5, y: y)
    let chip = app.buttons["draw.hline"]
    XCTAssertTrue(chip.waitForExistence(timeout: 8), "画线栏上没有水平线")
    // chip 住在一条横向 ScrollView 里，XCUI 自己那套可点性判定在这种容器上会抖，
    // 所以按坐标打（`UITestSupport.tapIntervalChip` 同一个理由）。
    chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    target.tap()
  }

  /// 那句问话本人。用带类型的查询（`otherElements`）而不是 `descendants(matching: .any)`：
  /// 后者每问一次都要把整棵可及性树捞下来，机器忙的时候一次就好几秒——问话只活 6 秒，
  /// 查询自己把时间吃光，就会出现「明明弹了却查不到」。
  private var prompt: XCUIElement { app.otherElements["alert.prompt"] }

  /// 画一笔并接住那句问话。
  ///
  /// 落笔本身偶尔会掉（工具 chip 的那一下被滚动容器吃掉、或者方向切换的动画还没停），
  /// 所以最多试三轮，每轮换一个高度免得两笔叠在一起。返回这一趟之后图上有哪些线。
  @discardableResult
  private func drawAndAwaitPrompt(at y: Double, _ what: String) throws -> Bool {
    for round in 0..<3 {
      try tapHorizontal(at: y + Double(round) * 0.06)
      if prompt.waitForExistence(timeout: 5) { return true }
      shot("_\(what)第\(round + 1)轮没问")
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
    // ① 画一条水平线，量那句问话长在哪儿。
    XCTAssertTrue(enterDrawing(), "没能进入竖屏画线态")
    // 那条问话只活 6 秒（方案写死的耐心），而 XCUI 查一次元素、截一张图在机器忙的时候
    // 都要一两秒。所以这儿分成两笔线来量：**第一笔只量位置**（问话的 frame、有没有用
    // 系统弹窗、截一张图），量完就放手让它按 6 秒自己收掉；**第二笔紧接着按「加入提醒」**，
    // 中间一次多余的查询都不插。挤在一笔里做完就会踩着 6 秒的边，忙的时候必偶发。
    XCTAssertTrue(try drawAndAwaitPrompt(at: 0.35, "画完问一句"), "画完没有问「要不要提醒」：\(info())")
    let promptFrame = prompt.frame
    let canvasFrame = canvas.frame
    XCTAssertFalse(promptFrame.intersects(canvasFrame),
                   "那句问话压在画布上了：问话 \(promptFrame)，画布 \(canvasFrame)")
    XCTAssertTrue(app.alerts.count == 0, "问话不许用系统弹窗")
    shot("01-画完问一句")
    XCTAssertTrue(prompt.waitForNonExistence(timeout: 12), "六秒过去那条问话还在")

    // ② 再画一笔，这一次紧接着按「加入提醒」：线右端挂铃铛，问话收掉。
    let before = Set(ids())
    let accept = app.buttons["alert.prompt.accept"]
    var tapped = false
    for round in 0..<3 {
      try tapHorizontal(at: 0.55 + Double(round) * 0.06)
      if accept.waitForExistence(timeout: 5) { accept.tap(); tapped = true; break }
      shot("_加入提醒第\(round + 1)轮没露面")
    }
    XCTAssertTrue(tapped, "没有「加入提醒」：\(info())")
    // 只认「恰好一条线挂了铃铛，而且是这一趟新画的那条」——上面重试过几轮的话
    // 图上可能不止一条新线，但点了一次「加入提醒」就只该有一枚铃铛。
    XCTAssertTrue(wait(seconds: 8) { self.alerted().count == 1 && !before.contains(self.alerted()[0]) },
                  "铃铛没挂上：alerted=\(alerted())，画之前=\(before)")
    XCTAssertTrue(prompt.waitForNonExistence(timeout: 6), "点完「加入提醒」那一条还赖着")
    shot("02-线上挂了铃铛")

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

  /// 六秒不动 = 只画线。方案 2.3 写死的默认动作。
  func testSixSecondsOfSilenceMeansJustTheLine() throws {
    XCTAssertTrue(enterDrawing(), "没能进入竖屏画线态")
    XCTAssertTrue(try drawAndAwaitPrompt(at: 0.5, "六秒不动"), "画完没有问「要不要提醒」：\(info())")
    let lines = ids()
    XCTAssertFalse(lines.isEmpty, "水平线没画上：\(info())")
    // 一下都不碰。6s 的耐心 + 动画和调度的余量。
    XCTAssertTrue(prompt.waitForNonExistence(timeout: 12), "六秒过去那条问话还在")
    XCTAssertEqual(ids(), lines, "线被那句问话带走了")
    XCTAssertEqual(alerted(), [], "没人点「加入提醒」，铃铛却挂上了")
    shot("06-六秒不动只剩线")
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
}
