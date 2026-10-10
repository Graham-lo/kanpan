/* 电脑网页「用手改出来的习惯跟着人走」（2026-10-10）：画线扩展样式、条件提醒的品种门槛、
 * 与手机上限不同的那几项（周期条 / 副图 / 参数）、接上手机已有的共用字段、网页独有 webPrefs、每格对数与根宽。 */
import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { cleanStyle } from '../src/chart/drawStyle'
import { cleanDrawing } from '../src/chart/drawTools'
import { conditionAlertsOk, decodeDrawings, drawingId, encodeDrawings, syncableAlert } from '../src/sync/codec'
import { makeConditionAlert, makePriceAlert } from '../src/alerts/shape'
import { OWNED, captureInto, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive, type SyncObject } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const base = (drawings: Record<string, Drawing[]> = {}): WebState => ({
  pinned: ['1h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null,
  watch: { crypto: ['BTCUSDT'], us: [], idx: [], com: [] }, drawings, alerts: [],
})
const fvp = (id: string, style?: Drawing['style']): Drawing => ({ id, type: 'fvp', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }], width: 2, ...(style ? { style } : {}) })

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

describe('B4 画线扩展样式 style 跟着人走', () => {
  it('cleanStyle 与服务端 drawing_style 同一组上限', () => {
    expect(cleanStyle({ vp: true, widthPct: 30, poc: { on: true, color: '#FF0000' } })).toEqual({ vp: true, widthPct: 30, poc: { on: true, color: '#FF0000' } })
    expect(cleanStyle({ a: [1], '1x': true, 'a-b': 1, n: null, ok: 1 })).toEqual({ ok: 1 })
    expect(cleanStyle({ a: { b: { c: { d: 1 } } } })).toEqual({ a: { b: {} } })
    expect(cleanStyle({ t: 'x'.repeat(65) })).toBeUndefined()
    expect(cleanStyle(Object.fromEntries(Array.from({ length: 300 }, (_, i) => ['k' + i, '#26C6DA80'])))).toBeUndefined()
    expect(cleanStyle([1])).toBeUndefined()
    // 读档清洗：坏的扩展样式就地洗掉，画线本身留着
    expect(cleanDrawing({ ...fvp('a'), style: { x: [1] } })).toEqual(fvp('a'))
  })

  it('编码带上 style，解码还原；清掉时记账发 null', async () => {
    const server = new FakeServer()
    const s = base({ BTCUSDT: [fvp('a', { vp: false, up: '#112233' })] })
    const a = await synced(server, s)
    const o = server.objects.get('drawings:' + drawingId('BTCUSDT', 'a'))!
    expect(o.body.style).toEqual({ vp: false, up: '#112233' })
    expect(decodeDrawings([o], {}).BTCUSDT[0].style).toEqual({ vp: false, up: '#112233' })
    // 恢复默认：本机没了 style → 发 null
    delete s.drawings.BTCUSDT[0].style
    captureInto(s, a.store, ctx, a.fp)
    const op = a.store.a.operations.at(-1)!
    expect(op.fields).toEqual({ style: null })
  })

  it('云端从没写过 style（手机改了几何 / 老服务端丢了这个键）：本机的扩展样式留着；云端明确清掉（null）才听云端', () => {
    const cloudNoKey: SyncObject = encodeDrawings({ BTCUSDT: [fvp('a')] }, [])[0]
    cloudNoKey.body.anchors = [{ t: 1, p: 5 }, { t: 2, p: 6 }]
    const mine = { BTCUSDT: [fvp('a', { vp: false })] }
    const d = decodeDrawings([cloudNoKey], mine).BTCUSDT[0]
    expect(d.pts[0].p).toBe(5)
    expect(d.style).toEqual({ vp: false })
    const cleared: SyncObject = { ...cloudNoKey, body: { ...cloudNoKey.body, style: null } }
    expect(decodeDrawings([cleared], mine).BTCUSDT[0].style).toBeUndefined()
  })

  it('手机推同一条线（只认契约字段、style 原样带回）后网页不丢 style', async () => {
    const server = new FakeServer()
    const s = base({ BTCUSDT: [fvp('a', { vp: false })] })
    const a = await synced(server, s)
    const key = 'drawings:' + drawingId('BTCUSDT', 'a')
    const o = server.objects.get(key)!
    // 手机改了颜色：它的 stage 把不认识的 style 原样带回（SyncStore.stage owned 规则），只发 color
    server.put({ collection: 'drawings', id: o.id, body: { ...o.body, color: { value: '#FF0000' } }, deleted: false })
    await a.engine.pull()
    const d = decodeDrawings(a.store.localOf('drawings'), s.drawings).BTCUSDT[0]
    expect(d.color).toBe('#FF0000')
    expect(d.style).toEqual({ vp: false })
  })
})

describe('B5 条件提醒只给币安 U 本位', () => {
  const rule = { type: 'funding', side: 'above', rate: '0.001' } as const
  it('conditionAlertsOk：币安 U 本位可以，美元指数与别家不行', () => {
    expect(conditionAlertsOk('BTCUSDT')).toBe(true)
    expect(conditionAlertsOk('DXY')).toBe(false)
    expect(conditionAlertsOk('okx/usd_m/BTCUSDT')).toBe(false)
    expect(conditionAlertsOk('coinbase/spot/BTC-USD')).toBe(false)
  })
  it('别家的条件提醒不上云（推上去必被服务端拒，整条堵队列），价格提醒照常', () => {
    expect(syncableAlert(makeConditionAlert('BTCUSDT', rule))).toBe(true)
    expect(syncableAlert(makeConditionAlert('okx/usd_m/BTCUSDT', rule))).toBe(false)
    expect(syncableAlert(makeConditionAlert('DXY', rule))).toBe(false)
    expect(syncableAlert(makePriceAlert('okx/usd_m/BTCUSDT', 70000, 69000))).toBe(true)
  })
})
