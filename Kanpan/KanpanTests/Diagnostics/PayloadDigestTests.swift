import Foundation
import Testing

@testable import Kanpan

@Suite("MetricKit 摘要")
struct PayloadDigestTests {

  @Test("每日指标 payload 抽出启动、挂起、磁盘三项")
  func metricDigest() throws {
    let d = try #require(
      PayloadParser.digest(from: PayloadFixtures.metricPayload(), kind: .metric))

    #expect(d.kind == .metric)
    #expect(d.appVersion == "1.0.0")
    #expect(d.appBuildVersion == "1")
    #expect(d.deviceType == "iPhone17,1")
    #expect(d.begin == "2026-09-13 00:00:00 -0000")

    // 启动：8 次，6 次在 [300,400)、2 次在 [400,500)。p50 落第一桶 → 350。
    let launch = try #require(d.launchTimeToFirstDrawMs)
    #expect(launch.count == 8)
    #expect(launch.p50 == 350)
    #expect(launch.p90 == 450)
    #expect(launch.max == 500)

    let resume = try #require(d.launchResumeMs)
    #expect(resume.count == 12)
    #expect(resume.p50 == 25)

    let hang = try #require(d.hangTimeMs)
    #expect(hang.count == 3)
    #expect(hang.p50 == 50)

    #expect(d.cumulativeLogicalWritesKB == 240)

    // metric payload 里没有崩溃这回事。
    #expect(d.incidents.isEmpty)
    #expect(d.crashCount == 0)
  }

  @Test("旧键名 histogrammedTimeToFirstDraw 也认")
  func legacyLaunchKey() throws {
    // 系统版本之间这个键改过（带不带 `Key` 后缀）。只认一个的话，
    // 换一版系统证据表上启动那一格就会突然空掉，而且没人会立刻发现。
    let raw: [String: Any] = [
      "applicationLaunchMetrics": [
        "histogrammedTimeToFirstDraw": PayloadFixtures.histogram([("200 ms", "300 ms", 4)])
      ]
    ]
    let d = PayloadParser.digest(from: raw, kind: .metric)
    #expect(d.launchTimeToFirstDrawMs?.p50 == 250)
  }

  @Test("崩溃 payload 数得出条数和终止原因")
  func crashDigest() throws {
    let d = try #require(
      PayloadParser.digest(from: PayloadFixtures.crashPayload(), kind: .diagnostic))
    #expect(d.kind == .diagnostic)
    #expect(d.crashCount == 1)
    let c = try #require(d.incidents.first)
    #expect(c.category == "crash")
    #expect(c.detail == "Namespace SIGNAL, Code 0xb")
    // 版本要带 build，否则「1.0.0 崩了」分不清是哪个包。
    #expect(c.version == "1.0.0 (1)")
  }

  @Test("没有 terminationReason 时退回信号号码，不留空")
  func crashWithoutReason() throws {
    let d = try #require(
      PayloadParser.digest(
        from: PayloadFixtures.crashPayload(terminationReason: nil), kind: .diagnostic))
    #expect(d.incidents.first?.detail == "signal=11 exceptionType=1")
  }

  @Test("挂起 / 磁盘 / CPU / 启动四类各归各位")
  func mixedDiagnostics() throws {
    let d = try #require(
      PayloadParser.digest(from: PayloadFixtures.mixedDiagnosticPayload(), kind: .diagnostic))

    #expect(d.crashCount == 0)  // 这份里没有崩溃
    #expect(d.hangCount == 1)
    #expect(d.incidents.count == 4)

    let byCategory = Dictionary(uniqueKeysWithValues: d.incidents.map { ($0.category, $0) })
    #expect(byCategory["hang"]?.durationMs == 3000)
    #expect(byCategory["diskWrite"]?.writtenKB == 1_024_000)  // "1024 mB" → 1024 MB → KB
    #expect(byCategory["cpu"]?.durationMs == 20_000)
    #expect(byCategory["launch"]?.durationMs == 5000)
  }

  @Test("四个数组全空 = 干净的一天")
  func cleanDay() throws {
    let d = try #require(
      PayloadParser.digest(from: PayloadFixtures.cleanDiagnosticPayload(), kind: .diagnostic))
    #expect(d.incidents.isEmpty)
    #expect(d.crashCount == 0)
  }

  @Test("JSON 坏掉返回 nil，不是返回一个空摘要")
  func brokenJSON() {
    // 空摘要会被当成「今天没崩溃」写进证据，那是最坏的一种假阳性。
    #expect(PayloadParser.digest(from: Data("不是 JSON".utf8), kind: .metric) == nil)
    #expect(PayloadParser.digest(from: Data(), kind: .diagnostic) == nil)
    // 顶层是数组也不行——我们要的是对象。
    #expect(PayloadParser.digest(from: Data("[1,2,3]".utf8), kind: .metric) == nil)
  }

  @Test("摘要能 Codable 往返")
  func codableRoundTrip() throws {
    let d = try #require(
      PayloadParser.digest(from: PayloadFixtures.metricPayload(), kind: .metric))
    let data = try DiagnosticsStore.encoder.encode(d)
    let back = try DiagnosticsStore.decoder.decode(PayloadDigest.self, from: data)
    #expect(back == d)
  }
}
