/* Hkline Web · 板块页（2026-10-10 照定稿原型 docs/prototypes/web-layout-2026-10-10.html 第 5 节重排）
 *
 * 左（38%）：栏头「板块 · N 个 · 大盘 ±x% · 今日」+ 市场 / 窗口分段；表三列 板块 · 涨跌幅（字 + 72×4 强弱条，
 *     中线为 0，长度按本表最大绝对涨跌幅）· 跑赢大盘（x / N）。名字一列、数字一块：数字两列定宽约 260、
 *     名字列不超过 420，表靠左，右边留空（同日早些时候删掉了「走势」迷你线一列，本页不再为板块拉小时 K 线）。
 * 右（62%）：栏头「板块名 · N 只 · 涨跌幅 · 跑赢大盘 x / N」+ 排序胶囊（涨跌幅 / 成交额 / 持仓变化，只记本机）；
 *     成分表 品种（徽标 + 代号 + 永续 / 现货）· 最新价 · 涨跌 · 成交额 · 持仓变化 · 费率 · 星，点行去图表页。
 *     持仓变化逐只取（sectors/oi.ts），费率用全市场表里 premiumIndex 的那份。
 * 口径全部在 src/sectors/aggregate.ts，和手机端逐条一致；本页只管取数、排版与交互。
 */
import '../styles/sectors.css'
import { st, save, subscribe } from '../app/store'
import { hooks, go } from '../app/shell'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { morphHtml, patchKeyedRows } from '../ui/patch'
import { GLOSSARY, term } from '../ui/overlay'
import { badge, cls, pctText, priceText, sym } from '../ui/common'
import { parseKey } from '../market'
import { fmtCompact } from '../util/format'
import { S, streamName } from '../market'
import { openSymbol, toggleWatch, isWatched, refreshStreams } from './chart'
import {
  EMPTY_HISTORY, MIN_ELIGIBLE_MEMBERS, boardOrder, catalog, hasEligible, isThin, marketReturn, outperformCount, rankable, resolveWindow, stats, symbolRows, windowReturn,
} from '../sectors/aggregate'
import type { SectorMarket, SectorStat, SectorWindow, SymbolRow } from '../sectors/aggregate'
import { applyLive, feed, seedFromUniverse, startFeed, stopFeed } from '../sectors/feed'
import { history, startHistory, stopHistory } from '../sectors/history'
import { pickWindow, shownWindow } from '../sectors/window'
import { MEMBER_SORTS, SORT_KEY, barScale, fundingText, parseSort, sortMembers, strengthBar } from '../sectors/view'
import type { MemberSort } from '../sectors/view'
import { loadOiChanges, oiChangeOf, stopOiChanges } from '../sectors/oi'

GLOSSARY['跑赢大盘'] = '这段时间里，板块成员跑赢全市场等权平均的有几只（分母是有行情的成员数）。'
GLOSSARY['领涨'] = '跑赢大盘，而且涨幅排进全市场前 10% 的成员。'
GLOSSARY['板块涨跌'] = '板块成员涨跌幅的中位数，不会被一两只暴涨暴跌的带偏。'
GLOSSARY['大盘'] = '全市场等权平均的涨跌幅，跑赢大盘就是和它比。'
GLOSSARY['持仓变化'] = '最近 24 小时持仓价值的变化，和图表页详情里的「持仓 24h」同一口径。'

/** 成分表按哪列排：只记本机，不随账号走（读写失败就当涨跌幅） */
function readSort(): MemberSort { try { return parseSort(localStorage.getItem(SORT_KEY)) } catch { return 'pct' } }
function writeSort(k: MemberSort): void { try { localStorage.setItem(SORT_KEY, k) } catch { /* 隐私模式 */ } }

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
  /** 大盘这段窗口的涨跌幅（%）；算不出 null */
  bench: null as number | null,
  sort: 'pct' as MemberSort,
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
  const hist = w.window === 'today' ? EMPTY_HISTORY : history.held
  let list = stats(m, feed.quotes, buckets, w.window, hist)
  if (w.window !== 'today') list = list.filter(s => rankable(m, s, feed.quotes, w.window, history.held, buckets))
  sp.boards = boardOrder(list)
  sp.bench = sp.boards.length ? marketReturn(m, feed.quotes, buckets, w.window, hist) : null
  // 行情没到（列表还空着）时保留外面指定的板块；列表出来后选中的必须在列表里（5 日会滤掉覆盖不足的板块）
  const known = sp.sel != null && (sp.boards.length ? sp.boards.some(b => b.id === sp.sel) : (catalog.sector(sp.sel)?.market === m || buckets.some(b => b.id === sp.sel)))
  if (!known) sp.sel = sp.boards[0]?.id ?? null
  return { hasD5, title: w.title }
}

// ------------------------------------------------------------ 画

function skeleton(): void {
  if (sp.built) return
  sp.built = '1'
  $('#secList').innerHTML = `<div class="sec-head" id="secHead"></div>
    <div class="scroll sec-scroll"><table class="tbl sec-boards"><colgroup><col class="c-name"><col class="c-pct"><col class="c-beat"></colgroup>
      <thead id="secThead"></thead><tbody id="secBody"></tbody></table><div id="secEmpty"></div></div>`
  $('#secMembers').innerHTML = `<div class="sec-head" id="secMHead"></div>
    <div class="scroll sec-scroll"><table class="tbl sec-syms"><colgroup><col class="c-name"><col class="c-price"><col class="c-pct"><col class="c-vol"><col class="c-oi"><col class="c-fr"><col class="c-star"></colgroup>
      <thead id="secMThead"></thead><tbody id="secMBody"></tbody></table><div id="secMEmpty"></div></div>`
  $('#secPreview').innerHTML = ''
}

function renderHead(hasD5: boolean, title: string): void {
  const n = sp.boards.length
  const sub = n ? `<span class="num">${n}</span> 个 · ${term('大盘')} <span class="num ${cls(sp.bench)}">${pctText(sp.bench)}</span> · ${title}` : ''
  const seg = `<div class="seg" role="group" aria-label="市场">
      <button data-mk="crypto" aria-pressed="${sp.market === 'crypto'}">加密</button><button data-mk="us" aria-pressed="${sp.market === 'us'}">美股</button></div>`
  const wins = hasD5 ? `<div class="seg sec-win" role="group" aria-label="时间段">
      <button data-win="today" aria-pressed="${sp.window === 'today'}">今日</button><button data-win="d5" aria-pressed="${sp.window === 'd5'}">5 日</button></div>` : ''
  // 每 10 秒的重算也走这里：就地改（按钮节点留着），不整块换——换了指针下的按钮 / 提示要等下一次 mousemove 才回来
  morphHtml($('#secHead'), `<h2>板块</h2><span class="sub">${sub}</span><div class="sec-tools">${seg}${wins}</div>`)
  morphHtml($('#secThead'), `<tr><th>板块</th><th>${term('板块涨跌', '涨跌幅')}</th><th>${term('跑赢大盘')}</th></tr>`)
}

function boardRow(s: SectorStat, scale: number): string {
  const n = s.memberCount, thin = isThin(s), on = s.id === sp.sel
  // 不到三家有行情：不算跑赢大盘、整档沉底（和手机一致）。格子写「—」不留空（空着像数据没到），悬停说明为什么
  const beat = thin
    ? `<span class="faint sec-thin" data-tip="只有 ${n} 只有行情，不到 ${MIN_ELIGIBLE_MEMBERS} 只不算跑赢大盘，排在最后">—</span>`
    : `${outperformCount(s)}<span class="faint"> / ${n}</span>`
  const b = strengthBar(s.pct, scale)
  return `<tr data-sec="${esc(s.id)}"${thin ? ' data-thin="1"' : ''} class="${on ? 'sel' : ''}" aria-selected="${on}" tabindex="0">
    <td><span class="sec-name">${esc(s.name)}</span></td>
    <td class="num"><span class="sec-pct ${cls(s.pct)}">${pctText(s.pct)}</span><span class="sec-sb" aria-hidden="true"><i class="${b.dir}" style="left:${b.left}%;width:${b.width}%"></i></span></td>
    <td class="num sec-beat">${beat}</td></tr>`
}

function renderBoards(): void {
  const empty = $('#secEmpty')
  if (!sp.boards.length) {
    patchKeyedRows($('#secBody'), [], 'data-sec')
    morphHtml(empty, emptyHTML())
    return
  }
  morphHtml(empty, '')
  const scale = barScale(sp.boards.map(b => b.pct))
  // 板块行按 id 复用：10 秒一次的重算只改变了的字 / 类，顺序变了挪位置，指针下的行不被换掉（探针 sector 场景量过）
  patchKeyedRows($('#secBody'), sp.boards.map(s => [s.id, boardRow(s, scale)] as const), 'data-sec')
}

function emptyHTML(): string {
  if (!feed.quotes.size) {
    const down = feed.ok === false || S.live === false
    return down ? `<div class="empty">${I('wifiOff', 'icon-24')}<div>连不上币安合约接口</div></div>` : '<div class="empty">正在取行情…</div>'
  }
  return '<div class="empty">这个市场暂时没有板块行情</div>'
}

const keyOfRow = (r: SymbolRow): string => feed.quotes.get(r.base)?.symbol ?? r.base + 'USDT'
/** 持仓变化按两位小数取整后再定号与色：−0.004% 写「0.00%」不标红 */
const oiRound = (v: number | null | undefined): number | null => v == null || !Number.isFinite(v) ? null : Math.round(v * 100) / 100 || 0

function symbolRowHTML(r: SymbolRow): string {
  const k = keyOfRow(r)
  const s = sym(k)
  const code = s?.code ?? r.base
  const cn0 = s?.cn || catalog.chineseName(r.base) || ''
  const cn = cn0.toUpperCase() === code.toUpperCase() ? '' : cn0
  const kind = parseKey(k).market === 'spot' ? '现货' : '永续'
  const star = isWatched(k)
  const oi = oiRound(oiChangeOf(k))
  // 中文名不占列（原型只写代号 + 永续 / 现货），悬停代号看得到；板块成员全是币安合约，不再逐行写「币安」
  return `<tr data-msym="${esc(k)}" tabindex="0">
    <td><div class="sym">${badge(s ?? { base: code })}<b${cn ? ` data-tip="${esc(cn)}"` : ''}>${esc(code)}</b><span class="sec-kind">${kind}</span>${r.isFrontier ? `<span class="sec-lead" data-tip="${esc(GLOSSARY['领涨'])}">领涨</span>` : ''}</div></td>
    <td class="num price-live" data-f="price">${priceText(s, Number.isFinite(r.price) ? r.price : null)}</td>
    <td class="num ${cls(r.pct)} price-live" data-f="pct">${pctText(r.pct)}</td>
    <td class="num" data-f="vol">${fmtCompact(r.quoteVolume)}</td>
    <td class="num ${cls(oi)}" data-f="oi">${pctText(oi)}</td>
    <td class="num" data-f="fr">${fundingText(s?.fr)}</td>
    <td><button class="ibtn sm sec-star" data-star="${esc(k)}" aria-label="${star ? '移出自选' : '加入自选'}" aria-pressed="${star}">${I(star ? 'star' : 'starOff', 'icon-16')}</button></td></tr>`
}

function renderMembers(title: string, fetchOi = true): void {
  const id = sp.sel
  const stat = sp.boards.find(b => b.id === id)
  const head = $('#secMHead'), body = $('#secMBody'), empty = $('#secMEmpty')
  morphHtml($('#secMThead'), `<tr><th>品种</th><th>最新价</th><th>${title}涨跌</th><th>成交额</th><th>${term('持仓变化')}</th><th>${term('资金费率', '费率')}</th><th></th></tr>`)
  if (!id) { morphHtml(head, ''); patchKeyedRows(body, [], 'data-msym'); morphHtml(empty, feed.quotes.size ? '' : emptyHTML()); setVisible([]); return }
  const raw = symbolRows(membersOf(id), feed.quotes, stat?.frontier ?? [], sp.window, history.held)
  const rows = sortMembers(raw, sp.sort, r => oiChangeOf(keyOfRow(r)))
  const n = stat?.memberCount ?? 0
  const parts = [`<span class="num">${rows.length}</span> 只`]
  if (stat) parts.push(`涨跌幅 <span class="num ${cls(stat.pct)}">${pctText(stat.pct)}</span>`)
  if (stat && !isThin(stat)) parts.push(`${term('跑赢大盘')} <span class="num">${outperformCount(stat)} / ${n}</span>`)
  const sorts = `<div class="sec-sort" role="group" aria-label="排序">${MEMBER_SORTS.map(([k, label]) =>
    `<button class="chip" data-sort="${k}" aria-pressed="${sp.sort === k}">${label}</button>`).join('')}</div>`
  morphHtml(head, `<h2>${esc(nameOf(id))}</h2><span class="sub">${parts.join(' · ')}</span><div class="sec-tools">${sorts}</div>`)
  // 成员行按品种复用（同板块的 10 秒重算只改字；星标按钮等节点留着）
  patchKeyedRows(body, rows.map(r => [keyOfRow(r), symbolRowHTML(r)] as const), 'data-msym')
  morphHtml(empty, rows.length ? '' : '<div class="empty">这个板块暂时没有行情</div>')
  sp.baseOf = new Map()
  for (const r of rows) { const k = feed.quotes.get(r.base)?.symbol; if (k && S.symbols.has(k)) sp.baseOf.set(k, r.base) }
  setVisible([...sp.baseOf.keys()])
  // 持仓变化逐只取（按表上顺序从上往下，回来一只补一格；按持仓变化排序时取齐了顺序才稳）
  if (fetchOi) loadOiChanges(rows.map(keyOfRow), oiArrived)
}

/** 持仓变化回来了：攒 250 ms 补一次成分表（只改字、按需挪行），不重新发请求 */
let oiTimer: ReturnType<typeof setTimeout> | undefined
function oiArrived(): void {
  if (oiTimer) return
  oiTimer = setTimeout(() => { oiTimer = undefined; if (st.page === 'sectors') renderMembers(windowName(), false) }, 250)
}
const windowName = (): string => sp.window === 'd5' ? '5 日' : '今日'

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
  renderHead(hasD5, title)
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
  renderMembers(windowName())
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
  sp.sort = readSort()
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
    const so = t.closest<HTMLElement>('[data-sort]')
    if (so) {
      const k = parseSort(so.dataset.sort)
      if (k !== sp.sort) { sp.sort = k; writeSort(k); renderMembers(windowName(), false); $('#secMembers .sec-scroll').scrollTop = 0 }
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
  hooks.pageHidden.sectors = () => { sp.once = null; stopFeed(); stopHistory(); stopOiChanges(); sp.visible = []; refreshStreams() }
  hooks.extraStreams.push(() => st.page === 'sectors' ? sp.visible.map(k => streamName.ticker(k)) : [])
  hooks.onTicks.push(patchTicks)
  hooks.booted.push(() => { if (st.page === 'sectors') render() })
}

