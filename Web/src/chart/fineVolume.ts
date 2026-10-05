/* Hkline Web · 成交量分布的细 K 线（4 小时及以上周期）
 *
 * 粗周期下一根 K 线的高低区间很宽，按「均匀摊到高低之间」算出来的分布和实际成交的价位差得远。
 * 4 小时到 1 天以下的周期向币安要可见这段的 15 分钟 K 线、1 天及以上要 1 小时 K 线（最多 5000 根，从右往左取），
 * 一根收完的粗 K 线整个被细 K 线盖住时，改用这些细 K 线各自的高低与主动买入去摊；没盖住的（更早的、正在走的那根）照旧均匀摊。
 * 控制点与七成价值区的算法不变。
 *
 * 缓存：按（品种，细周期）留一段连续的细 K 线，最多 16 份（一屏最多十六格）；可见范围没被盖住才去要，防抖、同一时刻只有一个请求，
 * 要回来置脏重画——画的那一帧从不等它。要失败了 30 秒内不再试（这段时间照旧均匀摊）。
 */
import type { Bar } from './calc'
import { klines } from '../market/rest'
import { ago } from '../util/clock'

export const FINE_CAP = 5000
const PAGE = 1500
const DEBOUNCE_MS = 250
const RETRY_MS = 30_000
// 要装得下一屏全部格子（最多十六图，每份最多 5000 根细 K 线、约 0.5 MB）：原来是 4，五格以上各开一只 4 小时成交量分布时
// 每重画一格就挤掉别格的，挤掉的那格重画又整段重要，停不下来（2026-09-29 A 路压测）
const KEEP = 16

interface Fine { bars: Bar[]; from: number; to: number; busy: boolean; failedAt: number; timer: ReturnType<typeof setTimeout> | null; want: [number, number] | null }
const cache = new Map<string, Fine>()

/** 这个周期用什么细周期（毫秒与币安周期名）；4 小时以下不用 */
export function fineOf(iv: number): { ms: number; name: string } | null {
  if (iv >= 864e5) return { ms: 36e5, name: '1h' }
  if (iv >= 4 * 36e5) return { ms: 15 * 60e3, name: '15m' }
  return null
}

/** 细 K 线里落在 [a, b) 的那一段（二分） */
function slice(bars: Bar[], a: number, b: number): Bar[] {
  let lo = 0, hi = bars.length
  while (lo < hi) { const m = (lo + hi) >> 1; if (bars[m].t < a) lo = m + 1; else hi = m }
  const out: Bar[] = []
  for (let i = lo; i < bars.length && bars[i].t < b; i++) out.push(bars[i])
  return out
}

/**
 * 给成交量分布的拆分函数：第 i 根粗 K 线整个被细 K 线盖住（且已经收完）就回它的细 K 线，否则回 null（照旧均匀摊）。
 * 可见范围没盖住时在后台去要，要回来调 onReady（置脏重画）。
 */
export function fineSplit(symbol: string, iv: number, bars: Bar[], from: number, to: number, onReady: () => void, now = Date.now()): ((i: number) => Bar[] | null) | null {
  const f = fineOf(iv)
  if (!f || !symbol || !bars.length) return null
  from = Math.max(0, from); to = Math.min(bars.length - 1, to)
  if (to < from) return null
  const key = `${symbol}|${f.name}`
  let c = cache.get(key)
  // 要盖住的：可见这段里已经收完的那些粗 K 线；太长了只要最右边 5000 根细 K 线那么长
  let lastClosed = to
  while (lastClosed >= from && bars[lastClosed].t + iv > now) lastClosed--
  if (lastClosed >= from) {
    const t1 = bars[lastClosed].t + iv, t0 = Math.max(bars[from].t, t1 - FINE_CAP * f.ms)
    if (!c || c.from > t0 || c.to < t1) request(key, symbol, f, t0, t1, onReady)
    c = cache.get(key)
  }
  if (!c || !c.bars.length) return null
  const fine = c
  return i => {
    const b = bars[i]
    if (!b || b.t < fine.from || b.t + iv > fine.to || b.t + iv > now) return null
    const s = slice(fine.bars, b.t, b.t + iv)
    // 细 K 线要齐：数一数（交易所停机缺几根时宁可照旧均匀摊）
    return s.length >= Math.floor(iv / f.ms * 0.9) ? s : null
  }
}

function request(key: string, symbol: string, f: { ms: number; name: string }, t0: number, t1: number, onReady: () => void): void {
  let c = cache.get(key)
  if (!c) {
    c = { bars: [], from: Infinity, to: -Infinity, busy: false, failedAt: 0, timer: null, want: null }
    cache.set(key, c)
    while (cache.size > KEEP) { const k = cache.keys().next().value; if (k == null || k === key) break; cache.delete(k) }
  }
  c.want = [t0, t1]
  if (c.busy || c.timer || ago(c.failedAt) < RETRY_MS) return
  const entry = c
  entry.timer = setTimeout(() => { entry.timer = null; void load(entry, symbol, f, onReady) }, DEBOUNCE_MS)
}

async function load(c: Fine, symbol: string, f: { ms: number; name: string }, onReady: () => void): Promise<void> {
  if (!c.want) return
  const [t0, t1] = c.want
  c.busy = true
  try {
    // 和已有的一段接得上就只补缺的那头；接不上整段重要
    const joins = c.bars.length > 0 && t1 >= c.from && t0 <= c.to
    const got: Bar[] = []
    let end = joins && t1 <= c.to ? c.from : t1
    const stop = joins && t1 > c.to ? Math.max(t0, c.to) : t0
    // 取到了这只品种最早的 K 线（上市之前没有）：把盖住的起点记到要的起点，免得每一帧都再去要
    let exhausted = false
    for (let n = 0; n < Math.ceil(FINE_CAP / PAGE) + 1 && end > stop && got.length < FINE_CAP; n++) {
      const r = await klines(symbol, f.name, end, PAGE, false)
      if (!r.ok) { c.failedAt = Date.now(); return }
      const page = r.bars.filter(b => b.t < end)
      if (!page.length) { exhausted = true; break }
      got.unshift(...page)
      end = page[0].t
      if (page.length < PAGE - 1) { exhausted = true; break }
    }
    if (!got.length) { c.failedAt = Date.now(); return }
    const lo = exhausted ? Math.min(got[0].t, stop) : got[0].t, hi = got[got.length - 1].t + f.ms
    if (joins) {
      const m = new Map<number, Bar>()
      for (const b of c.bars) m.set(b.t, b)
      for (const b of got) m.set(b.t, b)
      c.bars = [...m.values()].sort((a, b) => a.t - b.t)
      c.from = Math.min(c.from, lo); c.to = Math.max(c.to, hi)
    } else { c.bars = got; c.from = lo; c.to = hi }
    // 超过 5000 根只留这次要的那段（要的那段本身不超过 5000 根细 K 线那么长）
    if (c.bars.length > FINE_CAP) {
      c.bars = c.bars.filter(b => b.t >= t0 && b.t < t1)
      c.from = Math.max(c.from, t0); c.to = Math.min(c.to, t1)
    }
    // 细 K 线最后一根可能还没收完：到它开盘为止才算盖住
    const last = c.bars[c.bars.length - 1]
    if (last && last.t + f.ms > Date.now()) c.to = Math.min(c.to, last.t)
    onReady()
  } finally { c.busy = false }
}

/** 测试用 */
export function resetFine(): void { cache.clear() }
