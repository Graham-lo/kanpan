import XCTest

// ============================================================ iPad 版面体检
//
// 2026-09-18 用户给 iPad 定的口径是「不破」：每一页在 iPad 全部宽度下不错位、
// 不拉伸、可用——不做宽屏分栏布局。整套界面是照 iPhone 宽度画的，所以真正会「破」
// 的是那几张**铺满整屏**的页：搜索页、品种整页、复盘本。它们都是「左边一个名目、
// 右边一个数」的行，13" iPad 横屏铺满就是 1300pt，品种名钉在最左、价格钉在最右，
// 中间一片空白，对不上号。
//
// `readableColumn(560)` 给这几页封了顶，这个类就是那道封顶的看门人：每台 iPad 上
// 把这几页走一遍，量关键控件的宽度，顺手留一张截图。iPhone 上窗口本来就窄，
// 这几条会自己跳过（`skipUnlessWide`）——它们量的是「宽屏下别拉开」，不是功能。
@MainActor
final class IPadLayoutUITests: KanpanUICase {
  /// 内容列的上限（`readableColumn` 的 560）再加一点余量：控件自己还有内边距，
  /// 量出来只会比 560 小；留 600 是为了不被 1pt 的舍入判红。
  private static let columnCap: CGFloat = 600

  /// 窄窗口（iPhone、iPad 的窄分屏）上这几条没有意义，跳过。
  private func skipUnlessWide() throws {
    try XCTSkipUnless(windowFrame.width > 700,
                      "窗口只有 \(Int(windowFrame.width))pt 宽，封顶这件事无从谈起")
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot())
    a.name = name; a.lifetime = .keepAlways; add(a)
  }

  /// 搜索页与品种整页：满屏的一列品种行，封顶之后仍该是居中的一条，不许两端拉开。
  func testSearchAndSymbolPagesKeepAReadableColumn() throws {
    try skipUnlessWide()

    app.buttons[Ids.searchButton].tap()
    let query = app.textFields[Ids.searchQuery]
    expectExists(query, Self.long, "顶栏放大镜没开搜索页")
    shot("iPad-搜索页")
    XCTAssertLessThanOrEqual(query.frame.width, Self.columnCap,
                             "搜索框被拉到 \(Int(query.frame.width))pt，内容列没封住")

    query.typeText("BTC")
    let all = app.buttons[Ids.searchAll]
    if all.waitForExistence(timeout: Self.short) {
      all.tap()
      let symbolsQuery = app.textFields[Ids.symbolsQuery]
      expectExists(symbolsQuery, Self.long, "「查看全部」没过到品种整页")
      shot("iPad-品种整页")
      XCTAssertLessThanOrEqual(symbolsQuery.frame.width, Self.columnCap,
                               "品种整页的搜索框被拉到 \(Int(symbolsQuery.frame.width))pt")
      app.buttons[Ids.symbolsBack].tap()
    } else {
      // 结果不到七条就没有「查看全部」那一行，这一半略过——它不是这条用例的主角。
      shot("iPad-搜索页-有结果")
    }
  }

  /// 复盘本：分段控件（待办 / 记录 / 战绩）和列表行同样归内容列管。
  func testReviewBookKeepsAReadableColumn() throws {
    try skipUnlessWide()

    app.buttons[Ids.topReview].tap()
    expectExists(app.buttons["review.back"], Self.long, "顶栏的「复盘」没开复盘本")
    shot("iPad-复盘本")
    let tabs = app.segmentedControls.firstMatch
    if tabs.exists {
      XCTAssertLessThanOrEqual(tabs.frame.width, Self.columnCap,
                               "复盘本的分段控件被摊到 \(Int(tabs.frame.width))pt")
    }
    app.buttons["review.back"].tap()
  }
}
