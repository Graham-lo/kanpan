import XCTest
import UIKit

/// 搜索与入口（方案 `docs/提醒与体验细节-实施方案-2026-09-20.md` 第 3 节）。
///
/// 这一条把「搜品种」这件事从人的角度走一遍：进页面键盘不许自己顶上来、
/// 打拼音和首字母要找得到币、点星之后人留在原地。
/// 中文与拼音的**名次**由 `Kanpan/Symbols` 的单测钉死（`SymbolAliasesTests`），
/// 这儿只验真界面上确实是那个结果。
final class SearchEntryUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT"]
  }

  /// 进搜索页不弹键盘；点那个框它才起来（记忆 kanpan-symbol-search-keyboard）。
  func testSearchPageDoesNotRaiseKeyboardOnAppear() throws {
    openSearch()
    // 给它两秒——键盘要是会自己起来，这两秒足够了。
    XCTAssertFalse(waitUntil(timeout: 2) { self.app.keyboards.count > 0 }, "搜索页一进来就把键盘顶上来了")
    shot("搜索页-进来不弹键盘")
    app.textFields[Ids.searchQuery].tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "点了输入框键盘还不起来")
  }

  /// 拼音全拼、首字母、以及「ETH/USDT」这类写法都要找得到。
  func testPinyinInitialsAndSeparators() throws {
    openSearch()
    let field = app.textFields[Ids.searchQuery]
    field.tap()

    type("btb")
    XCTAssertTrue(app.buttons["symbols.row.BTCUSDT"].waitForExistence(timeout: 8), "btb 搜不到比特币")
    shot("搜索-btb")

    retype("bitebi")
    XCTAssertTrue(app.buttons["symbols.row.BTCUSDT"].waitForExistence(timeout: 8), "bitebi 搜不到比特币")
    shot("搜索-bitebi")

    retype("tsl")
    XCTAssertTrue(app.buttons["symbols.row.TSLAUSDT"].waitForExistence(timeout: 8), "tsl 搜不到特斯拉")
    shot("搜索-tsl")

    retype("eth usdt")
    XCTAssertTrue(app.buttons["symbols.row.ETHUSDT"].waitForExistence(timeout: 8), "「eth usdt」搜不到 ETHUSDT")
    retype("ETH/USDT")
    XCTAssertTrue(app.buttons["symbols.row.ETHUSDT"].waitForExistence(timeout: 8), "「ETH/USDT」搜不到 ETHUSDT")
    retype("$ETH")
    XCTAssertTrue(app.buttons["symbols.row.ETHUSDT"].waitForExistence(timeout: 8), "「$ETH」搜不到 ETHUSDT")
    shot("搜索-分隔符容忍")
  }

  /// 点星之后：页面不关、词不清、人还站在刚才那一行上。
  func testStarKeepsTheQueryAndThePage() throws {
    openSearch()
    let field = app.textFields[Ids.searchQuery]
    field.tap()
    type("sol")
    let row = app.buttons["symbols.row.SOLUSDT"]
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    let before = row.frame
    app.buttons["symbols.star.SOLUSDT"].tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].exists, "点个星把搜索页关掉了")
    XCTAssertEqual(app.textFields[Ids.searchQuery].value as? String, "sol", "点个星把搜索词清了")
    XCTAssertTrue(row.exists, "点个星那一行就不见了")
    XCTAssertEqual(row.frame.minY, before.minY, accuracy: 1, "点个星列表自己滚了")
    shot("搜索-点星后留在原地")
  }

  /// 复制了「SOL/USDT」再进搜索页：最上面摆一颗系统的粘贴按钮，按一下就开 SOL 那张图。
  ///
  /// 剪贴板是**进页面时看一眼**，所以这一条必须在 app 起来之前就把东西放进去。
  /// 这儿刻意不去读剪贴板内容再显示「打开 SOL」：一读系统就弹「允许粘贴？」
  /// （2026-09-20 实测，原因写在 `ClipboardSymbol` 文件头）。按这颗按钮本身
  /// 就是许可，全程不该有任何询问弹出来——所以按完直接就到图上了。
  func testClipboardOffersTheCopiedSymbol() throws {
    UIPasteboard.general.string = "SOL/USDT"
    app.terminate()
    app.launch()
    openSearch()
    let paste = app.buttons["search.clipboard"]
    XCTAssertTrue(paste.waitForExistence(timeout: 10), "复制了 SOL/USDT，搜索页顶上没有那颗粘贴按钮")
    XCTAssertTrue(paste.label.contains("粘贴"), "顶上那颗不是系统的粘贴按钮：\(paste.label)")
    shot("搜索-剪贴板-粘贴按钮")
    paste.tap()
    // 按了就去那张图：行情页的「图表设置」那颗按钮当准星。
    XCTAssertTrue(app.buttons[Ids.intervalChart].waitForExistence(timeout: 20), "按了粘贴没去图上")
    XCTAssertTrue(app.staticTexts[Ids.symbolButton].label.contains("SOL"), "按了粘贴去的不是 SOL：\(app.staticTexts[Ids.symbolButton].label)")
    shot("搜索-剪贴板-按了粘贴之后")
  }

  // ------------------------------------------------------------ 零件

  private func openSearch() {
    app.buttons[Ids.bottomFavorites].tap()
    let entry = app.buttons["favorites.add"]
    XCTAssertTrue(entry.waitForExistence(timeout: 10), "自选页上没有搜索入口")
    entry.tap()
    XCTAssertTrue(app.textFields[Ids.searchQuery].waitForExistence(timeout: 8), "搜索页没开")
  }

  private func type(_ text: String) {
    app.typeText(text)
  }

  private func retype(_ text: String) {
    let clear = app.buttons["search.clear"]
    if clear.exists { clear.tap() }
    app.typeText(text)
  }

  private func shot(_ name: String) {
    let value = XCTAttachment(screenshot: app.screenshot())
    value.name = name
    value.lifetime = .keepAlways
    add(value)
  }
}
