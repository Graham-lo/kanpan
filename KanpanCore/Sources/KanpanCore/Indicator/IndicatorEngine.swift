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
  @discardableResult
  public mutating func ensure(
    series: BarSeries, wanted: [IndicatorID], params: [IndicatorID: [Int]] = [:],
    oi: OISeries? = nil, dataKey: String = ""
  ) -> Bool {
    let ids = Array(Set(wanted))
    let resolved = Dictionary(uniqueKeysWithValues: ids.map { ($0, params[$0] ?? $0.defaultParams) })
    let k = Self.cacheKey(series: series, wanted: ids, params: resolved, dataKey: dataKey)
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
      // `.oi` 例外：它的输入除了 K 线还有那份持仓量，而缓存键里根本没有持仓量的影子
      // （见 `cacheKey`），`revision` 也管不着它。宁可每次重建。
      if sameData, id != .oi, oldParams[id] == p, let st = states[id], let v = values[id] {
        keptStates[id] = st
        keptValues[id] = v
      } else {
        let st = Self.build(id, p: p, series: series, oi: oi)
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

  /// 末根改了或者新追了一根：只重算尾巴，结果与全量逐位相同。
  public mutating func updateTail(series: BarSeries, oi: OISeries? = nil, dataKey: String = "") {
    // 空序列没有末根可更（WS 事件可能比 REST 历史先到），直接放过——
    // 下面的 `start` 会是 1，拿去扫零长数组就是越界。
    guard !states.isEmpty, series.count > 0 else { return }
    for (id, var st) in states {
      let p = params[id] ?? id.defaultParams
      let start = max(1, series.count - id.tailBars(params: p))
      st.update(series: series, from: start, oi: oi)
      states[id] = st
      values[id] = st.result
    }
    key = Self.cacheKey(series: series, wanted: Array(states.keys), params: params, dataKey: dataKey)
    dataRevision = series.revision
  }

  /// 参数或指标集合没变、只是想拿值。
  public subscript(id: IndicatorID) -> IndicatorResult? { values[id] }

  public static func cacheKey(
    series: BarSeries, wanted: [IndicatorID], params: [IndicatorID: [Int]], dataKey: String
  ) -> String {
    let parts = wanted.map(\.rawValue).sorted().map { id -> String in
      let p = (params[IndicatorID(rawValue: id)!] ?? []).map(String.init).joined(separator: "-")
      return "\(id):\(p)"
    }
    return "\(dataKey)|\(series.symbol)|\(series.interval.rawValue)|\(parts.joined(separator: ","))|\(series.count)"
  }

  // ---------------------------------------------------------------- 状态

  /// `.sma` 既给 MA（收盘）也给 VOL（成交量），靠这个选源列。
  enum Source: Sendable {
    case close, volume
    func column(_ b: BarSeries) -> [Double] { self == .close ? b.close : b.volume }
  }

  private static func build(_ id: IndicatorID, p: [Int], series b: BarSeries, oi: OISeries?) -> State {
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
    case .oi: .oi(oi?.aligned(to: b) ?? nanArray(b.count), oi?.revision ?? 0)
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
    /// 对齐好的那一列，外加它是从哪份持仓量来的（`OISeries.revision`，没有持仓量时 0）。
    /// 记着来源才敢在 `update` 里只对齐尾巴。
    case oi([Double], UInt64)

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
      case .oi(let v, _): IndicatorResult(lines: [v])
      }
    }

    mutating func update(series b: BarSeries, from start: Int, oi: OISeries?) {
      switch self {
      case .sma(var l, let src):
        let col = src.column(b)
        for i in l.indices {
          if l[i].canTail(from: start) { l[i].recompute(col, from: start) }
          else { l[i] = SMALine(col, l[i].n, offset: l[i].offset) }
        }
        self = .sma(l, src)
      case .ema(var l):
        for i in l.indices { l[i].recompute(b.close, from: start) }
        self = .ema(l)
      case .boll(var s): s.update(b.close, from: start); self = .boll(s)
      case .macd(var s): s.update(b.close, from: start); self = .macd(s)
      case .rsi(var l):
        for i in l.indices { l[i].update(b.close, from: start) }
        self = .rsi(l)
      case .kdj(var s): s.update(b, from: start); self = .kdj(s)
      case .srsi(var s): s.update(b.close, from: start); self = .srsi(s)
      case .atr(var s): s.update(b, from: start); self = .atr(s)
      case .oi(let prev, let rev):
        guard let oi, oi.revision != 0 else {
          // 没有持仓量：上次也没有的话，那一列已经全是 NaN，追长就行，
          // 不必每个 tick 现开一条几千长的 NaN 数组。
          if rev == 0, prev.count <= b.count {
            var out = prev
            grow(to: b.count, &out)
            self = .oi(out, 0)
          } else {
            self = .oi(nanArray(b.count), 0)
          }
          return
        }
        // 还是同一份持仓量、前缀也没动：只对齐尾巴，结果逐位相同。
        // 换了一份就老老实实整列重来。
        if oi.revision == rev, prev.count <= b.count, start <= prev.count {
          self = .oi(oi.aligned(to: b, from: start, previous: prev), oi.revision)
        } else {
          self = .oi(oi.aligned(to: b), oi.revision)
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
