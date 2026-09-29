import { describe, expect, it } from 'vitest'
import { Engine, MIN_BODY, isPermanent, scopesOf } from '../src/sync/engine'
import { SyncStore, deserialize, serialize } from '../src/sync/store'
import { type SyncObject, type SyncOperation, emptyArchive, keyOf } from '../src/sync/types'
import { FakeServer, HttpError } from './sync-fake'

const fav = (sym: string, order = 0): SyncObject =>
  ({ collection: 'favorites', id: 'binance/usd_m/' + sym, body: { symbol: sym, market: 'usd_m', venue: 'binance', groupId: null, order }, fields: {}, revision: 0, deleted: false, generation: 0 })
const drawing = (sym: string, id: string, p: number): SyncObject =>
  ({ collection: 'drawings', id: `binance/usd_m/${sym}/${id}`, body: { kind: 'hline', anchors: [{ t: 1, p }], symbol: sym, market: 'usd_m', venue: 'binance' }, fields: {}, revision: 0, deleted: false, generation: 0 })

function setup(server = new FakeServer()) {
  const store = new SyncStore(emptyArchive(), 'web-device', () => server.now)
  let applied = 0
  const engine = new Engine(store, server.transport(), {}, { capture: () => {}, apply: () => { applied++ } })
  return { server, store, engine, applied: () => applied }
}

describe('推送', () => {
  it('推空队列、ACK 之后本机与云端对上，op 不带 dependsOn', async () => {
    const { server, store, engine } = setup()
    store.capture([fav('BTCUSDT'), fav('ETHUSDT', 1)])
    store.capture([{ ...fav('BTCUSDT'), body: { ...fav('BTCUSDT').body, order: 2 } }])
    expect(store.a.operations).toHaveLength(3)
    expect(store.a.operations[2].dependsOn).toBe(store.a.operations[0].id)
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.sent.size).toBe(0)
    expect(server.objects.get(keyOf('favorites', 'binance/usd_m/BTCUSDT'))!.body.order).toBe(2)
    expect(store.a.objects[keyOf('favorites', 'binance/usd_m/BTCUSDT')].revision).toBe(2)
    for (const batch of server.pushes) for (const op of batch) expect('dependsOn' in op).toBe(false)
  })

  it('结果没回来（断网）：sent 保持，下一轮同一个 op id 重发，服务端幂等交回', async () => {
    const { server, store, engine } = setup()
    store.capture([fav('BTCUSDT')])
    const t = engine.t
    let drop = true
    engine.t = { ...t, push: async (b, k) => { const r = await t.push(b, k); if (drop) { drop = false; throw new HttpError(0, 'network') } return r } }
    await expect(engine.push()).rejects.toThrow()
    expect(store.a.sent.size).toBe(1)
    const id = store.a.operations[0].id
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(server.pushes.map(b => b[0].id)).toEqual([id, id])
    expect(server.objects.get(keyOf('favorites', 'binance/usd_m/BTCUSDT'))!.revision).toBe(1)
  })

  it('409 resync_required：退回、按品种前缀重拉、realign 之后推成功', async () => {
    const { server, store, engine } = setup()
    store.capture([drawing('BTCUSDT', 'd1', 100)])
    await engine.push()
    // 手机把这条删了又恢复：generation 变了，网页手上的 generation 过期
    const k = keyOf('drawings', 'binance/usd_m/BTCUSDT/d1')
    const cur = server.objects.get(k)!
    server.objects.set(k, { ...cur, revision: cur.revision + 2, generation: cur.generation + 1 })
    server.changes.push({ seq: ++server.seq, collection: 'drawings', id: cur.id, revision: cur.revision + 2, deleted: false })
    store.capture([drawing('BTCUSDT', 'd1', 105)])
    server.bootstraps.length = 0
    await engine.push()
    expect(server.bootstraps).toEqual([{ collection: 'drawings', prefix: 'binance/usd_m/BTCUSDT/' }])
    expect(store.a.operations).toHaveLength(0)
    expect(server.objects.get(k)!.body.anchors).toEqual([{ t: 1, p: 105 }])
    expect(server.objects.get(k)!.generation).toBe(1)
  })

  it('409 连续超过预算就停下交给下一轮，队列不丢', async () => {
    const { server, store, engine } = setup()
    store.capture([fav('BTCUSDT')])
    server.reject = () => new HttpError(409, 'resync_required')
    await expect(engine.push()).rejects.toMatchObject({ status: 409 })
    expect(store.a.operations).toHaveLength(1)
    expect(store.a.sent.size).toBe(0)
    server.reject = null
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
  })

  it('413：请求体预算减半直到推得动', async () => {
    const { server, store, engine } = setup()
    for (let i = 0; i < 120; i++) store.capture([drawing('BTCUSDT', 'd' + i, 100 + i)])
    server.reject = (_ops, body) => body.length > 20000 ? new HttpError(413, 'payload_too_large') : null
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(engine.budget).toBeLessThan(64 * 1024)
    expect(engine.budget).toBeGreaterThanOrEqual(MIN_BODY)
    expect(server.objects.size).toBe(120)
  })

  it('413 压到最低预算还推不动：按条数二分，单条挪进被拒，不原地打转', async () => {
    const { server, store, engine } = setup()
    for (let i = 0; i < 6; i++) store.capture([drawing('BTCUSDT', 'd' + i, 100 + i)])
    server.reject = ops => ops.some(o => o.objectId.endsWith('/d3')) ? new HttpError(413, 'payload_too_large') : null
    engine.budget = MIN_BODY
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.rejected.map(r => [r.operation.objectId, r.reason])).toEqual([['binance/usd_m/BTCUSDT/d3', 'payload_too_large']])
    expect(server.objects.size).toBe(5)
  })

  it('永久错误：整批退回，二分出坏的那条挪进被拒，其余照常推上去', async () => {
    const { server, store, engine } = setup()
    const syms = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT', 'DOGEUSDT', 'BNBUSDT']
    syms.forEach((s, i) => store.capture([fav(s, i)]))
    server.reject = ops => ops.some(o => o.objectId.endsWith('/XRPUSDT')) ? new HttpError(400, 'invalid_operation') : null
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.rejected.map(r => r.operation.objectId)).toEqual(['binance/usd_m/XRPUSDT'])
    expect(store.a.rejected[0].reason).toBe('invalid_operation')
    expect([...server.objects.keys()].sort()).toEqual(syms.filter(s => s !== 'XRPUSDT').map(s => keyOf('favorites', 'binance/usd_m/' + s)).sort())
  })

  it('401 / 429 / 5xx 不是永久错误，原样抛出、队列保留', async () => {
    expect(isPermanent({ status: 401 })).toBe(false)
    expect(isPermanent({ status: 429 })).toBe(false)
    expect(isPermanent({ status: 409, code: 'resync_required' })).toBe(false)
    expect(isPermanent({ status: 409, code: 'idempotency_mismatch' })).toBe(true)
    expect(isPermanent({ status: 400, code: 'invalid_batch' })).toBe(true)
    const { server, store, engine } = setup()
    store.capture([fav('BTCUSDT')])
    server.reject = () => new HttpError(503, 'temporarily_unavailable')
    await expect(engine.push()).rejects.toMatchObject({ status: 503 })
    expect(store.a.operations).toHaveLength(1)
  })

  it('ACK 回来的对象带着手机那边的字段：写回本机并标记待应用', async () => {
    const { server, store, engine } = setup()
    server.put({ ...drawing('BTCUSDT', 'd1', 100), body: { ...drawing('BTCUSDT', 'd1', 100).body, text: '手机写的' } })
    await engine.full()
    store.a.unapplied.clear()
    const local = store.get('drawings', 'binance/usd_m/BTCUSDT/d1')!
    store.capture([{ ...local, body: { ...local.body, anchors: [{ t: 1, p: 120 }] } }], { drawings: new Set(['kind', 'anchors']) })
    await engine.push()
    const after = store.get('drawings', 'binance/usd_m/BTCUSDT/d1')!
    expect(after.body.text).toBe('手机写的')
    expect(after.body.anchors).toEqual([{ t: 1, p: 120 }])
  })

  it('scopesOf：画线与提醒按品种前缀，整张表在的时候不再拉前缀', () => {
    const op = (collection: string, objectId: string) => ({ collection, objectId }) as SyncOperation
    expect(scopesOf([op('drawings', 'binance/usd_m/BTCUSDT/a'), op('drawings', 'binance/usd_m/BTCUSDT/b'), op('alerts', 'binance/usd_m/ETHUSDT/x'), op('settings', 'chart')])).toEqual([
      { collection: 'drawings', prefix: 'binance/usd_m/BTCUSDT/' }, { collection: 'alerts', prefix: 'binance/usd_m/ETHUSDT/' }, { collection: 'settings' },
    ])
  })
})

describe('拉取', () => {
  it('全量拉完所有集合、游标取最小；增量只重拉比本机新的', async () => {
    const { server, store, engine } = setup()
    server.put(fav('BTCUSDT'))
    server.put(drawing('ETHUSDT', 'd1', 10))
    await engine.full()
    expect(store.a.cursor).toBe(server.seq)
    expect(store.get('favorites', 'binance/usd_m/BTCUSDT')).toBeTruthy()
    expect(store.a.unapplied.has('favorites')).toBe(true)
    store.a.unapplied.clear()
    server.put({ ...fav('BTCUSDT'), body: { ...fav('BTCUSDT').body, order: 7 } })
    server.bootstraps.length = 0
    await engine.pull()
    expect(server.bootstraps).toEqual([{ collection: 'favorites', prefix: 'binance/usd_m/BTCUSDT' }])
    expect(store.get('favorites', 'binance/usd_m/BTCUSDT')!.body.order).toBe(7)
    expect(store.a.unapplied.has('favorites')).toBe(true)
    // 再拉一次没东西
    server.bootstraps.length = 0
    await engine.pull()
    expect(server.bootstraps).toEqual([])
  })

  it('本机攥着（队列里有）的对象，拉回来不覆盖本机那份', async () => {
    const { server, store, engine } = setup()
    server.put(fav('BTCUSDT'))
    await engine.full()
    const mine = { ...fav('BTCUSDT'), body: { ...fav('BTCUSDT').body, order: 3 } }
    store.capture([mine])
    server.put({ ...fav('BTCUSDT'), body: { ...fav('BTCUSDT').body, order: 9 } })
    await engine.pull()
    expect(store.get('favorites', 'binance/usd_m/BTCUSDT')!.body.order).toBe(3)
  })

  it('410 cursor_expired 退回全量', async () => {
    const { server, store, engine } = setup()
    server.put(fav('BTCUSDT'))
    await engine.full()
    const t = engine.t
    engine.t = { ...t, changes: async () => { throw new HttpError(410, 'cursor_expired') } }
    server.bootstraps.length = 0
    await engine.pull()
    expect(server.bootstraps.map(b => b.collection)).toEqual(['settings', 'favorites', 'groups', 'alerts', 'drawings'])
    expect(store.a.cursor).toBe(server.seq)
  })

  it('全量之后被拒的重新记账（云端已修好的就了结）', async () => {
    const { server, store, engine } = setup()
    store.capture([fav('BTCUSDT')])
    server.reject = () => new HttpError(422, 'invalid_operation')
    await engine.push()
    expect(store.a.rejected).toHaveLength(1)
    server.reject = null
    await engine.full()
    expect(store.a.operations).toHaveLength(1)
    await engine.push()
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.rejected).toHaveLength(0)
    expect(server.objects.has(keyOf('favorites', 'binance/usd_m/BTCUSDT'))).toBe(true)
  })
})

describe('账本落盘', () => {
  it('serialize / deserialize 往返保留队列、sent、本机与云端的差异', async () => {
    const { store, engine } = setup()
    store.capture([fav('BTCUSDT')])
    await engine.push()
    store.capture([{ ...fav('BTCUSDT'), body: { ...fav('BTCUSDT').body, order: 5 } }])
    store.markSent([store.a.operations[0].id])
    store.a.seen = { quickIntervals: ['1h'] }
    const back = deserialize(serialize(store.a))!
    expect(back.operations).toEqual(store.a.operations)
    expect([...back.sent]).toEqual([...store.a.sent])
    expect(back.local).toEqual(store.a.local)
    expect(back.objects).toEqual(store.a.objects)
    expect(back.seen).toEqual({ quickIntervals: ['1h'] })
  })
})
