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
    const s: WebState = { pinned: ['1h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, watch: { crypto: ['BTCUSDT'], us: [], idx: [], com: [] }, drawings: {}, alerts: [] }
    const localEdit = T0 + 10 * MIN // 真实时间 T0，比云端旧
    pcMergeFirst(s, store, ctx, { settings: localEdit, favorites: localEdit }, false)
    expect(s.watch.crypto).toEqual(['ETHUSDT'])
    expect(s.pinned).toEqual(['15m'])
  })
})

describe('中文底名的币安合约（币安人生USDT 这类）：代号规则与服务端 binance_symbol 一致', () => {
  const fav = (symbol: string, order: number) => ({ collection: 'favorites', id: 'binance/usd_m/' + symbol, body: { symbol, market: 'usd_m', venue: 'binance', groupId: null, order }, fields: {}, revision: 1, deleted: false, generation: 0 })

  it('代号判定：中文底名收、计价资产前没有底名不收、带下划线的交割 / 币本位不收（服务端也不收）', async () => {
    const { validSymbol } = await import('../src/sync/codec')
    expect(validSymbol('币安人生USDT')).toBe(true)
    expect(validSymbol('我踏马来了USDT')).toBe(true)
    expect(validSymbol('BTCUSDT')).toBe(true)
    expect(validSymbol('USDT')).toBe(false)
    expect(validSymbol('btcusdt')).toBe(false)
    expect(validSymbol('BTCUSD_PERP')).toBe(false)
    expect(validSymbol('币安 人生USDT')).toBe(false)
    expect(validSymbol('币'.repeat(37) + 'USDT')).toBe(false) // 41 个字
    expect(validSymbol('币'.repeat(36) + 'USDT')).toBe(true) // 40 个字（字节数远超 40）
  })

  it('PC 网页：云端有 iOS 加的「币安人生USDT」自选，网页推自选时不再把它当成被删掉', async () => {
    const { encodeFavorites, decodeFavorites } = await import('../src/sync/codec')
    const kctx = { ...ctx, kindOf: (s: string) => (s === '币安人生USDT' || s === 'BTCUSDT' || s === 'ETHUSDT' ? 'crypto' as const : ctx.kindOf(s)) }
    const cloud = [fav('BTCUSDT', 0), fav('币安人生USDT', 1)]
    const watch = decodeFavorites(cloud, kctx)
    expect(watch.crypto).toEqual(['BTCUSDT', '币安人生USDT'])
    watch.crypto.push('ETHUSDT')
    const out = encodeFavorites(watch, cloud, kctx)
    expect(out.filter(o => o.deleted).map(o => o.id)).toEqual([])
    expect(out.filter(o => !o.deleted).map(o => o.body.symbol)).toEqual(['BTCUSDT', '币安人生USDT', 'ETHUSDT'])
  })

  it('手机网页：云端的中文底名自选装得进来，本机加的也推得上去', () => {
    const local = { favorites: [] as string[], groups: [], groupForSymbol: {} }
    const got = C.decodeFavorites([fav('币安人生USDT', 0)], [], local)
    expect(got.favorites).toEqual(['币安人生USDT'])
    const out = C.encodeFavorites({ favorites: ['龙虾USDT'], groups: [], groupForSymbol: {} }, [], [])
    expect(out.filter(o => o.collection === 'favorites' && !o.deleted).map(o => o.body.symbol)).toEqual(['龙虾USDT'])
  })

  it('手机网页画线：中文底名的桶键可以上云，带下划线的币本位代号不上（服务端会整条 400）', async () => {
    const { syncableKey } = await import('../src/m/app/drawCodec')
    expect(syncableKey('binance/usd_m/币安人生USDT')).toBe(true)
    expect(syncableKey('binance/usd_m/BTCUSDT')).toBe(true)
    expect(syncableKey('coinbase/spot/BTC-USD')).toBe(true)
    expect(syncableKey('binance/usd_m/BTCUSD_PERP')).toBe(false)
    // 服务端 identity 2026-10-08 起按 venue / market 认那一家的代号形状（原来不分交易所、照收）：币安段里的 Coinbase 代号不收
    expect(syncableKey('binance/usd_m/BTC-USD')).toBe(false)
    expect(syncableKey('okx/usd_m/BTCUSDT')).toBe(true)
    expect(syncableKey('hyperliquid/usd_m/KPEPE')).toBe(true)
    expect(syncableKey('kraken/spot/BTC-USD')).toBe(false)
  })
})

describe('手机网页当前品种', () => {
  it('停在中文底名合约上刷新，回来还是它，不跳回 BTC', async () => {
    const { hydrate } = await import('../src/m/app/store')
    expect(hydrate({ symbol: '币安人生USDT' }).symbol).toBe('币安人生USDT')
    expect(hydrate({ symbol: 'ETHUSDT' }).symbol).toBe('ETHUSDT')
    expect(hydrate({ symbol: '<img src=x>' }).symbol).toBe('BTCUSDT')
  })
})
