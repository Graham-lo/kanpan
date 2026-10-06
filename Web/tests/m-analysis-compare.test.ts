// 手机网页「分析」面板恢复「对比」一节（2026-10-06 用户：「分析里的对比要留」，照 iOS IndicatorPage.compareSection）：
// 与顶栏「对比＋」并存，「添加对比」开的是同一张对比模式搜索页、共用同一份 compareSymbols；
// 此刻不能对比（复盘回放、横屏画线台、看朋友分享的线）时整节不排。
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { st } from '../src/m/app/store'
import { analysisHTML, compareName, compareSectionHTML, type PanelContext } from '../src/m/pages/chart/panels'
import panelSource from '../src/m/pages/chart/panels.ts?raw'
import chartSource from '../src/m/pages/chart.ts?raw'

const ctx = (o: Partial<PanelContext> = {}): PanelContext => ({
  symbol: () => 'BTCUSDT', port: () => null, onDraw: () => {}, onAddCompare: () => {}, canCompare: () => true, ...o,
})
const titles = (html: string): string[] => [...html.matchAll(/<div class="cp-gt">([^<]*)<\/div>/g)].map(m => m[1])

beforeEach(() => { st.compareSymbols = [] })

describe('分析面板四节：画线 · 指标 · 对比 · 主力订单流', () => {
  it('对比一节排在指标之后、主力订单流之前', () => {
    const t = titles(analysisHTML(ctx()))
    expect(t[0]).toBe('画线')
    const i = t.indexOf('对比')
    expect(i).toBeGreaterThan(0)
    expect(t[i - 1]).toMatch(/^副图/)
    expect(t[i + 1]).toBe('主力订单流')
  })
  it('此刻不能对比（复盘回放 / 横屏画线台 / 看朋友的线）：整节不排，面板回到三节', () => {
    expect(titles(analysisHTML(ctx({ canCompare: () => false })))).not.toContain('对比')
    expect(compareSectionHTML(ctx({ onAddCompare: undefined }))).toBe('')
  })
})

describe('对比一节的行', () => {
  it('没有对比：只有「添加对比」，没有「清除对比」', () => {
    const h = compareSectionHTML(ctx())
    expect(h).toContain('data-act="cmp-add"')
    expect(h).not.toContain('disabled')
    expect(h).not.toContain('cmp-clear')
  })
  it('每只一行带「移除」，有对比时「清除对比」；美元指数写 DXY', () => {
    st.compareSymbols = ['binance/usd_m/ETHUSDT', 'macro/index/DXY']
    const h = compareSectionHTML(ctx())
    expect(h).toContain('>ETH/USDT<')
    expect(h).toContain('>DXY<')
    expect(h).toContain('data-act="cmp-rm:binance/usd_m/ETHUSDT"')
    expect(h).toContain('data-act="cmp-rm:macro/index/DXY"')
    expect(h).toContain('data-act="cmp-clear"')
    expect(compareName('binance/usd_m/SOLUSDT')).toBe('SOL/USDT')
  })
  it('满三只：「添加对比」置灰', () => {
    st.compareSymbols = ['binance/usd_m/ETHUSDT', 'binance/usd_m/SOLUSDT', 'macro/index/DXY']
    expect(compareSectionHTML(ctx())).toMatch(/data-act="cmp-add" disabled/)
  })
})

describe('从分析面板添加对比：开顶栏 ＋ 那张对比模式搜索页', () => {
  it('cmp-add 先收面板再调 onAddCompare（不再开旧的单选小表）', () => {
    expect(panelSource).toMatch(/case 'cmp-add': sheet\.close\(\); ctx\.onAddCompare\?\.\(\)/)
    expect(panelSource).not.toContain('openComparePicker')
  })
  it('行情页把 onAddCompare 接到与顶栏 ＋ 同一个 openSearch({ compare })，并按回放 / 横屏 / 预览判能不能对比', () => {
    expect(chartSource).toContain("onCompare: panel(() => openSearch({ compare: { current: sym() } }))")
    expect(chartSource).toContain("onAddCompare: () => openSearch({ compare: { current: sym() } })")
    expect(chartSource).toMatch(/canCompare: \(\) => !replay && !isLand\(\) && !bench\.active && !preview\?\.previewing\(\)/)
  })
  it('onAddCompare 真被调到', () => {
    const fn = vi.fn()
    const h = compareSectionHTML(ctx({ onAddCompare: fn }))
    expect(h).toContain('cmp-add')
    ctx({ onAddCompare: fn }).onAddCompare!()
    expect(fn).toHaveBeenCalledOnce()
  })
})
