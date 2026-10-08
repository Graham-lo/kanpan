/* Hkline Web · 主力订单流 · 爆仓（逐分钟合计：抽屉「大单列表」的第四块，也并进图上的大单与爆仓气泡）
 *
 * 为什么：用户 2026-10-08 要在抽屉里一眼看到「这根 / 近 1 小时 / 今天」多头、空头各被强平了多少。
 * 数据由 kanpan-api 常驻跟各家（注册表 LIQ_EX 顺序）的强平推送按分钟并好：
 *   GET /v1/market/orderflow/liq?base=SOL&from=<ms>&to=<ms>
 *   → { base, tracked, rows: [[分钟毫秒, 多头爆仓额, 空头爆仓额, 笔数, 最大一笔额, 最大一笔价, 最大一笔方向(0 多头被平 / 1 空头被平), 交易所(LIQ_EX 下标)]] }
 * 参考家的强平推送每秒只给一笔，金额是下限。
 *
 * 规则：
 *   · 走 feed.ts 的 getJSON（限流、线路都照它的）；抽屉开着或图上气泡开着才拉，30 秒补一次，失败 30 秒后再试。
 *   · 本机留 3 天，最多 16 只（最久没看的那只先丢）。第一次拉 3 天，之后从已有的最后一分钟往前 2 分钟起接着拉（分钟会补齐）。
 *   · 抽屉里单列一块（没有数据的品种写「这只品种暂无爆仓数据」）；图上按本图 K 线开盘时间把分钟行并成根（LiqBarCache），
 *     多爆算向下 D、空爆算向上 U，和大卖 / 大买合成一枚气泡（bigTags.ts）。现货（X-USD）与宏观品种（DXY）没有爆仓项，不拉。
 *     秒级周期不并（行是分钟粒度）。
 * 只聚合、展示，不做判定。
 */
import { getJSON } from './feed'
import { LIQ_EX } from '../venues'
import type { BarLiq, LiqBars } from './bigTags'

export { LIQ_EX }

/** [分钟, 多头额, 空头额, 笔数, 最大一笔额, 最大一笔价, 方向 0 多 / 1 空, 交易所（LIQ_EX 下标）] */
export type LiqRow = [number, number, number, number, number, number, number, number]
export interface LiqBody { base: string; tracked: boolean; rows: LiqRow[] }

export const LIQ_KEEP_MS = 3 * 86_400_000
export const LIQ_POLL_MS = 30_000
export const LIQ_MAX_SYMBOLS = 16

const num = (v: unknown): number | null => typeof v === 'number' && Number.isFinite(v) ? v : null

/** 「哪家」下标：认得的（0..LIQ_EX.length-1）原样，其余当 0 */
const liqEx = (v: number | null): number => (v != null && Number.isInteger(v) && v >= 0 && v < LIQ_EX.length ? v : 0)

/** 解析服务端的回包；格式不对返回 null，个别坏行跳过 */
export function parseLiq(body: unknown): LiqBody | null {
  if (!body || typeof body !== 'object') return null
  const b = body as { base?: unknown; tracked?: unknown; rows?: unknown }
  if (!Array.isArray(b.rows)) return null
  const rows: LiqRow[] = []
  for (const r of b.rows) {
    if (!Array.isArray(r) || r.length < 4) continue
    const v = r.map(num)
    const m = v[0], lo = v[1], sh = v[2], n = v[3]
    if (m == null || lo == null || sh == null || n == null) continue
    rows.push([m, Math.max(0, lo), Math.max(0, sh), Math.max(0, n), v[4] ?? 0, v[5] ?? 0, v[6] === 1 ? 1 : 0, liqEx(v[7])])
  }
  return { base: typeof b.base === 'string' ? b.base : '', tracked: b.tracked === true, rows }
}

export interface LiqSum { long: number; short: number; n: number; max: LiqRow | null }
/** [a, b) 的合计（行按分钟，落在区间里的整分钟都算）与这段里最大的一笔 */
export function sumLiq(rows: Iterable<LiqRow>, a: number, b: number): LiqSum {
  const s: LiqSum = { long: 0, short: 0, n: 0, max: null }
  for (const r of rows) {
    if (r[0] < a || r[0] >= b) continue
    s.long += r[1]; s.short += r[2]; s.n += r[3]
    if (r[4] > 0 && (!s.max || r[4] > s.max[4])) s.max = r
  }
  return s
}

interface Entry { rows: Map<number, LiqRow>; tracked: boolean | null; nextAt: number; busy: boolean; touched: number; ver: number }

export class LiqStore {
  private map = new Map<string, Entry>()
  /** 有新数据时叫（抽屉据此重画） */
  onUpdate: (() => void) | null = null
  /** 另外要听新数据的（各张图的气泡层），用完自己删 */
  readonly listeners = new Set<() => void>()
  constructor(private fetcher: (url: string) => Promise<{ status: number; body: unknown }> = url => getJSON(url, 8000)) {}

  private entry(base: string, now: number): Entry {
    let e = this.map.get(base)
    if (!e) {
      e = { rows: new Map(), tracked: null, nextAt: 0, busy: false, touched: now, ver: 0 }
      this.map.set(base, e)
      if (this.map.size > LIQ_MAX_SYMBOLS) {
        const old = [...this.map.entries()].filter(([k]) => k !== base).sort((x, y) => x[1].touched - y[1].touched)[0]
        if (old) this.map.delete(old[0])
      }
    }
    e.touched = now
    return e
  }

  /** 到点就拉一次（抽屉每次重画都可以叫，没到点什么也不做） */
  ensure(base: string, now = Date.now()): void {
    const e = this.entry(base, now)
    if (e.busy || now < e.nextAt) return
    void this.pull(base, e, now)
  }

  private async pull(base: string, e: Entry, now: number): Promise<void> {
    e.busy = true
    let last = -Infinity
    for (const k of e.rows.keys()) if (k > last) last = k
    const from = Math.max(now - LIQ_KEEP_MS, isFinite(last) ? last - 120_000 : -Infinity)
    const url = `/v1/market/orderflow/liq?base=${encodeURIComponent(base)}&from=${Math.floor(from)}&to=${Math.floor(now)}`
    try {
      const r = await this.fetcher(url)
      const body = r.status === 200 ? parseLiq(r.body) : null
      if (body) {
        e.tracked = body.tracked
        for (const row of body.rows) e.rows.set(row[0], row)
        const cut = now - LIQ_KEEP_MS
        for (const k of [...e.rows.keys()]) if (k < cut) e.rows.delete(k)
        e.ver++
        this.onUpdate?.()
        for (const fn of this.listeners) fn()
      }
    } catch { /* 30 秒后再试 */ }
    e.busy = false
    e.nextAt = now + LIQ_POLL_MS
  }

  /** null = 还没拉到过；tracked=false 且没有行 = 这只没数据 */
  state(base: string): { rows: Map<number, LiqRow>; tracked: boolean | null; ver: number } | null {
    const e = this.map.get(base)
    return e ? { rows: e.rows, tracked: e.tracked, ver: e.ver } : null
  }
  size(): number { return this.map.size }
}

/** 没有爆仓项的品种：Coinbase 现货（X-USD）与宏观品种（DXY） */
export const noLiq = (sym: string): boolean => /-USD$/.test(sym) || sym === 'DXY'

type LiqState = NonNullable<ReturnType<LiqStore['state']>>
/** 每张图一份：把分钟行按本图 K 线并成根（多爆 / 空爆）。数据版本、品种、周期不变就复用同一个 LiqBars，按根记住算过的 */
export class LiqBarCache {
  private key = ''
  private bars: LiqBars | null = null
  /** 并过几根（测试看缓存） */
  computed = 0
  of(st: LiqState | null, base: string, iv: number): LiqBars | null {
    if (!st || !(iv >= 60_000) || !st.rows.size) { this.key = ''; this.bars = null; return null }
    const key = `${base}|${iv}|${st.ver}|${st.rows.size}`
    if (key === this.key && this.bars) return this.bars
    let lo = Infinity, hi = -Infinity
    for (const k of st.rows.keys()) { if (k < lo) lo = k; if (k > hi) hi = k }
    const rows = st.rows, memo = new Map<number, { t1: number; v: BarLiq | null }>()
    const at = (t0: number, t1: number): BarLiq | null => {
      const e = memo.get(t0)
      if (e && e.t1 === t1) return e.v
      this.computed++
      let long = 0, short = 0, has = false
      const a = Math.max(Math.ceil(t0 / 60_000) * 60_000, lo), b = Math.min(t1 - 1, hi)
      for (let m = a; m <= b; m += 60_000) {
        const r = rows.get(m)
        if (r) { long += r[1]; short += r[2]; has = true }
      }
      const v = has && (long > 0 || short > 0) ? { long, short } : null
      memo.set(t0, { t1, v })
      return v
    }
    this.key = key
    this.bars = { key, at }
    return this.bars
  }
}
