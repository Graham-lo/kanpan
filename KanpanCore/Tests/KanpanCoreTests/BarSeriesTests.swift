import Foundation
import Testing

@testable import KanpanCore

/// 序列本身：实时合成（§4.4）、补历史（§7）、时间↔下标。
///
/// 这些是所有上层逻辑的地基——指标增量、视野夹取、命中判定全踩在 `time(at:)`
/// 和 `index(atTime:)` 上，错一根整张图就偏一根。
@Suite("K 线序列")
struct BarSeriesTests {
  private func bar(_ t: Int64, _ v: Double = 1) -> Bar {
    Bar(openTime: t, open: v, high: v + 1, low: v - 1, close: v + 0.5, volume: v * 10)
  }

  private func regular(_ n: Int, step: Int64 = 3_600_000, t0: Int64 = 1_700_000_000_000) -> BarSeries {
    BarSeries(symbol: "BTCUSDT", interval: .h1,
              bars: (0..<n).map { bar(t0 + Int64($0) * step, Double($0)) })
  }

  @Test("等距周期不存 openTime，时间由 t0 推")
  func regularDerivesTime() {
    let s = regular(100)
    #expect(s.openTime.isEmpty, "等距周期不该白存一列")
    #expect(s.count == 100)
    for i in 0..<s.count { #expect(s.time(at: i) == s.t0 + Int64(i) * s.step) }
    #expect(s.firstTime == s.t0)
    #expect(s.lastTime == s.t0 + 99 * s.step)
  }

  @Test("下标越界要夹住，不能崩")
  func timeClampsIndex() {
    let s = regular(10)
    // 等距是外推（视野可以拖到数据之外），不等距是夹到两端。
    #expect(s.time(at: -3) == s.t0 - 3 * s.step)
    let m = BarSeries(symbol: "X", interval: .mo1, bars: (0..<3).map { bar(Int64($0) * 100, 1) })
    #expect(m.time(at: -5) == m.openTime[0])
    #expect(m.time(at: 99) == m.openTime[2])
  }

  @Test("空序列的时间")
  func emptySeries() {
    let s = BarSeries(symbol: "X", interval: .h1, bars: [])
    #expect(s.isEmpty && s.count == 0)
    #expect(s.lastTime == s.t0)
    #expect(s.index(atTime: 12345) == 0, "空序列查下标给 0，不能崩")
  }

  /// `index(atTime:)` 取**最近**的一根（原型 `Math.round`），不是向下取整。
  @Test("最近一根而不是向下取整")
  func indexRoundsToNearest() {
    let s = regular(10)
    let step = Double(s.step)
    #expect(s.index(atTime: Double(s.t0)) == 0)
    #expect(s.index(atTime: Double(s.t0) + step * 0.49) == 0)
    #expect(s.index(atTime: Double(s.t0) + step * 0.5) == 1, "半根整往上走")
    #expect(s.index(atTime: Double(s.t0) + step * 0.51) == 1)
    #expect(s.index(atTime: Double(s.t0) + step * 3) == 3)
    // 越界夹到两端
    #expect(s.index(atTime: Double(s.t0) - 1e9) == 0)
    #expect(s.index(atTime: Double(s.t0) + 1e12) == 9)
  }

  /// `jsRounded` 在负半数上要跟 JS 的 `Math.round` 一致（往 +∞，不是离零远）。
  @Test("负半数按 JS 规则进位")
  func jsRoundOnNegativeHalves() {
    #expect((-0.5).jsRounded() == 0, "JS 的 Math.round(-0.5) 是 -0 不是 -1")
    #expect((-1.5).jsRounded() == -1)
    #expect((-2.5).jsRounded() == -2)
    #expect((0.5).jsRounded() == 1)
    #expect((1.5).jsRounded() == 2)
    #expect((-1.6).jsRounded() == -2)
  }

  @Test("覆盖末根")
  func replaceLast() {
    var s = regular(5)
    let t = s.lastTime
    s.replaceLast(with: Bar(openTime: t, open: 9, high: 99, low: 0.5, close: 42, volume: 7))
    #expect(s.count == 5, "覆盖不该长出一根")
    #expect(s.close[4] == 42 && s.high[4] == 99 && s.low[4] == 0.5 && s.volume[4] == 7)
    #expect(s.lastTime == t)
    // 空序列上覆盖等于追加
    var e = BarSeries(symbol: "X", interval: .h1, bars: [])
    e.replaceLast(with: bar(1000))
    #expect(e.count == 1 && e.t0 == 1000)
  }

  @Test("追加新根")
  func appendBar() {
    var s = regular(5)
    let t = s.lastTime + s.step
    s.append(bar(t, 50))
    #expect(s.count == 6 && s.lastTime == t)
    #expect(s.close[5] == 50.5)
    #expect(s.openTime.isEmpty, "等距周期追加仍然不建表")
  }

  /// WS 事件合成：openTime 等于末根就覆盖、大于就追加、更早就丢掉。
  @Test("upsert 三种情形")
  func upsertCases() {
    var s = regular(5)
    let last = s.lastTime
    // `#expect` 把表达式塞进闭包里，mutating 方法不能直接写在里头，先落成 let。
    let 覆盖 = s.upsert(Bar(openTime: last, open: 1, high: 2, low: 0, close: 1.5, volume: 3))
    #expect(覆盖)
    #expect(s.count == 5 && s.close[4] == 1.5)

    let 追加 = s.upsert(bar(last + s.step, 7))
    #expect(追加)
    #expect(s.count == 6)

    // 迟到的旧事件（网络乱序）要丢掉，不能把历史写花
    let snapshot = s
    let 迟到 = s.upsert(bar(last - 10 * s.step, 999))
    #expect(!迟到)
    #expect(s == snapshot, "迟到事件改了数据")

    var e = BarSeries(symbol: "X", interval: .h1, bars: [])
    let 首根 = e.upsert(bar(5))
    #expect(首根)
    #expect(e.count == 1)
  }

  /// 反复 upsert 同一根（WS 每秒好几次）不该让序列变长。
  @Test("反复 upsert 末根不长胖")
  func repeatedUpsertKeepsLength() {
    var s = regular(30)
    var r = Rng(555)
    let t = s.lastTime
    for _ in 0..<500 {
      let c = r.d(100, 200)
      s.upsert(Bar(openTime: t, open: 100, high: c + 5, low: c - 5, close: c, volume: r.d(0, 10)))
    }
    #expect(s.count == 30)
  }

  @Test("向前补历史")
  func prependHistory() {
    var s = regular(10)
    let t0 = s.t0
    let older = (1...5).map { bar(t0 - Int64($0) * s.step, Double(-$0)) }
    s.prepend(older)
    #expect(s.count == 15)
    #expect(s.t0 == t0 - 5 * s.step, "t0 要跟着往前挪")
    #expect(s.time(at: 0) == s.t0)
    // 乱序给也要排好
    for i in 1..<s.count { #expect(s.time(at: i) > s.time(at: i - 1)) }

    // 与现有区间重叠的部分要切掉，不能出现重复根
    let before = s.count
    s.prepend([bar(s.t0, 0), bar(s.t0 + s.step, 0)])
    #expect(s.count == before, "重叠的旧根被重复插入了")
    s.prepend([])
    #expect(s.count == before)
  }

  /// 翻页拼起来的那批里自己带重根（页边界重一根）：只留一根、后到的为准，
  /// 整段仍严格等距、下标与时间一一对应。
  @Test("补历史的那批自带重根")
  func prependDedupesBatch() {
    var s = regular(10)
    let t0 = s.t0, step = s.step
    s.prepend([bar(t0 - 2 * step, 1), bar(t0 - step, 2), bar(t0 - step, 3), bar(t0 - 3 * step, 4)])
    #expect(s.count == 13)
    #expect(s.openTime.isEmpty, "去重之后整段严格等距，列应该丢掉")
    #expect(s.close[2] == 3.5, "同一时刻留后到的那根")
    for i in 0..<s.count { #expect(s.index(atTime: Double(s.time(at: i))) == i) }
  }

  /// 不等距周期补历史时 openTime 表要跟着长，不能错位。
  @Test("不等距周期补历史")
  func prependIrregular() {
    let months = (0..<6).map { k -> Bar in
      let t = Aggregator.utcMs(year: 2025, month: 1 + k, day: 1)
      return bar(t, Double(k))
    }
    var s = BarSeries(symbol: "X", interval: .mo1, bars: months)
    #expect(s.openTime.count == 6)
    let older = (1...3).map { k in bar(Aggregator.utcMs(year: 2024, month: 13 - k, day: 1), Double(-k)) }
    s.prepend(older)
    #expect(s.count == 9 && s.openTime.count == 9)
    #expect(s.t0 == Aggregator.utcMs(year: 2024, month: 10, day: 1))
    for i in 0..<s.count { #expect(s.time(at: i) == s.openTime[i]) }
    for i in 0..<s.count { #expect(s.index(atTime: Double(s.openTime[i])) == i) }
  }

  /// 等距序列在第一次 append 不等距周期的根时要把表补齐（懒建表别漏了前面的）。
  @Test("不等距周期追加时补建 openTime 表")
  func appendBuildsTable() {
    var s = BarSeries(symbol: "X", interval: .mo1, t0: 0, step: Interval.mo1.stepMs,
                      open: [1, 2], high: [1, 2], low: [1, 2], close: [1, 2], volume: [1, 2],
                      openTime: [])
    #expect(s.openTime.isEmpty)
    s.append(bar(Interval.mo1.stepMs * 2 + 777))
    #expect(s.openTime.count == 3, "补表没补全前面两根")
    #expect(s.openTime[0] == 0 && s.openTime[1] == Interval.mo1.stepMs)
  }

  @Test("bar(at:) 取出来的和列里的一致")
  func barRoundTrip() {
    let s = regular(20)
    for i in 0..<s.count {
      let b = s.bar(at: i)
      #expect(b.openTime == s.time(at: i))
      #expect(b.open == s.open[i] && b.high == s.high[i] && b.low == s.low[i])
      #expect(b.close == s.close[i] && b.volume == s.volume[i])
    }
  }

  /// 持仓量对齐：每根取「不晚于这根开盘」的那一条，越界留 NaN（原型 `oiAligned`）。
  @Test("持仓量对齐")
  func oiAlign() {
    let s = regular(10, step: 3_600_000, t0: 1_700_000_000_000)
    // OI 是 5 分钟粒度，从 K 线第 2 根开始有
    let oiT0 = s.t0 + 3_600_000
    let oi = OISeries(t0: oiT0, step: 300_000, values: (0..<200).map { Double($0) })
    let a = oi.aligned(to: s)
    #expect(a.count == s.count)
    #expect(a[0].isNaN, "第一根在 OI 起点之前，该是 NaN")
    #expect(a[1] == 0)
    #expect(a[2] == 12, "一小时 12 条 5 分钟")
    #expect(a[3] == 24)
    // 尾部越界也 NaN
    let short = OISeries(t0: oiT0, step: 300_000, values: [0, 1, 2])
    let b = short.aligned(to: s)
    #expect(b[1] == 0 && b[2].isNaN)
    // step 为 0 的脏数据不能除零
    let bad = OISeries(t0: 0, step: 0, values: [1, 2])
    let dirty = bad.aligned(to: s)
    #expect(dirty.count == s.count && dirty.filter(\.isNaN).count == dirty.count)
  }

  // ------------------------------------------------------------ 身份戳

  /// 戳只是加速器：说「相同」必须真的相同，说「不同」时逐列比照样兜底。
  @Test("身份戳：同内容一定同判定")
  func revisionAgreesWithContent() {
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<1000 {
      var a = regular(Int.random(in: 1...40, using: &rng))
      var b = a
      switch Int.random(in: 0...7, using: &rng) {
      case 0: break
      case 1: b.replaceLast(with: bar(b.lastTime, Double.random(in: 0...100, using: &rng)))
      // 同一条各自覆盖末根的兄弟俩：前缀戳相同、`revision` 不同，`==` 只比末根的那条快路
      // 必须和逐列比同一个结论——末根一样就相等，不一样就不等（审查 24）。
      case 6:
        let v = Double(Int.random(in: 0...2, using: &rng))
        a.replaceLast(with: bar(a.lastTime, v))
        b.replaceLast(with: bar(b.lastTime, Double(Int.random(in: 0...2, using: &rng))))
      case 7:
        a.replaceLast(with: bar(a.lastTime, 3))
        b.replaceLast(with: bar(b.lastTime + b.step, 3))   // 末根换了时间：摊开 openTime 列
      case 2: b.append(bar(b.lastTime + b.step, 7))
      case 3: b.close[Int.random(in: 0..<b.count, using: &rng)] += 1
      case 4: b.prepend([bar(b.t0 - b.step, 5)])
      default: a = regular(a.count)   // 内容一样、戳不一样的两条
      }
      // 逐列比是唯一的真相，`==` 必须和它一个结论。
      let byColumns = a.symbol == b.symbol && a.interval == b.interval && a.t0 == b.t0
        && a.step == b.step && a.open == b.open && a.high == b.high && a.low == b.low
        && a.close == b.close && a.volume == b.volume && a.openTime == b.openTime
      #expect((a == b) == byColumns)

      let prefixByColumns: Bool
      if a.symbol == b.symbol, a.interval == b.interval, a.t0 == b.t0, a.step == b.step,
         a.count == b.count, a.count > 0, a.openTime == b.openTime {
        prefixByColumns = a.open.dropLast().elementsEqual(b.open.dropLast())
          && a.high.dropLast().elementsEqual(b.high.dropLast())
          && a.low.dropLast().elementsEqual(b.low.dropLast())
          && a.close.dropLast().elementsEqual(b.close.dropLast())
          && a.volume.dropLast().elementsEqual(b.volume.dropLast())
      } else {
        prefixByColumns = byColumns
      }
      #expect(a.samePrefix(as: b) == prefixByColumns)
    }
  }

  @Test("身份戳：覆盖末根不动前缀，追加一根把老整条当前缀")
  func revisionMoves() {
    let a = regular(10)
    var tick = a
    tick.replaceLast(with: bar(a.lastTime, 99))
    #expect(tick.revision != a.revision)
    #expect(tick.prefixRevision == a.prefixRevision)   // 这就是「只动了末根」的快路

    var grown = a
    grown.append(bar(a.lastTime + a.step, 11))
    #expect(grown.prefixRevision == a.revision)

    // 直接改列的人不走 `replaceLast`，两个戳都得作废，不然前缀会说谎。
    var poked = a
    poked.close[3] += 1
    #expect(poked.revision != a.revision)
    #expect(poked.prefixRevision != a.prefixRevision)
    #expect(!poked.samePrefix(as: a))

    // 另建一条内容相同的：戳不同，但判定仍要是「相同」。
    let twin = regular(10)
    #expect(twin.revision != a.revision)
    #expect(twin == a)
    #expect(twin.samePrefix(as: a))
  }

  /// 品种精度与显示名。
  @Test("品种字段")
  func symbolInfo() {
    let s = SymbolInfo(symbol: "SOLUSDT", base: "SOL", pricePrecision: 4, quantityPrecision: 0, tickSize: 0.001)
    #expect(s.display == "SOL/USDT")
    #expect(s.id == InstrumentID("SOLUSDT"))
    #expect(s.priceDecimals == 3)
    // tickSize 脏了就退回 pricePrecision
    let bad = SymbolInfo(symbol: "X", base: "X", pricePrecision: 5, quantityPrecision: 0, tickSize: 0)
    #expect(bad.priceDecimals == 5)
  }
}
