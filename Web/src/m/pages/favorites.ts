/* 手机网页版 · 自选页（照 iOS Symbols/FavoritesView.swift「琉璃」版）
 *
 * 头部只有一行：分类胶囊条（能横滚）+ 放大镜圆片 +「…」圆片；「…」里是「调整顺序」和「删除当前分类」。
 * 列表永远按自选顺序、不排序；行直接长在琉璃底上（徽章 33 · 名字 / 成交额 · 价格 + 涨跌药丸）。
 * 左滑两颗砖：移到分类、取消自选；长按弹预览卡 + 菜单：打开 / 调整顺序 / 移到分类 › / 取消自选（./symbolPreview）。
 * 滚动位置按分类各记一份：页内切分类回顶；切走再回来回到这一类原来那一行；
 * 从这一页点进图的那一只、点的时候并不露着（滚远了），回来直接把它摆到屏幕中间（iOS restoreScrollAnchor）。
 * 「调整顺序」时价格冻住、点行不开图、长按拖动排序。删自选没有二次确认，给五秒撤销。
 * 加自选只在搜索结果行的星上（一个动作一个入口）。
 */
import '../styles/favorites.css'
import { st, save, subscribe } from '../app/store'
import { openSymbol, hooks, trackScroll, restoreScroll, type PageHandle } from '../app/shell'
import { icon } from '../ui/icons'
import { openMenu, openSheet, type MenuItem } from '../ui/sheet'
import { swipeRow, closeOpenSwipe, type SwipeHandle } from '../ui/swipeDelete'
import { reorderable, longPress } from '../ui/reorder'
import { toast } from '../ui/toast'
import { S, on, streamName } from '../../market'
import * as F from '../model/favorites'
import { esc } from '../model/rowText'
import { factsOf, liuliRowHTML, patchLiuli, type LiuliData } from '../model/rowHTML'
import { openSearch } from './search'
import { openPreviewMenu } from './symbolPreview'
import { ensureUniverse, takeOpenParam, wantStreams } from './_streams'

/** 琉璃底（光斑 + 冲淡 + 颗粒）：自选页和板块页共用 */
export function backdropHTML(): string {
  return `<div class="lg-bg" aria-hidden="true"><i class="lg-blob b1"></i><i class="lg-blob b2"></i><i class="lg-blob b3"></i><i class="lg-wash"></i><i class="lg-grain"></i></div>`
}

export function initFavorites(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'liuli')
  root.innerHTML = backdropHTML() + `
    <header class="fav-head">
      <div class="fav-cats" role="tablist" aria-label="自选分类"><div class="fav-rail"></div></div>
      <button type="button" class="fav-disc fav-search" aria-label="搜索">${icon('search', 16)}</button>
      <button type="button" class="fav-done" hidden>完成</button>
      <button type="button" class="fav-disc fav-more" aria-label="更多">${icon('more', 17)}</button>
    </header>
    <div class="fav-scroll"><div class="fav-list" role="list"></div><div class="fav-empty" hidden></div></div>`
  const cats = root.querySelector<HTMLElement>('.fav-cats')!
  const rail = root.querySelector<HTMLElement>('.fav-rail')!
  const scroll = root.querySelector<HTMLElement>('.fav-scroll')!
  const list = root.querySelector<HTMLElement>('.fav-list')!
  const empty = root.querySelector<HTMLElement>('.fav-empty')!
  const searchBtn = root.querySelector<HTMLButtonElement>('.fav-search')!
  const doneBtn = root.querySelector<HTMLButtonElement>('.fav-done')!
  const moreBtn = root.querySelector<HTMLButtonElement>('.fav-more')!

  let editing = false
  let active = false
  let shown: string[] = []
  let frozen = new Map<string, LiuliData>()
  const swipes: SwipeHandle[] = []
  const unpress: (() => void)[] = []
  let openSwipe = (): boolean => swipes.some(s => s.isOpen)

  if (F.seedDefaults(st.symbols, null)) save()

  const current = (): string | null => F.group(st.symbols, st.favoritesGroup || null)
  /** 这一类的滚动位置记在哪个键上（按分类各一份：A 类的位置套到 B 类上就是乱滚） */
  const scrollKey = (id: string | null = current()): string => 'fav.' + (id ?? '-')
  // 旧版只记一份整页的位置：交给当前这一类，别让升级后第一次回来停在表头
  if (st.scroll['favorites.list'] != null) {
    if (st.scroll[scrollKey()] == null) st.scroll[scrollKey()] = st.scroll['favorites.list']
    delete st.scroll['favorites.list']
  }
  /** 刚从这一页点进图的那一只，以及点的时候它露没露着 */
  let opened: { sym: string; visible: boolean } | null = null
  const dataOf = (sym: string): LiuliData => {
    if (editing && frozen.has(sym)) return frozen.get(sym)!
    const s = S.symbols.get(sym)
    const gone = S.live === true && !s
    return { price: s?.price ?? null, dec: s?.dec, pct: gone ? null : s?.pct ?? null, vol: gone ? null : s?.vol ?? null, gone }
  }

  // ---------------------------------------------------------------- 头部
  function renderHead(): void {
    const groups = st.symbols.groups
    cats.hidden = !groups.length
    const sel = current()
    rail.innerHTML = groups.map(g => `<button type="button" role="tab" class="fav-cat${g.id === sel ? ' on' : ''}" data-group="${esc(g.id)}" aria-selected="${g.id === sel}">${esc(g.name)}</button>`).join('')
    searchBtn.hidden = editing
    doneBtn.hidden = !editing
    requestAnimationFrame(() => centerSelected(false))
  }
  function centerSelected(smooth: boolean): void {
    const on = rail.querySelector<HTMLElement>('.fav-cat.on'); if (!on) return
    const left = on.offsetLeft - (cats.clientWidth - on.offsetWidth) / 2
    cats.scrollTo({ left: Math.max(0, left), behavior: smooth ? 'smooth' : 'auto' })
  }
  rail.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('.fav-cat'); if (!b) return
    if (b.dataset.group === current()) return
    closeOpenSwipe()
    st.favoritesGroup = b.dataset.group!
    save()
    rail.querySelectorAll('.fav-cat').forEach(x => { const on = x === b; x.classList.toggle('on', on); x.setAttribute('aria-selected', String(on)) })
    centerSelected(true)
    // 页内换一类从头看起：旧那一类的位置已经记在它自己的键上，接着记新这一类的
    retrack()
    opened = null
    renderList()
    scroll.scrollTop = 0
  })
  searchBtn.onclick = () => openSearch({
    onStarred: sym => { const g = st.symbols.groupForSymbol[F.key(sym)]; if (g && g !== st.favoritesGroup) { st.favoritesGroup = g; save() } },
    onClose: () => { if (active) render() },
  })
  doneBtn.onclick = () => setEditing(false)
  moreBtn.onclick = () => {
    const deletable = st.symbols.groups.length > 1 ? st.symbols.groups.find(g => g.id === current()) : undefined
    const items: (MenuItem | null)[] = [
      { title: editing ? '完成调整' : '调整顺序', icon: 'adjust', run: () => setEditing(!editing) },
      deletable ? { title: '删除当前分类', icon: 'trash', destructive: true, run: () => {
        F.deleteGroup(st.symbols, deletable.id, current())
        delete st.scroll[scrollKey(deletable.id)]
        st.favoritesGroup = F.group(st.symbols, null) ?? ''
        save(); retrack(); render(); scroll.scrollTop = 0
      } } : null,
    ]
    openMenu(moreBtn, items.filter(Boolean))
  }

  function setEditing(v: boolean): void {
    if (editing === v) return
    editing = v
    closeOpenSwipe()
    frozen = new Map()
    if (v) for (const s of shown) frozen.set(s, dataOf(s))
    root.classList.toggle('editing', v)
    renderHead()
    renderList()
  }

  // ---------------------------------------------------------------- 列表
  function renderList(): void {
    swipes.splice(0).forEach(s => s.destroy())
    unpress.splice(0).forEach(f => f())
    shown = F.visible(st.symbols, current())
    if (!shown.length) {
      list.innerHTML = ''
      empty.hidden = false
      empty.innerHTML = `<div class="fav-empty-in"><span class="fav-empty-mark">${icon('plus', 20)}</span><div class="fav-empty-title">还没有自选</div>
        <button type="button" class="fav-add">添加品种</button></div>`
      empty.querySelector<HTMLElement>('.fav-add')!.onclick = () => searchBtn.click()
      if (editing) setEditing(false)
    } else {
      empty.hidden = true
      list.innerHTML = shown.map((sym, i) => liuliRowHTML(factsOf(sym, S.symbols.get(sym)), dataOf(sym), i === 0)).join('')
      list.querySelectorAll<HTMLElement>('.lr').forEach(row => {
        const sym = row.dataset.sym!
        if (!editing) {
          swipes.push(swipeRow(row, {
            brick: 'flush', fullSwipe: false,
            trailing: [
              { id: 'move', title: '移到分类', fill: 'var(--accent)', run: () => chooseCategory([sym]) },
              { id: 'delete', title: '取消自选', fill: 'var(--danger)', destructive: true, run: () => remove([sym]) },
            ],
          }))
          unpress.push(longPress(row, () => rowMenu(row, sym)))
        }
      })
    }
    wantStreams('favorites', active ? shown.map(s => streamName.ticker(s)) : [])
  }
  function render(): void { renderHead(); renderList() }

  reorderable(list, {
    item: '.lr',
    enabled: () => editing,
    onMove(from, to) {
      F.moveVisible(st.symbols, shown, from, to)
      save()
      renderList()
    },
  })

  list.addEventListener('click', e => {
    const row = (e.target as HTMLElement).closest<HTMLElement>('.lr'); if (!row) return
    if ((e.target as HTMLElement).closest('.m-sw-bricks')) return
    if (openSwipe()) { closeOpenSwipe(); return }
    if (editing) return
    open(row.dataset.sym!, row)
  })

  /** 进图：先记下这一只、以及它这一刻是不是整行露在列表可视区里 */
  function open(sym: string, row: HTMLElement | null): void {
    const r = row?.getBoundingClientRect(), v = scroll.getBoundingClientRect()
    opened = { sym, visible: !!r && r.top >= v.top - 1 && r.bottom <= v.bottom + 1 }
    openSymbol(sym)
  }

  /** 长按：预览卡 + 菜单（iOS contextMenu：菜单项不带图标；「移到分类」是一层子菜单，列已有分类 + 还没开的预设） */
  function rowMenu(row: HTMLElement, sym: string): void {
    openPreviewMenu(row, { symbol: sym, recent: true, gone: () => !!dataOf(sym).gone }, [
      { title: '打开', run: () => open(sym, row) },
      { title: '调整顺序', run: () => setEditing(true) },
      {
        title: '移到分类', run: () => chooseCategory([sym]),
        submenu: () => F.moveTargets(st.symbols).map(n => {
          const g = st.symbols.groups.find(x => x.name === n)
          return { title: n, checked: !!g && st.symbols.groupForSymbol[F.key(sym)] === g.id, run: () => assign([sym], n) }
        }),
      },
      { title: '取消自选', destructive: true, run: () => remove([sym]) },
    ])
  }

  /** 移到分类：半屏列出已有分类 + 还没开的预设；五秒内可撤销 */
  function chooseCategory(symbols: string[]): void {
    closeOpenSwipe()
    const targets = F.moveTargets(st.symbols)
    openSheet((body, sheet) => {
      body.innerHTML = `<div class="fav-move">${targets.map(n => {
        const g = st.symbols.groups.find(x => x.name === n)
        const here = !!g && symbols.every(s => st.symbols.groupForSymbol[F.key(s)] === g.id)
        return `<button type="button" class="fav-move-row${here ? ' here' : ''}" data-name="${esc(n)}"><span>${esc(n)}</span>${here ? icon('check', 16) : ''}</button>`
      }).join('')}</div>`
      body.addEventListener('click', e => {
        const b = (e.target as HTMLElement).closest<HTMLElement>('.fav-move-row'); if (!b) return
        sheet.close()
        assign(symbols, b.dataset.name!)
      })
    }, { title: '移到分类', detent: 'auto', className: 'fav-move-sheet' })
  }
  function assign(symbols: string[], name: string): void {
    const p = st.symbols
    const existed = p.groups.some(g => g.name === name)
    const target = p.groups.find(g => g.name === name)?.id
    const before = symbols.map(s => F.snapshot(p, s)).filter((x): x is F.Snapshot => !!x && (target == null || x.group !== target))
    if (!before.length) return
    const id = F.assignToCategory(p, before.map(b => b.symbol), name)
    if (!id) return
    save(); render()
    toast(`已移到「${name}」`, {
      title: '撤销', run: () => {
        before.forEach(b => F.assign(p, b.symbol, b.group))
        if (!existed && !Object.values(p.groupForSymbol).includes(id)) F.deleteGroup(p, id, current())
        save(); render()
      },
    })
  }
  /** 取消自选：先删，给五秒撤销 */
  function remove(symbols: string[]): void {
    const p = st.symbols
    const snaps = symbols.map(s => F.snapshot(p, s)).filter((x): x is F.Snapshot => !!x)
    if (!snaps.length) return
    symbols.forEach(s => F.removeFavorite(p, s))
    save(); renderList()
    toast('已移除', { title: '撤销', run: () => { F.restore(p, snaps, current()); save(); renderList() } })
  }

  // ---------------------------------------------------------------- 行情
  let pending = new Set<string>(), raf = 0
  const flush = (): void => {
    raf = 0
    for (const sym of pending) {
      const row = list.querySelector(`.lr[data-sym="${CSS.escape(sym)}"]`)
      if (row) patchLiuli(row, dataOf(sym))
    }
    pending = new Set()
  }
  on(e => {
    if (!active) return
    if (e.type === 'universe') { renderList(); return }
    if (e.type !== 'ticker' || editing || !shown.includes(e.symbol)) return
    pending.add(e.symbol)
    if (!raf) raf = requestAnimationFrame(flush)
  })

  let untrack = trackScroll(scroll, scrollKey())
  function retrack(): void { untrack(); untrack = trackScroll(scroll, scrollKey()) }
  scroll.addEventListener('scroll', () => closeOpenSwipe(), { passive: true })
  hooks.onTheme.push(() => { if (active) renderList() })
  hooks.onForeground.push(() => { if (active) renderList() })
  // 推送断满 5 秒（app/linkGrace.ts 置 st.stale）整表价格变灰，接上立刻复原（iOS QuoteBook 同一条规矩）
  subscribe(() => root.classList.toggle('stale', st.stale))

  // 验收截图用：?open=search 进来直接开搜索页
  if (takeOpenParam(['search'])) requestAnimationFrame(() => searchBtn.click())

  /** 回到这一页停在哪：刚点进图的那一只走的时候不露着、而且还在表里 → 摆到屏幕中间；否则回到这一类原来那一行 */
  function landing(): void {
    const o = opened
    opened = null
    if (o && !o.visible && shown.includes(o.sym)) {
      const row = list.querySelector<HTMLElement>(`.lr[data-sym="${CSS.escape(o.sym)}"]`)
      if (row) {
        const r = row.getBoundingClientRect(), v = scroll.getBoundingClientRect()
        scroll.scrollTop = Math.max(0, scroll.scrollTop + r.top - v.top - (scroll.clientHeight - r.height) / 2)
        return
      }
    }
    restoreScroll(scroll, scrollKey())
  }

  return {
    show() {
      active = true
      root.classList.toggle('stale', st.stale)
      retrack()
      render()
      landing()
      void ensureUniverse().then(() => { if (active) renderList() })
    },
    hide() {
      active = false
      if (editing) setEditing(false)
      closeOpenSwipe()
      wantStreams('favorites', [])
    },
    reselect() {
      if (editing) { setEditing(false); return }
      scroll.scrollTo({ top: 0, behavior: 'smooth' })
    },
  }
}
