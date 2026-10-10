/* Hkline Web · 首页（电脑版，照 docs/prototypes/web-layout-2026-10-10.html 第 2 节，用户 2026-10-10 定板）
 *
 * 四栏并排（2560 宽：1.5 : 1 : 1 : .95；窄于 1800 板块栏并到持仓栏下方，窄于 1300 两栏两行，见 home/layout.ts）：
 * - 异动：栏头分类胶囊（全部 / 盘口 / 持仓 / 费率 / 波动，只有字与计数，10-10 去掉色点）+ 范围与更新时刻；列表打开时定序，之后每 60 秒拉一次，
 *   已有的行就地换数不换位，新的只浮「有 N 条新异动」药丸，点药丸滚到顶重排。合并 / 计数 / 筛选和手机共用 highlights/home.ts。
 *   点一行开图表页那只（电脑版图表还没有「盘口要点」半页，focus 暂不往下传）；悬停行出星，点了加自选。
 * - 涨跌：涨幅榜 / 跌幅榜；持仓：增仓榜 / 减仓榜（数值列写持仓额）。两栏各自一个窗口（1 时 / 4 时 / 24 时，出厂 4 时），
 *   分段在第一张榜标题行尾；每张榜默认 8 行，「全部」展开、「收起」收回；60 秒一拉。
 * - 板块：板块页同一份行情与口径（sectors/feed + aggregate），精简成 板块名 + 强弱条 · 跑赢 / 落后大盘 · 涨跌药丸；
 *   点一行进板块页并选中它，底部「全部板块 →」进板块页。
 * 分类胶囊与两栏的窗口只记本机（hkline-home-v1），不同步。不加任何设置项。
 */
import '../styles/home.css'
import { st, save, subscribe, validSymbol } from '../app/store'
import { hooks, go } from '../app/shell'
import { $, esc, tgt } from '../ui/dom'
import { morphHtml, patchKeyedRows } from '../ui/patch'
import { badge, priceText, sym } from '../ui/common'
import { S } from '../market'
import { openSymbol, toggleWatch } from './chart'
import { session, onSession } from '../account/session'
import { baseOfSymbol } from '../orderflow/settings'
import { HL, fill } from '../terms'
import { fetchBoard, fetchMarketBoard, type BoardCat, type BoardRow, type MarketKind, type MarketRow, type MarketWindow } from '../highlights/api'
import { agoText, boardFact, hhmm, levelPx, movePill, signedPct, usd } from '../highlights/format'
import { RANK_KINDS, chipCounts, favoriteBases, filterRows, mergeBoard, parseHomeLocal, symbolFor, type Chip, type HomeLocal, type RankPage } from '../highlights/home'
import { feed, seedFromUniverse, startFeed, stopFeed } from '../sectors/feed'
import { WINDOW_TITLE, boardOrder, isThin, marketReturn, stats } from '../sectors/aggregate'
import { beatParts, homeCols, pillOf, rankRowsFor, rankView, sectorLines, type SectorLine } from '../home/layout'

const LS_KEY = 'hkline-home-v1'
const POLL_MS = 60_000

const CAT_TAG: Record<Exclude<BoardCat, 'move'>, string> = { book: HL.catBook, oi: HL.catOi, funding: HL.catFunding }
// 类别字不上色（2026-10-10 精致层级：颜色只给涨跌）；只有急涨 / 急跌的类别字与强度格走涨跌色
const CAT_COLOR: Record<Exclude<BoardCat, 'move'>, string> = { book: 'var(--text-2)', oi: 'var(--text-2)', funding: 'var(--text-2)' }
const RANK_TITLE: Record<MarketKind, string> = { gainers: HL.rankGainers, losers: HL.rankLosers, oi: HL.rankOiUp, oidown: HL.rankOiDown }
const WIN_LABEL: Record<MarketWindow, string> = { '1h': HL.win1h, '4h': HL.win4h, '24h': HL.win24h }
const ALL_KINDS: readonly MarketKind[] = ['gainers', 'losers', 'oi', 'oidown']
const pageOf = (k: MarketKind): RankPage => (RANK_KINDS.change.includes(k) ? 'change' : 'oi')

const STAR = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.2l2.7 5.5 6 .9-4.35 4.25 1.03 6L12 17l-5.38 2.85 1.03-6L3.3 9.6l6-.9z"/></svg>'
const ARROW_UP = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 19V5M6 11l6-6 6 6"/></svg>'
const CALM = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 12h4l2-3 3 6 2-3h7"/></svg>'

// ───────── 品种 ─────────

/** 自选（各类合在一起，保序） */
const favorites = (): string[] => Object.values(st.watch).flat()
const baseOf = (k: string): string => baseOfSymbol(k).base
const symOf = (base: string): string => symbolFor(base, favorites(), baseOf, k => S.symbols.has(k))
const isFav = (base: string): boolean => favorites().some(k => baseOf(k) === base)

function coin(base: string): string {
  const s = sym(symOf(base))
  return badge(s ?? { base }, 'lg')
}
/** 品种表到了按它的小数位写；还没到按五位有效数字写 */
function pxText(base: string, price: number | null): string {
  const s = sym(symOf(base))
  return s ? priceText(s, price) : price == null ? '—' : levelPx(price)
}
const pillHTML = (p: { text: string; cls: string }): string => `<span class="hm-pill num ${p.cls}">${esc(p.text)}</span>`

// ───────── 异动行 ─────────

function rowTag(r: BoardRow): { tag: string; color: string } {
  if (r.top.kind === 'move') return r.top.dir === 'up' ? { tag: HL.moveUp, color: 'var(--up-text)' } : { tag: HL.moveDown, color: 'var(--down-text)' }
  const cat = r.cat === 'move' ? 'book' : r.cat
  return { tag: CAT_TAG[cat], color: CAT_COLOR[cat] }
}

const meter = (t: 1 | 2 | 3): string =>
  `<span class="mt" aria-hidden="true"><i class="${t >= 1 ? 'on' : ''}" style="height:4px"></i><i class="${t >= 2 ? 'on' : ''}" style="height:7px"></i><i class="${t >= 3 ? 'on' : ''}" style="height:10px"></i></span>`

function moveRowHTML(r: BoardRow, now: number): string {
  const { tag, color } = rowTag(r)
  const star = isFav(r.base) ? '' : `<button type="button" class="star" data-star="${esc(r.base)}" aria-label="${esc(HL.addFavorite)}" data-tip="${esc(HL.addFavorite)}">${STAR}</button>`
  // 波动行：药丸写这次波动本身（1 分 / 5 分的涨跌幅），按急涨 / 急跌着色，不写 24 时涨跌
  const pill = r.top.kind === 'move' ? movePill(r.top) : pillOf(r.changePct)
  return `<div class="hm-row" role="listitem" tabindex="0" data-key="${esc(r.key)}" style="--c:${color}">${coin(r.base)}<div class="mid">
    <div class="l1"><span class="tk">${esc(r.base)}</span>${star}<span class="p num">${esc(pxText(r.base, r.price))}</span></div>
    <div class="l2"><span class="kind">${esc(tag)}</span>${meter(r.tier)}<span class="tx num">${boardFact(r)}</span>${r.count > 1 ? `<span class="plus num">+${r.count - 1}</span>` : ''}<span class="ago">${esc(agoText(r.atMs, now))}</span></div>
  </div>${pillHTML(pill)}</div>`
}

const SKELETON = Array.from({ length: 10 }, () => `<div class="hm-row skel" aria-hidden="true"><span class="sk sk-b"></span><div class="mid"><div class="l1"><span class="sk" style="width:64px;height:14px"></span><span class="sk" style="width:72px;height:14px;margin-left:auto"></span></div><div class="sk" style="width:62%;height:11px;margin-top:8px"></div></div><span class="sk" style="width:68px;height:22px;border-radius:6px"></span></div>`).join('')
const RANK_SKELETON = Array.from({ length: 8 }, () => `<div class="rk-row skel" aria-hidden="true"><span class="sk" style="width:12px;height:12px"></span><span class="sk sk-b"></span><span class="sk" style="width:56px;height:13px"></span><span class="sk" style="width:56px;height:13px"></span><span class="sk" style="width:68px;height:22px;border-radius:6px"></span></div>`).join('')

// ───────── 榜单行 ─────────

function rankRowHTML(kind: MarketKind, r: MarketRow, i: number): string {
  const oi = kind === 'oi' || kind === 'oidown'
  const v = oi ? (r.oiUsd != null ? usd(r.oiUsd) : '—') : pxText(r.base, r.price)
  return `<button type="button" class="rk-row" data-base="${esc(r.base)}"><span class="i num">${i + 1}</span>${coin(r.base)}<span class="tk">${esc(r.base)}</span><span class="v num">${esc(v)}</span>${pillHTML(pillOf(r.changePct))}</button>`
}

// ───────── 板块行 ─────────

function sectorRowHTML(l: SectorLine): string {
  const beat = l.beat == null ? '—' : ((p) => fill(p.ahead ? HL.beatAhead : HL.beatBehind, { v: p.v }))(beatParts(l.beat))
  return `<button type="button" class="sc-row" data-sec="${esc(l.id)}"><span class="nm"><span class="tk">${esc(l.name)}</span><span class="bar" aria-hidden="true"><i class="${l.bar.up ? 'up' : 'down'}" style="left:${l.bar.left.toFixed(2)}%;width:${l.bar.width.toFixed(2)}%"></i></span></span><span class="beat num">${esc(beat)}</span>${pillHTML(pillOf(l.pct))}</button>`
}

interface CardState { rows: MarketRow[] | null; failed: boolean; open: boolean; seq: number }

function loadLocal(): HomeLocal {
  try { return parseHomeLocal(JSON.parse(localStorage.getItem(LS_KEY) || 'null')) } catch { return parseHomeLocal(null) }
}

export function initHome(): void {
  const root = $('#page-home')
  const L = loadLocal()
  const keep = (): void => { try { localStorage.setItem(LS_KEY, JSON.stringify(L)) } catch { /* 存不了就只在这一次有效 */ } }

  const rankCol = (pg: RankPage, title: string): string =>
    `<div class="card hm-col hm-rank" data-page="${pg}"><div class="hm-hd"><h4>${esc(title)}</h4><span class="sub"></span></div><div class="hm-rk-body scroll"></div></div>`
  root.innerHTML = `
    <div class="card hm-col hm-moves">
      <div class="hm-hd"><h4>${esc(HL.moves)}</h4><div class="hm-chips" role="tablist" aria-label="${esc(HL.moves)}"></div><span class="sub"></span></div>
      <div class="hm-body"><div class="hm-list scroll" role="list"></div><button type="button" class="hm-newpill" hidden>${ARROW_UP}<span></span></button></div>
    </div>
    ${rankCol('change', HL.segChange)}${rankCol('oi', HL.segOi)}
    <div class="card hm-col hm-sectors">
      <div class="hm-hd"><h4>${esc(HL.segSectors)}</h4><span class="sub"></span></div>
      <div class="hm-sc-list scroll"></div>
      <button type="button" class="hm-scbtn">${esc(HL.allSectors)} →</button>
    </div>`

  const q = <T extends HTMLElement>(s: string): T => root.querySelector<T>(s)!
  const chipsEl = q('.hm-moves .hm-chips'), movesSub = q('.hm-moves .sub'), list = q('.hm-list')
  const newPill = q<HTMLButtonElement>('.hm-newpill')
  const rankBody: Record<RankPage, HTMLElement> = { change: q('.hm-rank[data-page="change"] .hm-rk-body'), oi: q('.hm-rank[data-page="oi"] .hm-rk-body') }
  const rankSub: Record<RankPage, HTMLElement> = { change: q('.hm-rank[data-page="change"] .sub'), oi: q('.hm-rank[data-page="oi"] .sub') }
  const secList = q('.hm-sc-list'), secSub = q('.hm-sectors .sub')

  let active = false
  let shown: BoardRow[] | null = null    // 正在显示的那份（定了序）
  let latest: BoardRow[] | null = null   // 最近一次拉到的
  let generatedAt = 0
  let failed = false
  let loading = false
  let reqSeq = 0
  let timer = 0
  let lastPoll = 0
  let listState = ''
  const cards = Object.fromEntries(ALL_KINDS.map(k => [k, { rows: null, failed: false, open: false, seq: 0 }])) as Record<MarketKind, CardState>

  // ───────── 折行：按页面自己的宽度定几栏（窄于 1800 / 1300） ─────────
  const fit = (w: number): void => { if (w > 0) root.dataset.cols = String(homeCols(w)) }
  fit(root.getBoundingClientRect().width || window.innerWidth)

  // 每张榜默认几行：按栏高算（两张榜各占半栏、减榜头、整行向下取整，最少 8 行），栏高变了重算
  const rankN: Record<RankPage, number> = { change: rankRowsFor(0), oi: rankRowsFor(0) }
  const measureRanks = (): void => {
    for (const pg of ['change', 'oi'] as const) {
      const el = rankBody[pg]
      const pad = parseFloat(getComputedStyle(el).paddingBottom) || 0
      const h = el.clientHeight - pad
      if (!(h > 0)) continue
      const n = rankRowsFor(h)
      if (n !== rankN[pg]) { rankN[pg] = n; if (active) renderRank(pg) }
    }
  }
  if (typeof ResizeObserver !== 'undefined') {
    new ResizeObserver(es => { fit(es[0]?.contentRect.width ?? 0); fitSub() }).observe(root)
    const ro = new ResizeObserver(() => measureRanks())
    ro.observe(rankBody.change); ro.observe(rankBody.oi)
  } else addEventListener('resize', () => { fit(root.getBoundingClientRect().width); fitSub(); measureRanks() })

  // ───────── 异动 ─────────

  function renderChips(): void {
    const c = chipCounts(shown ?? [])
    // 只留字与计数，不带色点（与 iOS dc24bcfb、手机网页 4de6298a 一致）；选中段是中性凹槽里浮起的一块
    const chip = (id: Chip, label: string): string =>
      `<button type="button" role="tab" data-chip="${id}" class="${L.chip === id ? 'on' : ''}" aria-selected="${L.chip === id}">${esc(label)}${shown ? `<b class="num">${c[id]}</b>` : ''}</button>`
    morphHtml(chipsEl, chip('all', HL.all) + chip('book', HL.catBook) + chip('oi', HL.catOi) + chip('funding', HL.catFunding) + chip('move', HL.catMove))
  }

  function renderSub(): void {
    if (!shown) { subFull = subShort = ''; movesSub.textContent = ''; return }
    const scope = session.userId ? fill(HL.favScope, { n: favoriteBases(favorites(), baseOf).length }) : HL.guestHint
    const at = failed ? fill(HL.stoppedAt, { t: hhmm(generatedAt) }) : fill(HL.updatedAt, { t: hhmm(generatedAt) })
    subFull = `${scope} · ${at}`
    subShort = at
    fitSub()
  }

  /** 栏窄放不下「范围 · 时刻」时只写「HH:MM 更新」，不截断 */
  let subFull = '', subShort = ''
  function fitSub(): void {
    movesSub.textContent = subFull
    if (subFull && movesSub.scrollWidth > movesSub.clientWidth + 1) movesSub.textContent = subShort
  }

  function setList(state: string, html: string): void {
    if (listState === state) return
    listState = state
    list.innerHTML = html
  }

  function renderList(): void {
    const now = Date.now()
    list.classList.toggle('stale', failed && !!shown)
    if (!shown) {
      if (failed) setList('failed', `<div class="hm-empty"><span>${esc(HL.failed)}</span><button type="button" class="btn sm hm-retry">${esc(HL.retry)}</button></div>`)
      else setList('skel', SKELETON)
      return
    }
    if (!shown.length) {
      listState = ''
      list.innerHTML = `<div class="hm-calm">${CALM}<b>${esc(HL.calmTitle)}</b><span>${esc(HL.calmSub)} · ${esc(fill(HL.updatedAt, { t: hhmm(generatedAt) }))}</span></div>`
      return
    }
    const rows = filterRows(shown, L.chip)
    if (!rows.length) { listState = ''; list.innerHTML = `<div class="hm-empty"><span>${esc(HL.noRows)}</span></div>`; return }
    // 已有的行按键就地改（指针下的行、星都留着），顺序不动
    if (listState !== 'rows') { listState = 'rows'; list.textContent = '' }
    patchKeyedRows(list, rows.map(r => [r.key, moveRowHTML(r, now)] as const), 'data-key')
  }

  function renderPill(): void {
    if (!shown || !latest) { newPill.hidden = true; return }
    const { fresh } = mergeBoard(shown, latest)
    newPill.hidden = fresh === 0
    if (fresh) newPill.querySelector('span')!.textContent = fill(HL.newMoves, { n: fresh })
  }

  function renderMoves(): void { renderChips(); renderSub(); renderList(); renderPill() }

  /** 拉一份；reorder = 按服务端顺序重排（首次、点药丸、换账号） */
  async function loadMoves(reorder: boolean): Promise<void> {
    const seq = ++reqSeq
    loading = true
    const bases = session.userId ? favoriteBases(favorites(), baseOf) : []
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
    list.scrollTo({ top: 0, behavior: 'smooth' })
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
    let more = ''
    if (c.rows == null) rows = c.failed
      ? `<div class="hm-gempty"><span>${esc(HL.failed)}</span><button type="button" class="btn sm hm-retry" data-retry="${kind}">${esc(HL.retry)}</button></div>`
      : RANK_SKELETON
    else if (!c.rows.length) rows = `<div class="hm-gempty"><span>${esc(HL.noRows)}</span></div>`
    else {
      const v = rankView(c.rows, c.open, rankN[pg])
      rows = v.rows.map((r, i) => rankRowHTML(kind, r, i)).join('')
      if (v.more) more = `<button type="button" class="more" data-more="${kind}">${esc(v.more === 'collapse' ? HL.collapse : HL.all)}</button>`
    }
    return `<section class="rk${c.failed && c.rows ? ' stale' : ''}" data-kind="${kind}"><div class="rk-sh"><h5>${esc(RANK_TITLE[kind])}</h5>${first ? winsHTML(pg) : ''}${more}</div><div class="rk-rows">${rows}</div></section>`
  }

  function renderRank(pg: RankPage): void {
    const [a, b] = RANK_KINDS[pg]
    rankSub[pg].textContent = `${pg === 'change' ? HL.binancePerp : HL.boardOi} · ${WIN_LABEL[L.win[pg]]}`
    morphHtml(rankBody[pg], sectHTML(a, true) + sectHTML(b, false))
  }

  async function loadCard(kind: MarketKind): Promise<void> {
    const c = cards[kind]
    const seq = ++c.seq
    const r = await fetchMarketBoard(kind, L.win[pageOf(kind)])
    if (seq !== c.seq) return
    if (r.ok) { c.rows = r.data.rows; c.failed = false } else c.failed = true
    if (active) renderRank(pageOf(kind))
  }
  const loadRanks = (): void => { ALL_KINDS.forEach(k => void loadCard(k)) }

  // ───────── 板块 ─────────

  function renderSectors(): void {
    if (!active) return
    seedFromUniverse()
    const m = 'crypto'
    const ordered = boardOrder(stats(m, feed.quotes, feed.buckets[m], 'today'))
    const mkt = feed.quotes.size ? marketReturn(m, feed.quotes, feed.buckets[m], 'today') : null
    const lines = sectorLines(ordered, mkt, isThin)
    secSub.textContent = mkt == null ? WINDOW_TITLE.today : `${fill(HL.marketAvg, { v: signedPct(mkt) })} · ${WINDOW_TITLE.today}`
    if (!lines.length) {
      patchKeyedRows(secList, [], 'data-sec')
      const down = feed.ok === false || S.live === false
      const msg = feed.quotes.size ? HL.noRows : down ? HL.failed : ''
      if (msg) secList.innerHTML = `<div class="hm-gempty"><span>${esc(msg)}</span></div>`
      else secList.innerHTML = Array.from({ length: 10 }, () => `<div class="sc-row skel" aria-hidden="true"><span class="sk" style="width:120px;height:13px"></span><span class="sk" style="width:64px;height:13px"></span><span class="sk" style="width:68px;height:22px;border-radius:6px"></span></div>`).join('')
      return
    }
    patchKeyedRows(secList, lines.map(l => [l.id, sectorRowHTML(l)] as const), 'data-sec')
  }

  // ───────── 轮询 ─────────

  function tick(): void {
    if (!active || document.hidden) return
    lastPoll = Date.now()
    void loadMoves(false)
    loadRanks()
  }
  function startPoll(): void { stopPoll(); timer = window.setInterval(tick, POLL_MS) }
  function stopPoll(): void { if (timer) { clearInterval(timer); timer = 0 } }

  // ───────── 开图 ─────────

  function openBase(base: string): void {
    const k = symOf(base)
    if (!validSymbol(k)) return
    go('chart')
    openSymbol(k)
    // 图表还没摆好（冷启动品种表在路上）时 openSymbol 不动：先写进当前格，图表起来照它开
    const c = st.cells[st.active]
    if (c && c.symbol !== k) { st.cells[st.active] = { ...c, symbol: k }; save() }
  }

  // ───────── 事件 ─────────

  chipsEl.addEventListener('click', e => {
    const b = tgt(e).closest<HTMLElement>('[data-chip]')
    if (!b || b.dataset.chip === L.chip) return
    L.chip = b.dataset.chip as Chip
    keep()
    list.scrollTop = 0
    renderChips(); renderList()
  })

  list.addEventListener('click', e => {
    const t = tgt(e)
    if (t.closest('.hm-retry')) { failed = false; renderList(); void loadMoves(true); return }
    const star = t.closest<HTMLElement>('[data-star]')
    if (star) {
      e.stopPropagation()
      const base = star.dataset.star!
      if (!isFav(base)) toggleWatch(symOf(base))
      return
    }
    const row = t.closest<HTMLElement>('.hm-row[data-key]')
    const r = row && shown?.find(x => x.key === row.dataset.key)
    if (r) openBase(r.base)
  })
  list.addEventListener('keydown', e => {
    if (e.key !== 'Enter') return
    const row = tgt(e).closest<HTMLElement>('.hm-row[data-key]')
    const r = row && shown?.find(x => x.key === row.dataset.key)
    if (r) { e.preventDefault(); openBase(r.base) }
  })
  newPill.addEventListener('click', reorderNow)

  for (const pg of ['change', 'oi'] as const) {
    rankBody[pg].addEventListener('click', e => {
      const t = tgt(e)
      const win = t.closest<HTMLElement>('[data-win]')
      if (win) {
        const w = win.dataset.win as MarketWindow
        if (w === L.win[pg]) return
        L.win[pg] = w
        keep()
        for (const k of RANK_KINDS[pg]) Object.assign(cards[k], { rows: null, failed: false, open: false })
        renderRank(pg)
        RANK_KINDS[pg].forEach(k => void loadCard(k))
        return
      }
      const kind = t.closest<HTMLElement>('.rk')?.dataset.kind as MarketKind | undefined
      if (!kind) return
      if (t.closest('[data-retry]')) { cards[kind].failed = false; renderRank(pg); void loadCard(kind); return }
      if (t.closest('[data-more]')) { cards[kind].open = !cards[kind].open; renderRank(pg); return }
      const row = t.closest<HTMLElement>('.rk-row[data-base]')
      if (row) openBase(row.dataset.base!)
    })
  }

  secList.addEventListener('click', e => {
    const row = tgt(e).closest<HTMLElement>('.sc-row[data-sec]')
    if (!row) return
    // 板块页自己的入口：切到加密、选中这一块、滚到它（pages/sectors.ts openSector）；没装上就只进板块页
    if (hooks.openSector) hooks.openSector('c:' + row.dataset.sec)
    else go('sectors')
  })
  q('.hm-scbtn').addEventListener('click', () => go('sectors'))

  // 账号变了：重新拉、重新定序；自选变了：星与范围跟着改（不打断当前顺序）
  onSession(() => { shown = null; latest = null; listState = ''; if (active) { renderMoves(); void loadMoves(true) } })
  let favSig = favorites().join(',')
  subscribe(() => {
    const sig = favorites().join(',')
    if (sig === favSig) return
    favSig = sig
    if (active && shown) { renderSub(); renderList() }
  })
  // 品种表到了：小数位、徽章、千枚代号都跟着它认，重画一遍
  hooks.booted.push(() => {
    if (!active) return
    if (shown) renderList()
    renderRank('change'); renderRank('oi')
    renderSectors()
  })
  document.addEventListener('visibilitychange', () => {
    if (active && !document.hidden && Date.now() - lastPoll >= POLL_MS) tick()
  })

  hooks.pageShown.home = () => {
    active = true
    measureRanks()
    renderMoves(); renderRank('change'); renderRank('oi'); renderSectors()
    if (!shown && !loading) { lastPoll = Date.now(); void loadMoves(true); loadRanks() }
    else if (Date.now() - lastPoll >= POLL_MS) tick()
    startPoll()
    startFeed(renderSectors)
  }
  hooks.pageHidden.home = () => {
    active = false
    stopPoll()
    stopFeed()
  }
}
