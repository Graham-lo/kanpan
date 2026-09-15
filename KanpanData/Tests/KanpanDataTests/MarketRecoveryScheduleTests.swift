import Foundation
import Testing
@testable import KanpanData

struct MarketRecoveryScheduleTests {
  @Test func reopeningDoesNotProbeAndFailuresBackOff() {
    let now = Date(timeIntervalSince1970: 1000)
    var schedule = MarketRecoverySchedule(now: now)
    #expect(!schedule.isDue(at: now.addingTimeInterval(299)))
    #expect(schedule.isDue(at: now.addingTimeInterval(300)))
    let first = schedule.record(healthy: false, at: now.addingTimeInterval(300))
    #expect(!first)
    #expect(!schedule.isDue(at: now.addingTimeInterval(599)))
    let second = schedule.record(healthy: false, at: now.addingTimeInterval(600))
    #expect(!second)
    #expect(!schedule.isDue(at: now.addingTimeInterval(1199)))
    let third = schedule.record(healthy: false, at: now.addingTimeInterval(1200))
    #expect(!third)
    #expect(schedule.nextAttempt == now.addingTimeInterval(2100))
  }
  @Test func recoveryRequiresTwoCompleteSuccessesAndFlapsDoNotSpam() {
    let now = Date(timeIntervalSince1970: 1000)
    var schedule = MarketRecoverySchedule(now: now)
    schedule.networkRestored(at: now)
    #expect(schedule.isDue(at: now))
    let first = schedule.record(healthy: true, at: now)
    #expect(!first)
    schedule.networkRestored(at: now.addingTimeInterval(1))
    #expect(!schedule.isDue(at: now.addingTimeInterval(9)))
    let confirmed = schedule.record(healthy: true, at: now.addingTimeInterval(10))
    #expect(confirmed)
    let failed = schedule.record(healthy: false, at: now.addingTimeInterval(20))
    #expect(!failed)
    #expect(!schedule.confirming)
  }
}
