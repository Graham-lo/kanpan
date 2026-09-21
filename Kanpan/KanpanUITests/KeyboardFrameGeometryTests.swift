import XCTest

// ================================================== 键盘框换算的纯算术
//
// 被测的 `keyboardTopEdge(reported:window:)` **不在这个文件里**：它留在
// `ChartFoundationUITests.swift` 末尾，和它唯一的 UI 侧调用方（横屏画线台那条
// 键盘遮挡用例）待在一起。同一个 KanpanUITests target 里的 internal 函数互相可见，
// 不用 import 也不用挪。它为什么要这么算，注释写在它自己头上。

/// `keyboardTopEdge(reported:window:)` 那套换算的算术本身。转过 90° 的键盘框可遇不可求，
/// 所以拿 2026-09-21 iPhone 16 Pro 实测到的原始数字把它钉在这儿。
final class KeyboardFrameGeometryTests: XCTestCase {
  func testKeyboardTopEdgeUnrotatesAQuarterTurnedKeyboardFrame() throws {
    // 转过 90° 的（2026-09-21 iPhone 16 Pro 矩阵实测）：窗口 874×402，键盘报 {{-162,0},{162,874}}。
    // 厚 162，上沿该是 402-162=240，而不是它的 minY(=0)。
    let turned = CGRect(x: 0, y: 0, width: 874, height: 402)
    XCTAssertEqual(keyboardTopEdge(reported: CGRect(x: -162, y: 0, width: 162, height: 874),
                                   window: turned), 240)
    // 正着报的（2026-09-22 iPhone 15 实测）：横屏键盘左右各让开 75pt、铺不满窗宽，上沿仍是 minY。
    let landscape = CGRect(x: 0, y: 0, width: 852, height: 393)
    XCTAssertEqual(keyboardTopEdge(reported: CGRect(x: 75, y: 229, width: 702, height: 162),
                                   window: landscape), 229)
    // 竖屏那种铺满窗宽的，也走同一支。
    let portrait = CGRect(x: 0, y: 0, width: 393, height: 852)
    XCTAssertEqual(keyboardTopEdge(reported: CGRect(x: 0, y: 561, width: 393, height: 291),
                                   window: portrait), 561)
    // 竖着报、长边又对不上窗宽：还原不出来，宁可判不出来。
    XCTAssertNil(keyboardTopEdge(reported: CGRect(x: 0, y: 0, width: 100, height: 1000),
                                 window: landscape))

    // 把 09-21 那条红原样摆一遍：同一组数字，旧写法判红、新写法判绿。
    //
    // 转过 90° 的键盘框是可遇不可求的（2026-09-22 在新建的 iPhone 16 Pro / iOS 26.5 上
    // 连跑三轮都只报正着的 (75,238,724,162)，走的是 minY 那一支），所以这条红没法靠再跑一遍
    // 坐实，只能拿当时 xcresult 里记下来的原始数字回放：窗口与列表都和今天一模一样
    // （874×402、列表底边 188.666…），唯一的变量就是键盘那一格的报法。
    let listBottom: CGFloat = 188.66666666666666
    let asReported = CGRect(x: -162, y: 0, width: 162, height: 874)
    // 旧写法直接拿 minY 当上沿 → 0，列表被判成「压在键盘底下」，这就是当时那条红。
    XCTAssertGreaterThan(listBottom, asReported.minY + 1)
    // 新写法还原出 240，列表在它上方 51pt，判绿——产品行为本来就是对的。
    XCTAssertEqual(keyboardTopEdge(reported: asReported, window: turned), 240)
    XCTAssertLessThanOrEqual(listBottom, try XCTUnwrap(keyboardTopEdge(reported: asReported,
                                                                      window: turned)) + 1)
  }
}
