/* Hkline Web · 足迹图（主图的一种画法，替换蜡烛）
 *
 * 每根 K 线拆成一格格价位：中线左边是这一格里的主动卖出额、右边是主动买入额（币安、OKX、Coinbase 三家合计），
 * 格子够高够宽写数字（字号随格高缩放），不够只画横条，整根太窄就照旧画蜡烛。颜色跟蜡烛的涨跌色走；
 * 这根里成交额最大的那一格（控制点）描一圈橙框，开盘到收盘那段描一个涨跌色的框。
 *
 * 数据：
 *   历史 —— 服务端按（分钟 × 价位桶）攒好的（market/footprintApi.ts），按可见范围按窗去要，缓存照 fineVolume.ts：
 *           每只品种留一段连续的分钟，防抖、同一时刻只有一个请求、失败 30 秒内不再试，要回来置脏重画——画的那一帧从不等它。
 *   实时 —— 订单流数据层（orderflow/index.ts）收到的三家逐笔，按同一个步长分到（分钟 × 价位桶）里。
 *   每一分钟用哪份：这一分钟整个落在逐笔的覆盖区间里（判定直接用 tradeFlow.ts 的 covered，和累计量差同一口径）就用实时的，
 *   否则用服务端的；粗周期（5 分、15 分、1 小时……）在这里把分钟并起来。秒级周期不支持（菜单里置灰）。
 *
 * 价位桶：服务端给步长（价格 × 0.0002 取到 1/2/5×10ⁿ）；画的时候取它的整数倍（1、2、5、10、20、50……），
 * 让可见这段 K 线的中位高低差落在每根 10–30 格。没有服务端步长时（没跟踪的品种、接口没上线）按同一规则从价格现算。
 * 开关只是这一格图的看法（本机记住），不进设置、不跟账号同步。
 */
import type { TVChart, Pane, PriceRange } from './chart'
import type { TradeEvent } from '../orderflow/feed'
import type { MenuItem } from '../ui/overlay'
import { GLOSSARY, term } from '../ui/overlay'
import { flowOf } from './tradeFlow'
import { fetchFootprint, FOOT_WINDOW_MS, FOOT_KEEP_MS, type FootRow } from '../market/footprintApi'
import { ago } from '../util/clock'

GLOSSARY['足迹'] = '把每根 K 线拆成一格格价位：左边是这一格里的主动卖出额，右边是主动买入额（币安、OKX、Coinbase 三家合计）。放大到够宽才写数字。'
GLOSSARY['控制点'] = '这根 K 线里成交额最大的那一格价位（图上描橙框）。'

const MIN = 60_000
/** 间距小于这个就照旧画蜡烛 */
export const FP_MIN_SPACING = 6
const DEBOUNCE_MS = 250
const RETRY_MS = 30_000
/** 右边新收完的分钟多久补一次（上一次回空就放慢） */
const POLL_MS = 15_000
const POLL_EMPTY_MS = 60_000
/** 右边往回多要两分钟：服务端刚收完的那一分钟可能还没写全 */
const OVERLAP_MS = 2 * MIN
const KEEP_SYMBOLS = 16
const LIVE_KEEP_MS = FOOT_KEEP_MS
/** 一根 K 线还在这段时间里的就每帧重算（当前这根、刚收完还可能有晚到成交的那根） */
const HOT_MS = 2 * MIN
const POC = '#FF9800'

// ------------------------------------------------------------ 步长（纯函数）
/** 最接近的 1/2/5×10ⁿ（按比例算远近） */
export function nearestNice(x: number): number {
  if (!(x > 0) || !isFinite(x)) return 1
  const e = Math.floor(Math.log10(x)), p = Math.pow(10, e)
  let best = p, err = Infinity
  for (const m of [1, 2, 5, 10]) { const d = Math.abs(Math.log(m * p / x)); if (d < err) { err = d; best = m * p } }
  return +best.toPrecision(12)
}
/** 没有服务端步长时：和服务端同一规则（价格 × 0.0002 取到最近的 1/2/5×10ⁿ） */
export const fallbackStep = (price: number): number => nearestNice(price * 0.0002)
const MULTS: number[] = []
for (let e = 1; e <= 1e9; e *= 10) for (const m of [1, 2, 5]) MULTS.push(m * e)
/**
 * 画的时候的倍数：中位高低差 ÷（倍数 × 步长）落在 10–30 格。上一帧的倍数还在这个区间就不换（拖动时格子不跳）；
 * 一格的像素高不到 minPx 就再放粗（格子挤成一条线既看不清也白画）。
 */
export function pickMultiple(range: number, step: number, prev = 0, pxPerPrice = Infinity, minPx = 2): number {
  if (!(range > 0) || !(step > 0)) return prev || 1
  const rows = (k: number) => range / (k * step), tall = (k: number) => k * step * pxPerPrice >= minPx
  if (prev && rows(prev) >= 10 && rows(prev) <= 30 && tall(prev)) return prev
  const want = range / (25 * step)
  let k = MULTS.find(m => m >= want) ?? MULTS[MULTS.length - 1]
  while (!tall(k)) { const n = MULTS.find(m => m > k); if (!n) break; k = n }
  return k
}

// ------------------------------------------------------------ 并格（纯函数）
/** 一根 K 线的足迹：价位（桶下沿）升序，与每格的主动买 / 主动卖额 */
export interface FootAgg { px: Float64Array; buy: Float64Array; sell: Float64Array; tb: number; ts: number; poc: number; max: number }
type Acc = Map<number, [number, number]>
const addTo = (m: Acc, k: number, b: number, s: number): void => { const o = m.get(k); if (o) { o[0] += b; o[1] += s } else m.set(k, [b, s]) }
/** 一组价位行（按步长 step 的桶下沿）并进粗一级的桶 d */
export function bucketRows(m: Acc, rows: readonly FootRow[], d: number): void {
  for (const [p, b, s] of rows) addTo(m, Math.floor(p / d + 1e-7), b, s)
}
export function finishAgg(m: Acc, d: number): FootAgg | null {
  if (!m.size) return null
  const keys = [...m.keys()].sort((a, b) => a - b), n = keys.length
  const px = new Float64Array(n), buy = new Float64Array(n), sell = new Float64Array(n)
  let tb = 0, ts = 0, poc = 0, best = -1, max = 0
  for (let j = 0; j < n; j++) {
    const [b, s] = m.get(keys[j])!
    px[j] = +(keys[j] * d).toPrecision(12); buy[j] = b; sell[j] = s; tb += b; ts += s
    if (b + s > best) { best = b + s; poc = j }
    if (b > max) max = b
    if (s > max) max = s
  }
  return { px, buy, sell, tb, ts, poc, max }
}
/** 分钟行并成粗周期：按每分钟的起点分到 [t, t + ms) 里（ms 是周期毫秒；对齐和交易所的分钟线一样从 1970 起算） */
export function mergeMinutes(minutes: readonly { t: number; rows: readonly FootRow[] }[], ms: number, d: number): Map<number, FootAgg> {
  const acc = new Map<number, Acc>()
  for (const m of minutes) {
    const t = Math.floor(m.t / ms) * ms
    let a = acc.get(t); if (!a) { a = new Map(); acc.set(t, a) }
    bucketRows(a, m.rows, d)
  }
  const out = new Map<number, FootAgg>()
  for (const [t, a] of acc) { const g = finishAgg(a, d); if (g) out.set(t, g) }
  return out
}

// ------------------------------------------------------------ 实时：三家逐笔分到（分钟 × 价位桶）
interface Live { step: number; minutes: Map<number, Map<number, [number, number]>>; touched: number }
const live = new Map<string, Live>()
/** 服务端给过的步长（按品种） */
const srvStep = new Map<string, number>()

/** orderflow/index.ts 每进一笔成交调一次（价已经折成图上的口径）。数据层开着就一直记，开足迹之前的覆盖段也有数 */
export function recordFootprintTrade(symbol: string, ev: TradeEvent, now = Date.now()): void {
  const usd = ev.usd, price = ev.trade.price
  if (!(usd > 0) || !(price > 0)) return
  const key = symbol.toUpperCase()
  let l = live.get(key)
  if (!l) {
    l = { step: srvStep.get(key) ?? fallbackStep(price), minutes: new Map(), touched: now }
    live.set(key, l)
    if (live.size > KEEP_SYMBOLS) { const old = [...live.entries()].filter(([k]) => k !== key).sort((a, b) => a[1].touched - b[1].touched)[0]; if (old) live.delete(old[0]) }
  }
  l.touched = now
  const t = Math.floor((ev.trade.timeMs || now) / MIN) * MIN
  let m = l.minutes.get(t)
  if (!m) {
    m = new Map(); l.minutes.set(t, m)
    for (const k of l.minutes.keys()) { if (k >= now - LIVE_KEEP_MS) break; l.minutes.delete(k) }
  }
  addTo(m, Math.floor(price / l.step + 1e-7), ev.trade.hitSide === 'ask' ? usd : 0, ev.trade.hitSide === 'ask' ? 0 : usd)
}
/** 服务端的步长到了、和实时这边用的不一样：实时的桶按新步长重分 */
function adoptStep(symbol: string, step: number): void {
  srvStep.set(symbol, step)
  const l = live.get(symbol)
  if (!l || l.step === step) return
  for (const [t, m] of l.minutes) {
    const n: Acc = new Map()
    for (const [k, [b, s]] of m) addTo(n, Math.floor(k * l.step / step + 1e-7), b, s)
    l.minutes.set(t, n)
  }
  l.step = step
}
/** 这只品种现在用的步长：服务端的 > 实时那边的 > 按价格现算 */
export function stepOf(symbol: string, price: number): number {
  const k = symbol.toUpperCase()
  return srvStep.get(k) ?? live.get(k)?.step ?? fallbackStep(price)
}

// ------------------------------------------------------------ 历史缓存（照 fineVolume.ts）
interface Hist {
  minutes: Map<number, FootRow[]>; from: number; to: number; busy: boolean; failedAt: number; loadedAt: number; empty: boolean
  timer: ReturnType<typeof setTimeout> | null; want: [number, number] | null; ver: number
}
const hist = new Map<string, Hist>()
let apiBase = ''
const readyHooks = new Set<(symbol: string) => void>()

/** 画的那一帧调：[t0, t1) 没盖住就在后台去要（t1 只到已经收完的分钟） */
export function requestHistory(symbol: string, t0: number, t1: number, now = Date.now()): void {
  const key = symbol.toUpperCase()
  t0 = Math.max(Math.floor(t0 / MIN) * MIN, Math.ceil((now - FOOT_KEEP_MS) / MIN) * MIN)
  t1 = Math.min(Math.floor(t1 / MIN) * MIN, Math.floor(now / MIN) * MIN)
  if (!(t1 > t0)) return
  let h = hist.get(key)
  if (h && h.from <= t0 && h.to >= t1) return
  // 只差右边新收完的几分钟：别每帧都要，隔一阵补一次
  if (h && h.from <= t0 && h.to < t1 && ago(h.loadedAt, now) < (h.empty ? POLL_EMPTY_MS : POLL_MS)) return
  if (!h) {
    h = { minutes: new Map(), from: Infinity, to: -Infinity, busy: false, failedAt: 0, loadedAt: 0, empty: false, timer: null, want: null, ver: 0 }
    hist.set(key, h)
    while (hist.size > KEEP_SYMBOLS) { const k = hist.keys().next().value; if (k == null || k === key) break; hist.delete(k) }
  }
  h.want = [t0, t1]
  if (h.busy || h.timer || ago(h.failedAt, now) < RETRY_MS) return
  const entry = h
  entry.timer = setTimeout(() => { entry.timer = null; void loadHistory(key, entry) }, DEBOUNCE_MS)
}

async function loadHistory(symbol: string, h: Hist): Promise<void> {
  if (!h.want) return
  const [t0, t1] = h.want
  h.busy = true
  try {
    const joins = h.to > h.from && t1 >= h.from && t0 <= h.to
    // 和已有的一段连着：只要缺的两头（右边往回多要两分钟）；不连着就整段换掉
    const segs: [number, number][] = []
    if (!joins) segs.push([t0, t1])
    else {
      if (t1 > h.to) segs.push([Math.max(t0, h.to - OVERLAP_MS), t1])
      if (t0 < h.from) segs.push([t0, h.from])
    }
    const got: { t: number; rows: FootRow[] }[] = []
    let step: number | null = null
    // 一次最多 24 小时：从右往左一窗一窗要
    for (const [a, b] of segs) for (let e = b; e > a; e -= FOOT_WINDOW_MS) {
      const r = await fetchFootprint(symbol, Math.max(a, e - FOOT_WINDOW_MS), e, apiBase)
      if (!r.ok) { h.failedAt = Date.now(); return }
      if (r.data.step) step = r.data.step
      got.push(...r.data.minutes)
    }
    if (!joins) h.minutes.clear()
    for (const m of got) h.minutes.set(m.t, m.rows)
    h.from = joins ? Math.min(h.from, t0) : t0
    h.to = joins ? Math.max(h.to, t1) : t1
    h.empty = got.length === 0
    h.loadedAt = Date.now()
    const cut = Date.now() - FOOT_KEEP_MS
    for (const k of h.minutes.keys()) if (k < cut) h.minutes.delete(k)
    if (h.from < cut) h.from = Math.ceil(cut / MIN) * MIN
    if (step) adoptStep(symbol, step)
    h.ver++
    readyHooks.forEach(f => { try { f(symbol) } catch (e) { console.error(e) } })
  } finally { h.busy = false }
}

// ------------------------------------------------------------ 一根 K 线的足迹
/** [t, end) 这根 K 线按桶 d 并出来的足迹：每一分钟在覆盖区间里用实时的，否则用服务端的 */
export function barFootprint(symbol: string, t: number, end: number, d: number, now = Date.now()): FootAgg | null {
  const key = symbol.toUpperCase(), l = live.get(key), h = hist.get(key)
  if (!l && !h) return null
  const f = l ? flowOf(key) : null
  const m: Acc = new Map()
  for (let mt = Math.floor(t / MIN) * MIN; mt < end; mt += MIN) {
    if (l && f && f.covered(mt, mt + MIN, now)) {
      const lm = l.minutes.get(mt)
      if (lm) for (const [k, [b, s]] of lm) addTo(m, Math.floor(k * l.step / d + 1e-7), b, s)
    } else {
      const rows = h?.minutes.get(mt)
      if (rows) bucketRows(m, rows, d)
    }
  }
  return finishAgg(m, d)
}

// ------------------------------------------------------------ 每格图的开关与画法
/** 每格开没开足迹：开关记在格子配置里（st.cells[i].footprint，随布局集同步），由图表页接上；
 *  没接（单元测试）时用一份内存里的 */
export interface FootprintSource { on(idx: number): boolean; set(idx: number, on: boolean): void }
const memory = new Set<number>()
const memorySource: FootprintSource = { on: i => memory.has(i), set: (i, on) => { if (on) memory.add(i); else memory.delete(i) } }
let source: FootprintSource = memorySource
export function setFootprintSource(s: FootprintSource | null): void { source = s ?? memorySource }
const isOn = (idx: number): boolean => source.on(idx)
const bound = new Map<number, TVChart>()
interface View { key: string; mult: number; aggs: Map<number, FootAgg | null>; stat: { mode: 'num' | 'bar' | 'candle'; drawn: number; rows: number; ms: number; step: number; d: number; med: number; ppp: number } }
const views = new WeakMap<TVChart, View>()

readyHooks.add(symbol => { for (const c of bound.values()) if (!c.dead && c.meta.symbol.toUpperCase() === symbol) { c.dirty = true; c.legendDirty = true } })

const supports = (c: TVChart): boolean => c.iv >= MIN
/** 有没有哪格开着足迹（订单流数据层要不要为它开着） */
export function footprintWanted(): boolean {
  for (const [i, c] of bound) if (isOn(i) && !c.dead && supports(c)) return true
  return false
}
export function footprintOn(idx: number): boolean { return isOn(idx) }
export function setFootprint(idx: number, on: boolean): void {
  source.set(idx, on)
  const c = bound.get(idx)
  if (!c) return
  // 打开时放到最宽，一屏就能看到数字（少一步缩放）
  if (on && supports(c)) c.zoom(60 / Math.max(1, c.spacing))
  c.dirty = true; c.legendDirty = true
}

/** pages/chart.ts 建格子时挂上（重建格子再挂一次就换成新图） */
export function bindFootprint(chart: TVChart, idx: number): void {
  bound.set(idx, chart)
  chart.footprint = (p, r, from, to) => paint(chart, idx, p, r, from, to)
  chart.legendExtra = i => legendRow(chart, idx, i)
}

/** 周期菜单里的那一行（秒级周期置灰） */
export function footprintMenuItem(idx: number, iv: string): MenuItem {
  const sec = /^\d+s$/.test(iv)
  return { html: `${term('足迹')}${sec ? '<span class="faint" style="margin-left:8px">秒级周期不支持</span>' : ''}`, check: true, checked: !sec && isOn(idx), disabled: sec, run: () => { if (!sec) setFootprint(idx, !isOn(idx)) } }
}

function view(chart: TVChart, key: string): View {
  let v = views.get(chart)
  if (!v) { v = { key: '', mult: 0, aggs: new Map(), stat: { mode: 'candle', drawn: 0, rows: 0, ms: 0, step: 0, d: 0, med: 0, ppp: 0 } }; views.set(chart, v) }
  if (v.key !== key) { v.key = key; v.aggs.clear() }
  return v
}
const barEnd = (c: TVChart, i: number): number => c.bars[i + 1]?.t ?? c.bars[i].t + c.iv

function aggAt(c: TVChart, v: View, i: number, d: number, now: number): FootAgg | null {
  const b = c.bars[i]; if (!b) return null
  const end = barEnd(c, i), hot = end > now - HOT_MS
  if (!hot && v.aggs.has(b.t)) return v.aggs.get(b.t)!
  const g = barFootprint(c.meta.symbol, b.t, end, d, now)
  if (!hot) { if (v.aggs.size > 4000) v.aggs.clear(); v.aggs.set(b.t, g) }
  return g
}

/** 足迹图的格宽、步长与这一帧的视图（画与图例共用） */
function frameView(c: TVChart, from: number, to: number, now: number): { v: View; d: number } | null {
  const sym = c.meta.symbol, last = c.bars[c.bars.length - 1]
  if (!sym || !last) return null
  const step = stepOf(sym, last.c)
  const k = sym.toUpperCase(), h = hist.get(k), l = live.get(k)
  const pre = views.get(c)
  // 中位高低差定倍数
  const span: number[] = []
  for (let i = Math.max(0, from); i <= to && i < c.bars.length; i++) span.push(c.bars[i].h - c.bars[i].l)
  span.sort((a, b) => a - b)
  const med = span.length ? span[span.length >> 1] : 0
  const p = c._panes?.[0], r = c.mainRange
  const ppp = p && r && r.max > r.min ? Math.abs(c.priceToY(last.c, p, r) - c.priceToY(last.c + step, p, r)) / step : Infinity
  const mult = pickMultiple(med, step, pre?.key.startsWith(`${k}|${c.iv}|${step}|`) ? pre.mult : 0, ppp)
  const d = +(mult * step).toPrecision(12)
  const v = view(c, `${k}|${c.iv}|${step}|${mult}|${h?.ver ?? 0}|${l?.step ?? 0}`)
  v.mult = mult; v.stat.step = step; v.stat.d = d; v.stat.med = med; v.stat.ppp = ppp
  return { v, d }
}

function fmtUsd(x: number): string {
  if (x < 1e3) return x < 1 ? '' : String(Math.round(x))
  if (x < 1e6) return (x / 1e3).toFixed(x < 1e4 ? 1 : 0) + 'K'
  if (x < 1e9) return (x / 1e6).toFixed(x < 1e7 ? 1 : 0) + 'M'
  return (x / 1e9).toFixed(1) + 'B'
}

/** 主图这一帧的 K 线：画了返回 true（chart.ts 就不画蜡烛） */
function paint(c: TVChart, idx: number, p: Pane, r: PriceRange, from: number, to: number): boolean {
  const t0 = performance.now(), now = Date.now()
  if (!isOn(idx) || !supports(c) || !c.bars.length) return false
  const fv = frameView(c, from, to, now); if (!fv) return false
  const { v, d } = fv
  v.stat.mode = 'candle'; v.stat.drawn = 0; v.stat.rows = 0
  // 可见这段的历史不够就在后台去要（画这一帧不等它）
  const a = Math.max(0, from), b = Math.min(c.bars.length - 1, to)
  if (b >= a) requestHistory(c.meta.symbol, c.bars[a].t, barEnd(c, b), now)
  if (c.spacing < FP_MIN_SPACING) return false
  const aggs: (FootAgg | null)[] = []
  let any = false
  for (let i = a; i <= b; i++) { const g = aggAt(c, v, i, d, now); aggs.push(g); if (g) any = true }
  if (!any) return false
  const ctx = c.ctx, C = c.colors
  const W = Math.max(4, Math.floor(c.spacing * 0.88)), half = W / 2
  const y = (x: number) => c.priceToY(x, p, r)
  // 格高（线性坐标下每格一样高；对数坐标逐格算）
  const rowH = Math.abs(y(c.bars[b].c) - y(c.bars[b].c + d))
  let font = Math.max(8, Math.min(12, Math.floor(rowH * 0.72)))
  while (font > 8 && 2.6 * font > half - 4) font--
  const nums = rowH >= 9 && 2.6 * font <= half - 4
  v.stat.mode = nums ? 'num' : 'bar'
  // 没数据的那几根照旧画蜡烛（连成段一起画）
  let run = -1
  for (let k = 0; k <= aggs.length; k++) {
    if (k < aggs.length && !aggs[k]) { if (run < 0) run = k; continue }
    if (run >= 0) { c.drawCandles(p, r, a + run, a + k - 1); run = -1 }
  }
  // 影线（实体外的高低），涨跌色
  for (const up of [true, false]) {
    ctx.fillStyle = up ? C.up : C.down; ctx.beginPath()
    for (let k = 0; k < aggs.length; k++) {
      const bar = c.bars[a + k]; if (!aggs[k] || (bar.c >= bar.o) !== up) continue
      const x = Math.round(c.indexToX(a + k)), yh = Math.round(y(bar.h)), yl = Math.round(y(bar.l))
      ctx.rect(x, yh, 1, Math.max(1, yl - yh))
    }
    ctx.fill()
  }
  // 横条：左卖右买，长短按这根里最大的一格算
  const gap = rowH >= 4 ? 1 : 0
  for (const buy of [false, true]) {
    ctx.fillStyle = buy ? C.up : C.down; ctx.globalAlpha = nums ? 0.28 : 0.8; ctx.beginPath()
    for (let k = 0; k < aggs.length; k++) {
      const g = aggs[k]; if (!g || !(g.max > 0)) continue
      const x = Math.round(c.indexToX(a + k)), arr = buy ? g.buy : g.sell, sc = (half - 1) / g.max
      for (let j = 0; j < g.px.length; j++) {
        const len = arr[j] * sc; if (len < 0.5) continue
        const yt = y(g.px[j] + d), yb = y(g.px[j]), top = Math.round(Math.min(yt, yb)), hh = Math.max(1, Math.round(Math.abs(yb - yt)) - gap)
        ctx.rect(buy ? x + 1 : x - len, top, len, hh)
        v.stat.rows++
      }
    }
    ctx.fill()
  }
  ctx.globalAlpha = 1
  // 开到收的框（涨跌色）与控制点橙框
  ctx.lineWidth = 1
  for (const up of [true, false]) {
    ctx.strokeStyle = up ? C.up : C.down; ctx.beginPath()
    for (let k = 0; k < aggs.length; k++) {
      const bar = c.bars[a + k]; if (!aggs[k] || (bar.c >= bar.o) !== up) continue
      const x = Math.round(c.indexToX(a + k)), yo = Math.round(y(bar.o)), yc = Math.round(y(bar.c))
      ctx.rect(Math.round(x - half) + 0.5, Math.min(yo, yc) + 0.5, W - 1, Math.max(1, Math.abs(yc - yo)))
    }
    ctx.stroke()
  }
  ctx.strokeStyle = POC; ctx.beginPath()
  for (let k = 0; k < aggs.length; k++) {
    const g = aggs[k]; if (!g || g.px.length < 2) continue
    const x = Math.round(c.indexToX(a + k)), j = g.poc, yt = Math.round(y(g.px[j] + d)), yb = Math.round(y(g.px[j]))
    ctx.rect(Math.round(x - half) + 0.5, Math.min(yt, yb) + 0.5, W - 1, Math.max(1, Math.abs(yb - yt) - gap))
  }
  ctx.stroke()
  // 数字：卖额靠中线左、买额靠中线右
  if (nums) {
    ctx.font = `${font}px ${c.font.replace(/^[\d.]+px\s*/, '')}`; ctx.textBaseline = 'middle'
    for (const buy of [false, true]) {
      ctx.fillStyle = buy ? C.up : C.down; ctx.textAlign = buy ? 'left' : 'right'
      for (let k = 0; k < aggs.length; k++) {
        const g = aggs[k]; if (!g) continue
        const x = Math.round(c.indexToX(a + k)), arr = buy ? g.buy : g.sell
        for (let j = 0; j < g.px.length; j++) {
          const s = fmtUsd(arr[j]); if (!s) continue
          const ym = (y(g.px[j] + d) + y(g.px[j])) / 2
          if (ym < p.y || ym > p.y + p.h) continue
          ctx.fillText(s, buy ? x + 3 : x - 2, ym)
        }
      }
    }
    ctx.font = c.font
  }
  v.stat.drawn = aggs.filter(Boolean).length
  v.stat.ms = performance.now() - t0
  return true
}

/** 图例里足迹那一行：十字线所在那根的买、卖、净额与控制点 */
function legendRow(c: TVChart, idx: number, i: number): string {
  if (!isOn(idx) || !supports(c) || !c.bars[i]) return ''
  const now = Date.now(), r = c.visible()
  const fv = frameView(c, r.from, r.to, now); if (!fv) return ''
  const g = aggAt(c, fv.v, i, fv.d, now)
  const head = `<div class="lrow"><span class="ind-name">${term('足迹')}</span><span class="vals num">`
  if (!g) return `${head}<span class="faint">这根没有逐价成交</span></span></div>`
  const net = g.tb - g.ts, dec = Math.max(0, c.meta.dec)
  return `${head}<span class="up">买 ${fmtUsd(g.tb) || '0'}</span><span class="down">卖 ${fmtUsd(g.ts) || '0'}</span>`
    + `<span class="${net >= 0 ? 'up' : 'down'}">净 ${net >= 0 ? '+' : '−'}${fmtUsd(Math.abs(net)) || '0'}</span>`
    + `<span>${term('控制点')} ${(g.px[g.poc] + fv.d / 2).toFixed(dec)}</span></span></div>`
}

// ------------------------------------------------------------ 调试与测试
/** 压测 / 验收脚本读：第 i 格的足迹状态；__fpBench 连画 n 帧回每帧耗时中位（毫秒） */
;(globalThis as unknown as { __footprint?: (i?: number) => unknown }).__footprint = (i = 0) => {
  const c = bound.get(i); if (!c) return null
  const k = c.meta.symbol.toUpperCase(), h = hist.get(k), l = live.get(k), v = views.get(c)
  return { on: isOn(i), iv: c.iv, spacing: c.spacing, srvStep: srvStep.get(k) ?? null, histMinutes: h?.minutes.size ?? 0, histFrom: h?.from ?? null, histTo: h?.to ?? null, liveMinutes: l?.minutes.size ?? 0, ...(v?.stat ?? {}) }
}
/** 压测脚本读：第 i 格最后 n 根的足迹（买 / 卖合计、每一分钟用的是实时还是服务端的、可选逐档）——验历史与实时的接缝不重不漏 */
;(globalThis as unknown as { __fpBars?: (i?: number, n?: number, rows?: boolean) => unknown }).__fpBars = (i = 0, n = 30, rows = false) => {
  const c = bound.get(i); if (!c || !c.bars.length) return null
  const k = c.meta.symbol.toUpperCase(), l = live.get(k), h = hist.get(k), f = l ? flowOf(k) : null, now = Date.now()
  const d = stepOf(k, c.bars[c.bars.length - 1].c)
  return { step: d, bars: c.bars.slice(-n).map(b => {
    const end = b.t + c.iv, src: string[] = []
    for (let mt = Math.floor(b.t / MIN) * MIN; mt < end; mt += MIN) {
      src.push(l && f && f.covered(mt, mt + MIN, now) ? (l.minutes.has(mt) ? 'L' : 'l') : h?.minutes.has(mt) ? 'H' : '-')
    }
    const g = barFootprint(k, b.t, end, d, now)
    const mins = src.map((x, j) => { const mt = Math.floor(b.t / MIN) * MIN + j * MIN, m = barFootprint(k, mt, mt + MIN, d, now); return [mt, x, m?.tb ?? 0, m?.ts ?? 0] })
    return { t: b.t, buy: g?.tb ?? 0, sell: g?.ts ?? 0, src: src.join(''), mins, rows: rows && g ? [...g.px].map((p, j) => [p, g.buy[j], g.sell[j]]) : undefined }
  }) }
}
;(globalThis as unknown as { __fpBench?: (i?: number, n?: number, show?: number) => unknown }).__fpBench = (i = 0, n = 60, show = 0) => {
  const c = bound.get(i); if (!c) return null
  // show：先把视图摆成一屏正好 show 根（压测用）
  if (show > 0) { c.spacing = c.plotW() / show; c.rightBar = c.bars.length - 1 }
  const frame: number[] = [], fp: number[] = []
  for (let k = 0; k < n; k++) { const t = performance.now(); c.render(); frame.push(performance.now() - t); fp.push(views.get(c)?.stat.ms ?? 0) }
  const med = (a: number[]) => [...a].sort((x, y) => x - y)[Math.floor((a.length - 1) / 2)]
  const p95 = (a: number[]) => [...a].sort((x, y) => x - y)[Math.floor(a.length * 0.95)]
  return { frameMed: med(frame), frameP95: p95(frame), footprintMed: med(fp), stat: views.get(c)?.stat }
}
export function setFootprintApiBase(b: string): void { apiBase = b }
export function resetFootprint(): void { live.clear(); srvStep.clear(); hist.clear(); bound.clear(); memory.clear() }
export function historyOf(symbol: string): { from: number; to: number; minutes: number; empty: boolean } | null {
  const h = hist.get(symbol.toUpperCase()); return h ? { from: h.from, to: h.to, minutes: h.minutes.size, empty: h.empty } : null
}
export function onFootprintReady(fn: (symbol: string) => void): () => void { readyHooks.add(fn); return () => { readyHooks.delete(fn) } }
