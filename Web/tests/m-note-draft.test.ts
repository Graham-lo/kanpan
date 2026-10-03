/* 手机网页版 · 记一笔没记完的那一笔（src/m/model/noteDraft.ts）。口径照 iOS ReviewDraft.reusable / ReviewStore.saveDraft。 */
import { describe, expect, it } from 'vitest'
import { parseUnfinished, meaningful, reusableFor, nextStored, type UnfinishedNote } from '../src/m/model/noteDraft'

const base: UnfinishedNote = {
  symbol: 'BTCUSDT', interval: '1h', direction: 'observe', confirmation: 'bar_close', origin: 'chart_first',
  text: '', target: '', invalidation: '', targetEdited: false, invalidationEdited: false, updated: 1,
}
const v = (p: Partial<UnfinishedNote> = {}): UnfinishedNote => ({ ...base, ...p })

describe('手机网页版 · 没记完的记一笔', () => {
  it('好的认下来；形状坏的一律当没有', () => {
    expect(parseUnfinished(JSON.parse(JSON.stringify(v({ direction: 'long', text: '突破回踩' }))))?.text).toBe('突破回踩')
    expect(parseUnfinished(null)).toBeNull()
    expect(parseUnfinished('x')).toBeNull()
    expect(parseUnfinished({ ...v(), symbol: 'btc/usdt' })).toBeNull()
    expect(parseUnfinished({ ...v(), direction: 'up' })).toBeNull()
    expect(parseUnfinished({ ...v(), confirmation: 'x' })).toBeNull()
    expect(parseUnfinished({ ...v(), origin: 'toString' })).toBeNull()
    expect(parseUnfinished({ ...v(), target: '1e9' })).toBeNull()
    expect(parseUnfinished({ ...v(), text: 3 })).toBeNull()
    expect(parseUnfinished({ ...v(), interval: '' })).toBeNull()
  })
  it('缺的布尔与时刻按默认补', () => {
    const { targetEdited: _a, updated: _b, ...rest } = v()
    const got = parseUnfinished(rest)
    expect(got?.targetEdited).toBe(false)
    expect(got?.updated).toBe(0)
  })
  it('动过东西才算没记完', () => {
    expect(meaningful(v())).toBe(false)
    expect(meaningful(v({ text: '   ' }))).toBe(false)
    expect(meaningful(v({ text: '等回踩' }))).toBe(true)
    expect(meaningful(v({ direction: 'short' }))).toBe(true)
    expect(meaningful(v({ confirmation: 'trade_touch' }))).toBe(true)
    expect(meaningful(v({ origin: 'unknown' }))).toBe(true)
    expect(meaningful(v({ targetEdited: true, target: '100' }))).toBe(true)
  })
  it('只接在同品种同周期上', () => {
    expect(reusableFor(v(), 'BTCUSDT', '1h')).toBe(true)
    expect(reusableFor(v(), 'btcusdt', '1h')).toBe(true)
    expect(reusableFor(v(), 'BTCUSDT', '4h')).toBe(false)
    expect(reusableFor(v(), 'ETHUSDT', '1h')).toBe(false)
    expect(reusableFor(null, 'BTCUSDT', '1h')).toBe(false)
  })
  it('存 / 清 / 别碰', () => {
    expect(nextStored(null, v({ text: 'a' }))).toBe('save')
    expect(nextStored(v({ symbol: 'ETHUSDT', text: 'b' }), v({ text: 'a' }))).toBe('save')
    // 人把这一笔擦回默认：清掉
    expect(nextStored(v({ text: 'a' }), v())).toBe('clear')
    // 在别的品种上还没开始写：不能把那边没写完的冲掉
    expect(nextStored(v({ symbol: 'ETHUSDT', text: 'b' }), v())).toBe('keep')
    expect(nextStored(null, v())).toBe('keep')
  })
})
