import Foundation
import Testing

@testable import Kanpan

/// 板块「5 日」日线收盘取数的重试节奏（审查 P2-6）：失败后 5 秒起按 3 倍退避，封顶 10 分钟。
@Suite("板块日线收盘重试")
@MainActor
struct SectorHistoryRetryTests {
  @Test("没失败就按 10 分钟一拍")
  func steadyCadence() {
    #expect(SectorHistoryFeed.retryDelay(failures: 0) == SectorHistoryFeed.tickSeconds)
  }

  @Test("失败后 5、15、45、135、405 秒，再往后封顶 10 分钟")
  func backsOffAndCaps() {
    let delays = (1...8).map { SectorHistoryFeed.retryDelay(failures: $0) }
    #expect(delays == [5, 15, 45, 135, 405, 600, 600, 600])
    #expect(SectorHistoryFeed.retryDelay(failures: 10_000) == 600, "一直失败也不会越问越密，更不会溢出")
  }
}
