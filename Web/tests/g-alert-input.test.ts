/* 创建提醒的输入（G 线走查）：电脑网页与手机网页同一份解析，照 iOS AlertForm——
 * 以前电脑网页用 +input.value：「85,000」「85，000」「0。5」被拒；资金费率框清空时 +'' = 0 当成 0% 建了提醒 */
import { describe, it, expect } from 'vitest'
import { parsePercent, parseTarget } from '../src/alerts/shape'
import { parseTarget as mParseTarget } from '../src/m/model/formText'

describe('价格输入', () => {
  it('千分位、全角逗号、空白、全角句点都认；不是正数给 null', () => {
    expect(parseTarget('85,000')).toBe(85000)
    expect(parseTarget('85，000.5')).toBe(85000.5)
    expect(parseTarget(' 0。5 ')).toBe(0.5)
    expect(parseTarget('0．25')).toBe(0.25)
    for (const bad of ['', '.', 'abc', '-1', '0', '1e3', '1.2.3']) expect(parseTarget(bad)).toBeNull()
  })
  it('手机网页用的就是这一份', () => { expect(mParseTarget).toBe(parseTarget) })
})

describe('百分数输入（资金费率 / 持仓量变化）', () => {
  it('认负号（含全角）、末尾 %、全角句点；空的不当 0', () => {
    expect(parsePercent('0.05')).toBe(0.05)
    expect(parsePercent('0.05%')).toBe(0.05)
    expect(parsePercent('−0.01')).toBe(-0.01)
    expect(parsePercent('－0。01％')).toBe(-0.01)
    expect(parsePercent('25')).toBe(25)
    for (const bad of ['', ' ', '-', '%', 'abc', '1e3', '--1']) expect(parsePercent(bad)).toBeNull()
  })
})
