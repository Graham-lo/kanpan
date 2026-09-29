/* 手机网页版壳层：品种表刷新节奏（m/app/universeRefresh）与强制重拉口子（m/pages/_streams.refreshUniverse） */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const loads: { ok: boolean; symbols: string[] }[] = []
let calls = 0
vi.mock('../src/market/rest', async orig => {
  const real = await orig<typeof import('../src/market/rest')>()
  return {
    ...real,
    loadUniverse: vi.fn(async () => {
      // 每次按当前的模块表取 state（resetModules 之后是新的一份）
      const { S, emit } = await import('../src/market/state')
      calls++
      const r = loads.shift() ?? { ok: true, symbols: [...S.symbols.keys()] }
      if (r.ok) { S.symbols = new Map(r.symbols.map(s => [s, { symbol: s } as never])); S.live = true; S.error = '' }
      else { S.live = false; S.error = 'net' }
      emit({ type: 'universe' })
      return S.symbols
    }),
  }
})

const H = 3600_000
beforeEach(async () => {
  vi.resetModules(); loads.length = 0; calls = 0
})
afterEach(() => { vi.unstubAllGlobals() })

async function setup(initial = ['BTCUSDT', 'OLDUSDT']) {
  const market = await import('../src/market')
  const streams = await import('../src/m/pages/_streams')
  const { startUniverseRefresh } = await import('../src/m/app/universeRefresh')
  loads.push({ ok: true, symbols: initial })
  await streams.ensureUniverse()
  let t = 1_000_000
  let fg: () => void = () => {}
  let tick: () => void = () => {}
  let vis = true
  const events: boolean[] = []
  market.on(e => { if (e.type === 'universe') events.push(market.S.live === true) })
  const r = startUniverseRefresh({ onForeground: fn => { fg = fn }, now: () => t, visible: () => vis, every: fn => { tick = fn } })
  return {
    market, streams, r, events,
    advance: (ms: number) => { t += ms },
    foreground: async () => { fg(); await new Promise(res => setTimeout(res, 0)) },
    tick: async () => { tick(); await new Promise(res => setTimeout(res, 0)) },
    hide: () => { vis = false },
  }
}

describe('品种表刷新节奏（加到主屏的 PWA 常驻几天）', () => {
  it('回前台：距上次拉到不到 30 分钟不拉，超过就重拉；新上线的出现、下架的消失，并发 universe', async () => {
    const x = await setup()
    expect(calls).toBe(1)
    x.advance(20 * 60_000); await x.foreground()
    expect(calls).toBe(1)
    x.advance(15 * 60_000)
    loads.push({ ok: true, symbols: ['BTCUSDT', 'NEWUSDT'] })
    await x.foreground()
    expect(calls).toBe(2)
    expect([...x.market.S.symbols.keys()]).toEqual(['BTCUSDT', 'NEWUSDT'])
    expect(x.events.at(-1)).toBe(true)
  })

  it('前台常开：每 6 小时重拉一次；页面在后台时不拉（回前台那一下兜住）', async () => {
    const x = await setup()
    x.advance(6 * H); await x.tick()
    expect(calls).toBe(2)
    x.hide(); x.advance(6 * H); await x.tick()
    expect(calls).toBe(2)
  })

  it('手里有表时重拉失败：旧表不动、在线状态还原（价格不置灰、自选不误判下架），再发一次 universe 让各页按原状态重画', async () => {
    const x = await setup()
    x.advance(31 * 60_000)
    loads.push({ ok: false, symbols: [] })
    await x.foreground()
    expect(calls).toBe(2)
    expect([...x.market.S.symbols.keys()]).toEqual(['BTCUSDT', 'OLDUSDT'])
    expect(x.market.S.live).toBe(true)
    expect(x.market.S.error).toBe('')
    expect(x.events.at(-1)).toBe(true)
    // 失败不算「拉到过」：下一次回前台还会再试
    loads.push({ ok: true, symbols: ['BTCUSDT'] })
    await x.foreground()
    expect(calls).toBe(3)
  })

  it('强制重拉不看缓存（ensureUniverse 表在手就直接返回），同时来两次只拉一回', async () => {
    const x = await setup()
    await x.streams.ensureUniverse()
    expect(calls).toBe(1)
    await Promise.all([x.streams.refreshUniverse(), x.streams.refreshUniverse()])
    expect(calls).toBe(2)
  })
})
