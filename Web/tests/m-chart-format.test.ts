// 移植自 KanpanCore/Tests/KanpanCoreTests/FormatTests.swift 与 ChartOptionsTests.swift 的倒计时三条。
// 每条 it 的标题带 Swift 测试名；黄金值、种子照抄。
//
// 没移植的：SymbolInfo 一族（priceDecimals / displayDecimals / knownPriceDecimals，网页图表不带品种目录）、
// ReviewLabels（复盘文案，网页图表没有）、TZChoice / TZOffset.zone（TS 只收固定分钟偏移，纽约冬夏
// 用 −300 / −240 两个固定值代入）、toFixedFast 的「快路接住多少」计数（TS 只有一条路）。
import { describe, expect, it } from 'vitest'
import {
  changePercentText, dateParts, fmtCountdown, fmtDayTime, fmtFull, fmtNum, fmtPrice, fmtTick, fmtVol,
  priceDecimalsFallback, toFixed, volUnit,
} from '../src/m/chart/format'
import { coreFixture, Rng, SplitMix } from './m-chart-fixtures'

const NY_WINTER = -300
const NY_SUMMER = -240
const EXCHANGE = 480
const UTC = 0

/** 对拍用的标准答案：把 double 精确展开成 m·2^e，在第 p 位上逢五远离零；舍完全是 0 的不带负号。 */
function toFixedExact(x: number, p: number): string {
  const dv = new DataView(new ArrayBuffer(8))
  dv.setFloat64(0, x)
  const bits = dv.getBigUint64(0)
  const neg = (bits >> 63n) === 1n
  const bexp = Number((bits >> 52n) & 0x7ffn)
  const frac = bits & ((1n << 52n) - 1n)
  const m = bexp === 0 ? frac : frac | (1n << 52n)
  const e = (bexp === 0 ? 1 : bexp) - 1075
  // |x|·10^p = num / den
  let num = m * 10n ** BigInt(p)
  let den = 1n
  if (e >= 0) num <<= BigInt(e)
  else den <<= BigInt(-e)
  let q = num / den
  const r = num - q * den
  if (2n * r >= den) q += 1n
  let digits = q.toString()
  if (p > 0) {
    if (digits.length <= p) digits = '0'.repeat(p + 1 - digits.length) + digits
    digits = digits.slice(0, digits.length - p) + '.' + digits.slice(digits.length - p)
  }
  return neg && q !== 0n ? '-' + digits : digits
}

/** Swift `Double.nextUp`（只用于非负有限值）。 */
function nextUp(x: number): number {
  const dv = new DataView(new ArrayBuffer(8))
  dv.setFloat64(0, x === 0 ? 0 : x)
  dv.setBigUint64(0, dv.getBigUint64(0) + 1n)
  return dv.getFloat64(0)
}

/** Swift `.rounded()`（逢五远离零）。 */
function swiftRound(v: number): number {
  const t = Math.trunc(v)
  return Math.abs(v - t) >= 0.5 ? t + Math.sign(v) : t
}

describe('FormatTests（格式化）', () => {
  it('numMatches · fmtNum 与原型全等', () => {
    const cases = coreFixture<{ num: [number, number, string][] }>('format').num
    expect(cases.length).toBeGreaterThan(0)
    for (const [x, p, want] of cases) expect(fmtNum(x, p), `fmtNum(${x}, ${p})`).toBe(want)
    expect(fmtNum(NaN, 2)).toBe('--')
    expect(fmtNum(Infinity, 2)).toBe('--')
  })

  it('volBuckets · 成交量分档', () => {
    const cases: [number, string][] = [
      [0, '0.00'], [1.5, '1.50'], [99.994, '99.99'], [100, '100'], [999, '999'],
      [1000, '1.00K'], [1234, '1.23K'], [9999.5, '10.00K'], [123456, '123.46K'],
      [1e6, '1.00M'], [84_200_000, '84.20M'], [98_765_432, '98.77M'],
      [1e9, '1.00B'], [8.32e9, '8.32B'], [-5.5e9, '-5.50B'],
      [1e12, '1.00T'], [1.5415e12, '1.54T'], [NaN, '--'],
    ]
    for (const [x, want] of cases) expect(fmtVol(x), `fmtVol(${x})`).toBe(want)
  })

  it('volPinnedUnit · 单位由外面传进来', () => {
    expect(fmtVol(8.32e9, 'm')).toBe('8320.00M')
    expect(fmtVol(9.9e8, 'b')).toBe('0.99B')
    expect(fmtVol(1234, 'plain')).toBe('1234')
    expect(volUnit(8.32e9)).toBe('b')
    expect(volUnit(999)).toBe('plain')
    expect(volUnit(-1.2e12)).toBe('t')
  })

  it('changePercentOneFormat · 涨跌幅只有一种写法', () => {
    expect(changePercentText(2.744)).toBe('+2.74%')
    expect(changePercentText(-2.745)).toBe('−2.75%')
    expect(changePercentText(0)).toBe('+0.00%')
    expect(changePercentText(-0.004)).toBe('+0.00%')
    expect(changePercentText(null)).toBe('—')
    expect(changePercentText(NaN)).toBe('—')
    expect(changePercentText(Infinity)).toBe('—')
    expect(changePercentText(123.456)).toBe('+123.46%')
  })

  it('toFixedRule · toFixed 与 JS 同规则', () => {
    const cases: [number, number, string][] = [
      [0.125, 2, '0.13'], [1.005, 2, '1.00'], [2.675, 2, '2.67'], [-0.125, 2, '-0.13'],
      [1.5, 0, '2'], [2.5, 0, '3'], [0.5, 0, '1'], [-2.5, 0, '-3'],
      [0, 2, '0.00'], [-0.0001, 2, '0.00'], [9.999, 2, '10.00'], [0.0001234, 8, '0.00012340'],
    ]
    for (const [x, p, want] of cases) expect(toFixed(x, p), `toFixed(${x}, ${p})`).toBe(want)
  })

  it('toFixedFastMatchesReference · 定点小数快路与精确展开逐位一致', () => {
    const rng = new SplitMix(0x6B616E70616En)
    const bad: string[] = []
    for (let k = 0; k < 60_000; k++) {
      const p = Number(rng.next() % 13n)
      const scale = 10 ** p
      const kind = Number(rng.next() % 4n)
      const mag = 10 ** (Number(rng.next() % 16n) - 6)
      const u = Number(rng.next() >> 11n) / 2 ** 53
      let x: number
      switch (kind) {
        case 0: x = (Number(rng.next() % 1_000_000n) + 0.5) / scale; break
        case 1: x = swiftRound(u * mag * scale) / scale; break
        case 2: x = u * mag; break
        default: x = nextUp(u * mag)
      }
      if (rng.next() % 3n === 0n) x = -x
      const got = toFixed(x, p), want = toFixedExact(x, p)
      if (got !== want && bad.length < 10) bad.push(`x=${x} p=${p} 得到 ${got}，应为 ${want}`)
    }
    expect(bad).toEqual([])
    expect(toFixed(1e17, 2)).toBe('100000000000000000.00')
    // 对拍标准自身也钉一下（Swift toFixedRule 的几条）。
    expect(toFixedExact(1.005, 2)).toBe('1.00')
    expect(toFixedExact(0.125, 2)).toBe('0.13')
    expect(toFixedExact(-0.0001, 2)).toBe('0.00')
  })

  it('priceDecimals · fmtNum(76800.06, 1)（BTC 步长 0.1 → 1 位）', () => {
    expect(fmtNum(76800.06, 1)).toBe('76800.1')
  })

  it('priceDecimalsComeFromTheSymbol · 价格小数位来自品种（fmtPrice 部分）', () => {
    expect(fmtPrice(76_800, 1)).toBe('76800.0')
    expect(fmtPrice(0.0123456, 7)).toBe('0.0123456')
    expect(fmtPrice(1.2345, 4)).toBe('1.2345')
    expect(fmtPrice(238.4, 2)).toBe('238.40')
    expect(fmtPrice(0.00000001234, 2)).not.toBe('0.00')
    expect(Number(fmtPrice(0.00000001234, 2))).toBeGreaterThan(0)
    expect(fmtPrice(0.000004, 4)).not.toBe('0.0000')
    expect(fmtPrice(0, 2)).toBe('0.00')
    expect(fmtPrice(NaN, 2)).toBe('--')
    expect(Number(fmtPrice(0.0000004, priceDecimalsFallback(0.0000004)))).toBeGreaterThan(0)
  })

  it('displayDecimalsUseTickSize · 已知小数位时 fmtPrice 的写法', () => {
    // 小数位本身由 SymbolInfo.displayDecimals 算（网页图表没有品种目录），这里只核 fmtPrice 那一半。
    const cases: [number, number, string][] = [
      [1774.23, 2, '1774.23'], [1045.4, 2, '1045.40'], [76800.06, 1, '76800.1'],
      [0.00001234, 8, '0.00001234'], [123, 0, '123'], [1.234, 3, '1.234'],
    ]
    for (const [x, d, want] of cases) expect(fmtPrice(x, d)).toBe(want)
  })

  it('localOffsetFollowsTheInstant · 本地时区按被格式化的时刻取偏移（纽约用固定 −300 / −240 代入）', () => {
    const winter = 1_767_571_200_000
    const summer = 1_783_296_000_000
    expect(fmtFull(winter, NY_WINTER)).toBe('2026-01-04 19:00')
    expect(fmtFull(summer, NY_SUMMER)).toBe('2026-07-05 20:00')
    expect(fmtFull(winter, EXCHANGE)).toBe('2026-01-05 08:00')
    expect(fmtFull(winter, UTC)).toBe('2026-01-05 00:00')
  })

  it('dailyLabelsCarryTheUTCTradingDate · 日线标签在纽约落到前一天', () => {
    const day = 86_400_000
    const daily = 1_789_776_000_000
    expect(fmtTick(daily, day, UTC)).toBe('09-19')
    expect(fmtTick(daily, day, EXCHANGE)).toBe('09-19')
    expect(fmtTick(daily, day, NY_SUMMER)).toBe('09-18')
    expect(fmtFull(daily, NY_SUMMER)).toBe('2026-09-18 20:00')
    expect(fmtTick(1_789_948_800_000, 7 * day, NY_SUMMER)).toBe('09-20')
    // 月档标签只写年-月（刻度都在 1 号，写日子没有信息量，同 iOS 63994ab2 · 审查 B·P3-3）。
    expect(fmtTick(1_790_812_800_000, 30 * day, NY_SUMMER)).toBe('2026-09')
  })

  it('overlayLabelsFollowTheChartsTimezone · 复盘浮层与坐标轴同一只钟（fmtDayTime / fmtTick / fmtFull 部分）', () => {
    const instant = 1_767_571_200_000
    expect(fmtDayTime(instant, EXCHANGE)).toBe('1/5 08:00')
    expect(fmtTick(instant, 60_000, EXCHANGE)).toBe('08:00')
    expect(fmtFull(instant, EXCHANGE)).toBe('2026-01-05 08:00')
    expect(fmtDayTime(instant, NY_WINTER)).toBe('1/4 19:00')
    expect(fmtDayTime(instant, NY_WINTER)).not.toBe(fmtDayTime(instant, EXCHANGE))
    expect(fmtDayTime(1_783_296_000_000, EXCHANGE)).toBe('7/6 08:00')
    expect(fmtFull(instant, NY_WINTER)).toBe('2026-01-04 19:00')
    expect(fmtFull(instant, EXCHANGE)).not.toBe(fmtFull(instant - 365 * 86_400_000, EXCHANGE))
  })

  it('labelsMatch · 时间标签与原型全等', () => {
    const labels = coreFixture<{ labels: { tz: string; off: number; ms: number; step: number; tick: string; full: string }[] }>('ticks').labels
    expect(labels.length).toBe(18)
    for (const row of labels) {
      // 唯一的有意分歧：年档原型写「年-月」，现在只写年（年档刻度都在 1 月 1 号，同 iOS · 审查 B·P3-3）。
      const expected = row.step >= 365 * 86_400_000 ? row.tick.slice(0, 4) : row.tick
      expect(fmtTick(row.ms, row.step, row.off), `${row.tz} step=${row.step}`).toBe(expected)
      expect(fmtFull(row.ms, row.off), `${row.tz} 完整时间`).toBe(row.full)
    }
  })

  it('labelShapes · 标签形态', () => {
    const t = 1_789_318_920_000
    expect(fmtTick(t, 60_000, 0).length).toBe(5)
    expect(fmtTick(t, 86_400_000, 0).length).toBe(5)
    expect(fmtTick(t, 90 * 86_400_000, 0), '按月应是 yyyy-MM').toBe('2026-09')
    expect(fmtTick(t, 365 * 86_400_000, 0), '按年应是 yyyy').toBe('2026')
    expect(fmtTick(1_789_257_600_000, 3_600_000, 0)).toContain('-')
  })

  it('datePartsMatchCalendar · 日期拆解与系统日历一致', () => {
    const r = new Rng(606)
    const bad: string[] = []
    for (let k = 0; k < 5000; k++) {
      const off = [0, 480, -300, 330, 570][r.i(0, 4)]
      const ms = swiftRound(r.d(-2.2e12, 2.2e12))
      const p = dateParts(ms, off)
      const d = new Date(ms + off * 60_000)
      const ok = p.year === d.getUTCFullYear() && p.month === d.getUTCMonth() + 1 && p.day === d.getUTCDate()
        && p.hour === d.getUTCHours() && p.minute === d.getUTCMinutes()
      if (!ok && bad.length < 10) bad.push(`ms=${ms} off=${off}：${JSON.stringify(p)} vs ${d.toISOString()}`)
    }
    expect(bad).toEqual([])
  })

  it('leapYears · 闰年与月末', () => {
    const cases: [number, string][] = [
      [951_782_400_000, '2000-02-29 00:00'],
      [1_709_164_800_000, '2024-02-29 00:00'],
      [1_677_628_800_000, '2023-03-01 00:00'],
      [1_735_689_599_000, '2024-12-31 23:59'],
      [1_735_689_600_000, '2025-01-01 00:00'],
      [0, '1970-01-01 00:00'],
      [-86_400_000, '1969-12-31 00:00'],
    ]
    for (const [ms, want] of cases) expect(fmtFull(ms, 0), `ms=${ms}`).toBe(want)
  })
})

describe('ChartOptionsTests（本根倒计时）', () => {
  it('countdownTiers · 倒计时三档文案', () => {
    expect(fmtCountdown(42_000)).toBe('00:42')
    expect(fmtCountdown(59_999)).toBe('00:59')
    expect(fmtCountdown(60_000)).toBe('01:00')
    expect(fmtCountdown(59 * 60_000 + 59_000)).toBe('59:59')
    expect(fmtCountdown(3_600_000)).toBe('1:00:00')
    expect(fmtCountdown(3 * 3_600_000 + 5 * 60_000 + 12_000)).toBe('3:05:12')
    expect(fmtCountdown(23 * 3_600_000 + 59 * 60_000 + 59_000)).toBe('23:59:59')
    expect(fmtCountdown(86_400_000)).toBe('1d 00:00')
    expect(fmtCountdown(6 * 86_400_000 + 7 * 3_600_000 + 8 * 60_000)).toBe('6d 07:08')
  })

  it('countdownNil · 倒计时归零与非数给 nil', () => {
    for (const v of [0, -1, NaN, Infinity]) expect(fmtCountdown(v)).toBeNull()
  })

  it('countdownWidthStable · 同档内宽度稳定', () => {
    const short = new Set(Array.from({ length: 59 }, (_, i) => fmtCountdown((i + 1) * 1000)!.length))
    expect([...short]).toEqual([5])
    const day = new Set(Array.from({ length: 9 }, (_, i) => fmtCountdown((i + 1) * 86_400_000)!.length))
    expect([...day]).toEqual([8])
  })
})
