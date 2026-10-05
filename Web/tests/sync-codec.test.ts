import { describe, expect, it } from 'vitest'
import type { Alert } from '../src/app/store'
import { drawingIdOf, makeConditionAlert, makeDrawingAlert, makePriceAlert } from '../src/alerts/shape'
import type { Drawing } from '../src/chart/chart'
import {
  ALERT_MARKET, SETTINGS_ID, applySettings, decodeAlerts, decodeDrawings, decodeFavorites, drawingId, encodeAlerts,
  encodeDrawings, encodeFavorites, encodeSettings, favId, alertId, unseenDrawings, type SettingsState,
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
    const out = encodeFavorites({ crypto: ['ETHUSDT', 'BTCUSDT'], us: [], idx: [], com: ['XAUUSDT'] }, prev, ctx)
    const live = out.filter(o => !o.deleted).sort((a, b) => (a.body.order as number) - (b.body.order as number))
    expect(live.map(o => o.id)).toEqual([favId('ETHUSDT'), 'coinbase/spot/BTC-USD', favId('BTCUSDT'), favId('XAUUSDT')])
    expect(live.find(o => o.id === favId('BTCUSDT'))!.body.groupId).toBe('g1')
    expect(live.find(o => o.id === favId('ETHUSDT'))!.body).toEqual({ symbol: 'ETHUSDT', market: 'usd_m', venue: 'binance', groupId: null, order: 0 })
    expect(out.find(o => o.id === favId('NVDAUSDT'))!.deleted).toBe(true)
    expect(out.some(o => o.id === 'coinbase/spot/BTC-USD' && o.deleted)).toBe(false)
    expect(decodeFavorites(out, ctx)).toEqual({ crypto: ['ETHUSDT', 'BTCUSDT'], us: [], idx: [], com: ['XAUUSDT'] })
  })

  // 审查 D-01：网页上新加的自选以前一律 groupId: null，手机分类页按分类过滤，它在手机上就看不见了
  it('新加的自选挂进手机同名的那一类；没有同名的跟着同标签页的自选走；都没有才留空', () => {
    const groups = [
      obj('groups', 'g-crypto', { name: '加密', order: 0 }),
      obj('groups', 'g-us', { name: '美股', order: 1 }),
      obj('groups', 'g-mine', { name: '主力', order: 2 }),
      obj('groups', 'g-gone', { name: '贵金属', order: 3 }, { deleted: true }),
    ]
    const prev = [
      obj('favorites', favId('BTCUSDT'), { symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', groupId: 'g-mine', order: 0 }),
      obj('favorites', favId('XAGUSDT'), { symbol: 'XAGUSDT', market: 'usd_m', venue: 'binance', groupId: 'g-mine', order: 1 }),
    ]
    const out = encodeFavorites({ crypto: ['BTCUSDT', 'ETHUSDT'], us: ['NVDAUSDT'], idx: [], com: ['XAGUSDT', 'XAUUSDT'] }, prev, ctx, groups)
    const g = (s: string) => out.find(o => o.id === favId(s))!.body.groupId
    expect(g('BTCUSDT')).toBe('g-mine')        // 原来挂哪儿就挂哪儿
    expect(g('ETHUSDT')).toBe('g-crypto')      // 有同名的「加密」
    expect(g('NVDAUSDT')).toBe('g-us')
    expect(g('XAUUSDT')).toBe('g-mine')        // 「贵金属」删了，跟着同标签页的白银
    const bare = encodeFavorites({ crypto: ['ETHUSDT'], us: [], idx: [], com: [] }, [], ctx, [])
    expect(bare[0].body.groupId).toBeNull()    // 一个分类都没有：留空，手机装进来时补分类
  })
})

describe('drawings', () => {
  const trend: Drawing = { id: 'd1', type: 'trend', pts: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: '#FF0000', width: 2 }

  it('编码形状照手机端，往返一致', () => {
    const [o] = encodeDrawings({ BTCUSDT: [trend] }, [])
    expect(o.id).toBe(drawingId('BTCUSDT', 'd1'))
    expect(o.body).toMatchObject({ kind: 'trend', anchors: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: { value: '#FF0000' }, lineWidth: 2, locked: false, symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', dash: 'solid', hidden: false })
    const back = decodeDrawings([o], {})
    expect(back.BTCUSDT).toEqual([{ ...trend }])
  })

  it('没改的原样用云端 body；改了只覆盖网页的键，手机的文字留着（线型网页也管，装进来就是虚线）', () => {
    const cloud = obj('drawings', drawingId('BTCUSDT', 'd1'), { kind: 'trend', anchors: [{ t: 1, p: 100 }, { t: 2, p: 110 }], color: { value: '#FF0000' }, lineWidth: 2, locked: false, symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', dash: 'dashed', text: '支撑', filled: true, hidden: false, levels: [] })
    const dashed: Drawing = { ...trend, dash: 'dashed' }
    expect(decodeDrawings([cloud], {}).BTCUSDT[0].dash).toBe('dashed')
    const [same] = encodeDrawings({ BTCUSDT: [dashed] }, [cloud])
    expect(same.body).toEqual(cloud.body)
    const [moved] = encodeDrawings({ BTCUSDT: [{ ...dashed, pts: [{ t: 1, p: 101 }, { t: 2, p: 110 }] }] }, [cloud])
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
    expect(decodeDrawings([hidden, text], { BTCUSDT: [measure] }).BTCUSDT).toEqual([measure])
  })
})

describe('alerts', () => {
  const price = makePriceAlert('BTCUSDT', 120000, 110000, { now: 1000 })
  const fund = makeConditionAlert('ETHUSDT', { type: 'funding', side: 'above', rate: '0.0005' }, { now: 1000, webhook: 'https://example.com/h' })
  const hl: Drawing = { id: 'd1', type: 'hline', pts: [{ t: 5, p: 99000 }] }
  const onLine = makeDrawingAlert('BTCUSDT', hl, 1000)

  it('一条提醒一个对象：19 个键照手机端，可空的写 null；往返一致', () => {
    const out = encodeAlerts([price, fund], [])
    const p = out.find(o => o.id === alertId('BTCUSDT', price.id))!
    expect(Object.keys(p.body).sort()).toHaveLength(19)
    expect(p.body).toMatchObject({ kind: 'price', symbol: 'BTCUSDT', market: ALERT_MARKET, condition: 'touch', once: true, status: 'active', armedAt: 1000, created: 1000, rule: null, drawingID: null, firedAt: null, dueAt: null })
    expect(p.body.lines).toEqual([{ points: [{ t: 1000, p: 120000 }], extendLeft: true, extendRight: true }])
    const f = out.find(o => o.id === alertId('ETHUSDT', fund.id))!
    expect(f.body).toMatchObject({ kind: 'condition', rule: { type: 'funding', side: 'above', rate: '0.0005' }, webhook: 'https://example.com/h' })
    expect(decodeAlerts(out, [])).toEqual([price, fund])
  })

  it('画线提醒的 drawingID：线上是画线自己的 id（手机写 drawing.id），网页本机是完整对象 id', () => {
    expect(onLine.drawingID).toBe(drawingIdOf('BTCUSDT', 'd1'))
    const [o] = encodeAlerts([onLine], [])
    expect(o.body).toMatchObject({ kind: 'drawing', drawingID: 'd1', symbol: 'BTCUSDT' })
    expect(decodeAlerts([o], [])).toEqual([onLine])
    // 手机建的画线提醒进来，网页能按完整 id 找回那条画线
    const phone = obj('alerts', 'binance/usd_m/BTCUSDT/P9', { ...o.body, drawingID: 'X7' })
    expect(decodeAlerts([phone], [])[0]).toMatchObject({ id: 'P9', drawingID: drawingIdOf('BTCUSDT', 'X7') })
  })

  it('手机的条件提醒（持仓量、均线）进来原样保留，没改就原样推回去', () => {
    const cloud = obj('alerts', 'binance/usd_m/SOLUSDT/c1', {
      kind: 'condition', symbol: 'SOLUSDT', market: ALERT_MARKET, drawingID: null, lines: [], condition: 'touch', armedAt: 5, once: true,
      status: 'active', firedAt: null, firedPrice: null, dueAt: null, reviewID: null, title: 'SOL 均线', created: 5, note: '手机', webhook: null,
      webhookText: null, rule: { type: 'maCross', interval: '4h', length: 60, side: 'above' },
    })
    const [a] = decodeAlerts([cloud], [])
    expect(a).toMatchObject({ id: 'c1', kind: 'condition', note: '手机', rule: { type: 'maCross', length: 60 } })
    const [back] = encodeAlerts([a], [cloud])
    expect(back.body).toEqual(cloud.body)
    expect(back.revision).toBe(1)
  })

  it('本机删了、响过了 → 删云端那条；本机还在只是暂时上不了云的 → 不删', () => {
    const [o] = encodeAlerts([price], [])
    const live = { ...o, revision: 1 }
    expect(encodeAlerts([], [live])).toEqual([{ ...live, deleted: true }])
    const broken: Alert = { ...price, lines: [] }
    expect(encodeAlerts([broken], [live])).toEqual([])
    // 解码时这条上不了云的本机副本让位给云端
    expect(decodeAlerts([live], [broken])).toEqual([price])
  })

  it('挂在手机藏起来的画线上的提醒：网页不接手，本机没有也不删', () => {
    const hidden = obj('drawings', drawingId('BTCUSDT', 'H'), { kind: 'hline', anchors: [{ t: 1, p: 1 }], symbol: 'BTCUSDT', market: 'usd_m', venue: 'binance', hidden: true })
    const al = obj('alerts', 'binance/usd_m/BTCUSDT/q', { ...encodeAlerts([onLine], [])[0].body, drawingID: 'H' })
    const unseen = unseenDrawings([hidden])
    expect(decodeAlerts([al], [], unseen)).toEqual([])
    expect(encodeAlerts([], [al], unseen)).toEqual([])
    expect(encodeAlerts([], [al])).toHaveLength(1) // 对照：不给 unseen 就会删
  })

  it('超出服务端范围的条件不上云（本机留着）', () => {
    const bad = makeConditionAlert('BTCUSDT', { type: 'funding', side: 'above', rate: '0.5' }, { now: 1 })
    expect(encodeAlerts([bad], [])).toEqual([])
    expect(decodeAlerts([], [bad])).toEqual([bad])
  })

  it('已触发的、复盘到期、Coinbase 的网页管不着：不删不显示', () => {
    const fired = obj('alerts', 'binance/usd_m/BTCUSDT/x', { kind: 'price', status: 'fired', market: ALERT_MARKET, symbol: 'BTCUSDT', lines: [{ points: [{ t: 1, p: 1 }] }], condition: 'touch' })
    const review = obj('alerts', 'binance/usd_m/BTCUSDT/r', { kind: 'reviewDue', status: 'active', market: ALERT_MARKET, symbol: 'BTCUSDT', lines: [], dueAt: 9 })
    const cb = obj('alerts', 'coinbase/spot/BTC-USD/c', { kind: 'price', status: 'active', market: 'coinbase/spot', symbol: 'BTC-USD', lines: [{ points: [{ t: 1, p: 1 }] }] })
    expect(encodeAlerts([], [fired, review, cb])).toEqual([])
    expect(decodeAlerts([fired, review, cb], [])).toEqual([])
  })
})
