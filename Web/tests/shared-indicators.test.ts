import { describe, expect, it } from 'vitest'
import catalogJson from '../../KanpanCore/Sources/KanpanCore/Indicator/indicators.json'
import { CATALOG } from '../src/chart/calc'
import { SHARED_PC_IDS, sharedName } from '../src/chart/sharedIndicators'
import { ALL_INDICATOR_IDS, defaultParams, indicatorName } from '../src/m/indicator/ids'

// 指标名与出厂参数只有一份：KanpanCore/Sources/KanpanCore/Indicator/indicators.json（iOS 也读它，见 IndicatorCatalogTests）
const JSON_CATALOG = catalogJson as Record<string, { name: string; params: number[] }>

describe('三端共用的指标目录', () => {
  it('手机网页：每个指标都有一项，名字与参数照 JSON，没有多出来的键', () => {
    expect(new Set(Object.keys(JSON_CATALOG))).toEqual(new Set(ALL_INDICATOR_IDS))
    for (const id of ALL_INDICATOR_IDS) {
      expect(indicatorName(id)).toBe(JSON_CATALOG[id].name)
      expect(defaultParams(id)).toEqual(JSON_CATALOG[id].params)
    }
  })

  it('电脑网页：三端都有的那几只名字与 JSON 一样，参数按键表翻过来', () => {
    for (const id of SHARED_PC_IDS) expect(CATALOG[id].name).toBe(sharedName(id))
    expect(CATALOG.vwap.name).toBe('VWAP')
    expect(CATALOG.macd.params).toEqual({ fast: 10, slow: 30, signal: 9 })
    expect(CATALOG.rsi.params).toEqual({ n: 14 })
    expect(CATALOG.ma.params).toEqual({ periods: JSON_CATALOG.MA.params })
    expect(CATALOG.boll.params).toEqual({ n: 20, k: 2 })
    expect(CATALOG.kdj.params).toEqual({ n: 9, m1: 3, m2: 3 })
    expect(CATALOG.stochrsi.params).toEqual({ n: 14, stoch: 14, m1: 3, m2: 3 })
    expect(CATALOG.st.params).toEqual({ n: 10, k: 3 })
    expect(CATALOG.atr.params).toEqual({ n: 14 })
    // 电脑网页独有的 ADX 平滑留着，排在共用参数后面
    expect(CATALOG.dmi.params).toEqual({ n: 14, m1: 14 })
    expect(Object.keys(CATALOG.dmi.params!)).toEqual(['n', 'm1'])
    // 搜索别名还在
    expect(CATALOG.macd.cn).toBe('平滑异同')
    expect(CATALOG.vol.params).toBeUndefined()
  })
})
