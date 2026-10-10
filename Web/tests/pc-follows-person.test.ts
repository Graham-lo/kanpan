/* 电脑网页「用手改出来的习惯跟着人走」（2026-10-10）：画线扩展样式、条件提醒的品种门槛、
 * 与手机上限不同的那几项（周期条 / 副图 / 参数）、接上手机已有的共用字段、网页独有 webPrefs、每格对数与根宽。 */
import { describe, expect, it } from 'vitest'
import type { Drawing } from '../src/chart/chart'
import { cleanStyle } from '../src/chart/drawStyle'
import { cleanDrawing } from '../src/chart/drawTools'
import { conditionAlertsOk, decodeDrawings, drawingId, encodeDrawings, syncableAlert } from '../src/sync/codec'
import { makeConditionAlert, makePriceAlert } from '../src/alerts/shape'
import { OWNED, adoptNewSettings, applyInto, captureInto, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { SETTINGS_ID, encodeSettings, applySettings } from '../src/sync/codec'
import { buildWebPrefs, cleanWebPrefs, WEB_PREFS_MAX_BYTES } from '../src/sync/webPrefs'
import { DEFAULTS as CHART_DEFAULTS } from '../src/chart/chartSettings'
import type { Edited } from '../src/sync/bridge'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { COLLECTIONS, emptyArchive, type SyncObject } from '../src/sync/types'
import { DP_COLLECTION, DP_ID, DP_READY } from '../src/sync/drawPrefs'
import { drawPrefsPending, wantDrawPrefs, adoptDrawPrefs } from '../src/sync/bridge'
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

/** 一台「网页」：页面状态 + 账本 + 引擎，接同一个假服务端（同 tests/sync-bridge 的 browser） */
function device(server: FakeServer, s: WebState) {
  const store = new SyncStore(emptyArchive(), 'dev-' + Math.random(), () => server.now)
  const fp: Prints = {}
  let initial = true
  const engine = new Engine(store, server.transport(), OWNED, {
    capture: () => { if (!initial) captureInto(s, store, ctx, fp) },
    apply: () => { if (!initial) applyInto(s, store, ctx) },
  }, [...COLLECTIONS, DP_COLLECTION])
  return {
    s, store, engine, fp,
    async first(edited: Edited = { settings: 0, favorites: 0 }, override = false) {
      await engine.full()
      mergeFirst(s, store, ctx, edited, override)
      initial = false
      captureInto(s, store, ctx, fp)
      await engine.push()
    },
    async sync() { await engine.push(); await engine.pull(); await engine.push() },
  }
}
const SKEY = 'settings:' + SETTINGS_ID
/** 手机推一次设置：它的 stage 只改自己认识的字段，webPrefs 这类不认识的原样带回 */
function phonePush(server: FakeServer, patch: Record<string, unknown>) {
  server.now += 1000
  const o = server.objects.get(SKEY)!
  server.put({ collection: 'settings', id: SETTINGS_ID, body: { ...o.body, ...patch } as SyncObject['body'], deleted: false })
}
const ALL9 = ['1m', '3m', '5m', '15m', '30m', '1h', '2h', '4h', '1d']
const desk = (): WebState => ({
  ...base(),
  pinned: [...ALL9],
  ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd', 'rsi', 'kdj', 'atr', 'cvd', 'dmi', 'stochrsi', 'oi'] },
  params: { ma: { periods: [5, 2000] }, macd: { fast: 12, slow: 26, signal: 9 } },
})

describe('B6 与手机上限不同的那几项：共用字段只装手机能表达的，多出来的进 webPrefs', () => {
  it('电脑钉 9 个周期、开 8 个副图、均线周期 2000：共用字段只装头 6 / 头 3、不推表达不了的参数，整份进 webPrefs', async () => {
    const server = new FakeServer()
    const a = device(server, desk())
    await a.first()
    const b = server.objects.get(SKEY)!.body
    expect(b.quickIntervals).toEqual(ALL9.slice(0, 6))
    expect(b.subs).toEqual(['VOL', 'MACD', 'RSI', 'KDJ'])
    expect(b['params/MA']).toBeUndefined()
    expect(b['params/MACD']).toEqual([12, 26, 9])
    const wp = b.webPrefs as { pins: string[]; subs: string[]; params: Record<string, unknown> }
    expect(wp.pins).toEqual(ALL9)
    expect(wp.subs).toEqual(desk().ind.subs)
    expect(wp.params.ma).toEqual({ periods: [5, 2000] })
  })

  it('手机推 3 副图 / 6 周期后电脑不丢自己的多余项，也不把多余的挤回头部推回去', async () => {
    const server = new FakeServer()
    const a = device(server, desk())
    await a.first()
    phonePush(server, { quickIntervals: ['5m', '15m', '1h', '4h', '1d', '1w'], subs: ['VOL', 'RSI', 'MACD', 'OI'] })
    const before = server.pushes.length
    await a.sync()
    // 头 6 个换成手机的（1w 补进来），电脑多钉的 2h 留着；出厂顺序排
    expect(a.s.pinned).toEqual(['5m', '15m', '1h', '2h', '4h', '1d', '1w'])
    // 头三个共用的（macd / rsi / kdj）换成手机的 rsi / macd / oi，电脑多开的 atr / cvd / dmi / stochrsi 原地留着
    expect(a.s.ind.subs).toEqual(['rsi', 'macd', 'oi', 'atr', 'cvd', 'dmi', 'stochrsi'])
    const cloud = server.objects.get(SKEY)!.body
    // 共用字段还是手机那份（没被电脑的多余项回推冲掉）
    expect(cloud.quickIntervals).toEqual(['5m', '15m', '1h', '4h', '1d', '1w'])
    expect(cloud.subs).toEqual(['VOL', 'RSI', 'MACD', 'OI'])
    // webPrefs 跟着换成电脑装完的整份
    expect((cloud.webPrefs as { subs: string[] }).subs).toEqual(a.s.ind.subs)
    expect(server.pushes.slice(before).flat().every(op => !('quickIntervals' in op.fields) && !('subs' in op.fields))).toBe(true)
  })

  it('另一台电脑从 webPrefs 拿到整份（9 个周期、8 个副图、周期 2000）', async () => {
    const server = new FakeServer()
    const a = device(server, desk())
    await a.first({ settings: Date.now(), favorites: 0 })
    const b = device(server, base())
    await b.first()
    expect(b.s.pinned).toEqual(ALL9)
    expect(b.s.ind.subs).toEqual(desk().ind.subs)
    expect(b.s.params?.ma).toEqual({ periods: [5, 2000] })
  })

  it('参数：电脑这份手机表达不了时以 webPrefs 为准，手机推的不装；能表达的照常装', async () => {
    const server = new FakeServer()
    const a = device(server, desk())
    await a.first()
    phonePush(server, { 'params/MA': [7, 25], 'params/MACD': [10, 30, 9] })
    await a.sync()
    expect(a.s.params?.ma).toEqual({ periods: [5, 2000] })
    expect(a.s.params?.macd).toEqual({ fast: 10, slow: 30, signal: 9 })
  })
})

describe('网页独有 webPrefs', () => {
  it('主题 / 皮肤 / 联动 / 面板 / 画线锁 往返；手机推设置不冲掉它', async () => {
    const server = new FakeServer()
    const s: WebState = { ...base(), theme: 'dark', skin: 'terra', linkSymbol: true, panel: 'alerts', drawLocked: true, vpvrMode: 'delta' }
    const a = device(server, s)
    await a.first({ settings: Date.now(), favorites: 0, webPrefs: Date.now() })
    phonePush(server, { subs: ['VOL'] })
    await a.sync()
    const b = device(server, { ...base(), theme: 'light', skin: 'sage', linkSymbol: false, panel: 'watch', drawLocked: false, vpvrMode: 'split' })
    await b.first()
    expect([b.s.theme, b.s.skin, b.s.linkSymbol, b.s.panel, b.s.drawLocked, b.s.vpvrMode]).toEqual(['dark', 'terra', true, 'alerts', true, 'delta'])
  })

  it('坏值逐项丢、整份超过 8 KB 不收；拼出来超了按顺序丢大块', () => {
    expect(cleanWebPrefs({ theme: 'x'.repeat(WEB_PREFS_MAX_BYTES) })).toBeNull()
    expect(cleanWebPrefs([1])).toBeNull()
    const s: WebState = { ...base(), theme: 'neon' as never }
    applySettings(s, { collection: 'settings', id: SETTINGS_ID, body: { webPrefs: { theme: 'neon', skin: 'terra', panel: 'nope' } }, fields: {}, revision: 1, deleted: false, generation: 0 }, {})
    expect(s.skin).toBe('terra')
    expect(s.panel).toBeUndefined()
    // 画线样式塞满：超了先丢 toolLast / drawStyles，主题等小项还在
    const big: WebState = { ...base(), theme: 'dark', drawStyles: Object.fromEntries(Array.from({ length: 400 }, (_, i) => ['k' + i, { color: '#112233', width: 2 }])) }
    const wp = buildWebPrefs(big as never) as Record<string, unknown>
    expect(new TextEncoder().encode(JSON.stringify(wp)).length).toBeLessThanOrEqual(WEB_PREFS_MAX_BYTES)
    expect(wp.drawStyles).toBeUndefined()
    expect(wp.theme).toBe('dark')
  })
})

describe('接上手机已有的共用字段', () => {
  it('订单流 / 图上大单标记 / 红涨绿跌 / 板块市场与窗口：编码进共用字段，装回来同一个样子', () => {
    const s: WebState = { ...base(), orderFlow: true, bigTradeSigns: false, updown: 'red-up', sectorMarket: 'us', sectorWindow: 'd5' }
    const o = encodeSettings(s, undefined, {})!
    expect([o.body.orderFlow, o.body.bigTradeSigns, o.body.redUp, o.body.sectorMarket, o.body.sectorWindow]).toEqual([true, false, true, 'us', 'd5'])
    const t: WebState = { ...base(), orderFlow: false, bigTradeSigns: true, updown: 'green-up', sectorMarket: 'crypto', sectorWindow: 'today', chartSettings: { ...CHART_DEFAULTS, bodyUp: '#00FF00' } }
    applySettings(t, o, {})
    expect([t.orderFlow, t.bigTradeSigns, t.updown, t.sectorMarket, t.sectorWindow]).toEqual([true, false, 'red-up', 'us', 'd5'])
    // 换了涨跌配色：K 线涨跌色的覆盖清掉（同「我的」里切换）
    expect(t.chartSettings?.bodyUp).toBeNull()
    // 手机的 20 日网页没有：不装
    applySettings(t, { ...o, body: { sectorWindow: 'd20' } }, {})
    expect(t.sectorWindow).toBe('d5')
  })

  it('VWAP / 超级趋势 / SAR 进主图共用字段，累计量差 / 动向指标进副图，参数 ST / DMI 跟着走', () => {
    const s: WebState = { ...base(), ind: { ma: true, ema: false, boll: false, vol: true, subs: ['cvd', 'dmi'], vwap: true, st: true, mains: ['sar'] }, params: { st: { n: 10, k: 3 }, dmi: { n: 14, m1: 6 } } as never }
    const o = encodeSettings(s, undefined, {})!
    expect(o.body.overlays).toEqual(['MA', 'VWAP', 'ST', 'SAR'])
    expect(o.body.subs).toEqual(['VOL', 'CVD', 'DMI'])
    expect(o.body['params/ST']).toEqual([10, 3])
    expect(o.body['params/DMI']).toEqual([14])
    const t = base()
    applySettings(t, o, {})
    expect(t.ind.vwap && t.ind.st).toBe(true)
    expect(t.ind.mains).toEqual(['sar'])
    expect(t.params?.st).toEqual({ n: 10, k: 3 })
  })

  it('升级后第一次续上：本机以前只存本机的开关（订单流开着、VWAP 开着）不被云端「没有」关掉，下一次记账推上去', async () => {
    const server = new FakeServer()
    const a = device(server, base())
    await a.first()
    // 模拟老版本账本：seen 里还没有这一版新接的字段
    for (const f of ['webPrefs', 'orderFlow', 'bigTradeSigns', 'redUp', 'sectorMarket', 'sectorWindow', 'params/ST', 'params/DMI']) delete a.store.a.seen[f]
    a.store.a.seen.overlays = ['MA']
    a.s.orderFlow = true
    a.s.ind.vwap = true
    adoptNewSettings(a.s, a.store)
    expect(a.s.orderFlow).toBe(true)
    expect(a.s.ind.vwap).toBe(true)
    await a.sync()
    const b = server.objects.get(SKEY)!.body
    expect(b.orderFlow).toBe(true)
    expect(b.overlays).toEqual(['MA', 'VWAP'])
  })
})

describe('webPrefs 里别的模块登记的块', () => {
  it('订单流偏好（不含「显示」那组）、副图比例与网格比例：读出整份，装回来落进各自模块', async () => {
    const { OF } = await import('../src/orderflow/state')
    const { sizes } = await import('../src/app/sizes')
    OF.prefs.heat = true; OF.prefs.bookUnit = 'coin'; OF.prefs.tapeMin = { BTC: 50000 }
    sizes.panes = { macd: 0.123456789 }; sizes.grid = { '4': { cols: [0.6, 0.4] } }
    const wp = buildWebPrefs(base() as never) as Record<string, Record<string, unknown>>
    expect(wp.of).toMatchObject({ heat: true, bookUnit: 'coin', tapeMin: { BTC: 50000 } })
    expect(wp.of.display).toBeUndefined()
    expect(wp.panes).toEqual({ macd: 0.1235 })
    expect(wp.grid).toEqual({ '4': { cols: [0.6, 0.4] } })
    const s = base()
    applySettings(s, { collection: 'settings', id: SETTINGS_ID, body: { webPrefs: { of: { heat: false, bookUnit: 'x', band: 5, display: { walls: false } }, panes: { rsi: 0.2, bad: 7 }, grid: { '4': { rows: [1, 'x'] } } } }, fields: {}, revision: 1, deleted: false, generation: 0 }, {})
    expect([OF.prefs.heat, OF.prefs.bookUnit, OF.prefs.band]).toEqual([false, 'usd', 5])
    expect(OF.prefs.tapeMin).toEqual({})
    expect(sizes.panes).toEqual({ rsi: 0.2 })
    expect(sizes.grid).toBeUndefined()
  })

  it('老存档没有「图上大单标记」：照以前订单流那颗开关的样子；全新的按出厂（开）', async () => {
    const { hydrate } = await import('../src/app/store')
    expect(hydrate({ orderFlow: false }).bigTradeSigns).toBe(false)
    expect(hydrate({ orderFlow: true }).bigTradeSigns).toBe(true)
    expect(hydrate({}).bigTradeSigns).toBe(true)
    expect(hydrate({ orderFlow: false, bigTradeSigns: true }).bigTradeSigns).toBe(true)
  })
})

describe('画线工具偏好 drawingPreferences（磁吸、同族样式、线那一组的画法）', () => {
  const DKEY = DP_COLLECTION + ':' + DP_ID
  const phoneDp = (server: FakeServer, patch: Record<string, unknown>) => {
    server.now += 1000
    const o = server.objects.get(DKEY)
    server.put({ collection: DP_COLLECTION, id: DP_ID, body: { ...(o?.body ?? {}), ...patch } as SyncObject['body'], deleted: false })
  }
  const dpState = (x: Partial<WebState> = {}): WebState => ({ ...base(), magnet: true, drawStyles: {}, toolLast: {}, ...x })

  it('网页改了「线」那一族的颜色与线宽：这一族每个 kind 都写上，线宽夹到 6，手机的收藏 / 连续画 / 填色与刻度原样留着', async () => {
    const server = new FakeServer()
    phoneDp(server, { favorites: ['trend'], continuous: true, magnet: true, 'styles/hline': { lineWidth: 1, dash: 'solid', filled: false, levels: [] } })
    const a = device(server, dpState())
    await a.first()
    a.s.drawStyles = { lines: { color: '#FF0000', width: 8 } }
    await a.sync()
    const b = server.objects.get(DKEY)!.body
    expect(b.favorites).toEqual(['trend'])
    expect(b.continuous).toBe(true)
    for (const k of ['trend', 'ray', 'extended', 'hline', 'hray', 'vline', 'crossLine', 'arrowLine']) expect(b['styles/' + k]).toMatchObject({ color: { value: '#FF0000' }, lineWidth: 6, dash: 'solid' })
    expect(b['styles/hline']).toMatchObject({ filled: false, levels: [] })
    expect(b['styles/fibonacci']).toBeUndefined()
  })

  it('手机改了一把（水平线）的样式：网页整族换成它，不把这一族别的 kind 回推', async () => {
    const server = new FakeServer()
    const a = device(server, dpState({ drawStyles: { lines: { color: '#FF0000', width: 2 } } }))
    await a.first()
    const before = server.pushes.length
    phoneDp(server, { 'styles/hline': { color: { value: '#00FF00' }, lineWidth: 3, dash: 'solid', filled: true, levels: [] } })
    await a.sync()
    expect(a.s.drawStyles!.lines).toEqual({ color: '#00FF00', width: 3 })
    expect(server.pushes.slice(before).flat().filter(op => op.collection === DP_COLLECTION)).toEqual([])
  })

  it('画法：网页线那一组用的是两端延伸 → variants/trend；手机把竖线换成十字线 → 网页那一组换成十字线', async () => {
    const server = new FakeServer()
    const a = device(server, dpState({ toolLast: { lines: 'extended' } }))
    await a.first()
    expect(server.objects.get(DKEY)!.body['variants/trend']).toBe('extended')
    phoneDp(server, { 'variants/vline': 'crossLine' })
    await a.sync()
    expect(a.s.toolLast!.lines).toBe('crossLine')
    // 再拉一次不反复装
    a.s.toolLast!.lines = 'trend'
    await a.sync()
    expect(a.s.toolLast!.lines).toBe('trend')
    expect(server.objects.get(DKEY)!.body['variants/trend']).toBe('trend')
  })

  it('磁吸：云端有就装云端的（手机设过关），云端没有就推本机的', async () => {
    const server = new FakeServer()
    phoneDp(server, { magnet: false })
    const a = device(server, dpState())
    await a.first()
    expect(a.s.magnet).toBe(false)
    const fresh = new FakeServer()
    const b = device(fresh, dpState({ magnet: false }))
    await b.first()
    expect(fresh.objects.get(DKEY)!.body.magnet).toBe(false)
    b.s.magnet = true
    await b.sync()
    expect(fresh.objects.get(DKEY)!.body.magnet).toBe(true)
  })

  it('升级前的老账本：对上之前不推（出厂磁吸不冲掉手机的关），等一次全量拉完再装云端的', async () => {
    const server = new FakeServer()
    phoneDp(server, { magnet: false })
    const a = device(server, dpState())
    await a.first()
    // 模拟老账本：从没对上过画线工具偏好、账本里也没有那张表
    for (const k of Object.keys(a.store.a.seen)) if (k.startsWith('dp:')) delete a.store.a.seen[k]
    delete a.store.a.local[DKEY]; delete a.store.a.objects[DKEY]
    a.s.magnet = true
    wantDrawPrefs(a.store)
    expect(a.store.a.seen[DP_READY]).toBeUndefined()
    expect(drawPrefsPending(a.store)).toBe(false)
    captureInto(a.s, a.store, ctx, a.fp)
    expect(a.store.a.operations.filter(op => op.collection === DP_COLLECTION)).toEqual([])
    await a.engine.full()
    expect(drawPrefsPending(a.store)).toBe(true)
    expect(adoptDrawPrefs(a.s, a.store)).toBe(true)
    expect(a.s.magnet).toBe(false)
    expect(drawPrefsPending(a.store)).toBe(false)
  })
})

describe('每格的对数坐标与根宽跟人走（chartLayouts 格子短键 log / bs）', () => {
  it('记：出厂值不写键；根宽留两位小数；改回出厂删键；返回改没改', async () => {
    const { writeCellView, cellView, CELL_BS_DEFAULT } = await import('../src/app/layouts')
    const { DEFAULT_SPACING } = await import('../src/chart/wheel')
    expect(CELL_BS_DEFAULT).toBe(DEFAULT_SPACING)
    const c: import('../src/app/layouts').CellCfg = { symbol: 'BTCUSDT', iv: '1h' }
    expect(writeCellView(c, { log: false, spacing: 6 })).toBe(false)
    expect(c).toEqual({ symbol: 'BTCUSDT', iv: '1h' })
    expect(writeCellView(c, { log: true, spacing: 13.3333333 })).toBe(true)
    expect(c).toEqual({ symbol: 'BTCUSDT', iv: '1h', log: true, bs: 13.33 })
    expect(writeCellView(c, { log: true, spacing: 13.331 })).toBe(false) // 同一个两位小数：不再落盘
    expect(cellView(c)).toEqual({ log: true, spacing: 13.33 })
    expect(writeCellView(c, { log: false, spacing: 6.001 })).toBe(true)
    expect(c).toEqual({ symbol: 'BTCUSDT', iv: '1h' })
    // 坏值读成出厂；超大的夹住
    expect(cellView({ symbol: 'X', iv: '1h', log: 'yes', bs: 'x' } as never)).toEqual({ log: false, spacing: 6 })
    expect(cellView({ symbol: 'X', iv: '1h', bs: 1e9 })).toEqual({ log: false, spacing: 2000 })
  })

  it('格子短键满 6 个时，对数坐标与根宽先占位（别的按字母排在后面的丢掉）', async () => {
    const { cleanCells } = await import('../src/app/layouts')
    const raw = [{ symbol: 'BTCUSDT', iv: '1h', a1: 1, a2: 1, a3: 1, a4: 1, a5: 1, a6: 1, bs: 9, log: true }]
    const [c] = cleanCells(raw)
    expect(c.bs).toBe(9); expect(c.log).toBe(true)
    expect(Object.keys(c).filter(k => !['symbol', 'iv'].includes(k))).toEqual(['a1', 'a2', 'a3', 'a4', 'bs', 'log'])
  })

  it('编码进 chartLayouts、换一台电脑装回来同一个样子；首次合并时只差缩放的本机布局不另存一份', async () => {
    const { mergeBooks, bookFrom } = await import('../src/app/layouts')
    type Book = import('../src/app/layouts').LayoutBook
    const cells = [{ symbol: 'BTCUSDT', iv: '1h', log: true, bs: 12.5 }, { symbol: 'ETHUSDT', iv: '4h' }]
    const s = { ...base(), layout: '2', cells, active: 0, layouts: bookFrom('2', cells) } as WebState
    const o = encodeSettings(s, undefined, {})!
    const book = o.body.chartLayouts as unknown as Book
    expect(book.sets[0].cells[0]).toEqual({ symbol: 'BTCUSDT', iv: '1h', bs: 12.5, log: true })
    const one = [{ symbol: 'BTCUSDT', iv: '1h' }]
    const t = { ...base(), layout: '1', cells: one, active: 0, layouts: bookFrom('1', one) } as WebState
    applySettings(t, o, {})
    expect(t.cells![0]).toMatchObject({ log: true, bs: 12.5 })
    // 本机那套只是多缩放了一下：和云端算同一套
    const local = bookFrom('2', [{ symbol: 'BTCUSDT', iv: '1h', bs: 30 }, { symbol: 'ETHUSDT', iv: '4h' }])
    expect(mergeBooks(book, local).sets).toHaveLength(1)
    // 出厂那一格只开了对数：仍算出厂，不另存
    expect(mergeBooks(book, bookFrom('1', [{ symbol: 'BTCUSDT', iv: '1h', log: true }])).sets).toHaveLength(1)
  })
})

describe('死字段 drawColor 删掉（带迁移）', () => {
  it('老存档里不是出厂蓝的：并进还没设颜色的各族样式，键删掉；出厂蓝的直接删', async () => {
    const { hydrate } = await import('../src/app/store')
    const { TOOL_GROUPS } = await import('../src/chart/drawTools')
    const s = hydrate({ drawColor: '#D500F9', drawStyles: { lines: { color: '#FF0000', width: 3 }, fib: { width: 2 } } } as never)
    expect('drawColor' in s).toBe(false)
    expect(s.drawStyles.lines).toEqual({ color: '#FF0000', width: 3 })
    expect(s.drawStyles.fib).toEqual({ width: 2, color: '#D500F9' })
    for (const g of TOOL_GROUPS) expect(s.drawStyles[g.id]?.color).toBeTruthy()
    const d = hydrate({ drawColor: '#2962ff' } as never)
    expect('drawColor' in d).toBe(false)
    expect(d.drawStyles).toEqual({})
  })
})
