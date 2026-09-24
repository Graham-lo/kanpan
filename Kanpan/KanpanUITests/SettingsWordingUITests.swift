import XCTest

// ============================================================ 设置页的字面（审查 U13）
//
// 设置页每一行写的是用户得到什么，不是我们内部怎么叫它：
// 「开盘时间」其实设的是涨跌幅从哪儿算起；「UTC」「交易所」并排像同一件事；
// 分组标题「朋友」底下唯一一行又叫「朋友」；「启动快照」「清缓存」是工程用语；
// 「十字线磁吸」和画线里的「吸附到 K 线」一个事两种叫法；「自动护眼配色」和
// 「跟随系统」读起来重叠。这条用例把改过之后的字面钉住，旧字面一个都不许回来。

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

    for text in ["涨跌幅起点", "十字线吸附到 K 线", "按屏幕亮度切换深浅", "UTC", "UTC+8", "本地"] {
      XCTAssertTrue(labeled(text).firstMatch.waitForExistence(timeout: Self.short), "设置页上没有「\(text)」")
    }
    for old in ["开盘时间", "十字线磁吸", "自动护眼配色", "随屏幕明暗切换", "交易所", "启动快照",
                "重置所有偏好设置"] {
      XCTAssertFalse(labeled(old).firstMatch.exists, "旧字面「\(old)」又回来了")
    }

    // 滑到底：「朋友」只剩一行，清缓存改叫「清理存储空间」。
    let clear = app.descendants(matching: .any).matching(identifier: "settings.clearCache").firstMatch
    XCTAssertTrue(clear.waitForExistence(timeout: Self.short), "设置页上没有清理存储空间那一行")
    for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
    shot("设置-下半")
    XCTAssertTrue(labeled("清理存储空间").firstMatch.exists, "清缓存那一行没改成「清理存储空间」")
    XCTAssertFalse(labeled("清缓存").firstMatch.exists, "「清缓存」这个工程用语还在")
    XCTAssertEqual(labeled("朋友").count, 1, "「朋友」出现了不止一次：分组标题和行名又重复了")
  }
}
