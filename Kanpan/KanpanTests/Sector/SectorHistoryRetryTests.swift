import Foundation
import KanpanNetwork
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

  /// 停在板块页进后台：SwiftUI 不发 `onDisappear`，循环只能靠前后台这一位停（整机压测 2026-09-26）。
  @Test("进了后台取数循环就停，后台里重进页也不起，回前台再起")
  func stopsInBackground() {
    let feed = SectorHistoryFeed()
    // 本机必然拒连的地址：循环真的挂上，但一口请求也出不了这台机器。
    feed.configure(backend: BackendClient(hosts: ["127.0.0.1:9"]))
    feed.setVisible(true)
    #expect(feed.isRunning, "前提：前台可见时循环在跑")
    feed.setForeground(false)
    #expect(!feed.isRunning, "进了后台，5 日收盘的取数循环还挂着")
    feed.setVisible(false); feed.setVisible(true)
    #expect(!feed.isRunning, "后台里页面重挂，循环又被拉起来了")
    feed.setForeground(true)
    #expect(feed.isRunning)
    feed.setVisible(false)
    #expect(!feed.isRunning)
  }
}
