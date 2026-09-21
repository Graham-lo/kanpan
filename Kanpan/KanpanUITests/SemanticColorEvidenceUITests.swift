import UIKit
import XCTest

// ============================================================ 语义色整改的四处取证
//
// 2026-09-22 那一轮视觉/语义色整改（HEAD `de1ac11`）留了四处「够不着」的地方：
// 上一轮的取证要么拍不到那个状态，要么拍到的是另一条分支。这个文件专门把这四处
// **摆到镜头前**，截图 + 打印几何。
//
// 2026-09-22 第二轮改了口径：**左滑那两条现在真的断言颜色**。原来这儿写着
// 「XCUITest 读不到任何一个色值」，那是错的——`XCUIScreenshot.image.cgImage`
// 就是一张能逐像素读的位图（见下面的 `histogram`）。另外三条仍然只摆状态 + 截图，
// 因为它们要判的是「这层遮罩压下去有多深」这类没有定值的事，判读留给人。
//
// ------------------------------------------------------------ 四件事
//
// 1. **左滑「删除」的字色**。第一轮逮到了一条真的：`DrawingBar` 用系统
//    `.swipeActions` 画的那块砖，`Text("删除").foregroundStyle(theme.badgeInk)`
//    压根没生效，字是纯 `#FFFFFF`、对比度 2.43:1；同一屏上 `AlertListPage` 那块
//    手搓的砖是 `#060A08`、8.20:1。整改之后两处都走 `SwipeToDelete` 这一个零件，
//    这两条用例改成**断言**：字里必须有 `badgeInk`，一个近白像素都不许有。
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
  /// sequence`）。「再次提醒」那颗胶囊只在 `status == .fired` 时才在，属于
  /// 「有就记一笔、没有就算了」的探询，一律走这里。
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

  // ------------------------------------------------------------ 采色
  //
  // 这个文件开头原来写着「判读留给人，用例自己不下颜色结论——XCUITest 读不到任何
  // 一个色值」。**那句是错的。** `XCUIScreenshot.image.cgImage` 就是一张能逐像素读的
  // 位图，截图自带 sRGB 标记（落盘的 PNG 里那颗 `sRGB` chunk），画进 sRGB 的
  // `CGContext` 再读回来色值一个不差——拿上一轮落盘的两张 PNG 逐字节对过账。
  //
  // 所以左滑那两条现在**真的断言颜色**：回归时它们会红。剩下三条仍然只摆状态 + 截图，
  // 那三处要判的是「这一层遮罩压下去有多深」「行背景对不对」，不是一个定值。

  /// 一块矩形（单位**点**）里的颜色直方图。比例按当时那一帧的窗口宽现算。
  private func histogram(_ rect: CGRect, file: StaticString = #filePath, line: UInt = #line)
    -> [UInt32: Int] {
    guard let cg = XCUIScreen.main.screenshot().image.cgImage else {
      XCTFail("截图拿不到位图", file: file, line: line); return [:]
    }
    let window = app.windows.firstMatch.frame
    guard window.width > 1 else { XCTFail("量不到窗口宽", file: file, line: line); return [:] }
    let scale = CGFloat(cg.width) / window.width
    let box = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                     width: rect.width * scale, height: rect.height * scale).integral
    guard let crop = cg.cropping(to: box), crop.width > 0, crop.height > 0 else {
      XCTFail("裁不出 \(rect)（图 \(cg.width)×\(cg.height)，比例 \(scale)）", file: file, line: line)
      return [:]
    }
    let w = crop.width, h = crop.height
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                              bytesPerRow: w * 4, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
          ({ ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h)); return ctx.data }()) != nil
    else { XCTFail("开不出位图上下文", file: file, line: line); return [:] }
    let base = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let stride = ctx.bytesPerRow
    var counts: [UInt32: Int] = [:]
    for y in 0..<h {
      for x in 0..<w {
        let o = y * stride + x * 4
        let key = UInt32(base[o]) << 16 | UInt32(base[o + 1]) << 8 | UInt32(base[o + 2])
        counts[key, default: 0] += 1
      }
    }
    return counts
  }

  private func top(_ counts: [UInt32: Int], _ n: Int = 6) -> String {
    counts.sorted { $0.value > $1.value }.prefix(n)
      .map { String(format: "#%06X×%d", $0.key, $0.value) }.joined(separator: " ")
  }

  /// 「删除」两个字的笔画判词。**三条都得过**，写松一条这个用例就白留了：
  ///
  /// 1. `badgeInk` 原样出现（青苔深下 `#060A08`）——不是「接近」，是这个值本身；
  /// 2. 近黑的笔画得有点量（≥ 20 个像素），挡住「抗锯齿蹭出来一两个点」这种假阳；
  /// 3. **一个白点都不许有**。旧那版是纯 `#FFFFFF` 的白字，这一条就是防它回来的闸。
  ///    连近白（三通道都 ≥ 200）都算，`#F08A80` 自己是 (240,138,128)，不会误伤。
  private func assertDeleteInk(_ counts: [UInt32: Int], ink: UInt32, what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    let total = counts.values.reduce(0, +)
    note(String(format: "采色|%@|共 %d 像素|%@", what, total, top(counts)))
    XCTAssertGreaterThan(total, 50, "\(what)：字框里才 \(total) 个像素，没量到字", file: file, line: line)
    XCTAssertGreaterThan(counts[ink, default: 0], 0,
                         String(format: "%@：笔画里一个 #%06X 都没有，字色没落到 badgeInk。%@",
                                what, ink, top(counts)),
                         file: file, line: line)
    let dark = counts.filter { rgb, _ in
      (rgb >> 16) & 0xFF <= 40 && (rgb >> 8) & 0xFF <= 40 && rgb & 0xFF <= 40
    }.values.reduce(0, +)
    XCTAssertGreaterThanOrEqual(dark, 20,
                                "\(what)：近黑笔画只有 \(dark) 个像素，太少，字多半不是 badgeInk。\(top(counts))",
                                file: file, line: line)
    let whitish = counts.filter { rgb, _ in
      (rgb >> 16) & 0xFF >= 200 && (rgb >> 8) & 0xFF >= 200 && rgb & 0xFF >= 200
    }.values.reduce(0, +)
    XCTAssertEqual(whitish, 0,
                   "\(what)：字框里有 \(whitish) 个近白像素，系统又把「删除」画成白字了。\(top(counts))",
                   file: file, line: line)
  }

  /// 砖底判词：这块砖最多的那支色必须是 `theme.danger`，不能是系统红也不能是跌色。
  private func assertBrickFill(_ counts: [UInt32: Int], fill: UInt32, what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    note(String(format: "采色|%@|%@", what, top(counts)))
    let winner = counts.max { $0.value < $1.value }?.key
    XCTAssertEqual(winner, fill,
                   String(format: "%@：砖底最多的是 #%06X，不是 danger #%06X。%@",
                          what, winner ?? 0, fill, top(counts)),
                   file: file, line: line)
  }

  /// 把一行的删除砖划出来。
  ///
  /// **不用 `swipeLeft()`**：那是一记快甩，位移一大就越过「滑到底」的门槛
  /// （`SwipeToDelete` 里是行宽的 60%，iPhone 15 上 210pt 上下），砖还没截图人就被删了。
  /// 按住慢拖 120pt——够越过 36pt 的吸附线，又离全滑门槛差得远。
  private func revealDelete(_ ys: CGFloat, _ xs: [CGFloat]) -> XCUIElement {
    let delete = app.buttons[Self.deleteBrick]
    let window = app.windows.firstMatch
    for x in xs {
      if brickIsOpen(delete) { break }
      let from = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: ys))
      let to = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x - 120, dy: ys))
      from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
      _ = waitUntil(timeout: 2) { self.brickIsOpen(delete) }
      note("左划起手点 (\(Int(x)), \(Int(ys)))：砖"
           + (brickIsOpen(delete) ? "出来了（宽 \(Int(delete.frame.width))）" : "没出来"))
    }
    return delete
  }

  /// 砖真的划开了没有。门槛卡 60pt，**不是「宽度 > 1」**：吸附住的砖是 76（贴边）
  /// 或 92（药丸）宽，而没划开时树里要么根本没有这颗节点、要么是个二十来点的残影
  /// （改 `SwipeToDelete` 之前就是后者，害得这条用例一下没划就去采色，量到一片行底色）。
  /// 60 这道线两边都离得远，既不会把残影当开着，也不会把吸附住的砖判成没开。
  private func brickIsOpen(_ delete: XCUIElement) -> Bool {
    delete.exists && delete.frame.width >= 60
  }

  /// `SwipeToDelete` 那两个记号（见 `SwipeDeleteIDs`）。两处共用同一套。
  private static let deleteBrick = "swipe.delete"
  private static let deleteText = "swipe.delete.text"
  /// 青苔深：`badgeInk` = 种子的 `ground`，`danger` = 那支亮鲑红。
  private static let sageNightInk: UInt32 = 0x06_0A_08
  private static let sageNightDanger: UInt32 = 0xF0_8A_80

  /// 画线管理列表的左滑「删除」。
  ///
  /// 2026-09-22 之前这儿用的是系统 `.swipeActions` + `.tint(theme.danger)` +
  /// `Text("删除").foregroundStyle(theme.badgeInk)`，量出来：砖底 `#F08A80`（`.tint`
  /// 管用），字却是纯 `#FFFFFF` 218 个像素、`#060A08` 一个都没有，对比度 2.43:1。
  /// SwiftUI 只把 label 里的字符串取走塞进 `UIContextualAction.title`，那棵 SwiftUI
  /// 子树连同 `foregroundStyle` 一起被丢掉，字是 UIKit 画的，一律白色。
  ///
  /// 现在两处都走 `SwipeToDelete`。这条用例从「记录颜色」改成了「断言颜色」：
  /// 哪天谁把它换回 `.swipeActions`，这里立刻红。
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
    // 眼睛那颗按钮不许在这一轮改造里丢掉（它和行、和行的记号是同一条要求）。
    let eye = app.buttons["隐藏画线"]
    XCTAssertTrue(eye.exists, "行里那颗眼睛没了：\(app.debugDescription)")
    shot("iPhone15-左滑删除-画线管理-滑之前-青苔深")

    let cell = app.cells.containing(.button, identifier: "draw.object.\(first)").firstMatch
    let band = cell.exists ? cell.frame : row.frame
    let delete = revealDelete(band.midY, [band.maxX - 24, band.midX, band.minX + 60])
    XCTAssertTrue(brickIsOpen(delete),
                  "左滑没把删除砖划出来（量到宽 \(delete.exists ? Int(delete.frame.width) : -1)）："
                    + app.debugDescription)

    geometry("画线管理-行", row.frame)
    geometry("画线管理-删除砖", delete.frame)
    // 「删除」两个字自己的 frame。旧那版（`.swipeActions`）在树里根本没有这一颗，
    // 现在 `SwipeToDelete` 把字摆成了按钮的兄弟节点，带自己的记号。
    let label = app.staticTexts[Self.deleteText]
    XCTAssertTrue(label.waitForExistence(timeout: Self.short) && label.frame.width > 1,
                  "砖上「删除」两个字在无障碍树里没有 frame：\(app.debugDescription)")
    geometry("画线管理-删除二字", label.frame)
    // 画线数得在截图前后都不变：这一趟一条都不许真删掉。
    XCTAssertEqual(chartInfo()["drawingCount"] as? Int, ids.count, "还没截图线就少了")
    shot("iPhone15-左滑删除-画线管理-青苔深")

    assertDeleteInk(histogram(label.frame), ink: Self.sageNightInk, what: "画线管理-删除二字")
    assertBrickFill(histogram(delete.frame.insetBy(dx: 12, dy: 12)),
                    fill: Self.sageNightDanger, what: "画线管理-砖底")

    // 收回去，**不触发删除**。划开着的时候点这一行就是「收回去」（`SwipeDeleteProxy.close`）。
    row.tap()
    XCTAssertTrue(waitUntil(timeout: 3) { !delete.exists }, "点行没把砖收回去")
    XCTAssertEqual(chartInfo()["drawingCount"] as? Int, ids.count,
                   "这一趟只是滑出来看一眼，线却被删了：\(chartInfo())")
    XCTAssertEqual(chartInfo()["drawingIDs"] as? [String], ids, "线换了一批，说明删过又画过")
  }

  /// 提醒总表那一行。和画线管理是**同一个零件**（`SwipeToDelete`）的另一种砖型
  /// （`.flush` 贴边方砖，画线管理是 `.pill` 圆角药丸），两处判词一模一样。
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
    // - 「再次提醒」只在 `status == .fired` 时才在。第一版拿它当准星，起手点正压在
    //   那颗胶囊上，那一下把提醒重新上了膛、它自己换成「触碰时 ⌄」，被误判成「行被删了」。
    // - 「删除」那块砖没划开时压根不建出来（`SwipeToDelete.brickView` 里那个 `if`），
    //   不在无障碍树里，划之前找不着。
    // 行名两种状态都在，划开之后只是被推走，在树里照样在。
    let rowAnchor = app.staticTexts
      .matching(NSPredicate(format: "label CONTAINS %@", "水平线")).firstMatch
    expectExists(rowAnchor, Self.long, "种下的那条提醒没出现在总表里：\(app.debugDescription)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { rowAnchor.frame.height > 1 }, "那一行量不出 frame")
    let rowBand = rowAnchor.frame
    shot("iPhone15-左滑删除-提醒总表-滑之前-青苔深")

    // 起手点按顺序试三个，哪个划出来了就停：行右侧「再次提醒」胶囊下面一点、
    // 胶囊正中（划得动，代价是把提醒重新上了膛，不影响这一趟要量的砖）、行左半边文字区。
    let rearm = app.buttons["再次提醒"]
    let capsule = snapshotFrame(rearm) ?? rowBand
    let delete = revealDelete(capsule.midY,
                              [capsule.maxX - 16, capsule.midX, 200])
    XCTAssertTrue(brickIsOpen(delete),
                  "左滑没把删除砖划出来（量到宽 \(delete.exists ? Int(delete.frame.width) : -1)）："
                    + app.debugDescription)
    geometry("提醒总表-行名", rowBand)
    geometry("提醒总表-行名（划开后）", rowAnchor.frame)
    geometry("提醒总表-删除砖", delete.frame)
    let label = app.staticTexts[Self.deleteText]
    XCTAssertTrue(label.waitForExistence(timeout: Self.short) && label.frame.width > 1,
                  "砖上「删除」两个字在无障碍树里没有 frame：\(app.debugDescription)")
    geometry("提醒总表-删除二字", label.frame)
    shot("iPhone15-左滑删除-提醒总表-青苔深")

    assertDeleteInk(histogram(label.frame), ink: Self.sageNightInk, what: "提醒总表-删除二字")
    assertBrickFill(histogram(delete.frame.insetBy(dx: 8, dy: 8)),
                    fill: Self.sageNightDanger, what: "提醒总表-砖底")

    // 这一趟只是滑出来看一眼，不删：砖露着的时候那一行还在（只是被推走了）。
    XCTAssertTrue(rowAnchor.exists, "滑出删除砖的同时那一行没了，多半是被删了")

    // 再从头走一遍验「真的没删」：收掉总表、重新开出来，那条提醒还在。
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
