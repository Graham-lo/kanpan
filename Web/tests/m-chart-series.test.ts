// 移植自 KanpanCore/Tests/KanpanCoreTests 的 BarSeriesTests / SeriesGapTests / IrregularIntervalTests /
// IntervalLabelTests / ExternalSeriesTests（book、alignment）。每条 it 的标题带 Swift 测试名，黄金值照抄。
//
// 没移植的：
// - BarSeriesTests.revisionAgreesWithContent：TS 的 BarSeries 没有 `==` / `samePrefix`（列式序列只比戳，
//   逐列比没有对应实现），只移植了 revisionMoves 里戳的走向。
// - BarSeriesTests.symbolInfo：SymbolInfo 不在网页图表里。
// - IntervalLabelTests.rawStringFallsBackToItself：TS 没有 `Interval.shortLabel(raw:)`。
// - ExternalSeriesTests.cache 已在 m-indicator.test.ts；taker / partialBucket：TS 没有 TakerBucket（网页不接逐笔成交）。
import { describe, expect, it } from 'vitest'
import { BarSeries, ExternalSeries, INTERVALS, INTERVAL_SHORT, bar as mkBar, bucketStart, isIrregular, jsRound, stepMs } from '../src/m/chart/series'
import type { Bar, Interval } from '../src/m/chart/series'
import { ViewWindow, visibleRange } from '../src/m/chart/geometry'
import { makeOrderBook } from '../src/m/chart/state'
import { Rng, synthSeries } from './m-chart-fixtures'

const bar = (t: number, v = 1): Bar => mkBar(t, v, v + 1, v - 1, v + 0.5, v * 10)
const regular = (n: number, step = 3_600_000, t0 = 1_700_000_000_000): BarSeries =>
  BarSeries.fromBars('BTCUSDT', '1h', Array.from({ length: n }, (_, i) => bar(t0 + i * step, i)))
const utcMs = (year: number, month: number, day: number): number => Date.UTC(year, month - 1, day)

describe('BarSeriesTests（K 线序列）', () => {
  it('regularDerivesTime · 等距周期不存 openTime，时间由 t0 推', () => {
    const s = regular(100)
    expect(s.openTime.length).toBe(0)
    expect(s.count).toBe(100)
    for (let i = 0; i < s.count; i++) expect(s.time(i)).toBe(s.t0 + i * s.step)
    expect(s.firstTime).toBe(s.t0)
    expect(s.lastTime).toBe(s.t0 + 99 * s.step)
  })

  it('timeClampsIndex · 下标越界要夹住，不能崩', () => {
    const s = regular(10)
    expect(s.time(-3)).toBe(s.t0 - 3 * s.step)
    const m = BarSeries.fromBars('X', '1M', [0, 1, 2].map(k => bar(k * 100, 1)))
    expect(m.time(-5)).toBe(m.openTime[0])
    expect(m.time(99)).toBe(m.openTime[2])
  })

  it('emptySeries · 空序列的时间', () => {
    const s = BarSeries.fromBars('X', '1h', [])
    expect(s.isEmpty && s.count === 0).toBe(true)
    expect(s.lastTime).toBe(s.t0)
    expect(s.index(12345)).toBe(0)
  })

  it('indexRoundsToNearest · 最近一根而不是向下取整', () => {
    const s = regular(10)
    const step = s.step
    expect(s.index(s.t0)).toBe(0)
    expect(s.index(s.t0 + step * 0.49)).toBe(0)
    expect(s.index(s.t0 + step * 0.5)).toBe(1)
    expect(s.index(s.t0 + step * 0.51)).toBe(1)
    expect(s.index(s.t0 + step * 3)).toBe(3)
    expect(s.index(s.t0 - 1e9)).toBe(0)
    expect(s.index(s.t0 + 1e12)).toBe(9)
  })

  it('jsRoundOnNegativeHalves · 负半数按 JS 规则进位', () => {
    expect(jsRound(-0.5) === 0).toBe(true)
    expect(jsRound(-1.5)).toBe(-1)
    expect(jsRound(-2.5)).toBe(-2)
    expect(jsRound(0.5)).toBe(1)
    expect(jsRound(1.5)).toBe(2)
    expect(jsRound(-1.6)).toBe(-2)
  })

  it('replaceLast · 覆盖末根', () => {
    const s = regular(5)
    const t = s.lastTime
    s.replaceLast(mkBar(t, 9, 99, 0.5, 42, 7))
    expect(s.count).toBe(5)
    expect([s.close[4], s.high[4], s.low[4], s.volume[4]]).toEqual([42, 99, 0.5, 7])
    expect(s.lastTime).toBe(t)
    const e = BarSeries.fromBars('X', '1h', [])
    e.replaceLast(bar(1000))
    expect(e.count).toBe(1)
    expect(e.t0).toBe(1000)
  })

  it('appendBar · 追加新根', () => {
    const s = regular(5)
    const t = s.lastTime + s.step
    s.append(bar(t, 50))
    expect(s.count).toBe(6)
    expect(s.lastTime).toBe(t)
    expect(s.close[5]).toBe(50.5)
    expect(s.openTime.length).toBe(0)
  })

  it('upsertCases · upsert 三种情形', () => {
    const s = regular(5)
    const last = s.lastTime
    expect(s.upsert(mkBar(last, 1, 2, 0, 1.5, 3))).toBe(true)
    expect(s.count).toBe(5)
    expect(s.close[4]).toBe(1.5)
    expect(s.upsert(bar(last + s.step, 7))).toBe(true)
    expect(s.count).toBe(6)
    const snapshot = s.clone()
    expect(s.upsert(bar(last - 10 * s.step, 999))).toBe(false)
    expect(s.close).toEqual(snapshot.close)
    expect(s.count).toBe(snapshot.count)
    expect(s.revision).toBe(snapshot.revision)
    const e = BarSeries.fromBars('X', '1h', [])
    expect(e.upsert(bar(5))).toBe(true)
    expect(e.count).toBe(1)
  })

  it('repeatedUpsertKeepsLength · 反复 upsert 末根不长胖', () => {
    const s = regular(30)
    const r = new Rng(555)
    const t = s.lastTime
    for (let k = 0; k < 500; k++) {
      const c = r.d(100, 200)
      s.upsert(mkBar(t, 100, c + 5, c - 5, c, r.d(0, 10)))
    }
    expect(s.count).toBe(30)
  })

  it('prependHistory · 向前补历史', () => {
    const s = regular(10)
    const t0 = s.t0
    s.prepend([1, 2, 3, 4, 5].map(k => bar(t0 - k * s.step, -k)))
    expect(s.count).toBe(15)
    expect(s.t0).toBe(t0 - 5 * s.step)
    expect(s.time(0)).toBe(s.t0)
    for (let i = 1; i < s.count; i++) expect(s.time(i)).toBeGreaterThan(s.time(i - 1))
    const before = s.count
    s.prepend([bar(s.t0, 0), bar(s.t0 + s.step, 0)])
    expect(s.count).toBe(before)
    s.prepend([])
    expect(s.count).toBe(before)
  })

  it('prependDedupesBatch · 补历史的那批自带重根', () => {
    const s = regular(10)
    const t0 = s.t0, step = s.step
    s.prepend([bar(t0 - 2 * step, 1), bar(t0 - step, 2), bar(t0 - step, 3), bar(t0 - 3 * step, 4)])
    expect(s.count).toBe(13)
    expect(s.openTime.length).toBe(0)
    expect(s.close[2]).toBe(3.5)
    for (let i = 0; i < s.count; i++) expect(s.index(s.time(i))).toBe(i)
  })

  it('prependIrregular · 不等距周期补历史', () => {
    const months = Array.from({ length: 6 }, (_, k) => bar(utcMs(2025, 1 + k, 1), k))
    const s = BarSeries.fromBars('X', '1M', months)
    expect(s.openTime.length).toBe(6)
    s.prepend([1, 2, 3].map(k => bar(utcMs(2024, 13 - k, 1), -k)))
    expect(s.count).toBe(9)
    expect(s.openTime.length).toBe(9)
    expect(s.t0).toBe(utcMs(2024, 10, 1))
    for (let i = 0; i < s.count; i++) expect(s.time(i)).toBe(s.openTime[i])
    for (let i = 0; i < s.count; i++) expect(s.index(s.openTime[i])).toBe(i)
  })

  it('appendBuildsTable · 不等距周期追加时补建 openTime 表', () => {
    const step = stepMs('1M')
    const s = new BarSeries({ symbol: 'X', interval: '1M', t0: 0, step, open: [1, 2], high: [1, 2], low: [1, 2], close: [1, 2], volume: [1, 2], openTime: [] })
    expect(s.openTime.length).toBe(0)
    s.append(bar(step * 2 + 777))
    expect(s.openTime.length).toBe(3)
    expect(s.openTime[0]).toBe(0)
    expect(s.openTime[1]).toBe(step)
  })

  it('barRoundTrip · bar(at:) 取出来的和列里的一致', () => {
    const s = regular(20)
    for (let i = 0; i < s.count; i++) {
      const b = s.bar(i)
      expect(b.openTime).toBe(s.time(i))
      expect([b.open, b.high, b.low, b.close, b.volume]).toEqual([s.open[i], s.high[i], s.low[i], s.close[i], s.volume[i]])
    }
  })

  it('oiAlign · 持仓量对齐', () => {
    const s = regular(10, 3_600_000, 1_700_000_000_000)
    const oiT0 = s.t0 + 3_600_000
    const oi = new ExternalSeries({ t0: oiT0, step: 300_000, columns: [Array.from({ length: 200 }, (_, k) => k)] })
    const a = oi.aligned(s)[0]
    expect(a.length).toBe(s.count)
    expect(Number.isNaN(a[0])).toBe(true)
    expect(a[1]).toBe(0)
    expect(a[2]).toBe(12)
    expect(a[3]).toBe(24)
    const b = new ExternalSeries({ t0: oiT0, step: 300_000, columns: [[0, 1, 2]] }).aligned(s)[0]
    expect(b[1]).toBe(0)
    expect(Number.isNaN(b[2])).toBe(true)
    const dirty = new ExternalSeries({ t0: 0, step: 0, columns: [[1, 2]] }).aligned(s)[0]
    expect(dirty.length).toBe(s.count)
    expect(dirty.every(Number.isNaN)).toBe(true)
  })

  it('revisionMoves · 身份戳：覆盖末根不动前缀，追加一根把老整条当前缀', () => {
    const a = regular(10)
    const tick = a.clone()
    tick.replaceLast(bar(a.lastTime, 99))
    expect(tick.revision).not.toBe(a.revision)
    expect(tick.prefixRevision).toBe(a.prefixRevision)

    const grown = a.clone()
    grown.append(bar(a.lastTime + a.step, 11))
    expect(grown.prefixRevision).toBe(a.revision)
    expect(grown.isOneBarAfter(a)).toBe(true)

    // 直接改列的人要自己调 stampAll()（Swift 的列 didSet 自动作废），两个戳都得换。
    const poked = a.clone()
    poked.close[3] += 1
    poked.stampAll()
    expect(poked.revision).not.toBe(a.revision)
    expect(poked.prefixRevision).not.toBe(a.prefixRevision)

    const twin = regular(10)
    expect(twin.revision).not.toBe(a.revision)
    expect(twin.close).toEqual(a.close)
  })
})

describe('SeriesGapTests（带洞序列的时间）', () => {
  const T0 = 1_700_000_000_000
  const STEP = stepMs('1m')
  const slot = (k: number): Bar => bar(T0 + k * STEP, k)
  const series = (ks: number[]): BarSeries => BarSeries.fromBars('BTCUSDT', '1m', ks.map(slot))
  const range = (a: number, b: number): number[] => Array.from({ length: b - a }, (_, i) => a + i)

  it('holeDoesNotShiftTheTail · 中间缺一根，后面每一根的时间不能整体前移', () => {
    const slots = [0, 1, 2, 4, 5]
    const s = series(slots)
    expect(s.openTime.length).toBeGreaterThan(0)
    slots.forEach((k, i) => expect(s.time(i), `第 ${i} 根`).toBe(T0 + k * STEP))
    expect(s.lastTime).toBe(T0 + 5 * STEP)
    expect(s.index(T0 + 5 * STEP)).toBe(4)
  })

  it('filledSeriesGoesBackToTheFastPath · 洞被补上之后整段回到严格等距的快路', () => {
    const s = series(range(0, 6))
    expect(s.openTime.length).toBe(0)
    for (let i = 0; i < s.count; i++) expect(s.time(i)).toBe(T0 + i * STEP)
  })

  it('appendAcrossAHoleKeepsEarlierTimes · 跨过一个洞追加末根，前面那些根的时间一根不动', () => {
    const s = series(range(0, 3))
    expect(s.openTime.length).toBe(0)
    s.append(slot(7))
    expect(s.count).toBe(4)
    for (let i = 0; i < 3; i++) expect(s.time(i)).toBe(T0 + i * STEP)
    expect(s.lastTime).toBe(T0 + 7 * STEP)
    s.upsert(bar(T0 + 7 * STEP, 99))
    expect(s.count).toBe(4)
    expect(s.close[s.count - 1]).toBe(99.5)
  })

  it('prependWithAGapKeepsBothSidesHonest · 补历史接上的一段不连续时，两边的时间都要对', () => {
    const s = series(range(5, 8))
    s.prepend([slot(0), slot(1)])
    expect(s.count).toBe(5)
    expect(s.firstTime).toBe(T0)
    ;[0, 1, 5, 6, 7].forEach((k, i) => expect(s.time(i), `第 ${i} 根`).toBe(T0 + k * STEP))
    const whole = series(range(0, 8))
    expect(whole.openTime.length).toBe(0)
    expect(whole.lastTime).toBe(T0 + 7 * STEP)
  })

  it('contiguousPrependStaysOnTheFastPath · 补历史接得严丝合缝时仍然走快路', () => {
    const s = series(range(3, 6))
    s.prepend(range(0, 3).map(slot))
    expect(s.count).toBe(6)
    expect(s.openTime.length).toBe(0)
    for (let i = 0; i < 6; i++) expect(s.time(i)).toBe(T0 + i * STEP)
  })

  it('irregularIntervalsAlwaysKeepTheColumn · 不等距周期永远带着 openTime，不许被当成等距省掉', () => {
    const s = BarSeries.fromBars('BTCUSDT', '1M', range(0, 4).map(k => bar(k * stepMs('1M'), 1)))
    expect(s.openTime.length).toBeGreaterThan(0)
  })

  it('firstAppendOnEmptyIrregularSeriesKeepsTheColumn · 空的不等距序列追加第一根，列不能漏掉', () => {
    const t = 1_700_000_000_000
    const b = bar(t, 7)
    const s = new BarSeries({ symbol: 'BTCUSDT', interval: '1M', t0: 0, open: [], high: [], low: [], close: [], volume: [] })
    s.append(b)
    expect(s.openTime).toEqual([t])
    expect(s.time(0)).toBe(t)
    const ref = BarSeries.fromBars('BTCUSDT', '1M', [b])
    expect({ t0: s.t0, openTime: s.openTime, close: s.close, open: s.open, volume: s.volume })
      .toEqual({ t0: ref.t0, openTime: ref.openTime, close: ref.close, open: ref.open, volume: ref.volume })
  })
})

describe('IrregularIntervalTests（不等距周期）', () => {
  const monthStarts = Array.from({ length: 84 }, (_, k) => Date.UTC(2019 + Math.floor(k / 12), k % 12, 1))
  const monthly = (): BarSeries => {
    const s = synthSeries(monthStarts.length, { interval: '1M', t0: monthStarts[0], seed: 33 })
    s.openTime = monthStarts.slice()
    return s
  }

  it('onlyMonthlyAndYearlyAreIrregular · 只有 1M / 1y 算不等距', () => {
    for (const iv of INTERVALS) expect(isIrregular(iv), iv).toBe(iv === '1M' || iv === '1y')
  })

  it('indexRoundTrip · indexAt(openTime[i]) == i', () => {
    const s = monthly()
    for (let i = 0; i < s.count; i++) {
      expect(s.index(s.openTime[i])).toBe(i)
      expect(s.time(i)).toBe(monthStarts[i])
    }
  })

  it('pixelRoundTrip · 过一遍像素再回来还是同一根', () => {
    const s = monthly()
    const plotW = 390
    const v = ViewWindow.fromTo(s.firstTime - 1e9, s.lastTime + 1e9)
    for (let i = 0; i < s.count; i++) {
      const x = v.x(s.openTime[i], plotW)
      expect(s.index(v.t(x, plotW)), `第 ${i} 根 x=${x}`).toBe(i)
    }
  })

  it('nearestAndBounds · 就近取整与边界', () => {
    const s = monthly()
    expect(s.index(s.openTime[0] - 1e12)).toBe(0)
    expect(s.index(s.openTime[s.count - 1] + 1e12)).toBe(s.count - 1)
    for (let i = 0; i < s.count - 1; i++) {
      const a = s.openTime[i], b = s.openTime[i + 1]
      expect(s.index(a + (b - a) * 0.2)).toBe(i)
      expect(s.index(a + (b - a) * 0.8)).toBe(i + 1)
    }
  })

  it('monthsReallyDiffer · 月长确实不等', () => {
    const gaps = new Set(monthStarts.slice(1).map((t, i) => t - monthStarts[i]))
    expect(gaps.size).toBeGreaterThanOrEqual(3)
  })

  it('weeklyIsUniform · 1w 等距推导与 openTime 一致', () => {
    const week = 7 * 86_400_000
    const firstMonday = 4 * 86_400_000
    const t0 = firstMonday + week * 2800
    const s = synthSeries(300, { interval: '1w', t0, seed: 44 })
    expect(s.openTime.length).toBe(0)
    for (let i = 0; i < s.count; i++) {
      expect(s.time(i)).toBe(t0 + i * week)
      expect(s.index(t0 + i * week)).toBe(i)
      expect((s.time(i) - firstMonday) % week).toBe(0)
      expect(bucketStart(s.time(i), '1w')).toBe(s.time(i))
    }
  })

  it('appendAndVisible · 追加与可见区间', () => {
    const s = monthly()
    const next = monthStarts[monthStarts.length - 1] + 31 * 86_400_000
    s.append(mkBar(next, 1, 2, 0.5, 1.5, 10))
    expect(s.lastTime).toBe(next)
    expect(s.index(next)).toBe(s.count - 1)
    const r = visibleRange(ViewWindow.fromTo(s.openTime[10], s.openTime[20]), s)
    expect(r.lo <= 10 && r.hi >= 20).toBe(true)
    expect(r.lo >= 9 && r.hi <= 21).toBe(true)
  })
})

describe('IntervalLabelTests（周期短写）', () => {
  it('everyIntervalHasItsOwnShortLabel', () => {
    const labels = INTERVALS.map(iv => INTERVAL_SHORT[iv])
    expect(new Set(labels).size).toBe(INTERVALS.length)
    expect(labels).toEqual(['1分', '3分', '5分', '15分', '30分', '1时', '2时', '4时', '6时', '12时', '1日', '1周', '1月', '1年'])
  })

  it('noTwoLabelsDifferOnlyByCase', () => {
    const folded = INTERVALS.map(iv => INTERVAL_SHORT[iv].toLowerCase())
    expect(new Set(folded).size).toBe(INTERVALS.length)
    expect(INTERVAL_SHORT['1m']).not.toBe(INTERVAL_SHORT['1M'])
  })
})

describe('ExternalSeriesTests（外部指标：对齐、盘口）', () => {
  /** Swift OISeries.aligned(to:) 的稀疏分支原样照写，当裁判。 */
  function oiAlignedReference(times: number[], values: number[], step: number, iv: Interval | null, s: BarSeries): number[] {
    const out = new Array<number>(s.count).fill(NaN)
    if (!(step > 0) || times.length !== values.length || !times.length) return out
    const last = times[times.length - 1]
    let j = 0
    for (let i = 0; i < s.count; i++) {
      const t = s.time(i)
      while (j + 1 < times.length && times[j + 1] <= t) j++
      if (iv) {
        const matching = stepMs(iv) >= 300_000 ? times[j] === bucketStart(t, iv) : times[j] <= t && t - times[j] < 300_000
        if (matching) out[i] = values[j]
      } else if (times[j] <= t && t < last + step) out[i] = values[j]
    }
    return out
  }
  const bits = (a: number[]): string[] => a.map(v => (Number.isNaN(v) ? 'NaN' : String(v)))

  for (const interval of INTERVALS) {
    it(`alignment(${interval}) · 全部周期的稀疏对齐与持仓量逐位相同`, () => {
      const day = utcMs(2025, 1, 1)
      const series = BarSeries.fromBars('TEST', interval,
        Array.from({ length: 160 }, (_, i) => mkBar(day + i * stepMs(interval), 100, 101, 99, 100, 10)))
      for (const sparse of [false, true]) {
        const step = Math.max(300_000, stepMs(interval))
        const pts = Array.from({ length: 100 }, (_, k) => k).filter(k => !sparse || k % 7 !== 0)
          .map(k => ({ time: day + k * step, values: [k * 1.234] }))
        const ext = ExternalSeries.fromPoints(pts, step, interval)
        const got = ext.aligned(series)[0]
        const want = oiAlignedReference(pts.map(p => p.time), pts.map(p => p.values[0]), step, interval, series)
        expect(bits(got)).toEqual(bits(want))
        // 只重算尾巴那条路（aligned(to:from:previous:)）逐位同整列。
        for (const start of [0, 1, 37, 159, 160]) {
          const prev = [got.slice(0, start)]
          expect(bits(ext.alignedFrom(series, start, prev)[0]), `start=${start}`).toEqual(bits(got))
        }
      }
    })
  }

  it('book · 盘口只保留有效五档并按买降卖升排序', () => {
    const levels = [1, 2, 3, 4, 5, 6, 7, 8].map(p => ({ price: p, quantity: 1 }))
      .concat([{ price: NaN, quantity: 2 }, { price: 9, quantity: 0 }])
    const book = makeOrderBook('TEST', 1, levels, levels)
    expect(book.bids.map(l => l.price)).toEqual([8, 7, 6, 5, 4])
    expect(book.asks.map(l => l.price)).toEqual([1, 2, 3, 4, 5])
  })
})
