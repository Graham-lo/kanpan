import XCTest

@MainActor
final class ChartFoundationUITests: XCTestCase {
  var app: XCUIApplication!
  var canvas: XCUIElement { app.otherElements["chart.canvas"] }
  override func setUp() async throws {
    continueAfterFailure = false
    XCUIDevice.shared.orientation = .portrait
    app = XCUIApplication()
    if name.contains("testInstallRequestedFavoritesInUserStore") || name.contains("testUserSession") { return }
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    if name.contains("Drawing") || name.contains("IndicatorColor") || name.contains("CompactChart") || name.contains("Record") { app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString }
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    if name.contains("Record") { app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io" }
    if name.contains("testExternalIndicatorsAndDepthRoundTrip") || name.contains("testDepthLadderVisibleAtBothIntervals") {
      app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
      app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    }
    app.launch()
    if name.contains("testExternalIndicatorsAndDepthRoundTrip") || name.contains("testDepthLadderVisibleAtBothIntervals") {
      XCTAssertTrue(app.buttons["bottom.chart"].waitForExistence(timeout: 15))
      app.buttons["bottom.chart"].tap()
    }
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, feedEvidence())
  }
  /// 首屏等不到 K 线时，把「链路现场」一起写进失败信息。
  ///
  /// 光报一句 `[:]` 说明不了任何事——它只表示 `chart.canvas` 还停在「行情加载中」。
  /// 真正要回答的是：走的哪条线路、状态停在哪一档、REST/WS 各自到哪一步断的。
  /// 这三样分别挂在 `market.source`（label = 线路，value = 状态）和 `market.network`
  /// （`MarketNetworkDiagnostics.shared.lines`，DEBUG + `KANPAN_CHART_DIAGNOSTICS` 下才有）上。
  func feedEvidence() -> String {
    let source = app.staticTexts["market.source"]
    let route = source.exists ? "\(source.label)/\(String(describing: source.value))" : "未知"
    let net = app.staticTexts["market.network"]
    let lines = net.exists ? net.label : ""
    return "图 \(info())；线路 \(route)；链路日志：\n" + (lines.isEmpty ? "（空——一条请求都没发出去）" : lines)
  }
  override func tearDown() async throws {
    // 手动用例（`testUserSession*`、`testInstallRequestedFavoritesInUserStore`）在 setUp 里
    // 第 11 行就直接 return 了，压根没起过 app。这时候对它调 `screenshot()` 只会拿到一张
    // 「capture failed」的废图，接着 `terminate()` 是冲着 pid 0 下手——XCTest 会就此卡死，
    // 那一格要干等满 executionTimeAllowance 才肯往下走（真机、模拟器都复现）。没起来就别碰。
    guard app.state != .notRunning, app.state != .unknown else { return }
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.lifetime = .keepAlways; add(attachment)
    if (testRun?.failureCount ?? 0) > 0 {
      let state = canvas.exists ? String(describing: canvas.value) : "Chart is covered by another page"
      let tree = XCTAttachment(string: app.debugDescription + "\nChart state: " + state); tree.lifetime = .keepAlways; add(tree)
    }
    app.terminate()
  }
  /// 「视野没动」：右缘（`to`）和根宽（`spacing`）一点不差，图高不变。
  ///
  /// 为什么不直接比 `from` / `plotW`：价格刻度列按最宽那条刻度文字贴着算宽度（用户点名要窄），
  /// 行情在跳，刻度文字换了一位数，这一列就会宽或窄 1 pt。右缘贴着末根不动，根宽也不动，
  /// 左缘就跟着多露或少露四分之一根。这不是平移。2026-09-23 的 M8 矩阵里，十字线和拖副图
  /// 这两条都是这样红的：`plotW 356→355`、`spacing 4→4`、`to` 不变、`from` 差了 900000 ms。
  /// 这里把这 1–2 pt 的刻度列伸缩折算成左缘允许差的量；其余部分仍然要求一模一样。
  func assertViewportKept(_ before: [String: Any], _ after: [String: Any],
                          file: StaticString = #filePath, line: UInt = #line) throws {
    func v(_ d: [String: Any], _ k: String) throws -> Double { try XCTUnwrap(d[k] as? Double, k, file: file, line: line) }
    XCTAssertEqual(try v(after, "to"), try v(before, "to"), accuracy: 1, "右缘动了", file: file, line: line)
    XCTAssertEqual(try v(after, "spacing"), try v(before, "spacing"), accuracy: 0.001, "根宽变了", file: file, line: line)
    let dW = abs(try v(after, "plotW") - v(before, "plotW"))
    XCTAssertLessThanOrEqual(dW, 2, "绘图区宽度差了 \(dW) pt，已经不是刻度列伸缩", file: file, line: line)
    let msPerPt = try v(before, "span") / v(before, "plotW")
    XCTAssertEqual(try v(after, "from"), try v(before, "from"), accuracy: dW * msPerPt + 1,
                   "左缘挪得比刻度列伸缩多", file: file, line: line)
    if before["height"] != nil {
      XCTAssertEqual(try v(after, "height"), try v(before, "height"), accuracy: 0.001, "图高变了", file: file, line: line)
    }
  }
  func info() -> [String: Any] {
    guard canvas.exists, let value = canvas.value as? String, let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
  }
  func wait(seconds: Double = 40, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)], timeout: seconds) == .completed
  }
  /// 关面板：先走用户最常用的那一下——拽标题栏往下甩，甩不掉再点「完成」。
  ///
  /// 「完成」不是测试后门，它是面板自带的常驻出口（见 `PanelSheet` 的注释）：面板一旦被拉到
  /// 全屏，「往下拽」在一整页滚动内容上就不成立了，所以每张面板都留了这颗按钮。两条路都得能走通。
  func closePanel() {
    let header = app.staticTexts["panel.header"]
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    let end = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
    for _ in 0..<2 {
      start.press(forDuration: 0.05, thenDragTo: end)
      if wait(seconds: 3, { !header.exists }) { return }
    }
    let done = app.buttons["panel.done"]
    if done.exists, done.isHittable { done.tap() }
    XCTAssertTrue(wait { !header.exists }, "面板关不掉：拖不走，「完成」也没反应")
  }
  /// 把 Form 里的一个开关翻到指定值：打在滑块上，没翻就照原点再来一下。
  ///
  /// 为什么这儿要重试，而 `tapButton` 明写着「只接受一次中心点击」——因为那条规矩防的是
  /// 拿偏移重试去掩盖**产品的命中区问题**，这儿的丢点已经取证证明不是命中区的事：
  ///
  /// 2026-09-18 全量 13 台矩阵上，iPhone 16 Plus 和 iPhone 17 Pro 各红一次，都卡在
  /// `testMAParameterCancelAndSaveOutput` 关 MA 输出的那一下。取证做到了 app 里面——
  /// 临时给 `IndicatorPanel` 那个 `Toggle` 的 setter 挂一个计数器，再用「开面板 → 点一下
  /// → 关面板」的探针跑 40 轮，复现出没翻的那一次：点前点后元素的 frame 一模一样
  /// （`(20, 519.3, 390, 52.3)`），`isHittable` 为真，而 setter 的计数一动没动。
  /// 也就是说这一下压根没进 app，事件丢在 XCUI「合成 → 投递」那一段；既不是点歪了，
  /// 也不是 app 收到了又把状态弹回去。孤立探针上约 3% 丢一下，整套 49 条跑下来机器更忙，
  /// 矩阵里两台就都撞上了。
  ///
  /// 也别想着换个点躲开：同一轮探针里打在整行文字那半边（`dx 0.25`）点了 20 次、20 次都不翻——
  /// Form 里这一行只有开关本体认点击。目标点只能是滑块，能做的只有没翻就再点一下。
  ///
  /// 重试不会把真缺陷放过去：开关要是真的翻不动，三下点完照样红。
  func flip(_ toggle: XCUIElement, to expected: String,
            file: StaticString = #filePath, line: UInt = #line) {
    for _ in 0..<3 {
      toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
      if wait(seconds: 5, { toggle.value as? String == expected }) { return }
    }
    XCTFail("开关点了三下还是 \(String(describing: toggle.value))，没到 \(expected)：\(toggle.frame)",
            file: file, line: line)
  }
  /// 开画线工具面板：点「工具」，面板没上来就照原点再点一下。
  ///
  /// 理由和 `flip(_:to:)`、`tapButton` 那两处一样——2026-09-18 的全量矩阵上，
  /// 17e 这一条就是点完「工具」之后面板整整 5 秒没出来。合成事件是干净的一对按下/抬起、
  /// 坐标也在按钮上，app 那边没有任何反应；同一轮矩阵里周期条药丸和 MA 开关各自撞到一次
  /// 同样的事。重试不换点也不加偏移：按钮真打不开，两下之后照样红。
  func openDrawTools(file: StaticString = #filePath, line: UInt = #line) {
    for _ in 0..<2 {
      app.buttons["draw.tools"].tap()
      if app.buttons["draw.sheet.done"].waitForExistence(timeout: 5) { return }
    }
    XCTFail("点了两下「工具」，画线工具面板都没上来", file: file, line: line)
  }
  /// 离开设置页。
  ///
  /// 设置 2026-09-18 起不是半屏面板而是标签栏上的一整页：它既拖不走，也没有「完成」，
  /// 离开它的办法就是切到别的标签。行情页那一格叫「图表」。
  /// 这一下**按坐标点**，不用 `XCUIElement.tap()`。底栏没有自己的底，设置页那张
  /// `ScrollView` 是一直铺到屏幕底边的（页面的材料从标签栏背后穿过去，这是定下来的样子）；
  /// 设置页的内容一旦比一屏长（2026-09-21 多了「提醒」那一行之后就是），XCTest 发现
  /// 「图表」那一格底下压着一个能滚的祖先，就会先去「滚动到可见」，滚完算出来的命中点是
  /// `{-1, -1}`——那一下合成事件谁也没点到，人在手机上却是实实在在点得着的。
  /// 按坐标点绕开这套推断，点的仍旧是那一格的正中央。
  func leaveSettings() {
    let chartTab = app.buttons["bottom.chart"]
    XCTAssertTrue(chartTab.waitForExistence(timeout: 5), "标签栏上没有「图表」")
    chartTab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(wait(seconds: 8) { self.app.buttons["interval.chart"].exists },
                  "点了「图表」还没回到行情页")
  }
  func selectMain() {
    let h = info()["mainH"] as? Double ?? 300
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: min(130, h / 2))).tap()
  }
  func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  /// 在样式表的「换一种画法」那一行上换一种画法。
  ///
  /// 面板上只摆十二把（`Drawing.Kind.palette`）；向右延伸 / 两端延伸 / 箭头 / 十字线
  /// 这些和主工具形状一样、只差一处画法的，退到这一行里换（`Drawing.Kind.swaps`）。
  /// 这一行是一排直接摆开的按钮（`DrawingKindSwapRow`，标识 `draw.swap.<kind>`）。
  /// 原来是 `Picker` 的弹出菜单，半屏时往上弹出面板、「向右延伸」点不到，2026-09-23 改掉。
  ///
  /// 它排在「颜色 / 粗细 / 线型 / 锁定位置」后面，而样式表起手停在 0.4 屏高——
  /// 这一行落在下沿以外，`Form` 是懒加载的，**压根不在无障碍树里**（查 `exists`
  /// 返回 false，不是「在但点不着」）。所以找不着就先把半屏拖成整屏，再找；
  /// 粗细那一档早就吃过同一个亏（见 `testDrawingWidthPresets` 里那段）。
  func switchDrawKind(to label: String) {
    let option = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "draw.swap.", label)).firstMatch
    if !option.waitForExistence(timeout: 3) || !option.isHittable {
      let bar = app.navigationBars.element(boundBy: 0)
      bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .press(forDuration: 0.1,
               thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
    }
    if !option.waitForExistence(timeout: 3) { app.swipeUp() }
    XCTAssertTrue(option.waitForExistence(timeout: 5), "样式表的「画法」那一排里没有「\(label)」")
    option.tap()
    XCTAssertTrue(wait(seconds: 5) { option.isSelected }, "点了「\(label)」，画法那一排没有换过去")
  }

  /// 「记一笔」收在「图表设置」那一屏里，开出的取景卡只压图的下半截，一根 K 线都不动。
  ///
  /// 这颗按钮走过两站：先是浮在主图上、能拖着到处摆的一枚圆钮（浮着就一定挡图，
  /// 停哪儿糊哪儿，还在画布上挖出一块点不动的死区），后来挪到周期条右端常驻。
  /// 用户看过之后说「这个功能不是经常用到啊」「记和画线都放到图表栏目里」，于是
  /// 再收进「图表」面板——常驻的格子留给天天要点的东西。
  ///
  /// 取景卡这一头也改过一次：它原来和图排在同一根 `VStack` 里，卡片一出来图就被压到
  /// 剩三分之一——而记一笔恰恰是「看着这段行情写点什么」，图被压扁正好把要看的东西挤没了。
  /// 2026-09-17（`181a5bc`「交互定板落地」）改成压在图下沿的一层（见 `MainScreen.captureCard`）。
  /// 这条用例当初守的是「卡片整个待在图外面」，那一版之后就不成立了，同一天没跟着改。
  /// 现在守的是改版之后真正要守的三件事：图上没有浮着的控件、卡片只占下半截
  /// （上半截的主图还看得见）、卡片进出的时候一屏还是那么多根 K 线。
  func testRecordSitsOutsideTheChart() throws {
    XCTAssertFalse(app.buttons["review.record"].exists, "主图上不该再浮着「记」")
    XCTAssertFalse(app.buttons["interval.record"].exists, "「记」不该再占周期条的常驻格")
    let span = try XCTUnwrap(info()["span"] as? Double)
    app.buttons["interval.chart"].tap()
    let record = app.buttons["chart.record"]
    XCTAssertTrue(record.waitForExistence(timeout: 10), "「图表」面板里没有「记一笔」")
    record.tap()
    // 点一下开的是复盘取景卡（`ReviewCaptureCard`）：从出来到收回去，图的横向视野一格不许动。
    let close = app.buttons["收起"]
    XCTAssertTrue(close.waitForExistence(timeout: 10), "点「记一笔」没开出取景卡")
    XCTAssertGreaterThan(close.frame.minY, canvas.frame.midY, "取景卡盖过了图的一半")
    // 看的是**宽度**：卡片一压上来，一屏还是这么多根 K 线，图没有被压扁重排。
    // 左缘（`from`）不在这儿验——取景态下图挂的是 `reviewChart` 那份快照，它按整根收口，
    // 正在走的那一根不算，所以左缘差一根是它该有的样子，不是布局把图挤动了。
    XCTAssertEqual(try XCTUnwrap(info()["span"] as? Double), span, accuracy: 0.001, "卡片一出来一屏的根数就变了")
    shot("记一笔-图表面板入口")
    close.tap()
    XCTAssertTrue(wait(seconds: 5) { !close.exists }, "取景卡收不回去")
    XCTAssertEqual(try XCTUnwrap(info()["span"] as? Double), span, accuracy: 0.001)
  }

  /// 把主图调高，主副图仍在一屏里，横向视野一格不动。
  ///
  /// 调高的入口只剩图上那条把手：「图表」面板里那根「竖屏高度」滑块在第三批 16
  /// 撤了（同一件事两个入口，而且滑块在面板里、拖的时候图被面板盖着）。
  /// 这里把 VOL 的上沿往上推，主图跟着变高——和原来拉滑块测的是同一件事。
  func testHeightAndVerticalReachability() throws {
    let original = info()
    XCTAssertFalse(app.sliders["chart.portraitHeight"].exists, "竖屏高度滑块应已撤掉")
    let grip = app.otherElements["chart.resize.VOL"]
    XCTAssertTrue(grip.waitForExistence(timeout: 5))
    let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: grip.frame.midX, dy: grip.frame.midY))
    from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -40)))
    XCTAssertTrue(wait(seconds: 4) {
      (self.info()["mainH"] as? Double ?? 0) > (original["mainH"] as? Double ?? 0) + 15
    }, String(describing: info()))
    var kept = info(); kept["height"] = nil
    var was = original; was["height"] = nil
    try assertViewportKept(was, kept)
    shot("高度调高-主副图内容")
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    XCTAssertEqual(info()["scrollY"] as? Double, 0)
    shot("高度调高-一屏主副图")
  }

  func testResizeDividerWithinOneScreen() throws {
    let original = info()
    let grip = app.otherElements["chart.resize.VOL"]
    XCTAssertTrue(grip.waitForExistence(timeout: 5))
    let before = try XCTUnwrap(Double(grip.value as? String ?? ""))
    let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: grip.frame.midX, dy: grip.frame.midY))
    from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 35)))
    XCTAssertTrue(wait(seconds: 3) { (Double(grip.value as? String ?? "") ?? 0) > before + 15 }, String(describing: info()))
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    var kept = info(); kept["height"] = nil
    var was = original; was["height"] = nil
    try assertViewportKept(was, kept)
    shot("一屏三副图-手动边界调整")
  }

  func testCrosshairCenterDragAndOutsidePan() throws {
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    selectMain()
    let selected = info()
    let center = origin.withOffset(CGVector(dx: try XCTUnwrap(selected["crossX"] as? Double), dy: try XCTUnwrap(selected["crossY"] as? Double)))
    center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 50, dy: 10)))
    XCTAssertTrue(wait { self.info()["crossIndex"] as? Int != selected["crossIndex"] as? Int })
    try assertViewportKept(selected, info())
    let away = origin.withOffset(CGVector(dx: 45, dy: 100))
    away.press(forDuration: 0.05, thenDragTo: away.withOffset(CGVector(dx: 100, dy: 0)))
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertLessThan(try XCTUnwrap(info()["from"] as? Double), try XCTUnwrap(selected["from"] as? Double))
    shot("十字中心移线-其它区域拖图")
  }

  func testDragIndicatorTitleReordersCompletePane() throws {
    let original = info()
    let panes = try XCTUnwrap(original["panes"] as? [[String: Any]])
    let y = try XCTUnwrap(panes[0]["y"] as? Double)
    let lastY = try XCTUnwrap(panes[2]["y"] as? Double)
    let lastH = try XCTUnwrap(panes[2]["h"] as? Double)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: (original["plotW"] as? Double ?? 300) / 2, dy: y + (panes[0]["h"] as? Double ?? 80) / 2)).press(forDuration: 0.5,
      thenDragTo: origin.withOffset(CGVector(dx: 150, dy: lastY + lastH / 2)))
    XCTAssertTrue(wait { self.info()["subs"] as? [String] == ["OI", "MACD", "VOL"] }, String(describing: info()))
    XCTAssertEqual(info()["crosshair"] as? Bool, false)
    try assertViewportKept(original, info())
    shot("区域长按拖动-整块副图换序")
  }

  func testLiveMarketUpdatesWithinSeconds() throws {
    var samples: [[String: Double]] = []
    let start = Date()
    XCTAssertTrue(wait(seconds: 12) {
      let info = self.info()
      guard let close = info["lastClose"] as? Double, let volume = info["lastVolume"] as? Double else { return false }
      if samples.last?["close"] != close || samples.last?["volume"] != volume {
        samples.append(["seconds": Date().timeIntervalSince(start), "close": close, "volume": volume])
      }
      return samples.count >= 5
    }, "12 秒内应至少观测到 5 份不同 OHLCV，不能只靠 5–10 秒 REST 轮询")
    let a = XCTAttachment(string: String(describing: samples)); a.name = "实时行情变化采样"; a.lifetime = .keepAlways; add(a)
    shot("实时行情-持续更新")
  }

  private func revealChartControl(_ element: XCUIElement) {
    let scroll = app.scrollViews["panel.content"]
    XCTAssertTrue(scroll.waitForExistence(timeout: 5))
    for _ in 0..<24 {
      let bounds = scroll.frame
      if element.exists, element.isHittable, bounds.contains(element.frame) { return }
      // 半屏面板里整屏快扫会越过目标；按当前坐标决定方向，半屏一段地拖。
      let down = element.exists && element.frame.midY < bounds.midY
      let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.3 : 0.8))
      let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.8 : 0.3))
      start.press(forDuration: 0.1, thenDragTo: end)
    }
    XCTFail("图表面板找不到控件：" + element.identifier)
  }

  func testDepthLadderVisibleAtBothIntervals() throws {
    executionTimeAllowance = 420 // 图表面板里要滚动找「盘口」开关，机器重载时 180 秒曾被压线杀掉。
    app.buttons["interval.chart"].tap()
    let depth = app.buttons["chart.depth"]
    revealChartControl(depth); depth.tap(); closePanel()
    for interval in ["1h", "1m"] {
      app.tapIntervalChip(interval)
      XCTAssertTrue(wait(seconds: 40) {
        self.info()["symbol"] as? String == testInstrumentKey("BTCUSDT") && self.info()["interval"] as? String == interval
          && self.info()["renderedDepthRows"] as? Int == 10
      }, feedEvidence())
      shot("盘口梯-BTC-" + interval)
      let evidence = XCTAttachment(string: feedEvidence())
      evidence.name = "盘口梯-" + interval + "-绘制与订阅"; evidence.lifetime = .keepAlways; add(evidence)
    }
    app.buttons["interval.chart"].tap()
    revealChartControl(depth); depth.tap(); closePanel()
    XCTAssertTrue(wait { self.info()["renderedDepthRows"] as? Int == 0 })
  }

  func testExternalIndicatorsAndDepthRoundTrip() throws {
    executionTimeAllowance = 900 // 三次开图、线路往返与二十次品种切换都在同一条用例里。
    func toggleIndicator(_ id: String) {
      app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
      let toggle = app.buttons["indicator.switch." + id]
      revealChartControl(toggle); toggle.tap(); closePanel()
    }
    for id in (info()["subs"] as? [String] ?? []) { toggleIndicator(id) }
    for id in ["LSR", "TAKER", "BASIS"] { toggleIndicator(id) }
    XCTAssertEqual(info()["subs"] as? [String], ["LSR", "TAKER", "BASIS"])
    XCTAssertTrue(wait(seconds: 90) { Set(self.info()["externalReady"] as? [String] ?? []) == Set(["LSR", "TAKER", "BASIS"]) }, feedEvidence())
    shot("三副图-多空比-主动买卖比-基差")
    toggleIndicator("OI")
    XCTAssertEqual((info()["subs"] as? [String])?.count, 3, "不能出现第四格副图")
    // 满额时会替换最早那格；恢复三只本次指标。
    if !(info()["subs"] as? [String] ?? []).contains("LSR") {
      toggleIndicator("OI"); toggleIndicator("LSR")
    } else if (info()["subs"] as? [String] ?? []).contains("OI") {
      toggleIndicator("OI")
    }
    app.buttons["interval.chart"].tap()
    let depth = app.buttons["chart.depth"]
    revealChartControl(depth); depth.tap(); closePanel()
    XCTAssertTrue(wait(seconds: 30) { self.info()["depthLevels"] as? Int == 10 }, feedEvidence())
    for interval in ["1h", "1m"] {
      app.tapIntervalChip(interval)
      XCTAssertTrue(wait(seconds: 40) {
        self.info()["interval"] as? String == interval && self.info()["symbol"] as? String == testInstrumentKey("BTCUSDT")
          && self.info()["renderedDepthRows"] as? Int == 10
      }, "必须已实际绘制十行盘口梯；" + feedEvidence())
      shot("盘口梯-BTC-" + interval)
    }
    app.tapIntervalChip("1h")
    XCTAssertTrue(wait(seconds: 40) { self.info()["interval"] as? String == "1h" && self.info()["renderedDepthRows"] as? Int == 10 })
    var switches: [String] = []
    for index in 0..<20 {
      let symbol = index.isMultiple(of: 2) ? "ETHUSDT" : "BTCUSDT"
      XCTAssertTrue(app.openFavorites())
      let row = app.buttons["favorites.open." + testInstrumentKey(symbol)]
      XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
      XCTAssertTrue(wait(seconds: 30) { self.info()["symbol"] as? String == testInstrumentKey(symbol) && self.info()["depthSymbol"] as? String == testInstrumentKey(symbol) }, feedEvidence())
      switches.append("第\(index + 1)次：\(symbol)；" + feedEvidence())
    }
    let switchingLog = XCTAttachment(string: switches.joined(separator: "\n"))
    switchingLog.name = "连续切换20次-订阅与盘口品种一致"; switchingLog.lifetime = .keepAlways; add(switchingLog)
    app.buttons["bottom.settings"].tap()
    let gateway = app.buttons["settings.routePolicy.网关"]
    for _ in 0..<8 { if gateway.isHittable { break }; app.swipeUp() }
    gateway.tap(); leaveSettings()
    XCTAssertTrue(wait { self.info()["externalSupported"] as? Bool == false }, feedEvidence())
    XCTAssertEqual(info()["depthLevels"] as? Int, 0)
    XCTAssertTrue(wait { self.info()["renderedDepthRows"] as? Int == 0 })
    XCTAssertEqual((info()["subs"] as? [String])?.count, 3)
    shot("网关-三副图空态")
    app.buttons["bottom.settings"].tap()
    let direct = app.buttons["settings.routePolicy.直连"]
    for _ in 0..<8 { if direct.isHittable { break }; app.swipeUp() }
    direct.tap(); leaveSettings()
    XCTAssertTrue(wait(seconds: 40) { self.info()["depthLevels"] as? Int == 10 }, feedEvidence())
    app.buttons["interval.chart"].tap()
    revealChartControl(depth); depth.tap(); closePanel()
    XCTAssertTrue(wait { self.info()["depthLevels"] as? Int == 0 && self.info()["renderedDepthRows"] as? Int == 0 })
    shot("盘口关闭-回到普通图表")
    let log = XCTAttachment(string: feedEvidence()); log.name = "三指标与盘口-订阅日志"; log.lifetime = .keepAlways; add(log)
  }

  func testHistoricalOIUsesChartPeriod() throws {
    // 1d 在 UI 测试沙盒里没钉住（那六档是 1m 5m 15m 30m 1h 4h），
    // `tapIntervalChip` 会自己改从「更多」网格里选，结果一样。
    XCTAssertTrue(app.buttons[Ids.intervalMore].waitForExistence(timeout: 5))
    app.tapIntervalChip("1d")
    XCTAssertTrue(wait(seconds: 90) {
      self.info()["interval"] as? String == "1d" && self.info()["oiPeriod"] as? String == "1d" &&
      (self.info()["oiTimes"] as? [Double] ?? []).count > 35
    }, String(describing: info()))
    let times = try XCTUnwrap(info()["oiTimes"] as? [Double])
    XCTAssertTrue(times.allSatisfy { $0.truncatingRemainder(dividingBy: 86_400_000) == 0 })
    XCTAssertLessThan(try XCTUnwrap(times.first), Date().timeIntervalSince1970 * 1000 - 30 * 86_400_000)
    shot("日线OI-历史周期对齐")
  }

  func testTradFiSearchAndMarketData() throws {
    for symbol in ["SNDKUSDT", "SKHYUSDT", "MUUSDT"] {
      XCTAssertTrue(app.openSymbolSearch())
      let query = app.textFields["search.query"]
      XCTAssertTrue(query.waitForExistence(timeout: 5))
      query.tap()
      if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
      }
      query.typeText(symbol)
      let row = app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
      XCTAssertTrue(row.waitForExistence(timeout: 30), "未找到\(symbol)")
      row.tap()
      XCTAssertTrue(wait(seconds: 45) {
        self.info()["symbol"] as? String == testInstrumentKey(symbol) && (self.info()["bars"] as? Int ?? 0) > 20 &&
        (self.info()["lastClose"] as? Double ?? 0) > 0
      }, String(describing: info()))
      shot("TradFi-" + symbol)
    }
  }

  /// 分类只在加自选时按资产类型自动开；「新建分类」2026-09-24 删了（审查 §3.3：自建分组
  /// 早已判「不做」）。剩下的路这条用例各走一遍：自动开出来的分类能切、左滑「移到分类」
  /// 能把品种移进**还没开的预设分类**（当场开出这一格——没有「新建」之后第二类只能从这儿来）、
  /// 最后从自选点进图表。
  func testFavoritesCategoriesAndNavigation() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT"
    app.launch()
    if !app.buttons["favorites.more"].waitForExistence(timeout: 15) { XCTAssertTrue(app.openFavorites()) }
    let stocks = app.buttons["favorites.group.美股"]
    XCTAssertTrue(stocks.waitForExistence(timeout: 10), "SNDK 应当自己开出「美股」这一类")
    XCTAssertFalse(app.buttons["favorites.group.贵金属"].exists, "还没有贵金属，不该先开出这一格")
    XCTAssertTrue(waitHittable(stocks)); stocks.tap()
    let row = app.buttons["favorites.open.binance/usd_m/SNDKUSDT"]
    XCTAssertTrue(row.waitForExistence(timeout: 5))
    let move = revealFavoriteMove(row)
    XCTAssertTrue(move.exists, "左滑没露出「移到分类」：" + app.debugDescription)
    move.tap()
    let destination = app.buttons["贵金属"]
    XCTAssertTrue(wait { destination.exists && destination.isHittable }, "「移到分类」里要常驻还没开的预设分类")
    shot("独立自选页-移到分类")
    destination.tap()
    XCTAssertTrue(wait(seconds: 5) { !row.exists }, "移走之后不该还留在「美股」这一类里")
    let metals = app.buttons["favorites.group.贵金属"]
    XCTAssertTrue(metals.waitForExistence(timeout: 5), "挑了还没开的预设分类，分类条上该多出这一格")
    XCTAssertTrue(waitHittable(metals)); metals.tap()
    XCTAssertTrue(row.waitForExistence(timeout: 5)); shot("独立自选页-分类与品种")
    row.tap()
    XCTAssertTrue(wait(seconds: 45) { self.info()["symbol"] as? String == "binance/usd_m/SNDKUSDT" })
    XCTAssertTrue(app.buttons["interval.chart"].exists)
    // 「画线」2026-09-18 起是标签栏最左那一格，常驻——从自选页点进来也该在。
    XCTAssertTrue(app.buttons["bottom.draw"].exists)
  }

  /// 左滑一行，等「移到分类」那颗砖露出来（`SwipeToDelete`，`swipe.favorites.move`）。
  /// 先慢推，推不出来再快甩一下——和 `SemanticColorEvidenceUITests.revealBrick` 同一个手法。
  func revealFavoriteMove(_ row: XCUIElement) -> XCUIElement {
    let brick = app.buttons["swipe.favorites.move"]
    let from = row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
    let to = from.withOffset(CGVector(dx: -140, dy: 0))
    for velocity in [XCUIGestureVelocity.slow, XCUIGestureVelocity(900)] {
      if brick.exists && brick.frame.width > 20 { break }
      from.press(forDuration: 0.05, thenDragTo: to, withVelocity: velocity, thenHoldForDuration: 0.3)
      _ = wait(seconds: 2) { brick.exists && brick.frame.width > 20 }
    }
    return brick
  }

  func testColdLaunchFavoritesAndLiveQuotes() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    let price = app.staticTexts["favorites.price.binance/usd_m/BTCUSDT"]
    let change = app.staticTexts["favorites.change.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(wait(seconds: 30) { price.exists && price.label != "—" && change.exists && change.label.contains("%") })
    var values = Set<String>()
    XCTAssertTrue(wait(seconds: 15) {
      if price.exists { values.insert(price.label) }
      return values.count >= 2
    }, "自选价格未连续刷新")
    shot("冷启动自选-实时价格与涨跌幅")
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].tap()
    // 标签栏常驻，`bottom.settings` 在哪一页都在，拿它判不出落到哪儿了；
    // 「图表设置」那颗按钮只有行情页有，用它当准星。
    XCTAssertTrue(app.buttons["interval.chart"].waitForExistence(timeout: 8))
    XCUIDevice.shared.press(.home)
    app.activate()
    XCTAssertTrue(app.buttons["interval.chart"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.buttons["favorites.more"].exists, "普通前后台切换不重置首页")
  }

  /// 底栏五格轮一圈，报价还在跳。
  ///
  /// 2026-09-18 底栏改成常驻标签栏（画线 · 图表 · 自选 · 板块分类 · 设置），每一格都是独立一页
  /// （用户：「这四个底部拦都单独是一个页面」「切换页面下面还是那样」）。多页来回切
  /// 最容易出的事是把行情订阅切断——所以这条走满一圈，最后回自选页看价格还在不在刷新，
  /// 顺带确认标签栏本身每一步都在。
  ///
  /// 同一天加的第五格「板块分类」也走进这一圈：它自己另起一条 24h 全市场轮询
  /// （`SectorFeed`，只在可见且前台时跑），最容易出的事就是它启停的时候顺手把
  /// 行情页那条订阅也带停了，所以它必须夹在中间走一遍。
  func testQuotesKeepTickingAcrossAllFiveTabs() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    // 这条会真画一根线，给它一份只属于自己的档案，别把画线留给后面的用例。
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = UUID().uuidString
    app.launch()
    let price = app.staticTexts["favorites.price.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15), "有自选时冷启动该停在自选页")
    XCTAssertTrue(wait(seconds: 30) { price.exists && price.label != "—" }, "自选页第一轮报价没来")

    // ① 画线：对着用户当前看的这张图直接开画，点完横过去（横屏就是画线的工作台）。
    app.buttons["bottom.draw"].tap()
    // 画线进行中横屏侧栏整条收起，出口是画线栏上的「完成」，点完自动转回竖屏。
    let finish = app.buttons["draw.finish"]
    XCTAssertTrue(finish.waitForExistence(timeout: 25), "从自选页点「画线」没进画线态")
    XCTAssertFalse(app.buttons["land.exit"].exists, "画线进行中横屏侧栏还在")
    finish.tap()

    // ② 图表：退出画线就停在行情页，标签栏还在。
    XCTAssertTrue(app.buttons["interval.chart"].waitForExistence(timeout: 20), "画完没回行情页")
    XCTAssertTrue(app.buttons["bottom.chart"].exists, "行情页上没有标签栏")

    // ③ 板块分类：整页，顶上是加密／美股的硬切换，不占底栏第六格。
    app.buttons["bottom.sectors"].tap()
    XCTAssertTrue(app.otherElements["sector.page"].waitForExistence(timeout: 15), "点「板块分类」没进板块页")
    XCTAssertTrue(app.buttons["sector.market.us"].exists, "板块页顶上没有「美股」那一档")
    XCTAssertTrue(app.buttons["bottom.settings"].exists, "板块页上没有标签栏")

    // ④ 设置：整页，不是半屏。
    app.buttons["bottom.settings"].tap()
    XCTAssertTrue(app.buttons["settings.magnet"].waitForExistence(timeout: 10), "点「设置」没进设置页")
    XCTAssertFalse(app.buttons["panel.done"].exists, "设置是整页，不该有半屏那颗「完成」")
    XCTAssertTrue(app.buttons["bottom.favorites"].exists, "设置页上没有标签栏")

    // ⑤ 回自选：报价要接着跳，不能因为中间走了四页就断掉。
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 10), "点「自选」没回自选页")
    XCTAssertTrue(price.exists && price.label != "—", "转一圈回来自选页首帧应直接有真实报价")
    var values = Set<String>()
    XCTAssertTrue(wait(seconds: 25) {
      if price.exists { values.insert(price.label) }
      return values.count >= 2
    }, "五页轮一圈之后自选报价不再刷新")
    shot("标签栏-五页轮一圈后报价仍在刷新")
  }

  func testChangeBasisUpdatesFavorites() throws {
    app.buttons["bottom.settings"].tap()
    let basis = app.buttons["settings.changeBasis"]
    XCTAssertTrue(basis.waitForExistence(timeout: 5)); basis.tap()
    let option = app.buttons["上海8点 / UTC 0点"]
    XCTAssertTrue(wait { option.exists && option.isHittable }); option.tap()
    leaveSettings()
    XCTAssertTrue(app.openFavorites())
    addFavoriteFromSearch("BTCUSDT")
    // 涨跌口径不再常驻排序行，它是排序弹层里的一项——先把弹层打开再看。
    // 弹层里那一项是一颗整按钮，标题就是它的 label，没有单独的子 staticText。
    app.buttons["favorites.sort"].tap()
    let basis8 = app.buttons["8点涨跌幅"].firstMatch
    XCTAssertTrue(basis8.waitForExistence(timeout: 5))
    basis8.tap()
    let change = app.staticTexts["favorites.change.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(wait(seconds: 40) { change.exists && change.label.contains("%") })
    shot("自选-上海8点统一涨跌幅")
  }

  /// 「调整顺序」：批量编辑（勾选、全选、底部编辑条）2026-09-24 删了（审查 §3.3，判过「不做」），
  /// 剩下的就是这个排序模式——「…」里点进去，长按拖动整行，头部换成「完成」。
  func testFavoritesReorderMode() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.edit")
    XCTAssertTrue(app.buttons["favorites.editToggle"].waitForExistence(timeout: 5), "进了调整顺序，头部该换成「完成」")
    XCTAssertFalse(app.buttons["全选"].exists, "批量编辑已删，不该再有「全选」")
    XCTAssertFalse(app.buttons["favorites.select.binance/usd_m/ETHUSDT"].exists, "批量编辑已删，不该再有勾选框")
    let btc = app.buttons["favorites.open.binance/usd_m/BTCUSDT"]
    let sol = app.buttons["favorites.open.binance/usd_m/SOLUSDT"]
    let quote = app.staticTexts["favorites.price.binance/usd_m/BTCUSDT"]
    var previousFrame = quote.frame
    var stableFrames = 0
    XCTAssertTrue(wait(seconds: 5) {
      let frame = quote.frame
      stableFrames = frame == previousFrame ? stableFrames + 1 : 0
      previousFrame = frame
      return stableFrames >= 2
    }, "等待进入调整顺序的系统控件布局完成")
    let frozenPrice = quote.label, frozenFrame = quote.frame
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
      XCTAssertEqual(quote.label, frozenPrice, "调整顺序期间报价冻结，退出后恢复实时")
      XCTAssertEqual(quote.frame, frozenFrame, "调整顺序时右侧报价不能随WS抖动")
    }
    // 这一行整条都是 `favorites.open.<symbol>` 那个按钮，排序靠的是 List 自带的
    // 长按拖动——两个手势在抢同一个落点，按得不够久就被按钮先认走了（机器忙的时候
    // 0.6s 就会输）。按满 1.2s 让排序会话先起来，拖完再按住 0.8s 才松手，
    // 免得 SwiftUI 把它当成一次甩动而不是放下。
    let before = btc.frame.minY
    let source = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY))
    source.press(forDuration: 1.2,
                 thenDragTo: source.withOffset(CGVector(dx: 0, dy: sol.frame.midY - btc.frame.midY + 10)),
                 withVelocity: .slow,
                 thenHoldForDuration: 0.8)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > before + 30 }, "调整顺序时拖动应移动完整品种行")
    // 调整顺序时点一行什么都不做：不进图、不改任何东西。
    btc.tap()
    XCTAssertTrue(app.buttons["favorites.editToggle"].exists, "调整顺序时点一行不该跳走")
    // 切一格再切回来：调整顺序还得在。
    //
    // 自选页每切走一次就整个重建（`MainScreen.portraitBody` 里的 `switch tab` 只留
    // 当前那一格），这个模式原来是页面自己的 `@State`，跟着一起死。现在它住在宿主手里
    // （`FavoritesEditSession`），活过重建但不落盘。
    app.buttons["bottom.settings"].tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["favorites.more"].exists }, "没切到设置页")
    app.buttons["bottom.favorites"].tap()
    XCTAssertTrue(app.buttons["favorites.editToggle"].waitForExistence(timeout: 8), "切一格再回来，调整顺序自己退了")
    // 调整顺序下整页读的是冻住的那份报价。页面重建之后它要重新填上，别让行里空着。
    if frozenPrice != "—" {
      XCTAssertTrue(wait(seconds: 5) { self.app.staticTexts["favorites.price.binance/usd_m/ETHUSDT"].label != "—" },
                    "回到调整顺序之后行里的报价空着")
    }
    shot("自选-调整顺序")
    app.buttons["favorites.editToggle"].tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["favorites.editToggle"].exists }, "点「完成」没退出调整顺序")
    XCTAssertTrue(app.buttons["favorites.open.binance/usd_m/ETHUSDT"].exists)
  }

  /// 长按整行这一下 2026-09-20 起归预览卡（方案 §4.1）：`contextMenu` 把那半秒先认走了，
  /// `List` 自带的拖动排序（`onMove`）在普通状态下就起不来——同一个手势没法两件事都做。
  /// 排序没有丢，它退到卡旁边那份菜单的第一屏上（「调整顺序」），点一下进调整顺序，
  /// 那儿的长按仍旧是拖动。这条用例走的就是这条新路（原名 `testFavoritesDirectRowReorder`）。
  func testFavoritesLongPressPreviewThenReorder() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT"
    app.launch()
    let btc = app.buttons["favorites.open.binance/usd_m/BTCUSDT"]
    let sol = app.buttons["favorites.open.binance/usd_m/SOLUSDT"]
    XCTAssertTrue(btc.waitForExistence(timeout: 15))
    XCTAssertTrue(sol.waitForExistence(timeout: 5))
    btc.press(forDuration: 1.1)
    let reorder = app.buttons["调整顺序"]
    XCTAssertTrue(reorder.waitForExistence(timeout: 5), "长按整行应弹出预览卡和它那份菜单")
    XCTAssertTrue(app.buttons["打开"].exists, "菜单里该有「打开」")
    shot("自选-长按预览卡")
    reorder.tap()
    XCTAssertTrue(app.buttons["favorites.editToggle"].waitForExistence(timeout: 5),
                  "「调整顺序」应直接进调整顺序模式")
    // 整行还是 `favorites.open.<symbol>` 那颗按钮，排序和它抢同一个落点：按满 1.2s
    // 让排序会话先起来，拖完再按住 0.8s 才松手（同 `testFavoritesReorderMode`）。
    XCTAssertTrue(wait(seconds: 5) { btc.exists && sol.exists && btc.frame.minY < sol.frame.minY })
    let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
    let start = origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY))
    let end = origin.withOffset(CGVector(dx: btc.frame.midX, dy: sol.frame.maxY + 20))
    start.press(forDuration: 1.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.8)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > sol.frame.minY }, "编辑态长按整行应拖动排序")
    shot("自选-长按菜单进编辑后排序")
    app.buttons["favorites.editToggle"].tap()
  }

  /// 右划整个不响应（2026-09-24 审查 U8）：原来右划露的是和左划同一颗「取消自选」，
  /// 同一个动作一页上三处入口。现在右划既不露砖、行也不动（不许露半截），自选一个不少。
  func testFavoritesRightSwipeDoesNothing() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    let btc = app.buttons["favorites.open.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(btc.waitForExistence(timeout: 15))
    let band = btc.frame
    let width = app.windows.firstMatch.frame.width
    // 起手点从左到右三处，每处慢推一次、快甩一次（落点收在屏幕以内，手指出不了屏幕）。
    // 每一下之后：行没动、没露砖、也没被当成一次点击进了图表。
    for x in [80, width * 0.5, width - 40] {
      for velocity in [XCUIGestureVelocity.slow, XCUIGestureVelocity(900)] {
        let from = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
          .withOffset(CGVector(dx: x, dy: band.midY))
        from.press(forDuration: velocity == .slow ? 0.1 : 0.01,
                   thenDragTo: from.withOffset(CGVector(dx: min(120, width - 2 - x), dy: 0)),
                   withVelocity: velocity, thenHoldForDuration: 0.3)
        XCTAssertTrue(btc.waitForExistence(timeout: 2),
                      "右划（起手 x=\(Int(x))，\(velocity == .slow ? "慢推" : "快甩")）之后自选行不见了：" + app.debugDescription)
        XCTAssertEqual(btc.frame.minX, band.minX, accuracy: 0.5, "右划把行拉动了（露半截）")
      }
    }
    XCTAssertFalse(app.buttons["swipe.delete"].exists, "右划不该再露「取消自选」")
    XCTAssertFalse(app.buttons["swipe.favorites.move"].exists, "右划不该露任何砖")
    btc.swipeRight()
    XCTAssertTrue(btc.exists && app.buttons["favorites.open.binance/usd_m/ETHUSDT"].exists, "右划动到了自选")
    // 左划短短一下（刚过吸附门槛）：砖露出来，页面不许同时被当成一次点跳去图表。
    let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: width - 60, dy: band.midY))
    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -70, dy: 0)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertTrue(btc.waitForExistence(timeout: 2), "左划短短一下就进了图表：" + app.debugDescription)
    XCTAssertTrue(wait(seconds: 3) { self.app.buttons["swipe.favorites.move"].exists }, "左划过了门槛却没露砖")
    shot("自选-右划不响应")
  }

  /// 仅用户明确要求写入正式自选时单独运行；常规回归保持跳过。
  func testInstallRequestedFavoritesInUserStore() throws {
    try ManualTool.skipUnlessRequested(self, what: "把用户点名的品种写进正式自选")
    app.terminate()
    app.launchEnvironment.removeValue(forKey: "KANPAN_TEST_PROFILE")
    app.launchEnvironment.removeValue(forKey: "KANPAN_TEST_FAVORITES")
    app.launch()
    if !app.buttons["favorites.more"].waitForExistence(timeout: 3) {
      XCTAssertTrue(app.symbolLabel.waitForExistence(timeout: 20))
      XCTAssertTrue(app.openFavorites())
    }
    let groups: [(String, [String])] = [
      ("加密", ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"]),
      ("美股", ["AAPLUSDT", "MSFTUSDT", "NVDAUSDT", "AMZNUSDT", "GOOGLUSDT", "METAUSDT", "TSLAUSDT", "SNDKUSDT", "MUUSDT", "SKHYUSDT", "SKHYNIXUSDT", "MRVLUSDT", "LITEUSDT", "AVGOUSDT", "SOXLUSDT"]),
      ("贵金属", ["XAUUSDT", "XAGUSDT"])
    ]
    // 「新建分类」2026-09-24 删了：站进那一类再加，加进来的品种就留在那一类里；
    // 那一类还没开的话，把第一支左滑「移到分类」移过去（预设分类当场开出来）。
    for (group, symbols) in groups {
      let chip = app.buttons["favorites.group." + group]
      for symbol in symbols {
        if chip.exists, !chip.isSelected, waitHittable(chip) { chip.tap() }
        let row = app.buttons["favorites.open." + testInstrumentKey(symbol)]
        if row.exists { continue }
        addFavoriteFromSearch(symbol)
        guard !chip.exists else { continue }
        revealFavoriteMove(row).tap()
        let target = app.buttons[group]
        XCTAssertTrue(wait { target.exists && target.isHittable }); target.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "移到「\(group)」没开出这一类")
      }
    }
    /// 分类条能横滑（用户 2026-09-18 定的），排不下的分类往两边滑着找，不再折进设置菜单。
    func group(_ name: String) {
      let chip = app.buttons["favorites.group." + name]
      let strip = app.descendants(matching: .any).matching(identifier: "favorites.groups").firstMatch
      for _ in 0..<6 where !chip.isHittable { strip.swipeRight() }
      for _ in 0..<6 where !chip.isHittable { strip.swipeLeft() }
      XCTAssertTrue(chip.isHittable); chip.tap()
    }
    group("加密")
    let btc = app.buttons["favorites.open.binance/usd_m/BTCUSDT"]
    let sol = app.buttons["favorites.open.binance/usd_m/SOLUSDT"]
    let startY = btc.frame.minY
    let center = btc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.press(forDuration: 0.8, thenDragTo: center.withOffset(CGVector(dx: 0, dy: sol.frame.maxY - btc.frame.midY + 20)))
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > startY + 30 }, "直接拖动品种行应改变排序")
    let crypto = groups[0].1
    let movedOrder = crypto.sorted { app.buttons["favorites.open." + testInstrumentKey($0)].frame.minY < app.buttons["favorites.open." + testInstrumentKey($1)].frame.minY }
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 20), "结束后台进程后应直接恢复自选")
    group("加密")
    let restoredOrder = crypto.sorted { app.buttons["favorites.open." + testInstrumentKey($0)].frame.minY < app.buttons["favorites.open." + testInstrumentKey($1)].frame.minY }
    XCTAssertEqual(restoredOrder, movedOrder, "自定义顺序应在冷启动后完整保留")
    // 验收后恢复BTC排首位，保留用户请求的品种组织。
    let eth = app.buttons["favorites.open.binance/usd_m/ETHUSDT"]
    let restore = btc.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    restore.press(forDuration: 0.8, thenDragTo: eth.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY < eth.frame.minY })
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 20))
    for (name, symbols) in groups {
      group(name)
      for symbol in symbols {
        let row = app.buttons["favorites.open." + testInstrumentKey(symbol)]
        for _ in 0..<4 { if row.exists { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(row.exists, "冷启动丢失分类成员：" + name + "/" + symbol)
      }
      shot("正式自选持久化-" + name)
    }
    group("加密")
    shot("正式自选-冷启动二十二品种")
  }

  /// 正式存档验收：保留用户收藏，避免隔离测试页在手机上显示空列表。
  func testUserSessionLatestEdgeAndReentry() throws {
    try ManualTool.skipUnlessRequested(self, what: "正式存档下的「最新」边界与重进")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    try verifyLatestEdgeAndReentry()
  }

  func testLatestEdgeAndReentryCompatibility() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    try verifyLatestEdgeAndReentry()
  }

  private func verifyLatestEdgeAndReentry() throws {
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 15))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, String(describing: info()))
    func gap() -> Double { self.info()["latestRightGap"] as? Double ?? 99999 }
    XCTAssertTrue(wait(seconds: 5) { abs(gap()) < 0.5 }, "从列表进入末根应贴绘图区右缘")
    let width = try XCTUnwrap(info()["plotW"] as? Double)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    let right = origin.withOffset(CGVector(dx: width * 0.75, dy: 140))
    let left = origin.withOffset(CGVector(dx: width * 0.3, dy: 140))
    right.press(forDuration: 0.05, thenDragTo: left, withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertTrue(wait(seconds: 4) { abs(gap()) < 0.5 }, "最新端左滑释放应回位")
    left.press(forDuration: 0.05, thenDragTo: right, withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertLessThan(gap(), -40, "右滑进入历史，不应回最新")
    right.press(forDuration: 0.05, thenDragTo: right.withOffset(CGVector(dx: -30, dy: 0)), withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertLessThan(gap(), -20, "历史区左滑不能强制吸回最新")
    XCTAssertTrue(app.openFavorites())
    XCTAssertTrue(app.buttons["favorites.open.binance/usd_m/BTCUSDT"].waitForExistence(timeout: 5))
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    XCTAssertTrue(wait(seconds: 4) { abs(gap()) < 0.5 }, "同品种重进也回到最新右缘")
    shot("默认末根贴右-最新端回弹-历史自由拖动-重进复位")
  }

  func testComfortPalettesAndLayout() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT,SNDKUSDT,XAUUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.close")
    let original = info()
    // 配色（青苔 / 陶土）和深浅（浅 / 深）是两根独立的轴，所以两两都要走一遍：
    // 换的只有颜色，K 线底座的 span / plotW / spacing / mainH / height 一个数都不许动。
    // 画布的底跟着皮肤走（`367d572`）：只有「经典」照抄 AICoin 的白 / 深蓝，青苔和陶土
    // 取自己种子里的 `chart`，图区和页面读成一块材料。所以这里每一格的期望值都不一样，
    // 而不是从前那样只随深浅变。蜡烛 / 涨跌 / 均线仍然只有 AICoin 那一套，不在这条的射程里。
    for (skin, mode, background) in [("sage", "浅色", "#F3F7F4"), ("sage", "深色", "#0B120F"),
                                     ("terra", "浅色", "#FBF6F0"), ("terra", "深色", "#16100C"),
                                     ("classic", "浅色", "#FFFFFF"), ("classic", "深色", "#0D111C")] {
      app.buttons["bottom.settings"].tap()
      let card = app.buttons["display.theme." + skin]
      XCTAssertTrue(card.waitForExistence(timeout: 5), "配色卡要在树里：\(skin)")
      // 面板是往上推出来的：`waitForExistence` 一过就去问 `isHittable`，问到的是
      // 动画还在半路上的那一帧——卡片已经在无障碍树里，但还没落到它最终的位置上，
      // 于是「存在但点不着」。等它真能点，别拿存在当能点。
      XCTAssertTrue(wait(seconds: 5) { card.isHittable }, "配色卡要能点：\(skin)")
      card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      let segment = app.buttons["display.mode." + mode]
      XCTAssertTrue(segment.waitForExistence(timeout: 5))
      segment.tap()
      XCTAssertFalse(app.buttons["display.still"].exists)
      XCTAssertFalse(app.buttons["display.eyeBreak"].exists)
      leaveSettings()
      XCTAssertTrue(wait(seconds: 5) { self.info()["background"] as? String == background })
      for key in ["span", "plotW", "spacing", "mainH", "height"] {
        XCTAssertEqual(try XCTUnwrap(info()[key] as? Double), try XCTUnwrap(original[key] as? Double), accuracy: 0.001)
      }
      shot("配色-" + skin + mode + "-图表")
      XCTAssertTrue(app.openFavorites())
      let feed = app.descendants(matching: .any).matching(identifier: "favorites.feed").firstMatch
      // 自选页停在「他上次看的那一类」——这一栏是 `Prefs.favoritesGroup`，2026-09-19
      // 从 `SymbolPrefs.selectedGroupID` 搬进偏好里之后跟着人走、跨启动也记着。
      // 而这个种子（BTC/ETH/SOL/SNDK/XAU）自动分出来的三类里，第一类是「贵金属」
      // （XAU 靠 ISO 资产代码当场就能认，加密和美股要等合约目录到货才认得出来），
      // 没有存过选择时落在它身上；这条用例自己在下面又把三类挨个点了一遍、
      // 最后停在「贵金属」。所以「进自选页就该看见 BTC 那一行」是旧设计的写法，
      // 现在既进不去也不该成立。要验 BTC 就先回到它所在的「加密」类。
      let crypto = app.buttons["favorites.group.加密"]
      XCTAssertTrue(crypto.waitForExistence(timeout: 15), "自选页要有「加密」这一类")
      crypto.tap()
      XCTAssertTrue(app.buttons["favorites.open.binance/usd_m/BTCUSDT"].waitForExistence(timeout: 5))
      XCTAssertTrue(wait(seconds: 5) {
        (feed.value as? String)?.contains("background=" + background) == true
      })
      for name in ["加密", "美股", "贵金属"] {
        let tab = app.buttons["favorites.group." + name]
        XCTAssertTrue(tab.exists)
        XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
        // 分类胶囊不能和上面那条搜索框挤在一起。原来这里比的是 `maxX <= add.minX`——
        // 那是「加号还蹲在同一行最右边」年代的写法；`1f6f220` 之后头部改成了两行，
        // `favorites.add` 就是那条横贯整行的长搜索框（`minX` 12），胶囊自然从它下面
        // 重新起头，横向比一定不成立。真正要守的是纵向不压：胶囊整条在搜索框下沿以下。
        XCTAssertGreaterThanOrEqual(tab.frame.minY, app.buttons["favorites.add"].frame.maxY)
        // 也别让它甩出页面右缘——这条是原来那句横向断言真正想拦的事。
        XCTAssertLessThanOrEqual(tab.frame.maxX, app.windows.firstMatch.frame.maxX)
      }
      shot("配色-" + skin + mode + "-自选")
      favoritesAction("favorites.close")
    }
  }

  /// 换品种只剩放大镜一条路：左上角的品种名不再弹任何东西（用户 2026-09-18 定的），
  /// 这条用例连着验「点了不弹」和「搜索页照样能按板块筛、能换过去」。
  func testSymbolSearchAndMarketSectors() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    favoritesAction("favorites.close")
    let top = app.symbolLabel
    XCTAssertTrue(top.waitForExistence(timeout: 20))
    app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: top.frame.midX, dy: top.frame.midY)).tap()
    XCTAssertFalse(app.textFields["search.query"].waitForExistence(timeout: 2),
                   "左上角品种名不该再弹换品种的层")
    shot("行情页-左上角品种名不可点")
    // 板块筛选归品种整页，搜索页不做：打个字把「查看全部」逼出来，从那儿进整页。
    XCTAssertTrue(app.openSymbolPicker(matching: "SNDK"))
    app.buttons["symbols.market"].tap()
    let equities = app.buttons["美股"]
    XCTAssertTrue(equities.waitForExistence(timeout: 5)); equities.tap()
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/SNDKUSDT"].waitForExistence(timeout: 10))
    shot("交易所-美股板块筛选")
    app.buttons["symbols.row.binance/usd_m/SNDKUSDT"].tap()
    XCTAssertTrue(wait(seconds: 20) { self.info()["symbol"] as? String == "binance/usd_m/SNDKUSDT" })
  }

  func testLatestQuoteDoesNotRegressAcrossIntervals() throws {
    func quote() -> [String: String] {
      let element = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
      let raw = element.value as? String ?? ""
      return Dictionary(raw.split(separator: ";").compactMap { field in
        let parts = field.split(separator: "=", maxSplits: 1)
        return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
      }, uniquingKeysWith: { _, b in b })
    }
    for symbol in ["BTCUSDT", "SNDKUSDT", "ETHUSDT", "BTCUSDT"] {
      if symbol != "BTCUSDT" || info()["symbol"] as? String != "binance/usd_m/BTCUSDT" {
        XCTAssertTrue(app.openSymbolSearch())
        let query = app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap()
        if let old = query.value as? String, !old.isEmpty { query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        query.typeText(symbol)
        let row = app.buttons["symbols.row." + testInstrumentKey(symbol)]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
      }
      XCTAssertTrue(wait(seconds: 20) { quote()["symbol"] == testInstrumentKey(symbol) && (Int64(quote()["time"] ?? "0") ?? 0) > 0 })
      var stamp = Int64(quote()["time"] ?? "0") ?? 0
      for interval in ["1m", "1h", "4h", "1h"] {
        let previousSpacing = info()["spacing"] as? Double
        app.tapIntervalChip(interval)
        // Read during the actual transition, before the REST candle request finishes.
        for _ in 0..<3 {
          let value = quote()
          XCTAssertEqual(value["symbol"], testInstrumentKey(symbol))
          let next = Int64(value["time"] ?? "0") ?? 0
          XCTAssertGreaterThanOrEqual(next, stamp)
          XCTAssertGreaterThan(Double(value["last"] ?? "0") ?? 0, 0)
          stamp = next
        }
        XCTAssertTrue(wait(seconds: 20) { self.info()["symbol"] as? String == testInstrumentKey(symbol) && self.info()["interval"] as? String == interval })
        if let previousSpacing { XCTAssertEqual(self.info()["spacing"] as? Double ?? 0, previousSpacing, accuracy: 0.02) }
      }
    }
    shot("多品种多周期-报价时序")
  }

  /// 从自选页加一个品种。
  ///
  /// 加自选的入口这一页只剩头部中间那条长搜索框（`favorites.add`，用户 2026-09-18
  /// 定的：以前的加号和放大镜开的是同一张搜索页，两颗并成一颗，又照推特摊成了长条）。
  /// 流程不再是以前选品页
  /// 那样「点中一行就算加上了」，而是「打字 → 点那一行的星 → 取消退回自选」。
  /// 星是个开关，已经在自选里的品种再点一下反而会被移除，所以先看 label 再决定点不点。
  func addFavoriteFromSearch(_ symbol: String) {
    app.buttons["favorites.add"].tap()
    let query = app.textFields["search.query"]
    XCTAssertTrue(query.waitForExistence(timeout: 5)); query.tap()
    if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
      query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
    query.typeText(symbol)
    let star = app.buttons["symbols.star." + testInstrumentKey(symbol)]
    XCTAssertTrue(star.waitForExistence(timeout: 30), "搜索页没搜到 " + symbol)
    if star.label == "加入自选" { star.tap() }
    app.buttons["search.cancel"].tap()
    XCTAssertTrue(wait(seconds: 5) { !query.exists }, "取消后应收起搜索页")
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["favorites.open." + testInstrumentKey(symbol)].waitForExistence(timeout: 5),
                  "加完应停在品种落进去的那一组，看得见刚加的那一行")
  }

  /// 被测 app 掉到后台就把它拉回前台，拉不回来才判红。
  ///
  /// 2026-09-18 全量 13 台矩阵里，iPad Pro 11-inch (M5) 上
  /// `testFavoritesCategoryOverflow` 红过一次（`docs/acceptance/M8/ui-test/iPad-Pro-11-inch-M5.log`
  /// 第 4395 行附近），当时只记进了「未做 / 边界」。2026-09-19 复现出来了，机制是这样的：
  ///
  ///     t = 22.50s Tap "favorites.more" Button
  ///     t = 22.55s     Check for interrupting elements affecting "favorites.more" Button
  ///     t = 22.60s         Wait for com.apple.mobileslideshow to idle   ← 照片 App 抢了前台
  ///     t = 31.23s     Open com.mdd.kanpan / Activate com.mdd.kanpan    ← XCUITest 自己拉回来
  ///     t = 31.90s     Synthesize event                                 ← 这一下点击丢了
  ///     t = 32.32s Waiting 4.0s for "favorites.newGroup" Button to exist ← 菜单没开，红
  ///
  /// 也就是说：别的 app（那次是照片，`com.apple.mobileslideshow`，13 台 × 49 条日志里
  /// 只出现过这一次，就在挂掉的那一秒）抢到前台 → XCUITest 的「Check for interrupting
  /// elements」卡在等它 idle，被测 app 期间掉到后台 → XCUITest 再 `Open`/`Activate`
  /// 把它拉回来 → 那一下已经合成好的点击落在刚重新激活的 app 上，被丢掉。同一机制还有
  /// 第二种死法：app 在后台时，XCUITest 把**我们自己的**「新建分类」弹窗当成「打断元素」，
  /// 用默认处理器点掉了「取消」，之后的「保存」自然点不到（`Failed to compute hit point`）。
  ///
  /// 真实用户碰不到这个现象——这不是 app 的缺陷，是用例在「前台被抢走」这个边界上
  /// 一点容错都没有。守卫只负责把 app 摆回前台，恢复靠调用方自己重来一遍；
  /// 功能真坏了照样红，因为重来那一遍还是要看到同样的结果才算过。
  func ensureForeground(file: StaticString = #filePath, line: UInt = #line) {
    guard app.state != .runningForeground else { return }
    app.activate()
    XCTAssertTrue(wait(seconds: 10) { self.app.state == .runningForeground },
                  "app 掉到后台之后拉不回前台（state=\(app.state.rawValue)）", file: file, line: line)
  }

  /// 等一个元素重新变得可点，等不到返回 false（**不判红**，留给调用方决定）。
  ///
  /// 前台被抢走的那几秒里，屏幕上的东西会集体「存在但点不动」：`exists` 为真、
  /// `isHittable` 为假。2026-09-19 注入照片 App 的那一轮里就是这样——「保存」还在，
  /// 但那一刻算不出命中点，直接 `tap()` 会抛 `Failed to compute hit point`（XCTest
  /// 自己记的失败，Swift 这边接不住）。所以凡是要点的东西都先等它可点，再点。
  /// app 被 `Open`/`Activate` 拉回前台之后这个状态会自己好，等几秒就够了。
  ///
  /// 先问一次再进等待：`XCTNSPredicateExpectation` 第一次求值前会先歇一秒，本来就点得动的
  /// 东西也要平白多花 1 秒。这条用例上这样的点有二十来个，不走快路就是整整 +20 秒
  /// （实测干净跑 65s → 81s）。
  func waitHittable(_ element: XCUIElement, seconds: Double = 6) -> Bool {
    if element.exists, element.isHittable { return true }
    return wait(seconds: seconds) { element.exists && element.isHittable }
  }

  /// 「…」菜单开着没有。「调整顺序」是 `moreList` 里第一行，任何状态下都在，拿它当准星
  /// （原来的准星「新建分类」2026-09-24 删了）。
  var favoritesMenuIsOpen: Bool { app.buttons["favorites.edit"].exists }

  /// 开「…」菜单，没开就重来一次。返回是否真的开着；**不做断言**，好让调用方决定怎么收场。
  ///
  /// 只在「菜单确实没开」的前提下才重点：`FavoritesView` 的「…」是自绘浮层
  /// （`overlayPreferenceValue` → `floatingMenu`），菜单一开，那层吃点击的透明遮罩
  /// （`Color.black.opacity(0.001)`）就盖在「…」上面，再点一下等于点在遮罩上，
  /// 反而把已经开着的菜单关掉。
  @discardableResult func openFavoritesMenu() -> Bool {
    for attempt in 0..<2 {
      if favoritesMenuIsOpen { return true }
      if attempt > 0 { ensureForeground() }
      let more = app.buttons["favorites.more"]
      guard more.waitForExistence(timeout: 4), waitHittable(more) else { continue }
      more.tap()
      if app.buttons["favorites.edit"].waitForExistence(timeout: 4) { return true }
    }
    return favoritesMenuIsOpen
  }

  /// 点「…」里的一项，成了返回 true。同样不做断言，重试路径上要靠返回值判断。
  @discardableResult func tapFavoritesMenuAction(_ identifier: String) -> Bool {
    guard openFavoritesMenu() else { return false }
    let action = app.buttons[identifier]
    guard action.waitForExistence(timeout: 4), waitHittable(action) else { return false }
    action.tap()
    return true
  }

  func favoritesAction(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
    dismissNotificationBanner()
    // 「返回行情」既不在「…」里也不在分类栏左端了：2026-09-18 底栏改成常驻标签栏之后，
    // 页面之间的来回一律归标签栏管，自选页自己不再画返回按钮。
    if identifier == "favorites.close" {
      let chartTab = app.buttons["bottom.chart"]
      XCTAssertTrue(chartTab.waitForExistence(timeout: 4), "标签栏上没有「图表」", file: file, line: line)
      for attempt in 0..<2 {
        if attempt > 0 { ensureForeground() }
        if waitHittable(chartTab) { chartTab.tap() }
        if wait(seconds: 5, { !self.app.buttons["favorites.more"].exists && self.app.buttons["interval.chart"].isHittable }) { return }
      }
      XCTFail("点「图表」离不开自选页：重试一次仍然没切过去", file: file, line: line)
      return
    }
    XCTAssertTrue(tapFavoritesMenuAction(identifier),
                  "「…」里点不到 \(identifier)：重试一次仍然没开", file: file, line: line)
  }

  /// Physical-device notifications can cover the top category bar. Dismiss only
  /// the system banner, without opening it or changing notification preferences.
  private func dismissNotificationBanner() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let banner = springboard.descendants(matching: .any)
      .matching(identifier: "NotificationShortLookView").firstMatch
    for _ in 0..<3 {
      guard banner.exists else { return }
      banner.swipeUp()
    }
    XCTAssertFalse(banner.exists, "系统通知仍遮挡顶部分类栏")
  }

  /// 分类条横滑、「…」菜单的内容。分类全是按资产类型自己开出来的（「新建分类」
  /// 2026-09-24 删了），所以四支种子摆出三格：加密 / 美股 / 贵金属。
  func testFavoritesCategoryOverflow() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SNDKUSDT,XAUUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    XCTAssertFalse(app.textFields["favorites.query"].exists)
    XCTAssertGreaterThanOrEqual(app.buttons["favorites.group.加密"].frame.height, 44)
    for name in ["加密", "美股", "贵金属"] {
      XCTAssertTrue(app.buttons["favorites.group." + name].waitForExistence(timeout: 10), "种子没自动开出「\(name)」")
    }
    shot("自选-顶部分类条")
    dismissNotificationBanner()
    XCTAssertTrue(openFavoritesMenu(), "点「…」开不出菜单：重试一次仍然没开")
    XCTAssertFalse(app.staticTexts["更多分类"].exists, "分类条能横滑了，菜单里不该再有「更多分类」")
    XCTAssertFalse(app.buttons["favorites.newGroup"].exists, "自建分类判了不做，菜单里不该再有「新建分类」")
    XCTAssertFalse(app.buttons["favorites.rename"].exists, "自建分类判了不做，菜单里不该再有「重命名」")
    XCTAssertTrue(app.buttons["favorites.deleteGroup"].exists, "有三类时「删除当前分类」该在")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
    XCTAssertTrue(wait(seconds: 4) { !self.favoritesMenuIsOpen })
    favoritesAction("favorites.close")
    XCTAssertTrue(app.openFavorites())
    let strip = app.descendants(matching: .any).matching(identifier: "favorites.groups").firstMatch
    XCTAssertTrue(strip.waitForExistence(timeout: 4))
    let crypto = app.buttons["favorites.group.加密"]
    for _ in 0..<4 where !crypto.isHittable { strip.swipeRight() }
    XCTAssertTrue(crypto.isHittable, "往右滑要能滑回第一个分类")
    crypto.tap()
    favoritesAction("favorites.edit")
    XCTAssertTrue(app.buttons["favorites.editToggle"].waitForExistence(timeout: 4))
    XCTAssertFalse(app.buttons["全选"].exists, "批量编辑已删，调整顺序里不该有「全选」")
    app.buttons["favorites.editToggle"].tap()
    app.buttons["favorites.add"].tap()
    XCTAssertTrue(app.textFields["search.query"].waitForExistence(timeout: 5))
  }

  /// 只剩一类时不给删：删了页面就空了，只能再加一支把它开回来（2026-09-24 审查 U8）。
  func testFavoritesLastCategoryHasNoDelete() throws {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    XCTAssertTrue(app.buttons["favorites.group.加密"].waitForExistence(timeout: 10))
    XCTAssertTrue(openFavoritesMenu(), "点「…」开不出菜单")
    XCTAssertFalse(app.buttons["favorites.deleteGroup"].exists, "只剩一类时不该有「删除当前分类」")
    shot("自选-只剩一类的菜单")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
  }

  func testUserSessionFreshQuotesAndReorder() throws {
    try ManualTool.skipUnlessRequested(self, what: "正式存档下的前台恢复报价")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    XCTAssertFalse(app.buttons["favorites.group.全部"].exists)
    XCTAssertFalse(app.buttons["favorites.group.默认"].exists)
    let feed = app.descendants(matching: .any).matching(identifier: "favorites.feed").firstMatch
    let price = app.staticTexts["favorites.price.binance/usd_m/BTCUSDT"]
    XCTAssertTrue(wait(seconds: 20) { price.exists && price.label != "—" })
    let cold = feed.value as? String ?? ""
    let coldSession = cold.components(separatedBy: ";").first ?? ""
    print("FreshQuotes cold: " + cold)
    var prices = Set<String>()
    XCTAssertTrue(wait(seconds: 15) { prices.insert(price.label); return prices.count > 1 })
    favoritesAction("favorites.close")
    XCTAssertTrue(app.buttons["interval.chart"].waitForExistence(timeout: 8))
    let stayUntil = Date().addingTimeInterval(3)
    XCTAssertTrue(wait(seconds: 5) { Date() >= stayUntil })
    XCTAssertTrue(app.openFavorites())
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 3))
    XCTAssertTrue(price.exists && price.label != "—", "返回自选首帧应直接使用持续订阅的真实报价")
    XCTAssertEqual((feed.value as? String ?? "").components(separatedBy: ";").first, coldSession,
      "前台切页不能重建报价会话")
    print("FreshQuotes return: " + (feed.value as? String ?? ""))
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].swipeLeft()
    XCTAssertTrue(app.buttons["取消自选"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["置顶"].exists)
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].swipeRight()
    XCUIDevice.shared.press(.home)
    // 留在后台超过旧连接宽限时间，验证新会话而非旧画面还在。
    let until = Date().addingTimeInterval(7)
    XCTAssertTrue(wait(seconds: 10) { Date() >= until })
    app.activate()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 8))
    XCTAssertTrue(wait(seconds: 20) { price.exists && price.label != "—" && (feed.value as? String ?? "").components(separatedBy: ";").first != coldSession })
    print("FreshQuotes resume: " + (feed.value as? String ?? ""))
    shot("正式自选-前台恢复实时报价")
  }

  func testUserSessionRowReorderAndMove() throws {
    try ManualTool.skipUnlessRequested(self, what: "正式存档下的拖动排序与移动分类")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    let group = app.buttons["favorites.group.加密"]
    group.tap()
    let btc = app.buttons["favorites.open.binance/usd_m/BTCUSDT"], doge = app.buttons["favorites.open.binance/usd_m/DOGEUSDT"]
    let originalY = btc.frame.minY
    let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY)).press(forDuration: 1,
      thenDragTo: origin.withOffset(CGVector(dx: doge.frame.midX, dy: doge.frame.midY)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY > originalY + 80 }, "长按普通行拖动应更改顺序")
    let crypto = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT"]
    let moved = crypto.sorted { app.buttons["favorites.open." + testInstrumentKey($0)].frame.minY < app.buttons["favorites.open." + testInstrumentKey($1)].frame.minY }
    app.terminate(); app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    group.tap()
    let restored = crypto.sorted { app.buttons["favorites.open." + testInstrumentKey($0)].frame.minY < app.buttons["favorites.open." + testInstrumentKey($1)].frame.minY }
    XCTAssertEqual(restored, moved)
    let eth = app.buttons["favorites.open.binance/usd_m/ETHUSDT"]
    origin.withOffset(CGVector(dx: btc.frame.midX, dy: btc.frame.midY)).press(forDuration: 1,
      thenDragTo: origin.withOffset(CGVector(dx: eth.frame.midX, dy: eth.frame.minY)), withVelocity: .slow, thenHoldForDuration: 0.5)
    XCTAssertTrue(wait(seconds: 5) { btc.frame.minY < eth.frame.minY })
    shot("正式自选-原生长按排序与冷启动持久化")
    btc.swipeLeft()
    let move = app.buttons["移到分类"]
    XCTAssertTrue(move.waitForExistence(timeout: 4)); move.tap()
    let stocks = app.buttons["美股"]
    XCTAssertTrue(stocks.waitForExistence(timeout: 4)); stocks.tap()
    XCTAssertTrue(wait(seconds: 4) { !btc.exists })
    app.buttons["favorites.group.美股"].tap()
    XCTAssertTrue(btc.waitForExistence(timeout: 4))
    btc.swipeLeft(); app.buttons["移到分类"].tap()
    app.buttons["加密"].tap()
    app.buttons["favorites.group.加密"].tap()
    XCTAssertTrue(btc.waitForExistence(timeout: 4))
    shot("正式自选-滑动移到分类")
  }

  func testUserSessionChartInteractions() throws {
    try ManualTool.skipUnlessRequested(self, what: "正式存档下的图表交互")
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    XCTAssertTrue(app.buttons["favorites.more"].waitForExistence(timeout: 15))
    app.buttons["favorites.group.加密"].tap()
    app.buttons["favorites.open.binance/usd_m/BTCUSDT"].tap()
    XCTAssertTrue(canvas.waitForExistence(timeout: 15))
    XCTAssertTrue(wait(seconds: 60) { (self.info()["bars"] as? Int ?? 0) >= 256 }, String(describing: info()))
    // 顶栏品种名那块也只负责收起，不应穿透打开任何东西。
    let top = app.symbolLabel.frame
    app.buttons["interval.chart"].tap()
    XCTAssertTrue(app.staticTexts["panel.header"].waitForExistence(timeout: 5))
    app.windows.firstMatch.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: top.midX, dy: top.midY)).tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.staticTexts["panel.header"].exists })
    XCTAssertFalse(app.textFields["search.query"].exists)
    XCTAssertFalse(app.textFields["symbols.query"].exists)
    try testOutsideTapOnlyDismissesPanel()
    let original = try XCTUnwrap(info()["subs"] as? [String])
    let panes = try XCTUnwrap(info()["panes"] as? [[String: Any]])
    XCTAssertGreaterThanOrEqual(panes.count, 2)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    func center(_ pane: [String: Any]) -> XCUICoordinate {
      origin.withOffset(CGVector(dx: (info()["plotW"] as? Double ?? 300) / 2,
        dy: (pane["y"] as? Double ?? 0) + (pane["h"] as? Double ?? 80) / 2))
    }
    center(panes[0]).press(forDuration: 0.5, thenDragTo: center(panes[panes.count - 1]))
    XCTAssertTrue(wait(seconds: 5) { self.info()["subs"] as? [String] == Array(original.dropFirst()) + [original[0]] })
    shot("正式行情-整个副图区域长按换序")
    let moved = try XCTUnwrap(info()["panes"] as? [[String: Any]])
    center(moved[moved.count - 1]).press(forDuration: 0.5, thenDragTo: center(moved[0]))
    XCTAssertTrue(wait(seconds: 5) { self.info()["subs"] as? [String] == original })
    try testCrosshairCenterDragAndOutsidePan()
    XCTAssertTrue(app.openFavorites())
  }

  /// 交互规矩②：手指落到面板以外，第一下**只**收面板，不顺手落十字线。
  ///
  /// 竖屏现在只剩「图表设置」一张半屏（`interval.chart`，指标整段也在里头）：设置升成了
  /// 标签栏上的整页；周期「更多」从 `181a5bc` 起摊的是**内联**网格，不是 sheet
  /// （见 `MainScreenUITests.testMoreOpensPeriodPanel`）。这条用例原来把 `interval.more`
  /// 也按面板来等 `panel.header`，那一版之后就一直等不到，同一天没跟着改。
  /// 内联网格挪到下半段单测，按它自己的规矩验。
  func testOutsideTapOnlyDismissesPanel() throws {
    for entry in ["interval.chart"] {
      app.buttons[entry].tap()
      let header = app.staticTexts["panel.header"]
      XCTAssertTrue(header.waitForExistence(timeout: 5), "点了 " + entry + " 没开出面板")
      selectMain()
      XCTAssertTrue(wait(seconds: 5) { !header.exists }, "点了图，" + entry + " 那张面板没收起")
      XCTAssertEqual(info()["crosshair"] as? Bool, false, "首个外部点击只关闭面板：" + entry)
      selectMain()
      XCTAssertTrue(wait(seconds: 3) { self.info()["crosshair"] as? Bool == true })
      selectMain()
      XCTAssertTrue(wait(seconds: 3) { self.info()["crosshair"] as? Bool == false })
    }
    // 周期「更多」2026-09-23 起是盖在图上的一层弹层（网格 + 遮罩），遮罩上铺着同一层
    // `PanelDismissShield`，所以规矩②对它同样成立：点遮罩只收弹层，不落十字线。
    // 点的位置要避开从图上沿展开的网格（三行约 170pt），落在图的下半截遮罩上。
    app.buttons["interval.more"].tap()
    let row = app.buttons["period.row.1h"]
    XCTAssertTrue(row.waitForExistence(timeout: 5), "点「更多」没摊开周期网格")
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.8)).tap()
    XCTAssertTrue(wait(seconds: 5) { !row.exists }, "点了遮罩，周期网格没收起")
    XCTAssertEqual(info()["crosshair"] as? Bool, false, "点遮罩只收弹层，不许顺手落十字线")
    shot("面板外点击-只收起不触发十字线")
  }

  /// 副图开满，主图和副图仍然一起落在一屏可视区里，不用翻页。
  ///
  /// 「开满」是三个，不是四个：`Prefs.maxSubs` 从 `181a5bc`「交互定板落地」起卡死在 3
  /// （用户：「最多同时开三个副图……第四个进来就把最早开的那个换下去」），出厂默认
  /// 也正好是三个（`AICoinBehavior.subpanels` = 量 / 仓 / MACD）。这条用例写在那之前，
  /// 一直在等 `subs.count == 4`，那个数从此再也不可能出现。现在它验的是同一件事：
  /// 再开一个 RSI，最早那个被换下去、总数仍是三个，图整体高度还等于可视区高度
  /// （`height == viewportH` 就是「没有整页滚动」），新开的那格把手也点得到。
  func testThreeSubpanelsFitWithoutPageScroll() throws {
    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    let toggle = app.buttons["indicator.switch.RSI"]
    let scroll = app.scrollViews["panel.content"]
    for _ in 0..<5 {
      if toggle.exists, toggle.isHittable, scroll.frame.contains(toggle.frame) { break }
      scroll.swipeUp()
    }
    XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap(); closePanel()
    XCTAssertTrue(wait { (self.info()["subs"] as? [String])?.count == 3 },
                  "副图数不是三个：\(info()["subs"] ?? "?")")
    XCTAssertTrue(wait { (self.info()["subs"] as? [String])?.contains("RSI") == true },
                  "刚开的 RSI 没上图：\(info()["subs"] ?? "?")")
    XCTAssertEqual(try XCTUnwrap(info()["height"] as? Double), try XCTUnwrap(info()["viewportH"] as? Double), accuracy: 1)
    XCTAssertTrue(app.otherElements["chart.resize.RSI"].isHittable)
    shot("一屏三副图-无需滚动")
  }

  func testDataModesClearHeaderAndSelection() throws {
    app.buttons["interval.chart"].tap()
    app.buttons["顶部"].tap(); closePanel()
    selectMain()
    XCTAssertTrue(app.staticTexts["chart.topOHLC"].waitForExistence(timeout: 8))
    shot("顶部-历史OHLC")
    // 十字线开着时，周期条那一行让位给十字线操作行（上一根 / 下一根 / 按此价画线 / 看细节，
    // `2045efe`、`9f449e2` 起），「图表」钮不在手指够得着的地方——人要先在图上点一下收起十字线，
    // 周期条回来了才去开面板。这条用例写在那之前，一直在十字线开着时点「图表」。
    XCTAssertFalse(app.buttons["interval.chart"].isHittable, "十字线开着时周期条应让位给操作行")
    selectMain()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertTrue(wait(seconds: 5) { !self.app.staticTexts["chart.topOHLC"].exists }, "收起十字线后头部应回到实时")
    app.buttons["interval.chart"].tap()
    app.buttons["跟随K线"].tap(); closePanel()
    XCTAssertFalse(app.staticTexts["chart.topOHLC"].exists)
    selectMain()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == true })
    shot("跟随K线-单一容器")
    selectMain()
    XCTAssertTrue(wait { self.info()["crosshair"] as? Bool == false })
    XCTAssertFalse(app.staticTexts["chart.topOHLC"].exists)
    shot("关闭十字线-实时头部恢复")
  }

  func testMAParameterCancelAndSaveOutput() throws {
    let original = try XCTUnwrap(info()["ma"] as? [Int])
    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    // 手指还停在输入框里就按「取消」：一个参数都不许动（2026-09-20 加减改输入框后的验收 c）。
    let field = app.textFields["indicator.param.0.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("77")
    app.buttons["取消"].tap(); closePanel()
    XCTAssertEqual(info()["ma"] as? [Int], original)
    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    let output = app.switches["indicator.output.0"]
    XCTAssertTrue(output.waitForExistence(timeout: 5))
    XCTAssertEqual(output.value as? String, "1")
    // SwiftUI 把整行暴露成这个开关，真正认点击的只有右边那颗滑块（见 `flip`）。
    flip(output, to: "0")
    shot("MA草稿-输出已关闭")
    app.buttons["保存"].tap(); closePanel()
    XCTAssertTrue(wait { self.info()["hiddenMA"] as? [Int] == [0] })
    shot("MA输出关闭-曲线图例同步")
  }
  /// 均线周期能直接打字，也能加一条、删一条。
  ///
  /// 点进去原值就整段选上，直接打新的数就是换掉它（2026-09-20 起这一格没有加减了）；
  /// 手指还停在框里直接按「保存」，那一格也要算数。顺带把加减线时输出开关和颜色
  /// 跟着挪位的那段逻辑走一遍。
  func testMAPeriodsTypedAndAddRemove() throws {
    let original = try XCTUnwrap(info()["ma"] as? [Int])
    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()

    let field = app.textFields["indicator.param.0.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("34")

    let add = app.buttons["indicator.param.add"]
    XCTAssertTrue(add.waitForExistence(timeout: 5))
    add.tap()
    XCTAssertTrue(app.textFields["indicator.param.\(original.count).field"].waitForExistence(timeout: 5))

    app.buttons["保存"].tap(); closePanel()
    XCTAssertTrue(wait {
      guard let now = self.info()["ma"] as? [Int] else { return false }
      return now.count == original.count + 1 && now.first == 34
    })
    shot("均线周期-手输并加一条")

    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    let last = app.cells.containing(.textField,
                                    identifier: "indicator.param.\(original.count).field").firstMatch
    XCTAssertTrue(last.waitForExistence(timeout: 5))
    last.swipeLeft()
    let delete = app.buttons["Delete"].exists ? app.buttons["Delete"] : app.buttons["删除"]
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    app.buttons["保存"].tap(); closePanel()
    XCTAssertTrue(wait { (self.info()["ma"] as? [Int])?.count == original.count })
    shot("均线周期-删回原来的条数")
  }

  /// 参数格是输入框，不是加减：2026-09-20 用户说「ma 参数一律改成手动输入框，
  /// 不再搞那种加减，那个都没用，非必要这种加减的一律不要出现」。
  ///
  /// 这条守着改一个数的那四件事：点进去**原值全选**（所以打 169 得到的是 169，
  /// 不是接在 10 后面的 101）、打字途中**图不按中间值重算**、手指还在框里直接按
  /// 「保存」那一格也算数、按「取消」一个参数都不变；最后空着提交要回落到原值。
  func testParamFieldsReplaceSteppers() throws {
    let original = try XCTUnwrap(info()["ma"] as? [Int])
    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    let field = app.textFields["indicator.param.0.field"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertEqual(app.steppers.count, 0, "参数页上还有步进器")
    field.tap()
    field.typeText("1")
    XCTAssertEqual(info()["ma"] as? [Int], original, "打到一半图就按中间值重算了")
    field.typeText("69")
    XCTAssertEqual(info()["ma"] as? [Int], original, "还没保存图就变了")
    shot("均线参数-输入169还没保存")
    // 手指还停在框里，直接按「保存」：不用先点别处失焦。
    app.buttons["保存"].tap(); closePanel()
    XCTAssertTrue(wait { (self.info()["ma"] as? [Int])?.first == 169 },
                  "保存没把正在打的那格算进去：\(info()["ma"] ?? "?")")
    shot("均线参数-保存后第一条是169")
    let saved = try XCTUnwrap(info()["ma"] as? [Int])

    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap(); field.typeText("42")
    app.buttons["取消"].tap(); closePanel()
    XCTAssertEqual(info()["ma"] as? [Int], saved, "取消之后参数动了")

    app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
    app.buttons["indicator.edit.MA"].tap()
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(XCUIKeyboardKey.delete.rawValue)
    app.buttons["保存"].tap(); closePanel()
    XCTAssertEqual(info()["ma"] as? [Int], saved, "空着提交没回落到原值")
  }

  func testDeviceHistoricalPanPinchAndManualY() throws {
    let initial = info()
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    let start = origin.withOffset(CGVector(dx: 70, dy: 170))
    start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 180, dy: 0)))
    XCTAssertTrue(wait { (self.info()["to"] as? Double ?? .infinity) < (initial["to"] as? Double ?? 0) })
    // Wait for the finite fling to finish by observing a stable window.
    var previous = info()["to"] as? Double
    XCTAssertTrue(wait {
      let current = self.info()["to"] as? Double
      defer { previous = current }
      return current == previous
    })
    let history = info()
    canvas.pinch(withScale: 1.5, velocity: 1)
    XCTAssertTrue(wait { (self.info()["spacing"] as? Double ?? 0) > (history["spacing"] as? Double ?? 0) + 0.1 })
    XCTAssertLessThan(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(initial["to"] as? Double))
    shot("真机-历史横拖和双指缩放")
    let beforeY = info()
    let width = try XCTUnwrap(beforeY["plotW"] as? Double)
    let axis = origin.withOffset(CGVector(dx: width + 20, dy: 140))
    axis.press(forDuration: 0.05, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -85)))
    XCTAssertTrue(wait { abs((self.info()["zoomY"] as? Double ?? 1) - 1) > 0.05 })
    XCTAssertEqual(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(beforeY["to"] as? Double), accuracy: 0.001)
    let h = try XCTUnwrap(info()["mainH"] as? Double)
    origin.withOffset(CGVector(dx: width + 20, dy: h - 34)).tap()
    XCTAssertTrue(wait { self.info()["zoomY"] as? Double == 1 })
    XCTAssertEqual(try XCTUnwrap(info()["to"] as? Double), try XCTUnwrap(beforeY["to"] as? Double), accuracy: 0.001)
    shot("真机-A仅恢复自动Y")
  }

}

extension ChartFoundationUITests {
  /// 用户 2026-09-23 报的：「选了趋势线，把样式改成两端延伸保存，然后重画还是线段」。
  ///
  /// 样式表里换画法是他明确的选择：换一次就记住，之后面板上点「趋势线」落下来的就是
  /// 两端延伸（`DrawingPreferences.variants`）；杀掉 app 重开也还记得。
  /// 面板那一格的名字和标识不变，入口还是 `draw.tool.trend`。
  func testDrawingSwapIsRememberedForTheNextLine() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 5))
    app.buttons["draw.tool.trend"].tap()
    var origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    origin.withOffset(CGVector(dx: 240, dy: 160)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["trend"], "没换过画法，第一条该是线段")
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    XCTAssertTrue(app.buttons["draw.style"].waitForExistence(timeout: 5))
    app.buttons["draw.style"].tap()
    XCTAssertTrue(app.buttons["draw.save"].waitForExistence(timeout: 8))
    switchDrawKind(to: "两端延伸")
    shot("画线-样式表里画法一排选中两端延伸")
    app.buttons["draw.save"].tap()
    XCTAssertTrue(wait { self.info()["drawingKinds"] as? [String] == ["extended"] }, String(describing: info()))
    // 1e271ee 起选中栏左边是提醒胶囊，不再写线名（能挂提醒的线都是这样）；
    // 线名只剩样式表那排按钮上的字，界面上任何地方都不许再冒出旧名「直线」。
    XCTAssertTrue(app.buttons["alert.line"].waitForExistence(timeout: 5), "两端延伸选中后选中栏上该是提醒胶囊")
    XCTAssertFalse(app.staticTexts["直线"].exists, "界面上还叫「直线」")

    // 再从面板上点「趋势线」画一条：落下来的得是两端延伸，不是线段。
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 5))
    app.buttons["draw.tool.trend"].tap()
    origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 110, dy: 30)).tap()
    origin.withOffset(CGVector(dx: 250, dy: 55)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["extended", "extended"],
                   "换成两端延伸之后再画趋势线，第二条还是线段")
    // 画完不再弹「要不要加提醒」（1e271ee），刚落下的线是选中的，提醒在选中栏的胶囊上。
    XCTAssertTrue(app.buttons["alert.line"].waitForExistence(timeout: 5), "刚画完的两端延伸选中栏上没有提醒胶囊")
    shot("画线-换成两端延伸后再画仍是两端延伸")

    // 重开 app 还记得：这份记忆和样式一样落在画线存档的偏好里。
    app.buttons["draw.finish"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 }, String(describing: info()))
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 5))
    app.buttons["draw.tool.trend"].tap()
    origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 60, dy: 180)).tap()
    origin.withOffset(CGVector(dx: 200, dy: 215)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 3 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["extended", "extended", "extended"],
                   "重开 app 之后画法记忆丢了")
    shot("画线-重开后仍记得两端延伸")
  }

  /// 粗细是四条样张，点哪条是哪条，没有加减也没有输入框（2026-09-20）。
  func testDrawingWidthPresets() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 5))
    app.buttons["draw.tool.trend"].tap()
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    origin.withOffset(CGVector(dx: 240, dy: 160)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 }, String(describing: info()))
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    XCTAssertTrue(app.buttons["draw.style"].waitForExistence(timeout: 5))
    app.buttons["draw.style"].tap()
    XCTAssertTrue(app.buttons["draw.save"].waitForExistence(timeout: 8))
    let thick = app.buttons["draw.width.3"]
    // 样式面板起手是半屏，粗细那一行偶尔落在下沿以外：拖到整屏再点。
    if !thick.waitForExistence(timeout: 3) || !thick.isHittable {
      let bar = app.navigationBars.element(boundBy: 0)
      bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .press(forDuration: 0.1,
               thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
    }
    XCTAssertTrue(thick.waitForExistence(timeout: 5), app.debugDescription)
    XCTAssertEqual(app.steppers.count, 0, "画线样式面板上还有步进器")
    XCTAssertTrue(app.buttons["draw.width.1.5"].exists, "四档里少了 1.5pt")
    thick.tap()
    app.buttons["draw.save"].tap()
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    XCTAssertTrue(app.buttons["draw.style"].waitForExistence(timeout: 5))
    app.buttons["draw.style"].tap()
    XCTAssertTrue(app.buttons["draw.width.3"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.buttons["draw.width.3"].isSelected, "重开样式面板，3pt 那档没保持选中")
    shot("画线粗细-四档样张")
  }

  func testDrawingToolsAndPersistentStyles() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    XCTAssertTrue(app.buttons["draw.tool.trend"].waitForExistence(timeout: 5))
    shot("画线-工具格子")
    app.buttons["draw.tool.trend"].tap()
    var origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    origin.withOffset(CGVector(dx: 240, dy: 160)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["trend"])
    XCTAssertTrue(app.buttons["draw.undo"].isEnabled)
    app.buttons["draw.undo"].tap(); XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 0 })
    app.buttons["draw.redo"].tap(); XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 })
    // Undo removes selection; tap the actual line after redo.
    origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 80, dy: 100)).tap()
    XCTAssertTrue(app.buttons["draw.style"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.openDrawingStyleSheet(pick: "#4A90E2"), "样式面板里点不到蓝色")
    // 「换一种画法」：面板上只摆十二把，射线活在线段这一族的这一行里
    // （`Drawing.Kind.swaps`）。换完点数不变，所以这条线原地变成射线、id 也不换。
    switchDrawKind(to: "向右延伸")
    // 锁定只在样式表里（「锁定位置」那一行，2026-09-23 选中栏撤掉了「⋯」）。
    // `switchDrawKind` 已经把表拖成整屏，这一行就在「画法」上面。
    let lock = app.switches["锁定位置"]
    XCTAssertTrue(lock.waitForExistence(timeout: 5), "样式表里没有「锁定位置」")
    flip(lock, to: "1")
    app.buttons["draw.save"].tap()
    XCTAssertTrue(wait { self.info()["drawingColors"] as? [String] == ["#4A90E2"] })
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["ray"], "换画法没生效，或者被 isValid 挡掉了")
    XCTAssertTrue(wait { self.info()["drawingLocked"] as? [Bool] == [true] })
    let ids = try XCTUnwrap(info()["drawingIDs"] as? [String])
    shot("画线-换成射线并锁定")
    app.buttons["draw.finish"].tap()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids }, String(describing: info()))
    XCTAssertEqual(info()["drawingColors"] as? [String], ["#4A90E2"])
    XCTAssertEqual(info()["drawingLocked"] as? [Bool], [true])
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    XCTAssertTrue(app.openDrawList(), "「更多」里开不出画线列表")
    XCTAssertTrue(app.buttons["draw.object.\(ids[0])"].waitForExistence(timeout: 5))
    shot("画线-重启恢复对象")
    app.buttons["隐藏画线"].tap()
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: 50)).tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
    XCTAssertEqual(info()["crosshair"] as? Bool, false)
    XCTAssertTrue(wait { self.info()["drawingHidden"] as? [Bool] == [true] })
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(seconds: 5) { self.canvas.frame.width > self.canvas.frame.height && self.app.buttons["draw.tools"].isHittable })
    // 横屏的「绘图」面板不是半屏表单，是贴着左边推出来的一块卡片（`drawToolsLayer`），
    // 但里头的格子和关闭按钮跟竖屏是同一个视图，标识符也一样。
    // 2026-09-22 之后这张面板只剩标题、十二格和关闭——搜索框与分类标签都去掉了。
    openDrawTools()
    XCTAssertEqual(app.textFields["draw.tools.search"].exists, false, "「绘图」面板上还留着搜索框")
    // 末格是「持仓」，横屏那块卡片一屏放不下十二格，拿它验「翻得下去、翻到底点得着」。
    for _ in 0..<8 {
      if app.buttons["draw.tool.position"].exists && app.buttons["draw.tool.position"].isHittable { break }
      let list = app.scrollViews.containing(.button, identifier: "draw.tool.trend").firstMatch
      list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
        thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)),
        withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    XCTAssertTrue(app.buttons["draw.tool.position"].isHittable)
    app.buttons["draw.sheet.done"].tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists && self.app.buttons["draw.tools"].isHittable })
    let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscapeShot.name = "画线-横屏工具栏"; landscapeShot.lifetime = .keepAlways; add(landscapeShot)
    XCUIDevice.shared.orientation = .portrait
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingHidden"] as? [Bool] == [true] })
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    XCTAssertTrue(app.openDrawList(), "「更多」里开不出画线列表")
    app.buttons["draw.object.\(ids[0])"].tap()
    XCTAssertTrue(app.buttons["draw.copy"].waitForExistence(timeout: 5), "选中栏上没有「复制」")
    app.buttons["draw.copy"].tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 })
    app.buttons["draw.delete"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    app.buttons["draw.undo"].tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 2 })
    app.buttons["draw.redo"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-只删除选中对象并可撤销")
    // 吸附与连续画 2026-09-23 起收在「更多」弹层里：删掉的那条已经没了选中，「更多」该回到位。
    XCTAssertTrue(app.openDrawMore(), "取消选中之后开不出「更多」")
    app.buttons["draw.magnet.quick"].tap()
    app.buttons["draw.continuous.quick"].tap()
    app.closeDrawMore()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    XCTAssertEqual(info()["drawingMagnet"] as? Bool, false)
    XCTAssertEqual(info()["drawingContinuous"] as? Bool, true)
  }

  func testIndicatorColorSaveCancelAndRestart() throws {
    func edit(_ id: String, color: String, save: Bool) {
      app.buttons["interval.chart"].tap(); XCTAssertTrue(app.openIndicatorPage())
      if !app.buttons["indicator.edit.\(id)"].exists { app.buttons["indicator.switch.\(id)"].tap() }
      app.buttons["indicator.edit.\(id)"].tap()
      let swatch = app.buttons["indicator.color.0.\(color)"].firstMatch
      for _ in 0..<5 { if swatch.isHittable { break }; app.swipeUp() }
      XCTAssertTrue(swatch.isHittable); swatch.tap()
      shot("\(id)-独立颜色编辑")
      app.buttons[save ? "保存" : "取消"].tap(); closePanel()
    }
    let original = info()["maColor0"] as? String
    edit("MA", color: "#4A90E2", save: false)
    XCTAssertEqual(info()["maColor0"] as? String, original)
    edit("MA", color: "#4A90E2", save: true)
    XCTAssertTrue(wait { self.info()["maColor0"] as? String == "#4A90E2" })
    edit("EMA", color: "#37A78F", save: true)
    XCTAssertEqual(info()["maColor0"] as? String, "#4A90E2")
    XCTAssertEqual(info()["emaColor0"] as? String, "#37A78F")
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["maColor0"] as? String == "#4A90E2" })
    XCTAssertEqual(info()["emaColor0"] as? String, "#37A78F")
    shot("均线颜色-重启恢复")
  }
}

extension ChartFoundationUITests {
  func testDrawingAllToolsAndFingerTargets() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    XCTAssertTrue(app.openDrawMore(), "画线栏上开不出「更多」")
    app.buttons["draw.magnet.quick"].tap()
    app.closeDrawMore()
    // 「绘图」面板上摆出来的就是这十二把（`Drawing.Kind.palette`）。2026-09-22 砍掉
    // 分类标签之后，面板是一张铺平的格子，进去就能看见，不用先点标签。
    // 第二项是这把工具要在图上点几下（`Drawing.Kind.placeCount`）。
    //
    // 打头的必须是两点的线段：下面 `index == 0` 那一段要拖第一条线的端点，验「手指偏离
    // 可见把手 17pt 仍然只拖最近的那一端」。单点工具（水平线、标注）没有第二个端点可比，
    // 所以这里的顺序不照面板从左到右，把 `trend` 提到最前面。
    let tools: [(String, Int)] = [("trend", 2), ("hline", 1), ("vline", 1), ("channel", 3),
      ("fibonacci", 2), ("fibExtension", 3), ("measure", 2), ("note", 1),
      ("anchoredVWAP", 1), ("fixedVolumeProfile", 2), ("anchoredVolumeProfile", 1), ("position", 3)]
    // 十二趟下来图区高度必须是同一个数：「要不要加提醒」那一句现在占头部价格行的位置，
    // 它在与不在都不该让图缩一下（2026-09-21）。第一趟量到的就是基准。
    var baseH: Double?
    for (index, tool) in tools.enumerated() {
      openDrawTools()
      let target = app.buttons["draw.tool.\(tool.0)"]
      // 滚动必须**限定在工具面板自己的格子区里**。早先用的是 `app.collectionViews.firstMatch`：
      // 它取的是整棵树里第一个集合视图，不保证是这张面板——一旦落到主界面上，这十四次
      // 拖动就变成了在行情页上乱划，整条用例会跑飞（真出过：最后停在自选页，
      // `chart.canvas` 直接不存在了）。现在面板是 `ScrollView` + `LazyVGrid`，
      // 用「含有这把工具的那个滚动视图」把它钉死。
      let list = app.scrollViews.containing(.button, identifier: "draw.tool.\(tool.0)").firstMatch
      XCTAssertTrue(list.waitForExistence(timeout: 5), "没找到画线工具面板的格子区")
      for _ in 0..<14 {
        if target.exists && target.isHittable { break }
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
          thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
          withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      XCTAssertTrue(target.isHittable, tool.0); target.tap()
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
      // 下面每一下都是点在画布上的。面板收了但图不在（被别的页盖住），
      // 再点下去就是往别人身上点——先把图还在这件事断言死，失败信息也才看得懂。
      XCTAssertTrue(canvas.waitForExistence(timeout: 5), "\(tool.0)：工具面板收起后图不见了")
      // 上一把工具画完时问的那一句可能还挂在头部（方案 2.3，六秒自己走）。它在与不在
      // 图区都是同一个高度——这正是这一趟要盯的事，所以**不先收掉它**，直接量，
      // 量到的必须和第一趟一模一样。
      let h = try XCTUnwrap(info()["mainH"] as? Double)
      if let baseH {
        XCTAssertEqual(h, baseH, accuracy: 0.5,
                       "\(tool.0)：图区高度变了（\(baseH) → \(h)），那句问话又在图外占行了")
      } else { baseH = h }
      let origin = canvas.coordinate(withNormalizedOffset: .zero)
      let points = [CGVector(dx: 90, dy: h * 0.65), CGVector(dx: 245, dy: h * 0.3), CGVector(dx: 160, dy: h * 0.75)]
      for point in points.prefix(tool.1) { origin.withOffset(point).tap() }
      XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == index + 1 }, tool.0)
      XCTAssertEqual((info()["drawingKinds"] as? [String])?.last, tool.0)
      // 空的「文字标注」一落点就自己把样式表开出来（`DrawingController` 那句
      // `panel = .style`），省掉「发现没字再去找样式」。下一趟要点面板，先把它收掉。
      if tool.0 == "note" {
        // 样式表的出口是导航栏上的「取消 / 保存」，不是工具面板那颗 `draw.sheet.done`。
        let save = app.buttons["draw.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "落下一条空文字标注，样式表没自己开出来")
        app.buttons["取消"].tap()
        XCTAssertTrue(wait(seconds: 5) { !save.exists }, "样式表收不掉")
      }
      if index == 0 {
        // 画完什么都不弹（2026-09-23 起提醒只在选中栏的胶囊上开），图区一个 pt 都不该动：
        // 选中栏和平时那排工具是同一行，换上来也不改高度。
        XCTAssertFalse(app.otherElements["alert.prompt"].waitForExistence(timeout: 2), "画完线又弹了一句问话")
        XCTAssertEqual(try XCTUnwrap(info()["mainH"] as? Double), h, accuracy: 0.5,
                       "选中栏换上来之后图区高度变了")
        let before = try XCTUnwrap(info()["drawingAnchors"] as? [[[String: Double]]])
        origin.withOffset(CGVector(dx: 90, dy: h * 0.65 + 17)).press(forDuration: 0.1,
          thenDragTo: origin.withOffset(CGVector(dx: 115, dy: h * 0.65 + 42)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait { (self.info()["drawingAnchors"] as? [[[String: Double]]]) != before })
        let after = try XCTUnwrap(info()["drawingAnchors"] as? [[[String: Double]]])
        XCTAssertEqual(after[0][1], before[0][1], "手指偏离可见把手 17pt 仍应只拖动最近端点")
        app.buttons["draw.undo"].tap()
        XCTAssertTrue(wait { (self.info()["drawingAnchors"] as? [[[String: Double]]]) == before })
      }
    }
    let ids = try XCTUnwrap(info()["drawingIDs"] as? [String])
    app.buttons["draw.finish"].tap()
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    // 「清空全部画线」2026-09-23 起在「更多」弹层的最底下，点了还要确认一次。
    XCTAssertTrue(app.openDrawMore(), "画线栏上开不出「更多」")
    let clear = app.buttons["draw.clear"]
    XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
    let confirm = app.buttons["清空画线"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), "清空之前没有确认")
    confirm.tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 0 })
    app.buttons["draw.undo"].tap()
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-十二把工具与手指端点拖动")
  }

  /// 三把多点工具画完之后跨周期、重启都还在。
  ///
  /// 原来打头的是矩形，2026-09-22 用户点名把它从面板上去掉了（「去掉矩形吧」），
  /// 这里换成斐波那契扩展——同样是三点，而且是那一轮新摆上面板的。
  func testDrawingChannelFibonacciAndExtension() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    // 「绘图」面板（`DrawingToolPicker`）2026-09-22 起是一张铺平的十二格，没有分类标签，
    // 每把工具进去就在树里，只可能需要往下翻一屏。
    for (index, entry) in [("channel", 3), ("fibonacci", 2),
                           ("fibExtension", 3)].enumerated() {
      openDrawTools()
      let target = app.buttons["draw.tool.\(entry.0)"]
      // 翻格子只能翻面板自己那个 ScrollView，不能翻整个 app——理由同
      // `testDrawingAllToolsAndFingerTargets` 里那段注释：划到行情页上会把整条用例带飞。
      let list = app.scrollViews.containing(.button, identifier: "draw.tool.\(entry.0)").firstMatch
      XCTAssertTrue(list.waitForExistence(timeout: 5), "没找到画线工具面板的格子区")
      for _ in 0..<8 {
        if target.exists && target.isHittable { break }
        list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
          thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
          withVelocity: .slow, thenHoldForDuration: 0.1)
      }
      XCTAssertTrue(target.isHittable, entry.0); target.tap()
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
      let h = try XCTUnwrap(info()["mainH"] as? Double)
      let origin = canvas.coordinate(withNormalizedOffset: .zero)
      let points = [CGVector(dx: 90, dy: h * 0.7), CGVector(dx: 245, dy: h * 0.25), CGVector(dx: 160, dy: h * 0.65)]
      for point in points.prefix(entry.1) { origin.withOffset(point).tap() }
      XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == index + 1 }, String(describing: info()))
      XCTAssertEqual((info()["drawingKinds"] as? [String])?.last, entry.0)
      shot("画线-\(entry.0)")
    }
    let ids = info()["drawingIDs"] as? [String]
    app.buttons["draw.finish"].tap()
    app.tapIntervalChip("4h")
    XCTAssertTrue(wait { self.info()["interval"] as? String == "4h" })
    XCTAssertEqual(info()["drawingIDs"] as? [String], ids)
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    XCTAssertTrue(wait { self.info()["drawingIDs"] as? [String] == ids })
    shot("画线-多工具跨周期与重启")
  }

  /// 画线工作台里点品种名：出来的是「常看」那两列，键盘**不许**自己弹出来。
  ///
  /// 用户 2026-09-18 报的：「都还没点搜索框键盘就弹出来了」。这一层的主体是底下那格
  /// 「常看」，横屏里键盘一上来就盖掉小半块屏，用户要的那几个常看品种反而看不见。
  /// 真要打字的人点一下搜索框，键盘照常上来——这一条两头都要验。
  func testDrawingSymbolSwitcherKeepsKeyboardDown() throws {
    XCTAssertTrue(app.tapDrawEntry(), "没能进入画线")
    let symbol = app.buttons[Ids.landscapeSymbol]
    XCTAssertTrue(symbol.waitForExistence(timeout: 20), "横屏标题上没有品种名")
    symbol.tap()
    // 搜索框只在这一层里有，拿它当「这一层开着没有」的凭据。
    let field = app.textFields["draw.symbol.search"]
    XCTAssertTrue(field.waitForExistence(timeout: 8), "换品种那一层没出来")
    XCTAssertFalse(app.keyboards.element.waitForExistence(timeout: 3), "还没点搜索框，键盘就自己弹出来了")
    let list = app.scrollViews["draw.symbol.list"]
    XCTAssertTrue(list.waitForExistence(timeout: 5), "没找到品种列表")
    let tall = list.frame.height
    field.tap()
    let keyboard = app.keyboards.element
    XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "点了搜索框，键盘却没上来")
    // 键盘起来之后列表要自己缩到键盘上沿以内：横屏的键盘是半块屏，不缩的话
    // 用户看着一列结果却只点得到最上面一行（用户：「弹出来的键盘是不是占比太大了」）。
    XCTAssertTrue(wait { list.frame.height < tall - 40 },
                  "键盘起来了列表却没缩：\(tall) → \(list.frame.height)")
    let window = app.windows.firstMatch.frame
    let reported = keyboard.frame
    let top = try XCTUnwrap(keyboardTopEdge(reported: reported, window: window),
                            "键盘报回来的框既不是正着的也不是转过 90° 的：键盘 \(reported)，窗口 \(window)")
    // 绿的时候断言里的数看不见，所以把这组几何单独落一行进日志：
    // 要证明的是「16 Pro 上确实走了转过 90° 那一支、算出来 240」，不能只看它绿。
    let branch = reported.width > reported.height ? "正着报" : "转过 90°"
    let measured = "KB-GEOMETRY 分支=\(branch) 键盘=\(reported) 窗口=\(window) 键盘上沿=\(top) 列表底边=\(list.frame.maxY)"
    print(measured)
    XCTContext.runActivity(named: measured) { _ in }
    XCTAssertLessThanOrEqual(list.frame.maxY, top + 1,
                             "列表底边压在键盘底下了：列表 \(list.frame.maxY)，键盘上沿 \(top)"
                             + "（键盘报的框 \(reported)，窗口 \(window)）")
    shot("画线-换品种-键盘")
  }
}

extension ChartFoundationUITests {
  func testCompactChartStylesAndRotation() throws {
    XCTAssertFalse(app.buttons["bottom.style"].exists)
    XCTAssertFalse(app.buttons["bottom.landscape"].exists)
    XCTAssertFalse(app.buttons["chart.expand"].exists)
    shot("手机-简化入口")
    // 这儿原来挨个点四张风格卡再重启验持久化。风格表收成 AICoin 一套之后（见
    // `CandleStyle`）卡撤了，改用同一张面板上的「阳线」实心 / 空心走同一条路：
    // 改一下、收面板、杀进程重开，看它还在不在。
    app.buttons["interval.chart"].tap()
    XCTAssertTrue(app.openChartMorePage(), "图表设置里没有「更多设置」")
    let body = app.buttons["chart.bodyChoice.空心"]
    XCTAssertTrue(body.waitForExistence(timeout: 5), "图表面板没开出来")
    XCTAssertFalse(app.buttons["style.card.aicoin"].exists, "风格卡还在")
    body.tap()
    shot("手机-图表阳线实心空心")
    closePanel()
    app.terminate(); app.launch()
    XCTAssertTrue(canvas.waitForExistence(timeout: 30))
    app.buttons["interval.chart"].tap()
    XCTAssertTrue(app.openChartMorePage())
    XCTAssertTrue(wait { self.app.buttons["chart.bodyChoice.空心"].isSelected },
                  "重启之后阳线画法没留住")
    app.buttons["chart.bodyChoice.实心"].tap()
    closePanel()
    // 用户拿起手机旋转，不需要先点按钮。
    XCUIDevice.shared.orientation = .landscapeLeft
    XCTAssertTrue(wait(seconds: 8) { self.canvas.frame.width > self.canvas.frame.height })
    XCTAssertFalse(app.buttons["chart.expand"].isHittable)
    if UIDevice.current.userInterfaceIdiom == .pad {
      // iPad 横过来还是同一张常规宽度的页，不进画线工作台（`MainScreen.enterLandscape`
      // 在 iPad 上走的是 `expandedChart`，不是转屏），所以这儿没有横屏工具栏也没有「竖屏」。
      // 出口该在的地方是画线：那条路由 `AICoinBaseUITests` 守着。
      XCTAssertFalse(app.buttons["land.exit"].exists, "iPad 转个屏就进了横屏工作台")
      XCTAssertTrue(app.buttons["bottom.settings"].isHittable, "iPad 横过来底栏没了")
    } else {
      // 横屏工具栏常驻一颗「竖屏」。以前这儿断言它**不存在**，理由是「手机转回去就行了」——
      // 可锁了方向的手机转不回去，进了横屏就只能杀进程，横屏成了单程票（见 `LandscapeChrome`）。
      XCTAssertTrue(app.buttons["land.exit"].waitForExistence(timeout: 5), "横屏没有回竖屏的出口")
      // 手动横过来再开画线：画线进行中侧栏整条收起（「画线 / 竖屏」和「完成」重复），
      // 点「完成」之后留在横屏、侧栏回来——出口不能跟着一起丢。
      app.buttons["land.draw"].tap()
      XCTAssertTrue(app.buttons["draw.finish"].waitForExistence(timeout: 10), "侧栏的「画线」没进画线态")
      XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["land.exit"].exists }, "画线进行中侧栏还在")
      app.buttons["draw.finish"].tap()
      XCTAssertTrue(app.buttons["land.exit"].waitForExistence(timeout: 10), "画完之后横屏侧栏没回来")
      XCTAssertTrue(canvas.frame.width > canvas.frame.height, "手动横屏的画线，完成后不该自己转回竖屏")
    }
    let landscapeShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    landscapeShot.name = "手机-自动横屏"; landscapeShot.lifetime = .keepAlways; add(landscapeShot)
    XCUIDevice.shared.orientation = .portrait
    XCTAssertTrue(wait(seconds: 8) { self.canvas.frame.width < self.canvas.frame.height && self.app.buttons["interval.chart"].isHittable })
    // 手机转一圈回来，刚选的阳线画法还在。
    app.buttons["interval.chart"].tap()
    XCTAssertTrue(app.openChartMorePage())
    XCTAssertTrue(wait { self.app.buttons["chart.bodyChoice.实心"].isSelected }, "转一圈回来阳线画法丢了")
    closePanel()
  }
}

extension ChartFoundationUITests {
  /// 「区间成交量分布」：点两下就该出柱子，而且立刻是选中态（2026-09-20）。
  ///
  /// 这三把计算型工具和别的画线最大的不同，是它们的形状要拿 K 线算出来——真机上
  /// 一旦拿不到序列，图上只会留两个光秃秃的手柄。所以这条用例盯的不是像素，
  /// 而是「工具在面板里找得到、两下落得成、落完就能改样式」这条完整的路。
  func testDrawingFixedVolumeProfilePlacement() throws {
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")
    openDrawTools()
    let target = app.buttons["draw.tool.fixedVolumeProfile"]
    // 翻格子只翻面板自己那个 ScrollView（理由见 `testDrawingAllToolsAndFingerTargets`）。
    let list = app.scrollViews.containing(.button, identifier: "draw.tool.measure").firstMatch
    XCTAssertTrue(list.waitForExistence(timeout: 5), "没找到画线工具面板的格子区")
    for _ in 0..<8 {
      if target.exists && target.isHittable { break }
      list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.05,
        thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
        withVelocity: .slow, thenHoldForDuration: 0.1)
    }
    XCTAssertTrue(target.isHittable, "「测量」这一类里找不到区间成交量分布")
    shot("画线-测量类里的成交量分布")
    target.tap()
    XCTAssertTrue(wait(seconds: 5) { !self.app.buttons["draw.sheet.done"].exists })
    XCTAssertTrue(canvas.waitForExistence(timeout: 5), "工具面板收起后图不见了")

    let h = try XCTUnwrap(info()["mainH"] as? Double)
    let origin = canvas.coordinate(withNormalizedOffset: .zero)
    origin.withOffset(CGVector(dx: 100, dy: h * 0.65)).tap()
    XCTAssertEqual(info()["drawingCount"] as? Int, 0, "两点工具点一下不该成线")
    origin.withOffset(CGVector(dx: 260, dy: h * 0.35)).tap()
    XCTAssertTrue(wait { self.info()["drawingCount"] as? Int == 1 }, String(describing: info()))
    XCTAssertEqual(info()["drawingKinds"] as? [String], ["fixedVolumeProfile"])
    // 落完即选中：选中条真的出来了、上面写的是这把工具的名字、「样式」够得着，
    // 这把工具才算真的接上了后面那套编辑（`draw.save` 是样式面板里的保存，不在这条条上）。
    let bar = app.otherElements["draw.selection"]
    XCTAssertTrue(bar.waitForExistence(timeout: 5), "画完没有出现选中条")
    XCTAssertTrue(bar.staticTexts["区间成交量分布"].exists, "选中条上写的不是这把工具的名字")
    XCTAssertTrue(app.buttons["draw.style"].isHittable, "选中条上的「样式」点不到")
    shot("画线-区间成交量分布")
  }
}

/// 把 XCUITest 报回来的键盘框，换算成「这块屏幕上键盘的上沿」。
///
/// 为什么不能直接用 `keyboard.frame.minY`：iOS 把键盘放在另一个窗口里
/// （`UIRemoteKeyboardWindow`），而那个窗口跟的是**设备原生的竖屏坐标系**。
/// 画线工作台的横屏是点「画线」时用 `requestGeometryUpdate` 强行转出来的（见
/// `OrientationBridge`），模拟器/手机本身还竖着；键盘窗口赶不上这次旋转时，
/// 无障碍那边读到的整块键盘子树就是转过 90°、连位置一起落到屏幕外的。
/// 2026-09-21 的兼容性矩阵在 iPhone 16 Pro / iOS 26.5 上就撞到一次（只那一台红，
/// iPhone 15 / Air / 17e 同一版本全绿）：xcresult 里的无障碍树写着窗口
/// `Window (Main) {{0,0},{874,402}}`（横屏，对的）、列表 `draw.symbol.list {{122,96.7},{236,92}}`
/// （已经按设计缩到 92pt，底边 188.67），键盘却报 `Keyboard {{-162,0},{162,874}}`
/// ——长宽对调、整块落在屏幕外。拿这种框的 `minY`(=0) 当键盘上沿，
/// 量到的是屏幕最顶上，屏上任何东西都会被判成「压在键盘底下」。
/// 换算回来：真正的键盘上沿是 402-162=240，列表底边 188.67 实际在它上方 51pt，
/// 产品行为本来就是对的——错的是这条用例量键盘的方式。
///
/// **别拿「宽是不是等于窗宽」当锚**：横屏 iPhone 上键盘左右会各让开一段，铺不满整幅宽。
/// iPhone 15 实测是窗口 (0,0,852,393)、键盘 (75,229,702,162)，两边各空 75pt。
/// 站得住的不变量是另一条：**键盘永远是一条长轴水平的带**。于是
///
/// - 宽 > 高 → 报的是正着的，上沿就是它的 `minY`（iPhone 15 横屏 229；竖屏 393×291 同理）；
/// - 高 > 宽 → 报的是转过 90° 的，带的厚度是它的**宽**，上沿 = 窗口下沿 − 宽
///   （iPhone 16 Pro：402−162=240）。这一支再留一道保险：长边应当正好是窗宽，
///   对不上就返回 nil，宁可让用例报「量不出来」，也不瞎给一个数。
///
/// 转过 90° 那一支还原的是「键盘正贴着窗口下沿」的理想位置（402−162=240），
/// 比同一台机器正常报出来的 238 宽 2pt——那条回退路只在框已经报坏时才走，2pt 的余量
/// 不影响任何结论。注意这整件事不是把断言放松：列表要是真的探到了键盘下面，照样红。
func keyboardTopEdge(reported: CGRect, window: CGRect) -> CGFloat? {
  if reported.width > reported.height { return reported.minY }
  if abs(reported.height - window.width) <= 2 { return window.maxY - reported.width }
  return nil
}
