/* Hkline Web · 电脑网页的「对比」：纯函数 + 共用的取数器
 *
 * 规矩照 iOS（KanpanData/Feed/CompareFeed.swift、ChartRenderer+Compare.swift）与手机网页（src/m/chart/compare.source.ts、
 * renderer.compare.ts），这里另写一份不 import m/（两套 UI 各管各的，只共用 sync/codec 的清洗）：
 *   · 偏好里一人一份 compareSymbols（最多三只，键是完整三段 venue/market/SYMBOL：binance/usd_m/<代号>、macro/index/DXY、okx/usd_m/…）；
 *     每格按自己的主图挑：去掉主图那只、认不出的键（注册表里没有的交易所）留在偏好里但不取不画
 *   · 按主图的 openTime 一根一根对齐，缺根是 null，绝不拿邻根补；主图相邻两根之间缺了一截（美元指数的周末）也断线
 *   · 百分比：可见区第一根的开盘价是 0%；每条对比线的基准是从那一根起它自己第一根有开盘价的
 *   · 取数：先最新一页，再向左补到用到它的各格主图起点（一轮最多 8 页）；推送接末根；断档重拉末页；
 *     取不到按 2 s·2ⁿ 退避，最长 30 s。十六图里同一只对比品种同一周期只取一份（按「品种|周期」共用、按格子登记）
 */
import type { Bar } from './calc'
import { MAX_COMPARE, validSymbol } from '../sync/codec'
import { displayKey, syncKeyOf } from '../market/identity'
import { symbolOk } from '../venues'

export { MAX_COMPARE }
/** 每只对比线的颜色：按它在偏好里的槽位取（换主图不换色）。
 *  色相避开默认均线四色（橙 / 蓝 / 紫 / 青）与涨跌绿红——叠在 MA 上要一眼分得开；深浅两套底上都看得清 */
export const COMPARE_COLORS = ['#DB2777', '#65A30D', '#64748B'] as const
/** 一轮向左补历史最多翻几页 */
export const COMPARE_MAX_PAGES = 8
const RETRY_BASE_MS = 2_000
const RETRY_MAX_MS = 30_000

/** 偏好里的键 → 取数用的品种键（网页里存的那个）。`binance/usd_m/ETHUSDT` → ETHUSDT，`macro/index/DXY` / `DXY` → DXY，
 *  别家 `okx/usd_m/BTCUSDT` → 原样（2026-10-08 起别家的品种也能对比）；不认识的交易所 / 市场、写坏的键回 null
 *  （不取、不画，但留在偏好里——新版本同步下来的键不能被老页面吃掉） */
export function compareSymbolOf(key: string): string | null {
  const parts = key.trim().split('/')
  if (parts.length === 1) { const u = parts[0].toUpperCase(); return u === 'DXY' ? 'DXY' : validSymbol(u) ? u : null }
  if (parts.length !== 3) return null
  const k = `${parts[0].toLowerCase()}/${parts[1].toLowerCase()}/${parts[2].toUpperCase()}`
  if (k === 'macro/index/DXY') return 'DXY'
  return symbolOk(k) ? displayKey(k) : null
}
/** 品种键 → 偏好里的键（完整三段） */
export function compareKeyOf(symbol: string): string {
  return syncKeyOf(symbol.includes('/') ? symbol : symbol.toUpperCase())
}

export interface CompareTarget { key: string; symbol: string; slot: number }
/** 这一格真要画的几只：认得出、去重、去掉主图那只、最多三只；slot 是在偏好里的位置（定颜色） */
export function compareTargets(keys: readonly string[], mainSymbol: string): CompareTarget[] {
  const out: CompareTarget[] = []
  const main = mainSymbol.toUpperCase()
  keys.forEach((key, slot) => {
    if (out.length >= MAX_COMPARE) return
    const symbol = compareSymbolOf(key)
    if (!symbol || symbol === main || out.some(x => x.symbol === symbol)) return
    out.push({ key, symbol, slot })
  })
  return out
}

export interface Aligned { open: (number | null)[]; close: (number | null)[] }
/** 按主图 openTime 对齐：缺根 null、非法价 null。两边都按时间升序 */
export function alignCompare(main: readonly Bar[], cmp: readonly Bar[] | null): Aligned {
  const n = main.length
  const open = new Array<number | null>(n).fill(null), close = new Array<number | null>(n).fill(null)
  if (!cmp || !cmp.length || !n) return { open, close }
  let lo = 0, hi = cmp.length
  while (lo < hi) { const m = (lo + hi) >> 1; if (cmp[m].t < main[0].t) lo = m + 1; else hi = m }
  let j = lo
  for (let i = 0; i < n; i++) {
    const t = main[i].t
    while (j < cmp.length && cmp[j].t < t) j++
    if (j >= cmp.length) break
    if (cmp[j].t === t) {
      const o = cmp[j].o, c = cmp[j].c
      open[i] = Number.isFinite(o) && o > 0 ? o : null
      close[i] = Number.isFinite(c) && c > 0 ? c : null
    }
  }
  return { open, close }
}

/** 一条对比线的基准根：从主图基准根起（含）到 hi，第一根有开盘价的；一根都没有回 null（整条不画） */
export function compareBaseIndexFrom(open: readonly (number | null)[], mainBase: number, hi: number): number | null {
  for (let i = Math.max(0, mainBase); i <= hi && i < open.length; i++) if (open[i] != null) return i
  return null
}
/** 第 i 根相对基准根开盘价的涨跌（%）；缺根 null */
export function comparePercentAt(a: Aligned, i: number, base: number): number | null {
  const c = a.close[i], o = a.open[base]
  if (c == null || o == null || !(o > 0)) return null
  return (c / o - 1) * 100
}
/** 图例与轴上标签：+1.23% / −0.50% / 0% / —（没值） */
export function comparePercentLabel(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return '—'
  if (Math.abs(v) < 0.005) return '0%'
  return `${v > 0 ? '+' : '−'}${Math.abs(v).toFixed(2)}%`
}
/** 价格 → 相对基准的百分比 */
export const pctOf = (price: number, base: number): number => (price / base - 1) * 100
/** 百分比 → 价格（对比线画在主图的价格空间里，主图本身不动） */
export const priceOfPct = (pct: number, base: number): number => base * (1 + pct / 100)

/** 百分比轴的刻度（返回价格）：按百分比取整步长，0% 一定在（在区间里时），一列最多 64 个 */
export function percentTicks(min: number, max: number, base: number, n: number, nice: (v: number) => number): { prices: number[]; step: number } {
  if (!(base > 0) || !(max > min)) return { prices: [], step: 0 }
  const a = pctOf(min, base), b = pctOf(max, base)
  const step = nice((b - a) / Math.max(1, n))
  if (!(step > 0) || !Number.isFinite(step)) return { prices: [], step: 0 }
  const out: number[] = []
  for (let k = Math.ceil(a / step); k <= Math.floor(b / step) && out.length < 64; k++) out.push(priceOfPct(k * step, base))
  return { prices: out, step }
}
/** 轴上刻度的百分比文字：小数位跟步长走（步长 0.5 → 一位），0 写「0%」 */
export function percentTickLabel(price: number, base: number, step: number): string {
  const v = pctOf(price, base)
  const dec = Math.max(0, Math.min(2, -Math.floor(Math.log10(step || 1) + 1e-9)))
  const s = Math.abs(v).toFixed(dec)
  if (+s === 0) return '0%'
  return `${v > 0 ? '+' : '−'}${s}%`
}

/** 一条对比线在可见段上断成的几段：[下标, 百分比][]。
 *  缺根断开；主图相邻两根之间隔了超过 1.5 个周期（美元指数的周末、停牌）也断开，不拿直线连过去 */
export function compareSegments(timeOf: (i: number) => number, ivMs: number, from: number, to: number, pctAt: (i: number) => number | null): [number, number][][] {
  const segs: [number, number][][] = []
  let cur: [number, number][] = [], prevT: number | null = null
  for (let i = from; i <= to; i++) {
    const v = pctAt(i)
    if (v == null) { if (cur.length) segs.push(cur); cur = []; prevT = null; continue }
    const t = timeOf(i)
    if (prevT != null && t - prevT > ivMs * 1.5 && cur.length) { segs.push(cur); cur = [] }
    cur.push([i, v]); prevT = t
  }
  if (cur.length) segs.push(cur)
  return segs
}

/** 图上要画的一条对比线（页面给 TVChart 的） */
export interface CompareLine {
  key: string
  name: string
  color: string
  bars: readonly Bar[] | null
  /** 数据戳：取数器每变一次 +1（图上的对齐缓存按它判断要不要重算） */
  rev: number
  /** 第一次取、手里还没有数据：图例那一行挂一个小转圈（往前补历史时线已经在了，不挂） */
  loading?: boolean
}

// ------------------------------------------------------------ 取数器
export type CompareLoad = (symbol: string, iv: string, endTime: number | null) => Promise<Bar[] | null>
export interface CompareNeed { symbol: string; iv: string; /** 这一格主图的第一根时间：对比往左补到这里 */ from: number }
interface Timers { set: (fn: () => void, ms: number) => unknown; clear: (h: unknown) => void }

interface Entry {
  symbol: string
  iv: string
  bars: Bar[] | null
  /** 哪几格在用、各要补到哪儿 */
  need: Map<number, number>
  historyDone: boolean
  loading: boolean
  /** 取的时候推送又动了末根：合并最新一页时不拿 REST 的旧末根盖掉 */
  liveRev: number
  failures: number
  retry: unknown
  /** 不要了（最后一格撤掉）：在路上的取数回来不再写 */
  gen: number
  /** 数据变了就 +1（对齐缓存按它判断要不要重算） */
  rev: number
}
const keyOf = (symbol: string, iv: string) => `${symbol}|${iv}`

export class CompareStore {
  private map = new Map<string, Entry>()
  private gen = 0
  constructor(
    private readonly load: CompareLoad,
    private readonly onChange: (symbol: string, iv: string) => void,
    private readonly stepOf: (iv: string) => number,
    private readonly timers: Timers = { set: (fn, ms) => setTimeout(fn, ms), clear: h => clearTimeout(h as ReturnType<typeof setTimeout>) },
  ) {}

  /** 某一格此刻要的对比（整份替换）。不再有格子要的那只撤掉、在路上的作废 */
  want(owner: number, list: readonly CompareNeed[]): void {
    const keep = new Set<string>()
    for (const n of list) {
      const k = keyOf(n.symbol, n.iv)
      keep.add(k)
      let e = this.map.get(k)
      if (!e) {
        e = { symbol: n.symbol, iv: n.iv, bars: null, need: new Map(), historyDone: false, loading: false, liveRev: 0, failures: 0, retry: null, gen: ++this.gen, rev: 0 }
        this.map.set(k, e)
      }
      e.need.set(owner, n.from)
    }
    for (const [k, e] of this.map) {
      if (keep.has(k) || !e.need.has(owner)) continue
      e.need.delete(owner)
      if (!e.need.size) this.drop(k, e)
    }
    for (const n of list) { const e = this.map.get(keyOf(n.symbol, n.iv)); if (e) this.schedule(e) }
  }
  get(symbol: string, iv: string): { bars: Bar[] | null; rev: number; loading: boolean } | null {
    const e = this.map.get(keyOf(symbol, iv))
    return e ? { bars: e.bars, rev: e.rev, loading: e.loading } : null
  }
  /** 此刻在取的「品种 + 周期」（订推送用） */
  streams(): { symbol: string; iv: string }[] { return [...this.map.values()].map(e => ({ symbol: e.symbol, iv: e.iv })) }

  /** 推送来一根（已经换算成这个周期的）。返回是否接住 */
  upsert(symbol: string, iv: string, bar: Bar): boolean {
    const e = this.map.get(keyOf(symbol, iv))
    if (!e || !e.bars) return false
    if (!(Number.isFinite(bar.c) && bar.c > 0)) return false
    const b = e.bars, n = b.length, last = n ? b[n - 1] : null
    const step = this.stepOf(iv)
    // 断了一截（推送落后、隔了个周末）：等补末页，不拿一根孤零零的新根把中间的空白连起来
    if (last && bar.t > last.t && step > 0 && bar.t - last.t > step && iv !== '1M') { this.refreshTail(e); return true }
    if (!last || bar.t > last.t) b.push({ ...bar })
    else if (bar.t === last.t) Object.assign(last, bar)
    else return true
    e.liveRev++; e.rev++
    this.onChange(e.symbol, e.iv)
    return true
  }
  /** 断线重连 / 从后台回来：每只重拉末页补缺口 */
  resync(): void { for (const e of this.map.values()) this.refreshTail(e) }
  dispose(): void { for (const [k, e] of this.map) this.drop(k, e) }

  private drop(k: string, e: Entry): void {
    if (e.retry) { this.timers.clear(e.retry); e.retry = null }
    e.gen = -1
    this.map.delete(k)
  }
  private needFrom(e: Entry): number { let m = Infinity; for (const v of e.need.values()) m = Math.min(m, v); return m }
  private schedule(e: Entry): void {
    if (e.loading || e.retry || e.gen < 0) return
    if (!e.bars) { void this.run(e, null); return }
    if (e.bars.length && !e.historyDone && e.bars[0].t > this.needFrom(e)) void this.run(e, e.bars[0].t)
  }
  private refreshTail(e: Entry): void {
    if (e.loading || e.retry || e.gen < 0) return
    void this.run(e, null)
  }
  private async run(e: Entry, endTime: number | null): Promise<void> {
    const gen = e.gen
    e.loading = true
    let ok = true
    try {
      if (endTime == null) {
        const rev = e.liveRev
        const bars = await this.load(e.symbol, e.iv, null)
        if (gen !== e.gen) return
        if (!bars) { ok = false; return }
        this.mergeLatest(e, bars, rev !== e.liveRev)
        e.rev++; this.onChange(e.symbol, e.iv)
      } else {
        let end = endTime
        for (let page = 0; page < COMPARE_MAX_PAGES; page++) {
          const b = e.bars
          if (!b || !b.length || b[0].t <= this.needFrom(e)) break
          const more = await this.load(e.symbol, e.iv, end)
          if (gen !== e.gen) return
          if (!more) { ok = false; return }
          const first = e.bars![0].t
          const older = more.filter(x => x.t < first && Number.isFinite(x.c) && x.c > 0)
          if (!older.length) { e.historyDone = true; break }
          e.bars = older.concat(e.bars!)
          e.rev++; this.onChange(e.symbol, e.iv)
          end = e.bars[0].t
        }
      }
    } finally {
      if (gen === e.gen) {
        e.loading = false
        if (ok) { e.failures = 0; this.schedule(e) } else this.backoff(e)
        this.onChange(e.symbol, e.iv)   // 图例上的小转圈收起（成功那次的 onChange 发在 loading 还是 true 的时候）
      }
    }
  }
  private mergeLatest(e: Entry, bars: Bar[], keepLive: boolean): void {
    const valid = bars.filter(b => Number.isFinite(b.t) && Number.isFinite(b.c) && b.c > 0).map(b => ({ ...b }))
    const s = e.bars
    if (!valid.length) { if (!s) e.bars = []; return }
    const live = keepLive && s && s.length ? s[s.length - 1] : null
    const first = valid[0].t, step = this.stepOf(e.iv)
    const gap = s && s.length && first > s[s.length - 1].t + (e.iv === '1M' ? 32 * 864e5 : step)
    if (!s || !s.length || gap || first <= s[0].t) {
      // 首取、离开太久接不上（中间那段不拿直线连）、或这一页已经盖住手上的全部：整条换，更早的下一轮再往左补
      e.bars = valid; e.historyDone = false
    } else {
      let k = s.length
      while (k > 0 && s[k - 1].t >= first) k--
      e.bars = s.slice(0, k).concat(valid)
    }
    const out = e.bars
    if (live && out.length && live.t >= out[out.length - 1].t) {
      if (live.t === out[out.length - 1].t) out[out.length - 1] = live; else out.push(live)
    }
  }
  private backoff(e: Entry): void {
    const wait = Math.min(RETRY_MAX_MS, RETRY_BASE_MS * 2 ** e.failures)
    e.failures = Math.min(e.failures + 1, 10)
    const gen = e.gen
    e.retry = this.timers.set(() => {
      e.retry = null
      if (gen !== e.gen) return
      this.schedule(e)
    }, wait)
  }
}
