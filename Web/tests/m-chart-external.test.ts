// 手机网页版图表外部指标取数（src/m/chart/external.source.ts）的数值测试。对照的是
// KanpanData/Sources/KanpanData/Feed/OISource.swift 的 fetchMetric / dedup / downsample / chartSeries 与
// KanpanNetwork/Sources/KanpanNetwork/Binance/Interval+OIPeriod.swift 的 oiPeriod。
// Swift 那边这几支没有单独的单元测试（OIIntervalCoverageTests 只钉了 w1 / 1M / 1y 没有原生 period），
// 下面的用例按 Swift 源码逐条写出，标题带对应的 Swift 名字。
import { describe, expect, it } from 'vitest'
import {
  REST_WINDOW_MS, chartSeries, dedup, downsample, fetchMetric, metricPeriod,
} from '../src/m/chart/external.source'
import type { ExternalID, MetricPoint } from '../src/m/chart/external.source'
import { BarSeries, INTERVALS, bar, bucketStart, stepMs } from '../src/m/chart/series'
import type { Interval } from '../src/m/chart/series'

const MIN = 60_000, HOUR = 3_600_000, DAY = 86_400_000
const pts = (...a: [number, number][]): MetricPoint[] => a.map(([time, value]) => ({ time, value }))

describe('metricPeriod（Interval.oiPeriod ?? (step ≥ 1d ? "1d" : "5m")）', () => {
  it('Interval.oiPeriod · 1m / 3m 退到 5m，15m…1d 原样，1w / 1M / 1y 没有原生档退到 1d', () => {
    const want: Record<Interval, string> = {
      '1m': '5m', '3m': '5m', '5m': '5m', '15m': '15m', '30m': '30m', '1h': '1h', '2h': '2h', '4h': '4h',
      '6h': '6h', '12h': '12h', '1d': '1d', '1w': '1d', '1M': '1d', '1y': '1d',
    }
    for (const iv of INTERVALS) expect(metricPeriod(iv), iv).toBe(want[iv])
  })
})

describe('OISource.dedup', () => {
  it('dedup · 按时间排序，同一时刻留后来的', () => {
    expect(dedup(pts([300, 1], [100, 2], [300, 3], [200, 4], [100, 5]))).toEqual(pts([100, 5], [200, 4], [300, 3]))
    expect(dedup([])).toEqual([])
    expect(dedup(pts([7, 1]))).toEqual(pts([7, 1]))
  })

  it('dedup · 非数的值不收（Swift 解码失败整页作废，网页逐条丢）', () => {
    expect(dedup(pts([100, 1], [100, NaN], [200, Infinity]))).toEqual(pts([100, 1]))
  })
})

describe('OISource.downsample', () => {
  it('downsample · 1m / 3m 比 5m 还细，原样返回（连顺序都不动）', () => {
    const raw = pts([3 * MIN, 1], [0, 2], [MIN, 3])
    expect(downsample(raw, '1m')).toBe(raw)
    expect(downsample(raw, '3m')).toBe(raw)
  })

  it('downsample · 每桶取最后一条，时间戳打在桶头上', () => {
    // 1h：三个小时里每 5 分钟一条，乱序给。
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % HOUR)
    const raw: MetricPoint[] = []
    for (let k = 0; k < 36; k++) raw.push({ time: t0 + k * 5 * MIN, value: k })
    raw.reverse()
    expect(downsample(raw, '1h')).toEqual(pts([t0, 11], [t0 + HOUR, 23], [t0 + 2 * HOUR, 35]))
    // 5m 本身也过一遍（interval == .m5）：桶内偏了几秒的点打回桶头。
    expect(downsample(pts([t0 + 3_000, 1], [t0 + 5 * MIN + 1, 2], [t0 + 5 * MIN + 9, 3]), '5m'))
      .toEqual(pts([t0, 1], [t0 + 5 * MIN, 3]))
    expect(downsample([], '1h')).toEqual([])
  })

  it('downsample · 周线从周一起、月线按日历月', () => {
    const mon = Date.UTC(2026, 8, 21) // 2026-09-21 周一
    expect(downsample(pts([mon + DAY, 1], [mon + 6 * DAY, 2], [mon + 7 * DAY, 3]), '1w'))
      .toEqual(pts([mon, 2], [mon + 7 * DAY, 3]))
    expect(downsample(pts([Date.UTC(2026, 1, 3), 1], [Date.UTC(2026, 1, 28, 23), 2], [Date.UTC(2026, 2, 1), 3]), '1M'))
      .toEqual(pts([Date.UTC(2026, 1, 1), 2], [Date.UTC(2026, 2, 1), 3]))
  })

  it('chartSeries · 去重、降采样，步长至少 5 分钟、带桶周期', () => {
    const t0 = Date.UTC(2026, 8, 1)
    const s = chartSeries(pts([t0 + 10 * MIN, 1], [t0, 9], [t0 + 70 * MIN, 2], [t0 + 10 * MIN, 5]), '1h')
    expect(s.timestamps).toEqual([t0, t0 + HOUR])
    expect(s.columns).toEqual([[5, 2]])
    expect(s.step).toBe(HOUR)
    expect(s.bucketInterval).toBe('1h')
    expect(chartSeries([], '1m').step).toBe(5 * MIN)
    const bars = BarSeries.fromBars('X', '1h', [0, 1, 2].map(k => bar(t0 + k * HOUR, 1, 1, 1, 1, 1)))
    const a = s.aligned(bars)[0]
    expect(a.slice(0, 2)).toEqual([5, 2])
    expect(Number.isNaN(a[2])).toBe(true)
  })
})

// ------------------------------------------------------------------ fetchMetric（假取数器）

interface Call { url: string; path: string; params: URLSearchParams }

/**
 * 假的币安 `/futures/data/*`：按 endTime 往回取最多 limit 条，升序给（和真接口一样）。
 * `fail` 在第几次请求时抛错；`rowsFor` 可以整个替换返回。
 */
function fakeFetcher(series: MetricPoint[], field: string, o: { fail?: number; rowsFor?: (end: number, limit: number) => Record<string, number>[] } = {}) {
  const calls: Call[] = []
  const fetcher = async <T,>(url: string): Promise<T> => {
    const u = new URL(url)
    calls.push({ url, path: u.pathname, params: u.searchParams })
    if (o.fail != null && calls.length === o.fail) throw new Error('boom')
    const end = Number(u.searchParams.get('endTime')), limit = Number(u.searchParams.get('limit'))
    if (o.rowsFor) return o.rowsFor(end, limit) as T
    const eligible = series.filter(p => p.time <= end)
    return eligible.slice(Math.max(0, eligible.length - limit)).map(p => ({ timestamp: p.time, [field]: p.value })) as T
  }
  return { calls, fetcher }
}

/** now 取一个 5 分钟桶中间的时刻，数据是从 40 天前到 now 的每 5 分钟一条。 */
const NOW = Date.UTC(2026, 8, 29, 12, 2, 30)
const FIVE = 5 * MIN
const firstSample = bucketStart(NOW - 40 * DAY, '5m')
const everyFive: MetricPoint[] = []
for (let t = firstSample; t <= NOW; t += FIVE) everyFive.push({ time: t, value: (t - firstSample) / FIVE })

describe('OISource.fetchMetric（近 30 天那一段）', () => {
  it('fetchMetric · 从右往左 500 条一页翻，截在近 30 天里，翻到底算问完', async () => {
    const { calls, fetcher } = fakeFetcher(everyFive, 'longShortRatio')
    const r = await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - 60 * DAY, NOW + HOUR, NOW, fetcher)
    const cutoff = NOW - REST_WINDOW_MS
    const want = everyFive.filter(p => p.time >= cutoff && p.time <= NOW)
    expect(r.complete).toBe(true)
    expect(r.points).toEqual(want)
    // 30 天 5 分钟 = 8640 条 → 18 页满页 + 最后一页 first ≤ lower 收住。
    expect(calls.length).toBe(Math.ceil((want.length + 1) / 500))
    // 第一页 endTime = min(to, now)；之后每页 endTime = 上一页第一条 − 1。
    expect(Number(calls[0].params.get('endTime'))).toBe(NOW)
    for (let k = 1; k < calls.length; k++) {
      const prevEnd = Number(calls[k - 1].params.get('endTime'))
      const prevFirst = everyFive.filter(p => p.time <= prevEnd).slice(-500)[0].time
      expect(Number(calls[k].params.get('endTime'))).toBe(prevFirst - 1)
    }
    for (const c of calls) {
      expect(c.path).toBe('/futures/data/globalLongShortAccountRatio')
      expect(c.params.get('symbol')).toBe('BTCUSDT')
      expect(c.params.get('period')).toBe('5m')
      expect(c.params.get('limit')).toBe('500')
    }
  })

  it('fetchMetric · to 早于 now 时从 to 往回翻，晚于 to 的不要', async () => {
    const { calls, fetcher } = fakeFetcher(everyFive, 'longShortRatio')
    const to = NOW - 2 * DAY + 7, from = NOW - 3 * DAY
    const r = await fetchMetric('LSR', 'BTCUSDT', '1h', from, to, NOW, fetcher)
    expect(Number(calls[0].params.get('endTime'))).toBe(to)
    expect(calls[0].params.get('period')).toBe('1h')
    expect(r.complete).toBe(true)
    // 交回的是按 1h 降采样过的（OISource.fetchMetric 末尾的 downsample）：每小时取最后一条、打在桶头。
    expect(r.points).toEqual(downsample(everyFive.filter(p => p.time >= from && p.time <= to), '1h'))
    expect(r.points.every(p => p.time % HOUR === 0)).toBe(true)
  })

  it('fetchMetric · 不满一页就是问完了；空页也是问完了', async () => {
    const short = everyFive.slice(-120)
    const a = fakeFetcher(short, 'longShortRatio')
    const r = await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - DAY, NOW, NOW, a.fetcher)
    expect(a.calls.length).toBe(1)
    expect(r.complete).toBe(true)
    expect(r.points).toEqual(short.filter(p => p.time >= NOW - DAY))
    const b = fakeFetcher([], 'longShortRatio')
    const e = await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - DAY, NOW, NOW, b.fetcher)
    expect(b.calls.length).toBe(1)
    expect(e).toEqual({ points: [], complete: true })
  })

  it('fetchMetric · 断在半路：已经到手的几页照用，complete 留假', async () => {
    const { calls, fetcher } = fakeFetcher(everyFive, 'longShortRatio', { fail: 3 })
    const r = await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - 20 * DAY, NOW, NOW, fetcher)
    expect(calls.length).toBe(3)
    expect(r.complete).toBe(false)
    expect(r.points.length).toBe(1000)
    expect(r.points[r.points.length - 1].time).toBe(everyFive[everyFive.length - 1].time)
  })

  it('fetchMetric · 最多翻 20 页，翻满还没到下界就算没问完', async () => {
    // 每页 500 条都挤在 endTime 前 500 毫秒里：永远翻不到下界。
    const rowsFor = (end: number, limit: number) =>
      Array.from({ length: limit }, (_, k) => ({ timestamp: end - (limit - 1) + k, longShortRatio: 1 }))
    const { calls, fetcher } = fakeFetcher([], 'longShortRatio', { rowsFor })
    const r = await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - DAY, NOW, NOW, fetcher)
    expect(calls.length).toBe(20)
    expect(r.complete).toBe(false)
    // 已经到手的 20 页照用（降采样后挤在同一两个 5 分钟桶里）。
    expect(r.points.length).toBeGreaterThan(0)
    expect(r.points.every(p => p.time % FIVE === 0)).toBe(true)
  })

  it('fetchMetric · from > to 或整段早于近 30 天：不发请求，算问完（归档那一段网页不做）', async () => {
    const a = fakeFetcher(everyFive, 'longShortRatio')
    expect(await fetchMetric('LSR', 'BTCUSDT', '5m', NOW, NOW - 1, NOW, a.fetcher)).toEqual({ points: [], complete: true })
    expect(await fetchMetric('LSR', 'BTCUSDT', '5m', NOW - 50 * DAY, NOW - 40 * DAY, NOW, a.fetcher)).toEqual({ points: [], complete: true })
    expect(a.calls.length).toBe(0)
  })

  for (const [iv, sample] of [['1h', '1h'], ['1m', '5m'], ['15m', '15m'], ['1w', '1d']] as [Interval, Interval][]) {
    it(`fetchMetric(${iv}) · 主动买卖比不要还没成型的当前桶（按 ${sample} 取桶），多空比照收`, async () => {
      const current = bucketStart(NOW, sample)
      const series = pts([current - 2 * stepMs(sample), 1], [current - stepMs(sample), 2], [current, 3])
      const taker = fakeFetcher(series, 'buySellRatio')
      const r = await fetchMetric('TAKER', 'BTCUSDT', iv, NOW - DAY * 20, NOW, NOW, taker.fetcher)
      expect(taker.calls[0].path).toBe('/futures/data/takerlongshortRatio')
      expect(r.points).toEqual(downsample(series.slice(0, 2), iv))
      expect(r.complete).toBe(true)
      const lsr = fakeFetcher(series, 'longShortRatio')
      const l = await fetchMetric('LSR', 'BTCUSDT', iv, NOW - DAY * 20, NOW, NOW, lsr.fetcher)
      expect(l.points).toEqual(downsample(series, iv))
      expect(l.points[l.points.length - 1].value).toBe(3)
    })
  }

  it('fetchMetric · 四条接口的路径、参数和取值（基差存百分数）', async () => {
    const one = pts([NOW - HOUR, 0.0123])
    const cases: [ExternalID, string, string, string, number][] = [
      ['OI', '/futures/data/openInterestHist', 'symbol', 'sumOpenInterest', 0.0123],
      ['LSR', '/futures/data/globalLongShortAccountRatio', 'symbol', 'longShortRatio', 0.0123],
      ['TAKER', '/futures/data/takerlongshortRatio', 'symbol', 'buySellRatio', 0.0123],
      ['BASIS', '/futures/data/basis', 'pair', 'basisRate', 1.23],
    ]
    for (const [id, path, key, field, value] of cases) {
      const { calls, fetcher } = fakeFetcher(one, field)
      const r = await fetchMetric(id, 'ETHUSDT', '1h', NOW - DAY, NOW, NOW, fetcher)
      expect(calls[0].path, id).toBe(path)
      expect(calls[0].params.get(key), id).toBe('ETHUSDT')
      if (id === 'BASIS') expect(calls[0].params.get('contractType')).toBe('PERPETUAL')
      expect(r.points.length, id).toBe(1)
      expect(r.points[0].value, id).toBeCloseTo(value, 12)
    }
  })
})
