/* Hkline 手机网页版 · 壳（照 iOS Main/MainScreen.swift 的 tab 切换与 Main/TabBar.swift）
 *
 * - 五个整页 <section class="page" id="page-xxx">，hash 路由 #home #chart #favorites #sectors #me，与底栏五格一一对应。
 * - 页面合同见 ./README.md：每页 initXxx(root) → { show(); hide(); reselect?() }，由 main.ts 懒加载后 registerPage。
 * - 主题：data-theme（auto 跟系统，系统切深浅时跟着换）/ data-skin / data-updown，外加 meta theme-color。
 * - 现场：当前页、品种、滚动位置随时落盘，冷启动回到原地。
 * - 前台：切后台回来发 onForeground（行情 WS 由 market/stream.ts 自己在 visibilitychange 里重连，
 *   页面在这里补拉 REST、刷新列表）。
 * - 系统返回（鸿蒙 / 安卓侧边返回、Safari 左沿右划）：退最上面那层弹层 / 盖板 / 页内推进去的层，
 *   都没有时图表页有来路就回来路（与顶栏「‹」同一件事），见 ../ui/backStack。
 * - 换页是瞬切（iOS TabView 不做过场），按下态 / 防捏放大 / 长按菜单 / 看图不锁屏见 ../ui/native。
 */
import { st, save, persistQuiet, resolvedTheme, PAGES, type PageId } from './store'
import { glyph, type GlyphName } from '../ui/icons'
import { closeAllSheets } from '../ui/sheet'
import { closeOpenSwipe } from '../ui/swipeDelete'
import { el } from '../ui/dom'
import { installBack, onBack, syncBack } from '../ui/backStack'
import { installNativeFeel } from '../ui/native'
import { session, onSession } from '../../account/session'
import { normKey } from '../chart/symbolKey'

/** 一页对壳的承诺 */
export interface PageHandle {
  /** 切到这一页（每次都调；首次在 init 之后立刻调） */
  show(): void
  /** 离开这一页 */
  hide(): void
  /** 已经站在这一页又点了一次底栏那一格：回到这一页的根（板块页下钻两层时是唯一的出口） */
  reselect?(): void
}

const TAB_TITLE: Record<PageId, string> = { home: '首页', chart: '图表', favorites: '自选', sectors: '板块分类', me: '我的' }
const TAB_GLYPH: Record<PageId, GlyphName> = { home: 'home', chart: 'chart', favorites: 'favorites', sectors: 'sectors', me: 'me' }

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

/** 同步装进来的改动：settings = 改了的设置根（prefs 字段名）；drawings = 线变了的品种（规范键，
 *  图表不必管：绑着 drawingBook 的控制器会收到 replaced 自己重画）；drawingPreferences = 画线工具偏好换了 */
export interface SyncChange { settings: string[]; favorites: boolean; alerts: boolean; drawings: string[]; drawingPreferences: boolean }

const pages = new Map<PageId, PageHandle>()
/** 页还没注册时的挂起调用：注册时补 show */
let appRoot: HTMLElement | null = null
let tabbar: HTMLElement | null = null
let shown: PageId | null = null

/** 图表页的「来路」：从自选 / 板块点进来时记着，图表页顶栏据此画返回；自己点底栏就作废。
 *  有来路时系统返回也回那一页（与图表页顶栏「‹」一样：作废来路、切过去） */
let origin: PageId | null = null
let unbackOrigin: (() => void) | null = null
/** 连续扫图的名单（iOS Main/ScanList.swift）：从自选某个分类、板块下钻点进图时，把那一刻列表的顺序冻结下来，
 *  之后在价格区横滑就接着这张表往下看；列表自己再重排不影响这一趟。搜索、提醒、深链这些路不冻结名单——
 *  走过去之后手里这只若不在名单里，横滑自然什么都不做。底栏换页 = 人离开了那张表，名单作废 */
let scanList: string[] | null = null
export const nav = {
  get origin(): PageId | null { return origin },
  get scan(): readonly string[] | null { return scanList },
  set origin(v: PageId | null) {
    origin = v
    unbackOrigin?.(); unbackOrigin = null
    if (v && v !== 'chart') unbackOrigin = onBack(() => { const o = origin; nav.origin = null; if (o) go(o) }, 'chart')
  },
}
/** 来路与扫图名单是这个人这一趟的（iOS ChartTrail）：换号 / 退登 / 被顶下线 = 档案换了主人，两样一起作废——
 *  不然横滑翻的还是上一个人冻结下来的自选，返回键也指着上一个人的来路。同一个人重登（只换了会话）不算 */
let trailOwner: string | null = session.userId
onSession(() => {
  if (session.userId === trailOwner) return
  trailOwner = session.userId
  nav.origin = null
  scanList = null
})

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

// ───────── 盖板 ─────────

/** 不在 ui/sheet 那一摞里的盖板（搜索页这类整屏盖层）登记的关闭函数 → 它的系统返回注销函数；换页时统一收掉 */
const overlays = new Map<() => void, () => void>()

/** 登记一层盖板：开的时候登记、关的时候调返回的函数注销。壳换页时会调 close（close 里自己注销）；
 *  系统返回也关它（盖在它上面的弹层先退） */
export function registerOverlay(close: () => void): () => void {
  overlays.get(close)?.()
  overlays.set(close, onBack(close))
  return () => { overlays.get(close)?.(); overlays.delete(close) }
}

/** 收干净所有盖在页面上的层：弹层 / 面板 / 菜单 / 确认框（ui/sheet 那一摞）、左滑开着的行、登记过的盖板 */
export function closeOverlays(): void {
  closeAllSheets()
  closeOpenSwipe()
  for (const [close, unback] of [...overlays]) { overlays.delete(close); unback(); safe(close) }
}

/** 切到某一页。从底栏点的（fromTab）会把图表页的来路作废 */
export function go(page: string, opts: { fromTab?: boolean; replace?: boolean } = {}): void {
  const p = (PAGES as readonly string[]).includes(page) ? page as PageId : 'chart'
  const prev = st.page
  if (opts.fromTab) { nav.origin = null; scanList = null }
  if (p === prev && shown === p) {
    if (opts.fromTab) {
      const h = pages.get(p)
      if (h?.reselect) safe(() => h.reselect!())
      else pageRoot(p).scrollTo({ top: 0, behavior: 'smooth' })
    }
    return
  }
  closeOverlays()
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
  syncBack()
  native.refresh()
  hooks.onPage.forEach(fn => safe(() => fn(p, prev)))
}

/** 当前页若在 ids 里，重新 show 一遍（同步把自选、账号这些整块换掉之后用） */
export function refreshPage(ids: readonly PageId[]): void {
  const p = st.page
  if (!ids.includes(p) || shown !== p) return
  const h = pages.get(p)
  if (h) safe(() => h.show())
}

/** 打开一只品种的图（自选 / 板块 / 搜索点一行都走这里）：记最近、记来路、切到图表页。
 *  scanFrom：来源页那张列表此刻的顺序（自选当前分类、板块下钻那几行），给就冻结成扫图名单 */
export function openSymbol(symbol: string, scanFrom?: readonly string[]): void {
  const s = normKey(symbol)
  if (scanFrom) scanList = [...new Set(scanFrom.map(normKey).filter(Boolean))]
  const from = st.page
  st.symbol = s
  st.symbols.recents = [s, ...st.symbols.recents.filter(x => x !== s)].slice(0, 10)
  nav.origin = from === 'chart' ? nav.origin : from
  // 已经站在行情页上（提醒 / 通知的「查看」、复盘本「继续记录」）go 不换页、也就不收盖板：
  // 这里补上，和换页进来同一个收尾——不然开着的记一笔、分享、图表设置还对着上一只（iOS open(linkedSymbol:)）
  if (from === 'chart' && shown === 'chart') closeOverlays()
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

let native: { refresh(): void } = { refresh() {} }

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

  // 路由：地址里带了页就用它（刷新、深链）；不带（从主屏图标冷启动）落在首页（照 iOS：启动默认首页，不回上次那格）
  const fromHash = location.hash.slice(1)
  st.page = (PAGES as readonly string[]).includes(fromHash) ? fromHash as PageId : 'home'
  PAGES.forEach(x => pageRoot(x).classList.toggle('show', x === st.page))
  paintTabbar()
  if (location.hash !== '#' + st.page) history.replaceState(null, '', '#' + st.page)
  addEventListener('hashchange', () => go(location.hash.slice(1)))
  // 系统返回弹掉哨兵后地址回到上一格：把 hash 摆回当前页，随后那个 hashchange 就是空转
  installBack(() => st.page, () => { if (location.hash !== '#' + st.page) history.replaceState(history.state, '', '#' + st.page) })
  native = installNativeFeel(() => st.page === 'chart')

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
