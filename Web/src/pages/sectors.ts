/* Hkline Web · 板块页
 *
 * 左：板块列表（加密 / 美股 · 今日 / 5 日），每行 板块名 · 走势 · 跑赢大盘 · 涨跌幅；
 * 右：点中的那个板块的品种列表（照自选列表：徽标、代号、中文名、最新价、涨跌幅、成交额），
 *     点品种直接去图表页。
 * 口径全部在 src/sectors/aggregate.ts，和手机端逐条一致；本页只管取数、排版与交互。
 */
import '../styles/sectors.css'
import { st } from '../app/store'
import { hooks, go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { GLOSSARY, term } from '../ui/overlay'
import { badge, cls, pctText, priceText, sym } from '../ui/common'
import { fmtCompact } from '../util/format'
import { S, badgeColor, streamName } from '../market'
import { openSymbol, toggleWatch, isWatched, refreshStreams } from './chart'
import {
  EMPTY_HISTORY, MIN_ELIGIBLE_MEMBERS, boardOrder, catalog, hasEligible, isThin, outperformCount, rankable, resolveWindow, stats, symbolRows, windowReturn,
} from '../sectors/aggregate'
import type { SectorMarket, SectorStat, SectorWindow, SymbolRow } from '../sectors/aggregate'
import { applyLive, feed, seedFromUniverse, startFeed, stopFeed } from '../sectors/feed'
import { history, startHistory, stopHistory } from '../sectors/history'
import { PER_BOARD, boardPath, sparkSVG, stopSparks, wantSparks } from '../sectors/spark'
import { pickWindow, shownWindow } from '../sectors/window'

GLOSSARY['跑赢大盘'] = '这段时间里，板块成员跑赢全市场等权平均的有几只（分母是有行情的成员数）。'
GLOSSARY['领涨'] = '跑赢大盘，而且涨幅排进全市场前 10% 的成员。'
GLOSSARY['板块涨跌'] = '板块成员涨跌幅的中位数，不会被一两只暴涨暴跌的带偏。'

// 市场与窗口是这台电脑上的个人选择，只记本机
const PREF_KEY = 'hkline-web-sectors-v1'
function loadPref(): { market: SectorMarket; want: SectorWindow } {
  try {
    const p = JSON.parse(localStorage.getItem(PREF_KEY) || '{}') as { market?: string; want?: string }
    return { market: p.market === 'us' ? 'us' : 'crypto', want: p.want === 'd5' ? 'd5' : 'today' }
  } catch { return { market: 'crypto', want: 'today' } }
}
function savePref(): void { try { localStorage.setItem(PREF_KEY, JSON.stringify({ market: sp.market, want: sp.want })) } catch { /* 存不下就不存 */ } }

const pref = loadPref()
const sp = {
  market: pref.market,
  want: pref.want,
  /** 这一次临时改看的窗口（见 sectors/window.ts），不进偏好 */
  once: null as SectorWindow | null,
  /** 选中的板块：去掉市场前缀的 id（目录 id 或兜底桶 id） */
  sel: null as string | null,
  /** 右侧列表里正在显示、并订了推送的合约，及其 base */
  visible: [] as string[],
  baseOf: new Map<string, string>(),
  window: 'today' as SectorWindow,
  boards: [] as SectorStat[],
  built: '',
}
const membersOf = (id: string): string[] => {
  const d = catalog.sector(id)
  if (d && d.market === sp.market) return d.members
  return feed.buckets[sp.market].find(b => b.id === id)?.members ?? []
}
const nameOf = (id: string): string => catalog.sector(id)?.name ?? feed.buckets[sp.market].find(b => b.id === id)?.name ?? ''

// ------------------------------------------------------------ 算

function compute(): { hasD5: boolean; title: string } {
  const m = sp.market, buckets = feed.buckets[m]
  const hasD5 = hasEligible(m, feed.quotes, 'd5', history.held)
  const w = resolveWindow(shownWindow(sp), hasD5)
  sp.window = w.window
  let list = stats(m, feed.quotes, buckets, w.window, w.window === 'today' ? EMPTY_HISTORY : history.held)
  if (w.window !== 'today') list = list.filter(s => rankable(m, s, feed.quotes, w.window, history.held, buckets))
  sp.boards = boardOrder(list)
  // 行情没到（列表还空着）时保留外面指定的板块；列表出来后选中的必须在列表里（5 日会滤掉覆盖不足的板块）
  const known = sp.sel != null && (sp.boards.length ? sp.boards.some(b => b.id === sp.sel) : (catalog.sector(sp.sel)?.market === m || buckets.some(b => b.id === sp.sel)))
  if (!known) sp.sel = sp.boards[0]?.id ?? null
  return { hasD5, title: w.title }
}

// ------------------------------------------------------------ 画

function skeleton(): void {
  if (sp.built) return
  sp.built = '1'
  $('#secList').innerHTML = `<div class="page-head sec-head" id="secHead"></div>
    <div class="scroll sec-scroll"><table class="tbl sec-boards"><colgroup><col class="c-name"><col class="c-spark"><col class="c-beat"><col class="c-pct"></colgroup>
      <thead id="secThead"></thead><tbody id="secBody"></tbody></table><div id="secEmpty"></div></div>`
  $('#secMembers').innerHTML = `<div class="page-head sec-head" id="secMHead"></div>
    <div class="scroll sec-scroll"><table class="tbl sec-syms"><colgroup><col class="c-name"><col class="c-price"><col class="c-pct"><col class="c-vol"><col class="c-star"></colgroup>
      <thead id="secMThead"></thead><tbody id="secMBody"></tbody></table><div id="secMEmpty"></div></div>`
  $('#secPreview').innerHTML = ''
}

function renderHead(hasD5: boolean): void {
  const seg = `<div class="seg" role="group" aria-label="市场">
      <button data-mk="crypto" aria-pressed="${sp.market === 'crypto'}">加密</button><button data-mk="us" aria-pressed="${sp.market === 'us'}">美股</button></div>`
  const chips = hasD5 ? `<div class="sec-win" role="group" aria-label="时间段">
      <button class="chip" data-win="today" aria-pressed="${sp.window === 'today'}">今日</button><button class="chip" data-win="d5" aria-pressed="${sp.window === 'd5'}">5 日</button></div>` : ''
  $('#secHead').innerHTML = `<h2>板块</h2>${seg}${chips}`
  $('#secThead').innerHTML = `<tr><th>板块</th><th>走势</th><th>${term('跑赢大盘')}</th><th>${term('板块涨跌', '涨跌幅')}</th></tr>`
}

function boardRow(s: SectorStat): string {
  const n = s.memberCount, thin = isThin(s)
  // 不到三家有行情：不算跑赢大盘、整档沉底（和手机一致）。格子写「—」不留空（空着像数据没到），悬停说明为什么
  const beat = thin
    ? `<span class="faint sec-thin" data-tip="只有 ${n} 只有行情，不到 ${MIN_ELIGIBLE_MEMBERS} 只不算跑赢大盘，排在最后">—</span>`
    : `${outperformCount(s)}<span class="faint"> / ${n}</span>`
  return `<tr data-sec="${esc(s.id)}"${thin ? ' data-thin="1"' : ''} class="${s.id === sp.sel ? 'sel' : ''}" aria-selected="${s.id === sp.sel}" tabindex="0">
    <td><span class="sec-name">${esc(s.name)}</span></td>
    <td><svg class="sec-spark" data-spark="${esc(s.id)}" viewBox="0 0 160 32" preserveAspectRatio="none" aria-hidden="true">${sparkOf(s)}</svg></td>
    <td class="num">${beat}</td>
    <td class="num sec-pct ${cls(s.pct)}">${pctText(s.pct)}</td></tr>`
}

function renderBoards(): void {
  const empty = $('#secEmpty')
  if (!sp.boards.length) {
    $('#secBody').innerHTML = ''
    empty.innerHTML = emptyHTML()
    return
  }
  empty.innerHTML = ''
  $('#secBody').innerHTML = sp.boards.map(boardRow).join('')
}

function emptyHTML(): string {
  if (!feed.quotes.size) {
    const down = feed.ok === false || S.live === false
    return down ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>连不上币安合约接口</div></div>` : '<div class="empty">正在取行情…</div>'
  }
  return '<div class="empty">这个市场暂时没有板块行情</div>'
}

function symbolRowHTML(r: SymbolRow): string {
  const k = feed.quotes.get(r.base)?.symbol ?? r.base + 'USDT'
  const s = sym(k)
  const code = s?.code ?? r.base
  const cn0 = s?.cn || catalog.chineseName(r.base) || ''
  const cn = cn0.toUpperCase() === code.toUpperCase() ? '' : cn0
  const star = isWatched(k)
  return `<tr data-msym="${esc(k)}" tabindex="0">
    <td><div class="sym">${badge(s ?? { base: code, color: badgeColor(code) })}<b>${esc(code)}</b><span class="cn">${esc(cn)}</span>${r.isFrontier ? `<span class="sec-lead">领涨</span>` : ''}</div></td>
    <td class="num price-live" data-f="price">${priceText(s, Number.isFinite(r.price) ? r.price : null)}</td>
    <td class="num ${cls(r.pct)} price-live" data-f="pct">${pctText(r.pct)}</td>
    <td class="num muted" data-f="vol">${fmtCompact(r.quoteVolume)}</td>
    <td><button class="ibtn sm sec-star" data-star="${esc(k)}" aria-label="${star ? '移出自选' : '加入自选'}" aria-pressed="${star}">${I(star ? 'star' : 'starOff', 'icon-16')}</button></td></tr>`
}

function renderMembers(title: string): void {
  const id = sp.sel
  const stat = sp.boards.find(b => b.id === id)
  const head = $('#secMHead'), body = $('#secMBody'), empty = $('#secMEmpty')
  $('#secMThead').innerHTML = `<tr><th>品种</th><th>最新价</th><th>${title}涨跌</th><th>成交额</th><th></th></tr>`
  if (!id) { head.innerHTML = ''; body.innerHTML = ''; empty.innerHTML = feed.quotes.size ? '' : emptyHTML(); setVisible([]); return }
  const rows = symbolRows(membersOf(id), feed.quotes, stat?.frontier ?? [], sp.window, history.held)
  const n = stat?.memberCount ?? 0
  const sub = stat && !isThin(stat) ? `${title} · <span class="num">${outperformCount(stat)}/${n}</span> ${term('跑赢大盘')}` : title
  const lead = stat?.frontier.length ? ` · ${term('领涨')} <span class="num">${stat.frontier.length}</span>` : ''
  head.innerHTML = `<h2>${esc(nameOf(id))}</h2>${stat ? `<span class="num sec-big ${cls(stat.pct)}">${pctText(stat.pct)}</span>` : ''}<span class="sub">${sub}${lead}</span>`
  body.innerHTML = rows.map(symbolRowHTML).join('')
  empty.innerHTML = rows.length ? '' : '<div class="empty">这个板块暂时没有行情</div>'
  sp.baseOf = new Map()
  for (const r of rows) { const k = feed.quotes.get(r.base)?.symbol; if (k && S.symbols.has(k)) sp.baseOf.set(k, r.base) }
  setVisible([...sp.baseOf.keys()])
}

function setVisible(list: string[]): void {
  const same = list.length === sp.visible.length && list.every((k, i) => k === sp.visible[i])
  sp.visible = list
  if (!same) refreshStreams()
}

function render(): void {
  if (st.page !== 'sectors') return
  skeleton()
  seedFromUniverse()
  const { hasD5, title } = compute()
  renderHead(hasD5)
  renderBoards()
  renderMembers(title)
  requestSparks()
}

// ------------------------------------------------------------ 走势

function sparkMembers(s: SectorStat): string[] {
  return membersOf(s.id).map(b => feed.quotes.get(b)).filter(q => q?.symbol && S.symbols.has(q.symbol) && Number.isFinite(q.quoteVolume))
    .sort((a, b) => b!.quoteVolume - a!.quoteVolume).slice(0, PER_BOARD).map(q => q!.symbol as string)
}
function sparkOf(s: SectorStat): string {
  return sparkSVG(boardPath(sparkMembers(s), sp.window, history.held.asof), cls(s.pct) as 'up' | 'down' | '')
}
function requestSparks(): void {
  wantSparks(sp.boards.flatMap(sparkMembers), () => {
    if (st.page !== 'sectors') return
    for (const s of sp.boards) { const el = document.querySelector(`[data-spark="${CSS.escape(s.id)}"]`); if (el) el.innerHTML = sparkOf(s) }
  })
}

// ------------------------------------------------------------ 推送

function patchTicks(): void {
  if (st.page !== 'sectors' || !sp.visible.length) return
  applyLive(sp.visible)
  for (const k of sp.visible) {
    const tr = document.querySelector(`#secMBody tr[data-msym="${CSS.escape(k)}"]`); if (!tr) continue
    const s = sym(k), b = sp.baseOf.get(k), base = b ? feed.quotes.get(b) : undefined
    if (!s || !base) continue
    const pct = windowReturn(base, sp.window, history.held.closes.get(base.base)) ?? NaN
    const p = tr.querySelector('[data-f="price"]'), pc = tr.querySelector('[data-f="pct"]'), v = tr.querySelector('[data-f="vol"]')
    if (p) p.textContent = priceText(s, base.price)
    if (pc) { pc.textContent = pctText(pct); pc.className = `num ${cls(pct)} price-live` }
    if (v) v.textContent = fmtCompact(base.quoteVolume)
  }
}

// ------------------------------------------------------------ 交互

function select(id: string): void {
  sp.sel = id
  $$('#secBody tr[data-sec]').forEach(x => { const on = x.dataset.sec === id; x.classList.toggle('sel', on); x.setAttribute('aria-selected', String(on)) })
  renderMembers(sp.window === 'd5' ? '5 日' : '今日')
  $('#secMembers .sec-scroll').scrollTop = 0
}

function openSector(full: string): void {
  const m: SectorMarket = full.startsWith('u:') ? 'us' : 'crypto'
  const id = full.replace(/^[cu]:/, '')
  if (m !== sp.market) { sp.market = m; savePref() }
  sp.sel = id
  sp.once = null
  // 从图表点进来的板块若 5 日覆盖不足、不在 5 日榜上，这一次先看今日（不改存下的偏好）
  if (sp.want === 'd5' && feed.quotes.size) {
    compute()
    if (sp.window === 'd5' && !sp.boards.some(b => b.id === id)) { sp.once = 'today'; sp.sel = id }
  }
  go('sectors')
  render()
  document.querySelector('#secBody tr.sel')?.scrollIntoView({ block: 'center' })
}

function openInChart(k: string | undefined): void {
  if (!k || !S.symbols.has(k)) return
  go('chart'); openSymbol(k)
}

export function initSectors(): void {
  const page = $('#page-sectors')
  page.addEventListener('click', e => {
    const t = tgt(e)
    if (t.closest('.term')) return
    const mk = t.closest<HTMLElement>('[data-mk]')
    if (mk) { const m = mk.dataset.mk === 'us' ? 'us' : 'crypto'; if (m !== sp.market) { sp.market = m; sp.sel = null; sp.once = null; savePref(); $('#secList .sec-scroll').scrollTop = 0; render() } return }
    const win = t.closest<HTMLElement>('[data-win]')
    if (win) {
      const p = pickWindow(sp, win.dataset.win === 'd5' ? 'd5' : 'today')
      if (p) { sp.want = p.next.want; sp.once = p.next.once; if (p.save) savePref(); render() }
      return
    }
    const star = t.closest<HTMLElement>('[data-star]')
    if (star) {
      const k = star.dataset.star || ''; toggleWatch(k)
      const on = isWatched(k)
      star.innerHTML = I(on ? 'star' : 'starOff', 'icon-16'); star.setAttribute('aria-pressed', String(on)); star.setAttribute('aria-label', on ? '移出自选' : '加入自选')
      return
    }
    const r = t.closest<HTMLElement>('[data-sec]'); if (r) { select(r.dataset.sec || ''); return }
    const m = t.closest<HTMLElement>('[data-msym]'); if (m) openInChart(m.dataset.msym)
  })
  page.addEventListener('keydown', e => {
    const r = tgt(e).closest<HTMLElement>('tr[data-sec],tr[data-msym]'); if (!r) return
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const n = (e.key === 'ArrowDown' ? r.nextElementSibling : r.previousElementSibling) as HTMLElement | null
      if (n) { n.focus(); if (n.dataset.sec) select(n.dataset.sec) }
    }
    if (e.key === 'Enter') { if (r.dataset.msym) openInChart(r.dataset.msym); else ($('#secMBody tr[data-msym]') as HTMLElement | null)?.focus() }
    if (e.key === 'ArrowRight' && r.dataset.sec) { e.preventDefault(); ($('#secMBody tr[data-msym]') as HTMLElement | null)?.focus() }
    if (e.key === 'ArrowLeft' && r.dataset.msym) { e.preventDefault(); ($('#secBody tr.sel') as HTMLElement | null)?.focus() }
  })
  hooks.openSector = openSector
  hooks.pageShown.sectors = () => {
    render()
    startFeed(render)
    startHistory(render)
  }
  hooks.pageHidden.sectors = () => { sp.once = null; stopFeed(); stopHistory(); stopSparks(); sp.visible = []; refreshStreams() }
  hooks.extraStreams.push(() => st.page === 'sectors' ? sp.visible.map(k => streamName.ticker(k)) : [])
  hooks.onTicks.push(patchTicks)
  hooks.booted.push(() => { if (st.page === 'sectors') render() })
}

