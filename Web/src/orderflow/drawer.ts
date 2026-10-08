/* Hkline Web · 主力订单流 · 底部抽屉「大单列表」（2026-10-08 改版，照 docs/prototypes/web-bigtrade-drawer-2026-10-08.html）
 *
 * 四张卡横排（1440 宽 248 / 弹性 / 178 / 170，抽屉 ≥ 1500 宽时 400 / 弹性 / 330 / 330）：
 *   1. 汇总：今日净额大字 + 今日累计净额迷你走势；本根 / 近1时 / 今日三行对撞条（卖在左、买在右、金额写在条里，每行按自己比）；
 *      底部现货 / 合约、币安 / OKX / Coinbase 占比（只用浏览器近 1 小时记到的，只有历史时写「—」）。
 *      抽屉拉高（> 300）时迷你走势换成一张大图：累计净额 · 8:00 起 + 逐根净额柱与整点刻度。
 *   2. 每根：跟当前周期，最新在上，只列图上有气泡（或小圆点）且有大单的那几根（与图上同一套两级金额线，向上 / 向下含爆仓）。时间 | 对撞条 | 净额 | 笔数（买 / 卖）|
 *      最大（方向点 + 额）| 来源（各家细带）；卡宽 ≥ 640 时多一列现货、时间带日期、整列共用一把尺子，窄时每行自己比。
 *      正在走的那根带一个强调色小点；图上十字线停在哪根，那一行灰底 + 时间反白；点一行选中（强调色底与边线、图上那根一道竖带），再点取消。
 *   3. 价位：近 1 小时大单最集中的卖 / 买各三档，按真实价摆在一根竖轴上（挤了互相让开）；现价反白标签 + 虚线；
 *      最近的卖墙 / 买墙一道淡紫底带，右端一个小圆环（满一圈 = 挂了 1 小时）+ 「N分」，点墙图挪过去。
 *   4. 爆仓：今天每 15 分钟一桶（窄了自动并成 30 分 / 1 时）的镜像柱，上涨色 = 空头被平、下跌色 = 多头被平，开方比例，
 *      近 1 小时那段打底；下面本根 / 近1时 / 今日多空两边与「今日最大」。数据见 liquidation.ts。
 * 换周期 / 换品种：图一画出新的 K 线（layer.ts 的 after → drawerChartDrawn），同一帧里重算重画，不等订单流的下一帧。
 * 只聚合、门槛过滤、展示，不做判定。不加任何设置项。纯计算与 HTML / SVG 片段在 drawerView.ts。
 */
import { st, save } from '../app/store'
import { sizes, saveSizes } from '../app/sizes'
import { I } from '../ui/dom'
import { BT, fill } from '../terms'
import { patchKeyedRows } from '../ui/patch'
import { sym as symOf } from '../ui/common'
import { kindName, baseOf } from '../market/symbols'
import { flowOf, ensureHistory, type SymbolFlow } from '../chart/tradeFlow'
import type { TVChart } from '../chart/chart'
import { baseOfSymbol } from './settings'
import { BigBarCache, LevelCache, unitFor, sumBig, udOf, type BarBig } from './bigTags'
import { windows, liveShares, priceLevels, nearestWalls, dayStartUtc, HOUR, PX_MINUTES, type WinSum, type Wall, type TypicalAt } from './summary'
import { klines } from '../market'
import { LiqStore, LiqBarCache, noLiq, sumLiq, LIQ_EX, type LiqSum } from './liquidation'
import { OF, feedIdleText, amt, hm, mdhm, px, decFor } from './state'
import {
  DASH, signed, tone, pct, bfHtml, seg3, VENUES, srcHtml, maxOf, ivShort, levelsSvg, svgWrap,
  pickBucket, liqBuckets, liqSvg, cumSvg, hourTicks, LIQ_BUCKETS, NET_BUCKETS,
} from './drawerView'

const MIN = 60_000
const DAY = 86_400_000
const MAX_ROWS = 200
/** 抽屉比这高就是「拉高」：汇总换大图、爆仓多一个「近1时 ▸」 */
const TALL_H = 300
const SHORT_H = 240, LONG_H = 480
/** 图上点过的最早那根：列表至少列到它（否则点一枚很早的气泡，抽屉里找不到那一行） */
let reachT = Infinity

let slot: HTMLElement | null = null
let root: HTMLElement | null = null
const q = <T extends HTMLElement = HTMLElement>(k: string): T | null => root?.querySelector<T>(`[data-k="${k}"]`) ?? null
const liq = new LiqStore()
const cache = new BigBarCache()
const levelCache = new LevelCache()
const liqCache = new LiqBarCache()
let lastAt = 0
let lastKey = ''
let histSym = ''
let pendingReveal: number | null = null
let raf = 0
/** 上一次画进来的图（品种 | 周期 | 根数 | 首尾时间）：变了就同帧重画 */
let chartSig = ''

interface RowD { t: number; t1: number; d: BarBig; close: number }
let rows: RowD[] = []
let walls: { ask: Wall | null; bid: Wall | null } = { ask: null, bid: null }
let wallHits: { y0: number; y1: number; ask: boolean }[] = []

const onData = (): void => updateDrawer(true)
liq.onUpdate = onData

const GROW = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 7l3-3 3 3M5 12l3-3 3 3"/></svg>'
const SHRINK = '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 4l3 3 3-3M5 9l3 3 3-3"/></svg>'
const EMPTY_BARS_ICON = svgWrap(64, 28, '<rect x="2" y="10" width="26" height="8" rx="4" fill="var(--of-down-a)"/><rect x="36" y="10" width="26" height="8" rx="4" fill="var(--of-up-a)"/><rect x="31.5" y="4" width="1" height="20" fill="var(--line-strong)"/>')
const EMPTY_LIQ_ICON = svgWrap(46, 30, `<g fill="var(--line-strong)">${[0, 1, 2, 3, 4, 5, 6, 7].map(i => `<rect x="${i * 6}" y="${14 - (i % 3) * 2}" width="4" height="${2 + (i % 3) * 2}" rx="1"/><rect x="${i * 6}" y="16" width="4" height="${2 + ((i + 1) % 3) * 2}" rx="1" opacity=".6"/>`).join('')}</g>`)

export function mountDrawer(el: HTMLElement): void {
  slot = el
  el.innerHTML = `<div class="of-dr">
    <div class="of-dr-h"><h4>${BT.listTitle}</h4><div class="ctx"><span class="pill" data-k="psym" hidden></span><span class="pill" data-k="pcut" hidden></span></div>
      <div class="r"><button class="ibtn xs" id="ofDrGrow" data-k="grow"></button>
      <button class="ibtn xs" id="ofDrClose" aria-label="${BT.collapse}" data-tip="${BT.collapse}">${I('close', 'icon-16')}</button></div></div>
    <div class="of-dr-grid">
      <section class="of-blk of-sum" aria-label="${BT.summary}">
        <div class="ct"><span class="gl" style="background:var(--accent)"></span>${BT.summary}<span class="r"><span class="lg dn">${BT.sellShort}</span><span class="lg up">${BT.buyShort}</span></span></div>
        <div class="sum-hero"><div><div class="v num" data-k="net"></div><div class="l">${BT.todayNet}</div></div><div class="sp" data-k="spark"></div></div>
        <div class="sum-tall" data-k="cumTall"></div>
        <div class="wins" data-k="wins"></div>
        <div class="src" data-k="src"></div>
      </section>
      <section class="of-blk of-bars" aria-label="${BT.perBar}">
        <div class="bh" data-k="bh"></div>
        <div class="bl" role="list" data-k="bl"></div>
        <div class="fade" data-k="fade"></div>
        <div class="of-empty" data-k="be" hidden></div>
      </section>
      <section class="of-blk of-lvc" aria-label="${BT.levels}">
        <div class="ct"><span class="gl" style="background:var(--of-wall)"></span>${BT.levels}<span class="r">${BT.hour}</span></div>
        <div class="lv" data-k="lv"></div>
      </section>
      <section class="of-blk of-lqc" aria-label="${BT.liq}">
        <div class="ct"><span class="gl" style="background:var(--down)"></span>${BT.liq}<span class="r" data-k="lqlg"><span class="lg dn">${BT.long}</span><span class="lg up">${BT.short}</span></span></div>
        <div class="lq-c" data-k="lqc"></div>
        <div class="lq-w" data-k="lqw"></div>
        <div class="lmax" data-k="lmax"></div>
        <div class="of-empty" data-k="lqe" hidden></div>
      </section>
    </div></div>`
  root = el.querySelector('.of-dr')
  el.querySelector<HTMLElement>('#ofDrClose')!.onclick = () => { st.slots.drawer = false; save(); OF.api?.layoutSlots() }
  q('grow')!.onclick = () => { sizes.drawer = isTall() ? SHORT_H : LONG_H; saveSizes(); OF.api?.layoutSlots() }
  const bl = q('bl')!
  bl.addEventListener('click', onRowClick)
  bl.addEventListener('scroll', () => syncFade(), { passive: true })
  const lv = q('lv')!
  lv.addEventListener('click', e => { const w = wallAt(e); if (w) OF.focus?.(w.first) })
  lv.addEventListener('mousemove', e => { lv.style.cursor = wallAt(e) ? 'pointer' : '' })
  if (typeof ResizeObserver !== 'undefined') {
    let lastW = 0, lastH = 0
    new ResizeObserver(() => {
      const w = el.clientWidth, h = el.clientHeight
      if (w === lastW && h === lastH) return
      lastW = w; lastH = h
      schedulePaint()
    }).observe(el)
  }
  OF.revealBar = revealBar
  if (!crossBound) { crossBound = true; document.addEventListener('pointermove', onPointer, { passive: true, capture: true }) }
  lastKey = ''; chartSig = ''
  painted = { sum: '', bh: '', lv: '', lq: '', pills: '' }
  updateDrawer(true)
}

export function drawerVisible(): boolean { return !!slot && st.slots.drawer && !slot.hidden && slot.isConnected }
const isTall = (): boolean => (slot?.clientHeight ?? 0) > TALL_H

// ------------------------------------------------------------------ 数据

interface Ctx { sym: string; f: SymbolFlow; chart: TVChart; iv: number; unit: number; now: number }

function ctxNow(): Ctx | null {
  const a = OF.api?.activeChart()
  if (!a || !a.chart.bars.length) return null
  const sym = a.symbol.toUpperCase()
  if (!sym || sym === 'DXY') return null
  const f = flowOf(sym)
  const unit = unitFor(f, OF.feed?.symbol === sym ? OF.bigTrade : 0)
  return { sym, f, chart: a.chart, iv: a.chart.iv, unit, now: Date.now() }
}

/** 订单流出了一帧、历史到了、换了品种 / 周期：半秒最多重算一次（force 立刻） */
export function updateDrawer(force = false): void {
  if (!drawerVisible()) return
  const c = ctxNow()
  const key = c ? `${c.sym}|${c.iv}|${c.unit}` : ''
  const now = Date.now()
  if (!force && key === lastKey && now - lastAt < 500) return
  if (key !== lastKey) {
    reachT = Infinity
    // 换了品种 / 周期：选中的那根作废（图上的竖带也跟着没了）
    if (OF.selBar && (!c || OF.selBar.symbol !== c.sym || OF.selBar.iv !== c.iv)) { OF.selBar = null; if (c) c.chart.dirty = true }
  }
  lastAt = now; lastKey = key
  if (c) {
    if (histSym !== c.sym) { if (histSym) flowOf(histSym).listeners.delete(onData); histSym = c.sym }
    ensureHistory(c.f, onData, now)
    liq.ensure(baseOfSymbol(c.sym).base, now)
    buildRows(c)
  } else rows = []
  schedulePaint()
}

/** 图画完一帧（layer.ts 的 after 调）：活动格子的品种 / 周期 / K 线变了，就在这一帧里把抽屉重算重画——
 *  原来只跟着订单流的帧（像素变了才出、空闲 5 秒一帧）+ 半秒节流走，换周期后「每根」要晚 0.5–2.5 秒才跟上 */
export function drawerChartDrawn(chart: TVChart): void {
  if (!drawerVisible()) return
  const a = OF.api?.activeChart()
  if (!a || a.chart !== chart) return
  const b = chart.bars
  const sig = `${a.symbol}|${chart.iv}|${b.length}|${b.length ? b[0].t : 0}|${b.length ? b[b.length - 1].t : 0}`
  if (sig === chartSig) return
  chartSig = sig
  updateDrawer(true)
  if (raf && typeof cancelAnimationFrame !== 'undefined') { cancelAnimationFrame(raf); raf = 0 }
  paint()
}

function buildRows(c: Ctx): void {
  rows = []
  const { chart, f, now } = c
  cache.begin(f, `${c.sym}|${c.iv}`, now)
  const base = baseOfSymbol(c.sym).base
  const lb = !noLiq(c.sym) && c.iv >= MIN ? liqCache.of(liq.state(base), base, c.iv) : null
  const levels = levelCache.get(cache, f, chart, now, c.unit, lb)
  if (!levels) return
  let start = Infinity
  for (const k of f.min.keys()) { start = k; break }
  for (const k of f.sec.keys()) { start = Math.min(start, k); break }
  if (f.srv.tracked && f.srv.lo < start) start = f.srv.lo
  const bars = chart.bars
  for (let i = bars.length - 1; i >= 0 && (rows.length < MAX_ROWS || bars[i].t >= reachT); i--) {
    const t = bars[i].t
    const t1 = i + 1 < bars.length ? bars[i + 1].t : chart.timeAt(i + 1)
    if (t1 <= start) break
    const d = cache.get(f, t, t1, now)
    if (!d) continue
    const u = udOf(d, lb ? lb.at(t, t1) : null)
    if (Math.max(u.up, u.down) >= levels.dot) rows.push({ t, t1, d, close: bars[i].c })
  }
}

// ---- 十字线同步：活动格子的十字线（自己的或别的格子同步来的）停在哪根，「每根」那一行跟着亮。
let crossBound = false
let crossRaf = 0
function onPointer(): void {
  if (crossRaf || !drawerVisible() || typeof requestAnimationFrame === 'undefined') return
  crossRaf = requestAnimationFrame(() => { crossRaf = 0; syncCross() })
}
/** 图上十字线所在那根的开盘时间；不在图上 null */
export function crossTime(ch: Pick<TVChart, 'cross' | 'extCross' | 'bars' | 'xToIndex' | 'indexAt'>): number | null {
  let i: number
  if (ch.cross) i = Math.round(ch.xToIndex(ch.cross.x))
  else if (ch.extCross != null) i = Math.round(ch.indexAt(ch.extCross))
  else return null
  return i >= 0 && i < ch.bars.length ? ch.bars[i].t : null
}
function syncCross(): void {
  const a = OF.api?.activeChart()
  const t = a ? crossTime(a.chart) : null
  if (t === OF.crossT) return
  const was = OF.crossT
  OF.crossT = t
  // 只换前后两行（不整列重排）
  for (const k of [was, t]) if (k != null) patchRow(k)
  if (t == null) return
  const el = rowEl(t), bl = q('bl')
  if (!el || !bl || !bl.clientHeight) return
  const top = el.offsetTop, h = bl.clientHeight
  if (top < bl.scrollTop) bl.scrollTop = top
  else if (top + el.offsetHeight > bl.scrollTop + h) bl.scrollTop = top + el.offsetHeight - h
}

// ---- 价位用的 1 分钟 K 线：(高 + 低 + 收) / 3。一次取 60 根，每分钟作废一次；图本身是 1 分钟就直接读图上的
const k1 = { sym: '', min: 0, busy: false, typ: new Map<number, number>() }
function typicalFor(c: Ctx): TypicalAt | null {
  if (c.iv === MIN) {
    const bars = c.chart.bars, m = new Map<number, number>()
    for (let i = bars.length - 1; i >= Math.max(0, bars.length - PX_MINUTES - 1); i--) m.set(bars[i].t, (bars[i].h + bars[i].l + bars[i].c) / 3)
    return t => m.get(t) ?? null
  }
  const min = Math.floor(c.now / MIN)
  if ((k1.sym !== c.sym || k1.min !== min) && !k1.busy) {
    const sym = c.sym
    k1.busy = true
    void klines(sym, '1m', undefined, PX_MINUTES, false, true, () => drawerVisible() && ctxNow()?.sym === sym).then(r => {
      // 取失败也记下这一分钟（空表），下一分钟再试，不在每次重画里连发
      k1.busy = false; k1.sym = sym; k1.min = min
      k1.typ = new Map(r.ok ? r.bars.map(b => [b.t, (b.h + b.l + b.c) / 3]) : [])
      if (r.ok) schedulePaint()
    })
  }
  if (k1.sym !== c.sym) return null
  const m = k1.typ
  return t => m.get(t) ?? null
}

// ------------------------------------------------------------------ 交互

function onRowClick(e: MouseEvent): void {
  const el = (e.target as HTMLElement).closest<HTMLElement>('[data-t]')
  const a = OF.api?.activeChart()
  if (!el || !a) return
  const r = rows.find(x => x.t === Number(el.dataset.t))
  if (!r) return
  const sym = a.symbol.toUpperCase()
  const on = OF.selBar && OF.selBar.symbol === sym && OF.selBar.iv === a.chart.iv && OF.selBar.t === r.t
  if (on) OF.selBar = null
  else {
    OF.selBar = { symbol: sym, iv: a.chart.iv, t: r.t }
    const mx = maxOf(r.d)
    a.chart.centerOn(r.t + (r.t1 - r.t) / 2, mx?.price ?? r.close)
    OF.barHi = { symbol: sym, t: r.t, until: Date.now() + 1500 }
  }
  a.chart.dirty = true
  paintBars()
}

/** 图上点了一枚气泡：抽屉没开就打开，开着就滚到那一行（并选中它） */
function revealBar(_sym: string, t: number): void {
  pendingReveal = t
  // 点的是 200 行之外更早的那根：列表一直往回列到它（换品种 / 周期才收回去）
  reachT = Math.min(reachT, t)
  if (!st.slots.drawer) { st.slots.drawer = true; save(); OF.api?.layoutSlots() }
  updateDrawer(true)
}

function rowEl(t: number): HTMLElement | null { return q('bl')?.querySelector<HTMLElement>(`[data-t="${t}"]`) ?? null }

function scrollToPending(): void {
  const bl = q('bl')
  if (pendingReveal == null || !bl || !bl.clientHeight) return
  const el = rowEl(pendingReveal)
  pendingReveal = null
  if (!el) return
  const top = el.offsetTop, h = bl.clientHeight, rh = el.offsetHeight
  if (top < bl.scrollTop || top + rh > bl.scrollTop + h) bl.scrollTop = Math.max(0, top - h / 2 + rh / 2)
  syncFade()
}

function wallAt(e: MouseEvent): Wall | null {
  const lv = q('lv')
  if (!lv) return null
  const y = e.clientY - lv.getBoundingClientRect().top
  const h = wallHits.find(x => y >= x.y0 && y <= x.y1)
  return h ? (h.ask ? walls.ask : walls.bid) : null
}

// ------------------------------------------------------------------ 画

function schedulePaint(): void {
  if (raf || typeof requestAnimationFrame === 'undefined') return
  raf = requestAnimationFrame(() => { raf = 0; paint() })
}

/** 每块上次写进去的 HTML（没变就不碰 DOM） */
let painted = { sum: '', bh: '', lv: '', lq: '', pills: '' }
function setHtml(el: HTMLElement | null, html: string): void {
  if (!el) return
  const m = el as HTMLElement & { _h?: string }
  if (m._h === html) return
  m._h = html
  el.innerHTML = html
}
function setHidden(el: HTMLElement | null, h: boolean): void { if (el && el.hidden !== h) el.hidden = h }

function paint(): void {
  if (!drawerVisible() || !slot || !root) return
  const tall = isTall()
  root.classList.toggle('tall', tall)
  const grow = q('grow')!
  const gl = tall ? '放矮' : '拉高'
  if (grow.getAttribute('aria-label') !== gl) { grow.setAttribute('aria-label', gl); grow.dataset.tip = gl; grow.innerHTML = tall ? SHRINK : GROW }
  const c = ctxNow()
  paintPills(c)
  paintBars(c)
  scrollToPending()
  paintSum(c, tall)
  paintLevels(c)
  paintLiq(c, tall)
}

function paintPills(c: Ctx | null): void {
  const a = OF.api?.activeChart()
  const s = a?.symbol.toUpperCase() ?? ''
  const info = s ? symOf(s) : undefined
  const ps = q('psym'), pc = q('pcut')
  const cut = c ? c.f.cut : null
  const key = `${s}|${cut}`
  if (key === painted.pills) return
  painted.pills = key
  setHidden(ps, !s)
  if (s && ps) ps.innerHTML = `<b>${info?.base ?? baseOf(s)}</b> ${kindName(info)}`
  setHidden(pc, cut == null)
  if (cut != null && pc) pc.innerHTML = fill(BT.thresholdValue, { v: `<b class="num">${amt(cut)}</b>` })
}

// ---- 文字宽（金额写在条里还是挪到条外，按真实字宽算）
let mctx: CanvasRenderingContext2D | null = null
let numFamily = ''
const twCache = new Map<string, number>()
function tw(t: string, weight = 600): number {
  if (!t) return 0
  const k = weight + t
  const hit = twCache.get(k)
  if (hit != null) return hit
  if (!mctx) mctx = document.createElement('canvas').getContext('2d')
  if (!numFamily) numFamily = getComputedStyle(document.documentElement).getPropertyValue('--font-num').trim() || 'system-ui'
  let w = t.length * 6.6
  if (mctx) { mctx.font = `${weight} 11px ${numFamily}`; w = mctx.measureText(t).width }
  if (twCache.size > 2000) twCache.clear()
  twCache.set(k, w)
  return w
}

// ---- 1. 汇总

function paintSum(c: Ctx | null, tall: boolean): void {
  const net = q('net'), sp = q('spark'), big = q('cumTall'), wins = q('wins'), src = q('src')
  if (!net || !sp || !big || !wins || !src) return
  const w = c ? (() => { const b = c.chart.bars; return windows(c.f, b[b.length - 1].t, c.chart.timeAt(b.length), c.now) })() : null
  const has = !!w && w.today.has && w.today.bb + w.today.bs > 0
  const n = w ? w.today.bb - w.today.bs : 0
  setHtml(net, has ? signed(n) : '—')
  net.className = `v num ${has ? tone(n) : 't3'}`
  // 窗口三行：每行按自己的买卖比；半边宽 = (行宽 − 28 − 54 − 两道 5 的间距 − 中缝 2) / 2
  const half = Math.max(16, (wins.clientWidth - 36 - 54 - 10 - 2) / 2)
  const zero: WinSum = { bb: 0, bs: 0, bn: null, sn: null, has: false }
  const row = (k: string, s: WinSum): string => {
    const v = s.bb - s.bs
    return `<div class="wr"><span class="k">${k}</span>${bfHtml({ s: s.bs, b: s.bb, max: Math.max(s.bs, s.bb), half, tw })}<span class="n num ${tone(v)}">${signed(v)}</span></div>`
  }
  setHtml(wins, row(BT.currentBar, w?.bar ?? zero) + row(BT.hour, w?.hour ?? zero) + row(BT.today, w?.today ?? zero))
  const sh = c && OF.feed?.symbol === c.sym ? liveShares(c.f, c.now) : null
  setHtml(src, sh && sh.total > 0 ? srcHtml(sh.total, sh.spot, sh.ex) : srcHtml(0, null, null))
  // 今日累计净额：迷你走势（矮）/ 大图 + 逐根净额（高）
  const el = tall ? big : sp
  const W = Math.floor(el.clientWidth), H = Math.floor(el.clientHeight)
  if (!W || !H) return
  if (!c || !has) { setHtml(el, cumSvg({ w: W, h: H, nets: [], tall, empty: true })); return }
  const from = dayStartUtc(c.now)
  const B = tall ? pickBucket(from, c.now, W - 4, NET_BUCKETS, 3, 5 * MIN) : pickBucket(from, c.now, W - 4, NET_BUCKETS, 1.5, 5 * MIN)
  const nets = netsOf(c, from, B)
  const ticks = tall ? hourTicks(from, c.now, B, W, t => new Date(t + 8 * HOUR).getUTCHours()) : []
  setHtml(el, cumSvg({ w: W, h: H, nets, tall, ticks, startLabel: '8:00' }))
}

/** 今日每桶的净额（大买 − 大卖）：先按 5 分钟算一遍，再并成 B；按（品种、5 分钟序号、历史版本）缓存 */
const netMemo = { key: '', five: [] as number[] }
function netsOf(c: Ctx, from: number, B: number): number[] {
  const F = 5 * MIN
  const n5 = Math.floor((c.now - from) / F) + 1
  const key = `${c.sym}|${from}|${n5}|${c.f.srv.ver}|${Math.floor(c.now / 5000)}`
  if (netMemo.key !== key) {
    const five: number[] = []
    for (let i = 0; i < n5; i++) { const s = sumBig(c.f, from + i * F, from + (i + 1) * F, c.now).c; five.push(s.bb - s.bs) }
    netMemo.key = key; netMemo.five = five
  }
  const k = Math.max(1, Math.round(B / F)), out: number[] = []
  for (let i = 0; i < netMemo.five.length; i += k) { let s = 0; for (let j = i; j < Math.min(i + k, netMemo.five.length); j++) s += netMemo.five[j]; out.push(s) }
  return out
}

// ---- 2. 每根

function bhHtml(iv: number, empty: boolean): string {
  const t = `<span class="t">${BT.perBar}<em>${ivShort(iv)}</em></span>`
  if (empty) return t
  return t + `<div class="bf-h"><span>${BT.sellShort}</span><span>${BT.buyShort}</span></div><span class="rt">${BT.net}</span><span class="rt">${BT.trades}</span><span class="rt">${BT.maxSingle}</span><span class="x rt">${BT.spot}</span><span class="rt">${BT.source}</span>`
}

interface RowEnv { wide: boolean; half: number; max: number; lastT: number; live: boolean; daily: boolean; sel: number | null }
let env: RowEnv | null = null

function rowHtml(r: RowD, e: RowEnv): string {
  const d = r.d, n = d.bb - d.bs
  const cur = r.t === e.lastT, xh = OF.crossT === r.t, sel = e.sel === r.t
  const md = mdhm(r.t)
  const tm = e.daily ? md.slice(0, 5) : e.wide ? md : hm(r.t)
  const mark = !xh && cur && e.live ? '<span class="live"></span>' : ''
  const mx = d.exact ? maxOf(d) : null
  const cnt = d.bn != null && d.sn != null ? `<span class="up">${d.bn}</span><span class="t3">/</span><span class="dn">${d.sn}</span>` : DASH
  const tot = d.bb + d.bs
  const ex = d.ex && tot > 0 ? seg3(VENUES.map(([, col], j) => [d.ex![j], col] as [number, string]), 'v3') : `<span class="dash">—</span>`
  return `<div class="br${cur ? ' cur' : ''}${xh ? ' xh' : ''}${sel ? ' sel' : ''}" role="listitem" data-t="${r.t}" data-k="${r.t}">` +
    `<span class="tm num">${xh ? `<span class="xtag">${tm}</span>` : tm}${mark}</span>` +
    bfHtml({ s: d.bs, b: d.bb, max: e.wide ? e.max : Math.max(d.bs, d.bb), half: e.half, tw }) +
    `<span class="n num ${tone(n)}">${signed(n)}</span>` +
    `<span class="c num">${cnt}</span>` +
    `<span class="m num">${mx ? `<i style="background:var(--${mx.buy ? 'up' : 'down'})"></i>${amt(mx.usd)}` : DASH}</span>` +
    `<span class="x c num">${d.spot != null && tot > 0 ? pct(d.spot, tot) : DASH}</span>` +
    `<span class="v">${ex}</span></div>`
}

function patchRow(t: number): void {
  const el = rowEl(t), r = rows.find(x => x.t === t)
  if (!el || !r || !env) return
  const box = document.createElement('div')
  box.innerHTML = rowHtml(r, { ...env, sel: selT() })
  const nu = box.firstElementChild
  if (nu) el.replaceWith(nu)
}

function selT(): number | null {
  const a = OF.api?.activeChart(), s = OF.selBar
  return a && s && s.symbol === a.symbol.toUpperCase() && s.iv === a.chart.iv ? s.t : null
}

function paintBars(c: Ctx | null = ctxNow()): void {
  const bh = q('bh'), bl = q('bl'), be = q('be'), fade = q('fade')
  if (!bh || !bl || !be || !fade) return
  const a = OF.api?.activeChart()
  const iv = a?.chart.iv ?? MIN
  if (!rows.length || !c) {
    setHtml(bh, bhHtml(iv, true))
    patchKeyedRows(bl, [], 'data-k')
    setHidden(bl, true); setHidden(fade, true); setHidden(be, false)
    const s = a?.symbol.toUpperCase() ?? ''
    let html: string
    if (!a) html = ''
    else if (s === 'DXY') html = `<b>${BT.noTradeData}</b>`
    else if (!c || (OF.feed?.symbol !== s && !c.f.srv.tracked)) html = `<span>${feedIdleText()}</span>`
    else html = `${EMPTY_BARS_ICON}<b>${BT.noBigTrade}</b>${c.f.cut != null ? `<span>${fill(BT.thresholdValue, { v: `<span class="num">${amt(c.f.cut)}</span>` })}</span>` : ''}`
    setHtml(be, html)
    return
  }
  setHidden(bl, false); setHidden(fade, false); setHidden(be, true)
  setHtml(bh, bhHtml(iv, false))
  const bfh = bh.querySelector<HTMLElement>('.bf-h'), xcol = bh.querySelector<HTMLElement>('.x')
  const wide = !!xcol && getComputedStyle(xcol).display !== 'none'
  const half = Math.max(16, ((bfh?.clientWidth ?? 120) - 2) / 2)
  let max = 1
  for (const r of rows) max = Math.max(max, r.d.bb, r.d.bs)
  const live = OF.feed?.symbol === c.sym
  const b = c.chart.bars
  env = { wide, half, max, lastT: b[b.length - 1].t, live, daily: c.iv >= DAY, sel: selT() }
  const today = mdhm(c.now).slice(0, 5)
  const out: [string, string][] = []
  let day = today
  for (const r of rows) {
    // 窄卡的时间列只写时:分，跨天处插一行日期
    if (!wide && !env.daily) {
      const dd = mdhm(r.t).slice(0, 5)
      if (dd !== day) { day = dd; out.push([`d${dd}`, `<div class="bd num" data-k="d${dd}">${dd}</div>`]) }
    }
    out.push([String(r.t), rowHtml(r, env)])
  }
  patchKeyedRows(bl, out, 'data-k')
  syncFade()
}

function syncFade(): void {
  const bl = q('bl'), fade = q('fade')
  if (!bl || !fade) return
  const end = bl.scrollTop + bl.clientHeight >= bl.scrollHeight - 2
  fade.classList.toggle('off', end)
}

// ---- 3. 价位

function paintLevels(c: Ctx | null): void {
  const lv = q('lv')
  if (!lv) return
  const W = Math.floor(lv.clientWidth), H = Math.floor(lv.clientHeight)
  wallHits = []; walls = { ask: null, bid: null }
  if (!W || !H) return
  const live = !!c && OF.feed?.symbol === c.sym && !!OF.snap
  if (!c || !live) {
    setHtml(lv, `<div class="of-empty"><span>${c ? feedIdleText() : ''}</span></div>`)
    return
  }
  const step = OF.feed!.model.scheme?.step ?? 0
  const b = c.chart.bars
  const mid = OF.fine?.mid ?? b[b.length - 1].c
  const dec = decFor(step, OF.api?.dec(c.sym) ?? 2)
  walls = nearestWalls(OF.snap!.orders, mid)
  const { buy, sell } = priceLevels(c.f, step, c.now, typicalFor(c))
  const fmt = (p: number): string => px(p, dec)
  const prices = [mid, ...buy.map(l => l.price), ...sell.map(l => l.price), ...(walls.ask ? [walls.ask.price] : []), ...(walls.bid ? [walls.bid.price] : [])]
  const pxCol = Math.max(46, Math.ceil(Math.max(...prices.map(p => tw(fmt(p), 650)))) + 10)
  const wall = (w: Wall | null): { price: number; usd: number; age: number } | null => w ? { price: w.price, usd: w.usd, age: Math.max(0, c.now - w.since) } : null
  const r = levelsSvg({
    w: W, h: H, pxCol,
    sell: sell.map(l => ({ price: l.price, usd: l.usd })), buy: buy.map(l => ({ price: l.price, usd: l.usd })),
    ask: wall(walls.ask), bid: wall(walls.bid), cur: mid, fmt, tw,
    note: !buy.length && !sell.length ? BT.hourNoBigTrade : undefined,
  })
  wallHits = r.hits
  setHtml(lv, r.svg)
}

// ---- 4. 爆仓

function liqRow(k: string, s: LiqSum): string {
  const t = s.long + s.short || 1
  return `<div class="lr"><span class="k">${k}</span><span class="a num ${s.long ? 'dn' : 't3'}">${s.long ? amt(s.long) : '0'}</span>` +
    `<div class="rb"><i style="flex:${(s.long / t || 0.0001).toFixed(4)};background:var(--down)"></i><i style="flex:${(s.short / t || 0.0001).toFixed(4)};background:var(--up)"></i></div>` +
    `<span class="a b num ${s.short ? 'up' : 't3'}">${s.short ? amt(s.short) : '0'}</span></div>`
}

function paintLiq(c: Ctx | null, tall: boolean): void {
  const lc = q('lqc'), lw = q('lqw'), lm = q('lmax'), le = q('lqe'), lg = q('lqlg')
  if (!lc || !lw || !lm || !le || !lg) return
  const s = c ? liq.state(baseOfSymbol(c.sym).base) : null
  const empty = !c || !s || !s.rows.size
  for (const el of [lc, lw, lm, lg]) setHidden(el, empty)
  setHidden(le, !empty)
  if (empty) { setHtml(le, `${EMPTY_LIQ_ICON}${c && s && s.tracked != null ? `<b>${BT.noLiqData}</b>` : ''}`); return }
  const now = c!.now, all = [...s!.rows.values()]
  const b = c!.chart.bars
  const t0 = b[b.length - 1].t, t1 = c!.chart.timeAt(b.length)
  // 本根按分钟算：起点往下取整到分钟（秒级周期就是正在走的这一分钟）
  const m0 = Math.floor(t0 / MIN) * MIN
  const from = dayStartUtc(now)
  const bar = sumLiq(all, m0, Math.max(t1, m0 + MIN)), hour = sumLiq(all, Math.floor((now - HOUR) / MIN) * MIN, now + 1), today = sumLiq(all, from, now + 1)
  setHtml(lw, liqRow(BT.currentBar, bar) + liqRow(BT.hour, hour) + liqRow(BT.today, today))
  const mx = today.max
  if (!mx) { lm.className = 'lmax'; setHtml(lm, `<div><span>${BT.todayMaxLiq}</span><b class="num">—</b></div>`) }
  else {
    const short = mx[6] === 1
    lm.className = `lmax ${short ? 's' : 'l'}`
    const dec = OF.api?.dec(c!.sym) ?? 2
    setHtml(lm, `<div><span>${BT.todayMaxLiq}</span><b class="num">${amt(mx[4])}</b></div>` +
      `<div><span class="${short ? 'up' : 'dn'}">${short ? BT.shortLiq : BT.longLiq}</span><span class="num">· ${LIQ_EX[mx[7]] ?? ''}${mx[5] > 0 ? ` ${px(mx[5], dec)}` : ''}</span></div>`)
  }
  const W = Math.floor(lc.clientWidth), H = Math.floor(lc.clientHeight)
  if (!W || H < 24) { setHtml(lc, ''); return }
  const B = pickBucket(from, now, W, LIQ_BUCKETS, 4)
  setHtml(lc, liqSvg({ w: W, h: H, q: liqBuckets(all, from, now, B), hourFrom: now - HOUR, tall, startLabel: '8:00' }))
}

/** 测试 / 脚本看抽屉现在列了哪几根 */
export const drawerRows = (): readonly { t: number; bb: number; bs: number }[] => rows.map(r => ({ t: r.t, bb: r.d.bb, bs: r.d.bs }))
export const drawerLiq = liq
