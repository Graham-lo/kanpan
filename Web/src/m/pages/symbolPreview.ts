/* 手机网页版 · 长按一行品种弹出来的预览卡 + 菜单（照 iOS Symbols/SymbolPreviewCard.swift 与 contextMenu { } preview: { }）
 *
 * 卡：徽章 · 名字 · 最新价 · 涨跌药丸 · 一段 1 小时 × 60 根的迷你 K 线 · 几格数（1/4 小时、24 小时高/低、持仓量、成交额、市值、费率）。
 * 它只摆已经有的事实、不做交互；要动手的都在卡下面那份菜单里。背后整片压暗加模糊，点空白处收起。
 * 菜单项可以带一层子菜单（「移到分类 ›」）：点了就在原地换成子菜单，顶上一行「‹ 标题」回上一层。
 *
 * 取数一律走现成的路：价、涨跌、成交额、高低、费率读全市场推送那本 S.symbols；持仓量走 fetchDetail（一分钟最多一次），
 * 供应量走 wantMeta；K 线按品种记着，最多 24 个（model/preview 的 RecentKeys）。
 */
import '../styles/favorites.css'
import '../styles/symbolPreview.css'
import { openMenu, type MenuItem, type Popover } from '../ui/sheet'
import { el, esc, safeArea } from '../ui/dom'
import { icon } from '../ui/icons'
import { life } from '../model/life'
import { S, on, klines, fetchDetail, detailOf, wantMeta } from '../../market'
import { assetOf, badgeHTML } from '../model/badge'
import { changePercentText, MISSING, priceText } from '../model/rowText'
import { pillHTML, splitSymbol } from '../model/rowHTML'
import { historyChange, miniCandles, RecentKeys, PREVIEW_BARS, PREVIEW_IV, PREVIEW_MINUTE_BARS, PREVIEW_SPAN_TEXT, type PreviewBar } from '../model/preview'
import { fundingText, marketCapText, openInterestText, turnoverText } from './chart/logic'
import { ago } from '../../util/clock'
import { pairOf, venueTagHTML } from '../model/symKey'
import { tableLive } from '../model/quoteCache'

/** 菜单里的一项；带 submenu 的点了不关，原地换成子菜单 */
export interface PreviewItem extends MenuItem { submenu?: () => MenuItem[] }

/** 行上写的那份价 / 涨跌（板块页按所选窗口算的）；hiLo = 这份价是不是 24 小时口径（不是就不摆 24 小时高 / 低） */
export interface PreviewQuote { price: number | null; pct: number | null; vol: number | null; hiLo: boolean }

export interface PreviewOptions {
  symbol: string
  /** 摆「1小时 / 4小时」那一行（只有自选页：它另取逐分钟走势；没传就不摆，不拿 1 小时线去凑） */
  recent?: boolean
  /** 不给就读推送里的 24 小时那份 */
  quote?: () => PreviewQuote
  /** 已下架 / 目录里没有：由实时价算出来的几格一律空着，和列表同一个判据 */
  gone?: () => boolean
}

// ---------------------------------------------------------------- 取数（按品种记着）
interface Series { at: number; bars: PreviewBar[] }
const hourly = new Map<string, Series>()
const minutely = new Map<string, Series>()
const inflight = new Set<string>()
const recentKeys = new RecentKeys()
/** 1 小时线十分钟内不重取；逐分钟走势一分钟内不重取 */
const HOURLY_FRESH = 10 * 60_000, MINUTE_FRESH = 60_000

function touch(sym: string): void {
  for (const k of recentKeys.touch(sym)) { hourly.delete(k); minutely.delete(k) }
}
async function load(sym: string, iv: string, limit: number, book: Map<string, Series>, fresh: number, done: () => void): Promise<void> {
  const prev = book.get(sym)
  const key = sym + '@' + iv
  if ((prev && ago(prev.at) < fresh) || inflight.has(key)) return
  inflight.add(key)
  try {
    const r = await klines(sym, iv, undefined, limit, false)
    if (r.ok && r.bars.length) { book.set(sym, { at: Date.now(), bars: r.bars }); touch(sym); done() }
  } finally { inflight.delete(key) }
}

// ---------------------------------------------------------------- 卡
const cell = (label: string, value: string | null, k: string): string =>
  `<div class="pv-cell" data-k="${k}"><span class="pv-label">${esc(label)}</span><span class="pv-val num${value == null || value === MISSING ? ' none' : ''}">${esc(value ?? MISSING)}</span></div>`

function cardHTML(o: PreviewOptions): string {
  const s = S.symbols.get(o.symbol)
  // 别家（2026-10-08）：名字前带交易所缩写，计价币按那一家（USDC / USD）
  const venue = o.symbol.includes('/')
  const p = pairOf(o.symbol, s)
  const { base, quote } = s && !venue ? { base: s.base, quote: splitSymbol(o.symbol).quote || 'USDT' } : venue ? p : splitSymbol(o.symbol)
  return `<div class="pv-head">${badgeHTML(s?.base ?? base, 28, assetOf(s?.kind, s?.base ?? base))}`
    + `<div class="pv-name"><div class="pv-top">${venueTagHTML(o.symbol)}<span class="pv-base">${esc(base)}</span><span class="pv-quote">${esc(quote || (venue ? '' : 'USDT'))}</span></div>`
    + `<div class="pv-span">${esc(PREVIEW_SPAN_TEXT)}</div></div>`
    + `<div class="pv-right"><span class="pv-price num"></span><span class="pv-pill"></span></div></div>`
    + `<div class="pv-candles"><canvas aria-hidden="true"></canvas></div>`
    + `<div class="pv-stats"></div>`
}

/** 卡上要写的数（纯取值，渲染在 paint 里） */
function factsOf(o: PreviewOptions): { price: number | null; pct: number | null; dec?: number | null; gone: boolean; rows: [string, string | null, string][][] } {
  const s = S.symbols.get(o.symbol)
  const gone = o.gone?.() ?? (!s && tableLive(o.symbol))
  const q = o.quote?.() ?? { price: s?.price ?? null, pct: s?.pct ?? null, vol: s?.vol ?? null, hiLo: true }
  const price = q.price != null && Number.isFinite(q.price) ? q.price : null
  const pct = !gone && q.pct != null && Number.isFinite(q.pct) ? q.pct : null
  const fresh = !gone
  const dec = s?.dec
  const pos = (v: number | null | undefined): string | null => v != null && Number.isFinite(v) && v > 0 ? priceText(v, dec) : null
  const rows: [string, string | null, string][][] = []
  if (o.recent) {
    const m = minutely.get(o.symbol)?.bars
    const ch = (h: number): string | null => { if (gone) return null; const v = historyChange(m, s?.price ?? price, h); return v == null ? null : changePercentText(v) }
    rows.push([['1小时', ch(1), 'h1'], ['4小时', ch(4), 'h4']])
  }
  rows.push([['24小时高', fresh && q.hiLo ? pos(s?.hi) : null, 'hi'], ['24小时低', fresh && q.hiLo ? pos(s?.lo) : null, 'lo']])
  rows.push([['持仓量', openInterestText(detailOf(o.symbol)?.oiValue), 'oi'], ['成交额', turnoverText(q.vol, fresh), 'vol']])
  rows.push([['市值', marketCapText(s?.supply, price, fresh), 'cap'], ['费率', fundingText(s?.fr, fresh).text, 'fr']])
  return { price, pct, dec, gone, rows }
}

function paintFacts(card: HTMLElement, o: PreviewOptions): void {
  const f = factsOf(o)
  const p = card.querySelector<HTMLElement>('.pv-price')!
  p.textContent = f.price == null ? MISSING : priceText(f.price, f.dec)
  // 价格色：已下架退成次要文字色；否则跟涨跌走，没涨跌是正文色
  p.className = 'pv-price num' + (f.gone ? ' gone' : f.pct == null ? '' : f.pct >= 0 ? ' up' : ' down')
  const pill = card.querySelector<HTMLElement>('.pv-pill')!
  const pillNext = pillHTML(f.pct, undefined, f.gone)
  if (pill.innerHTML !== pillNext) pill.innerHTML = pillNext
  const stats = card.querySelector<HTMLElement>('.pv-stats')!
  const html = f.rows.map(r => r.map(([l, v, k]) => cell(l, v, k)).join('')).join('')
  if (stats.innerHTML !== html) stats.innerHTML = html
}

/** 迷你 K 线：按设备倍率画，蜡烛取图上的涨跌色；还没到货时只摆那块底色，不写「加载中」 */
function paintCandles(card: HTMLElement, sym: string): void {
  const box = card.querySelector<HTMLElement>('.pv-candles')!
  const cv = box.querySelector('canvas')!
  const bars = hourly.get(sym)?.bars ?? []
  const w = cv.clientWidth, h = cv.clientHeight
  if (!w || !h) return
  const dpr = window.devicePixelRatio || 1
  cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr)
  const ctx = cv.getContext('2d'); if (!ctx) return
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  ctx.clearRect(0, 0, w, h)
  const css = getComputedStyle(box)
  const up = css.getPropertyValue('--k-up').trim() || '#2EBD85', down = css.getPropertyValue('--k-down').trim() || '#E35561'
  // 影线 1 物理像素对齐
  const snap = (x: number): number => (Math.round(x * dpr) + 0.5) / dpr
  for (const g of miniCandles(bars, w, h)) {
    ctx.fillStyle = g.up ? up : down
    ctx.fillRect(snap(g.x) - 0.5, g.wickTop, 1, Math.max(1, g.wickBottom - g.wickTop))
    ctx.fillRect(g.x - g.bodyW / 2, g.bodyTop, g.bodyW, g.bodyH)
  }
}

// ---------------------------------------------------------------- 菜单
function menuButton(it: MenuItem, lead: boolean, sub: boolean): HTMLButtonElement {
  const l = it.checked ? icon('check', 15) : it.icon ? icon(it.icon, 18) : ''
  const b = el('button', 'm-menu-item' + (it.destructive ? ' danger' : '') + (it.checked ? ' checked' : '') + (sub ? ' pv-has-sub' : ''),
    `${lead ? `<span class="m-menu-lead">${l}</span>` : ''}<span class="m-menu-title">${esc(it.title)}</span>${sub ? `<span class="pv-sub-mark">${icon('chevronRight', 14)}</span>` : ''}`)
  b.type = 'button'; b.setAttribute('role', 'menuitem'); b.disabled = !!it.disabled
  return b
}

/** 在 row 上弹「预览卡 + 菜单」。返回菜单那层（关掉时卡一起走） */
export function openPreviewMenu(row: HTMLElement, opts: PreviewOptions, items: (PreviewItem | null)[]): Popover {
  const L = life()
  const sym = opts.symbol
  const pop = openMenu(row, items.map(it => it), () => L.end())
  const menu = pop.root
  const wrap = menu.parentElement!
  wrap.classList.add('pv')
  const card = el('div', 'pv-card', cardHTML(opts))
  card.setAttribute('role', 'group')
  card.setAttribute('aria-label', `${sym} 预览`)
  wrap.insertBefore(card, menu)
  // 点卡本身也收起（iOS 点预览是「打开」，这里卡只回答「现在什么样」，点哪儿都当看完了）
  card.addEventListener('click', () => pop.close())

  // 顶层菜单：带子菜单的那一项改成原地展开
  const top = items.filter((x): x is PreviewItem => !!x)
  const renderTop = (): void => {
    const lead = top.some(it => it.icon || it.checked !== undefined)
    menu.replaceChildren()
    items.forEach(it => {
      if (!it) { menu.appendChild(el('div', 'm-menu-sep')); return }
      const b = menuButton(it, lead, !!it.submenu)
      b.onclick = it.submenu ? () => renderSub(it) : () => { pop.close(); it.run() }
      menu.appendChild(b)
    })
    layout()
  }
  const renderSub = (parent: PreviewItem): void => {
    const subs = parent.submenu!()
    menu.replaceChildren()
    const back = el('button', 'm-menu-item pv-sub-head', `<span class="m-menu-lead">${icon('chevronLeft', 15)}</span><span class="m-menu-title">${esc(parent.title)}</span>`)
    back.type = 'button'; back.setAttribute('aria-label', '返回')
    back.onclick = renderTop
    menu.appendChild(back)
    menu.appendChild(el('div', 'm-menu-sep'))
    subs.forEach(it => {
      const b = menuButton(it, true, false)
      b.onclick = () => { pop.close(); it.run() }
      menu.appendChild(b)
    })
    layout()
  }

  /** 卡横向居中、竖向尽量停在原来那一行的位置；菜单左对齐挂在卡下面 8；整块放不下就往上推，顶住安全区 */
  function layout(): void {
    const vw = innerWidth, vh = window.visualViewport?.height ?? innerHeight
    const safe = safeArea()
    const cardW = Math.min(272, vw - 24)
    card.style.width = cardW + 'px'
    const left = Math.round((vw - cardW) / 2)
    const cardH = card.offsetHeight, menuH = menu.offsetHeight
    const total = cardH + 8 + menuH
    const minTop = safe.top + 12, maxTop = vh - safe.bottom - 12 - total
    const want = row.getBoundingClientRect().top
    const topY = Math.round(Math.max(minTop, Math.min(want, maxTop)))
    card.style.left = left + 'px'
    card.style.top = topY + 'px'
    menu.style.right = 'auto'
    menu.style.left = left + 'px'
    menu.style.top = (topY + cardH + 8) + 'px'
    menu.style.transformOrigin = 'left top'
  }

  const paint = L.frame(() => { paintFacts(card, opts); paintCandles(card, sym) })
  renderTop()
  paintFacts(card, opts)
  layout()
  paintCandles(card, sym)

  touch(sym)
  void load(sym, PREVIEW_IV, PREVIEW_BARS, hourly, HOURLY_FRESH, L.guard(paint))
  if (opts.recent) void load(sym, '1m', PREVIEW_MINUTE_BARS, minutely, MINUTE_FRESH, L.guard(paint))
  void fetchDetail(sym, () => !L.ended)
  wantMeta([sym])
  L.add(on(e => {
    if (e.type === 'meta' || e.type === 'universe' || ((e.type === 'ticker' || e.type === 'detail' || e.type === 'mark') && e.symbol === sym)) paint()
  }))
  L.listen(window, 'resize', () => layout())
  return pop
}
