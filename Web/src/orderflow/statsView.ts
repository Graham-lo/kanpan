/* Hkline Web · 主力订单流 · 侧栏「24 小时流动性」「24 小时成交」两块小图，以及详情里的「每秒成交」一行
 *
 * 两块都是 48 格（30 分钟一格、上海时间）的小画布，定高 120（标题 32 + 图 88）：
 *   · 流动性：买、卖两根线（中间价 ±2.5% 以内的挂单名义），悬停给那一格的值与相对上一格的变化；
 *   · 成交：灰柱是各家合计，上面叠币安的主动买、主动卖两条波形（OKX / Coinbase 的 K 线没有主动买，只计总额）。
 * 数据在 stats.ts；这里只画。
 */
import { OF, feedIdleText, amt, hm, canvasFont, showCard, hideCard } from './state'
import { hexA } from '../util/format'
import { SLOT_MS, SLOTS, slotOf, type LiqPoint, type VolSlot } from './stats'
import { signedPct } from './tradeLadder'
import { VENUE_LIST } from '../venues'

export type StatKind = 'liq' | 'vol'

const PAD_L = 8, PAD_R = 8, PAD_T = 16, PAD_B = 15

interface Pal { text1: string; text3: string; up: string; down: string; upT: string; downT: string; line: string }
function palette(el: Element): Pal {
  const css = getComputedStyle(el)
  const v = (k: string, d: string): string => css.getPropertyValue(k).trim() || d
  const up = v('--up', '#089981'), down = v('--down', '#F23645')
  return { text1: v('--text-1', '#131722'), text3: v('--text-3', '#767C8A'), up, down, upT: v('--up-text', up), downT: v('--down-text', down), line: v('--line', '#E0E3EB') }
}

/** 一格的时间区间（上海时间） */
export const slotLabel = (t: number): string => `${hm(t)}–${hm(t + SLOT_MS)}`

/** 相对上一格的变化（%）；上一格没有或为 0 给 null */
export function changePct(cur: number, prev: number | undefined): number | null {
  return prev != null && prev > 0 ? (cur - prev) / prev * 100 : null
}

export class StatChart {
  private hover = -1
  private sig = ''
  /** 宿主尺寸由 ResizeObserver 推过来：每帧读 clientWidth / clientHeight 会在刚改完 DOM 的那一帧强制布局（十六图挂机时每秒白付两次布局） */
  private W = 0
  private H = 0
  constructor(readonly kind: StatKind, readonly cv: HTMLCanvasElement) {
    cv.onmousemove = e => this.move(e)
    cv.onmouseleave = () => { this.hover = -1; hideCard(); this.draw(true) }
    const host = cv.parentElement
    if (host && typeof ResizeObserver !== 'undefined') {
      new ResizeObserver(es => { const r = es[es.length - 1]?.contentRect; if (r) { this.W = Math.round(r.width); this.H = Math.round(r.height); this.draw() } }).observe(host)
    }
  }

  private first(now: number): number { return slotOf(now) - (SLOTS - 1) * SLOT_MS }
  private xOf(t: number, now: number, W: number): number {
    const w = (W - PAD_L - PAD_R) / SLOTS
    return PAD_L + ((t - this.first(now)) / SLOT_MS + 0.5) * w
  }

  /** 数据或尺寸变了才重画（force 忽略） */
  draw(force = false): void {
    const cv = this.cv, host = cv.parentElement
    if (!host || !cv.isConnected) return
    if (!this.W || !this.H) { this.W = host.clientWidth; this.H = host.clientHeight }
    const W = this.W, H = this.H
    if (!W || !H) return
    const now = Date.now()
    const ver = this.kind === 'liq' ? OF.liq.version : OF.vol.version
    const sig = `${ver}|${W}|${H}|${this.hover}|${slotOf(now)}|${OF.feed?.symbol ?? ''}|${OF.pending}|${this.kind === 'liq' ? OF.liq.status : OF.vol.status}`
    if (!force && sig === this.sig) return
    this.sig = sig
    const dpr = window.devicePixelRatio || 1
    if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) {
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr)
      cv.style.width = W + 'px'; cv.style.height = H + 'px'
    }
    const c = cv.getContext('2d')!
    c.setTransform(dpr, 0, 0, dpr, 0, 0)
    c.clearRect(0, 0, W, H)
    const p = palette(cv)
    this.axis(c, W, H, now, p)
    if (this.kind === 'liq') this.drawLiq(c, W, H, now, p)
    else this.drawVol(c, W, H, now, p)
  }

  /** 底边的时间刻度：上海时间每 6 小时一个 */
  private axis(c: CanvasRenderingContext2D, W: number, H: number, now: number, p: Pal): void {
    c.font = canvasFont(10); c.fillStyle = p.text3; c.textBaseline = 'alphabetic'; c.textAlign = 'center'
    const first = this.first(now)
    for (let i = 0; i < SLOTS; i++) {
      const t = first + i * SLOT_MS
      const shH = Math.floor(((t / 3_600_000 + 8) % 24 + 24) % 24), shM = Math.round((t / 60_000) % 60)
      if (shM !== 0 || shH % 6 !== 0) continue
      const x = this.xOf(t, now, W) - (W - PAD_L - PAD_R) / SLOTS / 2
      if (x < PAD_L + 12 || x > W - PAD_R - 12) continue
      c.fillText(hm(t), x, H - 3)
    }
    c.fillStyle = hexA(p.text3, 0.18); c.fillRect(PAD_L, H - PAD_B, W - PAD_L - PAD_R, 1)
  }

  private hint(c: CanvasRenderingContext2D, W: number, H: number, p: Pal, t: string): void {
    c.font = canvasFont(12); c.fillStyle = p.text3; c.textAlign = 'center'; c.textBaseline = 'middle'
    c.fillText(t, W / 2, (H - PAD_B) / 2 + 4)
  }
  private note(c: CanvasRenderingContext2D, p: Pal, t: string, right?: string, W = 0): void {
    c.font = canvasFont(10); c.fillStyle = p.text3; c.textBaseline = 'alphabetic'
    c.textAlign = 'left'; c.fillText(t, PAD_L, 11)
    if (right) { c.textAlign = 'right'; c.fillText(right, W - PAD_R, 11) }
  }

  // ---------------------------------------------------------------- 流动性

  private drawLiq(c: CanvasRenderingContext2D, W: number, H: number, now: number, p: Pal): void {
    if (!OF.feed) { this.hint(c, W, H, p, feedIdleText()); return }
    const pts = OF.liq.points(now)
    if (!pts.length) { this.hint(c, W, H, p, OF.liq.status === 'loading' || OF.liq.status === 'idle' ? '正在取 24 小时深度…' : '正在记第一个点…'); return }
    const max = Math.max(1, ...pts.map(x => Math.max(x.bid, x.ask))) * 1.08
    const y = (v: number): number => PAD_T + (1 - v / max) * (H - PAD_T - PAD_B)
    const hasSrv = pts.some(x => x.src === 'server')
    const firstLive = pts.find(x => x.src === 'live')
    this.note(c, p, hasSrv ? '中间价 ±2.5% · 30 分钟一点' : `服务端没跟这只 · 自 ${hm(firstLive?.t ?? now)} 起`, `峰 ${amt(max / 1.08)}`, W)
    const line = (k: 'bid' | 'ask', col: string): void => {
      // 相邻格才连线，断开的格不补
      c.strokeStyle = col; c.lineWidth = 1.5; c.lineJoin = 'round'
      c.beginPath()
      let prev: LiqPoint | null = null
      for (const q of pts) {
        const x = this.xOf(q.t, now, W), yy = y(q[k])
        if (prev && q.t - prev.t === SLOT_MS) c.lineTo(x, yy); else c.moveTo(x, yy)
        prev = q
      }
      c.stroke()
      c.fillStyle = col
      for (let i = 0; i < pts.length; i++) {
        const q = pts[i], a = pts[i - 1], b = pts[i + 1]
        const lone = (!a || q.t - a.t !== SLOT_MS) && (!b || b.t - q.t !== SLOT_MS)
        if (lone) { c.beginPath(); c.arc(this.xOf(q.t, now, W), y(q[k]), 2, 0, Math.PI * 2); c.fill() }
      }
    }
    line('ask', p.down); line('bid', p.up)
    const h = this.hover >= 0 ? pts.find(q => q.t === this.first(now) + this.hover * SLOT_MS) : undefined
    if (h) {
      const x = this.xOf(h.t, now, W)
      c.fillStyle = hexA(p.text1, 0.18); c.fillRect(Math.round(x), PAD_T - 2, 1, H - PAD_T - PAD_B + 2)
      for (const [v, col] of [[h.bid, p.up], [h.ask, p.down]] as [number, string][]) {
        c.fillStyle = col; c.beginPath(); c.arc(x, y(v), 3, 0, Math.PI * 2); c.fill()
      }
    }
  }

  // ---------------------------------------------------------------- 成交

  private drawVol(c: CanvasRenderingContext2D, W: number, H: number, now: number, p: Pal): void {
    if (!OF.feed) { this.hint(c, W, H, p, feedIdleText()); return }
    const slots = OF.vol.slots
    if (!slots.some(s => s.total > 0)) { this.hint(c, W, H, p, OF.vol.status === 'down' ? '各家 K 线暂时取不到' : '正在取各家 30 分钟 K 线…'); return }
    const { split, total } = volSplitNames(OF.vol.exchanges)
    this.note(c, p, total.length ? `灰柱各家合计 · ${total.join(' / ')} 只计总额` : `灰柱合计 · 线为${split.join(' / ')}主动买 / 卖`, undefined, W)
    const max = Math.max(1, ...slots.map(s => s.total)) * 1.05
    const base = H - PAD_B
    const y = (v: number): number => base - v / max * (base - PAD_T)
    const bw = (W - PAD_L - PAD_R) / SLOTS
    for (let i = 0; i < slots.length; i++) {
      const s = slots[i]
      if (!(s.total > 0)) continue
      const x = this.xOf(s.t, now, W)
      c.fillStyle = hexA(p.text3, i === this.hover ? 0.36 : 0.18)
      c.fillRect(Math.round(x - bw / 2 + 1), y(s.total), Math.max(1, Math.round(bw - 2)), base - y(s.total))
    }
    const wave = (k: 'buy' | 'sell', col: string): void => {
      const ok = slots.filter(s => s.total > 0)
      if (!ok.length) return
      c.beginPath()
      c.moveTo(this.xOf(ok[0].t, now, W), base)
      for (const s of ok) c.lineTo(this.xOf(s.t, now, W), y(s[k]))
      c.lineTo(this.xOf(ok[ok.length - 1].t, now, W), base)
      c.closePath()
      c.fillStyle = hexA(col, 0.16); c.fill()
      c.beginPath()
      ok.forEach((s, i) => { const x = this.xOf(s.t, now, W); if (i) c.lineTo(x, y(s[k])); else c.moveTo(x, y(s[k])) })
      c.strokeStyle = col; c.lineWidth = 1.25; c.lineJoin = 'round'; c.stroke()
    }
    wave('sell', p.down); wave('buy', p.up)
  }

  // ---------------------------------------------------------------- 悬停

  private move(e: MouseEvent): void {
    const W = this.cv.clientWidth
    const w = (W - PAD_L - PAD_R) / SLOTS
    const i = Math.max(0, Math.min(SLOTS - 1, Math.floor((e.offsetX - PAD_L) / w)))
    const now = Date.now()
    const t = this.first(now) + i * SLOT_MS
    const html = this.kind === 'liq' ? liqCard(OF.liq.points(now), t, now) : volCard(OF.vol.slots.find(s => s.t === t), t, now)
    const next = html ? i : -1
    if (next !== this.hover) { this.hover = next; this.draw(true) }
    if (html) showCard(html, e.clientX, e.clientY); else hideCard()
  }
}

function liqCard(pts: LiqPoint[], t: number, now: number): string {
  const i = pts.findIndex(q => q.t === t)
  if (i < 0) return ''
  const q = pts[i], prev = pts[i - 1] && pts[i - 1].t === t - SLOT_MS ? pts[i - 1] : undefined
  const ch = (v: number, pv: number | undefined): string => {
    const x = changePct(v, pv)
    return x == null ? '' : ` <em class="${x >= 0 ? 'up' : 'down'}">${signedPct(x, 1)}</em>`
  }
  return `<div class="of-card-h">${slotLabel(t)}${t === slotOf(now) ? ' · 进行中' : ''}</div>
    <div class="of-card-r"><span>买 · ±2.5%</span><b class="num up">${amt(q.bid)}${ch(q.bid, prev?.bid)}</b></div>
    <div class="of-card-r"><span>卖 · ±2.5%</span><b class="num down">${amt(q.ask)}${ch(q.ask, prev?.ask)}</b></div>
    <div class="of-card-foot">${prev ? '百分比是相对上一个 30 分钟' : '上一个 30 分钟没有记录'} · ${q.src === 'server' ? '服务端深度快照的均值' : '本页实时取样的均值'}</div>`
}

/** 这次并进来的各家里：K 线带主动买（拆买卖）的、只有总额的，各自的显示名 */
function volSplitNames(exchanges: readonly string[]): { split: string[]; total: string[] } {
  const split: string[] = [], total: string[] = []
  for (const a of VENUE_LIST) if (exchanges.includes(a.key)) (a.takerSplit ? split : total).push(a.label)
  return { split, total }
}

function volCard(s: VolSlot | undefined, t: number, now: number): string {
  if (!s || !(s.total > 0)) return ''
  const { split, total } = volSplitNames(OF.vol.exchanges)
  const who = split.join(' / ')
  const bs = s.buy + s.sell
  const rows = [`<div class="of-card-r"><span>各家合计</span><b class="num">${amt(s.total)}</b></div>`]
  if (bs > 0) {
    rows.push(`<div class="of-card-r"><span>${who} 主动买</span><b class="num up">${amt(s.buy)} <em>${(s.buy / bs * 100).toFixed(0)}%</em></b></div>`)
    rows.push(`<div class="of-card-r"><span>${who} 主动卖</span><b class="num down">${amt(s.sell)} <em>${(s.sell / bs * 100).toFixed(0)}%</em></b></div>`)
  }
  VENUE_LIST.forEach((a, i) => { if (!a.takerSplit && s.ex[i] > 0) rows.push(`<div class="of-card-r"><span>${a.label}</span><b class="num">${amt(s.ex[i])}</b></div>`) })
  return `<div class="of-card-h">${slotLabel(t)}${t === slotOf(now) ? ' · 进行中' : ''}</div>${rows.join('')}${total.length ? `
    <div class="of-card-foot">${total.join(' / ')} 只计总额（K 线没有主动买）</div>` : ''}`
}

/** 标题行右边的数：流动性给现在的买 / 卖，成交给 24 小时合计 */
export function statHead(kind: StatKind): string {
  if (!OF.feed) return ''
  if (kind === 'liq') {
    const n = OF.liq.now
    return n ? `<span class="num up">买 ${amt(n[0])}</span><span class="num down">卖 ${amt(n[1])}</span>` : ''
  }
  const sum = OF.vol.slots.reduce((a, s) => a + s.total, 0)
  return sum > 0 ? `<span class="num faint">24h ${amt(sum)}</span>` : ''
}

/** 「每秒成交」一行的数据：读数文字 + 最近两分钟小折线的 path；没有数据时 null */
export function tpsLine(): { txt: string; d: string } | null {
  if (!OF.feed) return null
  const now = Date.now()
  const r = OF.tps.rate(now)
  if (r == null) return null
  const s = OF.tps.series(now)
  const max = Math.max(1, ...s)
  const d = s.map((v, i) => `${i ? 'L' : 'M'}${(i / (s.length - 1) * TPS_W).toFixed(1)},${(TPS_H - 1 - v / max * (TPS_H - 2)).toFixed(1)}`).join('')
  return { txt: `${r >= 10 ? r.toFixed(0) : r.toFixed(1)} 笔`, d }
}
const TPS_W = 96, TPS_H = 16
/** 「每秒成交」一行的外壳（读数与折线由调用方每帧就地改：整块重写会把带悬停说明的那一格换掉，说明跑到左上角） */
export const TPS_SHELL = `<div class="of-tps" data-tip="各家逐笔合流，最近 10 秒的平均；小线是最近两分钟"><span class="faint">每秒成交</span><b class="num"></b>
    <svg class="of-tps-sp" width="${TPS_W}" height="${TPS_H}" viewBox="0 0 ${TPS_W} ${TPS_H}" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="1.25"/></svg></div>`
