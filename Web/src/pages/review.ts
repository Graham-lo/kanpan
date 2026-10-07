/* Hkline Web · 复盘页
 *
 * 数据全部来自 kanpan-api 的 /v1/native-review（登录后才有）：
 *   交易回合  手机上连的交易所只读密钥拉来的成交，服务端拼成回合、算好持仓中最大浮盈浮亏与平仓后走势；
 *   观点记录  手机或网页图表上「记一笔」写下的判断，服务端按规则判对错，战绩按相对口径分好组；
 *   相似走势  「找相似」的结果与收藏的片段。
 * 页面布局照原型：上面一整条（页签 + 要点：交易回合十一格，另两个页签六格），左边列表与战绩，右边回放。
 * 回放是「还原当时的场景」：未来的 K 线与成交一律不画，放到哪儿才露到哪儿；
 * 播放条只有拖进度线与关键点跳转，没有逐根步进。时间一律上海时间。
 */
import '../styles/review.css'
import { morphHtml } from '../ui/patch'
import { hooks, go, goLogin } from '../app/shell'
import { $, I, esc } from '../ui/dom'
import { GLOSSARY, term, toast } from '../ui/overlay'
import { badge, shTime, sym } from '../ui/common'
import { IV_LABEL, baseOf } from '../market/symbols'
import { durText, fmt } from '../util/format'
import { openSymbol } from './chart'
import { ReviewError, errorText, forgetSearch, rememberSearch, reviewApi, reviewToken, storedSearches, type StoredSearch } from '../review/api'
import {
  GROUPINGS, OUTCOME_LABEL, ORIGIN_LABEL, CONFIRM_LABEL, TRADE_DIR_LABEL, VIEW_DIR_LABEL,
  closedRounds, distPct, equityCurve, groupByDay, groupRateText, groupRounds, judgedAt, lastWeekRounds,
  money, num, outcomeOf, ratioPct, resolvedGroups, roundDecimals, roundStats, scoreText, sideStats, sortTrades, sortViews,
  symbolsOf, titleParts, viewSummary,
} from '../review/model'
import { planMatch, planNote, planTrade, type Plan } from '../review/replay'
import { ReplayPlayer } from '../review/player'
import { createLoadGate } from '../review/loadGate'
import { onSession } from '../account/session'
import type { Match, SavedMatch, SearchResults, SearchStatus, Statistics, TradeRecord, ViewRecord } from '../review/types'
import { ago } from '../util/clock'

GLOSSARY['净盈亏'] = '已平仓回合的已实现盈亏，减去手续费，加上收到的资金费（付出的资金费是负数）。'
GLOSSARY['盈亏比'] = '赚钱回合的平均盈利 ÷ 亏钱回合的平均亏损。'
GLOSSARY['每笔期望'] = '净盈亏合计 ÷ 回合数：平均每做一笔赚或亏多少。'
GLOSSARY['盈利因子'] = '赚钱回合的盈利合计 ÷ 亏钱回合的亏损合计。大于 1 说明总体在赚；没有亏过时不算。'
GLOSSARY['最大回撤'] = '按平仓先后把净盈亏一笔笔累加，从最高点回落到之后最低点的那一段。百分比是回落额占当时最高累计盈利的比例；从一开始就在亏、没有盈利可回吐时不写百分比。'
GLOSSARY['最大单笔'] = '赚得最多的那一笔占净盈亏的比例。过半说明这段时间的盈利主要靠这一笔。'
GLOSSARY['最大浮盈'] = '持仓期间价格朝有利方向走得最远时，按开仓均价算的浮动盈利。'
GLOSSARY['最大浮亏'] = '持仓期间价格朝不利方向走得最远时，按开仓均价算的浮动亏损。'
GLOSSARY['战绩'] = '同一类判断（同品种、同方向、同确认方式，目标与失效幅度相近、时长相近）攒在一起算判对的比例；样本不够时只写「样本不足」，不拿一两笔的 0% 或 100% 冒充战绩。'

type Tab = 'trade' | 'view' | 'similar'
const TAB_LABEL: Record<Tab, string> = { trade: '交易回合', view: '观点记录', similar: '相似走势' }
const SOURCE_LABEL: Record<string, string> = { history: '全市场历史', private: '我的记录' }
const PREF_KEY = 'hkline-web-review-v1'

interface SearchEntry { meta: StoredSearch; status: SearchStatus | null; results: SearchResults | null; error: string | null }

const R = {
  tab: 'trade' as Tab,
  symbol: 'all',
  trades: [] as TradeRecord[],
  views: [] as ViewRecord[],
  stats: null as Statistics | null,
  saved: [] as SavedMatch[],
  searches: new Map<string, SearchEntry>(),
  loadedAt: 0,
  loading: false,
  /** 整页级的错误（401 走登录态，其它显示在页里） */
  error: null as unknown,
  sel: { trade: null as string | null, view: null as string | null, similar: null as string | null },
  /** 右边正在放的那条（选中项变了才重新拉 K 线） */
  playing: '',
  shown: false,
  built: false,
}
let player: ReplayPlayer | null = null
let pollTimer: ReturnType<typeof setTimeout> | undefined

function loadPref(): void {
  try {
    const v = JSON.parse(localStorage.getItem(PREF_KEY) || '{}')
    if (v.tab === 'trade' || v.tab === 'view' || v.tab === 'similar') R.tab = v.tab
  } catch { /* 读不到就用默认 */ }
}
function savePref(): void { try { localStorage.setItem(PREF_KEY, JSON.stringify({ tab: R.tab })) } catch { /* 存不下无所谓 */ } }

// ------------------------------------------------------------ 小件
const page = (): HTMLElement => $('#page-review')
const upDown = (v: number): string => v > 0 ? 'up' : v < 0 ? 'down' : ''
const pct = (v: number | null, signed = true): string => v == null || !isFinite(v) ? '—' : `${signed && v > 0 ? '+' : ''}${(v * 100).toFixed(1)}%`
function badgeFor(symbol: string): string {
  const s = sym(symbol)
  if (s) return badge(s)
  const b = baseOf(symbol)
  return badge({ base: b })
}
const codeOf = (symbol: string): string => sym(symbol)?.code ?? baseOf(symbol)
const decOf = (symbol: string, fallback = 2): number => sym(symbol)?.dec ?? fallback
const ivText = (iv: string): string => IV_LABEL[iv] ?? esc(iv)
const kpi = (k: string, v: string, d = '', vc = '', id = ''): string => `<div class="kpi"${id ? ` data-kpi="${id}"` : ''}><div class="k">${k}</div><div class="v num ${vc}">${v}</div><div class="d">${d || '&nbsp;'}</div></div>`
const outcomeTag = (o: string): string => {
  const c = o === 'realized' ? 'rv-ok' : o === 'unrealized' ? 'rv-bad' : o === 'waiting' ? 'accent' : ''
  return `<span class="tag ${c}">${OUTCOME_LABEL[o] ?? esc(o)}</span>`
}
const dirTag = (d: string, label: string): string => `<span class="dir ${d === 'long' ? 'long' : d === 'short' ? 'short' : 'obs'}">${label}</span>`
const stat = (k: string, v: string, vc = '', sub = ''): string => `<div class="rv-stat"><div class="k">${k}</div><div class="v num ${vc}">${v}</div>${sub ? `<div class="d num">${sub}</div>` : ''}</div>`

function filteredTrades(): TradeRecord[] {
  const all = sortTrades(R.trades)
  return R.symbol === 'all' ? all : all.filter(t => t.round.symbol === R.symbol)
}
function visibleViews(): ViewRecord[] { return sortViews(R.views.filter(v => !v.voided)) }

// ------------------------------------------------------------ 取数
const gate = createLoadGate()
async function load(): Promise<void> {
  if (!reviewToken()) { renderLogin(false); return }
  const ep = gate.begin()
  if (ep == null) return
  R.loading = true
  renderTop()
  const [t, v, s, m] = await Promise.allSettled([reviewApi.trades(), reviewApi.views(), reviewApi.statistics(), reviewApi.saved()])
  const end = gate.end(ep)
  if (end === 'stale') return
  R.loading = false
  if (end === 'again') return load()
  const rej = [t, v, s, m].find(x => x.status === 'rejected') as PromiseRejectedResult | undefined
  if (rej && rej.reason instanceof ReviewError && rej.reason.status === 401) { renderLogin(true); return }
  R.error = rej ? rej.reason : null
  if (t.status === 'fulfilled') R.trades = t.value
  if (v.status === 'fulfilled') R.views = v.value
  if (s.status === 'fulfilled') R.stats = s.value
  if (m.status === 'fulfilled') R.saved = m.value
  R.loadedAt = Date.now()
  if (R.symbol !== 'all' && !R.trades.some(x => x.round.symbol === R.symbol)) R.symbol = 'all'
  applyWanted()
  // 回合 / 观点先画出来（从侧栏成交跳进来要马上看到选中的那一回合），本机记着的相似搜索要逐个问，问完再补画
  if (R.shown) render()
  await refreshSearches()
  if (!R.shown || !gate.live(ep)) return
  render()
}

/** 本机记着的搜索：没结束的问一下进度，结束了的拉结果 */
async function refreshSearches(): Promise<void> {
  const ep = gate.epoch
  const list = storedSearches()
  for (const id of [...R.searches.keys()]) if (!list.some(x => x.id === id)) R.searches.delete(id)
  await Promise.all(list.map(async meta => {
    const e: SearchEntry = R.searches.get(meta.id) ?? { meta, status: null, results: null, error: null }
    e.meta = meta
    R.searches.set(meta.id, e)
    if (e.results && e.status?.status === 'completed') return
    try {
      const st = await reviewApi.search(meta.id)
      if (!gate.live(ep)) return
      e.status = st
      e.error = null
      if (st.status === 'completed') { const res = await reviewApi.results(meta.id); if (gate.live(ep)) e.results = res }
      else if (st.status === 'failed') e.error = st.error ? `没找成（${st.error}）` : '没找成'
    } catch (err) {
      // 换过账号：这是上个账号的搜索，别按「404」把它从本机删掉
      if (!gate.live(ep)) return
      if (err instanceof ReviewError && err.status === 404) { forgetSearch(meta.id); R.searches.delete(meta.id); return }
      e.error = errorText(err)
    }
  }))
}

function pending(): boolean { return [...R.searches.values()].some(e => e.status && (e.status.status === 'queued' || e.status.status === 'running')) }

/** 有没找完的搜索时，每 2 秒问一次；只在这一页、这个页签开着时问 */
function schedulePoll(): void {
  clearTimeout(pollTimer)
  if (!R.shown || R.tab !== 'similar' || !pending()) return
  pollTimer = setTimeout(async () => {
    await refreshSearches()
    if (!R.shown) return
    renderTop(); renderLeft()
    // 右侧还空着（没选中片段）时跟着换说法：搜索找完了、一段也没有，那里也要说，不能停在「选一段…」
    if (R.tab === 'similar' && !findMatch(R.sel.similar)) renderDetail()
    schedulePoll()
  }, 2000)
}

// ------------------------------------------------------------ 未登录 / 过期
function renderLogin(expired: boolean): void {
  teardown()
  const el = page()
  el.classList.add('rv-signed-out')
  el.innerHTML = `<div class="card rv-login">
    <div class="empty">${I('trades', 'icon-24')}
      <div class="rv-login-t">${expired ? '登录已过期' : '复盘需要登录'}</div>
      <div class="rv-login-d">交易回合、观点记录和战绩都存在你的账号里，登录后在这里看、在图上重放。</div>
      <button class="btn primary" id="rvLogin">${expired ? '重新登录' : '去登录'}</button>
    </div></div>`
  $('#rvLogin').onclick = () => goLogin()
}

function teardown(): void {
  clearTimeout(pollTimer)
  player?.destroy(); player = null
  R.built = false; R.playing = ''
}

// ------------------------------------------------------------ 骨架
function build(): void {
  const el = page()
  el.classList.remove('rv-signed-out')
  el.innerHTML = `
    <div class="card rv-top" id="rvTop"></div>
    <div class="card rv-left" id="rvLeft"></div>
    <div class="card rv-right">
      <div class="rv-trade-head" id="rvDetHead"></div>
      <div class="rv-chart-wrap" id="rvWrap"></div>
      <div class="replay-bar rv-bar" id="rvBar"></div>
      <div class="rv-foot scroll" id="rvFoot"></div>
    </div>`
  player = new ReplayPlayer($('#rvWrap'), $('#rvBar'))
  R.built = true
  R.playing = ''
  bindPage()
}

function render(): void {
  if (!reviewToken()) { renderLogin(false); return }
  if (!R.built) build()
  renderTop(); renderLeft(); ensureSelection(); renderDetail()
  schedulePoll()
}

// ------------------------------------------------------------ 上方一整条
function renderTop(): void {
  const top = document.getElementById('rvTop'); if (!top) return
  const syms = symbolsOf(R.trades.filter(t => !t.voided))
  const counts: Record<Tab, number> = { trade: sortTrades(R.trades).length, view: visibleViews().length, similar: R.saved.length }
  const filter = R.tab === 'trade' && syms.length > 1
    ? `<div class="seg rv-syms" role="group" aria-label="品种">${['all', ...syms].map(s => `<button data-sym="${esc(s)}" aria-pressed="${R.symbol === s}">${s === 'all' ? '全部' : esc(codeOf(s))}</button>`).join('')}</div>` : ''
  const asOf = R.loading ? '正在更新…' : R.loadedAt ? `更新于 ${shTime(R.loadedAt, false)}` : ''
  // 搜索没找完时每 2 秒重画一次：就地改，页签 / 刷新按钮等节点留着（整块换了，指针下的按钮要等下一次 mousemove 才算悬停、点不中）
  morphHtml(top, `
    <div class="rv-head">
      <h2>复盘</h2>
      <div class="seg" role="tablist" aria-label="复盘内容">${(Object.keys(TAB_LABEL) as Tab[]).map(t => `<button role="tab" data-tab="${t}" aria-pressed="${R.tab === t}" aria-selected="${R.tab === t}">${TAB_LABEL[t]}<span class="rv-count num">${counts[t]}</span></button>`).join('')}</div>
      ${filter}
      <span class="rv-sp"></span>
      ${R.error ? `<span class="rv-err">${esc(errorText(R.error))}</span>` : ''}
      <span class="rv-asof">${asOf}</span>
      <button class="ibtn sm" id="rvRefresh" aria-label="刷新" data-tip="刷新" ${R.loading ? 'disabled' : ''}>${I('undo', 'icon-16')}</button>
    </div>
    <div class="kpis${R.tab === 'trade' ? ' kpis-trade' : ''}">${R.tab === 'trade' ? tradeKpis() : R.tab === 'view' ? viewKpis() : similarKpis()}</div>`)
}

function tradeKpis(): string {
  const list = filteredTrades().map(t => t.round)
  const s = roundStats(list)
  const lw = roundStats(lastWeekRounds(list, Date.now()))
  const open = list.filter(r => r.status === 'open').length
  return [
    kpi(term('净盈亏'), s.count ? money(s.net) : '—', s.count ? `已实现 ${money(s.realized)} · 费用 ${money(-s.fees)}` : '', upDown(s.net)),
    kpi('胜率', pct(s.winRate, false), s.count ? `赚 ${s.wins} 笔 · 亏 ${s.losses} 笔` : ''),
    kpi(term('盈亏比'), s.rewardRisk == null ? '—' : s.rewardRisk.toFixed(2), s.avgWin != null || s.avgLoss != null ? `平均赚 ${s.avgWin == null ? '—' : money(s.avgWin)} · 平均亏 ${s.avgLoss == null ? '—' : money(s.avgLoss)}` : ''),
    kpi(term('每笔期望'), s.expectancy == null ? '—' : money(s.expectancy), s.count ? `最长连亏 ${s.maxLosingStreak} 笔` : '', upDown(s.expectancy ?? 0)),
    kpi('上周', lw.count ? money(lw.net) : '—', lw.count ? `${lw.count} 个回合 · 胜率 ${pct(lw.winRate, false)}` : '上周没有平仓', upDown(lw.net)),
    kpi('回合', String(s.count), `${open ? `持仓中 ${open} 个 · ` : ''}平均持仓 ${s.avgHoldingMs == null ? '—' : durText(s.avgHoldingMs)}`),
    ...moreTradeKpis(list),
  ].join('')
}

/** 盈利因子、最大回撤、最大单笔、做多、做空（数都在 model 的 roundStats / sideStats 里算好） */
function moreTradeKpis(list: TradeRecord['round'][]): string[] {
  const s = roundStats(list)
  const side = sideStats(list)
  const dd = s.maxDrawdown
  const lw = s.largestWin
  const day = (t: number): string => shTime(t).split(' ')[0]
  const sideKpi = (k: 'long' | 'short'): string => {
    const x = side[k]
    return kpi(TRADE_DIR_LABEL[k], x.count ? money(x.net) : '—', x.count ? `${x.count} 个回合 · 胜率 ${pct(x.winRate, false)}` : '没有平仓的回合', upDown(x.net), k)
  }
  return [
    kpi(term('盈利因子'), s.profitFactor == null ? '—' : s.profitFactor.toFixed(2),
      s.count ? `总盈利 ${money(s.grossProfit)} · 总亏损 ${money(s.grossLoss)}` : '', '', 'pf'),
    kpi(term('最大回撤'), !s.count ? '—' : money(-dd.amount),
      !s.count ? '' : !dd.amount ? '没有回撤' : `占峰值 ${pct(dd.pct, false)}${dd.peakAt != null ? ` · ${day(dd.peakAt)}起` : ''}`, dd.amount ? 'down' : '', 'dd'),
    kpi(term('最大单笔'), lw?.share == null ? '—' : pct(lw.share, false),
      !lw ? '' : s.dominant ? '<span class="rv-warn">这段时间的盈利主要来自 1 笔</span>' : `${esc(codeOf(lw.symbol))} 赚 ${money(lw.net)}`, '', 'top'),
    sideKpi('long'),
    sideKpi('short'),
  ]
}

function viewKpis(): string {
  const s = viewSummary(R.views)
  return [
    kpi('记录', String(s.total), '「记一笔」写下的判断'),
    kpi('判对', String(s.realized), '先碰到目标', s.realized ? 'up' : ''),
    kpi('判错', String(s.unrealized), '先碰到失效或到期', s.unrealized ? 'down' : ''),
    kpi('等答案', String(s.waiting), '还没碰到目标或失效'),
    kpi('只记录', String(s.observation), '不判对错'),
    kpi('待核实', String(s.other), '数据不全，服务端还在核'),
  ].join('')
}

function similarKpis(): string {
  const list = storedSearches()
  const last = list[0]
  const e = last ? R.searches.get(last.id) : undefined
  const st = e?.status?.status
  const lastText = !last ? '—' : st === 'completed' ? `${e?.results?.items.length ?? 0} 段` : st === 'failed' ? '没找成' : st ? '正在找' : '—'
  return [
    kpi('收藏的片段', String(R.saved.length), '在找相似结果里点星收藏'),
    kpi('找过', String(list.length), '在观点记录里点「找相似」'),
    kpi('最近一次', lastText, last ? `${esc(last.label)} · ${shTime(last.created)}` : ''),
    kpi('', '', ''), kpi('', '', ''), kpi('', '', ''),
  ].join('')
}

// ------------------------------------------------------------ 左边
function renderLeft(): void {
  const left = document.getElementById('rvLeft'); if (!left) return
  const keep = left.querySelector<HTMLElement>('.rv-list')?.scrollTop ?? 0
  morphHtml(left, R.tab === 'trade' ? tradeLeft() : R.tab === 'view' ? viewLeft() : similarLeft())
  const list = left.querySelector<HTMLElement>('.rv-list'); if (list) list.scrollTop = keep
  // 从别的页跳进来的那一条：滚到看得见
  if (scrollSel) { scrollSel = false; left.querySelector<HTMLElement>('tr.sel')?.scrollIntoView({ block: 'nearest' }) }
}

function emptyBlock(title: string, sub: string, icon = 'trades'): string {
  return `<div class="empty rv-empty">${I(icon, 'icon-24')}<div class="t">${title}</div><div>${sub}</div></div>`
}

function tradeLeft(): string {
  const list = filteredTrades()
  if (!list.length) {
    return emptyBlock(R.loading ? '正在加载…' : '还没有交易回合', R.loading ? '' : '在手机「我的 → 交易所」连上只读密钥后，平掉的仓位会自动拼成回合出现在这里。')
  }
  const now = Date.now()
  const groups = groupByDay(list, t => t.round.closedAt ?? t.round.openedAt, now)
  const rows = groups.map(g => {
    const net = g.items.filter(t => t.round.status === 'closed').reduce((a, t) => a + num(t.round.netPnl), 0)
    const head = `<tr class="rv-day"><td colspan="10"><span>${g.label}</span><span class="n">${g.items.length} 个回合</span><span class="num ${upDown(net)}">${net ? money(net) : ''}</span></td></tr>`
    return head + g.items.map(tradeRow).join('')
  }).join('')
  return `<div class="rv-lbody">
    <div class="rv-main">
      ${equityHtml(list.map(t => t.round))}
      <div class="scroll rv-list">
        <table class="tbl rv-tbl"><thead><tr>
          <th>品种</th><th>方向</th><th>开仓</th><th>持仓</th><th>开仓均价</th><th>平仓均价</th><th>${term('最大浮盈')}</th><th>${term('最大浮亏')}</th><th>${term('净盈亏')}</th><th></th>
        </tr></thead><tbody>${rows}</tbody></table>
      </div>
    </div>
    <div class="rv-side scroll">${tradeGroupsHtml(list)}</div>
  </div>`
}

function tradeRow(t: TradeRecord): string {
  const r = t.round, dec = roundDecimals(r), open = r.status === 'open'
  const ex = t.result?.excursion
  const net = num(r.netPnl)
  const hold = open ? Date.now() - r.openedAt : (r.holdingMs ?? 0)
  return `<tr data-trade="${esc(t.id)}" class="${R.sel.trade === t.id ? 'sel' : ''}" tabindex="0">
    <td><span class="sym">${badgeFor(r.symbol)}<b>${esc(codeOf(r.symbol))}</b>${r.leverage ? `<span class="cn">${Number(r.leverage)} 倍</span>` : ''}</span></td>
    <td>${dirTag(r.direction, TRADE_DIR_LABEL[r.direction])}</td>
    <td class="num">${shTime(r.openedAt)}</td>
    <td>${open ? '<span class="tag accent">持仓中</span> ' : ''}${durText(Math.max(0, hold))}</td>
    <td class="num">${fmt(num(r.openAvgPrice), dec)}</td>
    <td class="num">${r.closeAvgPrice ? fmt(num(r.closeAvgPrice), dec) : '—'}</td>
    <td class="num up">${ex ? ratioPct(ex.maxFavorablePct) : '—'}</td>
    <td class="num down">${ex ? ratioPct(ex.maxAdversePct) : '—'}</td>
    <td class="num rv-net ${open ? '' : upDown(net)}">${open ? '—' : money(net)}</td>
    <td class="rv-mark">${t.note?.text ? `<span data-tip="有笔记">${I('note', 'icon-16')}</span>` : ''}</td>
  </tr>`
}

/** 累计净盈亏：按平仓先后每个回合一步，线用 SVG 拉伸，文字与点用 HTML 定位（不跟着变形） */
function equityHtml(list: TradeRecord['round'][]): string {
  const pts = equityCurve(list)
  if (pts.length < 2) return `<div class="equity rv-equity"><div class="rv-eq-cap"><span>累计净盈亏</span></div><div class="rv-eq-empty">平掉第一个回合之后画曲线</div></div>`
  const vs = pts.map(p => p.v)
  let lo = Math.min(0, ...vs), hi = Math.max(0, ...vs)
  if (hi === lo) { hi += 1; lo -= 1 }
  const pad = (hi - lo) * 0.12; hi += pad; lo -= pad
  const n = pts.length - 1
  const X = (i: number) => i / n * 1000
  const Y = (v: number) => (hi - v) / (hi - lo) * 1000
  const line = pts.map((p, i) => `${i ? 'L' : 'M'}${X(i).toFixed(1)} ${Y(p.v).toFixed(1)}`).join(' ')
  const area = `${line} L1000 ${Y(0).toFixed(1)} L0 ${Y(0).toFixed(1)} Z`
  const last = pts[pts.length - 1].v
  const col = last >= 0 ? 'var(--up)' : 'var(--down)'
  const selId = R.sel.trade ? R.trades.find(t => t.id === R.sel.trade)?.round.id : null
  const dots = pts.map((p, i) => i === 0 ? '' : `<i class="rv-eq-dot${p.id === selId ? ' sel' : ''}" data-round="${esc(p.id)}" style="left:${(X(i) / 10).toFixed(2)}%;top:${(Y(p.v) / 10).toFixed(2)}%;--c:${p.v - pts[i - 1].v >= 0 ? 'var(--up)' : 'var(--down)'}"></i>`).join('')
  return `<div class="equity rv-equity">
    <div class="rv-eq-cap"><span>累计净盈亏</span><b class="num ${upDown(last)}">${money(last)}</b></div>
    <div class="rv-eq-plot">
      <svg viewBox="0 0 1000 1000" preserveAspectRatio="none" aria-hidden="true">
        <defs><linearGradient id="rvEqFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".18"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></linearGradient></defs>
        <line x1="0" x2="1000" y1="${Y(0).toFixed(1)}" y2="${Y(0).toFixed(1)}" class="zero" vector-effect="non-scaling-stroke"/>
        <path d="${area}" fill="url(#rvEqFill)"/>
        <path d="${line}" fill="none" stroke="${col}" stroke-width="2" stroke-linejoin="round" vector-effect="non-scaling-stroke"/>
      </svg>
      ${dots}
      <span class="rv-eq-y num" style="top:0">${money(hi - pad)}</span>
      <span class="rv-eq-y num" style="top:${(Y(0) / 10).toFixed(2)}%">0</span>
      ${lo + pad < 0 ? `<span class="rv-eq-y num" style="top:100%">${money(lo + pad)}</span>` : ''}
    </div>
    <div class="rv-eq-x num"><span>${shTime(pts[1].t)}</span><span>${shTime(pts[pts.length - 1].t)}</span></div>
  </div>`
}

/** 交易战绩：五种分法全摆出来（不给用户挑口径） */
function tradeGroupsHtml(list: TradeRecord[]): string {
  const rounds = list.map(t => t.round)
  if (!closedRounds(rounds).length) return `<div class="sec-title">${term('战绩')}</div>${emptyBlock('还没有平仓的回合', '', 'layers')}`
  return `<div class="sec-title"><span>战绩</span><span class="faint">只算已平仓</span></div>` + GROUPINGS.filter(g => !(g.id === 'symbol' && R.symbol !== 'all')).map(g => {
    const rows = groupRounds(rounds, g.id)
    return `<div class="rv-grp"><div class="rv-grp-t">${g.title}</div>
      <table class="tbl rv-gtbl"><thead><tr><th></th><th>回合</th><th>胜率</th><th>净盈亏</th></tr></thead><tbody>
      ${rows.map(r => `<tr><td>${esc(g.id === 'symbol' ? codeOf(r.key) : r.label)}</td><td class="num">${r.stats.count}</td><td class="num">${pct(r.stats.winRate, false)}</td><td class="num ${upDown(r.stats.net)}">${money(r.stats.net)}</td></tr>`).join('')}
      </tbody></table></div>`
  }).join('')
}

function viewLeft(): string {
  const list = visibleViews()
  if (!list.length) return emptyBlock(R.loading ? '正在加载…' : '还没有观点记录', R.loading ? '' : '在图表上右键「在这根 K 线记一笔」（手机上是行情页的「记一笔」）写下判断，服务端会按你定的目标与失效判对错。', 'note')
  const groups = groupByDay(list, judgedAt, Date.now())
  const rows = groups.map(g => `<tr class="rv-day"><td colspan="8"><span>${g.label}</span><span class="n">${g.items.length} 条</span></td></tr>` + g.items.map(viewRow).join('')).join('')
  return `<div class="rv-lbody">
    <div class="rv-main"><div class="scroll rv-list">
      <table class="tbl rv-tbl"><thead><tr><th>品种</th><th>看法</th><th>判断时间</th><th>参考价</th><th>目标</th><th>失效</th><th>想法</th><th>结果</th></tr></thead><tbody>${rows}</tbody></table>
    </div></div>
    <div class="rv-side scroll">${viewGroupsHtml()}</div>
  </div>`
}

function viewRow(v: ViewRecord): string {
  const d = v.draft, r = d.rule, dec = decOf(d.range.symbol)
  const obs = r.direction === 'observe'
  const dp = (p: number) => { const x = distPct(r.reference, p); return x == null ? '' : `<span class="faint"> ${x > 0 ? '+' : ''}${x.toFixed(2)}%</span>` }
  return `<tr data-view="${esc(d.id)}" class="${R.sel.view === d.id ? 'sel' : ''}" tabindex="0">
    <td><span class="sym">${badgeFor(d.range.symbol)}<b>${esc(codeOf(d.range.symbol))}</b><span class="cn">${ivText(d.range.interval)}</span></span></td>
    <td>${dirTag(r.direction, VIEW_DIR_LABEL[r.direction] ?? esc(r.direction))}</td>
    <td class="num">${shTime(judgedAt(v))}</td>
    <td class="num">${fmt(r.reference, dec)}</td>
    <td class="num">${obs ? '—' : fmt(r.target, dec) + dp(r.target)}</td>
    <td class="num">${obs ? '—' : fmt(r.invalidation, dec) + dp(r.invalidation)}</td>
    <td class="rv-text">${esc(d.text || '—')}</td>
    <td>${outcomeTag(outcomeOf(v))}</td>
  </tr>`
}

/** 观点战绩：服务端的相对口径分组，只摆这一份 */
function viewGroupsHtml(): string {
  const gs = resolvedGroups(R.stats)
  const head = `<div class="sec-title"><span>${term('战绩')}</span>${R.stats ? `<span class="faint">截至 ${shTime(R.stats.asOf)}</span>` : ''}</div>`
  if (!gs.length) return head + emptyBlock('暂无已判定样本', '', 'layers')
  return head + `<div class="rv-vgroups">${gs.map(g => `<div class="rv-vg">
      <div class="main"><div class="chips">${titleParts(g.title).map((p, i) => `<span class="chip">${esc(i === 0 && /^[A-Z0-9]+USDT?$/.test(p) ? codeOf(p) : p)}</span>`).join('')}</div>
      <div class="sub">${Number(g.total)} 条有效记录${g.total ? ` · 判对 ${Number(g.correct)}` : ''}${g.recheck ? ' · <span class="warn">最近十笔明显变差</span>' : ''}</div></div>
      <div class="rate num ${g.verdictStatus === 'insufficient' ? 'faint' : ''}">${groupRateText(g)}</div>
    </div>`).join('')}</div>`
}

/** 服务端留下一段的相似度门槛，按周期不同（照 Backend/kanpan-api/src/search.rs 的 min_score） */
export function minScoreOf(iv: string | undefined): number {
  return iv === '1h' ? 0.58 : iv === '4h' || iv === '1d' ? 0.56 : 0.60
}

/**
 * 找相似「找完了、一段也没有」时说清楚：服务端从公开 K 线里挑一批候选逐段细比，没有一段过门槛才会空
 * （1h / 4h 候选少，常见；线上压测 9 次里 2 次是这样）。不是出错，给一句能照着做的下一步。
 */
export function noMatchText(e: { status: Pick<SearchStatus, 'checked'> | null; meta?: Pick<StoredSearch, 'iv'> }): string {
  const n = e.status?.checked ?? 0, iv = e.meta?.iv
  const next = iv === '15m' ? '拉长或缩短区间再找' : '换个周期（15 分钟候选最多）或长度再找'
  return n ? `没有足够相似的走势：比过 ${n} 段，没有一段相似度到 ${minScoreOf(iv).toFixed(2)}，${next}` : `没有足够相似的走势，${next}`
}

/** 相似走势页签右侧什么都没选时那句话：最近一次找完是空的就直接说为什么空（有收藏时引到左边收藏的片段） */
export function similarBlankText(saved: number, latest: Pick<SearchEntry, 'status' | 'results' | 'meta'> | undefined): string {
  if (latest?.status?.status === 'completed' && latest.results && !latest.results.items.length)
    return saved ? '这次没找到足够相似的走势，可以选左边收藏的片段，看它后来怎么走' : noMatchText(latest)
  return '选一段相似片段，看它后来怎么走'
}

function similarLeft(): string {
  const searches = storedSearches().map(m => R.searches.get(m.id)).filter((x): x is SearchEntry => !!x)
  const savedIds = new Set(R.saved.map(s => s.item.id))
  const savedHtml = R.saved.length
    ? R.saved.map(s => matchRow(s.item, `saved:${s.item.id}`, true)).join('')
    : `<div class="rv-none">还没有收藏的片段</div>`
  const searchHtml = searches.length ? searches.map(e => {
    const st = e.status?.status
    const prog = e.status && e.status.total ? Math.round(e.status.processed / e.status.total * 100) : 0
    const state = e.error ? `<span class="warn">${esc(e.error)}</span>`
      : st === 'completed' ? `${e.results?.items.length ?? 0} 段${e.results?.partial ? ' · 部分结果' : ''}`
      : st ? `正在找 ${prog}%` : '—'
    const items = st === 'completed' ? (e.results?.items.length ? e.results.items.map(m => matchRow(m, `search:${e.meta.id}:${m.id}`, savedIds.has(m.id), e.meta.id)).join('') : `<div class="rv-none" data-none-checked="${Number(e.status?.checked ?? 0)}">${esc(noMatchText(e))}</div>`) : ''
    return `<div class="rv-search">
      <div class="rv-search-h"><b>${esc(e.meta.label)}</b><span class="faint">${shTime(e.meta.created)}</span><span class="rv-sp"></span><span class="num">${state}</span>
        <button class="ibtn xs" data-forget="${esc(e.meta.id)}" aria-label="不再显示这次搜索" data-tip="不再显示">${I('close', 'icon-16')}</button></div>
      ${items}</div>`
  }).join('') : `<div class="rv-none">在「观点记录」里选一条，点右上「找相似」</div>`
  return `<div class="rv-lbody one"><div class="rv-main"><div class="scroll rv-list">
    <div class="sec-title"><span>收藏的片段</span><span class="faint">${R.saved.length} 段</span></div>${savedHtml}
    <div class="sec-title"><span>找过的相似</span><span class="faint">记在这台电脑上</span></div>${searchHtml}
  </div></div></div>`
}

function matchRow(m: Match, key: string, saved: boolean, searchId?: string): string {
  const r = m.range
  const star = saved
    ? `<button class="ibtn sm rv-star on" data-unsave="${esc(m.id)}" aria-label="取消收藏" data-tip="取消收藏">${I('star', 'icon-16')}</button>`
    : searchId ? `<button class="ibtn sm rv-star" data-save="${esc(m.id)}" data-search="${esc(searchId)}" aria-label="收藏" data-tip="收藏">${I('starOff', 'icon-16')}</button>` : ''
  return `<div class="list-row rv-mrow${R.sel.similar === key ? ' sel' : ''}" data-match="${esc(key)}" tabindex="0">
    ${badgeFor(r.symbol)}
    <div class="main"><div class="t1"><b>${esc(codeOf(r.symbol))}</b><span class="faint">${ivText(r.interval)} · ${Number(r.bars)} 根</span><span class="tag accent">${scoreText(m.score)}</span></div>
    <div class="t2 num">${shTime(r.start)} – ${shTime(r.end - (r.end - r.start) / Math.max(1, r.bars))} · ${SOURCE_LABEL[m.source] ?? esc(m.source)}</div></div>
    ${star}
  </div>`
}

// ------------------------------------------------------------ 选中与右边
function findMatch(key: string | null): Match | null {
  if (!key) return null
  const [kind, a, b] = key.split(':')
  if (kind === 'saved') return R.saved.find(s => s.item.id === a)?.item ?? null
  return R.searches.get(a)?.results?.items.find(m => m.id === b) ?? null
}

function ensureSelection(): void {
  if (R.tab === 'trade') {
    const list = filteredTrades()
    if (!list.some(t => t.id === R.sel.trade)) R.sel.trade = list[0]?.id ?? null
  } else if (R.tab === 'view') {
    const list = visibleViews()
    if (!list.some(v => v.draft.id === R.sel.view)) R.sel.view = list[0]?.draft.id ?? null
  } else if (!findMatch(R.sel.similar)) {
    R.sel.similar = R.saved[0] ? `saved:${R.saved[0].item.id}` : null
    if (!R.sel.similar) for (const e of R.searches.values()) { const m = e.results?.items[0]; if (m) { R.sel.similar = `search:${e.meta.id}:${m.id}`; break } }
  }
}

function selKey(): string { return R.tab === 'trade' ? `t:${R.sel.trade}` : R.tab === 'view' ? `v:${R.sel.view}` : `m:${R.sel.similar}` }

function renderDetail(): void {
  const head = document.getElementById('rvDetHead'), foot = document.getElementById('rvFoot')
  if (!head || !foot || !player) return
  const key = selKey()
  let plan: Plan | null = null
  let meta = { title: '', dec: 2, badge: '' }
  const now = Date.now()
  if (R.tab === 'trade') {
    const t = R.trades.find(x => x.id === R.sel.trade)
    if (t) {
      head.innerHTML = tradeHead(t); foot.innerHTML = tradeFoot(t)
      plan = planTrade(t.round, t.result, now, t.note?.text ?? null)
      meta = { title: esc(codeOf(t.round.symbol)), dec: Math.max(roundDecimals(t.round), decOf(t.round.symbol, 0)), badge: badgeFor(t.round.symbol) }
    }
  } else if (R.tab === 'view') {
    const v = R.views.find(x => x.draft.id === R.sel.view)
    if (v) {
      head.innerHTML = viewHead(v); foot.innerHTML = viewFoot(v)
      plan = planNote(v, now)
      meta = { title: esc(codeOf(v.draft.range.symbol)), dec: decOf(v.draft.range.symbol), badge: badgeFor(v.draft.range.symbol) }
    }
  } else {
    const m = findMatch(R.sel.similar)
    if (m) {
      plan = planMatch(m, now)
      // 同一段已经在放（列表刷新、再点一次同一行）时不会重新载入，「后来」要按已拉到的 K 线当场补上，
      // 否则这里一重画就把载入后算好的那格冲回「载入后计算」，而且再也不会回来
      head.innerHTML = matchHead(m); foot.innerHTML = matchFoot(m, R.playing === key ? afterMove(plan) : null)
      meta = { title: esc(codeOf(m.range.symbol)), dec: decOf(m.range.symbol), badge: badgeFor(m.range.symbol) }
    }
  }
  const wrap = document.getElementById('rvWrap')!
  wrap.classList.toggle('blank', !plan)
  if (!plan) {
    morphHtml(head, `<span class="ttl">回放</span>`)
    const latest = storedSearches()[0]
    morphHtml(foot, `<div class="rv-none">${R.tab === 'similar' ? esc(similarBlankText(R.saved.length, latest ? R.searches.get(latest.id) : undefined)) : '选左边一条，在这里按当时的节奏重放'}</div>`)
    if (R.playing) { player.destroy(); player = new ReplayPlayer(wrap, $('#rvBar')); R.playing = '' }
    return
  }
  if (R.playing === key) return
  R.playing = key
  const p = plan
  void player.load(p, meta).then(res => {
    if (res === 'empty') toast('这段 K 线没取到', '币安暂时没返回这段行情，稍后刷新再试', 'info')
    if (res === 'ok' && p.kind === 'match') { const f = document.getElementById('rvFoot'); if (f && selKey() === key) f.innerHTML = matchFoot(findMatch(R.sel.similar)!, afterMove(p)) }
  })
}

/** 相似段结束之后，后来走了多少（按拉到的 K 线收盘价算，只是展示） */
function afterMove(p: Extract<Plan, { kind: 'match' }>): { pct: number; bars: number } | null {
  const bars = player?.bars || []
  const a = bars.find(b => b.t === p.initialBar), z = bars.filter(b => b.t <= p.stopBar).pop()
  if (!a || !z || z.t <= a.t) return null
  return { pct: (z.c - a.c) / a.c, bars: Math.round((z.t - a.t) / p.step) }
}

const openBtn = (symbol: string): string => `<button class="btn ghost sm" data-open="${esc(symbol)}">${I('candles', 'icon-16')}在图表中打开</button>`

function tradeHead(t: TradeRecord): string {
  const r = t.round, open = r.status === 'open'
  return `${badgeFor(r.symbol)}<span class="ttl">${esc(codeOf(r.symbol))}</span>${dirTag(r.direction, TRADE_DIR_LABEL[r.direction])}
    ${open ? '<span class="tag accent">持仓中</span>' : `<span class="faint num">${shTime(r.openedAt)} – ${shTime(r.closedAt!)}</span>`}
    ${r.leverage ? `<span class="faint">${Number(r.leverage)} 倍</span>` : ''}<span class="rv-sp"></span>${openBtn(r.symbol)}`
}

function tradeFoot(t: TradeRecord): string {
  const r = t.round, res = t.result, ex = res?.excursion, open = r.status === 'open'
  const net = num(r.netPnl), fund = num(r.funding)
  const after = (a: { changePct: string } | null | undefined) => a ? `<span class="${upDown(num(a.changePct))}">${ratioPct(a.changePct)}</span>` : '<span class="faint">—</span>'
  const stats = [
    stat(term('净盈亏'), open ? '—' : money(net), open ? '' : upDown(net), open ? '还没平完' : `已实现 ${money(num(r.realizedPnl))}`),
    stat('费用', money(-num(r.commission)), '', `资金费 ${fund ? money(fund) : '0'}`),
    stat(term('最大浮盈'), ex ? ratioPct(ex.maxFavorablePct) : '—', ex ? 'up' : '', ex ? `${money(num(ex.maxFavorable))} · ${shTime(ex.maxFavorableAt)}` : ''),
    stat(term('最大浮亏'), ex ? ratioPct(ex.maxAdversePct) : '—', ex ? 'down' : '', ex ? `${money(num(ex.maxAdverse))} · ${shTime(ex.maxAdverseAt)}` : ''),
    stat('持仓', durText(Math.max(0, open ? Date.now() - r.openedAt : r.holdingMs ?? 0)), '', `最多 ${fmt(num(r.maxQty), 4).replace(/\.?0+$/, '')} · 成交 ${r.fills.length} 笔`),
    stat('开仓均价', fmt(num(r.openAvgPrice), roundDecimals(r)), '', r.closeAvgPrice ? `平仓均价 ${fmt(num(r.closeAvgPrice), roundDecimals(r))}` : ''),
    `<div class="rv-stat wide"><div class="k">平仓后走势</div><div class="v num rv-after">${open || !res ? '<span class="faint">平仓后才有</span>' : `<span><i>1 小时</i>${after(res.after.h1)}</span><span><i>4 小时</i>${after(res.after.h4)}</span><span><i>24 小时</i>${after(res.after.h24)}</span>`}</div></div>`,
  ].join('')
  return `<div class="rv-trade-stats rv-stats">${stats}</div>
    <div class="rv-note">
      <label for="rvNote">当时怎么想</label>
      <textarea id="rvNote" rows="2" maxlength="2000" placeholder="写下开这一单时的想法，回放停在开仓处时会显示在图上">${esc(t.note?.text ?? '')}</textarea>
      <div class="rv-note-bar"><span class="faint">${t.note ? `改于 ${shTime(t.note.updatedAt)}` : ''}</span><button class="btn secondary sm" id="rvNoteSave" data-id="${esc(t.id)}" disabled>保存</button></div>
    </div>`
}

function viewHead(v: ViewRecord): string {
  const d = v.draft, r = d.rule
  const canSearch = d.range.bars >= 16
  return `${badgeFor(d.range.symbol)}<span class="ttl">${esc(codeOf(d.range.symbol))}</span><span class="faint">${ivText(d.range.interval)}</span>
    ${dirTag(r.direction, VIEW_DIR_LABEL[r.direction] ?? esc(r.direction))}${outcomeTag(outcomeOf(v))}<span class="rv-sp"></span>
    <button class="btn secondary sm" data-find="${esc(d.id)}" ${canSearch ? '' : 'disabled data-tip="图表区间不到 16 根，找不了相似"'}>${I('search', 'icon-16')}找相似</button>${openBtn(d.range.symbol)}`
}

function viewFoot(v: ViewRecord): string {
  const d = v.draft, r = d.rule, dec = decOf(d.range.symbol), obs = r.direction === 'observe'
  const dp = (p: number) => { const x = distPct(r.reference, p); return x == null ? '' : `${x > 0 ? '+' : ''}${x.toFixed(2)}%` }
  const a = v.assessment
  const stats = [
    stat(obs ? '当时价' : '参考价', fmt(r.reference, dec), '', shTime(judgedAt(v))),
    stat('目标', obs ? '—' : fmt(r.target, dec), '', obs ? '' : dp(r.target)),
    stat('失效', obs ? '—' : fmt(r.invalidation, dec), '', obs ? '' : dp(r.invalidation)),
    stat('到期', obs ? '—' : shTime(r.expires), '', obs ? '' : (CONFIRM_LABEL[r.confirmation] ?? esc(r.confirmation))),
    stat('来路', ORIGIN_LABEL[d.origin] ?? '—', '', d.confidence != null ? `把握 ${Math.round(d.confidence * (d.confidence <= 1 ? 100 : 1))}%` : ''),
    `<div class="rv-stat wide"><div class="k">结果</div><div class="v">${outcomeTag(outcomeOf(v))}<span class="rv-reason">${esc(a?.reason || '')}</span></div>${a?.eventAt ? `<div class="d num">${shTime(a.eventAt)}</div>` : ''}</div>`,
  ].join('')
  const refl = v.reflection && (v.reflection.note || v.reflection.nextTime)
    ? `<div class="rv-quote"><b>事后回看</b>${esc(v.reflection.note)}${v.reflection.nextTime ? `<br><span class="faint">下次：</span>${esc(v.reflection.nextTime)}` : ''}</div>` : ''
  return `<div class="rv-trade-stats rv-stats">${stats}</div>
    ${d.text ? `<div class="rv-quote"><b>当时的判断</b>${esc(d.text)}</div>` : ''}${refl}`
}

function matchHead(m: Match): string {
  const saved = R.saved.some(s => s.item.id === m.id)
  const searchId = R.sel.similar?.startsWith('search:') ? R.sel.similar.split(':')[1] : ''
  const star = saved ? `<button class="btn secondary sm" data-unsave="${esc(m.id)}">${I('star', 'icon-16')}取消收藏</button>`
    : searchId ? `<button class="btn secondary sm" data-save="${esc(m.id)}" data-search="${esc(searchId)}">${I('starOff', 'icon-16')}收藏</button>` : ''
  return `${badgeFor(m.range.symbol)}<span class="ttl">${esc(codeOf(m.range.symbol))}</span><span class="faint">${ivText(m.range.interval)}</span>
    <span class="tag accent">${scoreText(m.score)}</span><span class="faint">${SOURCE_LABEL[m.source] ?? esc(m.source)}</span><span class="rv-sp"></span>${star}${openBtn(m.range.symbol)}`
}

function matchFoot(m: Match, after: { pct: number; bars: number } | null): string {
  const r = m.range
  return `<div class="rv-trade-stats rv-stats">
    ${stat('片段', `${r.bars} 根`, '', `${shTime(r.start)} 起`)}
    ${stat('相似度', m.score.toFixed(2), '', '0 到 1，越大越像')}
    ${stat('后来', after ? `${after.pct > 0 ? '+' : ''}${(after.pct * 100).toFixed(2)}%` : '—', after ? upDown(after.pct) : '', after ? `相似段之后 ${after.bars} 根` : '载入后计算')}
    ${stat('周期', ivText(r.interval), '', SOURCE_LABEL[m.source] ?? esc(m.source))}
  </div>`
}

// ------------------------------------------------------------ 交互
function bindPage(): void {
  const el = page()
  el.onclick = async e => {
    const x = e.target as HTMLElement
    const tab = x.closest<HTMLElement>('[data-tab]')
    if (tab) {
      R.tab = tab.dataset.tab as Tab; savePref(); player?.stop(); render()
      // 别的浏览器页签里新找的相似，本页还没问过：切过来时补问一次
      if (R.tab === 'similar' && storedSearches().some(m => !R.searches.has(m.id))) { await refreshSearches(); render() }
      return
    }
    const s = x.closest<HTMLElement>('[data-sym]')
    if (s) { R.symbol = s.dataset.sym || 'all'; render(); return }
    if (x.closest('#rvRefresh')) { await refreshAll(); return }
    const open = x.closest<HTMLElement>('[data-open]')
    if (open) { const k = open.dataset.open!; go('chart'); openSymbol(k); return }
    const find = x.closest<HTMLElement>('[data-find]')
    if (find) { await startFind(find.dataset.find!, find as HTMLButtonElement); return }
    const save = x.closest<HTMLElement>('[data-save]')
    if (save) { e.stopPropagation(); await doSave(save.dataset.search!, save.dataset.save!, save as HTMLButtonElement); return }
    const unsave = x.closest<HTMLElement>('[data-unsave]')
    if (unsave) { e.stopPropagation(); await doUnsave(unsave.dataset.unsave!, unsave as HTMLButtonElement); return }
    const forget = x.closest<HTMLElement>('[data-forget]')
    if (forget) { forgetSearch(forget.dataset.forget!); R.searches.delete(forget.dataset.forget!); render(); return }
    if (x.closest('#rvNoteSave')) { await saveNote(x.closest<HTMLButtonElement>('#rvNoteSave')!); return }
    const dot = x.closest<HTMLElement>('[data-round]')
    if (dot) { const t = R.trades.find(t => t.round.id === dot.dataset.round); if (t) select('trade', t.id); return }
    const row = x.closest<HTMLElement>('[data-trade],[data-view],[data-match]')
    if (row) {
      if (row.dataset.trade) select('trade', row.dataset.trade)
      else if (row.dataset.view) select('view', row.dataset.view)
      else if (row.dataset.match) select('similar', row.dataset.match)
    }
  }
  el.onkeydown = e => {
    const x = e.target as HTMLElement
    if ((e.key === 'Enter') && x.matches('[data-trade],[data-view],[data-match]')) { e.preventDefault(); x.click() }
    if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && x.matches('[data-trade],[data-view],[data-match]')) {
      e.preventDefault()
      const all = [...el.querySelectorAll<HTMLElement>(`[data-${x.dataset.trade ? 'trade' : x.dataset.view ? 'view' : 'match'}]`)]
      const n = all[all.indexOf(x) + (e.key === 'ArrowDown' ? 1 : -1)]
      if (n) { n.focus(); n.click() }
    }
  }
  el.oninput = e => {
    const ta = e.target as HTMLElement
    if (ta.id === 'rvNote') {
      const t = R.trades.find(x => x.id === R.sel.trade)
      const btn = document.getElementById('rvNoteSave') as HTMLButtonElement | null
      if (btn) btn.disabled = (ta as HTMLTextAreaElement).value.trim() === (t?.note?.text ?? '').trim()
    }
  }
}

function select(kind: Tab, id: string): void {
  if (kind === 'trade') R.sel.trade = id
  else if (kind === 'view') R.sel.view = id
  else R.sel.similar = id
  page().querySelectorAll('.sel[data-trade],.sel[data-view],.sel[data-match]').forEach(n => n.classList.remove('sel'))
  page().querySelector(`[data-${kind === 'similar' ? 'match' : kind}="${CSS.escape(id)}"]`)?.classList.add('sel')
  if (kind === 'trade') {
    const rid = R.trades.find(t => t.id === id)?.round.id
    page().querySelectorAll<HTMLElement>('.rv-eq-dot').forEach(d => d.classList.toggle('sel', d.dataset.round === rid))
  }
  renderDetail()
}

async function refreshAll(): Promise<void> {
  R.playing = ''
  await load()
}

async function saveNote(btn: HTMLButtonElement): Promise<void> {
  const t = R.trades.find(x => x.id === btn.dataset.id); if (!t) return
  const ta = document.getElementById('rvNote') as HTMLTextAreaElement | null; if (!ta) return
  const text = ta.value.trim()
  btn.disabled = true
  try {
    const next = await reviewApi.tradeNote(t.id, t.revision, text)
    Object.assign(t, next)
    if (player?.plan?.kind === 'trade') player.plan.note = text || null
    toast('已保存', '回放停在开仓处时会显示', 'check')
    const foot = document.getElementById('rvFoot'); if (foot) foot.innerHTML = tradeFoot(t)
    renderLeft()
  } catch (err) {
    if (err instanceof ReviewError && err.code === 'record_revision_changed') {
      try { R.trades = await reviewApi.trades() } catch { /* 下次刷新再说 */ }
    }
    toast('没保存上', errorText(err), 'info')
    btn.disabled = false
  }
}

async function startFind(viewId: string, btn: HTMLButtonElement): Promise<void> {
  const v = R.views.find(x => x.draft.id === viewId); if (!v) return
  btn.disabled = true
  try {
    const cutoff = Math.min(Date.now() - 1000, v.draft.created)
    const job = await reviewApi.startSearch(v.draft.range, cutoff)
    const r = v.draft.range
    rememberSearch({ id: job.id, symbol: r.symbol, iv: r.interval, bars: r.bars, label: `${codeOf(r.symbol)} ${ivText(r.interval)} · ${r.bars} 根`, created: Date.now() })
    R.searches.set(job.id, { meta: storedSearches()[0], status: { id: job.id, status: job.status as SearchStatus['status'], checked: 0, processed: 0, total: 0, error: null }, results: null, error: null })
    toast('开始找相似', '在全市场历史里找和这段走势像的片段，找完会列在「相似走势」', 'search')
    // 先切过去（「排队中」这一条立刻就在），进度再慢慢补
    R.tab = 'similar'; savePref(); player?.stop(); render()
    await refreshSearches()
    if (R.shown) render()
  } catch (err) {
    toast('找相似没发起', errorText(err), 'info')
    btn.disabled = false
  }
}

async function doSave(searchId: string, matchId: string, btn: HTMLButtonElement): Promise<void> {
  btn.disabled = true
  try {
    const s = await reviewApi.save(searchId, matchId)
    R.saved = [s, ...R.saved.filter(x => x.item.id !== s.item.id)]
    render()
  } catch (err) { toast('没收藏上', errorText(err), 'info'); btn.disabled = false }
}

async function doUnsave(matchId: string, btn: HTMLButtonElement): Promise<void> {
  const s = R.saved.find(x => x.item.id === matchId); if (!s) return
  btn.disabled = true
  try {
    await reviewApi.unsave(matchId, s.revision)
    R.saved = R.saved.filter(x => x.item.id !== matchId)
    if (R.sel.similar === `saved:${matchId}`) R.sel.similar = null
    render()
  } catch (err) {
    if (err instanceof ReviewError && err.status === 409) { try { R.saved = await reviewApi.saved() } catch { /* 下次刷新 */ } }
    toast('没取消收藏', errorText(err), 'info'); btn.disabled = false
  }
}

function onKey(e: KeyboardEvent): void {
  if (!R.shown || !player || e.key !== ' ') return
  const t = e.target as HTMLElement
  if (t.closest('input,textarea,select,button,[contenteditable="true"]')) return
  e.preventDefault()
  player.toggle()
}

// ------------------------------------------------------------ 入口
function shown(): void {
  R.shown = true
  if (!reviewToken()) { renderLogin(false); return }
  if (!R.built) build()
  player?.wake()
  if (!R.loadedAt || ago(R.loadedAt) > 60_000) { render(); void load() }
  else render()
}

function hidden(): void {
  R.shown = false
  clearTimeout(pollTimer)
  player?.sleep()
}

/** 从别的页跳进来并选中一条：交易回合按回合 id（记录 id 或 round.id 都认）、观点按记录 id。
 * 强制重新取一次数——刚在图上记的那一笔、手机刚传上的成交都要看得到。 */
function openAt(tab: 'trade' | 'view', id: string): void {
  R.tab = tab; savePref()
  if (tab === 'trade') R.sel.trade = id
  else R.sel.view = id
  R.loadedAt = 0
  wantSel = { tab, id }
  go('review')
}
/** load() 之后把 round.id 换成记录 id（交易面板手上只有回合里的成交，拿得到的是 round.id） */
let wantSel: { tab: 'trade' | 'view'; id: string } | null = null
function applyWanted(): void {
  if (!wantSel) return
  const w = wantSel
  if (w.tab === 'trade') {
    const t = R.trades.find(x => x.id === w.id || x.round.id === w.id)
    if (!t) return
    R.sel.trade = t.id
    if (R.symbol !== 'all' && R.symbol !== t.round.symbol) R.symbol = 'all'
  } else if (!R.views.some(v => v.draft.id === w.id)) return
  wantSel = null
  scrollSel = true
}
let scrollSel = false

/** 换账号（登录、退出、被踢）：上个账号的回合、观点、战绩、收藏、搜索一律清掉，在途的作废；开着这一页就按新账号重来 */
function resetAccount(): void {
  gate.reset()
  clearTimeout(pollTimer)
  player?.stop()
  R.trades = []; R.views = []; R.stats = null; R.saved = []; R.searches.clear()
  R.loadedAt = 0; R.loading = false; R.error = null; R.symbol = 'all'; R.playing = ''
  R.sel = { trade: null, view: null, similar: null }
  wantSel = null
  if (R.shown) shown()
}

export function initReview(): void {
  loadPref()
  onSession(resetAccount)
  hooks.openReview = openAt
  hooks.pageShown.review = shown
  hooks.pageHidden.review = hidden
  hooks.onTheme.push(() => player?.readTheme())
  addEventListener('keydown', onKey)
}
