import { describe, it, expect } from 'vitest'
import { AN, BT, fill } from '../src/terms'
import termsJson from '../../KanpanCore/Sources/KanpanCore/Terms/terms.json'

describe('三端共用词表 terms.json', () => {
  it('模板填空', () => {
    expect(fill(BT.buyCount, { n: 12 })).toBe('买 12 笔')
    expect(fill(BT.hours, { h: 2 })).toBe('2 小时')
    expect(BT.shortLiq).toBe('空单爆仓')
  })
  it('「分析」组与组清单', () => {
    expect(AN.fvg).toBe('公允价值缺口')
    expect(Object.keys(AN)).toEqual(['fvg'])
    expect(Object.keys(termsJson).sort()).toEqual(['analysis', 'bigTrade', 'highlights'])
  })
  it('不出现口语化、含糊的说法', () => {
    const banned = ['空爆', '多爆', '被打', '被平', '还在走', '稳着', '该根', '这根', '这只品种', '第一次打开', '一笔']
    for (const [k, v] of Object.entries(BT)) for (const b of banned) expect(v.includes(b), `${k}「${v}」含「${b}」`).toBe(false)
  })
})
