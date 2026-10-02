/* 手机网页版 · 板块页（照 iOS Sector/SectorPage.swift、SectorBoardList.swift、SectorSymbolList.swift）
 *
 * 第一层：页头「板块」+ 规模一行（N 个板块 · M 个品种）+ 右侧市场分段（加密 / 美股）；
 *         有 5 日数据时下面一排「今日 / 5 日」分段；然后是普通板块列表（图标 32 · 名字 · x/n 跑赢大盘 · 涨跌）。
 * 第二层：点一个板块压上来它的品种列表——视觉照抄自选页的琉璃行；头部是返回圆片、板块图标 38、
 *         名字 + 「x/n 跑赢大盘」、右侧板块涨跌。口径全部在 src/sectors/aggregate.ts（和 iOS 一致），不给选。
 * 两层铺同一张琉璃底，换层只是一层淡入淡出；退回第一层时回到原来那一行（隐藏的层会丢滚动位置，按记下的接回来）。
 * 第二层的行长按：预览卡 + 菜单（打开 · 加入自选 / 取消自选），卡上价与涨跌照这一行写的（看 5 日时就是 5 日）。
 */
import '../styles/favorites.css'
import '../styles/sectors.css'
import { st, save } from '../app/store'
import { openSymbol, hooks, trackScroll, restoreScroll, type PageHandle } from '../app/shell'
import { icon } from '../ui/icons'
import { longPress } from '../ui/reorder'
import { toast } from '../ui/toast'
import { registerTerms, termHTML } from '../ui/hint'
import { S, on, streamName } from '../../market'
import {
  EMPTY_HISTORY, boardOrder, catalog, hasEligible, resolveWindow, stats, subtitle, symbolRows, windowReturn,
  type SectorMarket, type SectorStat, type SectorWindow,
} from '../../sectors/aggregate'
import { applyLive, feed, seedFromUniverse, startFeed, stopFeed } from '../../sectors/feed'
import { history, startHistory, stopHistory } from '../../sectors/history'
import * as F from '../model/favorites'
import { sectorIconHTML } from '../model/badge'
import { changePercentText, esc, MISSING, textIsUp } from '../model/rowText'
import { factsOf, liuliRowHTML, patchLiuli, type LiuliData } from '../model/rowHTML'
import { coveredCount, drillDecision } from '../model/sectorView'
import { backdropHTML } from './favorites'
import { ensureUniverse, wantStreams } from './_streams'
import { openPreviewMenu } from './symbolPreview'

registerTerms([
  { id: 'outperform', title: '跑赢大盘', body: '这段时间里，板块成员跑赢全市场等权平均的有几只。\n分母是有行情的成员数；不到 3 只有行情的板块不算，排在最后。' },
  { id: 'frontier', title: '领涨', body: '跑赢大盘，而且涨幅排进全市场前 10% 的成员。' },
  { id: 'sectorChange', title: '板块涨跌', body: '板块成员涨跌幅的中位数，不会被一两只暴涨暴跌的带偏。' },
])

const MARKETS: { id: SectorMarket; title: string }[] = [{ id: 'crypto', title: '加密' }, { id: 'us', title: '美股' }]
const WINDOWS: { id: SectorWindow; title: string }[] = [{ id: 'today', title: '今日' }, { id: 'd5', title: '5 日' }]

function segHTML(kind: string, opts: { id: string; title: string }[], sel: string): string {
  return `<div class="m-seg" role="group" data-seg="${kind}">${opts.map(o =>
    `<button type="button" class="m-seg-opt${o.id === sel ? ' on' : ''}" data-v="${o.id}" aria-pressed="${o.id === sel}" data-id="sector.${kind}.${o.id}">${esc(o.title)}</button>`).join('')}</div>`
}
const dirOf = (pct: number): string => { const t = changePercentText(pct); return t === MISSING ? '' : textIsUp(t) ? 'up' : 'down' }

export function initSectors(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'liuli')
  root.innerHTML = backdropHTML() + `
    <div class="sec-layer sec-boards">
      <header class="sec-head"><div class="sec-title"><h1>板块</h1><span class="sec-scale num"></span></div><div class="sec-market"></div></header>
      <div class="sec-win"></div>
      <div class="sec-scroll sec-board-scroll"><div class="sec-board-list" role="list"></div><button type="button" class="sec-empty" hidden><b>暂无行情</b><span>点此重试</span></button></div>
    </div>
    <div class="sec-layer sec-drill" hidden>
      <header class="sec-dhead"></header>
      <div class="sec-scroll sec-drill-scroll"><div class="sec-drill-list" role="list"></div><div class="sec-drill-empty" hidden>这个板块暂时没有行情</div></div>
    </div>`
  const boardsLayer = root.querySelector<HTMLElement>('.sec-boards')!
  const drillLayer = root.querySelector<HTMLElement>('.sec-drill')!
  const scaleEl = root.querySelector<HTMLElement>('.sec-scale')!
  const marketEl = root.querySelector<HTMLElement>('.sec-market')!
  const winEl = root.querySelector<HTMLElement>('.sec-win')!
  const boardScroll = root.querySelector<HTMLElement>('.sec-board-scroll')!
  const boardList = root.querySelector<HTMLElement>('.sec-board-list')!
  const emptyBtn = root.querySelector<HTMLButtonElement>('.sec-empty')!
  const dhead = root.querySelector<HTMLElement>('.sec-dhead')!
  const drillScroll = root.querySelector<HTMLElement>('.sec-drill-scroll')!
  const drillList = root.querySelector<HTMLElement>('.sec-drill-list')!
  const drillEmpty = root.querySelector<HTMLElement>('.sec-drill-empty')!

  let active = false
  let route: string | null = null
  let window: SectorWindow = 'today'
  let boards: SectorStat[] = []
  let shownSyms: string[] = []
  const baseOf = new Map<string, string>()
  const unpress: (() => void)[] = []

  const market = (): SectorMarket => st.sectorMarket === 'us' ? 'us' : 'crypto'
  const membersOf = (id: string): string[] => {
    const d = catalog.sector(id)
    if (d) return d.members
    return feed.buckets[market()].find(b => b.id === id)?.members ?? []
  }
  const nameOf = (id: string): string => catalog.sector(id)?.name ?? feed.buckets[market()].find(b => b.id === id)?.name ?? id
  const symbolFor = (base: string): string => feed.quotes.get(base)?.symbol ?? base + 'USDT'

  function compute(): boolean {
    const m = market(), buckets = feed.buckets[m]
    const hasD5 = hasEligible(m, feed.quotes, 'd5', history.held)
    window = resolveWindow(st.sectorWindow === 'd5' ? 'd5' : 'today', hasD5).window
    boards = boardOrder(stats(m, feed.quotes, buckets, window, window === 'today' ? EMPTY_HISTORY : history.held))
    return hasD5
  }

  // ---------------------------------------------------------------- 第一层
  function renderBoards(): void {
    const hasD5 = compute()
    marketEl.innerHTML = segHTML('market', MARKETS, market())
    winEl.innerHTML = hasD5 ? segHTML('window', WINDOWS, window) : ''
    winEl.hidden = !hasD5
    // 品种数照 iOS：目录板块与兜底桶去重后、这段窗口上真算得出收益的那些（5 日档缺收盘价的不算）
    const m = market()
    const covered = coveredCount(m, feed.quotes, feed.buckets[m], window, window === 'today' ? EMPTY_HISTORY : history.held)
    scaleEl.textContent = feed.quotes.size && covered > 0 ? `${boards.length} 个板块 · ${covered} 个品种` : ''
    const failed = !boards.length && (feed.ok === false || (S.live === false && !feed.quotes.size))
    emptyBtn.hidden = !failed
    boardList.innerHTML = boards.map((b, i) => {
      const sub = subtitle(b)
      return `<div class="sec-row${i === 0 ? ' first' : ''}" role="button" tabindex="0" data-sec="${esc(b.id)}" data-id="sector.row.${esc(b.id)}">`
        + `${sectorIconHTML(b.id, 32)}<div class="sec-name"><span class="sec-n">${esc(b.name)}</span>${sub ? `<span class="sec-sub num">${esc(sub)}</span>` : ''}</div>`
        + `<span class="sec-pct num ${dirOf(b.pct)}">${esc(changePercentText(b.pct))}</span></div>`
    }).join('')
  }

  marketEl.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('.m-seg-opt'); if (!b) return
    const v = b.dataset.v === 'us' ? 'us' : 'crypto'
    if (v === market()) return
    st.sectorMarket = v; save()
    route = null
    boardScroll.scrollTop = 0
    render()
  })
  winEl.addEventListener('click', e => {
    const b = (e.target as HTMLElement).closest<HTMLElement>('.m-seg-opt'); if (!b) return
    const v: SectorWindow = b.dataset.v === 'd5' ? 'd5' : 'today'
    if (v === st.sectorWindow) return
    st.sectorWindow = v; save()
    render()
  })
  boardList.addEventListener('click', e => {
    const r = (e.target as HTMLElement).closest<HTMLElement>('.sec-row'); if (!r) return
    push(r.dataset.sec!)
  })
  emptyBtn.onclick = () => { void ensureUniverse(); stopFeed(); startFeed(render) }

  // ---------------------------------------------------------------- 第二层
  function push(id: string): void {
    route = id
    boardsLayer.classList.remove('popped')
    render()
    // 新钻进的板块从头看起（render 之后再归零：隐藏时归零不算数）
    drillScroll.scrollTop = 0
    st.scroll['sectors.drill'] = 0
  }
  function pop(): void {
    if (!route) return
    route = null
    boardsLayer.classList.add('popped')
    render()
    // 第一层藏起来时浏览器把它的滚动位置丢了：按记下的接回来
    restoreScroll(boardScroll, 'sectors.boards')
  }
  boardsLayer.addEventListener('animationend', () => boardsLayer.classList.remove('popped'))

  function drillData(sym: string): LiuliData {
    const base = baseOf.get(sym)
    const q = base ? feed.quotes.get(base) : undefined
    const s = S.symbols.get(sym)
    const pct = q ? windowReturn(q, window, history.held.closes.get(q.base)) : null
    return {
      price: s?.price ?? (q && Number.isFinite(q.price) ? q.price : null), dec: s?.dec,
      pct: pct != null && Number.isFinite(pct) ? pct : null,
      vol: q && Number.isFinite(q.quoteVolume) ? q.quoteVolume : null,
    }
  }

  function renderDrill(): void {
    unpress.splice(0).forEach(f => f())
    const id = route!
    const stat = boards.find(b => b.id === id)
    const sub = stat ? subtitle(stat) : ''
    dhead.innerHTML = `<button type="button" class="sec-back" aria-label="返回" data-id="sector.back">${icon('chevronLeft', 18)}</button>`
      + `${sectorIconHTML(id, 38)}<div class="sec-dtitle"><h1>${esc(nameOf(id))}</h1>${sub ? `<span class="sec-dsub num">${esc(sub)}${termHTML('outperform')}</span>` : ''}</div>`
      + (stat ? `<span class="sec-dpct num ${dirOf(stat.pct)}">${esc(changePercentText(stat.pct))}</span>` : '')
    dhead.querySelector<HTMLElement>('.sec-back')!.onclick = pop
    const rows = symbolRows(membersOf(id), feed.quotes, stat?.frontier ?? [], window, history.held)
    baseOf.clear()
    shownSyms = []
    const html: string[] = []
    rows.forEach((r, i) => {
      const sym = symbolFor(r.base)
      baseOf.set(sym, r.base)
      shownSyms.push(sym)
      const d = drillData(sym)
      d.extra = r.isFrontier ? `<span class="lr-lead up"> · 领涨</span>` : ''
      html.push(liuliRowHTML(factsOf(sym, S.symbols.get(sym)), d, i === 0))
    })
    drillList.innerHTML = html.join('')
    drillEmpty.hidden = rows.length > 0 || !feed.quotes.size
    drillList.querySelectorAll<HTMLElement>('.lr').forEach(row => {
      const sym = row.dataset.sym!
      unpress.push(longPress(row, () => rowMenu(row, sym)))
    })
  }

  /** 长按：和自选页同一张预览卡，菜单是它的子集——「打开」加一颗收藏开关（iOS contextMenu 菜单项不带图标）。
   *  卡上价与涨跌照这一行写的（看 5 日时这一行写的就是 5 日），成交额是 24 小时那份；高低价不是这一口径，不摆 */
  function rowMenu(row: HTMLElement, sym: string): void {
    const fav = F.isFavorite(st.symbols, sym)
    openPreviewMenu(row, {
      symbol: sym,
      quote: () => { const d = drillData(sym); return { price: d.price, pct: d.pct, vol: d.vol, hiLo: window === 'today' } },
      gone: () => S.live === true && !S.symbols.has(sym),
    }, [
      { title: '打开', run: () => openSymbol(sym) },
      fav
        ? { title: '取消自选', destructive: true, run: () => {
          const snap = F.snapshot(st.symbols, sym)
          F.removeFavorite(st.symbols, sym); save()
          toast('已移除', { title: '撤销', run: () => { if (snap) { F.restore(st.symbols, [snap], st.favoritesGroup || null); save() } } })
        } }
        : { title: '加入自选', run: () => {
          const s = S.symbols.get(sym)
          F.addFavorite(st.symbols, sym, st.favoritesGroup || null, { kind: s?.kind, base: baseOf.get(sym) })
          save(); toast('已加入自选')
        } },
    ])
  }

  drillList.addEventListener('click', e => {
    const row = (e.target as HTMLElement).closest<HTMLElement>('.lr'); if (!row) return
    const sym = row.dataset.sym!
    if (S.symbols.size && !S.symbols.has(sym)) return
    openSymbol(sym)
  })

  // 左沿右滑返回（iOS 导航栈的边缘手势）
  let edge: { x: number; y: number; id: number } | null = null
  drillLayer.addEventListener('pointerdown', e => { if (e.clientX < 24) edge = { x: e.clientX, y: e.clientY, id: e.pointerId } })
  drillLayer.addEventListener('pointerup', e => {
    if (edge && e.pointerId === edge.id && e.clientX - edge.x > 70 && Math.abs(e.clientY - edge.y) < 60) pop()
    edge = null
  })

  // ---------------------------------------------------------------- 总装
  function render(): void {
    if (!active) return
    seedFromUniverse()
    renderBoards()
    // 钻进去的板块这一帧找不到：只有确认它没了（目录不认、兜底桶也没有、别的板块照常算得出）才退回列表，
    // 其余只是行情还没到，留在原地等（照 iOS SectorDrillDecision）
    if (route != null && drillDecision(route, boards, feed.buckets[market()]) === 'pop') route = null
    const drilling = route != null
    boardsLayer.hidden = drilling
    drillLayer.hidden = !drilling
    if (drilling) renderDrill()
    else { unpress.splice(0).forEach(f => f()); shownSyms = [] }
    wantStreams('sectors', shownSyms.filter(s => S.symbols.has(s)).map(s => streamName.ticker(s)))
  }

  let pending = new Set<string>(), raf = 0
  on(e => {
    if (!active) return
    if (e.type === 'universe') { render(); return }
    if (e.type !== 'ticker' || !route || !baseOf.has(e.symbol)) return
    pending.add(e.symbol)
    if (!raf) raf = requestAnimationFrame(() => {
      raf = 0
      applyLive(pending)
      for (const sym of pending) {
        const row = drillList.querySelector(`.lr[data-sym="${CSS.escape(sym)}"]`)
        if (row) patchLiuli(row, drillData(sym))
      }
      pending = new Set()
    })
  })

  trackScroll(boardScroll, 'sectors.boards')
  trackScroll(drillScroll, 'sectors.drill')
  hooks.onTheme.push(() => { if (active) render() })
  hooks.onForeground.push(() => { if (active) render() })

  return {
    show() {
      active = true
      render()
      restoreScroll(boardScroll, 'sectors.boards')
      if (route) restoreScroll(drillScroll, 'sectors.drill')
      startFeed(render)
      startHistory(render)
      void ensureUniverse().then(() => { if (active) render() })
    },
    hide() {
      active = false
      stopFeed(); stopHistory()
      wantStreams('sectors', [])
    },
    reselect() {
      if (route) { pop(); return }
      boardScroll.scrollTo({ top: 0, behavior: 'smooth' })
    },
  }
}
