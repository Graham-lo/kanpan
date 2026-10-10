/* 审查 2026-10-10 的同步正确性几项（和手机端 KanpanAccount 的 SyncCorrectnessTests 一一对应）：
 * 1. 记在别的设备号名下的操作照样推得上去（未发的开头改记；已发的被服务端拒了设备再改记）；
 * 2. 补推被拒操作只补被拒的那几项，别的设备之后的改动不许被冻住的旧值盖回去；
 * 3. 值不对的那一项本机认云端那份、不重发；不认识的字段记账叠回、不打转；
 * 5. 单条拒绝只隔离那一条。 */
import { describe, expect, it } from 'vitest'
import { Engine, type Transport } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { type Json, type PushResponse, type SyncObject, type SyncOperation, type SyncRejection, type SyncResult, emptyArchive, keyOf, splitPush } from '../src/sync/types'
import { FakeServer, HttpError } from './sync-fake'

const SESSION = 'web-device'
const CHART = keyOf('settings', 'chart')

/** 在 FakeServer 前面加一层 `sync.rs` 的 `push` 里 merge 之外的那几件事：先查回执，再查设备与内容
 *  （新服务端单条拒绝，老服务端整批 400），设置里值不对 / 不认识的字段拿掉并回报 */
class Screen {
  refuse: ((op: SyncOperation) => string | null) | null = null
  invalid: ((k: string, v: Json) => boolean) | null = null
  unknown = new Set<string>()
  pushes: number[] = []
  constructor(public server: FakeServer, public session = SESSION, public inline = true) {}
  transport(): Transport {
    return { ...this.server.transport(), push: async body => this.push(body) as unknown as PushResponse }
  }
  push(body: string): { results: (SyncResult | SyncRejection)[]; serverTime: number } {
    const { operations } = JSON.parse(body) as { operations: SyncOperation[] }
    this.pushes.push(operations.length)
    const rejections: SyncRejection[] = [], kept: SyncOperation[] = []
    const dropped = new Map<string, { dropped: string[]; invalid: string[] }>()
    for (const op of operations) {
      const code = this.server.done.has(op.id) ? null : op.deviceId !== this.session ? 'invalid_device' : this.refuse?.(op) ?? null
      if (code) {
        if (!this.inline) throw new HttpError(400, code)
        rejections.push({ operationId: op.id, status: 'rejected', code }); continue
      }
      const invalid = Object.entries(op.fields).filter(([k, v]) => this.invalid?.(k, v)).map(([k]) => k)
      const unknown = Object.keys(op.fields).filter(k => this.unknown.has(k))
      const fields = { ...op.fields }
      for (const k of [...invalid, ...unknown]) delete fields[k]
      kept.push({ ...op, fields })
      if (invalid.length || unknown.length) dropped.set(op.id, { dropped: [...invalid, ...unknown].sort(), invalid })
    }
    const res = kept.length ? this.server.push(JSON.stringify({ operations: kept })) : { results: [], serverTime: this.server.now }
    const results: (SyncResult | SyncRejection)[] = res.results.map(r => {
      const d = dropped.get(r.operationId)
      return d ? { ...r, droppedFields: d.dropped, invalidFields: d.invalid.length ? d.invalid : undefined } : r
    })
    return { results: [...results, ...rejections], serverTime: res.serverTime }
  }
}

function chart(body: Record<string, Json>): SyncObject {
  return { collection: 'settings', id: 'chart', body, fields: {}, revision: 0, deleted: false, generation: 0 }
}
function line(n: number, text: string): SyncObject {
  return { collection: 'drawings', id: `binance/usd_m/BTCUSDT/n${n}`, body: { symbol: 'BTCUSDT', text }, fields: {}, revision: 0, deleted: false, generation: 0 }
}
function rig(device = SESSION, inline = true) {
  const server = new FakeServer()
  const screen = new Screen(server, SESSION, inline)
  const store = new SyncStore(emptyArchive(), device, () => server.now)
  const engine = new Engine(store, screen.transport(), {}, { capture: () => {}, apply: () => {} }, ['settings', 'drawings'])
  return { server, screen, store, engine }
}

describe('1 设备号', () => {
  it('还没发出去、记在旧设备号名下的操作：开账本时就改记到这台设备', () => {
    const a = emptyArchive()
    const op = (id: string): SyncOperation => ({ id, collection: 'settings', objectId: 'chart', deviceId: 'old', baseRevision: 0, generation: 0, timestamp: 1, logical: 1, action: 'patch', fields: { x: 1 }, importBatch: null })
    a.operations = [op('sent'), op('fresh')]
    a.sent.add('sent')
    const store = new SyncStore(a, SESSION)
    expect(store.a.operations.map(o => o.deviceId)).toEqual(['old', SESSION])
  })

  for (const inline of [true, false]) {
    it(`已发出去的那条记在旧设备号名下：服务端拒了设备（${inline ? '单条拒绝' : '老服务端整批 400'}）之后改记重发，不隔离`, async () => {
      const { server, screen, engine } = rig(SESSION, inline)
      const archive = emptyArchive()
      const old = new SyncStore(archive, 'old-device', () => server.now)
      old.capture([line(0, '退出前')])
      old.markSent(old.a.operations.map(o => o.id))       // 发出去了、回话没到
      old.capture([line(1, '离线改的')])
      const store = new SyncStore(archive, SESSION, () => server.now)
      engine.store = store
      await engine.push()
      expect(screen.pushes).toEqual(inline ? [2, 1] : [2, 2])
      expect(store.a.operations).toHaveLength(0)
      expect(store.a.sent.size).toBe(0)
      expect(store.a.rejected).toHaveLength(0)
      expect(server.objects.get(keyOf('drawings', 'binance/usd_m/BTCUSDT/n0'))!.body.text).toBe('退出前')
      expect(server.objects.get(keyOf('drawings', 'binance/usd_m/BTCUSDT/n1'))!.body.text).toBe('离线改的')
    })
  }

  it('会话本身就不是这台设备（改不动任何一条）：老服务端整批 400 原样抛出，队列不动、不隔离', async () => {
    const { screen, store, engine } = rig('mine', false)
    screen.session = 'someone-else'
    store.capture([line(0, '新')])
    await expect(engine.push()).rejects.toMatchObject({ status: 400, code: 'invalid_device' })
    expect(store.a.operations).toHaveLength(1)
    expect(store.a.sent.size).toBe(0)
    expect(store.a.rejected).toHaveLength(0)
  })
})

describe('2 补推只补被拒的那几项', () => {
  it('A 被拒 → B 改了同一项和另一项 → A 补推：B 的两项都留着，A 只补没人动过的那一项', async () => {
    const { server, screen, store, engine } = rig()
    server.put(chart({ skin: 'moss', barSpacing: 6, color: 'a' }))
    await engine.full()
    screen.refuse = op => op.fields.skin === 'terra' ? 'invalid_operation' : null
    store.capture([chart({ skin: 'terra', barSpacing: 6, color: 'b' })])
    const original = store.a.operations[0]
    expect(Object.keys(original.fields).sort()).toEqual(['color', 'skin'])
    await engine.push()
    expect(store.a.rejected).toHaveLength(1)

    // B（手机）在 A 被拒之后改了皮肤与柱宽
    server.now += 1000
    server.push(JSON.stringify({ operations: [{ id: 'by-b', collection: 'settings', objectId: 'chart', deviceId: 'phone', baseRevision: 1, generation: 0, timestamp: server.now, logical: 1, action: 'patch', fields: { skin: 'ink', barSpacing: 9 }, importBatch: null }] }))
    screen.refuse = null

    await engine.full()
    const retry = store.a.operations[0]
    expect(retry.fields).toEqual({ color: 'b' })
    expect(retry.timestamp).toBe(original.timestamp)
    expect(retry.logical).toBe(original.logical)
    expect(retry.id).not.toBe(original.id)
    expect(store.a.local[CHART].body.skin).toBe('ink')

    await engine.push()
    const cloud = server.objects.get(CHART)!
    expect(cloud.body).toEqual({ skin: 'ink', barSpacing: 9, color: 'b' })
    expect(store.a.rejected).toHaveLength(0)
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.local[CHART].body).toEqual(cloud.body)
  })

  it('B 改的恰好就是被拒的那几项：什么都不补，记录了结，本机跟上云端', async () => {
    const { server, screen, store, engine } = rig()
    server.put(chart({ skin: 'moss', barSpacing: 6 }))
    await engine.full()
    screen.refuse = op => op.fields.skin === 'terra' ? 'invalid_operation' : null
    store.capture([chart({ skin: 'terra', barSpacing: 6 })])
    await engine.push()
    server.now += 1000
    server.push(JSON.stringify({ operations: [{ id: 'by-b', collection: 'settings', objectId: 'chart', deviceId: 'phone', baseRevision: 1, generation: 0, timestamp: server.now, logical: 1, action: 'patch', fields: { skin: 'ink', barSpacing: 9 }, importBatch: null }] }))
    screen.refuse = null
    const before = screen.pushes.length
    await engine.full()
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.rejected).toHaveLength(0)
    expect(store.a.local[CHART].body).toEqual(server.objects.get(CHART)!.body)
    expect(store.a.unapplied.has('settings')).toBe(true)
    expect(screen.pushes.length).toBe(before)
  })

  it('retryRejected 报出按云端了结的那几项', () => {
    const store = new SyncStore(emptyArchive(), SESSION, () => 100)
    const cloud: SyncObject = { ...chart({ skin: 'ink' }), revision: 2, fields: { skin: { revision: 2, timestamp: 200, logical: 1, deviceId: 'phone', operationId: 'x' } } }
    store.a.objects[CHART] = cloud
    store.a.local[CHART] = chart({ skin: 'terra' })
    store.a.rejected = [{ operation: { id: 'r', collection: 'settings', objectId: 'chart', deviceId: SESSION, baseRevision: 1, generation: 0, timestamp: 100, logical: 1, action: 'patch', fields: { skin: 'terra' }, importBatch: null }, reason: 'invalid_operation', at: 100, intent: chart({ skin: 'terra' }) }]
    expect(store.retryRejected()).toEqual({ [CHART]: ['skin'] })
    expect(store.a.rejected).toHaveLength(0)
    expect(store.a.local[CHART].body.skin).toBe('ink')
  })
})

describe('3 值不对 / 不认识的字段', () => {
  it('值不对的那一项：本机认云端那份，再记一遍不生出新操作', async () => {
    const { server, screen, store, engine } = rig()
    screen.invalid = (k, v) => k === 'skin' && v === 'neon'
    server.put(chart({ skin: 'moss', barSpacing: 6 }))
    await engine.full()
    store.capture([chart({ skin: 'neon', barSpacing: 8 })])
    await engine.push()
    expect(server.objects.get(CHART)!.body).toEqual({ skin: 'moss', barSpacing: 8 })
    expect(store.a.local[CHART].body).toEqual({ skin: 'moss', barSpacing: 8 })
    expect(store.a.unapplied.has('settings')).toBe(true)
    expect(store.a.rejected).toHaveLength(0)
    store.capture([chart({ skin: 'moss', barSpacing: 8 })])
    expect(store.a.operations).toHaveLength(0)
  })

  it('不认识的那一项：记账叠回本机的值，同一份再记一遍不生出新操作（不打转）', async () => {
    const { server, screen, store, engine } = rig()
    screen.unknown.add('glow')
    server.put(chart({ barSpacing: 6 }))
    await engine.full()
    const mine = chart({ barSpacing: 6, glow: true })
    store.capture([mine])
    await engine.push()
    expect(screen.pushes).toEqual([1])
    expect(server.objects.get(CHART)!.body.glow).toBeUndefined()
    expect(store.a.local[CHART].body.glow).toBe(true)
    store.capture([mine])
    expect(store.a.operations).toHaveLength(0)
  })
})

describe('5 单条拒绝', () => {
  it('一批里一条有毛病只拒那一条，其余一次落地，不再对半切', async () => {
    const { server, screen, store, engine } = rig()
    screen.refuse = op => op.fields.text === '坏' ? 'symbol' : null
    store.capture([line(0, '好'), line(1, '坏'), line(2, '也好')])
    const bad = store.a.operations[1].id
    await engine.push()
    expect(screen.pushes).toEqual([3])
    expect(store.a.operations).toHaveLength(0)
    expect(store.a.sent.size).toBe(0)
    expect(store.a.rejected.map(r => r.operation.id)).toEqual([bad])
    expect(store.a.rejected[0].reason).toBe('symbol')
    expect(server.objects.get(keyOf('drawings', 'binance/usd_m/BTCUSDT/n0'))!.body.text).toBe('好')
    expect(server.objects.get(keyOf('drawings', 'binance/usd_m/BTCUSDT/n2'))!.body.text).toBe('也好')
  })

  it('splitPush 把线上混在 results 里的拒绝格挪出来', () => {
    const r = splitPush({ results: [{ operationId: 'a', status: 'rejected', code: 'invalid_device' }], serverTime: 1 })
    expect(r.results).toEqual([])
    expect(r.rejections).toEqual([{ operationId: 'a', status: 'rejected', code: 'invalid_device' }])
  })
})
