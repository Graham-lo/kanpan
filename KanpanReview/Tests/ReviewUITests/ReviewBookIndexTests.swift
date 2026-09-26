import Foundation
import Testing
import ReviewDomain
import ReviewData
@testable import ReviewUI

// ============================================================ 复盘本那一列按输入缓存（压测 2026-09-26 第 7 项）
//
// 原来 `bookRecords` 每读一次都把服务端那一页逐条 `records.first(where:)` 找本机那份（H × R 次比较），
// 复盘本 body 一次读三遍（待处理 / 等答案 / 空状态），搜索框每敲一字又同步重算一遍。
// 现在：按 id 建一次索引、整列按输入缓存、过滤分组一趟做完、搜索词停手 200ms 才落定。
// 这里只数「真拼过几次」和结果对不对，不量墙钟。

/// 手拨的去抖钟：`sleep` 一直挂着，测试 `fire()` 才醒。
@MainActor final class ManualDebounceClock {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  var sleeping: Int { waiters.count }
  func sleep() async { await withCheckedContinuation { waiters.append($0) } }
  func fire() { let all = waiters; waiters = []; all.forEach { $0.resume() } }
}

@MainActor @Suite("复盘本：索引 + 按输入缓存 + 搜索去抖")
struct ReviewBookIndexTests {
  static let total = 1000
  static let hits = 200

  private func draft(_ n: Int) -> ReviewDraft {
    let step: Int64 = 3_600_000
    let end = (ReviewClock.now / step) * step
    let symbol = n % 3 == 0 ? "BTCUSDT" : (n % 3 == 1 ? "ETHUSDT" : "SOLUSDT")
    let range = ReviewRange(symbol: symbol, interval: "1h", start: end - step * 48, end: end, bars: 48)
    var value = ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: ReviewClock.now - Int64(n) * 1000)
    value.text = "第 \(n) 条"
    return value
  }

  /// 本机 1000 条（前 950 条已经在云端，后 50 条只在本机）；服务端这一页是其中每隔 5 条挑的 200 条。
  private func rig() async throws -> (ReviewFeature, ReviewStore, FakeReviewServer, [ReviewRecord], URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ReviewStore(directory: directory.appendingPathComponent("account"))
    let local: [ReviewRecord] = (0..<Self.total).map { n in
      var record = ReviewRecord(draft: draft(n))
      if n < Self.total - 50 { record.serverId = record.id }
      return record
    }
    try store.transaction { $0.records = local }
    let server = FakeReviewServer()
    for n in stride(from: 0, to: Self.total, by: Self.total / Self.hits) {
      var remote = local[n]; remote.revision = 3
      server.records[remote.id] = remote; server.page0.append(remote.id)
    }
    let feature = ReviewFeature()
    feature.activate(store: store, client: ScorebookClient(transport: server.transport))
    feature.autoSync = false
    await feature.loadHistory()
    return (feature, store, server, local, directory)
  }

  /// 原来那份算法原样搬过来，外加一个比较计数：修前每读一次 `bookRecords` 要比较多少次。
  private static func legacy(records: [ReviewRecord], history: [ReviewRecord], pending: Set<UUID>,
                             query: String) -> (rows: [ReviewRecord], comparisons: Int) {
    var comparisons = 0
    let page = history.map { item -> ReviewRecord in
      guard let local = records.first(where: { comparisons += 1; return $0.id == item.id }) else { return item }
      return pending.contains(item.id) || local.conflict != nil ? local : item
    }
    guard query.isEmpty else { return (page, comparisons) }
    let known = Set(page.map(\.id))
    let extras = records.filter { !known.contains($0.id) && (pending.contains($0.id) || $0.serverId == nil || $0.conflict != nil) }
    guard !extras.isEmpty else { return (page, comparisons) }
    return ((page + extras).sorted { $0.draft.created > $1.draft.created }, comparisons)
  }

  @Test("1000 条记录 × 200 条服务端页：结果和原算法一致，一次 body 读三遍只拼一次")
  func cachedAndEquivalent() async throws {
    let (feature, store, _, _, directory) = try await rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(feature.history.count == Self.hits)

    let before = feature.bookBuilds, indexBefore = feature.indexBuilds
    // 一次 body 原来读三遍：待处理、等答案、空状态。
    let first = feature.bookRecords
    _ = feature.bookRecords; _ = feature.bookRecords
    #expect(feature.bookBuilds - before == 1, "输入没变，读三遍只该拼一次")
    #expect(feature.indexBuilds - indexBefore == 1, "按 id 的索引只建一次")

    let pending = Set(store.archive.queue.map(\.recordId))
    let old = Self.legacy(records: feature.records, history: feature.history, pending: pending, query: "")
    #expect(first.map(\.id) == old.rows.map(\.id), "拼出来的那一列必须和原来一模一样")
    #expect(first.count == Self.hits + 40, "服务端 200 条 + 只在本机、又不在这一页里的 40 条")
    // 修前：每读一次比较这么多次，body 三遍再乘 3。修后：零次线性比较，只有一次建索引（1000 次插入）+ 200 次查表。
    print("[review-book] 修前每读一次 bookRecords 比较 \(old.comparisons) 次，一次 body ×3 = \(old.comparisons * 3)；修后同一次 body 拼 \(feature.bookBuilds - before) 次、索引建 \(feature.indexBuilds - indexBefore) 次")
    #expect(old.comparisons == 99_700)

    // 再读十遍（相当于十次 body 重算，比如同步时 `syncing` 翻来翻去）：一次都不重拼。
    for _ in 0..<10 { _ = feature.bookRecords }
    #expect(feature.bookBuilds - before == 1)
  }

  @Test("记录、服务端页、队列变了才失效；变一次只重拼一次")
  func invalidatesOnInputs() async throws {
    let (feature, _, _, _, directory) = try await rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    _ = feature.bookRecords
    let base = feature.bookBuilds, indexBase = feature.indexBuilds

    // 记一笔：records 与队列一起变。
    let fresh = draft(5000)
    feature.begin(fresh)
    #expect(feature.saveRecord())
    let after = feature.bookRecords
    _ = feature.bookRecords
    #expect(after.contains { $0.id == fresh.id }, "刚记的那条要在复盘本上")
    #expect(feature.bookBuilds - base == 1)
    #expect(feature.indexBuilds - indexBase == 1)

    // 服务端页重拉：history 变了，索引不用重建。
    await feature.loadHistory()
    _ = feature.bookRecords; _ = feature.bookRecords
    #expect(feature.bookBuilds - base == 2)
    #expect(feature.indexBuilds - indexBase == 1, "本机记录没变，索引不重建")

    // 点进一条详情走的是同一份索引，不再线性找。
    #expect(feature.record(fresh.id)?.id == fresh.id)
    #expect(feature.indexBuilds - indexBase == 1)
  }

  @Test("过滤 + 分组一趟做完、按输入缓存")
  func sectionsCached() async throws {
    let (feature, _, _, _, directory) = try await rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    let before = feature.sectionBuilds
    let sections = feature.bookSections
    _ = feature.bookSections; _ = feature.bookSections
    #expect(feature.sectionBuilds - before == 1)
    #expect(sections.all.count == feature.bookRecords.count)
    #expect(sections.pending.allSatisfy { $0.needsAction })
    #expect(sections.waiting.allSatisfy { $0.outcome == .waiting && !$0.needsAction })
    #expect(sections.pending.count + sections.waiting.count == sections.all.filter { $0.needsAction || $0.outcome == .waiting }.count)
  }

  @Test("搜索去抖：连敲三字只落定一次，落定前列表不重算，落定后按最后那串过滤")
  func searchIsDebounced() async throws {
    let (feature, _, _, _, directory) = try await rig()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = ManualDebounceClock()
    feature.bookSearchSleep = { _ in await clock.sleep() }
    _ = feature.bookSections
    let sectionsBefore = feature.sectionBuilds, commitsBefore = feature.bookQueryCommits

    feature.bookSearchText = "B"; feature.bookSearchText = "BT"; feature.bookSearchText = "BTC"
    // 三次各起一个等待，前两个已经被掐掉。等它们都挂到钟上再看。
    for _ in 0..<200 where clock.sleeping < 3 { await Task.yield() }
    #expect(clock.sleeping == 3)
    #expect(feature.bookQuery.isEmpty, "还没停手，搜索词不落定")
    _ = feature.bookSections; _ = feature.bookSections
    #expect(feature.sectionBuilds == sectionsBefore, "敲字期间列表一次都不重算")

    clock.fire()
    await feature.settleBookSearch()
    for _ in 0..<20 { await Task.yield() }
    #expect(feature.bookQuery == "BTC")
    #expect(feature.bookQueryCommits - commitsBefore == 1, "三字只落定一次（按最后一次输入）")
    let hits = feature.bookSections
    _ = feature.bookSections
    #expect(feature.sectionBuilds - sectionsBefore == 1)
    #expect(!hits.all.isEmpty && hits.all.allSatisfy { $0.draft.range.symbol.localizedCaseInsensitiveContains("BTC") })

    // 清空不等：一下子回到全表。
    feature.bookSearchText = ""
    #expect(feature.bookQuery.isEmpty)
    #expect(feature.bookSections.all.count == feature.bookRecords.count)

    // 关掉复盘本，搜索框回到空。
    feature.bookOpen = true
    feature.bookSearchText = "ETH"
    feature.bookOpen = false
    #expect(feature.bookSearchText.isEmpty && feature.bookQuery.isEmpty)
    clock.fire()
  }
}
