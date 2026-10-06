// 行情页引擎的生命周期：心跳随页面藏 / 露停开（ChartBeat）、换品种时留旧图只留到取数有结果（holdsPrevious）。
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AWAY_RESYNC_MS, ChartBeat, resyncOnOpen } from '../src/m/chart/beat'
import { ViewWindow, defaultChartOptions } from '../src/m/chart/geometry'
import { makeState, type ChartState } from '../src/m/chart/state'
import { showsOtherChart } from '../src/m/pages/chart/logic'
import { synthSeries } from './m-chart-fixtures'

describe('ChartBeat · 行情页藏起来时心跳停', () => {
  let now = 1_700_000_000_000
  let ticks = 0, stops = 0, returns = 0
  const hooks = () => ({
    tick: () => { ticks++ },
    stopped: () => { stops++ },
    onReturn: () => { returns++ },
    now: () => now,
  })
  const advance = (ms: number) => { now += ms; vi.advanceTimersByTime(ms) }
  beforeEach(() => { vi.useFakeTimers(); ticks = 0; stops = 0; returns = 0 })
  afterEach(() => { vi.useRealTimers() })

  it('露着：建好立刻补一拍，之后每秒一拍', () => {
    const b = new ChartBeat(hooks(), false)
    expect(ticks).toBe(1)
    advance(3000)
    expect(ticks).toBe(4)
    b.dispose()
  })

  it('pause 之后不再跳（原来只在 document.hidden 时停，切到自选页仍每秒 refresh + 覆盖层重算）', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause()
    expect(b.running).toBe(false)
    expect(stops).toBe(1)
    const before = ticks
    advance(60_000)
    expect(ticks).toBe(before)
    b.dispose()
  })

  it('建的时候就 pause（壳在后台先建页）：一拍都不跳', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause()
    ticks = 0
    advance(10_000)
    expect(ticks).toBe(0)
    b.dispose()
  })

  it('resume 立刻补一拍；离开不到 5 秒不重拉，超过 5 秒补缺口', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause(); ticks = 0
    advance(2000)
    b.resume()
    expect(ticks).toBe(1)
    expect(returns).toBe(0)
    b.pause()
    advance(AWAY_RESYNC_MS + 1)
    b.resume()
    expect(ticks).toBe(2)
    expect(returns).toBe(1)
    advance(1000)
    expect(ticks).toBe(3)
    b.dispose()
  })

  it('pause 与 document.hidden 叠着：两样都放开才跳；离开时长从最早停的那一刻算', () => {
    const b = new ChartBeat(hooks(), false)
    b.pause(); ticks = 0
    advance(1000)
    b.setHidden(true)
    advance(AWAY_RESYNC_MS)
    b.setHidden(false) // 页面仍 pause 着
    expect(ticks).toBe(0)
    expect(b.running).toBe(false)
    b.resume()
    expect(ticks).toBe(1)
    expect(returns).toBe(1)
    b.dispose()
  })

  it('重复 pause / resume 不叠定时器', () => {
    const b = new ChartBeat(hooks(), false)
    b.resume(); b.resume()
    ticks = 0
    advance(1000)
    expect(ticks).toBe(1)
    b.pause(); b.pause()
    expect(stops).toBe(1)
    b.dispose()
  })

  it('离线图（截图卡）从不跳；dispose 之后 resume 也不复活', () => {
    const off = new ChartBeat(hooks(), false, false)
    off.resume()
    advance(5000)
    expect(ticks).toBe(0)
    const b = new ChartBeat(hooks(), false)
    b.dispose(); ticks = 0
    b.resume()
    advance(5000)
    expect(ticks).toBe(0)
  })
})

// 引擎为了换品种 / 周期不闪空图会留上一张图（holdOnEmpty）。原来出错也一直留，于是新品种名底下画着上一只；
// 现在只留到取数有结果：出错或取到零根就撤图，宿主的 cp-nodata 盖层（showsOtherChart）照旧兜底。
describe('holdsPrevious · 换品种留旧图只留到取数有结果', () => {
  type Holds = typeof import('../src/m/chart/index').holdsPrevious
  let holdsPrevious: Holds
  beforeEach(async () => { holdsPrevious = (await import('../src/m/chart/index')).holdsPrevious })

  const drawn = (symbol: string, n = 200): ChartState => makeState({
    series: synthSeries(n, { interval: '1h', t0: 1_700_000_000_000, symbol }),
    view: ViewWindow.fromTo(0, 1), symbol: { symbol, base: symbol.replace(/USDT$/, ''), priceDecimals: 2 },
    options: defaultChartOptions(),
  })

  it('还在取：留着上一只，不闪空图', () => {
    expect(holdsPrevious(true, drawn('BTCUSDT'))).toBe(true)
  })
  it('取数出错 / 取到零根（loading 已落）：不留，撤图', () => {
    expect(holdsPrevious(false, drawn('BTCUSDT'))).toBe(false)
  })
  it('图上本来就空：没什么可留', () => {
    expect(holdsPrevious(true, null)).toBe(false)
    expect(holdsPrevious(true, drawn('BTCUSDT', 0))).toBe(false)
  })

  // 引擎一侧撤图后 drawn 为 null；宿主盖层的判定与引擎撤图并存时每个阶段都只出现一种画面
  const scene = (loading: boolean, error: string | null, prev: ChartState | null, symbol: string) => {
    const kept = holdsPrevious(loading, prev) ? prev : null
    const s = kept?.input.series
    const cover = showsOtherChart({ loading, error }, s ? { symbol: s.symbol, interval: s.interval } : null, symbol, '1h')
    return { chart: kept ? s!.symbol : null, cover }
  }
  it('BTC → 下架代号：取的时候留 BTC 不盖；出错后撤图 + 盖「取不到」，不再是 BTC 的 K 线配新名字', () => {
    const btc = drawn('BTCUSDT')
    expect(scene(true, null, btc, 'GONEUSDT')).toEqual({ chart: 'BTCUSDT', cover: false })
    expect(scene(false, '行情暂时取不到', btc, 'GONEUSDT')).toEqual({ chart: null, cover: true })
    expect(scene(false, '这只品种没有行情', btc, 'GONEUSDT')).toEqual({ chart: null, cover: true })
  })
})

// 同步整桶换线时画线提醒的对账（壳层接的是：onDrawingsChanged 的 replaced → reconcileLineAlertsIn，
// 控制器 onChanged → reconcileLineAlerts；这里把同一套接在一本 DrawingBook 上）。
// 2026-10-06 起提醒不依附画线：线删了（本机或同步）提醒照留、照自己的 lines 判；线挪了才跟着改。
describe('同步删线 → 线上的提醒照留', () => {
  type Bench = typeof import('../src/m/pages/chart/drawingBench')
  type Store = typeof import('../src/m/app/store')
  type Book = typeof import('../src/m/chart/draw/book')
  type Codec = typeof import('../src/m/chart/draw/drawing')
  let B: Bench, S: Store, K: Book, A: Codec
  beforeEach(async () => {
    B = await import('../src/m/pages/chart/drawingBench')
    S = await import('../src/m/app/store')
    K = await import('../src/m/chart/draw/book')
    A = await import('../src/m/chart/draw/drawing')
  })
  const T = 1_700_000_000_000
  const hline = (id: string, p: number) => A.decodeDrawing({ id, kind: 'hline', points: [{ t: T, p }] })
  const lineAlert = (sym: string, id: string, p: number) => ({
    id: 'al-' + id, kind: 'drawing' as const, market: 'binance/usd_m' as const, symbol: sym,
    lines: [{ points: [{ t: T, p }], extendLeft: true, extendRight: true }], condition: 'touch' as const, status: 'active' as const, once: true,
    armedAt: 1, firedAt: null, firedPrice: null, title: 't', note: null, webhook: null, webhookText: null,
    drawingID: `binance/usd_m/${sym}/${id}`, reviewID: null, dueAt: null, rule: null, created: 1,
  })
  const wire = (book: InstanceType<Book['DrawingBook']>) => {
    const itemsOf = (k: string) => book.items(k)
    book.observe({}, ch => { if (ch.kind === 'replaced') B.reconcileLineAlertsIn(itemsOf, ch.keys) })
    B.reconcileLineAlertsIn(itemsOf, Object.keys(book.archive.bySymbol))
  }
  const ids = () => S.st.alerts.map(a => a.id).sort()

  it('云端删了 BTC 的 a 线、ETH 的 e 线：提醒全留着、还生效、lines 不变', () => {
    const book = new K.DrawingBook()
    book.replaceBucket([hline('a', 60_000), hline('b', 61_000)], 'BTCUSDT')
    book.replaceBucket([hline('e', 3_000)], 'ETHUSDT')
    S.st.alerts = [lineAlert('BTCUSDT', 'a', 60_000), lineAlert('BTCUSDT', 'b', 61_000), lineAlert('ETHUSDT', 'e', 3_000)]
    wire(book)
    const before = structuredClone(S.st.alerts)
    const next = book.archive.clone()
    next.set('binance/usd_m/BTCUSDT', [hline('b', 61_000)])
    next.set('binance/usd_m/ETHUSDT', [])
    book.replace(next)
    expect(ids()).toEqual(['al-a', 'al-b', 'al-e'])
    expect(S.st.alerts).toEqual(before)
  })

  it('线被别处挪了：提醒跟着改价位并重新上膛', () => {
    const book = new K.DrawingBook()
    book.replaceBucket([hline('b', 61_000)], 'BTCUSDT')
    S.st.alerts = [lineAlert('BTCUSDT', 'b', 61_000)]
    wire(book)
    const next = book.archive.clone()
    next.set('binance/usd_m/BTCUSDT', [hline('b', 65_000)])
    book.replace(next)
    expect(S.st.alerts[0].lines[0].points[0].p).toBe(65_000)
    expect(S.st.alerts[0].armedAt).toBeGreaterThan(1)
  })

  it('本机删线（控制器 onChanged 那条路）：提醒照留', () => {
    const book = new K.DrawingBook()
    book.replaceBucket([hline('a', 60_000)], 'BTCUSDT')
    S.st.alerts = [lineAlert('BTCUSDT', 'a', 60_000)]
    wire(book)
    B.reconcileLineAlerts('BTCUSDT', [])
    expect(ids()).toEqual(['al-a'])
    expect(S.st.alerts[0]).toMatchObject({ status: 'active', armedAt: 1, lines: [{ points: [{ t: T, p: 60_000 }] }] })
  })
})

describe('推送连上时补缺口：只有真正断过再连上才补（冷启动末页不取两遍）', () => {
  const t0 = 1_000_000
  it('冷启动：首屏刚取完就第一次连上 → 同一批数据，不补', () => {
    expect(resyncOnOpen('connecting', 'open', false, t0, t0 + 600)).toBe(false)
    expect(resyncOnOpen('idle', 'open', false, t0, t0 + 4_999)).toBe(false)
  })
  it('冷启动但连得很慢（首屏取完超过 5 秒才连上）→ 期间可能收了根，补', () => {
    expect(resyncOnOpen('connecting', 'open', false, t0, t0 + 5_001)).toBe(true)
  })
  it('首屏还没取到（freshAt 为 0）就连上 → 交给 resync 自己按 loading 跳过', () => {
    expect(resyncOnOpen('connecting', 'open', false, 0, t0)).toBe(true)
  })
  it('真正断过再连上（见过连着 → 断开 → 连上）→ 补，哪怕刚取过末页', () => {
    expect(resyncOnOpen('connecting', 'open', true, t0, t0 + 100)).toBe(true)
    expect(resyncOnOpen('closed', 'open', true, t0, t0 + 60_000)).toBe(true)
  })
  it('F7：连过之后行情页自己收起来（idle）再回来连上 → 不补，交给心跳 onReturn；冷启动的 idle 不受影响', () => {
    expect(resyncOnOpen('idle', 'open', true, t0, t0 + 100, true)).toBe(false)
    expect(resyncOnOpen('connecting', 'open', true, t0, t0 + 60_000, true)).toBe(false)
    expect(resyncOnOpen('connecting', 'open', false, t0, t0 + 5_001, true)).toBe(true)
    expect(resyncOnOpen('connecting', 'open', true, t0, t0 + 100, false)).toBe(true)
  })
  it('没有变成连上（仍连着、断开、重连中）→ 不补', () => {
    expect(resyncOnOpen('open', 'open', true, 0, t0)).toBe(false)
    expect(resyncOnOpen('open', 'connecting', true, 0, t0)).toBe(false)
    expect(resyncOnOpen('open', 'closed', true, 0, t0)).toBe(false)
  })
})
