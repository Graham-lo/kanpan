/* Hkline Web · 我的：外观、通用（行情线路）、通知、关于；账号 / 交易所 / 设备等登录接入后再开 */
import { st, save } from '../app/store'
import { hooks, applyTheme } from '../app/shell'
import { $, I, esc, tgt } from '../ui/dom'
import { toast } from '../ui/overlay'
import { setRoute } from '../market'
import { session } from '../account/session'
import { openShortcuts } from './chart'

const ME: [string, string, string][] = [['account', 'user', '账号'], ['exchange', 'key', '交易所账号'], ['notify', 'bell', '通知'], ['look', 'palette', '外观'], ['general', 'gear', '通用'], ['devices', 'device', '设备'], ['about', 'info', '关于']]
const VERSION = '0.1.0'

const row = (t: string, d: string, ctl: string): string => `<div class="row"><div class="rl"><div class="t">${t}</div>${d ? `<div class="d">${d}</div>` : ''}</div>${ctl}</div>`
const seg = (k: string, v: string, opts: [string, string][]): string => `<div class="seg" role="group">${opts.map(([x, l]) => `<button data-seg="${k}" data-v="${x}" aria-pressed="${v === x}">${l}</button>`).join('')}</div>`
const later = (title: string, lede: string): string => `<h2>${title}</h2><p class="lede">${lede}</p><div class="group"><div class="empty" style="padding:32px 16px">${I('user', 'icon-24')}<div>网页版登录下一阶段接入</div></div></div>`

function notifText(): string {
  if (!('Notification' in window)) return '这个浏览器不支持'
  return ({ granted: '已允许', denied: '被浏览器拦了，要在地址栏左边的站点设置里打开', default: '还没问过' } as Record<NotificationPermission, string>)[Notification.permission]
}

function render(): void {
  if (!ME.some(m => m[0] === st.meSection)) st.meSection = 'look'
  const u = session.user
  $('#meNav').innerHTML = `<div class="who"><span class="avatar ${u ? '' : 'out'}">${u ? esc(u[0].toUpperCase()) : I('user', 'icon-16')}</span><div><div style="font-weight:600">${u ? esc(u) : '未登录'}</div><div class="muted" style="font-size:12px;line-height:16px">${u ? '这台电脑 · 在线' : '自选、画线、提醒存在这台电脑上'}</div></div></div>
    ${ME.map(([k, ic, l]) => `<a href="#me" data-me="${k}" ${st.meSection === k ? 'aria-current="page"' : ''}>${I(ic)}${l}</a>`).join('')}`
  const body: Record<string, () => string> = {
    account: () => later('账号', '登录后自选、画线、提醒、指标参数跟着账号走，手机和电脑之间同步；服务器断了本机照常能用。'),
    exchange: () => later('交易所账号', '只读密钥，只用来拉成交做复盘。不能下单、不能提币。'),
    devices: () => later('设备', '每一类设备同时只能有一台在线：手机、平板、电脑各一台。'),
    notify: () => `<h2>通知</h2><p class="lede">提醒响一次就结束。这个网页开着时弹浏览器通知。</p>
      <div class="group">${row('浏览器通知', notifText(), 'Notification' in window && Notification.permission === 'default' ? '<button class="btn secondary sm" id="meNotif">允许</button>' : '')}</div>`,
    look: () => `<h2>外观</h2><p class="lede">跟手机端分开记，这台电脑自己的选择。</p>
      <div class="group">${row('皮肤', '和手机端同名的三套；K 线的红绿不跟皮肤走', seg('skin', st.skin, [['sage', '青苔 · 冷'], ['terra', '陶土 · 暖'], ['classic', '经典 · 白']]))}${row('深浅色', '', seg('theme', st.theme, [['light', '浅色'], ['dark', '深色']]))}${row('涨跌颜色', '', seg('updown', st.updown, [['red-up', '红涨绿跌'], ['green-up', '绿涨红跌']]))}</div>`,
    general: () => `<h2>通用</h2><p class="lede">时间统一用上海时间，不能改；日线在北京时间 8:00 换日。</p>
      <div class="group">${row('行情线路', '只记在这台电脑上。网关走我们自己的服务器，直连连不上时手动切过去', seg('route', st.route, [['direct', '直连'], ['gateway', '网关']]))}</div>`,
    about: () => `<h2>关于</h2><p class="lede">Hkline 网页版 ${VERSION} · 行情来自币安 U 本位合约</p><div class="group">${row('快捷键', '', '<button class="btn secondary sm" id="meKeys">查看</button>')}</div>`,
  }
  $('#meBody').innerHTML = body[st.meSection]()
}

export function initMe(): void {
  $('#page-me').addEventListener('click', e => {
    const t = tgt(e)
    const a = t.closest<HTMLElement>('[data-me]'); if (a) { e.preventDefault(); st.meSection = a.dataset.me || 'look'; save(); render(); return }
    const sg = t.closest<HTMLElement>('[data-seg]')
    if (sg) {
      const k = sg.dataset.seg, v = sg.dataset.v || ''
      if (k === 'skin') st.skin = v as typeof st.skin
      if (k === 'theme') st.theme = v as typeof st.theme
      if (k === 'updown') st.updown = v as typeof st.updown
      if (k === 'route') { st.route = v as typeof st.route; setRoute(st.route); toast(v === 'gateway' ? '已切到网关' : '已切到直连', '只影响这台电脑', 'link', 1800) }
      save()
      if (k === 'theme' || k === 'updown' || k === 'skin') applyTheme()
      render(); return
    }
    if (t.closest('#meKeys')) { openShortcuts(); return }
    if (t.closest('#meNotif')) void Notification.requestPermission().then(render)
  })
  hooks.pageShown.me = render
  hooks.onTheme.push(() => { if (st.page === 'me') render() })
}
