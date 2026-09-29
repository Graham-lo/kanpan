// 移植自 KanpanCore/Model/Bar.swift、BarSeries.swift、Interval.swift、ExternalSeries.swift、Aggregator.bucketStart
//
// 列式（SoA）K 线序列。openTime 列为空 ⇔ 严格等距（走 t0 + i*step 快路）。
// revision / prefixRevision 两个戳：指标引擎靠它们 O(1) 判断「还是刚才那份」「只动了末根」。

export interface Bar {
  openTime: number
  open: number
  high: number
  low: number
  close: number
  volume: number
  /** 主动买入量，缺失为 NaN。 */
  takerBuy: number
}

export const bar = (openTime: number, open: number, high: number, low: number, close: number, volume: number, takerBuy = NaN): Bar =>
  ({ openTime, open, high, low, close, volume, takerBuy })

export function isValidMarketBar(b: Bar): boolean {
  return [b.open, b.high, b.low, b.close, b.volume].every(Number.isFinite)
    && b.low >= 0 && b.high >= Math.max(b.open, b.close) && b.low <= Math.min(b.open, b.close) && b.volume >= 0
}

// ------------------------------------------------------------------ 周期

export type Interval = '1m' | '3m' | '5m' | '15m' | '30m' | '1h' | '2h' | '4h' | '6h' | '12h' | '1d' | '1w' | '1M' | '1y'

const MIN = 60_000, HOUR = 3_600_000, DAY = 86_400_000
export const INTERVAL_STEP: Record<Interval, number> = {
  '1m': MIN, '3m': 3 * MIN, '5m': 5 * MIN, '15m': 15 * MIN, '30m': 30 * MIN,
  '1h': HOUR, '2h': 2 * HOUR, '4h': 4 * HOUR, '6h': 6 * HOUR, '12h': 12 * HOUR,
  '1d': DAY, '1w': 7 * DAY, '1M': 30 * DAY, '1y': 365 * DAY,
}
export const INTERVALS = Object.keys(INTERVAL_STEP) as Interval[]
export const stepMs = (iv: Interval): number => INTERVAL_STEP[iv]
export const isIrregular = (iv: Interval): boolean => iv === '1M' || iv === '1y'
export const INTERVAL_SHORT: Record<Interval, string> = {
  '1m': '1分', '3m': '3分', '5m': '5分', '15m': '15分', '30m': '30分',
  '1h': '1时', '2h': '2时', '4h': '4时', '6h': '6时', '12h': '12时',
  '1d': '1日', '1w': '1周', '1M': '1月', '1y': '1年',
}
export const INTERVAL_DISPLAY: Record<Interval, string> = {
  '1m': '1 分钟', '3m': '3 分钟', '5m': '5 分钟', '15m': '15 分钟', '30m': '30 分钟',
  '1h': '1 小时', '2h': '2 小时', '4h': '4 小时', '6h': '6 小时', '12h': '12 小时',
  '1d': '1 天', '1w': '1 周', '1M': '1 月', '1y': '1 年',
}
export const QUICK_INTERVALS: Interval[] = ['5m', '30m', '1h', '4h', '1d', '1w']

const floorDiv = (a: number, b: number): number => Math.floor(a / b)

/** Aggregator.bucketStart：币安的桶边界。周线从 1970-01-05（周一）起算，月 / 年按 UTC 日历。 */
export function bucketStart(ms: number, iv: Interval): number {
  switch (iv) {
    case '1w': return floorDiv(ms - 4 * DAY, 7 * DAY) * (7 * DAY) + 4 * DAY
    case '1M': { const d = new Date(ms); return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1) }
    case '1y': { const d = new Date(ms); return Date.UTC(d.getUTCFullYear(), 0, 1) }
    default: return floorDiv(ms, INTERVAL_STEP[iv]) * INTERVAL_STEP[iv]
  }
}

// ------------------------------------------------------------------ 戳

let stamp = 0
export const nextStamp = (): number => ++stamp

/** Double.jsRounded：JS 的 Math.round 语义（+0.5 向下取整）。 */
export const jsRound = (x: number): number => Math.floor(x + 0.5)

// ------------------------------------------------------------------ 序列

export class BarSeries {
  readonly symbol: string
  readonly interval: Interval
  t0: number
  readonly step: number
  open: number[]
  high: number[]
  low: number[]
  close: number[]
  volume: number[]
  takerBuy: number[]
  /** 空 ⇔ 严格等距。 */
  openTime: number[]
  revision = 0
  prefixRevision = 0

  constructor(o: {
    symbol: string; interval: Interval; t0: number; step?: number
    open: number[]; high: number[]; low: number[]; close: number[]; volume: number[]
    takerBuy?: number[]; openTime?: number[]
  }) {
    this.symbol = o.symbol.toUpperCase()
    this.interval = o.interval
    this.t0 = o.t0
    this.step = o.step ?? INTERVAL_STEP[o.interval]
    this.open = o.open; this.high = o.high; this.low = o.low; this.close = o.close; this.volume = o.volume
    this.takerBuy = o.takerBuy && o.takerBuy.length === o.close.length ? o.takerBuy : new Array(o.close.length).fill(NaN)
    this.openTime = o.openTime ?? []
    this.stampAll()
  }

  static fromBars(symbol: string, interval: Interval, bars: Bar[]): BarSeries {
    return new BarSeries({
      symbol, interval, t0: bars[0]?.openTime ?? 0, step: INTERVAL_STEP[interval],
      open: bars.map(b => b.open), high: bars.map(b => b.high), low: bars.map(b => b.low),
      close: bars.map(b => b.close), volume: bars.map(b => b.volume), takerBuy: bars.map(b => b.takerBuy),
      openTime: BarSeries.canDropTimes(bars, interval) ? [] : bars.map(b => b.openTime),
    })
  }

  static empty(symbol: string, interval: Interval): BarSeries {
    return new BarSeries({ symbol, interval, t0: 0, open: [], high: [], low: [], close: [], volume: [] })
  }

  private static canDropTimes(bars: Bar[], iv: Interval): boolean {
    if (isIrregular(iv)) return false
    if (!bars.length) return true
    const t0 = bars[0].openTime, step = INTERVAL_STEP[iv]
    if (step <= 0) return false
    for (let i = 0; i < bars.length; i++) if (bars[i].openTime !== t0 + i * step) return false
    return true
  }

  static isStrictlyRegular(times: number[], t0: number, step: number): boolean {
    if (step <= 0) return false
    for (let i = 0; i < times.length; i++) if (times[i] !== t0 + i * step) return false
    return true
  }

  /** 直接改了列之后调用：两个戳都作废。 */
  stampAll(): void {
    this.revision = nextStamp()
    this.prefixRevision = nextStamp()
  }

  clone(): BarSeries {
    const c = new BarSeries({
      symbol: this.symbol, interval: this.interval, t0: this.t0, step: this.step,
      open: this.open.slice(), high: this.high.slice(), low: this.low.slice(), close: this.close.slice(),
      volume: this.volume.slice(), takerBuy: this.takerBuy.slice(), openTime: this.openTime.slice(),
    })
    c.revision = this.revision; c.prefixRevision = this.prefixRevision
    return c
  }

  get count(): number { return this.close.length }
  get isEmpty(): boolean { return this.close.length === 0 }

  private materializeTimes(): void {
    if (this.openTime.length) return
    const n = this.count, out = new Array<number>(n)
    for (let i = 0; i < n; i++) out[i] = this.t0 + i * this.step
    this.openTime = out
  }

  time(i: number): number {
    if (this.openTime.length) return this.openTime[Math.max(0, Math.min(this.openTime.length - 1, i))]
    return this.t0 + i * this.step
  }

  get lastTime(): number { return this.count > 0 ? this.time(this.count - 1) : this.t0 }
  get firstTime(): number { return this.t0 }

  /** 离时刻 t 最近的那一根（夹在范围内）。 */
  index(t: number): number {
    const n = this.count
    if (n <= 0) return 0
    if (!this.openTime.length) {
      const i = jsRound((t - this.t0) / this.step)
      return Math.max(0, Math.min(n - 1, i))
    }
    const ot = this.openTime
    let lo = 0, hi = n - 1
    if (t <= ot[0]) return 0
    if (t >= ot[hi]) return hi
    while (lo + 1 < hi) {
      const mid = (lo + hi) >> 1
      if (ot[mid] <= t) lo = mid; else hi = mid
    }
    const dLo = Math.abs(t - ot[lo]), dHi = Math.abs(ot[hi] - t)
    return dHi < dLo ? hi : lo
  }

  firstIndexAtOrAfter(t: number): number {
    let lo = 0, hi = this.count
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (this.time(mid) < t) lo = mid + 1; else hi = mid
    }
    return lo
  }

  bar(i: number): Bar {
    return {
      openTime: this.time(i), open: this.open[i], high: this.high[i], low: this.low[i], close: this.close[i],
      volume: this.volume[i], takerBuy: i < this.takerBuy.length ? this.takerBuy[i] : NaN,
    }
  }

  replaceLast(b: Bar): void {
    if (this.count === 0) { this.append(b); return }
    const prefix = this.prefixRevision
    const i = this.count - 1
    if (!this.openTime.length && b.openTime !== this.t0 + i * this.step) this.materializeTimes()
    this.open[i] = b.open; this.high[i] = b.high; this.low[i] = b.low; this.close[i] = b.close; this.volume[i] = b.volume
    if (i < this.takerBuy.length) this.takerBuy[i] = b.takerBuy
    if (this.openTime.length) this.openTime[i] = b.openTime
    this.revision = nextStamp()
    this.prefixRevision = prefix
  }

  append(b: Bar): void {
    const prefix = this.revision
    if (this.count === 0) this.t0 = b.openTime
    const keep = this.openTime.length > 0 || isIrregular(this.interval) || b.openTime !== this.t0 + this.count * this.step
    if (keep) this.materializeTimes()
    this.open.push(b.open); this.high.push(b.high); this.low.push(b.low)
    this.close.push(b.close); this.volume.push(b.volume); this.takerBuy.push(b.takerBuy)
    if (keep) this.openTime.push(b.openTime)
    this.revision = nextStamp()
    this.prefixRevision = prefix
  }

  /** 同一时刻替换末根、更晚的追加、更早的丢弃（返回 false）。 */
  upsert(b: Bar): boolean {
    if (this.count === 0) { this.append(b); return true }
    const last = this.lastTime
    if (b.openTime === last) { this.replaceLast(b); return true }
    if (b.openTime > last) { this.append(b); return true }
    return false
  }

  replaceSuffix(index: number, bars: Bar[]): void {
    const k = Math.max(0, Math.min(index, this.count))
    if (this.openTime.length) this.openTime.length = k
    this.open.length = k; this.high.length = k; this.low.length = k; this.close.length = k; this.volume.length = k
    if (k < this.takerBuy.length) this.takerBuy.length = k
    if (this.count === 0) this.openTime = []
    this.stampAll()
    for (const b of bars) this.append(b)
    if (this.openTime.length && !isIrregular(this.interval) && BarSeries.isStrictlyRegular(this.openTime, this.t0, this.step)) this.openTime = []
  }

  /** 翻页补历史：同一 openTime 只留一根（后到为准），只接比 t0 早的。 */
  prepend(bars: Bar[]): void {
    if (!bars.length) return
    const byTime = new Map<number, Bar>()
    for (const b of bars) byTime.set(b.openTime, b)
    const sorted = [...byTime.values()].sort((a, b) => a.openTime - b.openTime)
    const cut = sorted.filter(b => this.count === 0 || b.openTime < this.t0)
    if (!cut.length) return
    this.materializeTimes()
    this.openTime = cut.map(b => b.openTime).concat(this.openTime)
    this.open = cut.map(b => b.open).concat(this.open)
    this.high = cut.map(b => b.high).concat(this.high)
    this.low = cut.map(b => b.low).concat(this.low)
    this.close = cut.map(b => b.close).concat(this.close)
    this.volume = cut.map(b => b.volume).concat(this.volume)
    this.takerBuy = cut.map(b => b.takerBuy).concat(this.takerBuy)
    this.t0 = cut[0].openTime
    if (!isIrregular(this.interval) && BarSeries.isStrictlyRegular(this.openTime, this.t0, this.step)) this.openTime = []
    this.stampAll()
  }

  /** 这一份是不是 `other` 追加了一根之后的样子。 */
  isOneBarAfter(other: BarSeries): boolean {
    return this.count === other.count + 1 && other.count > 0 && this.prefixRevision === other.revision
  }
}

// ------------------------------------------------------------------ 外部采样序列

/** 持仓量、多空比、主动买卖比、基差（ExternalSeries）。每列等长，顺序与 lineNames 一致。 */
export class ExternalSeries {
  t0: number
  step: number
  columns: number[][]
  timestamps: number[] | null
  bucketInterval: Interval | null
  revision: number

  constructor(o: { t0: number; step: number; columns: number[][]; timestamps?: number[] | null; bucketInterval?: Interval | null }) {
    this.t0 = o.t0; this.step = o.step; this.columns = o.columns
    this.timestamps = o.timestamps ?? null; this.bucketInterval = o.bucketInterval ?? null
    this.revision = nextStamp()
  }

  /** OISeries(points:)：按时间排序后的稀疏采样。 */
  static fromPoints(points: { time: number; values: number[] }[], step = 300_000, bucketInterval: Interval | null = null): ExternalSeries {
    const ordered = points.slice().sort((a, b) => a.time - b.time)
    const cols = ordered.length ? ordered[0].values.length : 1
    const columns = Array.from({ length: cols }, (_, c) => ordered.map(p => p.values[c] ?? NaN))
    return new ExternalSeries({ t0: ordered[0]?.time ?? 0, step, columns, timestamps: ordered.map(p => p.time), bucketInterval })
  }

  get columnCount(): number { return this.columns.length }
  get count(): number { return this.columns[0]?.length ?? 0 }

  static blank(cols: number, count: number): number[][] {
    return Array.from({ length: Math.max(0, cols) }, () => new Array<number>(count).fill(NaN))
  }

  private matches(j: number, t: number, last: number, times: number[]): boolean {
    const iv = this.bucketInterval
    if (iv) {
      return INTERVAL_STEP[iv] >= 300_000
        ? times[j] === bucketStart(t, iv)
        : times[j] <= t && t - times[j] < 300_000
    }
    return times[j] <= t && t < last + this.step
  }

  /** 每根 K 线取哪一条采样。 */
  aligned(series: BarSeries): number[][] {
    const out = ExternalSeries.blank(this.columns.length, series.count)
    if (this.step <= 0 || !this.columns.length) return out
    const n = this.count
    if (!this.columns.every(c => c.length === n)) return out
    const times = this.timestamps
    if (times) {
      if (times.length !== n || !n) return out
      const last = times[n - 1]
      let j = 0
      for (let i = 0; i < series.count; i++) {
        const t = series.time(i)
        while (j + 1 < times.length && times[j + 1] <= t) j++
        if (!this.matches(j, t, last, times)) continue
        for (let c = 0; c < this.columns.length; c++) out[c][i] = this.columns[c][j]
      }
      return out
    }
    for (let i = 0; i < series.count; i++) {
      const j = Math.floor((series.time(i) - this.t0) / this.step)
      if (j >= 0 && j < n) for (let c = 0; c < this.columns.length; c++) out[c][i] = this.columns[c][j]
    }
    return out
  }

  /**
   * 只重算 [start, count) 那一段。**原地改 previous 并把它交回**（调用方独占这几列：指标引擎的 ExternalState）；
   * 以前每跳一次都把整列复制一遍（几列 × 1500 根），推送一密就是一串白分配。形状对不上时照旧整列新算。
   */
  alignedFrom(series: BarSeries, start: number, previous: number[][]): number[][] {
    if (previous.length !== this.columns.length || start < 0
      || !previous.every(p => p.length <= series.count && start <= p.length)) return this.aligned(series)
    if (this.step <= 0) return this.aligned(series)
    const n = this.count
    if (!this.columns.every(c => c.length === n)) return this.aligned(series)
    const out = previous
    for (const col of out) while (col.length < series.count) col.push(NaN)
    if (start >= series.count) return out
    const times = this.timestamps
    if (times) {
      if (times.length !== n || !n) return this.aligned(series)
      const last = times[n - 1]
      let lo = 0, hi = n - 1
      const tb = series.time(start)
      while (lo < hi) {
        const mid = (lo + hi + 1) >> 1
        if (times[mid] <= tb) lo = mid; else hi = mid - 1
      }
      let j = lo
      for (let i = start; i < series.count; i++) {
        const t = series.time(i)
        while (j + 1 < times.length && times[j + 1] <= t) j++
        const hit = this.matches(j, t, last, times)
        for (let c = 0; c < this.columns.length; c++) out[c][i] = hit ? this.columns[c][j] : NaN
      }
      return out
    }
    for (let i = start; i < series.count; i++) {
      const j = Math.floor((series.time(i) - this.t0) / this.step)
      const hit = j >= 0 && j < n
      for (let c = 0; c < this.columns.length; c++) out[c][i] = hit ? this.columns[c][j] : NaN
    }
    return out
  }
}

// ------------------------------------------------------------------ 平均 K 线
// 移植自 KanpanCore/Sources/KanpanCore/Model/HeikinAshi.swift

/** 只算 [lo, hi] 这一段的平均 K 线；向前多推 warmup 根热身，热身段只推 prev、不落进结果。 */
export function heikinAshiSlice(s: BarSeries, lo: number, hi: number, warmup = 200): { open: number[]; high: number[]; low: number[]; close: number[] } {
  const open: number[] = [], high: number[] = [], low: number[] = [], close: number[] = []
  if (s.count <= 0) return { open, high, low, close }
  const a = Math.max(0, Math.min(lo, s.count - 1))
  const z = Math.max(a, Math.min(hi, s.count - 1))
  const start = Math.max(0, a - Math.max(0, warmup))
  let prevOpen = NaN, prevClose = NaN
  for (let i = start; i <= z; i++) {
    const hc = (s.open[i] + s.high[i] + s.low[i] + s.close[i]) / 4
    const ho = Number.isFinite(prevOpen) ? (prevOpen + prevClose) / 2 : (s.open[i] + s.close[i]) / 2
    if (i >= a) {
      open.push(ho)
      high.push(Math.max(s.high[i], Math.max(ho, hc)))
      low.push(Math.min(s.low[i], Math.min(ho, hc)))
      close.push(hc)
    }
    prevOpen = ho
    prevClose = hc
  }
  return { open, high, low, close }
}
