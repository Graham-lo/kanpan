import { describe, expect, it } from 'vitest'
import {
  barsBetween, buildDraft, captureRange, checkDraft, horizonMs, recordInterval, sideLevels, type BarLike, type Capture,
} from '../src/notes/draft'
import { noMatchText } from '../src/pages/review'

const H = 3600e3
/** 从 t0 起每小时一根，高低收随下标走 */
const hourly = (n: number, t0 = Date.UTC(2026, 8, 1)): BarLike[] =>
  Array.from({ length: n }, (_, i) => ({ t: t0 + i * H, h: 100 + i + 2, l: 100 + i - 2, c: 100 + i }))

describe('记一笔 · 周期换算', () => {
  it('原生周期原样；秒级记 1 分；自定义分钟按能整除它的最大原生周期', () => {
    expect(recordInterval('1h')).toBe('1h')
    expect(recordInterval('1M')).toBe('1M')
    expect(recordInterval('5s')).toBe('1m')
    expect(recordInterval('7m')).toBe('1m')
    expect(recordInterval('90m')).toBe('30m')
    expect(recordInterval('10m')).toBe('5m')
  })

  it('根数和服务端一样按时间整除；月线按日历', () => {
    expect(barsBetween('1h', 0, 10 * H)).toBe(10)
    expect(barsBetween('1h', 0, 10 * H - 1)).toBe(9)
    expect(barsBetween('1M', Date.UTC(2026, 0, 1), Date.UTC(2026, 3, 1))).toBe(3)
    expect(barsBetween('1M', Date.UTC(2026, 0, 1), Date.UTC(2026, 3, 1) - 1)).toBe(2)
  })

  it('到期：分钟线一天、小时线一周、日线一个月', () => {
    expect(horizonMs('15m')).toBe(864e5)
    expect(horizonMs('4h')).toBe(7 * 864e5)
    expect(horizonMs('1d')).toBe(30 * 864e5)
  })
})

describe('记一笔 · 取景', () => {
  it('取视野里已收盘的那几根：没收盘的最后一根不算，参考价是最后一根已收盘的收盘价', () => {
    const bars = hourly(50)
    const now = bars[49].t + 10 * 60e3 // 最后一根还没收
    const c = captureRange('BTCUSDT', '1h', bars, 20, 49, now)!
    expect(c.range).toMatchObject({ symbol: 'BTCUSDT', interval: '1h', start: bars[20].t, end: bars[49].t, bars: 29 })
    expect(c.reference).toBe(148)
    expect(c.high).toBe(150); expect(c.low).toBe(118)
  })

  it('视野不到 3 根往左补齐到 3 根', () => {
    const bars = hourly(10)
    const c = captureRange('BTCUSDT', '1h', bars, 8, 9, bars[9].t + H)!
    expect(c.range.bars).toBe(3)
    expect(c.range.start).toBe(bars[7].t)
  })

  it('超过 1500 根从左边砍，保留最近的', () => {
    const bars = hourly(1600)
    const c = captureRange('BTCUSDT', '1h', bars, 0, 1599, bars[1599].t + H)!
    expect(c.range.bars).toBe(1500)
    expect(c.range.end).toBe(bars[1599].t + H)
  })

  it('非 USDT 品种不上传（返回 null，只能记本机）', () => {
    expect(captureRange('BTCUSDC', '1h', hourly(10), 0, 9, Date.now())).toBeNull()
  })

  it('网页独有周期按原生周期对齐：7 分线记成 1 分线', () => {
    const t0 = Date.UTC(2026, 8, 1)
    const bars = Array.from({ length: 10 }, (_, i) => ({ t: t0 + i * 7 * 60e3, h: 2, l: 1, c: 1.5 }))
    const c = captureRange('ETHUSDT', '7m', bars, 0, 9, t0 + 70 * 60e3)!
    expect(c.range.interval).toBe('1m')
    expect(c.range.bars).toBe(70)
  })
})

describe('记一笔 · 草稿', () => {
  const cap: Capture = { range: { venue: 'binance', market: 'usd_m', symbol: 'BTCUSDT', interval: '1h', start: 0, end: 10 * H, bars: 10 }, reference: 100, high: 120, low: 90 }
  const base = { id: 'n1', capture: cap, confirmation: 'bar_close' as const, targetEdited: false, invalidationEdited: false, text: '  回踩不破  ', origin: 'chart_first' as const, created: 1000 }

  it('按方向把目标 / 失效摆到参考价两侧（区间太窄时至少 ±1%）', () => {
    expect(sideLevels('long', 100, 120, 90)).toEqual({ target: 120, invalidation: 90 })
    expect(sideLevels('short', 100, 120, 90)).toEqual({ target: 90, invalidation: 120 })
    expect(sideLevels('long', 100, 100.2, 99.9)).toEqual({ target: 101, invalidation: 99 })
  })

  it('键一个不多一个不少（服务端 deny_unknown_fields），文字去首尾空白，把握为 null', () => {
    const d = buildDraft({ ...base, direction: 'long', target: 120, invalidation: 90 })
    expect(Object.keys(d).sort()).toEqual(['confidence', 'created', 'id', 'origin', 'range', 'rule', 'text'])
    expect(Object.keys(d.rule).sort()).toEqual(['confirmation', 'direction', 'expires', 'invalidation', 'invalidationEdited', 'reference', 'target', 'targetEdited', 'version', 'expiryEdited'].sort())
    expect(d.text).toBe('回踩不破')
    expect(d.confidence).toBeNull()
    expect(d.rule.expires).toBe(1000 + 7 * 864e5)
    expect(checkDraft(d)).toBeNull()
  })

  it('只记录：目标 / 失效取区间高低，确认方式固定收盘确认', () => {
    const d = buildDraft({ ...base, direction: 'observe', confirmation: 'trade_touch', target: 1, invalidation: 1, targetEdited: true })
    expect(d.rule).toMatchObject({ target: 120, invalidation: 90, confirmation: 'bar_close', targetEdited: false })
    expect(checkDraft(d)).toBeNull()
  })

  it('本地先挡住服务端会拒的：看多目标低于参考价、价格非正', () => {
    expect(checkDraft(buildDraft({ ...base, direction: 'long', target: 95, invalidation: 90 }))).toMatch(/看多/)
    expect(checkDraft(buildDraft({ ...base, direction: 'short', target: 110, invalidation: 120 }))).toMatch(/看空/)
    expect(checkDraft(buildDraft({ ...base, direction: 'long', target: 120, invalidation: 0 }))).toMatch(/正数/)
  })
})

describe('找相似 · 没找到时的说明', () => {
  it('说清楚比过几段、门槛是 0.60', () => {
    expect(noMatchText({ status: { checked: 300 } as never })).toBe('比过 300 段，没有一段相似度到 0.60 · 换 15 分钟或拉长区间再试')
    expect(noMatchText({ status: null })).toBe('没有找到足够像的片段')
  })
})
