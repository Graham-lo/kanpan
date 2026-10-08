// 主力订单流开图提速（体感优化 2026-10-07）：步长 / 标定门槛记在本机、开图分阶段提示、换走的那几只先留着
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  CALIB_CACHE_KEY, CALIB_KEEP_MS, START_CACHE_MAX, STEP_CACHE_KEY, STEP_KEEP_MS,
  cachedCalibration, cachedStep, storeCalibration, storeStep,
} from '../src/orderflow/startCache'
import { FeedKeeper, KEEP_LIMIT, KEEP_TTL_MS, type Parkable } from '../src/orderflow/keep'
import { OrderFlowFeed } from '../src/orderflow/feed'
import { BucketScheme } from '../src/orderflow/bucket'
import { orderFlowLoadingText } from '../src/m/chart/renderer.orderflow'
import { toChartSnapshot } from '../src/m/chart/orderflow.source'

const DAY = 86_400_000

class MemStore {
  m = new Map<string, string>()
  getItem(k: string): string | null { return this.m.get(k) ?? null }
  setItem(k: string, v: string): void { this.m.set(k, v) }
  removeItem(k: string): void { this.m.delete(k) }
  clear(): void { this.m.clear() }
}
let store: MemStore
beforeEach(() => { store = new MemStore(); (globalThis as { localStorage?: unknown }).localStorage = store })
afterEach(() => { delete (globalThis as { localStorage?: unknown }).localStorage; vi.useRealTimers() })

describe('A1 · 步长与标定门槛记在本机', () => {
  const ref = BucketScheme.referenceDay(Date.UTC(2026, 9, 7, 12))

  it('步长按代号 + 参考日记：同一天是 exact，旧几天的先拿来开张，超过 7 天 / 比参考日还新的当没有', () => {
    expect(cachedStep('arbusdt', ref)).toBeNull()
    storeStep('arbusdt', ref, 0.0005)
    expect(cachedStep('ARBUSDT', ref)).toEqual({ step: 0.0005, exact: true })
    expect(cachedStep('ARBUSDT', ref + 2 * DAY)).toEqual({ step: 0.0005, exact: false })
    expect(cachedStep('ARBUSDT', ref + STEP_KEEP_MS + DAY)).toBeNull()
    expect(cachedStep('ARBUSDT', ref - DAY)).toBeNull()
  })

  it('坏值不记；坏 JSON 当没有', () => {
    storeStep('X', ref, 0); storeStep('Y', ref, NaN)
    expect(store.getItem(STEP_CACHE_KEY)).toBeNull()
    store.setItem(STEP_CACHE_KEY, '{oops')
    expect(cachedStep('X', ref)).toBeNull()
    storeCalibration('NVDA', -1, ref)
    expect(store.getItem(CALIB_CACHE_KEY)).toBeNull()
  })

  it('标定门槛留 3 天', () => {
    const now = Date.UTC(2026, 9, 7, 12)
    storeCalibration('xau', 250_000, now)
    expect(cachedCalibration('XAU', now + DAY)).toBe(250_000)
    expect(cachedCalibration('XAU', now + CALIB_KEEP_MS + 1)).toBeNull()
  })

  it('满 64 条丢最旧的', () => {
    for (let i = 0; i < START_CACHE_MAX + 5; i++) storeCalibration(`S${i}`, 1000 + i, 1_000_000 + i)
    const all = JSON.parse(store.getItem(CALIB_CACHE_KEY)!) as Record<string, unknown>
    expect(Object.keys(all)).toHaveLength(START_CACHE_MAX)
    expect(all.S0).toBeUndefined()
    expect(all[`S${START_CACHE_MAX + 4}`]).toBeDefined()
  })

  const feed = (symbol: string, crypto: boolean) => new OrderFlowFeed({
    symbol, crypto, turnover24h: null, tick: null, route: 'direct', override: null, onFrame: () => {},
  })

  it('要标定的品种：本机没有上一次的门槛才压着（定门槛），有就直接往下走', () => {
    const cold = feed('XAUUSDT', false)
    expect(cold.isCalibrating).toBe(true)
    expect(cold.stage).toBe('threshold')
    storeCalibration('XAU', 300_000, Date.now())
    const warm = feed('XAUUSDT', false)
    expect(warm.isCalibrating).toBe(false)
    expect(warm.stage).not.toBe('threshold')
    // 先拿上一次标的门槛出帧
    expect(Object.values(warm.model.thresholds).filter(v => typeof v === 'number')).toContain(300_000)
  })

  it('要推步长的币：本机记着今天的步长，一开张模型就有桶（不卡在「取步长」）', () => {
    const cold = feed('ARBUSDT', true)
    expect(cold.stage).toBe('step')
    storeStep('ARBUSDT', BucketScheme.referenceDay(Date.now()), 0.0005)
    const warm = feed('ARBUSDT', true)
    expect(warm.model.thresholds.step).toBe(0.0005)
    expect(warm.stage).toBe('connect')
  })

  it('park / unpark：留着时不出帧，换回来马上出', () => {
    const f = feed('BTCUSDT', true)
    expect(f.isParked).toBe(false)
    f.park()
    expect(f.isParked).toBe(true)
    f.unpark()
    expect(f.isParked).toBe(false)
    f.stop()
    f.park()
    expect(f.isParked).toBe(false)
  })

  it('留着的那只不取服务端历史、不拉深度快照（不和刚换上的抢出口），换回来再补', async () => {
    const urls: string[] = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => { urls.push(String(u)); return new Response('null', { status: 503 }) }))
    try {
      storeStep('ARBUSDT', BucketScheme.referenceDay(Date.now()), 0.0005)
      const f = feed('ARBUSDT', true)
      const book = { id: 'binance:usdtPerp:ARBUSDT', venue: { exchange: 'binance', product: 'usdtPerp', instrument: 'ARBUSDT', notional: { kind: 'linear' } }, tick: 0.0001, priceFactor: 1 }
      ;(f as unknown as { byId: Map<string, unknown> }).byId.set(book.id, book)
      const priv = f as unknown as { pumpHistory(): void; fetchSnapshot(b: unknown): Promise<void> }
      f.park()
      priv.pumpHistory()
      await priv.fetchSnapshot(book)
      await new Promise(r => setTimeout(r, 0))
      expect(urls.filter(u => u.includes('orderflow/history'))).toHaveLength(0)
      expect(urls.filter(u => u.includes('depth'))).toHaveLength(0)
      f.unpark()
      await new Promise(r => setTimeout(r, 0))
      expect(urls.filter(u => u.includes('orderflow/history')).length).toBe(1)
      expect(urls.filter(u => u.includes('depth')).length).toBe(1)
      f.stop()
    } finally { vi.unstubAllGlobals() }
  })
})

describe('A3 · 图例按阶段写短字', () => {
  it('定门槛 / 取步长 / 连盘口', () => {
    expect(orderFlowLoadingText('threshold')).toBe('主力 定门槛…')
    expect(orderFlowLoadingText('step')).toBe('主力 取步长…')
    expect(orderFlowLoadingText('connect')).toBe('主力 连盘口…')
    expect(orderFlowLoadingText(undefined)).toBe('主力 连盘口…')
  })
  it('快照带着阶段交给图', () => {
    const snap = toChartSnapshot('XAUUSDT', { phase: 'loading', orders: [], asOfMs: 1, thresholds: {}, venues: [] } as never, undefined, 'threshold')
    expect(snap.stage).toBe('threshold')
    expect(toChartSnapshot('XAUUSDT', { phase: 'loading', orders: [], asOfMs: 1, thresholds: {}, venues: [] } as never).stage).toBeUndefined()
  })
})

describe('A2 · 换走的那几只先留着', () => {
  class Fake implements Parkable {
    parked = 0; stopped = 0
    constructor(readonly name: string) {}
    park(): void { this.parked++ }
    stop(): void { this.stopped++ }
  }

  it('默认留 2 只、3 分钟', () => {
    expect(KEEP_LIMIT).toBe(2)
    expect(KEEP_TTL_MS).toBe(180_000)
  })

  it('留着的 park 一次；换回来 take 交出、不再归它管', () => {
    const k = new FeedKeeper<Fake>()
    const a = new Fake('a')
    k.park('A', a)
    expect(a.parked).toBe(1)
    expect(k.has('A')).toBe(true)
    expect(k.take('A')).toBe(a)
    expect(k.take('A')).toBeNull()
    expect(a.stopped).toBe(0)
    k.clear()
  })

  it('超上限停掉最早留下的那只，并通知调用方清附带状态', () => {
    const dropped: string[] = []
    const k = new FeedKeeper<Fake>({ onDrop: (_f, key) => dropped.push(key) })
    const a = new Fake('a'), b = new Fake('b'), c = new Fake('c')
    k.park('A', a); k.park('B', b); k.park('C', c)
    expect(k.keys()).toEqual(['B', 'C'])
    expect(a.stopped).toBe(1)
    expect(dropped).toEqual(['A'])
    k.clear()
    expect(b.stopped + c.stopped).toBe(2)
    expect(k.size).toBe(0)
  })

  it('到点自己停（不用等下一次换品种）', () => {
    vi.useFakeTimers()
    let now = 0
    const k = new FeedKeeper<Fake>({ ttlMs: 1000, now: () => now })
    const a = new Fake('a')
    k.park('A', a)
    now = 999; vi.advanceTimersByTime(999)
    expect(a.stopped).toBe(0)
    now = 1010; vi.advanceTimersByTime(20)
    expect(a.stopped).toBe(1)
    expect(k.size).toBe(0)
  })

  it('过期的 take 不到', () => {
    let now = 0
    const k = new FeedKeeper<Fake>({ ttlMs: 1000, now: () => now })
    const a = new Fake('a')
    k.park('A', a)
    now = 1000
    expect(k.take('A')).toBeNull()
    expect(a.stopped).toBe(1)
  })

  it('同一个键又留一只：旧的停掉', () => {
    const k = new FeedKeeper<Fake>()
    const a = new Fake('a'), a2 = new Fake('a2')
    k.park('A', a); k.park('A', a2)
    expect(a.stopped).toBe(1)
    expect(k.take('A')).toBe(a2)
    k.clear()
  })

  it('上限 0：不留，直接停', () => {
    const k = new FeedKeeper<Fake>({ limit: 0 })
    const a = new Fake('a')
    k.park('A', a)
    expect(a.stopped).toBe(1)
    expect(k.size).toBe(0)
  })
})
