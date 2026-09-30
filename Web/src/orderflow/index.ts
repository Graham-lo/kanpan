/* Hkline Web · 主力订单流 · 控制器（设计稿 2.1–2.7）
 *
 * 图表页只通过 installOrderFlow(api) 和几个 HTML 片段接进来；这里负责：
 *   · 数据层的生命周期：跟着活动格子的品种开一个 OrderFlowFeed（三家一起连），换品种就换，
 *     没有任何展示需要它（图上订单流、梯子、热力、小部件、面板都关着）或离开图表页一分钟后就停；
 *   · 每帧（半秒）把快照分发给图上层、梯子、小部件、抽屉、面板；
 *   · 深度热力：实时每秒一列，实时开始之前的时段向服务端要回填（按返回的 bucketMs 画列宽）；
 *   · 「主力订单流」侧栏面板、工具栏的「热力」按钮、指标里的那一行与齿轮。
 * 数据规则（门槛、分桶、出现 / 消失 / 结局）都在 model / feed 里照手机端的 Swift 模型，这里只管展示。
 */
import './orderflow.css'
import { st, save, type WidgetId } from '../app/store'
import { I, esc } from '../ui/dom'
import { term } from '../ui/overlay'
import { OrderFlowFeed, getJSON, type TradeEvent } from './feed'
import { buildFine, exName, venueName } from './aggregate'
import { HeatStore, parseHeat, heatHint, heatRing, heatUrl, type HeatRing } from './heat'
import { tapeBase } from './tape'
import { recordTrade, beat } from '../chart/tradeFlow'
import { heatFetchSent } from './heatFetch'
import { createLayer } from './layer'
import { mountLadder, ladderVisible, drawLadder, resetLadder, ladderDebug } from './ladder'
import { mountDrawer, updateDrawer, revealInDrawer } from './drawer'
import { widgetHTML, mountWidgets, isOfWidget, updateWidgets, resetTape, scheduleTape, markWall, OF_WIDGETS, tapeDebug } from './widgets'
import { openOrderFlowSettings, settingsLayerOpen } from './settingsDialog'
import { baseOfSymbol, productsOf, type Display } from './settings'
import { OF, savePrefs, amt, PRODUCT_FULL, durShort, type Api } from './state'
import { orderId, type BigOrder } from './types'
import type { Snapshot } from './model'
import type { TVChart } from '../chart/chart'
import { settle } from '../market/settle'

export { mountLadder, mountDrawer, widgetHTML, mountWidgets, isOfWidget, openOrderFlowSettings }
/** 侧栏某块是不是收起（本机偏好） */
export const isCollapsed = (w: string): boolean => OF.prefs.collapsed.includes(w)

const SYNC_MS = 500
/** 离开图表页多久后停掉数据层（切回来不用重连） */
const IDLE_STOP_MS = 60_000
/** 回填最多往前要多久（服务端历史只留几天） */
const HEAT_BACK_MAX_MS = 3 * 86_400_000
const HEAT_RETRY_MS = 20_000

let api: Api | null = null
const attached = new WeakSet<TVChart>()
let overrideSig = ''
let idleSince: number | null = null
let panelEl: HTMLElement | null = null

// ------------------------------------------------------------------ 安装

export function installOrderFlow(a: Api): void {
  api = a
  OF.api = a
  OF.onChartDrawn = (chart, g) => {
    const act = a.activeChart()
    if (!act || act.chart !== chart) return
    OF.geo = g
    if (ladderVisible()) drawLadder(chart, g)
  }
  if (!OF.prefs.seededStats && (st.orderFlow || st.slots.widgets.some(w => isOfWidget(w)))) { seedStats(); save() }
  OF.reveal = id => revealInDrawer(id)
  OF.focus = focusOrder
  setInterval(() => { if (document.visibilityState !== 'hidden') sync() }, SYNC_MS)
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') sync() })
  sync()
}

/** 有没有哪个展示在用订单流的数据。 */
function needed(): boolean {
  if (st.orderFlow || st.slots.ladder || st.slots.drawer || OF.prefs.heat) return true
  // 副图「累计量差」的三家实时段、「大单与散户累计量差」都靠这里的逐笔成交
  if (st.ind.subs.includes('cvd') || st.ind.subs.includes('whale')) return true
  if (st.panel === 'flow') return true
  return st.panel === 'watch' && st.slots.widgets.some(w => isOfWidget(w))
}

/** 每半秒：挂图上层、开 / 关 / 换数据层、告诉它可见窗口、同步线路与门槛、要热力回填。 */
export function sync(): void {
  if (!api) return
  for (const c of api.charts()) {
    if (attached.has(c.chart)) continue
    attached.add(c.chart)
    const chart = c.chart
    chart.layers.push(createLayer(chart, () => api!.charts().find(x => x.chart === chart) ?? { symbol: '', iv: '1h' }))
  }
  const act = api.activeChart()
  const onPage = st.page === 'chart'
  if (onPage) idleSince = null
  else if (idleSince == null) idleSince = Date.now()
  const want = !!act && needed() && (onPage || Date.now() - (idleSince ?? 0) < IDLE_STOP_MS)
  if (!want) { if (OF.feed) stopFeed(); setPending(false); return }
  const symbol = act!.symbol.toUpperCase()
  if (OF.feed && OF.feed.symbol !== symbol) stopFeed()
  if (!OF.feed) {
    // 深度快照（合约 20、现货 250 权重）、合约清单、步长这些不在首屏：连切时中间划过的品种不接，停稳约半秒再接
    if (!settle.settled()) { setPending(true); settle.whenSettled('orderflow', sync); return }
    setPending(false)
    startFeed(act!.symbol)
  }
  const f = OF.feed!
  OF.iv = act!.iv
  f.setRoute(st.route)
  const own = st.orderFlowOverrides[f.base] ?? null
  const sig = JSON.stringify(own)
  if (sig !== overrideSig) { overrideSig = sig; f.setOverride(own); OF.version++ }
  const g = act!.chart.geometry()
  if (g) f.setVisible(g.timeOf(g.from), g.timeOf(g.to + 1))
  if (!OF.prefs.heat && OF.heat) { OF.heat = null; heatBack = freshBack() }
  if (OF.prefs.heat && g) void heatBackfill(g.timeOf(g.from), g.timeOf(g.to + 1), g.range.min, g.range.max, g.iv / Math.max(1e-6, g.spacing))
}

function startFeed(symbol: string): void {
  const s = api!
  const own = st.orderFlowOverrides[baseOfSymbol(symbol.toUpperCase()).base] ?? null
  overrideSig = JSON.stringify(own)
  const f = new OrderFlowFeed({
    symbol, crypto: s.crypto(symbol), turnover24h: s.turnover(symbol), tick: null, route: st.route, override: own,
    onFrame, onTrade,
  })
  OF.feed = f
  resetSymbolState()
  void f.start()
  renderFlowPanel()
}

/** 等品种停稳的那半秒：各处空态写「正在接盘口…」，不写「打开指标后显示」 */
function setPending(v: boolean): void {
  if (OF.pending === v) return
  OF.pending = v
  updateWidgets(); updateDrawer(true); renderFlowPanel()
}

function stopFeed(): void {
  OF.feed?.stop()
  OF.feed = null
  resetSymbolState()
  api?.charts().forEach(c => { c.chart.dirty = true })
  updateWidgets(); updateDrawer(true); renderFlowPanel()
}

function resetSymbolState(): void {
  OF.snap = null; OF.fine = null; OF.heat = null
  OF.tape.clear(); OF.peaks.clear()
  OF.trades.clear(); OF.delta.reset(); OF.liq.reset(); OF.vol.reset(); OF.tps.clear()
  OF.highlight = null; OF.hoverRow = null; OF.bigTrade = 0
  OF.version++
  heatBack = freshBack()
  resetTape(); resetLadder()
}

// ------------------------------------------------------------------ 帧

function onFrame(s: Snapshot): void {
  const f = OF.feed
  if (!f || !api) return
  const now = Date.now()
  OF.snap = s
  // 三家逐笔的覆盖心跳：连接都开着这半秒才算盖住（副图累计量差 / 大单与散户）
  const conns = f.debug().conns
  beat(f.symbol, now, conns.length > 0 && conns.every(c => c.open))
  OF.fine = buildFine(f.model, 500, now)
  if (OF.prefs.heat && OF.fine) {
    if (!OF.heat || OF.heat.step !== OF.fine.step) { OF.heat = new HeatStore(OF.fine.step); heatBack = freshBack() }
    OF.heat.sample(OF.fine, s.thresholds, now)
  }
  const tb = tapeBase(s.thresholds)
  OF.bigTrade = tb ? tb / 5 : 0
  OF.tape.prune(now)
  if (OF.fine) {
    // 梯子「变化」的实时环（梯子开着才记）；两块 24 小时统计（放在侧栏里才取）
    if (st.slots.ladder) OF.delta.sample(OF.fine, s.thresholds, now)
    const ws = st.slots.widgets
    const wantLiq = ws.includes('liq'), wantVol = ws.includes('vol')
    if (wantLiq) OF.liq.sample(OF.fine, s.thresholds, now)
    if (wantVol || wantLiq) OF.vol.ensure(f.books, now)
    if (wantLiq) OF.liq.ensure(f.base, f.chartScale, OF.fine.step, OF.fine.mid, OF.vol.mids(), OF.vol.status === 'ok' || OF.vol.status === 'down', now)
  }
  OF.version++
  for (const c of api.charts()) if (c.symbol.toUpperCase() === f.symbol) c.chart.dirty = true
  updateWidgets()
  updateDrawer()
  updateFlowPanel()
}

function onTrade(ev: TradeEvent): void {
  const f = OF.feed
  if (!f) return
  const v = ev.book.venue
  const cut = OF.snap ? tapeBase(OF.snap.thresholds) : null
  recordTrade(f.symbol, ev, cut ? cut / 50 : null)
  const row = OF.tape.push({
    t: ev.trade.timeMs || Date.now(), exchange: v.exchange, label: exName(v.exchange), product: v.product,
    side: ev.trade.hitSide === 'ask' ? 'buy' : 'sell', price: ev.trade.price, usd: ev.usd, qty: ev.trade.quantity, instrument: v.instrument,
  })
  // 梯子中列：按细桶累加主动买 / 主动卖；详情里的每秒成交
  const step = f.model.scheme?.step
  if (step) OF.trades.add(ev.trade.price, ev.usd, row.side, step, row.t)
  OF.tps.add(Date.now())
  if (OF.bigTrade > 0) OF.tape.dotFor(row, OF.bigTrade)
  scheduleTape()
}

/** 抽屉 / 大单小部件里点了一单：图挪到那条带的中间、高亮它。 */
function focusOrder(o: BigOrder): void {
  const a = api?.activeChart()
  if (!a) return
  const end = o.endMs ?? Date.now()
  a.chart.centerOn((o.firstSeenMs + end) / 2, o.price)
  OF.highlight = orderId(o)
  OF.version++
  a.chart.dirty = true
  updateDrawer(true)
  markWall(o)
}

// ------------------------------------------------------------------ 深度热力回填

type BackStatus = 'idle' | 'loading' | 'ok' | 'empty' | 'down'
interface BackState { from: number; to: number; ring: HeatRing | null; busy: boolean; retryAt: number; status: BackStatus; bucketMs: number; gen: number }
const freshBack = (): BackState => ({ from: Infinity, to: -Infinity, ring: null, busy: false, retryAt: 0, status: 'idle', bucketMs: 0, gen: ++backGen })
let backGen = 0
let heatBack: BackState = freshBack()

/**
 * 图上看得到、实时列又还没覆盖到的那段，向服务端要。已经要过的不重要；往左拖出去了就补左边那一段；
 * 服务端给得很粗（bucketMs 放大了）而现在看的窗口小得多时，按现在的窗口重要一遍（细一些）。
 * 2026-09-29 起请求按可见范围收窄：价格只要可见中点 ±5% 的环（可见高度大就放宽），bucketMs 给一格约 2 像素的提示；
 * 上下拖出了已取的价格环，就按现在的窗口与新环重要一遍。往左右补的那一段沿用已取的环，拼起来价格范围一致。
 */
async function heatBackfill(visFrom: number, visTo: number, visMin: number, visMax: number, msPerPx: number): Promise<void> {
  const f = OF.feed, store = OF.heat
  if (!f || !store || heatBack.busy) return
  const now = Date.now()
  if (now < heatBack.retryAt) return
  const span = Math.max(60_000, visTo - visFrom)
  const from = Math.max(now - HEAT_BACK_MAX_MS, visFrom - span * 0.25)
  const to = Math.min(now, visTo, store.liveStart)
  if (!(to - from > 5000)) return
  const b = heatBack
  let q: [number, number] | null = null
  let replace = false
  const ring = heatRing(visMin, visMax)
  const covered = b.to >= b.from
  // 上下拖出了已取的环、且新环比旧环多出一成以上才重取（环已放到 ±50% 封顶时，小挪一下不来回重取）。
  const was = b.ring
  const outside = covered && !!was && !!ring && (visMin < was.lo || visMax > was.hi) &&
    (ring.lo < was.lo - 0.1 * (was.hi - was.lo) || ring.hi > was.hi + 0.1 * (was.hi - was.lo))
  if (!covered) q = [from, to]
  else if (outside) { q = [from, to]; replace = true }
  else if (b.bucketMs > 5000 && (b.to - b.from) > 4 * (to - from) && b.bucketMs * 40 > to - from) { q = [from, to]; replace = true }
  else if (from < b.from - Math.max(b.bucketMs, 0.05 * span)) q = [from, b.from]
  else if (to > b.to + Math.max(b.bucketMs, 60_000, 0.05 * span)) q = [b.to, to]
  if (!q) return
  const step = store.step, scale = f.chartScale, gen = b.gen
  // 新取（头一次、或整段重取）用这一刻的环；往两边补沿用已取的环，拼起来价格范围一致。
  const fresh = !covered || replace
  const useRing = fresh ? ring : b.ring
  b.busy = true
  if (b.status === 'idle') b.status = 'loading'
  try {
    const url = heatUrl(f.base, q[0], q[1], step, scale, heatHint(msPerPx), useRing)
    const r = await getJSON(url, 12_000)
    if (gen !== heatBack.gen || OF.heat !== store) return
    const cols = r.status === 200 ? parseHeat(r.body, step, scale) : null
    if (!cols) { b.status = 'down'; b.retryAt = Date.now() + HEAT_RETRY_MS; return }
    const bm = (r.body as { bucketMs?: unknown })?.bucketMs
    if (replace) { store.clearBack(); b.from = Infinity; b.to = -Infinity }
    if (fresh) b.ring = useRing
    b.bucketMs = typeof bm === 'number' && bm > 0 ? bm : 5000
    b.from = Math.min(b.from, q[0]); b.to = Math.max(b.to, q[1])
    if (cols.length) { store.addBackfill(cols); b.status = 'ok' } else if (b.status !== 'ok') b.status = 'empty'
    api?.charts().forEach(c => { if (c.symbol.toUpperCase() === f.symbol) c.chart.dirty = true })
    updateFlowPanel()
  } catch {
    if (gen === heatBack.gen) { b.status = 'down'; b.retryAt = Date.now() + HEAT_RETRY_MS }
  } finally {
    if (gen === heatBack.gen) b.busy = false
  }
}

// ------------------------------------------------------------------ 开关

/** 图上订单流的总开关（指标行、面板里的开关都走这里）。第一次打开时把梯子、抽屉和小部件摆出来。 */
export function setOrderFlow(on: boolean): void {
  st.orderFlow = on
  if (on) {
    st.slots.drawer = true
    if (!OF.prefs.seeded) {
      OF.prefs.seeded = true; savePrefs()
      st.slots.ladder = true
      const add: WidgetId[] = OF_WIDGETS.filter(w => !st.slots.widgets.includes(w))
      if (add.length) st.slots.widgets = [...st.slots.widgets, ...add]
      OF.prefs.seededStats = true; savePrefs()
    }
    seedStats()
  } else st.slots.drawer = false
  save()
  OF.version++
  api?.charts().forEach(c => { c.chart.dirty = true })
  sync()
  api?.renderPanel()
  api?.renderToolbar()
}

/** 2026-09-29 新加的两块统计：已经开过订单流的也摆一次（摆在「大单」后面），之后尊重用户的开合 */
function seedStats(): void {
  if (OF.prefs.seededStats) return
  OF.prefs.seededStats = true; savePrefs()
  const add = (['liq', 'vol'] as WidgetId[]).filter(w => !st.slots.widgets.includes(w))
  if (!add.length) return
  const list = st.slots.widgets.slice()
  const at = list.indexOf('walls')
  list.splice(at >= 0 ? at + 1 : list.length, 0, ...add)
  st.slots.widgets = list
}

export function toggleHeat(): void {
  OF.prefs.heat = !OF.prefs.heat
  savePrefs()
  if (!OF.prefs.heat) { OF.heat = null; heatBack = freshBack() }
  OF.version++
  api?.charts().forEach(c => { c.chart.dirty = true })
  sync()
  api?.renderToolbar()
  renderFlowPanel()
}

/** 工具栏上「热力」按钮（放在「记一笔」后面）。 */
export function heatButtonHTML(): string {
  const on = OF.prefs.heat
  return `<button class="tb-btn ${on ? 'on' : ''}" id="tbHeat" aria-pressed="${on}" data-tip="${on ? '关掉' : '打开'}深度热力：三家挂单按价位的浓淡铺在 K 线下面">${I('layers')}热力</button>`
}

// ------------------------------------------------------------------ 指标面板里的一行

export function indicatorRowHTML(): string {
  const on = st.orderFlow
  return `<div class="ind-row ${settingsLayerOpen() ? 'of-set-open' : ''}" data-of-row tabindex="0" role="checkbox" aria-checked="${on}">
    <span class="check-box ${on ? 'on' : ''}">${on ? I('check', 'icon-16') : ''}</span><span class="nm">主力订单流<small>三家大额挂单画在图上</small></span>
    <span class="tag">主图</span>
    <button class="ibtn xs" data-of-set aria-label="门槛与步长" data-tip="门槛与步长">${I('gear', 'icon-16')}</button></div>`
}

/** 指标面板的点击 / 回车：是订单流那一行就处理并返回 true（调用方随后重画列表）。 */
export function indicatorRowClick(t: HTMLElement): boolean {
  const gear = t.closest<HTMLElement>('[data-of-set]')
  if (gear) {
    const a = api?.activeChart()
    const row = gear.closest('[data-of-row]'), panel = gear.closest('.dialog')
    if (a) openOrderFlowSettings(a.symbol, row && panel ? { row: row.getBoundingClientRect(), panel: panel.getBoundingClientRect() } : undefined)
    return true
  }
  if (t.closest('[data-of-row]')) { setOrderFlow(!st.orderFlow); return true }
  return false
}

// ------------------------------------------------------------------ 侧栏「主力订单流」面板

const CHIPS: [keyof Display, string][] = [
  ['spot', '现货'], ['contract', '合约'], ['filledBid', '买单成交'], ['filledAsk', '卖单成交'], ['cancelledBid', '买单撤销'], ['cancelledAsk', '卖单撤销'],
]
const W_TITLE: Record<string, string> = { book: '盘口', tape: '成交', walls: '大单', alerts: '提醒', liq: '流动性', vol: '成交额' }

const sw = (id: string, label: string, on: boolean, tip: string): string =>
  `<div class="of-p-row" data-tip="${tip}"><span>${label}</span><button class="switch" role="switch" data-ofp="${id}" aria-checked="${on}" aria-label="${label}"></button></div>`

/** 图表页 panelFlow 调：整块重画。 */
export function flowPanel(el: HTMLElement): void {
  panelEl = el
  const a = api?.activeChart()
  el.innerHTML = `<div class="sp-head"><h3>${term('主力订单流')}</h3>
      <button class="ibtn sm" data-ofp="settings" aria-label="门槛与步长" data-tip="门槛与步长">${I('gear')}</button></div>
    <div class="scroll of-p">
      <div class="sec-title">显示</div>
      ${sw('flow', '图上订单流', st.orderFlow, '大额挂单画成横带垫在 K 线下面，成交的大单打点')}
      ${sw('ladder', '深度梯子', st.slots.ladder, '价格轴右边的一列三家合并盘口，和图同一根价格轴')}
      ${sw('drawer', '大单列表', st.slots.drawer, '图下面的抽屉，列出这只品种所有大单')}
      ${sw('heat', '深度热力', OF.prefs.heat, '每秒记一列挂单浓淡，之前的时段从服务端补')}
      <div class="sec-title">大单筛选</div>
      <div class="of-p-chips">${CHIPS.map(([k, l]) => `<button class="chip" data-ofp-chip="${k}" aria-pressed="${OF.prefs.display[k]}">${l}</button>`).join('')}</div>
      <div class="sec-title">侧栏小部件<span class="faint">放在「自选」视图里</span></div>
      <div class="of-p-chips">${OF_WIDGETS.map(w => `<button class="chip" data-ofp-w="${w}" aria-pressed="${st.slots.widgets.includes(w)}">${W_TITLE[w]}</button>`).join('')}
        <button class="btn ghost sm" data-ofp="watch">去看 ${I('chevronDown', 'icon-16 of-rot')}</button></div>
      <div class="sec-title">门槛<span class="faint">${a ? esc(baseOfSymbol(a.symbol.toUpperCase()).base) : ''}</span></div>
      <div id="ofpThr"></div>
      <div class="sec-title">数据</div>
      <div id="ofpStatus"></div>
    </div>`
  if (!el.dataset.ofpBound) {
    el.dataset.ofpBound = '1'
    el.addEventListener('click', onPanelClick)
  }
  updateFlowPanel(true)
}

function panelOpen(): boolean { return !!panelEl && panelEl.isConnected && st.panel === 'flow' && !!panelEl.querySelector('.of-p') }
function renderFlowPanel(): void { if (panelOpen()) flowPanel(panelEl!) }

function onPanelClick(e: MouseEvent): void {
  if (st.panel !== 'flow') return
  const t = e.target as HTMLElement
  const chip = t.closest<HTMLElement>('[data-ofp-chip]')
  if (chip) {
    const k = chip.dataset.ofpChip as keyof Display
    OF.prefs.display[k] = !OF.prefs.display[k]; savePrefs()
    chip.setAttribute('aria-pressed', String(OF.prefs.display[k]))
    OF.version++
    api?.charts().forEach(c => { c.chart.dirty = true })
    // 抽屉里那排胶囊是同一套开关
    document.querySelectorAll<HTMLElement>(`#drawerSlot [data-chip="${k}"]`).forEach(x => x.setAttribute('aria-pressed', String(OF.prefs.display[k])))
    updateDrawer(true)
    return
  }
  const wb = t.closest<HTMLElement>('[data-ofp-w]')
  if (wb) {
    const w = wb.dataset.ofpW as WidgetId
    st.slots.widgets = st.slots.widgets.includes(w) ? st.slots.widgets.filter(x => x !== w) : [...st.slots.widgets, w]
    save()
    wb.setAttribute('aria-pressed', String(st.slots.widgets.includes(w)))
    return
  }
  const b = t.closest<HTMLElement>('[data-ofp]')
  if (!b) return
  switch (b.dataset.ofp) {
    case 'settings': { const a = api?.activeChart(); if (a) openOrderFlowSettings(a.symbol); return }
    case 'flow': setOrderFlow(!st.orderFlow); return
    case 'ladder': st.slots.ladder = !st.slots.ladder; save(); sync(); api?.layoutSlots(); b.setAttribute('aria-checked', String(st.slots.ladder)); return
    case 'drawer': st.slots.drawer = !st.slots.drawer; save(); sync(); api?.layoutSlots(); updateDrawer(true); b.setAttribute('aria-checked', String(st.slots.drawer)); return
    case 'heat': toggleHeat(); return
    case 'watch': st.panel = 'watch'; save(); api?.renderPanel(); return
  }
}

let panelSig = ''
/** 每帧只改门槛与状态这两块（开关与胶囊是点了才变）。 */
function updateFlowPanel(force = false): void {
  if (!panelOpen()) return
  const el = panelEl!
  const f = OF.feed, s = OF.snap
  const thr = el.querySelector<HTMLElement>('#ofpThr'), stat = el.querySelector<HTMLElement>('#ofpStatus')
  if (!thr || !stat) return
  let thrHTML: string
  if (!f) thrHTML = `<div class="of-wait faint">${OF.pending ? '正在接三家盘口…' : '打开上面任意一项后开始接三家盘口'}</div>`
  else {
    const t = s?.thresholds ?? f.model.thresholds
    const own = st.orderFlowOverrides[f.base] || {}
    const dec = api?.dec(f.symbol) ?? 2
    thrHTML = `<div class="of-p-kv">${productsOf(t).map(p => `<span>${PRODUCT_FULL[p]}</span><b class="num">${amt(t[p])}${own[p] != null ? '<i class="of-p-own" data-tip="你改过的">·</i>' : ''}</b>`).join('')}
      <span>价位步长</span><b class="num">${t.step != null ? +t.step.toFixed(Math.max(dec, 8)) : '—'}${own.step != null ? '<i class="of-p-own" data-tip="你改过的">·</i>' : ''}</b></div>
      ${f.isCalibrating ? '<div class="faint of-p-note">正在按这只品种的盘口深度定门槛…</div>' : ''}
      <button class="btn secondary sm of-p-btn" data-ofp="settings">${I('gear', 'icon-16')}改门槛与步长</button>`
  }
  let statHTML: string
  if (!f) statHTML = ''
  else {
    const venues = s?.venues ?? []
    const back = heatBack
    const heatText = !OF.prefs.heat ? '关着' : back.status === 'ok' ? `实时每秒一列 · 之前从服务端补（${durShort(back.bucketMs)}一列）`
      : back.status === 'empty' ? '实时每秒一列 · 服务端这段没有记录' : back.status === 'down' ? '实时每秒一列 · 服务端暂时取不到' : '实时每秒一列'
    const hist = f.historyState === 'ok' ? '已并入' : f.historyState === 'down' ? '暂时取不到' : f.historyState === 'incompatible' ? '步长不同，没并' : '正在取'
    statHTML = `<div class="of-p-venues">${venues.length ? venues.map(v => `<span class="of-p-v ${v.ready ? 'ok' : ''}" data-tip="${esc(v.instrument)}${v.ready ? '' : ' · 正在连'}"><i></i>${venueName(v.label || exName(v.exchange), v.product)}</span>`).join('') : '<span class="faint">正在查这只品种在三家的合约…</span>'}</div>
      <div class="of-p-kv">
        <span>线路</span><b>${st.route === 'gateway' ? '网关' : '直连'}</b>
        <span>服务端历史</span><b>${hist}</b>
        <span>深度热力</span><b>${heatText}</b>
        <span>现在挂着</span><b class="num">${s ? s.orders.filter(o => o.status === 'live').length : 0} 单</b>
      </div>`
  }
  const sig = thrHTML + '|' + statHTML
  if (!force && sig === panelSig) return
  panelSig = sig
  if (thr.innerHTML !== thrHTML) thr.innerHTML = thrHTML
  if (stat.innerHTML !== statHTML) stat.innerHTML = statHTML
}

// ------------------------------------------------------------------ 诊断（验收脚本用）

export function orderFlowDebug(): unknown {
  const f = OF.feed
  return {
    symbol: f?.symbol ?? null, feed: f?.debug() ?? null, orders: OF.snap?.orders.length ?? 0,
    live: OF.snap?.orders.filter(o => o.status === 'live').length ?? 0,
    venues: OF.snap?.venues ?? [], heat: OF.heat ? { live: OF.heat.live.length, back: OF.heat.back.length, backRange: OF.heat.backRange } : null,
    heatBack: { ...heatBack }, tape: OF.tape.visible(0, 5).length, tapeVersion: OF.tape.version, thresholds: OF.snap?.thresholds ?? null,
    trades: { size: OF.trades.size, since: OF.trades.since, step: OF.trades.step },
    delta: { status: OF.delta.status, srvStep: OF.delta.srvStep, srvCols: OF.delta.srv?.cols.length ?? 0, srvUrl: OF.delta.srv?.url ?? null, fine: OF.delta.fine.length, coarse: OF.delta.coarse.length },
    liq: { status: OF.liq.status, srv: OF.liq.srv.size, live: OF.liq.live.size, points: OF.liq.points(Date.now()).length },
    vol: { status: OF.vol.status, exchanges: OF.vol.exchanges, slots: OF.vol.slots.filter(x => x.total > 0).length },
    tps: OF.tps.rate(Date.now()), heatFetchSent: heatFetchSent(), ladder: ladderDebug(), tapeRows: tapeDebug(), bigTrade: OF.bigTrade, prefs: { ladderMode: OF.prefs.ladderMode, deltaWin: OF.prefs.deltaWin },
  }
}
;(globalThis as unknown as { __of?: () => unknown }).__of = orderFlowDebug
