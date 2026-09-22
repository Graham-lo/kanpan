import XCTest
import UIKit

/// 搜索与入口（方案 `71bd340:docs/提醒与体验细节-实施方案-2026-09-20.md` 第 3 节）。
///
/// 这一条把「搜品种」这件事从人的角度走一遍：进页面键盘就位（这一页是来打字的）、
/// 打拼音和首字母要找得到币、点星之后人留在原地。
/// 中文与拼音的**名次**由 `Kanpan/Symbols` 的单测钉死（`SymbolAliasesTests`），
/// 这儿只验真界面上确实是那个结果。
final class SearchEntryUITests: KanpanUICase {
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT"]
  }

  /// 进搜索页键盘自己上来，焦点就落在框里，打的是 ASCII。
  ///
  /// **这一页自动聚焦是对的**，别把它跟画线那层浮层搞混。记忆
  /// `kanpan-symbol-search-keyboard` 里「进来不自动抢焦点」那一条，用户当时说的是
  /// **横屏画线工作台里点品种名弹的那层换品种浮层**（`DrawingSymbolSwitcher`，由
  /// `ChartFoundationUITests.testDrawingSymbolSwitcherKeepsKeyboardDown` 守着）：
  /// 那层的主体是底下那格「常看」，键盘一上来就把它盖了。同一条记忆紧接着写明
  /// 「整页级的搜索页（用户是从「搜索」入口点进去的）不在此列，那儿自动聚焦是对的」，
  /// `71bd340:docs/实施任务书.md` 第 545 行也是同一句：「页面进入时搜索框**自动聚焦弹键盘**
  /// （这是来搜的）」。自选页这颗「搜索品种」框开的就是同一张整页搜索页
  /// （`SymbolSearchView`），人点它就是为了打字。
  ///
  /// 这条用例原来断言的是反面（`testSearchPageDoesNotRaiseKeyboardOnAppear`）：
  /// 9638adf 把浮层那条规矩误套到了整页上，用例跟着一起写歪了；0dee684 已经把产品
  /// 改回自动聚焦（`SymbolSearchView` 的 `.task` 里那句 `focused = true`），却漏改了
  /// 这一条，于是 09-21 的兼容性矩阵上五台机器全红。2026-09-22 在 iPhone 15 上
  /// 实测确认：进这一页键盘自己上来、框上有焦点环——那是对的行为，改的是用例。
  func testSearchPageRaisesKeyboardOnAppear() throws {
    openSearch()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                  "从自选页进搜索页，键盘没有自己上来（这一页该自动聚焦）")
    shot("搜索页-进来就能打字")
    // 焦点真的在那个框上：**不点它**，直接打字，三个字母要原样落进去。
    let field = app.textFields[Ids.searchQuery]
    XCTAssertTrue(field.exists, "搜索页上没有输入框")
    field.typeText("BTC")
    XCTAssertTrue(waitUntil(timeout: 5) { (field.value as? String) == "BTC" },
                  "没点框直接打字，框里是「\(field.value as? String ?? "?")」——焦点没落在搜索框上")
  }

  /// 拼音全拼、首字母、以及「ETH/USDT」这类写法都要找得到。
  func testPinyinInitialsAndSeparators() throws {
    openSearch()
    let field = app.textFields[Ids.searchQuery]
    field.tap()

    type("btb")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/BTCUSDT"].waitForExistence(timeout: 8), "btb 搜不到比特币")
    shot("搜索-btb")

    retype("bitebi")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/BTCUSDT"].waitForExistence(timeout: 8), "bitebi 搜不到比特币")
    shot("搜索-bitebi")

    retype("tsl")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/TSLAUSDT"].waitForExistence(timeout: 8), "tsl 搜不到特斯拉")
    shot("搜索-tsl")

    retype("eth usdt")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/ETHUSDT"].waitForExistence(timeout: 8), "「eth usdt」搜不到 ETHUSDT")
    retype("ETH/USDT")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/ETHUSDT"].waitForExistence(timeout: 8), "「ETH/USDT」搜不到 ETHUSDT")
    retype("$ETH")
    XCTAssertTrue(app.buttons["symbols.row.binance/usd_m/ETHUSDT"].waitForExistence(timeout: 8), "「$ETH」搜不到 ETHUSDT")
    shot("搜索-分隔符容忍")
  }

  /// 点星之后：页面不关、词不清、人还站在刚才那一行上。
  func testStarKeepsTheQueryAndThePage() throws {
    openSearch()
    let field = app.textFields[Ids.searchQuery]
    field.tap()
    type("sol")
    let row = app.buttons["symbols.row.binance/usd_m/SOLUSDT"]
    XCTAssertTrue(row.waitForExistence(timeout: 8))
    let before = row.frame
    app.buttons["symbols.star.binance/usd_m/SOLUSDT"].tap()
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
