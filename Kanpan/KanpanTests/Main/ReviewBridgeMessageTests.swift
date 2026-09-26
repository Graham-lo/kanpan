import Foundation
import Testing
@testable import Kanpan

/// 重温取数失败时图上那句话：不能是系统原文，更不能露类型名。
@MainActor
struct ReviewBridgeMessageTests {
  private struct Opaque: Error {}

  @Test func networkAndOpaqueErrorsShowOneFixedLine() {
    let errors: [Error] = [URLError(.timedOut), URLError(.notConnectedToInternet),
                           DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "x")), Opaque()]
    for error in errors {
      let text = ReviewChartBridge.message(for: error)
      #expect(text == "这段历史暂时取不到，稍后再试")
      #expect(text != error.localizedDescription)
      #expect(!text.contains("Error") && !text.contains("错误"))
    }
  }

  @Test func ownReasonsKeepTheirWords() {
    #expect(ReviewChartBridge.message(for: ReviewBridgeError.historyGap) == "这段行情有缺口，暂不进入重温")
    #expect(ReviewChartBridge.message(for: ReviewBridgeError.rangeTooLarge) == "区间过长，请缩短后重温")
    #expect(ReviewChartBridge.message(for: ReviewBridgeError.noHistory) == "这段历史暂时无法获取")
  }
}
