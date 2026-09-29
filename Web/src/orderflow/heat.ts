/* Hkline Web · 主力订单流 · 深度热力
 *
 * 实时：每秒从聚合好的细桶里取中间价 ±5% 的一列（三家分通道），环形存 2 小时。
 * 回填：GET /v1/market/orderflow/heat（三家合起来、价格按「每个币」计）。一行代表多长以服务端返回的
 *       bucketMs 为准（默认 5 秒，行数超过 20 万时服务端自动放粗到 10/30/60 秒乃至 5–60 分钟），列宽照它画，
 *       不假定 5 秒；没跟踪的品种返回空行。只用在实时列开始之前的时段；接口不在就只有实时，不造数据。
 * 画：一根 K 线一列（1 分钟图按秒成列，太挤时几秒并一列），行与梯子同一套「k 个细桶一行」，
 *     亮度 = 值 ÷ 画面里可见格子的第 95 百分位。
 * 为和服务端一致，每本簿不到它产品门槛 5% 的桶不计。
 */
import type { Thresholds } from './types'
import { bucketIndex } from './bucket'
import { EXCHANGE_CH, rowOf, type FineBook } from './aggregate'

export const HEAT_RADIUS = 0.05
export const HEAT_LIVE_CAP = 7200
export const HEAT_BACK_CAP = 40_000
export const HEAT_MIN_FRACTION = 0.05
const STRIDE = 3

export interface HeatColumn {
  t: number
  /** 这一列代表多长（实时 1 秒，回填是服务端的 bucketMs） */
  dur: number
  /** 第一个细桶号 */
  lo: number
  n: number
  /** n × 3：币安 / OKX / Coinbase 的买卖合计美元名义；回填没有分家，全记在第 0 通道 */
  data: Float32Array
  split: boolean
}

export class HeatStore {
  live: HeatColumn[] = []
  back: HeatColumn[] = []
  version = 0
  /** 回填并进来一次加一（已经算好的「定稿列」要重算） */
  backVersion = 0
  /** 回填里最长的一列（服务端放粗后可到 60 分钟），往前找跨进窗口的列时用 */
  private maxBackDur = 5000
  constructor(readonly step: number) {}

  get liveStart(): number { return this.live.length ? this.live[0].t : Infinity }

  /** 取一列实时（fine 的步长必须和 store 一致）。 */
  sample(fine: FineBook, thresholds: Thresholds, nowMs: number): boolean {
    if (fine.step !== this.step || fine.mid == null) return false
    const mid = fine.mid
    const lo = bucketIndex(mid * (1 - HEAT_RADIUS), this.step), hi = bucketIndex(mid * (1 + HEAT_RADIUS), this.step)
    const n = hi - lo + 1
    if (n <= 0 || n > 20_000) return false
    const data = new Float32Array(n * STRIDE)
    const ch = fine.venues.map(v => EXCHANGE_CH[v.exchange] ?? 0)
    const min = fine.venues.map(v => (thresholds[v.product] ?? 0) * HEAT_MIN_FRACTION)
    let any = false
    for (const side of [fine.bid, fine.ask]) {
      for (const [idx, c] of side) {
        if (idx < lo || idx > hi) continue
        const base = (idx - lo) * STRIDE
        for (let i = 0; i < c.byVenue.length; i++) {
          const v = c.byVenue[i]
          if (v > 0 && v >= min[i]) { data[base + ch[i]] += v; any = true }
        }
      }
    }
    if (!any) return false
    const t = Math.floor(nowMs / 1000) * 1000
    const last = this.live[this.live.length - 1]
    if (last && last.t === t) this.live[this.live.length - 1] = { t, dur: 1000, lo, n, data, split: true }
    else this.live.push({ t, dur: 1000, lo, n, data, split: true })
    if (this.live.length > HEAT_LIVE_CAP) this.live.splice(0, this.live.length - HEAT_LIVE_CAP)
    this.version++
    return true
  }

  /** 并入一页回填（已换成图上价格）；同一时刻以后到的为准。 */
  addBackfill(cols: HeatColumn[]): void {
    if (!cols.length) return
    for (const c of cols) if (c.dur > this.maxBackDur) this.maxBackDur = c.dur
    const byT = new Map<number, HeatColumn>()
    for (const c of this.back) byT.set(c.t, c)
    for (const c of cols) byT.set(c.t, c)
    this.back = [...byT.values()].sort((a, b) => a.t - b.t)
    if (this.back.length > HEAT_BACK_CAP) this.back.splice(0, this.back.length - HEAT_BACK_CAP)
    this.version++; this.backVersion++
  }

  /** 周期换了：回填按新的粒度重取，旧的丢掉（免得粗细两种列混着平均）。 */
  clearBack(): void {
    if (!this.back.length) return
    this.back = []; this.maxBackDur = 5000
    this.version++; this.backVersion++
  }

  get backRange(): [number, number] | null {
    return this.back.length ? [this.back[0].t, this.back[this.back.length - 1].t + this.back[this.back.length - 1].dur] : null
  }

  /** 按时间顺序走一遍 [from, to) 里的列（实时开始之前用回填）。 */
  forEach(from: number, to: number, body: (c: HeatColumn) => void): void {
    const ls = this.liveStart
    if (from < ls) {
      const b = this.back
      let i = lowerBound(b, from - this.maxBackDur)
      for (; i < b.length && b[i].t < Math.min(to, ls); i++) if (b[i].t + b[i].dur > from) body(b[i])
    }
    const l = this.live
    for (let i = lowerBound(l, from); i < l.length && l[i].t < to; i++) body(l[i])
  }
}

function lowerBound(a: HeatColumn[], t: number): number {
  let lo = 0, hi = a.length
  while (lo < hi) { const m = (lo + hi) >> 1; if (a[m].t < t) lo = m + 1; else hi = m }
  return lo
}

/** 解服务端回填：`{"step","bucketMs","rows":[[t_ms,price,bid_usd,ask_usd]]}`，也认 `[{t,p,bid,ask}]`。价格乘 chartScale 换成图上的单位。 */
export function parseHeat(body: unknown, step: number, chartScale: number): HeatColumn[] | null {
  let rows: unknown[] | null = null
  let dur = 5000
  let src = 0
  if (Array.isArray(body)) rows = body
  else if (body && typeof body === 'object') {
    const b = body as Record<string, unknown>
    if (Array.isArray(b.rows)) rows = b.rows
    if (typeof b.bucketMs === 'number' && b.bucketMs > 0) dur = b.bucketMs
    if (typeof b.step === 'number' && b.step > 0) src = b.step * chartScale
  }
  if (!rows) return null
  // 服务端有自己的最小步长（BTC 是 100）：比图上的细桶粗时，一格的量均摊到它覆盖的那几个细桶
  // （这一格的挂单本来就只知道落在这段价里），免得细步长下画成一条一条的
  const span = src > step * 1.5 ? Math.min(1000, Math.round(src / step)) : 1
  const byT = new Map<number, Map<number, number>>()
  for (const r of rows) {
    let t: unknown, p: unknown, bid: unknown, ask: unknown
    if (Array.isArray(r)) [t, p, bid, ask] = r
    else if (r && typeof r === 'object') { const o = r as Record<string, unknown>; t = o.t; p = o.p ?? o.price; bid = o.bid; ask = o.ask }
    if (typeof t !== 'number' || typeof p !== 'number' || !(p > 0)) continue
    const v = (typeof bid === 'number' && bid > 0 ? bid : 0) + (typeof ask === 'number' && ask > 0 ? ask : 0)
    if (!(v > 0)) continue
    // 服务端按它的步长向下取整给出每格的下沿，加半格再落桶，免得浮点把下沿落到上一格
    const idx = bucketIndex(p * chartScale + step * 1e-6, step)
    let m = byT.get(t)
    if (!m) { m = new Map(); byT.set(t, m) }
    if (span === 1) m.set(idx, (m.get(idx) ?? 0) + v)
    else for (let j = 0; j < span; j++) m.set(idx + j, (m.get(idx + j) ?? 0) + v / span)
  }
  const out: HeatColumn[] = []
  for (const [t, m] of byT) {
    let lo = Infinity, hi = -Infinity
    for (const i of m.keys()) { if (i < lo) lo = i; if (i > hi) hi = i }
    const n = hi - lo + 1
    if (!(n > 0) || n > 50_000) continue
    const data = new Float32Array(n * STRIDE)
    for (const [i, v] of m) data[(i - lo) * STRIDE] = v
    out.push({ t, dur, lo, n, data, split: false })
  }
  out.sort((a, b) => a.t - b.t)
  return out
}

/** 第 q 百分位（线性插值；空数组给 0）。样本多时抽样，免得每帧排序十几万个数。 */
export function percentile(values: ArrayLike<number>, q: number, maxSamples = 20_000): number {
  const n = values.length
  if (!n) return 0
  let arr: number[]
  if (n <= maxSamples) arr = Array.from(values)
  else {
    arr = new Array(maxSamples)
    const stride = n / maxSamples
    for (let i = 0; i < maxSamples; i++) arr[i] = values[Math.floor(i * stride)]
  }
  arr.sort((a, b) => a - b)
  const pos = Math.min(1, Math.max(0, q)) * (arr.length - 1)
  const i = Math.floor(pos), f = pos - i
  return i + 1 < arr.length ? arr[i] * (1 - f) + arr[i + 1] * f : arr[i]
}

// ------------------------------------------------------------------ 画面网格

export interface HeatGrid {
  cols: number
  rows: number
  /** 列边界（时间，cols + 1 个） */
  edges: number[]
  rowLo: number
  k: number
  step: number
  /** cols × rows 的平均值（没有样本的格子是 0） */
  values: Float32Array
  /** cols × rows × 3 分家（回填格子全在第 0 通道，splitKnown 标 0） */
  parts: Float32Array
  splitKnown: Uint8Array
  p95: number
}

/** 画面上的一列：[t0, t1) 里所有样本按行（k 个细桶一行）取平均。 */
export interface HeatCol {
  t0: number; t1: number
  /** 第一行的行号 */
  lo: number
  n: number
  vals: Float32Array
  /** n × 3 分家 */
  parts: Float32Array
  /** 这一列里有实时样本（分得出三家） */
  split: boolean
  samples: number
  builtAt: number
  backV: number
}

/** 列的缓存：拖图、缩放时只有新露出来的列和还在长的最后几列要算。 */
export class HeatCache {
  private key = ''
  private cols = new Map<number, HeatCol>()
  private used = new Set<number>()

  /** 行倍数、步长或分列方式变了就整个作废。 */
  reset(key: string): void { if (key !== this.key) { this.key = key; this.cols.clear() } }

  column(store: HeatStore, t0: number, t1: number, k: number, now: number): HeatCol {
    this.used.add(t0)
    const c = this.cols.get(t0)
    if (c && c.t1 === t1 && c.backV === store.backVersion && c.t1 <= c.builtAt - 1500) return c
    const col = aggregateColumn(store, t0, t1, k, now)
    this.cols.set(t0, col)
    return col
  }

  /** 一帧画完：太多了就把这一帧没用到的丢掉。 */
  sweep(): void {
    if (this.cols.size > 6000) for (const t of [...this.cols.keys()]) if (!this.used.has(t)) this.cols.delete(t)
    this.used.clear()
  }
}

export function aggregateColumn(store: HeatStore, t0: number, t1: number, k: number, now: number): HeatCol {
  let lo = Infinity, hi = -Infinity, samples = 0, split = false
  const hit: HeatColumn[] = []
  store.forEach(t0, t1, col => {
    if (col.t < t0 && col.t + col.dur <= t0) return
    hit.push(col); samples++
    if (col.split) split = true
    const a = rowOf(col.lo, k), b = rowOf(col.lo + col.n - 1, k)
    if (a < lo) lo = a
    if (b > hi) hi = b
  })
  const n = samples ? hi - lo + 1 : 0
  const vals = new Float32Array(n), parts = new Float32Array(n * STRIDE)
  for (const col of hit) {
    const d = col.data
    for (let i = 0; i < col.n; i++) {
      const b = i * STRIDE
      const v = d[b] + d[b + 1] + d[b + 2]
      if (!(v > 0)) continue
      const r = rowOf(col.lo + i, k) - lo
      vals[r] += v
      parts[r * STRIDE] += d[b]; parts[r * STRIDE + 1] += d[b + 1]; parts[r * STRIDE + 2] += d[b + 2]
    }
  }
  if (samples > 1) {
    for (let r = 0; r < n; r++) vals[r] /= samples
    for (let r = 0; r < n * STRIDE; r++) parts[r] /= samples
  }
  return { t0, t1, lo: samples ? lo : 0, n, vals, parts, split, samples, builtAt: now, backV: store.backVersion }
}

/** 按列边界与行范围把 store 里的列聚成画面网格（每格取样本平均）。 */
export function buildGrid(store: HeatStore, edges: number[], rowLo: number, rowHi: number, k: number, now = Date.now()): HeatGrid | null {
  const cols = edges.length - 1, rows = rowHi - rowLo + 1
  if (cols <= 0 || rows <= 0 || cols * rows > 4_000_000) return null
  const values = new Float32Array(cols * rows)
  const parts = new Float32Array(cols * rows * STRIDE)
  const splitKnown = new Uint8Array(cols)
  const nz: number[] = []
  for (let ci = 0; ci < cols; ci++) {
    const col = aggregateColumn(store, edges[ci], edges[ci + 1], k, now)
    if (col.split) splitKnown[ci] = 1
    for (let i = 0; i < col.n; i++) {
      const r = col.lo + i - rowLo
      if (r < 0 || r >= rows || !(col.vals[i] > 0)) continue
      const cell = ci * rows + r
      values[cell] = col.vals[i]
      for (let q = 0; q < STRIDE; q++) parts[cell * STRIDE + q] = col.parts[i * STRIDE + q]
      nz.push(col.vals[i])
    }
  }
  return { cols, rows, edges, rowLo, k, step: store.step, values, parts, splitKnown, p95: percentile(nz, 0.95) }
}

/** 列边界：K 线周期 > 1 分钟时一根一列；1 分钟图按秒成列，一列至少 minPx 宽（几秒并一列）。 */
export function heatEdges(ivMs: number, from: number, to: number, pxPerMs: number, minPx = 2): number[] {
  if (!(to > from)) return []
  let w: number
  if (ivMs > 60_000) w = ivMs
  else {
    const g = Math.max(1, Math.ceil(minPx / Math.max(1e-9, pxPerMs * 1000)))
    w = [1, 2, 3, 5, 10, 15, 20, 30, 60].find(x => x >= g) ?? 60
    w *= 1000
  }
  const start = Math.floor(from / w) * w
  const edges: number[] = []
  for (let t = start; t <= to + w && edges.length < 20_000; t += w) edges.push(t)
  return edges
}
