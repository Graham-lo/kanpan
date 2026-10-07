/* K 线回放接管一格之后，图表实际收到的 K 线：起点之后的藏起来、播一根进一根、切周期按同一时刻重新定位、换品种交还实时。
 * 图表用真的 TVChart.setData / updateBar / prependData（不起画布），取数、回放条、提示都换成假的。 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Bar } from '../src/chart/calc'

const Q = 9e5, H = 36e5
const NOW = Date.UTC(2026, 9, 7, 4, 7, 30)

/** 交易所那边的「真相」：任何周期都是从很早开始首尾相接，收盘价 = 开盘时刻 / 周期（看值就知道是哪一根） */
const ivMs = (iv: string): number => ({ '1m': 6e4, '15m': Q, '1h': H } as Record<string, number>)[iv]
const barAt = (t: number, iv: string): Bar => ({ t, o: t / ivMs(iv), h: t / ivMs(iv) + 1, l: t / ivMs(iv) - 1, c: t / ivMs(iv), v: 1 }) as Bar
/** 开盘严格早于 endTime 的最后 limit 根（正在走的那根也给，和币安一样） */
function backPage(iv: string, endTime: number | undefined, limit: number): Bar[] {
  const ms = ivMs(iv), cur = Math.floor(NOW / ms) * ms
  const last = endTime == null ? cur : Math.min(cur, Math.ceil(endTime / ms) * ms - ms)
  return Array.from({ length: limit }, (_, i) => barAt(last - (limit - 1 - i) * ms, iv))
}
const calls: string[] = []

vi.mock('../src/market', () => ({
  REST: 'https://fapi.test',
  klines: vi.fn(async (_s: string, iv: string, endTime: number | undefined, limit: number) => { calls.push(`back ${iv} ${endTime}`); return { ok: true, bars: backPage(iv, endTime, limit) } }),
  attachOI: vi.fn(async () => {}),
  j: vi.fn(async (url: string) => {
    const u = new URL(url), iv = u.searchParams.get('interval')!, from = +u.searchParams.get('startTime')!, n = +u.searchParams.get('limit')!
    calls.push(`fwd ${iv} ${from} ${n}`)
    const ms = ivMs(iv), cur = Math.floor(NOW / ms) * ms, out: unknown[] = []
    for (let t = from; t <= cur && out.length < n; t += ms) { const b = barAt(t, iv); out.push([b.t, String(b.o), String(b.h), String(b.l), String(b.c), '1', b.t + ms - 1, '1', 1, '0', '0', '0']) }
    return out
  }),
}))
vi.mock('../src/chart/intervals', () => ({ isCustomIv: () => false, customBase: (iv: string) => iv, customKlines: vi.fn(), aggregate: (b: Bar[]) => b }))
vi.mock('../src/ui/overlay', () => ({ toast: vi.fn(), dialogs: [] }))
vi.mock('../src/ui/common', () => ({ cls: () => '', pctText: () => '', sym: () => undefined }))
/** 回放条与选起点竖线：记下处理器，测试里直接按 */
const ui: { handlers?: Record<string, (...a: unknown[]) => void>; onPick?: (t: number) => void } = {}
vi.mock('../src/replay/bar', () => ({
  ReplayBar: class { constructor(_p: unknown, h: Record<string, (...a: unknown[]) => void>) { ui.handlers = h } pick() {} play() {} destroy() {} },
  PickOverlay: class { constructor(_c: unknown, _iv: unknown, on: (t: number) => void) { ui.onPick = on } destroy() {} },
}))

const { TVChart } = await import('../src/chart/chart')
const R = await import('../src/replay/controller')
const { toast } = await import('../src/ui/overlay')

function fakeChart(bars: Bar[], iv: string): InstanceType<typeof TVChart> {
  const P = TVChart.prototype as unknown as Record<string, unknown>
  const me = {
    meta: { symbol: 'BTCUSDT' }, iv, bars, rightBar: bars.length - 1 + 6, manual: null, auto: true, dirty: false, legendDirty: false, o: {}, drag: null, draft: null, cross: null,
    replay: null, dead: false, layers: [{ name: 'orderflow' }], indWanted: {}, ind: {},
    recalc() {}, recalcTail() {}, renderLegend() {}, setAuto() {}, rightMarginBars: () => 6,
    dropGesture: P.dropGesture, setData: P.setData, updateBar: P.updateBar, prependData: P.prependData,
  }
  return me as unknown as InstanceType<typeof TVChart>
}

const cfg = { symbol: 'BTCUSDT', iv: '15m' }
let cell: import('../src/replay/controller').ReplayCell
const reloads: number[] = []
const flush = async () => { for (let i = 0; i < 10; i++) await Promise.resolve() }

beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(NOW)
  ;(globalThis as unknown as { window: unknown }).window ??= { addEventListener() {} }
  cfg.symbol = 'BTCUSDT'; cfg.iv = '15m'; calls.length = 0; reloads.length = 0
  cell = { idx: 0, el: { querySelector: () => null } as unknown as HTMLElement, host: {} as HTMLElement, chart: fakeChart(backPage('15m', undefined, 1500), '15m'), loadToken: 0, hold: null }
  R.installReplay({ cfg: () => cfg, meta: () => ({ symbol: cfg.symbol, iv: cfg.iv }) as never, reload: () => { reloads.push(1) }, active: () => undefined, quote() {} })
})
afterEach(() => { if (R.replaying(cell)) R.toggleReplay(cell); vi.useRealTimers() })

/** 在 t 那一根定起点 */
async function startAt(t: number): Promise<void> {
  R.toggleReplay(cell)
  ui.onPick!(t)
  await flush()
}

describe('K 线回放接管之后图表收到的数据', () => {
  it('定起点：图上只到起点那一根，起点左边至少 300 根，订单流层收起，不重取（手里的够用）', async () => {
    const start = Date.UTC(2026, 9, 4, 4, 0)       // 3 天前那一根 15m
    await startAt(start)
    expect(R.replaying(cell)).toBe(true)
    const b = cell.chart.bars
    expect(b[b.length - 1].t).toBe(start)
    expect(b.every(x => x.t <= start)).toBe(true)
    expect(b.length).toBeGreaterThanOrEqual(300)
    expect(cell.chart.layers).toEqual([])
    expect(calls).toEqual([])
    const st = R.replayState()!
    expect(st.clock).toBe(start + Q)
    // 未来 = 起点之后到最后一根走完的为止（正在走的那根不算）
    expect(st.future).toBe((Math.floor(NOW / Q) * Q - (start + Q)) / Q)
  })

  it('4× 播放：每秒进 4 根，按时间顺序一根接一根，最后一根价格跟着走', async () => {
    const start = Date.UTC(2026, 9, 4, 4, 0)
    await startAt(start)
    const n0 = cell.chart.bars.length
    ui.handlers!.speed(4)
    ui.handlers!.toggle()
    await vi.advanceTimersByTimeAsync(1000)
    const b = cell.chart.bars
    expect(b.length).toBe(n0 + 4)
    expect(b.slice(-5).map(x => x.t)).toEqual([0, 1, 2, 3, 4].map(k => start + k * Q))
    expect(b[b.length - 1].c).toBe((start + 4 * Q) / Q)
    expect(R.replayState()!.clock).toBe(start + 5 * Q)
    // 实时推送这时到了：页面看 replaying() 跳过这一格（这里断言接管标记还在）
    expect(R.replaying(cell)).toBe(true)
  })

  it('切到 1h：按同一时刻重新定位，从 REST 取前后两页，最后一根是走完的那根 1h', async () => {
    const start = Date.UTC(2026, 9, 4, 4, 0)
    await startAt(start)
    ui.handlers!.speed(16); ui.handlers!.toggle()
    await vi.advanceTimersByTimeAsync(1000 / 16 * 7)   // 播了 7 根：回放钟 = 06:00
    expect(R.replayState()!.clock).toBe(start + 8 * Q)
    ui.handlers!.toggle()                               // 暂停
    cfg.iv = '1h'
    expect(R.replayLoad(cell)).toBe(true)
    await flush()
    const clock = start + 8 * Q
    expect(calls).toEqual([`back 1h ${clock}`, `fwd 1h ${clock} 600`])
    const b = cell.chart.bars
    expect(cell.chart.iv).toBe('1h')
    expect(b[b.length - 1].t).toBe(clock - H)
    expect(b.length).toBeGreaterThanOrEqual(300)
    expect(R.replayState()!.iv).toBe('1h')
    expect(R.replayState()!.start).toBe(start + Q)  // 起点留着
  })

  it('拖进度线回到起点之前没走过的位置：多出来的收回「未来」，再往前拖又从「未来」搬回来，不重取', async () => {
    const start = Date.UTC(2026, 9, 4, 4, 0)
    await startAt(start)
    const stop = Math.floor(NOW / Q) * Q
    ui.handlers!.seek(0.5, 'start'); ui.handlers!.seek(0.5, 'end')
    await flush()
    const mid = R.replayState()!.clock, b = cell.chart.bars
    expect(b[b.length - 1].t + Q).toBe(mid)
    expect(mid).toBeGreaterThan(start); expect(mid).toBeLessThan(stop)
    ui.handlers!.toStart()
    expect(cell.chart.bars[cell.chart.bars.length - 1].t).toBe(start)
    expect(calls.filter(c => c.startsWith('back'))).toEqual([])
  })

  /** 3 天前定起点、16× 播过 30 小时、切到 1m：1m 从这里往回一页（1500 根 ≈ 25 小时）够不到起点 */
  async function farFromStart(): Promise<number> {
    const start = Date.UTC(2026, 9, 4, 4, 0)
    await startAt(start)
    ui.handlers!.speed(16); ui.handlers!.toggle()
    await vi.advanceTimersByTimeAsync(1000 / 16 * 120)
    ui.handlers!.toggle()
    cfg.iv = '1m'
    expect(R.replayLoad(cell)).toBe(true)
    await flush()
    expect(cell.chart.bars[0].t).toBeGreaterThan(start)
    calls.length = 0
    return start + Q                                     // 起点的回放钟（15m 那一根收线）
  }
  const atStart = (s0: number): void => {
    const b = cell.chart.bars
    expect(R.replayState()!.clock).toBe(s0)
    expect(b.length).toBeGreaterThanOrEqual(300)
    expect(b[b.length - 1].t).toBe(s0 - 6e4)
    expect(b.every((x, i) => !i || x.t - b[i - 1].t === 6e4)).toBe(true)
    expect(calls.some(c => c.startsWith('back 1m'))).toBe(true)   // 重取过（不是空图干等）
  }

  it('切到细周期后图上那份够不到起点：「回到起点」围着起点重取，不留空图', async () => {
    const s0 = await farFromStart()
    ui.handlers!.toStart()
    await flush()
    atStart(s0)
  })

  it('切到细周期后图上那份够不到起点：进度线一路拖到最左（取数没回来就松手）落在起点，等的时候不露「未来」', async () => {
    const s0 = await farFromStart()
    ui.handlers!.seek(0.95, 'start')
    ui.handlers!.seek(0.4, 'move')                      // 还在这份里：照常收回「未来」
    expect(cell.chart.bars.length).toBeGreaterThan(300)
    ui.handlers!.seek(0.05, 'move')                     // 过了这份最早那根
    expect(cell.chart.bars.length).toBe(0)
    ui.handlers!.seek(0.02, 'move')
    ui.handlers!.seek(0, 'move')
    ui.handlers!.seek(0, 'end')
    await flush(); await flush()
    atStart(s0)
  })

  it('播到最新：停下并提示，不会把正在走的那根当未来播出去', async () => {
    const start = Math.floor(NOW / Q) * Q - 3 * Q
    vi.mocked(toast).mockClear()
    await startAt(start)
    ui.handlers!.speed(16); ui.handlers!.toggle()
    await vi.advanceTimersByTimeAsync(3000)
    const b = cell.chart.bars
    expect(b[b.length - 1].t).toBe(Math.floor(NOW / Q) * Q - Q)
    expect(R.replayState()!.playing).toBe(false)
    expect(vi.mocked(toast).mock.calls.some(c => c[0] === '已经播到最新')).toBe(true)
  })

  it('换品种：交还实时（loadCell 照常往下取），订单流层放回去；退出回放走整份重取', async () => {
    await startAt(Date.UTC(2026, 9, 4, 4, 0))
    cfg.symbol = 'ETHUSDT'
    expect(R.replayLoad(cell)).toBe(false)
    expect(R.replaying(cell)).toBe(false)
    expect(cell.chart.layers).toEqual([{ name: 'orderflow' }])
    expect(reloads).toEqual([])
    cfg.symbol = 'BTCUSDT'
    await startAt(Date.UTC(2026, 9, 4, 4, 0))
    R.toggleReplay(cell)
    expect(R.replaying(cell)).toBe(false)
    expect(reloads).toEqual([1])
  })

  it('秒级周期：不进回放', () => {
    cfg.iv = '1s'
    vi.mocked(toast).mockClear()
    R.toggleReplay(cell)
    expect(R.replaying(cell)).toBe(false)
    expect(vi.mocked(toast).mock.calls[0]?.[0]).toBe('秒级周期不能回放')
  })
})
