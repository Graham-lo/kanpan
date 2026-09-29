/* 手机网页版 · 全部预警与提醒监听（照 iOS Alerts/AlertListPage.swift、AlertRecordRow.swift、AlertWatcher）
 *
 * - buildAlertList(host, opts)：「全部预警」那一页的正文。分「价格提醒 N」「画线提醒 N」两类，
 *   每类一张分组卡：品种头（徽章 + BTC/USDT + 币安 · USDT 永续 + 条数）下面挂这只品种的提醒行；
 *   行 = 状态圆点 + 价位（body）+「价格达到」（caption ink3，有 Webhook 时后面一个链接记号）+ 删除 icon。
 *   触发过的不展示（只响一次，响完就从表里删掉）。空表：铃铛 +「暂无预警」。
 * - recordRowHTML：创建提醒页底下「当前提醒」也用同一种行。
 * - startAlertWatcher()：常驻监听（幂等）。订有提醒挂着的品种的 ticker（切后台也保住），
 *   每笔新价交给 checkPrice；响了：全局提示条 + 系统通知（允许了才弹）+ 没登录时本机发 Webhook
 *   （登录后由服务端发，免得发两遍，照 PC webhookByPage）。
 */
import '../styles/alerts.css'
import { S, on, streamName } from '../../market'
import { loggedIn } from '../../account/session'
import { baseOf, priceLabel, webhookByPage } from '../../alerts/shape'
import { toast } from '../ui/toast'
import { icon } from '../ui/icons'
import { esc } from '../model/rowText'
import { badgeHTML } from '../model/badge'
import { factsOf, splitSymbol } from '../model/rowHTML'
import {
  deleteAlert, onAlertFired, onAlertsChange, recordTitle, restoreAlert, sections, watchedSymbols, checkPrice, webhookBody,
  type Alert,
} from '../model/alerts'
import { hooks } from '../app/shell'
import { wantStreams } from './_streams'

const LINK = '<svg width="11" height="11" viewBox="0 0 24 24" aria-label="Webhook" role="img"><path d="M10 14a4.5 4.5 0 0 0 6.4 0l3.2-3.2a4.5 4.5 0 0 0-6.4-6.4L12 5.6M14 10a4.5 4.5 0 0 0-6.4 0l-3.2 3.2a4.5 4.5 0 0 0 6.4 6.4L12 18.4" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/></svg>'
const BELL = '<svg width="36" height="36" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2.5a1.5 1.5 0 0 1 1.5 1.5v.6A6.5 6.5 0 0 1 18.5 11v3.6l1.6 2.3a1 1 0 0 1-.8 1.6H4.7a1 1 0 0 1-.8-1.6l1.6-2.3V11a6.5 6.5 0 0 1 5-6.4V4A1.5 1.5 0 0 1 12 2.5zM9.5 19.5h5a2.5 2.5 0 0 1-5 0z"/></svg>'

/** 品种卡第二行：「币安 · USDT 永续」 */
export const venueLine = (symbol: string): string => {
  const { quote } = splitSymbol(symbol)
  return '币安 · ' + (quote ? quote + ' 永续' : '永续')
}
export const pairName = (symbol: string): string => {
  const { base, quote } = splitSymbol(symbol)
  return quote ? `${base}/${quote}` : base
}

/** 一行提醒（圆点 + 价位 + 价格达到 + 删除） */
export function recordRowHTML(a: Alert, opts: { withSymbol?: boolean; divider?: boolean } = {}): string {
  const meta = a.kind === 'price' || a.kind === 'drawing' ? '价格达到' : '条件提醒'
  return `<div class="alr${opts.divider === false ? ' last' : ''}" data-id="${esc(a.id)}">
    <button type="button" class="alr-main" data-open="${esc(a.id)}">
      <i class="alr-dot" aria-hidden="true"></i>
      <span class="alr-text"><span class="alr-title num">${esc(recordTitle(a, !!opts.withSymbol))}</span>
        <span class="alr-meta">${meta}${a.webhook ? `<span class="alr-link">${LINK}</span>` : ''}</span></span>
    </button>
    <button type="button" class="alr-del" data-del="${esc(a.id)}" aria-label="删除">${icon('trash', 15)}</button>
  </div>`
}

function symbolHeadHTML(symbol: string, count: number): string {
  const f = factsOf(symbol, S.symbols.get(symbol))
  return `<div class="alh" data-sym="${esc(symbol)}">${badgeHTML(f.base, 28, f.asset)}
    <span class="alh-pair">${esc(pairName(symbol))}</span><span class="alh-venue">${esc(venueLine(symbol))}</span>
    <span class="alh-count num">${count}</span></div>`
}

/** 删一条：从表里拿掉，给 5 秒撤销 */
export function deleteWithUndo(id: string): void {
  const gone = deleteAlert(id)
  if (gone) toast('已删除提醒', { title: '撤销', run: () => restoreAlert(gone) })
}

/** 「全部预警」正文；返回解绑 */
export function buildAlertList(host: HTMLElement, opts: { onOpen?: (a: Alert) => void } = {}): () => void {
  host.classList.add('all-alerts')
  const render = (): void => {
    const secs = sections().filter(s => s.count > 0)
    if (!secs.length) {
      host.innerHTML = `<div class="al-empty">${BELL}<span>暂无预警</span></div>`
      return
    }
    host.innerHTML = secs.map(sec => `<section class="al-sec" data-kind="${sec.id}">
      <div class="al-title num">${sec.title} ${sec.count}</div>
      <div class="al-card">${sec.groups.map((g, gi) => symbolHeadHTML(g.symbol, g.alerts.length)
        + g.alerts.map((a, i) => recordRowHTML(a, { divider: !(gi === sec.groups.length - 1 && i === g.alerts.length - 1) })).join('')).join('')}</div>
    </section>`).join('')
  }
  const byId = (id: string): Alert | undefined => sections().flatMap(s => s.groups.flatMap(g => g.alerts)).find(a => a.id === id)
  const onClick = (e: Event): void => {
    const t = e.target as HTMLElement
    const del = t.closest<HTMLElement>('[data-del]')
    if (del) { deleteWithUndo(del.dataset.del!); return }
    const open = t.closest<HTMLElement>('[data-open]')
    if (open) { const a = byId(open.dataset.open!); if (a) opts.onOpen?.(a) }
  }
  host.addEventListener('click', onClick)
  const off = onAlertsChange(render)
  render()
  return () => { off(); host.removeEventListener('click', onClick) }
}

// ───────── 常驻监听 ─────────

let watching = false
/** 开始监听（幂等）：有提醒挂着的品种订 ticker，新价交给判定；响了就报 */
export function startAlertWatcher(): void {
  if (watching) return
  watching = true
  const resubscribe = (): void => {
    const syms = watchedSymbols()
    wantStreams('alerts', [], syms.map(s => streamName.ticker(s)))
    for (const s of syms) checkPrice(s, S.symbols.get(s)?.price)
  }
  onAlertsChange(resubscribe)
  on(e => {
    if (e.type === 'ticker') checkPrice(e.symbol, S.symbols.get(e.symbol)?.price)
    else if (e.type === 'universe') resubscribe()
  })
  onAlertFired(({ alert, price, level }) => {
    const text = `${alert.title}，现价 ${priceLabel(price, S.symbols.get(alert.symbol)?.dec)}`
    toast(text)
    notify(baseOf(alert.symbol) + ' 提醒', text, alert.id)
    if (alert.webhook && webhookByPage(alert, false, loggedIn())) {
      void fetch(alert.webhook, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: JSON.stringify(webhookBody(alert, price, Date.now(), level)) }).catch(() => { /* 对方收不收是对方的事 */ })
    }
  })
  hooks.onForeground.push(resubscribe)
  resubscribe()
}

function notify(title: string, body: string, tag: string): void {
  try {
    if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return
    const opts = { body, tag, icon: import.meta.env.BASE_URL + 'm/icon-192.png' }
    // 加到主屏幕的 PWA 里 new Notification 不可用，要经 service worker
    if (navigator.serviceWorker?.controller) void navigator.serviceWorker.ready.then(r => r.showNotification(title, opts)).catch(() => {})
    else new Notification(title, opts)
  } catch { /* 浏览器不给就算了，提示条已经说过 */ }
}

/** 建完第一条提醒时要一次通知权限（照 iOS 创建后 requestAuthorization） */
export function askNotifyPermission(): void {
  try {
    if (typeof Notification !== 'undefined' && Notification.permission === 'default') void Notification.requestPermission().catch(() => {})
  } catch { /* 忽略 */ }
}
