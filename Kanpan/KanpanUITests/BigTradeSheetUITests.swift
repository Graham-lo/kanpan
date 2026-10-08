import UIKit
import XCTest

// ============================================================ 「大单与爆仓」弹层（2026-10-08）
//
// 以交易员的身份走一遍：分析面板「主力订单流 › 大单与爆仓」一开就是整页（每张卡都在、没有「展开」）
// → 点「每根」里一根（十字线跳过去、本根卡改读那一根）→「门槛」开表再取消 → ‹ 收掉。另外两条：
//   · 往下拉：标题行往下拉就关（只有一档，不再落回半屏）。
//   · 点图上的大单签：一开就是整页、读的是那一根。
// 状态图（首次打开 / 现货 / 今天没爆仓 / 数据停了）用 DEBUG 钩子 `KANPAN_TEST_BIGTRADE_STATE` 钉住。
// 截图写进 `docs/acceptance/大单与爆仓-手机-2026-10-08/iOS-*.png`。
@MainActor
final class BigTradeSheetUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_TEST_INTERVAL": "1m", "KANPAN_PERSISTENCE_PROFILE": UUID().uuidString]
    env["KANPAN_TEST_DEEPLINK"] = name.contains("Spot")
      ? "hkline://symbol/coinbase/spot/BTC-USD?interval=1m" : "hkline://symbol/BTCUSDT?interval=1m"
    if name.contains("Loading") { env["KANPAN_TEST_BIGTRADE_STATE"] = "loading" }
    if name.contains("Stale") { env["KANPAN_TEST_BIGTRADE_STATE"] = "stale" }
    if name.contains("LiqEmpty") { env["KANPAN_TEST_BIGTRADE_STATE"] = "liqEmpty" }
    // 点签那条：DEBUG 钩子往成交账里补一笔门槛以上的买单，图上必有签可点（名册不许按数据有没有来跳过）。
    if name.contains("TapSign") { env["KANPAN_TEST_BIGTRADE_SEED"] = "1" }
    return env
  }

  private static let outDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/acceptance/大单与爆仓-手机-2026-10-08", isDirectory: true)

  private func shot(_ name: String) {
    let image = app.screenshot()
    let a = XCTAttachment(screenshot: image); a.name = name; a.lifetime = .keepAlways; add(a)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? image.pngRepresentation.write(to: Self.outDir.appendingPathComponent("iOS-\(name).png"))
  }

  private func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
  private var sheet: XCUIElement { el("bigtrade.sheet") }
  private var heroTitle: XCUIElement { app.staticTexts["bigtrade.hero.title"].firstMatch }

  private func waitForBars() {
    XCTAssertTrue(waitUntil(timeout: Self.long, poll: 0.5) { (self.chartInfo()["bars"] as? Int ?? 0) >= 40 },
                  "图上的 K 线一直没到 40 根")
  }

  /// 分析面板 → 「主力订单流 › 大单与爆仓」那一行。
  private func openFromPanel() {
    waitForBars()
    XCTAssertTrue(app.openIndicatorPage(), "周期条行尾「分析」没开出分析面板")
    let row = app.buttons["orderflow.bigTrades"]
    for _ in 0..<6 where !(row.exists && row.isHittable) { app.swipeUp(velocity: .slow) }
    XCTAssertTrue(row.exists && row.isHittable, "分析面板里找不到「大单与爆仓」那一行")
    row.tap()
    expectExists(sheet, Self.long, "点了「大单与爆仓」没开出弹层")
  }

  /// 等本根卡真画出来（第一次打开有 ≤1 秒骨架）。
  private func waitForHero() {
    expectExists(el("bigtrade.hero"), Self.long, "本根卡没出来（一直是骨架）")
  }

  /// 一开就是整页：「每根」「价位」「门槛」都在，没有半屏的「展开」。
  private func expectAllCards() {
    expectExists(el("bigtrade.columns"), Self.short, "一打开没有「每根」卡")
    expectExists(el("bigtrade.ladder"), Self.short, "一打开没有「价位」卡")
    XCTAssertFalse(el("bigtrade.hint").exists, "还留着半屏的「展开」")
  }

  private func closeSheet() {
    let back = app.buttons["bigtrade.back"]
    expectExists(back, Self.short, "弹层左上角没有 ‹")
    back.tap()
    expectGone(sheet, Self.short, "点 ‹ 弹层没收掉")
  }

  // MARK: 主流程

  func testOpenFullPickBarThresholdBack() {
    openFromPanel()
    waitForHero()
    XCTAssertTrue((heroTitle.label).hasPrefix("本根"), "刚打开该读正在走那根，读的是「\(heroTitle.label)」")
    expectAllCards()
    XCTAssertGreaterThan(sheet.frame.height, windowFrame.height * 0.8, "弹层该一开就是整页")
    shot("flow-1-open")

    // 点「每根」靠右的一根：十字线落过去，本根卡改读「该根 hh:mm」。
    let chart = el("bigtrade.columns.chart")
    expectExists(chart, Self.short)
    chart.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5)).tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == true },
                  "点了「每根」里的一根，图上没出十字线")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.heroTitle.label.contains(":") },
                  "点了一根，本根卡标题还是「\(heroTitle.label)」")
    // 十字线落在一根上时右边只写周期（不再有「点图回到本根」这类说明）。
    XCTAssertEqual(el("bigtrade.hero.right").label, "1 分钟")
    shot("flow-3-pick-bar")

    // 「门槛」开那张表，取消回来弹层还在。
    app.buttons["bigtrade.threshold"].tap()
    let cancel = app.buttons["orderflow.cancel"]
    expectExists(cancel, Self.short, "点「门槛」没开出门槛表")
    shot("flow-4-threshold")
    cancel.tap()
    expectGone(cancel, Self.short, "门槛表收不掉")
    XCTAssertTrue(sheet.exists, "收了门槛表，弹层也跟着没了")

    closeSheet()
  }

  // MARK: 往下拉

  func testPullDownCloses() {
    openFromPanel()
    waitForHero()
    let title = el("bigtrade.hero")
    let top = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
    top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: windowFrame.height * 0.6)))
    expectGone(title, Self.short, "从顶上往下拉，弹层没关")
  }

  // MARK: 点签

  func testTapSignOpensFullOnThatBar() throws {
    waitForBars()
    var signs: [[String: Any]] = []
    let ok = waitUntil(timeout: Self.long, poll: 1) {
      signs = self.chartInfo()["bigTradeSigns"] as? [[String: Any]] ?? []
      return !signs.isEmpty
    }
    XCTAssertTrue(ok, "开着 KANPAN_TEST_BIGTRADE_SEED 图上也没出大单签（钩子补的那笔没走到图上）")
    guard ok else { return }
    let sign = signs.max { ($0["x"] as? Double ?? 0) < ($1["x"] as? Double ?? 0) }!
    let canvas = app.otherElements["chart.canvas"]
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: sign["x"] as? Double ?? 0, dy: sign["y"] as? Double ?? 0)).tap()
    expectExists(sheet, Self.short, "点了大单签没开弹层")
    waitForHero()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.heroTitle.label.contains(":") || self.heroTitle.label.hasPrefix("本根") })
    expectAllCards()
    shot("flow-0-sign-tap")
    closeSheet()
  }

  // MARK: 三套皮肤 × 深浅

  private func pickSkin(_ skin: String, _ mode: String) {
    openSettingsPage()
    let card = app.buttons["display.theme." + skin]
    expectExists(card, Self.short, "设置页上没有皮肤卡 \(skin)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { card.isHittable }, "皮肤卡点不到")
    if (card.value as? String) != "已选" { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    let segment = app.buttons["display.mode." + mode]
    expectExists(segment, Self.short, "设置页上没有深浅档")
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { (card.value as? String) == "已选" && segment.isSelected })
    leaveSettings()
  }

  func testSkins() {
    for (skin, mode, file) in [("sage", "浅色", "sage-light"), ("sage", "深色", "sage-dark"),
                               ("terra", "浅色", "terra-light"), ("terra", "深色", "terra-dark"),
                               ("classic", "浅色", "classic-light"), ("classic", "深色", "classic-dark")] {
      pickSkin(skin, mode)
      openFromPanel()
      waitForHero()
      // 爆仓第一次取回来要一下：等它从骨架换成数（取不到时那张卡整张不出，也不再等）。
      _ = waitUntil(timeout: 5) { !self.el("bigtrade.liq").exists || self.el("bigtrade.liqmax").exists || self.el("bigtrade.liq.empty").exists || self.app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "今日最大")).count > 0 }
      shot(file)
      el("bigtrade.ladder").swipeUp(velocity: .slow)
      shot("\(file)-bottom")
      closeSheet()
    }
  }

  // MARK: 状态

  func testStateLoading() {
    openFromPanel()
    expectExists(el("bigtrade.skeleton"), Self.short, "钉在「第一次打开」却没有骨架")
    shot("state-first-open")
    closeSheet()
  }

  func testStateSpot() {
    waitForBars()
    XCTAssertTrue((chartInfo()["symbol"] as? String ?? "").contains("coinbase"), "深链没落到 Coinbase 现货")
    openFromPanel()
    waitForHero()
    XCTAssertTrue(el("bigtrade.subtitle").label.contains("现货"), "现货的副标题没写「现货」：\(el("bigtrade.subtitle").label)")
    XCTAssertFalse(el("bigtrade.liq").exists, "现货不该有爆仓卡")
    expectAllCards()
    XCTAssertFalse(el("bigtrade.liq24").exists, "现货不该有 24 小时爆仓")
    shot("state-spot")
    closeSheet()
  }

  func testStateLiqEmpty() {
    openFromPanel()
    waitForHero()
    let empty = el("bigtrade.liq.empty")
    expectExists(empty, Self.short, "钉在「今天没爆仓」却没出空态")
    XCTAssertEqual(empty.label, "今日无爆仓", "空态只留一句，不带说明")
    shot("state-no-liq")
    closeSheet()
  }

  func testStateStale() {
    openFromPanel()
    waitForHero()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.el("bigtrade.hero.right").label.hasPrefix("数据停于 ") },
                  "钉在「数据停了」标题右边却是「\(el("bigtrade.hero.right").label)」")
    shot("state-stale")
    closeSheet()
  }
}
