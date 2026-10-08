/* Hkline Web · 主力订单流 · 梯子「变化」模式（OpenMarket 通读 P1-5）
 *
 * 变化 = 这一行「现在」的挂单名义 − 窗口开始时的挂单名义，买、卖两侧分开算；窗口只有「1 小时 / 1 天」两档。
 *   · 现在：各家合并的细桶簿，按服务端同一口径过滤（每本簿不到它产品门槛 5% 的桶不计）。
 *   · 窗口开始：服务端深度快照（/v1/market/orderflow/heat，按梯子看得到的价格收窄、1 小时档 1 分钟一格、
 *     1 天档 30 分钟一格）与本页实时环（每 30 秒 / 每 5 分钟取一列）里，取最早一列落在窗口里的；
 *     服务端没跟的品种只有实时环，就从打开这页算起，脚注写实际起点。不造数据、不做真假判定。
 * 点一行：卡片里画这一价位在窗口里的一根小折线（买、卖两根）。
 */
import type { FineBook } from './aggregate'
import type { Thresholds } from './types'
import { bucketIndex } from './bucket'
import { HEAT_MIN_FRACTION } from './heat'
import { heatFetch, scopedHeatUrl, parseHeatSplit, colRows, type SplitCol } from './heatFetch'
import { ago, before } from '../util/clock'

export type DeltaWin = '1h' | '1d'
export const WIN_MS: Record<DeltaWin, number> = { '1h': 3_600_000, '1d': 86_400_000 }
/** 各档向服务端要的时间格、以及多久往前挪一次（to 对齐的粒度） */
const WIN_BUCKET: Record<DeltaWin, number> = { '1h': 60_000, '1d': 1_800_000 }
const WIN_ALIGN: Record<DeltaWin, number> = { '1h': 60_000, '1d': 300_000 }
/** 实时环：细的 30 秒一列留 2 小时，粗的 5 分钟一列留 1 天 */
const RING_FINE_MS = 30_000, RING_FINE_CAP = 240
const RING_COARSE_MS = 300_000, RING_COARSE_CAP = 289
const RADIUS = 0.05
/** 一次向服务端要的价格格数上限（× 列数 ≈ 行数，服务端收窄额度 1.4 万行） */
const MAX_PRICES = 200
const RETRY_MS = 20_000

/** 细桶簿按服务端口径过滤后的一列快照（中间价 ±5%）。 */
export function snapFine(fine: FineBook, thresholds: Thresholds, t: number, dur: number, radius = RADIUS): SplitCol | null {
  if (fine.mid == null || !(fine.step > 0)) return null
  const lo = bucketIndex(fine.mid * (1 - radius), fine.step), hi = bucketIndex(fine.mid * (1 + radius), fine.step)
  const n = hi - lo + 1
  if (n <= 0 || n > 50_000) return null
  const bid = new Float32Array(n), ask = new Float32Array(n)
  const min = fine.venues.map(v => (thresholds[v.product] ?? 0) * HEAT_MIN_FRACTION)
  const put = (m: FineBook['bid'], out: Float32Array): void => {
    for (const [idx, c] of m) {
      if (idx < lo || idx > hi) continue
      let s = 0
      for (let i = 0; i < c.byVenue.length; i++) { const v = c.byVenue[i]; if (v > 0 && v >= min[i]) s += v }
      out[idx - lo] += s
    }
  }
  put(fine.bid, bid); put(fine.ask, ask)
  return { t, dur, step: fine.step, lo, n, bid, ask }
}

/** 最早一列覆盖到 start（或在它之后）的。 */
export function firstFrom(cols: SplitCol[], start: number): SplitCol | null {
  for (const c of cols) if (c.t + Math.max(c.dur, 1) > start) return c
  return null
}

export interface DeltaRow { row: number; bid0: number; ask0: number; bid: number; ask: number; dBid: number; dAsk: number }

/** 按行算变化：start 列（及它覆盖的价格范围）对 now 列。只算 start 覆盖到的行，其余不给（不知道就不画）。 */
export function deltaRows(start: SplitCol, startRange: [number, number] | null, now: SplitCol, rs: number, rowLo: number, rowHi: number): Map<number, DeltaRow> {
  let a = rowLo, z = rowHi
  if (startRange) { a = Math.max(a, Math.ceil(startRange[0] / rs)); z = Math.min(z, Math.floor(startRange[1] / rs) - 1) }
  const out = new Map<number, DeltaRow>()
  if (z < a) return out
  const s = colRows(start, rs, a, z), n = colRows(now, rs, a, z)
  for (const r of new Set([...s.keys(), ...n.keys()])) {
    const [b0, a0] = s.get(r) ?? [0, 0], [b1, a1] = n.get(r) ?? [0, 0]
    out.set(r, { row: r, bid0: b0, ask0: a0, bid: b1, ask: a1, dBid: b1 - b0, dAsk: a1 - a0 })
  }
  return out
}

/** 一行在一串列里的买卖序列（小折线用）。 */
export function rowSeries(cols: SplitCol[], row: number, rs: number): { t: number; bid: number; ask: number }[] {
  return cols.map(c => { const m = colRows(c, rs, row, row).get(row) ?? [0, 0]; return { t: c.t, bid: m[0], ask: m[1] } })
}

/** 两根折线的 SVG（宽 w、高 h）：买涨色、卖跌色，同一纵轴。 */
export function sparkSVG(pts: { t: number; bid: number; ask: number }[], w: number, h: number, up: string, down: string): string {
  if (pts.length < 2) return ''
  const t0 = pts[0].t, t1 = pts[pts.length - 1].t
  const max = Math.max(1, ...pts.map(p => Math.max(p.bid, p.ask)))
  const x = (t: number): number => (t1 > t0 ? (t - t0) / (t1 - t0) : 0) * (w - 2) + 1
  const y = (v: number): number => h - 2 - v / max * (h - 4)
  const line = (k: 'bid' | 'ask'): string => pts.map((p, i) => `${i ? 'L' : 'M'}${x(p.t).toFixed(1)},${y(p[k]).toFixed(1)}`).join('')
  return `<svg class="of-spark" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" aria-hidden="true">
    <path d="${line('bid')}" fill="none" stroke="${up}" stroke-width="1.5"/><path d="${line('ask')}" fill="none" stroke="${down}" stroke-width="1.5"/></svg>`
}

type Status = 'idle' | 'loading' | 'ok' | 'empty' | 'down'
interface Srv { win: DeltaWin; url: string; from: number; to: number; lo: number; hi: number; step: number; bucketMs: number; cols: SplitCol[] }

/** 一只品种的「变化」数据：实时环 + 服务端快照。换品种整个换一个。 */
export class DeltaSource {
  fine: SplitCol[] = []
  coarse: SplitCol[] = []
  /** 当前窗口那一份（诊断与梯子用）；两档各留一份，来回切不重拉 */
  srv: Srv | null = null
  private srvs: Partial<Record<DeltaWin, Srv>> = {}
  status: Status = 'idle'
  /** 服务端那一份到了（或失败了）时叫一声，让梯子马上重画、不等下一帧行情 */
  onUpdate: (() => void) | null = null
  /** 服务端存储步长（图上的单位）：梯子在变化模式下行不能比它细 */
  srvStep = 0
  version = 0
  private busy = false
  private retryAt = 0
  private gen = 0

  /** 每帧调：到点就往两个环里各记一列。 */
  sample(fine: FineBook, thresholds: Thresholds, now: number): void {
    const f = this.fine[this.fine.length - 1], c = this.coarse[this.coarse.length - 1]
    const needF = !f || f.step !== fine.step || ago(f.t, now) >= RING_FINE_MS
    const needC = !c || c.step !== fine.step || ago(c.t, now) >= RING_COARSE_MS
    if (!needF && !needC) return
    if (f && f.step !== fine.step) { this.fine = []; this.coarse = [] }
    const col = snapFine(fine, thresholds, now, RING_FINE_MS)
    if (!col) return
    if (needF) { this.fine.push(col); if (this.fine.length > RING_FINE_CAP) this.fine.shift() }
    if (needC) { this.coarse.push({ ...col, dur: RING_COARSE_MS }); if (this.coarse.length > RING_COARSE_CAP) this.coarse.shift() }
    this.version++
  }

  /** 实时环里窗口能用的那一串 */
  ring(win: DeltaWin): SplitCol[] { return win === '1h' ? this.fine : this.coarse }

  /**
   * 需要的话向服务端要（窗口 / 价格范围 / 时间往前挪了才要；同一 URL 缓存 + 去重）。
   * lo / hi 是梯子看得到的价格（图上的单位），会先夹到中间价 ±5% 再往外放两成。
   */
  ensure(win: DeltaWin, base: string, chartScale: number, fineStep: number, lo: number, hi: number, mid: number, now: number): void {
    const s = this.srvs[win] ?? null
    if (this.srv !== s) { this.srv = s; this.srvStep = s && s.cols.length ? s.step : 0; this.status = s ? (s.cols.length ? 'ok' : 'empty') : 'idle'; this.version++ }
    if (this.busy || before(this.retryAt, RETRY_MS, now) || !(fineStep > 0) || !(mid > 0)) return
    const a = Math.max(lo, mid * (1 - RADIUS)), z = Math.min(hi, mid * (1 + RADIUS))
    if (!(z > a)) return
    const align = WIN_ALIGN[win]
    const to = Math.ceil(now / align) * align
    // 够不够用按「±4.5%」判：夹在 ±5% 边上时中间价一动就差一点点，不为这一点点重拉
    const a2 = Math.max(lo, mid * (1 - RADIUS * 0.9)), z2 = Math.min(hi, mid * (1 + RADIUS * 0.9))
    const inside = !!s && s.win === win && a2 >= s.lo && z2 <= s.hi
    if (inside && s!.to >= to) return
    const m = (z - a) * 0.2
    const qLo = Math.max(mid * (1 - RADIUS), a - m), qHi = Math.min(mid * (1 + RADIUS), z + m)
    const step = fineStep * niceCeil((qHi - qLo) / MAX_PRICES / fineStep)
    const from = now - WIN_MS[win] - WIN_BUCKET[win]
    const url = scopedHeatUrl(base, from, to, step, qLo, qHi, WIN_BUCKET[win], chartScale, align)
    const gen = this.gen
    this.busy = true
    if (this.status === 'idle') this.status = 'loading'
    heatFetch(url, Math.min(align, 60_000)).then(r => {
      if (gen !== this.gen) return
      const h = r.status === 200 ? parseHeatSplit(r.body, chartScale, step) : null
      if (!h) { this.status = 'down'; this.retryAt = Date.now() + RETRY_MS; return }
      this.srvs[win] = { win, url, from, to, lo: qLo, hi: qHi, step: h.step, bucketMs: h.bucketMs, cols: h.cols }
      // 取的时候若已切到另一档，下一次 ensure 会把 srv 换成那一档的
      this.srv = this.srvs[win]!
      this.srvStep = h.cols.length ? h.step : 0
      this.status = h.cols.length ? 'ok' : 'empty'
      this.version++
    }, () => { if (gen === this.gen) { this.status = 'down'; this.retryAt = Date.now() + RETRY_MS } })
      .finally(() => { if (gen === this.gen) { this.busy = false; this.onUpdate?.() } })
  }

  /** 窗口开始那一列：服务端与实时环里更早的那个（服务端的带它收窄的价格范围）。 */
  start(win: DeltaWin, now: number): { col: SplitCol; range: [number, number] | null; from: 'server' | 'live' } | null {
    const t0 = now - WIN_MS[win]
    const sv = this.srvs[win]
    const s = sv ? firstFrom(sv.cols, t0) : null
    const l = firstFrom(this.ring(win), t0)
    if (s && sv && (!l || s.t <= l.t)) return { col: s, range: [sv.lo, sv.hi], from: 'server' }
    if (l) return { col: l, range: null, from: 'live' }
    return null
  }

  /** 小折线用的整串（服务端的列在前，实时环接在服务端最后一列之后）。 */
  series(win: DeltaWin, now: number): SplitCol[] {
    const t0 = now - WIN_MS[win]
    const srv = this.srvs[win]?.cols.filter(c => c.t + c.dur > t0) ?? []
    const last = srv.length ? srv[srv.length - 1].t + srv[srv.length - 1].dur : -Infinity
    return [...srv, ...this.ring(win).filter(c => c.t >= Math.max(t0, last))]
  }

  reset(): void { this.fine = []; this.coarse = []; this.srv = null; this.srvs = {}; this.status = 'idle'; this.srvStep = 0; this.busy = false; this.retryAt = 0; this.gen++; this.version++ }
}

/** 向上取到 1 / 2 / 5 × 10ⁿ（至少 1） */
export function niceCeil(x: number): number {
  if (!(x > 1)) return 1
  const e = Math.pow(10, Math.floor(Math.log10(x)))
  for (const f of [1, 2, 5, 10]) if (f * e >= x - 1e-9) return f * e
  return 10 * e
}
