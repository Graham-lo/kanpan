import { afterEach, describe, expect, it, vi } from 'vitest'
import { COOL_418_MS, COOL_429_MS, Limiter, RateLimited, Superseded, admit, coolingFor, familyOf, isRateLimit, noteStatus, resetLimits, weightOf, type LimitSnap } from '../src/market/limit'
import { j } from '../src/market/rest'
import { S } from '../src/market/state'

const FAPI = 'https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT'

afterEach(() => { resetLimits(); vi.unstubAllGlobals() })

describe('交易所限流闸', () => {
  it('429 关 60 秒、418 关 5 分钟，按主机分，不连累别家', () => {
    noteStatus(FAPI, 429, null, 1000)
    expect(coolingFor(FAPI, 1000)).toBe(COOL_429_MS)
    expect(coolingFor('https://fapi.binance.com/fapi/v1/depth?symbol=ETHUSDT', 1000)).toBe(COOL_429_MS)
    expect(coolingFor('https://dapi.binance.com/dapi/v1/depth', 1000)).toBe(0)
    expect(coolingFor('https://www.okx.com/api/v5/market/candles', 1000)).toBe(0)
    expect(coolingFor(FAPI, 1000 + COOL_429_MS)).toBe(0)
    noteStatus('https://data-api.binance.vision/api/v3/depth', 418, '', 0)
    expect(coolingFor('https://data-api.binance.vision/api/v3/depth', 0)).toBe(COOL_418_MS)
  })
  it('读得到 Retry-After 就按它；200 / 500 不关', () => {
    noteStatus(FAPI, 429, '7', 0)
    expect(coolingFor(FAPI, 0)).toBe(7000)
    resetLimits()
    noteStatus(FAPI, 500, null, 0); noteStatus(FAPI, 200, null, 0)
    expect(coolingFor(FAPI, 0)).toBe(0)
  })
  it('j()：回一次 429 之后，冷却期内同主机的请求不再发出去', async () => {
    const f = vi.fn(async () => new Response('', { status: 429 }))
    vi.stubGlobal('fetch', f)
    await expect(j(FAPI)).rejects.toThrow(/^429/)
    for (let k = 0; k < 20; k++) await expect(j(`${FAPI}&k=${k}`)).rejects.toBeInstanceOf(RateLimited)
    expect(f).toHaveBeenCalledTimes(1)
    const e = await j(FAPI).catch(x => x)
    expect(isRateLimit(e)).toBe(true)
    expect(isRateLimit(new Error('500 x'))).toBe(false)
  })
})

const F = 'https://fapi.binance.com'
const K1500 = `${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=1500` // 权重 10
describe('限流闸 · 预算、再犯、共用一份（2026-09-29 A 路压测）', () => {
  it('按官方权重表记：K 线按根数分档、不带代号的 24h 行情 40、资金费 10；不是币安的记 0', () => {
    expect(weightOf(K1500)).toBe(10)
    expect(weightOf(`${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=1000`)).toBe(5)
    expect(weightOf(`${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1h&limit=170`)).toBe(2)
    expect(weightOf(`${F}/fapi/v1/klines?symbol=BTCUSDT&interval=1d&limit=16`)).toBe(1)
    expect(weightOf(`${F}/fapi/v1/ticker/24hr`)).toBe(40)
    expect(weightOf(`${F}/fapi/v1/ticker/24hr?symbol=BTCUSDT`)).toBe(1)
    expect(weightOf(`${F}/fapi/v1/premiumIndex`)).toBe(10)
    expect(weightOf(`${F}/fapi/v1/depth?symbol=BTCUSDT&limit=1000`)).toBe(20)
    expect(weightOf('https://dapi.binance.com/dapi/v1/depth?symbol=BTCUSD_PERP&limit=1000')).toBe(20)
    expect(weightOf('https://data-api.binance.vision/api/v3/depth?symbol=BTCUSDT&limit=5000')).toBe(250)
    expect(familyOf('https://www.okx.com/api/v5/market/books?instId=BTC-USDT')).toBeNull()
    expect(familyOf('/v1/market/meta?symbols=BTC')).toBeNull()
    expect(weightOf('https://www.okx.com/api/v5/market/books')).toBe(0)
  })

  it('一分钟超过预算就排队：等到最早的几笔滚出窗口；别家不管', () => {
    const g = new Limiter({ fapi: 100, dapi: 100, spot: 100 })
    for (let i = 0; i < 10; i++) expect(g.take(K1500, 1000 + i)).toBe(0)
    expect(g.usedOf('fapi', 1010)).toBe(100)
    expect(g.take(K1500, 2000)).toBe(1000 + 60_000 - 2000)
    expect(g.take('https://dapi.binance.com/dapi/v1/depth?symbol=BTCUSD_PERP', 2000)).toBe(0)
    expect(g.take(K1500, 61_000)).toBe(0)
    expect(g.take('https://www.okx.com/api/v5/x', 61_000)).toBe(0)
  })

  it('后台请求只用预算的一截：小走势吃到 60% 就排队，图表自己的 K 线还有 40% 能直接发', () => {
    const g = new Limiter({ fapi: 100, dapi: 100, spot: 100 })
    const spark = `${F}/fapi/v1/klines?symbol=ETHUSDT&interval=1h&limit=170` // 权重 2
    for (let i = 0; i < 30; i++) expect(g.take(spark, 1000 + i, 0.6)).toBe(0)
    expect(g.usedOf('fapi', 1030)).toBe(60)
    expect(g.take(spark, 1030, 0.6)).toBeGreaterThan(0)
    for (let i = 0; i < 4; i++) expect(g.take(K1500, 1031 + i)).toBe(0)
    expect(g.take(K1500, 1040)).toBeGreaterThan(0)
  })

  it('冷却一结束就再犯的翻倍；冷却期间才回来的 429 只续一轮不翻倍；冷却过后成功一次清零；418 从 5 分钟起', () => {
    const g = new Limiter()
    g.noteStatus(K1500, 429, null, 0)
    expect(g.coolingFor(K1500, 1000)).toBe(59_000)
    g.noteStatus(K1500, 429, null, 2000)
    expect(g.coolingFor(K1500, 2000)).toBe(60_000)
    g.noteStatus(K1500, 429, null, 70_000)
    expect(g.coolingFor(K1500, 70_000)).toBe(120_000)
    g.noteStatus(K1500, 200, null, 100_000) // 冷却前发出去、冷却中才回来的成功不清零
    g.noteStatus(K1500, 429, null, 190_000)
    expect(g.coolingFor(K1500, 190_000)).toBe(240_000)
    g.noteStatus(K1500, 200, null, 500_000)
    g.noteStatus(K1500, 429, null, 600_000)
    expect(g.coolingFor(K1500, 600_000)).toBe(COOL_429_MS)
    g.noteStatus(K1500, 418, null, 700_000)
    expect(g.coolingFor(K1500, 700_000)).toBe(COOL_418_MS * 2)
  })

  it('共用一份：刷新后的新页、另一个标签页看得见上一页记的权重与冷却；盘上写坏了当没记过', () => {
    let disk: string | null = null
    const store = { load: () => (disk ? JSON.parse(disk) : null), save: (x: LimitSnap) => { disk = JSON.stringify(x) } }
    const B = { fapi: 100, dapi: 100, spot: 100 }
    const a = new Limiter(B, store)
    for (let i = 0; i < 10; i++) expect(a.take(K1500, 1000 + i)).toBe(0)
    const b = new Limiter(B, store)
    expect(b.usedOf('fapi', 2000)).toBe(100)
    expect(b.take(K1500, 2000)).toBeGreaterThan(0)
    b.noteStatus(K1500, 429, null, 3000)
    expect(a.coolingFor(`${F}/fapi/v1/premiumIndex`, 3000)).toBe(60_000)
    expect(new Limiter(B, store).take(K1500, 64_000)).toBe(0)
    disk = '{"used":{"fapi":[["x",1],null]},"cool":{"fapi.binance.com":{"until":"a"}}}'
    const c = new Limiter(B, store)
    expect(c.coolingFor(K1500, 70_000)).toBe(0)
    expect(c.take(K1500, 70_000)).toBe(0)
    disk = '"坏了"'
    expect(new Limiter(B, store).take(K1500, 80_000)).toBe(0)
  })
})

describe('限流闸 · 排队中作废的不发（2026-09-29 A 路压测：高频切换后预算被作废的 K 线占满）', () => {
  it('预算满了在排队：要的人说不要了就抛 Superseded，不记账；还要的等窗口滚出去照发', async () => {
    vi.useFakeTimers()
    try {
      vi.setSystemTime(1_000_000)
      for (let i = 0; i < 120; i++) await admit(`${K1500}&i=${i}`) // 120 × 10 = 1200，fapi 这一分钟满了
      let live = true
      const gone = admit(`${K1500}&x=gone`, false, () => live).then(() => 'sent', e => e)
      const kept = admit(`${K1500}&x=kept`, false, () => true).then(() => 'sent', e => e)
      await vi.advanceTimersByTimeAsync(3000)
      live = false
      await vi.advanceTimersByTimeAsync(1500)
      expect(await gone).toBeInstanceOf(Superseded)
      await vi.advanceTimersByTimeAsync(60_000)
      expect(await kept).toBe('sent')
      // 作废的那笔没进账：前 120 笔滚出窗口以后，账上只有 kept 这一笔（10）
      const lim = (globalThis as unknown as { __limit: () => { fapi: number } }).__limit
      expect(lim().fapi).toBe(10)
    } finally { vi.useRealTimers() }
  })

  it('网关线路：合约 REST 每个浏览器只用服务端共用额度里的 800（直连仍是 1200）', async () => {
    vi.useFakeTimers()
    const was = S.route
    try {
      vi.setSystemTime(2_000_000)
      resetLimits()
      S.route = 'gateway'
      for (let i = 0; i < 80; i++) await admit(`${K1500}&g=${i}`) // 80 × 10 = 800
      let sent = false
      const next = admit(`${K1500}&g=over`).then(() => { sent = true })
      await vi.advanceTimersByTimeAsync(2000)
      expect(sent).toBe(false) // 网关这一截满了，排队而不是打出去吃服务端的 429
      S.route = 'direct'
      await vi.advanceTimersByTimeAsync(5000)
      expect(sent).toBe(true) // 直连照旧有 1200
      await next
    } finally { S.route = was; resetLimits(); vi.useRealTimers() }
  })
})

describe('限流闸 · 直连与网关各记一道（Web 深度审查 C 线 2026-10-05）', () => {
  it('直连被封（418）不连累网关：切到网关立刻能取；网关回 429 也不把直连冷却掉', async () => {
    const was = S.route
    try {
      const f = vi.fn(async () => new Response('[]', { status: 200 }))
      vi.stubGlobal('fetch', f)
      S.route = 'direct'
      noteStatus(FAPI, 418, null)
      await expect(j(FAPI)).rejects.toBeInstanceOf(RateLimited)
      expect(f).toHaveBeenCalledTimes(0)
      S.route = 'gateway'
      await expect(j(FAPI)).resolves.toEqual([])
      expect(f).toHaveBeenCalledTimes(1)
      expect(String((f.mock.calls[0] as unknown[])[0])).toContain('/v1/market/raw/fapi/v1/klines')
      resetLimits()
      f.mockImplementation(async () => new Response('', { status: 429, headers: { 'Retry-After': '5' } }))
      await expect(j(FAPI)).rejects.toThrow(/^429/)
      expect(coolingFor(FAPI)).toBeGreaterThan(4000) // 网关这一道按 Retry-After 冷却
      S.route = 'direct'
      expect(coolingFor(FAPI)).toBe(0)                // 直连那一道不受影响
    } finally { S.route = was }
  })

  it('预算两道分开：直连 1200 记满了，网关那一道照样有 800；Limiter 层直接按 gw 记', () => {
    const g = new Limiter()
    for (let i = 0; i < 120; i++) expect(g.take(`${K1500}&i=${i}`, 1000)).toBe(0)
    expect(g.take(K1500, 1000)).toBeGreaterThan(0)
    for (let i = 0; i < 80; i++) expect(g.take(`${K1500}&g=${i}`, 1000, 1, true)).toBe(0)
    expect(g.take(K1500, 1000, 1, true)).toBeGreaterThan(0)
    expect(g.usedOf('fapi', 1000)).toBe(1200)
    expect(g.usedOf('fapi', 1000, true)).toBe(800)
  })

  it('老格式的落盘（只有 fapi / 主机名）照读成直连那一道；网关那一道单独落盘', () => {
    let disk: string | null = JSON.stringify({ cool: { 'fapi.binance.com': { until: 90_000, strikes: 1 } }, used: { fapi: [[1000, 50]] } })
    const store = { load: () => (disk ? JSON.parse(disk) : null), save: (x: LimitSnap) => { disk = JSON.stringify(x) }, raw: () => disk }
    const g = new Limiter(undefined, store)
    expect(g.coolingFor(K1500, 30_000)).toBe(60_000)
    expect(g.coolingFor(K1500, 30_000, true)).toBe(0)
    expect(g.usedOf('fapi', 30_000)).toBe(50)
    expect(g.take(K1500, 30_000, 1, true)).toBe(0)
    expect(JSON.parse(disk!).used['fapi@gw']).toEqual([[30_000, 10]])
    expect(new Limiter(undefined, store).usedOf('fapi', 30_000, true)).toBe(10)
  })

  it('盘上原文没变就不再解析：一次 admit 原来解析两遍整本账，现在别的页没动过就一遍都不解析', () => {
    let disk: string | null = null
    let parses = 0
    const store = {
      load: () => { parses++; return disk ? JSON.parse(disk) : null },
      save: (x: LimitSnap) => { disk = JSON.stringify(x) },
      raw: () => disk,
    }
    const g = new Limiter(undefined, store)
    const spy = vi.spyOn(JSON, 'parse')
    try {
      g.take(K1500, 1000)
      spy.mockClear()
      for (let i = 0; i < 50; i++) { g.coolingFor(K1500, 2000 + i); g.take(`${K1500}&i=${i}`, 2000 + i) }
      expect(spy).toHaveBeenCalledTimes(0)
      expect(parses).toBe(0)
      // 别的标签页写了一笔：原文变了，下一次读回来
      const other = new Limiter(undefined, store)
      other.noteStatus(K1500, 429, null, 3000)
      expect(g.coolingFor(K1500, 3000)).toBe(COOL_429_MS)
    } finally { spy.mockRestore() }
  })
})
