/* Hkline 手机网页 · 半页「盘口要点」（照 docs/原型-手机首页异动与盘口要点-2026-10-10.html 的 halfSheet()）
 *
 * 只有一档：顶边 = 行情头下沿（价格 + 涨跌 + 六格露着，周期条以下全盖住），盖住底栏，内容可滚。
 *   · 关：拖拽条 / 标题行往下拉，或正文滚到顶再往下拉过 80（或甩一下）；点露出来的行情头；系统返回。
 *   · 四块：流向 · 关键价位（区间行 + 上方两条 + 现价 + 下方两条，点一条展开证据，再点收起）·
 *     持仓 / 费率 / 现货溢价（只在异常时出）· 近 4 小时事件（点一条回图）。
 *   · 新出现的块边框亮 600 ms；从首页进来指定的那张卡亮 1.2 s。
 * 这里只管 DOM 与手势；数从哪来、什么时候刷新在 highlights.ts。
 */
import { el, layer, reducedMotion, setHTML, setText } from '../../ui/dom'
import { pushLayer } from '../../ui/sheet'
import { liuliBackdropHTML } from '../../ui/liuli'
import { HL, fill } from '../../../terms'
import type { Highlights, HlEvent, Level } from '../../../highlights/api'
import {
  usd, signedUsd, signedPct, brokenWord, bandPx, levelPx, hhmm, heldText, wallStateWord, refWord, levelFill, levelTotal,
  eventTime, eventSentence, eventIcon, flowLabel, positionCells, rangeHead, rangeEdgesText, levelMeta2, straddles, type EventIcon,
} from '../../../highlights/format'
import '../../styles/highlights.css'

/** 往下拉过这么多就关 */
export const CLOSE_PX = 80
const GHOST_MS = 400

export type SheetState =
  | { kind: 'loading' }
  | { kind: 'failed' }
  | { kind: 'data'; data: Highlights; price: number | null; now: number }

export type Focus = { kind: 'level'; id: string } | { kind: 'event'; id: string } | { kind: 'position' }

export interface HighlightsSheetHooks {
  /** 顶边放在哪（行情头下沿，视口坐标） */
  top(): number
  onClose(viaBack: boolean): void
  /** 点开 / 收起一条价位：图上带子跟着换（null = 收起） */
  onLevel(l: Level | null): void
  /** 「回图」：价位或事件 */
  onBack(t: { level: Level } | { event: HlEvent }): void
  onRetry(): void
}

// ───────────────────────────── 片段（纯函数，测试直接测）

const EVI: Record<EventIcon, string> = {
  wall: '<rect x="4" y="6" width="16" height="12" rx="2"/><path d="M4 12h16"/>',
  liq: '<path d="M13 3 5 14h6l-1 7 8-11h-6z"/>',
  trade: '<path d="M4 9h13l-3-3M20 15H7l3 3"/>',
  oi: '<path d="M5 18V10M11 18V5M17 18v-7M3 21h18"/>',
}
const svg = (inner: string, cls: string): string => `<svg class="${cls}" viewBox="0 0 24 24" aria-hidden="true">${inner}</svg>`
export const LOCATE = '<circle cx="12" cy="12" r="6"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3"/>'
const WIFI = '<path d="M2 8.5a15 15 0 0 1 20 0M5.5 12a10 10 0 0 1 13 0M9 15.5a5 5 0 0 1 6 0"/><circle cx="12" cy="19" r="1" fill="currentColor"/>'
const escA = (s: string): string => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const plain = (html: string): string => html.replace(/<[^>]+>/g, '')

export function flowBlockHTML(d: Highlights, now: number): string {
  const rows = d.flow
  if (!rows || !rows.length) return ''
  let mx = 0
  for (const r of rows) if (r.netUsd != null) mx = Math.max(mx, Math.abs(r.netUsd))
  const last = rows.length - 1
  const body = rows.map((r, i) => {
    const n = r.netUsd
    const w = n != null && mx > 0 ? (Math.abs(n) / mx) * 50 : 0
    const bar = n == null || w <= 0 ? '' : n >= 0 ? `<i class="u" style="left:50%;width:${w.toFixed(1)}%"></i>` : `<i class="d" style="right:50%;width:${w.toFixed(1)}%"></i>`
    const val = n == null ? '<b>—</b>' : `<b class="${n >= 0 ? 'up' : 'down'}">${signedUsd(n)}</b>`
    return `<span class="w${i === last && rows.length > 3 ? ' lg' : ''}">${escA(flowLabel(r, now))}${r.diverge ? `<em class="tag">${HL.diverge}</em>` : ''}</span>`
      + `<span class="nb"><span class="trk">${bar}</span>${val}</span><span class="v">${signedPct(r.pxPct)}</span><span class="v">${signedPct(r.oiPct)}</span>`
  }).join('')
  return `<div class="hl-blk" data-blk="flow"><div class="bt"><h5>${HL.flow}</h5><span class="cap">${HL.flowCaption}</span></div>`
    + `<div class="hl-flow"><span class="th"></span><span class="th">${HL.netTaker}</span><span class="th r">${HL.price}</span><span class="th r">${HL.oi}</span>${body}</div></div>`
}

function levelRowHTML(l: Level, mx: number, open: boolean): string {
  const seg = (v: number, cls: string): string => (v > 0 ? `<i class="${cls}" style="width:${Math.max(1.5, (v / mx) * 100).toFixed(1)}%"></i>` : '')
  const fillUsd = levelFill(l)
  const meta1 = l.wallUsd > 0
    ? `${escA(HL.wall)} <b>${usd(l.wallUsd)}</b>${l.wallHeldMs > 0 ? ` · ${escA(fill(HL.heldFor, { d: heldText(l.wallHeldMs) }))}` : ''}`
    : `${escA(HL.fill)} <b>${usd(fillUsd)}</b>`
  const meta2 = escA(levelMeta2(l))
  const row = `<button type="button" class="row${open ? ' open' : ''} ${l.side}" data-lv="${escA(l.id)}" aria-expanded="${open}">`
    + `<span class="px">${bandPx(l.low, l.high)}</span>`
    + `<span class="bar">${seg(l.wallUsd, 'w')}${seg(fillUsd, 'f')}${seg(l.liqUsd, 'q')}</span>`
    + `<span class="meta">${meta1}${meta2 ? `<br>${meta2}` : ''}</span></button>`
  if (!open) return row
  const ev: [string, string][] = []
  if (fillUsd > 0) ev.push([HL.fill, escA(fill(HL.fillBuySell, { a: '\u0001', b: usd(l.fillSellUsd) })).replace('\u0001', `<b>${usd(l.fillBuyUsd)}</b>`)])
  if (l.wallUsd > 0 || l.wallState) {
    const parts = [l.wallUsd > 0 ? `<b>${usd(l.wallUsd)}</b>` : '']
    if (l.wallHeldMs > 0) parts.push(escA(fill(HL.heldFor, { d: heldText(l.wallHeldMs) })))
    const word = wallStateWord(l.wallState, l.cancelPct, l.side)
    if (word) parts.push(escA(word))
    ev.push([HL.wall, parts.filter(Boolean).join(' · ')])
  }
  if (l.liqUsd > 0) ev.push([HL.liq, `<b>${usd(l.liqUsd)}</b>`])
  const touches = l.touchMs.filter((t): t is number => t != null)
  const uniq = [...new Set(touches.map(hhmm))]
  const broken = l.wallState === 'broken'
  ev.push([HL.touch, [...uniq, broken ? brokenWord(l.side) : HL.unbroken].map(escA).join(' · ')])
  if (l.refs.length) ev.push([HL.overlap, l.refs.map(r => `= ${escA(refWord(r))}`).join(' · ')])
  return row + `<div class="lev">${ev.map(([k, v]) => `<s>${escA(k)}</s><span>${v}</span>`).join('')}`
    + `<button type="button" class="go" data-back="${escA(l.id)}">${svg(LOCATE, 'loc')}${HL.back}</button></div>`
}

export function levelsBlockHTML(d: Highlights, price: number | null, open: string | null, now: number): string {
  if (!d.levels.length && !d.range) return ''
  let mx = 0
  for (const l of d.levels) mx = Math.max(mx, levelTotal(l))
  if (!(mx > 0)) mx = 1
  // 包住现价的那条紧贴在现价线下面（不算上方也不算下方）
  const at = d.levels.filter(l => straddles(l, price))
  const above = d.levels.filter(l => !at.includes(l) && l.distPct > 0)
  const below = [...at, ...d.levels.filter(l => !at.includes(l) && l.distPct <= 0)]
  let rng = ''
  if (d.range) {
    const r = d.range, h = rangeHead(r, now)
    const pos = price != null && r.high > r.low ? Math.max(0, Math.min(100, ((price - r.low) / (r.high - r.low)) * 100)) : null
    const head = `${HL.range} <b>${h.band}</b> · ${escA(fill(HL.rangeAge, { h: h.hours }))}`
    rng = `<div class="rng"><div class="l1"><span>${head}</span><span class="rt">${pos != null ? `<i style="left:${pos.toFixed(1)}%"></i>` : ''}</span></div>`
      + `<div class="l2">${escA(rangeEdgesText(r))}</div></div>`
  }
  const nowRow = `<div class="now"><i></i>${escA(fill(HL.now, { p: price != null ? levelPx(price) : '—' }))}<i></i></div>`
  return `<div class="hl-blk" data-blk="levels"><div class="bt"><h5>${HL.levels}</h5><span class="cap"><i></i>${HL.wall}<i class="f"></i>${HL.fill}<i class="q"></i>${HL.liq}</span></div>`
    + `<div class="hl-lv">${rng}${above.map(l => levelRowHTML(l, mx, l.id === open)).join('')}${nowRow}${below.map(l => levelRowHTML(l, mx, l.id === open)).join('')}</div></div>`
}

export function positionBlockHTML(d: Highlights): string {
  const p = d.position
  if (!p || !p.show) return ''
  const cells = positionCells(p).map(c => `<div class="cell"><small>${escA(c.label)}</small><b>${escA(c.value)}</b><em>${escA(c.note || '—')}</em>`
    + `<span class="pct">${c.pctile != null ? `<i style="left:${Math.max(0, Math.min(100, c.pctile)).toFixed(0)}%"></i>` : ''}</span></div>`).join('')
  return `<div class="hl-blk" data-blk="position"><div class="bt"><h5>${HL.position}</h5><span class="cap">${HL.positionCaption}</span></div><div class="hl-tri">${cells}</div></div>`
}

export function eventsBlockHTML(d: Highlights): string {
  if (!d.events.length) return ''
  const items = d.events.slice(0, 4).map(e => `<button type="button" class="it" data-ev="${escA(e.id)}" aria-label="${escA(`${eventTime(e)} ${plain(eventSentence(e))}`)}">`
    + `<span class="t">${escA(eventTime(e))}</span><span class="ic">${svg(EVI[eventIcon(e)], 'evi')}</span><span class="x">${eventSentence(e)}</span><span class="go">${svg(LOCATE, 'loc')}</span></button>`).join('')
  return `<div class="hl-blk" data-blk="events"><div class="bt"><h5>${HL.events}</h5><span class="cap">${HL.eventsCaption}</span></div><div class="hl-evl">${items}</div></div>`
}

/** 价位与事件都还没有时那一句：服务端开盯不到 15 分钟 →「观察中 · 约 N 分钟」（N = 离 15 分钟还剩几分钟，至少 1）；
 *  盯满 15 分钟（或服务端没给开盯时刻）还什么都没有 →「近 4 小时没有值得注意的价位与事件」；有价位就都不写 */
export const OBSERVE_MS = 15 * 60_000
export type QuietState = { kind: 'none' } | { kind: 'observing'; minutes: number } | { kind: 'calm' }
export function quietState(d: Pick<Highlights, 'levels' | 'range' | 'events' | 'observingSinceMs'>, now: number): QuietState {
  if (d.levels.length) return { kind: 'none' }
  const since = d.observingSinceMs
  if (since != null && now - since < OBSERVE_MS) return { kind: 'observing', minutes: Math.max(1, Math.ceil((OBSERVE_MS - Math.max(0, now - since)) / 60_000)) }
  return !d.range && !d.events.length ? { kind: 'calm' } : { kind: 'none' }
}

export function bodyHTML(s: SheetState, open: string | null): string {
  if (s.kind === 'loading') return '<div class="hl-blk hl-skel"></div><div class="hl-blk hl-skel s2"></div>'
  if (s.kind === 'failed') return `<div class="hl-calm">${svg(WIFI, 'big')}<b>${HL.failed}</b><button type="button" class="hl-retry">${HL.retry}</button></div>`
  const d = s.data
  if (!d.tracked) return `<div class="hl-calm">${svg(WIFI, 'big')}<b>${HL.untracked}</b></div>`
  const q = quietState(d, s.now)
  const line = q.kind === 'observing' ? `<div class="hl-quiet obs">${escA(fill(HL.observing, { n: q.minutes }))}</div>`
    : q.kind === 'calm' ? `<div class="hl-quiet">${HL.quiet}</div>` : ''
  // 观察中那句紧跟在流向下面（价位、事件还没攒出来）；平静那句照旧在最后
  return flowBlockHTML(d, s.now) + (q.kind === 'observing' ? line : '') + levelsBlockHTML(d, s.price, open, s.now) + positionBlockHTML(d) + eventsBlockHTML(d)
    + (q.kind === 'calm' ? line : '')
}

// ───────────────────────────── 弹层

export class HighlightsSheet {
  readonly wrap: HTMLDivElement
  readonly root: HTMLDivElement
  private body: HTMLDivElement
  private upEl: HTMLElement
  private liveEl: HTMLElement
  private state: SheetState = { kind: 'loading' }
  private open: string | null = null
  private blocks = new Set<string>()
  private shut = false
  private unback: (() => void) | null = null
  private flashTimer: ReturnType<typeof setTimeout> | null = null

  constructor(private readonly hooks: HighlightsSheetHooks) {
    const wrap = this.wrap = el('div', 'hl-wrap')
    const catcher = el('div', 'hl-catch')
    const root = this.root = el('div', 'hl-sheet')
    root.setAttribute('role', 'dialog')
    root.setAttribute('aria-label', HL.title)
    root.innerHTML = `${liuliBackdropHTML(true)}<div class="hl-grab" aria-hidden="true"><i></i></div>
      <div class="hl-hdr"><h4>${HL.title}</h4><span class="hl-up"><span class="hl-live" aria-hidden="true"></span><span class="t"></span></span></div>
      <div class="hl-body"></div>`
    wrap.append(catcher, root)
    this.body = root.querySelector<HTMLDivElement>('.hl-body')!
    this.upEl = root.querySelector<HTMLElement>('.hl-up .t')!
    this.liveEl = root.querySelector<HTMLElement>('.hl-live')!
    catcher.addEventListener('click', () => this.close())
    const born = performance.now()
    wrap.addEventListener('click', e => { if (performance.now() - born < GHOST_MS) { e.stopPropagation(); e.preventDefault() } }, true)
    this.body.addEventListener('click', e => this.onTap(e))
    this.wireDrag()
    this.place()
    addEventListener('resize', this.place)
    layer().appendChild(wrap)
    this.unback = pushLayer(() => this.close(true))
    this.render()
    if (reducedMotion()) wrap.classList.add('in')
    else requestAnimationFrame(() => requestAnimationFrame(() => wrap.classList.add('in')))
  }

  get closed(): boolean { return this.shut }
  get openLevel(): string | null { return this.open }

  private place = (): void => {
    const top = Math.max(0, Math.round(this.hooks.top()))
    this.root.style.top = top + 'px'
    ;(this.wrap.firstElementChild as HTMLElement).style.height = top + 'px'
  }

  close(viaBack = false): void {
    if (this.shut) return
    this.shut = true
    removeEventListener('resize', this.place)
    this.unback?.(); this.unback = null
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.wrap.classList.remove('in')
    setTimeout(() => this.wrap.remove(), reducedMotion() ? 0 : 420)
    this.hooks.onClose(viaBack)
  }

  update(s: SheetState): void {
    if (this.shut) return
    this.state = s
    // 展开的那条没了（被合并 / 出视野）：收起，带子跟着撤
    if (this.open && (s.kind !== 'data' || !s.data.levels.some(l => l.id === this.open))) {
      if (s.kind === 'data') { this.open = null; this.hooks.onLevel(null) }
    }
    this.render()
  }

  /** 从首页进来：对应的卡展开并亮 1.2 秒 */
  focus(f: Focus): void {
    if (this.shut || this.state.kind !== 'data') return
    const d = this.state.data
    let sel = ''
    if (f.kind === 'level') {
      const l = d.levels.find(x => x.id === f.id)
      if (l) { this.open = l.id; this.hooks.onLevel(l); this.render(); sel = `[data-lv="${CSS.escape(l.id)}"]` }
      else sel = '[data-blk="levels"]'
    } else if (f.kind === 'event') {
      sel = d.events.some(e => e.id === f.id) ? `[data-ev="${CSS.escape(f.id)}"]` : '[data-blk="events"]'
    } else sel = '[data-blk="position"]'
    const node = this.body.querySelector<HTMLElement>(sel)
    if (!node) return
    node.scrollIntoView({ block: 'nearest', behavior: reducedMotion() ? 'auto' : 'smooth' })
    node.classList.add('flash')
    if (this.flashTimer) clearTimeout(this.flashTimer)
    this.flashTimer = setTimeout(() => node.classList.remove('flash'), 1200)
  }

  private render(): void {
    const s = this.state
    const stale = s.kind === 'data' && s.data.staleMs != null && s.data.staleMs > 0
    this.root.classList.toggle('stale', stale)
    this.liveEl.hidden = s.kind !== 'data' || stale || !s.data.tracked
    setText(this.upEl, s.kind !== 'data' || !s.data.tracked ? '' : stale
      ? fill(HL.staleSince, { t: hhmm(s.data.generatedAtMs - (s.data.staleMs ?? 0)) })
      : hhmm(s.data.generatedAtMs))
    const prev = this.blocks
    if (!setHTML(this.body, bodyHTML(s, this.open))) return
    const now = new Set<string>()
    this.body.querySelectorAll<HTMLElement>('[data-blk]').forEach(n => {
      const id = n.dataset.blk!
      now.add(id)
      if (prev.size && !prev.has(id) && !reducedMotion()) n.classList.add('fresh')
    })
    this.blocks = s.kind === 'data' ? now : new Set()
  }

  private onTap(e: MouseEvent): void {
    const t = e.target as Element
    if (t.closest('.hl-retry')) { this.hooks.onRetry(); return }
    const s = this.state
    if (s.kind !== 'data') return
    const back = t.closest<HTMLElement>('[data-back]')
    if (back) {
      const l = s.data.levels.find(x => x.id === back.dataset.back)
      if (l) this.hooks.onBack({ level: l })
      return
    }
    const ev = t.closest<HTMLElement>('[data-ev]')
    if (ev) {
      const x = s.data.events.find(y => y.id === ev.dataset.ev)
      if (x) this.hooks.onBack({ event: x })
      return
    }
    const row = t.closest<HTMLElement>('[data-lv]')
    if (row) {
      const id = row.dataset.lv!
      this.open = this.open === id ? null : id
      this.hooks.onLevel(this.open ? s.data.levels.find(x => x.id === id) ?? null : null)
      this.render()
    }
  }

  /** 只有一档：往下拉跟手，过 CLOSE_PX 或甩一下就关，不够就弹回 */
  private wireDrag(): void {
    let startY = 0, dy = 0, dragging = false, lastY = 0, lastT = 0, vel = 0
    const root = this.root
    const begin = (y: number): void => {
      startY = lastY = y; lastT = performance.now(); dy = 0; vel = 0; dragging = true
      root.classList.add('dragging')
    }
    const move = (y: number): void => {
      const now = performance.now()
      vel = (y - lastY) / Math.max(1, now - lastT); lastY = y; lastT = now
      dy = y - startY
      root.style.transform = dy > 0 ? `translateY(${dy}px)` : ''
    }
    const end = (): void => {
      if (!dragging) return
      dragging = false; root.classList.remove('dragging'); root.style.transform = ''
      if (dy > 0 && (dy > CLOSE_PX || vel > 0.6)) this.close()
    }
    for (const z of [root.querySelector<HTMLElement>('.hl-grab')!, root.querySelector<HTMLElement>('.hl-hdr')!]) {
      z.addEventListener('pointerdown', e => {
        try { z.setPointerCapture(e.pointerId) } catch { /* 合成事件没有指针 */ }
        begin(e.clientY)
      })
      z.addEventListener('pointermove', e => { if (dragging) move(e.clientY) })
      z.addEventListener('pointerup', end)
      z.addEventListener('pointercancel', end)
    }
    // 正文滚到顶时往下拉接手
    const body = this.body
    let touchY: number | null = null
    body.addEventListener('touchstart', e => { touchY = body.scrollTop <= 0 ? e.touches[0].clientY : null }, { passive: true })
    body.addEventListener('touchmove', e => {
      if (touchY == null) return
      const y = e.touches[0].clientY
      if (!dragging) { if (y - touchY > 6 && body.scrollTop <= 0) begin(touchY); else return }
      move(y)
      if (dy > 0 && e.cancelable) e.preventDefault()
    }, { passive: false })
    const tEnd = (): void => { touchY = null; end() }
    body.addEventListener('touchend', tEnd)
    body.addEventListener('touchcancel', tEnd)
  }
}
