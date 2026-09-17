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


