/* Hkline Web · 主力订单流 · 底部抽屉「大单列表」（2026-10-08 起是摘要，不再逐单一行）
 *
 * 为什么：原来的逐单明细（几千行、六颗筛选胶囊、点表头排序、虚拟滚动、往前翻页）没人真去翻；用户要一眼看到
 * 「这根 / 近 1 小时 / 今天大单是买多还是卖多、落在哪几个价、离最近的墙多远、爆了多少仓」，而且要图文结合、以图为主，
 * 文字只当标注。
 *
 * 四块（横着排，1440 宽时后两块折到第二行）：
 *   1. 汇总：三根「买卖对撞条」（本根 / 近 1 小时 / 今日）——买从中线往上长、卖往下长，三根共用一个开方比例尺
 *      （今日是本根的几十倍，线性比例下本根那根看不见），条宽 26 px、底轨两头全圆（填充短于条宽时是圆角 3 的矮矩形，长过条宽才是圆头），金额贴在条的外端，净额写在中线上；
 *      下面的占比条（现货 / 合约、币安 / OKX / Coinbase，只用浏览器近 1 小时记到的）只有至少两段时才画——
 *      100% 一段的条什么也没说，不画，那一截高度也收回去。
 *   2. 每根：跟着当前周期，最新在上，只列有大单签的那几根（和图上同一套相对档位，见 bigTags.ts）。行里是从中轴往两边长的
 *      镜像条（买向右、卖向左，长度按当前看得见的那几行里最大的那根比），金额放得下（两边各留 6 px）就写在条里，
 *      放不下写在条外、底轨让开那一截；净额是一个色点 + 数字，最大一笔是一颗小胶囊（不知道就空着）。
 *      点一行：图挪到那根并让那枚签亮 1.5 秒；图上点签：这里滚到那一行。活动格子的十字线（含别的格子同步过来的）停在哪根，
 *      这里那一行跟着亮（带一道强调色左边线），不在视野里就滚进来。
 *   3. 价位：近 1 小时大单最集中的买、卖各三档（取法见 summary.priceLevels：浏览器在记的分钟用真实成交价，其余分钟用
 *      服务端的大买 / 大卖 × 那分钟 1 分钟 K 线的典型价；1 分钟 K 线一次取 60 根、每分钟作废一次，图本身是 1 分钟就直接用图上的），
 *      按价格排成一张小价格图（同一档价位既是买前三又是卖前三时并成一行：一根条先涨色后跌色、两个额各按自己的颜色写，
 *      价位标签不重复），现价是一条虚线；最上 / 最下是离现价最近的卖墙 / 买墙胶囊（砖墙记号 · 价 · 额 · 距离），
 *      挂了多久画成一个小时钟弧（满一圈 = 1 小时），不写字。
 *   4. 爆仓：三根对撞条，空头被平往上（涨色）、多头被平往下（跌色），右边一颗「最大一笔」胶囊。数据见 liquidation.ts。
 *
 * 规则：背景透明、块与块之间 1 px 分隔线；块标题 11 px 弱色；数字一律等宽；只用皮肤已有的颜色变量（涨跌色条 85% 不透明、
 * 底轨同色 12%，深色皮肤下 24%——12% 在深底上几乎看不见）；条都用 Canvas / SVG 画，按设备像素比出图；没有数据时画一条淡淡的零线 + 一行 11 px 弱色提示。
 * 只聚合、门槛过滤、展示，不做判定（不写吸筹 / 扫单 / 骗单）。不加任何新的设置项。
 */
import { st, save } from '../app/store'
import { I } from '../ui/dom'
import { GLOSSARY, term } from '../ui/overlay'
import { patchAttr, patchClass, patchStyle, patchText, rowPool } from '../ui/patch'
import { flowOf, ensureHistory, type SymbolFlow } from '../chart/tradeFlow'
import { baseOfSymbol } from './settings'
import { BigBarCache, TierCache, unitFor, ivName, type BarBig } from './bigTags'
import { windows, liveShares, priceLevels, nearestWalls, HOUR, PX_MINUTES, type WinSum, type Wall, type Level, type TypicalAt } from './summary'
import { klines } from '../market'
import { LiqStore, sumLiq, LIQ_EX, type LiqSum } from './liquidation'
import { OF, feedIdleText, amt, hm, mdhm, px, decFor, canvasFont } from './state'

GLOSSARY['爆仓'] = '仓位保证金不够、被交易所强制平掉。这里是币安、OKX 两家按分钟的合计：空头被平往上画、多头被平往下画。币安的强平推送每秒只给一笔，金额是下限。'

const ROW_H = 24
const MAX_ROWS = 200
/** 图上点过的最早那根：列表至少列到它（否则点一枚很早的签，抽屉里找不到那一行） */
let reachT = Infinity
const EX_INITIAL: Record<string, string> = { binance: '币', okx: 'O', coinbase: 'C' }

let slot: HTMLElement | null = null
let list: HTMLElement | null = null
let cvSum: HTMLCanvasElement | null = null
let cvPx: HTMLCanvasElement | null = null
let cvLiq: HTMLCanvasElement | null = null
const liq = new LiqStore()
const cache = new BigBarCache()
const tierCache = new TierCache()
let lastAt = 0
let lastKey = ''
let histSym = ''
let pendingReveal: number | null = null
let raf = 0

interface RowD { t: number; t1: number; d: BarBig; close: number }
let rows: RowD[] = []
let walls: { ask: Wall | null; bid: Wall | null } = { ask: null, bid: null }

const onData = (): void => updateDrawer(true)
liq.onUpdate = onData

export function mountDrawer(el: HTMLElement): void {
  slot = el
  el.innerHTML = `<div class="of-dr-head"><b>大单列表</b><span class="of-dr-sp"></span>
      <button class="ibtn xs" id="ofDrClose" aria-label="收起抽屉" data-tip="收起">${I('close', 'icon-16')}</button></div>
    <div class="of-dr-grid scroll">
      <section class="of-blk of-blk-sum"><h4>汇总</h4><canvas class="of-cv" data-cv="sum" role="img" aria-label="本根、近 1 小时、今日的大单买卖"></canvas></section>
      <section class="of-blk of-blk-bars"><h4 id="ofDrBarsT">每根</h4><div class="of-kr-list scroll" role="list" aria-label="每根 K 线的大单"></div><div class="of-dr-empty faint" hidden></div></section>
      <section class="of-blk of-blk-px"><h4>价位</h4><canvas class="of-cv" data-cv="px" role="img" aria-label="近 1 小时大单最集中的价位与最近的挂墙"></canvas></section>
      <section class="of-blk of-blk-liq"><h4>${term('爆仓')}</h4><canvas class="of-cv" data-cv="liq" role="img" aria-label="本根、近 1 小时、今日的爆仓"></canvas></section>
    </div>`
  list = el.querySelector('.of-kr-list')
  cvSum = el.querySelector('[data-cv="sum"]'); cvPx = el.querySelector('[data-cv="px"]'); cvLiq = el.querySelector('[data-cv="liq"]')
  el.querySelector<HTMLElement>('#ofDrClose')!.onclick = () => { st.slots.drawer = false; save(); OF.api?.layoutSlots() }
  list!.addEventListener('click', onRowClick)
  list!.addEventListener('scroll', () => schedulePaint(), { passive: true })
  cvPx!.addEventListener('click', onPxClick)
  cvPx!.addEventListener('mousemove', e => { cvPx!.style.cursor = wallAt(e) ? 'pointer' : '' })
  if (typeof ResizeObserver !== 'undefined') {
    const ro = new ResizeObserver(() => schedulePaint())
    for (const c of [cvSum!, cvPx!, cvLiq!, list!]) ro.observe(c)
  }
  OF.revealBar = revealBar
  if (!crossBound) { crossBound = true; document.addEventListener('pointermove', onPointer, { passive: true, capture: true }) }
  measureFont = ''
  lastKey = ''
  updateDrawer(true)
}

export function drawerVisible(): boolean { return !!slot && st.slots.drawer && !slot.hidden && slot.isConnected }

// ------------------------------------------------------------------ 数据

interface Ctx { sym: string; f: SymbolFlow; chart: NonNullable<ReturnType<NonNullable<typeof OF.api>['activeChart']>>['chart']; iv: number; unit: number; now: number }

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
  if (key !== lastKey) reachT = Infinity
  lastAt = now; lastKey = key
  if (c) {
    if (histSym !== c.sym) { if (histSym) flowOf(histSym).listeners.delete(onData); histSym = c.sym }
    ensureHistory(c.f, onData, now)
    liq.ensure(baseOfSymbol(c.sym).base, now)
    buildRows(c)
  } else rows = []
  schedulePaint()
}

function buildRows(c: Ctx): void {
  rows = []
  const { chart, f, now } = c
  cache.begin(f, `${c.sym}|${c.iv}`, now)
  const tiers = tierCache.get(cache, f, chart, now, c.unit)
  if (!tiers) return
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
    if (d && Math.max(d.bb, d.bs) >= tiers.t1) rows.push({ t, t1, d, close: bars[i].c })
  }
}

// ---- 十字线同步：活动格子的十字线（自己的或别的格子同步来的）停在哪根，按根表那一行亮。
// 图层的 hover 只在主图窗格、而且只有「十字线只动」的轻量重画不走图层，所以这里跟着指针移动（一帧最多一次）直接读图的状态。
let crossBound = false
let crossRaf = 0
function onPointer(): void {
  if (crossRaf || !drawerVisible() || typeof requestAnimationFrame === 'undefined') return
  crossRaf = requestAnimationFrame(() => { crossRaf = 0; syncCross() })
}
/** 图上十字线所在那根的开盘时间；不在图上 null */
export function crossTime(ch: Pick<Ctx['chart'], 'cross' | 'extCross' | 'bars' | 'xToIndex' | 'indexAt'>): number | null {
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
  OF.crossT = t
  paintRows()
  if (t == null || !list || !list.clientHeight) return
  const i = rows.findIndex(r => r.t === t)
  if (i < 0) return
  const top = i * ROW_H, h = list.clientHeight
  if (top < list.scrollTop) list.scrollTop = top
  else if (top + ROW_H > list.scrollTop + h) list.scrollTop = top + ROW_H - h
}

// ---- 价位用的 1 分钟 K 线：(高 + 低 + 收) / 3。一次取 60 根，每分钟作废一次；图本身是 1 分钟就直接读图上的
const k1 = { sym: '', min: 0, busy: false, typ: new Map<number, number>() }
function typicalFor(c: Ctx): TypicalAt | null {
  if (c.iv === 60_000) {
    const bars = c.chart.bars, m = new Map<number, number>()
    for (let i = bars.length - 1; i >= Math.max(0, bars.length - PX_MINUTES - 1); i--) m.set(bars[i].t, (bars[i].h + bars[i].l + bars[i].c) / 3)
    return t => m.get(t) ?? null
  }
  const min = Math.floor(c.now / 60_000)
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
  const mx = maxOf(r.d)
  a.chart.centerOn(r.t + (r.t1 - r.t) / 2, mx?.price ?? r.close)
  OF.barHi = { symbol: a.symbol.toUpperCase(), t: r.t, until: Date.now() + 1500 }
  a.chart.dirty = true
  paintRows()
  setTimeout(() => paintRows(), 1520)
}

/** 图上点了一枚签：抽屉没开就打开，开着就滚到那一行 */
function revealBar(_sym: string, t: number): void {
  pendingReveal = t
  // 点的是 200 行之外更早的那根：列表一直往回列到它（换品种 / 周期才收回去）
  reachT = Math.min(reachT, t)
  if (!st.slots.drawer) { st.slots.drawer = true; save(); OF.api?.layoutSlots() }
  updateDrawer(true)
  setTimeout(() => paintRows(), 1520)
}

function scrollToPending(): void {
  if (pendingReveal == null || !list || !list.clientHeight) return
  const i = rows.findIndex(r => r.t === pendingReveal)
  pendingReveal = null
  if (i < 0) return
  const top = i * ROW_H, h = list.clientHeight
  if (top < list.scrollTop || top + ROW_H > list.scrollTop + h) list.scrollTop = Math.max(0, top - h / 2 + ROW_H / 2)
}

// ------------------------------------------------------------------ 画

function schedulePaint(): void {
  if (raf || typeof requestAnimationFrame === 'undefined') return
  raf = requestAnimationFrame(() => { raf = 0; paint() })
}

function paint(): void {
  if (!drawerVisible() || !slot) return
  const c = ctxNow()
  const p = pal(slot)
  patchText(slot.querySelector('#ofDrBarsT'), c ? `每根 · ${ivName(c.iv)}` : '每根')
  scrollToPending()
  paintRows()
  paintSum(c, p)
  paintPx(c, p)
  paintLiq(c, p)
}

interface Pal { up: string; down: string; t1: string; t2: string; t3: string; line: string; lineS: string; accent: string; s2: string; dark: boolean; track: number }
/** 颜色的亮度（0–1）；认 #rgb / #rrggbb / rgb()，认不出当亮色 */
export function lum(color: string): number {
  let r = 255, g = 255, b = 255
  const h = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(color.trim())
  if (h) {
    const x = h[1].length === 3 ? h[1].split('').map(c => c + c).join('') : h[1]
    r = parseInt(x.slice(0, 2), 16); g = parseInt(x.slice(2, 4), 16); b = parseInt(x.slice(4, 6), 16)
  } else {
    const m = /rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)/i.exec(color)
    if (m) { r = +m[1]; g = +m[2]; b = +m[3] }
  }
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
}
function pal(el: HTMLElement): Pal {
  const cs = getComputedStyle(el)
  const v = (k: string, d: string): string => cs.getPropertyValue(k).trim() || d
  // 深色皮肤：主文字是亮的。底轨在深底上要更浓才看得见
  const dark = lum(v('--text-1', '#131722')) > 0.5
  return {
    up: v('--up', '#26a69a'), down: v('--down', '#ef5350'), t1: v('--text-1', '#131722'), t2: v('--text-2', '#545B6A'), t3: v('--text-3', '#666B77'),
    line: v('--line', '#E1E4EA'), lineS: v('--line-strong', '#CDD2DB'), accent: v('--accent', '#2B63F0'), s2: v('--surface-2', '#F6F7F9'),
    dark, track: dark ? 0.24 : 0.12,
  }
}

function prep(cv: HTMLCanvasElement | null): { c: CanvasRenderingContext2D; W: number; H: number } | null {
  if (!cv) return null
  const W = cv.clientWidth, H = cv.clientHeight
  if (!W || !H) return null
  const dpr = window.devicePixelRatio || 1
  const bw = Math.round(W * dpr), bh = Math.round(H * dpr)
  if (cv.width !== bw || cv.height !== bh) { cv.width = bw; cv.height = bh }
  const c = cv.getContext('2d')
  if (!c) return null
  c.setTransform(dpr, 0, 0, dpr, 0, 0)
  c.clearRect(0, 0, W, H)
  c.textBaseline = 'middle'
  return { c, W, H }
}

const signed = (v: number): string => v > 0 ? `+${amt(v)}` : v < 0 ? `−${amt(-v)}` : '0'

function rr(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
  r = Math.max(0, Math.min(r, w / 2, h / 2))
  c.beginPath()
  c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r)
  c.closePath()
}

/** 零线 + 一行提示（没有数据时） */
function emptyState(c: CanvasRenderingContext2D, W: number, y: number, p: Pal, hint: string): void {
  c.globalAlpha = 0.6; c.strokeStyle = p.line; c.lineWidth = 1
  c.beginPath(); c.moveTo(8, Math.round(y) + .5); c.lineTo(W - 8, Math.round(y) + .5); c.stroke()
  c.globalAlpha = 1
  if (!hint) return
  c.font = canvasFont(11); c.fillStyle = p.t3; c.textAlign = 'center'
  c.fillText(hint, W / 2, y + 14)
}

interface Col { name: string; sub: string; up: number; down: number }

/** 开方比例尺：v / scale 开方后乘长度。今日常是本根的几十倍，线性下本根只剩一个点 */
export const sqrtLen = (v: number, scale: number, len: number): number => v > 0 && scale > 0 ? Math.sqrt(Math.min(1, v / scale)) * len : 0

/** 对撞条填充长：有数的最短 4 px（不至于缩成看不见的缝），没数为 0 */
export const fillLen = (v: number, scale: number, half: number): number => v > 0 ? Math.max(4, sqrtLen(v, scale, half)) : 0
/** 填充的圆角：长过条宽才是圆头（= 半条宽），短的是圆角 3 的矮矩形 */
export const fillRadius = (len: number, cw: number): number => len > cw ? cw / 2 : 3

/** 三根对撞条：up 从中线往上（涨色）、down 往下（跌色），共用一个开方比例尺；条 26 px 宽、底轨两头全圆，
 *  填充短于条宽时是圆角 3 的矮矩形、长过条宽才是圆头，
 *  底轨同色 12%（深色 24%）、填充 85%，金额贴在填充的外端；中线上写净额（up − down） */
function drawCollide(c: CanvasRenderingContext2D, x0: number, w: number, H: number, cols: Col[], p: Pal): void {
  const LAB = 30, TIP = 14, GAP = 10
  const step = w / cols.length
  const CW = Math.max(12, Math.min(26, Math.round(step * 0.4))), R = CW / 2
  const top = TIP, bottom = H - LAB - TIP
  const mid = Math.round((top + bottom) / 2)
  const half = Math.max(4, (bottom - top) / 2 - GAP)
  const scale = Math.max(1, ...cols.map(k => Math.max(k.up, k.down)))
  c.strokeStyle = p.line; c.lineWidth = 1; c.globalAlpha = 0.7
  c.beginPath(); c.moveTo(x0 + 4, mid + .5); c.lineTo(x0 + w - 4, mid + .5); c.stroke()
  c.globalAlpha = 1
  cols.forEach((k, j) => {
    const cx = Math.round(x0 + step * (j + .5)), x = cx - R
    c.globalAlpha = p.track
    c.fillStyle = p.up; rr(c, x, mid - GAP - half, CW, half, R); c.fill()
    c.fillStyle = p.down; rr(c, x, mid + GAP, CW, half, R); c.fill()
    c.globalAlpha = 0.85
    // 填充短于条宽时画成矮矩形（圆角 3、最矮 4），长过条宽才用圆头——不然短条被圆角画成一颗圆点，像指示灯；
    // 金额仍按「至少一个条宽」的位置写，短条长短变化时数字不跳
    const fu = fillLen(k.up, scale, half), fd = fillLen(k.down, scale, half)
    const lu = k.up > 0 ? Math.max(CW, fu) : 0, ld = k.down > 0 ? Math.max(CW, fd) : 0
    if (fu) { c.fillStyle = p.up; rr(c, x, mid - GAP - fu, CW, fu, fillRadius(fu, CW)); c.fill() }
    if (fd) { c.fillStyle = p.down; rr(c, x, mid + GAP, CW, fd, fillRadius(fd, CW)); c.fill() }
    c.globalAlpha = 1
    c.textAlign = 'center'; c.font = canvasFont(11)
    c.fillStyle = p.t2
    if (k.up > 0) c.fillText(amt(k.up), cx, mid - GAP - lu - 7)
    if (k.down > 0) c.fillText(amt(k.down), cx, mid + GAP + ld + 7)
    const net = k.up - k.down
    c.font = canvasFont(13, 700)
    c.fillStyle = net > 0 ? p.up : net < 0 ? p.down : p.t3
    c.fillText(k.up || k.down ? signed(net) : '0', cx, mid + .5)
    c.font = canvasFont(11); c.fillStyle = p.t2
    c.fillText(k.name, cx, H - LAB + 9)
    if (k.sub) { c.fillStyle = p.t3; c.fillText(k.sub, cx, H - LAB + 23) }
  })
}

interface Seg { v: number; color: string; name: string }
/** 6 px 圆角占比条（段与段之间留 1 px 缝，段上不写字）+ 右边 11 px 图例（太小的段不写）。至少两段才有意义，调用方先筛 */
export const splitWorth = (segs: readonly { v: number }[]): boolean => segs.filter(k => k.v > 0).length >= 2

function drawSplit(c: CanvasRenderingContext2D, x: number, y: number, bw: number, lx: number, lw: number, segs: Seg[], p: Pal): void {
  const tot = segs.reduce((s, k) => s + k.v, 0)
  if (!(tot > 0)) return
  const shown = segs.filter(k => k.v > 0)
  let cx = x
  const avail = bw - (shown.length - 1)
  c.save(); rr(c, x, y - 3, bw, 6, 3); c.clip()
  shown.forEach((k, i) => {
    const w = i === shown.length - 1 ? x + bw - cx : Math.max(1, k.v / tot * avail)
    c.globalAlpha = 0.85; c.fillStyle = k.color; c.fillRect(cx, y - 3, w, 6)
    cx += w + 1
  })
  c.restore(); c.globalAlpha = 1
  c.font = canvasFont(11); c.textAlign = 'left'
  let lxx = lx
  for (const k of segs) {
    const pct = k.v / tot * 100
    if (pct < 3) continue
    const t = `${Math.round(pct)}%`
    const nw = c.measureText(k.name).width, tw = c.measureText(t).width
    if (lxx + 10 + nw + 4 + tw > lx + lw) break
    c.globalAlpha = 0.85; c.fillStyle = k.color; c.beginPath(); c.arc(lxx + 3, y, 3, 0, Math.PI * 2); c.fill(); c.globalAlpha = 1
    c.fillStyle = p.t2; c.fillText(k.name, lxx + 10, y)
    c.fillStyle = p.t1; c.fillText(t, lxx + 10 + nw + 4, y)
    lxx += 10 + nw + 4 + tw + 10
  }
}

function paintSum(cx: Ctx | null, p: Pal): void {
  const g = prep(cvSum)
  if (!g) return
  const { c, W, H } = g
  if (!cx) { emptyState(c, W, H / 2, p, OF.api?.activeChart()?.symbol.toUpperCase() === 'DXY' ? '美元指数没有成交明细' : feedIdleText()); return }
  // 占比条：至少两段才画（100% 一段什么也没说），一条都没有就把那一截高度收回去
  const sh = liveShares(cx.f, cx.now)
  const splits: Seg[][] = sh ? [
    [{ v: sh.spot, color: p.accent, name: '现货' }, { v: sh.contract, color: p.t3, name: '合约' }],
    [{ v: sh.ex[0], color: p.accent, name: '币安' }, { v: sh.ex[1], color: p.t2, name: 'OKX' }, { v: sh.ex[2], color: p.lineS, name: 'Coinbase' }],
  ].filter(splitWorth) : []
  const SPLIT = splits.length ? 12 + splits.length * 20 : 0
  const bars = cx.chart.bars
  const t0 = bars[bars.length - 1].t, t1 = cx.chart.timeAt(bars.length)
  const w = windows(cx.f, t0, t1, cx.now)
  const cnt = (s: WinSum): string => s.bn != null && s.sn != null && s.bn + s.sn > 0 ? `${s.bn + s.sn} 笔` : ''
  const cols: Col[] = [
    { name: '本根', sub: cnt(w.bar), up: w.bar.bb, down: w.bar.bs },
    { name: '近 1 小时', sub: cnt(w.hour), up: w.hour.bb, down: w.hour.bs },
    { name: '今日', sub: cnt(w.today), up: w.today.bb, down: w.today.bs },
  ]
  if (!w.today.has && !w.hour.has && !w.bar.has) emptyState(c, W, (H - SPLIT) / 2, p, OF.feed ? '还没有大单' : feedIdleText())
  else drawCollide(c, 0, W, H - SPLIT, cols, p)
  if (!SPLIT) return
  const bw = Math.max(60, Math.round(W * 0.34)), lx = bw + 12, lw = W - lx
  c.strokeStyle = p.line; c.lineWidth = 1; c.beginPath(); c.moveTo(0, H - SPLIT + .5); c.lineTo(W, H - SPLIT + .5); c.stroke()
  splits.forEach((segs, i) => drawSplit(c, 0, H - SPLIT + 12 + i * 20, bw, lx, lw, segs, p))
}

/** 每行的金额文字宽，用来决定写在条里还是条外。字体照行里 SVG 文字实际算出来的样式量（不是猜的 canvasFont） */
let measureCtx: CanvasRenderingContext2D | null = null
let measureFont = ''
function textW(t: string, probe: Element): number {
  if (!t) return 0
  if (!measureCtx) measureCtx = document.createElement('canvas').getContext('2d')
  if (!measureCtx) return t.length * 7
  if (!measureFont) { const cs = getComputedStyle(probe); measureFont = `${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}` }
  measureCtx.font = measureFont
  return measureCtx.measureText(t).width
}
/** 条内金额两边各留的空 */
const IN_PAD = 6

const ROW_TPL = `<div class="of-kr" role="listitem" tabindex="-1"><span class="of-kr-t num"></span>` +
  `<svg class="of-kr-bar" height="16" aria-hidden="true"><line class="ax" x1="0" x2="0" y1="1" y2="15"></line>` +
  `<rect class="tk b" y="7" height="2" rx="1"></rect><rect class="tk s" y="7" height="2" rx="1"></rect>` +
  `<rect class="br b" y="3" height="10" rx="2"></rect><rect class="br s" y="3" height="10" rx="2"></rect>` +
  `<text class="tx b" y="8.5"></text><text class="tx s" y="8.5"></text></svg>` +
  `<span class="of-kr-net num"><i></i><b></b></span><span class="of-kr-max"><em></em><b class="num"></b></span></div>`

const maxOf = (d: BarBig): { usd: number; price: number; exchange: string; buy: boolean } | null => {
  const b = d.bmax, s = d.smax
  if (!b && !s) return null
  const m = b && (!s || b.usd >= s.usd) ? b : s!
  return { usd: m.usd, price: m.price, exchange: m.exchange, buy: m === b }
}

function paintRows(): void {
  if (!list || !slot) return
  const empty = slot.querySelector<HTMLElement>('.of-dr-empty')!
  const c = OF.api?.activeChart()
  const els = rowPool(list, rows.length, ROW_TPL)
  if (!rows.length) {
    empty.hidden = false
    patchText(empty, !c ? '' : c.symbol.toUpperCase() === 'DXY' ? '美元指数没有成交明细' : OF.feed || flowOf(c.symbol).srv.tracked ? '最近还没有够得上大单签的 K 线' : feedIdleText())
    return
  }
  empty.hidden = true
  const svg = els[0].querySelector('svg')!
  const bw = svg.getBoundingClientRect().width || 200
  const mid = Math.round(bw / 2), half = Math.max(10, mid - 2)
  // 比例：当前看得见的那几行里最大的那根
  const i0 = Math.max(0, Math.floor(list.scrollTop / ROW_H)), i1 = Math.min(rows.length, Math.ceil((list.scrollTop + list.clientHeight) / ROW_H) + 1)
  let mx = 1
  for (let i = i0; i < i1; i++) mx = Math.max(mx, rows[i].d.bb, rows[i].d.bs)
  const now = Date.now()
  const sym = c?.symbol.toUpperCase() ?? ''
  const hi = OF.barHi && OF.barHi.symbol === sym && OF.barHi.until > now ? OF.barHi.t : null
  const today = mdhm(now).slice(0, 5)
  const dec = c ? decFor(OF.feed?.model.scheme?.step ?? 0, OF.api?.dec(sym) ?? 2) : 2
  els.forEach((el, k) => {
    const r = rows[k], d = r.d
    patchAttr(el, 'data-t', String(r.t))
    patchClass(el, `of-kr${k === 0 ? ' new' : ''}${hi === r.t ? ' sel' : ''}${OF.crossT === r.t ? ' x' : ''}`)
    const s = mdhm(r.t)
    patchText(el.children[0], r.t1 - r.t >= 86_400_000 ? s.slice(0, 5) : s.slice(0, 5) === today ? hm(r.t) : s)
    const ax = svg === el.querySelector('svg') ? svg : el.querySelector('svg')!
    const q = (sel: string): Element => ax.querySelector(sel)!
    patchAttr(q('.ax'), 'x1', String(mid + .5)); patchAttr(q('.ax'), 'x2', String(mid + .5))
    const lb = d.bb / mx * half, ls = d.bs / mx * half
    const xb = q('.tx.b'), xs = q('.tx.s')
    const tb = d.bb > 0 ? amt(d.bb) : '', ts = d.bs > 0 ? amt(d.bs) : ''
    const wb = textW(tb, xb), ws = textW(ts, xs)
    // 放得下（两边各留 IN_PAD）才写在条里；写在条外时底轨从文字后面开始，不从字中间穿过去
    const inB = wb + IN_PAD * 2 <= lb, inS = ws + IN_PAD * 2 <= ls
    const gb = tb && !inB ? Math.min(half, lb + 4 + wb + 4) : 0, gs = ts && !inS ? Math.min(half, ls + 4 + ws + 4) : 0
    patchAttr(q('.tk.b'), 'x', String(mid + 1 + gb)); patchAttr(q('.tk.b'), 'width', String(Math.max(0, half - gb)))
    patchAttr(q('.tk.s'), 'x', String(mid - half)); patchAttr(q('.tk.s'), 'width', String(Math.max(0, half - gs)))
    patchAttr(q('.br.b'), 'x', String(mid + 1)); patchAttr(q('.br.b'), 'width', String(half)); patchStyle(q('.br.b'), 'transform', `scaleX(${(lb / half).toFixed(4)})`)
    patchAttr(q('.br.s'), 'x', String(mid - half)); patchAttr(q('.br.s'), 'width', String(half)); patchStyle(q('.br.s'), 'transform', `scaleX(${(ls / half).toFixed(4)})`)
    patchText(xb, tb); patchClass(xb, `tx b${inB ? ' in' : ''}`)
    patchAttr(xb, 'x', String(inB ? mid + 1 + lb - IN_PAD : mid + 1 + lb + 4)); patchAttr(xb, 'text-anchor', inB ? 'end' : 'start')
    patchText(xs, ts); patchClass(xs, `tx s${inS ? ' in' : ''}`)
    patchAttr(xs, 'x', String(inS ? mid - ls + IN_PAD : mid - ls - 4)); patchAttr(xs, 'text-anchor', inS ? 'start' : 'end')
    const net = d.bb - d.bs
    const ne = el.children[2]
    patchClass(ne.firstElementChild, net > 0 ? 'up' : net < 0 ? 'down' : '')
    patchText(ne.lastElementChild, signed(net))
    const m = maxOf(d), pe = el.children[3]
    patchClass(pe, `of-kr-max${m ? '' : ' none'}`)
    patchAttr(pe, 'title', m ? `最大一笔 ${amt(m.usd)} · ${m.buy ? '买' : '卖'} · ${px(m.price, dec)}` : null)
    patchText(pe.firstElementChild, m ? EX_INITIAL[m.exchange] ?? m.exchange.slice(0, 1).toUpperCase() : '')
    patchClass(pe.firstElementChild, m ? (m.buy ? 'up' : 'down') : '')
    patchText(pe.lastElementChild, m ? amt(m.usd) : '')
  })
}

// ---- 价位

let wallHits: { y0: number; y1: number; w: Wall }[] = []
function wallAt(e: MouseEvent): Wall | null {
  if (!cvPx) return null
  const r = cvPx.getBoundingClientRect(), y = e.clientY - r.top
  return wallHits.find(h => y >= h.y0 && y <= h.y1)?.w ?? null
}
function onPxClick(e: MouseEvent): void {
  const w = wallAt(e)
  if (w) OF.focus?.(w.first)
}

/** 三块砖：下面两块、上面一块居中 */
function bricks(c: CanvasRenderingContext2D, x: number, y: number, color: string): void {
  c.fillStyle = color
  c.fillRect(x, y + 5, 5, 4); c.fillRect(x + 6, y + 5, 5, 4); c.fillRect(x + 3, y, 5, 4)
}

/** 挂了多久：满一圈 = 1 小时 */
function clockArc(c: CanvasRenderingContext2D, x: number, y: number, age: number, color: string, p: Pal): void {
  const r = 5.5
  c.lineWidth = 1.5
  c.strokeStyle = p.line; c.beginPath(); c.arc(x, y, r, 0, Math.PI * 2); c.stroke()
  const f = Math.max(0.04, Math.min(1, age / HOUR))
  c.strokeStyle = color; c.beginPath(); c.arc(x, y, r, -Math.PI / 2, -Math.PI / 2 + f * Math.PI * 2); c.stroke()
}

function wallPill(c: CanvasRenderingContext2D, y: number, W: number, w: Wall | null, ask: boolean, mid: number, dec: number, now: number, p: Pal): void {
  const col = ask ? p.down : p.up, H = 22
  rr(c, .5, y + .5, W - 1, H - 1, H / 2)
  if (w) { c.globalAlpha = 0.12; c.fillStyle = col; c.fill(); c.globalAlpha = 0.45; c.strokeStyle = col; c.lineWidth = 1; c.stroke(); c.globalAlpha = 1 }
  else { c.strokeStyle = p.line; c.lineWidth = 1; c.stroke() }
  bricks(c, 10, y + 6, w ? col : p.t3)
  c.textAlign = 'left'; c.font = canvasFont(11)
  if (!w) { c.fillStyle = p.t3; c.fillText('—', 28, y + H / 2 + .5); return }
  const dist = mid > 0 ? (w.price - mid) / mid * 100 : 0
  const parts: [string, string, number][] = [[px(w.price, dec), p.t1, 600], [amt(w.usd), p.t1, 400], [`${dist >= 0 ? '+' : '−'}${Math.abs(dist).toFixed(2)}%`, p.t2, 400]]
  let x = 28
  parts.forEach(([t, color, wt], i) => {
    if (i) { c.fillStyle = p.t3; c.font = canvasFont(11); c.fillText('·', x, y + H / 2 + .5); x += 9 }
    c.font = canvasFont(11, wt); c.fillStyle = color
    c.fillText(t, x, y + H / 2 + .5); x += c.measureText(t).width + 5
  })
  clockArc(c, W - 14, y + H / 2, now - w.since, col, p)
}

function paintPx(cx: Ctx | null, p: Pal): void {
  const g = prep(cvPx)
  wallHits = []
  if (!g) return
  const { c, W, H } = g
  const live = !!cx && OF.feed?.symbol === cx.sym && !!OF.snap
  if (!cx || !live) { emptyState(c, W, H / 2, p, cx ? feedIdleText() : ''); return }
  const step = OF.feed!.model.scheme?.step ?? 0
  const mid = OF.fine?.mid ?? cx.chart.bars[cx.chart.bars.length - 1].c
  const dec = decFor(step, OF.api?.dec(cx.sym) ?? 2)
  walls = nearestWalls(OF.snap!.orders, mid)
  const PH = 22
  wallPill(c, 0, W, walls.ask, true, mid, dec, cx.now, p); wallHits.push({ y0: 0, y1: PH, w: walls.ask! })
  wallPill(c, H - PH, W, walls.bid, false, mid, dec, cx.now, p); wallHits.push({ y0: H - PH, y1: H, w: walls.bid! })
  wallHits = wallHits.filter(h => h.w)
  const { buy, sell } = priceLevels(cx.f, step, cx.now, typicalFor(cx))
  const top = PH + 8, bot = H - PH - 8
  if (!buy.length && !sell.length) { emptyState(c, W, (top + bot) / 2, p, '近 1 小时还没有大单'); return }
  const lv: (PxRow | null)[] = pxRows(buy, sell)
  // 现价那一行插在价格顺序里
  let at = lv.findIndex(l => l!.price < mid)
  if (at < 0) at = lv.length
  lv.splice(at, 0, null)
  const rowH = Math.min(22, (bot - top) / lv.length)
  const y0 = top + ((bot - top) - rowH * lv.length) / 2
  c.font = canvasFont(11)
  const labW = Math.max(...lv.map(l => c.measureText(px(l ? l.price : mid, dec)).width)) + 8
  const mxUsd = Math.max(1, ...lv.map(l => l ? l.buy + l.sell : 0))
  const amtW = Math.max(44, ...lv.map(l => l && l.buy && l.sell ? c.measureText(`${amt(l.buy)} ${amt(l.sell)}`).width + 8 : 0))
  const bx = labW + 4, bw = Math.max(20, W - bx - amtW)
  lv.forEach((l, i) => {
    const y = Math.round(y0 + rowH * (i + .5))
    c.textAlign = 'right'
    if (!l) {
      c.setLineDash([3, 3]); c.strokeStyle = p.t3; c.lineWidth = 1
      c.beginPath(); c.moveTo(bx, y + .5); c.lineTo(W, y + .5); c.stroke(); c.setLineDash([])
      c.font = canvasFont(11, 600); c.fillStyle = p.t1; c.fillText(px(mid, dec), labW, y + .5)
      return
    }
    c.font = canvasFont(11); c.fillStyle = p.t2; c.fillText(px(l.price, dec), labW, y + .5)
    c.globalAlpha = p.dark ? 0.32 : 0.2; c.fillStyle = l.buy >= l.sell ? p.up : p.down; rr(c, bx, y - 1, bw, 2, 1); c.fill()
    // 并成一行的：一根条，买的一截（涨色）在前、卖的一截（跌色）接着
    const lb = l.buy ? Math.max(2, l.buy / mxUsd * bw) : 0, ls = l.sell ? Math.max(2, l.sell / mxUsd * bw) : 0
    c.globalAlpha = 0.85
    if (lb && ls) {
      c.fillStyle = p.up; rr(c, bx, y - 4, lb, 8, 2); c.fill(); c.fillRect(bx + lb - 2, y - 4, 2, 8)
      c.fillStyle = p.down; rr(c, bx + lb, y - 4, ls, 8, 2); c.fill(); c.fillRect(bx + lb, y - 4, 2, 8)
    } else { c.fillStyle = lb ? p.up : p.down; rr(c, bx, y - 4, lb || ls, 8, 2); c.fill() }
    c.globalAlpha = 1
    c.textAlign = 'left'
    let tx = bx + lb + ls + 5
    if (lb && ls) { c.fillStyle = p.up; c.fillText(amt(l.buy), tx, y + .5); tx += c.measureText(amt(l.buy) + ' ').width; c.fillStyle = p.down; c.fillText(amt(l.sell), tx, y + .5) }
    else { c.fillStyle = p.t2; c.fillText(amt(lb ? l.buy : l.sell), tx, y + .5) }
  })
}

/** 价位块的一行：同一档价位的买、卖并在一起（只在一侧前三的那一侧是 0） */
export interface PxRow { price: number; buy: number; sell: number }
export function pxRows(buy: readonly Level[], sell: readonly Level[]): PxRow[] {
  const m = new Map<number, PxRow>()
  const key = (v: number): number => Math.round(v * 1e8)
  for (const l of buy) { const k = key(l.price); const r = m.get(k) ?? { price: l.price, buy: 0, sell: 0 }; r.buy += l.usd; m.set(k, r) }
  for (const l of sell) { const k = key(l.price); const r = m.get(k) ?? { price: l.price, buy: 0, sell: 0 }; r.sell += l.usd; m.set(k, r) }
  return [...m.values()].sort((a, b) => b.price - a.price)
}

// ---- 爆仓

function paintLiq(cx: Ctx | null, p: Pal): void {
  const g = prep(cvLiq)
  if (!g) return
  const { c, W, H } = g
  if (!cx) { emptyState(c, W, H / 2, p, ''); return }
  const s = liq.state(baseOfSymbol(cx.sym).base)
  if (!s) { emptyState(c, W, H / 2, p, ''); return }
  if (!s.rows.size) { emptyState(c, W, H / 2 - 15, p, s.tracked == null ? '' : '这只品种暂无爆仓数据'); return }
  const bars = cx.chart.bars
  const t0 = bars[bars.length - 1].t, t1 = cx.chart.timeAt(bars.length)
  const now = cx.now
  // 本根按分钟算：起点往下取整到分钟（秒级周期就是正在走的这一分钟）
  const m0 = Math.floor(t0 / 60_000) * 60_000
  const day = Math.floor((now + 8 * HOUR) / 86_400_000) * 86_400_000 - 8 * HOUR
  const ws: [string, LiqSum][] = [['本根', sumLiq(s.rows.values(), m0, Math.max(t1, m0 + 60_000))], ['近 1 小时', sumLiq(s.rows.values(), Math.floor((now - HOUR) / 60_000) * 60_000, now + 1)], ['今日', sumLiq(s.rows.values(), day, now + 1)]]
  const RW = Math.min(150, Math.round(W * 0.42))
  drawCollide(c, 0, W - RW - 8, H, ws.map(([name, v]) => ({ name, sub: v.n > 0 ? `${v.n} 笔` : '', up: v.short, down: v.long })), p)
  // 右边：今日最大一笔
  const mx = ws[2][1].max
  const x = W - RW
  c.textAlign = 'left'; c.font = canvasFont(11); c.fillStyle = p.t3
  const ty = Math.round(H / 2 - 30)
  c.fillText('今日最大一笔', x, ty)
  const py = ty + 12, ph = 40
  rr(c, x + .5, py + .5, RW - 1, ph - 1, 10)
  c.strokeStyle = p.line; c.lineWidth = 1; c.stroke()
  if (!mx) { c.fillStyle = p.t3; c.fillText('—', x + 12, py + ph / 2); return }
  const shortSide = mx[6] === 1, col = shortSide ? p.up : p.down
  c.fillStyle = col; c.beginPath(); c.arc(x + 13, py + 13, 3.5, 0, Math.PI * 2); c.fill()
  c.font = canvasFont(13, 700); c.fillStyle = p.t1; c.fillText(amt(mx[4]), x + 22, py + 13.5)
  const aw = c.measureText(amt(mx[4])).width
  c.font = canvasFont(11); c.fillStyle = col; c.fillText(shortSide ? '空头被平' : '多头被平', x + 22 + aw + 6, py + 13.5)
  const dec = OF.api?.dec(cx.sym) ?? 2
  c.fillStyle = p.t2; c.fillText(`${LIQ_EX[mx[7]] ?? ''}${mx[5] > 0 ? ` · ${px(mx[5], dec)}` : ''}`, x + 12, py + 29)
}

/** 测试 / 脚本看抽屉现在列了哪几根 */
export const drawerRows = (): readonly { t: number; bb: number; bs: number }[] => rows.map(r => ({ t: r.t, bb: r.d.bb, bs: r.d.bs }))
export const drawerLiq = liq
