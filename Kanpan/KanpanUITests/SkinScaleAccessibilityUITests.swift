import XCTest

// ============================================================ 审查 C.10 第 10 条
//
// 「六皮肤 × 大字号 × 最短 VoiceOver 流程」。
//
// 六皮肤那一半原本就有人守（`ChartFoundationUITests.testComfortPalettesAndLayout`
// 逐格对图区底色与版面），这条补的是它没走的另外两根轴：
//
// **大字号。** 整个 app 都在**最大**那一档动态字号下跑
// （`UICTContentSizeCategoryAccessibilityXXXL`，系统设置里「更大字体」拉到底那一格）。
// 这一档下最容易出的事是版面被文字顶破：控件挤出窗口、图区被压没、底栏叠上来。
// 所以每一格皮肤都要重新量一遍关键控件的位置，并且留一张截图。
//
// **最短 VoiceOver 流程。** XCUITest 里开不起真的 VoiceOver（它是系统级服务），
// 但 VoiceOver 念的就是无障碍树上的名字和动作——这条就照着盲人用户那条最短的路
// 「搜 BTC → 加入自选 → 从自选打开图」走一遍，逐个控件断言它报出来的是**中文**的
// 名字和状态，而不是一个图标、一个英文 id、或者干脆没有名字。
// 报告本来也只要「关键控件有中文可读角色/动作」，不要求全量无障碍重构。
//
// 启动参数那一条（`-UIPreferredContentSizeCategoryName`）是 UIKit 自己认的，
// Release 包里同样生效，不是我们的测试开关，所以不归 C-02 那张后门表管。
@MainActor
final class SkinScaleAccessibilityUITests: KanpanUICase {

  override var extraLaunchArguments: [String] {
    ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
  }

  /// 给一份固定的自选，让自选页上有东西可看；故意**不放 BTCUSDT**，
  /// 第二条用例要亲手把它加进去，才看得出星那一下有没有翻名字。
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "ETHUSDT,SOLUSDT"]
  }

  /// 三套皮肤 × 深浅两档，各自图区该有的底色。
  ///
  /// 只有「经典」照抄 AICoin 的白／深蓝，青苔与陶土取自己种子里的 `chart`
  /// （用户 2026-09-18 定的）。六个值互不相同，所以这张表本身就钉住了
  /// 「换皮肤图区真的跟着换」这件事。
  private static let combos: [(skin: String, mode: String, background: String, name: String)] = [
    ("sage", "浅色", "#F3F7F4", "青苔·浅"),
    ("sage", "深色", "#0B120F", "青苔·深"),
    ("terra", "浅色", "#FBF6F0", "陶土·浅"),
    ("terra", "深色", "#16100C", "陶土·深"),
    ("classic", "浅色", "#FFFFFF", "经典·浅"),
    ("classic", "深色", "#0D111C", "经典·深"),
  ]

  /// 最大字号下一个都不许被顶出窗口的控件。
  private static let keyControls: [(id: String, what: String)] = [
    ("top.symbol", "顶栏品种名"),
    ("top.lastPrice", "最新价"),
    ("top.changePercent", "涨跌幅"),
    ("interval.chart", "周期行右端的「图表」"),
    ("bottom.draw", "底栏画线"),
    ("bottom.chart", "底栏图表"),
    ("bottom.favorites", "底栏自选"),
    ("bottom.sectors", "底栏板块分类"),
    ("bottom.settings", "底栏设置"),
  ]

  // ------------------------------------------------------------ 六皮肤 × 大字号

  func testEverySkinStaysUsableAtTheLargestType() {
    // 版面基线：启动那一刻量到的图区高度——那时候最大字号已经生效了。
    // 皮肤只换颜色，不许换版面，所以六格都要回到这个数。
    let baseline = chartBottom - chartTop
    XCTAssertGreaterThan(baseline, 100, "最大字号下图区就已经被文字挤没了（\(baseline)pt）")

    for combo in Self.combos {
      openSettingsPage()
      let card = app.buttons["display.theme." + combo.skin]
      expectExists(card, Self.short, "\(combo.name)：设置页上没有皮肤卡")
      // 面板是推上来的：存在不等于点得着，等它落到位再点（拿中心坐标点，避开 XCUI 自己
      // 那套会抖的可点性判定）。
      XCTAssertTrue(waitUntil(timeout: Self.short) { card.isHittable }, "\(combo.name)：皮肤卡点不到")
      if (card.value as? String) != "已选" {
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      }
      let segment = app.buttons["display.mode." + combo.mode]
      expectExists(segment, Self.short, "\(combo.name)：设置页上没有深浅档")
      if !segment.isSelected { segment.tap() }
      XCTAssertTrue(waitUntil(timeout: Self.short) {
        (card.value as? String) == "已选" && segment.isSelected
      }, "\(combo.name)：选完了设置页上却没落在这一格（卡=\((card.value as? String) ?? "无值")）")
      // 选中与否是念得出来的「已选 / 未选」，不是只靠一圈描边——最大字号下尤其重要。
      XCTAssertEqual(card.value as? String, "已选", "\(combo.name)：皮肤卡的选中状态读不出来")

      leaveSettings()
      XCTAssertTrue(waitUntil(timeout: Self.short) {
        self.chartInfo()["background"] as? String == combo.background
      }, "\(combo.name)：图区底色是「\(chartInfo()["background"] as? String ?? "读不到")」，"
         + "应当是 \(combo.background)")

      // 关键控件一个都不许被大字号顶出窗口。
      for control in Self.keyControls {
        let element = app.descendants(matching: .any).matching(identifier: control.id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: Self.short),
                      "\(combo.name)：\(control.what) 不在了")
        let frame = element.frame
        XCTAssertGreaterThan(frame.width, 1, "\(combo.name)：\(control.what) 宽度塌了")
        XCTAssertGreaterThan(frame.height, 1, "\(combo.name)：\(control.what) 高度塌了")
        XCTAssertTrue(windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                      "\(combo.name)：\(control.what) 被顶出窗口了（\(frame) 不在 \(windowFrame) 里）")
      }

      // 版面不随皮肤变：图区还是那么高。
      let height = app.buttons[Ids.bottomFavorites].frame.minY
        - app.buttons[Ids.intervalMore].frame.maxY
      XCTAssertEqual(height, baseline, accuracy: 1,
                     "\(combo.name)：图区高度从 \(baseline) 变成了 \(height)")
      shot("最大字号-" + combo.name)
    }
  }

  // ------------------------------------------------------------ 最短 VoiceOver 流程

  func testTheShortestVoiceOverPathIsAllChinese() {
    // 一、起点：顶栏和底栏念出来都得是中文。
    let symbolLabel = app.symbolLabel.label
    XCTAssertTrue(symbolLabel.hasPrefix("当前品种 "), "顶栏品种名念出来是「\(symbolLabel)」")
    XCTAssertEqual(app.buttons[Ids.searchButton].label, "搜索品种",
                   "放大镜念出来是「\(app.buttons[Ids.searchButton].label)」")
    for (id, title) in [("bottom.draw", "画线"), ("bottom.chart", "图表"),
                        ("bottom.favorites", "自选"), ("bottom.sectors", "板块分类"),
                        ("bottom.settings", "设置")] {
      XCTAssertEqual(app.buttons[id].label, title,
                     "\(id) 念出来是「\(app.buttons[id].label)」，不是中文的「\(title)」")
    }

    // 二、搜 BTC，把它加进自选。星是这个动作在全 app 唯一的入口（一个动作一个入口）。
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没开出搜索页")
    let field = app.textFields[Ids.searchQuery]
    expectExists(field, Self.short, "搜索页上没有输入框")
    field.tap()
    field.typeText("BTC")
    let star = app.buttons["symbols.star.BTCUSDT"]
    expectExists(star, Self.long, "搜 BTC 没出 BTCUSDT 那一行的星")
    XCTAssertEqual(star.label, "加入自选", "还没加自选，星念出来却是「\(star.label)」")
    XCTAssertTrue(windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(star.frame),
                  "最大字号下那颗星被挤出窗口了：\(star.frame)")
    star.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { star.label == "移出自选" },
                  "点了星，念出来的动作没跟着翻成「移出自选」（现在是「\(star.label)」）")
    shot("最大字号-搜索-加入自选")
    app.buttons["search.cancel"].tap()

    // 三、去自选页把它打开。
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    let row = app.buttons["favorites.open.BTCUSDT"]
    expectExists(row, Self.long, "刚加的 BTCUSDT 没出现在自选页上")
    let group = app.buttons["favorites.group.加密"]
    expectExists(group, Self.short, "自选页上没有「加密」这条分类")
    XCTAssertTrue(group.label.contains("个品种"),
                  "分类胶囊念出来是「\(group.label)」，听不出里面有几个品种")
    let expand = app.buttons["favorites.expand.BTCUSDT"]
    expectExists(expand, Self.short, "自选行上没有展开详情的那一下")
    XCTAssertEqual(expand.label, "展开详情", "展开那一下念出来是「\(expand.label)」")
    XCTAssertEqual(expand.value as? String, "已收起", "展开状态念不出来")
    shot("最大字号-自选页")

    row.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.chartInfo()["symbol"] as? String == "BTCUSDT" },
                  "从自选点进去，图上还不是 BTCUSDT：\(chartInfo())")
    XCTAssertEqual(app.symbolLabel.label, "当前品种 BTCUSDT",
                   "到了行情页，顶栏念出来是「\(app.symbolLabel.label)」")
    shot("最大字号-自选打开-行情页")
    // 不用收尾：这一轮跑在 `KANPAN_TEST_PROFILE=1` 的隔离档案上，
    // 刚加的那条自选不会落到这台设备上用户自己那份里。
  }

  // ------------------------------------------------------------ 取证

  private func shot(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
