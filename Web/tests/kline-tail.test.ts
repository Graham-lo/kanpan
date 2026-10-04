import { describe, it, expect } from 'vitest'
import { tailNeed, tailFrom, TailResync, TAIL_MAX, HIDDEN_RESYNC_MS } from '../src/market/tail'
import type { Bar } from '../src/chart/calc'

const M = 60_000
const bar = (t: number, c: number): Bar => ({ t, o: c, h: c, l: c, c, v: 1 } as Bar)

describe('断线 / 藏久了之后补 K 线尾巴', () => {
  it('要取的根数：从图上最后一根到现在，加两根余量；短断也至少重取两根（断线前那根要定稿）', () => {
    const t0 = 1_700_000_000_000 - (1_700_000_000_000 % M)
    expect(tailNeed(t0, M, t0 + 20_000)).toBe(3)
    expect(tailNeed(t0, M, t0 + 125_000)).toBe(5)          // 断了两分多钟：中间收线两根 + 当前一根
    expect(tailNeed(t0, M, t0 + 10 * 60 * M)).toBeGreaterThan(TAIL_MAX)   // 断十小时 1m：超上限，整段重取
    expect(tailNeed(t0, 0, t0 + M)).toBe(2)
    expect(tailNeed(NaN, M, t0)).toBe(2)
  })

  it('并进图的只要开盘时间 ≥ 图上最后一根的：断线前那根被定稿盖掉，缺的几根按时间接上，更早的不碰', () => {
    const chart = [bar(0, 1), bar(M, 2), bar(2 * M, 3)]          // 2M 那根断线时停在半截（收 3）
    const fresh = [bar(4 * M, 6), bar(M, 20), bar(2 * M, 4), bar(3 * M, 5)]
    const out = tailFrom(chart, fresh)
    expect(out.map(b => b.t)).toEqual([2 * M, 3 * M, 4 * M])
    expect(out[0].c).toBe(4)
    // 拷贝出去，不和取回来的那份共用对象（updateBar 会 Object.assign 到图上那根）
    expect(out[0]).not.toBe(fresh[2])
    expect(tailFrom([], fresh)).toEqual([])
  })

  it('按 updateBar 的口径逐根并：补完相邻两根都只差一个周期', () => {
    const chart = [bar(0, 1), bar(M, 2)]
    const updateBar = (b: Bar) => { const last = chart[chart.length - 1]; if (b.t === last.t) Object.assign(last, b); else if (b.t > last.t) chart.push(b) }
    // 重连后已经推来的当前根（4M）先攒着，补完尾巴再按顺序补上
    for (const b of tailFrom(chart, [bar(M, 2.5), bar(2 * M, 3), bar(3 * M, 4), bar(4 * M, 5)])) updateBar(b)
    updateBar(bar(4 * M, 5.5))
    expect(chart.map(b => b.t)).toEqual([0, M, 2 * M, 3 * M, 4 * M])
    expect(chart[1].c).toBe(2.5)
    expect(chart[4].c).toBe(5.5)
  })

  it('重连判定：第一次连上不补（各格正在取整段），掉线再连上才补；中间多次 connecting / closed 只补一次', () => {
    const g = new TailResync()
    expect(g.ws('connecting')).toBe(false)
    expect(g.ws('open')).toBe(false)
    expect(g.ws('open')).toBe(false)
    expect(g.ws('connecting')).toBe(false)
    expect(g.ws('closed')).toBe(false)
    expect(g.ws('connecting')).toBe(false)
    expect(g.ws('open')).toBe(true)
    expect(g.ws('open')).toBe(false)
    expect(g.ws('idle')).toBe(false)
    expect(g.ws('open')).toBe(true)
  })

  it('回前台判定：藏够 30 秒再回来才补，短暂切走不补；连发两次 hidden 按第一次算', () => {
    const g = new TailResync()
    expect(g.visibility(true, 0)).toBe(false)                     // 没藏过
    g.visibility(false, 1000)
    expect(g.visibility(true, 1000 + HIDDEN_RESYNC_MS - 1)).toBe(false)
    g.visibility(false, 10_000); g.visibility(false, 30_000)
    expect(g.visibility(true, 10_000 + HIDDEN_RESYNC_MS)).toBe(true)
    expect(g.visibility(true, 10_000 + 2 * HIDDEN_RESYNC_MS)).toBe(false)
  })
})
