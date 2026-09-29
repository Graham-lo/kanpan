import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { makeConditionAlert, makeDrawingAlert, makePriceAlert } from '../src/alerts/shape'
import { OWNED, applyInto, captureInto, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const state = (): WebState => ({
  pinned: ['1h', '4h'],
  ind: { ma: true, ema: false, boll: false, vol: true, subs: [] },
  params: null,
  watch: { crypto: ['BTCUSDT'], us: [], com: [] },
  drawings: {},
  alerts: [],
})

/** 一台「网页」：页面状态 + 账本 + 引擎，接同一个假服务端 */
function browser(server: FakeServer, s = state()) {
  const store = new SyncStore(emptyArchive(), 'dev-' + Math.random(), () => server.now)
  const fp: Prints = {}
  let initial = true
  const engine = new Engine(store, server.transport(), OWNED, {
    capture: () => { if (!initial) captureInto(s, store, ctx, fp) },
    apply: () => { if (!initial) applyInto(s, store, ctx) },
  })
  return {
    s, store, engine, fp,
    async first(edited = { settings: 0, favorites: 0 }, override = false) {
      await engine.full()
      mergeFirst(s, store, ctx, edited, override)
      initial = false
      captureInto(s, store, ctx, fp)
      await engine.push()
    },
    async sync() { await engine.push(); await engine.pull(); await engine.push() },
  }
}

const line = (id: string, p: number): Drawing => ({ id, type: 'hline', pts: [{ t: 1, p }], width: 2 })

describe('首次对上', () => {
  it('云端一条自选都没有：保留本机的并推上去', async () => {
    const server = new FakeServer()
    const a = browser(server)
    await a.first()
    expect(a.s.watch.crypto).toEqual(['BTCUSDT'])
    expect([...server.objects.keys()]).toContain('favorites:binance/usd_m/BTCUSDT')
  })

  it('本机没改过：云端的自选与设置装进来', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), watch: { crypto: ['ETHUSDT', 'SOLUSDT'], us: ['NVDAUSDT'], com: [] }, pinned: ['15m'] })
    await a.first({ settings: Date.now(), favorites: Date.now() })
    const b = browser(server)
    await b.first()
    expect(b.s.watch).toEqual({ crypto: ['ETHUSDT', 'SOLUSDT'], us: ['NVDAUSDT'], com: [] })
    expect(b.s.pinned).toEqual(['15m'])
  })

  it('本机改得比云端新：本机的自选盖过去', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), watch: { crypto: ['ETHUSDT'], us: [], com: [] } })
    await a.first()
    const b = browser(server, { ...state(), watch: { crypto: ['SOLUSDT'], us: [], com: ['XAUUSDT'] } })
    await b.first({ settings: 0, favorites: server.now + 60e3 })
    expect(b.s.watch).toEqual({ crypto: ['SOLUSDT'], us: [], com: ['XAUUSDT'] })
    await a.sync()
    expect(a.s.watch).toEqual({ crypto: ['SOLUSDT'], us: [], com: ['XAUUSDT'] })
  })

  it('画线、提醒取并集；云端删掉的不从本机带回去', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), drawings: { BTCUSDT: [line('x', 1), line('gone', 2)] } })
    await a.first()
    a.s.drawings.BTCUSDT = [line('x', 1)]
    await a.sync()
    const b = browser(server, { ...state(), drawings: { BTCUSDT: [line('gone', 2), line('mine', 3)] }, alerts: [{ ...makePriceAlert('ETHUSDT', 5000, 4000, { now: 1 }), id: 'p1' }] })
    await b.first()
    expect(b.s.drawings.BTCUSDT.map(d => d.id).sort()).toEqual(['mine', 'x'])
    expect(b.s.alerts.map(x => x.id)).toEqual(['p1'])
    await a.sync()
    expect(a.s.drawings.BTCUSDT.map(d => d.id).sort()).toEqual(['mine', 'x'])
    expect(a.s.alerts.map(x => x.id)).toEqual(['p1'])
  })

  it('上一次同步的是另一个账号：云端整体覆盖，不把上一个人的东西带进来', async () => {
    const server = new FakeServer()
    const b = browser(server, { ...state(), drawings: { BTCUSDT: [line('prev', 1)] }, watch: { crypto: ['SOLUSDT'], us: [], com: [] } })
    await b.first({ settings: 0, favorites: 0 }, true)
    expect(b.s.drawings.BTCUSDT).toEqual([])
    expect(b.s.watch.crypto.length).toBeGreaterThan(1) // 云端空 → 出厂自选
    expect(server.objects.has('drawings:binance/usd_m/BTCUSDT/prev')).toBe(false)
  })
})

describe('两台来回', () => {
  it('加自选、画线、开提醒、改指标：另一台拉到同样的样子；删掉也跟着删', async () => {
    const server = new FakeServer()
    const a = browser(server), b = browser(server)
    await a.first(); await b.first()
    a.s.watch.crypto.push('ETHUSDT')
    a.s.drawings.BTCUSDT = [line('h1', 95000)]
    const onLine = makeDrawingAlert('BTCUSDT', line('h1', 95000), 1)
    const fr = { ...makeConditionAlert('ETHUSDT', { type: 'funding', side: 'below', rate: '0.0003' }, { now: 1 }), id: 'fr1' }
    a.s.alerts.push(onLine, fr)
    a.s.ind.boll = true
    a.s.params = { ma: { periods: [5, 10] } }
    await a.sync()
    await b.sync()
    expect(b.s.watch.crypto).toEqual(['BTCUSDT', 'ETHUSDT'])
    expect(b.s.drawings.BTCUSDT).toEqual([line('h1', 95000)])
    expect(b.s.alerts).toEqual([onLine, fr])
    expect(b.s.ind.boll).toBe(true)
    expect(b.s.params?.ma).toEqual({ periods: [5, 10] })

    b.s.drawings.BTCUSDT = []
    b.s.alerts = []
    b.s.watch.crypto = ['ETHUSDT']
    await b.sync()
    await a.sync()
    expect(a.s.drawings.BTCUSDT).toEqual([])
    expect(a.s.alerts).toEqual([])
    expect(a.s.watch.crypto).toEqual(['ETHUSDT'])
    // 画线与提醒都删了，云端不留活的提醒
    const liveAlerts = [...server.objects.values()].filter(o => o.collection === 'alerts' && !o.deleted)
    expect(liveAlerts).toEqual([])
  })

  it('没改动时来回不产生任何操作', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), drawings: { BTCUSDT: [line('h1', 1)] } })
    await a.first()
    const n = server.pushes.length
    for (const k of Object.keys(a.fp) as (keyof Prints)[]) delete a.fp[k]
    await a.sync()
    expect(server.pushes.length).toBe(n)
    expect(a.store.a.operations).toEqual([])
  })
})
