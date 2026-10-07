// 网页版足迹图与秒线补历史（2026-10-07）：分桶、步长倍数、合并周期、实时 / 历史按覆盖切换、历史拼接、翻页上限、空回包与失败冷却。
// 服务端用替换掉的 fetch 假扮（按路径回 404 / 空 / 5xx / 数据），不动线上。
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

const liveSecs: { bars: import('../src/chart/calc').Bar[] } = { bars: [] }
vi.mock('../src/chart/intervals', async orig => ({
  ...(await orig<typeof import('../src/chart/intervals')>()),
  secondBars: vi.fn(() => liveSecs.bars.map(b => ({ ...b }))),
}))

const fp = await import('../src/chart/footprint')
const api = await import('../src/market/footprintApi')
const sh = await import('../src/chart/secondsHistory')
const { flowOf, resetFlows } = await import('../src/chart/tradeFlow')
const { TVChart } = await import('../src/chart/chart')
type Bar = import('../src/chart/calc').Bar
type TradeEvent = import('../src/orderflow/feed').TradeEvent
type FootRow = import('../src/market/footprintApi').FootRow

const MIN = 60_000, H = 3_600_000

// ------------------------------------------------------------ 假服务端
interface Hit { path: string; q: URLSearchParams }
const hits: Hit[] = []
const route: { foot: (q: URLSearchParams) => [number, string]; secs: (q: URLSearchParams) => [number, string] } = {
  foot: () => [404, ''], secs: () => [404, ''],
}
const base = 'http://fake.test'
beforeAll(() => {
  vi.stubGlobal('fetch', async (input: string) => {
    const u = new URL(input)
    hits.push({ path: u.pathname, q: u.searchParams })
    await new Promise(r => setTimeout(r, 1))
    const [code, body] = u.pathname === '/v1/market/orderflow/footprint' ? route.foot(u.searchParams)
      : u.pathname === '/v1/market/klines/seconds' ? route.secs(u.searchParams) : [404, '']
    return new Response(code === 204 ? null : body, { status: code, headers: { 'content-type': 'application/json' } })
  })
  fp.setFootprintApiBase(base)
})
afterAll(() => { vi.unstubAllGlobals() })
beforeEach(() => { hits.length = 0; fp.resetFootprint(); resetFlows(); sh.resetSecondsHistory(); liveSecs.bars = [] })

const trade = (price: number, usd: number, buy: boolean, t: number): TradeEvent =>
  ({ book: { venue: { exchange: 'binance', product: 'usdtPerp', instrument: 'BTCUSDT' } }, trade: { price, quantity: usd / price, hitSide: buy ? 'ask' : 'bid', timeMs: t }, usd } as unknown as TradeEvent)
const ready = (sym: string) => new Promise<void>(res => { const off = fp.onFootprintReady(s => { if (s === sym) { off(); res() } }) })
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms))

// ------------------------------------------------------------ 步长与倍数
describe('足迹：步长与画的倍数', () => {
  it('没有服务端步长时和服务端同一规则：价格 × 0.0002 取最近的 1/2/5×10ⁿ', () => {
    expect(fp.fallbackStep(60_000)).toBe(10)
    expect(fp.fallbackStep(3_000)).toBe(0.5)
    expect(fp.fallbackStep(0.25)).toBe(0.00005)
    expect(fp.nearestNice(0.0013)).toBe(0.001)
    expect(fp.nearestNice(37)).toBe(50)
  })
  it('倍数让中位高低差落在 10–30 格；上一帧的还在区间里就不换；格子不到 2 像素就放粗', () => {
    const k = fp.pickMultiple(300, 1)
    expect(300 / k).toBeGreaterThanOrEqual(10); expect(300 / k).toBeLessThanOrEqual(30)
    expect(fp.pickMultiple(300, 1, 10)).toBe(10) // 30 格，留着
    expect(fp.pickMultiple(300, 1, 50)).toBe(k) // 6 格，换
    expect(fp.pickMultiple(300, 1, 0, 0.05)).toBe(50) // 20×0.05=1px 太矮 → 50
    expect(fp.pickMultiple(5, 10)).toBe(1) // 一根很短：最少 1 倍
    expect(fp.pickMultiple(0, 10, 7)).toBe(7)
  })
})

// ------------------------------------------------------------ 分桶与合并周期
describe('足迹：分桶与合并周期', () => {
  it('分钟行按粗桶并、按周期起点并到 5 分钟；控制点是买卖合计最大的一格', () => {
    const t0 = 1_700_000_100_000 - (1_700_000_100_000 % (5 * MIN))
    const minutes = [0, 1, 2, 3, 4, 5].map(k => ({ t: t0 + k * MIN, rows: [[100, 1, 2], [110, 3, 0], [120, 0, 5]] as FootRow[] }))
    const m = fp.mergeMinutes(minutes, 5 * MIN, 20)
    expect([...m.keys()]).toEqual([t0, t0 + 5 * MIN])
    const g = m.get(t0)!
    expect([...g.px]).toEqual([100, 120]) // 100、110 并进 [100,120)，120 自己一格
    expect([...g.buy]).toEqual([20, 0]); expect([...g.sell]).toEqual([10, 25])
    expect(g.tb).toBe(20); expect(g.ts).toBe(35); expect(g.poc).toBe(0); expect(g.max).toBe(25)
    expect(m.get(t0 + 5 * MIN)!.tb).toBe(4)
  })
  it('小数步长分桶不因浮点误差错格', () => {
    const a = new Map<number, [number, number]>()
    fp.bucketRows(a, [[0.3, 1, 0], [0.6, 1, 0], [0.9, 1, 0]], 0.3)
    const g = fp.finishAgg(a, 0.3)!
    expect([...g.px]).toEqual([0.3, 0.6, 0.9])
    expect(fp.finishAgg(new Map(), 1)).toBeNull()
  })
})

// ------------------------------------------------------------ 历史：解析、取数、空回包
describe('足迹：服务端历史', () => {
  it('解析：坏行丢掉、同价并起来、分钟取整、升序', () => {
    const p = api.parseFootprint({ symbol: 'X', step: 10, minutes: [
      { t: 120_005, rows: [[20, 1, 1], [10, 2, 0], [10, 1, 3], ['x', 1, 1], [30, -1, 0]] },
      { t: 60_000, rows: [] }, { bad: 1 },
    ] })!
    expect(p.step).toBe(10)
    expect(p.minutes.map(m => m.t)).toEqual([60_000, 120_000])
    expect(p.minutes[1].rows).toEqual([[10, 3, 3], [20, 1, 1]])
    expect(api.parseFootprint({ minutes: 'x' })).toBeNull()
    expect(api.parseFootprint(null)).toBeNull()
  })
  it('404、空回包、没跟踪（空 minutes）都是「没有历史」不算失败；5xx 才算失败', async () => {
    route.foot = () => [404, '']
    expect(await api.fetchFootprint('A', 0, MIN, base)).toEqual({ ok: true, data: { step: null, minutes: [] } })
    route.foot = () => [200, '']
    expect((await api.fetchFootprint('A', 0, MIN, base)).ok).toBe(true)
    route.foot = () => [200, JSON.stringify({ symbol: 'A', step: null, minutes: [] })]
    expect(await api.fetchFootprint('A', 0, MIN, base)).toEqual({ ok: true, data: { step: null, minutes: [] } })
    route.foot = () => [502, 'x']
    expect((await api.fetchFootprint('A', 0, MIN, base)).ok).toBe(false)
  })
  it('按 24 小时一窗从右往左要；拿到步长；空回包记成空、不进失败冷却', async () => {
    const now = Date.now(), t1 = Math.floor(now / MIN) * MIN - 5 * MIN, t0 = t1 - 50 * H
    route.foot = q => [200, JSON.stringify({ symbol: 'BTCUSDT', step: 10, minutes: [{ t: +q.get('to')! - MIN, rows: [[60_000, 5, 1]] }] })]
    const done = ready('BTCUSDT')
    fp.requestHistory('BTCUSDT', t0, t1, now)
    await done
    const reqs = hits.filter(h => h.path.endsWith('/footprint'))
    expect(reqs.length).toBe(3)
    expect(reqs.map(h => +h.q.get('to')!)).toEqual([t1, t1 - 24 * H, t1 - 48 * H])
    for (const h of reqs) expect(+h.q.get('to')! - +h.q.get('from')!).toBeLessThanOrEqual(24 * H)
    expect(+reqs[2].q.get('from')!).toBe(t0)
    expect(fp.historyOf('BTCUSDT')).toMatchObject({ from: t0, to: t1, minutes: 3, empty: false })
    expect(fp.stepOf('BTCUSDT', 60_000)).toBe(10)
    // 已盖住的范围不再去要
    hits.length = 0
    fp.requestHistory('BTCUSDT', t0 + H, t1, now); await sleep(300)
    expect(hits.length).toBe(0)

    route.foot = () => [404, '']
    const d2 = ready('ETHUSDT')
    fp.requestHistory('ETHUSDT', t1 - H, t1, now); await d2
    expect(fp.historyOf('ETHUSDT')).toMatchObject({ minutes: 0, empty: true })
  })
  it('只追历史的左边、往左扩；不超过 3 天', async () => {
    const now = Date.now(), t1 = Math.floor(now / MIN) * MIN - 5 * MIN
    route.foot = () => [200, JSON.stringify({ step: 10, minutes: [] })]
    let d = ready('SOLUSDT'); fp.requestHistory('SOLUSDT', t1 - H, t1, now); await d
    hits.length = 0
    d = ready('SOLUSDT'); fp.requestHistory('SOLUSDT', t1 - 5 * 86_400_000, t1, now); await d
    const reqs = hits.filter(h => h.path.endsWith('/footprint'))
    const lo = Math.min(...reqs.map(h => +h.q.get('from')!))
    expect(lo).toBeGreaterThanOrEqual(now - 3 * 86_400_000 - MIN)
    expect(reqs.every(h => +h.q.get('to')! <= t1 - H + 1)).toBe(true) // 右边已有的不重要
  })
  it('要失败了 30 秒内不再去要', async () => {
    const now = Date.now(), t1 = Math.floor(now / MIN) * MIN - 5 * MIN
    route.foot = () => [500, 'boom']
    fp.requestHistory('XRPUSDT', t1 - H, t1, now); await sleep(400)
    expect(hits.length).toBe(1)
    fp.requestHistory('XRPUSDT', t1 - 2 * H, t1, now); await sleep(400)
    expect(hits.length).toBe(1)
    expect(fp.historyOf('XRPUSDT')?.minutes).toBe(0)
  })
})

// ------------------------------------------------------------ 实时与历史按覆盖切换
describe('足迹：每一分钟在覆盖区间里用实时的，否则用服务端的', () => {
  it('覆盖判定与累计量差同一口径（tradeFlow.covered）；服务端步长不同时实时的桶按新步长重分', async () => {
    const now = Date.now(), m0 = Math.floor(now / MIN) * MIN - 10 * MIN, m1 = m0 + MIN, m2 = m0 + 2 * MIN
    // 实时：m0、m1 各有几笔（按价格现算的步长 10 分桶）
    for (const t of [m0, m1]) { fp.recordFootprintTrade('BTCUSDT', trade(60_005, 100, true, t + 1000), now); fp.recordFootprintTrade('BTCUSDT', trade(60_015, 40, false, t + 2000), now) }
    expect(fp.stepOf('BTCUSDT', 60_000)).toBe(10)
    // 历史：步长 20，三分钟都有
    route.foot = () => [200, JSON.stringify({ symbol: 'BTCUSDT', step: 20, minutes: [m0, m1, m2].map(t => ({ t, rows: [[60_000, 7, 3], [60_020, 1, 1]] })) })]
    const d = ready('BTCUSDT'); fp.requestHistory('BTCUSDT', m0, m2 + MIN, now); await d
    expect(fp.stepOf('BTCUSDT', 60_000)).toBe(20)
    // 只有 m1 整分钟在覆盖里
    flowOf('BTCUSDT').cover = [[m1 - 500, m1 + MIN + 500]]
    const g0 = fp.barFootprint('BTCUSDT', m0, m0 + MIN, 20, now)!
    expect(g0.tb).toBe(8); expect(g0.ts).toBe(4) // 历史
    const g1 = fp.barFootprint('BTCUSDT', m1, m1 + MIN, 20, now)!
    expect(g1.tb).toBe(100); expect(g1.ts).toBe(40) // 实时（重分到 20 的桶：60005、60015 都在 [60000,60020)）
    expect([...g1.px]).toEqual([60_000])
    // 3 分钟这根：m0 历史 + m1 实时 + m2 历史
    const g = fp.barFootprint('BTCUSDT', m0, m0 + 3 * MIN, 20, now)!
    expect(g.tb).toBe(8 + 100 + 8); expect(g.ts).toBe(4 + 40 + 4)
    // 覆盖断了：全用历史
    flowOf('BTCUSDT').cover = []
    expect(fp.barFootprint('BTCUSDT', m1, m1 + MIN, 20, now)!.tb).toBe(8)
    expect(fp.barFootprint('NONE', m1, m1 + MIN, 20, now)).toBeNull()
  })
})

// ------------------------------------------------------------ 画
type Any = Record<string, unknown>
function recCtx() {
  const calls: [string, unknown[]][] = []
  const ctx = new Proxy({} as Any, {
    get(o, k: string) { if (k in o) return o[k]; if (k === 'measureText') return () => ({ width: 40 }); return (...a: unknown[]) => { calls.push([k, a]) } },
    set(o, k: string, v) { o[k] = v; return true },
  })
  return { ctx, calls }
}
describe('足迹：画法', () => {
  function chart(spacing: number, iv = MIN) {
    const { ctx, calls } = recCtx()
    const now = Date.now(), t0 = Math.floor(now / MIN) * MIN - 40 * MIN
    const bars: Bar[] = Array.from({ length: 30 }, (_, k) => ({ t: t0 + k * iv, o: 60_000, h: 60_200, l: 59_800, c: k % 2 ? 60_100 : 59_900, v: 1 }))
    const pane = { id: 'main' as const, y: 0, h: 1200 }, r = { min: 59_700, max: 60_300 }
    const c = Object.assign(Object.create(TVChart.prototype), {
      ctx, colors: { up: '#0a0', down: '#a00' }, w: 2000, aw: 60, rightBar: 29, spacing, bars, iv, log: false, font: '12px x',
      meta: { symbol: 'BTCUSDT', dec: 1 }, _panes: [pane], mainRange: r, dead: false, dirty: false, legendDirty: false, zoom() {},
    }) as InstanceType<typeof TVChart>
    return { c, calls, pane, r, bars }
  }
  it('够宽：画横条、写数字、描控制点；没数据的那几根照旧画蜡烛；关了 / 秒级 / 太窄都交回蜡烛', async () => {
    const { c, calls, pane, r, bars } = chart(60)
    route.foot = () => [200, JSON.stringify({ step: 10, minutes: bars.slice(5).map(b => ({ t: b.t, rows: Array.from({ length: 40 }, (_, j) => [59_800 + j * 10, 1000 + j * 100, 2000]) })) })]
    fp.bindFootprint(c, 0)
    expect(c.footprint!(pane, r, 0, 29)).toBe(false) // 没开
    fp.setFootprint(0, true)
    const d = ready('BTCUSDT')
    expect(c.footprint!(pane, r, 0, 29)).toBe(false) // 历史还没到：照旧蜡烛
    await d
    expect(c.dirty).toBe(true)
    const spy = vi.spyOn(c, 'drawCandles').mockImplementation(() => {})
    calls.length = 0
    expect(c.footprint!(pane, r, 0, 29)).toBe(true)
    expect(spy).toHaveBeenCalledWith(pane, r, 0, 4) // 前 5 根没有逐价数据
    expect(calls.some(([k]) => k === 'fillText')).toBe(true)
    const st = (globalThis as unknown as { __footprint: (i: number) => Any }).__footprint(0)
    expect(st).toMatchObject({ on: true, mode: 'num', drawn: 25 })
    // 格高：400 价差 / 1184 px，按 10–30 格的倍数 → 每格够高写数字
    expect((st.d as number) % 10).toBe(0)
    // 图例：买 / 卖 / 净 / 控制点
    const row = c.legendExtra!(10)
    expect(row).toContain('买 '); expect(row).toContain('卖 '); expect(row).toContain('净 '); expect(row).toContain('控制点')
    expect(c.legendExtra!(2)).toContain('这根没有逐价成交')
    // 太窄
    c.spacing = 4
    expect(c.footprint!(pane, r, 0, 29)).toBe(false)
    // 关掉
    c.spacing = 60; fp.setFootprint(0, false)
    expect(c.footprint!(pane, r, 0, 29)).toBe(false)
    expect(c.legendExtra!(10)).toBe('')
  })
  it('格子太矮只画横条不写数字', async () => {
    const { c, calls, pane, bars } = chart(60)
    const r = { min: 50_000, max: 70_000 } // 纵向压得很扁
    route.foot = () => [200, JSON.stringify({ step: 10, minutes: bars.map(b => ({ t: b.t, rows: [[59_900, 5, 5], [60_000, 5, 5], [60_100, 9, 1]] })) })]
    fp.bindFootprint(c, 1); fp.setFootprint(1, true)
    const d = ready('BTCUSDT'); c.footprint!(pane, r, 0, 29); await d
    calls.length = 0
    expect(c.footprint!(pane, r, 0, 29)).toBe(true)
    expect(calls.some(([k]) => k === 'fillText')).toBe(false)
    expect(((globalThis as unknown as { __footprint: (i: number) => Any }).__footprint(1)).mode).toBe('bar')
  })
  it('秒级周期：菜单置灰、不画', () => {
    const it = fp.footprintMenuItem(0, '1s') as Any
    expect(it.disabled).toBe(true)
    expect(String(it.html)).toContain('秒级周期不支持')
    const { c, pane, r } = chart(60, 1000)
    fp.bindFootprint(c, 2); fp.setFootprint(2, true)
    expect(c.footprint!(pane, r, 0, 29)).toBe(false)
    expect(fp.footprintWanted()).toBe(false)
  })
})

// ------------------------------------------------------------ 秒线历史
describe('秒线：服务端历史', () => {
  const T = 1_800_000_000_000
  it('解析：vol / buyVol 当基础币量折成报价币额；坏行丢掉；同一秒留后一行；升序', () => {
    const b = sh.parseSeconds({ symbol: 'X', bars: [[T + 1000, 10, 12, 9, 11, 2, 1.5], [T, 10, 10, 10, 10, 1], [T + 1000, 10, 13, 9, 12, 3, 9], ['x'], [T + 2000, 0, 1, 1, 1, 1, 0]] })!
    expect(b.map(x => x.t)).toEqual([T, T + 1000])
    expect(b[1]).toMatchObject({ o: 10, h: 13, l: 9, c: 12, bv: 3 })
    expect(b[1].v).toBeCloseTo(3 * (13 + 9 + 12) / 3)
    expect(b[1].tb).toBeCloseTo(3 * (13 + 9 + 12) / 3) // 主动买不超过总量
    expect(b[0].tb).toBeUndefined()
    expect(sh.parseSeconds({ nope: 1 })).toBeNull()
  })
  it('没成交的秒补平；拼接时同一秒以逐笔攒的为准', () => {
    const h: Bar[] = [{ t: T, o: 1, h: 2, l: 1, c: 2, v: 1 }, { t: T + 3000, o: 3, h: 3, l: 3, c: 3, v: 1 }]
    const f = sh.fillGaps(h, T + 6000)
    expect(f.map(x => x.t)).toEqual([0, 1, 2, 3, 4, 5].map(k => T + k * 1000))
    expect(f[1]).toMatchObject({ o: 2, h: 2, l: 2, c: 2, v: 0 })
    expect(f[5].c).toBe(3)
    const live: Bar[] = [{ t: T + 3000, o: 9, h: 9, l: 9, c: 9, v: 5 }, { t: T + 4000, o: 9, h: 9, l: 9, c: 9, v: 5 }]
    const s = sh.spliceSeconds(h, live)
    expect(s.map(x => [x.t, x.c])).toEqual([[T, 2], [T + 3000, 9], [T + 4000, 9]])
    expect(sh.spliceSeconds([], live)).toBe(live)
  })
  it('打开秒级周期：要最近 6 小时，和逐笔攒的拼起来；5 秒从 1 秒并', async () => {
    const now = T + 10 * H
    route.secs = q => {
      const from = +q.get('from')!, to = +q.get('to')!
      return [200, JSON.stringify({ symbol: 'BTCUSDT', bars: [[to - 20_000, 1, 1, 1, 1, 1, 0], [to - 11_000, 2, 2, 2, 2, 1, 1], [from - 1000, 5, 5, 5, 5, 5, 5]] })]
    }
    liveSecs.bars = [{ t: now - 11_000 + 1000, o: 7, h: 7, l: 7, c: 7, v: 3 }]
    const r = await sh.secondsKlines('BTCUSDT', '1s', undefined, undefined, base, now)
    const q = hits[0].q
    expect(+q.get('to')! - +q.get('from')!).toBeLessThanOrEqual(6 * H + 1000)
    expect(r.ok).toBe(true)
    expect(r.bars[0].t).toBe(now + 1000 - 20_000) // 窗外那一行被丢
    expect(r.bars[r.bars.length - 1].c).toBe(7) // 逐笔的赢
    for (let k = 1; k < r.bars.length; k++) expect(r.bars[k].t - r.bars[k - 1].t).toBe(1000) // 中间补平
    expect(r.bars[r.bars.length - 1].t).toBe(now - 1000) // 历史 / 逐笔末尾到现在也补平，不留缺口
    const r5 = await sh.secondsKlines('BTCUSDT', '5s', undefined, undefined, base, now)
    expect(r5.bars.every(b => b.t % 5000 === 0)).toBe(true)
    // 没有历史（404）：照旧只有逐笔的
    route.secs = () => [404, '']
    expect((await sh.secondsKlines('BTCUSDT', '1s', undefined, undefined, base, now)).bars).toEqual(liveSecs.bars)
  })
  it('往左翻：一页 6 小时、补到这页右沿；到 3 天上限或回空就停', async () => {
    const now = T + 100 * H, end = now - 2 * H
    route.secs = q => [200, JSON.stringify({ bars: [[+q.get('from')! + 5000, 1, 1, 1, 1, 1, 0]] })]
    const r = await sh.secondsKlines('BTCUSDT', '15s', end, undefined, base, now)
    expect(+hits[0].q.get('to')!).toBe(end)
    expect(end - +hits[0].q.get('from')!).toBe(6 * H)
    expect(r.ok).toBe(true)
    expect(r.bars[r.bars.length - 1].t).toBeLessThan(end)
    expect(r.bars.every(b => b.t % 15_000 === 0)).toBe(true)
    // 快到 3 天：from 卡在下限
    hits.length = 0
    const nearFloor = now - 3 * 86_400_000 + H
    await sh.secondsKlines('BTCUSDT', '1s', nearFloor, undefined, base, now)
    expect(+hits[0].q.get('from')!).toBeGreaterThanOrEqual(now - 3 * 86_400_000 - 1000)
    // 过了 3 天：不再去要，回空（页面据此记「到头了」）
    hits.length = 0
    expect(await sh.secondsKlines('BTCUSDT', '1s', now - 3 * 86_400_000 - 1000, undefined, base, now)).toEqual({ bars: [], ok: true })
    expect(hits.length).toBe(0)
    // 回空：ok 且空
    route.secs = () => [200, JSON.stringify({ symbol: 'BTCUSDT', bars: [] })]
    expect(await sh.secondsKlines('BTCUSDT', '1s', end, undefined, base, now)).toEqual({ bars: [], ok: true })
  })
  it('失败（5xx）：这一页 ok=false，30 秒内不再去要；作废的请求不回数据', async () => {
    const now = Date.now()
    route.secs = () => [503, '']
    const r = await sh.secondsKlines('ETHUSDT', '1s', now - H, undefined, base, now)
    expect(r.ok).toBe(false)
    hits.length = 0
    expect((await sh.secondsKlines('ETHUSDT', '1s', now - 2 * H, undefined, base, now)).ok).toBe(false)
    expect(hits.length).toBe(0)
    // 不带 endTime 时冷却期内也不去要，照旧给逐笔的
    liveSecs.bars = [{ t: now - 1000, o: 1, h: 1, l: 1, c: 1, v: 1 }]
    const r2 = await sh.secondsKlines('ETHUSDT', '1s', undefined, undefined, base, now)
    expect(r2).toMatchObject({ ok: true, bars: liveSecs.bars })
    expect(hits.length).toBe(0)
    sh.resetSecondsHistory()
    route.secs = () => [200, JSON.stringify({ bars: [[now - H - 5000, 1, 1, 1, 1, 1]] })]
    expect((await sh.secondsKlines('ETHUSDT', '1s', now - H, () => false, base, now)).bars).toEqual([])
  })
})
