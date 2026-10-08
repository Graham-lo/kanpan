// 电脑网页「对比」（2026-10-05）：纯逻辑的用例——键的认法、按主图对齐、百分比、断线、取数器、偏好清洗与同步编解码
import { describe, expect, it } from 'vitest'
import {
  COMPARE_MAX_PAGES, CompareStore, alignCompare, compareBaseIndexFrom, compareKeyOf, comparePercentAt, comparePercentLabel,
  compareSegments, compareSymbolOf, compareTargets, pctOf, percentTickLabel, percentTicks, priceOfPct,
} from '../src/chart/compare'
import type { Bar } from '../src/chart/calc'
import { MAX_COMPARE, SETTINGS_FIELDS, cleanCompare, decodeSetting, encodeSetting, encodeSettings, factorySettings, webSetting } from '../src/sync/codec'
import { cleanCompare as cleanCompareM } from '../src/m/app/prefs'
import { OWNED, adoptNewSettings, applyInto, captureInto, fingerprint, mergeFirst, type Prints, type WebState } from '../src/sync/bridge'
import { hydrate } from '../src/app/store'
import { Engine } from '../src/sync/engine'
import { SyncStore } from '../src/sync/store'
import { emptyArchive } from '../src/sync/types'
import { FakeServer, ctx } from './sync-fake'

const H = 36e5, D = 864e5
const bar = (t: number, o: number, c = o): Bar => ({ t, o, h: Math.max(o, c), l: Math.min(o, c), c, v: 1 })
const run = (n: number, t0 = 0, iv = H, p = (k: number) => 100 + k): Bar[] => Array.from({ length: n }, (_, k) => bar(t0 + k * iv, p(k), p(k) + 0.5))
const nice = (v: number) => { const e = 10 ** Math.floor(Math.log10(v)); const f = v / e; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * e }
const flush = async () => { for (let k = 0; k < 6; k++) await Promise.resolve() }

describe('偏好里的键 ↔ 代号', () => {
  it('币安 U 本位、美元指数、裸代号、注册表里的别家（2026-10-08 起）；不认识的市场与写坏的不认', () => {
    expect(compareSymbolOf('binance/usd_m/ETHUSDT')).toBe('ETHUSDT')
    expect(compareSymbolOf('macro/index/DXY')).toBe('DXY')
    expect(compareSymbolOf('DXY')).toBe('DXY')
    expect(compareSymbolOf('solusdt')).toBe('SOLUSDT')
    expect(compareSymbolOf('coinbase/spot/BTC-USD')).toBe('coinbase/spot/BTC-USD')
    expect(compareSymbolOf('okx/usd_m/BTCUSDT')).toBe('okx/usd_m/BTCUSDT')
    expect(compareSymbolOf('hyperliquid/usd_m/kpepe')).toBe('hyperliquid/usd_m/KPEPE')
    expect(compareSymbolOf('okx/usd_m/BTC-USDT-SWAP')).toBeNull()
    expect(compareSymbolOf('coinbase/usd_m/BTC-USD')).toBeNull()
    expect(compareSymbolOf('ftx/usd_m/BTCUSDT')).toBeNull()
    expect(compareSymbolOf('binance/spot/ETHUSDT')).toBeNull()
    expect(compareSymbolOf('a/b')).toBeNull()
    expect(compareKeyOf('ethusdt')).toBe('binance/usd_m/ETHUSDT')
    expect(compareKeyOf('DXY')).toBe('macro/index/DXY')
    expect(compareKeyOf('bybit/usd_m/1000PEPEUSDT')).toBe('bybit/usd_m/1000PEPEUSDT')
  })
  it('一格要画的：去掉主图那只、去重、最多三只，slot 是在偏好里的位置（颜色跟它走）', () => {
    const keys = ['binance/usd_m/BTCUSDT', 'binance/usd_m/ETHUSDT', 'coinbase/spot/BTC-USD', 'ETHUSDT', 'macro/index/DXY', 'binance/usd_m/SOLUSDT', 'binance/usd_m/XRPUSDT']
    const t = compareTargets(keys, 'BTCUSDT')
    expect(t.map(x => x.symbol)).toEqual(['ETHUSDT', 'coinbase/spot/BTC-USD', 'DXY'])
    expect(t.map(x => x.slot)).toEqual([1, 2, 4])
    expect(compareTargets(['binance/usd_m/ETHUSDT'], 'ETHUSDT')).toEqual([])
  })
})

describe('按主图时间对齐', () => {
  it('缺根是 null，多出来的根不占位，非法价是 null', () => {
    const main = run(6)
    const cmp = [bar(-H, 9), bar(0, 10, 11), bar(2 * H, 12, 13), bar(3 * H, 0, -1), bar(2.5 * H, 99), bar(5 * H, 15, 16), bar(9 * H, 20)]
      .sort((a, b) => a.t - b.t)
    const a = alignCompare(main, cmp)
    expect(a.open).toEqual([10, null, 12, null, null, 15])
    expect(a.close).toEqual([11, null, 13, null, null, 16])
    expect(alignCompare(main, null).open.every(x => x == null)).toBe(true)
  })
  it('美元指数周末没根：对齐是 null，画出来断开、不拿直线连过去', () => {
    // 主图（币）是连续日线，美元指数周六周日没有
    const main = run(9, 0, D)
    const dxy = main.filter((_, k) => k !== 5 && k !== 6).map(b => bar(b.t, 100, 100 + (b.t / D) * 0.1))
    const a = alignCompare(main, dxy)
    const base = compareBaseIndexFrom(a.open, 0, 8)!
    const segs = compareSegments(i => main[i].t, D, 0, 8, i => comparePercentAt(a, i, base))
    expect(segs.map(s => s.map(([i]) => i))).toEqual([[0, 1, 2, 3, 4], [7, 8]])
  })
  it('主图自己隔了一截（停牌、周末收盘的品种当主图）：同样断开', () => {
    const times = [0, H, 2 * H, 10 * H, 11 * H]
    const segs = compareSegments(i => times[i], H, 0, 4, () => 1)
    expect(segs.map(s => s.length)).toEqual([3, 2])
  })
})

describe('百分比', () => {
  it('基准根是可见第一根（它没值就往右找），收盘相对基准开盘', () => {
    const a = { open: [null, null, 50, 60], close: [null, null, 55, 66] }
    expect(compareBaseIndexFrom(a.open, 0, 3)).toBe(2)
    expect(compareBaseIndexFrom(a.open, 0, 1)).toBeNull()
    expect(comparePercentAt(a, 3, 2)).toBeCloseTo(32)
    expect(comparePercentAt(a, 1, 2)).toBeNull()
  })
  it('图例文字：+x.xx% / −x.xx% / 0% / —', () => {
    expect(comparePercentLabel(1.234)).toBe('+1.23%')
    expect(comparePercentLabel(-0.5)).toBe('−0.50%')
    expect(comparePercentLabel(0.001)).toBe('0%')
    expect(comparePercentLabel(null)).toBe('—')
    expect(comparePercentLabel(NaN)).toBe('—')
  })
  it('价格 ↔ 百分比互逆；刻度按百分比取整，0% 在区间里时一定有', () => {
    expect(priceOfPct(pctOf(123, 100), 100)).toBeCloseTo(123)
    const { prices, step } = percentTicks(95, 112, 100, 6, nice)
    expect(step).toBeGreaterThan(0)
    const pcts = prices.map(p => pctOf(p, 100))
    expect(pcts.some(v => Math.abs(v) < 1e-9)).toBe(true)
    for (const v of pcts) expect(Math.abs(v / step - Math.round(v / step))).toBeLessThan(1e-6)
    expect(percentTickLabel(100, 100, step)).toBe('0%')
    expect(percentTickLabel(110, 100, 5)).toBe('+10%')
    expect(percentTickLabel(99.5, 100, 0.5)).toBe('−0.5%')
    expect(percentTicks(1, 2, 0, 5, nice).prices).toEqual([])
  })
})

describe('对比取数器', () => {
  function harness(pages: (symbol: string, end: number | null) => Bar[] | null) {
    const calls: { symbol: string; iv: string; end: number | null }[] = []
    const pending: (() => void)[] = []
    const timers: { fn: () => void; ms: number }[] = []
    const changes: string[] = []
    const store = new CompareStore(
      (symbol, iv, end) => { calls.push({ symbol, iv, end }); return new Promise(r => pending.push(() => r(pages(symbol, end)))) },
      (s, iv) => changes.push(`${s}|${iv}`),
      () => H,
      { set: (fn, ms) => { timers.push({ fn, ms }); return timers.length }, clear: () => {} },
    )
    const step = async () => { const p = pending.splice(0); p.forEach(f => f()); await flush() }
    return { store, calls, pending, timers, changes, step }
  }
  const T0 = 1_000 * H
  /** 假交易所：每页 5 根，endTime 之前（不含）的最近 5 根；最早到 T0-20H */
  const exchange = (_: string, end: number | null): Bar[] => {
    const last = end == null ? T0 + 4 * H : end - H
    const out: Bar[] = []
    for (let t = last - 4 * H; t <= last; t += H) if (t >= T0 - 20 * H) out.push(bar(t, 10 + t / H / 1000))
    return out
  }

  it('先取最新一页；主图往左翻，对比跟着往左补到主图第一根；补到头标记取完', async () => {
    const h = harness(exchange)
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 }])
    expect(h.calls).toEqual([{ symbol: 'ETHUSDT', iv: '1h', end: null }])
    await h.step()
    expect(h.store.get('ETHUSDT', '1h')!.bars!.map(b => b.t)).toEqual([0, 1, 2, 3, 4].map(k => T0 + k * H))
    expect(h.calls.length).toBe(1)
    // 主图往左翻到 T0-12H
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 - 12 * H }])
    expect(h.calls.at(-1)!.end).toBe(T0)
    await h.step(); await h.step(); await h.step()
    const bs = h.store.get('ETHUSDT', '1h')!.bars!
    expect(bs[0].t).toBeLessThanOrEqual(T0 - 12 * H)
    for (let k = 1; k < bs.length; k++) expect(bs[k].t - bs[k - 1].t).toBe(H)
    // 再往左越过交易所最早一根：取到头后不再取
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 - 100 * H }])
    for (let k = 0; k < COMPARE_MAX_PAGES + 2; k++) await h.step()
    expect(h.store.get('ETHUSDT', '1h')!.bars![0].t).toBe(T0 - 20 * H)
    const n = h.calls.length
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 - 200 * H }])
    expect(h.calls.length).toBe(n)
  })

  it('推送：同一根就地改、下一根追加；隔了一截就重取末页而不硬连', async () => {
    const h = harness(exchange)
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 }])
    await h.step()
    const rev = h.store.get('ETHUSDT', '1h')!.rev
    expect(h.store.upsert('ETHUSDT', '1h', bar(T0 + 4 * H, 1, 2))).toBe(true)
    expect(h.store.upsert('ETHUSDT', '1h', bar(T0 + 5 * H, 2, 3))).toBe(true)
    const g = h.store.get('ETHUSDT', '1h')!
    expect(g.bars!.length).toBe(6); expect(g.bars![4].c).toBe(2); expect(g.rev).toBe(rev + 2)
    const n = h.calls.length
    h.store.upsert('ETHUSDT', '1h', bar(T0 + 9 * H, 5))
    expect(h.store.get('ETHUSDT', '1h')!.bars!.length).toBe(6)
    expect(h.calls.length).toBe(n + 1); expect(h.calls.at(-1)!.end).toBeNull()
    expect(h.store.upsert('BTCUSDT', '1h', bar(T0, 1))).toBe(false)
  })

  it('取的时候推送动了末根：合并最新一页时留住推送那根', async () => {
    const h = harness(exchange)
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 }])
    await h.step()
    h.store.resync()
    h.store.upsert('ETHUSDT', '1h', bar(T0 + 4 * H, 7, 77))
    await h.step()
    expect(h.store.get('ETHUSDT', '1h')!.bars!.at(-1)!.c).toBe(77)
  })

  it('取失败退避重试；最后一格不要了就撤掉、在路上的作废', async () => {
    let fail = true
    const h = harness((s, e) => (fail ? null : exchange(s, e)))
    h.store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 }])
    await h.step()
    expect(h.timers.length).toBe(1); expect(h.timers[0].ms).toBe(2000)
    fail = false
    h.timers[0].fn()
    await h.step()
    expect(h.store.get('ETHUSDT', '1h')!.bars!.length).toBe(5)
    // 两格共用：一格撤了还留着，两格都撤了才没
    h.store.want(1, [{ symbol: 'ETHUSDT', iv: '1h', from: T0 }])
    h.store.want(0, [])
    expect(h.store.streams()).toEqual([{ symbol: 'ETHUSDT', iv: '1h' }])
    h.store.want(1, [{ symbol: 'DXY', iv: '1h', from: T0 }])
    expect(h.store.get('ETHUSDT', '1h')).toBeNull()
    h.store.want(1, [])
    await h.step()
    expect(h.store.get('DXY', '1h')).toBeNull()
  })
})

describe('偏好清洗与同步', () => {
  const inputs: unknown[] = [
    null, 'x', 42, {}, [],
    ['ethusdt', 'binance/usd_m/ETHUSDT', 'macro/index/DXY', 'DXY', 'coinbase/spot/BTC-USD', 'binance/usd_m/SOLUSDT'],
    ['binance/usd_m/币安人生USDT', 1, null, 'binance/spot/BTCUSDT', 'binance/usd_m/BTCUSDT'],
    ['macro/index/SPX', 'a/b/c/d', '', 'coinbase/spot/eth-usd', 'coinbase/spot/ETH-USD'],
  ]
  it('电脑与手机网页同一条清洗规则（同输入同输出），最多三只', () => {
    for (const v of inputs) expect(cleanCompare(v)).toEqual(cleanCompareM(v))
    expect(cleanCompare(inputs[5])).toEqual(['binance/usd_m/ETHUSDT', 'macro/index/DXY', 'coinbase/spot/BTC-USD'])
    expect(MAX_COMPARE).toBe(3)
  })
  it('本机存的偏好读回来过清洗；出厂是空', () => {
    expect(factorySettings().compareSymbols).toEqual([])
    expect(SETTINGS_FIELDS).toContain('compareSymbols')
    expect(hydrate({ compareSymbols: ['ethusdt', 'ethusdt', 7] } as never).compareSymbols).toEqual(['binance/usd_m/ETHUSDT'])
    expect(hydrate({} as never).compareSymbols).toEqual([])
  })
  it('编解码：原样往返、坏值不进不出', () => {
    const keys = ['binance/usd_m/ETHUSDT', 'macro/index/DXY']
    expect(encodeSetting('compareSymbols', keys, undefined)).toEqual(keys)
    expect(decodeSetting('compareSymbols', keys, factorySettings())).toEqual(keys)
    expect(decodeSetting('compareSymbols', ['DXY', 'ethusdt'], factorySettings())).toEqual(['binance/usd_m/ETHUSDT'])
    expect(webSetting({ ...factorySettings(), compareSymbols: keys }, 'compareSymbols')).toEqual(keys)
    const o = encodeSettings({ ...factorySettings(), compareSymbols: keys }, undefined, {})
    expect(o!.body.compareSymbols).toEqual(keys)
  })
  it('对比改了，设置指纹跟着变（才会记账推上去）', () => {
    const s: WebState = { pinned: ['1h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, watch: { crypto: [], us: [], idx: [], com: [] }, drawings: {}, alerts: [], compareSymbols: [] }
    const a = fingerprint(s).settings
    s.compareSymbols = ['binance/usd_m/ETHUSDT']
    expect(fingerprint(s).settings).not.toBe(a)
  })
})

describe('同一账号跨端：对比跟着人走', () => {
  const state = (): WebState => ({ pinned: ['1h', '4h'], ind: { ma: true, ema: false, boll: false, vol: true, subs: [] }, params: null, watch: { crypto: ['BTCUSDT'], us: [], idx: [], com: [] }, drawings: {}, alerts: [], compareSymbols: [] })
  function browser(server: FakeServer, s = state()) {
    const store = new SyncStore(emptyArchive(), 'dev-' + Math.random(), () => server.now)
    const fp: Prints = {}
    let initial = true
    const engine = new Engine(store, server.transport(), OWNED, {
      capture: () => { if (!initial) captureInto(s, store, ctx, fp) },
      apply: () => { if (!initial) applyInto(s, store, ctx) },
    })
    return {
      s, store, engine, fp,
      async first() { await engine.full(); mergeFirst(s, store, ctx, { settings: 0, favorites: 0 }, false); initial = false; captureInto(s, store, ctx, fp); await engine.push() },
      async sync() { await engine.push(); await engine.pull(); await engine.push() },
    }
  }

  it('一端加了对比，另一端拉下来；删掉也同步', async () => {
    const server = new FakeServer()
    const a = browser(server), b = browser(server)
    await a.first(); await b.first()
    a.s.compareSymbols = ['binance/usd_m/ETHUSDT', 'macro/index/DXY']
    await a.sync(); await b.sync()
    expect(b.s.compareSymbols).toEqual(['binance/usd_m/ETHUSDT', 'macro/index/DXY'])
    b.s.compareSymbols = ['macro/index/DXY']
    await b.sync(); await a.sync()
    expect(a.s.compareSymbols).toEqual(['macro/index/DXY'])
    expect(server.objects.get('settings:chart')!.body.compareSymbols).toEqual(['macro/index/DXY'])
  })

  it('老账本（seen 里还没有 compareSymbols）升级：先按云端装，不拿网页的出厂空表冲掉手机设好的', async () => {
    const server = new FakeServer()
    const phone = browser(server), web = browser(server)
    await phone.first(); await web.first()
    phone.s.compareSymbols = ['binance/usd_m/ETHUSDT']
    await phone.sync(); await web.sync()
    // 模拟升级前的网页：页面状态里没有对比、账本也没记过这一项
    web.s.compareSymbols = []
    delete web.store.a.seen.compareSymbols
    const changed = adoptNewSettings(web.s, web.store)
    expect(changed).toEqual(['compareSymbols'])
    expect(web.s.compareSymbols).toEqual(['binance/usd_m/ETHUSDT'])
    expect(web.store.a.seen.compareSymbols).toEqual(['binance/usd_m/ETHUSDT'])
    await web.sync(); await phone.sync()
    expect(server.objects.get('settings:chart')!.body.compareSymbols).toEqual(['binance/usd_m/ETHUSDT'])
    expect(phone.s.compareSymbols).toEqual(['binance/usd_m/ETHUSDT'])
    // seen 已齐：再调是空操作；第一次对上（seen 空）不归它管
    expect(adoptNewSettings(web.s, web.store)).toEqual([])
    const fresh = new SyncStore(emptyArchive(), 'dev-x', () => server.now)
    expect(adoptNewSettings(state(), fresh)).toEqual([])
  })
})
