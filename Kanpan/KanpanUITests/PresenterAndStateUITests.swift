import XCTest

// ============================================================ C-06 / C-07 / C-08
//
// 第五轮审查里这三条标的都是「疑似」：报告读出了结构上的隐患，但没有在机器上跑过，
// 所以它自己写着「不能凭读码断言」。这一整个文件就是那三条的**复现装置**——先拿它
// 在没改过的包上跑一遍留证，再动代码，改完同样三条必须转绿。
//
// 三条钉的是三件互不相干的事：
//   C-06 账号页同时被两个 presenter 驱动（根 + 设置整页）；
//   C-07 参数框里没确认的字符串，在「保存」那一下之前有没有被规范化；
//   C-08 自选滚到中间，切一趟设置再回来还在不在原处。
//
// 都不需要真实行情：账号页和指标编辑器跟 K 线无关，自选用的是注入的种子。

@MainActor
final class PresenterAndStateUITests: KanpanUICase {

  // ------------------------------------------------------------ C-06

  /// 屏幕上同时只能有一张账号页，关掉之后下一次点一下就得开。
  ///
  /// 从前设置整页（`SettingsPanel(asPage: true)`）自己也挂了一个
  /// `.sheet(isPresented: account.presented)`，而它是长在根视图树里的，根上那一个
  /// （`MainScreen`）绑的是同一个布尔。两个 presenter 抢一个开关：SwiftUI 只认一个，
  /// 另一个的状态没人收，于是出现「关掉之后要点两下才再开」这类症状。
  func testAccountHasExactlyOnePresenterFromSettingsPage() {
    openSettingsPage()
    let entry = app.buttons["settings.account"]
    expectExists(entry, Self.short, "设置整页上没有账号入口")
    entry.tap()

    let view = app.descendants(matching: .any).matching(identifier: "account.view")
    XCTAssertTrue(waitUntil(timeout: Self.short) { view.count > 0 }, "点了账号入口没开出账号页")
    XCTAssertEqual(view.count, 1, "屏幕上同时有 \(view.count) 张账号页——两个 presenter 抢同一个开关")

    // 关掉。左上角那颗「‹」是账号页唯一的出口。
    let back = app.buttons["account.back"]
    expectExists(back, Self.short, "账号页上没有返回")
    back.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { view.count == 0 }, "按了返回账号页没收走")

    // 再开。这一下必须一次就中——「要点两下」正是两个 presenter 留下的那份脏状态。
    XCTAssertTrue(waitUntil(timeout: Self.short) { entry.exists && entry.isHittable },
                  "账号页收走之后设置页上的入口没回来")
    entry.tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { view.count > 0 }, "第二次点账号入口一下没开（要点两下）")
    XCTAssertEqual(view.count, 1, "第二次开出了 \(view.count) 张账号页")
    app.buttons["account.back"].tap()
    XCTAssertTrue(waitUntil(timeout: Self.short) { view.count == 0 }, "第二次关不掉")
  }

  // ------------------------------------------------------------ C-07

  /// 焦点还在参数框里直接按「保存」，落盘的必须是规范化之后的那个数。
  ///
  /// 打 `999`（上限 400）：合法的中间值只到 `99`，`999` 本身不合法，所以
  /// 从前 `draft` 停在 99，而框里显示着 999。此时按「保存」，存进去的是 99——
  /// 「保存的不是最后显示出来的那个数」。正确结果是夹到 400。
  func testSavingWhileStillTypingCommitsTheClampedValue() {
    openIndicatorEditor()
    let field = app.textFields["indicator.param.0.field"]
    expectExists(field, Self.short, "指标编辑器里没有第一格参数")
    let before = field.value as? String ?? ""
    XCTAssertFalse(before.isEmpty, "第一格参数读不到当前值")

    field.tap()
    field.typeText("999")
    // 不失焦，直接按「保存」。
    let save = app.buttons["indicator.save"]
    expectExists(save, Self.short, "指标编辑器里没有「保存」")
    save.tap()

    openIndicatorEditor()
    let reread = app.textFields["indicator.param.0.field"]
    expectExists(reread, Self.short, "重开指标编辑器没见到参数格")
    XCTAssertEqual(reread.value as? String, "400",
                   "焦点没离开就按保存，存进去的是「\(reread.value as? String ?? "?")」而不是夹到上限的 400")
    app.buttons["indicator.cancel"].tap()
  }

  /// 同一个数，先失焦再保存，结果必须和「边打边保存」一模一样。
  /// 并且：把框清空直接保存，原来那个值原样留着——没打完的东西不算数，但也不该把它清零。
  func testFocusFirstThenSaveLandsTheSameValueAndEmptyKeepsTheOldOne() {
    openIndicatorEditor()
    let field = app.textFields["indicator.param.0.field"]
    expectExists(field, Self.short)
    field.tap()
    field.typeText("999")
    // 先收焦点：点一下同一张表上别的行（指标名那一栏的标题），再保存。
    app.navigationBars.firstMatch.tap()
    app.buttons["indicator.save"].tap()

    openIndicatorEditor()
    let afterFirst = app.textFields["indicator.param.0.field"]
    expectExists(afterFirst, Self.short)
    XCTAssertEqual(afterFirst.value as? String, "400", "先失焦再保存和边打边保存存的不是同一个数")

    // 第二轮：清空直接保存。
    afterFirst.tap()   // 点进来就清空（灰底纹留着原值）
    app.buttons["indicator.save"].tap()
    openIndicatorEditor()
    let afterEmpty = app.textFields["indicator.param.0.field"]
    expectExists(afterEmpty, Self.short)
    XCTAssertEqual(afterEmpty.value as? String, "400", "空串保存把原来的值弄没了")

    // 第三轮：打了字按「取消」，不许落盘。
    afterEmpty.tap()
    afterEmpty.typeText("7")
    app.buttons["indicator.cancel"].tap()
    openIndicatorEditor()
    let afterCancel = app.textFields["indicator.param.0.field"]
    expectExists(afterCancel, Self.short)
    XCTAssertEqual(afterCancel.value as? String, "400", "按了取消，没确认的编辑还是落了盘")
    app.buttons["indicator.cancel"].tap()
  }

  // 这两条路（设置整页、指标参数编辑器）现在住在 `KanpanUICase` 上：
  // C.10 第 8 条的键盘用例也要从同一个入口进去，别两边各抄一份。
}

// ============================================================ C-08

/// 自选页滚到中间，去设置转一圈回来，人还得在原地。
///
/// 报告把这条记成「疑似」，因为它只确认了「没找到已验证的滚动锚点保存链」。
/// 这条用例先把现象钉死：注入一份超过两屏的自选，滚到中部某个品种，切走再回来，
/// 比较它在可视区里的位置。存的是**品种代号**不是像素——换台设备、换个字号，
/// 绝对坐标本来就对不上。
@MainActor
final class FavoritesScrollAnchorUITests: KanpanUICase {
  /// 二十个真实存在的合约，足够铺满两屏以上。
  private static let seed = [
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT",
    "ADAUSDT", "AVAXUSDT", "LINKUSDT", "DOTUSDT", "TRXUSDT",
    "LTCUSDT", "BCHUSDT", "NEARUSDT", "APTUSDT", "FILUSDT",
    "ATOMUSDT", "ARBUSDT", "OPUSDT", "SUIUSDT", "INJUSDT",
  ]

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_TEST_FAVORITES": Self.seed.joined(separator: ",")]
  }

  /// 此刻可视区顶上那一行：屏幕上画着的行里最靠上、且整行都在窗口里的那个。
  ///
  /// 「他停在哪儿」这件事，对人来说就是这一行；比拿某一行的绝对 y 去比稳。
  /// 注意它和产品那头记的口径差一点：产品记的是 `List` **铺着**的第一行
  /// （比看得见的第一行高一两格，见 `FavoritesView.noteScrollAnchor`），
  /// 这笔固定差额就是下面容差放到两行的由来。
  private func firstVisibleRow() -> (symbol: String, y: CGFloat)? {
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open."))
    var best: (String, CGFloat)?
    for index in 0..<rows.count {
      let element = rows.element(boundBy: index)
      guard let snap = try? element.snapshot(), snap.frame.height > 1 else { continue }
      guard windowFrame.insetBy(dx: -0.5, dy: -0.5).contains(snap.frame) else { continue }
      if best == nil || snap.frame.minY < best!.1 {
        best = (String(snap.identifier.dropFirst("favorites.open.".count)), snap.frame.minY)
      }
    }
    return best.map { (symbol: $0.0, y: $0.1) }
  }

  /// 一行有多高。拿相邻两行的 y 差量出来，不写死——行高随字号、随展开的详情变。
  private func rowHeight() -> CGFloat {
    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open."))
    var ys: [CGFloat] = []
    for index in 0..<rows.count {
      guard let snap = try? rows.element(boundBy: index).snapshot(), snap.frame.height > 1 else { continue }
      ys.append(snap.frame.minY)
    }
    ys.sort()
    let gaps = zip(ys, ys.dropFirst()).map { $1 - $0 }.filter { $0 > 1 }
    return gaps.min() ?? 60
  }

  func testFavoritesKeepsTheScrollPositionAcrossTabs() {
    XCTAssertTrue(app.openFavorites(), "没进到自选页")
    // 默认按自选顺序排，种子是什么顺序列表就是什么顺序。
    let anchorSymbol = Self.seed[13]   // APTUSDT，两屏开外
    let anchor = app.buttons["favorites.open." + anchorSymbol]

    // 往下滚到它露出来。
    let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch
                                                     : app.tables.firstMatch
    var scrolled = 0
    while !onScreen(anchor), scrolled < 12 { list.swipeUp(); scrolled += 1 }
    XCTAssertTrue(onScreen(anchor), "滚了 \(scrolled) 下还没把 \(anchorSymbol) 滚出来")
    // 再往上带一点，保证它不贴着屏幕边——贴边的话「有没有恢复」看不出差别。
    let beforeY = anchor.frame.minY
    XCTAssertGreaterThan(beforeY, 0, "锚点行的位置读不出来")

    let topBefore = firstVisibleRow()
    XCTAssertNotNil(topBefore, "滚完了读不到可视区顶上那一行")
    let step = rowHeight()
    let diagBefore = String(describing: app.otherElements["favorites.feed"].value)

    // 去设置转一圈。自选页这一格每切走一次就整个重建（`MainScreen.portraitBody`）。
    let settings = app.buttons[Ids.bottomSettings]
    expectExists(settings, Self.short)
    settings.tap()
    expectExists(app.buttons[Ids.settingsMagnet], Self.short, "没进设置整页")
    XCTAssertTrue(app.openFavorites(), "从设置回不到自选页")

    XCTAssertTrue(waitUntil(timeout: Self.short) { self.onScreen(anchor) },
                  "切回自选，\(anchorSymbol) 不在屏幕上了——滚动位置没被持有\n走之前：\(diagBefore)\n回来后：" +
                  String(describing: app.otherElements["favorites.feed"].value))
    // 判据两条，都以「人看得出来吗」为准，容差都是**两行**：
    //
    // 一、可视区顶上那一行，和走之前差不到两行。产品那头记的是品种代号
    //     （`FavoritesEditSession.scrollAnchor`），拿代号在表里的序号比，
    //     不拿像素比——换台设备、换个字号，绝对坐标本来就对不上。
    //
    // 二、锚点行的位置差不到两行高。
    //
    // 为什么是两行而不是一行：`List` 在可视区上下各多铺几行，两头的缓冲厚度还
    // 不一样，而恢复时能拿到的最细的粒度就是「滚到某一行的顶上」，补偿只能按整行补。
    // 2026-09-20 在 iPhone 15 上实测，来回一趟稳定差 93pt（约一行半），不飘。
    // 更细的一档试过 `scrollPosition(id:)`——`List` 上它根本不往里写，落脚点是空的，
    // 切回来直接停在表头，比现在这版差得多（那次实测记在 `FavoritesView` 的注释里）。
    let topAfter = firstVisibleRow()
    let diagAfter = String(describing: app.otherElements["favorites.feed"].value)
    let before = Self.seed.firstIndex(of: topBefore?.symbol ?? "")
    let after = Self.seed.firstIndex(of: topAfter?.symbol ?? "")
    XCTAssertNotNil(after, "切回来读不到可视区顶上那一行")
    if let before, let after {
      XCTAssertLessThanOrEqual(abs(after - before), 2,
                               "切回来顶上那一行从 \(topBefore?.symbol ?? "?") 跳到了 \(topAfter?.symbol ?? "?")，差了 \(abs(after - before)) 行"
                               + "\n走之前：\(diagBefore)\n回来后：\(diagAfter)")
    }
    let afterY = anchor.frame.minY
    XCTAssertLessThan(abs(afterY - beforeY), step * 2,
                      "切回来 \(anchorSymbol) 从 \(beforeY) 跑到了 \(afterY)，一行才 \(step)pt"
                      + "\n走之前：\(diagBefore)\n回来后：\(diagAfter)")
  }
}
