import UIKit
import XCTest

// ============================================================ 「我的 › 全部预警」跟「我的」同一种页面底色
//
// 2026-10-04 G 线走查：「我的」那一叠推进来的交易所、朋友、设置都是皮肤的页面底色，
// 唯独「全部预警」浅色下是一整页白——提醒总表的底色是照创建提醒那张表定的（表是白的，
// 从它右上推进来的总表跟着白），推到「我的」里也照用；底栏身后那道「透明 → 页面底色」
// 的渐变铺在白页上，成了一条带色的横带。
//
// 判据：同一处空白（页面中下部、底栏渐变以上）在「我的」根页和推进来的「全部预警」上取色，
// 每个通道差不许超过几级。新档案里没有提醒，总表是空态，那一块一定是页面底。
@MainActor
final class MeAlertsGroundUITests: KanpanUICase {

  override var extraLaunchEnvironment: [String: String] {
    ["KANPAN_PERSISTENCE_PROFILE": UUID().uuidString]
  }

  override func setUp() async throws {
    XCUIDevice.shared.orientation = .portrait
    try await super.setUp()
  }

  func testAlertListPushedFromMeUsesThePageGround() {
    XCTAssertTrue(app.openMePage(), "没进到「我的」根页")
    Thread.sleep(forTimeInterval: 0.8)
    let window = app.windows.firstMatch.frame
    let me = Self.patchColor(XCUIScreen.main.screenshot(), window: window)

    XCTAssertTrue(app.tapMeRow(Ids.meAlerts), "「我的」上没有「全部预警」那一行")
    expectExists(app.descendants(matching: .any)["alerts.page"], Self.long, "点「全部预警」没推进总表")
    Thread.sleep(forTimeInterval: 0.8)
    let shot = XCUIScreen.main.screenshot()
    let alerts = Self.patchColor(shot, window: window)

    let diff = zip(me, alerts).map { abs($0 - $1) }.max() ?? 999
    if diff > Self.tolerance {
      let a = XCTAttachment(screenshot: shot)
      a.name = "全部预警-底色"
      a.lifetime = .keepAlways
      add(a)
    }
    XCTAssertLessThanOrEqual(diff, Self.tolerance,
                             "「全部预警」的页面底色和「我的」不是同一种：我的 \(me)，全部预警 \(alerts)"
                             + "（最大通道差 \(diff)）")
  }

  /// 页面底色与白底（`raised`）在浅色青苔下差十几级；同一种底色截两次只差零到一两级。
  private static let tolerance = 4

  /// 页面中下部一块 60×40pt 的平均 RGB（横向居中，纵向 70%——在内容以下、底栏渐变以上）。
  private static func patchColor(_ shot: XCUIScreenshot, window: CGRect) -> [Int] {
    guard let image = shot.image.cgImage else { return [999, 999, 999] }
    let scale = CGFloat(image.width) / window.width
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [999, 999, 999] }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let cx = window.width / 2, cy = window.height * 0.70
    let x0 = Int((cx - 30) * scale), x1 = Int((cx + 30) * scale)
    let y0 = Int((cy - 20) * scale), y1 = Int((cy + 20) * scale)
    var sum = [0, 0, 0], n = 0
    for y in y0..<y1 {
      for x in x0..<x1 {
        let i = (y * width + x) * 4
        sum[0] += Int(bytes[i]); sum[1] += Int(bytes[i + 1]); sum[2] += Int(bytes[i + 2]); n += 1
      }
    }
    return sum.map { $0 / max(n, 1) }
  }
}
