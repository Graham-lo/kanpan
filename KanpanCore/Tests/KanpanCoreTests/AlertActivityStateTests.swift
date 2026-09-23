import Foundation
import Testing
@testable import KanpanCore

/// 提醒「盯一个」实时活动的状态（P3.3）。
@Suite struct AlertActivityStateTests {
  @Test("实时活动：距离按线算，非有限数一律写空")
  func activityState() throws {
    let s = AlertActivityState(price: 101, change: -0.0123, line: 100, updatedAt: 1)
    #expect(s.distanceLabel == "+1.00%")
    #expect(s.changeLabel == "-1.23%")
    #expect(!s.fired)
    let empty = AlertActivityState(price: .nan, change: nil, line: 100, fired: true, updatedAt: 1)
    #expect(empty.distance == nil && empty.distanceLabel == "--")
    #expect(empty.state == "fired")
    // 服务端推来的那一拍（取不到的是 null）照样解得开。
    let pushed = #"{"price":null,"change":0.01,"line":100,"distance":null,"state":"watching","firedAt":null,"updatedAt":5}"#
    let decoded = try JSONDecoder().decode(AlertActivityState.self, from: Data(pushed.utf8))
    #expect(decoded.price == nil && decoded.change == 0.01 && decoded.updatedAt == 5 && !decoded.fired)
  }
}
