import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

/// 快照的字节格式是**持久化格式**：手机上装着的那一版写下的文件，升级之后必须还读得出来。
/// 这一组用例把旧实现（逐字节 `Data.append`）吐出来的字节原样钉死在这儿，
/// 保证块式编解码那一轮改写没有动过格式。
@Suite("快照字节格式：新旧实现逐字节相同")
struct SnapshotFormatTests {

  /// 旧实现对下面 `equidistant()` 那条序列的输出，逐字节抄下来的。
  private let equiHex = "5241424b01000700425443555344540200316d0068e5cf8b01000060ea00000000000004000000000000000000005940000000000040594000000000008059400000000000c05940000000000040594000000000008059400000000000c059400000000000005a400000000000c05840000000000000594000000000004059400000000000805940000000000020594000000000006059400000000000a059400000000000e059400000000000002440000000000000264000000000000028400000000000002a40"

  /// 旧实现对 `monthly()` 的输出（1M 是不等距周期，带 openTime 表，flag=1）。
  private let monthlyHex = "5241424b01000700455448555344540200314d00082e888b01000000c87e9a000000000300000001000000000000594000000000004059400000000000805940000000000040594000000000008059400000000000c059400000000000c0584000000000000059400000000000405940000000000020594000000000006059400000000000a0594000000000000024400000000000002640000000000000284000082e888b01000000d0ac228c01000000982bbd8c010000"

  private func bar(_ i: Int, base: Int64, step: Int64) -> Bar {
    let d = Double(i)
    let t: Int64 = base + Int64(i) * step
    return Bar(openTime: t, open: 100.0 + d, high: 101.0 + d, low: 99.0 + d,
               close: 100.5 + d, volume: 10.0 + d)
  }

  private func equidistant() -> BarSeries {
    var bars: [Bar] = []
    for i in 0..<4 { bars.append(bar(i, base: 1_700_000_000_000, step: 60_000)) }
    return BarSeries(symbol: "BTCUSDT", interval: .m1, bars: bars)
  }

  private func monthly() -> BarSeries {
    var bars: [Bar] = []
    for i in 0..<3 { bars.append(bar(i, base: 1_698_796_800_000, step: 2_592_000_000)) }
    return BarSeries(symbol: "ETHUSDT", interval: .mo1, bars: bars)
  }

  private func bytes(_ hex: String) -> Data {
    var out = Data()
    var i = hex.startIndex
    while i < hex.endIndex {
      let j = hex.index(i, offsetBy: 2)
      out.append(UInt8(hex[i..<j], radix: 16)!)
      i = j
    }
    return out
  }

  private func same(_ a: BarSeries, _ b: BarSeries) -> Bool {
    a.symbol == b.symbol && a.interval == b.interval && a.t0 == b.t0 && a.step == b.step
      && a.open == b.open && a.high == b.high && a.low == b.low
      && a.close == b.close && a.volume == b.volume && a.openTime == b.openTime
  }

  @Test("等距周期：新编码逐字节等于旧编码")
  func equidistantEncodeMatches() {
    #expect(Snapshot.encode(equidistant()) == bytes(equiHex))
  }

  @Test("不等距周期（1M，带 openTime 表）：新编码逐字节等于旧编码")
  func monthlyEncodeMatches() {
    #expect(Snapshot.encode(monthly()) == bytes(monthlyHex))
  }

  @Test("旧实现写下的字节，新实现解得出来，而且解出来的东西完全一致")
  func decodesLegacyBytes() throws {
    let a = try #require(Snapshot.decode(bytes(equiHex)))
    #expect(same(a, equidistant()))
    #expect(a.openTime.isEmpty)

    let b = try #require(Snapshot.decode(bytes(monthlyHex)))
    #expect(same(b, monthly()))
    #expect(b.openTime.count == 3)
    #expect(b.openTime.first == 1_698_796_800_000)
  }

  @Test("截断、魔数不对、版本不对都要稳稳返回 nil")
  func rejectsGarbage() {
    let full = bytes(equiHex)
    #expect(Snapshot.decode(Data()) == nil)
    #expect(Snapshot.decode(full.prefix(3)) == nil)
    // 头齐了但列少了半截。
    #expect(Snapshot.decode(full.prefix(full.count - 9)) == nil)
    var wrongMagic = full
    wrongMagic[0] = 0x00
    #expect(Snapshot.decode(wrongMagic) == nil)
    var wrongVersion = full
    wrongVersion[4] = 0x09
    #expect(Snapshot.decode(wrongVersion) == nil)
  }

  @Test("空序列也编得出、解得回")
  func emptySeries() throws {
    let empty = BarSeries(symbol: "BTCUSDT", interval: .h1, bars: [])
    let decoded = try #require(Snapshot.decode(Snapshot.encode(empty)))
    #expect(decoded.count == 0)
    #expect(decoded.symbol == "BTCUSDT")
    #expect(decoded.interval == .h1)
  }

  @Test("超过 maxBars 的序列只留最后 3000 根，首尾对得上")
  func trimsToMaxBars() throws {
    var bars: [Bar] = []
    for i in 0..<(Snapshot.maxBars + 500) { bars.append(bar(i, base: 1_700_000_000_000, step: 60_000)) }
    let long = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: bars)
    let decoded = try #require(Snapshot.decode(Snapshot.encode(long)))
    #expect(decoded.count == Snapshot.maxBars)
    #expect(decoded.close.last == long.close.last)
    #expect(decoded.close.first == long.close[500])
    #expect(decoded.t0 == long.time(at: 500))
  }
}
