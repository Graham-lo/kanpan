/* 手机网页版 · 首页（照 docs/原型-手机首页异动与盘口要点-2026-10-10.html §01 / §02，iOS Home/）
 *
 * 底栏最左一格、启动默认。头部一行：分段胶囊「异动 · 涨跌 · 持仓 · 板块」（照自选页分类胶囊，左对齐）+ 放大镜圆片。
 * 异动：分类胶囊（全部 / 盘口 / 持仓 / 费率 / 波动）+ 一行范围与更新时刻 + 列表。打开时定序，之后每 60 s 拉一次，
 *   已有的行就地换数不换位，有新的只浮「有 N 条新异动」药丸；点药丸滚到顶重排，下拉刷新立即重排。
 *   点一行：放一份意图（展开哪张卡）再进行情页，行情页 240 ms 后自己升半页；波动行只进图、不升半页。
 *   横滑扫图名单 = 当时列表顺序。未登录只扫热门（不带自选）；登录后带上自选的币名，服务端自选层补跟。
 * 涨跌：涨幅榜 / 跌幅榜；持仓：增仓榜 / 减仓榜。两页各自一个窗口（1 时 / 4 时 / 24 时，出厂 4 时），小胶囊摆在
 *   第一张榜的标题行尾；每张榜 6 行，「全部」展开、「收起」收回；点一行进行情页，不升半页。
 * 板块：原来底栏的「板块分类」整页挂进来（./sectors），点板块下钻品种列表，点品种进图。
 * 分段只在这一次打开里记（冷启动回「异动」，深链 #sectors 落「板块」，见 ../app/homeSeg）；
 * 分类胶囊与两页的窗口只记在本机（不加同步字段）。
 */
import '../styles/favorites.css'
import '../styles/home.css'
import { st, save, subscribe } from '../app/store'
import { openSymbol, hooks, type PageHandle } from '../app/shell'
import { homeSeg, onHomeSeg, registerSectorsRefresh, setHomeSeg, type HomeSeg } from '../app/homeSeg'
import { icon } from '../ui/icons'
import { backdropHTML } from './favorites'
import { initSectors } from './sectors'
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
import { RANK_KINDS, chipCounts, favoriteBases, filterRows, focusOf, mergeBoard, parseHomeLocal, symbolFor, type Chip, type HomeLocal, type RankPage } from '../../highlights/home'

const LS_KEY = 'hkline-m-home-v1'
const POLL_MS = 60_000
const PULL_PX = 64
const CARD_ROWS = 6

function loadLocal(): HomeLocal {
  try { return parseHomeLocal(JSON.parse(localStorage.getItem(LS_KEY) || 'null')) } catch { return parseHomeLocal(null) }
}

const SEG_TITLE: Record<HomeSeg, string> = { moves: HL.moves, change: HL.segChange, oi: HL.segOi, sectors: '板块' }
const CAT_TAG: Record<Exclude<BoardCat, 'move'>, string> = { book: HL.catBook, oi: HL.catOi, funding: HL.catFunding }
const CAT_COLOR: Record<Exclude<BoardCat, 'move'>, string> = { book: 'var(--accent)', oi: 'var(--amber)', funding: 'var(--ink2)' }
const RANK_TITLE: Record<MarketKind, string> = { gainers: HL.rankGainers, losers: HL.rankLosers, oi: HL.rankOiUp, oidown: HL.rankOiDown }
const WIN_LABEL: Record<MarketWindow, string> = { '1h': HL.win1h, '4h': HL.win4h, '24h': HL.win24h }
const ALL_KINDS: readonly MarketKind[] = ['gainers', 'losers', 'oi', 'oidown']
const isRank = (s: HomeSeg): s is RankPage => s === 'change' || s === 'oi'

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

/** 一行异动的标签与颜色：波动按方向（急涨涨色 / 急跌跌色），其余按类 */
export function rowTag(r: BoardRow): { tag: string; color: string } {
  if (r.top.kind === 'move') return r.top.dir === 'up' ? { tag: HL.moveUp, color: 'var(--up)' } : { tag: HL.moveDown, color: 'var(--down)' }
  const cat = r.cat === 'move' ? 'book' : r.cat
  return { tag: CAT_TAG[cat], color: CAT_COLOR[cat] }
}

export function moveRowHTML(r: BoardRow, now: number): string {
  const star = isFav(r.base) ? '' : `<button type="button" class="st" data-star="${esc(r.base)}" aria-label="${esc(HL.addFavorite)}">${STAR}</button>`
  const { tag, color } = rowTag(r)
  // 波动行服务端不带涨跌幅：用品种表里的 24 时涨跌
  const pct = r.changePct ?? (r.cat === 'move' ? S.symbols.get(symOf(r.base))?.pct ?? null : null)
  return `<div class="hm-row" role="listitem" data-key="${esc(r.key)}" style="--c:${color}">${badge(r.base, 28)}<div class="mid">
    <div class="l1"><span class="nm"><span class="tk">${esc(r.base)}</span>${star}</span><span class="p">${esc(pxText(r.base, r.price))}</span>${pill(pct)}</div>
    <div class="pt1"><span class="kind">${esc(tag)}</span>${meter(r.tier)}<span class="tx">${boardFact(r)}</span>${r.count > 1 ? `<span class="plus">+${r.count - 1}</span>` : ''}<span class="ago">${esc(agoText(r.atMs, now))}</span></div>
  </div></div>`
}

/** 涨跌 / 持仓榜的一行（照自选页的行：名次 · 徽章 28 · 名字 · 数 · 涨跌药丸） */
export function rankRowHTML(kind: MarketKind, r: MarketRow, i: number): string {
  const oi = kind === 'oi' || kind === 'oidown'
  const v = oi ? (r.oiUsd != null ? usd(r.oiUsd) : '—') : pxText(r.base, r.price)
  const t = signedPct(r.changePct)
  return `<button type="button" class="hm-rr" data-base="${esc(r.base)}"><span class="i">${i + 1}</span>${badge(r.base, 28)}<span class="n">${esc(r.base)}</span><span class="v">${esc(v)}</span><span class="m-pill ${r.changePct >= 0 ? 'up' : 'down'}">${esc(t)}</span></button>`
}

const SKELETON = Array.from({ length: 6 }, () => `<div class="hm-row skel" aria-hidden="true"><span class="sk sk-b"></span><div class="mid"><div class="l1"><span class="sk" style="width:70px;height:14px"></span><span style="flex:1"></span><span class="sk" style="width:60px;height:14px"></span><span class="sk" style="width:56px;height:20px"></span></div><div class="sk" style="width:62%;height:11px;margin-top:8px"></div></div></div>`).join('')
const RANK_SKELETON = Array.from({ length: CARD_ROWS }, () => `<div class="hm-rr skel" aria-hidden="true"><span class="sk sk-b"></span><span class="sk" style="width:64px;height:13px"></span><span style="flex:1"></span><span class="sk" style="width:56px;height:13px"></span><span class="sk" style="width:72px;height:28px;border-radius:8px"></span></div>`).join('')

interface CardState { rows: MarketRow[] | null; failed: boolean; open: boolean; seq: number }

export function initHome(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'liuli')
  const L = loadLocal()
  const keep = (): void => { try { localStorage.setItem(LS_KEY, JSON.stringify(L)) } catch { /* 存不了就只在这一次有效 */ } }

  const segs = (Object.keys(SEG_TITLE) as HomeSeg[])
    .map(id => `<button type="button" role="tab" class="hm-cap" data-seg="${id}" data-id="home.segment.${id}">${esc(SEG_TITLE[id])}</button>`).join('')
  const rankSection = (pg: RankPage): string => `<section class="hm-rank" data-page="${pg}"><div class="hm-scroll hm-ranks"></div></section>`
  root.innerHTML = backdropHTML() + `
    <header class="fav-head hm-head">
      <div class="hm-caps" role="tablist">${segs}</div>
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
    ${rankSection('change')}${rankSection('oi')}
    <section class="hm-sectors"></section>`

  const q = <T extends HTMLElement>(s: string): T => root.querySelector<T>(s)!
  const capsEl = q('.hm-caps'), movesEl = q('.hm-moves'), sectorsEl = q('.hm-sectors')
  const rankEl: Record<RankPage, HTMLElement> = { change: q('.hm-rank[data-page="change"]'), oi: q('.hm-rank[data-page="oi"]') }
  const ranksEl: Record<RankPage, HTMLElement> = { change: q('.hm-rank[data-page="change"] .hm-ranks'), oi: q('.hm-rank[data-page="oi"] .hm-ranks') }
  const chipsEl = q('.hm-chips'), subL = q('.hm-sub .l'), subR = q('.hm-sub .r')
  const body = q('.hm-body'), ptr = q('.hm-ptr'), scroll = q('.hm-moves .hm-scroll'), list = q('.hm-list')
  const newPill = q<HTMLButtonElement>('.hm-newpill')
  const sectors = initSectors(sectorsEl)
  let sectorsOn = false

  let active = false
  let shown: BoardRow[] | null = null    // 正在显示的那份（定了序）
  let latest: BoardRow[] | null = null   // 最近一次拉到的
  let generatedAt = 0
  let failed = false
  let loading = false
  let reqSeq = 0
  let timer = 0
  const cards = Object.fromEntries(ALL_KINDS.map(k => [k, { rows: null, failed: false, open: false, seq: 0 }])) as Record<MarketKind, CardState>
  const pageOf = (k: MarketKind): RankPage => (RANK_KINDS.change.includes(k) ? 'change' : 'oi')

  // ───────── 异动 ─────────

  function renderChips(): void {
    const c = chipCounts(shown ?? [])
    const chip = (id: Chip, label: string, dot: string | null): string =>
      `<button type="button" role="tab" data-chip="${id}" class="${L.chip === id ? 'on' : ''}"${dot ? ` style="--c:${dot}"` : ''}>${dot ? '<i></i>' : ''}${esc(label)}${shown ? `<b>${c[id]}</b>` : ''}</button>`
    // 波动：圆点一半涨色一半跌色（急涨 / 急跌都在这一类里）
    chipsEl.innerHTML = chip('all', HL.all, null) + chip('book', HL.catBook, CAT_COLOR.book) + chip('oi', HL.catOi, CAT_COLOR.oi)
      + chip('funding', HL.catFunding, CAT_COLOR.funding) + chip('move', HL.catMove, 'linear-gradient(135deg, var(--up) 50%, var(--down) 50%)')
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

  // ───────── 涨跌 / 持仓 ─────────

  function winsHTML(pg: RankPage): string {
    return `<div class="hm-wins" role="group">${(['1h', '4h', '24h'] as const).map(w =>
      `<button type="button" data-win="${w}" class="${L.win[pg] === w ? 'on' : ''}" aria-pressed="${L.win[pg] === w}">${esc(WIN_LABEL[w])}</button>`).join('')}</div>`
  }

  function sectHTML(kind: MarketKind, first: boolean): string {
    const c = cards[kind], pg = pageOf(kind)
    let rows: string
    if (c.rows == null) rows = c.failed
      ? `<div class="hm-gempty"><span>${esc(HL.failed)}</span><button type="button" class="hm-retry" data-retry="${kind}">${esc(HL.retry)}</button></div>`
      : RANK_SKELETON
    else if (!c.rows.length) rows = `<div class="hm-gempty"><span>${esc(HL.noRows)}</span></div>`
    else rows = (c.open ? c.rows : c.rows.slice(0, CARD_ROWS)).map((r, i) => rankRowHTML(kind, r, i)).join('')
    const more = c.rows && c.rows.length > CARD_ROWS
      ? `<button type="button" class="hm-more" data-more="${kind}">${esc(c.open ? HL.collapse : HL.all)}</button>` : ''
    return `<section class="hm-sect${c.failed && c.rows ? ' stale' : ''}" data-kind="${kind}"><div class="hm-sh"><h5>${esc(RANK_TITLE[kind])}</h5>${first ? winsHTML(pg) : ''}${more}</div><div class="hm-group">${rows}</div></section>`
  }

  function renderRank(pg: RankPage): void {
    const [a, b] = RANK_KINDS[pg]
    ranksEl[pg].innerHTML = sectHTML(a, true) + sectHTML(b, false)
  }

  async function loadCard(kind: MarketKind): Promise<void> {
    const c = cards[kind]
    const seq = ++c.seq
    const r = await fetchMarketBoard(kind, L.win[pageOf(kind)])
    if (seq !== c.seq) return
    if (r.ok) { c.rows = r.data.rows; c.failed = false } else c.failed = true
    if (active) renderRank(pageOf(kind))
  }
  const loadRank = (pg: RankPage): void => { RANK_KINDS[pg].forEach(k => void loadCard(k)) }

  // ───────── 分段 / 轮询 ─────────

  function applySeg(): void {
    const seg = homeSeg()
    capsEl.querySelectorAll<HTMLElement>('[data-seg]').forEach(b => {
      const on = b.dataset.seg === seg
      b.classList.toggle('on', on)
      b.setAttribute('aria-selected', String(on))
    })
    movesEl.hidden = seg !== 'moves'
    rankEl.change.hidden = seg !== 'change'
    rankEl.oi.hidden = seg !== 'oi'
    sectorsEl.hidden = seg !== 'sectors'
  }

  /** 板块那一段的 show / hide 跟着「首页在前台 + 站在板块段」走 */
  function syncSectors(): void {
    const want = active && homeSeg() === 'sectors'
    if (want === sectorsOn) return
    sectorsOn = want
    if (want) sectors.show(); else sectors.hide()
  }
  registerSectorsRefresh(() => { if (sectorsOn) sectors.show() })

  function tick(): void {
    if (!active || document.hidden) return
    const seg = homeSeg()
    if (seg === 'moves') void load(false)
    else if (isRank(seg)) loadRank(seg)
  }
  function startPoll(): void { stopPoll(); timer = window.setInterval(tick, POLL_MS) }
  function stopPoll(): void { if (timer) { clearInterval(timer); timer = 0 } }

  function enterSeg(): void {
    applySeg()
    syncSectors()
    const seg = homeSeg()
    if (seg === 'moves') { renderMoves(); if (!loading) void load(!shown) }
    else if (isRank(seg)) { renderRank(seg); loadRank(seg) }
  }

  function reselect(): void {
    const seg = homeSeg()
    if (seg === 'sectors') { sectors.reselect?.(); return }
    if (seg === 'moves' && latest && !newPill.hidden) { reorderNow(); return }
    const sc = seg === 'moves' ? scroll : ranksEl[seg]
    sc.scrollTo({ top: 0, behavior: 'smooth' })
  }

  // ───────── 事件 ─────────

  capsEl.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('[data-seg]')
    if (!b) return
    const seg = b.dataset.seg as HomeSeg
    if (seg === homeSeg()) { reselect(); return }
    setHomeSeg(seg)
  })
  onHomeSeg(() => { if (active) enterSeg(); else applySeg() })
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
      list.querySelectorAll(`[data-star="${CSS.escape(base)}"]`).forEach(x => x.remove())
      return
    }
    const row = t.closest<HTMLElement>('.hm-row[data-key]')
    if (!row || !shown) return
    const r = shown.find(x => x.key === row.dataset.key)
    if (!r) return
    const order = filterRows(shown, L.chip).map(x => symOf(x.base))
    const sym = symOf(r.base)
    const focus = focusOf(r.top)
    if (focus) setHighlightIntent(sym, focus)
    openSymbol(sym, order)
  })

  newPill.addEventListener('click', reorderNow)

  for (const pg of ['change', 'oi'] as const) {
    ranksEl[pg].addEventListener('click', e => {
      const t = e.target as HTMLElement
      const win = t.closest<HTMLElement>('[data-win]')
      if (win) {
        const w = win.dataset.win as MarketWindow
        if (w === L.win[pg]) return
        L.win[pg] = w
        keep()
        for (const k of RANK_KINDS[pg]) Object.assign(cards[k], { rows: null, failed: false, open: false })
        renderRank(pg)
        loadRank(pg)
        return
      }
      const kind = (t.closest<HTMLElement>('.hm-sect')?.dataset.kind) as MarketKind | undefined
      if (!kind) return
      if (t.closest('[data-retry]')) { cards[kind].failed = false; renderRank(pg); void loadCard(kind); return }
      if (t.closest('[data-more]')) { cards[kind].open = !cards[kind].open; renderRank(pg); return }
      const row = t.closest<HTMLElement>('.hm-rr[data-base]')
      if (!row) return
      const rows = cards[kind].rows ?? []
      const shownRows = cards[kind].open ? rows : rows.slice(0, CARD_ROWS)
      openSymbol(symOf(row.dataset.base!), shownRows.map(r => symOf(r.base)))
    })
  }

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
  onSession(() => { shown = null; latest = null; if (active && homeSeg() === 'moves') { renderMoves(); void load(true) } })
  let favSig = st.symbols.favorites.join(',')
  subscribe(() => {
    const sig = st.symbols.favorites.join(',')
    if (sig === favSig) return
    favSig = sig
    if (active && homeSeg() === 'moves' && shown) { renderSub(); renderList() }
  })
  hooks.onForeground.push(() => { if (active) tick() })
  // 品种表到了：小数位、徽章、千枚代号都跟着它认，重画一遍
  on(e => {
    if (e.type !== 'universe' || !active) return
    const seg = homeSeg()
    if (seg === 'moves') { if (shown) renderList() } else if (isRank(seg)) renderRank(seg)
  })
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
      syncSectors()
    },
    reselect,
  }
}
