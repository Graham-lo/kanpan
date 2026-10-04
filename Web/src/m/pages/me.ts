/* 手机网页版 · 「我的」（照 iOS Me/MePage.swift）
 *
 * 根：居中标题「我的」+ 四张 raised2 卡（圆角 12、卡间 16，卡内两行之间 1/3 px 发丝线左缩 16）：
 *   账号（没登录「账号 / 登录 / 注册」；登录了是用户名 + 同步状态，行尾一颗「立即同步」，照 MePage.accountRow）
 *   复盘本（观点 N 条 · 待判定 N / 交易那半句）· 全部预警（生效中 N）
 *   朋友与收件箱（未登录 / 未读 N）· 交易所
 *   设置
 * 推进去的每一层（model/navStack）从右滑入，左上 44 圆片返回，左沿右滑、系统返回手势都退一层；底栏还在。
 * 各层写在各自的文件里，经 MeHost 推层 / 退层 / 去行情页：
 *   账号 meAccount.ts · 复盘本 reviewBook.ts · 全部预警 alerts.ts · 朋友与收件箱 friends.ts · 设置 meSettings.ts。
 * 交易所：iOS 的只读 API 密钥存在手机钥匙串里、交易记录由手机拉了传上来，浏览器拿不到也不该拿密钥——
 *   网页版这一页只说「在 App 里接入」，接入之后复盘本里的交易照样能看（数据在账号上）。
 */
import '../styles/me.css'
import '../styles/alerts.css'
import { st, save } from '../app/store'
import { INTERVALS, type IntervalId } from '../app/prefs'
import { hooks, openSymbol, trackScroll, restoreScroll, type PageHandle } from '../app/shell'
import { setRoute } from '../../market'
import { icon } from '../ui/icons'
import { el, esc, pressGate, setHTML } from '../ui/dom'
import { session, loggedIn, onSession } from '../../account/session'
import { liveCount, onAlertsChange } from '../model/alerts'
import { onSyncChange, syncMeta, syncSource } from '../model/syncStatus'
import { navStack } from '../model/navStack'
import { buildAlertList, startAlertWatcher } from './alerts'
import { takeOpenParam } from './_streams'
import { buildAccount, buildAuth } from './meAccount'
import { buildSettings } from './meSettings'
import { buildFriends } from './friends'
import { inboxUnseen, onInboxChange } from './inboxStore'
import { buildReviewBook, onReviewStatus, refreshReviewStatus, reviewRootStatus } from './reviewBook'
import type { MeHost, MeLayer } from './meHost'
import { edgeIntent, edgeProgress, edgeShouldPop, inEdgeZone } from '../model/edgeSwipe'

const CHEV = icon('chevronRight', 12)
const DEEP = ['account', 'alerts', 'settings', 'review', 'friends', 'exchange'] as const
/** iOS 从主屏幕打开：没有 Safari 的左沿手势，边缘手势从 0 起接管 */
const standaloneIOS = (): boolean => /iPhone|iPad/.test(navigator.userAgent)
  && (matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true)

export function initMe(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'me-page')
  root.innerHTML = ''
  /** 每层推进来时压在它下面的那层（边缘手势拖动时一起挪） */
  const belowOf = new WeakMap<MeLayer, HTMLElement>()
  const stack = navStack<MeLayer>((layer, next) => {
    layer.off.forEach(f => { try { f() } catch (e) { console.error(e) } })
    ;(document.activeElement as HTMLElement | null)?.blur?.()
    layer.el.classList.remove('in')
    next.el.classList.remove('under')
    setTimeout(() => layer.el.remove(), 300)
    if (next === rootLayer) renderRoot()
  })
  // 线路只记在本机：页面一加载就按它连（选 gateway 但没有网关地址时 market 自己退回直连）
  setRoute(st.routePolicy)
  startAlertWatcher()

  function makeLayer(title: string, isRoot: boolean): MeLayer {
    const L = el('div', 'me-layer' + (isRoot ? '' : ' me-pushed'))
    L.innerHTML = `<header class="me-nav">${isRoot ? '<span class="me-nav-side"></span>' : `<button type="button" class="me-back" aria-label="返回">${icon('chevronLeft', 20)}</button>`}
      <h1 class="me-title">${esc(title)}</h1><span class="me-nav-side me-nav-trailing"></span></header>
      <div class="me-scroll"><div class="me-body"></div></div>`
    root.appendChild(L)
    const layer: MeLayer = { el: L, body: L.querySelector<HTMLElement>('.me-body')!, off: [], trailing: L.querySelector<HTMLElement>('.me-nav-trailing')! }
    L.querySelector<HTMLElement>('.me-back')?.addEventListener('click', () => host.back())
    if (!isRoot) edgeSwipe(layer)
    return layer
  }

  /** 推进去的层：左沿右划跟手返回（判定在 model/edgeSwipe.ts）。
   *  用 touch 事件而不是 pointer：横向拖动时浏览器会给 pointer 发 pointercancel，touchmove 能 preventDefault 把这一趟留给自己。 */
  function edgeSwipe(layer: MeLayer): void {
    const L = layer.el
    let g: { x: number; y: number; id: number; claimed: boolean; below: HTMLElement | null; w: number; samples: { x: number; t: number }[] } | null = null
    const paint = (dx: number): void => {
      if (!g) return
      const p = edgeProgress(dx, g.w)
      L.style.translate = `${Math.max(0, dx)}px 0`
      if (g.below) { g.below.style.translate = `${-0.24 * g.w * (1 - p)}px 0`; g.below.style.opacity = String(0.6 + 0.4 * p) }
    }
    /** 交还给 CSS：先恢复过渡、提交当前位置，再撤掉内联值——由类名（.in / .under）从手指那儿接着动画过去 */
    const release = (pop: boolean): void => {
      const below = g?.below ?? null
      g = null
      const els = [L, below].filter((x): x is HTMLElement => !!x)
      for (const e of els) e.style.transition = ''
      void L.offsetWidth
      for (const e of els) { e.style.translate = ''; e.style.opacity = '' }
      if (pop && stack.top === layer) host.back()
    }
    L.addEventListener('touchstart', e => {
      if (g || e.touches.length !== 1 || stack.top !== layer) return
      const t = e.touches[0]
      if (!inEdgeZone(t.clientX, standaloneIOS())) return
      g = { x: t.clientX, y: t.clientY, id: t.identifier, claimed: false, below: belowOf.get(layer) ?? null, w: L.clientWidth || innerWidth, samples: [{ x: t.clientX, t: e.timeStamp }] }
    }, { passive: true })
    L.addEventListener('touchmove', e => {
      if (!g) return
      const t = Array.from(e.changedTouches).find(x => x.identifier === g!.id)
      if (!t) return
      const dx = t.clientX - g.x
      if (!g.claimed) {
        const intent = edgeIntent(dx, t.clientY - g.y)
        if (intent === 'wait') return
        if (intent === 'abandon') { g = null; return }
        g.claimed = true
        L.style.transition = 'none'
        if (g.below) g.below.style.transition = 'none'
        ;(document.activeElement as HTMLElement | null)?.blur?.()
      }
      if (e.cancelable) e.preventDefault()
      e.stopPropagation()
      g.samples.push({ x: t.clientX, t: e.timeStamp })
      if (g.samples.length > 5) g.samples.shift()
      paint(dx)
    }, { passive: false, capture: true })
    L.addEventListener('touchend', e => {
      if (!g) return
      const t = Array.from(e.changedTouches).find(x => x.identifier === g!.id)
      if (!t) return
      if (!g.claimed) { g = null; return }
      // 拖动过的 touchmove 已 preventDefault，浏览器不会再补一次 click，不用另外拦
      const first = g.samples[0]
      const dt = e.timeStamp - first.t
      const vx = dt > 0 ? (t.clientX - first.x) / dt : 0
      release(edgeShouldPop(t.clientX - g.x, g.w, vx))
    }, { capture: true })
    // 浏览器 / 系统把这一趟抢走了（Safari 自己的左沿返回等）：弹回，不退——那边的返回由 backStack 退一层
    L.addEventListener('touchcancel', () => { if (g?.claimed) release(false); else g = null }, { capture: true })
  }

  const host: MeHost = {
    push(title, build) {
      const top = stack.top
      const layer = makeLayer(title, false)
      if (top) belowOf.set(layer, top.el)
      stack.push(layer)
      build(layer.body, layer)
      requestAnimationFrame(() => { layer.el.classList.add('in'); top?.el.classList.add('under') })
      return layer
    },
    back() { stack.back() },
    popToRoot() { stack.popToRoot() },
    isTop(layer) { return stack.top === layer },
    openSymbol(symbol, interval) {
      stack.popToRoot()
      openSymbol(symbol)
      // 行情页换品种时会套用学到的周期；信 / 记录指明了周期就以它为准
      if (interval && (INTERVALS as readonly string[]).includes(interval) && st.interval !== interval) {
        st.interval = interval as IntervalId
        save()
      }
    },
    openLogin() { host.push('登录', (b, l) => buildAuth(b, l, host, 'login')) },
  }

  // ───────── 根 ─────────
  const rootLayer = makeLayer('我的', true)
  stack.push(rootLayer)
  const rootScroll = rootLayer.el.querySelector<HTMLElement>('.me-scroll')!

  function row(id: string, title: string, lines: (string | null | undefined)[] = [], chevron = true, danger = false): string {
    const sub = lines.filter((x): x is string => !!x).map(s => `<span class="me-row-status num${danger ? ' danger' : ''}">${esc(s)}</span>`).join('')
    return `<button type="button" class="me-row" data-go="${id}"><span class="me-row-text"><span class="me-row-title">${esc(title)}</span>${sub}</span>${chevron ? `<span class="me-chev">${CHEV}</span>` : ''}</button>`
  }
  const divider = '<div class="me-divider" aria-hidden="true"></div>'

  /** 同步、对数、未读、预警、每分钟「N 分钟前」都会来重画：内容没变不动；
   *  手指按在某一行上时等松手再换，不然按着的那一行被换成新节点，点进去落空 */
  const rootGate = pressGate(rootLayer.body)
  function renderRoot(): void { rootGate(renderRootNow) }
  function renderRootNow(): void {
    // 被拒 / 被顶下去之后：账号行第二行先说为什么（红字），点进去是带说明的登录页
    const account = loggedIn()
      ? `<div class="me-acct">${row('account', session.user || '', [syncMeta(syncSource().state())], false)}<button type="button" class="me-sync" data-sync>立即同步</button></div>`
      : session.notice ? row('account', '账号', [session.notice], true, true) : row('account', '账号', ['登录 / 注册'])
    const rv = reviewRootStatus()
    setHTML(rootLayer.body, `<div class="me-card">${account}</div>
      <div class="me-card">${row('review', '复盘本', [rv.line1, rv.line2])}${divider}${row('alerts', '全部预警', [`生效中 ${liveCount()}`])}</div>
      <div class="me-card">${row('friends', '朋友与收件箱', [loggedIn() ? `未读 ${inboxUnseen()}` : '未登录'])}${divider}${row('exchange', '交易所', ['在 App 里接入'])}</div>
      <div class="me-card">${row('settings', '设置')}</div>`)
  }
  rootLayer.body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('[data-sync]')) { syncSource().syncNow(); return }
    const b = t.closest<HTMLElement>('[data-go]')
    if (b) go(b.dataset.go || '')
  })

  function go(id: string): void {
    switch (id) {
      case 'account':
        if (loggedIn()) host.push('账号', (b, l) => buildAccount(b, l, host))
        else host.openLogin()
        break
      case 'review': host.push('复盘本', (b, l) => buildReviewBook(b, l, host)); break
      case 'alerts':
        host.push('全部预警', (body, L) => {
          body.classList.add('me-alerts')
          L.off.push(buildAlertList(body, { onOpen: a => host.openSymbol(a.symbol) }))
        })
        break
      case 'friends': host.push('朋友与收件箱', (b, l) => buildFriends(b, l, host)); break
      case 'exchange': host.push('交易所', buildExchange); break
      case 'settings': host.push('设置', (b, l) => buildSettings(b, l, host)); break
    }
  }

  // ───────── 生命周期 ─────────
  const rerender = (): void => { if (stack.depth >= 1) renderRoot() }
  renderRoot()
  onSession(rerender)
  onAlertsChange(rerender)
  onSyncChange(rerender)
  onInboxChange(rerender)
  onReviewStatus(rerender)
  refreshReviewStatus()
  hooks.onForeground.push(() => refreshReviewStatus())
  // 「上次 N 分钟前」会过时：每分钟重画一次
  setInterval(() => { if (!document.hidden && loggedIn() && root.isConnected) renderRoot() }, 60_000)
  trackScroll(rootScroll, 'me.root')
  restoreScroll(rootScroll, 'me.root')
  // 深链（验收截图、通知点开用）：?open=account|alerts|settings|review|friends|exchange 直接推到那一层（读完从地址里去掉）
  const deep = takeOpenParam(DEEP)
  if (deep) go(deep)
  return {
    show() { renderRoot(); refreshReviewStatus() },
    hide() { (document.activeElement as HTMLElement | null)?.blur?.() },
    reselect() { if (stack.depth > 1) stack.popToRoot(); else rootScroll.scrollTo({ top: 0, behavior: 'smooth' }) },
  }
}

/** 交易所：浏览器做不到接入（密钥只在手机上），只说去哪儿接、接了以后这里能看到什么 */
function buildExchange(body: HTMLElement): void {
  body.innerHTML = `<div class="me-card"><div class="me-ex">
      <span class="me-row-text"><span class="me-row-title">币安 · 合约</span><span class="me-row-status">在 App 里接入</span></span>
    </div></div>
    <p class="me-foot">密钥只存在手机上；接入后交易记录这里也能看</p>`
}
