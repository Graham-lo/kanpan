import XCTest

// ============================================================ 审查 C.10 第 2 条
//
// 「体验状态全集不丢」。
//
// 报告要的不是「切回那一页它又出现了」，而是**每一项都有一个明确的期待值**：
// 走之前量下来多少，回来还得是多少。所以这个文件只做两件事——
//
//   一、把 C.2 那张「切页状态归属表」上**签了保留**的那几格一次性全摆出来：
//       自选停在非首分类、停在中部那一行；板块下钻到第二层；设置页上改一项；
//       图表这一边把该动的全动过（周期、根宽、手动 Y、三副图的次序与比例、
//       视野推进历史、十字线、以及一条画线）。然后逐页往返一趟，回到图上逐项对数；
//       再补一趟「画线横屏 → 竖屏」的往返，同样逐项对数。
//
//   二、把**规则明确要求清掉**的那两格单独列出来验（第二条用例）：
//       临时面板是呈现态，收了就不该自己回来；十字线在换周期时必须清掉。
//       它们不是「丢了」，是产品说好要清的，和上面那一堆必须分开断言，
//       否则「全都保留」这句话本身就不成立。
//
// 两处和报告的字面输入不一样，写在这儿免得后面的人以为是漏了：
//
//   * **「设置展开」这一格在产品里已经没有了。** C.2 记的是「设置网络展开项 /
//     SettingsPanel 里的 AppStorage 键」，而「高级与诊断」那一整段（API 域名、推送域名、
//     智能线路、缓存占用）2026-09-18 已经整段撤出界面，现在设置页上一个
//     `DisclosureGroup`、一个裸 `@AppStorage` 都不剩。所以这条腿改成钉
//     「他在设置页上真的改过的那一项」（十字线磁吸）——那才是那一格现在还剩下的语义。
//
//   * **「7.3pt 根宽」写不死。** 根宽只有双指捏这一个入口，捏不出一个指定的小数。
//     这里捏出一个**离出厂足够远**的值，当场记下来当期待值，回来必须一模一样
//     （0.01pt 以内）。报告要的是「有明确期待值」，不是那个具体数字。
@MainActor
final class ExperienceStateRoundTripUITests: KanpanUICase {

  /// 美股三个排在前面：分类是按自选顺序**边走边建**的（`SymbolPickerModel
  /// .classifyUnassigned` 逐个 `createGroup`），谁先出现谁就排第一类。
  /// 这样「加密」才是**非首分类**，而且它有二十行，够滚到中部去。
  private static let usSeed = ["SNDKUSDT", "MUUSDT", "SKHYUSDT"]
  private static let cryptoSeed = [
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT",
    "ADAUSDT", "AVAXUSDT", "LINKUSDT", "DOTUSDT", "TRXUSDT",
    "LTCUSDT", "BCHUSDT", "NEARUSDT", "APTUSDT", "FILUSDT",
    "ATOMUSDT", "ARBUSDT", "OPUSDT", "SUIUSDT", "INJUSDT",
  ]
  /// 滚到中部停住的那一行：二十行里的第十四行，两屏开外。
  private static let anchorSymbol = "APTUSDT"

  /// 这两条各自一棵干净的档案树。
  ///
  /// 不隔离的话，画线是**跨启动留着**的：跑一遍多一条，几遍之后整张图上全是线。
  /// 于是第二条用例里那一下「点主图出十字线」会点在上一遍留下的那条线上——点到线
  /// 是**选中它**（`DrawingController.select` 把 `active` 置真），而 `draw.active`
  /// 一真 `MainScreen` 就把屏幕转横进画线工作台（§10.7），十字线自然出不来。
  /// 第一次撞上时的证据：点完 `chart.canvas` 那一下日志里紧跟着
  /// `Interface orientation changed to Landscape Right`，画布从 393 宽变成 630 宽。
  ///
  /// 每条用例一个新 UUID 是这个仓库里的老办法（`AICoinBaseUITests`、
  /// `ChartLayoutPersistenceUITests` 都这么干），顺带也让「走之前量的那一份」
  /// 真的是这一遍自己摆出来的，不掺上一遍的残留。
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": (Self.usSeed + Self.cryptoSeed).joined(separator: ","),
     "KANPAN_PERSISTENCE_PROFILE": profile]
  }

  /// 这两条都会把屏幕转横（画线），转完必须把设备转回竖屏。
  ///
  /// 模拟器的朝向是**跨用例留着**的：前一条要是停在横屏（哪怕它是红着停的），
  /// 下一条一开机就是横的，量出来的坐标、点出来的位置全不对——第一次跑这个文件
  /// 就撞上了：第二条在横屏里点主图，怎么点都出不来十字线。
  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 图上那一份状态

  /// 走之前量一次、回来再量一次的那张表。每一项都是用户自己摆出来的，
  /// 没有一项是出厂值——出厂值相等证明不了任何事。
  private struct ChartState {
    var interval = ""
    /// 根宽。出厂 4pt，这里会捏到更宽。
    var spacing = 0.0
    /// 三个副图的次序。
    var subs: [String] = []
    /// 三个副图各占全图高度的比例。拖过分隔线之后这三个数就不是出厂那一组了。
    var paneShares: [Double] = []
    /// 主图上挂着的均线。
    var overlays: [String] = []
    /// 画上去的那几条线。
    var drawingIDs: [String] = []
    /// 手动 Y：缩放倍数与中心位置。自动 Y 时 `zoomY` 恒为 1。
    var zoomY = 0.0
    var centerY = 0.0
    /// 最新一根离图右沿还有多远。推进历史之后它是个负数。
    var latestRightGap = 0.0
    /// 十字线在不在，以及它画在哪个像素上。
    ///
    /// 这儿不记 `crossIndex`：往历史里拖会触发补拉，前面接上几百根之后同一个时刻的
    /// **下标**本来就会变，图自己也会按时间重新锚一次（`ChartHost.updateUIView`）。
    /// 用户看见的是那根线画在哪儿，所以按像素对。
    var crosshair = false
    var crossX = 0.0
    var crossY = 0.0
  }

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  /// 画布左上角起算的一个点。
  private func canvasPoint(_ dx: Double, _ dy: Double) -> XCUICoordinate {
    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: dx, dy: dy))
  }

  private func snapshot() -> ChartState {
    let info = chartInfo()
    let height = max(info["height"] as? Double ?? 1, 1)
    let panes = info["panes"] as? [[String: Any]] ?? []
    var state = ChartState()
    state.interval = info["interval"] as? String ?? "读不到"
    state.spacing = info["spacing"] as? Double ?? 0
    state.subs = info["subs"] as? [String] ?? []
    state.paneShares = panes.map { ($0["h"] as? Double ?? 0) / height }
    state.overlays = info["overlays"] as? [String] ?? []
    state.drawingIDs = info["drawingIDs"] as? [String] ?? []
    state.zoomY = info["zoomY"] as? Double ?? 0
    state.centerY = info["centerY"] as? Double ?? 0
    state.latestRightGap = info["latestRightGap"] as? Double ?? 0
    state.crosshair = info["crosshair"] as? Bool ?? false
    state.crossX = info["crossX"] as? Double ?? -1
    state.crossY = info["crossY"] as? Double ?? -1
    return state
  }

  /// 逐项对数。每一项各报各的，别让一句「状态不一样」把人扔回去自己找。
  private func expectSameChart(_ now: ChartState, _ want: ChartState, _ trip: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(now.interval, want.interval, "\(trip)：周期变了", file: file, line: line)
    XCTAssertEqual(now.spacing, want.spacing, accuracy: 0.01,
                   "\(trip)：根宽从 \(want.spacing) 变成了 \(now.spacing)", file: file, line: line)
    XCTAssertEqual(now.subs, want.subs, "\(trip)：三个副图的次序变了", file: file, line: line)
    XCTAssertEqual(now.paneShares.count, want.paneShares.count,
                   "\(trip)：副图数量变了", file: file, line: line)
    for (index, share) in want.paneShares.enumerated() where index < now.paneShares.count {
      XCTAssertEqual(now.paneShares[index], share, accuracy: 0.01,
                     "\(trip)：第 \(index + 1) 个副图的高度比例从 \(share) 变成了 \(now.paneShares[index])",
                     file: file, line: line)
    }
    XCTAssertEqual(now.overlays, want.overlays, "\(trip)：主图均线变了", file: file, line: line)
    XCTAssertEqual(now.drawingIDs, want.drawingIDs, "\(trip)：画上去的线变了", file: file, line: line)
    XCTAssertEqual(now.zoomY, want.zoomY, accuracy: 0.001,
                   "\(trip)：手动 Y 的倍数从 \(want.zoomY) 变成了 \(now.zoomY)", file: file, line: line)
    XCTAssertEqual(now.centerY, want.centerY, accuracy: 0.001,
                   "\(trip)：手动 Y 的中心从 \(want.centerY) 变成了 \(now.centerY)", file: file, line: line)
    XCTAssertEqual(now.latestRightGap, want.latestRightGap, accuracy: 2,
                   "\(trip)：图被推回最新了（离最新一根 \(want.latestRightGap) → \(now.latestRightGap)）",
                   file: file, line: line)
    XCTAssertEqual(now.crosshair, want.crosshair,
                   "\(trip)：十字线在不在这件事变了（该 \(want.crosshair)，实际 \(now.crosshair)）",
                   file: file, line: line)
    guard want.crosshair else { return }
    XCTAssertEqual(now.crossX, want.crossX, accuracy: 1,
                   "\(trip)：十字线从 x=\(want.crossX) 跑到了 x=\(now.crossX)", file: file, line: line)
    XCTAssertEqual(now.crossY, want.crossY, accuracy: 1,
                   "\(trip)：十字线从 y=\(want.crossY) 跑到了 y=\(now.crossY)", file: file, line: line)
  }

  // ------------------------------------------------------------ 该保留的那一整套

  func testEveryPieceOfTheExperienceSurvivesTheWholeRoundTrip() throws {
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线——这条要真行情，拿不到就是断了")

    // ---------------------------------------------------------- 一、把状态摆出来

    // 周期：出厂不是 4h，点到 4h 去。
    let bornInterval = chartInfo()["interval"] as? String ?? ""
    XCTAssertNotEqual(bornInterval, "4h", "出厂周期就是 4h，这条用例验不到换周期")
    app.tapIntervalChip("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      let info = self.chartInfo()
      return info["interval"] as? String == "4h" && (info["bars"] as? Int ?? 0) > 0
    }, "点了 4h 图没换过去：\(chartInfo()["interval"] ?? "?")")

    // 画线：进竖屏画线态，画一条水平线，退出画线态。
    //
    // 这一步放最前面是有讲究的：进画线本身要横一趟再转回来
    // （`enterDrawingInPortrait`），后面那些量（根宽、手动 Y、视野）都得留到这趟
    // 转屏**之后**再摆，不然分不清是「切页丢的」还是「转屏丢的」。
    // 横竖往返自己那一轮在第三段单独走。
    XCTAssertTrue(app.enterDrawingInPortrait(), "点「画线」没进竖屏画线态")
    let trend = app.buttons[Ids.drawTrend]
    expectExists(trend, Self.short, "竖屏画线栏上没有趋势线")
    trend.tap()
    // 两个锚点画一条趋势线。用趋势线而不是水平线：水平线只要一个锚点，而单点工具
    // 在这台模拟器上一下会落两条（`draw.hline` 点一次 `drawingCount` 就是 2），
    // 那是 `KanpanChart` 画线层自己的事，这一条要验的是「画好的线切页还在不在」，
    // 不该拿它去撞那个坑——两点工具是既有用例走通过的路。
    //
    // 数的是**多出来一条**，不是「一共一条」：画线存的是这台机器上这个品种的线，
    // `KANPAN_TEST_PROFILE` 那份隔离档案不管它，上一轮跑剩下的线还在图上
    // （第一次跑就撞上了：一条都没画就已经有 2 条）。这条用例要验的是
    // 「画好的线切页还在不在」，拿绝对条数去卡只会卡到上一轮的残留。
    let drawnBefore = chartInfo()["drawingCount"] as? Int ?? 0
    canvasPoint(100, 60).tap()
    canvasPoint(240, 120).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (self.chartInfo()["drawingCount"] as? Int ?? 0) == drawnBefore + 1
    }, "点了两下画布，趋势线没画上去：\(drawnBefore) → \(chartInfo()["drawingCount"] ?? "?")")
    XCTAssertEqual((chartInfo()["drawingKinds"] as? [String])?.last, "trend", "画出来的不是趋势线")
    app.buttons[Ids.drawFinish].tap()
    expectGone(trend, Self.short, "点「完成」没退出画线态")

    // 根宽：捏一把，离出厂那个值远一点。
    let bornSpacing = try XCTUnwrap(chartInfo()["spacing"] as? Double)
    canvas.pinch(withScale: 2.0, velocity: 1)
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (self.chartInfo()["spacing"] as? Double ?? 0) > bornSpacing + 1
    }, "捏了一把根宽没变：\(bornSpacing) → \(chartInfo()["spacing"] ?? "?")")

    // 三副图的次序：把第一个整块长按拖到最后，三个轮换一格。
    let bornSubs = try XCTUnwrap(chartInfo()["subs"] as? [String])
    XCTAssertEqual(bornSubs.count, 3, "出厂就该是三个副图，现在是 \(bornSubs)")
    let wantSubs = Array(bornSubs.dropFirst()) + [bornSubs[0]]
    dragPane(from: 0, to: 2)
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["subs"] as? [String] == wantSubs },
                  "整块拖到底也没换序：\(bornSubs) → \(chartInfo()["subs"] ?? "?")")

    // 三副图的比例：把第一个副图的下沿往下推，它变高、另外两个让出地方。
    let grip = app.otherElements["chart.resize." + wantSubs[0]]
    expectExists(grip, Self.short, "\(wantSubs[0]) 那一格没有可拖的分隔线")
    let gripHeightBefore = Double(grip.value as? String ?? "") ?? 0
    XCTAssertGreaterThan(gripHeightBefore, 0, "分隔线读不出它管的那一格有多高")
    let gripAt = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: grip.frame.midX, dy: grip.frame.midY))
    gripAt.press(forDuration: 0.05, thenDragTo: gripAt.withOffset(CGVector(dx: 0, dy: 35)))
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (Double(grip.value as? String ?? "") ?? 0) > gripHeightBefore + 15
    }, "拖了分隔线，\(wantSubs[0]) 还是 \(gripHeightBefore)pt 高")

    // 手动 Y：在价格轴上竖着拖一把，自动 Y 就被顶成手动的了。
    let plotW = try XCTUnwrap(chartInfo()["plotW"] as? Double)
    let axis = canvasPoint(plotW + 20, min(140, try XCTUnwrap(chartInfo()["mainH"] as? Double) / 2))
    axis.press(forDuration: 0.05, thenDragTo: axis.withOffset(CGVector(dx: 0, dy: -85)))
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      abs((self.chartInfo()["zoomY"] as? Double ?? 1) - 1) > 0.03
    }, "在价格轴上拖了一把，Y 还是自动的：\(chartInfo()["zoomY"] ?? "?")")

    // 视野：往回推到历史里去，「回到最新」跟着亮起来。
    var pushes = 0
    while (chartInfo()["latestRightGap"] as? Double ?? 0) > -20, pushes < 8 {
      dragChartRight(); pushes += 1
    }
    XCTAssertLessThan(try XCTUnwrap(chartInfo()["latestRightGap"] as? Double), -20,
                      "推了 \(pushes) 下图还贴在最新那根上")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "视野离开最新了，「回到最新」却没出来")

    // 十字线：最后摆，免得上面那几下手势把它扫掉。
    canvasPoint(200, min(140, try XCTUnwrap(chartInfo()["mainH"] as? Double) / 2)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "点了主图没出十字线")

    let baseline = snapshot()
    XCTAssertEqual(baseline.interval, "4h")
    XCTAssertGreaterThan(baseline.spacing, bornSpacing + 1)
    XCTAssertEqual(baseline.subs, wantSubs)
    XCTAssertEqual(baseline.drawingIDs.count, drawnBefore + 1, "画上去的那条线不见了")
    XCTAssertFalse(baseline.overlays.isEmpty, "出厂就该有均线，否则这一项验不到东西")
    shot("摆好的图表状态")

    // ---------------------------------------------------------- 二、逐页往返

    // 自选：停在**非首分类**（加密），并滚到中部那一行。
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    let usGroup = app.buttons["favorites.group.美股"]
    XCTAssertTrue(usGroup.waitForExistence(timeout: Self.long),
                  "自选页上没有「美股」这一类，只有 \(groupTitles())——种子没被归类")
    let cryptoGroup = app.buttons["favorites.group.加密"]
    XCTAssertTrue(cryptoGroup.waitForExistence(timeout: Self.long),
                  "自选页上没有「加密」这一类，只有 \(groupTitles())")
    XCTAssertTrue(waitUntil(timeout: Self.short) { usGroup.isSelected },
                  "刚进来该停在第一类（美股），实际停在 \(selectedGroupTitle() ?? "没有哪一类")"
                  + "——那「加密」就不是非首分类了（分类次序：\(groupTitles())）")
    // 等它真的能点再点。胶囊一出现就点，赶上头部那一条还在铺/还在动的那一瞬间，
    // XCUI 会判它不可点直接抛（2026-09-21 矩阵在 iPhone Air 上就红在这一句：
    // `Failed to not hittable: Button ... identifier: 'favorites.group.加密'`）。
    // 这不是把断言放松——点不动本来就该等，等不到照样红。
    XCTAssertTrue(waitUntil(timeout: Self.long) { cryptoGroup.isHittable },
                  "「加密」这颗胶囊一直点不动")
    cryptoGroup.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { cryptoGroup.isSelected }, "点了「加密」没切过去")

    let anchor = app.buttons["favorites.open." + testInstrumentKey(Self.anchorSymbol)]
    let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                                                     : app.tables.firstMatch
    // 一下滚三成屏幕，**不要用 `swipeUp()`**。
    //
    // `swipeUp()` 一甩差不多一整屏，而锚点是二十行里的第 14 行（`APTUSDT`，下标 13）。
    // 这张表滚到底时可视区里就剩最后六行，第 14 行卡在上沿之外——滚过头就再也回不来。
    // 2026-09-22 在 iPhone 16 Pro（iOS 26.5）上量到的就是这个：12 下 `swipeUp` 之后
    // 铺着的是 `FILUSDT@224 ATOMUSDT@320 ARBUSDT@416 OPUSDT@512 SUIUSDT@608 INJUSDT@704`
    // ——下标 14…19，一行 96pt，整张表顶到了尾巴上，`APTUSDT` 一次都没铺出来。
    //
    // 这条用例先前那次红（「切回自选，APTUSDT 不在屏幕上了」）是同一件事的另一面：
    // 同样滚到了表尾，只是那一回 `List` 还替 `APTUSDT` 留着一行缓冲，它的框正好压在
    // 头部底下，而 `onScreen` 只问「中心点在不在窗口里」（`UITestSupport.swift:204`），
    // 于是循环当场收工。**那时人停的那一行本来就是 `FILUSDT`**：诊断串量到走之前
    // 记的是 `anchor=FILUSDT`，切一圈回来顶上完整露着的还是 `FILUSDT@250`，
    // 一行不差——产品这头把落脚点还原得准准的，是用例自己滚过了头、又拿一行藏在
    // 头部底下的缓冲行当成了「在屏幕上」。
    //
    // 慢慢挪就不会跳过它。同一张种子表、同一个锚点的
    // `FavoritesScrollAnchorUITests`（`PresenterAndStateUITests.swift`）2026-09-21
    // 已经因为同样的原因换成了这一手，在 iPhone 16 Pro 上一直是绿的；两条用例
    // 量同一件事，就该用同一把尺。
    var scrolled = 0
    while !onScreen(anchor), scrolled < 12 {
      list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        .press(forDuration: 0.05,
               thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)))
      scrolled += 1
    }
    XCTAssertTrue(onScreen(anchor), "滚了 \(scrolled) 下还没把 \(Self.anchorSymbol) 滚出来"
                  + "（这会儿铺着：\(renderedFavorites())）")
    let anchorY = anchor.frame.minY
    let beforeRows = renderedFavorites()
    // 走之前的落脚点。回来对不上时，光看「APTUSDT 不在屏幕上」说不清是**没记住**
    // 还是**记住了没还原到位**，这一串（`anchor=` / `top=` / `used=`）分得开。
    let favoritesDiagnosticsBefore = favoritesDiagnostics()

    // 板块：下钻一层（板块列表 → 某个板块的品种列表）。
    // 注意全程不许在已经站在板块页时再点一次「板块分类」——那一下按规则要把下钻
    // 路径清回板块列表（`MainScreen.switchTo`），会把这条腿自己验的东西擦掉。
    app.buttons[Ids.bottomSectors].tap()
    expectExists(app.otherElements["sector.page"], Self.long, "点「板块分类」没进板块页")
    let sectorRow = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
    expectExists(sectorRow, Self.long, "板块列表里一行都没有")
    sectorRow.tap()
    let listBack = app.buttons["sector.list.back"]
    expectExists(listBack, Self.long, "点一个板块没进它的品种列表")
    let sectorMember = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sector.open.")).firstMatch
    expectExists(sectorMember, Self.long, "板块的品种列表里一行都没有")
    let sectorMemberID = sectorMember.identifier

    // 设置：改一项（十字线磁吸），它就是这一页上「他摆出来的样子」。
    openSettingsPage()
    let magnet = app.buttons[Ids.settingsMagnet]
    expectExists(magnet, Self.short, "设置页上没有十字线磁吸")
    let magnetBefore = magnet.value as? String ?? "?"
    magnet.tap()
    let magnetWant = magnetBefore == "开" ? "关" : "开"
    XCTAssertTrue(waitUntil(timeout: Self.short) { (magnet.value as? String) == magnetWant },
                  "点了十字线磁吸没翻过去：\(magnetBefore) → \(magnet.value as? String ?? "?")")

    // 回图表：逐项对数。
    leaveSettings()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.snapshot().subs == baseline.subs },
                  "回到图表，副图次序还没落回来：\(chartInfo()["subs"] ?? "?")")
    expectSameChart(snapshot(), baseline, "走了自选→板块→设置再回图表")
    shot("逐页往返之后的图表")

    // 回板块：还站在第二层那张品种列表上，而且还是同一个板块（C-01 钉的就是它）。
    app.buttons[Ids.bottomSectors].tap()
    XCTAssertTrue(listBack.waitForExistence(timeout: Self.long),
                  "切回板块，人被扔回板块列表了——下钻路径没被持有")
    XCTAssertTrue(app.buttons[sectorMemberID].waitForExistence(timeout: Self.long),
                  "切回板块，进的不是刚才那个板块（\(sectorMemberID) 不在了）")

    // 回自选：还停在加密，还停在那一行。
    XCTAssertTrue(app.openFavorites(), "从板块回不到自选页")
    XCTAssertTrue(waitUntil(timeout: Self.short) { cryptoGroup.isSelected },
                  "切回自选，分类跳回第一类了")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(anchor) },
                  "切回自选，\(Self.anchorSymbol) 不在屏幕上了——滚动位置没被持有"
                  + "\n走之前 \(Self.anchorSymbol)@\(Int(anchorY))，铺着：\(beforeRows)"
                  + "\n走之前：\(favoritesDiagnosticsBefore)"
                  + "\n回来后：\(favoritesDiagnostics())"
                  + "\n回来后铺着：\(renderedFavorites())")
    XCTAssertLessThan(abs(anchor.frame.minY - anchorY), 120,
                      "切回来 \(Self.anchorSymbol) 从 \(anchorY) 跑到了 \(anchor.frame.minY)"
                      + "\n走之前：\(favoritesDiagnosticsBefore)"
                      + "\n回来后：\(favoritesDiagnostics())")

    // 回设置：刚改的那一项还在。
    openSettingsPage()
    XCTAssertEqual(magnet.value as? String, magnetWant, "切回设置，刚改的十字线磁吸弹回去了")

    leaveSettings()
    expectSameChart(snapshot(), baseline, "又走了板块→自选→设置再回图表")

    // ---------------------------------------------------------- 三、画线横竖往返

    XCTAssertTrue(app.tapDrawEntry(), "标签栏上没有「画线」")
    let landscapeSymbol = app.descendants(matching: .any)
      .matching(identifier: Ids.landscapeSymbol).firstMatch
    expectExists(landscapeSymbol, Self.long, "点「画线」没横过去")
    // 横屏那一屏是**说好要空的**：指标一律不画（`kanpan-landscape-is-for-drawing`），
    // 但画上去的线必须还在——那才是横过来要干的事。
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["subs"] as? [String])?.isEmpty == true
    }, "画线横屏里还留着副图：\(chartInfo()["subs"] ?? "?")")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["overlays"] as? [String])?.isEmpty == true
    }, "画线横屏里还挂着均线：\(chartInfo()["overlays"] ?? "?")")
    XCTAssertEqual(chartInfo()["drawingIDs"] as? [String], baseline.drawingIDs,
                   "横过来画的线没了")
    shot("画线横屏")

    // 画线进行中横屏侧栏整条收起，用手把机器转回来接着画。
    XCTAssertFalse(app.buttons[Ids.landscapeExit].exists, "画线进行中横屏侧栏还在，和「完成」重复")
    app.rotateDrawingToPortraitByHand()
    expectExists(app.buttons[Ids.drawFinish], Self.long, "转回竖屏画线栏没回来")
    app.buttons[Ids.drawFinish].tap()
    expectExists(app.buttons[Ids.intervalChart], Self.long, "退出画线态没回到行情页")

    XCTAssertTrue(waitUntil(timeout: Self.long) { self.snapshot().subs == baseline.subs },
                  "转回竖屏，副图还没回来：\(chartInfo()["subs"] ?? "?")")
    expectSameChart(snapshot(), baseline, "画线横竖往返之后")
    shot("横竖往返之后的图表")
  }

  // ------------------------------------------------------------ 该清的那两格

  /// 规则明确要求清掉的两样：临时面板收了就不许自己回来，换周期必须清十字线。
  ///
  /// 这两条必须和上面那条分开写。上面那条的结论是「全都相等」，把这两样混进去，
  /// 要么它假红，要么得给它们开一个例外——而例外正是「假绿」的入口。
  ///
  /// 顺带把**同一次切页里两种状态的分野**钉死：面板里改的那个设置（关掉一个副图）
  /// 跟着人走，面板本身不跟着人走。
  func testOnlyTheThingsTheRulesSayToClearGetCleared() throws {
    XCTAssertTrue(waitForLiveChart(), "\(Self.long)s 内没等到 K 线——这条要真行情，拿不到就是断了")

    // ---------------------------------------------------------- 一、临时面板
    let bornSubs = try XCTUnwrap(chartInfo()["subs"] as? [String])
    XCTAssertFalse(bornSubs.isEmpty, "出厂就该有副图，否则这条用例验不到东西")
    let dropped = bornSubs[0]

    app.buttons[Ids.intervalChart].tap()
    let header = app.staticTexts[Ids.panelHeader]
    expectExists(header, Self.short, "图表设置面板没开出来")
    XCTAssertTrue(app.openIndicatorPage(), "图表设置面板里点「指标」没进到指标页")
    let toggle = app.buttons[Ids.indicatorSwitch(dropped)]
    expectExists(toggle, Self.short, "图表设置面板里没有 \(dropped) 的开关")
    scrollPanelContent(to: toggle)
    toggle.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (self.chartInfo()["subs"] as? [String])?.contains(dropped) == false
    }, "关掉 \(dropped)，图上还画着它：\(chartInfo()["subs"] ?? "?")")

    // 面板自己是呈现态：点面板外面那一下就该收（§10.6）。
    // 竖屏面板是系统 sheet，它正压着标签栏——用户想切页，本来就得先让它下去，
    // 所以「收面板」这一下是这条路上必经的一步，不是绕开断言的捷径。
    chartPoint().tap()
    expectGone(header, Self.short, "点了图区，临时面板没收起")

    // 切一趟页再回来：面板里改的那个设置跟着人走，面板自己不跟着人走。
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    leaveSettings()
    XCTAssertFalse(app.staticTexts[Ids.panelHeader].exists,
                   "切了一趟页回来，临时面板自己又出来了——它是呈现态，不是体验状态")
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["subs"] as? [String])?.contains(dropped) == false
    }, "切了一趟页回来，关掉的 \(dropped) 自己又回来了：\(chartInfo()["subs"] ?? "?")")

    // ---------------------------------------------------------- 二、十字线
    //
    // 同品种同周期切页要留着（上一条用例已经钉死），换周期就得清：
    // 换了周期，它原来指的那一根本来就不存在了。
    canvasPoint(200, min(140, try XCTUnwrap(chartInfo()["mainH"] as? Double) / 2)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "点了主图没出十字线：mainH=\(chartInfo()["mainH"] ?? "?") "
                  + "panes=\(chartInfo()["panes"] ?? "?") trace=\(chartInfo()["gestureTrace"] ?? "?") "
                  + "画布=\(app.otherElements["chart.canvas"].frame)")
    // 十字线活着时周期条整行让位给十字线的四颗动作、透明且点不着（ae1e7a4）；这时能换周期的
    // 只有「看细节」——它正是「换了周期、原来指的那一根不在了」的那条路。
    let from = try XCTUnwrap(chartInfo()["interval"] as? String)
    let detail = app.buttons["chart.detailZoom"]
    expectExists(detail, Self.short, "十字线开着却没有「看细节」")
    detail.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["interval"] as? String).map { $0 != from } ?? false
    }, "点了「看细节」图没换周期")
    let to = chartInfo()["interval"] as? String ?? "?"
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == false },
                  "从 \(from) 换到 \(to)，十字线还钉在那儿")
  }

  // ------------------------------------------------------------ 手势与取证

  /// 把面板里的某个控件用**真手势**滚进可视区，别让 XCUITest 自己去够。
  ///
  /// 为什么非得自己滚：`element.tap()` 够不着的时候，XCUITest 会先走一步
  /// 「Scroll element to visible」——那是**辅助功能的滚动请求**，不是手指划过屏幕。
  /// UIKit 把它交给 sheet 的呈现控制器，后者的反应是把面板从 `.medium` 撑到 `.large`
  /// （2026-09-21 实测：面板刚开时 `panel.content` 在 y=456，`tap()` 走完之后是 y=114，
  /// 也就是顶到了 y=59）。撑满之后这条用例下一步要点的图区整个被盖住，
  /// `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` 也不再放行，
  /// 于是「点图区收面板」永远收不掉——一条和产品无关的假红。
  ///
  /// 换成手指划：同一轮实测里连划四下，`panel.content` 一直钉在 y=456 没动过，
  /// 列表自己在滚（`PanelHost` 那句 `.presentationContentInteraction(.scrolls)`）。
  /// 也就是说人手里的面板不会因为找一个指标就涨满屏，只有 XCUITest 那条路会。
  ///
  /// 滚不动就算了：判红交给调用方那句断言，这儿不掺和。
  private func scrollPanelContent(to element: XCUIElement) {
    let content = app.scrollViews["panel.content"]
    guard content.waitForExistence(timeout: Self.short) else { return }
    for _ in 0..<12 {
      if element.isHittable { return }
      // 目标在下半场就往上滚，在上半场（划过头了）就往回滚——自己纠偏，不会一路滚飞。
      let up = element.frame.midY > content.frame.midY
      let from = CGVector(dx: 0.5, dy: up ? 0.66 : 0.34)
      let to = CGVector(dx: 0.5, dy: up ? 0.34 : 0.66)
      content.coordinate(withNormalizedOffset: from)
        .press(forDuration: 0.1, thenDragTo: content.coordinate(withNormalizedOffset: to))
    }
  }

  /// 自选页上现在有哪几类，按它们在胶囊条上的次序。失败信息里要有它。
  private func groupTitles() -> [String] {
    let chips = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "favorites.group."))
    return (0..<chips.count).map {
      String(chips.element(boundBy: $0).identifier.dropFirst("favorites.group.".count))
    }
  }

  /// 此刻停在哪一类。
  private func selectedGroupTitle() -> String? {
    let chips = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "favorites.group."))
    for index in 0..<chips.count where chips.element(boundBy: index).isSelected {
      return String(chips.element(boundBy: index).identifier.dropFirst("favorites.group.".count))
    }
    return nil
  }

  /// 自选页那串只活在辅助功能树里的诊断（`FavoritesView.paletteDiagnostics`）。
  /// 里头的 `anchor=` / `top=` / `used=` 三项就是落脚点这条腿的全部账本。
  private func favoritesDiagnostics() -> String {
    String(describing: app.otherElements["favorites.feed"].value)
  }

  /// 自选页这会儿真的铺出来了哪几行，按屏幕上从上到下。
  ///
  /// `List` 是懒的：滚远了的行会被卸掉，于是「XCUI 找不到这一行」既可能是它滚出了
  /// 视野、也可能是它压根没铺。把铺着的这一串打出来，两种情况当场分得开。
  private func renderedFavorites() -> [String] {
    let rows = app.buttons.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open."))
    var out: [(String, CGFloat)] = []
    for index in 0..<rows.count {
      guard let snap = try? rows.element(boundBy: index).snapshot() else { continue }
      out.append((String(snap.identifier.dropFirst("favorites.open.".count)), snap.frame.minY))
    }
    return out.sorted { $0.1 < $1.1 }.map { "\($0.0)@\(Int($0.1))" }
  }

  /// 把第 `from` 个副图整块长按拖到第 `to` 个的位置上。
  private func dragPane(from: Int, to: Int) {
    let info = chartInfo()
    guard let panes = info["panes"] as? [[String: Any]], panes.count > max(from, to) else {
      XCTFail("读不到副图的版面：\(info["panes"] ?? "?")"); return
    }
    let plotW = info["plotW"] as? Double ?? 300
    func center(_ pane: [String: Any]) -> XCUICoordinate {
      canvasPoint(plotW / 2, (pane["y"] as? Double ?? 0) + (pane["h"] as? Double ?? 80) / 2)
    }
    center(panes[from]).press(forDuration: 0.5, thenDragTo: center(panes[to]))
  }

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
