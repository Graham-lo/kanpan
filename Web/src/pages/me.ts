/* Hkline Web · 我的：账号（登录 / 注册 / 改密码 / 退出）、设备、外观、通用（行情线路、从 TradingView 导入自选）、通知、关于 */
import { st, save } from '../app/store'
import { hooks, applyTheme, renderHeader } from '../app/shell'
import { $, I, esc, tgt } from '../ui/dom'
import { toast } from '../ui/overlay'
import { setRoute } from '../market'
import { session, onSession } from '../account/session'
import { login, logout, devices, kick, changePassword, deleteAccount, errorText, type DeviceRow } from '../account/client'
import { sh, pad } from '../util/format'
import { openShortcuts, renderPanel, refreshStreams } from './chart'
import { tvImportHTML, tvImportClick, tvImportChange, onTvImported } from '../watch/importPanel'
import { reviewApi, errorText as reviewErrorText } from '../review/api'
import { NO_KEY_TEXT, venueRows, type VenueRow } from '../trades/panel'
import '../styles/account.css'

const ME: [string, string, string][] = [['account', 'user', '账号'], ['exchange', 'key', '交易所账号'], ['notify', 'bell', '通知'], ['look', 'palette', '外观'], ['general', 'gear', '通用'], ['devices', 'device', '设备'], ['about', 'info', '关于']]
const VERSION = '0.1.0'

const row = (t: string, d: string, ctl: string): string => `<div class="row"><div class="rl"><div class="t">${t}</div>${d ? `<div class="d">${d}</div>` : ''}</div>${ctl}</div>`
const seg = (k: string, v: string, opts: [string, string][]): string => `<div class="seg" role="group">${opts.map(([x, l]) => `<button data-seg="${k}" data-v="${x}" aria-pressed="${v === x}">${l}</button>`).join('')}</div>`

// ───────── 账号 ─────────

const KIND_CN: Record<string, string> = { desktop: '电脑', phone: '手机', tablet: '平板' }
let authMode: 'login' | 'register' = 'login'
let busy = false
/** 设备列表：null 表示还没拉（进「设备」时拉一次） */
let devs: { rows: DeviceRow[] | null; err: string } = { rows: null, err: '' }

function when(t: number): string {
  if (!t) return ''
  const d = sh(t), today = sh(Date.now())
  const hm = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`
  if (d.getUTCFullYear() === today.getUTCFullYear() && d.getUTCMonth() === today.getUTCMonth() && d.getUTCDate() === today.getUTCDate()) return '今天 ' + hm
  const md = `${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`
  return (d.getUTCFullYear() === today.getUTCFullYear() ? md : `${d.getUTCFullYear()}-${md}`) + ' ' + hm
}

function accountHTML(): string {
  const u = session.user
  if (!u) {
    const reg = authMode === 'register'
    return `<h2>账号</h2><p class="lede">登录后自选、画线、提醒、指标参数和手机同步。</p>
      ${session.notice ? `<div class="acct-notice">${I('info', 'icon-16')}<span>${esc(session.notice)}</span></div>` : ''}
      <form class="group acct-card" id="acctForm" novalidate>
        <div class="seg fill" role="group">${(['login', 'register'] as const).map(m => `<button type="button" data-auth="${m}" aria-pressed="${authMode === m}">${m === 'login' ? '登录' : '注册'}</button>`).join('')}</div>
        <div class="field"><label for="acctUser">用户名</label><input class="input lg" id="acctUser" name="username" autocomplete="username" autocapitalize="off" spellcheck="false" maxlength="32" ${reg ? 'placeholder="小写字母、数字、下划线"' : ''}></div>
        <div class="field"><label for="acctPass">密码</label><input class="input lg" id="acctPass" name="password" type="password" autocomplete="${reg ? 'new-password' : 'current-password'}" ${reg ? 'placeholder="至少 8 位，字母加数字"' : ''}></div>
        <div class="err" id="acctErr" role="alert"></div>
        <button class="btn primary lg" type="submit" id="acctGo">${reg ? '注册并登录' : '登录'}</button>
      </form>`
  }
  return `<h2>账号</h2><p class="lede">自选、画线、提醒、指标参数和手机同步。</p>
    <div class="group">${row('用户名', '', `<span class="acct-name">${esc(u)}</span>`)}${row('退出登录', '这台电脑上的自选、画线、提醒都留着', '<button class="btn secondary sm" id="acctLogout">退出</button>')}</div>
    <div class="group-title">修改密码</div>
    <form class="group acct-card" id="pwForm" novalidate>
      <input type="text" name="username" autocomplete="username" value="${esc(u)}" hidden>
      <div class="field"><label for="pwCur">当前密码</label><input class="input lg" id="pwCur" type="password" autocomplete="current-password"></div>
      <div class="field"><label for="pwNew">新密码</label><input class="input lg" id="pwNew" type="password" autocomplete="new-password" placeholder="至少 8 位，字母加数字"></div>
      <div class="err" id="pwErr" role="alert"></div>
      <button class="btn secondary lg" type="submit" id="pwGo">修改密码</button>
    </form>
    <div class="group-title">注销账号</div>
    <form class="group acct-card" id="closeForm" novalidate>
      <input type="text" name="username" autocomplete="username" value="${esc(u)}" hidden>
      <div class="acct-warn">云端的自选、画线、提醒、复盘记录会全部删除，不能恢复；这台电脑上的数据留着</div>
      <div class="field"><label for="closePass">密码</label><input class="input lg" id="closePass" type="password" autocomplete="current-password"></div>
      <div class="err" id="closeErr" role="alert"></div>
      <button class="btn danger lg" type="submit" id="closeGo">${closeArmed ? '再点一次，确认注销' : '注销账号'}</button>
    </form>`
}

function devicesHTML(): string {
  const head = '<h2>设备</h2><p class="lede">手机、平板、电脑各一台同时在线，同类设备登录会把前一台顶下去。</p>'
  if (!session.user) return head + `<div class="group"><div class="empty" style="padding:32px 16px">${I('device', 'icon-24')}<div>登录后能看到这个账号在哪些设备上登录</div><button class="btn primary sm" style="margin-top:12px" data-me="account">去登录</button></div></div>`
  if (!devs.rows) {
    if (!devs.err) void loadDevices()
    return head + `<div class="group">${devs.err ? `<div class="empty" style="padding:32px 16px"><div>${esc(devs.err)}</div><button class="btn secondary sm" style="margin-top:12px" id="devRetry">重试</button></div>` : '<div class="empty" style="padding:32px 16px">正在读取…</div>'}</div>`
  }
  const rows = [...devs.rows].sort((a, b) => Number(b.current) - Number(a.current) || b.lastSeen - a.lastSeen)
  return head + `<div class="group">${rows.map(d => row(
    `${esc(d.name || KIND_CN[d.kind] || '设备')}${d.current ? ' <span class="tag accent">这台</span>' : ''}`,
    `${KIND_CN[d.kind] ?? '设备'} · ${d.current ? '正在用' : '最近 ' + when(d.lastSeen)}`,
    d.current ? '' : `<button class="btn secondary sm" data-kick="${esc(d.id)}">下线</button>`,
  )).join('') || '<div class="empty">没有登录中的设备</div>'}</div>`
}

// ───────── 交易所账号 ─────────
// 只读密钥只在手机上绑定、只存在手机上；手机拉成交传到服务端拼成回合，网页只读服务端的回合。
// 服务端没有单独的「绑定状态」接口，这里按它收到的交易回合推：哪家交易所、哪个账户、最近一次上传。

let venues: { rows: VenueRow[] | null; err: string } = { rows: null, err: '' }

let venLoading = false
async function loadVenues(): Promise<void> {
  if (venLoading) return
  venLoading = true
  try { venues = { rows: venueRows(await reviewApi.trades()), err: '' } } catch (e) { venues = { rows: null, err: reviewErrorText(e) } }
  venLoading = false
  if (st.page === 'me' && st.meSection === 'exchange') render()
}

function exchangeHTML(): string {
  const head = `<h2>交易所账号</h2><p class="lede">只读密钥，只用来拉成交做复盘，不能下单、不能提币。</p>
    <div class="group">${row('在手机上绑定', '手机「我的 → 交易所」填只读密钥；密钥只存在手机上，网页不存、也不经手', '')}${row('成交怎么到网页', '手机拉取成交后上传到服务端，拼成交易回合；网页的复盘与图表侧栏「成交」读的都是这一份', '')}</div>
    <div class="group-title">服务端收到的成交</div>`
  if (!session.user) return head + `<div class="group"><div class="empty" style="padding:32px 16px">${I('key', 'icon-24')}<div>登录后能看到手机传上来的是哪家交易所、最近什么时候传的</div><button class="btn primary sm" style="margin-top:12px" data-me="account">去登录</button></div></div>`
  if (!venues.rows) {
    if (!venues.err) void loadVenues()
    return head + `<div class="group">${venues.err ? `<div class="empty" style="padding:32px 16px"><div>${esc(venues.err)}</div><button class="btn secondary sm" style="margin-top:12px" id="venRetry">重试</button></div>` : '<div class="empty" style="padding:32px 16px">正在读取…</div>'}</div>`
  }
  if (!venues.rows.length) return head + `<div class="group"><div class="empty" style="padding:32px 16px" data-ex-empty>${I('key', 'icon-24')}<div>${esc(NO_KEY_TEXT)}</div></div></div>`
  return head + `<div class="group" data-ex-venues>${venues.rows.map(v => row(
    `${esc(v.title)}${v.accountTag ? ` <span class="tag">${esc(v.accountTag)}</span>` : ''}`,
    `${v.rounds} 个回合 · 最近一次上传 ${when(v.lastUpload)}${v.lastFill ? ` · 最新成交 ${when(v.lastFill)}` : ''}`,
    '',
  )).join('')}</div>`
}

async function loadDevices(): Promise<void> {
  try { devs = { rows: await devices(), err: '' } } catch (e) { devs = { rows: null, err: errorText(e) } }
  if (st.page === 'me' && st.meSection === 'devices') render()
}

function setErr(id: string, text: string): void { const el = document.getElementById(id); if (el) el.textContent = text }
function val(id: string): string { return (document.getElementById(id) as HTMLInputElement | null)?.value ?? '' }

async function submitAuth(): Promise<void> {
  if (busy) return
  const u = val('acctUser').trim(), p = val('acctPass')
  if (!u || !p) { setErr('acctErr', '用户名和密码都要填'); return }
  busy = true
  const btn = document.getElementById('acctGo') as HTMLButtonElement | null
  if (btn) btn.disabled = true
  try {
    await login(u, p, authMode === 'register')
    devs = { rows: null, err: '' }; venues = { rows: null, err: '' }
    toast(authMode === 'register' ? '注册好了' : '已登录', '自选、画线、提醒开始和手机同步', 'check', 2400)
  } catch (e) {
    setErr('acctErr', errorText(e, authMode))
    if (btn) btn.disabled = false
  } finally { busy = false }
}

async function submitPassword(): Promise<void> {
  if (busy) return
  const cur = val('pwCur'), next = val('pwNew')
  if (!cur || !next) { setErr('pwErr', '两个都要填'); return }
  if (cur === next) { setErr('pwErr', '新密码和当前密码一样'); return }
  busy = true
  const btn = document.getElementById('pwGo') as HTMLButtonElement | null
  if (btn) btn.disabled = true
  try {
    await changePassword(cur, next)
    devs = { rows: null, err: '' }; venues = { rows: null, err: '' }
    toast('密码已修改', '其它设备已下线', 'check', 3000)
    render()
  } catch (e) {
    setErr('pwErr', errorText(e, 'password'))
    if (btn) btn.disabled = false
  } finally { busy = false }
}

/** 注销要点两次：第一次只把按钮变成「再点一次，确认注销」，5 秒内再点才真的删 */
let closeArmed = false
let closeTimer: ReturnType<typeof setTimeout> | null = null
async function submitClose(): Promise<void> {
  if (busy) return
  const pw = val('closePass')
  if (!pw) { setErr('closeErr', '要填当前密码'); return }
  const btn = document.getElementById('closeGo') as HTMLButtonElement | null
  if (!closeArmed) {
    closeArmed = true
    if (btn) btn.textContent = '再点一次，确认注销'
    setErr('closeErr', '')
    if (closeTimer) clearTimeout(closeTimer)
    closeTimer = setTimeout(() => { closeArmed = false; const b = document.getElementById('closeGo'); if (b) b.textContent = '注销账号' }, 5000)
    return
  }
  closeArmed = false
  if (closeTimer) { clearTimeout(closeTimer); closeTimer = null }
  busy = true
  if (btn) btn.disabled = true
  try {
    await deleteAccount(pw)
    devs = { rows: null, err: '' }; venues = { rows: null, err: '' }
    toast('账号已注销', '云端数据已删除，这台电脑上的数据留着', 'check', 4000)
  } catch (e) {
    setErr('closeErr', errorText(e, 'password'))
    if (btn) { btn.disabled = false; btn.textContent = '注销账号' }
  } finally { busy = false }
}

function notifText(): string {
  if (!('Notification' in window)) return '这个浏览器不支持'
  return ({ granted: '已允许', denied: '被浏览器拦了，要在地址栏左边的站点设置里打开', default: '还没问过' } as Record<NotificationPermission, string>)[Notification.permission]
}

function render(): void {
  if (!ME.some(m => m[0] === st.meSection)) st.meSection = 'look'
  const u = session.user
  $('#meNav').innerHTML = `<div class="who"><span class="avatar ${u ? '' : 'out'}">${u ? esc(u[0].toUpperCase()) : I('user', 'icon-16')}</span><div><div style="font-weight:600">${u ? esc(u) : '未登录'}</div><div class="muted" style="font-size:12px;line-height:16px">${u ? '已登录' : '自选、画线、提醒存在这台电脑上'}</div></div></div>
    ${ME.map(([k, ic, l]) => `<a href="#me" data-me="${k}" ${st.meSection === k ? 'aria-current="page"' : ''}>${I(ic)}${l}</a>`).join('')}`
  const body: Record<string, () => string> = {
    account: accountHTML,
    exchange: exchangeHTML,
    devices: devicesHTML,
    notify: () => `<h2>通知</h2><p class="lede">提醒响一次就结束。这个网页开着时弹浏览器通知。</p>
      <div class="group">${row('浏览器通知', notifText(), 'Notification' in window && Notification.permission === 'default' ? '<button class="btn secondary sm" id="meNotif">允许</button>' : '')}</div>`,
    look: () => `<h2>外观</h2><p class="lede">跟手机端分开记，这台电脑自己的选择。</p>
      <div class="group">${row('皮肤', '和手机端同名的三套；K 线的红绿不跟皮肤走', seg('skin', st.skin, [['sage', '青苔 · 冷'], ['terra', '陶土 · 暖'], ['classic', '经典 · 白']]))}${row('深浅色', '', seg('theme', st.theme, [['light', '浅色'], ['dark', '深色']]))}${row('涨跌颜色', '', seg('updown', st.updown, [['red-up', '红涨绿跌'], ['green-up', '绿涨红跌']]))}</div>`,
    general: () => `<h2>通用</h2><p class="lede">时间统一用上海时间，不能改；日线在北京时间 8:00 换日。</p>
      <div class="group">${row('行情线路', '只记在这台电脑上。网关经我们的新加坡服务器转一道，出厂就是它（国内不开代理连不上币安）；直连是浏览器自己连币安，海外或开着代理时少转一道', seg('route', st.route, [['direct', '直连'], ['gateway', '网关']]))}</div>
      ${tvImportHTML()}`,
    about: () => `<h2>关于</h2><p class="lede">Hkline 网页版 ${VERSION} · 行情来自币安 U 本位合约</p><div class="group">${row('快捷键', '', '<button class="btn secondary sm" id="meKeys">查看</button>')}</div>`,
  }
  $('#meBody').innerHTML = body[st.meSection]()
}

export function initMe(): void {
  $('#page-me').addEventListener('click', e => {
    const t = tgt(e)
    const a = t.closest<HTMLElement>('[data-me]'); if (a) { e.preventDefault(); st.meSection = a.dataset.me || 'look'; if (st.meSection === 'devices') devs = { rows: null, err: '' }; if (st.meSection === 'exchange') venues = { rows: null, err: '' }; save(); render(); return }
    const sg = t.closest<HTMLElement>('[data-seg]')
    if (sg) {
      const k = sg.dataset.seg, v = sg.dataset.v || ''
      if (k === 'skin') st.skin = v as typeof st.skin
      if (k === 'theme') st.theme = v as typeof st.theme
      if (k === 'updown') st.updown = v as typeof st.updown
      if (k === 'route') { st.route = v as typeof st.route; st.routePicked = true; setRoute(st.route); toast(v === 'gateway' ? '已切到网关' : '已切到直连', '只影响这台电脑', 'link', 1800) }
      save()
      if (k === 'theme' || k === 'updown' || k === 'skin') applyTheme()
      render(); return
    }
    const au = t.closest<HTMLElement>('[data-auth]')
    if (au) { authMode = au.dataset.auth === 'register' ? 'register' : 'login'; const keep = val('acctUser'); render(); const el = document.getElementById('acctUser') as HTMLInputElement | null; if (el) { el.value = keep; (keep ? document.getElementById('acctPass') : el)?.focus() } return }
    if (t.closest('#acctLogout')) { logout(); devs = { rows: null, err: '' }; toast('已退出', '这台电脑上的数据都留着', 'logout', 2000); return }
    if (t.closest('#devRetry')) { devs = { rows: null, err: '' }; render(); return }
    if (t.closest('#venRetry')) { venues = { rows: null, err: '' }; render(); return }
    const kb = t.closest<HTMLButtonElement>('[data-kick]')
    if (kb) {
      kb.disabled = true
      void kick(kb.dataset.kick || '').then(() => { toast('已让那台设备下线', '', 'check', 2000); devs = { rows: null, err: '' }; render() })
        .catch(err => { kb.disabled = false; toast('没能下线', errorText(err), 'info', 3000) })
      return
    }
    if (t.closest('#meKeys')) { openShortcuts(); return }
    if (tvImportClick(e, render)) return
    if (t.closest('#meNotif')) void Notification.requestPermission().then(render)
  })
  $('#page-me').addEventListener('change', e => { tvImportChange(e, render) })
  $('#page-me').addEventListener('input', e => { if ((e.target as HTMLElement).id === 'tviText') tvImportChange(e, render) })
  onTvImported(() => { renderPanel(); refreshStreams() })
  $('#page-me').addEventListener('submit', e => {
    const f = e.target as HTMLElement
    if (f.id === 'acctForm') { e.preventDefault(); void submitAuth() }
    else if (f.id === 'pwForm') { e.preventDefault(); void submitPassword() }
    else if (f.id === 'closeForm') { e.preventDefault(); void submitClose() }
  })
  // 登录 / 退出 / 被另一台电脑顶掉：头像、我的页跟着变；不在「我的」时弹一句
  onSession(() => {
    renderHeader()
    devs = { rows: null, err: '' }; venues = { rows: null, err: '' }
    if (st.page === 'me') render()
    else if (session.notice) toast(session.notice, '到「我的」重新登录', 'user', 6000)
  })
  hooks.pageShown.me = () => { if (st.meSection === 'devices') devs = { rows: null, err: '' }; if (st.meSection === 'exchange') venues = { rows: null, err: '' }; render() }
  hooks.onTheme.push(() => { if (st.page === 'me') render() })
}
