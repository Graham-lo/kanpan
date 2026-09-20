import XCTest

// ============================================================ 周期条行尾的固定槽位（P3-1 / P3-2）
//
// 这条用例只问一件事：**周期药丸会不会动**。
//
// 行尾那颗（「最新 / 返回刚才」）是随状态进出的，进出的时候常用行能分到的宽度就变了
// ——钉住的那几档本来是「排得下就铺满整行」，一变宽就全体重新摊一次，人正要点的那一档
// 在手指落下去之前挪了位置。所以行尾给它留了一个**恒定宽度的槽位**：空着、放「最新」、
// 放「返回刚才」三种状态下一样宽，常用行拿到的宽度一个点都不变。
//
// 槽位只按**一颗药丸里最宽的那句话**（「返回刚才」）钉宽度，不是按几颗之和：
// 「看细节」2026-09-20 已经从这儿搬去头部那行十字线动作（`CrosshairReadoutRow`），
// 两颗并排要 143pt，16 Pro 上会把钉住的周期挤得只剩三档半。
//
// 2026-09-21 又定了一条：**条上最多六档**（`Prefs.maxQuick`），横向滚动和右边那道渐隐
// 一起删了。所以 `testPinnedChipsAllFit` 守的是两头——钉满六档时六颗全在条上，
// 钉三档时那三颗把整行铺满；`testSixthPinIsTheLimit` 守的是「第七颗根本钉不下去」。
//
// 量的是每一颗药丸的 `frame`，不是截图像素：截图能看出「动了」，量框才说得出「动了多少」。
// 截图照旧落到 `/tmp/kanpan-p3/` 下给人看。

@MainActor
final class IntervalSlotUITests: KanpanUICase {

  private var canvas: XCUIElement { app.otherElements["chart.canvas"] }

  private func shot(_ name: String) {
    let screenshot = app.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    let dir = URL(fileURLWithPath: "/tmp/kanpan-p3", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? screenshot.pngRepresentation.write(to: dir.appendingPathComponent(name + ".png"))
  }

  /// 条上每一颗周期药丸现在画在哪儿。
  private func chipFrames() -> [String: CGRect] {
    var out: [String: CGRect] = [:]
    for raw in Ids.quickIntervals {
      let chip = app.buttons[Ids.intervalChip(raw)]
      guard let snap = try? chip.snapshot() else { continue }
      out[raw] = snap.frame
    }
    return out
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

  /// 取消钉住几档。
  ///
  /// 走网格右上角的图钉，不走条上的长按：`press(forDuration:)` 在 SwiftUI 的
  /// `Button` + `onLongPressGesture` 上不稳（实测按 0.8s 也取不下来），
  /// 而这条用例要验的是「排得下排不下」，不是长按手势本身。
  private func unpinFromGrid(_ list: [String]) {
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(app.buttons["period.pin.\(list[0])"].waitForExistence(timeout: Self.short),
                  "「更多」网格没打开")
    for raw in list {
      app.buttons["period.pin.\(raw)"].tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons[Ids.intervalChip(raw)].exists },
                    "取消钉住 \(raw) 之后它还在常用行上")
    }
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.pin.\(list[0])"].exists },
                  "网格没收起来")
  }

  /// 钉上几档（网格右上角那颗图钉）。钉满六档之后图钉会灰掉，所以顺序上要先取后钉。
  private func pinFromGrid(_ list: [String]) {
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(app.buttons["period.pin.\(list[0])"].waitForExistence(timeout: Self.short),
                  "「更多」网格没打开")
    for raw in list {
      let pin = app.buttons["period.pin.\(raw)"]
      XCTAssertTrue(pin.isEnabled, "\(raw) 那颗图钉按不动，钉位提前满了？")
      pin.tap()
      XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons[Ids.intervalChip(raw)].exists },
                    "钉上 \(raw) 之后它没出现在常用行上")
    }
    app.buttons[Ids.intervalMore].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["period.pin.\(list[0])"].exists },
                  "网格没收起来")
  }

  // ------------------------------------------------------------ 四种状态

  func testActionSlotKeepsPeriodChipsStill() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    // 4h 才有更细的一档，「看细节」那颗才可能出现（它现在在头部那一行）。
    pickFromGrid("4h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.app.buttons[Ids.intervalChip("4h")].isSelected },
                  "没切到 4h")
    // 量的就是满钉六档那一排（沙盒铺的正是 `Prefs.maxQuick` 六档）：最挤的情况下
    // 槽位进出还不动，比钉三档时不动更能说明问题。
    XCTAssertTrue(waitUntil(timeout: Self.long) { (self.chartInfo()["bars"] as? Int ?? 0) > 20 },
                  "4h 上没等到 K 线")

    // ① 什么都没有：停在最新、没有十字线。
    let empty = chipFrames()
    shot("01-槽位-空")

    // ② 十字线开着（头部多出「上一根 / 下一根 / 按此价画线 / 看细节」）：
    //    那几颗在**图外的另一行**上，周期条一个点都不该动。
    toggleCrosshair(); waitCrosshair(true, "点图没选中一根")
    XCTAssertTrue(app.buttons["chart.detailZoom"].waitForExistence(timeout: Self.short),
                  "十字线开着却没有「看细节」")
    XCTAssertTrue(app.buttons["chart.crosshair.prev"].exists, "十字线开着却没有「上一根」")
    XCTAssertTrue(app.buttons["chart.crosshair.next"].exists, "十字线开着却没有「下一根」")
    XCTAssertTrue(app.buttons["chart.crosshair.hline"].exists, "十字线开着却没有「按此价画线」")
    let crosshairOn = chipFrames()
    shot("02-槽位-十字线开着")

    // ③ 只有「最新」：收掉十字线，把图往回推。
    toggleCrosshair(); waitCrosshair(false, "再点一下没收掉十字线")
    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "往回拖了却没出现「最新」")
    let latestOnly = chipFrames()
    shot("03-槽位-只有最新")

    // ④ 「最新」+ 十字线一起。
    toggleCrosshair(); waitCrosshair(true, "历史视野上点图没选中一根")
    XCTAssertTrue(app.buttons["chart.detailZoom"].waitForExistence(timeout: Self.short),
                  "历史视野上十字线开着却没有「看细节」")
    let both = chipFrames()
    shot("04-槽位-最新加十字线")

    assertSame(empty, crosshairOn, "空 → 十字线")
    assertSame(empty, latestOnly, "空 → 最新")
    assertSame(empty, both, "空 → 最新加十字线")
  }

  // ------------------------------------------------------------ 钉住的档一个都不许被挤出去

  /// 钉满六档（`Prefs.maxQuick`）时六颗全在条上，取到三档时那三颗把整行铺满。
  ///
  /// 这是「最多展示六档」那条规矩的秤：槽位是给行尾留的，不能拿钉住的周期去垫，
  /// 也不许再靠横向滚动把排不下的那几档藏到屏幕外面。三种槽位状态（空 / 最新 /
  /// 返回刚才）各量一遍——槽位一变宽就把末档挤出去，正是用户在 16 Pro 上看到的那个样子。
  func testPinnedChipsAllFit() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    // 沙盒铺的就是满钉六档。先切到 4h，免得后面取消钉住时动到当前这一档
    //（当前档取下来会变成虚线的临时 chip，照旧占着位子）。
    pickFromGrid("4h")
    let full = Ids.quickIntervals                       // 1m 5m 15m 30m 1h 4h

    assertAllVisible(full, "六档满钉·空")
    assertNoOverlap(full, "六档满钉·空")
    shot("20-六档满钉-槽位空")

    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "往回拖了却没出现「最新」")
    assertAllVisible(full, "六档满钉·有「最新」")
    assertNoOverlap(full, "六档满钉·有「最新」")
    shot("21-六档满钉-有最新")

    app.buttons[Ids.latestButton].tap()
    XCTAssertTrue(app.buttons["chart.returnBack"].waitForExistence(timeout: Self.short),
                  "点了「最新」之后没有「返回刚才」")
    assertAllVisible(full, "六档满钉·有「返回刚才」")
    assertNoOverlap(full, "六档满钉·有「返回刚才」")
    shot("22-六档满钉-有返回刚才")

    // 取到三档：剩下的那三颗要把整行铺满（钉得少就平分，右边不留一条空白）。
    unpinFromGrid(["1m", "5m", "15m"])
    let three = ["30m", "1h", "4h"]
    assertAllVisible(three, "三档")
    assertFillsRow(three, "三档")
    // 槽位这会儿还挂着「返回刚才」（上一步点过「最新」），正好一起看：
    // 三档摊开铺满整行，行尾那一格照旧是同一个宽度。
    shot("23-三档-铺满整行")

    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "三档时往回拖了却没出现「最新」")
    assertAllVisible(three, "三档·有「最新」")
    assertFillsRow(three, "三档·有「最新」")
    shot("24-三档-有最新")
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
    shot("26-最宽六档-槽位空")

    dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "最宽六档时往回拖了却没出现「最新」")
    assertAllVisible(widest, "最宽六档·有「最新」")
    assertNoOverlap(widest, "最宽六档·有「最新」")
    shot("27-最宽六档-有最新")
  }

  /// 钉满六档之后，网格里其余那些图钉按不动。
  func testSixthPinIsTheLimit() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    XCTAssertEqual(Ids.quickIntervals.count, 6, "沙盒该铺满六档")
    app.buttons[Ids.intervalMore].tap()
    let seventh = app.buttons["period.pin.1d"]
    XCTAssertTrue(seventh.waitForExistence(timeout: Self.short), "「更多」网格没打开")
    XCTAssertFalse(seventh.isEnabled, "钉满六档之后，1d 那颗图钉还按得动")
    seventh.tap()                                        // 按下去应当什么也不发生
    XCTAssertFalse(app.buttons[Ids.intervalChip("1d")].exists, "钉满六档之后 1d 还是钉上了")
    XCTAssertTrue(app.staticTexts["已满六档"].exists, "钉满之后网格底下没有那句「已满六档」")
    shot("25-更多网格-已满六档")
    // 取下一档，图钉立刻又能按了。
    app.buttons["period.pin.1m"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.app.buttons["period.pin.1d"].isEnabled },
                  "取下一档之后，1d 那颗图钉还是按不动")
  }

  /// 这几档此刻是不是整颗都落在周期条里（没被右边那道渐隐吃掉、没滚出可视区）。
  private func assertAllVisible(_ list: [String], _ what: String,
                                file: StaticString = #filePath, line: UInt = #line) {
    guard let row = try? app.intervalStrip.snapshot() else {
      return XCTFail("找不到周期条", file: file, line: line)
    }
    for raw in list {
      guard let snap = try? app.buttons[Ids.intervalChip(raw)].snapshot() else {
        XCTFail("\(what)：\(raw) 这一档不在条上", file: file, line: line); continue
      }
      XCTAssertGreaterThanOrEqual(snap.frame.minX, row.frame.minX - 0.5,
        "\(what)：\(raw) 被推出了条的左沿", file: file, line: line)
      XCTAssertLessThanOrEqual(snap.frame.maxX, row.frame.maxX + 0.5,
        "\(what)：\(raw) 被挤出了条的右沿（药丸右沿 \(snap.frame.maxX)，条右沿 \(row.frame.maxX)）",
        file: file, line: line)
    }
  }

  /// 两颗药丸不许叠在一起——排不下时 `HStack` 不会自己换行，只会让内容互相压过去。
  private func assertNoOverlap(_ list: [String], _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
    let frames = list.compactMap { raw -> (String, CGRect)? in
      guard let snap = try? app.buttons[Ids.intervalChip(raw)].snapshot() else { return nil }
      return (raw, snap.frame)
    }.sorted { $0.1.minX < $1.1.minX }
    XCTAssertEqual(frames.count, list.count, "\(what)：有档位没量到", file: file, line: line)
    for (a, b) in zip(frames, frames.dropFirst()) {
      XCTAssertLessThanOrEqual(a.1.maxX, b.1.minX + 0.5,
        "\(what)：\(a.0) 和 \(b.0) 叠在一起了（\(a.1.maxX) > \(b.1.minX)）", file: file, line: line)
    }
  }

  /// 钉得少时这几颗要把整行铺满：末档的右沿贴着条的右沿，右边不留一条空白。
  private func assertFillsRow(_ list: [String], _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
    guard let row = try? app.intervalStrip.snapshot(),
          let last = list.last, let tail = try? app.buttons[Ids.intervalChip(last)].snapshot() else {
      return XCTFail("\(what)：量不到条或末档", file: file, line: line)
    }
    XCTAssertGreaterThan(tail.frame.maxX, row.frame.maxX - 6,
      "\(what)：\(last) 右边还空着 \(row.frame.maxX - tail.frame.maxX)pt，没铺满",
      file: file, line: line)
  }

  // ------------------------------------------------------------ 返回刚才

  /// 翻到历史上 → 点「最新」→ 行尾同一个槽位变成「返回刚才」→ 点它回到刚才那一屏。
  func testReturnToWhereIWasComesBack() {
    XCTAssertTrue(waitForLiveChart(), "图一直没有数据")
    dragChartRight(); dragChartRight()
    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(self.app.buttons[Ids.latestButton]) },
                  "往回拖了却没出现「最新」")
    guard let was = chartInfo()["to"] as? Double, let span = chartInfo()["span"] as? Double else {
      return XCTFail("读不到当前视野")
    }
    shot("05-返回刚才-翻到历史上")

    let latestOnly = chipFrames()
    app.buttons[Ids.latestButton].tap()
    let back = app.buttons["chart.returnBack"]
    XCTAssertTrue(back.waitForExistence(timeout: Self.short),
                  "点了「最新」之后，同一个槽位上没有「返回刚才」")
    shot("06-返回刚才-回到最新后出现")
    // 同一个槽位换了一颗更宽的药丸，周期药丸照旧一个点都不动。
    assertSame(latestOnly, chipFrames(), "最新 → 返回刚才")

    back.tap()
    XCTAssertTrue(waitUntil(timeout: Self.long) {
      guard let to = self.chartInfo()["to"] as? Double else { return false }
      return abs(to - was) < span * 0.05
    }, "点了「返回刚才」没回到刚才那一屏：to=\(String(describing: chartInfo()["to"])) 原 to=\(was)")
    XCTAssertTrue(waitUntil(timeout: Self.short) { !self.app.buttons["chart.returnBack"].exists },
                  "回去之后「返回刚才」还在")
    shot("07-返回刚才-回到了刚才那一屏")
  }
}
