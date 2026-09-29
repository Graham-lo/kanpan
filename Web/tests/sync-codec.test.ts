import { describe, expect, it } from 'vitest'
import type { Alert } from '../src/app/store'
import type { Drawing } from '../src/chart/chart'
import {
  ALERT_MARKET, SETTINGS_ID, applySettings, decodeAlerts, decodeDrawings, decodeFavorites, drawingId, encodeAlerts,
  encodeDrawings, encodeFavorites, encodeSettings, favId, pctToRatio, ratioToPct, type SettingsState,
} from '../src/sync/codec'
import type { SyncObject } from '../src/sync/types'
import { ctx } from './sync-fake'

const obj = (collection: string, id: string, body: SyncObject['body'], extra: Partial<SyncObject> = {}): SyncObject =>
  ({ collection, id, body, fields: {}, revision: 1, deleted: false, generation: 0, ...extra })

const settings = (): SettingsState => ({
  pinned: ['15m', '1h', '4h', '1d'],
  ind: { ma: true, ema: false, boll: false, vol: true, subs: ['macd'] },
  params: { ma: { periods: [7, 25, 99] }, macd: { fast: 12, slow: 26, signal: 9 } },
})

describe('百分数 ↔ 比值串', () => {
  it('不经过浮点除法', () => {
    expect(pctToRatio(0.05)).toBe('0.0005')
    expect(pctToRatio(1)).toBe('0.01')
    expect(pctToRatio(-0.01)).toBe('-0.0001')
    expect(pctToRatio(250)).toBe('2.5')
    expect(pctToRatio(0)).toBe('0')
    expect(pctToRatio(0.0123)).toBe('0.000123')
    expect(ratioToPct('0.000123')).toBe(0.0123)
  })
})

describe('settings', () => {
  it('编码只覆盖网页的字段，手机独有的周期与字段原样留着', () => {
    const prev = obj('settings', SETTINGS_ID, { quickIntervals: ['3d', '1h'], overlays: ['MA', 'SAR'], theme: 'dark', subs: ['VOL'] })
    const seen = {}
    const o = encodeSettings(settings(), prev, seen)!
    expect(o.body.theme).toBe('dark')
    expect(o.body.quickIntervals).toEqual(['3d', '1h', '15m', '4h', '1d'])
    // 手机独有的 SAR 原地不动，网页的 MA 保持
    expect(o.body.overlays).toEqual(['MA', 'SAR'])
    expect(o.body.subs).toEqual(['VOL', 'MACD'])
    expect(o.body['params/MA']).toEqual([7, 25, 99])
    expect(o.body['params/MACD']).toEqual([12, 26, 9])
    // 没改就不再产出
    expect(encodeSettings(settings(), o, seen)).toBeNull()
  })

  it('往返：编码出来的装回另一台是同一个样子', () => {
    const o = encodeSettings(settings(), undefined, {})!
    const other: SettingsState = { pinned: ['1h'], ind: { ma: false, ema: true, boll: false, vol: false, subs: [] }, params: null }
    const changed = applySettings(other, o, {})
    expect(changed.length).toBeGreaterThan(0)
    expect(other.pinned).toEqual(['15m', '1h', '4h', '1d'])
    expect(other.ind).toEqual(settings().ind)
    expect(other.params?.ma).toEqual({ periods: [7, 25, 99] })
    expect(other.params?.macd).toEqual({ fast: 12, slow: 26, signal: 9 })
  })

  it('云端值网页表达不了的不装也不推', () => {
    const s = settings(), seen = {}
    applySettings(s, obj('settings', SETTINGS_ID, { quickIntervals: ['3d'] }), seen)
    expect(s.pinned).toEqual(['15m', '1h', '4h', '1d'])
    expect(encodeSettings(s, obj('settings', SETTINGS_ID, { quickIntervals: ['3d'] }), seen)?.body.quickIntervals ?? ['3d']).toEqual(expect.arrayContaining(['3d']))
  })
})

describe('favorites', () => {
  it('编码按类别占位，Coinbase 等管不着的原地留着；解码回三个标签页', () => {
    const prev = [
      obj('favorites', favId('BTCUSDT'), { symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', groupId: 'g1', order: 0 }),
      obj('favorites', 'coinbase/spot/BTC-USD', { symbol: 'BTC-USD', market: 'spot', venue: 'coinbase', groupId: null, order: 1 }),
      obj('favorites', favId('NVDAUSDT'), { symbol: 'NVDAUSDT', market: 'usd_m', venue: 'binance', groupId: null, order: 2 }),
    ]
    const out = encodeFavorites({ crypto: ['ETHUSDT', 'BTCUSDT'], us: [], com: ['XAUUSDT'] }, prev, ctx)
    const live = out.filter(o => !o.deleted).sort((a, b) => (a.body.order as number) - (b.body.order as number))
    expect(live.map(o => o.id)).toEqual([favId('ETHUSDT'), 'coinbase/spot/BTC-USD', favId('BTCUSDT'), favId('XAUUSDT')])
    expect(live.find(o => o.id === favId('BTCUSDT'))!.body.groupId).toBe('g1')
    expect(live.find(o => o.id === favId('ETHUSDT'))!.body).toEqual({ symbol: 'ETHUSDT', market: 'usd_m', venue: 'binance', groupId: null, order: 0 })
    expect(out.find(o => o.id === favId('NVDAUSDT'))!.deleted).toBe(true)
    expect(out.some(o => o.id === 'coinbase/spot/BTC-USD' && o.deleted)).toBe(false)
    expect(decodeFavorites(out, ctx)).toEqual({ crypto: ['ETHUSDT', 'BTCUSDT'], us: [], com: ['XAUUSDT'] })
  })
})

describe('drawings', () => {
  const trend: Drawing = { id: 'd1', type: 'trend', pts: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: '#FF0000', width: 2 }

  it('编码形状照手机端，往返一致', () => {
    const [o] = encodeDrawings({ BTCUSDT: [trend] }, [])
    expect(o.id).toBe(drawingId('BTCUSDT', 'd1'))
    expect(o.body).toMatchObject({ kind: 'trend', anchors: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: { value: '#FF0000' }, lineWidth: 2, locked: false, symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', dash: 'solid', hidden: false })
    const back = decodeDrawings([o], {}, new Set())
    expect(back.BTCUSDT).toEqual([{ ...trend }])
  })

  it('没改的原样用云端 body；改了只覆盖网页的键，手机的文字和虚线留着', () => {
    const cloud = obj('drawings', drawingId('BTCUSDT', 'd1'), { kind: 'trend', anchors: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: { value: '#FF0000' }, lineWidth: 2, locked: false, symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', dash: 'dashed', text: '支撑', filled: true, hidden: false, levels: [] })
    const [same] = encodeDrawings({ BTCUSDT: [trend] }, [cloud])
    expect(same.body).toEqual(cloud.body)
    const [moved] = encodeDrawings({ BTCUSDT: [{ ...trend, pts: [{ t: 1, p: 101 }, { t: 2, p: 110 }] }] }, [cloud])
    expect(moved.body.text).toBe('支撑')
    expect(moved.body.dash).toBe('dashed')
    expect(moved.body.anchors).toEqual([{ t: 1, p: 101 }, { t: 2, p: 110 }])
  })

  it('手机上隐藏的、网页没有的种类不删不显示；量测线只留在本机', () => {
    const hidden = obj('drawings', drawingId('BTCUSDT', 'h'), { kind: 'hline', anchors: [{ t: 1, p: 1 }], symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', hidden: true })
    const text = obj('drawings', drawingId('BTCUSDT', 't'), { kind: 'text', anchors: [{ t: 1, p: 1 }], symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance' })
    expect(encodeDrawings({ BTCUSDT: [] }, [hidden, text])).toEqual([])
    const measure: Drawing = { id: 'm', type: 'measure', pts: [{ t: 1, p: 1 }, { t: 2, p: 2 }] }
    expect(encodeDrawings({ BTCUSDT: [measure] }, [])).toEqual([])
    expect(decodeDrawings([hidden, text], { BTCUSDT: [measure] }, new Set()).BTCUSDT).toEqual([measure])
  })
})

describe('alerts', () => {
  const price: Alert = { id: 'a1', symbol: 'BTCUSDT', kind: 'price', created: 1000, price: 120000, dir: 1, webhook: null }
  const fr: Alert = { id: 'a2', symbol: 'ETHUSDT', kind: 'fr', created: 1000, value: 0.05, op: 'gt', webhook: 'https://example.com/h' }
  const oi: Alert = { id: 'a3', symbol: 'BTCUSDT', kind: 'oi', created: 1000, value: 5, op: 'gt' }

  it('价格 / 资金费率 / 持仓量：形状照手机端，往返一致', () => {
    const out = encodeAlerts({ alerts: [price, fr, oi], drawings: {}, drawingObjs: [] }, [], ctx)
    const p = out.find(o => o.id.endsWith('/a1'))!
    expect(p.body).toMatchObject({ kind: 'price', symbol: 'BTCUSDT', market: ALERT_MARKET, condition: 'touch', once: true, status: 'active', armedAt: 1000, created: 1000, rule: null, title: 'BTC 涨到 120000.0' })
    expect(p.body.lines).toEqual([{ points: [{ t: 1000, p: 120000 }], extendLeft: true, extendRight: true }])
    const f = out.find(o => o.id.endsWith('/a2'))!
    expect(f.body).toMatchObject({ kind: 'condition', rule: { type: 'funding', side: 'above', rate: '0.0005' }, webhook: 'https://example.com/h' })
    const i = out.find(o => o.id.endsWith('/a3'))!
    expect(i.body.rule).toEqual({ type: 'openInterestChange', threshold: '0.05' })
    const { alerts } = decodeAlerts(out, [], ctx)
    expect(alerts).toEqual([price, fr, { ...oi, webhook: null }])
  })

  it('画线上的提醒开关 → 一条 kind=drawing 的提醒；关掉就删；解码回画线的开关', () => {
    const d: Drawing = { id: 'd1', type: 'hline', pts: [{ t: 5, p: 99000 }], alert: true }
    const drawingObjs = encodeDrawings({ BTCUSDT: [d] }, [])
    const on = encodeAlerts({ alerts: [], drawings: { BTCUSDT: [d] }, drawingObjs }, [], ctx)
    expect(on).toHaveLength(1)
    expect(on[0].body).toMatchObject({ kind: 'drawing', drawingID: 'd1', symbol: 'BTCUSDT', lines: [{ points: [{ t: 5, p: 99000 }], extendLeft: true, extendRight: true }] })
    const { drawingAlerts } = decodeAlerts(on, [], ctx)
    expect(decodeDrawings(drawingObjs, {}, drawingAlerts).BTCUSDT[0].alert).toBe(true)
    const off = encodeAlerts({ alerts: [], drawings: { BTCUSDT: [{ ...d, alert: false }] }, drawingObjs }, on, ctx)
    expect(off).toHaveLength(1)
    expect(off[0].deleted).toBe(true)
  })

  it('已触发的、复盘到期提醒网页管不着：不删不显示', () => {
    const fired = obj('alerts', 'binance/usd_m/BTCUSDT/x', { kind: 'price', status: 'fired', market: ALERT_MARKET, symbol: 'BTCUSDT', lines: [{ points: [{ t: 1, p: 1 }] }], condition: 'touch' })
    expect(encodeAlerts({ alerts: [], drawings: {}, drawingObjs: [] }, [fired], ctx)).toEqual([])
    expect(decodeAlerts([fired], [], ctx).alerts).toEqual([])
  })
})
