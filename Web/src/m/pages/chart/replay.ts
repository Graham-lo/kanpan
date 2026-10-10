/* 手机网页版 · 行情页上的回放（在图上重温 / 交易回放 / 相似片段）
 *
 * 照 iOS：ReviewChartBridge（open / openTrade / 播放循环 / seek / restart / jumpToKey / updateReplay）、
 * ReplayHeaderView（标题、游标那根的时刻 + 浮动盈亏胶囊、开高低收、开仓时写的那句话）、
 * ReviewReplayControls（顶替底栏：退出 · 播放 / 暂停 / 重播 · 进度线 · 倍速 · 关键点）、TradeReplayPainter
 * （开仓均价虚线、成交三角与「开 · 价」标签）。重温与相似片段的覆盖层照 PC 版 review/overlay.ts。
 *
 * 回放是盖在行情页上的一整层，用一张自己的图（ChartView），不碰实时图那一套：不写偏好、不改指标布局、
 * 不订推送；退出就把这一层拆掉，下面那张实时图原样还在。
 * 交易回放要还原当时的场景：往前多垫 300 根历史，均线和当时屏幕上看到的一样；只画「已经放到」的成交，
 * 后面的成交、平仓一律不提前露出来。没有逐根步进，定位只靠拖进度线和跳关键点。
 */
import { ChartView } from '../../chart/view'
import { BarSeries, bar, type Bar, type Interval } from '../../chart/series'
import { makeState, withInput, type ChartState } from '../../chart/state'
import { ViewWindow, priceTransform, SHANGHAI_OFFSET_MIN, ChartContentLayout, type Layout, type PriceRange } from '../../chart/geometry'
import { appChartOptions } from '../../chart'
import { readChartColors, normalizeColor, type ChartColors } from '../../chart/paint'
import { alive, placement, type IndicatorID } from '../../indicator/ids'
import type { ChartRenderer } from '../../chart/renderer'
import { S, REST, j } from '../../../market'
import { st } from '../../app/store'
import type { PriceMode } from '../../app/prefs'
import { fmtPrice } from '../../model/rowText'
import { decimalsOfCloses } from '../../model/reviewBook'
import { el, esc } from '../../ui/dom'
import { hexA } from '../../../util/format'
import { visibleMarks, positionAt, stepDelay, HOLD_MS, type Plan, type TradePlan, type NotePlan, type MatchPlan } from '../../../review/replay'
import * as R from '../../model/replayLogic'

export interface ReplayHost {
  /** 回放层挂在哪（行情页 .cp） */
  page: HTMLElement
  /** 图上用的价格轴（个性化学习的那档） */
  priceMode: (symbol: string) => PriceMode
  /** 指标配色表（行情页那张） */
  indicatorColors: () => ChartState['input']['indicatorColors']
  /** 点了「退出」 */
  onExit: () => void
  /** 打不开：一句话交给宿主提示后退回 */
  onFail: (message: string) => void
}

export interface ReplaySession {
  readonly intent: R.ReplayIntent
  destroy(): void
}

const PAGE = 1500
const MAX_SUBS = 3

const ICON = {
  play: '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="currentColor" d="M7.5 5.2v13.6c0 .9 1 1.5 1.8 1l10.6-6.8c.7-.5.7-1.5 0-2L9.3 4.2c-.8-.5-1.8.1-1.8 1z"/></svg>',
  pause: '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><rect fill="currentColor" x="6" y="4.5" width="4.4" height="15" rx="1.4"/><rect fill="currentColor" x="13.6" y="4.5" width="4.4" height="15" rx="1.4"/></svg>',
  replay: '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M4.6 12a7.4 7.4 0 1 0 2.2-5.3"/><path fill="currentColor" d="M3.6 3.9v4.8c0 .5.4.9.9.9h4.8c.8 0 1.2-1 .6-1.5L5.1 3.3c-.6-.6-1.5-.2-1.5.6z"/></svg>',
}

// ───────────────────────────── 取数

/** 一段 K 线：fetchFrom 起，一页 1500 根往后翻，只要到 stopBar 为止（再往后的是「将来」，不进卷） */
async function fetchTape(plan: Plan, alive: () => boolean): Promise<Bar[]> {
  const out: Bar[] = []
  let cursor = plan.fetchFrom
  while (cursor <= plan.fetchTo && out.length < R.MAX_TAPE_BARS) {
    if (!alive()) return out
    const rows = await j<unknown[][]>(`${REST}/fapi/v1/klines?symbol=${encodeURIComponent(plan.symbol)}&interval=${plan.iv}&startTime=${cursor}&endTime=${plan.fetchTo}&limit=${PAGE}`, 12000, false, alive)
    if (!Array.isArray(rows) || !rows.length) break
    for (const r of rows) {
      const b = bar(Number(r[0]), Number(r[1]), Number(r[2]), Number(r[3]), Number(r[4]), Number(r[5]), Number(r[9]))
      if (b.openTime <= plan.stopBar && (!out.length || b.openTime > out[out.length - 1].openTime)) out.push(b)
    }
    const next = Number(rows[rows.length - 1][0]) + plan.step
    if (!(next > cursor) || rows.length < PAGE) break
    cursor = next
  }
  return out
}

// ───────────────────────────── 覆盖层

interface PaintColors extends ChartColors { accent: string; danger: string; label: string }

function readPaintColors(root: Element): PaintColors {
  const c = readChartColors(root)
  const cs = getComputedStyle(root)
  const v = (n: string, fb: string) => normalizeColor(cs.getPropertyValue(n).trim()) ?? fb
  return { ...c, accent: v('--accent', c.band), danger: v('--danger', c.down), label: v('--ink', c.ink) }
}

interface PaintArgs {
  ctx: CanvasRenderingContext2D
  L: Layout
  r: ChartRenderer
  range: PriceRange
  series: BarSeries
  plan: Plan
  revealed: number
  dec: number
  C: PaintColors
}

const MONO = getComputedStyle(document.documentElement).getPropertyValue('--font-num').trim() || 'ui-monospace, Menlo, monospace'

/** 底色带字的小签（PC overlay 的 label）：放不下右边就翻到左边，夹进图区 */
function chip(a: PaintArgs, x: number, y: number, text: string, bg: string, fg = '#fff', align: 'left' | 'center' = 'left'): void {
  const { ctx, L } = a
  ctx.font = `600 11px ${MONO}`
  const tw = Math.ceil(ctx.measureText(text).width) + 12
  let lx = align === 'left' ? x : x - tw / 2
  if (align === 'left' && lx + tw > L.plotW - 2) lx = x - 8 - tw
  lx = Math.max(2, Math.min(L.plotW - tw - 2, lx))
  ctx.fillStyle = bg
  ctx.beginPath(); ctx.roundRect(lx, y - 9, tw, 18, 4); ctx.fill()
  ctx.fillStyle = fg; ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
  ctx.fillText(text, lx + 6, y + 0.5)
}

/** TradeReplayPainter：均价虚线在下，三角与标签在上 */
function paintTrade(a: PaintArgs, p: TradePlan): void {
  const { ctx, L, r, range, series, revealed: rv, C } = a
  const pane = L.main
  const X = (t: number) => r.x(t, L.plotW)
  const Y = (v: number) => r.yOf(v, pane, range)
  const half = Math.max(1, r.spacing(L.plotW) / 2)
  // 开仓均价：每次开 / 加仓之后一段，方向色 40%，1pt [3,3]
  const dirCol = p.direction === 'long' ? C.up : C.down
  ctx.save()
  ctx.setLineDash([3, 3]); ctx.lineWidth = 1; ctx.strokeStyle = hexA(dirCol, 0.4)
  for (const s of p.avgSegs) {
    if (s.from > rv) break
    const to = Math.min(s.to, rv)
    const y = Math.round(Y(s.price)) + 0.5
    ctx.beginPath(); ctx.moveTo(X(s.from) - half, y); ctx.lineTo(X(to) + half, y); ctx.stroke()
  }
  ctx.restore()
  // 成交三角：买在那根低点下方 6pt 朝上，卖在高点上方 6pt 朝下；同一根上几笔往外叠、隔 2pt
  const SIZE = 8, GAP = 6, STACK = 2
  const taken: R.Rect[] = []
  const labels: { m: (typeof p.marks)[number]; tri: R.Rect; buy: boolean }[] = []
  const perBar = new Map<number, { buys: number; sells: number }>()
  for (const m of visibleMarks(p, rv)) {
    const i = series.firstIndexAtOrAfter(m.bar)
    if (i >= series.count || series.time(i) !== m.bar) continue
    const x = X(m.bar)
    if (x < -SIZE || x > L.plotW + SIZE) continue
    const buy = m.side === 'BUY'
    const slot = perBar.get(m.bar) ?? { buys: 0, sells: 0 }
    perBar.set(m.bar, slot)
    const k = buy ? slot.buys++ : slot.sells++
    const top = buy ? Y(series.low[i]) + GAP + k * (SIZE + STACK) : Y(series.high[i]) - GAP - SIZE - k * (SIZE + STACK)
    const tri: R.Rect = { x: x - SIZE / 2, y: top, w: SIZE, h: SIZE }
    ctx.beginPath()
    if (buy) { ctx.moveTo(x, top); ctx.lineTo(x + SIZE / 2, top + SIZE); ctx.lineTo(x - SIZE / 2, top + SIZE) }
    else { ctx.moveTo(x - SIZE / 2, top); ctx.lineTo(x + SIZE / 2, top); ctx.lineTo(x, top + SIZE) }
    ctx.closePath()
    ctx.fillStyle = buy ? C.up : C.down
    ctx.fill()
    ctx.lineWidth = 1; ctx.strokeStyle = C.bg; ctx.stroke()
    taken.push(tri)
    labels.push({ m, tri, buy })
  }
  // 标签：三角右边 → 左边 → 三角外侧（居中 / 靠左 / 靠右）；不压价格轴与别的记号，尽量不压蜡烛，放不下就不写
  ctx.font = `500 11px ${MONO}`
  const LH = 14
  const vis = r.visible()
  const candles: R.Rect[] = []
  for (let i = Math.max(0, vis.lo); i <= Math.min(series.count - 1, vis.hi); i++) {
    const yh = Y(series.high[i]), yl = Y(series.low[i])
    candles.push({ x: X(series.time(i)) - half, y: Math.min(yh, yl), w: half * 2, h: Math.abs(yl - yh) })
  }
  // 图自己在可见段最高 / 最低那根旁边写着极值签（斜引线往外），这两块也让开
  let hiI = -1, loI = -1
  for (let i = Math.max(0, vis.lo); i <= Math.min(series.count - 1, vis.hi); i++) {
    if (hiI < 0 || series.high[i] > series.high[hiI]) hiI = i
    if (loI < 0 || series.low[i] < series.low[loI]) loI = i
  }
  if (hiI >= 0) taken.push({ x: X(series.time(hiI)) - 4, y: Y(series.high[hiI]) - 24, w: 84, h: 24 })
  if (loI >= 0) taken.push({ x: X(series.time(loI)) - 4, y: Y(series.low[loI]), w: 84, h: 24 })
  const bounds: R.Rect = { x: 0, y: pane.y, w: L.plotW, h: pane.h }
  for (const { m, tri, buy } of labels) {
    const text = `${R.tradeWord(p, m)} · ${fmtPrice(m.price, a.dec)}`
    const w = Math.ceil(ctx.measureText(text).width) + 4
    const cy = tri.y + tri.h / 2 - LH / 2
    const beyond = buy ? tri.y + tri.h + 2 : tri.y - 2 - LH
    const cx = tri.x + tri.w / 2
    const at = R.placeLabel([
      { x: tri.x + tri.w + 4, y: cy, w, h: LH },
      { x: tri.x - 4 - w, y: cy, w, h: LH },
      { x: cx - w / 2, y: beyond, w, h: LH },
      { x: tri.x, y: beyond, w, h: LH },
      { x: tri.x + tri.w - w, y: beyond, w, h: LH },
    ], bounds, taken, candles)
    if (!at) continue
    taken.push(at)
    ctx.textAlign = 'left'; ctx.textBaseline = 'middle'
    ctx.lineJoin = 'round'; ctx.lineWidth = 5; ctx.strokeStyle = C.bg
    ctx.strokeText(text, at.x + 2, at.y + LH / 2)
    ctx.fillStyle = C.label
    ctx.fillText(text, at.x + 2, at.y + LH / 2)
  }
}

/** 重温：圈的那段、判断处、目标 / 失效 / 参考线、答案或到期（照 PC review/overlay.ts drawNote） */
function paintNote(a: PaintArgs, p: NotePlan): void {
  const { ctx, L, r, range, revealed: rv, C } = a
  const pane = L.main, py = pane.y, ph = pane.h
  const X = (t: number) => r.x(t, L.plotW)
  const Y = (v: number) => r.yOf(v, pane, range)
  const half = Math.max(1, r.spacing(L.plotW) / 2)
  const lastRangeBar = p.rangeEnd - p.step
  if (rv >= p.rangeStart) {
    const r0 = X(p.rangeStart) - half, r1 = X(Math.min(lastRangeBar, rv)) + half
    ctx.fillStyle = hexA(C.text, 0.07); ctx.fillRect(r0, py, r1 - r0, ph)
  }
  if (rv < p.judgeBar) return
  const xj = Math.round(X(p.judgeBar)) + 0.5
  ctx.strokeStyle = hexA(C.text, 0.7); ctx.lineWidth = 1; ctx.setLineDash([3, 3])
  ctx.beginPath(); ctx.moveTo(xj, py); ctx.lineTo(xj, py + ph); ctx.stroke(); ctx.setLineDash([])
  chip(a, xj + 4, py + ph - 14, '判断', hexA(C.text, 0.9)) // 贴底：价位签在中间，别和它们叠
  const stopT = Math.min(rv, p.eventBar ?? Infinity, p.expireBar ?? Infinity)
  const x1 = Math.min(L.plotW, X(stopT) + half)
  const tags: { y: number; text: string; col: string }[] = []
  const line = (price: number, col: string, dash: number[], text: string) => {
    if (!Number.isFinite(price)) return
    const y = Math.round(Y(price)) + 0.5
    ctx.strokeStyle = col; ctx.lineWidth = 1; ctx.setLineDash(dash)
    ctx.beginPath(); ctx.moveTo(xj, y); ctx.lineTo(x1, y); ctx.stroke(); ctx.setLineDash([])
    tags.push({ y, text: `${text} ${fmtPrice(price, a.dec)}`, col })
  }
  const rule = p.rule
  if (rule.direction !== 'observe') {
    line(rule.target, C.accent, [], '目标')
    line(rule.invalidation, C.danger, [], '失效')
  }
  line(rule.reference, hexA(C.text, 0.9), [4, 3], rule.direction === 'observe' ? '当时价' : '参考')
  tags.sort((u, v) => u.y - v.y)
  for (let i = 1; i < tags.length; i++) tags[i].y = Math.max(tags[i].y, tags[i - 1].y + 20)
  for (const t of tags) chip(a, x1 + 4, t.y, t.text, t.col)
  const endMark = (t: number | null, text: string, col: string) => {
    if (t == null || t > rv) return
    const x = Math.round(X(t)) + 0.5
    ctx.strokeStyle = col; ctx.lineWidth = 1
    ctx.beginPath(); ctx.moveTo(x, py); ctx.lineTo(x, py + ph); ctx.stroke()
    chip(a, x + 4, py + ph - 38, text, col)
  }
  const good = p.outcome === 'realized'
  if (p.eventBar != null) endMark(p.eventBar, good ? '判对' : p.outcome === 'unrealized' ? '判错' : '答案', good ? C.accent : C.danger)
  else endMark(p.expireBar, '到期', C.text)
}

/** 相似片段：相似段铺一层，两边各一条竖线（PC drawMatch） */
function paintMatch(a: PaintArgs, p: MatchPlan): void {
  const { ctx, L, r, revealed: rv, C } = a
  const pane = L.main, py = pane.y, ph = pane.h
  const X = (t: number) => r.x(t, L.plotW)
  const half = Math.max(1, r.spacing(L.plotW) / 2)
  const last = p.rangeEnd - p.step
  const x0 = X(p.rangeStart) - half, x1 = X(Math.min(last, rv)) + half
  ctx.fillStyle = hexA(C.accent, 0.08); ctx.fillRect(x0, py, x1 - x0, ph)
  ctx.strokeStyle = hexA(C.accent, 0.6); ctx.lineWidth = 1
  ctx.beginPath(); ctx.moveTo(Math.round(x0) + 0.5, py); ctx.lineTo(Math.round(x0) + 0.5, py + ph)
  if (rv >= last) { ctx.moveTo(Math.round(x1) + 0.5, py); ctx.lineTo(Math.round(x1) + 0.5, py + ph) }
  ctx.stroke()
  chip(a, Math.max(4, x0 + 4), py + Math.min(100, ph * 0.3), '相似段', C.accent)
}

// ───────────────────────────── 会话

export function startReplay(intent: R.ReplayIntent, host: ReplayHost): ReplaySession {
  const plan = intent.plan
  const iv = plan.iv as Interval
  let dead = false

  // ---- DOM：页头 · 图 · 播放条
  const layer = el('div', 'cp-replay')
  layer.dataset.kind = plan.kind
  const head = el('div', 'cp-rhead')
  const title = el('div', 'cp-rtitle')
  title.textContent = R.replayTitle(plan)
  const row = el('div', 'cp-rrow')
  const time = el('span', 'cp-rtime')
  const capsule = el('span', 'cp-rcap')
  capsule.hidden = true
  row.append(time, capsule)
  const ohlc = el('div', 'cp-rohlc')
  const caption = el('div', 'cp-rcaption')
  const hasCaption = plan.kind === 'trade' && !!plan.note
  caption.hidden = !hasCaption
  head.append(title, row, ohlc, caption)
  if (plan.kind === 'trade') row.classList.add('trade')

  const box = el('div', 'cp-rchart')
  const scroller = el('div', 'cp-rscroll')
  const content = el('div', 'cp-rcontent')
  scroller.append(content)
  const wait = el('div', 'cp-rwait')
  wait.textContent = '正在取这段行情…'
  box.append(scroller, wait)

  const bar_ = el('div', 'cp-rbar')
  bar_.setAttribute('role', 'toolbar')
  const exit = el('button', 'cp-rbtn cp-rexit')
  exit.type = 'button'; exit.textContent = '退出'
  const play = el('button', 'cp-rbtn cp-rplay')
  play.type = 'button'
  const scrub = el('div', 'cp-rscrub')
  scrub.setAttribute('role', 'slider')
  scrub.setAttribute('aria-label', '回放进度')
  scrub.tabIndex = 0
  const track = el('div', 'cp-rtrack')
  const fill = el('div', 'cp-rfill')
  const ticks = el('div', 'cp-rticks')
  const knob = el('div', 'cp-rknob')
  track.append(fill)
  scrub.append(track, ticks, knob)
  const speedBtn = el('button', 'cp-rbtn cp-rspeed')
  speedBtn.type = 'button'
  const keyBtn = el('button', 'cp-rbtn cp-rkey')
  keyBtn.type = 'button'; keyBtn.textContent = R.keyTitle(plan)
  bar_.append(exit, play, scrub, speedBtn, keyBtn)
  layer.append(head, box, bar_)
  host.page.append(layer)

  const view = new ChartView(content)
  view.onParentScroll = dy => { scroller.scrollTop += dy }

  // ---- 状态
  let tape: Bar[] = []
  let times: number[] = []
  let trk: R.Track = { lower: 0, upper: 0, marks: [] }
  let cursor = 0
  let playing = false
  let scrubbing = false
  let speed = R.normalSpeed(plan.speed)
  let prevLast: number | null = null
  let showCaption = false
  let timer: ReturnType<typeof setTimeout> | null = null
  let dec = 2
  let colors = readPaintColors(host.page)

  const symbolInfo = () => {
    const s = S.symbols.get(plan.symbol)
    if (s && s.dec != null) return { symbol: s.symbol, base: s.base, priceDecimals: s.dec }
    return { symbol: plan.symbol, base: plan.symbol.replace(/USDT$|USDC$|USD$/, '') || plan.symbol, priceDecimals: decimalsOfCloses(tape.map(b => b.close)) ?? 2 }
  }

  const indicators = () => {
    const overlays = alive([...st.overlays] as IndicatorID[]).filter(id => placement(id) === 'main' && id !== 'ORDERFLOW')
    const uniq = R.replaySubs(alive([...st.subs] as IndicatorID[]).filter(id => placement(id) === 'sub'), plan.kind)
      .filter((id, i, a) => a.indexOf(id) === i)
    const counted = uniq.filter(id => id !== 'VOL')
    return { overlays, subs: uniq.filter(id => id === 'VOL' || counted.indexOf(id) < MAX_SUBS) }
  }

  const layoutContent = () => {
    const vh = scroller.clientHeight
    if (!(vh > 0)) return
    const h = ChartContentLayout.height(vh, view.state?.input.subs.length ?? 0, true)
    if (content.style.height !== `${h}px`) content.style.height = `${h}px`
  }
  const ro = new ResizeObserver(() => layoutContent())
  ro.observe(scroller)

  const compose = (s: BarSeries, win: ViewWindow): ChartState => {
    const si = symbolInfo()
    dec = si.priceDecimals
    const { overlays, subs } = indicators()
    const old = view.state
    const options = {
      ...appChartOptions(),
      grid: document.documentElement.dataset.skin === 'classic' ? 'off' as const : 'on' as const,
      // 竖屏主图占比（portraitHeight）跟 appChartOptions 的常量 0.5 走，2026-10-10 起不是偏好
      kind: st.candleKind,
      // 回放用 readingInside（iOS）：十字线读数写在图里，页头留给游标那根
      dataDisplay: 'inside' as const, countdown: false, drawings: false,
      allowMainInversion: false, allowSubInversion: false,
    }
    let state = makeState({
      series: s, symbol: si, view: win, colors,
      price: old ? old.viewport.price : { ...priceTransform(host.priceMode(plan.symbol)), inverted: false },
      overlays, subs, params: st.params, tzOffset: SHANGHAI_OFFSET_MIN, magnet: false,
      decimals: si.priceDecimals, options, nowMs: null,
      subScale: { ...st.subHeightOverrides }, drawings: [],
    })
    state = withInput(state, {
      indicatorColors: host.indicatorColors(), oiSupported: false, externalSupported: false,
      rsiUpper: 70, rsiLower: 30,
    })
    if (old) state = { ...state, overlay: { ...state.overlay, crosshair: old.overlay.crosshair && old.overlay.crosshair.index <= s.count - 1 ? old.overlay.crosshair : null } }
    return state
  }

  /** updateReplay：卷切到游标那根，视野按 ReviewReplayViewport.next 推 */
  const update = (reset: boolean) => {
    if (dead || !tape.length) return
    const s = BarSeries.fromBars(plan.symbol, iv, tape.slice(0, cursor + 1))
    const cur = view.state?.viewport.view
    const w = R.nextWindow(cur ? { to: cur.to, span: cur.span } : null, prevLast, s.lastTime, plan.step, reset)
    view.state = compose(s, new ViewWindow(w.to, w.span))
    prevLast = s.lastTime
    layoutContent()
    renderHead()
    renderBar()
  }

  const renderHead = () => {
    const b = tape[cursor]
    if (!b) return
    time.textContent = R.replayTime(b.openTime, plan.iv)
    ohlc.innerHTML = `<span>开 ${esc(fmtPrice(b.open, dec))}  高 ${esc(fmtPrice(b.high, dec))}</span><span>低 ${esc(fmtPrice(b.low, dec))}  收 ${esc(fmtPrice(b.close, dec))}</span>`
    if (plan.kind === 'trade') {
      const pos = positionAt(plan, b.openTime, b.close)
      capsule.hidden = !pos
      if (pos) {
        const text = R.capsuleText(pos.floating)
        capsule.textContent = text
        capsule.className = 'cp-rcap ' + (/^\+0\.00%$/.test(text) ? 'flat' : text.startsWith('-') ? 'down' : 'up')
      }
    }
    if (hasCaption) {
      caption.textContent = showCaption ? (plan as TradePlan).note ?? '' : ''
    }
  }

  const ended = () => !playing && cursor >= trk.upper
  const renderBar = () => {
    const ready = tape.length > 0
    play.disabled = !ready
    speedBtn.disabled = !ready
    keyBtn.disabled = !ready
    scrub.classList.toggle('off', !ready)
    play.innerHTML = playing ? ICON.pause : ended() && ready ? ICON.replay : ICON.play
    play.setAttribute('aria-label', playing ? '暂停' : ended() ? '重播' : '播放')
    speedBtn.textContent = `${speed}×`
    const f = R.fractionOf(trk, cursor)
    fill.style.width = `${f * 100}%`
    knob.style.left = `${f * 100}%`
    scrub.setAttribute('aria-valuenow', String(Math.round(f * 100)))
    const passed = ticks.children
    R.markFractions(trk).forEach((mf, i) => (passed[i] as HTMLElement | undefined)?.classList.toggle('on', mf <= f + 1e-9))
  }
  const buildTicks = () => {
    ticks.textContent = ''
    for (const f of R.markFractions(trk)) {
      const t = el('i')
      t.style.left = `${f * 100}%`
      ticks.append(t)
    }
  }

  // ---- 播放（iOS 播放循环：每根 1 秒 ÷ 倍速；经过开仓 / 平仓 / 判断 / 答案处多停 1.2 秒）
  const clearTimer = () => { if (timer) { clearTimeout(timer); timer = null } }
  const schedule = (ms: number) => { clearTimer(); timer = setTimeout(tick, ms) }
  function tick(): void {
    timer = null
    if (dead || !playing) return
    if (scrubbing) { schedule(1000 / speed); return }
    showCaption = false
    if (cursor >= trk.upper) { playing = false; renderHead(); renderBar(); return }
    cursor += 1
    const t = times[cursor]
    const pause = R.pausesAt(plan, t)
    if (pause && plan.kind === 'trade' && t === plan.openBar && plan.note) showCaption = true
    update(false)
    if (cursor >= trk.upper) { playing = false; renderBar(); return }
    schedule(stepDelay(speed, pause))
  }
  const setPlaying = (on: boolean) => {
    playing = on
    if (on) schedule(1000 / speed); else clearTimer()
    renderBar()
  }
  const restart = () => {
    cursor = R.clampToTrack(trk, R.indexAtOrBefore(times, R.restartTime(plan)))
    showCaption = false; prevLast = null
    update(true)
    setPlaying(true)
  }
  const seek = (i: number) => {
    const next = R.clampToTrack(trk, i)
    if (next === cursor) return
    cursor = next
    showCaption = false; prevLast = null
    update(false)
  }

  play.onclick = () => {
    if (!tape.length) return
    if (playing) setPlaying(false)
    else if (ended()) restart()
    else setPlaying(true)
  }
  speedBtn.onclick = () => {
    speed = R.cycleSpeed(speed)
    renderBar()
    if (playing) schedule(1000 / speed)
  }
  keyBtn.onclick = () => {
    if (!tape.length) return
    cursor = R.clampToTrack(trk, R.indexAtOrBefore(times, R.keyTime(plan)))
    showCaption = false; prevLast = null
    update(true)
  }
  exit.onclick = () => host.onExit()

  // ---- 进度线：按住就是拖，一松手接着放（拖的时候播放循环原地等）
  const fractionAt = (clientX: number) => {
    const r = track.getBoundingClientRect()
    return r.width > 0 ? (clientX - r.left) / r.width : 0
  }
  scrub.addEventListener('pointerdown', e => {
    if (!tape.length) return
    e.preventDefault()
    scrubbing = true
    scrub.classList.add('dragging')
    scrub.setPointerCapture?.(e.pointerId)
    seek(R.indexAtFraction(trk, fractionAt(e.clientX)))
  })
  scrub.addEventListener('pointermove', e => {
    if (!scrubbing) return
    seek(R.indexAtFraction(trk, fractionAt(e.clientX)))
  })
  const endScrub = () => {
    if (!scrubbing) return
    scrubbing = false
    scrub.classList.remove('dragging')
    if (playing) schedule(1000 / speed)
  }
  scrub.addEventListener('pointerup', endScrub)
  scrub.addEventListener('pointercancel', endScrub)
  scrub.addEventListener('lostpointercapture', endScrub)
  scrub.addEventListener('keydown', e => {
    if (!tape.length) return
    const n = Math.max(1, Math.round((trk.upper - trk.lower) / 20))
    if (e.key === 'ArrowRight') { seek(cursor + n); e.preventDefault() }
    else if (e.key === 'ArrowLeft') { seek(cursor - n); e.preventDefault() }
  })

  // ---- 覆盖层
  view.drawingOverlayPaint = ctx => {
    const s = view.state, L = view.chartLayout, range = view.chartPriceRange, r = view.renderer
    if (!s || !L || !range || !r || !tape.length) return
    const a: PaintArgs = { ctx, L, r, range, series: s.input.series, plan, revealed: tape[cursor].openTime, dec, C: colors }
    ctx.save()
    ctx.beginPath(); ctx.rect(0, L.main.y, L.plotW, L.main.h); ctx.clip()
    if (plan.kind === 'trade') paintTrade(a, plan)
    else if (plan.kind === 'note') paintNote(a, plan)
    else paintMatch(a, plan)
    ctx.restore()
  }

  // ---- 打开：先验市场与长度，再拉卷
  const fail = (k: R.TapeProblem) => { if (!dead) host.onFail(R.TAPE_MESSAGE[k]) }
  renderBar()
  speedBtn.textContent = `${speed}×`
  if (!R.replayableMarket(intent.market)) queueMicrotask(() => fail('market'))
  else if (R.tapeTooLarge(plan)) queueMicrotask(() => fail('tooLarge'))
  else {
    fetchTape(plan, () => !dead).then(bars => {
      if (dead) return
      const problem = R.checkTape(bars.map(b => b.openTime), plan)
      if (problem) { fail(problem); return }
      tape = bars
      times = bars.map(b => b.openTime)
      trk = R.makeTrack(times, plan)
      buildTicks()
      cursor = R.clampToTrack(trk, R.indexAtOrBefore(times, R.openTime(plan)))
      wait.hidden = true
      update(true)
      if (R.autoplays(plan)) { playing = true; renderBar(); schedule(HOLD_MS) }
    }, () => fail('failed'))
  }

  return {
    intent,
    destroy(): void {
      if (dead) return
      dead = true
      clearTimer()
      ro.disconnect()
      view.drawingOverlayPaint = null
      view.destroy()
      layer.remove()
    },
    /** 换皮肤：重读颜色重画 */
    ...{ restyle: () => { colors = readPaintColors(host.page); if (tape.length) update(false) } },
  } as ReplaySession & { restyle(): void }
}
