import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 回放取数留哪几根（审查 R12）：刚平仓的一笔，平仓那根还没收线也得留在卷里。
@MainActor
struct ReviewBridgeTapeTests {
  @Test func replayIncludesFormingBar() {
    let step = Interval.m1.stepMs
    let forming: Int64 = 1_790_000_000_000 // 这一根已开盘、还没收
    let now = forming + step / 2           // 交易回放的上限是「现在」
    // 交易回放：开了盘的这根留下。
    #expect(ReviewChartBridge.tapeKeeps(openTime: forming, interval: .m1, end: now, includeForming: true))
    // 收完的前一根照留，还没开盘的下一根不留。
    #expect(ReviewChartBridge.tapeKeeps(openTime: forming - step, interval: .m1, end: now, includeForming: true))
    #expect(!ReviewChartBridge.tapeKeeps(openTime: forming + step, interval: .m1, end: now, includeForming: true))
    // 上限正好落在收线时刻（交易早已平仓、取到平仓后第 5 根为止）：最后一根收完的仍留、下一根不留。
    #expect(ReviewChartBridge.tapeKeeps(openTime: forming, interval: .m1, end: forming + step, includeForming: true))
    #expect(!ReviewChartBridge.tapeKeeps(openTime: forming + step, interval: .m1, end: forming + step, includeForming: true))
    // 笔记重温不变：没收完的那根不当历史。
    #expect(!ReviewChartBridge.tapeKeeps(openTime: forming, interval: .m1, end: now, includeForming: false))
    #expect(ReviewChartBridge.tapeKeeps(openTime: forming - step, interval: .m1, end: now, includeForming: false))
  }
}
