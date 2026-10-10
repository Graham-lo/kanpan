// 手机网页「分析」面板 · 公允价值缺口那一行（照 iOS IndicatorPage 指标节：主图叠加之外单独一行，不进指标列表）
import { beforeEach, describe, expect, it } from 'vitest'
import { st, subscribe } from '../src/m/app/store'
import { analysisHTML, autoLayerGroupHTML, toggleAutoLayerPref, type PanelContext } from '../src/m/pages/chart/panels'
import { toggleAutoLayer } from '../src/m/pages/chart/logic'
import { AN } from '../src/terms'
import panelSource from '../src/m/pages/chart/panels.ts?raw'

const ctx = (): PanelContext => ({ symbol: () => 'BTCUSDT', port: () => null, onDraw: () => {}, onAddCompare: () => {}, canCompare: () => true })

beforeEach(() => { st.autoLayers = []; st.analysisUsage = {} })

describe('toggleAutoLayer', () => {
  it('开就追加、关就去掉，结果去重、只留白名单', () => {
    expect(toggleAutoLayer([], 'FVG')).toEqual(['FVG'])
    expect(toggleAutoLayer(['FVG'], 'FVG')).toEqual([])
    expect(toggleAutoLayer(['FVG', 'FVG', 'XX'], 'FVG')).toEqual([])
    expect(toggleAutoLayer(['XX'], 'FVG')).toEqual(['FVG'])
  })
})

describe('auto:FVG 动作', () => {
  it('拨开 / 拨关：改 st.autoLayers 并落盘（通知订阅者，同步与行情页都挂在这上面）', () => {
    let saved = 0
    const off = subscribe(() => { saved++ })
    toggleAutoLayerPref('FVG', true)
    expect(st.autoLayers).toEqual(['FVG'])
    expect(saved).toBe(1)
    expect(st.analysisUsage.indicators).toBe(1)
    toggleAutoLayerPref('FVG', true)
    expect(st.autoLayers).toEqual([])
    expect(saved).toBe(2)
    off()
  })
  it('横屏画线台那张不计用量；不认识的名字不动', () => {
    toggleAutoLayerPref('FVG', false)
    expect(st.autoLayers).toEqual(['FVG'])
    expect(st.analysisUsage.indicators).toBeUndefined()
    toggleAutoLayerPref('NOPE', true)
    expect(st.autoLayers).toEqual(['FVG'])
  })
  it('分析面板与横屏「主图指标」两处都接了这个动作', () => {
    expect(panelSource).toMatch(/case 'auto': toggleAutoLayerPref\(arg, true\)/)
    expect(panelSource).toMatch(/act === 'auto'\) toggleAutoLayerPref\(arg, false\)/)
  })
})

describe('面板那一行', () => {
  it('写「公允价值缺口」、开关跟着 st.autoLayers', () => {
    expect(AN.fvg).toBe('公允价值缺口')
    expect(autoLayerGroupHTML()).toContain(`>${AN.fvg}<`)
    expect(autoLayerGroupHTML()).toContain('data-act="auto:FVG"')
    expect(autoLayerGroupHTML()).toContain('aria-checked="false"')
    st.autoLayers = ['FVG']
    expect(autoLayerGroupHTML()).toContain('aria-checked="true"')
  })
  it('排在主图叠加之后、副图之前，不另起一节', () => {
    const h = analysisHTML(ctx())
    const ov = h.indexOf('主图叠加'), row = h.indexOf('data-act="auto:FVG"'), sub = h.indexOf('副图 · 最多三个')
    expect(ov).toBeGreaterThan(0)
    expect(row).toBeGreaterThan(ov)
    expect(sub).toBeGreaterThan(row)
    expect(h.split('data-act="auto:FVG"').length).toBe(2)
  })
})
