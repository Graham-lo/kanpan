/* Hkline 手机网页版 · 壳（照 iOS Main/MainScreen.swift 的 tab 切换与 Main/TabBar.swift）
 *
 * - 四个整页 <section class="page" id="page-xxx">，hash 路由 #chart #favorites #sectors #me，与底栏四格一一对应。
 * - 页面合同见 ./README.md：每页 initXxx(root) → { show(); hide(); reselect?() }，由 main.ts 懒加载后 registerPage。
 * - 主题：data-theme（auto 跟系统，系统切深浅时跟着换）/ data-skin / data-updown，外加 meta theme-color。
 * - 现场：当前页、品种、滚动位置随时落盘，冷启动回到原地。
 * - 前台：切后台回来发 onForeground（行情 WS 由 market/stream.ts 自己在 visibilitychange 里重连，
 *   页面在这里补拉 REST、刷新列表）。
 */
import { st, save, persistQuiet, resolvedTheme, PAGES, type PageId } from './store'
import { glyph, type GlyphName } from '../ui/icons'
import { closeAllSheets } from '../ui/sheet'
import { closeOpenSwipe } from '../ui/swipeDelete'
import { el } from '../ui/dom'

/** 一页对壳的承诺 */
export interface PageHandle {
  /** 切到这一页（每次都调；首次在 init 之后立刻调） */
  show(): void
  /** 离开这一页 */
  hide(): void
  /** 已经站在这一页又点了一次底栏那一格：回到这一页的根（板块页下钻两层时是唯一的出口） */
  reselect?(): void
}

const TAB_TITLE: Record<PageId, string> = { chart: '图表', favorites: '自选', sectors: '板块分类', me: '我的' }
const TAB_GLYPH: Record<PageId, GlyphName> = { chart: 'chart', favorites: 'favorites', sectors: 'sectors', me: 'me' }

/** 各处挂进来的回调（数组，谁都可以 push；返回值不用） */
export const hooks = {
  /** 皮肤 / 深浅 / 涨跌色换了（画布要重画的在这里重取颜色） */
  onTheme: [] as (() => void)[],
  /** 回到前台（visibilitychange → visible，或从 bfcache 回来） */
  onForeground: [] as (() => void)[],
  /** 切到后台 */
  onBackground: [] as (() => void)[],
  /** 换页之后（参数：新页、旧页） */
  onPage: [] as ((page: PageId, prev: PageId) => void)[],
  /** 换品种之后（openSymbol 调用） */
  onSymbol: [] as ((symbol: string) => void)[],
  /** 同步把云端的值装进了 st 之后（参数：改了哪几块；皮肤已由 applyTheme 处理，页面各自按需重画）。
   *  同一时刻 window 上也会发一个 `hkline:sync` 事件，detail 同参数 */
  onSync: [] as ((c: SyncChange) => void)[],
}

/** 同步装进来的改动：settings = 改了的设置根（prefs 字段名） */
export interface SyncChange { settings: string[]; favorites: boolean; alerts: boolean }

const pages = new Map<PageId, PageHandle>()
/** 页还没注册时的挂起调用：注册时补 show */
let appRoot: HTMLElement | null = null
let tabbar: HTMLElement | null = null
let shown: PageId | null = null

/** 图表页的「来路」：从自选 / 板块点进来时记着，图表页顶栏据此画返回；自己点底栏就作废 */
export const nav = { origin: null as PageId | null }

export const pageRoot = (id: PageId): HTMLElement => document.getElementById('page-' + id)!
export const currentPage = (): PageId => st.page

// ───────── 主题 ─────────

let mq: MediaQueryList | null = null
export function applyTheme(): void {
  const r = document.documentElement
  const theme = resolvedTheme()
  const changed = r.dataset.theme !== theme || r.dataset.skin !== st.skin || r.dataset.updown !== (st.redUp ? 'red-up' : 'green-up')
  r.dataset.theme = theme
  r.dataset.skin = st.skin
  r.dataset.updown = st.redUp ? 'red-up' : 'green-up'
  // 浏览器地址栏 / PWA 状态栏的底色跟页面底色
  const app = getComputedStyle(r).getPropertyValue('--app').trim()
  let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]')
  if (!meta) { meta = document.createElement('meta'); meta.name = 'theme-color'; document.head.appendChild(meta) }
  if (app) meta.content = app
  // 状态栏字色（只在加到主屏幕时起作用，且 iOS 只在启动时读；这里保持和首帧脚本一致）
  const sb = document.querySelector<HTMLMetaElement>('meta[name="apple-mobile-web-app-status-bar-style"]')
  if (sb) sb.content = theme === 'dark' ? 'black-translucent' : 'default'
  if (changed) hooks.onTheme.forEach(fn => { try { fn() } catch (e) { console.error(e) } })
}

function watchSystemTheme(): void {
  mq = matchMedia('(prefers-color-scheme: dark)')
  mq.addEventListener('change', () => { if (st.theme === 'auto') applyTheme() })
}

// ───────── 换页 ─────────

/** 注册一页（main.ts 懒加载完调用）；如果当前就停在这页，立刻 show */
export function registerPage(id: PageId, h: PageHandle): void {
  pages.set(id, h)
  if (st.page === id && shown !== id) { shown = id; safe(() => h.show()); restoreScroll(pageRoot(id), id) }
}

/** 切到某一页。从底栏点的（fromTab）会把图表页的来路作废 */
export function go(page: string, opts: { fromTab?: boolean; replace?: boolean } = {}): void {
  const p = (PAGES as readonly string[]).includes(page) ? page as PageId : 'chart'
  const prev = st.page
  if (opts.fromTab) nav.origin = null
  if (p === prev && shown === p) {
    if (opts.fromTab) {
      const h = pages.get(p)
      if (h?.reselect) safe(() => h.reselect!())
      else pageRoot(p).scrollTo({ top: 0, behavior: 'smooth' })
    }
    return
  }
  closeAllSheets()
  closeOpenSwipe()
  saveScroll(prev)
  st.page = p
  PAGES.forEach(x => pageRoot(x).classList.toggle('show', x === p))
  paintTabbar()
  if (location.hash !== '#' + p) history.replaceState(null, '', '#' + p)
  if (shown && shown !== p) { const h = pages.get(shown); if (h) safe(() => h.hide()) }
  shown = null
  const h = pages.get(p)
  if (h) { shown = p; safe(() => h.show()); restoreScroll(pageRoot(p), p) }
  save()
  hooks.onPage.forEach(fn => safe(() => fn(p, prev)))
}

/** 当前页若在 ids 里，重新 show 一遍（同步把自选、账号这些整块换掉之后用） */
export function refreshPage(ids: readonly PageId[]): void {
  const p = st.page
  if (!ids.includes(p) || shown !== p) return
  const h = pages.get(p)
  if (h) safe(() => h.show())
}

/** 打开一只品种的图（自选 / 板块 / 搜索点一行都走这里）：记最近、记来路、切到图表页 */
export function openSymbol(symbol: string): void {
  const s = symbol.toUpperCase()
  const from = st.page
  st.symbol = s
  st.symbols.recents = [s, ...st.symbols.recents.filter(x => x !== s)].slice(0, 10)
  nav.origin = from === 'chart' ? nav.origin : from
  go('chart')
  save()
  hooks.onSymbol.forEach(fn => safe(() => fn(s)))
}

/** 「我的」角标：复盘还欠着答案的条数，0 不画，封顶 99 */
export function setMeBadge(n: number): void {
  const b = tabbar?.querySelector<HTMLElement>('.m-tab-badge')
  if (!b) return
  b.hidden = !(n > 0)
  b.textContent = String(Math.min(99, Math.max(0, Math.floor(n))))
}

function paintTabbar(): void {
  if (!tabbar) return
  tabbar.dataset.page = st.page
  tabbar.querySelectorAll<HTMLElement>('.m-tab').forEach(a => {
    if (a.dataset.page === st.page) a.setAttribute('aria-current', 'page')
    else a.removeAttribute('aria-current')
  })
}

// ───────── 滚动位置 ─────────

function saveScroll(id: PageId): void {
  const root = document.getElementById('page-' + id)
  if (!root || root.classList.contains('page-fixed')) return
  st.scroll[id] = Math.round(root.scrollTop)
}

/** 滚动位置随时落盘：滚停（scrollend，没有就 250ms 静止）时落一次 */
export function trackScroll(target: HTMLElement, key: string): () => void {
  let t = 0
  const commit = (): void => { st.scroll[key] = Math.round(target.scrollTop); persistQuiet() }
  const onScroll = (): void => { st.scroll[key] = Math.round(target.scrollTop); clearTimeout(t); t = window.setTimeout(commit, 250); closeOpenSwipe() }
  target.addEventListener('scroll', onScroll, { passive: true })
  target.addEventListener('scrollend', commit)
  return () => { clearTimeout(t); target.removeEventListener('scroll', onScroll); target.removeEventListener('scrollend', commit) }
}

/** 把滚动位置接回来。内容可能是异步渲染的：高度不够时盯着它长，最多 4 秒，用户一动就停 */
export function restoreScroll(target: HTMLElement, key: string): void {
  const want = st.scroll[key]
  if (!want || target.classList.contains('page-fixed')) return
  target.scrollTop = want
  if (Math.abs(target.scrollTop - want) < 2) return
  let done = false
  const stop = (): void => {
    if (done) return
    done = true; mo.disconnect(); clearTimeout(timer)
    target.removeEventListener('touchstart', stop); target.removeEventListener('wheel', stop)
  }
  const mo = new MutationObserver(() => { target.scrollTop = want; if (Math.abs(target.scrollTop - want) < 2) stop() })
  mo.observe(target, { childList: true, subtree: true })
  const timer = window.setTimeout(stop, 4000)
  target.addEventListener('touchstart', stop, { passive: true })
  target.addEventListener('wheel', stop, { passive: true })
}

// ───────── 装壳 ─────────

function safe(fn: () => void): void { try { fn() } catch (e) { console.error(e) } }

/** 建出四页与底栏，接好路由、主题、前后台；返回 #m-app */
export function installShell(mount: HTMLElement = document.body): HTMLElement {
  appRoot = el('div', 'booting')
  appRoot.id = 'm-app'
  for (const id of PAGES) {
    const s = el('section', 'page')
    s.id = 'page-' + id
    s.setAttribute('aria-label', TAB_TITLE[id])
    appRoot.appendChild(s)
    trackScroll(s, id)
  }
  tabbar = el('nav', 'm-tabbar')
  tabbar.setAttribute('aria-label', '底栏')
  tabbar.innerHTML = PAGES.map(id => `<a class="m-tab" href="#${id}" data-page="${id}" aria-label="${TAB_TITLE[id]}" data-id="bottom.${id}"><span class="m-tab-mark">${glyph(TAB_GLYPH[id], 27)}${id === 'me' ? '<span class="m-tab-badge" hidden></span>' : ''}</span></a>`).join('')
  tabbar.addEventListener('click', e => {
    const a = (e.target as Element).closest<HTMLElement>('.m-tab')
    if (!a) return
    e.preventDefault()
    go(a.dataset.page || 'chart', { fromTab: true })
  })
  appRoot.appendChild(tabbar)
  mount.appendChild(appRoot)

  // 路由：地址里带了页就用它，否则回到上次停的那一页
  const fromHash = location.hash.slice(1)
  if ((PAGES as readonly string[]).includes(fromHash)) st.page = fromHash as PageId
  PAGES.forEach(x => pageRoot(x).classList.toggle('show', x === st.page))
  paintTabbar()
  if (location.hash !== '#' + st.page) history.replaceState(null, '', '#' + st.page)
  addEventListener('hashchange', () => go(location.hash.slice(1)))

  applyTheme()
  watchSystemTheme()

  // 前后台
  const fg = (): void => { applyTheme(); hooks.onForeground.forEach(fn => safe(fn)); dispatchEvent(new CustomEvent('hkline:foreground')) }
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') fg()
    else { saveScroll(st.page); persistQuiet(); hooks.onBackground.forEach(fn => safe(fn)) }
  })
  addEventListener('pageshow', e => { if ((e as PageTransitionEvent).persisted) fg() })
  addEventListener('pagehide', () => { saveScroll(st.page); persistQuiet() })

  requestAnimationFrame(() => requestAnimationFrame(() => appRoot?.classList.remove('booting')))
  return appRoot
}
