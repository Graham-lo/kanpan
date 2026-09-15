import XCTest

// ============================================================ A8.4 的公共底座
//
// 这一个 target 是整个工程里**唯一**用 XCTest 的地方：XCUIApplication 只有 XCTest 有，
// swift-testing 跑不了 UI 测试。其余所有单测（core / data / symbols / settings / diag /
// chart）一律 `import Testing`，别照着这儿的写法去改它们。
//
// 定位一律走 accessibility identifier（`Ids` 里那一张表），不按中文 label 猜、
// 不按坐标硬点。唯一用坐标的地方是 K 线图本身——它是一整块 CoreGraphics 画布，
// 没有子元素可点，所以按「周期条底边」和「底栏顶边」两个**有 identifier 的**元素
// 把图区框出来，再在框里取点（见 `chartPoint`）。

/// 界面上所有可点元素的 identifier。改界面时这张表和视图里的 `.accessibilityIdentifier`
/// 一起改，别让它们漂移。
enum Ids {
  // 顶栏
  static let symbolButton = "top.symbol"
  static let starButton = "top.star"
  /// 换品种的三个入口收敛成顶栏品种名那一个之后（第三批 15），搜索页和完整自选页
  /// 都在那个半屏弹层的头两行里。顶栏的放大镜、底栏的「自选」都没了，
  /// 用例统一走 `openSymbolSearch()` / `openFavorites()`，别再直接找那两个 id。
  static let quickSearch = "quickFavorites.search"
  static let quickAll = "quickFavorites.all"
  // 周期条
  static func intervalChip(_ raw: String) -> String { "interval.chip.\(raw)" }
  static let intervalMore = "interval.more"
  /// 常用行默认那六档（`Interval.quick`）。
  static let quickIntervals = ["1m", "5m", "15m", "1h", "4h", "1d"]
  // 底栏
  /// 底栏第三批之后是「自选 · 复盘 · 指标 · 设置」四格：没有「风格」也没有「横屏」。
  /// K 线风格搬进了周期行的「图表」面板（`interval.chart` → `CandleStylePicker`），
  /// 横屏收在「画线」上（`interval.draw` 直接横过去）。要量图区下沿就用底栏第一格。
  static let bottomFavorites = "bottom.favorites"
  static let bottomReview = "bottom.review"
  static let bottomIndicator = "bottom.indicator"
  /// 周期行右端的「图表」：K 线风格、网格、主图形态都在这张面板里。
  static let intervalChart = "interval.chart"
  static let bottomDraw = "interval.draw"
  static let bottomSettings = "bottom.settings"
  /// 横屏工具栏上的「竖屏」。以前只有 iPad 有，第三批 17 起手机也有。
  static let landscapeExit = "land.exit"
  /// 横屏顶上那行小字里的品种名：拿它当「已经横过来了」的准星。
  static let landscapeSymbol = "land.symbol"
  // 图区
  static let latestButton = "chart.latest"
  // 品种页
  static let symbolsBack = "symbols.back"
  static let symbolsQuery = "symbols.query"
  // 面板里各自的「招牌元素」：拿它在不在，判断面板开没开
  static func styleCard(_ id: String) -> String { "style.card.\(id)" }
  static func periodRow(_ raw: String) -> String { "period.row.\(raw)" }
  static func indicatorSwitch(_ raw: String) -> String { "indicator.switch.\(raw)" }
  static let settingsMagnet = "settings.magnet"
  /// 半屏面板顶上的标题。当作往下甩的把手用（它在滚动区外面，甩它动的是面板不是内容）。
  static let panelHeader = "panel.header"
  /// 每张半屏面板标题右边那颗常驻「完成」：面板唯一明确的出口。
  static let panelDone = "panel.done"
  // 画线底栏
  static let drawTrend = "draw.trend"
  static let drawHLine = "draw.hline"
  static let drawFinish = "draw.finish"
}

@MainActor
class KanpanUICase: XCTestCase {
  var app: XCUIApplication!

  /// 图区上下边与窗口框，启动后量一次存着。
  ///
  /// 不每次现量：面板一开，底下那几个控件会被系统从可及性树里遮掉，再去取 `frame`
  /// 会直接把用例判失败。竖屏这几个数在一次运行里不变。
  private(set) var chartTop: CGFloat = 0
  private(set) var chartBottom: CGFloat = 0
  private(set) var windowFrame: CGRect = .zero

  /// 等元素出现的默认上限。冷启动要等网络回第一批 K 线，给得宽一点。
  static let short: TimeInterval = 8
  static let long: TimeInterval = 30

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    app.launch()
    // 主界面就是第一帧，没有启动页也没有弹窗（X1）；顶栏出来就算起来了。
    XCTAssertTrue(
      app.buttons[Ids.symbolButton].waitForExistence(timeout: Self.long),
      "启动后 \(Self.long)s 还没见到顶栏品种按钮")
    windowFrame = app.windows.firstMatch.frame
    chartTop = app.buttons[Ids.intervalMore].frame.maxY
    chartBottom = app.buttons[Ids.bottomFavorites].frame.minY
    XCTAssertGreaterThan(chartBottom - chartTop, 100, "图区高度不到 100pt，版面不对")
  }

  override func tearDown() async throws {
    app = nil
  }

  // ------------------------------------------------------------ 等待

  @discardableResult
  func expectExists(_ el: XCUIElement, _ timeout: TimeInterval = short,
                    _ message: String = "", file: StaticString = #filePath,
                    line: UInt = #line) -> Bool {
    let ok = el.waitForExistence(timeout: timeout)
    XCTAssertTrue(ok, message.isEmpty ? "\(el) 没出现" : message, file: file, line: line)
    return ok
  }

  @discardableResult
  func expectGone(_ el: XCUIElement, _ timeout: TimeInterval = short,
                  _ message: String = "", file: StaticString = #filePath,
                  line: UInt = #line) -> Bool {
    let ok = waitUntil(timeout: timeout) { !el.exists }
    XCTAssertTrue(ok, message.isEmpty ? "\(el) 没消失" : message, file: file, line: line)
    return ok
  }

  /// 轮询一个条件。XCTNSPredicateExpectation 对 `isHittable` 这种非 KVO 属性不可靠，
  /// 所以这里老老实实自己转圈。
  func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.25,
                 _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      _ = XCTWaiter.wait(for: [XCTestExpectation(description: "poll")], timeout: poll)
    }
    return condition()
  }

  // ------------------------------------------------------------ 点击

  /// 只接受一次中心点击，不用偏移重试掩盖产品命中问题。
  @discardableResult
  func tapButton(_ el: XCUIElement, _ timeout: TimeInterval = short,
                 until settled: () -> Bool) -> Bool {
    el.tap()
    if waitUntil(timeout: timeout, settled) { return true }
    let evidence = XCTAttachment(string: "Button: \(el.debugDescription)\nChart: \(String(describing: app.otherElements["chart.canvas"].value))\n" + app.debugDescription)
    evidence.name = "单次中心命中失败"; evidence.lifetime = .keepAlways; add(evidence)
    let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
    return false
  }

  // ------------------------------------------------------------ 图区取点

  /// 图区里的一个点。`fraction` 是从图区顶边往下量的比例。
  ///
  /// x 取靠左 40pt：iPhone 上半屏面板是通栏的，靠左靠右都一样；iPad 上面板是居中的
  /// form sheet，靠左才保证落在面板外面。y 取上四分之一，保证在半屏面板的上边缘之上。
  func chartPoint(fraction: CGFloat = 0.25) -> XCUICoordinate {
    let window = app.windows.firstMatch
    let y = chartTop + (chartBottom - chartTop) * fraction
    let x = windowFrame.minX + 40
    return window.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: x - windowFrame.minX, dy: y - windowFrame.minY))
  }

  /// 等到图真的有数据、手势也活了。
  ///
  /// 没数据时 `ChartView` 整层让开（`gestureReady`），点和拖都不会有任何反应，
  /// 所以「等数据」没法靠某个静态元素判断——只能真拖一下看图认不认。
  /// 拖完视野离开最新一根，「回到最新」就会亮，拿它当信号；完事按一下回到最新，
  /// 把视野恢复原样，不给后面的用例留状态。
  @discardableResult
  func waitForLiveChart(timeout: TimeInterval = long) -> Bool {
    let latest = app.buttons[Ids.latestButton]
    let live = waitUntil(timeout: timeout, poll: 0.5) {
      if latest.isHittable { return true }
      dragChartRight()
      return latest.isHittable
    }
    if live, latest.isHittable {
      _ = tapButton(latest, Self.short) { !latest.isHittable }
    }
    return live
  }

  /// 图的实时诊断（`chart.canvas` 的无障碍 `value`，要 `KANPAN_CHART_DIAGNOSTICS=1`）。
  /// 读不到就返回空字典，别让取值本身把用例打挂。
  func chartInfo() -> [String: Any] {
    let canvas = app.otherElements["chart.canvas"]
    guard canvas.exists, let text = canvas.value as? String, let data = text.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
  }

  /// 把图往右推（= 往回看历史），视野离开最新一根。
  func dragChartRight() {
    let from = chartPoint(fraction: 0.45)
    let to = from.withOffset(CGVector(dx: 220, dy: 0))
    from.press(forDuration: 0.05, thenDragTo: to)
  }

  // ------------------------------------------------------------ 面板

  /// 半屏面板收起来的通用手法：先按标题右边那颗常驻的「完成」。
  ///
  /// 「完成」是每张面板都有的明确出口（见 `PanelSheet`），一下就收，不吃手势的脾气。
  /// 不用「再点一次底栏那颗按钮」——半屏面板正好压着底栏，那颗按钮根本点不到。
  ///
  /// 「完成」不在（横屏侧栏之类）才退回拖：抓住面板标题一路拖到屏幕底下（标题在滚动区
  /// 外面，拖它动的是面板不是内容）。为什么是「慢慢拖到底」而不是 `swipeDown(velocity:
  /// .fast)`：面板有 medium / large 两档（`presentationDetents`），一记快甩只是把它从
  /// large 摔到 medium，从 medium 甩下去还得看那一下的速度够不够——iPhone Air 上实测
  /// 甩了没反应。按住拖满一屏高是位移说话，不看速度；两档最多拖三次（large → medium → 关）。
  ///
  /// 全拖不动才退到「点图区」这条路（§10.6 的「面板外一点就收」）。这条路要图先有数据：
  /// 没数据时 `ChartView` 整层让开，那一下报不上来——所以它只能当兜底，不能当主力。
  func dismissSheet(until gone: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    if !gone.exists { return }
    let done = app.buttons[Ids.panelDone].firstMatch
    if done.exists, done.isHittable {
      done.tap()
      if waitUntil(timeout: Self.short, { !gone.exists }) { return }
    }
    let header = app.staticTexts[Ids.panelHeader].firstMatch
    let window = app.windows.firstMatch
    for _ in 0..<3 {
      if !gone.exists { return }
      // `exists` 到 `coordinate` 之间面板可能已经自己收了，那一下取快照会直接抛
      // 「No matches found」把用例打挂——所以这里拿 frame 判空，而不是让它去解析元素。
      let frame = header.exists ? header.frame : .zero
      guard frame != .zero else { break }
      let from = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
      from.press(forDuration: 0.05, thenDragTo: to)
      if waitUntil(timeout: 2, { !gone.exists }) { return }
    }
    chartPoint().tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !gone.exists },
                  "面板拖不下去、点图也不收", file: file, line: line)
  }
}

extension XCUIApplication {
  /// 顶栏品种名 →「搜索品种」→ 全屏搜索页。返回是否真的到了搜索页。
  @discardableResult func openSymbolSearch() -> Bool {
    buttons[Ids.symbolButton].tap()
    let entry = buttons[Ids.quickSearch]
    guard entry.waitForExistence(timeout: 10) else { return false }
    entry.tap()
    return textFields[Ids.symbolsQuery].waitForExistence(timeout: 10)
  }

  /// 点「画线」→ 先横过去 →  按横屏工具栏上的「竖屏」转回来，停在**竖屏画线态**。
  ///
  /// 画线入口改成「点画线直接横屏」之后，`interval.draw` 那一下已经不再留在竖屏了。
  /// 但「管理 / 吸附 / 连续」这几个快捷键只有竖屏那条画线栏上有，用例里按坐标点的
  /// 位置也都是按竖屏量的，所以这些用例统一走这个入口：横过去再转回来——这也正是
  /// 用户「横屏画完转回竖屏接着看」走的那条路，顺带把它一并验了。
  @discardableResult func enterDrawingInPortrait() -> Bool {
    buttons[Ids.bottomDraw].tap()
    let exit = buttons[Ids.landscapeExit]
    if exit.waitForExistence(timeout: 15) { exit.tap() }
    return buttons["draw.objects.quick"].waitForExistence(timeout: 15)
  }

  /// 打开选中画线的样式面板并挑一个颜色。
  ///
  /// 样式面板第二批改成了 `.fraction(0.4)` 起手的半屏（图还看得见），色板在那一截里
  /// 有可能被挡住或落在屏幕外——直接点 `color.<hex>` 会「no matches found」。
  /// 所以这里先等面板起来，色板点不到就把导航栏往上拖到 `.large` 再点。
  @discardableResult func openDrawingStyleSheet(pick hex: String) -> Bool {
    buttons["draw.style"].tap()
    guard buttons["draw.save"].waitForExistence(timeout: 8) else { return false }
    let swatch = buttons["color.\(hex)"]
    if !swatch.waitForExistence(timeout: 2) || !swatch.isHittable {
      let bar = navigationBars.element(boundBy: 0)
      if bar.exists {
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
          .press(forDuration: 0.1,
                 thenDragTo: windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
      }
      guard swatch.waitForExistence(timeout: 5) else { return false }
    }
    swatch.tap()
    return true
  }

  /// 顶栏品种名 →「全部自选与分组」→ 完整自选页。返回是否真的到了自选页。
  ///
  /// 走三轮：上一张面板的收起动画偶尔会吃掉第一下点击，顶栏品种名就白点了一次。
  /// 每轮开头先确认没有面板压在上面，有就按「完成」收掉，再点。
  @discardableResult func openFavorites() -> Bool {
    for _ in 0..<3 {
      if buttons["favorites.back"].exists { return true }
      let header = staticTexts["panel.header"]
      if header.exists {
        let done = buttons["panel.done"]
        if done.exists, done.isHittable { done.tap() }
        _ = header.waitForNonExistence(timeout: 3)
      }
      buttons[Ids.symbolButton].tap()
      let entry = buttons[Ids.quickAll]
      guard entry.waitForExistence(timeout: 10) else { continue }
      entry.tap()
      if buttons["favorites.back"].waitForExistence(timeout: 15) { return true }
    }
    return false
  }
}
