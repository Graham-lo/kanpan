import XCTest

// ============================================================ A8.4 主界面可达性
//
// 任务书 §13 A8.4：「8 机型 UI 测试全绿（同一套用例）」。
// 这一套测的**不是像素**（像素归 `make evidence` 取证与渲染单测），而是 §9.1 的可达性：
// 每一个该点的地方点得到、点了有反应、反应完还能退回去。
//
// 每条用例都把自己改过的状态改回来（风格、周期、自选），所以跑的顺序无所谓，
// 也可以在同一台机器上连跑两遍。

@MainActor
final class MainScreenUITests: KanpanUICase {

  // ---------------------------------------------------------------- 顶栏

  func testHeaderStatsAtLargestDynamicType() {
    let priceHeight = app.staticTexts["top.lastPrice"].frame.height
    let statsHeight = app.otherElements["top.stats"].frame.height
    app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                            "UICTContentSizeCategoryAccessibilityXXXL"]
    testHeaderStatsStayRightOfPrice()
    XCTAssertEqual(app.staticTexts["top.lastPrice"].frame.height, priceHeight, accuracy: 0.5)
    XCTAssertEqual(app.otherElements["top.stats"].frame.height, statsHeight, accuracy: 0.5)
  }

  /// 六格按实际数值占宽；美股市值、费率和倒计时同样会挤满头部。
  func testHeaderStatsStayRightOfPrice() {
    continueAfterFailure = true
    var statsHeight: CGFloat?
    var intervalY: CGFloat?
    for symbol in ["SNDKUSDT", "MUUSDT", "1000SATSUSDT", "BTCUSDT"] {
      app.terminate()
      app.launchEnvironment["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/\(symbol)"
      app.launch()
      let price = app.staticTexts["top.lastPrice"]
      let change = app.descendants(matching: .any)["top.changePercent"].firstMatch
      let stats = app.otherElements["top.stats"]
      guard expectExists(price, Self.long), expectExists(stats, Self.long) else { continue }
      XCTAssertTrue(waitUntil(timeout: Self.long) {
        [price.label, app.staticTexts["top.marketCap"].label,
         app.staticTexts["top.turnover"].label, app.staticTexts["top.funding"].label]
          .allSatisfy { !["", "—", "--"].contains($0) }
      }, "\(symbol) 的价格与六格实值没有到齐")
      XCTAssertTrue(app.symbolLabel.label.contains(symbol), "深链没有打开 \(symbol)")
      let digits = ["SNDKUSDT": 2, "MUUSDT": 2, "1000SATSUSDT": 8, "BTCUSDT": 1][symbol]!
      let pattern = "^[0-9,]+\\.[0-9]{\(digits)}$"
      XCTAssertNotNil(price.label.range(of: pattern, options: .regularExpression), "\(symbol) 价格未按报价步长展示：\(price.label)")
      let amount = change.label.components(separatedBy: "  ").first ?? ""
      XCTAssertNotNil(amount.range(of: "^[+−-]?[0-9,]+\\.[0-9]{\(digits)}$", options: .regularExpression),
                      "\(symbol) 涨跌额未按报价步长展示：\(change.label)")
      print("PRECISION \(symbol) price=\(price.label) change=\(change.label) digits=\(digits)")
      let p = price.frame, s = stats.frame
      let y = app.buttons[Ids.intervalMore].frame.minY
      let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      shot.name = "header-\(symbol)"; shot.lifetime = .keepAlways; add(shot)
      print("HEADER \(symbol) price=\(p) stats=\(s) intervalY=\(y)")
      XCTAssertGreaterThanOrEqual(s.minX, p.maxX, "\(symbol) 六格掉到价格下面")
      XCTAssertGreaterThanOrEqual(s.minX, change.frame.maxX + 7.5, "\(symbol) 涨跌行挤进六格")
      XCTAssertGreaterThanOrEqual(p.minX, 11.5, "\(symbol) 价格超出左侧留白")
      XCTAssertTrue(change.label.contains("  "), "\(symbol) 涨跌额或涨跌幅缺失")
      XCTAssertGreaterThanOrEqual(change.frame.minY, p.maxY, "\(symbol) 涨跌行没在价格下面")
      XCTAssertEqual(change.frame.minX, p.minX, accuracy: 0.5, "\(symbol) 涨跌行没有左对齐")
      XCTAssertLessThanOrEqual(s.maxX, app.windows.firstMatch.frame.maxX - 12 + 0.5,
                               "\(symbol) 六格超出屏幕右缘")
      if let statsHeight { XCTAssertEqual(s.height, statsHeight, accuracy: 0.5) }
      if let intervalY { XCTAssertEqual(y, intervalY, accuracy: 0.5, "\(symbol) 头部挤高了周期条") }
      statsHeight = s.height; intervalY = y
      let chartMatches = {
        self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) && self.chartInfo()["priceDecimals"] as? Int == digits
      }
      var chartReady = waitUntil(timeout: Self.long, chartMatches)
      if !chartReady {
        // 真行情的历史请求可能遇到上游限流。等罚停窗口过去，再走界面的重试入口一次；
        // 最后的品种、精度与十字线断言不放宽，也不切线路或改成假行情。
        let retry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "重试")).firstMatch
        if retry.exists {
          RunLoop.current.run(until: Date(timeIntervalSinceNow: 60))
          retry.tap()
          chartReady = waitUntil(timeout: Self.long, chartMatches)
        }
      }
      XCTAssertTrue(chartReady, "\(symbol) 图表未就绪或精度不一致：\(chartInfo())")
      guard chartReady else { continue }
      let canvas = app.otherElements["chart.canvas"]
      let mainH = chartInfo()["mainH"] as? Double ?? 300
      canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: min(130, mainH / 2))).tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true })
      let crossShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
      crossShot.name = "crosshair-\(symbol)"; crossShot.lifetime = .keepAlways; add(crossShot)
      canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 150, dy: min(130, mainH / 2))).tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false })
    }
  }

  func testPricePrecisionInFavoritesAndSectorRows() {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "SNDKUSDT,MUUSDT,1000SATSUSDT,BTCUSDT"
    app.launch()
    func check(_ id: String, digits: Int) {
      let value = app.descendants(matching: .any)[id].firstMatch
      XCTAssertTrue(waitUntil(timeout: Self.long) {
        value.exists && value.label.range(of: "^[0-9,]+\\.[0-9]{\(digits)}$", options: .regularExpression) != nil
      }, "\(id) 未按报价步长展示：\(value.exists ? value.label : "不存在")")
      print("LIST PRECISION \(id)=\(value.label)")
    }
    func shot(_ name: String) {
      let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    let stocks = app.buttons["favorites.group.美股"]
    guard expectExists(stocks, Self.long) else { return }
    stocks.tap()
    check("favorites.price.binance/usd_m/SNDKUSDT", digits: 2)
    check("favorites.price.binance/usd_m/MUUSDT", digits: 2)
    shot("precision-favorites-stocks")
    app.buttons["favorites.group.加密"].tap()
    check("favorites.price.binance/usd_m/1000SATSUSDT", digits: 8)
    check("favorites.price.binance/usd_m/BTCUSDT", digits: 1)
    shot("precision-favorites-crypto")
    app.buttons[Ids.bottomSectors].tap()
    let usMarket = app.buttons["sector.market.us"]
    guard expectExists(usMarket, Self.long) else { return }
    usMarket.tap()
    let storage = app.descendants(matching: .any)["sector.row.mem"].firstMatch
    _ = storage.waitForExistence(timeout: Self.long)
    for _ in 0..<8 where !storage.isHittable { app.swipeUp() }
    guard expectExists(storage, Self.long) else { return }
    storage.tap()
    check("sector.price." + testInstrumentKey("SNDKUSDT"), digits: 2)
    check("sector.price." + testInstrumentKey("MUUSDT"), digits: 2)
    shot("precision-sector-stocks")
    app.buttons["sector.list.back"].tap()
    app.buttons["sector.market.crypto"].tap()
    let bitcoin = app.descendants(matching: .any)["sector.row.btc-eco"].firstMatch
    _ = bitcoin.waitForExistence(timeout: Self.long)
    for _ in 0..<8 where !bitcoin.isHittable { app.swipeUp() }
    guard expectExists(bitcoin, Self.long) else { return }
    bitcoin.tap()
    check("sector.price." + testInstrumentKey("BTCUSDT"), digits: 1)
    let sats = app.descendants(matching: .any)["sector.price." + testInstrumentKey("1000SATSUSDT")].firstMatch
    for _ in 0..<5 where !sats.isHittable {
      app.swipeUp()
    }
    check("sector.price." + testInstrumentKey("1000SATSUSDT"), digits: 8)
    shot("precision-sector-crypto")
  }

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
    // 冷启动是「回家」不是「走进来」，左边不该有返回箭头。
    XCTAssertFalse(app.buttons[Ids.topBack].exists, "冷启动的顶栏上出现了返回")
  }

  // ---------------------------------------------------------------- 来回一趟

  /// 板块列表 → 某个板块的品种列表 → 行情页 → 顶栏返回 → **还站在那张品种列表上**。
  ///
  /// 两件事一起验：顶栏那颗返回在「走进来」的图上要存在；退回去之后板块页下钻到
  /// 第几层就还在第几层（路由挪到宿主身上之前，切走一次就整页重建，人被扔回板块列表）。
  func testSectorDrillDownRoundTripsThroughChart() {
    app.buttons[Ids.bottomSectors].tap()
    expectExists(app.otherElements["sector.page"], Self.long, "点「板块分类」没进板块页")
    let sectorRow = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
    expectExists(sectorRow, Self.long, "板块列表里一行都没有")
    sectorRow.tap()

    let listBack = app.buttons["sector.list.back"]
    expectExists(listBack, Self.long, "点一个板块没进它的品种列表")
    let symbolRow = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sector.open.")).firstMatch
    expectExists(symbolRow, Self.long, "板块的品种列表里一行都没有")
    symbolRow.tap()

    let back = app.buttons[Ids.topBack]
    expectExists(back, Self.long, "从板块下钻点进图表，顶栏没有返回")
    back.tap()

    expectExists(listBack, Self.long, "顶栏返回没把人放回那张品种列表")
    listBack.tap()
    expectExists(sectorRow, Self.long, "品种列表退不回板块列表")
    expectGone(listBack, Self.short, "退回板块列表之后品种列表还压在上面")
  }

  /// 自选行 → 行情页 → 顶栏返回 → 自选页。自选是「走进来」的另一条路。
  func testFavoritesRowRoundTripsThroughChart() {
    app.terminate()
    app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT"
    app.launch()
    expectExists(app.buttons["favorites.more"], Self.long, "有自选时冷启动该停在自选页")
    let row = app.buttons["favorites.open.binance/usd_m/BTCUSDT"]
    expectExists(row, Self.long, "自选页上没有 BTCUSDT 这一行")
    row.tap()

    let back = app.buttons[Ids.topBack]
    expectExists(back, Self.long, "从自选点进图表，顶栏没有返回")
    back.tap()
    expectExists(app.buttons["favorites.more"], Self.long, "顶栏返回没把人送回自选页")
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
      // 立刻选中，点不中要当场留证据。真正落手的那一下换成坐标点
      // （`tapIntervalChip`）——药丸挂在一条滚不动的横向 `ScrollView` 里，
      // `XCUIElement.tap()` 那套「先滚到可见」在这种条上会算出 `{-1, -1}`，
      // 于是明明画得好好的按钮被判 not hittable 直接放弃。
      XCTAssertTrue(tapButton(chip, tap: { _ in app.tapIntervalChip(raw) }) { chip.isSelected },
                    "点了 \(raw)，它自己没变成选中")
      for other in Ids.quickIntervals where other != raw {
        XCTAssertFalse(app.buttons[Ids.intervalChip(other)].isSelected,
                       "选了 \(raw)，\(other) 还亮着——同一时刻只能有一档选中")
      }
    }
    if let original { app.tapIntervalChip(original) }
  }

  /// 周期条右端「更多」→ 盖在图上的周期弹层（十四档都在、每格带图钉）。
  ///
  /// 2026-09-23 起它不再是周期条底下摊开的一段（那样一展开图就被压扁一半），而是从周期条
  /// 下沿往下展开、盖在图上的一层，外面压一层遮罩。所以这儿先量**图的框一个 pt 都不动**，
  /// 再把三条收起的路各走一遍：再点「更多」、在面板上滑一下、点遮罩。
  func testMoreOpensPeriodPanel() {
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: Self.long), "没有图")
    let before = canvas.frame
    app.buttons[Ids.intervalMore].tap()
    let row = app.buttons[Ids.periodRow("1h")]
    expectExists(row, Self.short, "点「更多」没摊开周期网格")
    expectExists(app.buttons[Ids.periodRow("1M")], Self.short, "周期网格里没有冷门档（1M）")
    expectExists(app.buttons[Ids.periodPin("1M")], Self.short, "周期网格的格子上没有图钉")
    XCTAssertEqual(canvas.frame, before, "「更多」一展开图的框变了：\(before) → \(canvas.frame)")
    XCTAssertGreaterThanOrEqual(row.frame.minY, before.minY - 1, "网格没从周期条下沿往下展开")
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !row.exists }, "再点一下「更多」，网格没收起来")

    // 在面板上往上推一下：收起。
    app.buttons[Ids.intervalMore].tap()
    expectExists(row, Self.short, "第二次点「更多」没摊开周期网格")
    app.otherElements["interval.grid"].swipeUp()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !row.exists }, "在面板上滑一下，网格没收起来")

    // 点遮罩（图的下半截）：收起，不落十字线。
    app.buttons[Ids.intervalMore].tap()
    expectExists(row, Self.short, "第三次点「更多」没摊开周期网格")
    canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.8)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !row.exists }, "点遮罩，网格没收起来")
    XCTAssertEqual(canvas.frame, before, "收起之后图的框变了")
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
    // 2026-09-23 起面板上只留一行「指标」摘要，点进去才是开关（同一张面板里推进去的一页）。
    XCTAssertTrue(app.openIndicatorPage(), "图表设置面板里点「指标」没进到指标页")
    let macd = app.buttons[Ids.indicatorSwitch("MACD")]
    expectExists(macd, Self.short, "点周期行「图表」没开出指标那几栏")
    expectExists(app.buttons[Ids.indicatorSwitch("MA")], Self.short, "指标那几栏里没有主图叠加")
    // 主力订单流（2026-09-24）：主图叠加区第七行，只有开关。
    expectExists(app.buttons[Ids.indicatorSwitch("ORDERFLOW")], Self.short, "主图叠加里没有「主力订单流」")
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
  func testTappingChartDismissesPanel() {
    // 审查 C.9：这儿原来是 `XCTSkipUnless(waitForLiveChart())`——等不到 K 线就跳过，
    // 而跳过在汇总里既不是失败也不是通过，「点一下收面板」这件事实际一次都没被验到。
    // 拿不到行情不是「这条用例不适用」，是环境或产品断了，该红就红。
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据——这条要真数据，拿不到就是断了")
    app.buttons[Ids.intervalChart].tap()
    let macd = app.buttons["chart.indicators"]
    expectExists(macd, Self.short, "图表设置面板没开出来")
    chartPoint().tap()
    expectGone(macd, Self.short, "点了图，面板没收起")
  }

  // ---------------------------------------------------------------- 画线

  /// 画线按钮：点「画线」直接横过去，转回竖屏画线栏还在，「完成」退出；
  /// 退出后还能再进一次，再点一次「画线」把它收掉。
  ///
  /// 第三批最后一版把独立的「横屏」撤了——画线本来就要更大的地方，所以点「画线」
  /// 就横屏。`enterDrawingInPortrait()` 走的是「横过去再用手把机器转回来」，
  /// 也就是用户横屏画一半转回竖屏接着画的那条路：只退横屏、不退画线。
  /// （画线进行中横屏侧栏整条收起，没有「竖屏」按钮可按，2026-09-23。）
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
  func testLandscapeDrawingHidesEveryIndicator() {
    // 审查 C.9：同上，跳过改硬断言。
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据——这条要真数据，拿不到就是断了")
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
  func testLatestButtonAppearsAfterLeavingLatest() {
    // 审查 C.9：同上，跳过改硬断言。
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线数据——这条要真数据，拿不到就是断了")
    let latest = app.buttons[Ids.latestButton]
    // `waitForLiveChart()` 末尾按过一次「回到最新」，但视野归位是一帧一帧滑过去的
    // （iPad 上图宽、滑得久），所以这里轮询等它收回去，不瞬时断言。
    XCTAssertTrue(waitUntil(timeout: Self.long) { !onScreen(latest) },
                  "视野就在最新一根上，「回到最新」不该露面")
    // 往回拖最多试三次。历史是边拖边补的，补齐之前只有一屏数据，`clampView` 会把窗口
    // 按回右缘——视野自己弹回最新一根，「最新」跟着收回去。那是图与行情层的既有行为，
    // 不是这颗 chip 的事，所以这里等它**站稳**再点（连着两拍都在），中途被弹回去就重拖一次，
    // 而不是把断言放宽：真出不来照样红。
    var appeared = false
    for _ in 0..<3 {
      dragChartRight()
      guard waitUntil(timeout: Self.short, { onScreen(latest) }) else { continue }
      if waitUntil(timeout: 1, poll: 0.5, { !onScreen(latest) }) { continue }
      appeared = true
      break
    }
    XCTAssertTrue(appeared, "视野离开最新一根了，「回到最新」没出现")
    XCTAssertTrue(tapButton(latest) { !onScreen(latest) },
                  "点了「回到最新」，按钮没收回去")
  }
}
