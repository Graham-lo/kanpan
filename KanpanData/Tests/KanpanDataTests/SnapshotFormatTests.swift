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

  /// 版本 1（五列）对下面 `equidistant()` 那条序列的输出，逐字节抄下来的。
  /// 手机上装着的老版本写下的就是这些字节，升级之后必须还读得出来。
  private let legacyEquiHex = "5241424b01000700425443555344540200316d0068e5cf8b01000060ea00000000000004000000000000000000005940000000000040594000000000008059400000000000c05940000000000040594000000000008059400000000000c059400000000000005a400000000000c05840000000000000594000000000004059400000000000805940000000000020594000000000006059400000000000a059400000000000e059400000000000002440000000000000264000000000000028400000000000002a40"

  /// 版本 1 对 `monthly()` 的输出（1M 是不等距周期，带 openTime 表，flag=1）。
  private let legacyMonthlyHex = "5241424b01000700455448555344540200314d00082e888b01000000c87e9a000000000300000001000000000000594000000000004059400000000000805940000000000040594000000000008059400000000000c059400000000000c0584000000000000059400000000000405940000000000020594000000000006059400000000000a0594000000000000024400000000000002640000000000000284000082e888b01000000d0ac228c01000000982bbd8c010000"

  /// 版本 2 的输出：版本号那两个字节从 1 变 2，成交量那一列后面多一列主动买成交量。
  /// 这条序列的 bar 没给主动买量，所以多出来的整列都是 NaN（`7ff8000000000000`）。
  private let equiHex = "5241424b02000700425443555344540200316d0068e5cf8b01000060ea00000000000004000000000000000000005940000000000040594000000000008059400000000000c05940000000000040594000000000008059400000000000c059400000000000005a400000000000c05840000000000000594000000000004059400000000000805940000000000020594000000000006059400000000000a059400000000000e059400000000000002440000000000000264000000000000028400000000000002a40000000000000f87f000000000000f87f000000000000f87f000000000000f87f"
  /// 版本 2 的 1M：多出来的那一列排在 openTime 表**前面**，和编码顺序一致。
  private let monthlyHex = "5241424b02000700455448555344540200314d00082e888b01000000c87e9a000000000300000001000000000000594000000000004059400000000000805940000000000040594000000000008059400000000000c059400000000000c0584000000000000059400000000000405940000000000020594000000000006059400000000000a05940000000000000244000000000000026400000000000002840000000000000f87f000000000000f87f000000000000f87f00082e888b01000000d0ac228c01000000982bbd8c010000"

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

  @Test("等距周期：编码逐字节钉死")
  func equidistantEncodeMatches() {
    #expect(Snapshot.encode(equidistant()) == bytes(equiHex))
  }

  @Test("不等距周期（1M，带 openTime 表）：编码逐字节钉死")
  func monthlyEncodeMatches() {
    #expect(Snapshot.encode(monthly()) == bytes(monthlyHex))
  }

  @Test("版本 1 写下的字节照样解得出来，主动买量整列当缺失")
  func decodesLegacyBytes() throws {
    let a = try #require(Snapshot.decode(bytes(legacyEquiHex)))
    #expect(same(a, equidistant()))
    #expect(a.openTime.isEmpty)
    // 老快照没有这一列：整列是 NaN，长度仍然和别的列一样。
    #expect(a.takerBuy.count == a.close.count)
    #expect(a.takerBuy.allSatisfy { $0.isNaN })

    let b = try #require(Snapshot.decode(bytes(legacyMonthlyHex)))
    #expect(same(b, monthly()))
    #expect(b.openTime.count == 3)
    #expect(b.openTime.first == 1_698_796_800_000)
    #expect(b.takerBuy.allSatisfy { $0.isNaN })
  }

  @Test("主动买成交量写进快照再读回来，一位不差；缺失的那几根读回来还是缺失")
  func takerBuyRoundTrips() throws {
    var bars: [Bar] = []
    for i in 0..<4 {
      var b = bar(i, base: 1_700_000_000_000, step: 60_000)
      // 第三根故意不给：源头缺这一列是常态（撮合价合成、OKX、网关截断）。
      if i != 2 { b.takerBuy = 3.0 + Double(i) }
      bars.append(b)
    }
    let series = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: bars)
    let back = try #require(Snapshot.decode(Snapshot.encode(series)))
    #expect(back.takerBuy[0] == 3.0)
    #expect(back.takerBuy[1] == 4.0)
    #expect(back.takerBuy[2].isNaN)
    #expect(back.takerBuy[3] == 6.0)
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
