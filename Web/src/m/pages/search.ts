/* 手机网页版 · 搜索页（照 iOS Symbols/SymbolSearchView.swift）
 *
 * 自选页头部的放大镜开的那一页：满屏盖在上面，顶上一条 44 高的胶囊输入框 +「取消」。
 * 没打字：历史搜索（小块）→ 最近看过 → 都没有时给「热门」（24h 成交额前 10）。
 * 打了字：「品种 N」，先按最匹配、同档按 24h 成交额降序，先摆 6 行，多了给「查看全部 N 个品种」。
 * 行上的星是加自选的唯一入口；点行换图。
 *
 * 键盘：输入框锁英文（autocapitalize/autocorrect/spellcheck 关、lang=en、inputmode=latin）；
 * visualViewport 跟着键盘缩，整页高度等于可视区，内容始终留在键盘上沿以内。
 */
import '../styles/search.css'
import { st, save } from '../app/store'
import { openSymbol, hooks } from '../app/shell'
import { el, layer } from '../ui/dom'
import { icon } from '../ui/icons'
import { confirmDialog } from '../ui/sheet'
import { toast } from '../ui/toast'
import { S, on, streamName, type Sym } from '../../market'
import { esc } from '../model/rowText'
import { clearHistory, hot, rank, readHistory, remember, SEARCH_PREVIEW, type Ranked } from '../model/search'
import { factsOf, listRowHTML, splitSymbol } from '../model/rowHTML'
import { isFavorite, toggleFavorite } from '../model/favorites'
import { life } from '../model/life'
import { ensureUniverse, wantStreams } from './_streams'

const EMPTY_TEXT = '没有这个品种'

export interface SearchOptions {
  /** 加了自选之后（自选页用它把分类切到品种落进去的那一类） */
  onStarred?: (symbol: string) => void
  onClose?: () => void
}

/** 屏上那一个搜索页（同一时刻只有一个） */
let current: { close(): void } | null = null

/** 打开搜索页。必须在点击回调里同步调用，iOS Safari 才肯把键盘弹上来 */
export function openSearch(opts: SearchOptions = {}): void {
  if (current) return
  const root = el('div', 'msr')
  root.setAttribute('role', 'dialog')
  root.setAttribute('aria-label', '搜索品种')
  root.innerHTML = `<div class="msr-bar">
      <label class="msr-field">${icon('search', 16)}
        <input type="search" enterkeyhint="search" placeholder="搜 BTC、ETH、SOL…" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" lang="en" inputmode="latin" aria-label="搜索品种">
        <button type="button" class="msr-clear" aria-label="清空" hidden>${CLEAR}</button>
      </label>
      <button type="button" class="msr-cancel">取消</button>
    </div>
    <div class="msr-scroll"><div class="msr-body"></div></div>`
  const input = root.querySelector<HTMLInputElement>('input')!
  const clearBtn = root.querySelector<HTMLButtonElement>('.msr-clear')!
  const scroll = root.querySelector<HTMLElement>('.msr-scroll')!
  const body = root.querySelector<HTMLElement>('.msr-body')!
  layer().appendChild(root)
  input.focus({ preventScroll: true })
  // 这一次打开的生命期：关掉时监听、排着的帧、迟到的回调一起作废（见 model/life.ts）
  const L = life()

  let q = ''
  let showAll = false
  let hotList: string[] = []
  let shown: string[] = []

  const all = (): Sym[] => [...S.symbols.values()]
  const fitViewport = (): void => {
    const vv = window.visualViewport
    if (!vv) return
    root.style.height = vv.height + 'px'
    root.style.transform = `translateY(${vv.offsetTop}px)`
  }
  const refreshHot = (): void => {
    if (hotList.length >= 10 || readHistory().length || st.symbols.recents.length) return
    const next = hot(all().map(s => ({ symbol: s.symbol, vol: s.vol, price: s.price }))).map(s => s.symbol)
    if (next.length > hotList.length) hotList = next
  }

  const row = (s: Sym | undefined, symbol: string, hl: [number, number] | null = null): string => {
    const f = factsOf(symbol, s)
    return listRowHTML(f, { price: s?.price ?? null, dec: s?.dec, pct: s?.pct ?? null, meta: `${symbol} 永续`, fav: isFavorite(st.symbols, symbol), hl })
  }
  const rows = (list: string[] | Ranked<Sym>[]): string => list.map((x, i) => {
    const html = typeof x === 'string' ? row(S.symbols.get(x), x) : row(x.item, x.item.symbol, x.hit.hl)
    return (i ? '<div class="sr-div"></div>' : '') + html
  }).join('')
  const head = (title: string, trailing = ''): string => `<div class="msr-head"><span>${esc(title)}</span>${trailing}</div>`

  function render(): void {
    if (L.ended) return
    const term = q.trim()
    clearBtn.hidden = !q
    let html = ''
    shown = []
    if (term) {
      const hits = rank(all().map(s => s), term, s => splitSymbol(s.symbol).base)
      if (!hits.length) html = `<div class="msr-empty">${S.symbols.size ? EMPTY_TEXT : S.live === false ? '品种表没拉到，稍后再试' : '品种表加载中…'}</div>`
      else {
        const list = showAll ? hits.slice(0, 200) : hits.slice(0, SEARCH_PREVIEW)
        shown = list.map(h => h.item.symbol)
        html = head('品种', `<span class="msr-count num">${hits.length}</span>`) + rows(list)
        if (!showAll && hits.length > SEARCH_PREVIEW) html += `<button type="button" class="msr-all">查看全部 ${hits.length} 个品种${icon('chevronRight', 12)}</button>`
      }
    } else {
      const terms = readHistory()
      if (terms.length) {
        html += head('历史搜索', `<button type="button" class="msr-trash" aria-label="清除搜索记录">${icon('trash', 13)}</button>`)
        html += `<div class="msr-chips">${terms.map(t => `<button type="button" class="msr-chip" data-term="${esc(t)}">${esc(t)}</button>`).join('')}</div>`
      }
      const rec = st.symbols.recents.filter(s => S.symbols.has(s))
      if (rec.length) { html += head('最近看过') + rows(rec); shown.push(...rec) }
      if (!terms.length && !rec.length) {
        refreshHot()
        if (hotList.length) { html += head('热门') + rows(hotList); shown.push(...hotList) }
      }
    }
    body.innerHTML = html
    wantStreams('search', shown.map(s => streamName.ticker(s)))
  }
  const schedule = L.frame(render)

  input.addEventListener('input', () => { q = input.value; showAll = false; scroll.scrollTop = 0; render() })
  input.addEventListener('keydown', e => { if (e.key === 'Enter') { remember(q); input.blur() } })
  clearBtn.onclick = () => { input.value = ''; q = ''; showAll = false; render(); input.focus() }
  root.querySelector<HTMLElement>('.msr-cancel')!.onclick = () => close()
  // 滚动收键盘（iOS scrollDismissesKeyboard）
  scroll.addEventListener('touchmove', () => { if (document.activeElement === input) input.blur() }, { passive: true })

  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    const star = t.closest<HTMLElement>('[data-star]')
    if (star) {
      const sym = star.dataset.star!
      const s = S.symbols.get(sym)
      const added = toggleFavorite(st.symbols, sym, st.favoritesGroup || null, { kind: s?.kind, base: splitSymbol(sym).base })
      save()
      star.classList.toggle('on', added)
      star.setAttribute('aria-pressed', String(added))
      star.setAttribute('aria-label', added ? '取消自选' : '加入自选')
      if (added) opts.onStarred?.(sym)
      return
    }
    const chip = t.closest<HTMLElement>('.msr-chip')
    if (chip) { input.value = q = chip.dataset.term || ''; remember(q); render(); input.focus(); return }
    if (t.closest('.msr-trash')) {
      input.blur()
      void confirmDialog({ title: '清除搜索记录', confirm: '清除', destructive: true }).then(ok => { if (ok) { clearHistory(); render() } })
      return
    }
    if (t.closest('.msr-all')) { remember(q); showAll = true; render(); return }
    const r = t.closest<HTMLElement>('.sr')
    if (r) {
      const sym = r.dataset.sym!
      if (q.trim()) remember(q)
      close()
      openSymbol(sym)
    }
  })

  // 行情推送：图表那只品种每笔成交都会来一次 ticker，一帧里只按最后的价补一次行尾
  let pending = new Set<string>()
  const flush = L.frame(() => {
    const syms = pending; pending = new Set()
    syms.forEach(patch)
  })
  L.add(on(e => {
    if (e.type === 'universe') { refreshHot(); schedule() }
    else if (e.type === 'ticker' && shown.includes(e.symbol)) { pending.add(e.symbol); flush() }
  }))
  function patch(sym: string): void {
    const s = S.symbols.get(sym); if (!s) return
    body.querySelectorAll<HTMLElement>(`.sr[data-sym="${CSS.escape(sym)}"]`).forEach(r => {
      const tmp = document.createElement('div')
      tmp.innerHTML = row(s, sym)
      const next = tmp.firstElementChild!
      r.querySelector('.sr-right')!.replaceWith(next.querySelector('.sr-right')!)
    })
  }

  const vv = window.visualViewport
  L.listen(vv, 'resize', fitViewport)
  L.listen(vv, 'scroll', fitViewport)
  fitViewport()
  const onFg = (): void => schedule()
  hooks.onForeground.push(onFg)
  L.add(() => { const i = hooks.onForeground.indexOf(onFg); if (i >= 0) hooks.onForeground.splice(i, 1) })
  // 按系统返回（Android / 浏览器返回手势）也只是关掉这一层；关掉时连同这条监听一起摘掉
  L.listen(window, 'hashchange', () => close())

  const me = { close }
  function close(): void {
    if (!L.end()) return
    if (current === me) current = null
    input.blur()
    wantStreams('search', [])
    root.classList.remove('in')
    setTimeout(() => root.remove(), 220)
    opts.onClose?.()
  }
  current = me
  render()
  requestAnimationFrame(() => root.classList.add('in'))
  void ensureUniverse().then(L.guard(() => { refreshHot(); schedule() }), L.guard(() => toast('品种表没拉到')))
}

export function closeSearch(): void { current?.close() }

const CLEAR = '<svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="currentColor"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke="var(--raised2)" stroke-width="2" stroke-linecap="round"/></svg>'
