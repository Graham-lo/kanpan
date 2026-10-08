// 手机网页 · 「大单与爆仓」弹层：纯函数 + 片段 HTML + 胶水（BigTradeController）在半屏 / 满屏 / 骨架 / 现货 / 爆仓空 / 停住
// 各状态下交给弹层的模型，以及十字线联动（拉到哪根看哪根、抬手 3 秒回本根、点签只换根、点「每根」十字线跳过去）。
// 场地：node 里假的 DOM 元素与假画布；弹层本体换成只记 update 的替身（真 DOM 走 scripts/m-bigtrade.mjs 截图验收）。
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  netText, summaryLine, niceStep, ladderRows, liqCells, LIQ_CELLS, LIQ_CELL_MS,
  liqCardHTML, barsCardHTML, ladderCardHTML, liqDayCardHTML, type BtModel, type LiqModel, type Detent,
} from '../src/m/pages/chart/bigTradeSheet'
import { BigTradeController, RETURN_MS, STALE_MS, SKELETON_MS, type BtForce } from '../src/m/pages/chart/bigTrade'
import { LiqStore, type LiqRow } from '../src/orderflow/liquidation'
import { recordTrade, resetFlows, flowOf } from '../src/chart/tradeFlow'
import { BarSeries, INTERVAL_STEP } from '../src/m/chart/series'
import { makeState } from '../src/m/chart/state'
import { ViewWindow } from '../src/m/chart/geometry'
import { ChartView } from '../src/m/chart/view'
import { st } from '../src/m/app/store'

// ------------------------------------------------------------------ 纯函数

describe('大单与爆仓 · 纯函数', () => {
  it('净买 / 净卖文字与分析面板那一行', () => {
    expect(netText(1_200_000)).toBe('净买入 +1.2M')
    expect(netText(-350_000)).toBe('净卖出 −350.0K')
    expect(summaryLine(null)).toBe('本根暂无大单')
    expect(summaryLine({ bb: 0, bs: 0, bn: 0, sn: 0, has: true })).toBe('本根暂无大单')
    expect(summaryLine({ bb: 2_000_000, bs: 800_000, bn: 3, sn: 1, has: true })).toBe('本根 净买入 +1.2M')
  })

  it('好看的步长：1 / 2 / 2.5 / 5 × 10^k', () => {
    expect(niceStep(0.7)).toBe(1); expect(niceStep(1.3)).toBe(2); expect(niceStep(2.2)).toBe(2.5)
    expect(niceStep(3)).toBe(5); expect(niceStep(7)).toBe(10); expect(niceStep(0.03)).toBeCloseTo(0.05)
    expect(niceStep(0)).toBe(1); expect(niceStep(NaN)).toBe(1)
  })

  it('价位梯：11 行、现价居中、行距盖住最远那档；墙落在对应行', () => {
    const lv = { buy: [{ price: 100.4, usd: 500_000 }, { price: 99, usd: 200_000 }], sell: [{ price: 101.2, usd: 300_000 }] }
    const rows = ladderRows(lv as never, 100, 0.1, { ask: { price: 101, usd: 2e6 } as never, bid: null })
    expect(rows.length).toBe(11)
    expect(rows[5].now).toBe(true); expect(rows[5].price).toBe('100.00')
    // 最远 1.2 → 行距 niceStep(0.24) = 0.25
    expect(rows[0].price).toBe('101.25'); expect(rows[10].price).toBe('98.75')
    const buyRow = rows.find(r => r.buy === 500_000)!
    expect(buyRow.bw).toBe(100)
    expect(rows.find(r => r.sell === 300_000)!.sw).toBeCloseTo(60)
    expect(rows.filter(r => r.askWall === 2e6).length).toBe(1)
    expect(rows.every(r => r.bidWall == null)).toBe(true)
    expect(ladderRows(lv as never, 0, 0.1, { ask: null, bid: null })).toEqual([])
  })

  it('24 小时爆仓 96 格：每格 15 分钟，最后一格含现在，超出范围的行不算', () => {
    const now = 1_760_000_000_000
    const last = Math.floor(now / LIQ_CELL_MS) * LIQ_CELL_MS
    const row = (t: number, lo: number, sh: number): LiqRow => [t, lo, sh, 1, Math.max(lo, sh), 100, lo ? 0 : 1, 0]
    const { start, cells } = liqCells([row(last + 60_000, 10, 0), row(last - 1, 0, 7), row(last - 200 * LIQ_CELL_MS, 99, 99)], now)
    expect(cells.length).toBe(LIQ_CELLS)
    expect(start).toBe(last - 95 * LIQ_CELL_MS)
    expect(cells[95]).toEqual([10, 0]); expect(cells[94]).toEqual([0, 7])
    expect(cells.reduce((s, c) => s + c[0] + c[1], 0)).toBe(17)
  })
})

// ------------------------------------------------------------------ 片段

const zero = { long: 0, short: 0, n: 0, max: null }
function liqM(o: Partial<LiqModel> = {}): LiqModel {
  return { state: 'data', hour: zero, today: zero, day: zero, cells: Array.from({ length: 96 }, () => [0, 0] as [number, number]), from: '昨天 12:30', maxWhen: '', maxPrice: '', selCell: -1, ...o }
}

describe('大单与爆仓 · 片段', () => {
  it('爆仓卡：现货整块不出现；骨架 / 暂无数据 / 今日无爆仓 / 有数；只留数字与短标签', () => {
    expect(liqCardHTML(null, false)).toBe('')
    expect(liqCardHTML(liqM({ state: 'loading' }), false)).toContain('bt-skel')
    expect(liqCardHTML(liqM({ state: 'none' }), false)).toContain('<b>暂无爆仓数据</b>')
    expect(liqCardHTML(liqM(), false)).toContain('<b>今日无爆仓</b></div>')
    const max: LiqRow = [0, 900_000, 0, 1, 900_000, 98765.4, 0, 1]
    const m = liqM({ hour: { long: 1_000_000, short: 200_000, n: 4, max }, today: { long: 3e6, short: 1e6, n: 9, max }, day: { long: 5e6, short: 2e6, n: 20, max }, maxWhen: '12:31', maxPrice: '98765.4' })
    const half = liqCardHTML(m, false)
    for (const x of ['被打得更狠', '多空都稳着', '空爆', '多爆', '被平']) expect(half).not.toContain(x)
    expect(half).toContain('空单爆仓 200.0K'); expect(half).toContain('多单爆仓 1.0M'); expect(half).toContain('今日最大单笔 <b class="down">多单 900.0K</b>'); expect(half).toContain('@ 98765.4 · 12:31')
    expect(half).not.toContain('24 小时 多单')
    expect(liqCardHTML(m, true)).toContain('24 小时 多单 <b>5.0M</b>')
  })

  it('每根：40 根一根一组，看的那根加框，点过的那根闪；最后一根带呼吸点', () => {
    const bars = Array.from({ length: 40 }, (_, i) => ({ t: i * 1000, bb: i % 3 ? 100_000 * i : 0, bs: i % 2 ? 50_000 * i : 0, label: `L${i}` }))
    const h = barsCardHTML(bars, 5000, 7000)
    expect(h.match(/<g data-t=/g)!.length).toBe(40)
    expect(h).toContain('<g data-t="5000" class="on">')
    expect(h).toContain('<g data-t="7000" data-flash="1">')
    expect(h.match(/bt-sel/g)!.length).toBe(1)
    expect(h).toContain('bt-breath')
    expect(h).toContain('<span>L0</span><span>L19</span><span>L39</span>')
    expect(barsCardHTML([], null, null)).toBe('')
  })

  it('价位梯：有量但很短的条画成最窄 4px、圆角 3 的矮矩形，不缩成细线；没量的不画', () => {
    const rows = ladderRows({ buy: [{ price: 100, usd: 1e6 }, { price: 100.5, usd: 1e3 }], sell: [] } as never, 100, 0.5, { ask: null, bid: null })
    const lad = ladderCardHTML(rows)
    const tiny = rows.find(r => r.buy > 0 && r.buy < 1e4)!
    expect(tiny.bw * 0.62).toBeLessThan(3)
    expect(lad).toContain('<i class="tiny" style="width:max(4px,')
    expect(lad.match(/class="tiny"/g)!.length).toBe(1)
    expect(lad).toContain('<i style="width:0%"></i>')
  })
  it('价位梯与 24 小时爆仓：墙写成「墙 2.0M」，96 格、最大一笔一行', () => {
    const rows = ladderRows({ buy: [{ price: 100, usd: 1e6 }], sell: [] } as never, 100, 0.5, { ask: null, bid: { price: 99, usd: 2e6 } as never })
    const lad = ladderCardHTML(rows)
    expect(lad.match(/class="p/g)!.length).toBe(11)
    expect(lad).toContain('买墙 2.0M'); expect(lad).toContain('class="p now"')
    expect(ladderCardHTML(null)).toBe('')
    const cells = Array.from({ length: 96 }, (_, i) => [i === 3 ? 500 : 0, i === 90 ? 800 : 0] as [number, number])
    const max: LiqRow = [0, 0, 800, 1, 800, 12.5, 1, 1]
    const d = liqDayCardHTML(liqM({ cells, today: { long: 500, short: 800, n: 2, max }, day: { long: 500, short: 800, n: 2, max }, maxWhen: '09:15', maxPrice: '12.5', selCell: 90 }))
    expect(d.match(/class="bt-[ud]"/g)!.length).toBe(2)
    expect(d).toContain('bt-sel'); expect(d).toContain('今日最大单笔 · 空单爆仓'); expect(d).toContain('OKX')
    expect(d).toContain('<span class="rt">24 小时</span>'); expect(d).not.toContain('每格 15 分钟')
    // 服务端 max_ex = 2 是 Bybit
    const byb: LiqRow = [0, 0, 800, 1, 800, 12.5, 1, 2]
    expect(liqDayCardHTML(liqM({ cells, today: { long: 0, short: 800, n: 1, max: byb }, day: { long: 0, short: 800, n: 1, max: byb }, maxWhen: '09:15', maxPrice: '12.5', selCell: -1 }))).toContain('Bybit')
    expect(liqDayCardHTML(liqM({ state: 'none' }))).toBe('')
  })
})

// ------------------------------------------------------------------ 胶水：控制器 → 弹层的模型

type Listener = (e: unknown) => void
function fakeEl(): Record<string, unknown> {
  const listeners = new Map<string, Set<Listener>>()
  const el: Record<string, unknown> = {
    style: Object.assign(Object.create(null) as Record<string, unknown>, { setProperty() { /* 无 */ } }),
    dataset: {}, className: '', children: [] as unknown[], width: 0, height: 0,
    setAttribute(k: string, v: string) { el[`attr:${k}`] = v },
    getAttribute(k: string) { return el[`attr:${k}`] ?? null },
    appendChild(c: unknown) { (el.children as unknown[]).push(c); return c },
    insertBefore(c: unknown) { (el.children as unknown[]).push(c); return c },
    replaceChildren(...cs: unknown[]) { el.children = cs },
    remove() { /* 无 */ },
    addEventListener(type: string, fn: Listener) { if (!listeners.has(type)) listeners.set(type, new Set()); listeners.get(type)!.add(fn) },
    removeEventListener(type: string, fn: Listener) { listeners.get(type)?.delete(fn) },
    setPointerCapture() { /* 无 */ }, releasePointerCapture() { /* 无 */ },
    getBoundingClientRect: () => ({ left: 0, top: 0, width: 393, height: 560, right: 393, bottom: 560, x: 0, y: 0 }),
    getContext: () => null,
  }
  return el
}

beforeAll(() => {
  const g = globalThis as Record<string, unknown>
  if (!g.document) g.document = { createElement: () => fakeEl() }
  if (!g.window) g.window = { devicePixelRatio: 2 }
  if (!g.ResizeObserver) g.ResizeObserver = class { observe() { /* 无 */ } unobserve() { /* 无 */ } disconnect() { /* 无 */ } }
  if (!g.requestAnimationFrame) g.requestAnimationFrame = () => 1
  if (!g.cancelAnimationFrame) g.cancelAnimationFrame = () => { /* 无 */ }
})

const STEP = INTERVAL_STEP['15m']
const T0 = 1_760_000_400_000 - (1_760_000_400_000 % STEP) - 299 * STEP // 300 根，最后一根从 lastT 起
const LAST = T0 + 299 * STEP
const NOW = LAST + 5 * 60_000

/** 替身弹层：只记模型与调用 */
class FakeSheet {
  closed = false
  calls: string[] = []
  last: BtModel | null = null
  constructor(public detent: Detent = 'half') {}
  update(m: BtModel): void { this.last = m }
  setDetent(d: Detent): void { this.detent = d }
  noteSignTap(): void { this.calls.push('noteSignTap') }
  flash(t: number): void { this.calls.push(`flash:${t}`) }
  park(): void { this.calls.push('park') }
  unpark(): void { this.calls.push('unpark') }
  close(): void { this.closed = true }
}

interface Rig { c: BigTradeController; sheet: FakeSheet; view: ChartView; port: Record<string, unknown>; emit(type: string, e: unknown): void; clock: { now: number } }
function rig(o: { sym?: string; force?: BtForce; detent?: Detent; land?: boolean; liq?: LiqStore; trades?: boolean } = {}): Rig {
  const sym = o.sym ?? 'BTCUSDT'
  const n = 300
  const op: number[] = [], h: number[] = [], l: number[] = [], cl: number[] = [], v: number[] = []
  for (let k = 0; k < n; k++) { const p = 100 + Math.sin(k / 7); op.push(p); cl.push(p); h.push(p + 1); l.push(p - 1); v.push(1) }
  const series = new BarSeries({ symbol: sym, interval: '15m', t0: T0, step: STEP, open: op, high: h, low: l, close: cl, volume: v })
  const view = new ChartView(fakeEl() as unknown as HTMLElement)
  const state = makeState({ series, symbol: { symbol: sym, base: 'BTC', priceDecimals: 2 }, view: new ViewWindow(series.lastTime + STEP * 3, STEP * 60), overlays: [], subs: [] })
  view.state = state
  const handlers = new Map<string, Listener[]>()
  const chart = { view, get state() { return view.state }, on(type: string, fn: Listener) { handlers.set(type, [...(handlers.get(type) ?? []), fn]) } }
  const clock = { now: NOW }
  const port: Record<string, unknown> = { setSigns: vi.fn(), snapshot: null, step: 0.5, lastTradeMs: NOW - 2000, thresholds: null, defaults: null }
  if (o.trades !== false) {
    const venue = { exchange: 'binance', product: 'usdtPerp', instrument: sym }
    // 按时间先后进：前 4 根那根卖 1.5M；本根买 2 笔 0.9M、卖 1 笔 0.3M
    const put = (t: number, usd: number, buy: boolean) => recordTrade(sym, { usd, trade: { timeMs: t, hitSide: buy ? 'ask' : 'bid', price: 100 }, book: { venue } } as never, 50_000)
    put(LAST - 4 * STEP + 60_000, 1_500_000, false)
    put(LAST + 60_000, 500_000, true); put(LAST + 120_000, 400_000, true); put(LAST + 180_000, 300_000, false)
  }
  const c = new BigTradeController({
    chart: chart as never, symbol: () => sym, port: () => port as never,
    thresholds: () => ({ usdtPerp: 100_000, spot: 50_000 } as never),
    isLand: () => !!o.land, isMacro: () => false, openThreshold: back => { back() },
    now: () => clock.now, liq: o.liq ?? new LiqStore(() => new Promise(() => { /* 不回 */ })), force: o.force ?? null,
  })
  const sheet = new FakeSheet(o.detent ?? 'half')
  ;(c as unknown as { sheet: FakeSheet }).sheet = sheet
  ;(c as unknown as { openedAt: number }).openedAt = NOW - 5000
  ;(c as unknown as { sym: string }).sym = sym
  return { c, sheet, view, port, clock, emit: (type, e) => { for (const fn of handlers.get(type) ?? []) fn(e) } }
}
const model = (r: Rig): BtModel => { r.c.refresh(); return r.sheet.last! }

beforeEach(() => { resetFlows(); vi.stubGlobal('fetch', () => new Promise(() => { /* 不回 */ })); st.bigTradeSigns = true })
afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals() })

describe('大单与爆仓 · 弹层各状态的模型', () => {
  it('半屏：本根卡片（买卖、笔数、近 1 小时 / 今日），不算每根和价位', () => {
    const m = model(rig())
    expect(m.loading).toBe(false); expect(m.stale).toBe(false)
    expect(m.hero).toMatchObject({ title: '本根', live: true, rt: '15 分钟', untracked: false })
    expect(m.hero.bar).toMatchObject({ bb: 900_000, bs: 300_000, bn: 2, sn: 1 })
    expect(m.hero.hour).toMatchObject({ bb: 900_000, bs: 300_000 })
    expect(m.hero.today.bs).toBe(1_800_000)
    expect(m.bars).toEqual([]); expect(m.ladder).toBeNull(); expect(m.sel).toBeNull()
    expect(m.sub).toBe('BTC · 币安 · OKX · Coinbase · Bybit · Hyperliquid 合并')
    expect(m.thr).toBe('永续 100.0K · 现货 50.0K · 步长 0.5')
    expect(m.liq!.state).toBe('loading')
  })

  it('满屏：每根 40 根（标签按北京时间）、价位梯 11 行', () => {
    const m = model(rig({ detent: 'full' }))
    expect(m.bars.length).toBe(40)
    expect(m.bars[39]).toMatchObject({ t: LAST, bb: 900_000, bs: 300_000 })
    expect(m.bars[35].bs).toBe(1_500_000)
    expect(m.bars[39].label).toBe(new Date(LAST + 8 * 3600_000).toISOString().slice(11, 16))
    expect(m.ladder!.length).toBe(11)
    expect(m.ladder!.some(r => r.now)).toBe(true)
  })

  it('骨架：第一次打开、服务端还没回、本机也没数时最多挂 1 秒；强制 loading 一直挂', () => {
    const r = rig({ trades: false })
    ;(r.c as unknown as { openedAt: number }).openedAt = NOW - 200
    expect(model(r).loading).toBe(true)
    r.clock.now = NOW - 200 + SKELETON_MS + 1
    expect(model(r).loading).toBe(false)
    expect(model(r).hero.bar.bb + model(r).hero.bar.bs).toBe(0)
    expect(model(rig({ force: 'loading' })).loading).toBe(true)
  })

  it('现货（Coinbase X-USD）没有爆仓整块；强制 spot 同样', () => {
    expect(model(rig({ sym: 'BTC-USD' })).liq).toBeNull()
    expect(model(rig({ force: 'spot' })).liq).toBeNull()
  })

  it('爆仓：拉到数据给近 1 小时 / 今日 / 24 小时与最大一笔；没数据的品种说暂无；强制空 = 96 格全 0', async () => {
    const mx: LiqRow = [NOW - 10 * 60_000, 800_000, 0, 2, 600_000, 101.234, 0, 0]
    const store = new LiqStore(async () => ({ status: 200, body: { base: 'BTC', tracked: true, rows: [mx, [NOW - 3 * 3600_000, 0, 200_000, 1, 200_000, 99, 1, 1]] } }))
    const r = rig({ liq: store })
    r.c.tick()
    await new Promise(res => setTimeout(res, 0))
    const m = model(r)
    expect(m.liq!.state).toBe('data')
    expect(m.liq!.hour).toMatchObject({ long: 800_000, short: 0 })
    expect(m.liq!.day).toMatchObject({ long: 800_000, short: 200_000 })
    expect(m.liq!.maxPrice).toBe('101.23')
    expect(m.liq!.cells.length).toBe(96)
    const none = new LiqStore(async () => ({ status: 200, body: { base: 'X', tracked: false, rows: [] } }))
    const r2 = rig({ liq: none }); r2.c.tick(); await new Promise(res => setTimeout(res, 0))
    expect(model(r2).liq!.state).toBe('none')
    const e = model(rig({ force: 'liqEmpty' })).liq!
    expect(e.state).toBe('data'); expect(e.cells.every(([a, b]) => a + b === 0)).toBe(true)
    expect(liqCardHTML(e, false)).toContain('今日无爆仓')
  })

  it('停住：20 秒没进成交 → 数字变灰、右上写「数据停于 hh:mm」；断网同样', () => {
    const r = rig()
    r.port.lastTradeMs = NOW - STALE_MS - 1000
    const m = model(r)
    expect(m.stale).toBe(true)
    expect(m.hero.rt).toBe(`数据停于 ${new Date(NOW - STALE_MS - 1000 + 8 * 3600_000).toISOString().slice(11, 16)}`)
    r.port.lastTradeMs = NOW - 5000
    expect(model(r).stale).toBe(false)
    expect(model(rig({ force: 'stale' })).stale).toBe(true)
  })

  it('服务端不跟这只：本根卡片底下提示只算打开以后的成交', () => {
    const r = rig()
    flowOf('BTCUSDT').srv.tracked = false
    expect(model(r).hero.untracked).toBe(true)
    expect(model(rig({ force: 'untracked' })).hero.untracked).toBe(true)
  })

  it('分析面板那一行的小字跟着本根', () => {
    expect(rig().c.summaryText()).toBe('本根 净买入 +600.0K')
    resetFlows()
    expect(rig({ trades: false }).c.summaryText()).toBe('本根暂无大单')
  })
})

describe('大单与爆仓 · 十字线联动', () => {
  const TB = LAST - 4 * STEP
  const hhmm = (t: number) => new Date(t + 8 * 3600_000).toISOString().slice(11, 16)

  it('十字线拉到哪根卡片看哪根；抬手 3 秒回到本根', () => {
    vi.useFakeTimers()
    const r = rig()
    r.emit('crosshair', { crosshair: {}, bar: { openTime: TB } })
    let m = r.sheet.last!
    expect(m.hero).toMatchObject({ title: hhmm(TB), live: false, rt: '15 分钟' })
    expect(m.hero.bar.bs).toBe(1_500_000); expect(m.sel).toBe(TB)
    r.emit('interaction', 'ended')
    vi.advanceTimersByTime(RETURN_MS - 10)
    expect(r.sheet.last!.hero.title).toBe(hhmm(TB))
    vi.advanceTimersByTime(20)
    m = r.sheet.last!
    expect(m.hero.title).toBe('本根'); expect(m.sel).toBeNull()
  })

  it('又按下去就不回；十字线拉回本根那根也算本根', () => {
    vi.useFakeTimers()
    const r = rig()
    r.emit('crosshair', { bar: { openTime: TB } })
    r.emit('interaction', 'ended')
    vi.advanceTimersByTime(1000)
    r.emit('crosshair', { bar: { openTime: TB - STEP } })
    vi.advanceTimersByTime(RETURN_MS)
    expect(r.sheet.last!.hero.title).toBe(hhmm(TB - STEP))
    r.emit('crosshair', { bar: { openTime: LAST } })
    expect(r.sheet.last!.hero).toMatchObject({ title: '本根', live: true, rt: '15 分钟' })
  })

  it('开着时点另一枚签：只换根、不关，标记这一下不是点外面', () => {
    const r = rig()
    const tap = (r.c as unknown as { tapSign(s: { t: number }): boolean }).tapSign.bind(r.c)
    expect(tap({ t: TB })).toBe(true)
    expect(r.sheet.calls).toContain('noteSignTap'); expect(r.sheet.closed).toBe(false)
    expect(r.sheet.last!.hero).toMatchObject({ title: hhmm(TB), rt: '15 分钟' })
  })

  it('横屏只画签不开弹层', () => {
    const r = rig({ land: true })
    ;(r.c as unknown as { sheet: null }).sheet = null
    const tap = (r.c as unknown as { tapSign(s: { t: number }): boolean }).tapSign.bind(r.c)
    expect(tap({ t: TB })).toBe(false)
    r.c.open()
    expect(r.c.isOpen).toBe(false)
  })

  it('「每根」点一根：十字线跳过去、那根闪；跟着来的十字线事件不把它当成人拉', () => {
    vi.useFakeTimers()
    const r = rig({ detent: 'full' })
    const spy = vi.spyOn(r.view, 'crosshairTo')
    ;(r.c as unknown as { pickBar(t: number): void }).pickBar(TB)
    expect(spy).toHaveBeenCalledWith(295)
    expect(r.sheet.calls).toContain(`flash:${TB}`)
    r.emit('crosshair', { bar: { openTime: TB } })
    r.emit('interaction', 'ended')
    vi.advanceTimersByTime(RETURN_MS + 100)
    const m = r.sheet.last!
    expect(m.sel).toBe(TB); expect(m.hero.rt).toBe('15 分钟')
  })

  it('门槛：弹层先收下去，门槛页关了再升回来', () => {
    const r = rig()
    ;(r.c as unknown as { threshold(): void }).threshold()
    expect(r.sheet.calls).toEqual(['park', 'unpark'])
  })
})
