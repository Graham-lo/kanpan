/* 手机网页版 · 「我的」（照 iOS Me/MePage.swift、Settings/DisplaySettingsSection.swift、Account/AccountView.swift）
 *
 * 根：居中标题「我的」+ 三张 raised2 卡（圆角 12、卡间 16）：
 *   账号（没登录「账号 / 登录 / 注册」；登录了是用户名 + 同步状态，行尾一颗「立即同步」，照 MePage.accountRow）、
 *   全部预警（生效中 N）、设置。
 *   手机端的复盘本、朋友与收件箱、交易所网页版不做。
 * 推进去的几层在本页里推（底栏还在，左上 44 圆片返回，左沿右滑也能回）：
 *   账号：登录 / 注册表单；登录后用户名、登录设备（踢下线）、修改密码、退出登录、注销账号。
 *   全部预警：pages/alerts.ts 的总表。
 *   设置：配色三卡、深浅（外观）、行情（涨跌色、线路 ?、价格轴 ?）。
 */
import '../styles/me.css'
import '../styles/alerts.css'
import { st, save, resolvedTheme } from '../app/store'
import { applyTheme, hooks, openSymbol, trackScroll, restoreScroll, type PageHandle } from '../app/shell'
import { setRoute } from '../../market'
import { icon } from '../ui/icons'
import { registerTerms, termHTML } from '../ui/hint'
import { confirmDialog } from '../ui/sheet'
import { toast } from '../ui/toast'
import { el, esc } from '../ui/dom'
import { session, loggedIn, onSession } from '../../account/session'
import { login, logout, devices, kick, changePassword, deleteAccount, errorText, type DeviceRow } from '../../account/client'
import { liveCount, onAlertsChange } from '../model/alerts'
import { onPlaceholderSync, onSyncChange, syncMeta, syncSource } from '../model/syncStatus'
import { KIND_CN, PASSWORD_RULE, USERNAME_RULE, deviceMeta, validPassword, validUsername } from '../model/formText'
import { buildAlertList, startAlertWatcher } from './alerts'
import { navStack } from '../model/navStack'
import { takeOpenParam } from './_streams'

registerTerms([
  { id: 'route', title: '线路', body: '直连：手机自己直接连交易所，出厂就是它。\n网关：经我们的服务器转一道，手机连不上交易所时用。\n选了哪条就一直走哪条，不会自己切换。' },
  { id: 'priceScale', title: '价格轴 · 线性 / 对数', body: '线性：每格代表同样多的钱。\n对数：每格代表同样的涨跌幅，看大涨大跌的长周期更公平。' },
])

/** 配色卡的取色（照 tokens.css 各皮肤的 app / ink / ink3 / accent；卡要画别的皮肤，不能读当前变量） */
const SKINS = {
  sage: { name: '青苔', note: '冷 · 墨绿', light: ['#F3F7F4', '#14211B', '#606F67', '#2E7D6B'], dark: ['#0B120F', '#E9F2EC', '#7B8D85', '#4FB69C'] },
  terra: { name: '陶土', note: '暖 · 赤陶', light: ['#FBF6F0', '#241A13', '#756659', '#B25735'], dark: ['#16100C', '#F7EFE6', '#958576', '#E2874F'] },
  classic: { name: '经典', note: '白 · 墨绿', light: ['#FFFFFF', '#14211B', '#606F67', '#2E7D6B'], dark: ['#0D111C', '#E9F2EC', '#7B8D85', '#4FB69C'] },
} as const
type SkinId = keyof typeof SKINS

const seg = (id: string, opts: [string, string][], on: string): string =>
  `<div class="m-seg" role="radiogroup" data-seg="${id}">${opts.map(([v, t]) => `<button type="button" class="m-seg-opt${v === on ? ' on' : ''}" role="radio" aria-checked="${v === on}" data-v="${v}">${t}</button>`).join('')}</div>`
const CHEV = icon('chevronRight', 12)

interface Layer { el: HTMLElement; body: HTMLElement; off: (() => void)[] }

export function initMe(root: HTMLElement): PageHandle {
  root.classList.add('page-fixed', 'me-page')
  root.innerHTML = ''
  const stack = navStack<Layer>((layer, next) => {
    layer.off.forEach(f => f())
    ;(document.activeElement as HTMLElement | null)?.blur?.()
    layer.el.classList.remove('in')
    next.el.classList.remove('under')
    setTimeout(() => layer.el.remove(), 300)
    renderRoot()
  })
  // 线路只记在本机：页面一加载就按它连（选 gateway 但没有网关地址时 market 自己退回直连）
  setRoute(st.routePolicy)
  startAlertWatcher()

  function makeLayer(title: string, isRoot: boolean): Layer {
    const L = el('div', 'me-layer' + (isRoot ? '' : ' me-pushed'))
    L.innerHTML = `<header class="me-nav">${isRoot ? '<span class="me-nav-side"></span>' : `<button type="button" class="me-back" aria-label="返回">${icon('chevronLeft', 20)}</button>`}
      <h1 class="me-title">${esc(title)}</h1><span class="me-nav-side"></span></header>
      <div class="me-scroll"><div class="me-body"></div></div>`
    root.appendChild(L)
    const layer: Layer = { el: L, body: L.querySelector<HTMLElement>('.me-body')!, off: [] }
    L.querySelector<HTMLElement>('.me-back')?.addEventListener('click', () => back())
    if (!isRoot) {
      let edge: { x: number; y: number } | null = null
      L.addEventListener('pointerdown', e => { edge = e.clientX < 24 ? { x: e.clientX, y: e.clientY } : null })
      L.addEventListener('pointerup', e => {
        if (edge && e.clientX - edge.x > 60 && Math.abs(e.clientY - edge.y) < 60) back()
        edge = null
      })
    }
    return layer
  }
  function push(title: string, build: (body: HTMLElement, layer: Layer) => void): Layer {
    const top = stack.top
    const layer = makeLayer(title, false)
    stack.push(layer)
    build(layer.body, layer)
    requestAnimationFrame(() => { layer.el.classList.add('in'); top?.el.classList.add('under') })
    return layer
  }
  const back = (): void => { stack.back() }
  const popToRoot = (): void => stack.popToRoot()

  // ───────── 根 ─────────
  const rootLayer = makeLayer('我的', true)
  stack.push(rootLayer)
  const rootScroll = rootLayer.el.querySelector<HTMLElement>('.me-scroll')!
  function renderRoot(): void {
    // 登录了：用户名 + 同步状态，行尾「立即同步」（点行本身进账号页，没有 ›）。
    // TODO(A 同步引擎)：状态与「立即同步」现在读 model/syncStatus 的占位；A 的运行时落地后调 setSyncSource 接上，这里不用改。
    const account = loggedIn()
      ? `<div class="me-acct">${row('account', session.user || '', session.notice || syncMeta(syncSource().state()), false)}<button type="button" class="me-sync" data-sync>立即同步</button></div>`
      : row('account', '账号', session.notice || '登录 / 注册')
    rootLayer.body.innerHTML = `<div class="me-card">${account}</div>
      <div class="me-card">${row('alerts', '全部预警', `生效中 ${liveCount()}`)}</div>
      <div class="me-card">${row('settings', '设置')}</div>`
  }
  function row(id: string, title: string, status?: string, chevron = true): string {
    return `<button type="button" class="me-row" data-go="${id}"><span class="me-row-text"><span class="me-row-title">${esc(title)}</span>${status ? `<span class="me-row-status num">${esc(status)}</span>` : ''}</span>${chevron ? `<span class="me-chev">${CHEV}</span>` : ''}</button>`
  }
  rootLayer.body.addEventListener('click', e => {
    const t = e.target as HTMLElement
    if (t.closest('[data-sync]')) { syncSource().syncNow(); return }
    const b = t.closest<HTMLElement>('[data-go]')
    if (b) go(b.dataset.go || '')
  })
  onPlaceholderSync(() => toast('同步还没接上'))
  onSyncChange(() => { if (stack.depth >= 1) renderRoot() })
  // 「上次 N 分钟前」会过时：回到前台 / 每分钟重画一次
  setInterval(() => { if (!document.hidden && loggedIn()) renderRoot() }, 60_000)
  function go(id: string): void {
    if (id === 'account') openAccount()
    else if (id === 'alerts') push('全部预警', (body, L) => { body.classList.add('me-alerts'); L.off.push(buildAlertList(body, { onOpen: a => { popToRoot(); openSymbol(a.symbol) } })) })
    else if (id === 'settings') push('设置', buildSettings)
  }

  // ───────── 设置 ─────────
  function buildSettings(body: HTMLElement, L: Layer): void {
    body.classList.add('me-settings')
    const paint = (): void => {
      const dark = resolvedTheme() === 'dark'
      body.innerHTML = `
        <div class="me-group">配色</div>
        <div class="me-swatches">${(Object.keys(SKINS) as SkinId[]).map(id => swatch(id, dark)).join('')}</div>
        <div class="me-group">深浅</div>
        <div class="me-prow"><span class="me-pname">外观</span>${seg('theme', [['auto', '跟随系统'], ['light', '浅色'], ['dark', '深色']], st.theme)}</div>
        <div class="me-group">行情</div>
        <div class="me-prow"><span class="me-pname">涨跌色</span>${seg('updown', [['green', '绿涨红跌'], ['red', '红涨绿跌']], st.redUp ? 'red' : 'green')}</div>
        <div class="me-prow"><span class="me-pname">线路${termHTML('route')}</span>${seg('route', [['direct', '直连'], ['gateway', '网关']], st.routePolicy)}</div>
        <div class="me-prow last"><span class="me-pname">价格轴${termHTML('priceScale')}</span>${seg('scale', [['linear', '线性'], ['log', '对数']], st.priceMode)}</div>`
    }
    const swatch = (id: SkinId, dark: boolean): string => {
      const s = SKINS[id]
      const [app, ink, ink3, accent] = dark ? s.dark : s.light
      const bars = Array.from({ length: 6 }, (_, i) => `<i style="height:${10 + (i * 7) % 27}px;background:var(${i % 3 === 0 ? '--k-down' : '--k-up'})"></i>`).join('')
      return `<button type="button" class="me-swatch${st.skin === id ? ' on' : ''}" data-skin="${id}" role="radio" aria-checked="${st.skin === id}" style="background:${app}">
        <span class="me-sw-art"><span class="me-sw-bars">${bars}</span><span class="me-sw-dot" style="background:${accent}"></span></span>
        <span class="me-sw-name"><b style="color:${ink}">${s.name}</b><small style="color:${ink3}">${s.note}</small></span></button>`
    }
    body.addEventListener('click', e => {
      const t = e.target as HTMLElement
      const sw = t.closest<HTMLElement>('.me-swatch')
      if (sw) { st.skin = sw.dataset.skin as SkinId; save(); applyTheme(); paint(); return }
      const opt = t.closest<HTMLElement>('.m-seg-opt')
      if (!opt) return
      const v = opt.dataset.v!
      switch (opt.parentElement!.dataset.seg) {
        case 'theme': st.theme = v as typeof st.theme; save(); applyTheme(); break
        case 'updown': st.redUp = v === 'red'; save(); applyTheme(); break
        case 'route': st.routePolicy = v as typeof st.routePolicy; save(); setRoute(st.routePolicy); break
        case 'scale': st.priceMode = v as typeof st.priceMode; save(); break
      }
      paint()
    })
    const onTheme = (): void => paint()
    hooks.onTheme.push(onTheme)
    L.off.push(() => { const i = hooks.onTheme.indexOf(onTheme); if (i >= 0) hooks.onTheme.splice(i, 1) })
    paint()
  }

  // ───────── 账号 ─────────
  function openAccount(): void {
    if (loggedIn()) push('账号', buildAccount)
    else push('登录', (b, L) => buildAuth(b, L, 'login'))
  }
  function buildAccount(body: HTMLElement, L: Layer): void {
    const paint = (): void => {
      if (!loggedIn()) { body.innerHTML = ''; return }
      body.innerHTML = `
        <div class="me-card"><div class="me-kv"><span>用户名</span><b>${esc(session.user)}</b></div></div>
        <div class="me-card">
          <button type="button" class="me-row plain" data-a="devices"><span class="me-row-title">登录设备</span><span class="me-chev">${CHEV}</span></button>
          <button type="button" class="me-row plain" data-a="password"><span class="me-row-title">修改密码</span><span class="me-chev">${CHEV}</span></button>
        </div>
        <div class="me-card"><button type="button" class="me-row plain danger" data-a="logout"><span class="me-row-title">退出登录</span></button></div>
        <div class="me-card"><button type="button" class="me-row plain danger" data-a="close"><span class="me-row-title">注销账号</span></button></div>`
    }
    body.addEventListener('click', e => {
      const a = (e.target as HTMLElement).closest<HTMLElement>('[data-a]')?.dataset.a
      if (a === 'devices') push('登录设备', buildDevices)
      else if (a === 'password') push('修改密码', (b, l) => buildAuth(b, l, 'password'))
      else if (a === 'close') push('注销账号', (b, l) => buildAuth(b, l, 'close'))
      else if (a === 'logout') {
        void confirmDialog({ title: '退出登录', message: '本机的自选、画线和提醒都留着', confirm: '退出', destructive: true }).then(ok => {
          if (!ok) return
          logout(); popToRoot(); toast('已退出登录')
        })
      }
    })
    L.off.push(onSession(() => { if (!loggedIn()) popToRoot(); else paint() }))
    paint()
  }
  function buildDevices(body: HTMLElement, L: Layer): void {
    let list: DeviceRow[] | null = null
    let failed = ''
    const paint = (): void => {
      if (failed) { body.innerHTML = `<div class="me-note danger">${esc(failed)}</div>`; return }
      if (!list) { body.innerHTML = '<div class="me-note">加载中…</div>'; return }
      body.innerHTML = `<div class="me-card">${list.map(d => `<div class="me-dev">
          <span class="me-row-text"><span class="me-row-title">${esc(d.name || KIND_CN[d.kind] || '设备')}</span><span class="me-row-status num">${esc(deviceMeta(d))}</span></span>
          ${d.current ? '' : `<button type="button" class="me-kick" data-kick="${esc(d.id)}">退出</button>`}</div>`).join('')}</div>`
    }
    const load = (): void => { devices().then(r => { list = r; failed = ''; paint() }, err => { failed = errorText(err); paint() }) }
    body.addEventListener('click', e => {
      const b = (e.target as HTMLElement).closest<HTMLElement>('[data-kick]')
      if (!b) return
      b.setAttribute('disabled', '')
      kick(b.dataset.kick!).then(() => { list = list?.filter(d => d.id !== b.dataset.kick) ?? null; paint() }, err => { toast(errorText(err)); b.removeAttribute('disabled') })
    })
    L.off.push(onSession(() => { if (!loggedIn()) popToRoot() }))
    paint(); load()
  }

  type AuthPage = 'login' | 'register' | 'password' | 'close'
  function buildAuth(body: HTMLElement, L: Layer, page: AuthPage): void {
    body.classList.add('me-form')
    const title = { login: '登录', register: '注册', password: '保存', close: '注销账号' }[page]
    const fields: [string, string, string, string][] = page === 'login' || page === 'register'
      ? [['user', '用户名', 'text', 'username'], ['pass', '密码', 'password', page === 'register' ? 'new-password' : 'current-password']]
      : page === 'password' ? [['pass', '当前密码', 'password', 'current-password'], ['next', '新密码', 'password', 'new-password']]
        : [['pass', '密码', 'password', 'current-password']]
    const notice = (page === 'login' || page === 'register') && session.notice
      ? `<div class="me-card me-notice"><div class="danger">${esc(session.notice)}</div><div class="me-note-in">已退出登录，本机数据都在</div></div>` : ''
    body.innerHTML = `${notice}${fields.map(([k, label, type, ac]) => `<label class="me-field"><span class="me-flabel">${label}</span>
        <input data-k="${k}" type="${type}" autocomplete="${ac}" autocapitalize="off" autocorrect="off" spellcheck="false" ${k === 'user' ? 'lang="en" inputmode="latin"' : ''} placeholder="${label}">
        <span class="me-rule" data-rule="${k}" hidden></span></label>`).join('')}
      ${page === 'close' ? '<div class="me-close-note">注销后云端数据将删除</div>' : ''}
      <div class="me-err" hidden></div>
      <button type="button" class="me-primary${page === 'close' ? ' danger' : ''}" disabled>${title}</button>
      ${page === 'login' || page === 'register' ? `<button type="button" class="me-switch">${page === 'login' ? '注册' : '登录'}</button>` : ''}`
    const input = (k: string): HTMLInputElement | null => body.querySelector<HTMLInputElement>(`input[data-k="${k}"]`)
    const btn = body.querySelector<HTMLButtonElement>('.me-primary')!
    const errEl = body.querySelector<HTMLElement>('.me-err')!
    let busy = false
    const values = (): Record<string, string> => ({ user: input('user')?.value.trim() ?? '', pass: input('pass')?.value ?? '', next: input('next')?.value ?? '' })
    const ok = (): boolean => {
      const v = values()
      if (page === 'login') return validUsername(v.user) && v.pass.length > 0
      if (page === 'register') return validUsername(v.user) && validPassword(v.pass)
      if (page === 'password') return v.pass.length > 0 && validPassword(v.next)
      return v.pass.length > 0
    }
    const paint = (): void => {
      const v = values()
      const ru = body.querySelector<HTMLElement>('[data-rule="user"]')
      if (ru) { ru.textContent = USERNAME_RULE; ru.hidden = !v.user || validUsername(v.user) }
      const rp = body.querySelector<HTMLElement>(page === 'register' ? '[data-rule="pass"]' : '[data-rule="next"]')
      const pw = page === 'register' ? v.pass : v.next
      if (rp && (page === 'register' || page === 'password')) { rp.textContent = PASSWORD_RULE; rp.hidden = !pw || validPassword(pw) }
      btn.disabled = busy || !ok()
      btn.textContent = busy ? '请稍候…' : title
    }
    body.addEventListener('input', e => {
      const t = e.target as HTMLInputElement
      if (t.dataset.k === 'user') { const low = t.value.toLowerCase(); if (low !== t.value) t.value = low }
      errEl.hidden = true; paint()
    })
    body.addEventListener('keydown', e => { if ((e as KeyboardEvent).key === 'Enter' && !btn.disabled) btn.click() })
    body.querySelector<HTMLElement>('.me-switch')?.addEventListener('click', () => {
      back(); push(page === 'login' ? '注册' : '登录', (b, l) => buildAuth(b, l, page === 'login' ? 'register' : 'login'))
    })
    // 请求在路上时人可能已经退出这一层、又推了别的层：回来的结果只在这一层还在栈顶时才动导航，
    // 否则 popToRoot / back 会把人家后来推的那层弹掉（结果照样用提示条告诉他）
    const onTop = (): boolean => stack.top === L
    btn.onclick = async () => {
      if (!ok() || busy) return
      const v = values()
      busy = true; paint()
      try {
        if (page === 'login' || page === 'register') {
          await login(v.user, v.pass, page === 'register')
          stack.whenTop(L, popToRoot)
          toast(page === 'register' ? '注册成功' : '已登录')
        } else if (page === 'password') {
          await changePassword(v.pass, v.next)
          stack.whenTop(L, back)
          toast('密码已修改')
        } else {
          const sure = await confirmDialog({ title: '注销账号', message: '云端的自选、画线、提醒都会删除，本机这份留着', confirm: '注销', destructive: true })
          if (!sure || !onTop()) { busy = false; paint(); return }
          await deleteAccount(v.pass)
          stack.whenTop(L, popToRoot)
          toast('账号已注销')
        }
      } catch (err) {
        busy = false
        const text = errorText(err, page === 'login' ? 'login' : page === 'register' ? 'register' : 'password')
        if (!onTop()) { toast(text); return }
        errEl.textContent = text
        errEl.hidden = false
        paint()
      }
    }
    L.off.push(() => { busy = false })
    paint()
    requestAnimationFrame(() => input(fields[0][0])?.focus({ preventScroll: true }))
  }

  // ───────── 生命周期 ─────────
  renderRoot()
  onSession(renderRoot)
  onAlertsChange(renderRoot)
  trackScroll(rootScroll, 'me.root')
  restoreScroll(rootScroll, 'me.root')
  // 验收截图用：?open=account|alerts|settings 直接推到那一层（读完从地址里去掉）
  const deep = takeOpenParam(['account', 'alerts', 'settings'])
  if (deep) go(deep)
  return {
    show() { renderRoot() },
    hide() { (document.activeElement as HTMLElement | null)?.blur?.() },
    reselect() { if (stack.depth > 1) popToRoot(); else rootScroll.scrollTo({ top: 0, behavior: 'smooth' }) },
  }
}
