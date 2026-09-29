/* 手机网页版收尾审查（同步与壳）的回归用例。每条对应审查报告里的一个问题。 */
import { describe, expect, it } from 'vitest'
import { defaultPrefs } from '../src/m/app/prefs'
import * as C from '../src/m/app/syncCodec'
import { onServerClock } from '../src/m/app/sync'
import { OWNED, mergeFirst as pcMergeFirst, type WebState } from '../src/sync/bridge'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const MIN = 60_000

describe('第一次对上比「谁新」：本机钟与服务器钟不一致', () => {
  // 手机钟快 10 分钟：10 分钟前（真实时间）本机改过皮肤；1 分钟前另一台把皮肤改成 terra（真的更新）
  it('手机网页：本机钟快 10 分钟，别的设备后改的设置不被本机旧值盖回去', async () => {
    const server = new FakeServer()
    const T0 = server.now
    const store = new SyncStore(emptyArchive(), 'dev-fast', () => server.now + 10 * MIN)
    server.now = T0 + MIN
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'terra' }, deleted: false })
    server.now = T0 + 2 * MIN
    const engine = new Engine(store, server.transport(), C.OWNED_M, { capture: () => {}, apply: () => {} })
    await engine.full()
    expect(store.a.offset).toBe(-10 * MIN)
    const p = defaultPrefs(); p.skin = 'classic'
    const localEdit = T0 + 10 * MIN // 本机钟上的「最后一次改」，真实时间是 T0
    const ed = onServerClock({ settings: { skin: localEdit }, favorites: localEdit, drawings: { 'binance/usd_m/BTCUSDT': localEdit }, drawingPrefs: 0 }, store.a.offset)
    expect(ed.settings.skin).toBe(T0)
    expect(ed.favorites).toBe(T0)
    expect(ed.drawings['binance/usd_m/BTCUSDT']).toBe(T0)
    expect(ed.drawingPrefs).toBe(0) // 没改过的仍是 0
    store.a.seen = {}
    C.mergeSettings(p, store.get('settings', C.SETTINGS_ID), store.a.seen, ed.settings, false)
    expect(p.skin).toBe('terra')
  })

  it('手机网页：本机钟慢 10 分钟，本机刚改的设置不被云端旧值盖掉', async () => {
    const server = new FakeServer()
    const T0 = server.now
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'terra' }, deleted: false }) // 云端 T0
    server.now = T0 + 2 * MIN
    const store = new SyncStore(emptyArchive(), 'dev-slow', () => server.now - 10 * MIN)
    const engine = new Engine(store, server.transport(), C.OWNED_M, { capture: () => {}, apply: () => {} })
    await engine.full()
    const p = defaultPrefs(); p.skin = 'classic'
    const localEdit = T0 + MIN - 10 * MIN // 真实时间 T0 + 1 分，比云端新
    store.a.seen = {}
    C.mergeSettings(p, store.get('settings', C.SETTINGS_ID), store.a.seen, onServerClock({ settings: { skin: localEdit }, favorites: 0, drawings: {}, drawingPrefs: 0 }, store.a.offset).settings, false)
    expect(p.skin).toBe('classic')
  })

  it('PC 网页（sync/bridge.mergeFirst）：同一个问题，本机钟快时云端后改的自选与设置装进来', async () => {
    const server = new FakeServer()
    const T0 = server.now
    server.now = T0 + MIN
    server.put({ collection: 'favorites', id: 'binance/usd_m/ETHUSDT', body: { symbol: 'ETHUSDT', market: 'usd_m', venue: 'binance', order: 0 }, deleted: false })
    server.put({ collection: 'settings', id: 'chart', body: { interval: '4h', quickIntervals: ['15m'] }, deleted: false })
    server.now = T0 + 2 * MIN
    const store = new SyncStore(emptyArchive(), 'pc-fast', () => server.now + 10 * MIN)
    const engine = new Engine(store, server.transport(), OWNED, { capture: () => {}, apply: () => {} })
    await engine.full()
    const s: WebState = { pinned: ['1h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, watch: { crypto: ['BTCUSDT'], us: [], com: [] }, drawings: {}, alerts: [] }
    const localEdit = T0 + 10 * MIN // 真实时间 T0，比云端旧
    pcMergeFirst(s, store, ctx, { settings: localEdit, favorites: localEdit }, false)
    expect(s.watch.crypto).toEqual(['ETHUSDT'])
    expect(s.pinned).toEqual(['15m'])
  })
})
