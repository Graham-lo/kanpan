import Foundation

/// 全局递增的身份戳。
///
/// 用「全局唯一」而不是「每条序列自己的计数器」：两条刚建好的序列各自都是 0，
/// 拿计数器当身份会把两条不相干的序列判成同一条。
enum SeriesStamp {
  private static let lock = NSLock()
  private nonisolated(unsafe) static var counter: UInt64 = 0

  static func next() -> UInt64 {
    lock.lock(); defer { lock.unlock() }
    counter &+= 1
    return counter
  }
}

/// 列式 K 线序列（§4.2）。
///
/// 列式而不是 `[Bar]`：指标逐列扫、绘制逐列扫、快照逐列写，三处都省一次拆包。
public struct BarSeries: Sendable, Equatable {
  public let symbol: String
  public let interval: Interval
  /// 第一根 openTime，毫秒。
  public private(set) var t0: Int64
  /// 周期毫秒。1M 是名义 30 天，真实位置看 `openTime`。
  public let step: Int64

  // 六列都挂了 `didSet`：列是 `public var`，外面（测试、复盘桥）可以直接
  // `series.close[i] = x`，不挂观察器的话戳就会说谎。`didSet` 里没有碰
  // `oldValue`，所以编译器不会为了它多拷一份数组（SE-0268），`close[i] = x`
  // 仍然是原地改。直接改列时两个戳都作废——谁也不知道改的是哪一根。
  public var open: [Double] { didSet { stampAll() } }
  public var high: [Double] { didSet { stampAll() } }
  public var low: [Double] { didSet { stampAll() } }
  public var close: [Double] { didSet { stampAll() } }
  public var volume: [Double] { didSet { stampAll() } }
  /// 逐根的主动买成交量，缺失是 NaN（见 `Bar.takerBuy`）。
  ///
  /// 第六列，专为「累计成交量差」加的。它和前五列一样长——构造时给空数组就整列
  /// 补 NaN，这样所有老调用方一个字都不用改，而 `takerBuy[i]` 永远能取。
  public var takerBuy: [Double] { didSet { stampAll() } }
  /// 每根的真实 openTime。
  ///
  /// **不变量：这一列为空 ⟺ 整段已经被验过严格等距**（`openTime[i] == t0 + i*step`
  /// 对每一个 i 成立），这时才允许省掉它、由 `t0 + i*step` 推。不等距周期（1M / 1y）
  /// 永远带着它；等距周期只要中间缺了一根（交易所停盘、REST 缺根、聚合缺桶），
  /// 列就必须原样留着——省掉的话洞后面每一根都会整体前移一格，`time(at:)` 从此说谎，
  /// 而 `merge` 又会拿这条错时间去建字典，把错位的旧根和正确时间的新根混在一起，
  /// 序列就被永久污染。所有会改变下标 ↔ 时间对应关系的入口（`append`、`replaceLast`、
  /// `prepend`、以及构造器）都必须自己守住这条不变量。
  public var openTime: [Int64] { didSet { stampAll() } }

  /// 这条序列的身份。全局唯一：任何一次改动都会换一个新值，两条 `revision`
  /// 相同的序列内容一定相同（反过来不成立——内容相同但各自建出来的两条，
  /// 戳不一样，这时候 `==` 会退回逐列比）。
  public private(set) var revision: UInt64 = 0
  /// 「除末根以外的部分」的身份。末根被覆盖（`replaceLast`）时它不变，
  /// 这就是「只动了末根」的标记。追加一根时它变成老的 `revision`——
  /// 新序列的前缀正好是老序列的全部。
  public private(set) var prefixRevision: UInt64 = 0

  private mutating func stampAll() {
    revision = SeriesStamp.next()
    prefixRevision = SeriesStamp.next()
  }

  public var count: Int { close.count }
  public var isEmpty: Bool { close.isEmpty }

  public init(
    symbol: String, interval: Interval, t0: Int64, step: Int64? = nil,
    open: [Double], high: [Double], low: [Double], close: [Double], volume: [Double],
    takerBuy: [Double] = [], openTime: [Int64] = []
  ) {
    self.symbol = InstrumentID.canonical(symbol)
    self.interval = interval
    self.t0 = t0
    self.step = step ?? interval.stepMs
    self.open = open
    self.high = high
    self.low = low
    self.close = close
    self.volume = volume
    // 长度对不上（多半是压根没给）就整列补 NaN：这一列允许缺，但不允许比别的列短，
    // 否则每个读它的地方都要先判一次下标。
    self.takerBuy = takerBuy.count == close.count
      ? takerBuy : [Double](repeating: .nan, count: close.count)
    // 这里不替调用方做主：给什么列就存什么列。省列（走 `t0 + i*step` 快路）
    // 是调用方自己验过严格等距之后的决定，见下面 `init(symbol:interval:bars:)`。
    self.openTime = openTime
    self.revision = SeriesStamp.next()
    self.prefixRevision = SeriesStamp.next()
  }

  public init(symbol: String, interval: Interval, bars: [Bar]) {
    self.init(
      symbol: symbol, interval: interval,
      t0: bars.first?.openTime ?? 0, step: interval.stepMs,
      open: bars.map(\.open), high: bars.map(\.high), low: bars.map(\.low),
      close: bars.map(\.close), volume: bars.map(\.volume), takerBuy: bars.map(\.takerBuy),
      // 丢列走快路的唯一许可：等距周期 + 逐根验过严格等距。哪怕中间只缺一根，
      // 列也必须原样留着，否则洞后面每一根的时间都要整体前移一格。
      openTime: Self.canDropTimes(bars, interval: interval) ? [] : bars.map(\.openTime)
    )
  }

  /// 这一串 bar 能不能省掉 `openTime` 列。
  private static func canDropTimes(_ bars: [Bar], interval: Interval) -> Bool {
    guard !interval.isIrregular else { return false }
    guard let t0 = bars.first?.openTime else { return true }
    let step = interval.stepMs
    guard step > 0 else { return false }
    for (i, b) in bars.enumerated() where b.openTime != t0 + Int64(i) * step { return false }
    return true
  }

  // ------------------------------------------------------------ 时间 ↔ 下标

  /// 整段是不是严格等距：`times[i] == t0 + i*step` 逐根成立。
  ///
  /// 这是「可以省掉 `openTime` 列」的充要条件，只在构造和补历史这种低频路径上算，
  /// 实时那条路（`append` / `replaceLast`）只做 O(1) 的单根校验。
  static func isStrictlyRegular(_ times: [Int64], t0: Int64, step: Int64) -> Bool {
    guard step > 0 else { return false }
    for (i, t) in times.enumerated() where t != t0 + Int64(i) * step { return false }
    return true
  }

  /// 把省掉的列摊开成真实时间（调用前这条序列一定是严格等距的，所以推出来就是真值）。
  private mutating func materializeTimes() {
    guard openTime.isEmpty else { return }
    openTime = (0..<count).map { t0 + Int64($0) * step }
  }

  /// 第 i 根的 openTime。等距周期算出来，不等距周期查表。
  public func time(at i: Int) -> Int64 {
    if !openTime.isEmpty { return openTime[max(0, min(openTime.count - 1, i))] }
    return t0 + Int64(i) * step
  }

  /// 最后一根的 openTime。空序列返回 `t0`。
  public var lastTime: Int64 { count > 0 ? time(at: count - 1) : t0 }
  public var firstTime: Int64 { t0 }

  /// 距离 `t` 最近的一根（原型 `indexAt` 的 `Math.round`；不等距周期改二分）。
  public func index(atTime t: Double) -> Int {
    guard count > 0 else { return 0 }
    if openTime.isEmpty {
      let i = Int(((t - Double(t0)) / Double(step)).jsRounded())
      return max(0, min(count - 1, i))
    }
    // 二分找最后一个 openTime <= t，再和下一根比距离，取近的。
    var lo = 0, hi = count - 1
    if t <= Double(openTime[0]) { return 0 }
    if t >= Double(openTime[hi]) { return hi }
    while lo + 1 < hi {
      let mid = (lo + hi) / 2
      if Double(openTime[mid]) <= t { lo = mid } else { hi = mid }
    }
    let dLo = abs(t - Double(openTime[lo]))
    let dHi = abs(Double(openTime[hi]) - t)
    return dHi < dLo ? hi : lo
  }

  public func bar(at i: Int) -> Bar {
    Bar(
      openTime: time(at: i), open: open[i], high: high[i], low: low[i], close: close[i],
      volume: volume[i], takerBuy: i < takerBuy.count ? takerBuy[i] : .nan)
  }

  // ------------------------------------------------------------ 实时合成（§4.4）

  /// 覆盖末根。openTime 不同则是新根，走 `append`。
  public mutating func replaceLast(with bar: Bar) {
    guard count > 0 else { append(bar); return }
    let prefix = prefixRevision   // 前缀一个字节都没动，戳原样留着
    let i = count - 1
    // 末根被换成了另一个时间（调用方直接改写末根），快路的前提就破了：先摊开列。
    if openTime.isEmpty, bar.openTime != t0 + Int64(i) * step { materializeTimes() }
    open[i] = bar.open; high[i] = bar.high; low[i] = bar.low
    close[i] = bar.close; volume[i] = bar.volume
    if i < takerBuy.count { takerBuy[i] = bar.takerBuy }
    if !openTime.isEmpty { openTime[i] = bar.openTime }
    revision = SeriesStamp.next()
    prefixRevision = prefix
  }

  public mutating func append(_ bar: Bar) {
    // 追加之后「除末根以外」＝追加之前的整条，所以新前缀的身份就是老的 `revision`。
    let prefix = revision
    if count == 0 { t0 = bar.openTime }
    // 这一根没有正好落在 `t0 + count*step`（中间缺了根），或者本来就是不等距周期：
    // 省列的前提没了，这一根之后必须带着列。先决定带不带，再摊开、再接上去——
    // 不能拿 `materializeTimes()` 之后的 `openTime.isEmpty` 去判：空序列摊出来仍是空列，
    // 1M/1y 的第一根就会把列漏掉，和 `init(symbol:interval:bars:)` 造出来的不是同一条。
    let keepTimes = !openTime.isEmpty || interval.isIrregular
      || bar.openTime != t0 + Int64(count) * step
    if keepTimes { materializeTimes() }
    open.append(bar.open); high.append(bar.high); low.append(bar.low)
    close.append(bar.close); volume.append(bar.volume); takerBuy.append(bar.takerBuy)
    if keepTimes { openTime.append(bar.openTime) }
    revision = SeriesStamp.next()
    prefixRevision = prefix
  }

  /// WS 事件合成：openTime 等于末根就覆盖，大于就追加，更早就忽略。
  @discardableResult
  public mutating func upsert(_ bar: Bar) -> Bool {
    guard count > 0 else { append(bar); return true }
    let last = lastTime
    if bar.openTime == last { replaceLast(with: bar); return true }
    if bar.openTime > last { append(bar); return true }
    return false
  }

  /// 向前补历史：接在最前面，`t0` 跟着走（§7 补历史触发）。
  public mutating func prepend(_ bars: [Bar]) {
    guard !bars.isEmpty else { return }
    let sorted = bars.sorted { $0.openTime < $1.openTime }
    let cut = sorted.filter { count == 0 || $0.openTime < t0 }
    guard !cut.isEmpty else { return }
    // 补在前面的这段和原来的 t0 之间可能缺根，`cut` 自己也可能带洞：先无条件摊开
    // 接上真实时间，接完再看整段是不是仍然严格等距——是的话把列重新丢掉走快路。
    materializeTimes()
    openTime.insert(contentsOf: cut.map(\.openTime), at: 0)
    open.insert(contentsOf: cut.map(\.open), at: 0)
    high.insert(contentsOf: cut.map(\.high), at: 0)
    low.insert(contentsOf: cut.map(\.low), at: 0)
    close.insert(contentsOf: cut.map(\.close), at: 0)
    volume.insert(contentsOf: cut.map(\.volume), at: 0)
    takerBuy.insert(contentsOf: cut.map(\.takerBuy), at: 0)
    t0 = cut[0].openTime
    if !interval.isIrregular, Self.isStrictlyRegular(openTime, t0: t0, step: step) { openTime = [] }
    // 补历史把每一根的下标都挪了，两个戳都作废（`didSet` 已经作废过一次，这里不必再写）。
  }

  // ------------------------------------------------------------ 身份比较

  /// 逐列比之前先看戳。
  ///
  /// 从前这是编译器合成的 `==`：`ChartRenderer.recalc` 和 `ChartView.sameFrame`
  /// 每个 tick 都要靠它扫五列。戳相同就一定同内容，可以直接收工；戳不同**不**代表
  /// 内容不同（两条分别建出来的一样的序列），所以老的逐列比一个字没删，留在后面兜底。
  public static func == (a: BarSeries, b: BarSeries) -> Bool {
    if a.revision == b.revision { return true }
    return a.symbol == b.symbol && a.interval == b.interval && a.t0 == b.t0 && a.step == b.step
      && a.close == b.close && a.open == b.open && a.high == b.high
      && a.low == b.low && a.volume == b.volume && a.openTime == b.openTime
      && sameColumn(a.takerBuy, b.takerBuy)
  }

  /// 除末根以外的一切是否一样。
  ///
  /// 「只有末根在动」是行情的常态（每个 WS tick 都是），指标能不能走增量、
  /// 底图要不要重画，问的都是这一句。先看前缀戳——`replaceLast` 会原样留着它，
  /// 所以正常 tick 一次比较就够；戳对不上再退回逐列比。
  public func samePrefix(as other: BarSeries) -> Bool {
    guard symbol == other.symbol, interval == other.interval, t0 == other.t0, step == other.step,
      count == other.count, count > 0, openTime == other.openTime
    else { return self == other }
    if prefixRevision == other.prefixRevision { return true }
    return open.dropLast().elementsEqual(other.open.dropLast())
      && high.dropLast().elementsEqual(other.high.dropLast())
      && low.dropLast().elementsEqual(other.low.dropLast())
      && close.dropLast().elementsEqual(other.close.dropLast())
      && volume.dropLast().elementsEqual(other.volume.dropLast())
      && Self.sameColumn(takerBuy.dropLast(), other.takerBuy.dropLast())
  }

  /// 逐位比一列「可以缺失」的数，两边都是 NaN 算相等。
  ///
  /// 主动买量整列常年是 NaN（撮合价合成的根、旧快照、OKX），用 `==` 比的话
  /// 两条内容完全一样的序列会被判成不等，每个 tick 都要白重画一次。
  static func sameColumn<A: Collection, B: Collection>(_ a: A, _ b: B) -> Bool
  where A.Element == Double, B.Element == Double {
    a.count == b.count && zip(a, b).allSatisfy { Bar.sameOptional($0, $1) }
  }

  /// 我是不是「`other` 后面又长了一根」——即我的前 `count - 1` 根就是 `other` 的全部。
  ///
  /// 新周期开盘时行情就走这一条：老的整条原样变成新的前缀，指标只要接着算最后
  /// 那一根就行，没必要从头重建。判定只认戳（`append` 会把新的 `prefixRevision`
  /// 设成老的 `revision`），对不上就当不是——宁可多重建一次，绝不会误判成增量。
  public func isOneBarAfter(_ other: BarSeries) -> Bool {
    count == other.count + 1 && other.count > 0 && prefixRevision == other.revision
  }
}

extension Double {
  /// JS 的 `Math.round`：.5 一律往 +∞ 走（Swift 的 `rounded()` 是离零远，负半数上不同）。
  func jsRounded() -> Double { (self + 0.5).rounded(.down) }
}
