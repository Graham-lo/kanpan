/* Hkline Web · 提醒模块（界面与盯盘）
 *
 * 三块界面，规矩和手机「创建提醒」页一致：
 *   · 侧栏「提醒」：分段「列表 | 日志」（照 iOS 543a308d 铃铛开的那张表）。列表只列这只品种还没触发的，右上「全部」打开按品种分组的总表，
 *     行上只有删除；日志是响过的提醒（alerts/log.ts，账在服务端、留 30 天），按上海时间分天，右上「清空」要确认，没登录只有「登录后可查看」
 *   · 「创建提醒」对话框：品种不可改；条件叫「价格达到」；Webhook 只填地址；没有备注、没有重复
 *   · 总表：按品种分组，价格 / 画线 / 条件三类可筛
 * 盯盘：逐笔价看价格与画线提醒；资金费率在结算前 15 分钟那个窗口里看；持仓量每分钟看一次最近一小时。
 * 响了就弹通知（浏览器通知 + 页内提示）；没登录时 Webhook 由这个网页自己发（登录后由服务端发，不重复）。
 */
import { loggedIn } from '../account/session'
import { st } from '../app/store'
import { S, on, j, REST, klines, headName } from '../market'
import { $, I, esc, tgt } from '../ui/dom'
import { dialog, head, toast, type Dialog } from '../ui/overlay'
import { badge, cls, pctText, priceText, shTime, sym, venueTag } from '../ui/common'
import { fmt } from '../util/format'
import {
  activeAlerts, addAlert, alertLevel, checkPrice, cleanWebhook, conditionLabel, conditionPercentOK, deleteAlert, fire, judgeFunding, makeConditionAlert,
  makePriceAlert, oiChange, oiHit, onAlertFired, onAlertsChange, rulePhrase, setQuoteSource, validWebhook, webhookBody, webhookByPage, type Alert, type AlertRule,
} from './model'
import { parsePercent, parseTarget, syncIdOf } from './shape'
import {
  IND_INTERVALS, IV_MS_IND, barsNeeded, draftFromChart, flipLevel, indicatorPhrase, indicatorRuleError, isIndicatorRule, judgeClosedBars, lastCloseAt,
  parseIntField, parseNumField, rejectReason, ruleFromDraft, type ChartIndView, type Direction, type IndInterval, type IndicatorDraft, type IndicatorKind, type IndicatorRule, type MaType,
} from './indicator'
import { CATALOG } from '../chart/calc'
import { onRejected } from '../sync/engine'
import { conditionAlertsOk } from '../sync/codec'
import { alertLog, bareSymbol, logClock, logDays, logDetail, logName, logOwner } from './log'

export interface AlertUIHooks {
  /** 打开某只品种（总表里点品种名） */
  openSymbol: (symbol: string) => void
}
let ui: AlertUIHooks = { openSymbol: () => { /* 页面装上前什么都不做 */ } }

const decOf = (k: string): number => sym(k)?.dec ?? 2
const code = (k: string): string => sym(k)?.code || headName({ symbol: k })
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
    <div class="main"><div class="t1">${withSym ? `${venueTag(a.symbol)}${esc(code(a.symbol))}<span class="tag">${kindTag(a)}</span>` : ''}<span>${alertDesc(a)}</span></div>
    <div class="t2">${alertSub(a)}</div></div>
    <button class="ibtn sm" data-del-alert="${esc(a.id)}" aria-label="删除提醒" data-tip="删除">${I('trash', 'icon-16')}</button></div>`
}

// ------------------------------------------------------------ 侧栏
type SideTab = 'list' | 'log'
let sideTab: SideTab = 'list'
/** 侧栏正摆着的那一块（日志拉回来 / 清空后就地重画） */
let side: { el: HTMLElement; symbol: string } | null = null
let logWired = false

function logPane(): string {
  if (!logOwner()) return `<div class="empty">${I('bell', 'icon-24')}<div>登录后可查看</div></div>`
  const log = alertLog()
  const days = logDays(log.records)
  if (!days.length) return `<div class="empty">${I('bell', 'icon-24')}<div>${log.phase === 'idle' || log.phase === 'loading' ? '正在载入…' : log.phase === 'failed' ? '暂时取不到记录' : '暂无记录'}</div></div>`
  return days.map(d => `<div class="alog-day">${esc(d.title)}</div>${d.records.map(r => {
    const k = bareSymbol(r.symbol), s = k ? sym(k) : undefined
    const detail = logDetail(r, s?.dec)
    return `<div class="list-row alog-row"${k && s ? ` data-log-open="${esc(k)}" data-tip="打开这只品种"` : ''}>${badge(s ?? (k ? { base: k } : undefined))}
      <div class="main"><div class="t1"><span>${esc(logName(r, code))}</span></div>${detail ? `<div class="t2 num">${esc(detail)}</div>` : ''}</div>
      <span class="alog-clock num faint">${logClock(r.firedAt)}</span></div>`
  }).join('')}`).join('')
}

export function renderAlertsPanel(el: HTMLElement, symbol: string): void {
  side = { el, symbol }
  if (!logWired) {
    logWired = true
    alertLog().onChange(() => { if (side && sideTab === 'log' && side.el.isConnected) renderAlertsPanel(side.el, side.symbol) })
  }
  const tabs = `<div class="sp-sub"><div class="seg fill alog-tabs" role="tablist" aria-label="提醒">${([['list', '列表'], ['log', '日志']] as [SideTab, string][])
    .map(([k, l]) => `<button role="tab" data-atab="${k}" aria-pressed="${k === sideTab}" aria-selected="${k === sideTab}">${l}</button>`).join('')}</div></div>`
  if (sideTab === 'log') {
    const canClear = !!logOwner() && alertLog().records.length > 0
    el.innerHTML = `<div class="sp-head"><h3>提醒</h3>
        <button class="ibtn sm" id="aNew" aria-label="创建提醒" data-tip="创建提醒" data-kbd="Alt A">${I('plus')}</button>
        ${canClear ? `<button class="btn ghost sm" id="aLogClear" data-tip="清空全部记录">清空</button>` : ''}</div>
      ${tabs}
      <div class="scroll" style="flex:1;min-height:0">${logPane()}</div>`
    return
  }
  const mine = activeAlerts(symbol).sort((a, b) => b.created - a.created)
  const total = activeAlerts().length
  el.innerHTML = `<div class="sp-head"><h3>提醒</h3>
      <button class="ibtn sm" id="aNew" aria-label="创建提醒" data-tip="创建提醒" data-kbd="Alt A">${I('plus')}</button>
      <button class="btn ghost sm" id="aAllBtn" data-tip="所有品种的提醒">全部<span class="num faint" style="margin-left:4px">${total}</span></button></div>
    ${tabs}
    <div class="sp-sub"><span class="alert-sym">${badge(sym(symbol))}<b>${esc(code(symbol))}</b></span><span class="faint num">${mine.length ? `${mine.length} 条在等` : ''}</span></div>
    <div class="scroll" style="flex:1;min-height:0">
    ${mine.length ? mine.map(a => row(a, false)).join('') : `<div class="empty">${I('bell', 'icon-24')}<div>这只品种没有在等的提醒</div><div class="faint" style="font-size:12px;margin-top:4px">点价格轴，或在图上右键</div></div>`}
    </div>`
}

/** 清空日志前问一句（居中小框，照 iOS confirmationDialog「清空全部记录？」） */
function confirmClearLog(): void {
  const d = dialog(`${head('清空全部记录？')}<div class="dialog-foot"><button class="btn ghost" data-close>取消</button><button class="btn danger" id="alogOk">清空</button></div>`, 'alog-confirm', { center: true, label: '清空全部记录？' })
  const ok = $<HTMLButtonElement>('#alogOk', d.dlg)
  ok.focus()
  ok.onclick = async () => {
    ok.disabled = true
    const done = await alertLog().clear()
    d.close()
    if (!done) toast('没清掉', '稍后再试', 'info')
  }
}

/** 侧栏里的点击；认得就返回 true */
export function alertsPanelClick(e: MouseEvent, symbol: string): boolean {
  const t = tgt(e)
  const tab = t.closest<HTMLElement>('[data-atab]')
  if (tab) {
    const next = tab.dataset.atab as SideTab
    if (next !== sideTab) {
      sideTab = next
      const host = tab.closest<HTMLElement>('.sp-head')?.parentElement ?? side?.el
      if (host) renderAlertsPanel(host, symbol)
      if (next === 'log') void alertLog().refresh(logOwner())
    }
    return true
  }
  if (t.closest('#aLogClear')) { confirmClearLog(); return true }
  const lo = t.closest<HTMLElement>('[data-log-open]'); if (lo) { if (lo.dataset.logOpen !== symbol) ui.openSymbol(lo.dataset.logOpen || ''); return true }
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
type CKind = 'price' | 'funding' | 'oi' | IndicatorKind
/** 建提醒页的起点：直接落在哪一种条件、从哪个图例 / 副图点进来的（预填参数用）、哪个周期 */
export interface CreatePreset { kind?: CKind; from?: 'ma' | 'ema' | 'rsi'; iv?: string }
const KIND_LABEL: [CKind, string][] = [['price', '价格'], ['funding', '费率'], ['oi', '持仓量'], ['ma_cross', '均线交叉'], ['rsi_level', 'RSI'], ['bar_breakout', '突破']]
const isInd = (k: CKind): k is IndicatorKind => k === 'ma_cross' || k === 'rsi_level' || k === 'bar_breakout'
/** 当前格子图上的指标（预填用）：开着哪几条、参数是图上的那份（没改过就是目录默认） */
export function chartIndView(iv?: string): ChartIndView {
  return {
    iv: iv ?? st.cells[st.active]?.iv ?? '1h',
    ma: !!st.ind.ma, ema: !!st.ind.ema, rsi: st.ind.subs.includes('rsi'),
    params: id => st.params?.[id] ?? CATALOG[id].params,
  }
}
const DIR_LABEL: Record<IndicatorKind, [string, string]> = { ma_cross: ['金叉', '死叉'], rsi_level: ['上穿', '下穿'], bar_breakout: ['上破', '下破'] }
const segOf = <T extends string>(id: string, items: [T, string][], cur: T, attr: string, fill = true): string =>
  `<div class="seg${fill ? ' fill' : ''}" id="${id}" role="group">${items.map(([k, l]) => `<button type="button" data-${attr}="${k}" aria-pressed="${k === cur}">${l}</button>`).join('')}</div>`
const numInput = (id: string, v: number, label: string, mode = 'numeric'): string =>
  `<div class="input-wrap"><input id="${id}" class="input num" inputmode="${mode}" autocomplete="off" aria-label="${label}" value="${Number.isFinite(v) ? v : ''}"></div>`

let createDlg: Dialog | null = null
export function openCreateAlert(symbol: string, price?: number | null, preset: CreatePreset = {}): void {
  createDlg?.close()
  const s = sym(symbol), dec = decOf(symbol)
  const last = s?.price ?? null
  // 只有币安 U 本位能建条件提醒（服务端 sync_validation：条件提醒的 market 必须是 binance/usd_m，四种条件的数据也只来自那里）；
  // 美元指数、OKX / Bybit / Hyperliquid / Coinbase 只给价格提醒
  const priceOnly = !conditionAlertsOk(symbol)
  const kind0: CKind = preset.kind && !(priceOnly && preset.kind !== 'price') ? preset.kind : 'price'
  if (kind0 === 'price' && last == null && price == null) { toast('还没有这只品种的价格', '行情连上后再建', 'info'); return }
  let kind: CKind = kind0
  const p0 = price ?? last ?? 0
  const draft: IndicatorDraft = draftFromChart(chartIndView(preset.iv), preset.from)
  let off = (): void => { /* 下面挂上 */ }
  const KINDS = priceOnly ? KIND_LABEL.slice(0, 1) : KIND_LABEL
  const d = dialog(`${head('创建提醒', `<button class="btn ghost sm" id="aAll">全部提醒</button>`)}<div class="dialog-body"><div class="form-grid">
    <div class="sym-card">${badge(s, 'lg')}<div style="flex:1"><b>${esc(code(symbol))}</b><div class="muted" style="font-size:12px;line-height:16px">${esc(s?.cn || symbol)}</div></div><div style="text-align:right"><div class="num" style="font-weight:600">${last != null ? fmt(last, dec) : '—'}</div><div class="num ${cls(s?.pct)}" style="font-size:12px;line-height:16px">${pctText(s?.pct)}</div></div></div>
    ${KINDS.length > 1 ? `<div class="field"><label>条件</label>${segOf('aKind', KINDS, kind, 'k')}</div>` : ''}
    <div id="aVal" class="form-grid"></div>
    <div class="field"><label for="aHook">Webhook 地址 <span class="faint" style="font-weight:400">选填</span></label><div class="input-wrap"><input id="aHook" class="input" inputmode="url" autocomplete="off" spellcheck="false" placeholder="https://"></div><div class="hint" id="aHookHint"></div></div>
    <div id="aExisting"></div>
    </div></div><div class="dialog-foot"><span class="faint" style="margin-right:auto;font-size:12px;align-self:center" id="aFootNote">响一次就结束</span><button class="btn ghost" data-close>取消</button><button class="btn primary" id="aOk">创建</button></div>`, 'alert-dlg', { label: '创建提醒', onClose: () => { if (createDlg === d) createDlg = null; off() } })
  createDlg = d
  /** 技术指标那三种：预览这条会叫什么；参数不对就说哪里不对 */
  function preview(): void {
    if (!isInd(kind)) return
    const el = $('#aPreview', d.dlg)
    const rule = ruleFromDraft(kind, draft), err = indicatorRuleError(rule)
    el.textContent = err ?? indicatorPhrase(rule)
    el.classList.toggle('bad', !!err)
  }
  function renderVal(): void {
    const v = $('#aVal', d.dlg)
    $('#aFootNote', d.dlg).textContent = isInd(kind) ? '收盘时判 · 响一次就结束' : '响一次就结束'
    if (kind === 'price') {
      v.innerHTML = `<div class="field"><label for="aPrice">价格</label><div class="input-wrap"><input id="aPrice" class="input lg num" inputmode="decimal" value="${p0.toFixed(dec)}"><span class="suffix">USDT</span></div><div class="hint num" id="aHint"></div></div>`
      const inp = $<HTMLInputElement>('#aPrice', d.dlg)
      const hint = () => { const p = parseTarget(inp.value); $('#aHint', d.dlg).textContent = p == null ? '填一个价格' : last == null ? '' : `比现价${p >= last ? '高' : '低'} ${Math.abs((p - last) / last * 100).toFixed(2)}%` }
      inp.addEventListener('input', hint); hint(); inp.focus(); inp.select()
      return
    }
    if (kind === 'funding') { v.innerHTML = `<div class="field"><label>资金费率</label><div style="display:flex;gap:8px"><div class="seg" id="aOp"><button data-op="above" aria-pressed="true">高于</button><button data-op="below" aria-pressed="false">低于</button></div><div class="input-wrap" style="flex:1"><input id="aNum" class="input num" inputmode="decimal" value="0.05"><span class="suffix">%</span></div></div><div class="hint">现在 <span class="num">${s?.fr != null ? (s.fr * 100).toFixed(4) + '%' : '—'}</span> · 结算前 15 分钟判</div></div>`; $<HTMLInputElement>('#aNum', d.dlg).focus(); return }
    if (kind === 'oi') { v.innerHTML = `<div class="field"><label>1 小时内持仓量变化超过</label><div class="input-wrap"><input id="aNum" class="input num" inputmode="decimal" value="5"><span class="suffix">%</span></div><div class="hint">增减都算</div></div>`; $<HTMLInputElement>('#aNum', d.dlg).focus(); return }
    const ivs = IND_INTERVALS.map(k => [k, k] as [IndInterval, string])
    const [up, down] = DIR_LABEL[kind]
    const dir = kind === 'ma_cross' ? draft.maDir : kind === 'rsi_level' ? draft.rsiDir : draft.brDir
    const maRow = (which: 'fast' | 'slow', label: string): string => {
      const l = draft[which]
      return `<div class="field"><label for="a${which}N">${label}</label><div class="ma-line">${segOf(`a${which}Ma`, [['sma', 'MA'], ['ema', 'EMA']], l.ma, `ma-${which}`, false)}${numInput(`a${which}N`, l.period, `${label}长度`)}</div></div>`
    }
    let body = ''
    if (kind === 'ma_cross') body = `<div class="ind-pair">${maRow('fast', '快线')}${maRow('slow', '慢线')}</div>`
    else if (kind === 'rsi_level') body = `<div class="ind-pair"><div class="field"><label for="aRsiN">长度</label>${numInput('aRsiN', draft.rsiPeriod, 'RSI 长度')}</div><div class="field"><label for="aLevel">水平</label>${numInput('aLevel', draft.level, '水平', 'decimal')}</div></div>`
    else body = `<div class="field"><label for="aBars">前几根</label>${numInput('aBars', draft.bars, '根数')}</div>`
    v.innerHTML = `<div class="field"><label>周期</label>${segOf('aIv', ivs, draft.interval, 'iv')}</div>${body}
      <div class="field"><label>方向</label>${segOf('aDir', [['up', up], ['down', down]], dir, 'dir')}<div class="hint num" id="aPreview" aria-live="polite"></div></div>`
    preview()
    const first = v.querySelector<HTMLInputElement>('input'); first?.focus(); first?.select()
  }
  function renderExisting(): void {
    const mine = activeAlerts(symbol)
    $('#aExisting', d.dlg).innerHTML = mine.length ? `<div class="field"><label>这只品种还在等的</label><div class="group" style="margin:0">${mine.map(a => `<div class="row" style="min-height:40px;padding:4px 8px 4px 12px"><div class="rl">${alertDesc(a)}</div><button class="ibtn sm" data-x="${esc(a.id)}" aria-label="删除" data-tip="删除">${I('trash', 'icon-16')}</button></div>`).join('')}</div></div>` : ''
  }
  off = onAlertsChange(renderExisting)
  const hook = $<HTMLInputElement>('#aHook', d.dlg)
  hook.addEventListener('input', () => { $('#aHookHint', d.dlg).textContent = validWebhook(hook.value) ? '' : '要以 http:// 或 https:// 开头' })
  const press = (b: HTMLElement): void => { b.parentElement?.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', String(x === b))) }
  d.dlg.addEventListener('click', e => {
    const t = tgt(e)
    const k = t.closest<HTMLElement>('#aKind [data-k]'); if (k) { kind = k.dataset.k as CKind; press(k); renderVal(); return }
    const op = t.closest<HTMLElement>('[data-op]'); if (op) { press(op); return }
    const iv = t.closest<HTMLElement>('[data-iv]'); if (iv) { draft.interval = iv.dataset.iv as IndInterval; press(iv); preview(); return }
    const ma = t.closest<HTMLElement>('[data-ma-fast],[data-ma-slow]')
    if (ma) { const which = ma.dataset.maFast ? 'fast' : 'slow'; draft[which] = { ...draft[which], ma: (ma.dataset.maFast || ma.dataset.maSlow) as MaType }; press(ma); preview(); return }
    const dr = t.closest<HTMLElement>('[data-dir]')
    if (dr && isInd(kind)) {
      const v = dr.dataset.dir as Direction
      if (kind === 'ma_cross') draft.maDir = v
      else if (kind === 'bar_breakout') draft.brDir = v
      else {
        draft.rsiDir = v
        const lv = flipLevel(draft.level, v)
        if (lv !== draft.level) { draft.level = lv; const inp = d.dlg.querySelector<HTMLInputElement>('#aLevel'); if (inp) inp.value = String(lv) }
      }
      press(dr); preview(); return
    }
    const x = t.closest<HTMLElement>('[data-x]'); if (x) deleteAlert(x.dataset.x || '')
  })
  // 指标参数框：边打边记进草稿（解析不出来记 NaN，预览那行就说哪里不对）
  d.dlg.addEventListener('input', e => {
    const inp = tgt(e) as HTMLInputElement
    const n = (inp.id === 'aLevel' ? parseNumField(inp.value) : parseIntField(inp.value)) ?? NaN
    if (inp.id === 'afastN') draft.fast = { ...draft.fast, period: n }
    else if (inp.id === 'aslowN') draft.slow = { ...draft.slow, period: n }
    else if (inp.id === 'aRsiN') draft.rsiPeriod = n
    else if (inp.id === 'aLevel') draft.level = n
    else if (inp.id === 'aBars') draft.bars = n
    else return
    preview()
  })
  $('#aAll', d.dlg).onclick = () => { d.close(); openAllAlerts() }
  const ok = () => {
    if (!validWebhook(hook.value)) { hook.focus(); return }
    const webhook = cleanWebhook(hook.value)
    let a: Alert
    if (kind === 'price') {
      const inp = $<HTMLInputElement>('#aPrice', d.dlg), p = parseTarget(inp.value)
      if (p == null) { inp.focus(); return }
      a = makePriceAlert(symbol, p, last, { dec, webhook })
    } else if (isInd(kind)) {
      const rule = ruleFromDraft(kind, draft), err = indicatorRuleError(rule)
      if (err) { toast(err, '', 'info', 2400); d.dlg.querySelector<HTMLInputElement>('#aVal input')?.focus(); return }
      a = makeConditionAlert(symbol, rule, { webhook })
    } else {
      const inp = $<HTMLInputElement>('#aNum', d.dlg), v = parsePercent(inp.value)
      if (v == null || !conditionPercentOK(kind, v)) { inp.focus(); toast(kind === 'oi' ? '填 0.1 到 1000 之间的百分数' : '填 −10 到 10 之间的百分数', '', 'info', 2000); return }
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
  d.dlg.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing && tgt(e).tagName === 'INPUT') ok() })
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
function postWebhook(a: Alert, price: number, level: number | null, remote = false): void {
  if (!a.webhook || !webhookByPage(a, remote, loggedIn())) return
  const at = Date.now()
  // 跨域只能发「简单请求」：text/plain、不读回应
  void fetch(a.webhook, { method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'text/plain;charset=utf-8' }, body: JSON.stringify(webhookBody(a, price, at, level)) }).catch(() => { /* 对方收不收是对方的事 */ })
}

async function checkOI(): Promise<void> {
  // 登录着时服务端也在判，页面在后台就不必每分钟去问；没登录只有这一页在判，后台也照问
  if (typeof document !== 'undefined' && document.visibilityState === 'hidden' && loggedIn()) return
  const list = activeAlerts().filter(a => a.kind === 'condition' && a.rule?.type === 'openInterestChange')
  for (const k of new Set(list.map(a => a.symbol))) {
    try {
      const rows = await j<{ timestamp: number; sumOpenInterest: string }[]>(`${REST}/futures/data/openInterestHist?symbol=${k}&period=5m&limit=13`)
      for (const a of list.filter(x => x.symbol === k)) {
        const chg = oiChange(rows, a.armedAt)
        if (chg != null && a.rule && oiHit(a.rule, chg)) fire(a, sym(k)?.price ?? 0, null)
      }
    } catch { /* 下一分钟再看 */ }
  }
}
/** 技术指标提醒：每条判到了哪一根的收盘（判过的那根不再判） */
const indJudged = new Map<string, number>()
/** 收盘后等几秒再取：币安那根 K 线落定要一小会 */
const CLOSE_GRACE = 2500
let indBusy = false
/** 页面开着时的收盘判定：哪条提醒的周期刚收了一根，就取那只品种那个周期的 K 线判一次。
 *  第一次判（刚建、刚打开页面）只看最近收的那一根，不把页面关着那段时间的旧穿越翻出来响 */
export async function checkIndicators(now = Date.now()): Promise<void> {
  if (indBusy) return
  const due = activeAlerts().filter(a => {
    if (a.kind !== 'condition' || !isIndicatorRule(a.rule)) return false
    const lc = lastCloseAt(a.rule.interval, now)
    return lc > a.armedAt && lc > (indJudged.get(a.id) ?? 0) && now >= lc + CLOSE_GRACE
  })
  if (!due.length) return
  indBusy = true
  try {
    const groups = new Map<string, Alert[]>()
    for (const a of due) { const k = `${a.symbol}|${(a.rule as IndicatorRule).interval}`; groups.set(k, [...(groups.get(k) || []), a]) }
    for (const [k, as] of groups) {
      const [symbol, iv] = k.split('|') as [string, IndInterval]
      const lc = lastCloseAt(iv, now)
      const res = await klines(symbol, iv, undefined, Math.min(1500, Math.max(...as.map(a => barsNeeded(a.rule as IndicatorRule))) + 1), false, true)
      // 取不到、或者最新收的那根还没出现在里面：这一轮不判，下一轮再取
      if (!res.ok || !res.bars.some(b => b.t + IV_MS_IND[iv] === lc)) continue
      for (const a of as) {
        const r = a.rule as IndicatorRule
        const i = judgeClosedBars(r, res.bars, a.armedAt, now, indJudged.get(a.id) ?? lc - IV_MS_IND[iv])
        indJudged.set(a.id, lc)
        if (i >= 0) fire(a, res.bars[i].c, null)
      }
    }
  } finally { indBusy = false }
}
/** 同步被服务端拒了的技术指标提醒：每条每次打开页面只说一次 */
const toldRejected = new Set<string>()

/** 资金费率提醒：每条判过的是哪一次结算（一次结算只判窗口里的第一眼） */
const fundingJudged = new Map<string, number>()

let installed = false
export function installAlerts(hooks: AlertUIHooks): void {
  ui = hooks
  if (installed) return
  installed = true
  setQuoteSource(k => ({ price: sym(k)?.price ?? null, dec: sym(k)?.dec }))
  onAlertFired(({ alert, price, level, remote }) => { notify(alert, price); postWebhook(alert, price, level, remote) })
  on(e => {
    if (st.stale) return
    if (e.type === 'ticker') { const p = S.symbols.get(e.symbol)?.price; if (p != null) checkPrice(e.symbol, p) }
    else if (e.type === 'mark') {
      const s = S.symbols.get(e.symbol); if (!s) return
      for (const a of activeAlerts(e.symbol)) if (a.kind === 'condition' && judgeFunding(a, s.fr, s.nextFunding, Date.now(), fundingJudged)) fire(a, s.price ?? 0, null)
    }
  })
  setInterval(() => { void checkOI() }, 60e3)
  setInterval(() => { void checkIndicators() }, 5e3)
  // 服务端还不认技术指标条件时会 400：说一声中文原因（这条照样留在本机、本页开着照判，服务端认了之后同步层自己补推）
  onRejected(({ op, code, reason }) => {
    if (op.collection !== 'alerts') return
    const a = st.alerts.find(x => syncIdOf(x) === op.objectId)
    if (!a || !isIndicatorRule(a.rule) || toldRejected.has(a.id)) return
    toldRejected.add(a.id)
    toast('这条提醒没存上云端', `${indicatorPhrase(a.rule)}：${rejectReason(code, reason)}`, 'info', 8000)
  })
}

/** 要一直订着的行情：提醒涉及的品种（价格、画线要逐笔价；费率要标记价） */
export function alertStreams(): { ticker: string[]; mark: string[] } {
  const as = activeAlerts()
  return {
    ticker: [...new Set(as.filter(a => a.kind === 'price' || a.kind === 'drawing').map(a => a.symbol))],
    mark: [...new Set(as.filter(a => a.kind === 'condition' && a.rule?.type === 'funding').map(a => a.symbol))],
  }
}
