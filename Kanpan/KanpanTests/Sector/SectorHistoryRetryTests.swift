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

  /// 审查 D-04：原来这份是板块页自己的 `@State`，底栏每切回来一次就新建一份、立刻重拉。
  /// 现在由 `SectorFeed`（宿主持有）带着，进出页面只是开关循环，一小时内不再重取。
  @Test("进出板块页三趟，一小时里只向后端取一次")
  func revisitsDoNotRefetch() async throws {
    let feed = SectorFeed(route: RouteResolver(policy: .direct))
    feed.fetchTickers = { _ in throw CancellationError() }   // 全市场行情那一路不出网
    let calls = FetchCounter()
    let asof = Self.todayUTC()
    feed.daily.fetch = { _ in
      await calls.bump()
      return Data(#"{"data":{"asof":"\#(asof)","symbols":{"BTCUSDT":{"c5":100,"c20":90}}}}"#.utf8)
    }
    feed.daily.configure(backend: BackendClient(hosts: ["127.0.0.1:9"]))
    feed.setVisible(true)
    // 单测跑在模拟器上的 app 宿主里，Caches 里可能躺着前几天真跑留下的那份（asof 是旧日期），
    // 而磁盘那份先于网络那份顶上来：等「非空」会在磁盘那份一到就放行，拿旧日期去比今天就红。
    // 要等的是网络那份（今天）真的装进去。
    for _ in 0..<300 where feed.daily.history.asof != asof { try await Task.sleep(for: .milliseconds(10)) }
    #expect(feed.daily.history.asof == asof)
    for _ in 0..<3 {
      feed.setVisible(false)
      feed.setVisible(true)
      try await Task.sleep(for: .milliseconds(50))
    }
    feed.setVisible(false)
    #expect(await calls.count == 1, "进出页面又去后端重拉了")
  }

  private static func todayUTC() -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
  }
}

private actor FetchCounter {
  private(set) var count = 0
  func bump() { count += 1 }
}
