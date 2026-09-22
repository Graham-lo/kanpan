import Foundation

/// 指标的算与缓存（§5.7、§8）。
///
/// 缓存键 = `数据键|品种|周期|指标集合|参数|根数`。末根变化只**重算最后 N 根**
/// （N = `tailBars`），整段换了才全量。增量与全量逐位相同：每种线都把自己的递推
/// 状态（滑动窗累加和、EMA/RMA 的前值、KDJ 的 K/D）存着，不是近似。
public struct IndicatorEngine: Sendable {
  /// 当前算出来的值，按指标取。
  public private(set) var values: [IndicatorID: IndicatorResult] = [:]

  private var states: [IndicatorID: State] = [:]
  private var params: [IndicatorID: [Int]] = [:]
  private var key = ""
  /// 现有这些状态是照着哪一份 K 线算出来的（`BarSeries.revision`，全局唯一）。
  /// 0 是「还没算过」——戳从 1 开始发，永远撞不上。
  private var dataRevision: UInt64 = 0

  public init() {}

  // ---------------------------------------------------------------- 对外

  /// 保证 `wanted` 里的指标都是算好的。键没变就直接返回，什么都不做。
  ///
  /// `external` 是那些不从 K 线算的输入（持仓量、多空比、主动买卖比、基差），按指标索引。
  /// 一个指标要不要外部输入看 `IndicatorID.externalColumns`；没喂到的那个指标画一列 NaN，
  /// 不是报错——数据是按需拉的，副图刚打开时本来就还没到。
  @discardableResult
  public mutating func ensure(
    series: BarSeries, wanted: [IndicatorID], params: [IndicatorID: [Int]] = [:],
    external: [IndicatorID: ExternalSeries] = [:], dataKey: String = ""
  ) -> Bool {
    let ids = Array(Set(wanted))
    let resolved = Dictionary(uniqueKeysWithValues: ids.map { ($0, params[$0] ?? $0.defaultParams) })
    let k = Self.cacheKey(series: series, wanted: ids, params: resolved,
                          external: external, dataKey: dataKey)
    if k == key { return false }
    key = k

    // 按指标失效，不再一有风吹草动就全量重建。
    //
    // 键里塞了品种、周期、根数、指标集合、全部参数，任何一样变了都会走到这儿；
    // 但「改了 MA 的周期」不该让 MACD、KDJ、BOLL 陪着从头算一遍——加一个副图指标
    // 同理，已经算好的那几个一个字都没变。
    //
    // 敢留用的前提有两条，缺一不可：这份 K 线还是刚才那份（`revision` 全局唯一，
    // 相等就一定同内容），以及这个指标自己的参数没动。
    let sameData = dataRevision == series.revision && dataRevision != 0
    let oldParams = self.params
    var keptStates: [IndicatorID: State] = [:]
    var keptValues: [IndicatorID: IndicatorResult] = [:]
    for id in ids {
      let p = resolved[id]!
      // 吃外部数据的指标一律不留用：它的输入除了 K 线还有那一路外部序列，
      // `series.revision` 管不着它。宁可重建。
      //
      // 从前这儿硬写着 `id != .oi`，因为外部输入只有持仓量一路；现在有四路了，
      // 再按名字开后门必然漏掉新的，所以改成问 `isExternal`。
      if sameData, !id.isExternal, oldParams[id] == p, let st = states[id], let v = values[id] {
        keptStates[id] = st
        keptValues[id] = v
      } else {
        let st = Self.build(id, p: p, series: series, external: external[id])
        keptStates[id] = st
        keptValues[id] = st.result
      }
    }
    self.params = resolved
    states = keptStates
    values = keptValues
    dataRevision = series.revision
    return true
  }

  /// 只有持仓量的调用点用这个：`OISeries` 保持原样不动，进引擎之前转成单列的
  /// `ExternalSeries`（戳原样带过去，见 `ExternalSeries.init(oi:)`）。
  @discardableResult
  public mutating func ensure(
    series: BarSeries, wanted: [IndicatorID], params: [IndicatorID: [Int]] = [:],
    oi: OISeries?, dataKey: String = ""
  ) -> Bool {
    ensure(series: series, wanted: wanted, params: params,
           external: Self.externalMap(oi: oi), dataKey: dataKey)
  }

  /// 末根改了或者新追了一根：只重算尾巴，结果与全量逐位相同。
  ///
  /// 这里的写法有两处看着多余、实则是这条路径**不随历史长度变慢**的全部原因。
  /// 递推算术本来只碰最后几十根（`tailBars`），可数组的所有权会把它拖成整列的活：
  ///
  /// 1. **先把上一批发布出去的结果放掉**（`values.removeAll`）。`values` 里的每条线
  ///    和 `states` 里的递推状态指着同一块缓冲——引擎自己一手攥一份，引用数恒 ≥2，
  ///    于是每次往状态里写一个数，写时复制都得先把整列 N 个 Double 抄一遍。
  ///    先放手，缓冲就是独占的，改尾巴就是真的只改尾巴。算完再挂回去，
  ///    `values` 仍然是那份完整结果，外面一个字都不用改。
  ///    （调用方要是自己攥着上一次拿到的快照，写时复制照常分家，他手里的数不会被改掉——
  ///    值语义没丢，丢的只是这一次的省事。）
  /// 2. **按键就地改**（`states[id]?.update`，不是 `for (id, var st) in states`）。
  ///    后者把字典里的值复制出来改完再写回去，改的全程字典也攥着同一块缓冲，
  ///    同样一次整列复制。字典下标的 `_modify` 是就地借出去改，没有这份副本；
  ///    键先抄成数组，是为了别在遍历字典视图的同时改字典（那又会把字典复制一份）。
  ///
  /// 量过：N=10000、MA×3+BOLL+MACD+KDJ+RSI 共 15 条线，改前每次末根更新要重新分配
  /// 并复制 15 条整列（1.2 MB），改后 0 条。
  public mutating func updateTail(series: BarSeries,
                                  external: [IndicatorID: ExternalSeries] = [:],
                                  dataKey: String = "") {
    // 空序列没有末根可更（WS 事件可能比 REST 历史先到），直接放过。
    guard !states.isEmpty, series.count > 0 else { return }
    values.removeAll(keepingCapacity: true)
    for id in Array(states.keys) {
      let p = params[id] ?? id.defaultParams
      // 下限是 0 而不是 1：序列短到 `count <= tailBars` 时（新上市的品种只有一两根），
      // 首根同时也是末根，它自己就是这次被改掉的那一根。夹到 1 的话重算区间退化成
      // `1..<1` 空区间——改掉的收盘价不但当场没生效，还把 `sum[0]`、`tr[0]` 这些
      // 递推种子永久留在旧值上，后面每追一根都接着错的种子往下算，一直错到
      // 均线开始出值之后。起点是 0 时各条线的 `canTail` 一律返回假，自然退回全量重建：
      // 这种极短状态本来就没有几根可算，全量不构成负担；长序列的起点仍是
      // `count - tailBars`，增量路径一点没动。
      let start = max(0, series.count - id.tailBars(params: p))
      states[id]?.update(series: series, from: start, external: external[id])
      values[id] = states[id]?.result
    }
    key = Self.cacheKey(series: series, wanted: Array(states.keys), params: params,
                        external: external, dataKey: dataKey)
    dataRevision = series.revision
  }

  /// 持仓量专用的便捷入口，理由同上面那个 `ensure`。
  public mutating func updateTail(series: BarSeries, oi: OISeries?, dataKey: String = "") {
    updateTail(series: series, external: Self.externalMap(oi: oi), dataKey: dataKey)
  }

  /// 单列持仓量 → 外部序列表。`nil` 给空表，`.oi` 那一列就画成 NaN。
  static func externalMap(oi: OISeries?) -> [IndicatorID: ExternalSeries] {
    guard let oi else { return [:] }
    return [.oi: ExternalSeries(oi: oi)]
  }

  /// 参数或指标集合没变、只是想拿值。
  public subscript(id: IndicatorID) -> IndicatorResult? { values[id] }

  /// 缓存键。外部输入按 `revision` 记进来：那些序列不是从 K 线算出来的，
  /// K 线一个字没动它们也会变（持仓量补上了新的一段、多空比翻了一页历史），
  /// 键里没有它们的影子就意味着「数据更新了但键没变」，`ensure` 直接短路返回、
  /// 画面停在旧值上。戳是全局唯一的，比一遍数组便宜。
  public static func cacheKey(
    series: BarSeries, wanted: [IndicatorID], params: [IndicatorID: [Int]],
    external: [IndicatorID: ExternalSeries] = [:], dataKey: String = ""
  ) -> String {
    let parts = wanted.map(\.rawValue).sorted().map { id -> String in
      let p = (params[IndicatorID(rawValue: id)!] ?? []).map(String.init).joined(separator: "-")
      return "\(id):\(p)"
    }
    let ext = external.keys.map(\.rawValue).sorted().map { id -> String in
      "\(id)@\(external[IndicatorID(rawValue: id)!]!.revision)"
    }
    return "\(dataKey)|\(series.symbol)|\(series.interval.rawValue)|\(parts.joined(separator: ","))|\(ext.joined(separator: ","))|\(series.count)"
  }

  // ---------------------------------------------------------------- 状态

  /// `.sma` 既给 MA（收盘）也给 VOL（成交量），靠这个选源列。
  enum Source: Sendable {
    case close, volume
    func column(_ b: BarSeries) -> [Double] { self == .close ? b.close : b.volume }
  }

  private static func build(_ id: IndicatorID, p: [Int], series b: BarSeries,
                            external: ExternalSeries?) -> State {
    switch id {
    case .ma: .sma(p.map { SMALine(b.close, $0) }, .close)
    case .vol: .sma(p.map { SMALine(b.volume, $0) }, .volume)
    case .ema: .ema(p.map { RecursiveLine(b.close, $0, kind: .ema) })
    case .boll: .boll(BollState(b.close, n: p[0], k: Double(p[1])))
    case .macd: .macd(MACDState(b.close, fast: p[0], slow: p[1], sig: p[2]))
    case .rsi: .rsi(p.map { RSIState(b.close, n: $0) })
    case .kdj: .kdj(KDJState(b, n: p[0], kn: p[1], dn: p[2]))
    case .srsi: .srsi(SRSIState(b.close, rlen: p[0], slen: p[1], kn: p[2], dn: p[3]))
    case .atr: .atr(ATRState(b, n: p[0]))
    case .oi, .lsr, .taker, .basis:
      .external(external?.aligned(to: b) ?? ExternalSeries.blank(id.externalColumns ?? 1, b.count),
                external?.revision ?? 0)
    }
  }

  enum State: Sendable {
    case sma([SMALine], Source)
    case ema([RecursiveLine])
    case boll(BollState)
    case macd(MACDState)
    case rsi([RSIState])
    case kdj(KDJState)
    case srsi(SRSIState)
    case atr(ATRState)
    /// 对齐好的那几列，外加它是从哪一份外部序列来的（`ExternalSeries.revision`，
    /// 没喂到数据时 0）。记着来源才敢在 `update` 里只对齐尾巴。
    case external([[Double]], UInt64)
    /// 负载刚被掏出去的那一瞬间（见 `update`）。`update` 的每条路径都会在返回前填回来，
    /// 外面永远碰不到这个值。
    case moved

    var result: IndicatorResult {
      switch self {
      case .sma(let l, _): IndicatorResult(lines: l.map(\.out))
      case .ema(let l): IndicatorResult(lines: l.map(\.out))
      case .boll(let s): IndicatorResult(lines: [s.mid.out, s.up, s.dn])
      case .macd(let s): IndicatorResult(lines: [s.dif, s.dea.out], histogram: s.hist)
      case .rsi(let l): IndicatorResult(lines: l.map(\.out))
      case .kdj(let s): IndicatorResult(lines: [s.k, s.d, s.j])
      case .srsi(let s): IndicatorResult(lines: [s.k.out, s.d.out])
      case .atr(let s): IndicatorResult(lines: [s.line.out])
      case .external(let cols, _): IndicatorResult(lines: cols)
      case .moved: IndicatorResult(lines: [])
      }
    }

    /// 尾部重算。每个分支都是「先把 self 掏空，再改掏出来的那一份」。
    ///
    /// `case .sma(var l, let src)` 只是把负载**复制**一份出来——数组结构复制等于缓冲多一个
    /// 引用，而 self 那边还攥着同一块。接着往 `l` 里写一个数，写时复制就得先把整列抄一遍：
    /// 几千根的历史，改末根一个数要搬几万个字节，算术只碰最后几十根也没用。
    /// 中间那句 `self = .moved` 把 self 这一侧的引用放掉，掏出来的那份就成了独占，
    /// 尾巴是真的只改尾巴。
    ///
    /// Release 下优化器有时能自己看出这是一次搬移，Debug 下不会（量过：`-Onone` 里
    /// 不写这一句，15 条线每次更新整列复制 15 次）。写明白，模拟器上跑的也是同一条快路。
    mutating func update(series b: BarSeries, from start: Int, external: ExternalSeries?) {
      switch self {
      case .sma(var l, let src):
        self = .moved
        let col = src.column(b)
        for i in l.indices {
          if l[i].canTail(from: start) { l[i].recompute(col, from: start) }
          else { l[i] = SMALine(col, l[i].n, offset: l[i].offset) }
        }
        self = .sma(l, src)
      case .ema(var l):
        self = .moved
        for i in l.indices { l[i].recompute(b.close, from: start) }
        self = .ema(l)
      case .boll(var s): self = .moved; s.update(b.close, from: start); self = .boll(s)
      case .macd(var s): self = .moved; s.update(b.close, from: start); self = .macd(s)
      case .rsi(var l):
        self = .moved
        for i in l.indices { l[i].update(b.close, from: start) }
        self = .rsi(l)
      case .kdj(var s): self = .moved; s.update(b, from: start); self = .kdj(s)
      case .srsi(var s): self = .moved; s.update(b.close, from: start); self = .srsi(s)
      case .atr(var s): self = .moved; s.update(b, from: start); self = .atr(s)
      case .moved: break
      case .external(var prev, let rev):
        self = .moved
        guard let ext = external, ext.revision != 0 else {
          // 没喂到数据：上次也没有的话，那几列已经全是 NaN，追长就行，
          // 不必每个 tick 现开几条几千长的 NaN 数组。
          if rev == 0, prev.allSatisfy({ $0.count <= b.count }) {
            for c in prev.indices { grow(to: b.count, &prev[c]) }
            self = .external(prev, 0)
          } else {
            self = .external(ExternalSeries.blank(max(prev.count, 1), b.count), 0)
          }
          return
        }
        // 还是同一份、列数没变、前缀也没动：只对齐尾巴，结果逐位相同。
        // 换了一份就老老实实整列重来。
        if ext.revision == rev, prev.count == ext.columnCount,
           prev.allSatisfy({ $0.count <= b.count && start <= $0.count }) {
          self = .external(ext.aligned(to: b, from: start, previous: prev), ext.revision)
        } else {
          self = .external(ext.aligned(to: b), ext.revision)
        }
      }
    }
  }
}

// ---------------------------------------------------------------- 各指标状态

/// 布林：mid 是滑动窗均值（能增量），上下轨是窗内标准差，只能从 `start` 往后重扫。
struct BollState: Sendable, Equatable {
  var n: Int
  var k: Double
  var mid: SMALine
  var up: [Double]
  var dn: [Double]

  init(_ close: [Double], n: Int, k: Double) {
    self.n = n
    self.k = k
    mid = SMALine(close, n)
    up = nanArray(close.count)
    dn = nanArray(close.count)
    band(close, from: 0)
  }

  private mutating func band(_ close: [Double], from start: Int) {
    grow(to: close.count, &up, &dn)
    guard n >= 1, close.count >= n else { return }
    for i in max(n - 1, start)..<close.count {
      var s = 0.0
      for j in (i - n + 1)...i {
        let d = close[j] - mid.out[i]
        s += d * d
      }
      let sd = (s / Double(n)).squareRoot()
      up[i] = mid.out[i] + k * sd
      dn[i] = mid.out[i] - k * sd
    }
  }

  mutating func update(_ close: [Double], from start: Int) {
    if mid.canTail(from: start) {
      mid.recompute(close, from: start)
      band(close, from: start)
    } else {
      mid = SMALine(close, n)
      up = nanArray(close.count); dn = nanArray(close.count)
      band(close, from: 0)
    }
  }
}

/// MACD：两条 EMA 差出 DIF，DEA 是 DIF 的 EMA（从 DIF 第一个有值处起算）。
struct MACDState: Sendable, Equatable {
  var fast: Int, slow: Int, sig: Int
  var f: RecursiveLine, s: RecursiveLine
  var dea: RecursiveLine
  var dif: [Double], hist: [Double]

  init(_ close: [Double], fast: Int, slow: Int, sig: Int) {
    self.fast = fast; self.slow = slow; self.sig = sig
    f = RecursiveLine(close, fast, kind: .ema)
    s = RecursiveLine(close, slow, kind: .ema)
    dif = nanArray(close.count)
    hist = nanArray(close.count)
    dea = RecursiveLine([], sig, kind: .ema)
    full(close)
  }

  private mutating func full(_ close: [Double]) {
    dif = nanArray(close.count)
    for i in 0..<close.count where f.out[i].isFinite && s.out[i].isFinite { dif[i] = f.out[i] - s.out[i] }
    let start = dif.firstIndex(where: { $0.isFinite }) ?? dif.count
    dea = RecursiveLine(dif, sig, kind: .ema, offset: start)
    fillHist(from: 0)
  }

  private mutating func fillHist(from start: Int) {
    grow(to: dif.count, &hist)
    for i in max(0, start)..<dif.count {
      hist[i] = (dif[i].isFinite && dea.out[i].isFinite) ? (dif[i] - dea.out[i]) * 2 : .nan
    }
  }

  mutating func update(_ close: [Double], from start: Int) {
    guard f.canTail(from: start), s.canTail(from: start), dea.canTail(from: start) else {
      f = RecursiveLine(close, fast, kind: .ema)
      s = RecursiveLine(close, slow, kind: .ema)
      full(close)
      return
    }
    f.recompute(close, from: start)
    s.recompute(close, from: start)
    grow(to: close.count, &dif)
    for i in start..<close.count {
      dif[i] = (f.out[i].isFinite && s.out[i].isFinite) ? f.out[i] - s.out[i] : .nan
    }
    dea.recompute(dif, from: start)
    fillHist(from: start)
  }
}

/// RSI：涨跌两列各走 RMA，再合成。
struct RSIState: Sendable, Equatable {
  var n: Int
  var up: [Double], dn: [Double]
  var au: RecursiveLine, ad: RecursiveLine
  var out: [Double]

  init(_ close: [Double], n: Int) {
    self.n = n
    (up, dn) = Self.deltas(close)
    au = RecursiveLine(up, n, kind: .rma)
    ad = RecursiveLine(dn, n, kind: .rma)
    out = nanArray(close.count)
    fill(from: 0)
  }

  private static func deltas(_ close: [Double]) -> ([Double], [Double]) {
    var up = nanArray(close.count), dn = nanArray(close.count)
    guard !close.isEmpty else { return (up, dn) }
    up[0] = 0; dn[0] = 0
    for i in 1..<close.count {
      let d = close[i] - close[i - 1]
      up[i] = d > 0 ? d : 0
      dn[i] = d < 0 ? -d : 0
    }
    return (up, dn)
  }

  private mutating func fill(from start: Int) {
    grow(to: up.count, &out)
    for i in max(0, start)..<up.count {
      out[i] = au.out[i].isFinite
        ? (ad.out[i] == 0 ? 100 : 100 - 100 / (1 + au.out[i] / ad.out[i]))
        : .nan
    }
  }

  /// 只补 `[start, count)` 这一段的涨跌幅。
  ///
  /// `up[i]/dn[i]` 只看 `close[i]` 和 `close[i-1]`，前缀没动就一个字都不会变；
  /// 从前每个 tick 都把整列重算一遍（几千根），纯浪费。列比收盘还长（序列缩短了）
  /// 说明前缀的假设不成立，退回整列。
  private mutating func tailDeltas(_ close: [Double], from start: Int) {
    guard up.count <= close.count, dn.count <= close.count else {
      (up, dn) = Self.deltas(close)
      return
    }
    grow(to: close.count, &up, &dn)
    guard !close.isEmpty else { return }
    let s = max(0, min(start, close.count))
    if s == 0 { up[0] = 0; dn[0] = 0 }
    for i in max(1, s)..<close.count {
      let d = close[i] - close[i - 1]
      up[i] = d > 0 ? d : 0
      dn[i] = d < 0 ? -d : 0
    }
  }

  mutating func update(_ close: [Double], from start: Int) {
    tailDeltas(close, from: start)
    if au.canTail(from: start), ad.canTail(from: start) {
      au.recompute(up, from: start)
      ad.recompute(dn, from: start)
      fill(from: start)
    } else {
      au = RecursiveLine(up, n, kind: .rma)
      ad = RecursiveLine(dn, n, kind: .rma)
      out = nanArray(close.count)
      fill(from: 0)
    }
  }
}

/// KDJ：K/D 从 50 起步一路递推，尾部重算得拿上一根的 K/D 当种子。
struct KDJState: Sendable, Equatable {
  var n: Int, kn: Int, dn: Int
  var k: [Double], d: [Double], j: [Double]

  init(_ b: BarSeries, n: Int, kn: Int, dn: Int) {
    self.n = n; self.kn = kn; self.dn = dn
    k = nanArray(b.count); d = nanArray(b.count); j = nanArray(b.count)
    run(b, from: 0, seedK: 50, seedD: 50)
  }

  private mutating func run(_ b: BarSeries, from start: Int, seedK: Double, seedD: Double) {
    grow(to: b.count, &k, &d, &j)
    guard b.count > 0, n >= 1, kn >= 1, dn >= 1 else { return }
    var kk = seedK, dd = seedD
    for i in start..<b.count {
      let hi = hhv(b.high, n, i), lo = llv(b.low, n, i)
      let rsv = hi == lo ? 50 : ((b.close[i] - lo) / (hi - lo)) * 100
      kk = (Double(kn - 1) * kk + rsv) / Double(kn)
      dd = (Double(dn - 1) * dd + kk) / Double(dn)
      if i >= n - 1 { k[i] = kk; d[i] = dd; j[i] = 3 * kk - 2 * dd }
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    if start > 0, start - 1 < k.count, k[start - 1].isFinite, d[start - 1].isFinite {
      run(b, from: start, seedK: k[start - 1], seedD: d[start - 1])
    } else {
      k = nanArray(b.count); d = nanArray(b.count); j = nanArray(b.count)
      run(b, from: 0, seedK: 50, seedD: 50)
    }
  }
}

/// StochRSI：RSI → Stoch → 两条跳过前导 NaN 的均线。
struct SRSIState: Sendable, Equatable {
  var rlen: Int, slen: Int, kn: Int, dn: Int
  var r: RSIState
  var raw: [Double]
  var k: SMALine, d: SMALine

  init(_ close: [Double], rlen: Int, slen: Int, kn: Int, dn: Int) {
    self.rlen = rlen; self.slen = slen; self.kn = kn; self.dn = dn
    r = RSIState(close, n: rlen)
    raw = nanArray(close.count)
    k = SMALine([], kn); d = SMALine([], dn)
    full()
  }

  private mutating func stoch(from start: Int) {
    grow(to: r.out.count, &raw)
    for i in max(0, start)..<r.out.count {
      raw[i] = .nan
      guard r.out[i].isFinite else { continue }
      var hi = -Double.infinity, lo = Double.infinity, ok = true
      var j = i - slen + 1
      while j <= i {
        if j < 0 || !r.out[j].isFinite { ok = false; break }
        if r.out[j] > hi { hi = r.out[j] }
        if r.out[j] < lo { lo = r.out[j] }
        j += 1
      }
      guard ok else { continue }
      raw[i] = hi == lo ? 0 : ((r.out[i] - lo) / (hi - lo)) * 100
    }
  }

  private mutating func full() {
    raw = nanArray(r.out.count)
    stoch(from: 0)
    k = SMALine(raw, kn, offset: raw.firstIndex(where: { $0.isFinite }) ?? raw.count)
    d = SMALine(k.out, dn, offset: k.out.firstIndex(where: { $0.isFinite }) ?? k.out.count)
  }

  mutating func update(_ close: [Double], from start: Int) {
    r.update(close, from: start)
    if start > 0, k.canTail(from: start), d.canTail(from: start) {
      stoch(from: start)
      k.recompute(raw, from: start)
      d.recompute(k.out, from: start)
    } else {
      full()
    }
  }
}

/// ATR：真实波幅再 RMA。
struct ATRState: Sendable, Equatable {
  var n: Int
  var tr: [Double]
  var line: RecursiveLine

  init(_ b: BarSeries, n: Int) {
    self.n = n
    tr = Self.trueRange(b)
    line = RecursiveLine(tr, n, kind: .rma)
  }

  private static func trueRange(_ b: BarSeries) -> [Double] {
    var tr = nanArray(b.count)
    guard b.count > 0 else { return tr }
    tr[0] = b.high[0] - b.low[0]
    for i in 1..<b.count {
      tr[i] = max(b.high[i] - b.low[i], max(abs(b.high[i] - b.close[i - 1]), abs(b.low[i] - b.close[i - 1])))
    }
    return tr
  }

  /// 只补 `[start, count)` 这一段的真实波幅。理由同 RSI 的 `tailDeltas`：
  /// `tr[i]` 只看第 i 根和第 i-1 根的收盘，前缀没动就不会变。
  private mutating func tailTrueRange(_ b: BarSeries, from start: Int) {
    guard tr.count <= b.count else {
      tr = Self.trueRange(b)
      return
    }
    grow(to: b.count, &tr)
    guard b.count > 0 else { return }
    let s = max(0, min(start, b.count))
    if s == 0 { tr[0] = b.high[0] - b.low[0] }
    for i in max(1, s)..<b.count {
      tr[i] = max(b.high[i] - b.low[i], max(abs(b.high[i] - b.close[i - 1]), abs(b.low[i] - b.close[i - 1])))
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    tailTrueRange(b, from: start)
    if line.canTail(from: start) { line.recompute(tr, from: start) }
    else { line = RecursiveLine(tr, n, kind: .rma) }
  }
}

/// 追长到 `n`，补的都是 NaN。（`inout` 不能可变参数，所以按个数重载。）
func grow(to n: Int, _ a: inout [Double]) {
  if a.count < n { a.append(contentsOf: nanArray(n - a.count)) }
}

func grow(to n: Int, _ a: inout [Double], _ b: inout [Double]) {
  grow(to: n, &a); grow(to: n, &b)
}

func grow(to n: Int, _ a: inout [Double], _ b: inout [Double], _ c: inout [Double]) {
  grow(to: n, &a); grow(to: n, &b); grow(to: n, &c)
}
