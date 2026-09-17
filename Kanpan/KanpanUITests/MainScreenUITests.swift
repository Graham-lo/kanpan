import XCTest

// ============================================================ A8.4 主界面可达性
//
// 任务书 §13 A8.4：「8 机型 UI 测试全绿（同一套用例）」。
// 这一套测的**不是像素**（那是 M3 的 176 张基线干的活），而是 §9.1 的可达性：
// 每一个该点的地方点得到、点了有反应、反应完还能退回去。
//
// 每条用例都把自己改过的状态改回来（风格、周期、自选），所以跑的顺序无所谓，
// 也可以在同一台机器上连跑两遍。

@MainActor
final class MainScreenUITests: KanpanUICase {

  // ---------------------------------------------------------------- 顶栏

  /// 左上角的品种名只报「我正在看哪个」，点它不该弹出任何东西。
  ///
  /// 它以前开一张半屏弹层（头两行是搜索和完整自选，下面列自选）。搜索页做出来
  /// 之后那一层就是重复入口，用户 2026-09-18 让把它撤掉：换品种走放大镜，
  /// 浏览走底栏的自选，左上角回到纯展示。
  func testSymbolNameIsNotATrigger() {
    let label = app.symbolLabel
    expectExists(label, Self.short, "左上角没有品种名")
    app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: label.frame.midX, dy: label.frame.midY)).tap()
    expectGone(app.textFields[Ids.searchQuery], Self.short, "点品种名还是弹出了换品种的层")
    expectExists(app.buttons[Ids.searchButton], Self.short, "点完还应停在主界面")
  }

  /// 顶栏放大镜 → 品种搜索页，且落在搜索框上。换品种只有这一条路。
  ///
  /// 这一页的出口是输入框右边那颗「取消」，不是页头的返回箭头——手指在键盘上，
  /// 出口就该在同一条横线上（返回箭头是品种整页的，那一页才有页头）。
  func testSearchEntryOpensSymbolPage() {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页的输入框")
    app.buttons["search.cancel"].tap()
    expectGone(app.textFields[Ids.searchQuery], Self.short, "搜索页取消没关掉")
  }

  /// 顶栏右上角只剩放大镜一颗。自选星 2026-09-18 撤了——加自选统一在搜索页和
  /// 自选页的品种行上做，顶栏那一颗既重复又紧贴品种名，最容易误触。
  func testTopBarHasOnlySearch() {
    expectExists(app.buttons[Ids.searchButton])
    XCTAssertFalse(app.buttons["top.star"].exists, "顶栏还留着自选星")
  }

  // ---------------------------------------------------------------- 周期条

  /// 常用行铺出来的那几档挨个点一遍，选中态跟着走：点谁谁 selected，其余都不 selected。
  func testIntervalChipsSelectOneAtATime() {
    let chips = Ids.quickIntervals.map { app.buttons[Ids.intervalChip($0)] }
    for (raw, chip) in zip(Ids.quickIntervals, chips) {
      expectExists(chip, Self.short, "常用行里没有 \(raw) 这一档")
    }
    let original = Ids.quickIntervals.first { app.buttons[Ids.intervalChip($0)].isSelected }

    for raw in Ids.quickIntervals {
      let chip = app.buttons[Ids.intervalChip(raw)]
      // 走 `tapButton` 而不是裸 `tap()`：`market.interval` 是同步赋值的，点到了就该
      // 立刻选中；iPad mini 上实测出现过「点了 1m，等满 30s 也不选中」，和顶栏搜索
      // 那颗一样是正中心那一点吃掉了——退到框内 1/3 处再点就中。
      XCTAssertTrue(tapButton(chip) { chip.isSelected },
                    "点了 \(raw)，它自己没变成选中")
      for other in Ids.quickIntervals where other != raw {
        XCTAssertFalse(app.buttons[Ids.intervalChip(other)].isSelected,
                       "选了 \(raw)，\(other) 还亮着——同一时刻只能有一档选中")
      }
    }
    if let original { app.buttons[Ids.intervalChip(original)].tap() }
  }

  /// 周期条右端「更多」→ **内联**周期网格（十四档都在、每格带图钉）→ 再点一下收起。
  ///
  /// 原来这是一张半屏 sheet，收起走 `dismissSheet`（拖面板 / 点「完成」）。网格改成
  /// 内联展开之后（§2C4）既没有 `panel.done` 也没有 `panel.header`，那条路整条不适用；
  /// 现在「更多」自己就是开关，点第二下收起。`period.row.*` / `period.pin.*` 两个 id
  /// 原样挪到了格子上，所以这条用例验的还是同一件事。
  func testMoreOpensPeriodPanel() {
    app.buttons[Ids.intervalMore].tap()
    let row = app.buttons[Ids.periodRow("1h")]
    expectExists(row, Self.short, "点「更多」没摊开周期网格")
    expectExists(app.buttons[Ids.periodRow("1M")], Self.short, "周期网格里没有冷门档（1M）")
    expectExists(app.buttons[Ids.periodPin("1M")], Self.short, "周期网格的格子上没有图钉")
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !row.exists }, "再点一下「更多」，网格没收起来")
  }

  // ---------------------------------------------------------------- 底栏三个面板

  /// 「图表」面板：开得出来、改得动、收得回去。
  ///
  /// 这条原来验的是那张四选一的「K 线风格」卡。风格表收成 AICoin 一套之后（见
  /// `CandleStyle`）卡撤了，改用同一张面板上的「阳线」实心 / 空心来验同一件事：
  /// 它是多项配置页里的一行，所以选完**不**自动收（规矩①：单选面板即选即收，
  /// 配置页不连着关）——这页上还有网格、画法、价格轴要一起调，收掉反而碍事。
  /// 选完调回「实心」，不给下一条用例留状态。
  func testChartPanelTogglesCandleBody() {
    app.buttons[Ids.intervalChart].tap()
    let solid = app.buttons[Ids.chartBody("实心")], hollow = app.buttons[Ids.chartBody("空心")]
    expectExists(hollow, Self.short, "点周期行「图表」没开出图表面板")
    hollow.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { hollow.isSelected }, "选了「空心」它自己没变成选中")
    XCTAssertFalse(solid.isSelected, "同一时刻只能有一档选中")
    XCTAssertTrue(hollow.exists, "配置页不该选一下就自己收起")

    solid.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { solid.isSelected }, "调不回「实心」")
    dismissSheet(until: hollow)
  }

  /// 指标：开得出来、收得回去。多项配置页，选完**不**自动收（规矩①的另一半）。
  ///
  /// 2026-09-18 起指标不再是底栏上单独的一格，整段并进了「图表设置」面板
  /// （用户：「行情页面的指标放到图表里作为一个子栏目」），入口是周期行右端的「图表」。
  func testIndicatorPanelOpensAndCloses() {
    app.buttons[Ids.intervalChart].tap()
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    expectExists(macd, Self.short, "点周期行「图表」没开出指标那几栏")
    expectExists(app.buttons[Ids.indicatorSwitch("MA")], Self.short, "指标那几栏里没有主图叠加")
    dismissSheet(until: macd)
  }

  /// 设置页：进得去、出得来。
  ///
  /// 2026-09-18 起设置是标签栏上的一整页，不是半屏面板（用户：「这四个底部拦都单独是
  /// 一个页面」），所以出来靠切回「图表」那一格，不是拖或者点「完成」。
  func testSettingsPanelOpensAndCloses() {
    app.buttons[Ids.bottomSettings].tap()
    let magnet = app.buttons[Ids.settingsMagnet]
    expectExists(magnet, Self.short, "点底栏「设置」没进设置页")
    XCTAssertFalse(app.buttons[Ids.panelDone].exists, "整页不该有半屏那颗「完成」")
    leaveSettings()
    expectGone(magnet, Self.short, "切回「图表」之后还停在设置页")
  }

  /// 交互规矩②：手指落到面板以外（这里点的是 K 线图）面板就收起。
  ///
  /// 要先等图真的有数据——没数据时 `ChartView` 整层让开，点下去不会往外报。
  func testTappingChartDismissesPanel() throws {
    try XCTSkipUnless(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据，跳过（这条要真数据）")
    app.buttons[Ids.intervalChart].tap()
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    expectExists(macd, Self.short, "图表设置面板没开出来")
    chartPoint().tap()
    expectGone(macd, Self.short, "点了图，面板没收起")
  }

  // ---------------------------------------------------------------- 画线

  /// 画线按钮：点「画线」直接横过去，转回竖屏画线栏还在，「完成」退出；
  /// 退出后还能再进一次，再点一次「画线」把它收掉。
  ///
  /// 第三批最后一版把独立的「横屏」撤了——画线本来就要更大的地方，所以点「画线」
  /// 就横屏。`enterDrawingInPortrait()` 走的是「横过去再用横屏工具栏那颗『竖屏』
  /// 转回来」，也就是用户横屏画一半转回竖屏接着画的那条路：只退横屏、不退画线。
  func testDrawingModeEntersAndExits() {
    XCTAssertTrue(app.enterDrawingInPortrait(), "点「画线」没进画线态")
    let trend = app.buttons[Ids.drawTrend]
    expectExists(trend, Self.short, "竖屏画线栏上没有趋势线")
    expectExists(app.buttons[Ids.drawHLine], Self.short, "画线底栏少了水平线")
    app.buttons[Ids.drawFinish].tap()
    expectGone(trend, Self.short, "点「完成」没退出画线态")

    XCTAssertTrue(app.enterDrawingInPortrait(), "第二次进画线态失败")
    expectExists(trend, Self.short, "第二次进画线态失败")
    XCTAssertTrue(app.tapDrawEntry(), "标签栏上没有「画线」")
    expectGone(trend, Self.short, "再点一次「画线」没退出画线态")
  }

  /// 画线横屏是一张**原始 K 线**：副图和主图均线全不画。
  ///
  /// 副图（成交量、MACD）不画是因为它们把主图挤扁；主图均线也要收掉，是因为价格轴的
  /// 上下界把均线一起算进去——MA256 一挂上量程就被拉宽，K 线当场压扁、位置也挪，
  /// 画在上面的线和真正的价格结构对不上。退出画线回到竖屏，两样都要原样回来：
  /// 这一路只影响画出来的那一帧，用户开着的指标偏好一个字没动。
  func testLandscapeDrawingHidesEveryIndicator() throws {
    try XCTSkipUnless(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据，跳过（这条要真数据）")
    let subsBefore = chartInfo()["subs"] as? [String] ?? []
    let overlaysBefore = chartInfo()["overlays"] as? [String] ?? []
    XCTAssertFalse(subsBefore.isEmpty, "竖屏默认就该有副图，否则这条用例验不到东西")
    XCTAssertFalse(overlaysBefore.isEmpty, "竖屏默认就该有均线，否则这条用例验不到东西")

    XCTAssertTrue(app.tapDrawEntry(), "标签栏上没有「画线」")
    // 横屏那行品种名早就不是按钮了——竖屏的品种名不再开换品种弹层之后，横屏这一行
    // 跟着退回纯图例（`LandscapeHeadline` 只有 `accessibilityElement(children: .combine)`，
    // 没有 `.isButton`）。用例还按 `app.buttons` 找它，于是 iPhone、iPad 一台不落地
    // 全报「点「画线」没横过去」，其实横是横过去了。按 identifier 找任意元素。
    let landscapeSymbol = app.descendants(matching: .any).matching(identifier: Ids.landscapeSymbol).firstMatch
    expectExists(landscapeSymbol, Self.long, "点「画线」没横过去")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["subs"] as? [String])?.isEmpty == true },
                  "画线横屏里还留着副图：\(chartInfo()["subs"] ?? "?")")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["overlays"] as? [String])?.isEmpty == true },
                  "画线横屏里还挂着均线：\(chartInfo()["overlays"] ?? "?")")

    app.buttons[Ids.drawFinish].tap()
    expectExists(app.buttons[Ids.bottomSettings], Self.long, "画完没自己转回竖屏")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["subs"] as? [String]) == subsBefore },
                  "退回竖屏后副图没回来：\(chartInfo()["subs"] ?? "?")")
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["overlays"] as? [String]) == overlaysBefore },
                  "退回竖屏后均线没回来：\(chartInfo()["overlays"] ?? "?")")
  }

  // ---------------------------------------------------------------- 回到最新

  /// 「回到最新」：视野在最新一根上时它不在，往回拖一段就出现，点一下又消失。
  func testLatestButtonAppearsAfterLeavingLatest() throws {
    try XCTSkipUnless(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据，跳过（这条要真数据）")
    let latest = app.buttons[Ids.latestButton]
    // `waitForLiveChart()` 末尾按过一次「回到最新」，但视野归位是一帧一帧滑过去的
    // （iPad 上图宽、滑得久），所以这里轮询等它收回去，不瞬时断言。
    XCTAssertTrue(waitUntil(timeout: Self.long) { !hittable(latest) },
                  "视野就在最新一根上，「回到最新」不该露面")
    // 往回拖最多试三次。历史是边拖边补的，补齐之前只有一屏数据，`clampView` 会把窗口
    // 按回右缘——视野自己弹回最新一根，「最新」跟着收回去。那是图与行情层的既有行为，
    // 不是这颗 chip 的事，所以这里等它**站稳**再点（连着两拍都在），中途被弹回去就重拖一次，
    // 而不是把断言放宽：真出不来照样红。
    var appeared = false
    for _ in 0..<3 {
      dragChartRight()
      guard waitUntil(timeout: Self.short, { hittable(latest) }) else { continue }
      if waitUntil(timeout: 1, poll: 0.5, { !hittable(latest) }) { continue }
      appeared = true
      break
    }
    XCTAssertTrue(appeared, "视野离开最新一根了，「回到最新」没出现")
    XCTAssertTrue(tapButton(latest) { !hittable(latest) },
                  "点了「回到最新」，按钮没收回去")
  }
}
