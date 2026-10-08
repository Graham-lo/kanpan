import { describe, it, expect } from 'vitest'
import { BT, fill } from '../src/terms'

describe('三端共用词表 terms.json', () => {
  it('模板填空', () => {
    expect(fill(BT.buyCount, { n: 12 })).toBe('买 12 笔')
    expect(fill(BT.hours, { h: 2 })).toBe('近 2 小时')
    expect(BT.shortLiq).toBe('空单爆仓')
  })
  it('不出现口语化、含糊的说法', () => {
    const banned = ['空爆', '多爆', '被打', '被平', '还在走', '稳着', '该根', '这根', '这只品种', '第一次打开', '一笔']
    for (const [k, v] of Object.entries(BT)) for (const b of banned) expect(v.includes(b), `${k}「${v}」含「${b}」`).toBe(false)
  })
})
