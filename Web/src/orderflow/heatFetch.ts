/* Hkline Web · 主力订单流 · 热力接口的收窄请求、缓存去重与「买卖分开」的解析（2026-09-29 订单流吸收）
 *
 * 梯子的「变化」模式、侧栏「24 小时流动性」都要服务端的深度快照，但只要其中一小块：
 *   · 价格一律带 lo / hi（每个币的单位）、时间格一律带 bucketMs 提示，绝不拉 24 小时全量；
 *   · 同一个 URL 在有效期内只发一次（进行中的也共用同一个 Promise），失败的不缓存；
 *   · getJSON 走 no-store，所以缓存只能在这里做。
 * 解析保留买、卖两侧（parseHeat 是给热力图的，买卖合在一起），价格按服务端的步长落格，不往细桶里摊——
 * 变化量要的是真值，摊开就成了造出来的数。
 */
import { getJSON } from './feed'
import { bucketIndex } from './bucket'

export type Resp = { status: number; body: unknown }
interface Entry { at: number; ttl: number; p: Promise<Resp> }
const cache = new Map<string, Entry>()
let sent = 0

/** 带缓存与去重的 GET：ttl 以内同一个 URL 共用一次请求。 */
export function heatFetch(url: string, ttlMs: number, timeoutMs = 12_000): Promise<Resp> {
  const now = Date.now()
  const e = cache.get(url)
  if (e && now - e.at < e.ttl) return e.p
  sent++
  const p = getJSON(url, timeoutMs).then(r => { if (r.status !== 200) cache.delete(url); return r }, err => { cache.delete(url); throw err })
  cache.set(url, { at: now, ttl: ttlMs, p })
  if (cache.size > 64) for (const [k, v] of cache) if (now - v.at >= v.ttl) cache.delete(k)
  return p
}
/** 诊断：一共真发出去几次（回归脚本看去重有没有生效） */
export const heatFetchSent = (): number => sent

/** 收窄的热力 URL：价格用 lo / hi（每个币），时间对齐到 alignMs。 */
export function scopedHeatUrl(base: string, from: number, to: number, step: number, lo: number, hi: number, bucketMs: number, chartScale: number, alignMs = 5000): string {
  const s = chartScale || 1
  const q = [`base=${encodeURIComponent(base)}`, `from=${Math.floor(from / alignMs) * alignMs}`, `to=${Math.ceil(to / alignMs) * alignMs}`,
    `step=${+(step / s).toPrecision(10)}`, `lo=${+(lo / s).toPrecision(10)}`, `hi=${+(hi / s).toPrecision(10)}`, `bucketMs=${bucketMs}`]
  return `/v1/market/orderflow/heat?${q.join('&')}`
}

/** 买卖分开的一列：第 i 格价格是 [(lo + i) × step, (lo + i + 1) × step)（图上的单位）。 */
export interface SplitCol {
  t: number
  /** 这一列代表多长（服务端的 bucketMs；实时快照是取样间隔） */
  dur: number
  step: number
  lo: number
  n: number
  bid: Float32Array
  ask: Float32Array
}
export interface SplitHeat { step: number; bucketMs: number; cols: SplitCol[] }

/** 解 `{"step","bucketMs","rows":[[t,price,bid,ask]]}`，价格乘 chartScale；步长以服务端返回的为准。 */
export function parseHeatSplit(body: unknown, chartScale: number, fallbackStep: number): SplitHeat | null {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null
  const b = body as Record<string, unknown>
  if (!Array.isArray(b.rows)) return null
  const bucketMs = typeof b.bucketMs === 'number' && b.bucketMs > 0 ? b.bucketMs : 5000
  const step = typeof b.step === 'number' && b.step > 0 ? b.step * chartScale : fallbackStep
  if (!(step > 0)) return null
  const byT = new Map<number, Map<number, [number, number]>>()
  for (const r of b.rows) {
    if (!Array.isArray(r)) continue
    const [t, p, bid, ask] = r as unknown[]
    if (typeof t !== 'number' || typeof p !== 'number' || !(p > 0)) continue
    const bv = typeof bid === 'number' && bid > 0 ? bid : 0, av = typeof ask === 'number' && ask > 0 ? ask : 0
    if (!(bv > 0 || av > 0)) continue
    // 服务端给的是格的下沿，加一点再落格，免得浮点落到下一格
    const idx = bucketIndex(p * chartScale + step * 1e-6, step)
    let m = byT.get(t)
    if (!m) { m = new Map(); byT.set(t, m) }
    const e = m.get(idx)
    if (e) { e[0] += bv; e[1] += av } else m.set(idx, [bv, av])
  }
  const cols: SplitCol[] = []
  for (const [t, m] of byT) {
    let lo = Infinity, hi = -Infinity
    for (const i of m.keys()) { if (i < lo) lo = i; if (i > hi) hi = i }
    const n = hi - lo + 1
    if (!(n > 0) || n > 100_000) continue
    const bidA = new Float32Array(n), askA = new Float32Array(n)
    for (const [i, [bv, av]] of m) { bidA[i - lo] = bv; askA[i - lo] = av }
    cols.push({ t, dur: bucketMs, step, lo, n, bid: bidA, ask: askA })
  }
  cols.sort((a, b2) => a.t - b2.t)
  return { step, bucketMs, cols }
}

/** 一列在 [pLo, pHi] 价格里的买、卖合计（按格的中点算落没落在里面）。 */
export function colSum(c: SplitCol, pLo: number, pHi: number): [number, number] {
  let bid = 0, ask = 0
  const a = Math.max(0, Math.ceil(pLo / c.step - 0.5) - c.lo), z = Math.min(c.n - 1, Math.floor(pHi / c.step - 0.5) - c.lo)
  for (let i = a; i <= z; i++) { bid += c.bid[i]; ask += c.ask[i] }
  return [bid, ask]
}

/** 一列按行（rs 一行，行号 floor(价格 / rs)）并起来，只要 [rowLo, rowHi]。 */
export function colRows(c: SplitCol, rs: number, rowLo: number, rowHi: number): Map<number, [number, number]> {
  const out = new Map<number, [number, number]>()
  for (let i = 0; i < c.n; i++) {
    const b = c.bid[i], a = c.ask[i]
    if (!(b > 0 || a > 0)) continue
    const r = Math.floor((c.lo + i + 0.5) * c.step / rs)
    if (r < rowLo || r > rowHi) continue
    const e = out.get(r)
    if (e) { e[0] += b; e[1] += a } else out.set(r, [b, a])
  }
  return out
}
