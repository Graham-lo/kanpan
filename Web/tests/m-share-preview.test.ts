/* 手机网页版 · 行情页看朋友的线（src/m/model/sharePreview.ts）。口径照 iOS MainScreen.shareAndAlertCard / ShareCard /
 * AlertPromptModel.offerBatch / ShareItem.preferred。 */
import { describe, expect, it } from 'vitest'
import {
  ALERT_LIMIT, batchRoom, cardSubtitle, cardTitle, headerCard, isDismissSwipe, offerBatch, preferredCopies,
} from '../src/m/model/sharePreview'

describe('手机网页版 · 头部那一格摆什么', () => {
  const s = (p: Partial<{ prompt: boolean; previewing: boolean; replying: boolean; unseen: number }> = {}) =>
    headerCard({ prompt: false, previewing: false, replying: false, unseen: 0, ...p })
  it('先后：问提醒 > 正在看 > 没看过的信 > 回信条', () => {
    expect(s()).toBeNull()
    expect(s({ unseen: 2 })).toBe('unseen')
    expect(s({ replying: true })).toBe('reply')
    expect(s({ previewing: true, unseen: 3 })).toBe('preview')
    expect(s({ prompt: true, previewing: true, unseen: 3, replying: true })).toBe('prompt')
  })
  it('回信进行中时不摆没看过的信，摆回信条', () => {
    expect(s({ replying: true, unseen: 5 })).toBe('reply')
  })
})

describe('手机网页版 · 卡上的字', () => {
  it('标题', () => {
    expect(cardTitle('alice', true, false)).toBe('正在看 alice 的线')
    expect(cardTitle('alice', true, true)).toBe('正在看 alice 的线')
    expect(cardTitle('alice', false, true)).toBe('alice 回了你')
    expect(cardTitle('alice', false, false)).toBe('alice')
  })
  it('副标题：还有几封没看过的才带 +N', () => {
    expect(cardSubtitle('BTC', 3, 0)).toBe('BTC · 3 条线')
    expect(cardSubtitle('ETH', 1, 2)).toBe('ETH · 1 条线  +2')
  })
})

describe('手机网页版 · 收下后发信人设了提醒的是哪几条', () => {
  it('按下标对应原线与新线；原线解不开的那一位跳过', () => {
    const originals = [{ id: 'a' }, null, { id: 'c' }, { id: 'd' }]
    const copies = [{ id: 'A' }, null, { id: 'C' }, { id: 'D' }]
    expect([...preferredCopies(originals, copies, ['a', 'd', 'zz'])].sort()).toEqual(['A', 'D'])
    expect(preferredCopies(originals, copies, []).size).toBe(0)
  })
})

describe('手机网页版 · 顺便建提醒', () => {
  type L = { id: string; ok: boolean }
  const lines: L[] = [{ id: '1', ok: true }, { id: '2', ok: false }, { id: '3', ok: true }, { id: '4', ok: true }]
  const supported = (d: L) => d.ok
  it('发信人设过的优先，只问那几条', () => {
    const o = offerBatch(lines, supported, new Set(['3', '2']), 'bob')
    expect(o?.sentence).toBe('bob 在其中 1 条上设了提醒，也给你设上？')
    expect(o?.batch.map(d => d.id)).toEqual(['3'])
  })
  it('一条都没设过就问整组能挂提醒的', () => {
    const o = offerBatch(lines, supported, new Set(), 'bob')
    expect(o?.sentence).toBe('要在这 3 条线上提醒你吗？')
    expect(o?.batch.map(d => d.id)).toEqual(['1', '3', '4'])
  })
  it('一条都挂不了提醒就不问', () => {
    expect(offerBatch(lines, () => false, new Set(['1']), 'bob')).toBeNull()
    expect(offerBatch([], supported, new Set(), 'bob')).toBeNull()
  })
  it('提醒上限 200：满了一条都不加，差几条加几条', () => {
    expect(ALERT_LIMIT).toBe(200)
    expect(batchRoom(0, 3)).toBe(3)
    expect(batchRoom(198, 3)).toBe(2)
    expect(batchRoom(200, 3)).toBe(0)
    expect(batchRoom(250, 3)).toBe(0)
  })
})

describe('手机网页版 · 划掉没看过的信', () => {
  it('横向超过 44 且明显比竖向大才算', () => {
    expect(isDismissSwipe(60, 10)).toBe(true)
    expect(isDismissSwipe(-60, 10)).toBe(true)
    expect(isDismissSwipe(40, 0)).toBe(false)
    expect(isDismissSwipe(60, 50)).toBe(false)
  })
})
