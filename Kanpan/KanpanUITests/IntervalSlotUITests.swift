import XCTest

// 固定六个周期槽 + 更多 / 分析 / 设置，九格按当前屏宽动态均分。
// 验证宽度与位置、最长文字、非常用周期、入口命中、十字线与历史视野切换。

@MainActor
final class IntervalSlotUITests: KanpanUICase {

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  /// 一条用例一棵干净的档案树：沙盒的六档种子、出厂的「青苔 · 跟随系统」都从零起，
  /// 不吃共享测试档案里别的用例留下的皮肤与深浅（2026-09-24 取证时撞到过：
  /// 共享档案里存着「深色」，模拟器切成浅色拍出来的仍是深色）。
  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] { ["KANPAN_PERSISTENCE_PROFILE": profile] }

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-p3", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  // ---------------------------------------------------------- 怎么量这一条

  /// 量一次周期条：条框与各档药丸取自**同一张**快照，而且要等版面停稳才作数。
  ///
  /// （下面说的是 10-02 之前行尾还有「最新」的时候；药丸删了，这套「同一张快照」的量法照留。）
  /// 行尾的「最新」进出时，周期区本来就要用 0.18s 的 easeOut 重新铺满
  ///（`IntervalBar.body` 上那句 `animation`）。而 `XCUIElement.snapshot()` **每调一次
  /// 都是一次独立的抓取**：一件一件分别量的时候，「条」可能抓在动画中途（还窄着），
  /// 「药丸」抓在动画停稳之后（已经铺满），两个不同时刻的数字一比，就报出根本不存在的
  /// 越界——iPhone Air 上那次 `药丸右沿 294.0 > 条右沿 293.794` 正是这么来的：停稳之后
  /// 条宽 282.0 = 6 × 47.0、右沿正好 294.0，一点没越。
  ///
  /// 所以量法只能是：① 一张快照里同时取条和六颗药丸（`interval.quick` 是
  /// `children: .contain` 起的容器，药丸就在它的子树里）；② 连着两次读到的框一样，
  /// 说明版面已经停稳，这一次的数才算数。
  private func stripLayout(_ list: [String]) -> (row: CGRect, chips: [String: CGRect])? {
    var last: (row: CGRect, chips: [String: CGRect])?
    for _ in 0..<24 {
      guard let strip = try? app.intervalStrip.snapshot() else { return last }
      var chips: [String: CGRect] = [:]
      for raw in list {
        guard let hit = Self.findSnapshot(Ids.intervalChip(raw), under: strip) else { continue }
        chips[raw] = hit.frame
      }
      let now = (row: strip.frame, chips: chips)
      if let prev = last, Self.sameLayout(prev, now) { return now }
      last = now
    }
    return last
  }

  /// 在一张快照的子树里按 identifier 找元素。
  private static func findSnapshot(_ id: String,
                                   under snap: XCUIElementSnapshot) -> XCUIElementSnapshot? {
    if snap.identifier == id { return snap }
    for child in snap.children {
      if let hit = Self.findSnapshot(id, under: child) { return hit }
    }
    return nil
  }

  private static func sameLayout(_ a: (row: CGRect, chips: [String: CGRect]),
                                 _ b: (row: CGRect, chips: [String: CGRect])) -> Bool {
    guard abs(a.row.minX - b.row.minX) < 0.5, abs(a.row.width - b.row.width) < 0.5,
          a.chips.count == b.chips.count else { return false }
    for (raw, left) in a.chips {
      guard let right = b.chips[raw],
            abs(left.minX - right.minX) < 0.5, abs(left.width - right.width) < 0.5 else { return false }
    }
    return true
  }

  /// 条上每一颗周期药丸现在画在哪儿（停稳之后的那一份）。
  private func chipFrames() -> [String: CGRect] {
    stripLayout(Ids.quickIntervals)?.chips ?? [:]
  }

  /// 把这几档此刻的框打进日志：`x / 宽` 一档一行，验收时直接抄这个数。
  private func dumpFrames(_ list: [String], _ what: String) {
    guard let m = stripLayout(list) else { return print("〔周期条框〕\(what)：量不到条") }
    let line = list.compactMap { raw -> String? in
      guard let f = m.chips[raw] else { return nil }
      return String(format: "%@ x=%.1f w=%.1f", raw, f.minX, f.width)
    }.joined(separator: " | ")
    print(String(format: "〔周期条框〕%@：条 x=%.1f w=%.1f ｜ %@", what, m.row.minX, m.row.width, line))
  }

  private func assertSame(_ a: [String: CGRect], _ b: [String: CGRect],
                          _ what: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(a.isEmpty, "一颗药丸都没量到", file: file, line: line)
    for (raw, left) in a {
      guard let right = b[raw] else {
        XCTFail("\(what)：\(raw) 这一档不见了", file: file, line: line); continue
      }
      XCTAssertEqual(left.minX, right.minX, accuracy: 0.5,
                     "\(what)：\(raw) 的左边挪了（\(left.minX) → \(right.minX)）",
                     file: file, line: line)
      XCTAssertEqual(left.width, right.width, accuracy: 0.5,
                     "\(what)：\(raw) 的宽度变了（\(left.width) → \(right.width)）",
                     file: file, line: line)
    }
  }

  /// 图区靠右点一下：开/关十字线。
  private func toggleCrosshair() {
    let mainH = chartInfo()["mainH"] as? Double ?? 300
    let plotW = chartInfo()["plotW"] as? Double ?? 300
    canvas.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: plotW * 0.8, dy: min(130, mainH / 2))).tap()
  }

  private func waitCrosshair(_ on: Bool, _ message: String) {
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.chartInfo()["crosshair"] as? Bool == on },
                  message)
  }

  // ------------------------------------------------------------ 从「更多」网格里操作

  /// 切一档周期。**不点条上的药丸**：网格里每一档都有自己的按钮，位置固定、点得准，
  /// 条上那颗还要先算 frame 再打坐标，偏一点就落到隔壁那一档上。
  private func pickFromGrid(_ raw: String) {
    app.buttons[Ids.intervalMore].tap()
    let cell = app.buttons["period.row.\(raw)"]
    XCTAssertTrue(cell.waitForExistence(timeout: Self.short), "「更多」网格里没有 \(raw)")
    cell.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !cell.exists }, "选完 \(raw) 网格没收起来")
  }

  /// 点「更多」打开网格，等到 `raw` 那颗图钉出来。
  ///
  /// 走 `tapButton`（同一个点最多两下）：当年刚点完「最新」、图还在滑回右缘时，XCUI 偶尔把
  /// 「更多」的命中点算成 `{-1, -1}`，那一下就落空了（2026-09-24 整组跑时撞到一次，单跑复现
  /// 不出来）。「最新」10-02 删了，多点一下的兜底留着不碍事。
  private func openGrid(_ raw: String) {
    let pin = app.buttons["period.pin.\(raw)"]
    XCTAssertTrue(tapButton(app.buttons[Ids.intervalMore]) { pin.exists }, "「更多」网格没打开")
  }

  /// 取消钉住几档。
  ///
  /// 走网格右上角的图钉，不走条上的长按：`press(forDuration:)` 在 SwiftUI 的
  /// `Button` + `onLongPressGesture` 上不稳（实测按 0.8s 也取不下来），
  /// 而这条用例要验的是「排得下排不下」，不是长按手势本身。
  private func unpinFromGrid(_ list: [String]) {
    openGrid(list[0])
    for raw in list {
      app.buttons["period.pin.\(raw)"].tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons[Ids.intervalChip(raw)].exists },
                    "取消钉住 \(raw) 之后它还在常用行上")
    }
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.pin.\(list[0])"].exists },
                  "网格没收起来")
  }

  /// 钉上几档（网格右上角那颗图钉）。钉满六档之后点图钉是「挑一档换掉」，所以顺序上要先取后钉。
  private func pinFromGrid(_ list: [String]) {
    openGrid(list[0])
    for raw in list {
      let pin = app.buttons["period.pin.\(raw)"]
      pin.tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalChip(raw)].exists },
                    "钉上 \(raw) 之后它没出现在常用行上")
    }
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.pin.\(list[0])"].exists },
                  "网格没收起来")
  }

  // ------------------------------------------------------------ 四种状态

  /// 十字线开关、往回拖到历史里，都不许动周期条：六档一个点都不挪。
  func testCrosshairAndHistoryKeepChipsStill() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    // 换一档不是默认的周期，量的是「用户切过周期之后」那一排。
    pickFromGrid("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChip("4h")].isSelected },
                  "没切到 4h")
    // 量的就是满钉六档那一排（沙盒铺的正是 `Prefs.maxQuick` 六档）：最挤的一种工况。
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                  "4h 上没等到 K 线")
    let full = Ids.quickIntervals

    // ① 什么都没有：停在最新、没有十字线。
    let empty = chipFrames()
    shot("01-出厂态-停在最新")

    // ② 十字线开着：「涨到 / 跌到 X 提醒我」那颗药丸顶替周期条，就摆在周期条那一行的框里；
    //    周期条透明让位、点不着。十字线一收，六档原地出现。
    guard let strip = try? app.intervalStrip.snapshot().frame else { return XCTFail("量不到周期条") }
    toggleCrosshair(); waitCrosshair(true, "点图没选中一根")
    XCTAssertTrue(app.buttons["chart.crosshair.alert"].waitForExistence(timeout: Self.short),
                  "十字线开着却没有「提醒我」药丸")
    for id in ["chart.crosshair.alert"] {
      let b = app.buttons[id]
      XCTAssertTrue(b.exists && b.isHittable, "十字线开着却点不着 \(id)")
      XCTAssertEqual(b.frame.midY, strip.midY, accuracy: 2, "\(id) 不在周期条那一行上：\(b.frame) 条 \(strip)")
    }
    let moreButton = app.buttons[Ids.intervalMore]
    XCTAssertFalse(moreButton.exists && moreButton.isHittable, "十字线开着时周期条没让位")
    shot("02-十字线开着")
    toggleCrosshair(); waitCrosshair(false, "再点一下没收掉十字线")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalMore].isHittable },
                  "十字线收了周期条没回来")
    assertSame(empty, chipFrames(), "十字线收起后")

    // ③ 把图往回推到历史里：行尾不再冒出任何东西，六档原地不动。
    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.chartAtLatest() }, "往回拖了视野还在最新")
    Thread.sleep(forTimeInterval: 0.4)
    assertSame(empty, chipFrames(), "往回拖到历史之后")
    shot("03-在历史里")

    // ④ 历史视野上开十字线：药丸照旧顶替整行；收起后六档原地回来。
    toggleCrosshair(); waitCrosshair(true, "历史视野上点图没选中一根")
    XCTAssertTrue(app.buttons["chart.crosshair.alert"].waitForExistence(timeout: Self.short),
                  "历史视野上十字线开着却没有「提醒我」药丸")
    shot("04-历史加十字线")
    toggleCrosshair(); waitCrosshair(false, "历史视野上再点一下没收掉十字线")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalMore].isHittable },
                  "十字线收起后周期条没回来")
    assertSame(empty, chipFrames(), "历史 → 十字线 → 收起")
  }

  // ------------------------------------------------------------ 钉住的档一个都不许被挤出去

  /// 钉满六档（`Prefs.maxQuick`）时六颗全在条上，取到三档时那三颗把整行铺满。
  ///
  /// 这是「最多展示六档」那条规矩的秤：行尾的动作再宽也不许把钉住的周期挤出去，
  /// 也不许再靠横向滚动把排不下的那几档藏到屏幕外面。行尾「更多 ▾ · 分析 · 图表设置」
  /// 三件都在、六档满钉是最挤的一屏，六档在那时还排得下、三件都点得着，
  /// 才谈得上排版对「≤6 档」这一种情况负责。
  func testPinnedChipsAllFit() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    // 沙盒铺的就是满钉六档。先切到 4h，免得后面取消钉住时动到当前这一档
    //（当前档取下来会变成虚线的临时 chip，照旧占着位子）。
    pickFromGrid("4h")
    let full = Ids.quickIntervals                       // 1m 5m 15m 30m 1h 4h

    assertAllVisible(full, "六档满钉·空")
    assertNoOverlap(full, "六档满钉·空")
    assertTailFits(full, "六档满钉")
    assertEqualSlots(full, "六档满钉")
    // 最挤的那一屏的实测数字，留在日志里给人看（16 Pro 上尤其要看这一行）。
    dumpFrames(full, "六档满钉")
    shot("20-六档满钉-行尾三件")

    // 兼容旧偏好不足六档：六个周期槽仍保留，右侧入口不挪位。
    unpinFromGrid(["1m", "5m", "15m"])
    let three = ["30m", "1h", "4h"]
    assertAllVisible(three, "三档")
    assertTailFits(three, "旧偏好三档")
    assertEqualSlots(three, "三档")
    // 旧偏好不足六档时保留槽位，三个入口不移动。
    shot("23-旧偏好三档-保持九格位置")
  }

  /// 最宽的那六档一起钉上，照样一行排得下、一个字不截。
  ///
  /// 沙盒铺的六档（1m 5m 15m 30m 1h 4h）里有四档是两个字符的窄药丸，排得下不算数。
  /// 十四档里真正宽的是「15m」「30m」「12h」这三个三字符的，再挑三个字面偏宽的
  /// 「1M」「1w」「1y」凑满六档——这是这一行可能遇到的最挤的一屏，SE 上也得排得下。
  func testWidestSixStillFit() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    // 先切到 15m：它在最宽那六档里，当前档不会因为被取消钉住而变成临时 chip。
    pickFromGrid("15m")
    unpinFromGrid(["1m", "5m", "1h", "4h"])
    pinFromGrid(["12h", "1w", "1M", "1y"])
    let widest = ["15m", "30m", "12h", "1w", "1M", "1y"]

    assertAllVisible(widest, "最宽六档·空")
    assertNoOverlap(widest, "最宽六档·空")
    assertTailFits(widest, "最宽六档")
    assertEqualSlots(widest, "最宽六档")
    dumpFrames(widest, "最宽六档")
    shot("26-最宽六档-行尾三件")
  }

  /// 钉满六档时点没钉住的图钉：进「挑一档换掉」，六个已钉格子标成可替换，点哪个换哪个；
  /// 点别处（同一颗图钉）取消。没有「已满六档」那句解释。
  func testFullPinsSwapInOneStep() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    XCTAssertEqual(Ids.quickIntervals.count, 6, "沙盒该铺满六档")
    app.buttons[Ids.intervalMore].tap()
    let seventh = app.buttons["period.pin.1d"]
    XCTAssertTrue(seventh.waitForExistence(timeout: Self.short), "「更多」网格没打开")
    XCTAssertFalse(app.staticTexts["已满六档"].exists, "解释文案「已满六档」还在")

    // 点一下又点一下：取消，什么都没换。
    seventh.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["period.row.1m"].label.hasPrefix("换掉") },
                  "钉满时点 1d 的图钉没进「挑一档换掉」")
    shot("25-更多网格-挑一档换掉")
    seventh.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.row.1m"].label.hasPrefix("换掉") },
                  "再点一次同一颗图钉没取消换档")

    // 再来一次，这回点 1m 那一格：1m 出去、1d 进来，还是六档。
    seventh.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["period.row.1m"].label.hasPrefix("换掉") },
                  "第二次点 1d 的图钉没进「挑一档换掉」")
    app.buttons["period.row.1m"].tap()
    XCTAssertTrue(app.buttons[Ids.intervalMore].exists)
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.row.1m"].exists },
                  "网格没收起来")
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalChip("1d")].exists },
                  "换档之后 1d 没上条")
    XCTAssertFalse(app.buttons[Ids.intervalChip("1m")].exists, "换档之后 1m 还在条上")
    let now = ["5m", "15m", "30m", "1h", "4h", "1d"]
    assertAllVisible(now, "换档之后")
    assertNoOverlap(now, "换档之后")
    shot("28-换档之后")
  }

  /// 从网格里切到一个没钉住的周期（2h）：钉住的六档一个都不少，「更多」写成「2h」并高亮。
  func testOffBarIntervalNeverEvictsPins() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    let before = chipFrames()
    pickFromGrid("2h")
    let more = app.buttons[Ids.intervalMore]
    XCTAssertTrue(waitUntil(timeout: Self.long) { more.isSelected }, "切到没钉住的 2h，「更多」没高亮")
    XCTAssertTrue(more.label.contains("当前"), "「更多」没替 2h 说话：\(more.label)")
    XCTAssertFalse(app.buttons[Ids.intervalChip("2h")].exists, "没钉住的 2h 挤上了周期条")
    assertAllVisible(Ids.quickIntervals, "当前档没钉住")
    assertNoOverlap(Ids.quickIntervals, "当前档没钉住")
    assertSame(before, chipFrames(), "更多显示2时")
    assertEqualSlots(Ids.quickIntervals, "更多显示2时")
    shot("29-当前档没钉住-更多写成周期名")
    pickFromGrid("12h")
    XCTAssertTrue(waitUntil(timeout: Self.short) { more.label.contains("12") && more.isSelected })
    assertSame(before, chipFrames(), "更多显示最长的12时")
    assertEqualSlots(Ids.quickIntervals, "更多显示12时")
    shot("29b-当前12时-整格高亮")
    pickFromGrid("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { !more.isSelected }, "切回钉住档，「更多」还亮着")
  }

  /// 这几档此刻是不是整颗都落在周期条里（没被右边那道渐隐吃掉、没滚出可视区）。
  private func assertAllVisible(_ list: [String], _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
    guard let m = stripLayout(list) else {
      return XCTFail("找不到周期条", file: file, line: line)
    }
    for raw in list {
      guard let f = m.chips[raw] else {
        XCTFail("\(what)：\(raw) 这一档不在条上", file: file, line: line); continue
      }
      XCTAssertGreaterThanOrEqual(f.minX, m.row.minX - 0.5,
        "\(what)：\(raw) 被推出了条的左沿", file: file, line: line)
      XCTAssertLessThanOrEqual(f.maxX, m.row.maxX + 0.5,
        "\(what)：\(raw) 被挤出了条的右沿（药丸右沿 \(f.maxX)，条右沿 \(m.row.maxX)）",
        file: file, line: line)
    }
  }

  /// 两颗药丸不许叠在一起——排不下时 `HStack` 不会自己换行，只会让内容互相压过去。
  private func assertNoOverlap(_ list: [String], _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    guard let m = stripLayout(list) else {
      return XCTFail("找不到周期条", file: file, line: line)
    }
    let frames = list.compactMap { raw -> (String, CGRect)? in
      guard let f = m.chips[raw] else { return nil }
      return (raw, f)
    }.sorted { $0.1.minX < $1.1.minX }
    XCTAssertEqual(frames.count, list.count, "\(what)：有档位没量到", file: file, line: line)
    for (a, b) in zip(frames, frames.dropFirst()) {
      XCTAssertLessThanOrEqual(a.1.maxX, b.1.minX + 0.5,
        "\(what)：\(a.0) 和 \(b.0) 叠在一起了（\(a.1.maxX) > \(b.1.minX)）", file: file, line: line)
    }
  }

  /// 行尾「更多 ▾ · 分析 · 图表设置」都在屏上、点得着，一件也没压到末档上，
  /// 也没被推出屏幕右沿。「画线」09-27 到 09-28 在这儿待过一天，现在和指标并列在「分析」面板里。
  private func assertTailFits(_ list: [String], _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
    guard let m = stripLayout(list) else { return XCTFail("找不到周期条", file: file, line: line) }
    let lastChip = list.compactMap { m.chips[$0] }.map(\.maxX).max() ?? m.row.maxX
    let screen = app.windows.firstMatch.frame
    var prevMaxX = lastChip
    for id in [Ids.intervalMore, Ids.intervalIndicators, Ids.intervalChart] {
      let b = app.buttons[id]
      XCTAssertTrue(b.exists && b.isHittable, "\(what)：\(id) 点不着", file: file, line: line)
      XCTAssertGreaterThanOrEqual(b.frame.minX, lastChip - 0.5,
        "\(what)：\(id) 压到了末档上（\(b.frame.minX) < \(lastChip)）", file: file, line: line)
      XCTAssertLessThanOrEqual(b.frame.maxX, screen.maxX + 0.5,
        "\(what)：\(id) 被推出了屏幕右沿（\(b.frame.maxX)）", file: file, line: line)
      // 命中区可以往两边伸一两点，但顺序不许乱。
      XCTAssertGreaterThanOrEqual(b.frame.midX, prevMaxX - 2,
        "\(what)：\(id) 和前一件叠在一起了", file: file, line: line)
      prevMaxX = b.frame.maxX
    }
  }

  /// 固定九格，周期与三个动作等宽且高 44pt；更多改写名称也不移动。
  private func assertEqualSlots(_ list: [String], _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
    let indexed = list.enumerated().map { ($0.offset, Ids.intervalChip($0.element)) }
      + [(6, Ids.intervalMore), (7, Ids.intervalIndicators), (8, Ids.intervalChart)]
    let screen = app.windows.firstMatch.frame
    let width = screen.width / 9
    for (index, id) in indexed {
      let button = app.buttons[id]
      XCTAssertTrue(button.exists && button.isHittable, "\(what)：\(id) 点不着", file: file, line: line)
      XCTAssertEqual(button.frame.width, width, accuracy: 0.5,
                     "\(what)：\(id) 没有等宽", file: file, line: line)
      XCTAssertEqual(button.frame.minX, screen.minX + CGFloat(index) * width, accuracy: 0.5,
                     "\(what)：\(id) 有间隔或越界", file: file, line: line)
      XCTAssertEqual(button.frame.height, 44, accuracy: 0.5, file: file, line: line)
    }
  }

  // ------------------------------------------------------------ 行尾「分析」

  /// 周期条行尾「分析」（09-24 到 09-28 叫「指标」）：点它直接开分析面板（不经「图表设置」）；
  /// 左上角那颗关面板，不是退回「图表设置」。「更多」网格开着时点它，网格先收起来。
  func testIndicatorsOpensIndicatorPage() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    let entry = app.buttons[Ids.intervalIndicators]
    XCTAssertTrue(entry.waitForExistence(timeout: Self.short) && entry.isHittable, "周期条上没有「分析」")
    XCTAssertEqual(entry.label, "分析")

    // 网格开着时点「分析」：网格收起、面板开出来。
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(app.buttons[Ids.periodRow("4h")].waitForExistence(timeout: Self.short), "「更多」网格没打开")
    entry.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons[Ids.periodRow("4h")].exists },
                  "点「分析」之后「更多」网格没收起来")
    let marker = app.buttons[Ids.indicatorSwitch("RSI")]
    XCTAssertTrue(marker.waitForExistence(timeout: Self.short), "点「分析」没开出分析面板")
    let header = app.staticTexts["panel.header"]
    XCTAssertTrue(header.exists && header.label == "分析", "面板标题不是「分析」：\(header.label)")
    XCTAssertFalse(app.buttons[Ids.chartPanelMarker].exists, "开出来的是图表设置，不是分析面板")
    // 2026-09-28：分析面板分四节（画线 · 指标 · 对比 · 主力订单流），画线在最上面。
    // 10-05 曾把「对比」撤到顶栏加号，10-06 用户要求两处并存，这一节恢复。
    let draw = app.buttons[Ids.indicatorDraw]
    XCTAssertTrue(draw.exists, "分析面板里没有「画线」一节")
    XCTAssertLessThan(draw.frame.maxY, marker.frame.minY, "「画线」不在指标之上")
    XCTAssertTrue(app.descendants(matching: .any)["compare.add"].firstMatch.exists, "分析面板里没有「对比」一节")
    shot("30-周期条分析-开出分析面板")

    // 左上角那颗：关面板，不退回「图表设置」。
    app.buttons["panel.done"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !marker.exists }, "左上角那颗没关掉分析面板")
    XCTAssertFalse(app.buttons[Ids.chartPanelMarker].exists, "左上角那颗退回了图表设置，而不是关面板")
    XCTAssertTrue(waitUntil(timeout: Self.short) { entry.isHittable }, "面板关了周期条没回来")
  }
}
