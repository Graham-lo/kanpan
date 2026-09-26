import Foundation
import Testing
@testable import Kanpan

/// 压测 M3：分享时间串的解析器整个进程只建一份，结果与原来逐次新建的一致，多线程同时用不出错。
@Suite struct ShareDatesTests {
  private func item(_ createdAt: String) -> ShareItem {
    ShareItem(id: "s", from: "qa_friend", symbol: "BTCUSDT", market: "binance/usd_m", interval: .h1,
              view: ShareWindow(from: 0, to: 1), drawings: [], alerted: [], createdAt: createdAt)
  }

  @Test func parserIsBuiltOnceNotPerCall() {
    let before = ShareDates.identities
    for _ in 0..<500 { _ = item("2026-09-22T00:00:00.123456Z").createdDate }
    #expect(ShareDates.identities == before)
    #expect(Set(before).count == 2)
  }

  @Test func fiveHundredCreatedDatesMatchTheOldParser() {
    // 对照组照原来的写法：每次新建，先认小数秒、认不出再认整秒。
    func reference(_ raw: String) -> Date? {
      let parser = ISO8601DateFormatter()
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return parser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    let plain = ISO8601DateFormatter()
    let base = Date(timeIntervalSince1970: 1_790_000_000)
    var parsed = 0
    for index in 0..<500 {
      let whole = plain.string(from: base.addingTimeInterval(Double(index) * 61))
      let raw: String = switch index % 3 {
      case 0: whole
      case 1: whole.replacingOccurrences(of: "Z", with: ".\(String(format: "%03d", index % 1000))Z")
      default: whole.replacingOccurrences(of: "Z", with: ".\(String(format: "%06d", index * 1987 % 1_000_000))Z")
      }
      let got = item(raw).createdDate
      let want = reference(raw)
      #expect(got == want, "\(raw)")
      if got != nil { parsed += 1 }
    }
    #expect(parsed == 500)
    #expect(ShareItem.date("not a date") == nil)
  }

  @Test func stampRoundTripsThroughTheParser() {
    let now = Date(timeIntervalSince1970: 1_790_000_123)
    let stamp = ShareDates.stamp(now)
    #expect(stamp == ISO8601DateFormatter().string(from: now))
    #expect(ShareItem.date(stamp) == now)
  }

  @Test func concurrentParsingIsSafe() async {
    let raw = "2026-09-22T08:30:15.250Z"
    let want = ShareItem.date(raw)
    #expect(want != nil)
    let results = await withTaskGroup(of: Int.self) { group in
      for _ in 0..<8 {
        group.addTask {
          var ok = 0
          for _ in 0..<250 where ShareItem.date(raw) == want && ShareDates.stamp(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00Z" { ok += 1 }
          return ok
        }
      }
      return await group.reduce(0, +)
    }
    #expect(results == 2000)
  }
}
