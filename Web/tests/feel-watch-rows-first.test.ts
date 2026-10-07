// 网页版体感优化（2026-10-07）：品种表还没到时自选先按本机代号摆出行，价格写「—」；没自选的品种表也不再整块「正在取行情…」
import { describe, expect, it } from 'vitest'
import { st } from '../src/app/store'
import { S } from '../src/market'
import { installWatch, widgetWatch } from '../src/watch/widget'
import { decOfBars } from '../src/pages/chart'

describe('自选：行先摆出来', () => {
  it('品种表还没到：按自选代号出行，徽标按代号猜、价格与涨跌幅写「—」', () => {
    installWatch({
      openSymbol() {}, renderPanel() {}, refreshStreams() {}, openSearch() {},
      current: () => 'BTCUSDT', activeIndex: () => 0, cellCount: () => 1, collapsed: () => false, collapseBtn: () => '',
    })
    S.symbols.clear()
    st.watchTab = 'crypto'
    st.watch.crypto = ['BTCUSDT', 'ETHUSDT', '1000PEPEUSDT']
    const html = widgetWatch()
    expect(html).toContain('id="wTbl"')
    expect(html).not.toContain('正在取行情')
    const rows = html.match(/<tr data-sym="([^"]+)"/g)!.map(x => x.slice(14, -1))
    expect(rows).toEqual(['BTCUSDT', 'ETHUSDT', '1000PEPEUSDT'])
    expect(html).toContain('<b>BTC</b>')
    expect(html).toContain('<b>PEPE</b>')        // 和品种表到了之后的展示代号一样，不会跳
    expect((html.match(/data-f="price">—</g) || []).length).toBe(3)
    expect(html).toMatch(/class="badge/)
  })
})

describe('品种表还没到时按 K 线猜价格精度', () => {
  it('取最近几根开高低收里最长的小数位，最多 8 位；没 K 线是 null', () => {
    expect(decOfBars([{ t: 0, o: 83844.3, h: 83850.1, l: 83800, c: 83844.3, v: 1 }])).toBe(1)
    expect(decOfBars([{ t: 0, o: 0.08936, h: 0.0894, l: 0.0893, c: 0.08936, v: 1 }])).toBe(5)
    expect(decOfBars([{ t: 0, o: 1e-7, h: 1.25e-7, l: 1e-7, c: 1e-7, v: 1 }])).toBe(8)
    expect(decOfBars([])).toBeNull()
    expect(decOfBars(undefined)).toBeNull()
  })
})
