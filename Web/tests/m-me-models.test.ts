/* 手机网页版 · 「我的」底下几块纯逻辑：收件箱（m/model/inbox.ts）、上新下架通知（listingNotices.ts）、恢复默认（prefsReset.ts） */
import { describe, expect, it } from 'vitest'
import {
  emptyCache, itemKey, letterTime, markLocal, mergePage, openableSymbol, plannedCopies, readCache, readItem, receiptIsDead, unseen, withFriend,
  pageHasMore, prunedCopies, RETENTION_MS, PER_SYMBOL_LIMIT, type ShareItem,
} from '../src/m/model/inbox'
import { LN, cursorKey, noticeSymbol, planNotices, readNotices, type ListingNotice } from '../src/m/model/listingNotices'
import { resetPrefs, restorePrefs } from '../src/m/model/prefsReset'
import { defaultPrefs } from '../src/m/app/prefs'

const NOW = Date.parse('2026-10-03T12:00:00Z')
const item = (id: string, createdAt: string, extra: Partial<ShareItem> = {}): ShareItem => ({
  id, from: 'amy', symbol: 'BTCUSDT', market: 'binance/usd_m', interval: '1h', view: { from: 1, to: 2 },
  drawings: [{ id: 'a' }], alerted: [], createdAt, openedAt: null, keptAt: null, replyTo: null, ...extra,
})

describe('收件箱', () => {
  it('读信：形状不对的丢掉；线进门裁到 50 条（丢头上的）', () => {
    expect(readItem({ id: 'x' })).toBeNull()
    const many = Array.from({ length: 60 }, (_, i) => ({ id: String(i) }))
    const r = readItem({ ...item('s1', '2026-10-01T00:00:00.123456Z'), drawings: many })!
    expect(r.drawings.length).toBe(PER_SYMBOL_LIMIT)
    expect((r.drawings[0] as { id: string }).id).toBe('10')
    expect(readCache({ items: [r, { bad: 1 }], friends: ['a', 3], pending: { s1: true, z: 'no' }, copies: { s1: ['n1'] } }))
      .toMatchObject({ friends: ['a'], pending: { s1: true }, copies: { s1: ['n1'] } })
    expect(readCache(null)).toEqual(emptyCache())
  })
  it('并页：有待发回执的不被服务端旧值盖；90 天前没留下的丢；新的在前', () => {
    const cache = { ...emptyCache(), items: [item('a', '2026-10-02T00:00:00Z', { openedAt: 'L' })], pending: { a: false } }
    const old = new Date(NOW - RETENTION_MS - 1000).toISOString()
    const merged = mergePage(cache, [item('a', '2026-10-02T00:00:00Z'), item('b', '2026-10-03T00:00:00Z'), item('c', old), item('d', old, { keptAt: 'K' })], NOW)
    expect(merged.map(i => i.id)).toEqual(['b', 'a', 'd'])
    expect(merged.find(i => i.id === 'a')!.openedAt).toBe('L')
    // 没有待发回执：服务端说了算
    const m2 = mergePage({ ...cache, pending: {} }, [item('a', '2026-10-02T00:00:00Z')], NOW)
    expect(m2[0].openedAt).toBeNull()
  })
  it('回执：哪些码永远不会收', () => {
    expect([400, 404, 410].every(receiptIsDead)).toBe(true)
    expect([0, 401, 403, 408, 429, 500, 503].some(receiptIsDead)).toBe(false)
  })
  it('已读 / 留下：本机先盖戳、记待发；留下压过已读', () => {
    let c = { ...emptyCache(), items: [item('a', '2026-10-02T00:00:00Z')] }
    c = markLocal(c, 'a', false, 'T1')
    expect(c.items[0].openedAt).toBe('T1')
    expect(c.pending.a).toBe(false)
    expect(unseen(c.items)).toEqual([])
    c = markLocal(c, 'a', true, 'T2')
    expect(c.items[0]).toMatchObject({ openedAt: 'T1', keptAt: 'T2' })
    expect(c.pending.a).toBe(true)
    c = markLocal(c, 'a', false, 'T3')
    expect(c.pending.a).toBe(true)
  })
  it('留下的新 id 只分一次', () => {
    let n = 0
    const it0 = item('a', '2026-10-02T00:00:00Z', { drawings: [{}, {}] })
    const p1 = plannedCopies(emptyCache(), it0, () => 'id' + n++)
    expect(p1.ids).toEqual(['id0', 'id1'])
    const p2 = plannedCopies(p1.cache, it0, () => 'id' + n++)
    expect(p2.ids).toEqual(['id0', 'id1'])
  })
  it('翻页：服务端说截断了（more）才接着拉；老服务端没这一位就停在这一页', () => {
    expect(pageHasMore({ items: [], cursor: 'x', more: true })).toBe(true)
    expect(pageHasMore({ items: [], cursor: 'x', more: false })).toBe(false)
    expect(pageHasMore({ items: [], cursor: 'x' })).toBe(false)
    expect(pageHasMore({ more: 'yes' })).toBe(false)
    expect(pageHasMore(null)).toBe(false)
  })
  it('留下分过的新 id：信过了留存期从列表里滤掉，它那一份也跟着清', () => {
    const kept = item('a', '2026-10-02T00:00:00Z')
    expect(prunedCopies({ a: ['n1'], gone: ['n2'] }, [kept])).toEqual({ a: ['n1'] })
    expect(prunedCopies({}, [kept])).toEqual({})
  })
  it('规范键、能不能开、朋友名单、时间', () => {
    expect(itemKey({ symbol: 'btcusdt', market: 'binance/usd_m' })).toBe('binance/usd_m/BTCUSDT')
    expect(openableSymbol({ symbol: 'BTCUSDT', market: 'binance/usd_m' })).toBe('BTCUSDT')
    expect(openableSymbol({ symbol: 'coinbase/spot/BTC-USD', market: 'coinbase/spot' })).toBeNull()
    expect(withFriend(['zed', 'amy'], 'bob')).toEqual(['amy', 'bob', 'zed'])
    expect(withFriend(['amy'], 'amy')).toEqual(['amy'])
    expect(letterTime('nope')).toBe('')
    expect(letterTime('2026-10-03T06:05:00Z')).toMatch(/^10月3日 \d\d:05$/)
  })
})

describe('上新下架通知', () => {
  const n = (id: number, at: number): ListingNotice => ({ id, venue: 'binance', market: 'usd_m', symbol: 'ABCUSDT', event: 'listed', at, title: 't' + id, body: '' })
  it('第一次只出 1 小时内的；之后出游标以后 24 小时内的；最多 5 条，新的在前', () => {
    const list = [n(1, NOW - 2 * 3_600_000), n(2, NOW - 1000), n(3, NOW - 500)]
    expect(planNotices(list, null, NOW)).toEqual({ show: [list[2], list[1]], cursor: 3 })
    expect(planNotices(list, 2, NOW)).toEqual({ show: [list[2]], cursor: 3 })
    const many = Array.from({ length: 8 }, (_, i) => n(10 + i, NOW - 1000))
    const p = planNotices(many, 9, NOW)
    expect(p.show.map(x => x.id)).toEqual([17, 16, 15, 14, 13])
    expect(planNotices([], 7, NOW)).toEqual({ show: [], cursor: 7 })
    expect(planNotices([n(4, NOW - LN.windowMs - 1)], 1, NOW)).toEqual({ show: [], cursor: 4 })
  })
  it('读与键', () => {
    expect(readNotices({ notices: [{ id: 1, at: 2, title: 'x', venue: 'binance' }, { id: 'no' }] }).length).toBe(1)
    expect(readNotices(null)).toEqual([])
    expect(cursorKey('ABC')).toBe('listingNotices.cursor.abc')
    expect(noticeSymbol({ venue: 'binance', market: 'usd_m', symbol: 'abcusdt' })).toBe('ABCUSDT')
    expect(noticeSymbol({ venue: 'okx', market: 'swap', symbol: 'X' })).toBeNull()
  })
})

describe('恢复默认', () => {
  it('只动改过的设置字段，线路留着；撤销只还原那几项', () => {
    const p = defaultPrefs()
    p.skin = 'terra'; p.routePolicy = p.routePolicy === 'gateway' ? 'direct' : 'gateway'; p.subs = ['RSI']
    const route = p.routePolicy
    const { changed, before } = resetPrefs(p)
    expect(changed.sort()).toEqual(['skin', 'subs'])
    expect(p.skin).toBe(defaultPrefs().skin)
    expect(p.routePolicy).toBe(route)
    // 撤销窗口里别处改了别的字段：撤销不抹掉它
    p.theme = 'dark'
    expect(restorePrefs(p, changed, before).sort()).toEqual(['skin', 'subs'])
    expect(p.skin).toBe('terra')
    expect(p.subs).toEqual(['RSI'])
    expect(p.theme).toBe('dark')
    expect(resetPrefs(defaultPrefs()).changed).toEqual([])
  })
})
