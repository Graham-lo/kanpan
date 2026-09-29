// 对比行情（compare.source.ts）与盘口（depth.source.ts）两个数据源、以及百分比价格轴的回归用例。
// 对照 iOS：KanpanData/Feed/CompareFeed.swift、Kanpan/Compare/CompareModel.swift、
// MarketFeed 的 depth5 流、ChartRenderer.swift:553 的百分比刻度写法。
import { describe, expect, it } from 'vitest'
import { COMPARE_MAX_PAGES, CompareFeed, alignCompare, compareSymbolOf, compareTargets } from '../src/m/chart/compare.source'
import type { CompareLoad } from '../src/m/chart/compare.source'
import { DepthFeed, depthURL, parseDepthFrame } from '../src/m/chart/depth.source'
import type { DepthSocket } from '../src/m/chart/depth.source'
import { BarSeries, INTERVAL_STEP, bar } from '../src/m/chart/series'
import type { Bar, Interval } from '../src/m/chart/series'
import type { OrderBook } from '../src/m/chart/state'
import { comparePercentLabel, effectivePriceMode, makeState, withInput } from '../src/m/chart/state'
import { Layout, ViewMath, AICoinBehavior, defaultChartOptions, priceTransform } from '../src/m/chart/geometry'
import { ChartRenderer } from '../src/m/chart/renderer'
import { compareLegend } from '../src/m/chart/renderer.compare'

const H = INTERVAL_STEP['1h']
const T0 = 1_700_000_000_000

const mk = (t: number, c: number): Bar => bar(t, c, c * 1.01, c * 0.99, c, 10)
function barsAt(from: number, n: number, base = 100): Bar[] {
  return Array.from({ length: n }, (_, k) => mk(from + k * H, base + k))
}
const series = (sym: string, bars: Bar[], iv: Interval = '1h') => BarSeries.fromBars(sym, iv, bars)

/** 手动拨的计时器：set 记下来，run() 把到期的一个个跑掉。 */
class Clock {
  now = 0
  jobs: { id: number; at: number; fn: () => void }[] = []
  private seq = 0
  timers = {
    set: ((fn: () => void, ms: number) => { const id = ++this.seq; this.jobs.push({ id, at: this.now + ms, fn }); return id }) as unknown as typeof setTimeout,
    clear: ((id: number) => { this.jobs = this.jobs.filter(j => j.id !== id) }) as unknown as typeof clearTimeout,
  }
  advance(ms: number): void {
    this.now += ms
    for (;;) {
      const due = this.jobs.filter(j => j.at <= this.now).sort((a, b) => a.at - b.at)[0]
      if (!due) return
      this.jobs = this.jobs.filter(j => j !== due)
      due.fn()
    }
  }
  delays(): number[] { return this.jobs.map(j => j.at - this.now) }
}

const flush = async () => { for (let i = 0; i < 20; i++) await Promise.resolve() }

/** 一台假的交易所：每只代号一整段根，按 endTime 往左一页一页给（与 loadBars 一样，endTime 那根不含）。 */
function exchange(data: Record<string, Bar[]>, page = 100) {
  const calls: { symbol: string; end: number | null }[] = []
  let fail = 0
  const load: CompareLoad = async (symbol, _iv, end) => {
    calls.push({ symbol, end })
    if (fail > 0) { fail--; return null }
    const all = data[symbol] ?? []
    const upto = end == null ? all.length : all.findIndex(b => b.openTime >= end)
    const hi = upto < 0 ? all.length : upto
    return all.slice(Math.max(0, hi - page), hi)
  }
  return { load, calls, failNext: (n: number) => { fail = n } }
}

// ------------------------------------------------------------------ 键与对齐

describe('对比 · 键、目标与对齐', () => {
  it('只认币安合约键与裸代号；别家、别的市场、写坏的键一律不取', () => {
    expect(compareSymbolOf('binance/usd_m/ethusdt')).toBe('ETHUSDT')
    expect(compareSymbolOf('SOLUSDT')).toBe('SOLUSDT')
    expect(compareSymbolOf('coinbase/spot/BTC-USD')).toBeNull()
    expect(compareSymbolOf('binance/spot/ETHUSDT')).toBeNull()
    expect(compareSymbolOf('binance/usd_m/')).toBeNull()
    expect(compareSymbolOf('a/b')).toBeNull()
    expect(compareSymbolOf('<img>')).toBeNull()
  })

  it('去重、去掉主图那只、最多三只，顺序照偏好', () => {
    const t = compareTargets(['binance/usd_m/BTCUSDT', 'binance/usd_m/ETHUSDT', 'ETHUSDT', 'coinbase/spot/X', 'SOLUSDT', 'BNBUSDT', 'XRPUSDT'], 'btcusdt')
    expect(t.map(x => x.symbol)).toEqual(['ETHUSDT', 'SOLUSDT', 'BNBUSDT'])
    expect(t[0].key).toBe('binance/usd_m/ETHUSDT')
  })

  it('按主序列 openTime 一根根对：缺根是 null，不拿邻根补；非法价是 null；周期不同全空', () => {
    const main = series('BTCUSDT', barsAt(T0, 6))
    const other = series('ETHUSDT', [mk(T0 + H, 50), mk(T0 + 2 * H, 51), mk(T0 + 4 * H, NaN), mk(T0 + 5 * H, 53)])
    const a = alignCompare(main, other)
    expect(a.close).toEqual([null, 50, 51, null, null, 53])
    expect(a.open).toEqual([null, 50, 51, null, null, 53])
    const wrongIv = series('ETHUSDT', barsAt(T0, 6), '4h')
    expect(alignCompare(main, wrongIv).close.every(x => x === null)).toBe(true)
    expect(alignCompare(main, null).close).toHaveLength(6)
  })
})

// ------------------------------------------------------------------ CompareFeed

describe('对比 · CompareFeed 取数', () => {
  it('先取最新一页，再往左补到主序列起点；补到头就停', async () => {
    const clock = new Clock()
    const ex = exchange({ ETHUSDT: barsAt(T0 - 250 * H, 300, 50) }, 100)
    let changes = 0
    const f = new CompareFeed(ex.load, () => { changes++ }, clock.timers)
    const main = series('BTCUSDT', barsAt(T0 - 220 * H, 270))
    f.configure(['binance/usd_m/ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    expect(ex.calls[0]).toEqual({ symbol: 'ETHUSDT', end: null })
    const out = f.series(main, () => '#ff0000', k => k)
    expect(out).toHaveLength(1)
    const s = (f as unknown as { entries: { series: BarSeries }[] }).entries[0].series
    expect(s.firstTime, '补到了主序列起点之前').toBeLessThanOrEqual(main.firstTime)
    expect(ex.calls.length).toBeLessThanOrEqual(1 + COMPARE_MAX_PAGES)
    const c = out[0].close
    expect(c[0]).not.toBeNull()
    expect(c[c.length - 1], '末根对上 ETH 同一时刻那根').toBe(50 + 299)
    expect(changes).toBeGreaterThan(1)
  })

  it('交易所那边早就没有更早的：翻到空页就记下到头，不再往左要', async () => {
    const clock = new Clock()
    const ex = exchange({ ETHUSDT: barsAt(T0, 50, 50) }, 100)
    const f = new CompareFeed(ex.load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0 - 100 * H, 150))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    const n = ex.calls.length
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    expect(ex.calls.length, '到头之后同一组键再配置不再请求').toBe(n)
    expect(f.series(main, () => '#fff', k => k)[0].close.slice(0, 100).every(x => x === null)).toBe(true)
  })

  it('取不到按 2 s·2ⁿ 退避、最长 30 s；取到后清零', async () => {
    const clock = new Clock()
    const ex = exchange({ ETHUSDT: barsAt(T0, 20, 50) })
    ex.failNext(6)
    const f = new CompareFeed(ex.load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 20))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    const seen: number[] = []
    for (let i = 0; i < 6; i++) {
      await flush()
      seen.push(clock.delays()[0])
      clock.advance(clock.delays()[0])
    }
    await flush()
    expect(seen).toEqual([2000, 4000, 8000, 16000, 30000, 30000])
    expect(f.series(main, () => '#fff', k => k)[0].close[19]).toBe(69)
    expect(clock.jobs).toHaveLength(0)
  })

  it('推送接末根；断了一截就重拉末页，不拿孤根把空白连起来', async () => {
    const clock = new Clock()
    const data = { ETHUSDT: barsAt(T0, 20, 50) }
    const ex = exchange(data)
    let changes = 0
    const f = new CompareFeed(ex.load, () => { changes++ }, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 22))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    const before = changes
    expect(f.upsert('ethusdt', '1h', mk(T0 + 20 * H, 70))).toBe(true)
    expect(changes).toBe(before + 1)
    expect(f.series(main, () => '#fff', k => k)[0].close[20]).toBe(70)
    expect(f.upsert('ETHUSDT', '4h', mk(T0 + 21 * H, 71)), '别的周期不收').toBe(false)
    expect(f.upsert('SOLUSDT', '1h', mk(T0 + 21 * H, 71)), '不是对比品种不收').toBe(false)
    const calls = ex.calls.length
    data.ETHUSDT = barsAt(T0, 24, 50)
    f.upsert('ETHUSDT', '1h', mk(T0 + 23 * H, 99))
    const s = (f as unknown as { entries: { series: BarSeries }[] }).entries[0].series
    expect(ex.calls.length, '跳根触发重拉末页').toBe(calls + 1)
    await flush()
    const s2 = (f as unknown as { entries: { series: BarSeries }[] }).entries[0].series
    expect(s2.count).toBe(24)
    expect(s2.close[21], '中间补的是交易所的真根').toBe(71)
    void s
  })

  it('取最新页的途中推送动了末根：以推送为准，REST 的旧末根不盖回去', async () => {
    const clock = new Clock()
    let release: (b: Bar[]) => void = () => {}
    let first = true
    const load: CompareLoad = (_s, _iv, end) => {
      if (first) { first = false; return Promise.resolve(barsAt(T0, 10, 50)) }
      if (end == null) return new Promise(r => { release = r })
      return Promise.resolve([])
    }
    const f = new CompareFeed(load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 10))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    f.resync()
    f.upsert('ETHUSDT', '1h', mk(T0 + 9 * H, 123))
    release(barsAt(T0, 10, 50))
    await flush()
    expect(f.series(main, () => '#fff', k => k)[0].close[9]).toBe(123)
  })

  it('换周期、换键集合：旧的在途请求作废，不把上一只的根写进来', async () => {
    const clock = new Clock()
    let release: (b: Bar[]) => void = () => {}
    const load: CompareLoad = () => new Promise(r => { release = r })
    const f = new CompareFeed(load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 10))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    const stale = release
    f.configure(['SOLUSDT'], main, 'BTCUSDT', '1h')
    stale(barsAt(T0, 10, 999))
    await flush()
    expect(f.symbols).toEqual(['SOLUSDT'])
    expect(f.series(main, () => '#fff', k => k)[0].close.every(x => x === null)).toBe(true)
  })

  it('主序列不是当前这只（换品种过渡中）不给对比；dispose 之后一切作废', async () => {
    const clock = new Clock()
    const ex = exchange({ ETHUSDT: barsAt(T0, 10, 50) })
    const f = new CompareFeed(ex.load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 10))
    f.configure(['ETHUSDT'], main, 'SOLUSDT', '1h')
    expect(f.symbols).toEqual([])
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    expect(f.series(series('BTCUSDT', barsAt(T0, 10)), () => '#fff', k => k), '别的主序列对象不给').toEqual([])
    f.dispose()
    expect(f.series(main, () => '#fff', k => k)).toEqual([])
    expect(clock.jobs).toHaveLength(0)
  })

  it('对齐有缓存：主序列与对比序列都没动时返回同一份数组', async () => {
    const clock = new Clock()
    const ex = exchange({ ETHUSDT: barsAt(T0, 10, 50) })
    const f = new CompareFeed(ex.load, () => {}, clock.timers)
    const main = series('BTCUSDT', barsAt(T0, 10))
    f.configure(['ETHUSDT'], main, 'BTCUSDT', '1h')
    await flush()
    const a = f.series(main, () => '#fff', k => k)[0].close
    expect(f.series(main, () => '#fff', k => k)[0].close).toBe(a)
    main.upsert(mk(T0 + 10 * H, 1))
    expect(f.series(main, () => '#fff', k => k)[0].close).not.toBe(a)
  })
})

// ------------------------------------------------------------------ 盘口

class FakeSock implements DepthSocket {
  onopen: ((ev: unknown) => void) | null = null
  onmessage: ((ev: { data: unknown }) => void) | null = null
  onclose: ((ev: unknown) => void) | null = null
  onerror: ((ev: unknown) => void) | null = null
  closed = false
  constructor(readonly url: string) {}
  close(): void { this.closed = true }
  send(o: unknown): void { this.onmessage?.({ data: JSON.stringify(o) }) }
}

const frame = (T: number, s = 'BTCUSDT', bid = 100) => ({
  stream: 'btcusdt@depth5@100ms',
  data: { e: 'depthUpdate', s, T, E: T + 5, b: [[String(bid), '1.5'], [String(bid - 1), '2']], a: [[String(bid + 1), '3']] },
})

function depthRig() {
  const clock = new Clock()
  const socks: FakeSock[] = []
  const books: (OrderBook | null)[] = []
  const f = new DepthFeed(b => books.push(b), {
    connect: url => { const s = new FakeSock(url); socks.push(s); return s },
    timers: clock.timers, now: () => clock.now,
  })
  const live = () => socks.filter(s => !s.closed)
  return { clock, socks, books, f, live }
}

describe('盘口 · depth5 数据源', () => {
  it('解析：组合流外壳与裸事件都认；时间取 T、没有退 E；别的品种、别的事件不认', () => {
    const b = parseDepthFrame('btcusdt', frame(1000))!
    expect(b.symbol).toBe('BTCUSDT')
    expect(b.time).toBe(1000)
    expect(b.bids[0]).toEqual({ price: 100, quantity: 1.5 })
    expect(b.asks).toHaveLength(1)
    expect(parseDepthFrame('BTCUSDT', { e: 'depthUpdate', E: 77, b: [], a: [['1', '1']] })!.time).toBe(77)
    expect(parseDepthFrame('ETHUSDT', frame(1000))).toBeNull()
    expect(parseDepthFrame('BTCUSDT', { e: 'kline', b: [] })).toBeNull()
    expect(parseDepthFrame('BTCUSDT', 'x')).toBeNull()
    expect(depthURL('BTCUSDT')).toBe('wss://fstream.binance.com/public/stream?streams=btcusdt@depth5@100ms')
  })

  it('只在直连上连；网关、关着、切后台都不连且交 null', () => {
    const g = depthRig()
    g.f.setWanted(true, 'BTCUSDT', false)
    expect(g.socks).toHaveLength(0)
    g.f.setWanted(true, 'BTCUSDT', true)
    expect(g.live()).toHaveLength(1)
    g.live()[0].send(frame(1))
    expect(g.f.current?.time).toBe(1)
    g.f.setVisible(false)
    expect(g.live()).toHaveLength(0)
    expect(g.f.current).toBeNull()
    g.f.setVisible(true)
    expect(g.live()).toHaveLength(1)
    g.f.setWanted(false, 'BTCUSDT', true)
    expect(g.live()).toHaveLength(0)
    expect(g.books[g.books.length - 1]).toBeNull()
  })

  it('乱序帧不收；换品种立刻清掉旧盘口、旧连接的迟到帧不认', () => {
    const g = depthRig()
    g.f.setWanted(true, 'BTCUSDT', true)
    const s1 = g.live()[0]
    s1.send(frame(10))
    s1.send(frame(5, 'BTCUSDT', 90))
    expect(g.f.current?.time).toBe(10)
    g.f.setWanted(true, 'ETHUSDT', true)
    expect(g.f.current).toBeNull()
    expect(s1.closed).toBe(true)
    s1.onmessage?.({ data: JSON.stringify(frame(20)) })
    expect(g.f.current).toBeNull()
    expect(g.live()[0].url).toContain('ethusdt@depth5')
  })

  it('断线 1 s·2ⁿ 退避、最长 15 s；首帧 8 s 不来、中途静默 10 s 都当断线', () => {
    const g = depthRig()
    g.f.setWanted(true, 'BTCUSDT', true)
    const waits: number[] = []
    for (let i = 0; i < 6; i++) {
      g.live()[0].onclose?.({})
      expect(g.f.current).toBeNull()
      waits.push(g.clock.delays()[0])
      g.clock.advance(g.clock.delays()[0])
    }
    expect(waits).toEqual([1000, 2000, 4000, 8000, 15000, 15000])
    const n = g.socks.length
    g.clock.advance(8000)
    expect(g.socks.length, '8 s 没有首帧：断开重连').toBe(n)
    expect(g.live()).toHaveLength(0)
    g.clock.advance(g.clock.delays()[0])
    g.live()[0].send(frame(1))
    g.clock.advance(9000)
    expect(g.live(), '首帧到了之后按 10 s 静默算，不再按首帧的 8 s 砍').toHaveLength(1)
    g.live()[0].send(frame(2))
    g.clock.advance(9999)
    expect(g.live(), '仍在推就不断').toHaveLength(1)
    g.clock.advance(1)
    expect(g.live()).toHaveLength(0)
    expect(g.f.current).toBeNull()
    expect(g.clock.delays()[0], '收到过帧，断线后从 1 s 起退避').toBe(1000)
  })

  it('默认计时器不脱离 window 调：浏览器里 timers.set(...) 以别的对象为 this 会抛 Illegal invocation', async () => {
    const g = globalThis as unknown as { setTimeout: typeof setTimeout; clearTimeout: typeof clearTimeout }
    const realSet = g.setTimeout, realClear = g.clearTimeout
    function strictSet(this: unknown, fn: () => void, ms?: number) {
      if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation')
      return realSet(fn, ms)
    }
    function strictClear(this: unknown, id?: ReturnType<typeof setTimeout>) {
      if (this !== undefined && this !== globalThis) throw new TypeError('Illegal invocation')
      realClear(id)
    }
    g.setTimeout = strictSet as unknown as typeof setTimeout
    g.clearTimeout = strictClear as unknown as typeof clearTimeout
    try {
      const socks: FakeSock[] = []
      const f = new DepthFeed(() => {}, { connect: url => { const s = new FakeSock(url); socks.push(s); return s } })
      expect(() => f.setWanted(true, 'BTCUSDT', true)).not.toThrow()
      expect(() => socks[0].onclose?.({})).not.toThrow()
      f.dispose()
      const feed = new CompareFeed(async () => null, () => {})
      feed.configure(['ETHUSDT'], series('BTCUSDT', barsAt(T0, 10)), 'BTCUSDT', '1h')
      await flush()
      expect(() => feed.dispose()).not.toThrow()
    } finally {
      g.setTimeout = realSet; g.clearTimeout = realClear
    }
  })

  it('dispose：关连接、清计时器，之后不再连', () => {
    const g = depthRig()
    g.f.setWanted(true, 'BTCUSDT', true)
    g.f.dispose()
    expect(g.live()).toHaveLength(0)
    expect(g.clock.jobs).toHaveLength(0)
    g.f.setWanted(true, 'SOLUSDT', true)
    expect(g.live()).toHaveLength(0)
  })
})

// ------------------------------------------------------------------ 百分比轴与对比叠层

/** 记下所有 fillText 的上下文（其余调用什么都不做）。 */
function recordText(paint: (ctx: CanvasRenderingContext2D) => void): { text: string; x: number; y: number }[] {
  const out: { text: string; x: number; y: number }[] = []
  const t: Record<string | symbol, unknown> = {
    fillText: (text: string, x: number, y: number) => { out.push({ text, x, y }) },
  }
  const ctx = new Proxy(t, {
    get: (o, k) => (k in o ? o[k] : () => ({ width: 10 })),
    set: (o, k, v) => { o[k] = v; return true },
  }) as unknown as CanvasRenderingContext2D
  paint(ctx)
  return out
}

/** 等宽数字是一格一格画的：同一行（y 相同、x 相连）的拼回一串。 */
function joinRuns(ts: { text: string; x: number; y: number }[]): string[] {
  const out: string[] = []
  let y = NaN
  for (const t of ts) { if (t.y === y) out[out.length - 1] += t.text; else { out.push(t.text); y = t.y } }
  return out
}

describe('百分比轴 · 对比叠层', () => {
  const b = series('BTCUSDT', barsAt(T0, 200, 1000))
  const L = new Layout(402, 520, ['VOL'])
  const state = (mode: 'linear' | 'percent') => makeState({
    series: b, symbol: { symbol: 'BTCUSDT', base: 'BTC', priceDecimals: 2 },
    view: ViewMath.reset(b, L.plotW, AICoinBehavior.initialSpacing),
    price: priceTransform(mode), subs: ['VOL'], tzOffset: 0, decimals: 2,
    options: defaultChartOptions(), nowMs: b.lastTime,
  })

  it('priceMode percent：价格轴刻度写成带正负号的百分比（ChartRenderer.swift:553）', () => {
    const r = new ChartRenderer(state('percent'))
    expect(effectivePriceMode(r.state)).toBe('percent')
    const texts = recordText(ctx => r.drawPlot(ctx, 402, 520, 3))
    const labels = joinRuns(texts.filter(t => t.x > L.plotW)).filter(t => /%$/.test(t))
    expect(labels.length).toBeGreaterThan(1)
    for (const s of labels) expect(s).toMatch(/^[+-]?\d+(\.\d)?%$/)
    expect(labels.some(s => s.startsWith('+'))).toBe(true)
  })

  it('对比：percentAxis 打开就按百分比画，图例按名字给出可见区末根涨跌', () => {
    const other = series('ETHUSDT', barsAt(T0, 200, 50))
    const a = alignCompare(b, other)
    const r = new ChartRenderer(withInput(state('linear'), {
      percentAxis: true, compare: [{ key: 'binance/usd_m/ETHUSDT', name: 'ETH', color: '#4f7cff', ...a }],
    }))
    expect(effectivePriceMode(r.state)).toBe('percent')
    const legend = compareLegend(r)
    expect(legend.map(x => x.name), '主图在前、对比按顺序跟上').toEqual(['BTC', 'ETH'])
    expect(legend[1].color).toBe('#4f7cff')
    expect(legend[1].value).not.toBeNull()
    expect(comparePercentLabel(legend[1].value)).toMatch(/%$/)
  })
})
