import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 冷启动接回锁屏实时活动（压测收尾 2026-09-26，整机线移交第 4 项）。
///
/// 原来 `adopt` 在 `boot()` 里、账号桥装档案之前调，拿的是设备级（访客）那份提醒表，
/// 登录用户的活动一个都对不上，被当场结束；而且只看 `Activity.activities.first`，
/// 第二块起一律不管。现在按档案主人的提醒表、挨个看全部，账号没核完时对不上的先放着。
@Suite("提醒 · 冷启动接回实时活动")
@MainActor
struct AlertActivityAdoptTests {
  private static let btc = "binance/usd_m/BTCUSDT"
  private static let eth = "binance/usd_m/ETHUSDT"

  private func alert(_ symbol: String, paused: Bool = false) -> KanpanCore.Alert {
    var a = KanpanCore.Alert.price(symbol: symbol, target: 100, current: 90, label: "100", now: 1_000)
    if paused { a.status = .paused }
    return a
  }
  private func activity(_ id: String, for alert: KanpanCore.Alert) -> (id: String, alertID: String) {
    (id, AlertActivityController.syncID(alert))
  }

  @Test("修前那条路：设备级表里没有登录用户的提醒——账号没核完时一块都不收")
  func unsettledKeepsWhatItCannotMatchYet() {
    let mine = alert(Self.btc)   // 登录用户档案里的那条
    let guestTable: [KanpanCore.Alert] = []
    let plan = AlertActivityController.adoptPlan(activities: [activity("A1", for: mine)], alerts: guestTable,
                                                 attachedID: nil, settled: false)
    #expect(plan == .init(attach: nil, end: []), "档案还没到就把登录用户的活动收了")
  }

  @Test("档案到了：按档案主人的表接回")
  func profileTableAttaches() {
    let mine = alert(Self.btc)
    let plan = AlertActivityController.adoptPlan(activities: [activity("A1", for: mine)], alerts: [mine],
                                                 attachedID: nil, settled: false)
    #expect(plan == .init(attach: ("A1", mine.id), end: []))
  }

  @Test("挨个看全部：第一块对不上、第二块对得上，接第二块；账号核完后第一块收掉")
  func iteratesAllActivities() {
    let gone = alert(Self.eth)       // 早就删了的那条（不在表里）
    let mine = alert(Self.btc)
    let live = [activity("A1", for: gone), activity("A2", for: mine)]
    let early = AlertActivityController.adoptPlan(activities: live, alerts: [mine], attachedID: nil, settled: false)
    #expect(early == .init(attach: ("A2", mine.id), end: []))
    let settled = AlertActivityController.adoptPlan(activities: live, alerts: [mine], attachedID: "A2", settled: true)
    #expect(settled == .init(attach: nil, end: ["A1"]))
  }

  @Test("一台设备只挂一块：两块都对得上时接第一块、收第二块；暂停的提醒不接")
  func oneBlockPerDevice() {
    let a = alert(Self.btc), b = alert(Self.eth), off = alert(Self.btc, paused: true)
    let live = [activity("A1", for: a), activity("A2", for: b), activity("A3", for: off)]
    let early = AlertActivityController.adoptPlan(activities: live, alerts: [a, b, off], attachedID: nil, settled: false)
    #expect(early == .init(attach: ("A1", a.id), end: ["A2"]))
    let late = AlertActivityController.adoptPlan(activities: live, alerts: [a, b, off], attachedID: "A1", settled: true)
    #expect(late == .init(attach: nil, end: ["A2", "A3"]))
  }

  @Test("访客 / 没有账号桥：账号即刻落定，对不上的当场收")
  func settledGuestEndsStrays() {
    let stray = alert(Self.btc)
    let plan = AlertActivityController.adoptPlan(activities: [activity("A1", for: stray)], alerts: [],
                                                 attachedID: nil, settled: true)
    #expect(plan == .init(attach: nil, end: ["A1"]))
  }
}
