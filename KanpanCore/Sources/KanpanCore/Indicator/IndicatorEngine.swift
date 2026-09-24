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
  private var key: CacheKey?
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
    // 参数先理一遍再用：`build` 按下标取固定个数的参数，长度不够就是越界崩溃。
    let resolved = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0.normalizedParams(params[$0])) })
    let k = CacheKey(series: series, params: resolved, external: external, dataKey: dataKey)
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
      let p = resolved[id] ?? id.defaultParams
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
    key = CacheKey(series: series, params: params, external: external, dataKey: dataKey)
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
  ///
  /// 从前是一条拼出来的字符串（`数据键|品种|周期|指标:参数,…|外部@戳,…|根数`），
  /// 每个 tick 要排序、插值、拼接两遍（审查 24）。现在是一个值：字段逐个比，
  /// 指标集合就是参数表的键，比较结论和那条字符串一样，只是不再每 tick 造字符串。
  struct CacheKey: Equatable, Sendable {
    var dataKey: String
    var symbol: String
    var interval: Interval
    /// 指标 → 理过的参数。键集合就是「要哪些指标」。
    var params: [IndicatorID: [Int]]
    /// 外部输入 → 它的戳。
    var external: [IndicatorID: UInt64]
    var count: Int

    init(series: BarSeries, params: [IndicatorID: [Int]],
         external: [IndicatorID: ExternalSeries], dataKey: String) {
      self.dataKey = dataKey
      symbol = series.symbol
      interval = series.interval
      self.params = params
      self.external = external.mapValues(\.revision)
      count = series.count
    }
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
    case .vwap: .vwap(VWAPState(b))
    case .supertrend: .supertrend(SuperTrendState(b, n: p[0], mult: Double(p[1])))
    case .sar: .sar(SARState(b))
    // 主力订单流不从 K 线算（大单来自挂单簿），也从不进 `overlays`；给一列 NaN 占位（和没喂到的外部指标同一种写法）。
    case .orderFlow: .external(ExternalSeries.blank(1, b.count), 0)
    case .dmi: .dmi(DMIState(b, n: p[0]))
    case .cvd: .cvd(CVDState(b))
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
    case vwap(VWAPState)
    case supertrend(SuperTrendState)
    case sar(SARState)
    case dmi(DMIState)
    case cvd(CVDState)
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
      case .vwap(let s): IndicatorResult(lines: [s.out])
      // 超级趋势与抛物线转向都只出一条线，多空靠 `dir` 那一列分段着色。
      case .supertrend(let s): IndicatorResult(lines: [s.line], dir: s.dir)
      case .sar(let s): IndicatorResult(lines: [s.out], dir: s.dir)
      case .dmi(let s): IndicatorResult(lines: [s.pdi, s.mdi, s.adx.out])
      case .cvd(let s): IndicatorResult(lines: [s.out])
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
      case .vwap(var s): self = .moved; s.update(b, from: start); self = .vwap(s)
      case .supertrend(var s): self = .moved; s.update(b, from: start); self = .supertrend(s)
      case .sar(var s): self = .moved; s.update(b, from: start); self = .sar(s)
      case .dmi(var s): self = .moved; s.update(b, from: start); self = .dmi(s)
      case .cvd(var s): self = .moved; s.update(b, from: start); self = .cvd(s)
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

// ---------------------------------------------------------------- 累计周期

/// 毫秒时间戳 → UTC 的月序号（年×12+月）。
///
/// 不走 `Calendar`：那东西带时区和本地化，同一根 K 线在不同设备上可能落进不同的月。
/// 这里要的只是币安那套 UTC 口径，整数算术（civil-from-days）算得又准又快。
func utcMonthIndex(_ ms: Int64) -> Int {
  let dayMs: Int64 = 86_400_000
  var z = Int(ms / dayMs)
  if ms < 0, ms % dayMs != 0 { z -= 1 }
  z += 719_468
  let era = (z >= 0 ? z : z - 146_096) / 146_097
  let doe = z - era * 146_097
  let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let m = mp < 10 ? mp + 3 : mp - 9
  return (m <= 2 ? y + 1 : y) * 12 + m
}

/// 第 i 根是不是一个新累计周期的头一根。
///
/// 累计型指标（当日VWAP、累计成交量差）必须有一个固定的归零点，否则线的高低只取决于
/// **这次加载了多少历史**：往回翻一页，整条线换一个样，读不出任何东西。所以日内周期
/// 按 UTC 零点归零（币安的日线就是这么切的），日线及以上按自然月归零——日线上再按天
/// 归零的话每根自己就是一个周期，累计就不存在了。这是 TradingView 的口径。
func startsAnchorPeriod(_ b: BarSeries, _ i: Int) -> Bool {
  guard i > 0 else { return true }
  let dayMs: Int64 = 86_400_000
  let now = b.time(at: i), prev = b.time(at: i - 1)
  if b.step < dayMs { return now / dayMs != prev / dayMs }
  return utcMonthIndex(now) != utcMonthIndex(prev)
}

/// 当日VWAP：成交量加权均价，每天零点归零。
///
/// 逐根的累加和存下来，尾部重算才接得上——和 `SMALine` 存 `sum` 是同一个道理。
struct VWAPState: Sendable, Equatable {
  var out: [Double]
  var pv: [Double]
  var vv: [Double]

  init(_ b: BarSeries) {
    out = nanArray(b.count); pv = nanArray(b.count); vv = nanArray(b.count)
    run(b, from: 0, seedPV: 0, seedVV: 0)
  }

  private mutating func run(_ b: BarSeries, from start: Int, seedPV: Double, seedVV: Double) {
    grow(to: b.count, &out, &pv, &vv)
    guard b.count > 0, start < b.count else { return }
    var sp = seedPV, sv = seedVV
    for i in start..<b.count {
      if startsAnchorPeriod(b, i) { sp = 0; sv = 0 }
      // 典型价（高+低+收）/3，和交易所自己算 VWAP 的口径一致。
      let tp = (b.high[i] + b.low[i] + b.close[i]) / 3
      sp += tp * b.volume[i]
      sv += b.volume[i]
      pv[i] = sp; vv[i] = sv
      // 一整天零成交（新上市、极冷门）时退回典型价，不出 NaN 也不除零。
      out[i] = sv > 0 ? sp / sv : tp
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    if start > 0, start - 1 < pv.count, pv[start - 1].isFinite, vv[start - 1].isFinite {
      run(b, from: start, seedPV: pv[start - 1], seedVV: vv[start - 1])
    } else {
      out = nanArray(b.count); pv = nanArray(b.count); vv = nanArray(b.count)
      run(b, from: 0, seedPV: 0, seedVV: 0)
    }
  }
}

/// 累计成交量差（CVD）：逐根的「主动买 − 主动卖」累加起来。
///
/// 一根里主动卖 = 成交量 − 主动买，所以这一根的净额就是 `2×主动买 − 成交量`。
/// 它回答的是「这段行情是被买上去的还是被卖下去的」：价格创了新高而这条线没跟上，
/// 说明推价的是撤掉的卖单而不是真的买盘。
///
/// **和当日VWAP 用同一个锚**（日内按 UTC 零点、日线及以上按自然月）归零。不归零的话
/// 这条线的绝对值取决于「这台手机当前加载了多少历史」——往前补一段历史，整条线就整体
/// 平移一次，同一个品种在两台设备上读出来的数还不一样。锚定之后它在任何设备上都可复现。
///
/// **主动买量缺失的那一根留白，累计值原样往下传。** 缺失来自撮合价合成的根、OKX、
/// 被截断的镜像行（见 `Bar.takerBuy`）。把缺失当 0 会凭空画出一段砸下去的台阶，
/// 而把累计值污染成 NaN 会让这一根之后的整条线全都消失。留白只损失那一根。
struct CVDState: Sendable, Equatable {
  var out: [Double]
  /// 到第 i 根为止的累计值；这一根不知道主动买量时沿用上一根，好让尾部重算接得上。
  var sum: [Double]

  init(_ b: BarSeries) {
    out = nanArray(b.count); sum = nanArray(b.count)
    run(b, from: 0, seed: 0)
  }

  private mutating func run(_ b: BarSeries, from start: Int, seed: Double) {
    grow(to: b.count, &out, &sum)
    guard b.count > 0, start < b.count else { return }
    var s = seed
    for i in start..<b.count {
      if startsAnchorPeriod(b, i) { s = 0 }
      let buy = b.takerBuy[i], vol = b.volume[i]
      if buy.isFinite, vol.isFinite {
        s += 2 * buy - vol
        out[i] = s
      } else {
        out[i] = .nan
      }
      sum[i] = s
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    if start > 0, start - 1 < sum.count, sum[start - 1].isFinite {
      run(b, from: start, seed: sum[start - 1])
    } else {
      out = nanArray(b.count); sum = nanArray(b.count)
      run(b, from: 0, seed: 0)
    }
  }
}

/// 超级趋势：ATR 通道加一条只会往趋势方向收紧的轨，翻向那一根直接跳到价格另一侧。
///
/// 两条「最终轨」逐根存着，不只是为了增量——翻向判定要拿**上一根的轨**比，
/// 没存下来就没法从中间接着算。
struct SuperTrendState: Sendable, Equatable {
  var n: Int
  var mult: Double
  var a: ATRState
  var up: [Double]
  var dn: [Double]
  var line: [Double]
  var dir: [Double]

  init(_ b: BarSeries, n: Int, mult: Double) {
    self.n = n
    self.mult = mult
    a = ATRState(b, n: n)
    up = nanArray(b.count); dn = nanArray(b.count)
    line = nanArray(b.count); dir = nanArray(b.count)
    run(b, from: 0, seedUp: .nan, seedDn: .nan, long: true)
  }

  private mutating func run(_ b: BarSeries, from start: Int,
                            seedUp: Double, seedDn: Double, long seedLong: Bool) {
    grow(to: b.count, &up, &dn); grow(to: b.count, &line, &dir)
    guard b.count > 0, start < b.count else { return }
    var fUp = seedUp, fDn = seedDn, long = seedLong
    for i in start..<b.count {
      let width = a.line.out[i]
      guard width.isFinite else {
        up[i] = .nan; dn[i] = .nan; line[i] = .nan; dir[i] = .nan
        continue
      }
      let mid = (b.high[i] + b.low[i]) / 2
      let basicUp = mid + mult * width
      let basicDn = mid - mult * width
      let prevClose = i > 0 ? b.close[i - 1] : b.close[i]
      // 轨只往「夹紧」的方向走；价格穿出去了才允许松开重来。
      fUp = (!fUp.isFinite || basicUp < fUp || prevClose > fUp) ? basicUp : fUp
      fDn = (!fDn.isFinite || basicDn > fDn || prevClose < fDn) ? basicDn : fDn
      if long {
        if b.close[i] < fDn { long = false }
      } else if b.close[i] > fUp {
        long = true
      }
      up[i] = fUp; dn[i] = fDn
      line[i] = long ? fDn : fUp
      dir[i] = long ? 1 : -1
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    a.update(b, from: start)
    if start > 0, start - 1 < dir.count,
       up[start - 1].isFinite, dn[start - 1].isFinite, dir[start - 1].isFinite {
      run(b, from: start, seedUp: up[start - 1], seedDn: dn[start - 1], long: dir[start - 1] > 0)
    } else {
      up = nanArray(b.count); dn = nanArray(b.count)
      line = nanArray(b.count); dir = nanArray(b.count)
      run(b, from: 0, seedUp: .nan, seedDn: .nan, long: true)
    }
  }
}

/// 抛物线转向（Wilder）。加速因子从 0.02 起、每创一次新高加 0.02、封顶 0.20。
///
/// 这三个数不做成参数：它们是 Wilder 定的出厂值，也是所有平台的默认，
/// 摆出来只会变成一个用户看不懂该填什么的输入框（`kanpan-sector-page-no-basis-picker`）。
///
/// 每根的极值点与加速因子都存着，理由同超级趋势：递推状态不存下来就接不上尾巴。
struct SARState: Sendable, Equatable {
  /// 加速步长与上限。
  static let step = 0.02
  static let maxAF = 0.20

  var out: [Double]
  var dir: [Double]
  var ep: [Double]
  var af: [Double]

  init(_ b: BarSeries) {
    out = nanArray(b.count); dir = nanArray(b.count)
    ep = nanArray(b.count); af = nanArray(b.count)
    full(b)
  }

  private mutating func full(_ b: BarSeries) {
    out = nanArray(b.count); dir = nanArray(b.count)
    ep = nanArray(b.count); af = nanArray(b.count)
    guard b.count >= 2 else { return }
    // 头一根没有上一根可比，拿第二根的方向当种子；走错了也就错头几根，
    // 价格一穿轨就自己翻回来了。
    let long = b.close[1] >= b.close[0]
    out[0] = long ? b.low[0] : b.high[0]
    ep[0] = long ? b.high[0] : b.low[0]
    af[0] = Self.step
    dir[0] = long ? 1 : -1
    run(b, from: 1)
  }

  private mutating func run(_ b: BarSeries, from start: Int) {
    grow(to: b.count, &out, &dir); grow(to: b.count, &ep, &af)
    guard start >= 1, start < b.count else { return }
    var sar = out[start - 1], e = ep[start - 1], a = af[start - 1]
    var long = dir[start - 1] > 0
    for i in start..<b.count {
      sar += a * (e - sar)
      if long {
        // 轨不许进到前两根的最低价里面去，否则会在一根实体里被自己扫出去。
        sar = min(sar, b.low[i - 1], b.low[max(0, i - 2)])
        if b.low[i] < sar {
          long = false; sar = e; e = b.low[i]; a = Self.step
        } else if b.high[i] > e {
          e = b.high[i]; a = min(a + Self.step, Self.maxAF)
        }
      } else {
        sar = max(sar, b.high[i - 1], b.high[max(0, i - 2)])
        if b.high[i] > sar {
          long = true; sar = e; e = b.high[i]; a = Self.step
        } else if b.low[i] < e {
          e = b.low[i]; a = min(a + Self.step, Self.maxAF)
        }
      }
      out[i] = sar; ep[i] = e; af[i] = a; dir[i] = long ? 1 : -1
    }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    if start >= 1, start - 1 < out.count,
       out[start - 1].isFinite, ep[start - 1].isFinite,
       af[start - 1].isFinite, dir[start - 1].isFinite {
      run(b, from: start)
    } else {
      full(b)
    }
  }
}

/// 动向指标：+DI / -DI 两条方向线，加一条趋势强度 ADX。
///
/// 三列原始动向（+DM、-DM、真实波幅）只看第 i 根与第 i-1 根，前缀没动就一个字不变，
/// 所以尾部只补这一段——和 `RSIState.tailDeltas`、`ATRState.tailTrueRange` 一个写法。
struct DMIState: Sendable, Equatable {
  var n: Int
  var pdm: [Double], mdm: [Double], tr: [Double]
  var spdm: RecursiveLine, smdm: RecursiveLine, str: RecursiveLine
  var pdi: [Double], mdi: [Double], dx: [Double]
  var adx: RecursiveLine

  init(_ b: BarSeries, n: Int) {
    self.n = n
    (pdm, mdm, tr) = Self.raw(b)
    spdm = RecursiveLine(pdm, n, kind: .rma)
    smdm = RecursiveLine(mdm, n, kind: .rma)
    str = RecursiveLine(tr, n, kind: .rma)
    pdi = nanArray(b.count); mdi = nanArray(b.count); dx = nanArray(b.count)
    adx = RecursiveLine([], n, kind: .rma)
    full()
  }

  private static func raw(_ b: BarSeries) -> ([Double], [Double], [Double]) {
    var pdm = nanArray(b.count), mdm = nanArray(b.count), tr = nanArray(b.count)
    guard b.count > 0 else { return (pdm, mdm, tr) }
    pdm[0] = 0; mdm[0] = 0
    tr[0] = b.high[0] - b.low[0]
    for i in 1..<b.count { fill(b, i, &pdm, &mdm, &tr) }
    return (pdm, mdm, tr)
  }

  private static func fill(_ b: BarSeries, _ i: Int,
                          _ pdm: inout [Double], _ mdm: inout [Double], _ tr: inout [Double]) {
    let up = b.high[i] - b.high[i - 1]
    let down = b.low[i - 1] - b.low[i]
    // 只有「明显更大的那一边」才算一次动向；两边一样大或者都在收缩，两边都记 0。
    pdm[i] = (up > down && up > 0) ? up : 0
    mdm[i] = (down > up && down > 0) ? down : 0
    tr[i] = max(b.high[i] - b.low[i],
                max(abs(b.high[i] - b.close[i - 1]), abs(b.low[i] - b.close[i - 1])))
  }

  private mutating func full() {
    pdi = nanArray(tr.count); mdi = nanArray(tr.count); dx = nanArray(tr.count)
    fillDI(from: 0)
    adx = RecursiveLine(dx, n, kind: .rma, offset: dx.firstIndex(where: { $0.isFinite }) ?? dx.count)
  }

  private mutating func fillDI(from start: Int) {
    grow(to: tr.count, &pdi, &mdi, &dx)
    for i in max(0, start)..<tr.count {
      guard str.out[i].isFinite, str.out[i] != 0,
            spdm.out[i].isFinite, smdm.out[i].isFinite else {
        pdi[i] = .nan; mdi[i] = .nan; dx[i] = .nan
        continue
      }
      let p = 100 * spdm.out[i] / str.out[i]
      let m = 100 * smdm.out[i] / str.out[i]
      pdi[i] = p; mdi[i] = m
      let sum = p + m
      // 两条方向线都是 0（一整段完全没有动向）时强度记 0，不是 NaN——线断一截更难读。
      dx[i] = sum == 0 ? 0 : 100 * abs(p - m) / sum
    }
  }

  private mutating func tailRaw(_ b: BarSeries, from start: Int) {
    guard pdm.count <= b.count, mdm.count <= b.count, tr.count <= b.count else {
      (pdm, mdm, tr) = Self.raw(b)
      return
    }
    grow(to: b.count, &pdm, &mdm, &tr)
    guard b.count > 0 else { return }
    let s = max(0, min(start, b.count))
    if s == 0 { pdm[0] = 0; mdm[0] = 0; tr[0] = b.high[0] - b.low[0] }
    for i in max(1, s)..<b.count { Self.fill(b, i, &pdm, &mdm, &tr) }
  }

  mutating func update(_ b: BarSeries, from start: Int) {
    tailRaw(b, from: start)
    guard spdm.canTail(from: start), smdm.canTail(from: start), str.canTail(from: start),
          adx.canTail(from: start) else {
      spdm = RecursiveLine(pdm, n, kind: .rma)
      smdm = RecursiveLine(mdm, n, kind: .rma)
      str = RecursiveLine(tr, n, kind: .rma)
      full()
      return
    }
    spdm.recompute(pdm, from: start)
    smdm.recompute(mdm, from: start)
    str.recompute(tr, from: start)
    fillDI(from: start)
    adx.recompute(dx, from: start)
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
