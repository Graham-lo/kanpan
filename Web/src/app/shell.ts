/* Hkline Web · 外壳：主题、页面切换（hash 路由）、头部 */
import { st, save, type PageId } from './store'
import { $, $$, I, esc } from '../ui/dom'
import { hideTip } from '../ui/overlay'
import { session } from '../account/session'
import { landingPage } from '../home/landing'

export const PAGES: PageId[] = ['home', 'chart', 'sectors', 'review', 'me']

/** 各页挂进来的回调 */
export const hooks = {
  onTheme: [] as (() => void)[],
  pageShown: {} as Partial<Record<PageId, () => void>>,
  pageHidden: {} as Partial<Record<PageId, () => void>>,
  onSearch: null as null | ((initial?: string) => void),
  /** 其它页想额外订的推送流（板块页的成员 ticker 等） */
  extraStreams: [] as (() => string[])[],
  /** 一批 ticker 刷完之后 */
  onTicks: [] as (() => void)[],
  /** 品种表取到之后 */
  booted: [] as (() => void)[],
  openSector: null as null | ((id: string) => void),
  /** 跳到复盘页并选中一条（图表侧栏「交易」点一行 → 交易回放；记一笔传上后 → 观点记录） */
  openReview: null as null | ((tab: 'trade' | 'view', id: string) => void),
}

export function applyTheme(): void {
  const r = document.documentElement
  r.dataset.theme = st.theme
  r.dataset.skin = st.skin
  r.dataset.updown = st.updown
  const b = $('#hdrTheme'); if (b) b.innerHTML = I(st.theme === 'dark' ? 'moon' : 'sun')
  hooks.onTheme.forEach(fn => fn())
}

/** 首页按需装：第一次显示时才取它的代码（pages/home.ts 引用图表页的入口，静态引进来会和外壳成环） */
let homeLoading: Promise<void> | null = null
function ensureHome(): void {
  if (hooks.pageShown.home || homeLoading) return
  homeLoading = import('../pages/home').then(m => {
    m.initHome()
    if (st.page === 'home') hooks.pageShown.home?.()
  }).catch(e => { homeLoading = null; console.error(e) })
}

export function go(page: string, push = true): void {
  const p = (PAGES as string[]).includes(page) ? page as PageId : 'chart'
  if (p === 'home') ensureHome()
  const prev = st.page
  st.page = p
  PAGES.forEach(x => $('#page-' + x)?.classList.toggle('show', x === p))
  $$('.nav a').forEach(a => { if (a.dataset.page === p) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current') })
  // 不认的 #页名（手打、旧书签）也换成实际显示的那页，不让地址栏和页面对不上
  if ((push || p !== page) && location.hash !== '#' + p) history.replaceState(null, '', '#' + p)
  if (prev !== p) hooks.pageHidden[prev]?.()
  hooks.pageShown[p]?.()
  hideTip()
}

export function renderHeader(): void {
  const av = $('#hdrAvatar'); if (!av) return
  const u = session.user
  av.className = 'avatar' + (u ? '' : ' out')
  av.innerHTML = u ? esc(u[0].toUpperCase()) : I('user', 'icon-16')
  av.dataset.tip = u ? `我的 · ${u}` : '我的'
}

/** 去登录：「我的」翻到账号那一栏 */
export function goLogin(): void {
  if (st.meSection !== 'account') { st.meSection = 'account'; save() }
  go('me')
}

export function installShell(): void {
  // 地址不带 #页名：冷启动落首页；带品种 / 周期 / 布局参数的深链照旧进图表（home/landing.ts）
  if (!location.hash || location.hash === '#') history.replaceState(history.state, '', '#' + landingPage())
  addEventListener('hashchange', () => go(location.hash.slice(1), false))
  // 没登录时头像就是登录入口：落在「我的 · 账号」那一栏（默认那栏是外观，点了看不到登录框）
  $('#hdrAvatar').onclick = () => session.user ? go('me') : goLogin()
  $('#hdrTheme').onclick = () => { st.theme = st.theme === 'dark' ? 'light' : 'dark'; save(); applyTheme() }
  $('#searchTrigger').onclick = () => { go('chart'); hooks.onSearch?.() }
  $$('.nav a').forEach(a => a.addEventListener('click', e => { e.preventDefault(); go(a.dataset.page || 'chart') }))
}
