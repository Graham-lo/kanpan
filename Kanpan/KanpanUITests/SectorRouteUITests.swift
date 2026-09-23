import XCTest

// ============================================================ 网关线路下的板块页
//
// 板块页一次要**全市场**的 24h 行情（五百多个品种）。这一笔以前在「网关」那一档上
// 根本没有路：网关只代理带 symbol 的单品种请求，`gatewayPlan` 撞上没有 symbol 的
// `ticker/24hr` 直接 `return nil`，于是选了网关的用户进这一页永远是「暂无行情」
// （审查 A-04）。现在它走网关自己的 `/market/v1/tickers`。
//
// 这条用例把币安 REST 整个按死（`KANPAN_TEST_BINANCE_REST_DOWN=1`，只在 Debug 包里
// 认这个开关），所以屏上只要出现了板块行，那份全市场行情就只可能来自网关——偷偷绕回
// 直连的话这一页一行都长不出来。要真网络：跑的是线上那两台网关。
//
// 币安那边被按死之后，行情源就是 OKX（OKX 本来也只有网关这一条路），顶栏那个
// 只给用例看的 `market.source` 会写 `okx`——这就是「数据确实从网关来」的凭据。
// **OKX V5 不发以计价币结算的成交额**（`volCcy24h` 是按币算的量，不是 USDT 额），
// 网关那边也就照实把 `quoteVolume` 留空，没有拿另一个单位去凑。所以这一档下
// 板块列表的副文案里多半不会出现「成交额」这三个字——缺数就整段省掉，
// 既不许算出个假的 0.00，也不许排一整列「成交额 —」。这条用例两种情况都验：
// 提到成交额的行必须是真数，一行都不提也算对（附一张说明）。
//
// 2026-09-24 起板块页没有气泡场了，底栏第四格进来就是板块列表（`sector.row.<id>`）。

@MainActor
final class SectorRouteUITests: KanpanUICase {

  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] {
    [
      // 出厂默认是直连，这儿从一开始就落在网关那一档，不用进设置里点。
      "KANPAN_TEST_ROUTE_POLICY": "gateway",
      // 一份只属于这次运行的档案，不碰这台机器上真实用户的设置。
      "KANPAN_PERSISTENCE_PROFILE": profile,
      // 币安 REST 一律失败：这一页还能有数，就只能是网关给的。
      "KANPAN_TEST_BINANCE_REST_DOWN": "1",
    ]
  }

  /// 网关这一档下，板块页真的有全市场行情：没有空态、列表有行、成交额不作假。
  func testSectorPageGetsMarketWideTickersThroughTheGateway() {
    // 先在行情页取一次行情源：币安 REST 被按死之后只剩 OKX，而 OKX 没有直连这条路，
    // 所以 `okx` 本身就证明这一趟数据是网关给的。
    let source = app.staticTexts["market.source"]
    XCTAssertTrue(waitUntil(timeout: Self.long) { source.label == "okx" },
                  "币安 REST 被按死之后行情源仍不是 okx（label=\(source.label)），这一趟没走网关")

    app.buttons[Ids.bottomSectors].tap()
    expectExists(app.otherElements["sector.page"], Self.long, "点「板块分类」没进板块页")

    let row = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
    let empty = app.buttons["sector.empty"]
    XCTAssertTrue(waitUntil(timeout: Self.long) { row.exists },
                  "网关线路下 \(Self.long)s 内板块列表一行都没有——全市场行情没从网关回来")
    XCTAssertFalse(empty.exists, "板块页停在「暂无行情」")

    // 页头那行规模「N 个板块 · M 个品种」：两个数都得大于 0。
    let scale = app.staticTexts["sector.scale"]
    expectExists(scale, Self.short, "板块页头上没有规模那一行")
    let numbers = scale.label.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    XCTAssertEqual(numbers.count, 2, "规模那行不是「N 个板块 · M 个品种」：\(scale.label)")
    XCTAssertTrue(numbers.allSatisfy { $0 > 0 }, "规模那行有个 0：\(scale.label)")

    // 行是 `children: .contain`，副文案是行里的一块 `staticText`，直接按内容找。
    let subtitles = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "个品种"))
      .allElementsBoundByIndex.prefix(12).map { $0.label }
      .filter { $0 != scale.label }
    XCTAssertFalse(subtitles.isEmpty, "板块列表里一句副文案都没读到")
    // 提到成交额的，必须是真数。
    XCTAssertFalse(subtitles.contains { $0.contains("成交额 —") || $0.contains("成交额 0.00") },
                   "板块副文案里出现了假的成交额：\(subtitles)")
    if !subtitles.contains(where: { $0.contains("成交额") }) {
      // 这条线路（OKX）根本没有以 USDT 结算的成交额。那就一个字都别提。
      let note = XCTAttachment(string: """
        行情源 = okx（币安 REST 被 KANPAN_TEST_BINANCE_REST_DOWN 按死）。
        OKX V5 的 /market/tickers 不发以计价币结算的成交额（volCcy24h 是按币算的量），
        网关照实把 quoteVolume 留空，所以板块副文案里那一段整个不写。
        规模：\(scale.label)
        板块列表抽样：\(subtitles)
        """)
      note.name = "网关线路没有成交额的原因"
      note.lifetime = .keepAlways
      add(note)
    }

    let sheet = XCTAttachment(screenshot: app.screenshot())
    sheet.name = "网关-板块列表"
    sheet.lifetime = .keepAlways
    add(sheet)
  }
}
