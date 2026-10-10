/* Hkline Web · 板块页
 *
 * 左：板块列表（加密 / 美股 · 今日 / 5 日），每行 板块名 · 跑赢大盘 · 涨跌幅（2026-10-10 删掉了「走势」迷你线一列：
 *     用户嫌它「像一根线一样很丑都不搭配」；本页因此也不再为板块拉成员的小时 K 线）；
 * 右：点中的那个板块的品种列表（照自选列表：徽标、代号、中文名、最新价、涨跌幅、成交额），
 *     点品种直接去图表页。
 * 口径全部在 src/sectors/aggregate.ts，和手机端逐条一致；本页只管取数、排版与交互。
 */
import '../styles/sectors.css'
import { st, save, subscribe } from '../app/store'
import { hooks, go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { morphHtml, patchKeyedRows } from '../ui/patch'
import { GLOSSARY, term } from '../ui/overlay'
import { badge, cls, pctText, priceText, sym, venueTag } from '../ui/common'
import { fmtCompact } from '../util/format'
import { S, streamName } from '../market'
import { openSymbol, toggleWatch, isWatched, refreshStreams } from './chart'
import {
  EMPTY_HISTORY, MIN_ELIGIBLE_MEMBERS, boardOrder, catalog, hasEligible, isThin, outperformCount, rankable, resolveWindow, stats, symbolRows, windowReturn,
} from '../sectors/aggregate'
import type { SectorMarket, SectorStat, SectorWindow, SymbolRow } from '../sectors/aggregate'
import { applyLive, feed, seedFromUniverse, startFeed, stopFeed } from '../sectors/feed'
import { history, startHistory, stopHistory } from '../sectors/history'
import { pickWindow, shownWindow } from '../sectors/window'

GLOSSARY['跑赢大盘'] = '这段时间里，板块成员跑赢全市场等权平均的有几只（分母是有行情的成员数）。'
GLOSSARY['领涨'] = '跑赢大盘，而且涨幅排进全市场前 10% 的成员。'
GLOSSARY['板块涨跌'] = '板块成员涨跌幅的中位数，不会被一两只暴涨暴跌的带偏。'

// 市场与窗口随账号走：st.sectorMarket / sectorWindow（和手机 Prefs 同一对共用字段；网页只有今日 / 5 日，手机的 20 日装不进来）。
// 2026-10-10 以前只记本机这个键：第一次打开读一次并进 st（只在 st 还是出厂值时），然后删掉
const OLD_PREF_KEY = 'hkline-web-sectors-v1'
function migratePref(): void {
  try {
    const raw = localStorage.getItem(OLD_PREF_KEY)
    if (raw == null) return
    const p = JSON.parse(raw) as { market?: string; want?: string } | null
    if (p?.market === 'us' && st.sectorMarket === 'crypto') st.sectorMarket = 'us'
    if (p?.want === 'd5' && st.sectorWindow === 'today') st.sectorWindow = 'd5'
    localStorage.removeItem(OLD_PREF_KEY)
    save()
  } catch { /* 读不到就当没有 */ }
}
function savePref(): void { st.sectorMarket = sp.market; st.sectorWindow = sp.want === 'd5' ? 'd5' : 'today'; save() }
/** 别的设备改了市场 / 窗口（同步装进 st）：本页跟着换，正开着就重画 */
function followPref(): void {
  if (sp.market === st.sectorMarket && sp.want === st.sectorWindow) return
  if (sp.market !== st.sectorMarket) { sp.market = st.sectorMarket; sp.sel = null }
  sp.want = st.sectorWindow; sp.once = null
  if (st.page === 'sectors') render()
}

const sp = {
  market: st.sectorMarket as SectorMarket,
  want: st.sectorWindow as SectorWindow,
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
    <div class="scroll sec-scroll"><table class="tbl sec-boards"><colgroup><col class="c-name"><col class="c-beat"><col class="c-pct"></colgroup>
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
  // 每 10 秒的重算也走这里：就地改（按钮节点留着），不整块换——换了指针下的按钮 / 提示要等下一次 mousemove 才回来
  morphHtml($('#secHead'), `<h2>板块</h2>${seg}${chips}`)
  morphHtml($('#secThead'), `<tr><th>板块</th><th>${term('跑赢大盘')}</th><th>${term('板块涨跌', '涨跌幅')}</th></tr>`)
}

function boardRow(s: SectorStat): string {
  const n = s.memberCount, thin = isThin(s)
  // 不到三家有行情：不算跑赢大盘、整档沉底（和手机一致）。格子写「—」不留空（空着像数据没到），悬停说明为什么
  const beat = thin
    ? `<span class="faint sec-thin" data-tip="只有 ${n} 只有行情，不到 ${MIN_ELIGIBLE_MEMBERS} 只不算跑赢大盘，排在最后">—</span>`
    : `${outperformCount(s)}<span class="faint"> / ${n}</span>`
  return `<tr data-sec="${esc(s.id)}"${thin ? ' data-thin="1"' : ''} class="${s.id === sp.sel ? 'sel' : ''}" aria-selected="${s.id === sp.sel}" tabindex="0">
    <td><span class="sec-name">${esc(s.name)}</span></td>
    <td class="num">${beat}</td>
    <td class="num sec-pct ${cls(s.pct)}">${pctText(s.pct)}</td></tr>`
}

function renderBoards(): void {
  const empty = $('#secEmpty')
  if (!sp.boards.length) {
    patchKeyedRows($('#secBody'), [], 'data-sec')
    morphHtml(empty, emptyHTML())
    return
  }
  morphHtml(empty, '')
  // 板块行按 id 复用：10 秒一次的重算只改变了的字 / 类，顺序变了挪位置，指针下的行不被换掉（探针 sector 场景量过）
  patchKeyedRows($('#secBody'), sp.boards.map(s => [s.id, boardRow(s)] as const), 'data-sec')
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
    <td><div class="sym">${badge(s ?? { base: code })}${venueTag(k)}<b>${esc(code)}</b><span class="cn">${esc(cn)}</span>${r.isFrontier ? `<span class="sec-lead">领涨</span>` : ''}</div></td>
    <td class="num price-live" data-f="price">${priceText(s, Number.isFinite(r.price) ? r.price : null)}</td>
    <td class="num ${cls(r.pct)} price-live" data-f="pct">${pctText(r.pct)}</td>
    <td class="num muted" data-f="vol">${fmtCompact(r.quoteVolume)}</td>
    <td><button class="ibtn sm sec-star" data-star="${esc(k)}" aria-label="${star ? '移出自选' : '加入自选'}" aria-pressed="${star}">${I(star ? 'star' : 'starOff', 'icon-16')}</button></td></tr>`
}

function renderMembers(title: string): void {
  const id = sp.sel
  const stat = sp.boards.find(b => b.id === id)
  const head = $('#secMHead'), body = $('#secMBody'), empty = $('#secMEmpty')
  morphHtml($('#secMThead'), `<tr><th>品种</th><th>最新价</th><th>${title}涨跌</th><th>成交额</th><th></th></tr>`)
  if (!id) { morphHtml(head, ''); patchKeyedRows(body, [], 'data-msym'); morphHtml(empty, feed.quotes.size ? '' : emptyHTML()); setVisible([]); return }
  const rows = symbolRows(membersOf(id), feed.quotes, stat?.frontier ?? [], sp.window, history.held)
  const n = stat?.memberCount ?? 0
  const sub = stat && !isThin(stat) ? `${title} · <span class="num">${outperformCount(stat)}/${n}</span> ${term('跑赢大盘')}` : title
  const lead = stat?.frontier.length ? ` · ${term('领涨')} <span class="num">${stat.frontier.length}</span>` : ''
  morphHtml(head, `<h2>${esc(nameOf(id))}</h2>${stat ? `<span class="num sec-big ${cls(stat.pct)}">${pctText(stat.pct)}</span>` : ''}<span class="sub">${sub}${lead}</span>`)
  // 成员行按品种复用（同板块的 10 秒重算只改字；星标按钮等节点留着）
  patchKeyedRows(body, rows.map(r => [feed.quotes.get(r.base)?.symbol ?? r.base + 'USDT', symbolRowHTML(r)] as const), 'data-msym')
  morphHtml(empty, rows.length ? '' : '<div class="empty">这个板块暂时没有行情</div>')
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
  migratePref()
  sp.market = st.sectorMarket; sp.want = st.sectorWindow
  subscribe(followPref)
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
  hooks.pageHidden.sectors = () => { sp.once = null; stopFeed(); stopHistory(); sp.visible = []; refreshStreams() }
  hooks.extraStreams.push(() => st.page === 'sectors' ? sp.visible.map(k => streamName.ticker(k)) : [])
  hooks.onTicks.push(patchTicks)
  hooks.booted.push(() => { if (st.page === 'sectors') render() })
}

