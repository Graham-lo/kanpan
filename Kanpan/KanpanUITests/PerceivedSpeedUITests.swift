import XCTest

// ============================================================ 体感优化 2026-10-07
//
// 网慢、或者本身就慢的那几处，先让人看见「马上就来」：
// 1. 板块页第一次装好、第一趟行情还没回来：几行和真行同版式的骨架，不再整块留白。
// 2. 交易回放第一次打开（K 线磁带还没缓存）：先把缩略图那段已经取过的 K 线画上，
//    顶上一枚「加载回放」，剩下的补齐了就收掉；同一笔第二次打开直接画，不再出这枚。
//
// 截图落在本仓库 docs/acceptance/体感优化-2026-10-07/。
@MainActor
final class PerceivedSpeedUITests: KanpanUICase {
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile, "KANPAN_EXCHANGE_FIXTURE": "1",
               "KANPAN_EXCHANGE_FIXTURE_KEY": "DEMOREADONLY7C31"]
    // 交易回放那条：每页取数先停 1.5 秒、K 线盘从空的起——快网上也真走一趟「第一次打开」。
    if name.contains("TradeReplay") { env["KANPAN_TEST_REVIEW_KLINE_DELAY"] = "1.5" }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  /// 本仓库的 docs/acceptance/体感优化-2026-10-07（按这份源文件的位置找仓库根）。
  private static let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/acceptance/体感优化-2026-10-07", isDirectory: true)

  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent(name + ".png"))
  }

  /// 一直看着，直到条件成立（间隔比 `waitUntil` 短：骨架只露一小会儿）。
  private func watch(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
      if condition() { return true }
      RunLoop.main.run(until: Date().addingTimeInterval(0.03))
    }
    return condition()
  }

  func testSectorPageShowsSkeletonRowsWhileTheFirstBatchIsOnTheWay() {
    app.openSectors()
    let skeleton = app.descendants(matching: .any)["sector.skeleton"]
    let board = app.descendants(matching: .any)["sector.board"]
    // 第一趟在路上：骨架（没赶上就说明这一趟太快——那正是想要的，也照样记下来）。
    let caught = watch(Self.short) { skeleton.exists || board.exists }
    XCTAssertTrue(caught, "板块页既没有骨架也没有表")
    if skeleton.exists {
      shot("板块页骨架行")
      XCTAssertFalse(app.staticTexts["加载中"].exists)
      XCTAssertFalse(app.staticTexts["暂无行情"].exists)
    }
    // 数据一到原地换成真表，骨架不留。
    XCTAssertTrue(board.waitForExistence(timeout: Self.long), "第一趟回来了还是骨架")
    XCTAssertTrue(watch(Self.short) { !skeleton.exists }, "真表出来了骨架还压着")
  }

  func testTradeReplayShowsLoadingCapsuleThenCachesTheTape() {
    XCTAssertTrue(app.openMePage(), "开不出「我的」")
    let review = app.buttons[Ids.meReview]
    XCTAssertTrue(waitUntil(timeout: Self.long) { review.label.contains("笔 · 净盈亏") }, "本机没拼出回合")
    XCTAssertTrue(app.openReviewBookFromMe(), "复盘本没开出来")
    let tradesTab = app.buttons["review.segment.交易"]
    if tradesTab.waitForExistence(timeout: Self.short) { tradesTab.tap() }
    let btc = app.buttons.matching(identifier: "review.trades.row.BTC")
    XCTAssertTrue(waitUntil(timeout: Self.long) { btc.count >= 2 }, "交易段里没有两笔 BTC")
    let detailBar = app.navigationBars["交易详情"]
    let disc = app.buttons["trade.detail.replay"]
    let capsule = app.descendants(matching: .any)["replay.loading"]
    let title = app.descendants(matching: .any)["review.replay.title"]

    // 第一次：磁带还没缓存，先画缩略图那段、顶上一枚「加载回放」。
    btc.element(boundBy: 1).tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "没进交易详情")
    XCTAssertTrue(disc.waitForExistence(timeout: Self.short), "已平那笔没有播放记号")
    disc.tap()
    XCTAssertTrue(capsule.waitForExistence(timeout: Self.short), "取数时没出「加载回放」")
    XCTAssertEqual(capsule.label, "加载回放")
    shot("交易回放加载提示")
    XCTAssertTrue(title.waitForExistence(timeout: Self.long), "回放没起来")
    XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: Self.long), "K 线到了也没播起来")
    XCTAssertTrue(watch(Self.short) { !capsule.exists }, "磁带补齐了提示还挂着")

    // 第二次：同一笔再开，磁带在盘上，直接画，提示不出来。
    app.buttons["退出"].tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "退出没回到交易详情")
    detailBar.buttons.firstMatch.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !detailBar.exists }, "交易详情没退回列表")
    btc.element(boundBy: 1).tap()
    XCTAssertTrue(detailBar.waitForExistence(timeout: Self.short), "第二次没进交易详情")
    XCTAssertTrue(disc.waitForExistence(timeout: Self.short), "第二次详情没有播放记号")
    disc.tap()
    XCTAssertTrue(title.waitForExistence(timeout: Self.short), "第二次回放没起来")
    XCTAssertTrue(app.buttons["暂停"].waitForExistence(timeout: Self.short), "第二次没直接播")
    XCTAssertFalse(capsule.exists && capsule.isHittable, "第二次还出了「加载回放」")
  }
}
