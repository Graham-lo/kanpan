import Foundation
import Testing
@testable import KanpanData
import KanpanCore
import KanpanNetworkTestSupport

// 数据层自己的测试辅助：fixture 与造数据。网络、时钟、socket 的假件在
// `KanpanNetworkTestSupport`（随 `KanpanNetwork` 包），两边测试共用同一份。

// ---------------------------------------------------------------- 取 fixture

public enum Fixture {
  public static func url(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/" + (name as NSString).deletingPathExtension,
                      withExtension: (name as NSString).pathExtension)!
  }
  public static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }
  public static func text(_ name: String) -> String { String(decoding: data(name), as: UTF8.self) }
  public static func lines(_ name: String) -> [String] {
    text(name).split(separator: "\n").map(String.init)
  }
}

// ---------------------------------------------------------------- 造数据

public func makeBars(t0: Int64, step: Int64, count: Int, base: Double = 100) -> [Bar] {
  (0..<count).map { i in
    let x = base + Double(i)
    return Bar(openTime: t0 + Int64(i) * step, open: x, high: x + 1, low: x - 1,
               close: x + 0.5, volume: Double(10 + i))
  }
}

public func makeSeries(_ symbol: String, _ iv: Interval, count: Int, t0: Int64 = 1_700_000_000_000) -> BarSeries {
  BarSeries(symbol: symbol, interval: iv, bars: makeBars(t0: t0, step: iv.stepMs, count: count))
}

/// 停在 `ms`（毫秒）之后 `aheadMs` 的墙上时钟。
///
/// 夹具的 K 线都在 2023 年（`t0 = 1_700_000_000_000`），而 `MarketFeed` 判「快照离现在多远」
/// 「缺口有几根」用的是墙上时钟：拿真的 `Date()` 去比，快照一律「太旧」、缺口一律「太长」，
/// 用例验的补缺路径根本走不到。要走补缺那一路的用例，把时钟钉在夹具末根附近。
public func clock(near ms: Int64, aheadMs: Int64 = 60_000) -> @Sendable () -> Date {
  let at = Date(timeIntervalSince1970: Double(ms + aheadMs) / 1000)
  return { at }
}



// ---------------------------------------------------------------- 稳态

/// 等 feed 把启动期的异步尾巴都跑完：首屏那一发落了地、补缺不在途、缺口不欠着。
///
/// 为什么非等不可：WS 的 `.connected` 一旦排在首屏之后才被处理，`MarketFeed` 就会为
/// 「REST 快照到 WS 连上」之间那一段派一发补缺——生产上那段确实缺，所以这是对的。
/// 但补缺期间 WS 帧只排进合成器的队列，落地时统一走 `.series`，一条 `.lastBar` 都不发。
/// 用例要是在这之前就放报文进来、或者开始数补缺请求，量到的就是机器快慢而不是行为。
///
/// 调用前先确认 `.connected` 已经被处理过（等一次 `.status(.live)`：WS 连上就紧跟着
/// 发它，而 feed 处理事件是顺序的），否则这里可能在补缺开始之前就判定稳态。
@discardableResult
public func waitForSteadyState(_ feed: MarketFeed, timeout: Double = 15) async -> Bool {
  // `&&` 的右边是不支持并发的 autoclosure，两个 await 不能串在一句里。
  await waitUntil(timeout) {
    if await feed.isFillingForTests { return false }
    if await feed.isBackfillingForTests { return false }
    return await feed.pendingGapForTests == 0
  }
}
