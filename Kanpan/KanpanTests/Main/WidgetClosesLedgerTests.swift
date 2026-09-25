import Foundation
import Testing

@testable import Kanpan

/// 小组件折线的取数账本（审查 P2-5）：收下的那份只能越来越新；切后台掐掉的回前台立刻重取。
/// （`#expect` 里不能调 mutating 方法，所以先落到 let 再断言。）
@Suite("小组件折线取数账本")
struct WidgetClosesLedgerTests {
  let t0 = Date(timeIntervalSince1970: 1_800_000_000)
  func ledger() -> WidgetClosesLedger { WidgetClosesLedger(every: 900, retry: 60, concurrency: 2) }

  @Test("同一只一次只有一笔在路上，并发不超过上限，一刻钟内不再取")
  func gatesByInFlightConcurrencyAndDue() throws {
    var l = ledger()
    let aTicket = l.begin("A", now: t0)
    let a = try #require(aTicket)
    let againA = l.begin("A", now: t0)
    #expect(againA == nil, "A 在路上")
    let b = l.begin("B", now: t0)
    #expect(b != nil)
    let c = l.begin("C", now: t0)
    #expect(c == nil, "并发满了")
    let done = l.finish(a, success: true, now: t0 + 1)
    #expect(done)
    let early = l.begin("A", now: t0 + 60)
    #expect(early == nil, "一刻钟内不再取")
    let due = l.begin("A", now: t0 + 900)
    #expect(due != nil)
  }

  @Test("取不到一分钟后再来")
  func failureRetriesInAMinute() throws {
    var l = ledger()
    let aTicket = l.begin("A", now: t0)
    let a = try #require(aTicket)
    let done = l.finish(a, success: false, now: t0 + 5)
    #expect(done)
    let early = l.begin("A", now: t0 + 30)
    #expect(early == nil)
    let retry = l.begin("A", now: t0 + 65)
    #expect(retry != nil)
  }

  @Test("切后台掐掉的那笔：后到的结果不认，回前台立刻重取")
  func cancelledTicketIsDeadAndDueImmediately() throws {
    var l = ledger()
    let oldTicket = l.begin("A", now: t0)
    let old = try #require(oldTicket)
    l.cancelAll()
    let freshTicket = l.begin("A", now: t0 + 2)
    let fresh = try #require(freshTicket, "被掐掉的不该按「刚取过」再等一刻钟")
    let lateOld = l.finish(old, success: true, now: t0 + 3)
    #expect(!lateOld, "旧的那笔后到，不许盖掉")
    let tookFresh = l.finish(fresh, success: true, now: t0 + 4)
    #expect(tookFresh)
    #expect(l.acceptedAt["A"] == fresh.at)
  }

  @Test("收下的时刻单调递增：同一时刻连发的两笔，后一笔的票也比前一笔新")
  func acceptedIsMonotonic() throws {
    var l = WidgetClosesLedger(every: 0, retry: 0, concurrency: 2)
    let firstTicket = l.begin("A", now: t0)
    let first = try #require(firstTicket)
    let tookFirst = l.finish(first, success: true, now: t0)
    #expect(tookFirst)
    let secondTicket = l.begin("A", now: t0)
    let second = try #require(secondTicket)
    #expect(second.at > first.at)
    let tookSecond = l.finish(second, success: true, now: t0)
    #expect(tookSecond)
    #expect(l.acceptedAt["A"] == second.at)
    let twice = l.finish(second, success: true, now: t0 + 52)
    #expect(!twice, "同一张票回来两次，第二次不认")
  }
}
