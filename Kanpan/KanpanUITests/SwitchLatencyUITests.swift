import XCTest

// M5 A5.5：缓存命中时换周期 / 换品种，100 毫秒内出图；快切 20 次不崩、不串源。
//
// 耗时不在这里量：XCUITest 的点按与查询本身就有几十到几百毫秒的开销，拿它计时没有意义。
// 这条用例只负责「按固定节奏切」，同时在外面用 `simctl io recordVideo` 录屏，
// 事后逐帧比：周期条选中的药丸（或顶栏的品种与价格）变了的那一帧 → 图区整块换掉的那一帧。
// 每一步之间停 1.5 秒，让两次切换在录像里分得开。
//
// 先把要切的几档都走一遍（进内存缓存），之后的切换才算「命中」。命中的旁证是录像本身：
// 这台机器到币安 REST 一次往返 200 毫秒以上，一两帧之内就换好的图不可能是现取的。
@MainActor
final class SwitchLatencyUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT"]
  }

  private let intervals = ["1h", "15m", "4h"]
  private let symbols = ["BTCUSDT", "ETHUSDT", "SOLUSDT"]

  private func symbolOnChart() -> String {
    (chartInfo()["symbol"] as? String ?? "").split(separator: "/").last.map(String.init) ?? ""
  }

  private func settled(_ symbol: String, _ interval: String) -> Bool {
    let info = chartInfo()
    return symbolOnChart() == symbol && info["interval"] as? String == interval && (info["bars"] as? Int ?? 0) > 0
  }

  private func pause() { Thread.sleep(forTimeInterval: 1.5) }

  /// 顶栏价格区横滑一下。左滑 = 名单里的下一只（同 `ScanSwipeUITests`）。
  private func swipePrice(next: Bool) {
    let quote = app.descendants(matching: .any).matching(identifier: "market.quote").firstMatch
    XCTAssertTrue(quote.waitForExistence(timeout: Self.short), "顶栏价格区不在")
    quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.85 : 0.15, dy: 0.5))
      .press(forDuration: 0.05, thenDragTo: quote.coordinate(withNormalizedOffset: CGVector(dx: next ? 0.1 : 0.9, dy: 0.5)))
  }

  func testCachedSwitchesForTheScreenRecording() throws {
    XCTAssertTrue(app.openFavorites(), "进不了自选页")
    let row = app.buttons["favorites.open." + testInstrumentKey("BTCUSDT")]
    expectExists(row, Self.long, "自选页上没有 BTCUSDT")
    row.tap()

    // 预热：BTC 的三档，再把三只的 1h 各走一遍。
    for interval in intervals {
      app.tapIntervalChip(interval)
      XCTAssertTrue(waitUntil(timeout: Self.long) { self.settled("BTCUSDT", interval) }, "BTC \(interval) 没出图：\(chartInfo())")
    }
    app.tapIntervalChip("1h")
    XCTAssertTrue(waitUntil(timeout: Self.long) { self.settled("BTCUSDT", "1h") })
    for symbol in symbols.dropFirst() {
      swipePrice(next: true)
      XCTAssertTrue(waitUntil(timeout: Self.long) { self.settled(symbol, "1h") }, "滑到 \(symbol) 没出图：\(chartInfo())")
    }
    for symbol in symbols.reversed().dropFirst() {
      swipePrice(next: false)
      XCTAssertTrue(waitUntil(timeout: Self.long) { self.settled(symbol, "1h") })
    }
    pause(); pause()

    // 计时段一：同一只换周期，1h → 15m → 4h → 1h …… 共 12 次。
    var step = 0
    for round in 0..<4 {
      for interval in ["15m", "4h", "1h"] {
        app.tapIntervalChip(interval)
        XCTAssertTrue(waitUntil(timeout: 10) { self.settled("BTCUSDT", interval) }, "第 \(round) 轮换 \(interval) 没对上：\(chartInfo())")
        step += 1
        pause()
      }
    }
    pause(); pause()

    // 计时段二：同一周期换品种，BTC → ETH → SOL → ETH → BTC …… 共 12 次（顶栏横滑）。
    var at = 0
    for _ in 0..<12 {
      let next = (at == 0) ? true : (at == symbols.count - 1 ? false : (step % 4 < 2))
      at += next ? 1 : -1
      step += 1
      swipePrice(next: next)
      let want = symbols[at]
      XCTAssertTrue(waitUntil(timeout: 10) { self.settled(want, "1h") }, "滑到 \(want) 没对上：\(chartInfo())")
      pause()
    }

    // 全程图上的品种从没跑到别的名字上（不串源）：最后一只和 app 报的一致。
    XCTAssertEqual(symbolOnChart(), symbols[at])
  }
}
