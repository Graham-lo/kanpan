/* 画线：新工具的算法、45° 吸附、上限，以及同步自检（读坏 ≠ 删光、拉失败 ≠ 云端是空的、账本不串账号） */
import { describe, expect, it } from 'vitest'
import type { Bar } from '../src/chart/calc'
import type { Drawing } from '../src/chart/chart'
import { QUOTA, anchoredVwap, familyOf, fvpRows, groupOf, placeCount, positionStats, quotaOK, snap45 } from '../src/chart/drawTools'
import { vwap } from '../src/chart/indicators'
import { sanitizeDrawings } from '../src/app/store'
import { ANCHORS, KIND_OF, WEB_BODY_KEYS, decodeDrawings, drawingId, encodeDrawings } from '../src/sync/codec'
import { OWNED, captureInto, mergeFirst, restoreDrawings, type Prints, type WebState } from '../src/sync/bridge'
import { Engine, badPage } from '../src/sync/engine'
import { SyncStore, resumeArchive, serialize } from '../src/sync/store'
import { emptyArchive, keyOf } from '../src/sync/types'
import { FakeServer, HttpError, ctx } from './sync-fake'
import CONTRACT from '../../Backend/kanpan-api/contract/drawing-fields.json'

const bars = (n: number): Bar[] => Array.from({ length: n }, (_, i) => {
  const c = 100 + Math.sin(i / 3) * 5 + i * 0.2
  return { t: i * 60e3, o: c - 0.5, h: c + 1, l: c - 1.2, c, v: 1000 + i * 10, bv: 10 + (i % 7) }
})

describe('锚定 VWAP', () => {
  it('从第 0 根起算和主图 VWAP（按根数不分段时）逐根一致', () => {
    const b = bars(40)
    const a = anchoredVwap(b, 0, 39)
    // 主图 VWAP 按日分段；这 40 根都在同一天里，所以两者应当逐根相等
    const [mid, u1, d1] = vwap(b, 60e3) as number[][]
    for (let i = 0; i < 40; i++) {
      expect(a.mid[i]).toBeCloseTo(mid[i], 9)
      if (u1?.[i] != null) expect(a.u1[i]).toBeCloseTo(u1[i], 9)
      if (d1?.[i] != null) expect(a.d1[i]).toBeCloseTo(d1[i], 9)
    }
  })
  it('锚点那根：中线就是它的典型价、带宽为 0；之后 ±2σ 恰好是 ±1σ 的两倍宽', () => {
    const b = bars(30)
    const a = anchoredVwap(b, 10, 29)
    const k = b[10], tp = (k.h + k.l + k.c) / 3
    expect(a.mid[0]).toBeCloseTo(tp, 12)
    expect(a.u1[0]).toBeCloseTo(tp, 4) // 方差是 E[x²]−E[x]² 相减，有浮点残差
    expect(a.mid).toHaveLength(20)
    const i = 15
    expect(a.u2[i] - a.mid[i]).toBeCloseTo(2 * (a.u1[i] - a.mid[i]), 9)
    expect(a.mid[i] - a.d2[i]).toBeCloseTo(2 * (a.mid[i] - a.d1[i]), 9)
  })
  it('只算到 to（复盘回放时不看未来）', () => {
    expect(anchoredVwap(bars(30), 5, 12).mid).toHaveLength(8)
  })
})

describe('固定区间成交量分布 / 多空持仓 / 工具', () => {
  it('行数按像素高自动定：每行至少 4 px', () => {
    expect(fvpRows(400)).toBe(100)
    expect(fvpRows(3)).toBe(1)
    expect(fvpRows(10000)).toBe(240)
    expect(fvpRows(-80)).toBe(20)
  })
  it('多空持仓只算止盈止损百分比与盈亏比', () => {
    const l = positionStats(100, 110, 95)
    expect(l.long).toBe(true)
    expect(l.targetPct).toBeCloseTo(10, 9)
    expect(l.stopPct).toBeCloseTo(-5, 9)
    expect(l.r).toBeCloseTo(2, 9)
    const s = positionStats(100, 88, 104)
    expect(s.long).toBe(false)
    expect(s.r).toBeCloseTo(3, 9)
    expect(positionStats(100, 110, 100).r).toBeNull()
  })
  it('一点工具与两点工具', () => {
    expect(placeCount('avwap')).toBe(1)
    expect(placeCount('hline')).toBe(1)
    expect(placeCount('fvp')).toBe(2)
    expect(placeCount('position')).toBe(2) // 第三点（止损）按 1R 对称自动放
  })
  it('分组：新的「成交量」组里是锚定 VWAP 与固定区间成交量分布；同族共用样式', () => {
    expect(groupOf('avwap')?.name).toBe('成交量')
    expect(groupOf('fvp')?.id).toBe('volume')
    expect(familyOf('ray')).toBe(familyOf('trend'))
    expect(familyOf('position')).not.toBe(familyOf('trend'))
  })
})

describe('⇧ 吸 45°', () => {
  const X = (x: number) => Math.round(x / 10) * 10 // 每根 10 px
  it('接近水平 → 水平，接近竖直 → 竖直', () => {
    expect(snap45({ x: 0, y: 0 }, { x: 97, y: 8 }, X)).toEqual({ x: 100, y: 0 })
    expect(snap45({ x: 0, y: 0 }, { x: 6, y: -90 }, X)).toEqual({ x: 0, y: -90 })
  })
  it('接近对角 → 正好 45°（x 先落到整根，y 按 x 反推）', () => {
    const r = snap45({ x: 0, y: 0 }, { x: 52, y: -47 }, X)
    expect(r).toEqual({ x: 50, y: -50 })
    const q = snap45({ x: 20, y: 20 }, { x: -31, y: 72 }, X)
    expect(Math.abs(q.x - 20)).toBe(Math.abs(q.y - 20))
  })
})

describe('每只品种上限 500 条 / 2 MB', () => {
  const d = (i: number): Drawing => ({ id: 'd' + i, type: 'hline', pts: [{ t: 1, p: i }] })
  it('条数', () => {
    const list = Array.from({ length: QUOTA.count }, (_, i) => d(i))
    expect(quotaOK(list.slice(1), [d(999)])).toBe(true)
    expect(quotaOK(list, [d(999)])).toBe(false)
  })
  it('体积', () => {
    const big: Drawing = { id: 'big', type: 'trend', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }], color: '#' + 'A'.repeat(QUOTA.bytes) }
    expect(quotaOK([], [big])).toBe(false)
  })
  it('测量框不算', () => {
    const list = Array.from({ length: QUOTA.count }, (_, i) => d(i))
    expect(quotaOK(list, [{ id: 'm', type: 'measure', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }] }])).toBe(true)
  })
})

describe('同步编码：新工具与线型', () => {
  const avwap: Drawing = { id: 'a1', type: 'avwap', pts: [{ t: 60e3, p: 100 }], color: '#2962FF', width: 2 }
  const fvp: Drawing = { id: 'f1', type: 'fvp', pts: [{ t: 60e3, p: 1 }, { t: 600e3, p: 1 }], color: '#2962FF', width: 2 }
  const pos: Drawing = { id: 'p1', type: 'position', pts: [{ t: 60e3, p: 100 }, { t: 600e3, p: 110 }, { t: 600e3, p: 95 }], color: '#2962FF', width: 2, dash: 'dotted' }
  it('线上种类名照手机 Drawing.Kind，往返一致', () => {
    const out = encodeDrawings({ BTCUSDT: [avwap, fvp, pos] }, [])
    expect(out.map(o => o.body.kind)).toEqual(['anchoredVWAP', 'fixedVolumeProfile', 'position'])
    expect(out[2].body.dash).toBe('dotted')
    expect(out[0].body.dash).toBe('solid')
    expect(decodeDrawings(out, {}).BTCUSDT).toEqual([avwap, fvp, pos])
  })
  it('手机画的虚线装进网页后是虚线；网页改成实线会推 solid', () => {
    const [o] = encodeDrawings({ BTCUSDT: [{ ...pos, dash: 'dashed' }] }, [])
    const back = decodeDrawings([o], {}).BTCUSDT[0]
    expect(back.dash).toBe('dashed')
    const [solid] = encodeDrawings({ BTCUSDT: [{ ...back, dash: undefined }] }, [o])
    expect(solid.body.dash).toBe('solid')
  })
  it('和契约 drawing-fields.json 对账：网页的每个种类都在 anchorCounts 里且锚点数相等，写的键都在 syncFields 里', () => {
    const contract = CONTRACT as unknown as { anchorCounts: Record<string, number>; syncFields: string[] }
    for (const kind of Object.values(KIND_OF)) {
      expect(contract.anchorCounts[kind!], kind).toBe(ANCHORS[kind!])
    }
    for (const k of WEB_BODY_KEYS) expect(contract.syncFields).toContain(k)
    const out = encodeDrawings({ BTCUSDT: [avwap, fvp, pos] }, [])
    for (const o of out) for (const k of Object.keys(o.body)) expect(contract.syncFields).toContain(k)
  })
})

// ───────── 同步自检 ─────────

const state = (drawings: Record<string, Drawing[]> = {}): WebState => ({
  pinned: ['1h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null,
  watch: { crypto: ['BTCUSDT'], us: [], com: [] }, drawings, alerts: [],
})
const line = (id: string, p: number): Drawing => ({ id, type: 'hline', pts: [{ t: 1, p }], width: 2 })

/** 登录着、已经对上过的一台网页 */
async function synced(server: FakeServer, s: WebState) {
  const store = new SyncStore(emptyArchive(), 'web', () => server.now)
  const fp: Prints = {}
  const engine = new Engine(store, server.transport(), OWNED, { capture: () => {}, apply: () => {} })
  await engine.full()
  mergeFirst(s, store, ctx, { settings: 0, favorites: 0 }, false)
  captureInto(s, store, ctx, fp)
  await engine.push()
  return { store, engine, fp }
}

describe('同步自检：本机画线存档读坏 ≠ 用户删光', () => {
  it('读盘：整理形状，坏的丢掉并报 damaged', () => {
    expect(sanitizeDrawings(undefined)).toEqual({ drawings: {}, damaged: false })
    expect(sanitizeDrawings({ BTCUSDT: [line('a', 1)] }).damaged).toBe(false)
    expect(sanitizeDrawings('garbage').damaged).toBe(true)
    expect(sanitizeDrawings([1, 2]).damaged).toBe(true)
    const r = sanitizeDrawings({ BTCUSDT: [line('a', 1), { id: 'x' }], ETHUSDT: 'no' })
    expect(r.damaged).toBe(true)
    expect(r.drawings).toEqual({ BTCUSDT: [line('a', 1)] })
  })

  it('标记着读坏时记账只补不删：本机是空的也一条删除都不发', async () => {
    const server = new FakeServer()
    const a = await synced(server, state({ BTCUSDT: [line('a', 1), line('b', 2)] }))
    expect([...server.objects.values()].filter(o => o.collection === 'drawings' && !o.deleted)).toHaveLength(2)
    // 本机存档坏了，读出来是空的
    const empty = state({})
    delete a.fp.drawings
    captureInto(empty, a.store, ctx, a.fp, undefined, { holdDeletes: true })
    expect(a.store.a.operations.filter(o => o.collection === 'drawings')).toHaveLength(0)
    await a.engine.push()
    expect([...server.objects.values()].filter(o => o.collection === 'drawings' && !o.deleted)).toHaveLength(2)
    // 并回云端那份之后，本机 ⊇ 云端，正常记账也不会删
    const r = restoreDrawings(empty, a.store)
    expect([...r.drawings]).toEqual(['BTCUSDT'])
    expect(empty.drawings.BTCUSDT.map(d => d.id).sort()).toEqual(['a', 'b'])
    delete a.fp.drawings
    captureInto(empty, a.store, ctx, a.fp)
    expect(a.store.a.operations.filter(o => o.action === 'delete')).toHaveLength(0)
  })

  it('对照：没标记时本机的空就是删除（用户真的删光了）', async () => {
    const server = new FakeServer()
    const a = await synced(server, state({ BTCUSDT: [line('a', 1)] }))
    delete a.fp.drawings
    captureInto(state({ BTCUSDT: [] }), a.store, ctx, a.fp)
    expect(a.store.a.operations.map(o => o.action)).toEqual(['delete'])
  })

  it('读坏后又新画了一条：并回时两边都留着', async () => {
    const server = new FakeServer()
    const a = await synced(server, state({ BTCUSDT: [line('a', 1)] }))
    const s = state({ BTCUSDT: [line('n', 9)] })
    restoreDrawings(s, a.store)
    expect(s.drawings.BTCUSDT.map(d => d.id)).toEqual(['n', 'a'])
  })
})

describe('同步自检：拉取失败 ≠ 云端是空的', () => {
  it('画线那一页 5xx：全量抛出、游标不动、账本里没有任何操作，首次合并不会发生', async () => {
    const server = new FakeServer()
    server.put({ collection: 'drawings', id: drawingId('BTCUSDT', 'a'), body: { kind: 'hline', anchors: [{ t: 1, p: 1 }], symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance' }, deleted: false })
    const store = new SyncStore(emptyArchive(), 'web', () => server.now)
    const t = server.transport()
    const engine = new Engine(store, { ...t, bootstrap: async (c, p, a) => { if (c === 'drawings') throw new HttpError(503, 'http_503'); return t.bootstrap(c, p, a) } }, OWNED, { capture: () => {}, apply: () => {} })
    await expect(engine.full()).rejects.toMatchObject({ status: 503 })
    expect(store.a.cursor).toBeNull()
    expect(store.a.operations).toHaveLength(0)
  })

  it('形状不对的 200（代理错误页、字段缺了）：当成拉失败抛出，不当成「云端没有画线」', async () => {
    const server = new FakeServer()
    server.put({ collection: 'drawings', id: drawingId('BTCUSDT', 'a'), body: { kind: 'hline', anchors: [{ t: 1, p: 1 }], symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance' }, deleted: false })
    for (const junk of [null, {}, { objects: 'x', cursor: 1, serverTime: 1, next: null }, { objects: [], serverTime: 1, next: null }, { objects: [{ id: 1 }], cursor: 1, serverTime: 1, next: null }]) {
      const store = new SyncStore(emptyArchive(), 'web', () => server.now)
      const t = server.transport()
      const engine = new Engine(store, { ...t, bootstrap: async (c, p, a) => c === 'drawings' ? junk as never : t.bootstrap(c, p, a) }, OWNED, { capture: () => {}, apply: () => {} })
      await expect(engine.full()).rejects.toMatchObject({ code: 'bad_page' })
      expect(store.a.cursor).toBeNull()
      expect(store.a.operations).toHaveLength(0)
    }
  })

  it('增量页形状不对也抛出，游标不动', async () => {
    const server = new FakeServer()
    const a = await synced(server, state({ BTCUSDT: [line('a', 1)] }))
    const cur = a.store.a.cursor
    a.engine.t = { ...a.engine.t, changes: async () => ({ objects: [], cursor: 99 }) as never }
    await expect(a.engine.pull()).rejects.toMatchObject({ code: 'bad_page' })
    expect(a.store.a.cursor).toBe(cur)
  })

  it('真的是空的（合法的空页）：并集合并把本机的推上去', async () => {
    const server = new FakeServer()
    const s = state({ BTCUSDT: [line('a', 1)] })
    await synced(server, s)
    expect(server.objects.get(keyOf('drawings', drawingId('BTCUSDT', 'a')))?.deleted).toBe(false)
  })

  it('badPage 认得合法页', () => {
    expect(badPage({ objects: [], next: null, cursor: 0, serverTime: 1 })).toBe(false)
    expect(badPage({ objects: [], invalidations: [], cursor: 0, hasMore: false, serverTime: 1 }, true)).toBe(false)
    expect(badPage({ objects: [], cursor: 0, serverTime: 1 }, true)).toBe(true)
  })
})

describe('同步自检：没推出去的账本只给同一个账号接着用', () => {
  it('A 的账本（含没推出去的删除）不会在 B 登录时重放', () => {
    const a = new SyncStore(emptyArchive(), 'web')
    a.capture([{ collection: 'drawings', id: drawingId('BTCUSDT', 'x'), body: { kind: 'hline' }, fields: {}, revision: 0, deleted: false, generation: 0 }])
    a.a.cursor = 5
    const text = serialize(a.a)
    expect(resumeArchive('user-a', 'user-a', text)?.operations).toHaveLength(1)
    expect(resumeArchive('user-a', 'user-b', text)).toBeNull()
    expect(resumeArchive(null, 'user-b', text)).toBeNull()
  })
})
