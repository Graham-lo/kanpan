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
  /// 左上角的品种名。2026-09-18 起它不再是按钮（半屏换品种弹层已撤），
  /// 只是一块文字，所以用例要找它得走 `symbolLabel`，不能再用 `buttons[...]`。
  static let symbolButton = "top.symbol"
  /// 顶栏放大镜：换品种唯一的入口。浏览走底栏的「自选」。
  static let searchButton = "top.search"
  /// 顶栏最左那颗返回。**只在有来路时才存在**：板块下钻点中一行品种、自选页点中一行，
  /// 人是「走进」这张图的，这颗把他原路送回去（并且原来那一页下钻到哪层还在哪层）。
  /// 从底栏直接点「图表」是回家，不是走进来，那时它不该在——冷启动更不该有。
  static let topBack = "top.back"
  /// 底栏「自选」那一格。标签栏常驻，任何一页上都点得到。
  static let favoritesTab = "bottom.favorites"
  // 周期条
  static func intervalChip(_ raw: String) -> String { "interval.chip.\(raw)" }
  static let intervalMore = "interval.more"
  /// UI 测试沙盒里铺出来的那六档（`PrefsStore.uiTestQuick`）。
  ///
  /// 出厂默认也是六档（`Interval.quick` = 5m 30m 1h 4h 1d 1w，2026-09-21 放满），
  /// 沙盒挑的这六档和它不同：1m / 15m 在里头，别的用例按 `interval.chip.1m` 才点得着。
  /// 档数一致（`Prefs.maxQuick` = 6）——「钉满时这一行还排得下」正是要验的那件事。
  /// 2026-09-21 从七档收到六档，上限一起从 10 收到 6。
  static let quickIntervals = ["1m", "5m", "15m", "30m", "1h", "4h"]
  // 底栏
  /// 2026-09-18 起底栏是一条**常驻标签栏**：从左到右「画线 · 图表 · 自选 · 板块分类 · 设置」，
  /// 五格各是一整页，切到哪一页它都还在（用户：「大部分 app 把常用的大分页都固定在底部」）。
  /// 所以不再有「复盘」「指标」两格——复盘挪进了顶栏那颗带角标的按钮（`topReview`），
  /// 指标整段并进了「图表设置」面板（`intervalChart` 开的那张）。
  /// 要量图区下沿就用标签栏任意一格，这儿沿用第一格。
  ///
  /// 第五格「板块分类」是同一天加的：加密／美股在那一页里用顶部硬切换，
  /// 不占底栏第六格（`kanpan-bottom-tab-bar`）。
  static let bottomDraw = "bottom.draw"
  static let bottomChart = "bottom.chart"
  static let bottomFavorites = "bottom.favorites"
  static let bottomSectors = "bottom.sectors"
  static let bottomSettings = "bottom.settings"
  /// 顶栏的「复盘」：右上角那颗带待办角标的按钮，开复盘本。
  static let topReview = "top.review"
  /// 周期行右端的「图表」：网格、阳线实心/空心、价格轴，外加整段指标开关，都在这张
  /// 名叫「图表设置」的面板里。面板名和标签名要分清——标签栏那一格叫「图表」，是整页。
  static let intervalChart = "interval.chart"
  /// 「画线」：标签栏最左那一格，任何一页上点它都直接在当前这张图上开画。
  static let drawEntry = "bottom.draw"
  /// 横屏工具栏上的「竖屏」。以前只有 iPad 有，第三批 17 起手机也有。
  static let landscapeExit = "land.exit"
  /// 横屏顶上那行小字里的品种名：拿它当「已经横过来了」的准星。
  static let landscapeSymbol = "land.symbol"
  // 图区
  static let latestButton = "chart.latest"
  // 品种页
  static let symbolsBack = "symbols.back"
  static let symbolsQuery = "symbols.query"
  // 搜索页。顶栏放大镜和自选页那颗放大镜开的都是它；品种整页现在只在
  // 「查看全部 N 个品种」之后才露面，所以两张页的输入框要分开记。
  static let searchQuery = "search.query"
  static let searchAll = "search.all"
  // 面板里各自的「招牌元素」：拿它在不在，判断面板开没开
  /// 「图表」面板里「阳线」那一行的某一档（实心 / 空心）。风格卡撤掉之后，拿它当这张面板的招牌元素。
  static func chartBody(_ raw: String) -> String { "chart.bodyChoice.\(raw)" }
  static func periodRow(_ raw: String) -> String { "period.row.\(raw)" }
  static func periodPin(_ raw: String) -> String { "period.pin.\(raw)" }
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

  /// 子类要给 app 额外的启动环境（比如一份自己的持久化档案）就覆写这个；
  /// 默认什么都不加，Prefs 只留在内存里。
  var extraLaunchEnvironment: [String: String] { [:] }

  /// 子类要给 app 额外的启动参数就覆写这个。
  ///
  /// 目前只有一处用它：把动态字号顶到最大
  /// （`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`，
  /// 见 `SkinScaleAccessibilityUITests`）。这是 UIKit 自己认的启动参数，不是我们的
  /// 测试开关——它在 Release 包里同样生效，所以不归 C-02 那张后门表管。
  var extraLaunchArguments: [String] { [] }

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["KANPAN_TEST_PROFILE"] = "1"
    app.launchEnvironment["KANPAN_CHART_DIAGNOSTICS"] = "1"
    for (key, value) in extraLaunchEnvironment { app.launchEnvironment[key] = value }
    app.launchArguments += extraLaunchArguments
    app.launch()
    // 冷启动可能先停在自选页（有自选就落在「自选」那一格）——那一页没有顶栏，
    // 先按标签栏上的「图表」回行情页。标签栏是常驻的，自选页上也点得到。
    let chartTab = app.buttons[Ids.bottomChart]
    if chartTab.waitForExistence(timeout: 3), !app.symbolLabel.exists { chartTab.tap() }
    // 主界面就是第一帧，没有启动页也没有弹窗（X1）；顶栏出来就算起来了。
    // 左上角的品种名 2026-09-18 起不再是按钮（点它不弹任何东西），所以这儿按
    // identifier 找元素，不能再按 `buttons[...]` 找——那样永远等不到。
    XCTAssertTrue(
      app.symbolLabel.waitForExistence(timeout: Self.long),
      "启动后 \(Self.long)s 还没见到顶栏品种名")
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

  /// 「这颗现在露在屏幕上吗」——只问一遍，而且只问快照。
  ///
  /// 这个函数是被同一颗雷炸出来的：`XCUIElement` 上几乎每个属性都会在「元素这一帧
  /// 正好走了」的时候**当场把用例判失败**，而不是老实答 false。三种说法都见过——
  /// `isHittable` 报 `Failed to determine hittability … Activation point invalid and
  /// no suggested hit points based on element frame`，`.frame` 和 `isHittable` 都报
  /// `Failed to get matching snapshot: No matches found`。`exists` 挡不住任何一种：
  /// 它答「在」之后、下一句问出去之前，那一帧里按钮可能已经走了。
  ///
  /// 「最新」这颗正是随视野进出的（`IntervalBar` 里 `if !atLatest` 整个插拔，带
  /// `.opacity` 过场），轮询时撞上那一帧的概率不低：`waitForLiveChart` 在 iPhone 上红过，
  /// iPad mini / iPad (A16) / iPad Air 11" 三台更容易红——图宽、视野归位滑得久，窗口更大。
  ///
  /// 所以**一个属性都不许再问**：`snapshot()` 是这组接口里唯一会把「没这个元素」
  /// 交成 Swift 错误的，在不在、可不可用、有没有面积、在不在屏幕上，全从同一张快照上读，
  /// 读不到就算「现在露不出来」。走了就是从树上没了，这一遍就答得出来。
  ///
  /// **它答不了遮挡。** `isHittable` 会在控件被别的视图盖住时答 false，这一层跟着没了：
  /// 一颗被半屏面板压住的按钮，在这里仍然算「露着」。所以它叫 `onScreen` 不叫 `hittable`，
  /// 别拿它去验「面板有没有盖住底栏」那类事——真要验遮挡就直接问 `isHittable`，那种地方
  /// 树是稳的（`dismissSheet` 里那一问就是），撞不上过场帧。
  ///
  /// 也别想着「拿 `try? el.isHittable` 兜一层」：`isHittable` 在头文件里是
  /// `@property (readonly, getter = isHittable) BOOL hittable`，一个不抛错的普通属性，
  /// 它判红走的是 XCTest 自己那套、不是 Swift 的 throw，`try?` 接不住（只会换来一条
  /// 「no calls to throwing functions」的警告）。
  func onScreen(_ el: XCUIElement) -> Bool {
    guard let snap = try? el.snapshot(), snap.isEnabled else { return false }
    guard snap.frame.width > 1, snap.frame.height > 1 else { return false }
    guard let window = try? app.windows.firstMatch.snapshot() else { return false }
    return window.frame.contains(CGPoint(x: snap.frame.midX, y: snap.frame.midY))
  }

  // ------------------------------------------------------------ 点击

  /// 打在同一个点上，最多两下：**不换点、不加偏移**，只是容忍 XCUI 偶尔丢一下事件。
  ///
  /// `tap` 留成可换的一手，是给滚不动的横向 `ScrollView` 里那些控件用的
  /// （周期条的药丸就是），那儿要走 `XCUIApplication.tapIntervalChip(_:)`
  /// 那样的坐标点，绕开 XCUI 自己会抖的可点性判定。默认仍是元素中心点一下。
  ///
  /// **为什么从「只接受一次中心点击」改成了两下（2026-09-18）。** 那条规矩防的是拿偏移重试
  /// 掩盖**产品的命中区问题**，这条现在仍然守着：重试打的是同一个点，一个像素都不挪，
  /// 命中区真有问题时两下照样红，失败证据也照旧存进 xcresult。改的只是对「合成事件丢了」
  /// 这一种情况的容忍度，而它是当场取证证明存在的：
  ///
  /// 全量 13 台矩阵上三个互不相干的地方各红过一次——MA 输出开关（iPhone 16 Plus / 17 Pro）、
  /// 周期条 1m 药丸（17e）、画线工具面板的入口（17e）——签名一模一样：
  /// 从 xcresult 里解出来的合成事件是干净的一对 50ms 按下/抬起，坐标正落在控件中心
  /// （药丸那次是 `(27.5, 154.3)`，控件框 `{{12, 140.3}, {31, 28}}`），
  /// 无障碍层级显示控件在、位置没变、app 也没被别的东西盖住，而 app 毫无反应。
  ///
  /// MA 开关那一处还把取证做进了 app：临时给 `Toggle` 的 setter 挂计数器跑四十轮探针，
  /// 复现到的那一次计数一动没动——**这一下压根没进 app**，丢在 XCUI「合成 → 投递」那一段，
  /// 既不是点歪了，也不是 app 收到后把状态弹了回去。（计数器没有进任何提交。）
  ///
  /// 空跑机器上复现不出来：药丸连点 160 下（50ms 与 200ms 各 80）一下没丢，
  /// 开关连点 80 下也一下没丢。只有整套 49 条跑下来才撞得到，概率量级在千分之几。
  @discardableResult
  func tapButton(_ el: XCUIElement, _ timeout: TimeInterval = short,
                 tap: (XCUIElement) -> Void = { $0.tap() },
                 until settled: () -> Bool) -> Bool {
    for attempt in 0..<2 {
      tap(el)
      if waitUntil(timeout: timeout, settled) { return true }
      if attempt == 0 {
        let lost = XCTAttachment(string: "第一下没反应，照原点再打一下：\(el.debugDescription)")
        lost.name = "疑似丢了一次合成事件"; lost.lifetime = .keepAlways; add(lost)
      }
    }
    let evidence = XCTAttachment(string: "Button: \(el.debugDescription)\nChart: \(String(describing: app.otherElements["chart.canvas"].value))\n" + app.debugDescription)
    evidence.name = "同一点打两下都没反应"; evidence.lifetime = .keepAlways; add(evidence)
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
  /// 分两步，顺序不能反。
  ///
  /// **先等数据。** 一根 K 线都还没到的时候 `ChartView` 整层让开（`gestureReady`），
  /// 拖多少下图都不认；把整份预算耗在空拖上，机器一忙就会假报「没等到行情」——
  /// 2026-09-18 实测过：`testDirectRouteGetsLiveBinanceChart` 单跑 16s 就过，
  /// 排在十几条用例后面跑就报「30s 内没等到币安的 K 线」。诊断里的 `bars`
  /// 是这件事唯一的直接答案（要 `KANPAN_CHART_DIAGNOSTICS=1`），别拿手势去猜。
  ///
  /// **再等手势。** 数据到了不等于手势活了，这一步只能真拖一下看图认不认：拖完视野
  /// 离开最新一根，「回到最新」就会亮，拿它当信号。完事按一下回到最新，把视野恢复原样，
  /// 不给后面的用例留状态。数据来得晚的时候第二步至少还留 `short` 那么久，
  /// 免得预算刚好在交界处用完、白白判一次假阴。
  @discardableResult
  func waitForLiveChart(timeout: TimeInterval = long) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    guard waitUntil(timeout: timeout, poll: 0.5, { (self.chartInfo()["bars"] as? Int ?? 0) > 0 })
    else { return false }
    let latest = app.buttons[Ids.latestButton]
    let live = waitUntil(timeout: max(Self.short, deadline.timeIntervalSinceNow), poll: 0.5) {
      if onScreen(latest) { return true }
      dragChartRight()
      return onScreen(latest)
    }
    if live, onScreen(latest) {
      _ = tapButton(latest, Self.short) { !onScreen(latest) }
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

  /// 离开设置页，回到行情页。
  ///
  /// 设置 2026-09-18 起不是半屏面板而是标签栏上的一整页：既拖不走，也没有「完成」，
  /// 离开它就是切到别的标签，所以它不能走 `dismissSheet(until:)`。
  func leaveSettings(file: StaticString = #filePath, line: UInt = #line) {
    let chartTab = app.buttons[Ids.bottomChart]
    XCTAssertTrue(chartTab.waitForExistence(timeout: Self.short), "标签栏上没有「图表」",
                  file: file, line: line)
    chartTab.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalChart].exists },
                  "点了「图表」还没回到行情页", file: file, line: line)
  }

  // ------------------------------------------------------------ 常走的两条路

  /// 标签栏 →「设置」整页。
  func openSettingsPage(file: StaticString = #filePath, line: UInt = #line) {
    let tab = app.buttons[Ids.bottomSettings]
    XCTAssertTrue(tab.waitForExistence(timeout: Self.short), "标签栏上没有「设置」",
                  file: file, line: line)
    tab.tap()
    XCTAssertTrue(app.buttons[Ids.settingsMagnet].waitForExistence(timeout: Self.short),
                  "点了「设置」没进设置整页", file: file, line: line)
  }

  /// 图表设置面板 → 均线的「参数与颜色」。指标那一段排在面板最上面，开出来就看得见。
  ///
  /// C-07（保存的不是显示的那个数）和 C.10 第 8 条（数字键盘挡不挡主动作）都要从这儿进去，
  /// 所以摆在底座上，别两个文件各抄一份。
  func openIndicatorEditor(file: StaticString = #filePath, line: UInt = #line) {
    let edit = app.buttons["indicator.edit.MA"]
    // 面板可能还开着（上一步刚从编辑器 dismiss 回来），开着就直接用。
    if !edit.exists {
      if !app.buttons[Ids.intervalChart].exists { leaveSettings(file: file, line: line) }
      let entry = app.buttons[Ids.intervalChart]
      expectExists(entry, Self.short, "周期行右端没有「图表」", file: file, line: line)
      entry.tap()
      expectExists(app.staticTexts[Ids.panelHeader], Self.short, "图表设置面板没开出来",
                   file: file, line: line)
      XCTAssertTrue(app.openIndicatorPage(), "点了「指标」没进到指标页", file: file, line: line)
      let toggle = app.buttons[Ids.indicatorSwitch("MA")]
      expectExists(toggle, Self.short, "图表设置面板里没有均线开关", file: file, line: line)
      if !edit.exists {
        toggle.tap()
        expectExists(edit, Self.short, "打开均线之后没露出「参数与颜色」", file: file, line: line)
      }
    }
    XCTAssertTrue(waitUntil(timeout: Self.short) { edit.isHittable }, "「参数与颜色」点不到",
                  file: file, line: line)
    edit.tap()
    expectExists(app.textFields["indicator.param.0.field"], Self.short, "没进到指标参数编辑器",
                 file: file, line: line)
  }
}

extension XCUIApplication {
  /// 顶栏品种名 →「搜索品种」→ 全屏搜索页。返回是否真的到了搜索页。
  /// 左上角那块品种名。它不是按钮了，但用例还要拿它的位置点顶栏。
  var symbolLabel: XCUIElement {
    descendants(matching: .any).matching(identifier: Ids.symbolButton).firstMatch
  }

  /// 周期条上钉住的那一排（`interval.quick`）。
  ///
  /// 2026-09-21 起这一排不再是横向 `ScrollView`——档数封在六个、一行全排得下，
  /// 滚动和右边那道渐隐一起删了，容器换成了一个 `children: .contain` 的无障碍容器。
  /// 所以这儿按 `otherElements` 找，不再是 `scrollViews`。
  var intervalStrip: XCUIElement { otherElements["interval.quick"] }

  /// 点一档周期。**按坐标点，不走 `XCUIElement.tap()`。**
  ///
  /// `XCUIElement.tap()` 点容器里的东西之前一定先做「滚到可见」，那一步算回来的命中点
  /// 偶尔就是 `{-1, -1}`，于是 XCUI 判它 not hittable 直接放弃——报错原文是
  /// `Computed hit point {-1, -1} after scrolling to visible`。
  ///
  /// 这是 XCUI 自己的判定抖动，不是 app 的毛病：2026-09-18 在卡住的那一刻从 app 里
  /// 对药丸中心做过跨窗口取证，`UIWindow.hitTest` 命中的正是药丸自己的容器，
  /// `accessibilityHitTest` 也落在它的无障碍节点上，键盘那层 `UITextEffectsWindow`
  /// 两种命中测试都返回 `nil`——真人的手指和 VoiceOver 的焦点从来没被挡过。
  ///
  /// 坐标点绕开可点性判定，打在药丸中心。条上没有这一档（没钉住、或者钉满六档时
  /// 它排不上）就改从「更多」网格里选同一档——十四档全在那张网格上，切档的结果一模一样。
  func tapIntervalChip(_ raw: String) {
    let chip = buttons[Ids.intervalChip(raw)]
    if chip.exists, let one = try? chip.snapshot(), one.frame.width > 1 {
      coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: one.frame.midX, dy: one.frame.midY))
        .tap()
      return
    }
    buttons[Ids.intervalMore].tap()
    let cell = buttons["period.row.\(raw)"]
    if cell.waitForExistence(timeout: 8) { cell.tap() }
  }

  /// 顶栏放大镜 → 搜索页。这一页是「我知道要找什么」那条路：打字、历史词、
  /// 最近看过，行还是品种整页那一行（`symbols.row.*` / `symbols.star.*` 通用）。
  @discardableResult func openSymbolSearch() -> Bool {
    let entry = buttons[Ids.searchButton]
    guard entry.waitForExistence(timeout: 10) else { return false }
    entry.tap()
    return textFields[Ids.searchQuery].waitForExistence(timeout: 10)
  }

  /// 搜索页 → 「查看全部 N 个品种」→ 品种整页。板块筛选、全部合约这些浏览的事
  ///
  /// 「查看全部」只有命中数超过搜索页预览的那 6 行时才露面，所以打一个精确的代号
  /// （像 SNDK）根本进不去整页。先用一个宽的词（默认 USD，几乎命中所有合约）把那一行
  /// 逼出来，进了整页再把查询词收窄成真正要找的那个。
  /// 只有整页有，搜索页不做，所以要验它们得先打个字把那一行逼出来。
  @discardableResult func openSymbolPicker(matching term: String, broad: String = "USD") -> Bool {
    guard openSymbolSearch() else { return false }
    let query = textFields[Ids.searchQuery]
    query.tap(); query.typeText(broad)
    let all = buttons[Ids.searchAll]
    guard all.waitForExistence(timeout: 10) else { return false }
    all.tap()
    let picker = textFields[Ids.symbolsQuery]
    guard picker.waitForExistence(timeout: 10) else { return false }
    guard term != broad else { return true }
    picker.tap()
    if let text = picker.value as? String, !text.isEmpty, text != picker.placeholderValue {
      picker.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
    }
    picker.typeText(term)
    return true
  }

  /// 点标签栏最左的「画线」。它对着用户当前正看的这张图开画，不再问品种
  /// （用户：「用户当前看的这张图作为画线的目标」），所以这儿就是干干净净一下。
  ///
  /// 点完先横过去（`kanpan-landscape-is-for-drawing`：横屏就是画线的工作台）。
  /// 用例里按坐标点的位置都是按竖屏量的，所以要竖屏画线态的用例走
  /// `enterDrawingInPortrait()`：横过去再按「竖屏」转回来——这也正是用户
  /// 「横屏画完转回竖屏接着看」走的那条路。
  @discardableResult func tapDrawEntry() -> Bool {
    let entry = buttons[Ids.bottomDraw]
    guard entry.waitForExistence(timeout: 10) else { return false }
    entry.tap()
    return true
  }

  /// 图表设置面板上那一行「指标」→ 同一张面板里推进去的指标页。
  /// 2026-09-23 起指标开关与参数都在这一页上，图表面板本身只留一行摘要。已经在指标页就直接认。
  @discardableResult func openIndicatorPage() -> Bool {
    let marker = buttons["indicator.switch.RSI"]
    if marker.exists { return true }
    let row = buttons["chart.indicators"]
    guard row.waitForExistence(timeout: 8) else { return false }
    row.tap()
    return marker.waitForExistence(timeout: 8)
  }

  @discardableResult func enterDrawingInPortrait() -> Bool {
    _ = tapDrawEntry()
    let exit = buttons[Ids.landscapeExit]
    if exit.waitForExistence(timeout: 15) { exit.tap() }
    // 到没到竖屏画线栏：认「完成」在场 + 横屏工具栏独有的「竖屏」不在场。
    // 2026-09-23 起「全部隐藏」收进了「更多」弹层，横竖屏都不再常驻，不能再拿它当路标。
    guard buttons["draw.finish"].waitForExistence(timeout: 15) else { return false }
    return waitUntilGone(buttons[Ids.landscapeExit], timeout: 5)
  }

  private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
    return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
  }

  /// 画线栏上的「更多」→ 那块弹层（吸附、连续画、全部隐藏、画线列表、清空）。
  /// 已经开着就直接认。
  @discardableResult func openDrawMore() -> Bool {
    let magnet = buttons["draw.magnet.quick"]
    if magnet.exists { return true }
    let more = buttons["draw.more"]
    guard more.waitForExistence(timeout: 8) else { return false }
    more.tap()
    return magnet.waitForExistence(timeout: 5)
  }

  /// 收掉「更多」弹层：点弹层外面（系统给弹层外面铺的那块 `PopoverDismissRegion`）。
  func closeDrawMore() {
    let magnet = buttons["draw.magnet.quick"]
    guard magnet.exists else { return }
    let region = otherElements["PopoverDismissRegion"].firstMatch
    if region.exists { region.tap() }
    else { windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() }
    _ = waitUntilGone(magnet, timeout: 5)
  }

  /// 「更多」→「画线列表」。返回列表开没开出来。
  @discardableResult func openDrawList() -> Bool {
    guard openDrawMore() else { return false }
    buttons["draw.objects.quick"].tap()
    return navigationBars["画线列表"].waitForExistence(timeout: 8)
      || staticTexts["画线列表"].waitForExistence(timeout: 2)
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

  /// 标签栏的「自选」→ 完整自选页。返回是否真的到了自选页。
  ///
  /// 到没到用「…」那颗菜单按钮判断——自选页上只有它，别的页都没有
  /// （返回按钮随标签栏一起撤了，页面之间的来回归标签栏管）。
  ///
  /// 走三轮：上一张面板的收起动画偶尔会吃掉第一下点击，标签就白点了一次。
  /// 每轮开头先确认没有半屏面板压在上面，有就按「完成」收掉，再点。
  @discardableResult func openFavorites() -> Bool {
    for _ in 0..<3 {
      if buttons["favorites.more"].exists { return true }
      let header = staticTexts["panel.header"]
      if header.exists {
        let done = buttons["panel.done"]
        if done.exists, done.isHittable { done.tap() }
        _ = header.waitForNonExistence(timeout: 3)
      }
      let entry = buttons[Ids.favoritesTab]
      guard entry.waitForExistence(timeout: 10) else { continue }
      entry.tap()
      if buttons["favorites.more"].waitForExistence(timeout: 15) { return true }
    }
    return false
  }
}

// ============================================================ 手动工具（审查 C.9）
//
// 有几条用例不是回归项，是**手动工具**：它们故意不隔离档案，直接往用户正式的自选存档
// 里写（`KANPAN_INSTALL_USER_FAVORITES=1` 才开），跑完手机上那份自选就被改了。
// 所以它们既不能进常规回归、也不能自动打开。
//
// 但「不跑」和「跑过了」在 xcresult 里长得太像：一条 `XCTSkipUnless` 出来的灰钩，
// 和真的通过只差一行小字。这个口子统一收在这儿——跳过时挂一张写明「未执行」的附件，
// 谁翻结果都一眼看得出这一格根本没跑，别把它算进分母。
enum ManualTool {
  /// 当前这条是不是被显式点名要跑的手动工具；不是就带着证据跳过。
  static func skipUnlessRequested(_ test: XCTestCase, what: String) throws {
    guard ProcessInfo.processInfo.environment["KANPAN_INSTALL_USER_FAVORITES"] != "1" else { return }
    let note = XCTAttachment(string:
      "未执行：\(what) 是手动工具，会写进这台设备上用户正式的自选存档。" +
      "要跑就显式给 KANPAN_INSTALL_USER_FAVORITES=1，别把它算进回归分母。")
    note.name = "手动工具-未执行"
    note.lifetime = .keepAlways
    test.add(note)
    throw XCTSkip("\(what)：手动工具，没给 KANPAN_INSTALL_USER_FAVORITES=1（未执行，不等于通过）")
  }
}
