/* Hkline Web · 搜品种弹层（电脑版顶栏搜索、⌘K、在图上直接打字、自选栏「＋」都开它；2026-10-10 审查 C2 从 pages/chart.ts 挪出来）
 *
 * 一个品种一行（pages/searchGroups searchRows）：同一个基础币在几家交易所的合约并成一行，
 * 交易所是行尾一排小记号（缩写 + 分类色圆点，规范 §2：分类色只上小记号）。
 *   回车 / 点行：开这一行选中的那一家（默认：匹配档最高 → 当前图所在那一家 → 自选里有的 → 币安）；
 *   悬停某个记号 / ← →：这一行改选那一家（价、涨跌、成交额跟着换）；点记号直接开那一家；
 *   ⇧↵ / 星：加 / 移自选（选中的那一家）；Tab：换分类。
 * 美股 / 大宗 / 美元指数这类只一家有的照常一行。
 */
import { S, on, loadAllVenues, type Kind, type Sym } from '../market'
import { normalize } from '../market/searchText'
import { parseKey } from '../market/identity'
import { venueLabel } from '../venues'
import { dialog, dialogs } from '../ui/overlay'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { badge, cls, pctText, priceText, chartSub } from '../ui/common'
import { fmtCompact } from '../util/format'
import { HL } from '../terms'
import { searchRows, rowName, venueStatusHTML, type SearchRow } from './searchGroups'

export interface SymbolSearchDeps {
  isWatched: (k: string) => boolean
  toggleWatch: (k: string) => unknown
  /** 当前图那只的键（回车默认开它所在的那一家） */
  current: () => string
  /** 打开一只（切到图表页、换品种） */
  open: (k: string) => void
}

const CATS: ['all' | Kind, string][] = [['all', '全部'], ['crypto', '加密'], ['us', '美股'], ['com', '大宗']]

export interface RowOpts {
  active: boolean
  /** 归一后的查询（名字高亮用） */
  qq: string
  /** 这一行选中第几家 */
  pick: number
  /** 行尾那一格（搜索弹层是星，对比弹层是 加入 / 移出 钮或「主图」） */
  tail: string
  /** 行上另加的类（对比弹层的 cmp-off） */
  cls?: string
  /** 行上另加的属性（对比弹层的 aria-disabled） */
  attrs?: string
  /** 哪几家的记号打勾（对比弹层：已在对比里的那几只） */
  mark?: (s: Sym) => boolean
}

/** 行尾的交易所记号：一家一颗（美元指数这类没有交易所缩写的不出）；同一家两只（倍数前缀不同）时记号后带上名字。
 *  搜索弹层与对比弹层共用 */
export function venueChips(row: SearchRow, pick = row.pick, mark?: (s: Sym) => boolean): string {
  const names = row.items.map(s => venueLabel(s.symbol))
  return row.items.map((s, j) => {
    const v = names[j]
    if (!v) return ''
    const dup = names.filter(x => x === v).length > 1
    return `<button type="button" class="sr-v${mark?.(s) ? ' in' : ''}" tabindex="-1" data-v="${j}" data-venue="${esc(parseKey(s.symbol).venue)}" aria-pressed="${j === pick}" data-tip="${esc(chartSub(s.symbol, s))}"><i aria-hidden="true"></i>${esc(dup ? `${v} ${s.title || s.code}` : v)}</button>`
  }).join('')
}

/** 一行的 HTML（k：键盘下标）：徽标 · 名字 · 选中那一家的价 / 涨跌 / 成交额 · 交易所记号 · 行尾一格。搜索弹层与对比弹层共用 */
export function rowHTML(row: SearchRow, k: number, o: RowOpts): string {
  const s = row.items[o.pick]
  return `<div class="sr ${o.active ? 'active' : ''} ${o.cls ?? ''}" role="option" aria-selected="${o.active}" data-i="${k}"${o.attrs ? ' ' + o.attrs : ''}>
    ${badge(s, 'lg')}<div class="sr-name"><div class="n1">${rowName(s, o.qq)}</div>${s.cn ? `<div class="n2">${esc(s.cn)}</div>` : ''}</div>
    <div class="r num" data-f="p">${priceText(s)}</div><div class="r num ${cls(s.pct)}" data-f="c">${pctText(s.pct)}</div><div class="r num muted" data-f="v">${fmtCompact(s.vol)}</div>
    <div class="sr-vs">${venueChips(row, o.pick, o.mark)}</div>
    <div class="sr-tail" data-tail>${o.tail}</div></div>`
}

/** 一行改选了交易所：就地换价 / 涨跌 / 成交额 / 记号 / 行尾一格，不重建行节点（指针下的记号不换对象，悬停不闪） */
export function paintRow(el: HTMLElement, row: SearchRow, o: Pick<RowOpts, 'pick' | 'tail' | 'mark'> & { toggle?: Record<string, boolean>; attrs?: Record<string, string> }): void {
  const s = row.items[o.pick]
  const set = (f: string, txt: string, c?: string) => { const x = el.querySelector<HTMLElement>(`[data-f="${f}"]`); if (!x) return; x.textContent = txt; if (c != null) x.className = `r num ${c}` }
  set('p', priceText(s)); set('c', pctText(s.pct), cls(s.pct)); set('v', fmtCompact(s.vol))
  $$('.sr-v', el).forEach(b => { const j = +(b.dataset.v ?? -1); b.setAttribute('aria-pressed', String(j === o.pick)); b.classList.toggle('in', !!(o.mark && row.items[j] && o.mark(row.items[j]))) })
  const tail = el.querySelector<HTMLElement>('[data-tail]'); if (tail) tail.innerHTML = o.tail
  for (const [c, on_] of Object.entries(o.toggle ?? {})) el.classList.toggle(c, on_)
  for (const [k, v] of Object.entries(o.attrs ?? {})) el.setAttribute(k, v)
}

/** ← → 换交易所：这一行不止一家才接（只有一家的行照旧移光标）；回下一个要选的下标，不接回 null */
export function stepPick(e: KeyboardEvent, row: SearchRow | undefined, pick: number): number | null {
  if ((e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') || !row || row.items.length < 2 || e.metaKey || e.altKey || e.shiftKey || e.ctrlKey) return null
  return Math.max(0, Math.min(row.items.length - 1, pick + (e.key === 'ArrowRight' ? 1 : -1)))
}

/** 这一行现在选中第几家：这次弹层里改选过（chosen：行键 → 品种键）就用它；再看 prefer（对比弹层：已在对比里的那只）；
 *  否则用默认那一家。回车 / 点行作用的就是 items[这个] */
export function pickIndex(r: SearchRow, chosen?: ReadonlyMap<string, string>, prefer?: (s: Sym) => boolean): number {
  const k = chosen?.get(r.id); const j = k ? r.items.findIndex(s => s.symbol === k) : -1
  if (j >= 0) return j
  const p = prefer ? r.items.findIndex(prefer) : -1
  return p >= 0 ? p : r.pick
}

/** 搜索弹层行尾的星 */
const starHTML = (w: boolean): string => `<button class="ibtn sm" data-w aria-label="${w ? '移出自选' : '加入自选'}" style="color:${w ? '#F5A623' : ''}">${I(w ? 'star' : 'starOff')}</button>`

export function openSymbolSearch(initial: string, D: SymbolSearchDeps): void {
  if (dialogs.some(d => d.dlg.classList.contains('search-dlg'))) return
  let cat: 'all' | Kind = 'all', q = initial, activeIdx = 0, rows: SearchRow[] = []
  /** 这次弹层里改选过的那一家（行键 → 品种键）；换查询后同一行还认它 */
  const chosen = new Map<string, string>()
  const pickOf = (r: SearchRow): number => pickIndex(r, chosen)
  const target = (r: SearchRow | undefined): Sym | undefined => r && r.items[pickOf(r)]
  // 别家的品种表懒拉：弹层一打开就拉全部（已经拉到的不再拉），到了一家重画一次
  const off = on(e => { if (e.type === 'universe') render() })
  const d = dialog(`<div class="search-top">${I('search', 'icon-24')}<input id="sq" placeholder="搜索品种，比如 BTC、英伟达、黄金" autocomplete="off" spellcheck="false" aria-label="搜索品种" value="${esc(initial)}"><kbd>Esc</kbd></div>
    <div class="search-cats" role="tablist">${CATS.map(([k, l]) => `<button class="chip" data-cat="${k}" aria-pressed="${k === cat}">${l}</button>`).join('')}</div>
    <div class="search-list scroll" id="sl" role="listbox"></div>
    <div class="search-foot"><span><kbd>↑</kbd><kbd>↓</kbd>选择</span><span><kbd>←</kbd><kbd>→</kbd>${esc(HL.searchVenue)}</span><span><kbd>↵</kbd>打开</span><span><kbd>⇧</kbd><kbd>↵</kbd>加自选</span><span><kbd>Tab</kbd>换分类</span></div>`, 'search-dlg sym-dlg', { label: '搜索品种', onClose: off })
  void loadAllVenues()
  const inp = $<HTMLInputElement>('#sq', d.dlg), listEl = $('#sl', d.dlg)
  function render(): void {
    const qq = normalize(q)
    const pool = [...S.symbols.values()].filter(s => cat === 'all' || s.kind === cat)
    rows = searchRows(pool, q, D.isWatched, D.current())
    activeIdx = Math.min(activeIdx, Math.max(0, rows.length - 1))
    listEl.innerHTML = !S.symbols.size ? `<div class="empty">${S.live === false ? '连不上币安合约接口，搜不了' : '正在取品种表…'}</div>`
      : rows.length ? rows.map((r, k) => { const p = pickOf(r); return rowHTML(r, k, { active: k === activeIdx, qq, pick: p, tail: starHTML(D.isWatched(r.items[p].symbol)) }) }).join('') + venueStatusHTML()
      : `<div class="empty">没有找到「${esc(q)}」<div class="faint" style="font-size:var(--t12);margin-top:var(--s1)">代号、中文名都能搜，比如「英伟达」「黄金」</div></div>${venueStatusHTML()}`
  }
  function repaint(k: number): void {
    const r = rows[k], el = listEl.querySelector<HTMLElement>(`.sr[data-i="${k}"]`); if (!r || !el) return
    const p = pickOf(r)
    paintRow(el, r, { pick: p, tail: starHTML(D.isWatched(r.items[p].symbol)) })
  }
  function choose(k: number, j: number): void {
    const r = rows[k]; if (!r || !r.items[j] || pickOf(r) === j) return
    chosen.set(r.id, r.items[j].symbol); repaint(k)
  }
  function openRow(s: Sym | undefined): void { d.close(); if (s) D.open(s.symbol) }
  const setCat = (k: 'all' | Kind) => { cat = k; $$('[data-cat]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.cat === cat))); activeIdx = 0; render() }
  function move(k: number): void { activeIdx = Math.max(0, Math.min(rows.length - 1, activeIdx + k)); render(); $('.sr.active', listEl)?.scrollIntoView({ block: 'nearest' }) }
  inp.addEventListener('input', () => { q = inp.value; activeIdx = 0; render() })
  inp.addEventListener('keydown', e => {
    const step = stepPick(e, rows[activeIdx], rows[activeIdx] ? pickOf(rows[activeIdx]) : 0)
    if (step != null) { e.preventDefault(); choose(activeIdx, step) }
    else if (e.key === 'ArrowDown') { e.preventDefault(); move(1) }
    else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1) }
    else if (e.key === 'Enter') { e.preventDefault(); const s = target(rows[activeIdx]); if (!s) return; if (e.shiftKey) { D.toggleWatch(s.symbol); repaint(activeIdx) } else openRow(s) }
    else if (e.key === 'Tab') { e.preventDefault(); const cs = CATS.map(c => c[0]); setCat(cs[(cs.indexOf(cat) + (e.shiftKey ? cs.length - 1 : 1)) % cs.length]) }
  })
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const c = t.closest<HTMLElement>('[data-cat]'); if (c) { setCat(c.dataset.cat as 'all' | Kind); inp.focus(); return }
    const r = t.closest<HTMLElement>('.sr'); if (!r) return
    const k = +(r.dataset.i || 0), row = rows[k]; if (!row) return
    const w = t.closest<HTMLElement>('[data-w]'); if (w) { e.stopPropagation(); const s = target(row); if (s) D.toggleWatch(s.symbol); repaint(k); inp.focus(); return }
    const v = t.closest<HTMLElement>('.sr-v'); if (v) { openRow(row.items[+(v.dataset.v || 0)]); return }
    openRow(target(row))
  })
  listEl.addEventListener('mousemove', e => {
    const r = tgt(e).closest<HTMLElement>('.sr'); if (!r) return
    const k = +(r.dataset.i || 0)
    if (k !== activeIdx) { activeIdx = k; $$('.sr', listEl).forEach(x => { const on_ = +(x.dataset.i || -1) === activeIdx; x.classList.toggle('active', on_); x.setAttribute('aria-selected', String(on_)) }) }
    const v = tgt(e).closest<HTMLElement>('.sr-v'); if (v) choose(k, +(v.dataset.v || 0))
  })
  render(); inp.focus(); inp.setSelectionRange(q.length, q.length)
}
