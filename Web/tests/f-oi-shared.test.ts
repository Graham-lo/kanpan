// 深度审查 Web F 线 F11：PC 冷启动时详情块与自选宽列持仓额各取一次当前品种的未平仓量（同一秒、同一个请求）。
// 现场复现见 scripts/f-perf.mjs cold 段「重复」一栏（修前 2× /fapi/v1/openInterest?symbol=BTCUSDT）。
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { detailOf, fetchDetail, fetchOpenInterest } from '../src/market'
import { resetLimits } from '../src/market/limit'
import { S } from '../src/market/state'

const okJson = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })
const oiCalls = (calls: string[], sym: string) => calls.filter(u => u.includes('/fapi/v1/openInterest?') && u.includes(`symbol=${sym}`)).length

describe('F11 同一只的未平仓量：详情块与自选宽列共用一个请求', () => {
  let calls: string[] = []
  let fail = false
  beforeEach(() => {
    resetLimits(); calls = []; fail = false
    vi.stubGlobal('fetch', vi.fn(async (u: string) => {
      calls.push(String(u))
      if (String(u).includes('/fapi/v1/openInterest?')) return fail ? new Response('', { status: 500 }) : okJson({ openInterest: '10' })
      if (String(u).includes('openInterestHist')) return okJson([{ sumOpenInterestValue: '100' }, { sumOpenInterestValue: '110' }])
      if (String(u).includes('takerlongshortRatio')) return okJson([{ buySellRatio: '1.2' }])
      return okJson([{ longShortRatio: '0.9' }])
    }))
  })
  afterEach(() => { vi.unstubAllGlobals() })

  it('冷启动同一秒两边各要一次：网络上只有一笔，两边都拿到数', async () => {
    S.symbols.set('F11AUSDT', { symbol: 'F11AUSDT', price: 3 } as never)
    const [, raw] = await Promise.all([fetchDetail('F11AUSDT'), fetchOpenInterest('F11AUSDT')])
    expect(oiCalls(calls, 'F11AUSDT')).toBe(1) // 修前 2
    expect(raw).toBe('10')
    expect(detailOf('F11AUSDT')!.oiValue).toBe(30)
  })

  it('取到后 10 秒内再要直接用；过了 10 秒重新取', async () => {
    vi.useFakeTimers({ toFake: ['Date'] })
    try {
      await fetchOpenInterest('F11BUSDT')
      await fetchOpenInterest('F11BUSDT')
      expect(oiCalls(calls, 'F11BUSDT')).toBe(1)
      vi.setSystemTime(Date.now() + 11e3)
      await fetchOpenInterest('F11BUSDT')
      expect(oiCalls(calls, 'F11BUSDT')).toBe(2)
    } finally { vi.useRealTimers() }
  })

  it('带 alive 的（扫图时可能被作废）不给别人共用；失败的不留着，下一次照常取', async () => {
    await Promise.all([fetchOpenInterest('F11CUSDT', () => true), fetchOpenInterest('F11CUSDT')])
    expect(oiCalls(calls, 'F11CUSDT')).toBe(2)
    fail = true
    await expect(fetchOpenInterest('F11DUSDT')).rejects.toBeTruthy()
    fail = false
    await expect(fetchOpenInterest('F11DUSDT')).resolves.toBe('10')
    expect(oiCalls(calls, 'F11DUSDT')).toBe(2)
  })
})
