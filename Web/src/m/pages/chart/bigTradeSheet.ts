/* Hkline 手机网页 · 盘口洞察全屏页。
 * 固定顶栏、100dvh纵向正文、主图同所挂单与真实成交价区、独立爆仓；逐根读数收进页末证据。
 * 返回沿用系统返回栈，门槛编辑时保留现场，更新不替换焦点或折叠展开的依据。
 * 这里只管 DOM；数据与请求生命周期在 bigTrade.ts / insights.ts。
 */
import { el, esc, layer, reducedMotion, setHTML, setText, pressGate } from '../../ui/dom'
import { icon } from '../../ui/icons'
import { pushLayer } from '../../ui/sheet'
import { liuliBackdropHTML } from '../../ui/liuli'
import { orderFlowAmount } from '../../chart/renderer.orderflow'
import type { WinSum, Level, Wall } from '../../../orderflow/summary'
import type { LiqSum, LiqRow } from '../../../orderflow/liquidation'
import { LIQ_EX } from '../../../orderflow/liquidation'
import { BT, fill } from '../../../terms'
import { INSIGHT as L } from './insightLabels'
import type { InsightView, InsightSection } from './insights'
import '../../styles/bigTrade.css'

/** 保留旧测试调用口；实际页面高度由 CSS 100dvh 管理。 */
export const SHEET_H = 780
/** 历史弹层兼容常量；全屏正文不再拦截下滑。 */
export const CLOSE_PX = 110
/** 开弹层后吞掉补发 click 的时长（毫秒） */
const GHOST_MS = 400

const fmt = orderFlowAmount
const MINUS = '−'

// ───────────────────────────── 模型

export interface HeroModel {
  /** 「本根」/「该根 12:30」 */
  title: string
  /** 标题前那颗呼吸点（看的是正在走的这根） */
  live: boolean
  /** 右上小字：「15 分钟 · 还在走」/「抬手回到本根」/「数据停在 12:31」 */
  rt: string
  bar: WinSum
  hour: WinSum
  today: WinSum
  /** 服务端不跟这只：只算打开以后的成交 */
  untracked: boolean
}

export interface LiqModel {
  /** loading = 第一次还在取；none = 这只没有爆仓数据；data = 有（可能全是 0） */
  state: 'loading' | 'none' | 'data'
  hour: LiqSum
  today: LiqSum
  day: LiqSum
  /** 24 小时、每格 15 分钟：[多头爆仓额, 空头爆仓额]，最早的在前 */
  cells: [number, number][]
  /** 第一格的时刻（「昨天 12:30」） */
  from: string
  /** 今日最大一笔：时刻文字 + 价格文字 */
  maxWhen: string
  maxPrice: string
  /** 正在看的那根落在第几格（没有 -1） */
  selCell: number
}

export interface BarCol { t: number; bb: number; bs: number; label: string }

export interface LadderRow {
  price: string
  now: boolean
  buy: number
  sell: number
  /** 0…100 */
  bw: number
  sw: number
  bidWall: number | null
  askWall: number | null
}

export interface BtModel {
  /** 副标题全称（读屏念它） */
  sub: string
  /** 副标题从长到短的几种写法：弹层挑第一种一行放得下的 */
  subs: string[]
  loading: boolean
  stale: boolean
  hero: HeroModel
  /** null = 现货：爆仓整块不出现 */
  liq: LiqModel | null
  bars: BarCol[]
  /** 每根里正在看的那根（时间） */
  sel: number | null
  ladder: LadderRow[] | null
  thr: string
  insights?: InsightView
}

// ───────────────────────────── 纯函数（测试直接测）

const share = (b: number, s: number): number => (b + s > 0 ? b / (b + s) : 0.5)

/** 「净买入 +3.3M」/「净卖出 −1.2M」 */
export function netText(net: number): string {
  return net >= 0 ? `${BT.netBuy} +${fmt(net)}` : `${BT.netSell} ${MINUS}${fmt(-net)}`
}

/** 分析面板那一行的小字：本根净买 / 净卖，还没大单就说没有 */
export function summaryLine(bar: WinSum | null): string {
  if (!bar || bar.bb + bar.bs <= 0) return BT.currentNoBigTrade
  return `${BT.currentBar} ${netText(bar.bb - bar.bs)}`
}

/** 往上取一个好看的步长：1 / 2 / 2.5 / 5 × 10^k */
export function niceStep(x: number): number {
  if (!(x > 0) || !Number.isFinite(x)) return 1
  const p = Math.pow(10, Math.floor(Math.log10(x)))
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= x * (1 - 1e-9)) return m * p
  return 10 * p
}
const decimalsOf = (x: number): number => {
  const s = x.toFixed(10).replace(/0+$/, '')
  const i = s.indexOf('.')
  return i < 0 ? 0 : s.length - i - 1
}

/** 价位梯的时间窗：近 2 小时（与 iOS BigTradeDigest.ladderWindowMs、定版原型同） */
export const LADDER_HOURS = 2

/** 价位梯：现价上下五档（11 行）。行距按近 2 小时大单落的价位自适应（盖住最远那一档），不小于订单流步长 */
export function ladderRows(lv: { buy: Level[]; sell: Level[] }, mid: number, step: number, walls: { ask: Wall | null; bid: Wall | null }): LadderRow[] {
  if (!(mid > 0)) return []
  let far = 0
  for (const l of [...lv.buy, ...lv.sell]) far = Math.max(far, Math.abs(l.price - mid))
  for (const w of [walls.ask, walls.bid]) if (w && Math.abs(w.price - mid) <= mid * 0.05) far = Math.max(far, Math.abs(w.price - mid))
  const row = niceStep(Math.max(far / 5, step > 0 ? step : 0, far > 0 ? 0 : mid * 0.001))
  const center = Math.round(mid / row) * row
  const k = (p: number): number => Math.max(-5, Math.min(5, Math.round((p - center) / row)))
  const buy = new Array<number>(11).fill(0), sell = new Array<number>(11).fill(0)
  for (const l of lv.buy) buy[5 - k(l.price)] += l.usd
  for (const l of lv.sell) sell[5 - k(l.price)] += l.usd
  let mx = 0
  for (let i = 0; i < 11; i++) mx = Math.max(mx, buy[i], sell[i])
  const pct = (v: number): number => (v > 0 && mx > 0 ? Math.max(2, Math.min(100, (v / mx) * 100)) : 0)
  const dec = decimalsOf(row)
  const out: LadderRow[] = []
  for (let i = 0; i < 11; i++) {
    const kk = 5 - i
    out.push({
      price: (center + kk * row).toFixed(dec), now: kk === 0, buy: buy[i], sell: sell[i], bw: pct(buy[i]), sw: pct(sell[i]),
      bidWall: walls.bid && k(walls.bid.price) === kk ? walls.bid.usd : null,
      askWall: walls.ask && k(walls.ask.price) === kk ? walls.ask.usd : null,
    })
  }
  return out
}

/** 24 小时爆仓的 96 格（每格 15 分钟，最后一格含现在） */
export const LIQ_CELL_MS = 15 * 60_000
export const LIQ_CELLS = 96
export function liqCells(rows: Iterable<LiqRow>, now: number): { start: number; cells: [number, number][] } {
  const last = Math.floor(now / LIQ_CELL_MS) * LIQ_CELL_MS
  const start = last - (LIQ_CELLS - 1) * LIQ_CELL_MS
  const cells: [number, number][] = Array.from({ length: LIQ_CELLS }, () => [0, 0])
  for (const r of rows) {
    const i = Math.floor((r[0] - start) / LIQ_CELL_MS)
    if (i < 0 || i >= LIQ_CELLS) continue
    cells[i][0] += r[1]; cells[i][1] += r[2]
  }
  return { start, cells }
}

// ───────────────────────────── 片段

const skel = (style: string): string => `<span class="bt-skel" style="${style}"></span>`

function heroSkelHTML(): string {
  return `<div class="bt-card bt-hero"><h5>${BT.currentBar}<span class="rt"></span></h5>
    <div class="bt-amts">${skel('width:88px;height:22px')}${skel('width:88px;height:22px')}</div>
    <div class="bt-vs bt-skel" style="margin-top:12px"></div>
    <div class="bt-rows"><span class="lab">${BT.hour}</span><div class="bt-vs s bt-skel"></div><span class="lab">${BT.today}</span><div class="bt-vs s bt-skel"></div></div></div>`
}

function vsHTML(b: number, s: number, small: boolean): string {
  const k = share(b, s), gap = small ? 1 : 2
  const has = b + s > 0
  return `<div class="bt-vs${small ? ' s' : ''}"><div class="b" style="width:${has ? `calc(${(k * 100).toFixed(1)}% - ${gap}px)` : '0'}"></div><div class="a" style="width:${has ? `calc(${((1 - k) * 100).toFixed(1)}% - ${gap}px)` : '0'}"></div></div>`
}

export function liqCardHTML(m: LiqModel | null): string {
  if (!m) return ''
  if (m.state === 'loading') return `<div class="bt-card thin"><h5>${BT.liq}</h5><div class="bt-vs s bt-skel" style="margin:4px 0 10px"></div>${skel('display:block;height:14px;width:60%')}</div>`
  if (m.state === 'none') return `<div class="bt-card thin"><h5>${BT.liq}</h5><div class="bt-empty"><b>${BT.noLiqData}</b></div></div>`
  if (m.today.long + m.today.short <= 0) return `<div class="bt-card thin" data-liq="empty"><h5>${BT.liq}<span class="rt">${BT.hour}</span></h5><div class="bt-empty"><b>${BT.noLiqToday}</b></div></div>`
  const h = m.hour
  const mx = m.today.max
  const maxLine = mx
    ? `<span>${BT.todayMaxLiq} <b class="${mx[6] === 0 ? 'down' : 'up'}">${mx[6] === 0 ? BT.long : BT.short} ${esc(fmt(mx[4]))}</b> @ ${esc(m.maxPrice)} · ${esc(m.maxWhen)}</span>`
    : '<span></span>'
  return `<div class="bt-card thin" data-liq="data"><h5>${BT.liq}<span class="rt">${BT.hour}</span></h5>
    ${vsHTML(h.short, h.long, true).replace('class="bt-vs s"', 'class="bt-vs s liq"')}
    <div class="bt-ends"><b class="up">${BT.shortLiq} ${esc(fmt(h.short))}</b><span></span><b class="down">${BT.longLiq} ${esc(fmt(h.long))}</b></div>
    <div class="bt-mini">${maxLine}<span>${BT.day} ${BT.long} <b>${esc(fmt(m.day.long))}</b> · ${BT.short} <b>${esc(fmt(m.day.short))}</b></span></div></div>`
}

export function barsCardHTML(bars: BarCol[], sel: number | null, flash: number | null): string {
  if (!bars.length) return ''
  let mx = 0
  for (const b of bars) mx = Math.max(mx, b.bb, b.bs)
  if (!(mx > 0)) mx = 1
  const W = bars.length * 8
  let sv = `<svg class="bt-cols" width="${W}" height="96" viewBox="0 0 ${W} 96" role="img" aria-label="${fill(BT.barsA11y, { n: bars.length })}">`
  sv += `<line class="bt-mid" x1="0" x2="${W}" y1="48" y2="48"/>`
  bars.forEach((b, i) => {
    const x = i * 8, hb = (b.bb / mx) * 44, hs = (b.bs / mx) * 44
    const on = b.t === sel
    sv += `<g data-t="${b.t}"${on ? ' class="on"' : ''}${b.t === flash ? ' data-flash="1"' : ''}>`
      + `<rect class="bt-hit" x="${x}" y="0" width="8" height="96"/>`
      + (hb > 0 ? `<rect class="bt-u" x="${x}" y="${(48 - hb).toFixed(1)}" width="7" height="${hb.toFixed(1)}" rx="1.5"/>` : '')
      + (hs > 0 ? `<rect class="bt-d" x="${x}" y="48" width="7" height="${hs.toFixed(1)}" rx="1.5"/>` : '')
      + (on ? `<rect class="bt-sel" x="${x - 2}" y="1" width="11" height="94" rx="4"/>` : '')
      + '</g>'
    if (i === bars.length - 1) sv += `<circle class="bt-breath" cx="${x + 3.5}" cy="4" r="2.5"/>`
  })
  sv += '</svg>'
  const mid = bars[Math.floor((bars.length - 1) / 2)]
  return `<div class="bt-card" data-card="bars"><h5>${BT.perBar}<span class="rt">${fill(BT.recentBars, { n: bars.length })}</span></h5>
    <div class="bt-scroll">${sv}</div>
    <div class="bt-mini"><span>${esc(bars[0].label)}</span><span>${esc(mid.label)}</span><span>${esc(bars[bars.length - 1].label)}</span></div></div>`
}

export function ladderCardHTML(rows: LadderRow[] | null): string {
  if (!rows || !rows.length) return ''
  // 条最长占这一侧的 62%：金额字贴在条外头，最长那条的字也不出卡片
  // 有量但条很短（不到 3%，约 4px）时不缩成细线：画成最窄 4px、圆角 3 的矮矩形（照网页版）
  const side = (cls: 'bl' | 'br', w0: number, v: number, wall: number | null, w = w0 * 0.62): string => {
    const tiny = v > 0 && w < 3
    const ww = v > 0 ? `max(4px,${w.toFixed(1)}%)` : '0%'
    return `<div class="${cls}" style="--w:${ww}"><i${tiny ? ' class="tiny"' : ''} style="width:${ww}"></i>${wall != null ? `<span class="wall">${cls === 'bl' ? BT.buyWall : BT.sellWall} ${esc(fmt(wall))}</span>` : w0 > 6 ? `<s>${esc(fmt(v))}</s>` : ''}</div>`
  }
  return `<div class="bt-card" data-card="ladder"><h5>${BT.levels}<span class="rt">${fill(BT.levelsRange, { h: LADDER_HOURS })}</span></h5><div class="bt-ladder">${rows.map(r =>
    side('bl', r.bw, r.buy, r.bidWall) + `<div class="p${r.now ? ' now' : ''}">${esc(r.price)}</div>` + side('br', r.sw, r.sell, r.askWall)).join('')}</div></div>`
}

export function liqDayCardHTML(m: LiqModel | null): string {
  if (!m || m.state !== 'data') return ''
  let mx = 0
  for (const [a, b] of m.cells) mx = Math.max(mx, a, b)
  if (!(mx > 0)) mx = 1
  let sv = '<svg class="bt-liq24" width="330" height="64" viewBox="0 0 330 64" role="img" aria-label="${BT.liqDayA11y}"><line class="bt-mid" x1="0" x2="330" y1="32" y2="32"/>'
  m.cells.forEach(([lo, sh], i) => {
    const x = (i * 3.4).toFixed(1), a = (lo / mx) * 28, c = (sh / mx) * 28
    if (c > 0) sv += `<rect class="bt-u" x="${x}" y="${(32 - c).toFixed(1)}" width="2.4" height="${c.toFixed(1)}"/>`
    if (a > 0) sv += `<rect class="bt-d" x="${x}" y="32" width="2.4" height="${a.toFixed(1)}"/>`
  })
  if (m.selCell >= 0) sv += `<rect class="bt-sel" x="${(m.selCell * 3.4 - 1).toFixed(1)}" y="2" width="4.4" height="60" rx="2"/>`
  sv += '</svg>'
  const mx1 = m.today.max
  const max = mx1 ? `<div class="bt-liqmax"><span class="ic ${mx1[6] === 0 ? 'down' : 'up'}">${mx1[6] === 0 ? BT.longMark : BT.shortMark}</span>
    <span class="t">${BT.todayMaxLiq} · ${mx1[6] === 0 ? BT.longLiq : BT.shortLiq}<small>${esc(m.maxWhen)} · ${esc(m.maxPrice)} · ${LIQ_EX[mx1[7]] ?? '币安'}</small></span>
    <span class="v ${mx1[6] === 0 ? 'down' : 'up'}">${esc(fmt(mx1[4]))}</span></div>` : ''
  return `<div class="bt-card" data-card="liq24"><h5>${BT.liq}<span class="rt">${BT.day}</span></h5><div class="bt-scroll">${sv}</div>
    <div class="bt-mini"><span>${esc(m.from)}</span><span>${BT.long} <b class="down">${esc(fmt(m.day.long))}</b> · ${BT.short} <b class="up">${esc(fmt(m.day.short))}</b></span><span>${BT.now}</span></div>${max}</div>`
}

// ───────────────────────────── 数字滚动

const rolling = new WeakMap<Element, { v: number; raf: number }>()
function roll(node: Element, v: number, f: (n: number) => string): void {
  const r = rolling.get(node)
  const prev = r?.v
  if (r?.raf) cancelAnimationFrame(r.raf)
  const me = { v, raf: 0 }
  rolling.set(node, me)
  if (prev == null || prev === v || reducedMotion() || typeof requestAnimationFrame === 'undefined') { setText(node, f(v)); return }
  const t0 = performance.now()
  const step = (): void => {
    const k = Math.min(1, (performance.now() - t0) / 200)
    const e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2
    setText(node, f(prev + (v - prev) * e))
    me.raf = k < 1 ? requestAnimationFrame(step) : 0
  }
  me.raf = requestAnimationFrame(step)
}

// ───────────────────────────── 弹层

export interface SheetHooks {
  onClose(): void
  onThreshold(): void
  onPickBar(t: number): void
  onLocate?(t: number, price?: number): void
}

export function insightSectionHTML(s: InsightSection): string {
  return `<div class="bt-card bt-insight-card" data-insight="${esc(s.id)}"><h5>${esc(s.title)}${s.subtitle ? `<span class="rt">${esc(s.subtitle)}</span>` : ''}</h5>
    ${s.rows.length ? s.rows.map(r => `<div class="bt-insight-row"><div class="bt-insight-line"><span>${esc(r.title)}</span>${r.value ? `<b class="${r.tone ?? ''}">${esc(r.value)}</b>` : ''}</div>
      <p>${esc(r.detail)}</p>${r.note ? `<small>${esc(r.note)}</small>` : ''}${r.main && r.time != null ? `<button type="button" class="bt-locate" data-locate="${r.time}"${r.price != null ? ` data-price="${r.price}"` : ''}>${L.chart} ›</button>` : ''}</div>`).join('') : `<p class="bt-insight-empty">${esc(s.empty ?? '')}</p>`}
    <details class="bt-evidence"><summary>${L.evidence}</summary><p>${esc(s.evidence)}</p></details></div>`
}

export class BigTradeSheet {
  readonly wrap: HTMLDivElement
  readonly root: HTMLDivElement
  private body: HTMLDivElement
  private subEl: HTMLElement
  private heroSkel: HTMLElement
  private hero: HTMLElement
  private liqEl: HTMLElement
  private barsEl: HTMLElement
  private ladderEl: HTMLElement
  private liqDayEl: HTMLElement
  private thrEl: HTMLButtonElement
  private shut = false
  private parked = false
  private unback: (() => void) | null = null
  private model: BtModel | null = null
  private heroTitle = ''
  private flashT: number | null = null
  private flashTimer: ReturnType<typeof setTimeout> | null = null
  private scrolledRight = false
  private insightEl: HTMLElement
  private insightStatus: HTMLElement
  private insightNote: HTMLElement
  private evidenceEl: HTMLDetailsElement
  private readonly opener = typeof document !== 'undefined' ? document.activeElement as HTMLElement | null : null
  private previousInert = false
  private previousOverflow = ''
  private readonly keys = (e: KeyboardEvent): void => {
    if (this.shut || this.parked || e.key !== 'Tab') return
    const nodes = [...this.root.querySelectorAll<HTMLElement>('button:not([disabled]), summary, [tabindex="0"]')].filter(n => n.getClientRects().length > 0)
    const first = nodes[0], last = nodes.at(-1)
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last?.focus() }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first?.focus() }
  }

  constructor(private readonly hooks: SheetHooks) {
    const wrap = this.wrap = el('div', 'bt-wrap')
    const scrim = el('div', 'bt-scrim')
    const root = this.root = el('div', 'bt-sheet')
    root.setAttribute('role', 'dialog')
    root.setAttribute('aria-label', L.title)
    root.setAttribute('aria-modal', 'true')
    root.innerHTML = `${liuliBackdropHTML(true)}
      <div class="bt-hdr"><button type="button" class="bt-bk" aria-label="返回行情">${icon('chevronLeft', 20)}</button>
        <h4>${L.title}<small class="bt-sub"></small></h4><button type="button" class="bt-pill">${BT.threshold}</button></div>
      <div class="bt-body">
        <div class="bt-card bt-observation"><h5>${L.observation}</h5><p class="bt-insight-status"></p><small class="bt-insight-note"></small></div>
        <div class="bt-insights"></div>
        <details class="bt-bar-evidence"><summary>${L.barEvidence}</summary>
        <div class="bt-hero-skel" hidden>${heroSkelHTML()}</div>
        <div class="bt-card bt-hero" data-card="hero">
          <h5><span class="bt-live" aria-hidden="true"></span><span class="bt-ht">${BT.currentBar}</span><span class="rt"></span></h5>
          <div class="bt-hero-main">
            <div class="bt-amts"><b class="up"><span data-r="bb"></span><small data-n="bn"></small></b><b class="down"><span data-r="bs"></span><small data-n="sn"></small></b></div>
            <div class="bt-vs" data-vs="bar"><div class="b"></div><div class="a"></div><span class="net"></span></div>
          </div>
          <div class="bt-empty bt-hero-empty" hidden><b>${BT.noBigTrade}</b></div>
          <div class="bt-rows">
            <span class="lab">${BT.hour}</span>${this.rowHTML('hour')}
            <span class="lab">${BT.today}</span>${this.rowHTML('today')}
          </div>
          <div class="bt-hint bt-untracked" hidden>${BT.untracked}</div>
        </div>
        <div class="bt-liq"></div>
        <div class="bt-bars"></div><div class="bt-lad"></div><div class="bt-liqday"></div></details>
        <button type="button" class="bt-card thin bt-thr"><span class="l">${BT.threshold}</span><span class="v"></span><span class="go">›</span></button>
      </div>`
    wrap.append(scrim, root)
    const q = <T extends HTMLElement>(s: string): T => root.querySelector<T>(s)!
    this.body = q('.bt-body'); this.subEl = q('.bt-sub')
    this.insightEl = q('.bt-insights'); this.insightStatus = q('.bt-insight-status'); this.insightNote = q('.bt-insight-note'); this.evidenceEl = q('.bt-bar-evidence')
    this.heroSkel = q('.bt-hero-skel'); this.hero = q('.bt-hero[data-card="hero"]')
    this.liqEl = q('.bt-liq')
    this.barsEl = q('.bt-bars'); this.ladderEl = q('.bt-lad'); this.liqDayEl = q('.bt-liqday'); this.thrEl = q('.bt-thr')

    q('.bt-bk').addEventListener('click', () => this.close())
    q('.bt-pill').addEventListener('click', () => this.hooks.onThreshold())
    this.thrEl.addEventListener('click', () => this.hooks.onThreshold())
    scrim.addEventListener('click', () => this.close())
    // 点签是在 touchend 上开的：随后浏览器补发的那下 click 会落在刚铺上的遮罩 / 弹层里，把它当场关掉或误点一根。
    // 开后这一小段把补发的 click 吞掉
    const born = performance.now()
    wrap.addEventListener('click', e => { if (performance.now() - born < GHOST_MS) { e.stopPropagation(); e.preventDefault() } }, true)
    this.barsEl.addEventListener('click', e => this.pickBar(e))
    this.insightEl.addEventListener('click', e => { const hit = (e.target as Element).closest<HTMLElement>('[data-locate]'); if (hit) this.hooks.onLocate?.(+hit.dataset.locate!, hit.dataset.price ? +hit.dataset.price : undefined) })
    this.root.addEventListener('keydown', this.keys)

    layer().appendChild(wrap)
    this.unback = pushLayer(() => this.close())
    const app = document.getElementById('m-app')
    if (app) { this.previousInert = app.inert; app.inert = true }
    this.previousOverflow = document.body.style.overflow; document.body.style.overflow = 'hidden'
    if (reducedMotion()) wrap.classList.add('in')
    else requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add('in')))
    setTimeout(() => { if (!this.shut && !this.parked) q('.bt-bk').focus({ preventScroll: true }) }, reducedMotion() ? 0 : 300)
  }

  get closed(): boolean { return this.shut }
  get current(): BtModel | null { return this.model }

  /** 门槛页盖上来时先收下去（不关），那页关了再升回来 */
  park(): void { if (this.shut || this.parked) return; this.parked = true; this.root.inert = true; this.root.setAttribute('aria-hidden', 'true'); this.wrap.classList.add('parked') }
  unpark(): void { if (this.shut || !this.parked) return; this.parked = false; this.root.inert = false; this.root.removeAttribute('aria-hidden'); this.wrap.classList.remove('parked'); this.root.querySelector<HTMLElement>('.bt-pill')?.focus({ preventScroll: true }) }

  close(): void {
    if (this.shut) return
    this.shut = true
    const app = document.getElementById('m-app'); if (app) app.inert = this.previousInert
    document.body.style.overflow = this.previousOverflow
    this.root.removeEventListener('keydown', this.keys)
    this.unback?.(); this.unback = null
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.wrap.classList.remove('in')
    setTimeout(() => this.wrap.remove(), reducedMotion() ? 0 : 300)
    this.hooks.onClose()
    if (this.opener?.isConnected) this.opener.focus({ preventScroll: true })
  }

  /** 点气泡进入同一页，展开并定位该根证据；保留图表大单来源的互斥定位。 */
  showSelected(): void { this.evidenceEl.open = true; requestAnimationFrame(() => this.hero.scrollIntoView({ block: 'start', behavior: reducedMotion() ? 'instant' : 'smooth' })) }

  /** 每根里那一根闪 1.2 秒（点了一根之后） */
  flash(t: number): void {
    this.flashT = t
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => { this.flashT = null; if (this.model) this.renderBars(this.model) }, 1200)
    if (this.model) this.renderBars(this.model)
  }

  /** 副标题挑第一种一行放得下的（同一组写法、同一宽度只量一次）；弹层没排版（宽 0）时先摆全称 */
  private subKey = ''
  private fitSub(m: BtModel): void {
    const el = this.subEl
    const w = el.clientWidth
    const key = `${w}|${m.subs.join('|')}`
    if (key === this.subKey) return
    this.subKey = w > 0 ? key : ''
    el.setAttribute('aria-label', m.sub)
    let pick = m.subs[0] ?? m.sub
    if (w > 0) for (const s of m.subs) { setText(el, s); pick = s; if (el.scrollWidth <= w + 1) break }
    setText(el, pick)
  }

  update(m: BtModel): void {
    if (this.shut) return
    this.model = m
    this.fitSub(m)
    this.root.classList.toggle('stale', m.stale)
    if (m.insights) this.renderInsights(m.insights)
    this.heroSkel.hidden = !m.loading
    this.hero.hidden = m.loading
    if (!m.loading) this.renderHero(m.hero)
    setHTML(this.liqEl, liqCardHTML(m.loading && m.liq ? { ...m.liq, state: 'loading' } : m.liq))
    this.renderBars(m)
    setHTML(this.ladderEl, ladderCardHTML(m.ladder))
    setHTML(this.liqDayEl, liqDayCardHTML(m.liq))
    setText(this.thrEl.querySelector('.v')!, m.thr)
  }

  private readonly updateGate = new Map<string, (fn: () => void) => void>()
  private renderInsights(view: InsightView): void {
    setText(this.insightStatus, view.status); setText(this.insightNote, view.note)
    const ids = new Set(view.sections.map(s => s.id))
    for (const n of this.insightEl.children) if (!ids.has((n as HTMLElement).dataset.section!)) n.remove()
    for (const s of view.sections) {
      let node = this.insightEl.querySelector<HTMLElement>(`[data-section="${s.id}"]`)
      if (!node) { node = el('div'); node.dataset.section = s.id; this.insightEl.append(node); this.updateGate.set(s.id, pressGate(node)) }
      const html = insightSectionHTML(s), target = node
      this.updateGate.get(s.id)!(() => {
        // Preserve the exact focused evidence control while live updates arrive.
        if (target.contains(document.activeElement)) return
        const open = !!target.querySelector<HTMLDetailsElement>('details')?.open, top = this.body.scrollTop
        if (setHTML(target, html)) { const details = target.querySelector<HTMLDetailsElement>('details'); if (details) details.open = open; this.body.scrollTop = top }
      })
    }
  }

  // ------------------------------------------------------------ 本根卡片

  private rowHTML(k: 'hour' | 'today'): string {
    return `<div data-w="${k}"><div class="bt-vs s"><div class="b"></div><div class="a"></div></div><div class="bt-ends"><b class="up" data-r="b"></b><span data-r="net"></span><b class="down" data-r="s"></b></div></div>`
  }

  private setVs(vs: Element, b: number, s: number, gap: number): number {
    const has = b + s > 0, k = share(b, s)
    ;(vs.querySelector('.b') as HTMLElement).style.width = has ? `calc(${(k * 100).toFixed(1)}% - ${gap}px)` : '0px'
    ;(vs.querySelector('.a') as HTMLElement).style.width = has ? `calc(${((1 - k) * 100).toFixed(1)}% - ${gap}px)` : '0px'
    return k
  }

  private renderHero(h: HeroModel): void {
    const root = this.hero
    const title = root.querySelector('.bt-ht')!
    if (this.heroTitle && this.heroTitle !== h.title && h.live && !reducedMotion() && typeof root.animate === 'function') {
      root.animate([{ opacity: 0.4 }, { opacity: 1 }], { duration: 300, easing: 'ease-out' })
    }
    this.heroTitle = h.title
    setText(title, h.title)
    ;(root.querySelector('.bt-live') as HTMLElement).hidden = !h.live
    setText(root.querySelector('h5 .rt')!, h.rt)
    const b = h.bar
    const empty = b.bb + b.bs <= 0
    ;(root.querySelector('.bt-hero-main') as HTMLElement).hidden = empty
    ;(root.querySelector('.bt-hero-empty') as HTMLElement).hidden = !empty
    if (!empty) {
      roll(root.querySelector('[data-r="bb"]')!, b.bb, fmt)
      roll(root.querySelector('[data-r="bs"]')!, b.bs, fmt)
      setText(root.querySelector('[data-n="bn"]')!, b.bn != null ? fill(BT.buyCount, { n: b.bn }) : '')
      setText(root.querySelector('[data-n="sn"]')!, b.sn != null ? fill(BT.sellCount, { n: b.sn }) : '')
      const vs = root.querySelector('[data-vs="bar"]')!
      const k = this.setVs(vs, b.bb, b.bs, 2)
      const net = vs.querySelector('.net') as HTMLElement
      net.style.left = `${(Math.max(0.16, Math.min(0.84, k)) * 100).toFixed(1)}%`
      net.classList.toggle('up', b.bb >= b.bs)
      net.classList.toggle('down', b.bb < b.bs)
      roll(net, b.bb - b.bs, netText)
    }
    for (const [key, w] of [['hour', h.hour], ['today', h.today]] as const) {
      const row = root.querySelector(`[data-w="${key}"]`)!
      this.setVs(row.querySelector('.bt-vs')!, w.bb, w.bs, 1)
      roll(row.querySelector('[data-r="b"]')!, w.bb, fmt)
      roll(row.querySelector('[data-r="s"]')!, w.bs, fmt)
      setText(row.querySelector('[data-r="net"]')!, w.bb + w.bs > 0 ? netText(w.bb - w.bs) : BT.noBigTrade)
    }
    ;(root.querySelector('.bt-untracked') as HTMLElement).hidden = !h.untracked
  }

  private renderBars(m: BtModel): void {
    setHTML(this.barsEl, barsCardHTML(m.bars, m.sel, this.flashT))
    const sc = this.barsEl.querySelector<HTMLElement>('.bt-scroll')
    if (sc && !this.scrolledRight) { sc.scrollLeft = sc.scrollWidth; this.scrolledRight = true }
  }

  private pickBar(e: MouseEvent): void {
    const svg = this.barsEl.querySelector<SVGSVGElement>('svg.bt-cols')
    const m = this.model
    if (!svg || !m || !m.bars.length) return
    const r = svg.getBoundingClientRect()
    if (e.clientY < r.top - 8 || e.clientY > r.bottom + 8) return
    const i = Math.max(0, Math.min(m.bars.length - 1, Math.floor(((e.clientX - r.left) / Math.max(1, r.width)) * m.bars.length)))
    this.hooks.onPickBar(m.bars[i].t)
  }

}
