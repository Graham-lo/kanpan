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

  /// 顶栏品种按钮 → 半屏弹层 → 关掉回主界面。
  ///
  /// 第三批 15 之后这颗按钮开的不再是整张品种页，而是一张半屏弹层：头两行是
  /// 「搜索品种」和「全部自选与分组」，下面直接列自选，常看的那几个一点就换。
  /// 换品种最短的那条路不该再让人先翻一整页。
  func testSymbolButtonOpensQuickSheet() {
    app.buttons[Ids.symbolButton].tap()
    let search = app.buttons[Ids.quickSearch]
    expectExists(search, Self.short, "点品种按钮没开出半屏弹层")
    expectExists(app.buttons[Ids.quickAll], Self.short, "弹层里没有「全部自选与分组」")
    app.buttons["quickFavorites.close"].tap()
    expectGone(search, Self.short, "弹层关不掉")
    expectExists(app.buttons[Ids.symbolButton], Self.short, "关掉弹层后没回到主界面")
  }

  /// 顶栏品种名 → 半屏弹层第一行「搜索品种」→ 品种页，且落在搜索框上。
  ///
  /// 顶栏那颗放大镜在第三批 15 里撤了：换品种原来有三个入口（顶栏品种名、顶栏放大镜、
  /// 底栏自选），三条路通向两张不同的页，现在只剩品种名这一条，搜索和完整自选页
  /// 都是那个弹层里的头两行。
  func testSearchEntryOpensSymbolPage() {
    XCTAssertTrue(app.openSymbolSearch(), "品种名弹层里的「搜索品种」没开出品种页的搜索框")
    app.buttons[Ids.symbolsBack].tap()
    expectGone(app.buttons[Ids.symbolsBack], Self.short, "品种页返回没关掉")
  }

  /// 自选星：点一下加进自选、再点一下移出，label 跟着翻。
  ///
  /// 断言读的是 label（「加入自选」/「移出自选」），因为这颗星的「亮没亮」在界面上
  /// 就是靠颜色，颜色不归 UI 测试管。两次点完回到出发时的状态。
  func testFavoriteStarToggles() {
    let star = app.buttons[Ids.starButton]
    expectExists(star)
    let before = star.label
    star.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { star.label != before },
                  "点了自选星，状态没变（还是「\(before)」）")
    let after = star.label
    star.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { star.label == before },
                  "再点一次自选星没退回原状（停在「\(after)」）")
  }

  // ---------------------------------------------------------------- 周期条

  /// 常用行六档挨个点一遍，选中态跟着走：点谁谁 selected，其余都不 selected。
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

  /// 周期条右端「更多」→ 周期面板（十四档都在）→ 收起。
  func testMoreOpensPeriodPanel() {
    app.buttons[Ids.intervalMore].tap()
    let row = app.buttons[Ids.periodRow("1h")]
    expectExists(row, Self.short, "点「更多」没开出周期面板")
    expectExists(app.buttons[Ids.periodRow("1M")], Self.short, "周期面板里没有冷门档（1M）")
    dismissSheet(until: row)
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

  /// 指标面板：开得出来、收得回去。多项配置页，选完**不**自动收（规矩①的另一半）。
  func testIndicatorPanelOpensAndCloses() {
    app.buttons[Ids.bottomIndicator].tap()
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    expectExists(macd, Self.short, "点底栏「指标」没开出指标面板")
    expectExists(app.buttons[Ids.indicatorSwitch("MA")], Self.short, "指标面板里没有主图叠加那几项")
    dismissSheet(until: macd)
  }

  /// 设置面板：开得出来、收得回去。同样是多项配置页，不自动收。
  func testSettingsPanelOpensAndCloses() {
    app.buttons[Ids.bottomSettings].tap()
    let magnet = app.buttons[Ids.settingsMagnet]
    expectExists(magnet, Self.short, "点底栏「设置」没开出设置面板")
    dismissSheet(until: magnet)
  }

  /// 交互规矩②：手指落到面板以外（这里点的是 K 线图）面板就收起。
  ///
  /// 要先等图真的有数据——没数据时 `ChartView` 整层让开，点下去不会往外报。
  func testTappingChartDismissesPanel() throws {
    try XCTSkipUnless(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据，跳过（这条要真数据）")
    app.buttons[Ids.bottomIndicator].tap()
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    expectExists(macd, Self.short, "指标面板没开出来")
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
    app.buttons[Ids.bottomDraw].tap()
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

    app.buttons[Ids.bottomDraw].tap()
    expectExists(app.buttons[Ids.landscapeSymbol], Self.long, "点「画线」没横过去")
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
    XCTAssertTrue(waitUntil(timeout: Self.long) { !latest.isHittable },
                  "视野就在最新一根上，「回到最新」不该露面")
    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { latest.isHittable },
                  "视野离开最新一根了，「回到最新」没出现")
    XCTAssertTrue(tapButton(latest) { !latest.isHittable },
                  "点了「回到最新」，按钮没收回去")
  }
}
