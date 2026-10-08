/* Hkline 手机网页 · 「大单与爆仓」弹层（照 docs/原型-手机大单与爆仓-2026-10-08.html 的 sheet()）
 *
 * 两档：半屏 440（「脉搏」：本根 + 近 1 小时 / 今日 + 一条爆仓）/ 满屏 780（再加每根、价位、24 小时爆仓、门槛）。
 * 都盖住底栏（挂在 #m-layer）。半屏不压暗、不挡图：图照样能拉十字线、点别的签（只换根不关）；点弹层以外的地方关。
 *   · 拖：拖拽条 / 标题行随便拖；正文滚到顶时往下拉接手。半屏往上拉过 90 落满屏；满屏往下拉回半屏，半屏再往下拉就关。
 *   · 「‹」关；右上「门槛」开订单流门槛页，那页关了回到原来那一档。
 *   · 本根卡片的数字换值时滚 200 ms，对撞条交汇点 240 ms 缓动；减少动效时一律直接换。
 * 这里只管 DOM 与手势；数从哪来、什么时候刷新在 bigTrade.ts。
 */
import { el, esc, layer, reducedMotion, safeArea, setHTML, setText } from '../../ui/dom'
import { icon } from '../../ui/icons'
import { pushLayer } from '../../ui/sheet'
import { liuliBackdropHTML } from '../../ui/liuli'
import { orderFlowAmount } from '../../chart/renderer.orderflow'
import type { WinSum, Level, Wall } from '../../../orderflow/summary'
import type { LiqSum, LiqRow } from '../../../orderflow/liquidation'
import { LIQ_EX } from '../../../orderflow/liquidation'
import '../../styles/bigTrade.css'

export type Detent = 'half' | 'full'
export const HALF_H = 440
export const FULL_H = 780
/** 半屏往上拉过这么多才落满屏 */
export const EXPAND_PX = 90

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
  sub: string
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
}

// ───────────────────────────── 纯函数（测试直接测）

const share = (b: number, s: number): number => (b + s > 0 ? b / (b + s) : 0.5)

/** 「净买 +3.3M」/「净卖 −1.2M」 */
export function netText(net: number): string {
  return net >= 0 ? `净买 +${fmt(net)}` : `净卖 ${MINUS}${fmt(-net)}`
}

/** 分析面板那一行的小字：本根净买 / 净卖，还没大单就说没有 */
export function summaryLine(bar: WinSum | null): string {
  if (!bar || bar.bb + bar.bs <= 0) return '本根暂无大单'
  return `本根 ${netText(bar.bb - bar.bs)}`
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

/** 价位梯：现价上下五档（11 行）。行距按近 1 小时大单落的价位自适应（盖住最远那一档），不小于订单流步长 */
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
  return `<div class="bt-card bt-hero"><h5>本根<span class="rt">第一次打开</span></h5>
    <div class="bt-amts">${skel('width:88px;height:22px')}${skel('width:88px;height:22px')}</div>
    <div class="bt-vs bt-skel" style="margin-top:12px"></div>
    <div class="bt-rows"><span class="lab">近 1 小时</span><div class="bt-vs s bt-skel"></div><span class="lab">今日</span><div class="bt-vs s bt-skel"></div></div></div>`
}

function vsHTML(b: number, s: number, small: boolean): string {
  const k = share(b, s), gap = small ? 1 : 2
  const has = b + s > 0
  return `<div class="bt-vs${small ? ' s' : ''}"><div class="b" style="width:${has ? `calc(${(k * 100).toFixed(1)}% - ${gap}px)` : '0'}"></div><div class="a" style="width:${has ? `calc(${((1 - k) * 100).toFixed(1)}% - ${gap}px)` : '0'}"></div></div>`
}

export function liqCardHTML(m: LiqModel | null, full: boolean): string {
  if (!m) return ''
  if (m.state === 'loading') return `<div class="bt-card thin"><h5>爆仓</h5><div class="bt-vs s bt-skel" style="margin:4px 0 10px"></div>${skel('display:block;height:14px;width:60%')}</div>`
  if (m.state === 'none') return `<div class="bt-card thin"><h5>爆仓</h5><div class="bt-empty"><b>这只品种暂无爆仓数据</b></div></div>`
  if (m.today.long + m.today.short <= 0) return `<div class="bt-card thin" data-liq="empty"><h5>爆仓<span class="rt">近 1 小时</span></h5><div class="bt-empty"><b>今天还没有人被打爆</b>多空都稳着</div></div>`
  const h = m.hour
  const mid = h.long + h.short <= 0 ? '这一小时多空都稳着' : h.long >= h.short ? '多头被打得更狠' : '空头被打得更狠'
  const mx = m.today.max
  const maxLine = mx
    ? `<span>今日最大 <b class="${mx[6] === 0 ? 'down' : 'up'}">${mx[6] === 0 ? '多单' : '空单'} ${esc(fmt(mx[4]))}</b> @ ${esc(m.maxPrice)} · ${esc(m.maxWhen)}</span>`
    : '<span></span>'
  return `<div class="bt-card thin" data-liq="data"><h5>爆仓<span class="rt">近 1 小时</span></h5>
    ${vsHTML(h.short, h.long, true).replace('class="bt-vs s"', 'class="bt-vs s liq"')}
    <div class="bt-ends"><b class="up">空爆 ${esc(fmt(h.short))}</b><span>${mid}</span><b class="down">多爆 ${esc(fmt(h.long))}</b></div>
    <div class="bt-mini">${maxLine}${full ? `<span>24h 多爆 <b>${esc(fmt(m.day.long))}</b> · 空爆 <b>${esc(fmt(m.day.short))}</b></span>` : ''}</div></div>`
}

export function barsCardHTML(bars: BarCol[], sel: number | null, flash: number | null): string {
  if (!bars.length) return ''
  let mx = 0
  for (const b of bars) mx = Math.max(mx, b.bb, b.bs)
  if (!(mx > 0)) mx = 1
  const W = bars.length * 8
  let sv = `<svg class="bt-cols" width="${W}" height="96" viewBox="0 0 ${W} 96" role="img" aria-label="近 ${bars.length} 根的大买大卖">`
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
  return `<div class="bt-card" data-card="bars"><h5>每根<span class="rt">近 ${bars.length} 根 · 点一根十字线就跳过去</span></h5>
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
    return `<div class="${cls}" style="--w:${ww}"><i${tiny ? ' class="tiny"' : ''} style="width:${ww}"></i>${wall != null ? `<span class="wall">墙 ${esc(fmt(wall))}</span>` : w0 > 6 ? `<s>${esc(fmt(v))}</s>` : ''}</div>`
  }
  return `<div class="bt-card" data-card="ladder"><h5>价位<span class="rt">现价上下五档 · 近 1 小时</span></h5><div class="bt-ladder">${rows.map(r =>
    side('bl', r.bw, r.buy, r.bidWall) + `<div class="p${r.now ? ' now' : ''}">${esc(r.price)}</div>` + side('br', r.sw, r.sell, r.askWall)).join('')}</div></div>`
}

export function liqDayCardHTML(m: LiqModel | null): string {
  if (!m || m.state !== 'data') return ''
  let mx = 0
  for (const [a, b] of m.cells) mx = Math.max(mx, a, b)
  if (!(mx > 0)) mx = 1
  let sv = '<svg class="bt-liq24" width="330" height="64" viewBox="0 0 330 64" role="img" aria-label="24 小时爆仓"><line class="bt-mid" x1="0" x2="330" y1="32" y2="32"/>'
  m.cells.forEach(([lo, sh], i) => {
    const x = (i * 3.4).toFixed(1), a = (lo / mx) * 28, c = (sh / mx) * 28
    if (c > 0) sv += `<rect class="bt-u" x="${x}" y="${(32 - c).toFixed(1)}" width="2.4" height="${c.toFixed(1)}"/>`
    if (a > 0) sv += `<rect class="bt-d" x="${x}" y="32" width="2.4" height="${a.toFixed(1)}"/>`
  })
  if (m.selCell >= 0) sv += `<rect class="bt-sel" x="${(m.selCell * 3.4 - 1).toFixed(1)}" y="2" width="4.4" height="60" rx="2"/>`
  sv += '</svg>'
  const mx1 = m.today.max
  const max = mx1 ? `<div class="bt-liqmax"><span class="ic ${mx1[6] === 0 ? 'down' : 'up'}">${mx1[6] === 0 ? '多' : '空'}</span>
    <span class="t">今日最大一笔 · ${mx1[6] === 0 ? '多单' : '空单'}爆仓<small>${esc(m.maxWhen)} · ${esc(m.maxPrice)} · ${LIQ_EX[mx1[7]] ?? '币安'}</small></span>
    <span class="v ${mx1[6] === 0 ? 'down' : 'up'}">${esc(fmt(mx1[4]))}</span></div>` : ''
  return `<div class="bt-card" data-card="liq24"><h5>爆仓<span class="rt">24 小时 · 每格 15 分钟</span></h5><div class="bt-scroll">${sv}</div>
    <div class="bt-mini"><span>${esc(m.from)}</span><span>多爆 <b class="down">${esc(fmt(m.day.long))}</b> · 空爆 <b class="up">${esc(fmt(m.day.short))}</b></span><span>现在</span></div>${max}</div>`
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
  onDetent?(d: Detent): void
}

export class BigTradeSheet {
  readonly wrap: HTMLDivElement
  readonly root: HTMLDivElement
  private body: HTMLDivElement
  private subEl: HTMLElement
  private heroSkel: HTMLElement
  private hero: HTMLElement
  private liqEl: HTMLElement
  private hintEl: HTMLButtonElement
  private fullEl: HTMLElement
  private barsEl: HTMLElement
  private ladderEl: HTMLElement
  private liqDayEl: HTMLElement
  private thrEl: HTMLButtonElement
  private d: Detent
  private shut = false
  private parked = false
  private unback: (() => void) | null = null
  private signTapAt = -1e9
  private model: BtModel | null = null
  private heroTitle = ''
  private flashT: number | null = null
  private flashTimer: ReturnType<typeof setTimeout> | null = null
  private scrolledRight = false
  private readonly offDoc: () => void

  constructor(private readonly hooks: SheetHooks, detent: Detent = 'half') {
    this.d = detent
    const wrap = this.wrap = el('div', 'bt-wrap')
    const scrim = el('div', 'bt-scrim')
    const root = this.root = el('div', 'bt-sheet')
    root.setAttribute('role', 'dialog')
    root.setAttribute('aria-label', '大单与爆仓')
    root.innerHTML = `${liuliBackdropHTML(true)}<div class="bt-grab" aria-hidden="true"><i></i></div>
      <div class="bt-hdr"><button type="button" class="bt-bk" aria-label="收起">${icon('chevronLeft', 20)}</button>
        <h4>大单与爆仓<small class="bt-sub"></small></h4><button type="button" class="bt-pill">门槛</button></div>
      <div class="bt-body">
        <div class="bt-hero-skel" hidden>${heroSkelHTML()}</div>
        <div class="bt-card bt-hero" data-card="hero">
          <h5><span class="bt-live" aria-hidden="true"></span><span class="bt-ht">本根</span><span class="rt"></span></h5>
          <div class="bt-hero-main">
            <div class="bt-amts"><b class="up"><span data-r="bb"></span><small data-n="bn"></small></b><b class="down"><span data-r="bs"></span><small data-n="sn"></small></b></div>
            <div class="bt-vs" data-vs="bar"><div class="b"></div><div class="a"></div><span class="net"></span></div>
          </div>
          <div class="bt-empty bt-hero-empty" hidden><b>这根还没有大单</b>门槛以上的成交一出现就在这里</div>
          <div class="bt-rows">
            <span class="lab">近 1 小时</span>${this.rowHTML('hour')}
            <span class="lab">今日</span>${this.rowHTML('today')}
          </div>
          <div class="bt-hint bt-untracked" hidden>这只品种只算打开以后的成交</div>
        </div>
        <div class="bt-liq"></div>
        <button type="button" class="bt-hint bt-more">上拉看每根 · 价位 · 24 小时爆仓</button>
        <div class="bt-full">
          <div class="bt-bars"></div><div class="bt-lad"></div><div class="bt-liqday"></div>
          <button type="button" class="bt-card thin bt-thr"><span class="l">门槛</span><span class="v"></span><span class="go">改 ›</span></button>
        </div>
      </div>`
    wrap.append(scrim, root)
    const q = <T extends HTMLElement>(s: string): T => root.querySelector<T>(s)!
    this.body = q('.bt-body'); this.subEl = q('.bt-sub')
    this.heroSkel = q('.bt-hero-skel'); this.hero = q('.bt-hero[data-card="hero"]')
    this.liqEl = q('.bt-liq'); this.hintEl = q('.bt-more'); this.fullEl = q('.bt-full')
    this.barsEl = q('.bt-bars'); this.ladderEl = q('.bt-lad'); this.liqDayEl = q('.bt-liqday'); this.thrEl = q('.bt-thr')

    q('.bt-bk').addEventListener('click', () => this.close())
    q('.bt-pill').addEventListener('click', () => this.hooks.onThreshold())
    this.thrEl.addEventListener('click', () => this.hooks.onThreshold())
    this.hintEl.addEventListener('click', () => this.setDetent('full'))
    scrim.addEventListener('click', () => this.close())
    this.barsEl.addEventListener('click', e => this.pickBar(e))
    this.wireDrag()

    layer().appendChild(wrap)
    this.unback = pushLayer(() => this.close())
    this.applyDetent(false)
    if (reducedMotion()) wrap.classList.add('in')
    else requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add('in')))
    this.offDoc = this.wireOutside()
  }

  get closed(): boolean { return this.shut }
  get detent(): Detent { return this.d }
  get current(): BtModel | null { return this.model }

  /** 点中图上的一枚签（宿主先叫这个，弹层以外的那一下就不当成「点外面关掉」） */
  noteSignTap(): void { this.signTapAt = performance.now() }

  setDetent(d: Detent): void {
    if (this.shut || d === this.d) return
    this.d = d
    this.applyDetent(true)
    if (this.model) this.update(this.model)
    this.hooks.onDetent?.(d)
  }

  /** 门槛页盖上来时先收下去（不关），那页关了再升回原来那一档 */
  park(): void { if (this.shut || this.parked) return; this.parked = true; this.wrap.classList.add('parked') }
  unpark(): void { if (this.shut || !this.parked) return; this.parked = false; this.wrap.classList.remove('parked') }

  close(): void {
    if (this.shut) return
    this.shut = true
    this.offDoc()
    this.unback?.(); this.unback = null
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.wrap.classList.remove('in')
    setTimeout(() => this.wrap.remove(), reducedMotion() ? 0 : 300)
    this.hooks.onClose()
  }

  /** 每根里那一根闪 1.2 秒（点了一根之后） */
  flash(t: number): void {
    this.flashT = t
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => { this.flashT = null; if (this.model) this.renderBars(this.model) }, 1200)
    if (this.model) this.renderBars(this.model)
  }

  update(m: BtModel): void {
    if (this.shut) return
    this.model = m
    setText(this.subEl, m.sub)
    this.root.classList.toggle('stale', m.stale)
    this.heroSkel.hidden = !m.loading
    this.hero.hidden = m.loading
    if (!m.loading) this.renderHero(m.hero)
    setHTML(this.liqEl, m.loading && m.liq ? liqCardHTML({ ...m.liq, state: 'loading' }, false) : liqCardHTML(m.liq, this.d === 'full'))
    const full = this.d === 'full'
    this.hintEl.hidden = full
    this.fullEl.hidden = !full
    if (full) {
      this.renderBars(m)
      setHTML(this.ladderEl, ladderCardHTML(m.ladder))
      setHTML(this.liqDayEl, liqDayCardHTML(m.liq))
      setText(this.thrEl.querySelector('.v')!, m.thr)
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
      setText(root.querySelector('[data-n="bn"]')!, b.bn != null ? `买 ${b.bn} 笔` : '')
      setText(root.querySelector('[data-n="sn"]')!, b.sn != null ? `卖 ${b.sn} 笔` : '')
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
      setText(row.querySelector('[data-r="net"]')!, w.bb + w.bs > 0 ? netText(w.bb - w.bs) : '暂无大单')
    }
    ;(root.querySelector('.bt-untracked') as HTMLElement).hidden = !h.untracked
  }

  private renderBars(m: BtModel): void {
    if (this.d !== 'full') return
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

  // ------------------------------------------------------------ 档位与拖

  private maxH(): number {
    const vh = typeof innerHeight === 'number' && innerHeight > 0 ? innerHeight : 852
    return Math.max(200, vh - safeArea().top - 10)
  }
  private heightOf(d: Detent): number { return Math.min(d === 'full' ? FULL_H : HALF_H, this.maxH()) }

  private applyDetent(_animated: boolean): void {
    this.root.style.height = this.heightOf(this.d) + 'px'
    this.root.classList.toggle('full', this.d === 'full')
    this.wrap.classList.toggle('full', this.d === 'full')
    if (this.d === 'half') this.body.scrollTop = 0
  }

  private wireDrag(): void {
    let startY = 0, startH = 0, dy = 0, dragging = false, lastY = 0, lastT = 0, vel = 0
    const root = this.root
    const begin = (y: number): void => {
      startY = lastY = y; lastT = performance.now(); dy = 0; vel = 0; dragging = true
      startH = root.offsetHeight || this.heightOf(this.d); root.classList.add('dragging')
    }
    const move = (y: number): void => {
      const now = performance.now()
      vel = (y - lastY) / Math.max(1, now - lastT); lastY = y; lastT = now
      dy = y - startY
      if (this.d === 'half' && dy > 0) { root.style.transform = `translateY(${dy}px)`; return }
      root.style.transform = ''
      const h = startH - dy
      const max = this.heightOf('full')
      root.style.height = `${Math.max(this.heightOf('half') - 40, Math.min(max + 12, h))}px`
    }
    const end = (): void => {
      if (!dragging) return
      dragging = false; root.classList.remove('dragging'); root.style.transform = ''
      if (this.d === 'half') {
        if (dy > 0 && (dy > 110 || vel > 0.6)) { this.close(); return }
        if (dy < 0 && (-dy > EXPAND_PX || vel < -0.6)) { this.setDetent('full'); return }
      } else if (dy > 60 || vel > 0.6) { this.setDetent('half'); return }
      this.applyDetent(true)
    }
    const zones = [root.querySelector<HTMLElement>('.bt-grab')!, root.querySelector<HTMLElement>('.bt-hdr')!]
    for (const z of zones) {
      z.addEventListener('pointerdown', e => {
        if ((e.target as Element).closest('button')) return
        try { z.setPointerCapture(e.pointerId) } catch { /* 合成事件没有指针 */ }
        begin(e.clientY)
      })
      z.addEventListener('pointermove', e => { if (dragging) move(e.clientY) })
      z.addEventListener('pointerup', end)
      z.addEventListener('pointercancel', end)
    }
    // 正文：满屏滚到顶往下拉 → 半屏；半屏（正文不滚）往上 / 往下拉都接手
    const body = this.body
    let y0 = 0, armed = false
    body.addEventListener('touchstart', e => { y0 = e.touches[0].clientY; armed = this.d === 'half' || body.scrollTop <= 0 }, { passive: true })
    body.addEventListener('touchmove', e => {
      const y = e.touches[0].clientY
      if (!dragging && armed && Math.abs(y - y0) > 6 && (this.d === 'half' || (y > y0 && body.scrollTop <= 0))) begin(y0)
      if (dragging) { e.preventDefault(); move(y) }
      else if (this.d === 'full' && y < y0) armed = false
    }, { passive: false })
    body.addEventListener('touchend', end)
    body.addEventListener('touchcancel', end)
  }

  /** 点弹层以外的地方关（半屏不压暗、不挡图；点中图上的签只换根，见 noteSignTap） */
  private wireOutside(): () => void {
    let down: { x: number; y: number; t: number } | null = null
    const inside = (t: EventTarget | null): boolean => t instanceof Node && (this.root.contains(t) || !this.wrap.isConnected)
    const onDown = (e: PointerEvent): void => {
      down = inside(e.target) || this.parked || !e.isPrimary ? null : { x: e.clientX, y: e.clientY, t: performance.now() }
    }
    const onUp = (e: PointerEvent): void => {
      const d = down
      down = null
      if (!d || this.parked || this.shut) return
      if (performance.now() - d.t > 500 || Math.hypot(e.clientX - d.x, e.clientY - d.y) > 10) return
      // 别的弹层（门槛页、解释卡）盖在上面时点的是它们
      const top = layer().lastElementChild
      if (top && top !== this.wrap && top.contains(e.target as Node)) return
      const at = performance.now()
      setTimeout(() => { if (!this.shut && this.signTapAt < at - 5) this.close() }, 60)
    }
    document.addEventListener('pointerdown', onDown, true)
    document.addEventListener('pointerup', onUp, true)
    return () => { document.removeEventListener('pointerdown', onDown, true); document.removeEventListener('pointerup', onUp, true) }
  }
}
