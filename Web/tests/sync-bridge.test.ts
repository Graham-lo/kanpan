import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { makeConditionAlert, makeDrawingAlert, makePriceAlert } from '../src/alerts/shape'
import { OWNED, applyInto, captureInto, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { alertToBody, factorySettings } from '../src/sync/codec'
import { hydrate } from '../src/app/store'
import type { SubId } from '../src/chart/calc'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const state = (): WebState => ({
  pinned: ['1h', '4h'],
  ind: { ma: true, ema: false, boll: false, vol: true, subs: [] },
  params: null,
  watch: { crypto: ['BTCUSDT'], us: [], idx: [], com: [] },
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
    const a = browser(server, { ...state(), watch: { crypto: ['ETHUSDT', 'SOLUSDT'], us: ['NVDAUSDT'], idx: [], com: [] }, pinned: ['15m'] })
    await a.first({ settings: Date.now(), favorites: Date.now() })
    const b = browser(server)
    await b.first()
    expect(b.s.watch).toEqual({ crypto: ['ETHUSDT', 'SOLUSDT'], us: ['NVDAUSDT'], idx: [], com: [] })
    expect(b.s.pinned).toEqual(['15m'])
  })

  it('本机改得比云端新：本机的自选盖过去', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), watch: { crypto: ['ETHUSDT'], us: [], idx: [], com: [] } })
    await a.first()
    const b = browser(server, { ...state(), watch: { crypto: ['SOLUSDT'], us: [], idx: [], com: ['XAUUSDT'] } })
    await b.first({ settings: 0, favorites: server.now + 60e3 })
    expect(b.s.watch).toEqual({ crypto: ['SOLUSDT'], us: [], idx: [], com: ['XAUUSDT'] })
    await a.sync()
    expect(a.s.watch).toEqual({ crypto: ['SOLUSDT'], us: [], idx: [], com: ['XAUUSDT'] })
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
    const b = browser(server, { ...state(), drawings: { BTCUSDT: [line('prev', 1)] }, watch: { crypto: ['SOLUSDT'], us: [], idx: [], com: [] } })
    await b.first({ settings: 0, favorites: 0 }, true)
    expect(b.s.drawings.BTCUSDT).toEqual([])
    expect(b.s.watch.crypto.length).toBeGreaterThan(1) // 云端空 → 出厂自选
    expect(server.objects.has('drawings:binance/usd_m/BTCUSDT/prev')).toBe(false)
  })

  it('换了个新账号（云端没有设置）：指标布局、钉住周期、参数回到出厂，不把上一个人的带进新账号的云端', async () => {
    const server = new FakeServer()
    const prev = { ...state(), pinned: ['15m'], ind: { ma: false, ema: true, boll: true, vol: false, subs: ['macd', 'kdj', 'oi'] as SubId[] }, params: { macd: { fast: 5, slow: 9, signal: 3 } } }
    const b = browser(server, prev)
    await b.first({ settings: 0, favorites: 0 }, true)
    const f = factorySettings()
    expect(b.s.pinned).toEqual(f.pinned)
    expect(b.s.ind).toEqual(f.ind)
    expect(b.s.params).toBeNull()
    const pushed = server.objects.get('settings:chart')?.body
    expect(pushed?.subs).toEqual(['VOL', 'MACD', 'RSI'])
    expect(pushed?.['params/MACD']).toBeUndefined()
  })

  it('换了账号、云端只有部分设置：有的装云端的，缺的回出厂', async () => {
    const server = new FakeServer()
    server.put({ collection: 'settings', id: 'chart', body: { subs: ['KDJ'] }, deleted: false })
    const b = browser(server, { ...state(), pinned: ['15m'], ind: { ma: false, ema: true, boll: false, vol: true, subs: ['oi'] } })
    await b.first({ settings: 0, favorites: 0 }, true)
    expect(b.s.ind).toEqual({ ma: true, ema: false, boll: false, vol: false, subs: ['kdj'] })
    expect(b.s.pinned).toEqual(factorySettings().pinned)
  })

  it('出厂设置与 app/store 的 defaults() 对得上', () => {
    const d = hydrate({})
    const f = factorySettings()
    expect({ pinned: d.pinned, ind: d.ind, params: d.params, orderFlowOverrides: d.orderFlowOverrides, compareSymbols: d.compareSymbols, drawHidden: d.drawHidden }).toEqual(f)
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

describe('提醒触发（照手机 markFired → 报 → purgeFired，服务端靠 active → fired 发 Webhook）', () => {
  const hooked = (id: string) => ({ ...makePriceAlert('BTCUSDT', 101000, 100000, { now: 1, webhook: 'https://example.com/h' }), id })

  it('本机响：先推「已触发」（带 firedAt / firedPrice）再推删除，同一条提醒的两笔按先后', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), alerts: [hooked('p1')] })
    await a.first()
    const spent = new Set<string>()
    const x = a.s.alerts[0]
    // model.fire 的三步：标已触发并记账 → 报（记进 spent）→ 删掉并记账
    x.status = 'fired'; x.firedAt = server.now; x.firedPrice = 101002
    captureInto(a.s, a.store, ctx, a.fp, spent)
    spent.add('binance/usd_m/BTCUSDT/p1')
    a.s.alerts = []
    captureInto(a.s, a.store, ctx, a.fp, spent)
    await a.engine.push()
    const ops = server.pushes.flat().filter(o => o.objectId === 'binance/usd_m/BTCUSDT/p1')
    const fired = ops.findIndex(o => o.action === 'patch' && o.fields.status === 'fired')
    const del = ops.findIndex(o => o.action === 'delete')
    expect(fired).toBeGreaterThanOrEqual(0)
    expect(ops[fired].fields).toMatchObject({ status: 'fired', firedAt: server.now, firedPrice: 101002 })
    expect(del).toBeGreaterThan(fired)
    expect(server.objects.get('alerts:binance/usd_m/BTCUSDT/p1')?.deleted).toBe(true)
  })

  it('服务端响了、同步下来：applyInto 交出来报给人；记进 spent 之后才删', async () => {
    const server = new FakeServer()
    const a = browser(server, { ...state(), alerts: [hooked('p2')] })
    await a.first()
    const k = 'alerts:binance/usd_m/BTCUSDT/p2'
    const o = server.objects.get(k)!
    server.put({ collection: 'alerts', id: o.id, deleted: false, body: { ...o.body, status: 'fired', firedAt: server.now, firedPrice: 101001 } })
    await a.engine.pull()
    // 引擎的 apply 钩子已经装过一次（结果被丢掉了）；本机再放回那条在等的，看 applyInto 交不交出来
    a.store.a.unapplied.add('alerts')
    a.s.alerts = [hooked('p2')]
    const r = applyInto(a.s, a.store, ctx)
    expect(r.fired.map(f => [f.id, f.status, f.firedPrice])).toEqual([['p2', 'fired', 101001]])
    expect(a.s.alerts).toEqual([])
    // 没报过（不在 spent）不删
    delete a.fp.alerts
    captureInto(a.s, a.store, ctx, a.fp, new Set())
    await a.engine.push()
    expect(server.objects.get(k)?.deleted).toBe(false)
    // 报过了再删
    delete a.fp.alerts
    captureInto(a.s, a.store, ctx, a.fp, new Set([o.id]))
    await a.engine.push()
    expect(server.objects.get(k)?.deleted).toBe(true)
  })

  it('别的设备的已触发、这个网页没报过：本机改别的提醒时也不顺手删', async () => {
    const server = new FakeServer()
    const a = browser(server)
    await a.first()
    const phone = { ...hooked('ph'), status: 'fired' as const, firedAt: server.now, firedPrice: 1 }
    server.put({ collection: 'alerts', id: 'binance/usd_m/BTCUSDT/ph', deleted: false, body: alertToBody(phone) })
    await a.sync()
    a.s.alerts.push(hooked('mine'))
    captureInto(a.s, a.store, ctx, a.fp, new Set())
    await a.engine.push()
    expect(server.objects.get('alerts:binance/usd_m/BTCUSDT/ph')?.deleted).toBe(false)
    expect(server.objects.get('alerts:binance/usd_m/BTCUSDT/mine')?.deleted).toBe(false)
  })
})
