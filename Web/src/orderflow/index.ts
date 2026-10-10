/* Hkline Web · 主力订单流 · 控制器（设计稿 2.1–2.7）
 *
 * 图表页只通过 installOrderFlow(api) 和几个 HTML 片段接进来；这里负责：
 *   · 数据层的生命周期：跟着活动格子的品种开一个 OrderFlowFeed（各家一起连），换品种就换，
 *     没有任何展示需要它（图上订单流、梯子、热力、小部件、面板都关着）或离开图表页一分钟后就停；
 *   · 每帧（半秒）把快照分发给图上层、梯子、小部件、抽屉、面板；
 *   · 深度热力：实时每秒一列，实时开始之前的时段向服务端要回填（按返回的 bucketMs 画列宽）；
 *   · 「主力订单流」侧栏面板、工具栏的「热力」按钮、指标里的那一行与齿轮。
 * 数据规则（门槛、分桶、出现 / 消失 / 结局）都在 model / feed 里照手机端的 Swift 模型，这里只管展示。
 */
import './orderflow.css'
import { st, save } from '../app/store'
import { I, esc } from '../ui/dom'
import { patchShell } from '../ui/patch'
import { term } from '../ui/overlay'
import { BT } from '../terms'
import { OrderFlowFeed, getJSON, type TradeEvent } from './feed'
import { buildFine, exName } from './aggregate'
import { HeatStore, parseHeat, heatHint, heatRing, heatUrl, type HeatRing } from './heat'
import { Tape } from './tape'
import { TradeLadder } from './tradeLadder'
import { TpsMeter } from './stats'
import { FeedKeeper } from './keep'
import { recordFeedTrade, feedBeat, tierFloor } from './flowTap'
import { recordFootprintTrade, footprintWanted } from '../chart/footprint'
import { heatFetchSent } from './heatFetch'
import { createLayer } from './layer'
import { mountLadder, ladderVisible, drawLadder, resetLadder, ladderDebug } from './ladder'
import { mountDrawer, updateDrawer } from './drawer'
import { widgetHTML, mountWidgets, isOfWidget, updateWidgets, resetTape, scheduleTape, markWall, tapeDebug } from './widgets'
import { openOrderFlowSettings, settingsLayerOpen } from './settingsDialog'
import { D, baseOfSymbol, productsOf } from './settings'
import { OF, savePrefs, amt, PRODUCT_FULL, type Api } from './state'
import { orderId, type BigOrder } from './types'
import type { Snapshot } from './model'
import type { TVChart } from '../chart/chart'
import { settle } from '../market/settle'
import { IdleGate } from './idle'
import { before } from '../util/clock'

export { mountLadder, mountDrawer, widgetHTML, mountWidgets, isOfWidget, openOrderFlowSettings }
/** 侧栏某块是不是收起（本机偏好） */
export const isCollapsed = (w: string): boolean => OF.prefs.collapsed.includes(w)

const SYNC_MS = 500
/** 回填最多往前要多久（服务端历史只留几天） */
const HEAT_BACK_MAX_MS = 3 * 86_400_000
const HEAT_RETRY_MS = 20_000

let api: Api | null = null
const attached = new WeakSet<TVChart>()
let overrideSig = ''
/** 离开图表页、或标签页藏到后台一分钟就停掉数据层（一分钟内切回来不用重连），见 idle.ts */
const idle = new IdleGate()
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
  OF.focus = focusOrder
  // 藏着时不做整套评估，只看要不要收掉数据层（原来藏着时一拍都不跑，后台标签页的几条簿 / 成交连接永远不关）
  setInterval(() => {
    if (document.visibilityState !== 'hidden') sync()
    else if ((OF.feed || keeper.size) && !idle.want(true, Date.now())) { if (OF.feed) stopFeed(); keeper.clear() }
  }, SYNC_MS)
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') sync() })
  sync()
}

/** 有没有哪个展示在用订单流的数据。 */
function needed(): boolean {
  if (st.orderFlow || st.slots.ladder || st.slots.drawer || OF.prefs.heat) return true
  // 副图「累计量差」的各家实时段、「大单与散户累计量差」都靠这里的逐笔成交
  if (st.ind.subs.includes('cvd') || st.ind.subs.includes('whale')) return true
  if (footprintWanted()) return true
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
  const away = st.page !== 'chart' || document.visibilityState === 'hidden'
  // 美元指数没有盘口（算出来的指数，没有簿）：不起订单流 / 盘口 / 成交（照 iOS hasOrderFlow）
  const want = idle.want(away, Date.now()) && !!act && act.symbol.toUpperCase() !== 'DXY' && needed()
  if (!want) { if (OF.feed) stopFeed(); keeper.clear(); setPending(false); return }
  const symbol = act!.symbol.toUpperCase()
  // 换品种：旧的那只先留着（keep.ts：最多两只、三分钟），切回来接着用
  if (OF.feed && OF.feed.symbol !== symbol) stopFeed(true)
  if (!OF.feed) {
    const kept = keeper.take(symbol)
    if (kept) { setPending(false); resumeFeed(kept) }
    // 深度快照（合约 20、现货 250 权重）、合约清单、步长这些不在首屏：连切时中间划过的品种不接，停稳约半秒再接
    else if (!settle.settled()) { setPending(true); settle.whenSettled('orderflow', sync); return }
    else { setPending(false); startFeed(act!.symbol) }
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

/** 换走了留着的那几只各自的逐笔累计（成交带、梯子中列、每秒成交、单子峰值）：留着期间照样往里记，换回来接着用 */
interface Kept { tape: Tape; trades: TradeLadder; tps: TpsMeter; peaks: Map<string, number>; sig: string }
const keptState = new WeakMap<OrderFlowFeed, Kept>()
const keeper = new FeedKeeper<OrderFlowFeed>({ onDrop: f => keptState.delete(f) })

function startFeed(symbol: string): void {
  const s = api!
  const own = st.orderFlowOverrides[baseOfSymbol(symbol.toUpperCase()).base] ?? null
  overrideSig = JSON.stringify(own)
  const f: OrderFlowFeed = new OrderFlowFeed({
    symbol, crypto: s.crypto(symbol), turnover24h: s.turnover(symbol), tick: null, route: st.route, override: own,
    // 鼠标停在色块 / 梯子行上、或点选了某一单：逐拍给精确金额；平时金额 5 秒换一次（feed.ts 的 FramePacer）
    precise: () => OF.hoverRow != null || OF.highlight != null,
    onFrame, onTrade: ev => onTrade(f, ev),
  })
  OF.feed = f
  resetSymbolState()
  void f.start()
  renderFlowPanel()
}

/** 切回刚看过的那只：连接、簿、历史都还在，逐笔累计换回它自己那份，马上出一帧 */
function resumeFeed(f: OrderFlowFeed): void {
  const k = keptState.get(f)
  keptState.delete(f)
  OF.feed = f
  resetSymbolState()
  if (k) { OF.tape = k.tape; OF.trades = k.trades; OF.tps = k.tps; OF.peaks = k.peaks; OF.version++ }
  // 留着期间门槛若改过：紧接着的 sync 比对后再套（没改就不动）
  overrideSig = k?.sig ?? '\u0000'
  f.unpark()
  renderFlowPanel()
}

/** 等品种停稳的那半秒：各处空态写「正在接盘口…」，不写「打开指标后显示」 */
function setPending(v: boolean): void {
  if (OF.pending === v) return
  OF.pending = v
  updateWidgets(); updateDrawer(true); renderFlowPanel()
}

/** keep = true：换品种，这只先留着（逐笔累计跟着它走）；否则停掉 */
function stopFeed(keep = false): void {
  const f = OF.feed
  if (f && keep) {
    keptState.set(f, { tape: OF.tape, trades: OF.trades, tps: OF.tps, peaks: OF.peaks, sig: overrideSig })
    OF.tape = new Tape(); OF.trades = new TradeLadder(); OF.tps = new TpsMeter(); OF.peaks = new Map()
    keeper.park(f.symbol, f)
  } else f?.stop()
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
  // 各家逐笔的覆盖心跳：连接都开着这半秒才算盖住（副图累计量差 / 大单与散户）
  feedBeat(f, now)
  OF.fine = buildFine(f.model, D.fineRadiusBps, now)
  if (OF.prefs.heat && OF.fine) {
    if (!OF.heat || OF.heat.step !== OF.fine.step) { OF.heat = new HeatStore(OF.fine.step); heatBack = freshBack() }
    OF.heat.sample(OF.fine, s.thresholds, now)
  }
  OF.bigTrade = tierFloor(s.thresholds)
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

function onTrade(f: OrderFlowFeed, ev: TradeEvent): void {
  if (f !== OF.feed) { keptTrade(f, ev); return }
  const v = ev.book.venue
  recordFeedTrade(f.symbol, ev, OF.snap?.thresholds)
  recordFootprintTrade(f.symbol, ev)
  const row = OF.tape.push({
    t: ev.trade.timeMs || Date.now(), exchange: v.exchange, label: exName(v.exchange), product: v.product,
    side: ev.trade.hitSide === 'ask' ? 'buy' : 'sell', price: ev.trade.price, usd: ev.usd, qty: ev.trade.quantity, instrument: v.instrument,
  })
  // 梯子中列：按细桶累加主动买 / 主动卖；详情里的每秒成交
  const step = f.model.scheme?.step
  if (step) OF.trades.add(ev.trade.price, ev.usd, row.side, step, row.t)
  OF.tps.add(Date.now())
  scheduleTape()
}

/** 留着的那只来的逐笔：记进它自己那份（按品种记的成交流、足迹照常记） */
function keptTrade(f: OrderFlowFeed, ev: TradeEvent): void {
  const k = keptState.get(f)
  if (!k) return
  recordFeedTrade(f.symbol, ev, f.model.thresholds)
  recordFootprintTrade(f.symbol, ev)
  const v = ev.book.venue
  const row = k.tape.push({
    t: ev.trade.timeMs || Date.now(), exchange: v.exchange, label: exName(v.exchange), product: v.product,
    side: ev.trade.hitSide === 'ask' ? 'buy' : 'sell', price: ev.trade.price, usd: ev.usd, qty: ev.trade.quantity, instrument: v.instrument,
  })
  const step = f.model.scheme?.step
  if (step) k.trades.add(ev.trade.price, ev.usd, row.side, step, row.t)
  k.tps.add(Date.now())
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
  if (before(heatBack.retryAt, HEAT_RETRY_MS, now)) return
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

/** 图上订单流的总开关（指标行、面板里的开关都走这里）。只管自己这一颗：梯子、抽屉、热力、侧栏小部件各有各的开关，
 *  不再「第一次打开就把整套摆出来」、也不再跟着开 / 关抽屉（用户 2026-10-08：开第一颗后面全开了，体验很不好）。 */
export function setOrderFlow(on: boolean): void {
  st.orderFlow = on
  save()
  OF.version++
  api?.charts().forEach(c => { c.chart.dirty = true })
  sync()
  api?.renderPanel()
  api?.renderToolbar()
}

/** 图上大单标记（透明气泡）：和手机「图上大单标记」同一颗、同一个共用字段 bigTradeSigns，和订单流横带的开关各管各的 */
export function setBigTradeSigns(on: boolean): void {
  st.bigTradeSigns = on
  save()
  api?.charts().forEach(c => { c.chart.dirty = true })
  api?.renderToolbar()
  renderFlowPanel()
}

/** 图上挂单历史的同一颗开关：指标弹窗与右侧面板共用。 */
export function setOrderFlowHistory(on: boolean): void {
  st.orderFlowHistory = on
  OF.highlight = null
  OF.version++
  save()
  api?.charts().forEach(c => { c.chart.dirty = true })
  renderFlowPanel()
}

/** 深度热力的唯一开关在主力订单流面板「深度热力」一行（2026-10-10 起工具条不再放「热力」按钮：一个动作一个入口） */
export function toggleHeat(): void {
  OF.prefs.heat = !OF.prefs.heat
  savePrefs()
  if (!OF.prefs.heat) { OF.heat = null; heatBack = freshBack() }
  OF.version++
  api?.charts().forEach(c => { c.chart.dirty = true })
  sync()
  renderFlowPanel()
}

// ------------------------------------------------------------------ 指标面板里的一行

export function indicatorRowHTML(): string {
  const on = st.orderFlow
  return `<div class="ind-row ${settingsLayerOpen() ? 'of-set-open' : ''}" data-of-row tabindex="0" role="checkbox" aria-checked="${on}">
    <span class="check-box ${on ? 'on' : ''}">${on ? I('check', 'icon-16') : ''}</span><span class="nm">主力订单流<small>各家大额挂单画在图上</small></span>
    <span class="tag">主图</span>
    <button class="ibtn xs" data-of-set aria-label="门槛与步长" data-tip="门槛与步长">${I('gear', 'icon-16')}</button></div>
    <div class="ind-row" data-of-history tabindex="0" role="checkbox" aria-checked="${st.orderFlowHistory}"><span class="check-box ${st.orderFlowHistory ? 'on' : ''}">${st.orderFlowHistory ? I('check', 'icon-16') : ''}</span><span class="nm">历史大单</span></div>
    <div class="ind-row" data-of-marks tabindex="0" role="checkbox" aria-checked="${st.bigTradeSigns}"><span class="check-box ${st.bigTradeSigns ? 'on' : ''}">${st.bigTradeSigns ? I('check', 'icon-16') : ''}</span><span class="nm">${BT.chartMarks}</span></div>`
}

/** 指标面板的点击 / 回车：是订单流那一行就处理并返回 true（调用方随后重画列表）。 */
export function indicatorRowClick(t: HTMLElement): boolean {
  if (t.closest('[data-of-history]')) {
    setOrderFlowHistory(!st.orderFlowHistory)
    return true
  }
  if (t.closest('[data-of-marks]')) { setBigTradeSigns(!st.bigTradeSigns); return true }
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

/** 四行开关前面的小图标：「质感」一套（docs/prototypes/web-visual-2026-10-08.html §ofTiles）——
 *  和左右栏同一块中性磨砂底（styles/icons.css 的 .of-p-row .tgi），18 格小图；强调 / 涨 / 跌三色在 oklch 里色度 × .6、明度不动，
 *  热力的亮格用皮肤强调字色；主力订单流两根横带在竖条两侧留缝（和右栏那只同一画法）；抽屉上的两道小白条改成底块中间色（看着是镂空）。 */
const svg18 = (body: string): string => `<svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">${body}</svg>`
const rr = (x: number, y: number, w: number, h: number, rx: number, c: string, o = 1): string =>
  `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${rx}" fill="${c}"${o === 1 ? '' : ` opacity="${o}"`}/>`
const QA = 'var(--ofq-a)', QU = 'var(--ofq-u)', QD = 'var(--ofq-d)', QH = 'var(--qac)', QM = 'var(--qtm)'
let ofMask = 0
const TILE: Record<string, () => string> = {
  history: () => `<span class="tgi">${I('replay')}</span>`,
  // 图上大单标记：大小两颗透明气泡（涨 / 跌色）
  marks: () => `<span class="tgi">${svg18(`<circle cx="6.5" cy="11" r="4.5" fill="${QU}" opacity=".55"/><circle cx="12.5" cy="6" r="3.5" fill="${QD}" opacity=".7"/>`)}</span>`,
  flow: () => {
    const id = 'ofq' + (++ofMask)
    return `<span class="tgi">${svg18(
      `<mask id="${id}" maskUnits="userSpaceOnUse" x="-2" y="-2" width="22" height="22"><rect x="-2" y="-2" width="22" height="22" fill="#fff"/><path d="M6 .5V17.5M12 3.5V16.5" stroke="#000" stroke-width="4.2" stroke-linecap="round"/></mask>` +
      `<g mask="url(#${id})">${rr(1, 4, 16, 3, 1.5, QA, .4)}${rr(1, 11, 16, 3, 1.5, QA, .7)}</g>${rr(5, 2, 2, 14, 1, QU)}${rr(11, 5, 2, 10, 1, QD)}`)}</span>`
  },
  ladder: () => `<span class="tgi">${svg18(rr(3, 2, 12, 2.4, 1.2, QD, .55) + rr(6, 5.6, 9, 2.4, 1.2, QD) + rr(7, 10, 8, 2.4, 1.2, QU) + rr(2, 13.6, 13, 2.4, 1.2, QU, .55))}</span>`,
  drawer: () => `<span class="tgi">${svg18(rr(2, 10, 14, 6, 2, QA) + rr(2, 2, 14, 6, 2, QA, .28) + rr(5, 12.2, 4, 1.6, .8, QM) + rr(10, 12.2, 3, 1.6, .8, QM, .7))}</span>`,
  heat: () => `<span class="tgi">${svg18([0, 1, 2, 3].map(c => [0, 1, 2, 3].map(r =>
    rr(1 + c * 4.2, 1 + r * 4.2, 3.4, 3.4, .8, (c + r) % 3 ? QA : QH, +(.25 + ((c * 3 + r * 5) % 7) / 9).toFixed(2))).join('')).join(''))}</span>`,
}

/** 面板贴在屏幕右缘：提示出在行的左侧（data-tip-side="left"），不盖本行开关、不压下一行；左边放不下时自动翻面（ui/tipPlace.ts） */
const sw = (id: string, label: string, on: boolean, tip: string): string =>
  `<div class="of-p-row" data-tip="${tip}" data-tip-side="left">${TILE[id]?.() ?? ''}<span class="l">${label}</span><button class="switch" role="switch" data-ofp="${id}" aria-checked="${on}" aria-label="${label}"></button></div>`

/** 图表页 panelFlow 调：整块重画。 */
export function flowPanel(el: HTMLElement): void {
  panelEl = el
  const a = api?.activeChart()
  el.innerHTML = `<div class="sp-head"><h3>${term('主力订单流')}</h3>
      <button class="ibtn sm" data-ofp="settings" aria-label="门槛与步长" data-tip="门槛与步长">${I('gear')}</button></div>
    <div class="scroll of-p">
      <div class="sec-title">显示</div>
      ${sw('flow', '图上订单流', st.orderFlow, '大额挂单画成横带垫在 K 线下面')}
      ${sw('history', '历史大单', st.orderFlowHistory, '显示已结束的挂单；关闭时只看仍有效的挂单')}
      ${sw('marks', BT.chartMarks, st.bigTradeSigns, '成交的大单与爆仓在 K 线上画成气泡')}
      ${sw('ladder', '深度梯子', st.slots.ladder, '价格轴右边的一列各家合并盘口，和图同一根价格轴')}
      ${sw('drawer', '大单列表', st.slots.drawer, '图下面的抽屉，列出这只品种所有大单')}
      ${sw('heat', '深度热力', OF.prefs.heat, '每秒记一列挂单浓淡，之前的时段从服务端补')}
      <div class="sec-title">门槛<span class="faint">${a ? esc(baseOfSymbol(a.symbol.toUpperCase()).base) : ''}</span></div>
      <div id="ofpThr"></div>
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
  const b = t.closest<HTMLElement>('[data-ofp]')
  if (!b) return
  switch (b.dataset.ofp) {
    case 'settings': { const a = api?.activeChart(); if (a) openOrderFlowSettings(a.symbol); return }
    case 'flow': setOrderFlow(!st.orderFlow); return
    case 'history': setOrderFlowHistory(!st.orderFlowHistory); return
    case 'marks': setBigTradeSigns(!st.bigTradeSigns); return
    case 'ladder': st.slots.ladder = !st.slots.ladder; save(); sync(); api?.layoutSlots(); b.setAttribute('aria-checked', String(st.slots.ladder)); return
    case 'drawer': st.slots.drawer = !st.slots.drawer; save(); sync(); api?.layoutSlots(); updateDrawer(true); b.setAttribute('aria-checked', String(st.slots.drawer)); return
    case 'heat': toggleHeat(); return
  }
}

let panelSig = ''
/** 每帧只改门槛这一块（开关是点了才变）。 */
function updateFlowPanel(force = false): void {
  if (!panelOpen()) return
  const el = panelEl!
  const f = OF.feed, s = OF.snap
  const thr = el.querySelector<HTMLElement>('#ofpThr')
  if (!thr) return
  let thrHTML: string
  if (!f) thrHTML = `<div class="of-wait faint">${OF.pending ? '正在接各家盘口…' : '打开上面任意一项后开始接各家盘口'}</div>`
  else {
    const t = s?.thresholds ?? f.model.thresholds
    const own = st.orderFlowOverrides[f.base] || {}
    const dec = api?.dec(f.symbol) ?? 2
    thrHTML = `<div class="of-p-kv">${productsOf(t).map(p => `<span>${PRODUCT_FULL[p]}</span><b class="num">${amt(t[p])}${own[p] != null ? '<i class="of-p-own" data-tip="你改过的">·</i>' : ''}</b>`).join('')}
      <span>价位步长</span><b class="num">${t.step != null ? +t.step.toFixed(Math.max(dec, 8)) : '—'}${own.step != null ? '<i class="of-p-own" data-tip="你改过的">·</i>' : ''}</b></div>
      ${f.isCalibrating ? '<div class="faint of-p-note">正在按这只品种的盘口深度定门槛…</div>' : ''}
      <button class="btn secondary sm of-p-btn" data-ofp="settings">${I('gear', 'icon-16')}改门槛与步长</button>`
  }
  if (!force && thrHTML === panelSig) return
  panelSig = thrHTML
  // 拿拼好的字符串当键比，不拿 innerHTML 比（齿轮 SVG 的自闭合标签读回来写法不同，那样每次都判成变了、把「改门槛与步长」钮换掉）
  patchShell(thr, thrHTML, thrHTML)
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
