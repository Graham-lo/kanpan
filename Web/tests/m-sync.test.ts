/* 手机网页版同步：st ↔ 云端对象（m/app/syncCodec.ts）。照 iOS PersonalSyncCodec / AppAccountBridge / SettingsStamp。
 * 两台「手机网页」接同一个假服务端（tests/sync-fake.ts，合并规则照 kanpan-api sync.rs）来回。 */
import { describe, expect, it } from 'vitest'
import { makePriceAlert, type Alert } from '../src/alerts/shape'
import { defaultPrefs, settleIndicatorLayouts, layoutSnapshot, type Prefs } from '../src/m/app/prefs'
import type { SymbolPrefs } from '../src/m/app/store'
import * as C from '../src/m/app/syncCodec'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { alertId, decodeAlerts, encodeAlerts, unseenDrawings } from '../src/sync/codec'
import { emptyArchive, keyOf, same, type SyncObject } from '../src/sync/types'
import { FakeServer } from './sync-fake'

interface Dev { p: Prefs; sym: SymbolPrefs; alerts: Alert[] }
const dev = (): Dev => ({ p: defaultPrefs(), sym: { favorites: ['BTCUSDT'], recents: [], groups: [], groupForSymbol: {}, seeded: true }, alerts: [] })

/** 一台「手机网页」：st + 账本 + 引擎。逻辑与 m/app/sync.ts 的适配器同一套（指纹 → 编码 → 记账；应用 → 解码） */
function phone(server: FakeServer, s = dev()) {
  const store = new SyncStore(emptyArchive(), 'dev-' + Math.random(), () => server.now)
  let fp: Record<string, string> = {}
  let initial = true
  const spent = new Set<string>()
  const prints = () => ({ settings: JSON.stringify(C.settingsSubs(s.p)), favorites: C.favPrint(s.sym), alerts: JSON.stringify(s.alerts) })
  const capture = (): number => {
    const now = prints(); const vals: SyncObject[] = []
    if (now.settings !== fp.settings) { const o = C.encodeSettings(s.p, store.get('settings', C.SETTINGS_ID), store.a.seen); if (o) vals.push(o); fp.settings = now.settings }
    if (now.favorites !== fp.favorites) { vals.push(...C.encodeFavorites(s.sym, store.localOf('favorites'), store.localOf('groups'))); fp.favorites = now.favorites }
    if (now.alerts !== fp.alerts) { vals.push(...encodeAlerts(s.alerts, store.localOf('alerts'), unseenDrawings(store.localOf('drawings')), spent)); fp.alerts = now.alerts }
    return store.capture(vals, C.OWNED_M)
  }
  const fired: Alert[] = []
  const apply = (): void => {
    const u = store.a.unapplied
    if (u.has('settings')) C.applySettings(s.p, store.get('settings', C.SETTINGS_ID), store.a.seen)
    let merged: Record<string, string> = {}
    if (u.has('favorites') || u.has('groups')) { const d = C.decodeFavorites(store.localOf('favorites'), store.localOf('groups'), s.sym); merged = d.merged; Object.assign(s.sym, { favorites: d.favorites, groups: d.groups, groupForSymbol: d.groupForSymbol }) }
    let f: Alert[] = []
    if (u.has('alerts')) { f = C.remoteFired(s.alerts, id => store.get('alerts', id)); s.alerts = decodeAlerts(store.localOf('alerts'), s.alerts, unseenDrawings(store.localOf('drawings'))) }
    u.clear()
    fp = prints()
    if (Object.keys(merged).length) delete fp.favorites
    for (const a of f) { spent.add(alertId(a.symbol, a.id)); fired.push(a); delete fp.alerts }
    capture()
  }
  const engine = new Engine(store, server.transport(), C.OWNED_M, { capture: () => { if (!initial) capture() }, apply: () => { if (!initial) apply() } })
  return {
    s, store, engine, fired, spent,
    async first(edited: { settings: Record<string, number>; favorites: number } = { settings: {}, favorites: 0 }, override = false) {
      await engine.full()
      store.a.seen = {}
      C.mergeSettings(s.p, store.get('settings', C.SETTINGS_ID), store.a.seen, edited.settings, override)
      const fav = C.mergeFavorites(s.sym, store.localOf('favorites'), store.localOf('groups'), edited.favorites, override, () => ({ favorites: [], groups: [], groupForSymbol: {} }))
      if (fav) Object.assign(s.sym, { favorites: fav.favorites, groups: fav.groups, groupForSymbol: fav.groupForSymbol })
      s.alerts = C.mergeAlerts(s.alerts, store.localOf('alerts'), store.localOf('drawings'), override, id => !!store.a.objects[keyOf('alerts', id)])
      store.a.unapplied.clear()
      initial = false; fp = {}
      capture()
      await engine.push()
    },
    async sync() { await engine.push(); await engine.pull(); await engine.push() },
    capture,
    /** 像 store.save() 一样：改完顶层指标先理顺分组 */
    edit(fn: (p: Prefs) => void) { const before = layoutSnapshot(s.p); fn(s.p); settleIndicatorLayouts(s.p, before) },
  }
}

const settingsOnServer = (server: FakeServer) => server.objects.get('settings:chart')!

describe('settings 编码（照 iOS PrefsCodec / PersonalSyncCodec.flatten）', () => {
  it('31 个根一个不少；嵌套根拍平；颜色是 {value}；subInverted 排好序', () => {
    const p = defaultPrefs()
    p.indicatorColors = { MA: { 0: '#112233' } } as Prefs['indicatorColors']
    p.subInverted = ['RSI', 'MACD']
    p.params = { MA: [5, 10] }
    const b = C.settingsBody(p)
    for (const r of C.ROOTS) if (!['params', 'indicatorColors', 'subHeightOverrides', 'indicatorLayouts'].includes(r)) expect(b).toHaveProperty(r)
    expect(b['indicatorColors/MA/0']).toEqual({ value: '#112233' })
    expect(b['params/MA']).toEqual([5, 10])
    expect(b.subInverted).toEqual(['MACD', 'RSI'])
    expect(Object.keys(b).some(k => k.startsWith('indicatorLayouts'))).toBe(false)
  })

  it('分叉的组写 indicatorLayouts/<组>（整份六键），顶层写共用那份', () => {
    const p = defaultPrefs()
    p.interval = '5m'
    const before = layoutSnapshot(p)
    p.overlays = ['EMA']
    settleIndicatorLayouts(p, before)
    const b = C.settingsBody(p)
    expect(b.overlays).toEqual(defaultPrefs().overlays)
    expect((b['indicatorLayouts/minute'] as { overlays: string[] }).overlays).toEqual(['EMA'])
    expect(Object.keys(b['indicatorLayouts/minute'] as object).sort()).toEqual(['candleKind', 'overlays', 'params', 'priceMode', 'subHeightOverrides', 'subs'])
  })
})

describe('两台来回', () => {
  it('A 改皮肤、涨跌色、钉住周期、指标参数与颜色：B 拉到同样的样子；没改动时不产生操作', async () => {
    const server = new FakeServer()
    const a = phone(server), b = phone(server)
    await a.first(); await b.first()
    a.s.p.skin = 'terra'; a.s.p.redUp = false; a.s.p.quickIntervals = ['1m', '4h']
    a.edit(p => { p.params = { ...p.params, MA: [7, 25, 99] } })
    a.s.p.indicatorColors = { MA: { 1: '#abcdef' } } as Prefs['indicatorColors']
    a.capture(); await a.sync()
    await b.sync()
    expect(b.s.p.skin).toBe('terra')
    expect(b.s.p.redUp).toBe(false)
    expect(b.s.p.quickIntervals).toEqual(['1m', '4h'])
    expect(b.s.p.params.MA).toEqual([7, 25, 99])
    expect(b.s.p.indicatorColors).toEqual({ MA: { 1: '#abcdef' } })
    const n = server.pushes.length
    await a.sync(); await b.sync()
    expect(server.pushes.length).toBe(n)
  })

  it('清掉一个颜色：那条路径发 null（服务端删掉），另一台跟着清', async () => {
    const server = new FakeServer()
    const a = phone(server), b = phone(server)
    a.s.p.indicatorColors = { MA: { 0: '#111111', 1: '#222222' } } as Prefs['indicatorColors']
    await a.first({ settings: { indicatorColors: 1 }, favorites: 0 }); await b.first()
    expect(b.s.p.indicatorColors).toEqual({ MA: { 0: '#111111', 1: '#222222' } })
    a.s.p.indicatorColors = { MA: { 1: '#222222' } } as Prefs['indicatorColors']
    a.capture(); await a.sync(); await b.sync()
    expect(settingsOnServer(server).body['indicatorColors/MA/0']).toBeNull()
    expect(b.s.p.indicatorColors).toEqual({ MA: { 1: '#222222' } })
  })

  it('分叉 / 回到共用跟着走：A 的分钟组分叉，B 在日线上看不到变化，切到 5 分才看到', async () => {
    const server = new FakeServer()
    const a = phone(server), b = phone(server)
    await a.first(); await b.first()
    a.edit(p => { p.interval = '5m' })
    a.edit(p => { p.overlays = ['BOLL'] })
    a.capture(); await a.sync(); await b.sync()
    expect(b.s.p.interval).toBe('5m') // interval 也跟人走
    expect(b.s.p.overlays).toEqual(['BOLL'])
    b.edit(p => { p.interval = '1d' })
    expect(b.s.p.overlays).toEqual(defaultPrefs().overlays)
    b.capture(); await b.sync(); await a.sync()
    expect(a.s.p.interval).toBe('1d')
    expect(a.s.p.overlays).toEqual(defaultPrefs().overlays)
    expect(a.s.p.indicatorLayouts.others.minute?.overlays).toEqual(['BOLL'])
  })

  it('iOS 写了本机认不得的子路径（更新版的新指标）：记账时原样留着，不发 null', async () => {
    const server = new FakeServer()
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'classic', 'params/NEWIND': [3] }, deleted: false })
    const a = phone(server)
    await a.first()
    expect(a.s.p.skin).toBe('classic')
    a.edit(p => { p.params = { ...p.params, MA: [9] } })
    a.capture(); await a.sync()
    expect(settingsOnServer(server).body['params/NEWIND']).toEqual([3])
    // 改指标参数 = 当前组（小时）分叉，照 iOS settleIndicatorLayouts
    expect((settingsOnServer(server).body['indicatorLayouts/hour'] as { params: Record<string, number[]> }).params.MA).toEqual([9])
  })

  it('云端的值本机表达不了（未知皮肤）：不装、也不把本机的推回去盖掉', async () => {
    const server = new FakeServer()
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'future', redUp: false }, deleted: false })
    const a = phone(server)
    await a.first()
    expect(a.s.p.skin).toBe('sage')
    expect(a.s.p.redUp).toBe(false)
    a.s.p.theme = 'dark'; a.capture(); await a.sync()
    expect(settingsOnServer(server).body.skin).toBe('future')
    expect(settingsOnServer(server).body.theme).toBe('dark')
  })
})

describe('第一次对上（照 iOS SettingsStamp：按根比谁新）', () => {
  it('本机没改过：云端的设置装进来；本机改得比云端新的根留本机的并推上去', async () => {
    const server = new FakeServer()
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'terra', redUp: false }, deleted: false })
    const a = phone(server)
    a.s.p.redUp = true; a.s.p.skin = 'classic'
    await a.first({ settings: { skin: server.now + 10 }, favorites: 0 })
    expect(a.s.p.skin).toBe('classic')
    expect(a.s.p.redUp).toBe(false)
    expect(settingsOnServer(server).body.skin).toBe('classic')
  })

  it('上一次同步的是另一个账号：云端整体覆盖', async () => {
    const server = new FakeServer()
    server.put({ collection: 'settings', id: 'chart', body: { skin: 'terra' }, deleted: false })
    const a = phone(server)
    a.s.p.skin = 'classic'
    await a.first({ settings: { skin: server.now + 10 }, favorites: server.now + 10 }, true)
    expect(a.s.p.skin).toBe('terra')
  })
})

describe('自选与分类（照 iOS SymbolPrefs）', () => {
  it('分类、归属、顺序来回；Coinbase 那几条原位留着', async () => {
    const server = new FakeServer()
    server.put({ collection: 'favorites', id: 'coinbase/spot/BTC-USD', body: { symbol: 'BTC-USD', market: 'spot', venue: 'coinbase', groupId: null, order: 0 }, deleted: false })
    const a = phone(server), b = phone(server)
    await a.first(); await b.first()
    a.s.sym.groups = [{ id: 'g1', name: '加密' }]
    a.s.sym.favorites = ['ETHUSDT', 'BTCUSDT']
    a.s.sym.groupForSymbol = { ETHUSDT: 'g1' }
    a.capture(); await a.sync(); await b.sync()
    expect(b.s.sym.favorites).toEqual(['ETHUSDT', 'BTCUSDT'])
    expect(b.s.sym.groups).toEqual([{ id: 'g1', name: '加密' }])
    expect(b.s.sym.groupForSymbol).toEqual({ ETHUSDT: 'g1' })
    const cb = server.objects.get('favorites:coinbase/spot/BTC-USD')!
    expect(cb.deleted).toBe(false)
    expect(cb.body.order).toBe(0)
    a.s.sym.favorites = ['BTCUSDT']; a.s.sym.groupForSymbol = {}
    a.capture(); await a.sync(); await b.sync()
    expect(server.objects.get('favorites:binance/usd_m/ETHUSDT')!.deleted).toBe(true)
    expect(b.s.sym.favorites).toEqual(['BTCUSDT'])
  })

  it('两台各建了一个同名分类：并成 id 小的那个，成员跟过去，多出来的那个删掉', async () => {
    const server = new FakeServer()
    server.put({ collection: 'groups', id: 'b-2', body: { name: '美股', order: 0 }, deleted: false })
    server.put({ collection: 'groups', id: 'a-1', body: { name: '美股 ', order: 1 }, deleted: false })
    server.put({ collection: 'favorites', id: 'binance/usd_m/NVDAUSDT', body: { symbol: 'NVDAUSDT', market: 'usd_m', venue: 'binance', groupId: 'b-2', order: 0 }, deleted: false })
    const a = phone(server)
    await a.first()
    expect(a.s.sym.groups.map(g => g.id)).toEqual(['a-1'])
    expect(a.s.sym.groupForSymbol).toEqual({ NVDAUSDT: 'a-1' })
    expect(server.objects.get('groups:b-2')!.deleted).toBe(true)
  })

  it('第一次对上：云端没有自选时留本机；本机改得新时本机做底、把云端的并进来', async () => {
    const server = new FakeServer()
    const a = phone(server)
    await a.first()
    expect(server.objects.get('favorites:binance/usd_m/BTCUSDT')).toBeTruthy()
    const b = phone(server, { ...dev(), sym: { favorites: ['SOLUSDT'], recents: [], groups: [], groupForSymbol: {}, seeded: true } })
    await b.first({ settings: {}, favorites: server.now + 100 })
    expect(b.s.sym.favorites).toEqual(['SOLUSDT', 'BTCUSDT'])
    const c = phone(server, { ...dev(), sym: { favorites: ['XRPUSDT'], recents: [], groups: [], groupForSymbol: {}, seeded: true } })
    await c.first()
    expect(c.s.sym.favorites).toEqual(['SOLUSDT', 'BTCUSDT']) // 本机没改过：云端的
  })
})

describe('提醒', () => {
  it('新建的推上去、另一台看到；本机响：先推「已触发」再删；服务端响的交出来报给人再删', async () => {
    const server = new FakeServer()
    const a = phone(server), b = phone(server)
    await a.first(); await b.first()
    const x = makePriceAlert('BTCUSDT', 120000, 100000, { now: server.now })
    a.s.alerts = [x]; a.capture(); await a.sync(); await b.sync()
    expect(b.s.alerts.map(y => y.id)).toEqual([x.id])
    // A 本机响（model/alerts.fire 的两步）
    const id = alertId('BTCUSDT', x.id)
    a.s.alerts = [{ ...x, status: 'fired', firedAt: server.now, firedPrice: 120001 }]
    a.capture(); a.spent.add(id); await a.engine.push()
    expect(server.objects.get('alerts:' + id)!.body.status).toBe('fired')
    a.s.alerts = []; a.capture(); await a.sync()
    expect(server.objects.get('alerts:' + id)!.deleted).toBe(true)
    await b.sync()
    expect(b.s.alerts).toEqual([])
    // 服务端判响
    const y = makePriceAlert('ETHUSDT', 5000, 4000, { now: server.now })
    b.s.alerts = [y]; b.capture(); await b.sync()
    const yid = alertId('ETHUSDT', y.id)
    const o = server.objects.get('alerts:' + yid)!
    server.put({ collection: 'alerts', id: yid, body: { ...o.body, status: 'fired', firedAt: server.now, firedPrice: 5001 }, deleted: false })
    await b.sync(); await b.sync()
    expect(b.fired.map(f => f.id)).toEqual([y.id])
    expect(b.s.alerts).toEqual([])
    expect(server.objects.get('alerts:' + yid)!.deleted).toBe(true)
  })
})

describe('mergeSameNamed / absorb', () => {
  it('同名留 id 最小的、站同名里最靠前的位置', () => {
    const r = C.mergeSameNamed([{ id: 'z', name: 'A' }, { id: 'm', name: 'B' }, { id: 'a', name: 'A' }])
    expect(r.groups).toEqual([{ id: 'a', name: 'A' }, { id: 'm', name: 'B' }])
    expect(r.merged).toEqual({ z: 'a' })
  })
  it('absorb 按名字并分类、按代号并自选', () => {
    const out = C.absorb({ favorites: ['A'], groups: [{ id: 'g1', name: '甲' }], groupForSymbol: { A: 'g1' } },
      { favorites: ['A', 'B', 'C'], groups: [{ id: 'g9', name: '甲' }, { id: 'g2', name: '乙' }], groupForSymbol: { A: 'g2', B: 'g9', C: 'g2' } })
    expect(out.favorites).toEqual(['A', 'B', 'C'])
    expect(out.groups.map(g => g.id)).toEqual(['g1', 'g2'])
    expect(out.groupForSymbol).toEqual({ A: 'g1', B: 'g1', C: 'g2' })
    expect(same(out.groups, [{ id: 'g1', name: '甲' }, { id: 'g2', name: '乙' }])).toBe(true)
  })
})
