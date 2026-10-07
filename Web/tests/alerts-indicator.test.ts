/* 技术指标提醒（均线交叉 / RSI 穿越 / 收盘突破）：线格式、校验、文案、收盘判定、图上预填、服务端 400 的中文原因 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  barBreakoutRule, barsNeeded, crossed, draftFromChart, flipLevel, indicatorHitAt, indicatorPhrase, indicatorRuleError, indicatorRuleOk, isIndicatorRule, judgeClosedBars,
  lastCloseAt, maCrossRule, maFromChart, nearestInterval, parseIntField, parseNumField, rejectReason, rsiLevelRule, rsiSeries, ruleFromDraft, type ChartIndView,
} from '../src/alerts/indicator'
import { makeConditionAlert, rulePhrase } from '../src/alerts/shape'
import { alertToBody, decodeAlert, ruleOk } from '../src/sync/codec'
import { ApiError, request } from '../src/account/client'
import { Engine, onRejected, type Rejected } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive, type SyncObject } from '../src/sync/types'
import type { Bar } from '../src/chart/calc'
import { FakeServer, HttpError } from './sync-fake'

const MA = maCrossRule('15m', { ma: 'ema', period: 9 }, { ma: 'sma', period: 21 }, 'up')
const RSI = rsiLevelRule('1h', 14, 70, 'up')
const BR = barBreakoutRule('4h', 20, 'up')

describe('线格式：和服务端约定的一字不差', () => {
  it('三种条件 JSON 序列化后键名、键序、取值照约定', () => {
    expect(JSON.stringify(MA)).toBe('{"kind":"ma_cross","interval":"15m","fast":{"ma":"ema","period":9},"slow":{"ma":"sma","period":21},"direction":"up"}')
    expect(JSON.stringify(RSI)).toBe('{"kind":"rsi_level","interval":"1h","period":14,"level":70,"direction":"up"}')
    expect(JSON.stringify(BR)).toBe('{"kind":"bar_breakout","interval":"4h","bars":20,"direction":"up"}')
  })

  it('编码进提醒记录（rule 字段、kind=condition）再解回来，条件原样', () => {
    for (const rule of [MA, RSI, BR, rsiLevelRule('1d', 7, 30, 'down'), barBreakoutRule('1m', 2, 'down')]) {
      const a = { ...makeConditionAlert('BTCUSDT', rule, { now: 1 }), id: 'ind1' }
      const body = alertToBody(a)
      expect(body.kind).toBe('condition')
      expect(body.lines).toEqual([])
      expect(body.rule).toEqual(rule)
      expect(ruleOk(a.rule)).toBe(true)
      const o: SyncObject = { collection: 'alerts', id: 'binance/usd_m/BTCUSDT/ind1', body, fields: {}, revision: 1, deleted: false, generation: 0 }
      const back = decodeAlert(o)
      expect(back?.rule).toEqual(rule)
      expect(back?.kind).toBe('condition')
      expect(JSON.stringify(back?.rule)).toBe(JSON.stringify(rule))
    }
  })

  it('认得出是技术指标条件；老的 type 型条件不受影响', () => {
    expect(isIndicatorRule(MA)).toBe(true)
    expect(isIndicatorRule({ type: 'funding', side: 'above', rate: '0.0005' })).toBe(false)
    expect(ruleOk({ type: 'funding', side: 'above', rate: '0.0005' })).toBe(true)
  })
})

describe('校验', () => {
  it('合格的放行', () => {
    expect(indicatorRuleError(MA)).toBeNull()
    expect(indicatorRuleError(RSI)).toBeNull()
    expect(indicatorRuleError(BR)).toBeNull()
    expect(indicatorRuleError(maCrossRule('1d', { ma: 'sma', period: 2 }, { ma: 'sma', period: 500 }, 'down'))).toBeNull()
    expect(indicatorRuleError(rsiLevelRule('1m', 2, 1, 'down'))).toBeNull()
    expect(indicatorRuleError(rsiLevelRule('1m', 500, 99, 'up'))).toBeNull()
    expect(indicatorRuleError(barBreakoutRule('30m', 500, 'down'))).toBeNull()
  })

  it('长度 2–500、水平 1–99、根数 2–500，只收整数', () => {
    expect(indicatorRuleError(rsiLevelRule('1h', 1, 70, 'up'))).toMatch(/RSI 长度/)
    expect(indicatorRuleError(rsiLevelRule('1h', 501, 70, 'up'))).toMatch(/RSI 长度/)
    expect(indicatorRuleError(rsiLevelRule('1h', 14.5, 70, 'up'))).toMatch(/RSI 长度/)
    expect(indicatorRuleError(rsiLevelRule('1h', 14, 0, 'up'))).toMatch(/水平/)
    expect(indicatorRuleError(rsiLevelRule('1h', 14, 100, 'up'))).toMatch(/水平/)
    expect(indicatorRuleError(rsiLevelRule('1h', NaN, 70, 'up'))).toMatch(/RSI 长度/)
    expect(indicatorRuleError(barBreakoutRule('4h', 1, 'up'))).toMatch(/根数/)
    expect(indicatorRuleError(barBreakoutRule('4h', 501, 'up'))).toMatch(/根数/)
    expect(indicatorRuleError(maCrossRule('15m', { ma: 'ema', period: 1 }, { ma: 'sma', period: 21 }, 'up'))).toMatch(/快线长度/)
    expect(indicatorRuleError(maCrossRule('15m', { ma: 'ema', period: 9 }, { ma: 'sma', period: 600 }, 'up'))).toMatch(/慢线长度/)
  })

  it('快慢线完全相同不行；同长度不同类型可以', () => {
    expect(indicatorRuleError(maCrossRule('15m', { ma: 'ema', period: 9 }, { ma: 'ema', period: 9 }, 'up'))).toBe('快线和慢线不能一样')
    expect(indicatorRuleError(maCrossRule('15m', { ma: 'ema', period: 9 }, { ma: 'sma', period: 9 }, 'up'))).toBeNull()
  })

  it('周期只认七档、均线只认两种、方向只认上下、多余字段不收', () => {
    expect(indicatorRuleError({ ...RSI, interval: '2h' })).not.toBeNull()
    expect(indicatorRuleError({ ...MA, fast: { ma: 'wma', period: 9 } })).not.toBeNull()
    expect(indicatorRuleError({ ...BR, direction: 'left' })).not.toBeNull()
    expect(indicatorRuleError({ ...BR, extra: 1 })).not.toBeNull()
    expect(indicatorRuleError({ ...MA, fast: { ma: 'ema', period: 9, x: 1 } })).not.toBeNull()
    expect(ruleOk({ ...RSI, level: 120 } as never)).toBe(false)
    // 水平可以带小数（服务端 1–99 收小数）；超界照样不收
    expect(indicatorRuleOk({ ...RSI, level: 70.5 })).toBe(true)
    expect(indicatorRuleOk({ ...RSI, level: 0.5 })).toBe(false)
    expect(indicatorRuleOk({ ...RSI, level: 99.5 })).toBe(false)
    expect(parseNumField('６９。５')).toBe(69.5)
    expect(parseNumField('70.')).toBe(null)
  })

  it('输入框：全角数字、空白都认，非整数不认', () => {
    expect(parseIntField(' ２１ ')).toBe(21)
    expect(parseIntField('9')).toBe(9)
    expect(parseIntField('9.5')).toBeNull()
    expect(parseIntField('')).toBeNull()
    expect(parseIntField('-3')).toBeNull()
  })
})

describe('列表文案', () => {
  it('照约定的三句话', () => {
    expect(indicatorPhrase(MA)).toBe('15m EMA9 上穿 SMA21')
    expect(indicatorPhrase(RSI)).toBe('1h RSI(14) 上穿 70')
    expect(indicatorPhrase(BR)).toBe('4h 收盘突破前 20 根最高')
    expect(indicatorPhrase(maCrossRule('5m', { ma: 'sma', period: 50 }, { ma: 'sma', period: 200 }, 'down'))).toBe('5m SMA50 下穿 SMA200')
    expect(indicatorPhrase(rsiLevelRule('1d', 14, 30, 'down'))).toBe('1d RSI(14) 下穿 30')
    expect(indicatorPhrase(barBreakoutRule('1h', 55, 'down'))).toBe('1h 收盘跌破前 55 根最低')
  })

  it('提醒行走同一句；标题带品种', () => {
    expect(rulePhrase(MA)).toBe('15m EMA9 上穿 SMA21')
    expect(makeConditionAlert('BTCUSDT', RSI, { now: 1 }).title).toContain('1h RSI(14) 上穿 70')
  })
})

const M = 60e3
const mk = (closes: number[], hl = 0.5): Bar[] => closes.map((c, i) => ({ t: i * M, o: c, h: c + hl, l: c - hl, c, v: 1 }))

describe('收盘判定（照 TradingView 上穿 / 下穿口径）', () => {
  it('恰好相等不算穿越；上一根相等、这一根越过才算', () => {
    expect(crossed(1, 1, 1, 1, 'up')).toBe(false)
    expect(crossed(0, 1, 1, 1, 'up')).toBe(false)
    expect(crossed(1, 1, 2, 1, 'up')).toBe(true)
    expect(crossed(2, 1, 3, 1, 'up')).toBe(false)
    expect(crossed(1, 1, 0, 1, 'down')).toBe(true)
    expect(crossed(null, 1, 2, 1, 'up')).toBe(false)
  })

  it('均线交叉：平盘后一根大阳线，EMA3 上穿 SMA5 就在那一根', () => {
    const bars = mk([...Array(20).fill(100), 110, 111, 112])
    const r = maCrossRule('1m', { ma: 'ema', period: 3 }, { ma: 'sma', period: 5 }, 'up')
    const hits = bars.map((_, i) => indicatorHitAt(r, bars, i)).flatMap((h, i) => h ? [i] : [])
    expect(hits).toEqual([20])
    expect(indicatorHitAt({ ...r, direction: 'down' }, bars, 20)).toBe(false)
  })

  it('RSI 穿越：下跌后一路上涨，第一根 RSI > 70 的那根算上穿', () => {
    const closes = [...Array.from({ length: 30 }, (_, i) => 200 - i), ...Array.from({ length: 30 }, (_, i) => 171 + i * 3)]
    const bars = mk(closes)
    const s = rsiSeries(bars, 14)
    const k = s.findIndex((v, i) => i > 0 && v != null && v > 70 && (s[i - 1] ?? 0) <= 70)
    expect(k).toBeGreaterThan(30)
    const hits = bars.map((_, i) => indicatorHitAt(RSI, bars, i)).flatMap((h, i) => h ? [i] : [])
    expect(hits).toEqual([k])
  })

  it('突破：收盘等于前 N 根最高不算，高过才算；不含本根', () => {
    const bars = mk([...Array(20).fill(100), 100.5, 101.2])
    const r = barBreakoutRule('1m', 20, 'up')
    expect(indicatorHitAt(r, bars, 20)).toBe(false)   // 100.5 = 前 20 根最高
    expect(indicatorHitAt(r, bars, 21)).toBe(true)
    const d = mk([...Array(20).fill(100), 99.5, 98.8])
    expect(indicatorHitAt(barBreakoutRule('1m', 20, 'down'), d, 20)).toBe(false)
    expect(indicatorHitAt(barBreakoutRule('1m', 20, 'down'), d, 21)).toBe(true)
    expect(indicatorHitAt(r, bars, 10)).toBe(false)  // 前面不够 N 根
  })

  it('只判已收盘的、建好之后收的、上次判过之后的', () => {
    const bars = mk([...Array(20).fill(100), 100.5, 101.2, 102.5])
    const r = barBreakoutRule('1m', 20, 'up')
    const closeOf = (i: number): number => bars[i].t + M
    // 第 21 根还没收：不判
    expect(judgeClosedBars(r, bars, 0, closeOf(21) - 1)).toBe(-1)
    expect(judgeClosedBars(r, bars, 0, closeOf(21))).toBe(21)
    // 第 21 根收在建提醒之前：不翻旧账，往后找到 22
    expect(judgeClosedBars(r, bars, closeOf(21), closeOf(22))).toBe(22)
    // 判过 22 根：不再判
    expect(judgeClosedBars(r, bars, 0, closeOf(22), closeOf(22))).toBe(-1)
  })

  it('最近一次收盘时刻、拉多少根', () => {
    expect(lastCloseAt('15m', 15 * M * 4 + 1000)).toBe(15 * M * 4)
    expect(lastCloseAt('1h', 36e5 * 3)).toBe(36e5 * 3)
    expect(barsNeeded(RSI)).toBe(143)
    expect(barsNeeded(BR)).toBe(50)
    expect(barsNeeded(MA)).toBe(50)
    expect(barsNeeded(maCrossRule('1h', { ma: 'ema', period: 200 }, { ma: 'sma', period: 500 }, 'up'))).toBe(803)
    expect(barsNeeded(rsiLevelRule('1h', 500, 70, 'up'))).toBe(1500)
  })
})

const view = (o: Partial<ChartIndView> & { p?: Record<string, unknown> } = {}): ChartIndView => ({
  iv: '15m', ma: false, ema: false, rsi: false, ...o,
  params: id => (o.p?.[id] as never) ?? undefined,
})

describe('图上预填', () => {
  it('周期取当前格子，不在七档里取最近的', () => {
    expect(nearestInterval('15m')).toBe('15m')
    expect(nearestInterval('3m')).toBe('5m')
    expect(nearestInterval('2h')).toBe('1h')
    expect(nearestInterval('1w')).toBe('1d')
    expect(nearestInterval('1s')).toBe('1m')
  })

  it('图上没挂均线 / RSI：用默认 EMA9 / SMA21、RSI 14 / 70 上穿、20 根上破', () => {
    const d = draftFromChart(view())
    expect(ruleFromDraft('ma_cross', d)).toEqual(maCrossRule('15m', { ma: 'ema', period: 9 }, { ma: 'sma', period: 21 }, 'up'))
    expect(ruleFromDraft('rsi_level', d)).toEqual(rsiLevelRule('15m', 14, 70, 'up'))
    expect(ruleFromDraft('bar_breakout', d)).toEqual(barBreakoutRule('15m', 20, 'up'))
  })

  it('图上挂着 EMA 与 MA：最短的当快线、第一条更长的当慢线', () => {
    const v = view({ ma: true, ema: true, p: { ma: { periods: [20, 60] }, ema: { periods: [12, 26] } } })
    expect(maFromChart(v)).toEqual({ fast: { ma: 'ema', period: 12 }, slow: { ma: 'sma', period: 20 } })
  })

  it('从均线图例点进来用那一组；从 RSI 副图点进来用图上长度', () => {
    const v = view({ iv: '4h', ma: true, rsi: true, p: { ma: { periods: [50, 200] }, rsi: { n: 6 } } })
    const d = draftFromChart(v, 'ma')
    expect(d.interval).toBe('4h')
    expect(d.fast).toEqual({ ma: 'sma', period: 50 })
    expect(d.slow).toEqual({ ma: 'sma', period: 200 })
    expect(draftFromChart(v, 'rsi').rsiPeriod).toBe(6)
    expect(draftFromChart(view({ p: { rsi: { n: 6 } } })).rsiPeriod).toBe(14)   // 没挂 RSI 不借图上参数
  })

  it('RSI 换方向时 70 ↔ 30 跟着翻，别的水平不动', () => {
    expect(flipLevel(70, 'down')).toBe(30)
    expect(flipLevel(30, 'up')).toBe(70)
    expect(flipLevel(80, 'down')).toBe(80)
  })
})

describe('服务端没上线时的 400：中文原因', () => {
  afterEach(() => { vi.unstubAllGlobals() })

  it('请求层把服务端 error.message 带进 ApiError.reason', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: { code: 'invalid_sync_value', message: '不认识的提醒条件' } }), { status: 400 })))
    const e = await request('POST', '/v1/sync/push', {}).catch((x: unknown) => x)
    expect(e).toBeInstanceOf(ApiError)
    expect((e as ApiError).status).toBe(400)
    expect((e as ApiError).code).toBe('invalid_sync_value')
    expect((e as ApiError).reason).toBe('不认识的提醒条件')
  })

  it('服务端的 indicator_* 错误：界面直接用它的中文 message', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: { code: 'indicator_invalid_period', message: '均线长度要在 2 到 500 之间' } }), { status: 400 })))
    const e = await request('POST', '/v1/sync/push', {}).catch((x: unknown) => x) as ApiError
    expect(e.code).toBe('indicator_invalid_period')
    expect(rejectReason(e.code, e.reason)).toBe('均线长度要在 2 到 500 之间')
  })

  it('没有 message 时 reason 为空，按错误码给中文', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(JSON.stringify({ error: { code: 'invalid_sync_value' } }), { status: 400 })))
    const e = await request('POST', '/v1/sync/push', {}).catch((x: unknown) => x) as ApiError
    expect(e.reason).toBeUndefined()
    expect(rejectReason(e.code, e.reason)).toBe('服务端暂不支持这种条件，本页开着时照常判')
    expect(rejectReason('invalid_sync_value', 'unknown rule type')).toBe('服务端暂不支持这种条件，本页开着时照常判')
    expect(rejectReason('invalid_sync_value', '水平要在 1 到 99 之间')).toBe('水平要在 1 到 99 之间')
    expect(rejectReason('weird')).toBe('服务端没收（weird）')
  })

  it('同步推送被 400：这一条单独隔开，onRejected 收到错误码与原因，别的照推', async () => {
    const server = new FakeServer()
    const store = new SyncStore(emptyArchive(), 'web-device', () => server.now)
    const engine = new Engine(store, server.transport(), {}, { capture: () => {}, apply: () => {} })
    const ind = { ...makeConditionAlert('BTCUSDT', RSI, { now: 1 }), id: 'ind1' }
    const fr = { ...makeConditionAlert('ETHUSDT', { type: 'funding', side: 'above', rate: '0.0005' }, { now: 1 }), id: 'fr1' }
    const obj = (sym: string, a: typeof ind): SyncObject => ({ collection: 'alerts', id: `binance/usd_m/${sym}/${a.id}`, body: alertToBody(a), fields: {}, revision: 0, deleted: false, generation: 0 })
    store.capture([obj('BTCUSDT', ind), obj('ETHUSDT', fr)])
    server.reject = ops => ops.some(o => (o.fields.rule as { kind?: string } | undefined)?.kind === 'rsi_level')
      ? Object.assign(new HttpError(400, 'invalid_sync_value'), { reason: '条件提醒不认识 rsi_level' }) : null
    const seen: Rejected[] = []
    const off = onRejected(r => seen.push(r))
    await engine.push()
    off()
    expect(seen).toHaveLength(1)
    expect(seen[0].op.objectId).toBe('binance/usd_m/BTCUSDT/ind1')
    expect(seen[0].code).toBe('invalid_sync_value')
    expect(rejectReason(seen[0].code, seen[0].reason)).toBe('条件提醒不认识 rsi_level')
    expect(store.a.rejected.map(r => r.operation.objectId)).toEqual(['binance/usd_m/BTCUSDT/ind1'])
    expect([...server.objects.values()].map(o => o.id)).toEqual(['binance/usd_m/ETHUSDT/fr1'])
  })
})
