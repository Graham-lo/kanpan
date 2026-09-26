import Foundation
import Observation
import Testing
import ReviewDomain
import ReviewData
@testable import ReviewUI

// ============================================================ 角标与战绩卡的几个数：记录变了才数（压测 2026-09-26 第 8 项）
//
// 原来 `pendingCount` 是计算属性，每读一次把全部记录过滤一遍；复盘本一次 body 读两遍（筹码条），
// 战绩卡再 `filter` 三遍（没作废的、判对的、判错的）——一次 body 扫 5 遍记录。
// 现在 `records` 一变就一趟数完，数没变不赋值。这里只数「真数过几趟」和数对不对，不量墙钟。

private final class Fired: @unchecked Sendable { var value = false }

@MainActor @Suite("复盘：待处理数与战绩一趟数完、按记录缓存")
struct ReviewTallyTests {
  static let total = 1000

  private func draft(_ n: Int) -> ReviewDraft {
    let step: Int64 = 3_600_000
    let end = (ReviewClock.now / step) * step
    let range = ReviewRange(symbol: "BTCUSDT", interval: "1h", start: end - step * 48, end: end, bars: 48)
    var value = ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: ReviewClock.now - Int64(n) * 1000)
    value.text = "第 \(n) 条"
    return value
  }

  /// 四种样子轮着来：判对没写复盘（欠着）、判错写完了（已判定）、同步出错（欠着）、还在等；每十条作废一条。
  private func rig() throws -> (ReviewFeature, [ReviewRecord], URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    let local: [ReviewRecord] = (0..<Self.total).map { n in
      var record = ReviewRecord(draft: draft(n))
      record.serverId = record.id
      switch n % 4 {
      case 0: record.assessment = ReviewAssessment(outcome: .realized, reason: "到了", assessedAt: 1)
      case 1:
        record.assessment = ReviewAssessment(outcome: .unrealized, reason: "没到", assessedAt: 1)
        record.reflection.publishedAt = 2
      case 2: record.syncError = "网络"
      default: break
      }
      if n % 10 == 9 { record.voided = true }
      return record
    }
    try store.transaction { $0.records = local }
    let feature = ReviewFeature()
    feature.activate(store: store, client: nil)
    return (feature, local, directory)
  }

  @Test("数和原来逐个 filter 出来的一样；读多少遍都不再扫记录")
  func equivalentAndCached() throws {
    let (feature, local, directory) = try rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    let records = feature.records
    #expect(records.count == local.count)

    // 原来的算法：角标 / 筹码条一次 filter，战绩卡三次。
    let live = records.filter { !$0.voided }
    #expect(feature.pendingCount == records.filter(\.needsAction).count)
    #expect(feature.tally.live == live.count)
    #expect(feature.tally.realized == live.filter { $0.outcome == .realized }.count)
    #expect(feature.tally.unrealized == live.filter { $0.outcome == .unrealized }.count)
    #expect(feature.pendingCount > 0 && feature.tally.realized > 0 && feature.tally.unrealized > 0)

    // 复盘本 body 重算 100 次（每次原来要扫 5 遍 = 5000 条）：一趟都不再数。
    let passes = feature.tallyPasses
    for _ in 0..<100 {
      _ = feature.pendingCount; _ = feature.pendingCount
      _ = feature.tally.live; _ = feature.tally.realized; _ = feature.tally.unrealized
    }
    #expect(feature.tallyPasses == passes)
    print("[review-tally] 修前 100 次 body 扫记录 \(100 * 5) 遍（每遍 \(records.count) 条）；修后 \(feature.tallyPasses - passes) 遍")
  }

  @Test("记录变一次数一趟；待处理数没变，读角标的视图不收到通知")
  func recountsOnlyOnChange() throws {
    let (feature, _, directory) = try rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    let pending = feature.pendingCount, live = feature.tally.live
    let passes = feature.tallyPasses

    // 记一笔新的：还在等答案，不欠人处理——记录变了，待处理数不变。
    let badge = Fired()
    withObservationTracking { _ = feature.pendingCount } onChange: { badge.value = true }
    feature.begin(draft(5000))
    #expect(feature.saveRecord())
    #expect(feature.tallyPasses > passes, "记录变了要重数")
    #expect(feature.tally.live == live + 1)
    #expect(feature.pendingCount == pending)
    #expect(!badge.value, "待处理数没变，角标不该被叫去重画")

    // 作废一条欠着的：待处理数少一。
    let owed = try #require(feature.records.first { $0.needsAction })
    let changed = Fired()
    withObservationTracking { _ = feature.pendingCount } onChange: { changed.value = true }
    feature.voidRecord(owed.id)
    #expect(feature.pendingCount == pending - 1)
    #expect(feature.tally.live == live)
    #expect(changed.value)
    #expect(feature.pendingCount == feature.records.filter(\.needsAction).count)
  }
}
