/* 手机网页版 · 首页（照 docs/原型-手机首页异动与盘口要点-2026-10-10.html §01 / §02，iOS Home/）
 *
 * 底栏最左一格、启动默认。头部一行：分段「异动 · 榜单」+ 放大镜圆片。
 * 异动：分类胶囊（全部 / 盘口 / 持仓 / 费率）+ 一行范围与更新时刻 + 列表。打开时定序，之后每 60 s 拉一次，
 *   已有的行就地换数不换位，有新的只浮「有 N 条新异动」药丸；点药丸滚到顶重排，下拉刷新立即重排。
 *   点一行：放一份意图（展开哪张卡）再进行情页，行情页 240 ms 后自己升半页；横滑扫图名单 = 当时列表顺序。
 *   未登录只扫热门（不带自选）；登录后带上自选的币名，服务端自选层补跟。
 * 榜单：持仓变化 / 涨幅 / 跌幅三张卡，各自 1 时 / 4 时 / 24 时（出厂 4 时），每张 6 行，「全部」展开、「收起」收回。
 *   点一行进行情页，不升半页。
 * 分段、胶囊、三张卡的窗口只记在本机（不加同步字段）。
 */
import '../styles/favorites.css'
import '../styles/home.css'
import { st, save, subscribe } from '../app/store'
import { openSymbol, hooks, type PageHandle } from '../app/shell'
import { icon } from '../ui/icons'
import { backdropHTML } from './favorites'
import { openSearch } from './search'
import { setHighlightIntent } from './chart/highlightIntent'
import { S, on } from '../../market'
import { ensureUniverse } from './_streams'
import * as F from '../model/favorites'
import { assetOf, badgeHTML } from '../model/badge'
import { changePercentText, esc, priceText, textIsUp } from '../model/rowText'
import { session, onSession } from '../../account/session'
import { baseOfSymbol } from '../../orderflow/settings'
import { HL, fill } from '../../terms'
import { fetchBoard, fetchMarketBoard, type BoardRow, type BoardCat, type MarketKind, type MarketRow, type MarketWindow } from '../../highlights/api'
import { agoText, boardFact, hhmm, levelPx, signedPct, usd } from '../../highlights/format'
import { chipCounts, favoriteBases, filterRows, focusOf, mergeBoard, symbolFor, type Chip } from '../../highlights/home'

const LS_KEY = 'hkline-m-home-v1'
const POLL_MS = 60_000
const PULL_PX = 64
const CARD_ROWS = 6

type Seg = 'moves' | 'board'
interface Local { seg: Seg; chip: Chip; win: Record<MarketKind, MarketWindow> }

function loadLocal(): Local {
  const d: Local = { seg: 'moves', chip: 'all', win: { oi: '4h', gainers: '4h', losers: '4h' } }
  try {
    const v = JSON.parse(localStorage.getItem(LS_KEY) || 'null') as Partial<Local> | null
    if (v && (v.seg === 'moves' || v.seg === 'board')) d.seg = v.seg
    if (v && ['all', 'book', 'oi', 'funding'].includes(v.chip as string)) d.chip = v.chip as Chip
    for (const k of ['oi', 'gainers', 'losers'] as const) {
      const w = v?.win?.[k]
      if (w === '1h' || w === '4h' || w === '24h') d.win[k] = w
    }
  } catch { /* 本机存不了就用出厂 */ }
  return d
}

const CAT_TAG: Record<BoardCat, string> = { book: HL.catBook, oi: HL.catOi, funding: HL.catFunding }
const CAT_COLOR: Record<BoardCat, string> = { book: 'var(--accent)', oi: 'var(--amber)', funding: 'var(--ink2)' }
const CARD_TITLE: Record<MarketKind, string> = { oi: HL.boardOi, gainers: HL.boardGainers, losers: HL.boardLosers }
const WIN_LABEL: Record<MarketWindow, string> = { '1h': HL.win1h, '4h': HL.win4h, '24h': HL.win24h }
const KINDS: readonly MarketKind[] = ['oi', 'gainers', 'losers']

const baseOf = (symbol: string): string => baseOfSymbol(symbol).base
const symOf = (base: string): string => symbolFor(base, st.symbols.favorites, baseOf, s => S.symbols.has(s))
const isFav = (base: string): boolean => st.symbols.favorites.some(k => baseOf(k) === base)

function badge(base: string, size: number): string {
  const s = S.symbols.get(symOf(base))
  return badgeHTML(base, size, assetOf(s?.kind, base))
}
/** 品种表到了按它的小数位写；还没到按五位有效数字写（不补尾零，免得先出 12.1100 再跳成 12.11） */
function pxText(base: string, price: number | null): string {
  const dec = S.symbols.get(symOf(base))?.dec
  return dec != null ? priceText(price, dec) : price == null ? '—' : levelPx(price)
}

function pill(pct: number | null): string {
  const t = changePercentText(pct)
  if (pct == null) return `<span class="hm-pill none">${esc(t)}</span>`
  return `<span class="hm-pill ${textIsUp(t) ? 'up' : 'down'}">${esc(t)}</span>`
}

const meter = (t: 1 | 2 | 3): string =>
  `<span class="mt" aria-hidden="true"><i class="${t >= 1 ? 'on' : ''}" style="height:4px"></i><i class="${t >= 2 ? 'on' : ''}" style="height:7px"></i><i class="${t >= 3 ? 'on' : ''}" style="height:10px"></i></span>`

const STAR = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.2l2.7 5.5 6 .9-4.35 4.25 1.03 6L12 17l-5.38 2.85 1.03-6L3.3 9.6l6-.9z"/></svg>'
const ARROW_UP = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg>'
const CALM = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l2-3 3 6 2-3h7"/></svg>'

export function moveRowHTML(r: BoardRow, now: number): string {
  const star = isFav(r.base) ? '' : `<button type="button" class="st" data-star="${esc(r.base)}" aria-label="${esc(HL.addFavorite)}">${STAR}</button>`
  return `<div class="hm-row" role="listitem" data-base="${esc(r.base)}" style="--c:${CAT_COLOR[r.cat]}">${badge(r.base, 28)}<div class="mid">
    <div class="l1"><span class="nm"><span class="tk">${esc(r.base)}</span>${star}</span><span class="p">${esc(pxText(r.base, r.price))}</span>${pill(r.changePct)}</div>
    <div class="pt1"><span class="kind">${esc(CAT_TAG[r.cat])}</span>${meter(r.tier)}<span class="tx">${boardFact(r)}</span>${r.count > 1 ? `<span class="plus">+${r.count - 1}</span>` : ''}<span class="ago">${esc(agoText(r.atMs, now))}</span></div>
  </div></div>`
}

const SKELETON = Array.from({ length: 6 }, () => `<div class="hm-row skel" aria-hidden="true"><span class="sk sk-b"></span><div class="mid"><div class="l1"><span class="sk" style="width:70px;height:14px"></span><span style="flex:1"></span><span class="sk" style="width:60px;height:14px"></span><span class="sk" style="width:56px;height:20px"></span></div><div class="sk" style="width:62%;height:11px;margin-top:8px"></div></div></div>`).join('')

interface CardState { rows: MarketRow[] | null; failed: boolean; open: boolean; seq: number }

export function initHome(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'liuli')
  const L = loadLocal()
  const keep = (): void => { try { localStorage.setItem(LS_KEY, JSON.stringify(L)) } catch { /* 存不了就只在这一次有效 */ } }

  root.innerHTML = backdropHTML() + `
    <header class="fav-head hm-head">
      <div class="hm-seg" role="tablist"><button type="button" data-seg="moves" role="tab">${esc(HL.moves)}</button><button type="button" data-seg="board" role="tab">${esc(HL.board)}</button></div>
      <button type="button" class="fav-disc hm-search" aria-label="${esc(HL.search)}">${icon('search', 16)}</button>
    </header>
    <section class="hm-moves">
      <div class="hm-chips" role="tablist"></div>
      <div class="hm-sub"><span class="l"></span><span class="r"></span></div>
      <div class="hm-body">
        <div class="hm-ptr" aria-hidden="true">${icon('refresh', 16)}</div>
        <div class="hm-scroll"><div class="hm-list" role="list"></div></div>
        <button type="button" class="hm-newpill" hidden>${ARROW_UP}<span></span></button>
      </div>
    </section>
    <section class="hm-board"><div class="hm-scroll hm-cards"></div></section>`

  const q = <T extends HTMLElement>(s: string): T => root.querySelector<T>(s)!
  const segEl = q('.hm-seg'), movesEl = q('.hm-moves'), boardEl = q('.hm-board')
  const chipsEl = q('.hm-chips'), subL = q('.hm-sub .l'), subR = q('.hm-sub .r')
  const body = q('.hm-body'), ptr = q('.hm-ptr'), scroll = q('.hm-moves .hm-scroll'), list = q('.hm-list')
  const newPill = q<HTMLButtonElement>('.hm-newpill'), cardsEl = q('.hm-cards')

  let active = false
  let shown: BoardRow[] | null = null    // 正在显示的那份（定了序）
  let latest: BoardRow[] | null = null   // 最近一次拉到的
  let generatedAt = 0
  let failed = false
  let loading = false
  let reqSeq = 0
  let timer = 0
  const cards: Record<MarketKind, CardState> = {
    oi: { rows: null, failed: false, open: false, seq: 0 },
    gainers: { rows: null, failed: false, open: false, seq: 0 },
    losers: { rows: null, failed: false, open: false, seq: 0 },
  }

  // ───────── 异动 ─────────

  function renderChips(): void {
    const c = chipCounts(shown ?? [])
    const chip = (id: Chip, label: string, dot: string | null): string =>
      `<button type="button" role="tab" data-chip="${id}" class="${L.chip === id ? 'on' : ''}"${dot ? ` style="--c:${dot}"` : ''}>${dot ? '<i></i>' : ''}${esc(label)}${shown ? `<b>${c[id]}</b>` : ''}</button>`
    chipsEl.innerHTML = chip('all', HL.all, null) + chip('book', HL.catBook, CAT_COLOR.book) + chip('oi', HL.catOi, CAT_COLOR.oi) + chip('funding', HL.catFunding, CAT_COLOR.funding)
  }

  function renderSub(): void {
    const show = !!shown && shown.length > 0
    root.querySelector<HTMLElement>('.hm-sub')!.hidden = !show
    if (!show) return
    subL.textContent = session.userId ? fill(HL.favScope, { n: favoriteBases(st.symbols.favorites, baseOf).length }) : HL.guestHint
    subR.textContent = failed ? fill(HL.stoppedAt, { t: hhmm(generatedAt) }) : fill(HL.updatedAt, { t: hhmm(generatedAt) })
  }

  function renderList(): void {
    const now = Date.now()
    list.classList.toggle('stale', failed && !!shown)
    if (!shown) {
      list.innerHTML = failed
        ? `<div class="hm-empty"><span>${esc(HL.failed)}</span><button type="button" class="hm-retry">${esc(HL.retry)}</button></div>`
        : SKELETON
      return
    }
    if (!shown.length) {
      list.innerHTML = `<div class="hm-calm">${CALM}<b>${esc(HL.calmTitle)}</b><span>${esc(HL.calmSub)} · ${esc(fill(HL.updatedAt, { t: hhmm(generatedAt) }))}</span></div>`
      return
    }
    const rows = filterRows(shown, L.chip)
    list.innerHTML = rows.length ? rows.map(r => moveRowHTML(r, now)).join('') : `<div class="hm-empty"><span>${esc(HL.noRows)}</span></div>`
  }

  function renderPill(): void {
    if (!shown || !latest) { newPill.hidden = true; return }
    const { fresh } = mergeBoard(shown, latest)
    newPill.hidden = fresh === 0
    if (fresh) newPill.querySelector('span')!.textContent = fill(HL.newMoves, { n: fresh })
  }

  function renderMoves(): void { renderChips(); renderSub(); renderList(); renderPill() }

  /** 拉一份；reorder = 按服务端顺序重排（首次、点药丸、下拉刷新、换账号） */
  async function load(reorder: boolean): Promise<void> {
    const seq = ++reqSeq
    loading = true
    const bases = session.userId ? favoriteBases(st.symbols.favorites, baseOf) : []
    const r = await fetchBoard(bases)
    if (seq !== reqSeq) return
    loading = false
    if (!r.ok) { failed = true; if (active) renderMoves(); return }
    failed = false
    generatedAt = r.data.generatedAtMs
    latest = r.data.rows
    if (reorder || !shown) shown = latest
    else shown = mergeBoard(shown, latest).rows
    if (active) renderMoves()
  }

  function reorderNow(): void {
    if (!latest) return
    shown = latest
    newPill.hidden = true
    scroll.scrollTo({ top: 0, behavior: 'smooth' })
    renderMoves()
  }

  // ───────── 榜单 ─────────

  function cardHTML(kind: MarketKind): string {
    const c = cards[kind]
    const segs = (['1h', '4h', '24h'] as const).map(w => `<button type="button" data-win="${w}" class="${L.win[kind] === w ? 'on' : ''}">${esc(WIN_LABEL[w])}</button>`).join('')
    let rows: string
    if (c.rows == null) rows = c.failed
      ? `<div class="bempty"><span>${esc(HL.failed)}</span><button type="button" class="hm-retry" data-retry="${kind}">${esc(HL.retry)}</button></div>`
      : Array.from({ length: CARD_ROWS }, () => '<div class="br skel"><span class="sk" style="width:100%;height:12px;grid-column:1/-1"></span></div>').join('')
    else if (!c.rows.length) rows = `<div class="bempty"><span>${esc(HL.noRows)}</span></div>`
    else {
      const list = c.open ? c.rows : c.rows.slice(0, CARD_ROWS)
      rows = list.map((r, i) => {
        const v = kind === 'oi' ? (r.oiUsd != null ? usd(r.oiUsd) : '—') : pxText(r.base, r.price)
        const up = r.changePct >= 0
        return `<button type="button" class="br" data-base="${esc(r.base)}"><span class="i">${i + 1}</span>${badge(r.base, 22)}<span class="n">${esc(r.base)}</span><span class="v">${esc(v)}</span><span class="c ${up ? 'up' : 'down'}">${esc(signedPct(r.changePct))}</span></button>`
      }).join('')
      if (c.rows.length > CARD_ROWS) rows += `<button type="button" class="more" data-more="${kind}">${esc(c.open ? HL.collapse : HL.all)}${c.open ? '' : ' ›'}</button>`
    }
    return `<section class="hm-card${c.failed && c.rows ? ' stale' : ''}" data-kind="${kind}"><div class="bh"><h5>${esc(CARD_TITLE[kind])}</h5><div class="hm-seg sm">${segs}</div></div>${rows}</section>`
  }

  function renderBoard(): void { cardsEl.innerHTML = KINDS.map(cardHTML).join('') }
  function renderCard(kind: MarketKind): void {
    const old = cardsEl.querySelector(`.hm-card[data-kind="${kind}"]`)
    if (!old) { renderBoard(); return }
    old.outerHTML = cardHTML(kind)
  }

  async function loadCard(kind: MarketKind): Promise<void> {
    const c = cards[kind]
    const seq = ++c.seq
    const r = await fetchMarketBoard(kind, L.win[kind])
    if (seq !== c.seq) return
    if (r.ok) { c.rows = r.data.rows; c.failed = false } else c.failed = true
    if (active) renderCard(kind)
  }
  const loadCards = (): void => { KINDS.forEach(k => void loadCard(k)) }

  // ───────── 分段 / 轮询 ─────────

  function applySeg(): void {
    segEl.querySelectorAll<HTMLElement>('[data-seg]').forEach(b => {
      const on = b.dataset.seg === L.seg
      b.classList.toggle('on', on)
      b.setAttribute('aria-selected', String(on))
    })
    movesEl.hidden = L.seg !== 'moves'
    boardEl.hidden = L.seg !== 'board'
  }

  function tick(): void {
    if (!active || document.hidden) return
    if (L.seg === 'moves') void load(false)
    else loadCards()
  }
  function startPoll(): void { stopPoll(); timer = window.setInterval(tick, POLL_MS) }
  function stopPoll(): void { if (timer) { clearInterval(timer); timer = 0 } }

  function enterSeg(): void {
    applySeg()
    if (L.seg === 'moves') { renderMoves(); if (!loading) void load(!shown) }
    else { renderBoard(); loadCards() }
  }

  // ───────── 事件 ─────────

  segEl.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-seg]')
    if (!b || b.dataset.seg === L.seg) return
    L.seg = b.dataset.seg as Seg
    keep()
    enterSeg()
  })
  q('.hm-search').addEventListener('click', () => openSearch())

  chipsEl.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-chip]')
    if (!b || b.dataset.chip === L.chip) return
    L.chip = b.dataset.chip as Chip
    keep()
    scroll.scrollTop = 0
    renderChips(); renderList()
  })

  list.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('.hm-retry')) { failed = false; renderList(); void load(true); return }
    const star = t.closest<HTMLElement>('[data-star]')
    if (star) {
      e.stopPropagation()
      const base = star.dataset.star!
      const sym = symOf(base)
      const s = S.symbols.get(sym)
      F.addFavorite(st.symbols, sym, F.group(st.symbols, st.favoritesGroup || null), s ? { kind: s.kind, base: s.base } : undefined)
      save()
      star.remove()
      return
    }
    const row = t.closest<HTMLElement>('.hm-row[data-base]')
    if (!row || !shown) return
    const r = shown.find(x => x.base === row.dataset.base)
    if (!r) return
    const order = filterRows(shown, L.chip).map(x => symOf(x.base))
    const sym = symOf(r.base)
    setHighlightIntent(sym, focusOf(r.top))
    openSymbol(sym, order)
  })

  newPill.addEventListener('click', reorderNow)

  cardsEl.addEventListener('click', e => {
    const t = e.target as HTMLElement
    const card = t.closest<HTMLElement>('.hm-card')
    const kind = (card?.dataset.kind ?? (t.closest<HTMLElement>('[data-retry]')?.dataset.retry)) as MarketKind | undefined
    if (!kind) return
    const win = t.closest<HTMLElement>('[data-win]')
    if (win) {
      const w = win.dataset.win as MarketWindow
      if (w === L.win[kind]) return
      L.win[kind] = w
      keep()
      cards[kind].rows = null; cards[kind].failed = false; cards[kind].open = false
      renderCard(kind)
      void loadCard(kind)
      return
    }
    if (t.closest('[data-retry]')) { cards[kind].failed = false; renderCard(kind); void loadCard(kind); return }
    if (t.closest('[data-more]')) { cards[kind].open = !cards[kind].open; renderCard(kind); return }
    const row = t.closest<HTMLElement>('.br[data-base]')
    if (!row) return
    const rows = cards[kind].rows ?? []
    const shownRows = cards[kind].open ? rows : rows.slice(0, CARD_ROWS)
    openSymbol(symOf(row.dataset.base!), shownRows.map(r => symOf(r.base)))
  })

  // 下拉刷新：列表在顶上时往下拉过 64 松手，立即重排
  let pullFrom: number | null = null
  let pulled = 0
  const setPull = (px: number, anim: boolean): void => {
    pulled = px
    body.classList.toggle('pulling', !anim)
    scroll.style.transform = px ? `translateY(${px}px)` : ''
    ptr.style.opacity = String(Math.min(1, px / PULL_PX))
    ptr.style.transform = `translate(-50%, ${Math.min(px, PULL_PX) - 28}px) rotate(${px * 4}deg)`
  }
  scroll.addEventListener('touchstart', e => { pullFrom = scroll.scrollTop <= 0 && !body.classList.contains('refreshing') ? e.touches[0].clientY : null }, { passive: true })
  scroll.addEventListener('touchmove', e => {
    if (pullFrom == null) return
    const dy = e.touches[0].clientY - pullFrom
    if (dy <= 0 || scroll.scrollTop > 0) { if (pulled) setPull(0, false); return }
    e.preventDefault()
    setPull(Math.min(110, dy * 0.5), false)
  }, { passive: false })
  const endPull = (): void => {
    if (pullFrom == null) return
    pullFrom = null
    if (pulled >= PULL_PX) {
      body.classList.add('refreshing')
      setPull(44, true)
      newPill.hidden = true
      void load(true).finally(() => { body.classList.remove('refreshing'); setPull(0, true) })
    } else setPull(0, true)
  }
  scroll.addEventListener('touchend', endPull)
  scroll.addEventListener('touchcancel', endPull)

  // 账号变了：重新拉、重新定序；自选变了：星与范围跟着改（不打断当前顺序）
  onSession(() => { shown = null; latest = null; if (active && L.seg === 'moves') { renderMoves(); void load(true) } })
  let favSig = st.symbols.favorites.join(',')
  subscribe(() => {
    const sig = st.symbols.favorites.join(',')
    if (sig === favSig) return
    favSig = sig
    if (active && L.seg === 'moves' && shown) { renderSub(); renderList() }
  })
  hooks.onForeground.push(() => { if (active) tick() })
  // 品种表到了：小数位、徽章、千枚代号都跟着它认，重画一遍
  on(e => { if (e.type !== 'universe' || !active) return; if (L.seg === 'moves') { if (shown) renderList() } else renderBoard() })
  void ensureUniverse()

  applySeg()
  renderMoves()

  return {
    show() {
      active = true
      enterSeg()
      startPoll()
    },
    hide() {
      active = false
      stopPoll()
    },
    reselect() {
      const sc = L.seg === 'moves' ? scroll : cardsEl
      if (L.seg === 'moves' && latest && !newPill.hidden) { reorderNow(); return }
      sc.scrollTo({ top: 0, behavior: 'smooth' })
    },
  }
}
