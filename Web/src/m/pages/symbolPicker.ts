/* 手机网页版 · 品种整页（照 iOS Symbols/SymbolPickerView.swift + SymbolPickerModel.swift）
 *
 * 搜索页搜到的比 6 行多时「查看全部 N 个品种」进来这一页，查询词跟着过来；
 * 页头那颗返回原路退回搜索页（查询词也带回去），挑中一只品种就两层一起收掉、换图。
 *
 * 从上到下：页头（‹ · 品种 · N 个永续合约）→ 搜索框 +「清空」→ 筛选两颗小块（市场 / 板块）→ 分组列表。
 * 进页不弹键盘：这一页第一眼是那张表，人多半是进来翻的，要打字他自己点框。
 * 自选那一组的行：左划「取消自选」、长按拖动排序（只在看得见的自选之间挪）。
 * 行情只订露在屏上的那几行（IntersectionObserver），不给整张 120 行的表全订。
 */
import '../styles/search.css'
import '../styles/symbolPicker.css'
import { st, save } from '../app/store'
import { hooks, registerOverlay } from '../app/shell'
import { el, layer } from '../ui/dom'
import { icon } from '../ui/icons'
import { openSheet } from '../ui/sheet'
import { swipeRow, closeOpenSwipe, type SwipeHandle } from '../ui/swipeDelete'
import { reorderable, type ReorderHandle } from '../ui/reorder'
import { S, on, streamName, type Sym } from '../../market'
import { esc } from '../model/rowText'
import { factsOf, listRowHTML, splitSymbol } from '../model/rowHTML'
import * as F from '../model/favorites'
import { applyFilter, buildSections, countText, EMPTY_TEXT, marketTitle, moreNote, type PickerSection } from '../model/picker'
import { life } from '../model/life'
import { ensureUniverse, wantStreams } from './_streams'

export interface PickerOptions {
  /** 带进来的查询词 */
  query?: string
  /** 返回：原路退回上一层，带回此刻的查询词 */
  onBack?: (query: string) => void
  /** 挑中一只品种（调用方负责收掉下面那几层、换图） */
  onPick: (symbol: string) => void
  /** 加了自选之后（自选页用它把分类切到品种落进去的那一类） */
  onStarred?: (symbol: string) => void
}

/** 筛选在这一次会话里记着（iOS 的 model 常驻，下回进来还是上回筛的那样） */
let marketFilter = 'all'
let sectorFilter: string | null = null

let current: { close(): void } | null = null

export function openPicker(opts: PickerOptions): void {
  if (current) return
  const root = el('div', 'mpk')
  root.setAttribute('role', 'dialog')
  root.setAttribute('aria-label', '品种')
  root.innerHTML = `<div class="mpk-head">
      <button type="button" class="mpk-back" aria-label="返回">${BACK}</button>
      <div class="mpk-title"><span class="mpk-name">品种</span><span class="mpk-count num"></span></div>
    </div>
    <div class="mpk-bar">
      <label class="msr-field">${icon('search', 16)}
        <input type="search" enterkeyhint="search" placeholder="搜 BTC、ETH、SOL…" autocomplete="off" autocapitalize="characters" autocorrect="off" spellcheck="false" lang="en" inputmode="latin" aria-label="搜索品种">
      </label>
      <button type="button" class="mpk-clear">清空</button>
    </div>
    <div class="mpk-filters">
      <button type="button" class="mpk-chip" data-f="market" aria-haspopup="dialog"></button>
      <button type="button" class="mpk-chip" data-f="sector" aria-haspopup="dialog"></button>
    </div>
    <div class="mpk-scroll"><div class="mpk-body"></div></div>`
  const input = root.querySelector<HTMLInputElement>('input')!
  const scroll = root.querySelector<HTMLElement>('.mpk-scroll')!
  const body = root.querySelector<HTMLElement>('.mpk-body')!
  const count = root.querySelector<HTMLElement>('.mpk-count')!
  const chipM = root.querySelector<HTMLButtonElement>('[data-f="market"]')!
  const chipS = root.querySelector<HTMLButtonElement>('[data-f="sector"]')!
  layer().appendChild(root)
  const L = life()

  let q = opts.query ?? ''
  input.value = q
  let markets: string[] = []
  let sectors: string[] = []
  let swipes: SwipeHandle[] = []
  let sorter: ReorderHandle | null = null
  /** 拖自选的途中品种表 / 回前台要重画：先记下，松手再画（重画会把手里那行换掉、拖动凭空取消） */
  let redrawAfterDrag = false
  let filterTimer = 0

  const all = (): Sym[] => [...S.symbols.values()]
  const fitViewport = (): void => {
    const vv = window.visualViewport
    if (!vv) return
    root.style.height = vv.height + 'px'
    root.style.transform = `translateY(${vv.offsetTop}px)`
  }

  const chipHTML = (title: string): string => `<span>${esc(title)}</span>${icon('chevron', 11)}`
  function paintChips(): void {
    chipM.innerHTML = chipHTML(marketTitle(marketFilter))
    chipM.classList.toggle('on', marketFilter !== 'all')
    chipM.setAttribute('aria-pressed', String(marketFilter !== 'all'))
    chipS.innerHTML = chipHTML(sectorFilter ? marketTitle(sectorFilter) : '全部板块')
    chipS.classList.toggle('on', sectorFilter != null)
    chipS.setAttribute('aria-pressed', String(sectorFilter != null))
    chipS.disabled = !sectors.length
  }

  const row = (symbol: string, hl: [number, number] | null): string => {
    const s = S.symbols.get(symbol)
    // 品种表认得的照常；不认得的（已下架的自选）凑一行占位：价格与涨跌写「—」，退成灰
    const gone = !s && S.live === true
    const html = listRowHTML(factsOf(symbol, s), { price: s?.price ?? null, dec: s?.dec, pct: s?.pct ?? null, meta: s?.macro ? `${symbol} 指数` : `${symbol} 永续`, fav: F.isFavorite(st.symbols, symbol), hl })
    return gone ? html.replace('class="sr"', 'class="sr stale"') : html
  }
  const sectionHTML = (sec: PickerSection): string => {
    const note = moreNote(sec.more)
    return `<section class="mpk-sec" data-kind="${sec.kind}"><div class="mpk-sh">${esc(sec.title)}</div>`
      + `<div class="mpk-rows">${sec.rows.map(r => row(r.symbol, r.hl)).join('')}</div>`
      + (note ? `<div class="mpk-more">${esc(note)}</div>` : '') + `</section>`
  }

  function render(): void {
    if (L.ended) return
    if (sorter?.dragging) { redrawAfterDrag = true; return }
    const catalog = all()
    const f = applyFilter(catalog, marketFilter, sectorFilter)
    // 筛到一半品种表换了，选中的板块已经不在了：退回全部
    if (catalog.length && sectorFilter && !f.sectors.includes(sectorFilter)) { sectorFilter = null; return render() }
    markets = f.markets; sectors = f.sectors
    count.textContent = catalog.length ? countText(catalog) : ''
    paintChips()
    const sections = buildSections(f.list, { query: q, favorites: st.symbols.favorites, recents: st.symbols.recents, known: new Set(S.symbols.keys()) })
    swipes.forEach(s => s.destroy()); swipes = []
    sorter?.destroy(); sorter = null
    visible.clear(); io?.disconnect()
    if (!sections.some(s => s.rows.length)) {
      body.innerHTML = `<div class="mpk-empty">${q.trim() || S.symbols.size ? EMPTY_TEXT : S.live === false ? '品种表没拉到，稍后再试' : '品种表加载中…'}</div>`
      pushStreams()
      return
    }
    body.innerHTML = sections.map(sectionHTML).join('')
    const favList = body.querySelector<HTMLElement>('.mpk-sec[data-kind="favorites"] .mpk-rows')
    if (favList) {
      favList.querySelectorAll<HTMLElement>('.sr').forEach(r => {
        const sym = r.dataset.sym!
        swipes.push(swipeRow(r, { brick: 'flush', fullSwipe: false, trailing: [{ id: 'delete', title: '取消自选', fill: 'var(--danger)', destructive: true, run: () => unstar(sym) }] }))
      })
      sorter = reorderable(favList, {
        item: '.sr',
        onMove(from, to, rows) { F.moveVisible(st.symbols, rows.map(r => r.dataset.sym!), from, to); save(); redrawAfterDrag = true },
        onEnd() { if (redrawAfterDrag) { redrawAfterDrag = false; keepScroll(render) } },
      })
    }
    body.querySelectorAll<HTMLElement>('.sr').forEach(r => io?.observe(r))
  }
  const schedule = L.frame(render)
  /** 重画整张表但不跳：加 / 删自选、拖完排序之后行会挪组，滚动位置留在原处 */
  const keepScroll = (fn: () => void): void => { const y = scroll.scrollTop; fn(); scroll.scrollTop = y }

  function unstar(sym: string): void {
    F.removeFavorite(st.symbols, sym)
    save()
    keepScroll(render)
  }

  // ---------------------------------------------------------------- 只订屏上那几行
  const visible = new Set<string>()
  const pushStreams = L.frame(() => wantStreams('picker', [...visible].map(s => streamName.ticker(s))))
  const io = typeof IntersectionObserver === 'undefined' ? null : new IntersectionObserver(entries => {
    for (const e of entries) {
      const sym = (e.target as HTMLElement).dataset.sym
      if (!sym) continue
      if (e.isIntersecting) visible.add(sym); else visible.delete(sym)
    }
    pushStreams()
  }, { root: scroll, rootMargin: '120px 0px' })
  L.add(() => io?.disconnect())

  // ---------------------------------------------------------------- 输入
  input.addEventListener('input', () => { q = input.value; scroll.scrollTop = 0; render() })
  input.addEventListener('keydown', e => { if (e.key === 'Enter') input.blur() })
  root.querySelector<HTMLElement>('.mpk-clear')!.onclick = () => { input.value = q = ''; scroll.scrollTop = 0; render() }
  root.querySelector<HTMLElement>('.mpk-back')!.onclick = () => { close(); opts.onBack?.(q) }
  // 滚动收键盘、收回划开的行（iOS scrollDismissesKeyboard）
  scroll.addEventListener('touchmove', () => { if (document.activeElement === input) input.blur() }, { passive: true })
  scroll.addEventListener('scroll', () => closeOpenSwipe(), { passive: true })

  // ---------------------------------------------------------------- 筛选：先收键盘，等它退下去（250ms）再弹选项
  function openFilter(kind: 'market' | 'sector'): void {
    input.blur()
    clearTimeout(filterTimer)
    filterTimer = window.setTimeout(L.guard(() => {
      const keys = kind === 'market' ? ['all', ...markets] : ['', ...sectors]
      const sel = kind === 'market' ? marketFilter : sectorFilter ?? ''
      openSheet((sb, sheet) => {
        sb.innerHTML = `<div class="mpk-pick">${keys.map(k => {
          const title = k ? marketTitle(k) : '全部板块'
          return `<button type="button" class="mpk-pick-row${k === sel ? ' here' : ''}" data-k="${esc(k)}"><span>${esc(title)}</span>${k === sel ? icon('check', 16) : ''}</button>`
        }).join('')}</div>`
        sb.addEventListener('click', e => {
          const b = (e.target as HTMLElement).closest<HTMLElement>('.mpk-pick-row'); if (!b) return
          sheet.close()
          const k = b.dataset.k ?? ''
          // 换市场时板块一起回到「全部」（iOS marketFilter didSet）
          if (kind === 'market') { if (k !== marketFilter) { marketFilter = k; sectorFilter = null } }
          else sectorFilter = k || null
          scroll.scrollTop = 0
          render()
        })
      }, { title: kind === 'market' ? '市场' : '板块', detent: 'auto', className: 'mpk-pick-sheet' })
    }), 250)
  }
  chipM.onclick = () => openFilter('market')
  chipS.onclick = () => { if (!chipS.disabled) openFilter('sector') }
  L.add(() => clearTimeout(filterTimer))

  // ---------------------------------------------------------------- 点行
  body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('.m-sw-bricks')) return
    if (swipes.some(s => s.isOpen)) { closeOpenSwipe(); return }
    const star = t.closest<HTMLElement>('[data-star]')
    if (star) {
      const sym = star.dataset.star!
      const s = S.symbols.get(sym)
      const added = F.toggleFavorite(st.symbols, sym, st.favoritesGroup || null, { kind: s?.kind, base: splitSymbol(sym).base })
      save()
      keepScroll(render)
      if (added) opts.onStarred?.(sym)
      return
    }
    const r = t.closest<HTMLElement>('.sr')
    if (r) { input.blur(); close(); opts.onPick(r.dataset.sym!) }
  })

  // ---------------------------------------------------------------- 行情：一帧里只按最后的价补一次行尾
  let pending = new Set<string>()
  const flush = L.frame(() => {
    const syms = pending; pending = new Set()
    syms.forEach(patch)
  })
  L.add(on(e => {
    if (e.type === 'universe') schedule()
    else if (e.type === 'ticker' && visible.has(e.symbol)) { pending.add(e.symbol); flush() }
  }))
  function patch(sym: string): void {
    body.querySelectorAll<HTMLElement>(`.sr[data-sym="${CSS.escape(sym)}"]`).forEach(r => {
      const tmp = document.createElement('div')
      tmp.innerHTML = row(sym, null)
      r.querySelector('.sr-right')?.replaceWith(tmp.querySelector('.sr-right')!)
    })
  }

  const vv = window.visualViewport
  L.listen(vv, 'resize', fitViewport)
  L.listen(vv, 'scroll', fitViewport)
  fitViewport()
  const onFg = (): void => schedule()
  hooks.onForeground.push(onFg)
  L.add(() => { const i = hooks.onForeground.indexOf(onFg); if (i >= 0) hooks.onForeground.splice(i, 1) })
  L.listen(window, 'hashchange', () => close())

  const me = { close }
  function close(): void {
    if (!L.end()) return
    if (current === me) current = null
    input.blur()
    swipes.forEach(s => s.destroy()); swipes = []
    sorter?.destroy(); sorter = null
    wantStreams('picker', [])
    root.classList.remove('in')
    setTimeout(() => root.remove(), 220)
  }
  current = me
  // 系统返回只退这一层（回到搜索页）；壳换页时由壳统一收掉
  L.add(registerOverlay(() => { if (current === me) { close(); opts.onBack?.(q) } }))
  render()
  requestAnimationFrame(() => root.classList.add('in'))
  void ensureUniverse().then(L.guard(schedule), () => {})
}

export function closePicker(): void { current?.close() }

/** 返回箭头：18 的框、1.7 描边、ink2（SymbolPickerView.header 的 Chevron） */
const BACK = '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11.5 3.5 6 9l5.5 5.5"/></svg>'
