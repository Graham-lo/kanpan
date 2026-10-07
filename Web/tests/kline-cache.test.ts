import { describe, expect, it } from 'vitest'
import { KlineCache, CACHE_TTL_MS } from '../src/market/klineCache'
import { TAIL_MAX } from '../src/market/tail'
import type { Bar } from '../src/chart/calc'

const M = 60_000
const bar = (t: number, c: number): Bar => ({ t, o: c, h: c, l: c, c, v: 1 } as Bar)
const run = (t0: number, n: number, c = 100): Bar[] => Array.from({ length: n }, (_, i) => bar(t0 + i * M, c + i))

describe('最近取过的 K 线（换布局集只补尾巴）', () => {
  it('刚取过：要补几根 = 从缓存最后一根到现在 + 两根余量', () => {
    const k = new KlineCache()
    const t0 = 1_000 * M
    k.put('BTCUSDT|1m', run(t0, 1500), t0 + 1500 * M)
    expect(k.need('BTCUSDT|1m', M, t0 + 1503 * M)).toBe(6)
    expect(k.need('ETHUSDT|1m', M, t0)).toBeNull()
  })

  it('尾巴并进去：同一根盖掉、新的接上，长度不涨、旧的从前面滚掉，拿到的是拷贝', () => {
    const k = new KlineCache()
    const t0 = 1_000 * M, base = run(t0, 1500)
    k.put('X|1m', base, t0)
    base[1499].c = -1 // 外面改原数组不影响缓存
    const last = t0 + 1499 * M
    const out = k.merge('X|1m', [bar(last, 7), bar(last + M, 8), bar(last + 2 * M, 9)], t0 + M)!
    expect(out).toHaveLength(1500)
    expect(out[out.length - 1]).toMatchObject({ t: last + 2 * M, c: 9 })
    expect(out[out.length - 3]).toMatchObject({ t: last, c: 7 })
    expect(out[0].t).toBe(t0 + 2 * M)
    for (let i = 1; i < out.length; i++) expect(out[i].t - out[i - 1].t).toBe(M)
    out[0].c = -5
    expect(k.merge('X|1m', [bar(last + 2 * M, 10)], t0 + 2 * M)![0].c).not.toBe(-5)
  })

  it('尾巴接不上（断档）、过期、断得太久：整段重取', () => {
    const k = new KlineCache()
    const t0 = 1_000 * M
    k.put('A|1m', run(t0, 10), t0)
    expect(k.merge('A|1m', [bar(t0 + 20 * M, 1)], t0)).toBeNull()
    expect(k.need('A|1m', M, t0)).toBeNull() // 接不上的那份已丢
    k.put('B|1m', run(t0, 10), t0)
    expect(k.need('B|1m', M, t0 + CACHE_TTL_MS + 1)).toBeNull()
    k.put('C|1m', run(t0, 10), t0)
    expect(k.need('C|1m', M, t0 + (TAIL_MAX + 20) * M)).toBeNull()
  })

  it('有上限：超了丢最久没用的', () => {
    const k = new KlineCache(2)
    k.put('a', run(0, 3), 0); k.put('b', run(0, 3), 0); k.put('c', run(0, 3), 0)
    expect(k.size).toBe(2)
    expect(k.need('a', M, 3 * M)).toBeNull()
    expect(k.need('c', M, 3 * M)).not.toBeNull()
  })
})
