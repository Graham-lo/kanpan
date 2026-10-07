/* 2026-10-07 P1-1 / P2-3 · 非当前格首次少取、限流闸排队作废即放弃、持仓量只给露着副图的格子取
 *   P1-1 根因：1↔16 每切一次，15 格各重取 1500 根（权重 10），20 轮 300 次请求 ≈ 权重 3000，网关那道一分钟只有 800，
 *          后几轮全在限流闸里排队，格子一片空白、没有任何提示。（刚看过的整段复用见 market/klineCache.ts 与 tests/kline-cache.test.ts）
 *   P2-3 根因：attachOI 不带 alive、也不看这一格是否露着持仓量副图；限流重取只认 token、不认格子死活；
 *          admit 排队时睡满一觉（最长 1 秒 / 5 秒）才知道自己已经作废。 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { SIDE_LIMIT, attachOI } from '../src/market/rest'
import { Superseded, admit, queuedCount, resetLimits, wakeQueued, weightOf } from '../src/market/limit'

const H = 3_600_000
const barsAt = (lastT: number, n: number): Bar[] => Array.from({ length: n }, (_, i) => ({ t: lastT - (n - 1 - i) * H, o: 1, h: 2, l: 0.5, c: 1.5, v: 10 }))
const K1500 = 'https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=1500'

afterEach(() => { resetLimits(); vi.useRealTimers(); vi.unstubAllGlobals() })

describe('多格布局首次取数（rest.ts SIDE_LIMIT）', () => {
  it(`非当前格首次只取 ${SIDE_LIMIT} 根：权重 2（1500 根是 10）`, () => {
    expect(weightOf(K1500.replace('limit=1500', `limit=${SIDE_LIMIT}`))).toBe(2)
    expect(weightOf(K1500)).toBe(10)
  })
})

describe('限流闸排队：作废就立刻放弃（limit.ts admit）', () => {
  async function fill(): Promise<void> {
    vi.useFakeTimers()
    vi.setSystemTime(1_000_000)
    for (let i = 0; i < 120; i++) await admit(`${K1500}&i=${i}`) // 120 × 10 = 1200，这一分钟满了
  }

  it('要排队时 onWait 回调一次（格子上写「排队取数…」）', async () => {
    await fill()
    const waits: number[] = []
    const p = admit(`${K1500}&x=1`, false, () => true, ms => waits.push(ms)).then(() => 'sent')
    await vi.advanceTimersByTimeAsync(0)
    expect(waits.length).toBe(1)
    expect(waits[0]).toBeGreaterThan(0)
    await vi.advanceTimersByTimeAsync(61_000)
    expect(await p).toBe('sent')
  })

  it('wakeQueued：排队中的马上醒来问 alive，不要了当场 Superseded，不睡满那一觉', async () => {
    await fill()
    let live = true
    let out: unknown = 'pending'
    const p = admit(`${K1500}&x=gone`, false, () => live).then(() => 'sent', e => e).then(r => { out = r })
    await vi.advanceTimersByTimeAsync(0)
    expect(queuedCount()).toBe(1)
    live = false
    wakeQueued()
    await vi.advanceTimersByTimeAsync(0)                      // 不推进时钟
    expect(out).toBeInstanceOf(Superseded)
    expect(queuedCount()).toBe(0)
    await p
  })

  it('睡醒那一刻 alive 已经是 false：直接放弃，不再拿预算、不再睡下一觉', async () => {
    await fill()
    let live = true, asks = 0
    const p = admit(`${K1500}&x=gone`, false, () => { asks++; return live }).then(() => 'sent', e => e)
    await vi.advanceTimersByTimeAsync(0)
    live = false
    await vi.advanceTimersByTimeAsync(1000)
    expect(await p).toBeInstanceOf(Superseded)
    expect(queuedCount()).toBe(0)
    expect(asks).toBe(2)                                       // 进门问一次、醒来问一次
  })
})

describe('持仓量：带 alive 排队，不要了就不发（rest.ts attachOI）', () => {
  it('排队期间格子没了 / 副图被收起：不发 openInterestHist，返回 false 让下次再取', async () => {
    vi.useFakeTimers()
    vi.setSystemTime(1_000_000)
    const fetchSpy = vi.fn(async () => new Response('[]', { status: 200 }))
    vi.stubGlobal('fetch', fetchSpy)
    for (let i = 0; i < 120; i++) await admit(`${K1500}&i=${i}`)
    // openInterestHist 在 fapi 那一族之外（futures/data），先把它这一族也占满
    const OIH = 'https://fapi.binance.com/futures/data/openInterestHist?symbol=BTCUSDT&period=1h&limit=500'
    let n = 0
    for (; n < 2000; n++) { const t = admit(`${OIH}&f=${n}`).then(() => true); await vi.advanceTimersByTimeAsync(0); if (queuedCount()) break; await t }
    let shown = true
    const r = attachOI('BTCUSDT', '1h', barsAt(100 * H, 5), () => shown)
    await vi.advanceTimersByTimeAsync(0)
    shown = false
    wakeQueued()
    await vi.advanceTimersByTimeAsync(0)
    expect(await r).toBe(false)
    expect(fetchSpy).not.toHaveBeenCalled()
  })

  it('不支持的周期（1m）不取，算取过了', async () => {
    const fetchSpy = vi.fn()
    vi.stubGlobal('fetch', fetchSpy)
    expect(await attachOI('BTCUSDT', '1m', barsAt(H, 3))).toBe(true)
    expect(fetchSpy).not.toHaveBeenCalled()
  })
})
