import Foundation
import Testing

@testable import KanpanCore

/// 提醒判定的跨端夹具：`Backend/kanpan-api/contract/alert-cases.json`。
///
/// 判定器有两份——前台 `AlertEvaluator`、服务端 `alerts.rs` 的 `judge`——规则从前只靠注释
/// 「照同一段文字实现」，已经分歧过两次（low > high、竖直段取哪个点）。现在两边都逐条跑同一份
/// 手工维护的夹具；Rust 那一半是 `alerts::tests::every_shared_alert_case_agrees`（只核价，
/// 服务端不返回线的下标），这里连「响在第几条线」一起核。改规则先改夹具。
@Suite("提醒判定夹具（alert-cases.json）")
struct AlertCasesContractTests {
  struct Fixture: Decodable {
    struct Bar: Decodable {
      var openTime: Double
      var low: Double
      var high: Double
      var close: Double?
      var closed: Bool
      var previousClose: Double?
    }
    struct Expect: Decodable, Equatable { var line: Int; var price: Double }
    struct Case: Decodable {
      var name: String
      var why: String
      var condition: Alert.Condition
      var armedAt: Double
      var lines: [AlertLine]
      var bar: Bar
      var expect: Expect?
    }
    var version: Int
    var cases: [Case]
  }

  static func load() throws -> Fixture {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Backend/kanpan-api/contract/alert-cases.json")
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  }

  @Test("夹具里每一条，AlertEvaluator 的结论和夹具一字不差")
  func everySharedCaseAgrees() throws {
    let fixture = try Self.load()
    #expect(fixture.version == 1, "alert-cases.json 的格式版本变了，这里的读法要一起改")
    #expect(fixture.cases.count >= 30, "夹具被删薄了")
    for c in fixture.cases {
      let alert = Alert(symbol: "BTCUSDT", lines: c.lines, condition: c.condition,
                        armedAt: c.armedAt, title: c.name, created: 0)
      let bar = AlertEvaluator.Bar(openTime: c.bar.openTime, high: c.bar.high, low: c.bar.low,
                                   close: c.bar.close, isClosed: c.bar.closed, previousClose: c.bar.previousClose)
      let got = AlertEvaluator.hit(alert, bar: bar).map { Fixture.Expect(line: $0.line, price: $0.price) }
      #expect(got == c.expect, "\(c.name)：\(c.why)")
    }
  }
}
