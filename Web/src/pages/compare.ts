/* Hkline Web · 图表页的「对比」：工具条入口、挑品种的弹层、各格叠线与推送
 *
 * 偏好里一人一份 st.compareSymbols（最多三只，与 iOS / 手机网页同一份、跟账号同步）。
 * 每格按自己的主图挑：去掉格子主图那只，剩下的取同周期 K 线叠成百分比线（chart/compare.ts）。
 * 取数器按「品种|周期」共用：十六图里同一只对比品种同一周期只取一份、只订一条推送。
 * 秒级周期没有交易所 K 线可对，不叠（自定义分钟周期照常，从原生周期并）。
 */
import '../styles/compare.css'
import { st, save } from '../app/store'
import { hooks } from '../app/shell'
import { cleanCompare } from '../sync/codec'
import { CompareStore, COMPARE_COLORS, MAX_COMPARE, compareKeyOf, compareSymbolOf, compareTargets, type CompareLoad, type CompareLine } from '../chart/compare'
import type { TVChart } from '../chart/chart'
import { isSecondIv, isCustomIv, customBase, customTick, streamIvOf } from '../chart/intervals'
import { S, on, streamName, headName, isDefaultVenue, loadAllVenues, type Kind, type Sym } from '../market'
import { venueLabel } from '../venues'
import { searchGroups, resultName, groupHead, venueStatusHTML } from './searchGroups'
import { normalize } from '../market/searchText'
import { IV_MS, fmtCompact } from '../util/format'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { toast, dialog, dialogs } from '../ui/overlay'
import { sym, badge, priceText, pctText, cls, chartSub } from '../ui/common'

export interface CompareCell { idx: number; chart: TVChart; symbol: string; iv: string }
export interface CompareDeps {
  cells: () => readonly CompareCell[]
  load: CompareLoad
  refreshStreams: () => void
  /** 工具条上「对比」的计数 */
  renderToolbar: () => void
  /** 当前格的主图品种（弹层里禁用它） */
  activeSymbol: () => string
  isWatched: (k: string) => boolean
}

let deps: CompareDeps | null = null
let store: CompareStore | null = null
/** 上一轮登记过对比的格子（布局收小了要把多出来的撤掉） */
let owners = new Set<number>()
/** 每张图上一次给的对比（没变就不重设，免得每次推送都重写图例） */
const painted = new WeakMap<TVChart, string>()
let streamsKey = ''
let paintTimer: ReturnType<typeof setTimeout> | null = null

export const MAX_TOAST = `最多对比 ${MAX_COMPARE} 个品种`

/** 展示名：品种表里的代号（1000PEPE → PEPE 那套），表里没有的去掉计价币；别家的前面带交易所缩写（OKX BTC 与币安 BTC 是两只） */
export function compareName(symbol: string): string {
  const code = sym(symbol)?.code || headName({ symbol }) || symbol
  return isDefaultVenue(symbol) ? code : `${venueLabel(symbol)} ${code}`.trim()
}
/** 偏好里的键 → 展示名（认不出的键显示最后一段） */
function keyName(key: string): string {
  const s = compareSymbolOf(key)
  return s ? compareName(s) : key.split('/').pop() || key
}

export function installCompare(d: CompareDeps): void {
  deps = d
  store = new CompareStore(d.load, () => schedulePaint(), iv => IV_MS[iv] ?? 0)
  hooks.extraStreams.push(() => {
    if (!store) return []
    const out: string[] = []
    for (const x of store.streams()) { const siv = streamIvOf(x.iv); if (siv) out.push(streamName.kline(x.symbol, siv)) }
    return out
  })
  let wsWas = S.wsState
  on(e => {
    if (!store) return
    if (e.type === 'kline') {
      for (const x of store.streams()) {
        if (x.symbol !== e.symbol) continue
        if (x.iv === e.iv) store.upsert(x.symbol, x.iv, { ...e.bar })
        else if (isCustomIv(x.iv) && customBase(x.iv) === e.iv) store.upsert(x.symbol, x.iv, customTick(x.symbol, x.iv, e.bar))
      }
    } else if (e.type === 'ws') {
      // 断线重连上：币安只推当前那一根，断开期间收线的几根要重拉末页补回来
      if (S.wsState === 'open' && wsWas !== 'open') store.resync()
      wsWas = S.wsState
    }
  })
  let hiddenAt = 0
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') { hiddenAt = Date.now(); return }
    if (hiddenAt && Date.now() - hiddenAt > 30e3) store?.resync()
    hiddenAt = 0
  })
}

/** 这一格此刻要叠的几只（秒级、还没装好 K 线的格子不叠） */
function targetsOf(c: CompareCell): ReturnType<typeof compareTargets> {
  if (isSecondIv(c.iv) || !c.chart.bars.length) return []
  return compareTargets(st.compareSymbols, c.symbol)
}
/** K 线已经是这一格配置的那份（换品种 / 周期的取数还在路上时不动，等 setData 之后再来） */
const loaded = (c: CompareCell): boolean => c.chart.meta.symbol === c.symbol && c.chart.iv === IV_MS[c.iv]

/** 偏好变了、格子装好 / 往左翻了 / 换了品种周期 / 布局变了：重新登记各格要的对比，再重画 */
export function refreshCompare(): void {
  if (!deps || !store) return
  const seen = new Set<number>()
  for (const c of deps.cells()) {
    if (c.chart.dead) continue
    seen.add(c.idx)
    if (!loaded(c)) continue
    const from = c.chart.bars[0]?.t ?? Infinity
    store.want(c.idx, targetsOf(c).map(t => ({ symbol: t.symbol, iv: c.iv, from })))
  }
  for (const k of owners) if (!seen.has(k)) store.want(k, [])
  owners = seen
  paint()
}

function schedulePaint(): void {
  if (paintTimer) return
  paintTimer = setTimeout(() => { paintTimer = null; paint() }, 100)
}
function paint(): void {
  if (!deps || !store) return
  if (paintTimer) { clearTimeout(paintTimer); paintTimer = null }
  for (const c of deps.cells()) {
    if (c.chart.dead || !loaded(c)) continue
    const lines: CompareLine[] = targetsOf(c).map(t => {
      const g = store!.get(t.symbol, c.iv)
      return { key: t.key, name: compareName(t.symbol), color: COMPARE_COLORS[t.slot % COMPARE_COLORS.length], bars: g?.bars ?? null, rev: g?.rev ?? 0, loading: !!g?.loading && !g.bars?.length }
    })
    const sig = lines.map(l => `${l.key}:${l.color}:${l.rev}:${l.bars ? l.bars.length : -1}:${l.loading ? 1 : 0}`).join('|')
    if (painted.get(c.chart) === sig) continue
    painted.set(c.chart, sig)
    c.chart.setCompare(lines)
  }
  const sk = store.streams().map(x => `${x.symbol}|${x.iv}`).sort().join(',')
  if (sk !== streamsKey) { streamsKey = sk; deps.refreshStreams() }
}

// ------------------------------------------------------------ 偏好
function inCompare(symbol: string): boolean { return st.compareSymbols.some(k => compareSymbolOf(k) === symbol) }
function setCompare(next: string[]): void {
  st.compareSymbols = cleanCompare(next)
  save(); refreshCompare(); deps?.renderToolbar()
}
/** 图例上点 × */
export function removeCompare(key: string): void {
  const s = compareSymbolOf(key)
  setCompare(st.compareSymbols.filter(k => k !== key && (s == null || compareSymbolOf(k) !== s)))
}
/** 加 / 撤一只；满了返回 false（调用方提示） */
export function toggleCompare(symbol: string): boolean {
  if (inCompare(symbol)) { setCompare(st.compareSymbols.filter(k => compareSymbolOf(k) !== symbol)); return true }
  if (st.compareSymbols.length >= MAX_COMPARE) return false
  setCompare([...st.compareSymbols, compareKeyOf(symbol)])
  return true
}

// ------------------------------------------------------------ 弹层（搜索框的样式，进入对比模式）
export function openCompare(): void {
  if (!deps || dialogs.some(d => d.dlg.classList.contains('search-dlg'))) return
  const D = deps
  let cat: 'all' | Kind = 'all', q = '', activeIdx = 0, results: Sym[] = []
  let offUniverse = (): void => {}
  const CATS: ['all' | Kind, string][] = [['all', '全部'], ['crypto', '加密'], ['us', '美股'], ['idx', '指数'], ['com', '大宗']]
  const d = dialog(`<div class="search-top">${I('compare', 'icon-24')}<input id="cq" placeholder="搜索要对比的品种，比如 ETH、美元指数" autocomplete="off" spellcheck="false" aria-label="搜索要对比的品种"><kbd>Esc</kbd></div>
    <div class="cmp-head" id="cmpHead"></div>
    <div class="search-cats" role="tablist">${CATS.map(([k, l]) => `<button class="chip" data-cat="${k}" aria-pressed="${k === cat}">${l}</button>`).join('')}</div>
    <div class="search-list scroll" id="cl" role="listbox" aria-multiselectable="true"></div>
    <div class="search-foot"><span><kbd>↑</kbd><kbd>↓</kbd>选择</span><span><kbd>↵</kbd>加入 / 移出对比</span><span><kbd>Tab</kbd>换分类</span></div>`, 'search-dlg cmp-dlg', { label: '对比', onClose: () => offUniverse() })
  const inp = $<HTMLInputElement>('#cq', d.dlg), listEl = $('#cl', d.dlg), headEl = $('#cmpHead', d.dlg)
  function renderHead(): void {
    const keys = st.compareSymbols
    headEl.innerHTML = `<span class="cmp-count">正在对比 <b class="num">${keys.length}/${MAX_COMPARE}</b></span>` + keys.map((k, i) =>
      `<span class="cmp-chip"><i style="background:${COMPARE_COLORS[i % COMPARE_COLORS.length]}"></i>${esc(keyName(k))}<button class="ibtn xs" data-rm="${esc(k)}" aria-label="移出对比 ${esc(keyName(k))}" data-tip="移出对比">${I('close', 'icon-16')}</button></span>`).join('')
  }
  function render(): void {
    renderHead()
    const qq = normalize(q), main = D.activeSymbol(), full = st.compareSymbols.length >= MAX_COMPARE
    const pool = [...S.symbols.values()].filter(s => cat === 'all' || s.kind === cat)
    const { groups, flat } = searchGroups(pool, q, D.isWatched)
    results = flat
    activeIdx = Math.min(activeIdx, Math.max(0, results.length - 1))
    let i = -1
    listEl.innerHTML = !S.symbols.size ? `<div class="empty">${S.live === false ? '连不上币安合约接口，搜不了' : '正在取品种表…'}</div>`
      : results.length ? groups.map(g => groupHead(g) + g.items.map(s => {
        i++
        const isMain = s.symbol === main, on_ = inCompare(s.symbol), dis = isMain || (full && !on_)
        const btn = isMain ? `<span class="cmp-tag">主图</span>`
          : `<button class="ibtn sm cmp-tgl ${on_ ? 'on' : ''}" data-t="${esc(s.symbol)}" aria-label="${on_ ? '移出对比' : '加入对比'}" aria-pressed="${on_}">${I(on_ ? 'check' : 'plus')}</button>`
        return `<div class="sr ${i === activeIdx ? 'active' : ''} ${dis ? 'cmp-off' : ''}" role="option" aria-selected="${on_}" aria-disabled="${dis}" data-i="${i}">
      ${badge(s, 'lg')}<div><div class="n1">${resultName(s, qq)}</div><div class="n2">${esc(s.cn || '')}${s.cn ? ' · ' : ''}${esc(chartSub(s.symbol, s))}</div></div>
      <div class="r num">${priceText(s)}</div><div class="r num ${cls(s.pct)}">${pctText(s.pct)}</div><div class="r num muted">${fmtCompact(s.vol)}</div>${btn}</div>`
      }).join('')).join('') + venueStatusHTML()
      : `<div class="empty">没有找到「${esc(q)}」</div>${venueStatusHTML()}`
  }
  function pick(s: Sym | undefined): void {
    if (!s) return
    if (s.symbol === D.activeSymbol()) return
    if (!toggleCompare(s.symbol)) { toast(MAX_TOAST, '先移出一个再加', 'compare', 2400); return }
    render()
  }
  const setCat = (k: 'all' | Kind) => { cat = k; $$('[data-cat]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.cat === cat))); activeIdx = 0; render() }
  function move(k: number): void { activeIdx = Math.max(0, Math.min(results.length - 1, activeIdx + k)); render(); $('.sr.active', listEl)?.scrollIntoView({ block: 'nearest' }) }
  inp.addEventListener('input', () => { q = inp.value; activeIdx = 0; render() })
  inp.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
    else if (e.key === 'Enter') { e.preventDefault(); pick(results[activeIdx]) }
    else if (e.key === 'Tab') { e.preventDefault(); const cs = CATS.map(c => c[0]); setCat(cs[(cs.indexOf(cat) + (e.shiftKey ? cs.length - 1 : 1)) % cs.length]) }
  })
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const c = t.closest<HTMLElement>('[data-cat]'); if (c) { setCat(c.dataset.cat as 'all' | Kind); inp.focus(); return }
    const rm = t.closest<HTMLElement>('[data-rm]'); if (rm) { e.stopPropagation(); removeCompare(rm.dataset.rm || ''); render(); inp.focus(); return }
    const r = t.closest<HTMLElement>('.sr'); if (r) { activeIdx = +(r.dataset.i || 0); pick(results[activeIdx]); inp.focus() }
  })
  listEl.addEventListener('mousemove', e => { const r = tgt(e).closest<HTMLElement>('.sr'); if (r && +(r.dataset.i || 0) !== activeIdx) { activeIdx = +(r.dataset.i || 0); $$('.sr', listEl).forEach(x => x.classList.toggle('active', +(x.dataset.i || -1) === activeIdx)) } })
  // 别家的品种表懒拉：弹层一打开就拉全部，到了一家重画一次（关掉弹层时撤掉）
  offUniverse = on(e => { if (e.type === 'universe') render() })
  void loadAllVenues()
  render(); inp.focus()
}

/** 测试用：清掉模块状态 */
export function _resetCompareForTest(): void { store?.dispose(); store = null; deps = null; owners = new Set(); streamsKey = '' }
