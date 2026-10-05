// 深度审查 Web F 线 F8：手机行情页顶栏横滑连扫，划过去的品种的非首屏请求不再排在限流队列里干等。
// 现场复现见 scripts/f-perf.mjs scan-m 段（100 次横滑：限流排队等待 131 → 个位数）。
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { detailOf, fetchDetail } from '../src/market'
import { Superseded, resetLimits } from '../src/market/limit'
import { ExternalFeed } from '../src/m/chart/external.source'
import { synthSeries } from './m-chart-fixtures'
import { S } from '../src/market/state'
import { Settle } from '../src/market/settle'

const okJson = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })

describe('F8 划过去的品种：详情五个慢数作废后不发、不占「一分钟内取过」', () => {
  let calls: string[] = []
  beforeEach(() => {
    resetLimits(); calls = []
    vi.stubGlobal('fetch', vi.fn(async (u: string) => {
      calls.push(String(u))
      if (String(u).includes('/fapi/v1/openInterest')) return okJson({ openInterest: '10' })
      if (String(u).includes('openInterestHist')) return okJson([{ sumOpenInterestValue: '100' }, { sumOpenInterestValue: '110' }])
      if (String(u).includes('takerlongshortRatio')) return okJson([{ buySellRatio: '1.2' }])
      return okJson([{ longShortRatio: '0.9' }])
    }))
  })
  afterEach(() => { vi.unstubAllGlobals() })

  it('alive 已经说不要了：一笔都不发，缓存里不留这一分钟的空壳；回到这只照常取齐', async () => {
    S.symbols.set('F8AUSDT', { symbol: 'F8AUSDT', price: 2 } as never)
    await fetchDetail('F8AUSDT', () => false)
    expect(calls).toEqual([])
    expect(detailOf('F8AUSDT')).toBeUndefined() // 修前会留一个 t = 现在 的空详情，60 秒内回来不再取
    await fetchDetail('F8AUSDT', () => true)
    expect(calls).toHaveLength(5)
    const d = detailOf('F8AUSDT')!
    expect(d.oiValue).toBe(20)
    expect(d.oiChg).toBeCloseTo(10)
    expect(d.taker).toBe(1.2)
  })

  it('不传 alive 的老调用照旧（宽屏侧栏等）', async () => {
    await fetchDetail('F8BUSDT')
    expect(calls).toHaveLength(5)
  })
})

describe('F8 外部副图：feed 作废后，排着队的那页不再发', () => {
  afterEach(() => { vi.unstubAllGlobals() })

  it('换走了（dispose）之后才轮到发的那页抛 Superseded，网络上没有这一笔', async () => {
    resetLimits()
    const net = vi.fn(async () => okJson([]))
    vi.stubGlobal('fetch', net)
    let release!: () => void
    const gate = new Promise<void>(r => { release = r })
    let outcome: unknown = null
    const feed = new ExternalFeed('F8CUSDT', '1h', () => {}, async (_id, _s, _iv, _from, _to, _now, get) => {
      await gate
      outcome = await get!('https://fapi.binance.com/futures/data/openInterestHist?symbol=F8CUSDT').catch(e => e)
      return { points: [], complete: true }
    })
    const s = synthSeries(10, { interval: '1h', t0: Date.now() - 10 * 3_600_000, symbol: 'F8CUSDT' })
    feed.want(['OI'], s)
    feed.dispose()
    release()
    await vi.waitFor(() => expect(outcome).not.toBeNull())
    expect(outcome).toBeInstanceOf(Superseded)
    expect(net).not.toHaveBeenCalled()
  })
})

describe('F8 连扫只给停下的那只取：同一个键停稳后只做最后一次', () => {
  beforeEach(() => { vi.useFakeTimers() })
  afterEach(() => { vi.useRealTimers() })

  it('每 200 ms 划一只、划 20 只：划的过程中一次都不做，停下 500 ms 后只给最后那只做一次', () => {
    const st = new Settle(500)
    const done: string[] = []
    for (let i = 0; i < 20; i++) {
      st.noteSwitch()
      const sym = `S${i}`
      st.whenSettled('m-ext:1', () => done.push(sym))
      st.whenSettled('m-detail', () => done.push('d' + sym))
      vi.advanceTimersByTime(200)
    }
    expect(done).toEqual([])
    vi.advanceTimersByTime(300)
    expect(done.sort()).toEqual(['S19', 'dS19'])
  })
})
