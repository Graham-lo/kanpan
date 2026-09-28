import XCTest

// ============================================================ 设置页的字面（审查 U13）
//
// 设置页每一行写的是用户得到什么，不是我们内部怎么叫它：
// 「开盘时间」其实设的是涨跌幅从哪儿算起；「UTC」「交易所」并排像同一件事；
// 分组标题「朋友」底下唯一一行又叫「朋友」；「启动快照」「清缓存」是工程用语；
// 「十字线磁吸」和画线里的「吸附到 K 线」一个事两种叫法；「自动护眼配色」和
// 「跟随系统」读起来重叠。这条用例把改过之后的字面钉住，旧字面一个都不许回来。
// 2026-09-28「收设置项」之后又收掉五行，这里一并钉住它们不许回来。

@MainActor
final class SettingsWordingUITests: KanpanUICase {

  private func labeled(_ text: String) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text))
  }

  private func shot(_ name: String) {
    let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
  }

  func testSettingsRowsSayWhatTheyDo() {
    openSettingsPage()
    shot("设置-上半")

    for text in ["涨跌色", "外观", "线路"] {
      XCTAssertTrue(labeled(text).firstMatch.waitForExistence(timeout: Self.short), "设置页上没有「\(text)」")
    }
    for old in ["开盘时间", "十字线磁吸", "自动护眼配色", "随屏幕明暗切换", "交易所", "启动快照",
                "重置所有偏好设置",
                // 2026-09-28 第二阶段缩短的展示语：长的那版不许回来。
                "涨跌配色", "行情线路", "提醒铃声", "自选波动提醒", "品种上新与停牌下架", "按我的习惯自动调整"] {
      XCTAssertFalse(labeled(old).firstMatch.exists, "旧字面「\(old)」又回来了")
    }
    // 2026-09-28「收设置项」收掉的几行一个都不许回来：口径按品种自动定、时间一律上海 UTC+8、
    // 看图时自动常亮、缓存自己按上限清。
    for retired in ["涨跌幅起点", "按屏幕亮度切换深浅", "时区", "盯盘时不锁屏", "清理存储空间", "清缓存",
                    "十字线吸附到 K 线"] {
      XCTAssertFalse(labeled(retired).firstMatch.exists, "已收掉的「\(retired)」又回到设置页了")
    }
    for id in ["settings.changeBasis", "settings.keepAwake", "settings.clearCache", "display.ambient",
               "settings.magnet"] {
      XCTAssertFalse(app.descendants(matching: .any).matching(identifier: id).firstMatch.exists, "\(id) 还在")
    }

    // 滑到底：最后一行是「恢复默认」。
    let reset = app.descendants(matching: .any).matching(identifier: "settings.reset").firstMatch
    XCTAssertTrue(reset.waitForExistence(timeout: Self.short), "设置页上没有恢复默认那一行")
    for _ in 0..<4 where !reset.isHittable { app.swipeUp() }
    shot("设置-下半")
    // 「朋友」2026-09-27 整个搬去「我的 › 朋友与收件箱」，设置页上一处都不该再有。
    XCTAssertEqual(labeled("朋友").count, 0, "「朋友」已搬去「我的」，设置页上又出现了")
  }
}
