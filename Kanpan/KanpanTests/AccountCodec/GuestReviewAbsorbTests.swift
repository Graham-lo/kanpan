import Foundation
import Testing
import ReviewDomain
import ReviewData

@testable import Kanpan

/// 访客的复盘并进账号（`AppAccountBridge.absorbGuestReview`，登录那一下在主线程上跑）。
///
/// 规矩：只收访客本机独有（没 serverId）、账号里还没有的记录；待发操作只收挂在本机独有记录上的、
/// 账号队列里还没有的；新建那一笔 body 洗一遍。压测那条只看结构（条数、无重复、谁进谁不进），耗时只打印。
@Suite("访客复盘并进账号")
struct GuestReviewAbsorbTests {

  private func draft(_ id: UUID = UUID(), text: String = "") -> ReviewDraft {
    var value = ReviewDraft(range: ReviewRange(symbol: "BTCUSDT", interval: "1m", start: 0, end: 180_000, bars: 3),
                            reference: 100, high: 110, low: 90, now: 1_700_000_000_000)
    value.id = id; value.text = text
    return value
  }
  private func record(_ id: UUID = UUID(), server: Bool = false) -> ReviewRecord {
    var value = ReviewRecord(draft: draft(id))
    if server { value.serverId = UUID() }
    return value
  }
  private func create(_ record: ReviewRecord) throws -> ReviewOperation {
    var op = ReviewOperation(recordId: record.id, kind: "create", body: try JSONEncoder().encode(record.draft))
    op.attempted = true
    return op
  }
  private let mark: (ReviewDraft) -> ReviewDraft = { var d = $0; d.text = "洗过"; return d }

  @Test("谁进谁不进：本机独有的新记录与它的操作进；已同步的、账号里已有的、队列里已有的都不进")
  func absorbsOnlyLocalOnlyNewcomers() throws {
    let accountLocal = record(), accountSynced = record(server: true)
    var account = ReviewArchive()
    account.records = [accountLocal, accountSynced]
    let alreadyQueued = try create(accountLocal)
    account.queue = [alreadyQueued]

    let fresh = record(), synced = record(server: true)
    let duplicate = ReviewRecord(draft: draft(accountLocal.id, text: "访客那份"))
    var guest = ReviewArchive()
    guest.records = [fresh, synced, duplicate]
    let freshCreate = try create(fresh)
    let onSynced = try create(synced)
    let onAccountLocal = ReviewOperation(recordId: accountLocal.id, kind: "review", body: Data("{}".utf8))
    let onAccountSynced = ReviewOperation(recordId: accountSynced.id, kind: "review", body: Data("{}".utf8))
    guest.queue = [freshCreate, onSynced, alreadyQueued, onAccountLocal, onAccountSynced, freshCreate]

    try AppAccountBridge.absorbGuestReview(guest, into: &account, sanitize: mark)

    #expect(account.records.map(\.id) == [accountLocal.id, accountSynced.id, fresh.id])
    #expect(account.records.first { $0.id == accountLocal.id }?.draft.text == "", "账号里已有的那条被访客那份盖了")
    #expect(account.records.last?.draft.text == "洗过")
    #expect(account.queue.map(\.id) == [alreadyQueued.id, freshCreate.id, onAccountLocal.id])
    let body = try JSONDecoder().decode(ReviewDraft.self, from: account.queue[1].body)
    #expect(body.text == "洗过")
    #expect(account.queue[1].attempted == nil)
  }

  @Test("访客 4000 条 + 4000 笔新建，账号 3000 条（200 条已同步）+ 2800 笔：条数、去重逐条对得上")
  func absorbsAtScale() throws {
    var account = ReviewArchive()
    account.records = (0..<3000).map { record(server: $0 < 200) }
    account.queue = try account.records.filter { $0.serverId == nil }.map(create)
    var guest = ReviewArchive()
    guest.records = (0..<4000).map { _ in record() } + account.records.prefix(500)
    guest.queue = try guest.records.prefix(4000).map(create) + account.queue.prefix(300)

    let clock = ContinuousClock()
    let elapsed = try clock.measure { try AppAccountBridge.absorbGuestReview(guest, into: &account, sanitize: { $0 }) }
    #expect(account.records.count == 7000)
    #expect(Set(account.records.map(\.id)).count == 7000)
    #expect(account.queue.count == 6800)
    #expect(Set(account.queue.map(\.id)).count == 6800)
    print("GUEST-REVIEW-ABSORB guest=4000 account=3000 elapsed=\(elapsed)")
  }
}
