import UIKit
import XCTest

// ============================================================ 底栏下面 home 条那一截不许露出滚动内容
//
// 2026-09-28 底栏身后加了一道「透明 → 页面底色」的渐变（`TabBar.fadeBed`），设计是
// 「70% 起实色，一直铺到 home 条」：滚到中间时记号下面那一行被压淡，记号**下方**
// 那 34pt 是一整块页面底色，什么字都没有。
//
// 2026-10-04 G 线走查拍到的却是：板块列表、板块下钻页、自选页最下面那一行完整清楚地
// 躺在底栏图标下方。根因是 home 条那一截的写法 `ground.frame(height: 1).ignoresSafeArea(...)`
// ——安全区放大的是 1pt 框外面的摆放区域，框自己不长，只被居中挪到 home 条半腰，
// 那 34pt 一直透明。
//
// 判据：在底栏格子下沿与屏幕下沿之间那一条里（左右各取一段，避开正中 home 指示条可能
// 出现的位置），横向相邻像素的亮度跳变不许超过阈值——页面底色、底栏的灯座光都是平滑渐变，
// 只有文字、徽章边缘才会一步跳几十级。列表停在几个不同的滚动位置各验一次，免得某一刻
// 正好是两行之间的空隙。
@MainActor
final class TabBarHomeStripUITests: KanpanUICase {

  private let profile = UUID().uuidString
  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": profile,
     // 二十只：自选列表一屏放不下，静止时就有行落在底栏身后。
     "KANPAN_TEST_FAVORITES": "BTCUSDT,ETHUSDT,SOLUSDT,XRPUSDT,DOGEUSDT,SUIUSDT,BNBUSDT,ADAUSDT,"
       + "LINKUSDT,AVAXUSDT,DOTUSDT,LTCUSDT,TRXUSDT,NEARUSDT,APTUSDT,ARBUSDT,OPUSDT,ATOMUSDT,FILUSDT,UNIUSDT"]
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  func testScrollingRowsNeverShowBelowTheTabBar() {
    app.buttons[Ids.bottomFavorites].tap()
    let favRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "favorites.open.")).firstMatch
    expectExists(favRow, Self.long, "自选页没有行")
    checkStrip(page: "自选")

    app.buttons[Ids.bottomSectors].tap()
    expectExists(app.otherElements["sector.page"], Self.long, "点「板块分类」没进板块页")
    let sectorRow = app.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier BEGINSWITH %@", "sector.row.")).firstMatch
    XCTAssertTrue(waitUntil(timeout: Self.long) { sectorRow.exists }, "板块列表一行都没有")
    checkStrip(page: "板块")
  }

  /// 在当前页的几个滚动位置上，量 home 条那一截里最大的横向亮度跳变。
  private func checkStrip(page: String) {
    let window = app.windows.firstMatch.frame
    let tab = app.buttons[Ids.bottomFavorites].frame
    // 一格的按钮下沿 + 5pt 竖向留白 = 栏的下沿 = home 条上沿。上下各让 4pt，躲开灯座最浓那一线的抖动。
    let top = tab.maxY + 5 + 4
    let bottom = window.maxY - 4
    XCTAssertGreaterThan(bottom - top, 12, "\(page)：home 条那一截高度不对（栏下沿 \(tab.maxY)，屏高 \(window.maxY)）")

    for position in 0..<4 {
      if position > 0 {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -97)))
        Thread.sleep(forTimeInterval: 1.0)
      }
      let shot = XCUIScreen.main.screenshot()
      let jump = Self.maxHorizontalJump(shot, window: window, top: top, bottom: bottom)
      // 本机看图用：这个目录存在才落盘（平时不建，不留东西）。
      let dir = URL(fileURLWithPath: "/tmp/kanpan-homestrip", isDirectory: true)
      if FileManager.default.fileExists(atPath: dir.path) {
        try? shot.pngRepresentation.write(to: dir.appendingPathComponent("\(page)-\(position)-跳变\(jump).png"))
      }
      if jump >= Self.threshold {
        let a = XCTAttachment(screenshot: shot)
        a.name = "\(page)-第\(position)屏-home条露字"
        a.lifetime = .keepAlways
        add(a)
      }
      XCTAssertLessThan(jump, Self.threshold,
                        "\(page) 第 \(position) 个滚动位置：底栏下方 home 条那一截里出现了文字/图形边缘"
                        + "（最大横向亮度跳变 \(jump)，阈值 \(Self.threshold)）——滚动内容从底栏下面露出来了")
    }
  }

  /// 文字边缘一步能跳一两百级；底色与灯座光的渐变每像素不到几级。
  private static let threshold = 40

  /// 两段横带（左 16…140pt、右 宽-140…宽-16pt）里，横向相邻像素亮度差的最大值（0–255）。
  private static func maxHorizontalJump(_ shot: XCUIScreenshot, window: CGRect,
                                        top: CGFloat, bottom: CGFloat) -> Int {
    guard let image = shot.image.cgImage else { return 999 }
    let scale = CGFloat(image.width) / window.width
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return 999 }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func lum(_ x: Int, _ y: Int) -> Int {
      let i = (y * width + x) * 4
      return (299 * Int(bytes[i]) + 587 * Int(bytes[i + 1]) + 114 * Int(bytes[i + 2])) / 1000
    }
    let y0 = max(0, Int(top * scale)), y1 = min(height - 1, Int(bottom * scale))
    let bands = [(16.0, 140.0), (Double(window.width) - 140, Double(window.width) - 16)]
    var worst = 0
    for y in stride(from: y0, through: y1, by: 1) {
      for (from, to) in bands {
        let x0 = Int(CGFloat(from) * scale), x1 = min(width - 2, Int(CGFloat(to) * scale))
        for x in x0..<x1 {
          worst = max(worst, abs(lum(x + 1, y) - lum(x, y)))
        }
      }
    }
    return worst
  }
}
