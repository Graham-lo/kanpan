import { afterEach, describe, expect, it, vi } from 'vitest'
import { beijingDayStart, buildInsights, flowObservation, InsightPoller, matchesChart, nearestInsightOrders, parseInsights, priceReaction, shouldOpenInsightSwipe, type InsightBody, type InsightInput } from '../src/m/pages/chart/insights'
import type { BigOrder } from '../src/orderflow/types'
import type { Bar } from '../src/chart/calc'
const M = 60_000, NOW = Date.UTC(2026, 9, 9, 9, 20, 10), END = Math.floor((NOW - 3000) / M) * M
const source = { venueID: 'binance:usdtPerp:BTCUSDT', exchange: '币安', product: 'usdtPerp' as const, buyUsd: 3e6, sellUsd: 1e6 }
const body = (patch: Partial<InsightBody> = {}): InsightBody => ({ base: 'BTC', generatedAtMs: NOW, dayStartMs: beijingDayStart(NOW), tracked: true, coverageSinceMs: END - 60 * M, lastTradeMs: END - M, bigUsd: 1e5,
  windows: [5, 15, 60].map(minutes => ({ minutes: minutes as 5 | 15 | 60, sources: [source] })), zones: [{ ...source, low: 100, high: 101, recentBuyUsd: 2e6, recentSellUsd: 1e6, firstMs: END - 30 * M, lastMs: END - M }], ...patch })
const bars = (from = END - 60 * M, n = 60): Bar[] => Array.from({ length: n }, (_, j) => ({ t: from + j * M, o: 100 + j * .1, h: 101 + j * .1, l: 99 + j * .1, c: 100.1 + j * .1, v: 1 }))
const order = (patch: Partial<BigOrder> = {}): BigOrder => ({ ...source, side: 'ask', bucket: 10, price: 101, firstSeenMs: NOW - 10 * M, endMs: null, status: 'live', initialNotional: 1e6, notional: 9e5, filledNotional: 1e5, threshold: 1e5, vanishedNotional: null, ...patch })
const input = (patch: Partial<InsightInput> = {}): InsightInput => ({ symbol: 'BTCUSDT', now: NOW, mid: 100, dec: 2, orders: [], snapshotReady: true, body: body(), state: 'ready', prices: bars(), stale: false, liq: null, ...patch })
afterEach(() => vi.useRealTimers())

describe('盘口洞察 · 真实数据与覆盖', () => {
  it('北京时间零点独立于交易所UTC日线，跨午夜重置今日价区', () => {
    expect(beijingDayStart(Date.UTC(2026, 9, 9, 16, 1))).toBe(Date.UTC(2026, 9, 9, 16))
    const view = buildInsights(input({ now: NOW + 24 * 3600_000 }))
    expect(view.sections.find(s => s.id === 'zones')!.rows).toEqual([])
  })
  it('拒绝错币、非法产品、非北京日界、未来覆盖/价区和溢出金额', () => {
    expect(parseInsights(body(), 'BTC')).not.toBeNull()
    expect(parseInsights(body(), 'ETH')).toBeNull()
    for (const patch of [{ dayStartMs: Date.UTC(2026, 9, 9) }, { generatedAtMs: 0 }, { coverageSinceMs: NOW + M }, { lastTradeMs: NOW + M }]) expect(parseInsights(body(patch), 'BTC')).toBeNull()
    expect(parseInsights(body({ zones: [{ ...body().zones[0], firstMs: NOW + M, lastMs: NOW + M }] }), 'BTC')).toBeNull()
    expect(parseInsights(body({ windows: [{ minutes: 5, sources: [{ ...source, buyUsd: Number.MAX_VALUE, sellUsd: Number.MAX_VALUE }] }] }), 'BTC')).toBeNull()
    expect(parseInsights(body({ windows: [{ minutes: 5, sources: [{ ...source, product: 'delivery' }] }] }), 'BTC')).toBeNull()
  })
  it('精确匹配交易所、产品与报价币，OKX规范名可对齐', () => {
    expect(matchesChart('okx:usdtPerp:BTC-USDT-SWAP', 'okx/usd_m/BTCUSDT')).toBe(true)
    expect(matchesChart(source.venueID, 'okx/usd_m/BTCUSDT')).toBe(false)
    expect(matchesChart('binance:spot:BTCUSDT', 'BTCUSDT')).toBe(false)
    expect(matchesChart('binance:usdtPerp:BTCUSDC', 'BTCUSDT')).toBe(false)
  })
  it('最近上下墙只取主图簿；断线保留的live挂单不冒充当前墙', () => {
    const orders = [order({ price: 102 }), order(), order({ side: 'bid', price: 99 }), order({ venueID: 'okx:usdtPerp:BTCUSDT', price: 100.2 }), order({ status: 'filled', price: 100.1 })]
    expect(nearestInsightOrders(orders, 'BTCUSDT', 100).map(o => o.price)).toEqual([101, 99])
    expect(buildInsights(input({ orders, snapshotReady: false })).sections[0].rows).toEqual([])
    expect(buildInsights(input({ orders, snapshotReady: false })).sections[0].empty).toContain('获取')
  })
  it('完整连续分钟行情才比较价格；拒绝缺口、缺首根与当前未完成分钟', () => {
    const rows = bars(END - 5 * M, 5)
    expect(priceReaction(rows, END - 5 * M, END)).toBeCloseTo(.5)
    expect(priceReaction(rows.filter((_, n) => n !== 2), END - 5 * M, END)).toBeNull()
    expect(priceReaction(rows.slice(1), END - 5 * M, END)).toBeNull()
    expect(priceReaction(rows, END - 5 * M, END + 30_000)).toBeNull()
    expect(priceReaction(rows.map((b, n) => n === 2 ? { ...b, h: Infinity } : b), END - 5 * M, END)).toBeNull()
    expect(priceReaction(rows.map((b, n) => n === 2 ? { ...b, l: b.h + 1 } : b), END - 5 * M, END)).toBeNull()
  })
  it('主动成交与价格只描述观察，不把逆向/未推进写成确定吸收', () => {
    expect(flowObservation(60, 40, .06)).toBe('主动买入伴随价格上移')
    expect(flowObservation(60, 40, -.1)).toBe('主动买入偏多，价格仍下移')
    expect(flowObservation(20, 80, .01)).toBe('主动卖出偏多，价格暂未推进')
    expect(flowObservation(50, 50, .1)).toBe('主动买卖相对均衡')
    expect(flowObservation(60, 40, null)).toContain('不足')
  })
  it('后端完整分钟窗口对齐价格；最近覆盖不够15m时不做15m判断', () => {
    const good = buildInsights(input()).sections.find(s => s.id === 'activity')!.rows
    expect(good[0].detail).toContain('伴随价格上移')
    expect(good.some(r => r.id.startsWith('observed-'))).toBe(true)
    const partial = buildInsights(input({ body: body({ coverageSinceMs: END - 10 * M }) })).sections.find(s => s.id === 'activity')!.rows
    expect(partial[0].detail).toContain('伴随价格上移'); expect(partial[1].detail).toContain('覆盖不足')
    expect(partial.some(r => r.id.startsWith('observed-'))).toBe(false)
  })
  it('接口失败/过期保留价区但停方向推断；缺源不补零、不套其他所', () => {
    const failed = buildInsights(input({ state: 'error' }))
    expect(failed.status).toContain('无法更新'); expect(failed.sections.find(s => s.id === 'zones')!.rows).toHaveLength(1)
    expect(failed.sections.find(s => s.id === 'activity')!.rows[0].note).toBeUndefined()
    expect(failed.sections.find(s => s.id === 'activity')!.rows).toHaveLength(2)
    expect(failed.sections.find(s => s.id === 'zones')!.rows[0].note).toContain('截至')
    const other = buildInsights(input({ symbol: 'okx/usd_m/BTCUSDT' }))
    expect(other.sections.find(s => s.id === 'activity')!.rows[0].detail).toContain('覆盖不足')
    expect(buildInsights(input({ body: null, state: 'error' })).sections.find(s => s.id === 'zones')!.empty).toContain('无法更新')
    expect(buildInsights(input({ body: body({ generatedAtMs: NOW + 60_000 }) })).sections.find(s => s.id === 'activity')!.rows[0].detail).toContain('覆盖不足')
  })
  it('真实价区按每币价映射千倍品种，跨所分源不合成虚构支撑区', () => {
    const view = buildInsights(input({ symbol: '1000PEPEUSDT', dec: 5, body: body({ base: 'PEPE', zones: [{ ...body().zones[0], low: .00001, high: .000011 }, { ...body().zones[0], venueID: 'okx:usdtPerp:PEPEUSDT', exchange: 'OKX', low: .00001, high: .000011 }] }) }))
    const rows = view.sections.find(s => s.id === 'zones')!.rows
    expect(rows).toHaveLength(2); expect(rows[0].title).toBe('0.01000–0.01100'); expect(rows[1].detail).toContain('OKX')
  })
  it('爆仓与大单不相加；现货不展示爆仓；请求失败不显示0', () => {
    const liq = { tracked: true, updatedAtMs: NOW, rows: new Map([[END - 3 * M, [END - 3 * M, 700, 200, 2, 500, 100, 0, 0] as [number, number, number, number, number, number, number, number]]]) }
    const view = buildInsights(input({ liq }))
    expect(view.sections.find(s => s.id === 'activity')!.rows[0].note).toContain('3.0M')
    expect(view.sections.find(s => s.id === 'liquidation')!.rows[0].detail).toContain('700')
    expect(buildInsights(input({ liq: { ...liq, failed: true } })).sections.find(s => s.id === 'liquidation')!.rows[0].detail).toContain('暂无')
    expect(buildInsights(input({ symbol: 'coinbase/spot/BTC-USD', liq })).sections.some(s => s.id === 'liquidation')).toBe(false)
  })
  it('价区旧回包或失败不拖旧独立爆仓窗口；无回包也保留3秒宽限', () => {
    const liq = { tracked: true, updatedAtMs: NOW, rows: new Map([[END - 3 * M, [END - 3 * M, 700, 200, 2, 500, 100, 0, 0] as [number, number, number, number, number, number, number, number]]]) }
    for (const state of ['ready', 'error'] as const) {
      const view = buildInsights(input({ state, body: body({ generatedAtMs: NOW - 3600_000 }), liq }))
      expect(view.sections.find(s => s.id === 'liquidation')!.rows[0].detail).toContain('700')
    }
    const marginLiq = { tracked: true, updatedAtMs: END + 1000, rows: new Map([[END - M, [END - M, 700, 200, 2, 500, 100, 0, 0] as [number, number, number, number, number, number, number, number]]]) }
    const margin = buildInsights(input({ now: END + 1000, body: null, state: 'error', liq: marginLiq }))
    expect(margin.sections.find(s => s.id === 'liquidation')!.rows[0].note).toBe('该时段未观测到爆仓')
  })
  it('系统边缘、横滑、缓慢移动与图表外非入口不会触发上滑', () => {
    expect(shouldOpenInsightSwipe(5, -80, 300, 180, 393)).toBe(true)
    expect(shouldOpenInsightSwipe(5, -48, 300, 180, 393)).toBe(true)
    expect(shouldOpenInsightSwipe(5, -80, 300, 10, 393)).toBe(false)
    expect(shouldOpenInsightSwipe(80, -80, 300, 180, 393)).toBe(false)
    expect(shouldOpenInsightSwipe(5, -80, 1300, 180, 393)).toBe(false)
    expect(shouldOpenInsightSwipe(0, 80, 300, 180, 393)).toBe(false)
  })
})

describe('盘口洞察 · 请求生命周期', () => {
  it('只在打开时请求，30秒轮询，关闭取消且旧币响应不能串入', async () => {
    vi.useFakeTimers()
    const pending: { base: string; signal: AbortSignal; resolve(v: unknown): void }[] = [], update = vi.fn()
    const poll = new InsightPoller((base, signal) => new Promise(resolve => pending.push({ base, signal, resolve })), update)
    poll.start('BTC'); poll.start('BTC'); expect(pending).toHaveLength(1)
    poll.start('ETH'); expect(pending[0].signal.aborted).toBe(true)
    pending[0].resolve(body()); await Promise.resolve(); expect(update).not.toHaveBeenCalledWith(expect.anything(), 'ready')
    pending[1].resolve(body({ base: 'ETH' })); await Promise.resolve(); expect(update).toHaveBeenLastCalledWith(expect.objectContaining({ base: 'ETH' }), 'ready')
    await vi.advanceTimersByTimeAsync(30_000); expect(pending).toHaveLength(3)
    poll.stop(); expect(pending[2].signal.aborted).toBe(true)
    pending[2].resolve(body({ base: 'ETH' })); await Promise.resolve()
    await vi.advanceTimersByTimeAsync(60_000); expect(pending).toHaveLength(3)
  })
  it('错误或格式损坏显式error，不创建全零统计', async () => {
    vi.useFakeTimers(); const update = vi.fn(), poll = new InsightPoller(async () => ({ base: 'BTC', windows: [], zones: [] }), update)
    poll.start('BTC'); await Promise.resolve(); expect(update).toHaveBeenLastCalledWith(null, 'error'); poll.stop()
  })
})
