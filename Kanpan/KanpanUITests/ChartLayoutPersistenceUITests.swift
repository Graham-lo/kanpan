import XCTest

/// 「打开 app 进入选择 BTC 缩小后，立马退出后台冷启动，回来并不是我缩小后的样子。」
///
/// 用户 2026-09-19 报的现象。**两条杀法，都在这儿钉住：**
///
/// - **甲（不需要服务器）**：图开张时用的是出厂根宽（档案还没到），档案晚到之后只改了
///   内存那一份，图还画在出厂宽度上；之后任何一次视野变化都会把图身上那个出厂宽度
///   当成「用户想要多宽」报回去，反手把用户真正的那份**写掉**。所以这条用例
///   **同品种同周期，中途一次都不许切**——一切就会走 `.reset`，按新根宽重开一张图，
///   bug 自己好了，也就照不出来。
/// - **乙（要登录）**：根宽只落到 `prefs.json`，那条同步操作还没写进存档就被杀；
///   冷启动时 `applyPending()` 拿存档里那份旧的把它盖回去。
///
/// 所以**登录和没登录两条路都要跑**：对模块来说这是同一个功能，无非是云端还是本地，
/// 保存时机、读取时机、语义必须一模一样。
@MainActor final class ChartLayoutPersistenceUITests: XCTestCase {
  private let profile = UUID().uuidString
  private let account = "test_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)
  private let password = "Testpass2026"

  private func makeApp(signedIn: Bool) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_PERSISTENCE_PROFILE"] = profile
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    // 没有这个变量就没有账号桥，走的是纯本地那条路。
    if signedIn { app.launchEnvironment["KANPAN_ACCOUNT_API_URL"] = "https://kanpan.107-174-172-10.sslip.io" }
    return app
  }

  private func wait(_ seconds: Double, _ condition: @escaping () -> Bool) -> Bool {
    XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)],
                   timeout: seconds) == .completed
  }

  /// 干等一会儿（让同步把第一份 settings 推上去、让冷启动那一轮 applyPending 跑完）。
  private func settle(_ seconds: Double) { _ = wait(seconds) { false } }

  private func info(_ app: XCUIApplication) -> [String: Any] {
    guard let raw = app.otherElements["chart.canvas"].value as? String,
          let data = raw.data(using: .utf8) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  /// 图自己量出来的那一份根宽。
  private func spacing(_ app: XCUIApplication) -> Double { info(app)["spacing"] as? Double ?? 0 }

  /// 三份拷贝：`PrefsStore` 手上那份（等于盘上那份）、`ChartViewport` 内存那份、图自己那份。
  private func copies(_ app: XCUIApplication) -> String {
    // 旧代码里没有这份旁证，别让读不到把用例炸在「元素不存在」上——
    // 这条用例要照的是用户看到的那个现象，不是诊断元素在不在。
    let probe = app.descendants(matching: .any).matching(identifier: "layout.diagnostics")
    let side = probe.count > 0 ? (probe.firstMatch.value as? String ?? "?") : "(这一版没有旁证)"
    return "\(side);chart=\(spacing(app))"
  }

  private func waitForChart(_ app: XCUIApplication) {
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(canvas.waitForExistence(timeout: 60), "K 线画布没出来")
    XCTAssertTrue(wait(60) { (self.info(app)["bars"] as? Int ?? 0) >= 120 }, "K 线没拿到数据：\(info(app))")
  }

  private func typeSecret(_ app: XCUIApplication, _ text: String) {
    let field = app.secureTextFields["account.password"]
    field.tap()
    if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 2) { app.buttons["xmark"].tap() }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
    for character in text { field.typeText(String(character)) }
  }

  private func attach(_ name: String, _ text: String) {
    let note = XCTAttachment(string: text); note.name = name; note.lifetime = .keepAlways; add(note)
  }

  // ---------------------------------------------------------------- 共用的那一段

  /// 真的把图捏成另一个样子，返回捏完的根宽。
  ///
  /// **这一步自己会验自己**：合成手势没生效的那一跑，`spacing` 一动不动，
  /// 后面「冷启动还是这个样子」就会拿 4.0 和 4.0 比——**两头都是出厂值，
  /// 测试照样绿**，等于什么都没验。所以这里先钉死「手势真的改了布局」。
  ///
  /// 顺带记一笔踩过的坑：`pinch(withScale: 0.4, velocity: -3)`（捏小）在这台
  /// 模拟器上**一点事都不发生**——诊断里 `stored/live/chart` 三份全是 4.0。
  /// 同一块画布上用真手指（`simctl` 两指路径）捏小是好的，盘上立刻就写成了 1.6，
  /// 所以不是 app 不认捏小，是 XCUITest 合成的那一版捏合没送到。捏大
  /// （`AICoinBaseUITests.testPinchAndUnifiedBackground` 一直在用的那组参数）是好的。
  /// 对「布局要记住」这件事来说方向无所谓——记的是同一个 `barSpacing`——
  /// 所以捏小没生效就改捏大，两条都不生效才算手势本身坏了。
  private func pinchUntilLayoutChanges(_ app: XCUIApplication, from before: Double) -> Double {
    let canvas = app.otherElements["chart.canvas"]
    canvas.pinch(withScale: 0.4, velocity: -1)          // 用户原话是「缩小」，先照着来
    if abs(spacing(app) - before) < before * 0.15 {
      attach("捏小没生效，改捏大", copies(app))
      canvas.pinch(withScale: 2.6, velocity: 1)
    }
    let pinched = spacing(app)
    XCTAssertGreaterThan(abs(pinched - before), before * 0.15,
      "两种捏法都没能改变布局，这一跑什么也没验到：捏前 \(before)，捏后 \(pinched)")
    return pinched
  }

  /// 捏一下 → 手一松立刻杀 → 冷启动。**同品种同周期，中途不切。**
  /// 返回（手一松时的根宽，冷启动之后的根宽）。
  private func pinchKillRelaunch(_ app: XCUIApplication, signedIn: Bool) -> (Double, Double) {
    let before = spacing(app)
    XCTAssertGreaterThan(before, 0, "读不到根间距：\(info(app))")
    attach("捏之前的三份", copies(app))

    let pinched = pinchUntilLayoutChanges(app, from: before)
    attach("手一松的三份", copies(app))
    // 手指抬起那一刻就该落盘落档了。不给任何定时器机会。
    app.terminate()

    let restarted = makeApp(signedIn: signedIn)
    restarted.launch()
    waitForChart(restarted)
    // 登录那条路上 `applyPending()` 是同步跑完之后才落地的，等它跑过再读，
    // 免得读到「盖回去之前」的那一帧。没登录那条路等这几秒也无害。
    settle(12)
    attach("冷启动之后的三份", copies(restarted))
    return (pinched, spacing(restarted))
  }

  /// 布局跟着人走：换周期、换品种都还是这一份。
  /// **只在断言过「冷启动还是捏出来的样子」之后才做**——切一下就会重开图，
  /// 那会把杀法甲盖住。
  private func assertLayoutFollowsThePerson(_ app: XCUIApplication, expected: Double) {
    app.buttons["interval.chip.1h"].tap()
    XCTAssertTrue(wait(30) { (self.info(app)["bars"] as? Int ?? 0) >= 120 })
    XCTAssertEqual(spacing(app), expected, accuracy: 0.3, "换周期不该改变根间距")

    app.buttons["top.search"].tap()
    XCTAssertTrue(app.textFields["search.query"].waitForExistence(timeout: 15))
    app.textFields["search.query"].tap()
    app.textFields["search.query"].typeText("ETHUSDT")
    let row = app.buttons["symbols.row.ETHUSDT"]
    XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
    row.tap()
    waitForChart(app)
    XCTAssertTrue(wait(20) { (self.info(app)["symbol"] as? String) == "ETHUSDT" })
    XCTAssertEqual(spacing(app), expected, accuracy: 0.3, "换品种不该改变根间距")
  }

  // ---------------------------------------------------------------- 登录那条路

  func testZoomSurvivesImmediateKillWhileSignedIn() throws {
    continueAfterFailure = false

    let app = makeApp(signedIn: true)
    app.launch()
    waitForChart(app)

    // 自己造一个账号（现造的测试口令，不碰任何真账号）。
    app.buttons["bottom.settings"].tap()
    app.buttons["settings.account"].tap()
    XCTAssertTrue(app.buttons["注册"].waitForExistence(timeout: 10))
    app.buttons["注册"].tap()
    app.textFields["account.email"].tap()
    app.textFields["account.email"].typeText(String(account))
    typeSecret(app, password)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait(40) { !app.otherElements["account.view"].exists }, app.debugDescription)

    app.buttons["bottom.chart"].tap()
    waitForChart(app)
    // 让第一轮同步把这份设置推上去：这样存档里有一份「旧宽度」的基线，
    // 下面那一捏要是没落进存档，冷启动就会被它盖回去——正是用户看到的那一下。
    settle(10)

    let (pinched, after) = pinchKillRelaunch(app, signedIn: true)
    XCTAssertEqual(after, pinched, accuracy: max(0.05, pinched * 0.03),
      "捏完立刻杀掉 app，冷启动回来应当还是手一松时的样子（登录）：松手 \(pinched)，回来 \(after)")

    let restarted = XCUIApplication()
    assertLayoutFollowsThePerson(restarted, expected: after)

    let shot = XCTAttachment(screenshot: restarted.screenshot())
    shot.name = "冷启动之后的布局（登录）"; shot.lifetime = .keepAlways; add(shot)

    // 收尾：把测试账号删掉，不在后端留垃圾。
    restarted.buttons["bottom.settings"].tap()
    restarted.buttons["settings.account"].tap()
    XCTAssertTrue(restarted.buttons["注销账号"].waitForExistence(timeout: 15))
    restarted.buttons["注销账号"].tap()
    typeSecret(restarted, password)
    restarted.buttons["account.submit"].tap()
    XCTAssertTrue(wait(30) { !restarted.otherElements["account.view"].exists })
  }

  /// 用户 2026-09-19 报的那条路，**跟上面那条差的只是落地页**：有自选的人冷启动
  /// 落在自选页，图在他点进品种之前一直不存在；账号档案是在这段时间里到货的。
  /// 从前这一到货没人接（图不在），点进去的图装回的是落地前存下的那份旧视野——
  /// 盘上、云端都是捏完的宽度，屏幕上却是默认的密度，而且下一下拖动还会把旧宽度
  /// 写回盘上、推上云端，把正确的那份彻底冲掉。
  ///
  /// 所以这条要连做两轮冷启动：第一轮证明「点进去还是捏完的样子」，第二轮证明
  /// 中间那一下拖动没把旧宽度写回去。
  func testZoomSurvivesColdStartLandingOnFavoritesWhileSignedIn() throws {
    continueAfterFailure = false

    func launchOnFavorites() -> XCUIApplication {
      let app = makeApp(signedIn: true)
      app.launchEnvironment["KANPAN_TEST_FAVORITES"] = "BTCUSDT"
      app.launch()
      XCTAssertTrue(app.buttons["favorites.open.BTCUSDT"].waitForExistence(timeout: 60), "有自选的人冷启动该落在自选页")
      return app
    }
    func openChart(_ app: XCUIApplication) {
      app.buttons["favorites.open.BTCUSDT"].tap()
      waitForChart(app)
      XCTAssertTrue(wait(20) { (self.info(app)["symbol"] as? String) == "BTCUSDT" })
    }

    let app = launchOnFavorites()
    openChart(app)

    // 自己造一个账号（现造的测试口令，不碰任何真账号）。
    app.buttons["bottom.settings"].tap()
    app.buttons["settings.account"].tap()
    XCTAssertTrue(app.buttons["注册"].waitForExistence(timeout: 10))
    app.buttons["注册"].tap()
    app.textFields["account.email"].tap()
    app.textFields["account.email"].typeText(String(account))
    typeSecret(app, password)
    app.buttons["account.submit"].tap()
    XCTAssertTrue(wait(40) { !app.otherElements["account.view"].exists }, app.debugDescription)

    app.buttons["bottom.chart"].tap()
    waitForChart(app)
    settle(10)                                        // 让第一轮同步把旧宽度推上去，存档里有基线

    let before = spacing(app)
    XCTAssertGreaterThan(before, 0, "读不到根间距：\(info(app))")
    let pinched = pinchUntilLayoutChanges(app, from: before)
    attach("手一松的三份", copies(app))
    app.terminate()

    // 第一轮：落在自选页，等账号档案在图不存在的时候到货，再点进去。
    let second = launchOnFavorites()
    settle(12)
    openChart(second)
    settle(3)
    attach("落地自选之后点进去的三份", copies(second))
    let reopened = spacing(second)
    XCTAssertEqual(reopened, pinched, accuracy: max(0.05, pinched * 0.03),
      "冷启动落在自选页、再点进品种，应当还是手一松时的样子：松手 \(pinched)，回来 \(reopened)")
    let shot = XCTAttachment(screenshot: second.screenshot())
    shot.name = "落地自选后点进去的布局（登录）"; shot.lifetime = .keepAlways; add(shot)

    // 拖一下：从前正是这一下把旧宽度写回盘上。
    second.otherElements["chart.canvas"].swipeRight()
    settle(3)
    XCTAssertEqual(spacing(second), pinched, accuracy: max(0.05, pinched * 0.03), "拖动不该改变根间距")
    second.terminate()

    // 第二轮：拖过之后再冷启动，还得是捏出来的那份。
    let third = launchOnFavorites()
    settle(12)
    openChart(third)
    settle(3)
    attach("拖过一下再冷启动的三份", copies(third))
    XCTAssertEqual(spacing(third), pinched, accuracy: max(0.05, pinched * 0.03),
      "拖过一下再冷启动，旧宽度不许被写回去：松手 \(pinched)，回来 \(spacing(third))")

    // 收尾：把测试账号删掉，不在后端留垃圾。
    third.buttons["bottom.settings"].tap()
    third.buttons["settings.account"].tap()
    XCTAssertTrue(third.buttons["注销账号"].waitForExistence(timeout: 15))
    third.buttons["注销账号"].tap()
    typeSecret(third, password)
    third.buttons["account.submit"].tap()
    XCTAssertTrue(wait(30) { !third.otherElements["account.view"].exists })
  }

  // ---------------------------------------------------------------- 没登录那条路

  /// 同一个功能的另一半。对 `ChartViewport` 来说登录与否只差「云端那条腿在不在」，
  /// 保存时机、读取时机、语义一个字都不能不一样——所以这条用例的断言和上面那条
  /// 逐字相同，只是不造账号。
  func testZoomSurvivesImmediateKillWhileSignedOut() throws {
    continueAfterFailure = false

    let app = makeApp(signedIn: false)
    app.launch()
    waitForChart(app)
    settle(3)

    let (pinched, after) = pinchKillRelaunch(app, signedIn: false)
    XCTAssertEqual(after, pinched, accuracy: max(0.05, pinched * 0.03),
      "捏完立刻杀掉 app，冷启动回来应当还是手一松时的样子（没登录）：松手 \(pinched)，回来 \(after)")

    let restarted = XCUIApplication()
    assertLayoutFollowsThePerson(restarted, expected: after)

    let shot = XCTAttachment(screenshot: restarted.screenshot())
    shot.name = "冷启动之后的布局（没登录）"; shot.lifetime = .keepAlways; add(shot)
  }
}
