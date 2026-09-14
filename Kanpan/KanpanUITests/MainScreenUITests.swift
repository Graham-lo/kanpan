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

  /// 顶栏品种按钮 → 品种页 → 返回。
  func testSymbolButtonOpensAndClosesSymbolPage() {
    app.buttons[Ids.symbolButton].tap()
    expectExists(app.buttons[Ids.symbolsBack], Self.short, "点品种按钮没开出品种页")
    app.buttons[Ids.symbolsBack].tap()
    expectGone(app.buttons[Ids.symbolsBack], Self.short, "品种页返回没关掉")
    expectExists(app.buttons[Ids.symbolButton], Self.short, "关掉品种页后没回到主界面")
  }

  /// 顶栏搜索按钮 → 同一张品种页，且落在搜索框上。
  func testSearchButtonOpensSymbolPage() {
    let query = app.textFields[Ids.symbolsQuery]
    app.buttons[Ids.searchButton].tap()
    if app.buttons[Ids.searchButton].exists {
      print("[UIHit] search callback count: \(String(describing: app.buttons[Ids.searchButton].value))")
    }
    XCTAssertTrue(query.waitForExistence(timeout: Self.short),
                  "搜索按钮正中心一次点击应开出品种页的搜索框")
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

  /// 风格面板：开得出来，**点一款之后自己收起**（刚定下的交互规矩①）。
  ///
  /// 收起之后再开一次，把风格选回默认的「墩」（stout），不给下一条用例留状态。
  func testStylePanelDismissesItselfAfterPick() {
    app.buttons[Ids.bottomStyle].tap()
    let indigo = app.buttons[Ids.styleCard("indigo")]
    expectExists(indigo, Self.short, "点底栏「风格」没开出风格面板")
    indigo.tap()
    expectGone(indigo, Self.short, "选了一款风格，面板没有自己收起——违反单选面板即选即收")

    app.buttons[Ids.bottomStyle].tap()
    let stout = app.buttons[Ids.styleCard("stout")]
    expectExists(stout, Self.short, "风格面板第二次没开出来")
    stout.tap()
    expectGone(stout, Self.short, "第二次选完面板没收起")
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

  /// 画线按钮：进画线态底栏换成四颗（A7.1），「完成」退出；再进一次用底栏那颗退出。
  func testDrawingModeEntersAndExits() {
    app.buttons[Ids.bottomDraw].tap()
    let trend = app.buttons[Ids.drawTrend]
    expectExists(trend, Self.short, "点「画线」没进画线态")
    expectExists(app.buttons[Ids.drawHLine], Self.short, "画线底栏少了水平线")
    app.buttons[Ids.drawFinish].tap()
    expectGone(trend, Self.short, "点「完成」没退出画线态")

    app.buttons[Ids.bottomDraw].tap()
    expectExists(trend, Self.short, "第二次进画线态失败")
    app.buttons[Ids.bottomDraw].tap()
    expectGone(trend, Self.short, "再点一次「画线」没退出画线态")
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
