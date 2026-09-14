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
  static let searchButton = "top.search"
  static let starButton = "top.star"
  // 周期条
  static func intervalChip(_ raw: String) -> String { "interval.chip.\(raw)" }
  static let intervalMore = "interval.more"
  /// 常用行默认那六档（`Interval.quick`）。
  static let quickIntervals = ["1m", "5m", "15m", "1h", "4h", "1d"]
  // 底栏
  static let bottomStyle = "bottom.style"
  static let bottomIndicator = "bottom.indicator"
  static let bottomDraw = "bottom.draw"
  static let bottomSettings = "bottom.settings"
  static let bottomLandscape = "bottom.landscape"
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
    app.launch()
    // 主界面就是第一帧，没有启动页也没有弹窗（X1）；顶栏出来就算起来了。
    XCTAssertTrue(
      app.buttons[Ids.symbolButton].waitForExistence(timeout: Self.long),
      "启动后 \(Self.long)s 还没见到顶栏品种按钮")
    windowFrame = app.windows.firstMatch.frame
    chartTop = app.buttons[Ids.intervalMore].frame.maxY
    chartBottom = app.buttons[Ids.bottomStyle].frame.minY
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
      latest.tap()
      _ = waitUntil(timeout: Self.short) { !latest.isHittable }
    }
    return live
  }

  /// 把图往右推（= 往回看历史），视野离开最新一根。
  func dragChartRight() {
    let from = chartPoint(fraction: 0.45)
    let to = from.withOffset(CGVector(dx: 220, dy: 0))
    from.press(forDuration: 0.05, thenDragTo: to)
  }

  // ------------------------------------------------------------ 面板

  /// 半屏面板收起来的通用手法：抓住面板标题往下甩（标题在滚动区外面，甩它动的是面板）。
  ///
  /// 不用「再点一次底栏那颗按钮」——半屏面板正好压着底栏，那颗按钮根本点不到。
  /// 甩不动就退而求其次点一下图区（§10.6 的「面板外一点就收」），两条路都是真实交互。
  func dismissSheet(until gone: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
    let header = app.staticTexts[Ids.panelHeader].firstMatch
    if header.exists { header.swipeDown(velocity: .fast) }
    if waitUntil(timeout: 3, { !gone.exists }) { return }
    chartPoint().tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !gone.exists },
                  "面板甩不下去、点图也不收", file: file, line: line)
  }
}
