import XCTest

// ============================================================ 语义色整改的四处取证
//
// 2026-09-22 那一轮视觉/语义色整改（HEAD `de1ac11`）留了四处「够不着」的地方：
// 上一轮的取证要么拍不到那个状态，要么拍到的是另一条分支。这个文件专门把这四处
// **摆到镜头前**，截图 + 打印几何，判读留给人，用例自己**不下颜色结论**——
// 屏幕上的像素只有截图说了算，XCUITest 读不到任何一个色值。
//
// 所以这里的断言只管一件事：**那个状态真的摆出来了**（删除块露出来了、自选段在场、
// 找相似那张表开着、侧栏开着）。摆不出来就红，摆出来了就把图和几何交出去。
//
// ------------------------------------------------------------ 四件事
//
// 1. **左滑「删除」的字色**（`DrawingBar.swift` 的 `.swipeActions`）。
//    SwiftUI 的 `swipeActions` 会不会无视 label 上的 `foregroundStyle`、按
//    `UIContextualAction` 的老规矩把文字强行画成白色？这是这一轮「字给 `badgeInk`」
//    那个修法到底成不成立的关键。`AlertListPage` 那个**手搓的**删除块（不是
//    `swipeActions`，是自己 ZStack + DragGesture 画的）作对照——它理论上一定生效。
// 2. **`SymbolPickerView` 自选段在拖拽分支开着时的行特征**。
//    `FavoriteDragModifier` 是 `_ConditionalContent`，排在 `.listRowBackground` /
//    `.listRowSeparatorTint` **后面**，和 `b804408` 那个回归同型（那次是
//    `.onGeometryChange` 把行特征挡在了 List 外面，每行冒出白底加半截系统分隔线）。
//    上一轮只拍到 `enabled == false` 那条分支；`enabled == true` 才是带
//    `.draggable` / `.dropDestination` 的那条。
// 3. **复盘「找相似」那张 sheet**（`ReviewSearchView`）。只从取景卡的「找相似」出来。
// 4. **横屏画线台的侧栏遮罩**（`SidePanelLayer` 里写死的 `Color.black.opacity(0.18)`）。
//    它不跟皮肤走，要的是它压在青苔夜底上的实际数值。侧栏开着与收着各一张，
//    同一坐标前后对照——整屏都被这层盖住，同一张图里找不到「没被盖住的可比区域」。
//
// ------------------------------------------------------------ 图往哪儿落
//
// 两份：一份 `XCTAttachment` 进 xcresult（失败时好回看），一份 PNG 直接写进
// `docs/acceptance/兼容-2026-09-22/`。模拟器进程和 xcodebuild 跑在同一个文件系统上，
// 写绝对路径就是写到仓库里（`AlertsFlowUITests` 写 `/tmp/kanpan-c` 同一个道理）。
//
// 几何用 `print` 打到测试输出里，前缀 `取证|`，人拿它换算像素坐标去采样。
// 单位是**点**，截图是**像素**：比例 = 图宽 / 窗口宽（iPhone 15 是 3）。
@MainActor
final class SemanticColorEvidenceUITests: KanpanUICase {

  /// 一条用例一棵干净的档案树。
  private let profile = UUID().uuidString

  override var extraLaunchEnvironment: [String: String] {
    var env = ["KANPAN_PERSISTENCE_PROFILE": profile]
    // 提醒总表那条要开局就有一条提醒，不然表是空的、没有行可以左滑。
    // `AlertStore.testSeed` 只在 DEBUG 下编，摆的是「服务端判到价之后同步换下来的那一份」。
    if name.contains("AlertList") { env["KANPAN_TEST_ALERT_FIRED"] = "BTCUSDT" }
    // 自选段要在场，得先有自选。
    if name.contains("FavoriteSection") { env["KANPAN_TEST_FAVORITES"] = "BTCUSDT,ETHUSDT,SOLUSDT" }
    return env
  }

  /// 图落在这儿。和上一轮兼容性取证同一个目录、同一套命名（`iPhone15-…-青苔深.png`）。
  private static let outDir = URL(
    fileURLWithPath: "/Users/mdd/zhk/kanpan/docs/acceptance/兼容-2026-09-22", isDirectory: true)

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  override func tearDown() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.tearDown()
  }

  // ------------------------------------------------------------ 取证小工具

  /// 一行证据：既打到测试输出里（人 grep `取证|` 拿走），也挂一张附件进 xcresult。
  private func note(_ line: String) {
    print("取证|" + line)
    let a = XCTAttachment(string: line)
    a.name = "取证"
    a.lifetime = .keepAlways
    add(a)
  }

  /// **主图**里的一个点（y 按 `mainH` 折算）。
  ///
  /// `KanpanUICase.chartPoint` 量的是「周期条底边到标签栏顶边」这一整段，副图三格
  /// （VOL / OI / MACD）也在里头。而画线只认主图那一段：`ChartView+Drawing` 里
  /// 落笔和取消选中都先判 `axes.bounds.contains(startPoint)`，打在副图上等于没打——
  /// 2026-09-22 就是踩着这个卡住的（点了四下副图，选中栏一直没让开）。
  private func mainChartPoint(_ fraction: CGFloat) -> XCUICoordinate {
    let canvas = app.otherElements["chart.canvas"]
    let frame = canvas.frame
    let reported = CGFloat((chartInfo()["height"] as? Double) ?? Double(frame.height))
    let mainH = CGFloat((chartInfo()["mainH"] as? Double) ?? Double(frame.height))
    let scale = reported > 1 ? frame.height / reported : 1
    return canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: frame.width * 0.35, dy: mainH * scale * fraction))
  }

  /// 一个元素的 frame，单位点。采样坐标靠它换算。
  private func geometry(_ what: String, _ frame: CGRect) {
    note(String(format: "几何|%@|x=%.2f|y=%.2f|w=%.2f|h=%.2f",
                what, frame.minX, frame.minY, frame.width, frame.height))
  }

  /// 「这颗现在有 frame 吗」——一个属性都不问，只问快照。
  ///
  /// `XCUIElement.exists` 在**查询本身匹配不到**的时候不会老实答 false，会当场把用例
  /// 判失败（`Failed to get matching snapshot: No matches found for first query match
  /// sequence`）——`delete.staticTexts.firstMatch` 这种「按钮里有没有子文字」的探询
  /// 正好每次都踩到（swipeAction 的按钮是叶子，里头根本没有 StaticText 节点）。
  /// 所以这一类「有就记一笔、没有就算了」的探询一律走这里。
  private func snapshotFrame(_ el: XCUIElement) -> CGRect? {
    guard let snap = try? el.snapshot(), snap.frame.width > 1, snap.frame.height > 1
    else { return nil }
    return snap.frame
  }

  /// 截一张：进 xcresult，也落一份 PNG 到验收目录。
  ///
  /// 顺手把这一张的窗口尺寸也打出来——同一条用例里横竖屏会换，比例得按当时那一帧算。
  private func shot(_ name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let a = XCTAttachment(screenshot: screenshot)
    a.name = name
    a.lifetime = .keepAlways
    add(a)
    let window = app.windows.firstMatch.frame
    note("图|\(name)|窗口 \(window.width)x\(window.height) 点")
    try? FileManager.default.createDirectory(at: Self.outDir, withIntermediateDirectories: true)
    let url = Self.outDir.appendingPathComponent(name + ".png")
    do { try screenshot.pngRepresentation.write(to: url) }
    catch { note("落盘失败|\(name)|\(error)") }
  }

  /// 换到「青苔·深」，并且确认真的换过去了。
  ///
  /// 只 `tap()` 一下不够：皮肤卡排在一张会重排的网格上，坐标兜底那一下有时候打在
  /// 隔壁格子里（`AlertsFlowUITests.selectSkin` 那段的教训）。按 `value == "已选"` 复核。
  private func applySkin(_ skin: String, _ mode: String, _ what: String,
                         file: StaticString = #filePath, line: UInt = #line) {
    openSettingsPage(file: file, line: line)
    let card = app.buttons["display.theme." + skin]
    guard expectExists(card, Self.short, "\(what)：设置页上没有皮肤卡", file: file, line: line)
    else { return }
    for _ in 0..<3 {
      if (card.value as? String) == "已选" { break }
      if waitUntil(timeout: Self.short, { card.isHittable }) { card.tap() }
      else { card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
      if waitUntil(timeout: Self.short, { (card.value as? String) == "已选" }) { break }
    }
    XCTAssertEqual(card.value as? String, "已选", "\(what)：皮肤没换到 \(skin)", file: file, line: line)
    let segment = app.buttons["display.mode." + mode]
    guard expectExists(segment, Self.short, "\(what)：设置页上没有深浅档", file: file, line: line)
    else { return }
    if !segment.isSelected { segment.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { segment.isSelected },
                  "\(what)：深浅没落在 \(mode)", file: file, line: line)
    leaveSettings(file: file, line: line)
  }

  private func applySageNight(_ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
    applySkin("sage", "深色", what, file: file, line: line)
    // 图区底色是「换过去了」唯一的硬证据（`sageNightSeed.chart`）。
    XCTAssertTrue(waitUntil(timeout: Self.short) {
      self.chartInfo()["background"] as? String == "#0B120F"
    }, "\(what)：图区底色是「\(chartInfo()["background"] as? String ?? "读不到")」，不是青苔夜的 #0B120F",
       file: file, line: line)
  }

  // ============================================================ 一、左滑「删除」

  /// 画线管理列表的左滑「删除」：`swipeActions` 里的 `Text("删除").foregroundStyle(theme.badgeInk)`，
  /// 外面 `.tint(theme.danger)`。
  ///
  /// 要拍的就是这一块露出来的样子——**不删**，滑出来截完再滑回去。
  /// 青苔夜下 `badgeInk` = `ground` = `#060A08`，`danger` = `#F08A80`：
  /// 字笔画中心采到接近 `#060A08` 说明 `foregroundStyle` 生效，接近 `#FFFFFF`
  /// 说明被系统按 `UIContextualAction` 的老规矩强制成白的。
  func testSwipeDeleteInkInDrawingManager() throws {
    applySageNight("画线管理左滑")
    XCTAssertTrue(waitForLiveChart(), "没等到行情：\(chartInfo())")
    XCTAssertTrue(app.enterDrawingInPortrait(), "没能进入竖屏画线态")

    // 落一笔水平线（一下就成），管理表里才有行可以滑。
    let hline = app.buttons[Ids.drawHLine]
    expectExists(hline, Self.short, "画线栏上没有水平线")
    hline.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    mainChartPoint(0.25).tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["drawingCount"] as? Int ?? 0) >= 1 },
                  "水平线没落上：\(chartInfo())")
    // 画完那一句问话只活 6 秒，顺手收掉，别让它占着头部影响这一屏。
    let dismissPrompt = app.buttons["alert.prompt.dismiss"]
    if dismissPrompt.waitForExistence(timeout: 3) { dismissPrompt.tap() }

    // 选中之后上排左半边换成 `DrawingSelectionBar`，三个开关连同「管理」一起暂时
    // 不在树上——点一下图上的空白处取消选中，「管理」才回来（同
    // `ChartFoundationUITests` 里「取消选中之后开关那排没回来」那一段）。
    //
    // 而且要打在**主图**里：`axes.bounds` 之外的那一下（副图三格）连判都不判。
    // 第一下常常只是收掉十字线（`busy` 那条早退），所以最多打四下。
    let manage = app.buttons["draw.objects.quick"]
    for _ in 0..<4 where !manage.exists {
      mainChartPoint(0.8).tap()
      _ = waitUntil(timeout: 3) { manage.exists }
    }
    XCTAssertTrue(manage.exists, "画线栏上没有「管理」：\(app.debugDescription)")
    manage.tap()

    let ids = try XCTUnwrap(chartInfo()["drawingIDs"] as? [String], "读不到画线 id：\(chartInfo())")
    let first = try XCTUnwrap(ids.first)
    let row = app.buttons["draw.object.\(first)"]
    expectExists(row, Self.long, "画线管理表里没有那一行")
    shot("iPhone15-左滑删除-画线管理-滑之前-青苔深")

    // 左滑把删除块滑出来。先走 `swipeLeft()`（系统 List 认这一下），不成再自己按住拖。
    let delete = app.buttons["删除"]
    let cell = app.cells.containing(.button, identifier: "draw.object.\(first)").firstMatch
    for round in 0..<3 {
      if delete.exists, delete.frame.width > 1 { break }
      if round == 0, cell.exists { cell.swipeLeft() }
      else {
        let target = cell.exists ? cell : row
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
          .press(forDuration: 0.06,
                 thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)),
                 withVelocity: .slow, thenHoldForDuration: 0.2)
      }
      _ = waitUntil(timeout: 3) { delete.exists && delete.frame.width > 1 }
    }
    XCTAssertTrue(delete.exists && delete.frame.width > 1,
                  "左滑没把删除块滑出来：\(app.debugDescription)")

    geometry("画线管理-行", row.frame)
    geometry("画线管理-删除块", delete.frame)
    // 块里那行字自己的 frame（有的话）。swipeAction 的按钮是叶子节点，多半没有。
    if let label = snapshotFrame(delete.staticTexts.firstMatch) { geometry("画线管理-删除二字", label) }
    // 画线数得在截图前后都是 1：这一趟一条都不许真删掉。
    XCTAssertEqual(chartInfo()["drawingCount"] as? Int, ids.count, "还没截图线就少了")
    shot("iPhone15-左滑删除-画线管理-青苔深")

    // 滑回去，**不触发删除**。
    if cell.exists { cell.swipeRight() }
    _ = waitUntil(timeout: 3) { !delete.exists }
    XCTAssertEqual(chartInfo()["drawingCount"] as? Int, ids.count,
                   "这一趟只是滑出来看一眼，线却被删了：\(chartInfo())")
    XCTAssertEqual(chartInfo()["drawingIDs"] as? [String], ids, "线换了一批，说明删过又画过")
  }

  /// 对照组：`AlertListPage` 那个**手搓的** SwiftUI 删除块。
  ///
  /// 它不是 `swipeActions`——自己 ZStack 摆一个 `Button`，`Text("删除")
  /// .foregroundStyle(t.badgeInk).background(t.danger)`，位移靠 `DragGesture` 自己算。
  /// 系统那套 `UIContextualAction` 的规矩碰不到它，所以理论上 `badgeInk` 一定生效。
  /// 拍它是为了给上一条一个**同屏同皮肤**的参照：两块砖的字色如果不一样，
  /// 差别只可能来自 `swipeActions` 本身。
  func testSwipeDeleteInkInAlertList() throws {
    applySageNight("提醒总表左滑")

    let settingsTab = app.buttons[Ids.bottomSettings]
    expectExists(settingsTab, Self.short, "标签栏上没有「设置」")
    settingsTab.tap()
    let entry = app.descendants(matching: .any).matching(identifier: "settings.alerts").firstMatch
    expectExists(entry, Self.long, "设置里没有「提醒」这一行")
    XCTAssertTrue(waitUntil(timeout: Self.short) { entry.frame.height > 1 }, "「提醒」那一行量不出 frame")
    entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    let page = app.descendants(matching: .any).matching(identifier: "alerts.page").firstMatch
    expectExists(page, Self.long, "「提醒」没开出总表")

    // 「这一行还在不在」的准星用**行名那行字**（「BTC · 水平线」），
    // 既不用「再次提醒」也不用「删除」：
    // - 「再次提醒」只在 `status == .fired` 时才在（`AlertListPage.swift:179`）。
    //   第一版拿它当准星，起手点正压在那颗胶囊上，那一下把提醒重新上了膛、
    //   它自己换成「触碰时 ⌄」，被误判成「行被删了」。
    // - 「删除」那块砖虽然恒在 `ZStack` 里，但没划开时 `opacity` 是 0，
    //   SwiftUI 把它整个从无障碍树里摘掉了——第二版拿它数行数，划之前就找不到。
    // 行名那行字两种状态都在，而且划开之后只是被推走（`.clipped()` 截掉一截），
    // 在树里照样在。
    let rowAnchor = app.staticTexts
      .matching(NSPredicate(format: "label CONTAINS %@", "水平线")).firstMatch
    expectExists(rowAnchor, Self.long, "种下的那条提醒没出现在总表里：\(app.debugDescription)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { rowAnchor.frame.height > 1 }, "那一行量不出 frame")
    let rowBand = rowAnchor.frame
    shot("iPhone15-左滑删除-提醒总表-滑之前-青苔深")

    // 手搓的那一下：`DragGesture(minimumDistance: 12)`，横向位移超过 36pt 才吸附到位。
    // 按住慢拖，别用 `swipeLeft()`——那是一记快甩，位移不够就弹回去了。
    //
    // 起手点按顺序试三个，哪个划出来了就停：
    // 1. 行右侧、「再次提醒」胶囊**下面**一点——划得动，又按不到那颗胶囊；
    // 2. 胶囊正中（第一版用的点，实测一定划得动）——代价是那一下把提醒重新上了膛，
    //    行右边从「再次提醒」变成「触碰时 ⌄」；不影响这一趟要量的删除块；
    // 3. 行左半边的文字区 x = 200——实测划不动（`DragGesture` 没起来），兜底用。
    let rearm = app.buttons["再次提醒"]
    let capsule = snapshotFrame(rearm) ?? rowBand
    let starts: [CGPoint] = [
      CGPoint(x: capsule.maxX - 16, y: capsule.maxY + 12),
      CGPoint(x: capsule.maxX - 16, y: capsule.midY),
      CGPoint(x: 200, y: rowBand.midY),
    ]
    let delete = app.buttons["删除"].firstMatch
    for start in starts {
      if delete.exists, delete.frame.width > 1 { break }
      let window = app.windows.firstMatch
      let from = window.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: start.x, dy: start.y))
      let to = window.coordinate(withNormalizedOffset: .zero)
        .withOffset(CGVector(dx: start.x - 120, dy: start.y))
      from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
      _ = waitUntil(timeout: 2) { delete.exists && delete.frame.width > 1 }
      note("提醒总表左滑起手点 (\(Int(start.x)), \(Int(start.y)))：删除块"
           + (delete.exists && delete.frame.width > 1 ? "出来了" : "没出来"))
    }
    XCTAssertTrue(delete.exists && delete.frame.width > 1,
                  "左滑没把删除块滑出来：\(app.debugDescription)")
    geometry("提醒总表-行名", rowBand)
    geometry("提醒总表-行名（划开后）", rowAnchor.frame)
    geometry("提醒总表-删除块", delete.frame)
    if let label = snapshotFrame(delete.staticTexts.firstMatch) { geometry("提醒总表-删除二字", label) }
    shot("iPhone15-左滑删除-提醒总表-青苔深")

    // 这一趟只是滑出来看一眼，不删：块露着的时候那一行还在（只是被推走了 76pt）。
    XCTAssertTrue(rowAnchor.exists, "滑出删除块的同时那一行没了，多半是被删了")

    // 再从头走一遍验「真的没删」：收掉总表、重新开出来，那条提醒还在。
    //
    // **不往回拖**。手搓那一层的行本身是个 `Button`（点它跳到那张图），往回拖那一下
    // 会被当成一次点击，整张表连着被收掉、人被送去行情页——第一版就是这么误判成
    // 「被删了」的。收了再开是同样的证明，而且不碰任何手势的脾气。
    let done = app.buttons[Ids.panelDone]
    if done.exists, done.isHittable { done.tap() }
    XCTAssertTrue(waitUntil(timeout: Self.short) { !page.exists }, "提醒总表收不掉")
    XCTAssertTrue(waitUntil(timeout: Self.short) { entry.frame.height > 1 }, "「提醒」那一行量不出 frame")
    entry.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    expectExists(page, Self.long, "提醒总表第二次开不出来")
    XCTAssertTrue(rowAnchor.waitForExistence(timeout: Self.long),
                  "重新开总表那条提醒不见了，这一趟把它删掉了")
  }

  // ============================================================ 二、自选段的行特征

  /// 品种整页、搜索框为空、自选段在场——也就是 `FavoriteDragModifier(enabled: true)`
  /// 那条分支（`.draggable` + `.dropDestination` 都挂上了）。
  ///
  /// 上一轮拍到的是 `enabled == false`（搜索有词、自选段不出现），行背景正常；
  /// 真正有风险的是这一条：`_ConditionalContent` 排在 `.listRowBackground` /
  /// `.listRowSeparatorTint` 后面，和 `b804408` 那个回归同型。
  ///
  /// 上一轮在 `enabled == false` 时量到的基准：行内背景与表外空白同为 `#0D111C`，
  /// 分隔线 `#161A25`、横向 x 177–1130（图宽 1178）。那是**经典·深**的数，所以这儿
  /// 青苔深、经典深各拍一张，后者能和基准直接对账。
  func testFavoriteSectionRowTraitsWithDragEnabled() throws {
    for (skin, mode, tag) in [("sage", "深色", "青苔深"), ("classic", "深色", "经典深")] {
      applySkin(skin, mode, "自选段-" + tag)
      XCTAssertTrue(openFullSymbolPageWithEmptyQuery(), "\(tag)：没能把品种整页开成空搜索")

      // 自选段真的在场：段头那两个字 + 段里那几行。
      expectExists(app.staticTexts["自选"], Self.long, "\(tag)：品种整页上没有「自选」这一段")
      let row = app.buttons["symbols.row.BTCUSDT"]
      expectExists(row, Self.long, "\(tag)：自选段里没有 BTCUSDT 那一行")
      let second = app.buttons["symbols.row.ETHUSDT"]
      expectExists(second, Self.long, "\(tag)：自选段里没有 ETHUSDT 那一行")
      // 搜索框确实是空的——不空的话拍到的还是 `enabled == false` 那条分支。
      let query = app.textFields[Ids.symbolsQuery]
      let text = (query.value as? String) ?? ""
      XCTAssertTrue(text.isEmpty || text == query.placeholderValue,
                    "\(tag)：搜索框里还留着「\(text)」，这一屏不是自选段那条分支")

      geometry("自选段-\(tag)-窗口", app.windows.firstMatch.frame)
      geometry("自选段-\(tag)-BTCUSDT 行", row.frame)
      geometry("自选段-\(tag)-ETHUSDT 行", second.frame)
      geometry("自选段-\(tag)-段头「自选」", app.staticTexts["自选"].frame)
      geometry("自选段-\(tag)-搜索框", query.frame)
      shot("iPhone15-品种整页-自选段可拖拽-" + tag)

      // 回行情页，换下一套皮肤。
      let back = app.buttons[Ids.symbolsBack]
      if back.exists { back.tap() }
      let cancel = app.buttons["search.cancel"]
      if cancel.waitForExistence(timeout: Self.short) { cancel.tap() }
      XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChart].exists },
                    "\(tag)：退不回行情页")
    }
  }

  /// 顶栏放大镜 → 打个宽词把「查看全部」逼出来 → 进品种整页 → 把搜索框清空。
  ///
  /// 「查看全部 N 个品种」只有命中数超过搜索页那 6 行预览时才露面，所以进整页这一趟
  /// 绕不开先打个字（`openSymbolPicker` 同一个道理）；进去之后**必须清空**，
  /// 不然自选段根本不出现（`SymbolSections.build` 里 query 非空就只剩搜索结果段）。
  private func openFullSymbolPageWithEmptyQuery() -> Bool {
    guard app.openSymbolSearch() else { return false }
    let search = app.textFields[Ids.searchQuery]
    search.tap()
    search.typeText("USD")
    let all = app.buttons[Ids.searchAll]
    guard all.waitForExistence(timeout: Self.long) else { return false }
    all.tap()
    let query = app.textFields[Ids.symbolsQuery]
    guard query.waitForExistence(timeout: Self.long) else { return false }
    let clear = app.buttons["清空"]
    if clear.exists, clear.isHittable {
      clear.tap()
    } else {
      query.tap()
      if let text = query.value as? String, !text.isEmpty, text != query.placeholderValue {
        query.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count))
      }
    }
    return waitUntil(timeout: Self.long) {
      let text = (query.value as? String) ?? ""
      return text.isEmpty || text == query.placeholderValue
    }
  }

  // ============================================================ 三、复盘「找相似」

  /// `ReviewSearchView` 只从取景卡的「找相似」出来（`ReviewCaptureCard` 的
  /// `.sheet(isPresented: $feature.searchOpen)`）。
  ///
  /// 取景卡默认框的就是 49 根（`ReviewChartBridge.beginCapture` 里 `left = right - 48`），
  /// 早过了 `ReviewFeature.search` 那道「至少 16 根」的门槛，所以不必再手动拖框选——
  /// 拖一遍反而会把默认那 49 根改小、把这条用例的前提搞乱。
  /// 没登录也开得出来，只是里头是「登录后可用」那张空状态。
  func testReviewSimilarSearchSheet() throws {
    applySageNight("找相似")
    XCTAssertTrue(waitForLiveChart(), "没等到行情：\(chartInfo())")

    let entry = app.buttons[Ids.intervalChart]
    expectExists(entry, Self.short, "周期行右端没有「图表」")
    entry.tap()
    let record = app.buttons["chart.record"]
    expectExists(record, Self.short, "「图表」面板里没有「记一笔」")
    record.tap()
    let similar = app.buttons["找相似"]
    expectExists(similar, Self.long, "点「记一笔」没开出取景卡")
    shot("iPhone15-复盘取景卡-青苔深")
    similar.tap()

    let back = app.buttons["review.search.back"]
    expectExists(back, Self.long, "点「找相似」没开出那张表：\(app.debugDescription)")
    // 导航栏标题就叫「找相似」。
    expectExists(app.staticTexts["找相似"], Self.short, "那张表上没有「找相似」这个标题")
    let bar = app.navigationBars.firstMatch
    if bar.exists { geometry("找相似-导航栏", bar.frame) }
    geometry("找相似-窗口", app.windows.firstMatch.frame)
    geometry("找相似-返回", back.frame)
    let picker = app.segmentedControls.firstMatch
    if picker.exists { geometry("找相似-范围切换", picker.frame) }
    // 没登录时表身是「登录后可用」那张空状态（`!feature.isConnected` 那条分支）。
    let login = app.buttons["review.search.login"]
    note("状态|找相似|登录按钮在场=\(login.exists)")
    if login.exists { geometry("找相似-登录按钮", login.frame) }
    shot("iPhone15-复盘找相似-青苔深")

    back.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !back.exists }, "那张表收不回去")
  }

  // ============================================================ 四、横屏侧栏遮罩

  /// 横屏画线台，侧栏**开着**。
  ///
  /// 遮罩是 `SidePanelLayer` 里写死的 `Color.black.opacity(0.18)`，`.ignoresSafeArea()`——
  /// 它盖满整屏，所以同一张图里找不到「没被盖住的可比区域」。对照只能是**同一坐标的
  /// 前后两张**：侧栏收着一张、开着一张，一个像素都不挪。
  ///
  /// 横屏下能把侧栏推出来的只有周期栏底下那颗「更多周期」（`MainScreen` 里
  /// `onMore: { panel = .period }` 是横屏唯一给 `panel` 赋值的地方）。
  func testLandscapeSidePanelScrim() throws {
    applySageNight("横屏侧栏遮罩")
    XCTAssertTrue(waitForLiveChart(), "没等到行情：\(chartInfo())")

    // 点「画线」直接横过来（`kanpan-landscape-is-for-drawing`）。
    XCTAssertTrue(app.tapDrawEntry(), "标签栏上没有「画线」")
    let exit = app.buttons[Ids.landscapeExit]
    expectExists(exit, Self.long, "点「画线」没横过来")
    let canvas = app.otherElements["chart.canvas"]
    XCTAssertTrue(waitUntil(timeout: Self.long) { canvas.exists && canvas.frame.width > canvas.frame.height },
                  "图还没横过来：\(canvas.frame)")

    let more = app.buttons["更多周期"]
    expectExists(more, Self.long, "横屏周期栏底下没有「更多周期」")
    geometry("横屏-窗口", app.windows.firstMatch.frame)
    geometry("横屏-画布", canvas.frame)
    geometry("横屏-更多周期", more.frame)
    // 两张图必须是同一帧构图：先把图停住（视野不动），再一前一后各截一张。
    shot("iPhone15-横屏画线台-侧栏收着-青苔深")

    more.tap()
    let grid = app.buttons["period.row.1m"]
    expectExists(grid, Self.long, "点「更多周期」没推出侧栏：\(app.debugDescription)")
    geometry("横屏-侧栏里的 1m", grid.frame)
    shot("iPhone15-横屏画线台-侧栏开着遮罩-青苔深")

    // 收掉侧栏，回竖屏。
    let done = app.buttons[Ids.panelDone]
    if done.exists, done.isHittable { done.tap() }
    _ = waitUntil(timeout: Self.short) { !grid.exists }
  }
}
