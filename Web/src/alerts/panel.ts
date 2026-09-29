/* Hkline Web · 提醒模块（界面与盯盘）
 *
 * 三块界面，规矩和手机「创建提醒」页一致：
 *   · 侧栏「提醒」：只列这只品种还没触发的；右上「全部」打开按品种分组的总表；行上只有删除
 *   · 「创建提醒」对话框：品种不可改；条件叫「价格达到」；Webhook 只填地址；没有备注、没有重复
 *   · 总表：按品种分组，价格 / 画线 / 条件三类可筛
 * 盯盘：逐笔价看价格与画线提醒；资金费率在结算前 15 分钟那个窗口里看；持仓量每分钟看一次最近一小时。
 * 响了就弹通知（浏览器通知 + 页内提示）；没登录时 Webhook 由这个网页自己发（登录后由服务端发，不重复）。
 */
import { loggedIn } from '../account/session'
import { st } from '../app/store'
import { S, on, j, REST } from '../market'
import { $, $$, I, esc, tgt } from '../ui/dom'
import { dialog, head, toast, type Dialog } from '../ui/overlay'
import { badge, cls, pctText, priceText, shTime, sym } from '../ui/common'
import { fmt } from '../util/format'
import {
  activeAlerts, addAlert, alertLevel, checkPrice, cleanWebhook, conditionLabel, deleteAlert, fire, fundingHit, makeConditionAlert,
  makePriceAlert, oiHit, onAlertFired, onAlertsChange, rulePhrase, setQuoteSource, validWebhook, webhookBody, type Alert, type AlertRule,
} from './model'

export interface AlertUIHooks {
  /** 打开某只品种（总表里点品种名） */
  openSymbol: (symbol: string) => void
}
let ui: AlertUIHooks = { openSymbol: () => { /* 页面装上前什么都不做 */ } }

const decOf = (k: string): number => sym(k)?.dec ?? 2
const code = (k: string): string => sym(k)?.code || k
const LINE_NAME: Record<string, string> = { hline: '水平线', trend: '趋势线', ray: '射线' }

// ------------------------------------------------------------ 一行
function kindTag(a: Alert): string { return a.kind === 'drawing' ? '画线' : a.kind === 'condition' ? '条件' : '价格' }
export function alertDesc(a: Alert): string {
  if (a.kind === 'condition') return esc(rulePhrase(a.rule))
  const lv = alertLevel(a)
  if (a.kind === 'drawing') {
    const type = (a.drawingID || '').split('/').pop() || ''
    const d = (st.drawings[a.symbol] || []).find(x => x.id === type)
    return `触到${d ? LINE_NAME[d.type] || '画线' : '画线'}${lv != null ? ` <span class="num">${fmt(lv, decOf(a.symbol))}</span>` : ''}`
  }
  return `${conditionLabel(a.condition)} <span class="num">${lv != null ? fmt(lv, decOf(a.symbol)) : '—'}</span>`
}
function alertSub(a: Alert): string {
  const last = sym(a.symbol)?.price, lv = a.kind === 'condition' ? null : alertLevel(a)
  const dist = last && lv != null ? (lv - last) / last * 100 : null
  const parts: string[] = []
  if (dist != null) parts.push(`距现价 <span class="num">${dist >= 0 ? '+' : ''}${dist.toFixed(2)}%</span>`)
  parts.push(`${shTime(a.created)} 创建`)
  if (a.webhook) parts.push('Webhook')
  return parts.join(' · ')
}
function row(a: Alert, withSym: boolean): string {
  const s = sym(a.symbol)
  return `<div class="list-row alert-row" data-alert="${esc(a.id)}">${withSym ? badge(s, 'lg') : `<span class="alert-kind" data-kind="${a.kind}">${I(a.kind === 'drawing' ? 'trend' : a.kind === 'condition' ? 'indicators' : 'bell', 'icon-16')}</span>`}
    <div class="main"><div class="t1">${withSym ? `${esc(code(a.symbol))}<span class="tag">${kindTag(a)}</span>` : ''}<span>${alertDesc(a)}</span></div>
    <div class="t2">${alertSub(a)}</div></div>
    <button class="ibtn sm" data-del-alert="${esc(a.id)}" aria-label="删除提醒" data-tip="删除">${I('trash', 'icon-16')}</button></div>`
}

// ------------------------------------------------------------ 侧栏
export function renderAlertsPanel(el: HTMLElement, symbol: string): void {
  const mine = activeAlerts(symbol).sort((a, b) => b.created - a.created)
  const total = activeAlerts().length
  el.innerHTML = `<div class="sp-head"><h3>提醒</h3>
      <button class="ibtn sm" id="aNew" aria-label="创建提醒" data-tip="创建提醒" data-kbd="Alt A">${I('plus')}</button>
      <button class="btn ghost sm" id="aAllBtn" data-tip="所有品种的提醒">全部<span class="num faint" style="margin-left:4px">${total}</span></button></div>
    <div class="sp-sub"><span class="alert-sym">${badge(sym(symbol))}<b>${esc(code(symbol))}</b></span><span class="faint num">${mine.length ? `${mine.length} 条在等` : ''}</span></div>
    <div class="scroll" style="flex:1;min-height:0">
    ${mine.length ? mine.map(a => row(a, false)).join('') : `<div class="empty">${I('bell', 'icon-24')}<div>这只品种没有在等的提醒</div><div class="faint" style="font-size:12px;margin-top:4px">点价格轴，或在图上右键</div></div>`}
    </div>`
}
/** 侧栏里的点击；认得就返回 true */
export function alertsPanelClick(e: MouseEvent, symbol: string): boolean {
  const t = tgt(e)
  const del = t.closest<HTMLElement>('[data-del-alert]'); if (del) { deleteAlert(del.dataset.delAlert || ''); return true }
  if (t.closest('#aAllBtn')) { openAllAlerts(); return true }
  if (t.closest('#aNew')) { openCreateAlert(symbol); return true }
  return false
}

// ------------------------------------------------------------ 总表
export function openAllAlerts(): void {
  type F = 'all' | 'price' | 'drawing' | 'condition'
  let f: F = 'all'
  let off = (): void => { /* 下面挂上 */ }
  const d = dialog(`${head('全部提醒')}<div class="dialog-body alerts-all">
      <div class="seg" id="aaF" role="tablist"></div>
      <div class="scroll" id="aaList"></div></div>`, 'alerts-all-dlg', { label: '全部提醒', onClose: () => off() })
  const render = (): void => {
    const all = activeAlerts()
    const counts: Record<F, number> = { all: all.length, price: 0, drawing: 0, condition: 0 }
    all.forEach(a => { if (a.kind in counts) counts[a.kind as F]++ })
    $('#aaF', d.dlg).innerHTML = ([['all', '全部'], ['price', '价格'], ['drawing', '画线'], ['condition', '条件']] as [F, string][])
      .filter(([k]) => k === 'all' || counts[k]).map(([k, l]) => `<button data-f="${k}" aria-pressed="${k === f}">${l}<span class="num faint">${counts[k]}</span></button>`).join('')
    const list = all.filter(a => f === 'all' || a.kind === f)
    const bySym = new Map<string, Alert[]>()
    for (const a of list) { const g = bySym.get(a.symbol) || []; g.push(a); bySym.set(a.symbol, g) }
    const groups = [...bySym.entries()].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]))
    $('#aaList', d.dlg).innerHTML = groups.length ? groups.map(([k, as]) => {
      const s = sym(k)
      return `<div class="aa-group"><button class="aa-head" data-open="${esc(k)}" data-tip="打开这只品种">${badge(s)}<b>${esc(code(k))}</b><span class="muted">${esc(s?.cn || '')}</span>
        <span class="aa-px num">${priceText(s)}</span><span class="num ${cls(s?.pct)}">${pctText(s?.pct)}</span><span class="faint num">${as.length} 条</span></button>
        ${as.sort((a, b) => b.created - a.created).map(a => row(a, false)).join('')}</div>`
    }).join('') : `<div class="empty">${I('bell', 'icon-24')}<div>没有在等的提醒</div></div>`
  }
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const fb = t.closest<HTMLElement>('[data-f]'); if (fb) { f = fb.dataset.f as F; render(); return }
    const del = t.closest<HTMLElement>('[data-del-alert]'); if (del) { deleteAlert(del.dataset.delAlert || ''); return }
    const op = t.closest<HTMLElement>('[data-open]'); if (op) { d.close(); ui.openSymbol(op.dataset.open || '') }
  })
  off = onAlertsChange(render)
  render()
}

// ------------------------------------------------------------ 创建
type CKind = 'price' | 'funding' | 'oi'
let createDlg: Dialog | null = null
export function openCreateAlert(symbol: string, price?: number | null): void {
  createDlg?.close()
  const s = sym(symbol), dec = decOf(symbol)
  const last = s?.price ?? null
  if (last == null && price == null) { toast('还没有这只品种的价格', '行情连上后再建', 'info'); return }
  const p0 = price ?? last!
  let kind: CKind = 'price'
  let off = (): void => { /* 下面挂上 */ }
  const KINDS: [CKind, string][] = [['price', '价格达到'], ['funding', '资金费率'], ['oi', '持仓量变化']]
  const d = dialog(`${head('创建提醒', `<button class="btn ghost sm" id="aAll">全部提醒</button>`)}<div class="dialog-body"><div class="form-grid">
    <div class="sym-card">${badge(s, 'lg')}<div style="flex:1"><b>${esc(code(symbol))}</b><div class="muted" style="font-size:12px;line-height:16px">${esc(s?.cn || symbol)}</div></div><div style="text-align:right"><div class="num" style="font-weight:600">${last != null ? fmt(last, dec) : '—'}</div><div class="num ${cls(s?.pct)}" style="font-size:12px;line-height:16px">${pctText(s?.pct)}</div></div></div>
    <div class="field"><label>条件</label><div class="seg fill" id="aKind">${KINDS.map(([k, l]) => `<button data-k="${k}" aria-pressed="${k === kind}">${l}</button>`).join('')}</div></div>
    <div id="aVal"></div>
    <div class="field"><label for="aHook">Webhook 地址 <span class="faint" style="font-weight:400">选填</span></label><div class="input-wrap"><input id="aHook" class="input" inputmode="url" autocomplete="off" spellcheck="false" placeholder="https://"></div><div class="hint" id="aHookHint"></div></div>
    <div id="aExisting"></div>
    </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center">响一次就结束</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="aOk">创建</button></div>`, 'alert-dlg', { label: '创建提醒', onClose: () => { if (createDlg === d) createDlg = null; off() } })
  createDlg = d
  function renderVal(): void {
    const v = $('#aVal', d.dlg)
    if (kind === 'price') {
      v.innerHTML = `<div class="field"><label for="aPrice">价格</label><div class="input-wrap"><input id="aPrice" class="input lg num" inputmode="decimal" value="${p0.toFixed(dec)}"><span class="suffix">USDT</span></div><div class="hint num" id="aHint"></div></div>`
      const inp = $<HTMLInputElement>('#aPrice', d.dlg)
      const hint = () => { const p = +inp.value; $('#aHint', d.dlg).textContent = !(p > 0) ? '填一个价格' : last == null ? '' : `比现价${p >= last ? '高' : '低'} ${Math.abs((p - last) / last * 100).toFixed(2)}%` }
      inp.addEventListener('input', hint); hint(); inp.focus(); inp.select()
    } else if (kind === 'funding') v.innerHTML = `<div class="field"><label>资金费率</label><div style="display:flex;gap:8px"><div class="seg" id="aOp"><button data-op="above" aria-pressed="true">高于</button><button data-op="below" aria-pressed="false">低于</button></div><div class="input-wrap" style="flex:1"><input id="aNum" class="input num" inputmode="decimal" value="0.05"><span class="suffix">%</span></div></div><div class="hint">现在 <span class="num">${s?.fr != null ? (s.fr * 100).toFixed(4) + '%' : '—'}</span> · 结算前 15 分钟判</div></div>`
    else v.innerHTML = `<div class="field"><label>1 小时内持仓量变化超过</label><div class="input-wrap"><input id="aNum" class="input num" inputmode="decimal" value="5"><span class="suffix">%</span></div><div class="hint">增减都算</div></div>`
    $<HTMLInputElement>('#aNum', d.dlg)?.focus()
  }
  function renderExisting(): void {
    const mine = activeAlerts(symbol)
    $('#aExisting', d.dlg).innerHTML = mine.length ? `<div class="field"><label>这只品种还在等的</label><div class="group" style="margin:0">${mine.map(a => `<div class="row" style="min-height:40px;padding:4px 8px 4px 12px"><div class="rl">${alertDesc(a)}</div><button class="ibtn sm" data-x="${esc(a.id)}" aria-label="删除" data-tip="删除">${I('trash', 'icon-16')}</button></div>`).join('')}</div></div>` : ''
  }
  off = onAlertsChange(renderExisting)
  const hook = $<HTMLInputElement>('#aHook', d.dlg)
  hook.addEventListener('input', () => { $('#aHookHint', d.dlg).textContent = validWebhook(hook.value) ? '' : '要以 http:// 或 https:// 开头' })
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const k = t.closest<HTMLElement>('#aKind [data-k]'); if (k) { kind = k.dataset.k as CKind; $$('#aKind button', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b === k))); renderVal() }
    const op = t.closest<HTMLElement>('[data-op]'); if (op) $$('[data-op]', d.dlg).forEach(b => b.setAttribute('aria-pressed', String(b === op)))
    const x = t.closest<HTMLElement>('[data-x]'); if (x) deleteAlert(x.dataset.x || '')
  })
  $('#aAll', d.dlg).onclick = () => { d.close(); openAllAlerts() }
  const ok = () => {
    if (!validWebhook(hook.value)) { hook.focus(); return }
    const webhook = cleanWebhook(hook.value)
    let a: Alert
    if (kind === 'price') {
      const inp = $<HTMLInputElement>('#aPrice', d.dlg), p = +inp.value
      if (!(p > 0)) { inp.focus(); return }
      a = makePriceAlert(symbol, p, last, { dec, webhook })
    } else {
      const inp = $<HTMLInputElement>('#aNum', d.dlg), v = +inp.value
      if (!isFinite(v) || (kind === 'oi' && !(v >= 0.1)) || Math.abs(v) > 10) { inp.focus(); toast(kind === 'oi' ? '填 0.1 到 1000 之间的百分数' : '填 −10 到 10 之间的百分数', '', 'info', 2000); return }
      const ratio = String(+(v / 100).toPrecision(8))
      const rule: AlertRule = kind === 'funding'
        ? { type: 'funding', side: ($('[data-op][aria-pressed="true"]', d.dlg)?.dataset.op as 'above' | 'below' | undefined) ?? 'above', rate: ratio }
        : { type: 'openInterestChange', threshold: ratio }
      a = makeConditionAlert(symbol, rule, { webhook })
    }
    addAlert(a); d.close()
    toast('提醒已创建', a.title, 'bell')
    askNotify()
  }
  $('#aOk', d.dlg).onclick = ok
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter' && tgt(e).tagName === 'INPUT') ok() })
  renderVal(); renderExisting()
}

export function askNotify(): void {
  if ('Notification' in window && Notification.permission === 'default') void Notification.requestPermission()
}

// ------------------------------------------------------------ 盯盘与触发
function notify(a: Alert, price: number): void {
  const body = `现价 ${fmt(price, decOf(a.symbol))} · 这条提醒已结束`
  toast(a.title, body, 'bell', 8000)
  if ('Notification' in window && Notification.permission === 'granted') { try { new Notification(a.title, { body, tag: a.id }) } catch { /* 有的浏览器只允许在 Service Worker 里弹 */ } }
}
function postWebhook(a: Alert, price: number, level: number | null): void {
  if (!a.webhook || loggedIn()) return
  const at = Date.now()
  // 跨域只能发「简单请求」：text/plain、不读回应
  void fetch(a.webhook, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: JSON.stringify(webhookBody(a, price, at, level)) }).catch(() => { /* 对方收不收是对方的事 */ })
}

async function checkOI(): Promise<void> {
  if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return
  const list = activeAlerts().filter(a => a.kind === 'condition' && a.rule?.type === 'openInterestChange')
  for (const k of new Set(list.map(a => a.symbol))) {
    try {
      const rows = await j<{ sumOpenInterest: string }[]>(`${REST}/futures/data/openInterestHist?symbol=${k}&period=5m&limit=13`)
      if (rows.length < 2) continue
      const chg = +rows[rows.length - 1].sumOpenInterest / +rows[0].sumOpenInterest - 1
      if (!isFinite(chg)) continue
      for (const a of list.filter(x => x.symbol === k)) if (a.rule && oiHit(a.rule, chg)) fire(a, sym(k)?.price ?? 0, null)
    } catch { /* 下一分钟再看 */ }
  }
}

let installed = false
export function installAlerts(hooks: AlertUIHooks): void {
  ui = hooks
  if (installed) return
  installed = true
  setQuoteSource(k => ({ price: sym(k)?.price ?? null, dec: sym(k)?.dec }))
  onAlertFired(({ alert, price, level }) => { notify(alert, price); postWebhook(alert, price, level) })
  on(e => {
    if (st.stale) return
    if (e.type === 'ticker') { const p = S.symbols.get(e.symbol)?.price; if (p != null) checkPrice(e.symbol, p) }
    else if (e.type === 'mark') {
      const s = S.symbols.get(e.symbol); if (!s) return
      for (const a of activeAlerts(e.symbol)) if (a.kind === 'condition' && a.rule && fundingHit(a.rule, s.fr, s.nextFunding, Date.now())) fire(a, s.price ?? 0, null)
    }
  })
  setInterval(() => { void checkOI() }, 60e3)
}

/** 要一直订着的行情：提醒涉及的品种（价格、画线要逐笔价；费率要标记价） */
export function alertStreams(): { ticker: string[]; mark: string[] } {
  const as = activeAlerts()
  return {
    ticker: [...new Set(as.filter(a => a.kind === 'price' || a.kind === 'drawing').map(a => a.symbol))],
    mark: [...new Set(as.filter(a => a.kind === 'condition' && a.rule?.type === 'funding').map(a => a.symbol))],
  }
}
