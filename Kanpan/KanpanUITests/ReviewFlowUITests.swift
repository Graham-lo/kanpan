import XCTest

// ============================================================ 复盘的两条端到端
//
// 对应报告 B.5 客户端那张表最后两行「完整 UI」。别的用例都在包里跑（`KanpanReview`
// 那三个测试 target），只有这两件事非得把整个 app 跑起来才算数：
//
// 1. **记一笔落在哪张图上。** 记号是手绘在 `RangeOverlayView` 里的，它不是控件，
//    XCUITest 看不见画布上的像素。所以那一层在 `KANPAN_CHART_DIAGNOSTICS=1` 下
//    额外报一个数：这一帧到底画了几个记号（见 `RangeOverlayView.report(marks:)`）。
//    切周期、切品种、横过去再转回来，这个数怎么变，就是用户眼里记号在不在。
// 2. **回放往前走会不会把人的视野拽回去**（审查 B-05）。这条只能端到端验：
//    要的是「手真的拖过图之后，再往前播几根」，而手势写的是 `ChartView.state.view`，
//    只有真机/模拟器上才有那一层。
//
// 两条用例各用一棵全新的档案子树（`KANPAN_PERSISTENCE_PROFILE`），互不继承对方
// 记下的那条记录——记号计数是这两条用例的核心断言，串了就什么都验不准。

@MainActor
final class ReviewFlowUITests: KanpanUICase {

  /// 每条用例一棵干净的档案树：上一条记下的那笔不许漏到下一条。
  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": profile] }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 小工具

  /// 这一帧图上画了几个复盘记号。
  ///
  /// 一律走 `snapshot()`：这一层随图表重建（`chart` 那棵树挂着 `.id(mode)`），
  /// 问 `.value` 正好撞上重建的那一帧会当场把用例判失败，而不是老实答 nil
  /// （同 `KanpanUICase.onScreen` 那段的教训）。
  /// 记号层每一帧往无障碍值里报一行「几条/共几条 品种 周期 行情源」，这里取回整行。
  /// 用例红了的时候光有个数字不够：「记号没画出来」和「这一帧根本还是上一档周期的图」
  /// 是两件事，得把那一帧是在哪张图上画的一起打进失败信息里。
  private func markReport() -> String? {
    guard let snap = try? app.otherElements["review.range"].snapshot() else { return nil }
    return snap.value as? String
  }

  private func marks() -> Int? {
    guard let text = markReport() else { return nil }
    return Int(text.prefix(while: { $0 != "/" }))
  }

  private func expectMarks(_ count: Int, _ message: String,
                           file: StaticString = #filePath, line: UInt = #line) {
    let ok = waitUntil(timeout: Self.short) { self.marks() == count }
    XCTAssertTrue(ok, message + "（这一帧报的是 \(markReport() ?? "没读到")）",
                  file: file, line: line)
  }

  /// 走一遍用户记一笔的全程：「图表」面板 →「记一笔」→ 取景卡 →「记下」。
  ///
  /// 卡片里什么都不改——方向默认「只记录」，一句话留空，这正是「看着这段行情顺手记一笔」
  /// 最常见的样子，也是本地校验最该放行的那一档（`ReviewContract` 里 observe
  /// 那条早退分支）。卡片收回去就算记成了：`saveRecord()` 失败时卡片会留在屏幕上。
  @discardableResult
  private func recordOnce(file: StaticString = #filePath, line: UInt = #line) -> Bool {
    // 2026-09-28 顶栏方案 B：「记一笔」是顶栏右侧那颗书本圆片。
    let record = app.buttons[Ids.topNote]
    guard expectExists(record, Self.short, "顶栏没有「记一笔」那颗", file: file, line: line) else { return false }
    record.tap()
    let save = app.buttons["记下"]
    guard expectExists(save, Self.short, "点「记一笔」没开出取景卡", file: file, line: line) else { return false }
    save.tap()
    let saved = waitUntil(timeout: Self.short) { !save.exists }
    XCTAssertTrue(saved, "点了「记下」取景卡没收回去，这一条多半没记成", file: file, line: line)
    return saved
  }

  /// 「我的 › 复盘本」→ 复盘本的「全部」那一枚筛选（默认落在「待判定」，而「只记录」的那条
  /// 既不待处理也不等答案，本来就不该出现在待判定里）。
  /// 2026-09-27 底栏四格：顶栏那颗复盘撤了，复盘本只从「我的」进；收起之后人停在「我的」页。
  private func openBookRecords(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openReviewBookFromMe(), "「我的 › 复盘本」没开出复盘本", file: file, line: line)
    guard expectExists(app.buttons["review.back"], Self.long, "「复盘本」没开出复盘本", file: file, line: line)
    else { return }
    let records = app.buttons["review.chip.all"]
    if records.waitForExistence(timeout: Self.short) { records.tap() }
  }

  // ------------------------------------------------------------ B.5：记一笔落在哪张图上

  /// 记一笔 →「记下」，那个记号只画在本品种本周期，并且复盘本里看得见。
  ///
  /// 四件事连着验，缺哪件用户都会觉得「我记的东西丢了」或者「怎么画到别的图上去了」：
  ///
  /// - 记完当前这张图上多一个记号；
  /// - 切一档周期，记号不跟过去（记录里的起止是绝对时刻，1h 上框的 48 根搬到 1m 上
  ///   是同样两个时刻之间的 2880 根，位置画得出来、意思全错），切回来又在；
  /// - 换个品种，记号不跟过去，换回来又在；
  /// - 复盘本的「记录」里确实有这一条（不是只画在图上、本子里没有）；
  /// - 横过去再转回来，记号还在——横屏只有画线态才屏蔽这一层（§2E5），
  ///   单纯把手机转一下不该让记号消失。
  func testAMarkOnlyPaintsOnItsOwnSymbolAndIntervalAndLandsInTheBook() throws {
    XCTAssertTrue(waitForLiveChart(), "没等到行情：\(chartInfo())")
    // 诊断里的 `symbol` 自多交易所阶段 1 起是完整品种键（`binance/usd_m/BTCUSDT`）；
    // 搜索框里敲的是人打的代号，取最后一段。
    let key = try XCTUnwrap(chartInfo()["symbol"] as? String)
    let symbol = String(key.split(separator: "/").last ?? Substring(key))
    let interval = try XCTUnwrap(chartInfo()["interval"] as? String)
    expectMarks(0, "还没记就有记号")

    XCTAssertTrue(recordOnce(), "记一笔这条路没走通")
    expectMarks(1, "记完了图上没有记号")
    shot("复盘-记完一笔-图上的记号")

    // ---- 换一档周期
    let other = try XCTUnwrap(Ids.quickIntervals.first { $0 != interval }, "测试档案里只有一档周期")
    app.tapIntervalChip(other)
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.chartInfo()["interval"] as? String == other },
                  "没切到 \(other)：\(chartInfo())")
    expectMarks(0, "\(interval) 上记的那条画到了 \(other) 上")
    shot("复盘-换周期-记号不跟过去")
    app.tapIntervalChip(interval)
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.chartInfo()["interval"] as? String == interval },
                  "没切回 \(interval)：\(chartInfo())")
    expectMarks(1, "切回本周期，记号没回来")

    // ---- 换个品种
    let elsewhere = symbol == "ETHUSDT" ? "BTCUSDT" : "ETHUSDT"
    switchSymbol(to: elsewhere)
    expectMarks(0, "\(symbol) 上记的那条画到了 \(elsewhere) 上")
    shot("复盘-换品种-记号不跟过去")
    switchSymbol(to: symbol)
    expectMarks(1, "换回 \(symbol)，记号没回来")

    // ---- 复盘本里确实有这一条
    openBookRecords()
    XCTAssertFalse(app.descendants(matching: .any)["review.empty"].exists, "图上画着记号，复盘本里却说一条都没有")
    XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: Self.short), "「记录」里一行都没有")
    shot("复盘-复盘本记录里有这一条")
    app.buttons["review.back"].tap()
    // 复盘本是从「我的」开的，收起来回到「我的」；再切回「图表」看记号。
    expectExists(app.buttons[Ids.meSettings], Self.long, "复盘本收起之后没回到「我的」页")
    app.buttons[Ids.bottomChart].tap()
    expectExists(app.buttons[Ids.intervalChart], Self.long, "从「我的」切不回行情页")
    expectMarks(1, "从复盘本回来，记号没了")

    // ---- 横过去再转回来
    XCUIDevice.shared.orientation = .landscapeLeft
    expectExists(app.staticTexts[Ids.landscapeSymbol], Self.long, "没横过来")
    expectMarks(1, "横屏（没在画线）把记号也屏蔽了")
    shot("复盘-横屏记号仍在")
    XCUIDevice.shared.orientation = .portrait
    expectExists(app.buttons[Ids.intervalChart], Self.long, "没转回竖屏")
    expectMarks(1, "转回竖屏记号没回来")
  }

  /// 顶栏放大镜 → 打字 → 点那一行。`openSymbolPicker` 走的是品种整页，这儿只要
  /// 换一个确定存在的合约，搜索页那一行就够了。
  private func switchSymbol(to symbol: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页", file: file, line: line)
    let query = app.textFields[Ids.searchQuery]
    guard expectExists(query, Self.short, "搜索页没有输入框", file: file, line: line) else { return }
    query.tap()
    if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
      query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
    query.typeText(symbol)
    let row = app.descendants(matching: .any).matching(identifier: "symbols.row." + testInstrumentKey(symbol)).firstMatch
    guard expectExists(row, Self.long, "搜不到 \(symbol)", file: file, line: line) else { return }
    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      self.chartInfo()["symbol"] as? String == testInstrumentKey(symbol) && (self.chartInfo()["bars"] as? Int ?? 0) > 20
    }, "没换到 \(symbol)：\(chartInfo())", file: file, line: line)
  }

  // ------------------------------------------------------------ B.5：回放不许抢视野（B-05）

  /// 回放里拖去看历史，播放往前走视野留在原地；只有「判断处」才重铺。
  ///
  /// 这就是审查 B-05 说的那件事：每走一根都写死「80 根、右缘贴最新」，于是人放大看
  /// 一根的细节、或者往回拖看前因，走一根就被拽回去——等于一次次把人的手拨开。
  /// 修在 `ReviewReplayViewport.next(current:…:reset:)`，`reset` 只有两处给
  /// `true`：刚打开一条记录、人点「判断处」。这条用例验的是屏幕上那份视野
  /// （手势写进 `ChartView.state.view` 的那份），不是 bridge 里的快照。
  ///
  /// 原来播放条有「前一根」「后一根」，这条用例靠它们一根根走 → 2026-09-28 去掉了
  /// （「谁看行情也不是一根根点」），定位靠拖进度线、往前走靠播放，用例跟着改。
  func testSteppingThroughAReplayKeepsTheViewportTheUserChose() throws {
    XCTAssertTrue(waitForLiveChart(), "没等到行情：\(chartInfo())")
    XCTAssertTrue(recordOnce(), "记一笔这条路没走通")

    openBookRecords()
    let row = app.cells.firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: Self.long), "「记录」里没有刚记下的那一条")
    row.tap()
    let replay = app.buttons["在图上重温"]
    XCTAssertTrue(replay.waitForExistence(timeout: Self.short), "记录详情里没有「在图上重温」")
    replay.tap()

    // 回放条起来 + 这张重放的图真的有 K 线了，才谈得上视野。
    let progress = app.descendants(matching: .any)["review.replay.progress"]
    XCTAssertTrue(progress.waitForExistence(timeout: Self.long), "没进回放（进度线没出来）")
    XCTAssertFalse(app.buttons["前一根"].exists || app.buttons["后一根"].exists, "前一根 / 后一根该去掉了")
    XCTAssertTrue(waitUntil(timeout: Self.long, poll: 0.5) { (self.chartInfo()["bars"] as? Int ?? 0) > 0 },
                  "回放的图一根 K 线都没有：\(chartInfo())")
    let opened = chartInfo()
    let span = try XCTUnwrap(opened["span"] as? Double)
    shot("复盘-回放-刚打开")

    // ---- 拖进度线往回退：给播放腾出往前走的余地
    //
    // 这一笔是刚记下的，记在**最新那根已收盘 K 线**上，回放的游标一进来就落在这段历史的
    // 最后一根上——此刻它前面本来就没有下一根。用例要验的是「往前走不会把人的视野拽回
    // 最右边」，不是「未来那根 K 线存不存在」，所以先把进度线拖回中间。
    let openedBars = try XCTUnwrap(opened["bars"] as? Int)
    progress.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
      .press(forDuration: 0.15, thenDragTo: progress.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["bars"] as? Int ?? .max) < openedBars },
                  "拖了进度线但回放没往回退：\(chartInfo())")
    XCTAssertTrue(app.buttons["播放"].exists, "拖完进度线该保持原来的停着")

    // ---- 手动往回拖图，离开播放头
    let seeked = chartInfo()
    let seekedTo = try XCTUnwrap(seeked["to"] as? Double)
    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      (self.chartInfo()["to"] as? Double ?? .infinity) < seekedTo - span * 0.05
    }, "拖了一下回放的图，视野没动：\(chartInfo())")
    let panned = chartInfo()
    let pannedTo = try XCTUnwrap(panned["to"] as? Double)
    XCTAssertEqual(try XCTUnwrap(panned["span"] as? Double), span, accuracy: span * 0.01,
                   "拖动不该改一屏的根数")

    // ---- 播放往前走几根再停：视野留在原地
    app.buttons["播放"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { (self.chartInfo()["bars"] as? Int ?? 0) > (panned["bars"] as? Int ?? 0) },
                  "按了播放但回放没往前走：\(chartInfo())")
    app.buttons["暂停"].tap()
    XCTAssertTrue(app.buttons["播放"].waitForExistence(timeout: Self.short), "按了暂停没停")
    let stepped = chartInfo()
    XCTAssertEqual(try XCTUnwrap(stepped["to"] as? Double), pannedTo, accuracy: span * 0.02,
                   "播放往前走，视野被拽回最右边了：\(stepped)")
    XCTAssertEqual(try XCTUnwrap(stepped["span"] as? Double), span, accuracy: span * 0.01,
                   "播放往前走，一屏的根数被改回默认值了：\(stepped)")
    shot("复盘-回放-拖开后播放视野不动")

    // ---- 「判断处」才是人自己要求换地方，这时候才重铺
    app.buttons["判断处"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      (self.chartInfo()["to"] as? Double ?? 0) > pannedTo + span * 0.1
    }, "点了「判断处」视野没跳回判断那一刻：\(chartInfo())")
    shot("复盘-回放-判断处")

    // ---- 退出回到实时图
    app.buttons["退出"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { !progress.exists && self.app.buttons[Ids.intervalChart].exists },
                  "点「退出」没回到实时行情页")
  }

  /// P4.6 要「全跑一遍并截图」：关键几步各留一张，`keepAlways` 让通过的用例也留下来。
  private func shot(_ name: String) {
    let value = XCTAttachment(screenshot: app.screenshot())
    value.name = name
    value.lifetime = .keepAlways
    add(value)
  }
}
