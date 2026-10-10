import UIKit
import XCTest

// ============================================================ 美元指数（macro/index/DXY）
//
// 以交易员的身份走一遍：搜「美元」→ 第一行就是「美元指数」→ 点星 → 自选页多出「指数」那一类、
// 它在里面 → 点开进图 → 顶栏五格都是「—」（指数没有持仓、市值、费率、结算、成交额，也没有估值格）
// → 头部右侧那块整块不摆（一格都给不出）、成交量副图也不画（指数没有成交量）
// → 15m / 1d 都有 K 线 → 切到 BTC 那块与成交量原样回来 → 再回美元指数
// → 图上点一根，十字线那颗「创建提醒」开出的创建页写的是美元指数。
//
// 要真网络：美元指数只有 kanpan-api 一个来源（`/v1/market/raw/*?source=macro`、
// `/v1/market/stream?source=macro`），直连、网关都打它。
//
// 截图除了进 xcresult，也直接落一份 PNG 到验收目录（文件名带机型），见 `shot`。

@MainActor
final class DollarIndexUITests: KanpanUICase {

  private let key = "macro/index/DXY"
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile]
    if name.contains("Compare") {
      // 主图 BTC，对比叠一条美元指数。
      env["KANPAN_TEST_COMPARE_SYMBOLS"] = key
      env["KANPAN_TEST_DEEPLINK"] = "hkline://symbol/binance/usd_m/BTCUSDT?interval=1h"
    }
    if name.contains("Badge") {
      // 徽章那一行：美元指数夹在两只币中间，一屏比得出它是不是一枚自己的记号。
      env["KANPAN_TEST_FAVORITES"] = "binance/usd_m/BTCUSDT,\(key),binance/usd_m/ETHUSDT"
    }
    return env
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/美元指数-2026-10-05", isDirectory: true)

  /// 机型短名：「16Pro」「17ProMax」。
  private var deviceTag: String {
    let model = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
    return model.replacingOccurrences(of: "iPhone ", with: "").replacingOccurrences(of: " ", with: "")
  }

  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot); a.name = name; a.lifetime = .keepAlways; add(a)
    let s = XCTAttachment(string: String(describing: chartInfo())); s.name = name + "-读数"; s.lifetime = .keepAlways
    add(s)
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: Self.outDir.appendingPathComponent("\(deviceTag)-\(name).png"))
  }

  private func waitChart(_ symbol: String, _ interval: String, _ seconds: TimeInterval = 45) -> Bool {
    waitUntil(timeout: seconds, poll: 0.5) {
      let d = self.chartInfo()
      return d["symbol"] as? String == symbol && d["interval"] as? String == interval
        && (d["bars"] as? Int ?? 0) >= 20 && (d["lastClose"] as? Double ?? 0) > 50
    }
  }

  /// 把搜索框里的字换成 `text`。中文走剪贴板 + 编辑菜单「粘贴」（搜索框锁的是 ASCII 键盘，
  /// 人要搜中文本来也只能粘进来）；菜单没出来再退回直接打字。
  private func enter(_ text: String, into field: XCUIElement) {
    field.tap()
    let old = (field.value as? String) ?? ""
    if !old.isEmpty, old != field.placeholderValue {
      field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
    }
    guard text.unicodeScalars.contains(where: { !$0.isASCII }) else { field.typeText(text); return }
    UIPasteboard.general.string = text
    defer { UIPasteboard.general.items = [] }
    for _ in 0..<2 {
      field.press(forDuration: 1.0)
      let paste = app.menuItems.matching(NSPredicate(format: "label IN %@", ["粘贴", "Paste"])).firstMatch
      let pasteButton = app.buttons.matching(NSPredicate(format: "label IN %@", ["粘贴", "Paste"])).firstMatch
      if paste.waitForExistence(timeout: 3) { paste.tap() } else if pasteButton.exists { pasteButton.tap() } else { continue }
      if waitUntil(timeout: 3, { (field.value as? String) == text }) { return }
    }
    field.typeText(text)
  }

  /// 搜索页上从上往下排的品种行（`symbols.row.<键>`），返回键。
  private func rowKeys() -> [String] {
    app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'symbols.row.'")).allElementsBoundByIndex
      .compactMap { el -> (String, CGFloat)? in
        guard let s = try? el.snapshot(), s.frame.height > 1 else { return nil }
        return (String(s.identifier.dropFirst("symbols.row.".count)), s.frame.minY)
      }
      .sorted { $0.1 < $1.1 }.map(\.0)
  }

  private func firstRow(is expected: String, _ what: String) {
    XCTAssertTrue(waitUntil(timeout: 20) { self.rowKeys().first == expected },
                  "\(what)：第一行不是美元指数，而是 \(rowKeys().prefix(5))")
  }

  // ------------------------------------------------------------ 主流程

  func testDollarIndexSearchFavoriteChartAndAlert() {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没进搜索页")
    let field = app.textFields[Ids.searchQuery]

    // 1. 搜「美元」：第一行是美元指数，行上写「DXY」跟一截「美元指数」。
    enter("美元", into: field)
    let row = app.buttons["symbols.row." + key]
    XCTAssertTrue(row.waitForExistence(timeout: 30), "搜「美元」没出美元指数那一行（\(field.value ?? "")）")
    firstRow(is: key, "搜「美元」")
    let name = row.staticTexts.matching(NSPredicate(format: "label CONTAINS '美元指数'")).firstMatch
    XCTAssertTrue(name.waitForExistence(timeout: Self.short),
                  "美元指数那一行没写中文名：\(row.staticTexts.allElementsBoundByIndex.map(\.label))")
    XCTAssertFalse(row.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("DXY/") },
                   "没有计价币的品种行里不该有斜杠")
    shot("搜索-美元")

    // 英文叫法也排第一：DXY、整词 USD（排在所有 xxxUSDT 前面）。
    for (query, what) in [("DXY", "搜「DXY」"), ("USD", "搜「USD」")] {
      enter(query, into: field)
      firstRow(is: key, what)
    }
    shot("搜索-USD")

    // 2. 点星：加进自选。再把词换回「美元」，点行进图。
    enter("美元", into: field)
    XCTAssertTrue(row.waitForExistence(timeout: 20))
    let star = app.buttons["symbols.star." + key]
    XCTAssertTrue(star.waitForExistence(timeout: Self.short), "美元指数那一行上没有星")
    star.tap()
    row.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { self.chartInfo()["symbol"] as? String == self.key },
                  "点美元指数那一行没进它的图：\(chartInfo())")

    // 3. 自选页：多出「指数」那一类，美元指数在里面、有价格。
    app.buttons[Ids.bottomFavorites].tap()
    let group = app.buttons["favorites.group.指数"]
    XCTAssertTrue(group.waitForExistence(timeout: Self.short), "自选页没有「指数」这一类")
    if !group.isSelected { group.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    let open = app.descendants(matching: .any).matching(identifier: "favorites.open." + key).firstMatch
    XCTAssertTrue(open.waitForExistence(timeout: Self.short), "「指数」这一类里没有美元指数")
    let price = app.descendants(matching: .any).matching(identifier: "favorites.price." + key).firstMatch
    XCTAssertTrue(waitUntil(timeout: 30) { price.exists && price.label.contains(where: \.isNumber) },
                  "自选行上美元指数没有价格：\(price.label)")
    shot("自选-指数")

    // 4. 从自选点进图：价格照常，头部右侧那块整块不摆（指数一格都给不出），成交量副图不画。
    open.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { self.chartInfo()["symbol"] as? String == self.key },
                  "从自选点美元指数没进它的图：\(chartInfo())")
    let top = app.symbolLabel.label.replacingOccurrences(of: " ", with: "")
    XCTAssertTrue(top.contains("DXY") && !top.contains("/"), "顶栏品种名不是 DXY：\(app.symbolLabel.label)")
    let lastPrice = app.descendants(matching: .any).matching(identifier: "top.lastPrice").firstMatch
    XCTAssertTrue(waitUntil(timeout: 30) { lastPrice.exists && lastPrice.label.contains(where: \.isNumber) },
                  "美元指数头部没有最新价：\(lastPrice.label)")
    assertNoStatsNoVolume("进图")

    // 5. 15m、1d 都有 K 线。
    app.tapIntervalChip("15m")
    XCTAssertTrue(waitChart(key, "15m"), "美元指数 15m 没出图：\(chartInfo())")
    assertNoStatsNoVolume("15m")
    shot("图-15m")
    app.tapIntervalChip("1d")
    XCTAssertTrue(waitChart(key, "1d"), "美元指数 1d 没出图：\(chartInfo())")
    shot("图-1d-MA")
    app.tapIntervalChip("1h")
    XCTAssertTrue(waitChart(key, "1h"), "美元指数 1h 没出图：\(chartInfo())")
    assertNoStatsNoVolume("1h")
    shot("图-1h-MA")

    // 5b. 切到 BTC：涨跌列保留、成交量副图立刻回来（指标布局跟人走，一个字没动）；再切回来。
    switchTo("BTC", "binance/usd_m/BTCUSDT")
    XCTAssertTrue(waitUntil(timeout: 30) { (self.chartInfo()["subs"] as? [String])?.contains("VOL") == true },
                  "切回 BTC 成交量副图没回来：\(chartInfo()["subs"] ?? "")")
    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "top.change").firstMatch
                    .waitForExistence(timeout: Self.short), "切回 BTC 头部右侧那块没回来")
    switchTo("DXY", key)
    XCTAssertTrue(waitChart(key, "1h"), "切回美元指数 1h 没出图：\(chartInfo())")
    assertNoStatsNoVolume("切回美元指数")

    // 6. 图上点一根 → 十字线「创建提醒」→ 创建页写的是美元指数（DXY · 美元指数 · 指数）。
    XCTAssertTrue(openNewAlertFromChart(), "十字线上的「创建提醒」没开出美元指数的创建页")
    let symbol = app.staticTexts["alerts.new.symbol"]
    XCTAssertTrue(symbol.waitForExistence(timeout: Self.short), "创建页上没有品种卡")
    XCTAssertEqual(symbol.label, "DXY", "创建页品种卡上的名字不对")
    let venue = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '美元指数'")).firstMatch
    XCTAssertTrue(venue.waitForExistence(timeout: Self.short),
                  "创建页品种卡第二行没写美元指数：\(app.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label))")
    let last = app.staticTexts["alerts.new.last"]
    XCTAssertTrue(waitUntil(timeout: 20) { last.exists && last.label != "—" && !last.label.isEmpty },
                  "创建页上美元指数没有现价")
    shot("创建提醒")
  }

  /// 主图 BTC、对比叠美元指数：对比那条到齐、图换成百分比轴。
  func testDollarIndexCompareOverBTC() {
    XCTAssertTrue(waitUntil(timeout: 90, poll: 0.5) {
      let d = self.chartInfo()
      return d["symbol"] as? String == "binance/usd_m/BTCUSDT" && d["interval"] as? String == "1h"
        && (d["bars"] as? Int ?? 0) >= 100 && (d["compareReady"] as? Int ?? 0) == 1
    }, "BTC + 美元指数对比没到齐：\(chartInfo())")
    XCTAssertEqual(chartInfo()["percentAxis"] as? Bool, true, "叠了对比却不是百分比轴")
    let chip = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'compare.chip.'")).firstMatch
    if chip.exists {
      XCTAssertTrue(chip.label.contains("DXY"), "对比胶囊上写的不是 DXY：\(chip.label)")
    }
    shot("对比-BTC-DXY")
  }

  /// 徽章那一行：三套皮肤 × 浅深，自选页里美元指数那一枚「$」各截一张。
  func testDollarIndexBadgeRowInEverySkin() {
    for (skin, tag) in [("sage", "青苔"), ("terra", "陶土"), ("classic", "经典")] {
      for mode in ["浅色", "深色"] {
        applySkin(skin, mode)
        app.buttons[Ids.bottomFavorites].tap()
        // 种子里币在前：分类条是「加密」「指数」，美元指数在第二类里，点过去再截。
        let group = app.descendants(matching: .any).matching(identifier: "favorites.group.指数").firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: Self.long), "\(tag)\(mode)：自选页没有「指数」这一类")
        if !group.isSelected { group.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        let open = app.descendants(matching: .any).matching(identifier: "favorites.open." + key).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: Self.long), "\(tag)\(mode)：自选页上没有美元指数那一行")
        shot("徽章-\(tag)\(mode == "浅色" ? "浅" : "深")")
      }
    }
  }

  // ------------------------------------------------------------ 零件

  /// 头部右侧那块（仓 / 额 · 市值 / 费率 · 结算 / 估值）整块不在；副图里没有成交量、量差，
  /// 画出来的各格里也没有成交量那一格。
  private func assertNoStatsNoVolume(_ step: String) {
    for id in ["top.stats", "top.openInterest", "top.marketCap", "top.settlement", "top.turnover",
               "top.funding", "top.valuation"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists,
                     "\(step)：美元指数头部不该有 \(id)")
    }
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      let subs = self.chartInfo()["subs"] as? [String] ?? ["?"]
      return !subs.contains("VOL") && !subs.contains("CVD")
    }, "\(step)：美元指数不该画成交量副图：\(chartInfo()["subs"] ?? "")")
    let panes = (chartInfo()["panes"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    XCTAssertFalse(panes.contains("VOL"), "\(step)：副图格子里还有成交量：\(panes)")
    let overlays = chartInfo()["overlays"] as? [String] ?? []
    XCTAssertFalse(overlays.contains("VWAP"), "\(step)：美元指数不该画 VWAP：\(overlays)")
  }

  /// 顶栏放大镜 → 搜 `query` → 点 `key` 那一行进图。
  private func switchTo(_ query: String, _ key: String) {
    XCTAssertTrue(app.openSymbolSearch(), "顶栏放大镜没进搜索页")
    enter(query, into: app.textFields[Ids.searchQuery])
    let row = app.buttons["symbols.row." + key]
    XCTAssertTrue(row.waitForExistence(timeout: 30), "搜「\(query)」没出 \(key) 那一行")
    row.tap()
    XCTAssertTrue(waitUntil(timeout: 30) { self.chartInfo()["symbol"] as? String == key },
                  "点 \(key) 那一行没进它的图：\(chartInfo())")
  }

  private func applySkin(_ skin: String, _ mode: String) {
    openSettingsPage()
    let card = app.buttons["display.theme." + skin]
    XCTAssertTrue(card.waitForExistence(timeout: Self.short), "设置页上没有皮肤卡 \(skin)")
    for _ in 0..<3 {
      if (card.value as? String) == "已选" { break }
      if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
      else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
      if waitUntil(timeout: Self.short, { (card.value as? String) == "已选" }) { break }
    }
    XCTAssertEqual(card.value as? String, "已选", "皮肤没换到 \(skin)")
    let segment = app.buttons["display.mode." + mode]
    XCTAssertTrue(segment.waitForExistence(timeout: Self.short), "设置页上没有深浅档")
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { segment.isSelected }, "深浅没落在 \(mode)")
    leaveSettings()
  }

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  /// 图上点一根：主图靠右、偏下，等十字线出来（照 `AlertsFlowUITests`）。
  private func selectACandle() -> Bool {
    let info = chartInfo()
    guard let mainH = info["mainH"] as? Double, let plotW = info["plotW"] as? Double else { return false }
    let scale = canvas.frame.height / max(1, info["height"] as? Double ?? canvas.frame.height)
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * scale * 0.8, dy: mainH * scale * 0.7)).tap()
    return waitUntil(timeout: 8) { self.chartInfo()["crosshair"] as? Bool == true }
  }

  private func openNewAlertFromChart() -> Bool {
    let price = app.textFields["alerts.new.price"]
    for _ in 0..<3 {
      if price.exists { return true }
      if chartInfo()["crosshair"] as? Bool != true, !selectACandle() { continue }
      let chip = app.buttons["chart.crosshair.alert"]
      guard chip.waitForExistence(timeout: 5) else { continue }
      chip.tap()
      if price.waitForExistence(timeout: 8) { return true }
    }
    return false
  }
}
