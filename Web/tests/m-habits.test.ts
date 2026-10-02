/* 手机网页版 · 个性化学习（m/model/habits.ts，照 iOS HabitLogTests / HabitInferenceTests / LearnedDefaultsTests） */
import { describe, expect, it } from 'vitest'
import {
  H, appendLog, learn, learnIntervals, learnPriceAxis, learnSectorWindow, learnWatchMove, learnedGroups, learnedCount,
  mergedLearned, moveStep, prunedLearned, pruneLog, readLog, habitName, type HabitEvent,
} from '../src/m/model/habits'
import { emptyLearned } from '../src/m/app/prefs'

const NOW = 2_000_000_000
const ev = (t: number, kind: HabitEvent['kind'], key: string, value?: string, w?: number): HabitEvent => ({ t, kind, key, value, w })
const base = (s: string): string => s.replace(/USDT$/, '')

describe('日志', () => {
  it('停留同一只同一值一小时内并成一条', () => {
    const log: HabitEvent[] = []
    appendLog(log, ev(NOW - 100, 'interval', 'k', '1h', 60), NOW)
    appendLog(log, ev(NOW - 50, 'interval', 'k', '1h', 30), NOW)
    expect(log).toEqual([{ t: NOW - 50, kind: 'interval', key: 'k', value: '1h', w: 90 }])
    appendLog(log, ev(NOW - 40, 'interval', 'k', '4h', 10), NOW)
    expect(log.length).toBe(2)
  })
  it('超过一小时不并；别的种类不并', () => {
    const log: HabitEvent[] = []
    appendLog(log, ev(NOW - 4000, 'interval', 'k', '1h', 60), NOW)
    appendLog(log, ev(NOW - 10, 'interval', 'k', '1h', 60), NOW)
    appendLog(log, ev(NOW - 5, 'sectorWindow', 'crypto', 'd5'), NOW)
    appendLog(log, ev(NOW - 4, 'sectorWindow', 'crypto', 'd5'), NOW)
    expect(log.length).toBe(4)
    expect(log[2].w).toBeUndefined()
  })
  it('时钟往回拨的插到该在的位置', () => {
    const log: HabitEvent[] = []
    appendLog(log, ev(NOW - 10, 'moveFired', 'a'), NOW)
    appendLog(log, ev(NOW - 30, 'moveFired', 'b'), NOW)
    expect(log.map(e => e.key)).toEqual(['b', 'a'])
  })
  it('30 天前的丢、超容量丢最旧的', () => {
    const log = [ev(NOW - H.retention - 1, 'moveFired', 'old'), ev(NOW, 'moveFired', 'new')]
    pruneLog(log, NOW)
    expect(log.map(e => e.key)).toEqual(['new'])
    const big = Array.from({ length: H.capacity + 5 }, (_, i) => ev(NOW - H.capacity + i, 'moveFired', String(i)))
    pruneLog(big, NOW)
    expect(big.length).toBe(H.capacity)
    expect(big[0].key).toBe('5')
  })
  it('读盘丢掉形状不对的并排序', () => {
    expect(readLog([{ t: 2, kind: 'interval', key: 'a', value: '1h', w: 7 }, { t: 1, kind: 'nope', key: 'b' }, null, { t: 1, kind: 'moveFired', key: 'c', w: 1 }]))
      .toEqual([{ t: 1, kind: 'moveFired', key: 'c' }, { t: 2, kind: 'interval', key: 'a', value: '1h', w: 7 }])
    expect(readLog('x')).toEqual([])
  })
})

describe('推断', () => {
  it('周期：不到 120 秒不算，多的胜；打平取字面小的', () => {
    expect(learnIntervals([ev(NOW, 'interval', 'k', '1h', 100)], NOW)).toEqual({})
    expect(learnIntervals([ev(NOW, 'interval', 'k', '1h', 100), ev(NOW - 5, 'interval', 'k', '4h', 300)], NOW).k)
      .toEqual({ v: '4h', n: 1, at: NOW })
    expect(learnIntervals([ev(NOW, 'interval', 'k', '4h', 200), ev(NOW, 'interval', 'k', '1h', 200)], NOW).k.v).toBe('1h')
  })
  it('周期：一周前的权重减半', () => {
    const r = learnIntervals([ev(NOW - H.halfLife, 'interval', 'k', '1h', 300), ev(NOW, 'interval', 'k', '4h', 200)], NOW)
    expect(r.k.v).toBe('4h')
  })
  it('价格轴：亲手切一次压过之前全部停留', () => {
    const r = learnPriceAxis([ev(NOW - 10, 'axisDwell', 'crypto', 'linear', 1800), ev(NOW, 'axisPick', 'crypto', 'log')], NOW)
    expect(r.crypto.v).toBe('log')
    // 亲手切的即使只一次、权重不到门槛也算学到
    expect(learnPriceAxis([ev(NOW, 'axisPick', 'metal', 'linear')], NOW).metal.v).toBe('linear')
    expect(learnPriceAxis([ev(NOW, 'axisDwell', 'metal', 'linear', 60)], NOW)).toEqual({})
  })
  it('板块：最近 10 次里多的；不到 3 次或打平不算', () => {
    expect(learnSectorWindow([ev(1, 'sectorWindow', 'us', 'd5'), ev(2, 'sectorWindow', 'us', 'd5')])).toEqual({})
    expect(learnSectorWindow([ev(1, 'sectorWindow', 'us', 'd5'), ev(2, 'sectorWindow', 'us', 'today'), ev(3, 'sectorWindow', 'us', 'd5'), ev(4, 'sectorWindow', 'us', 'today')])).toEqual({})
    expect(learnSectorWindow([ev(1, 'sectorWindow', 'us', 'd5'), ev(2, 'sectorWindow', 'us', 'today'), ev(3, 'sectorWindow', 'us', 'd5')]).us)
      .toEqual({ v: 'd5', n: 2, at: 3 })
  })
  it('波动提醒：点开降一档，连续两次没点开升一档', () => {
    expect(moveStep([])).toBe(H.factorStart)
    expect(moveStep(['opened'])).toBe(H.factorStart - 1)
    expect(moveStep(['ignored'])).toBe(H.factorStart)
    expect(moveStep(['ignored', 'ignored'])).toBe(H.factorStart + 1)
    expect(moveStep(['ignored', 'opened', 'ignored'])).toBe(H.factorStart - 1)
    expect(moveStep(new Array(20).fill('opened'))).toBe(0)
  })
  it('波动提醒：没满 15 分钟的那一响不算', () => {
    const r = learnWatchMove([ev(NOW - 2000, 'moveFired', 's'), ev(NOW - 1000, 'moveFired', 's'), ev(NOW - 100, 'moveFired', 's')], NOW)
    expect(r.s).toEqual({ v: H.factorLadder[H.factorStart + 1], n: 2, at: NOW - 1000 })
    const opened = learnWatchMove([ev(NOW - 100, 'moveFired', 's'), ev(NOW - 50, 'moveOpened', 's')], NOW)
    expect(opened.s.v).toBe(H.factorLadder[H.factorStart - 1])
  })
  it('整份', () => {
    const l = learn([ev(NOW, 'interval', 'k', '1h', 200), ev(NOW - H.retention - 5, 'interval', 'old', '1h', 900)], NOW)
    expect(Object.keys(l.intervals)).toEqual(['k'])
  })
})

describe('结论整理', () => {
  it('同一个键 at 新的胜，一样新用本机的；只在一边的照留', () => {
    const synced = { ...emptyLearned(), intervals: { a: { v: '1h', n: 1, at: NOW - 5 }, b: { v: '1d', n: 1, at: NOW } } }
    const local = { ...emptyLearned(), intervals: { a: { v: '4h', n: 2, at: NOW }, b: { v: '1w', n: 2, at: NOW } } }
    const m = mergedLearned(synced, local, NOW)
    expect(m.intervals.a.v).toBe('4h')
    expect(m.intervals.b.v).toBe('1w')
  })
  it('30 天前的丢；按品种的表留最新 80 只', () => {
    const intervals: Record<string, { v: string; n: number; at: number }> = {}
    for (let i = 0; i < 90; i++) intervals['s' + i] = { v: '1h', n: 1, at: NOW - i }
    const p = prunedLearned({ ...emptyLearned(), intervals, priceAxis: { crypto: { v: 'log', n: 1, at: NOW - H.retention - 1 } } }, NOW)
    expect(Object.keys(p.intervals).length).toBe(H.maxSymbols)
    expect(p.intervals.s89).toBeUndefined()
    expect(p.priceAxis).toEqual({})
  })
  it('「已学到的」分组、名字与值', () => {
    const l = {
      intervals: { 'binance/usd_m/BTCUSDT': { v: '4h', n: 3, at: 5 }, 'coinbase/spot/ETH-USD': { v: '1d', n: 1, at: 9 } },
      priceAxis: { equity: { v: 'linear', n: 2, at: 1 }, crypto: { v: 'log', n: 4, at: 1 } },
      sectorWindow: { us: { v: 'd5', n: 3, at: 1 } },
      watchMove: { 'binance/usd_m/SOLUSDT': { v: 1.25, n: 4, at: 1 }, 'binance/usd_m/XRPUSDT': { v: 1, n: 2, at: 2 } },
    }
    const g = learnedGroups(l, base)
    expect(g.map(x => x.title)).toEqual(['周期', '价格轴', '板块', '波动提醒'])
    expect(g[0].rows.map(r => [r.name, r.value])).toEqual([['ETH/USD', '1日'], ['BTC', '4时']])
    expect(g[1].rows.map(r => [r.name, r.value, r.count])).toEqual([['加密', '对数', 4], ['美股', '线性', 2]])
    expect(g[2].rows[0]).toMatchObject({ name: '美股', value: '5 日' })
    expect(g[3].rows.map(r => [r.name, r.value])).toEqual([['SOL', '更迟钝']])
    expect(learnedCount(l, base)).toBe(6)
    expect(learnedGroups(emptyLearned(), base)).toEqual([])
    expect(habitName('BTCUSDT', base)).toBe('BTC')
  })
})
