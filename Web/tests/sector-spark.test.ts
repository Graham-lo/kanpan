/* 板块迷你走势的取数（sectors/spark.ts）：服务端小时收盘优先、按 200 只分批、不通退回直连且在 sessionStorage 留几分钟 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const klinesMock = vi.fn()
vi.mock('../src/market', () => ({ klines: (...a: unknown[]) => klinesMock(...a) }))

const { wantSparks, stopSparks, resetSparks, boardPath, BATCH, TTL_MS } = await import('../src/sectors/spark')

const HOUR = 3_600_000
const lastHour = (): number => Math.floor(Date.now() / HOUR) * HOUR
/** 最近 n 根已收盘小时的收盘（从 base 起每小时 +1%） */
const rows = (n: number, base = 100): [number, number][] => Array.from({ length: n }, (_, i) => [lastHour() - (n - i) * HOUR, base * (1 + i / 100)])
const flush = async (): Promise<void> => { for (let i = 0; i < 20; i++) await new Promise(r => setTimeout(r, 0)) }

function memStorage(): Storage {
  const m = new Map<string, string>()
  return {
    get length() { return m.size }, clear: () => m.clear(), key: i => [...m.keys()][i] ?? null,
    getItem: k => m.get(k) ?? null, setItem: (k, v) => { m.set(k, String(v)) }, removeItem: k => { m.delete(k) },
  }
}

let fetchMock: ReturnType<typeof vi.fn>
beforeEach(() => {
  resetSparks()
  klinesMock.mockReset()
  fetchMock = vi.fn()
  vi.stubGlobal('fetch', fetchMock)
  vi.stubGlobal('sessionStorage', memStorage())
})
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers() })

const okJSON = (body: unknown) => ({ ok: true, status: 200, json: async () => body })
const status = (s: number) => ({ ok: false, status: s, json: async () => ({ error: 'nope' }) })
/** 服务端：请求里的每只都给 30 根，除了 omit 里的 */
function serverWith(omit: string[] = []) {
  return async (url: string) => {
    const syms = new URL(url, 'http://x').searchParams.get('symbols')!.split(',')
    return okJSON({ asOf: Date.now(), hours: 170, series: Object.fromEntries(syms.filter(k => !omit.includes(k)).map(k => [k, rows(30)])) })
  }
}

describe('服务端小时收盘', () => {
  it('成功：一次同源请求取齐，不打币安；板块走势画得出', async () => {
    fetchMock.mockImplementation(serverWith())
    const ready = vi.fn()
    wantSparks(['BTCUSDT', 'ETHUSDT', 'BTCUSDT'], ready)
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const url = String(fetchMock.mock.calls[0][0])
    expect(url).toMatch(/\/v1\/market\/hourly-closes\?symbols=BTCUSDT,ETHUSDT$/)
    expect(klinesMock).not.toHaveBeenCalled()
    await new Promise(r => setTimeout(r, 150))
    expect(ready).toHaveBeenCalled()
    const p = boardPath(['BTCUSDT', 'ETHUSDT'], 'today', '')
    expect(p).not.toBeNull()
    expect(p![p!.length - 1]).toBeGreaterThan(0)
  })

  it('五分钟内不重取，过了 max-age 再取', async () => {
    fetchMock.mockImplementation(serverWith())
    wantSparks(['BTCUSDT'], () => {})
    await flush()
    wantSparks(['BTCUSDT'], () => {})
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const now = Date.now()
    vi.spyOn(Date, 'now').mockReturnValue(now + TTL_MS + 1)
    wantSparks(['BTCUSDT'], () => {})
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('分批：450 只拆成 200 + 200 + 50，全部都取（不再有 180 的上限）', async () => {
    fetchMock.mockImplementation(serverWith())
    const syms = Array.from({ length: 450 }, (_, i) => `S${i}USDT`)
    wantSparks(syms, () => {})
    await flush()
    expect(BATCH).toBe(200)
    const sizes = fetchMock.mock.calls.map(c => new URL(String(c[0]), 'http://x').searchParams.get('symbols')!.split(',').length)
    expect(sizes).toEqual([200, 200, 50])
    expect(klinesMock).not.toHaveBeenCalled()
    expect(boardPath([syms[449]], 'today', '')).not.toBeNull()
  })

  it('服务端省略的品种（它那里没数）不打币安，板块由其余成员出中位数', async () => {
    fetchMock.mockImplementation(serverWith(['NEWUSDT']))
    wantSparks(['BTCUSDT', 'NEWUSDT'], () => {})
    await flush()
    expect(klinesMock).not.toHaveBeenCalled()
    expect(boardPath(['NEWUSDT'], 'today', '')).toBeNull()
    expect(boardPath(['BTCUSDT', 'NEWUSDT'], 'today', '')).not.toBeNull()
  })

  it('中文名合约不发给服务端，走直连', async () => {
    fetchMock.mockImplementation(serverWith())
    klinesMock.mockResolvedValue({ ok: true, bars: rows(30).map(([t, c]) => ({ t, o: c, h: c, l: c, c, v: 1 })) })
    wantSparks(['BTCUSDT', '币安人生USDT'], () => {})
    await flush()
    expect(String(fetchMock.mock.calls[0][0])).toMatch(/symbols=BTCUSDT$/)
    expect(klinesMock).toHaveBeenCalledTimes(1)
    expect(klinesMock.mock.calls[0][0]).toBe('币安人生USDT')
  })
})

describe('退回直连', () => {
  const bars = () => rows(30).map(([t, c]) => ({ t, o: c, h: c, l: c, c, v: 1 }))

  it('404（服务端还没上这个接口）：退回直连币安、走后台预算；取到的在 sessionStorage 留几分钟，刷新页面不重打', async () => {
    fetchMock.mockResolvedValue(status(404))
    klinesMock.mockImplementation(async () => ({ ok: true, bars: bars() }))
    wantSparks(['BTCUSDT', 'ETHUSDT'], () => {})
    await flush()
    expect(klinesMock).toHaveBeenCalledTimes(2)
    // 1 小时、170 根、不带持仓量、后台
    expect(klinesMock.mock.calls[0].slice(1, 6)).toEqual(['1h', undefined, 170, false, true])
    expect(boardPath(['BTCUSDT'], 'today', '')).not.toBeNull()
    await new Promise(r => setTimeout(r, 600))
    expect(sessionStorage.getItem('hkline-web-spark-v1')).toContain('BTCUSDT')
    // 「刷新页面」：进程内清空，sessionStorage 还在
    resetSparks(); klinesMock.mockClear(); fetchMock.mockClear()
    wantSparks(['BTCUSDT', 'ETHUSDT'], () => {})
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()
    expect(klinesMock).not.toHaveBeenCalled()
    expect(boardPath(['BTCUSDT'], 'today', '')).not.toBeNull()
  })

  it('5xx 与网络错也退回直连；服务端不通的这几分钟里不再每轮先撞一次', async () => {
    fetchMock.mockResolvedValueOnce(status(502)).mockRejectedValueOnce(new Error('offline'))
    klinesMock.mockImplementation(async () => ({ ok: true, bars: bars() }))
    wantSparks(['AUSDT'], () => {})
    await flush()
    expect(klinesMock).toHaveBeenCalledTimes(1)
    wantSparks(['AUSDT', 'BUSDT'], () => {})
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(klinesMock).toHaveBeenCalledTimes(2)
  })

  it('边渲染边要：第一趟在路上时再要的并进下一趟；服务端 404 时只撞一次，后面的直接走直连', async () => {
    let answer: (v: unknown) => void = () => {}
    fetchMock.mockImplementationOnce(() => new Promise(r => { answer = r }))
    klinesMock.mockImplementation(async () => ({ ok: true, bars: bars() }))
    wantSparks(['AUSDT'], () => {})
    wantSparks(['AUSDT', 'BUSDT'], () => {})
    wantSparks(['AUSDT', 'BUSDT', 'CUSDT'], () => {})
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    answer(status(404))
    await flush()
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(klinesMock.mock.calls.map(c => c[0]).sort()).toEqual(['AUSDT', 'BUSDT', 'CUSDT'])
  })

  it('服务端好的时候，在路上时攒下的并成一个请求', async () => {
    let answer: () => void = () => {}
    const serve = serverWith()
    fetchMock.mockImplementationOnce((u: string) => new Promise(r => { answer = () => r(serve(u)) })).mockImplementation(serve)
    wantSparks(['AUSDT'], () => {})
    wantSparks(['AUSDT', 'BUSDT'], () => {})
    wantSparks(['AUSDT', 'BUSDT', 'CUSDT'], () => {})
    await flush()
    answer()
    await flush()
    expect(fetchMock.mock.calls.map(c => new URL(String(c[0]), 'http://x').searchParams.get('symbols'))).toEqual(['AUSDT', 'BUSDT,CUSDT'])
    expect(klinesMock).not.toHaveBeenCalled()
  })

  it('离开板块页：直连队列清空，还没发的不发', async () => {
    fetchMock.mockResolvedValue(status(404))
    let release: () => void = () => {}
    klinesMock.mockImplementation(() => new Promise(r => { release = () => r({ ok: true, bars: bars() }) }))
    wantSparks(Array.from({ length: 20 }, (_, i) => `Q${i}USDT`), () => {})
    await flush()
    expect(klinesMock).toHaveBeenCalledTimes(6)   // 同时最多 6 个在路上
    stopSparks()
    release()
    await flush()
    expect(klinesMock).toHaveBeenCalledTimes(6)
  })
})
