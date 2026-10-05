import { describe, expect, it } from 'vitest'
import { ApiError } from '../src/account/client'
import {
  AlertLogModel, bareSymbol, dayTitle, decodeLog, localDay, logCacheKey, logClock, logDays, logDetail, logName, type AlertLogRecord, type LogFetch,
} from '../src/alerts/log'

const rec = (id: string, firedAt: number, extra: Partial<AlertLogRecord> = {}): AlertLogRecord =>
  ({ id, alertId: null, kind: 'price', symbol: 'binance/usd_m/BTCUSDT', title: 'BTC 价格达到 86,000', condition: '价格达到 86,000', firedAt, firedPrice: 86010.5, ...extra })

// 2026-10-05 12:00 上海 = 04:00 UTC
const NOON = Date.UTC(2026, 9, 5, 4, 0, 0)

class MemKV { m = new Map<string, string>(); getItem(k: string) { return this.m.get(k) ?? null } setItem(k: string, v: string) { this.m.set(k, v) } removeItem(k: string) { this.m.delete(k) } }

describe('提醒日志 · 拆包与文字（照 iOS AlertLogText）', () => {
  it('包在 {data} 里与裸的 {records} 都认；倒序、同一刻按 id；缺 id / firedAt 的丢掉；firedAt 是浮点也认', () => {
    const body = { data: { records: [
      { id: 'a', kind: 'price', symbol: 'macro/index/DXY', title: '美元指数 价格达到 150', condition: '价格达到 150', firedAt: 1000.7, firedPrice: 150.012 },
      { id: 'c', firedAt: 2000 }, { id: 'b', firedAt: 2000, extra: 1 }, { kind: 'price', firedAt: 3 }, { id: 'x' },
    ] } }
    const rs = decodeLog(body)
    expect(rs.map(r => r.id)).toEqual(['c', 'b', 'a'])
    expect(rs[2]).toMatchObject({ firedAt: 1000, symbol: 'macro/index/DXY', firedPrice: 150.012 })
    expect(rs[0]).toMatchObject({ kind: 'price', symbol: '', title: '', condition: null, firedPrice: null })
    expect(decodeLog({ records: [{ id: 'z', firedAt: 1 }] }).map(r => r.id)).toEqual(['z'])
    expect(decodeLog(null)).toEqual([])
    expect(decodeLog({ data: null })).toEqual([])
  })

  it('按上海的天分组：今天 / 昨天 / 10月3日 / 去年写年份；组内组间都倒序', () => {
    const rs = [
      rec('1', NOON - 3600e3),
      rec('2', NOON),
      rec('3', Date.UTC(2026, 9, 4, 15, 59)), // 上海 10-04 23:59 → 昨天
      rec('4', Date.UTC(2026, 9, 4, 16, 1)), // 上海 10-05 00:01 → 今天
      rec('5', Date.UTC(2026, 9, 2, 20, 0)), // 上海 10-03 04:00
      rec('6', Date.UTC(2025, 9, 3, 2, 0)),
    ]
    const ds = logDays(rs, NOON)
    expect(ds.map(d => d.title)).toEqual(['今天', '昨天', '10月3日', '2025年10月3日'])
    expect(ds[0].records.map(r => r.id)).toEqual(['2', '1', '4'])
    expect(ds[1].records.map(r => r.id)).toEqual(['3'])
    expect(dayTitle(localDay(NOON), localDay(NOON))).toBe('今天')
  })

  it('时刻按上海 24 小时制', () => {
    expect(logClock(NOON)).toBe('12:00')
    expect(logClock(Date.UTC(2026, 9, 4, 16, 3))).toBe('00:03')
    expect(logClock(Date.UTC(2026, 9, 5, 6, 7))).toBe('14:07')
  })

  it('第二行：条件 · 触发价（千分位）；没条件用标题；没价 / 价是 0 就不写', () => {
    expect(logDetail(rec('1', 1), 1)).toBe('价格达到 86,000 · 触发价 86,010.5')
    expect(logDetail(rec('1', 1, { condition: '  ', firedPrice: null }))).toBe('BTC 价格达到 86,000')
    expect(logDetail(rec('1', 1, { condition: '复盘到点', firedPrice: 0 }))).toBe('复盘到点')
    expect(logDetail(rec('1', 1, { condition: null, title: '', firedPrice: null }))).toBe('')
  })

  it('品种：完整键换回网页版裸代号；没品种用标题，再没有叫「提醒」', () => {
    expect(bareSymbol('macro/index/DXY')).toBe('DXY')
    expect(bareSymbol('binance/usd_m/BTCUSDT')).toBe('BTCUSDT')
    expect(bareSymbol('coinbase/spot/ETH-USD')).toBe('ETH-USD')
    expect(bareSymbol('SOLUSDT')).toBe('SOLUSDT')
    const pair = (s: string) => s === 'DXY' ? 'DXY' : s.replace(/USDT$/, '/USDT')
    expect(logName(rec('1', 1), pair)).toBe('BTC/USDT')
    expect(logName(rec('1', 1, { symbol: '', title: 'SOL 到点了' }), pair)).toBe('SOL 到点了')
    expect(logName(rec('1', 1, { symbol: '', title: ' ' }), pair)).toBe('提醒')
  })
})

describe('提醒日志 · 状态（缓存按账号、404 当空、失败照摆缓存、清空）', () => {
  const body = { records: [rec('a', 2), rec('b', 1)] }

  it('拉到就按账号缓存；换号摆那个人的缓存；没登录是空', async () => {
    const kv = new MemKV()
    const calls: string[] = []
    const f: LogFetch = async (m, p, o) => { calls.push(`${m} ${p} ${o}`); return body }
    const m = new AlertLogModel(f, () => kv)
    await m.refresh('U1')
    expect(calls).toEqual(['GET /v1/alerts/log?limit=200 U1'])
    expect(m.phase).toBe('loaded')
    expect(m.records.map(r => r.id)).toEqual(['a', 'b'])
    expect(JSON.parse(kv.getItem(logCacheKey('U1'))!)).toHaveLength(2)
    m.select('U2'); expect(m.records).toEqual([])
    m.select(null); expect(m.records).toEqual([])
    const m2 = new AlertLogModel(async () => { throw new ApiError(500, 'http_500') }, () => kv)
    await m2.refresh('U1')
    expect(m2.phase).toBe('failed')
    expect(m2.records.map(r => r.id)).toEqual(['a', 'b']) // 服务器不通照摆上一次那份
  })

  it('404（服务端还没这条路）当「暂无记录」', async () => {
    const kv = new MemKV()
    kv.setItem(logCacheKey('U1'), JSON.stringify([rec('old', 1)]))
    const m = new AlertLogModel(async () => { throw new ApiError(404, 'http_404') }, () => kv)
    await m.refresh('U1')
    expect(m.phase).toBe('loaded')
    expect(m.records).toEqual([])
  })

  it('拉的路上换了号：旧号那一趟作废，不装进新号', async () => {
    let release: (v: unknown) => void = () => {}
    const m = new AlertLogModel(() => new Promise(r => { release = r }), () => new MemKV())
    const p = m.refresh('U1')
    m.select('U2')
    release(body); await p
    expect(m.owner).toBe('U2')
    expect(m.records).toEqual([])
  })

  it('清空：DELETE 成功就清本机与缓存；失败返回 false、记录照留；清空前在路上的那趟拉取作废', async () => {
    const kv = new MemKV()
    const calls: string[] = []
    let fail = false
    let release: (v: unknown) => void = () => {}
    const f: LogFetch = (m, p) => {
      calls.push(`${m} ${p}`)
      if (m === 'DELETE') return fail ? Promise.reject(new ApiError(503, 'http_503')) : Promise.resolve(null)
      return calls.length === 1 ? Promise.resolve(body) : new Promise(r => { release = r })
    }
    const m = new AlertLogModel(f, () => kv)
    await m.refresh('U1')
    fail = true
    expect(await m.clear()).toBe(false)
    expect(m.records).toHaveLength(2)
    fail = false
    const late = m.refresh('U1')
    expect(await m.clear()).toBe(true)
    release(body); await late
    expect(m.records).toEqual([])
    expect(JSON.parse(kv.getItem(logCacheKey('U1'))!)).toEqual([])
    expect(calls).toContain('DELETE /v1/alerts/log')
    expect(await new AlertLogModel(f, () => kv).clear()).toBe(false) // 没登录不清
  })
})
