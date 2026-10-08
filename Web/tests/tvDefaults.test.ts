// 电脑网页指标显示照 TradingView 内置指标默认（2026-10-08 从 pine-facade STD 元信息逐个取的）：
// 线色、参考线（#787B86、[5, 6] 虚线、中线 50% 透明）、带间填充、MACD 四色柱、线宽 1 px。改这些要先去 TV 对过
import { describe, expect, it, vi } from 'vitest'

vi.mock('../src/market/rest', () => ({ klines: vi.fn(async () => ({ ok: false, bars: [] })) }))

const { CATALOG } = await import('../src/chart/calc')
const { TV_HLINE, subBandFills, subLevelLines } = await import('../src/chart/indicators')
const { LINE, TVChart } = await import('../src/chart/chart')

/** TV 对应指标的默认线色（按我们 series 的顺序）；KDJ、标准差、AC、大单、累计量差、持仓量 TV 没有同名内置，不在表里 */
const TV_COLORS: Record<string, string[]> = {
  ma: ['#F6C309', '#FB9800', '#FB6500', '#F60C0C'], // TV MA Ribbon 四色
  ema: ['#2962FF', '#FF6D00', '#43A047', '#E91E63'],
  boll: ['#2962FF', '#F23645', '#089981'], // 中轨 / 上轨 / 下轨
  macd: ['#2962FF', '#FF6D00'],
  rsi: ['#7E57C2'],
  vwap: ['#2962FF', '#4CAF50', '#4CAF50', '#808000', '#808000'],
  st: ['#4CAF50', '#F23645'],
  ichi: ['#2962FF', '#B71C1C', '#A5D6A7', '#EF9A9A', '#43A047'], // 转换 / 基准 / 先行 A / 先行 B / 迟行
  atr: ['#B71C1C'], obv: ['#2962FF'], stochrsi: ['#2962FF', '#FF6D00'], cci: ['#2962FF'], wr: ['#7E57C2'],
  wma: ['#2962FF'], hma: ['#2962FF'], dema: ['#43A047'], tema: ['#2962FF'], smma: ['#673AB7'], vwma: ['#2962FF'],
  lsma: ['#2962FF'], alma: ['#2962FF'], mcg: ['#2962FF'],
  kc: ['#2962FF', '#2962FF', '#2962FF'], dc: ['#FF6D00', '#2962FF', '#2962FF'], env: ['#FF6D00', '#2962FF', '#2962FF'],
  sar: ['#2962FF'], vstop: ['#009688', '#F44336'], alligator: ['#2962FF', '#E91E63', '#66BB6A'],
  fractals: ['#009688', '#F44336'], zigzag: ['#2962FF'], pivots: Array(7).fill('#FB8C00'),
  stoch: ['#2962FF', '#FF6D00'], dmi: ['#2962FF', '#FF6D00', '#F50057'], mfi: ['#7E57C2'], aroon: ['#FB8C00', '#2962FF'],
  cmf: ['#43A047'], chosc: ['#EC407A'], ao: ['#009688'], mom: ['#2962FF'], roc: ['#2962FF'], trix: ['#F44336'],
  dpo: ['#43A047'], uo: ['#F44336'], bbp: ['#089981'], efi: ['#F44336'], chop: ['#2962FF'], coppock: ['#2962FF'],
  cmo: ['#2962FF'], vortex: ['#2962FF', '#E91E63'], kst: ['#009688', '#F44336'], mass: ['#2962FF'], eom: ['#43A047'],
  pvt: ['#2962FF'], bop: ['#F23645'], hv: ['#2962FF'], fisher: ['#2962FF', '#FF6D00'], rvgi: ['#008000', '#FF0000'],
  rvi: ['#7E57C2'], klinger: ['#2962FF', '#43A047'], ad: ['#999915'], crsi: ['#2962FF'], tsi: ['#2962FF', '#E91E63'],
  smi: ['#2962FF', '#FF9800'], bbw: ['#2962FF'], bbpct: ['#2962FF'], nv: ['#2962FF'],
}

describe('TradingView 默认样式', () => {
  it('目录线色与 TV 内置指标默认一致', () => {
    for (const [id, cols] of Object.entries(TV_COLORS)) expect([id, CATALOG[id as keyof typeof CATALOG].colors]).toEqual([id, cols])
  })
  it('指标线宽 1 px', () => { expect(LINE.plot).toBe(1) })
  it('参考线：数值、#787B86、虚线；中线 50% 透明，威廉 −50 点线', () => {
    const lv = (id: string) => subLevelLines(id).map(l => [l.v, l.color, l.dash])
    const MID = 'rgba(120,123,134,0.5)'
    expect(lv('rsi')).toEqual([[70, TV_HLINE, 'dashed'], [50, MID, 'dashed'], [30, TV_HLINE, 'dashed']])
    expect(lv('macd')).toEqual([[0, MID, 'dashed']])
    expect(lv('stoch')).toEqual([[80, TV_HLINE, 'dashed'], [50, MID, 'dashed'], [20, TV_HLINE, 'dashed']])
    expect(lv('cci')).toEqual([[100, TV_HLINE, 'dashed'], [0, MID, 'dashed'], [-100, TV_HLINE, 'dashed']])
    expect(lv('wr')).toEqual([[-20, TV_HLINE, 'dashed'], [-50, TV_HLINE, 'dotted'], [-80, TV_HLINE, 'dashed']])
    expect(lv('chop').map(x => x[0])).toEqual([61.8, 50, 38.2])
    expect(lv('fisher').map(x => x[1])).toEqual(['#E91E63', TV_HLINE, '#E91E63', TV_HLINE, '#E91E63'])
    // TV 没有参考线的：动量、AO、终极振荡、涡旋、质量、简易波动、均势、相对活力、克林格、ATR、能量潮
    for (const id of ['mom', 'ao', 'uo', 'vortex', 'mass', 'eom', 'bop', 'rvgi', 'klinger', 'atr', 'obv', 'kdj']) expect([id, subLevelLines(id)]).toEqual([id, []])
  })
  it('带间填充：RSI 等紫 10%，随机等蓝 10%，%B 三段', () => {
    expect(subBandFills('rsi')).toEqual([{ a: 70, b: 30, color: 'rgba(126,87,194,0.1)' }])
    expect(subBandFills('wr')).toEqual([{ a: -20, b: -80, color: 'rgba(126,87,194,0.1)' }])
    expect(subBandFills('stoch')).toEqual([{ a: 80, b: 20, color: 'rgba(33,150,243,0.1)' }])
    expect(subBandFills('cci')).toEqual([{ a: 100, b: -100, color: 'rgba(33,150,243,0.1)' }])
    expect(subBandFills('bbpct')).toHaveLength(3)
    expect(subBandFills('macd')).toEqual([])
  })
  it('MACD 四色柱照 TV hColor 规则（绿涨红跌）', () => {
    const ch = Object.assign(Object.create(TVChart.prototype), { colors: { up: '#089981', down: '#F23645' } })
    expect(ch.hist4Colors()).toEqual(['#26A69A', '#B2DFDB', '#FF5252', '#FFCDD2'])
    expect(ch.histColor('hist4', 2, 1)).toBe('#26A69A')   // 零上变长
    expect(ch.histColor('hist4', 1, 2)).toBe('#B2DFDB')   // 零上变短
    expect(ch.histColor('hist4', -1, -2)).toBe('#FFCDD2') // 零下回升
    expect(ch.histColor('hist4', -2, -1)).toBe('#FF5252') // 零下变深
    expect(ch.histColor('histTrend', 2, 1)).toBe('#009688') // AO：比上一根高
    expect(ch.histColor('histTrend', 1, 2)).toBe('#F44336')
  })
})
