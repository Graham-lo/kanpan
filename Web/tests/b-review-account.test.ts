import { describe, it, expect, vi, beforeEach } from 'vitest'
import { createLoadGate } from '../src/review/loadGate'
import { session, setSession, endSession } from '../src/account/session'
import { reviewApi, rememberSearch, storedSearches, searchKey } from '../src/review/api'
import { installTradesPanel, renderTradesPanel } from '../src/trades/panel'
import type { TradeRecord } from '../src/review/types'

vi.mock('../src/notes/sync', () => ({ canUpload: () => true }))

function memoryStorage(): Storage {
  const m = new Map<string, string>()
  return { get length() { return m.size }, clear: () => m.clear(), getItem: k => m.get(k) ?? null, key: i => [...m.keys()][i] ?? null, removeItem: k => { m.delete(k) }, setItem: (k, v) => { m.set(k, String(v)) } }
}
const login = (id: string): void => setSession({ username: id, userId: id, sessionId: 's-' + id, accessToken: 't-' + id } as Parameters<typeof setSession>[0])

describe('复盘页整页取数闸（B13）', () => {
  it('取的途中又被要求重取：这一份回来后再取一次，不吞掉', () => {
    const g = createLoadGate()
    const ep = g.begin()!
    expect(g.begin()).toBeNull()
    expect(g.end(ep)).toBe('again')
    const ep2 = g.begin()!
    expect(g.end(ep2)).toBe('ok')
  })
  it('换账号后上个账号在途的那份作废，不往页面里写', () => {
    const g = createLoadGate()
    const ep = g.begin()!
    g.reset()
    expect(g.live(ep)).toBe(false)
    expect(g.end(ep)).toBe('stale')
    expect(g.busy).toBe(false)
    expect(g.begin()).not.toBeNull()
  })
})

describe('找过的相似按账号分开记（B13）', () => {
  beforeEach(() => { vi.stubGlobal('localStorage', memoryStorage()); endSession(null as never) })
  it('A 记的搜索换 B 登录后看不到，换回 A 还在', () => {
    login('A')
    rememberSearch({ id: 'sa', symbol: 'BTCUSDT', iv: '1h', bars: 60, label: 'x', created: 1 })
    expect(storedSearches().map(x => x.id)).toEqual(['sa'])
    login('B')
    expect(storedSearches()).toEqual([])
    login('A')
    expect(storedSearches().map(x => x.id)).toEqual(['sa'])
  })
  it('老版本不分账号记的那份由第一个登录上来的账号认领', () => {
    localStorage.setItem('hkline-review-searches', JSON.stringify([{ id: 'old', symbol: 'ETHUSDT', iv: '4h', bars: 30, label: 'y', created: 1 }]))
    login('A')
    expect(storedSearches().map(x => x.id)).toEqual(['old'])
    expect(localStorage.getItem('hkline-review-searches')).toBeNull()
    expect(searchKey()).toBe('hkline-review-searches:A')
    login('B')
    expect(storedSearches()).toEqual([])
  })
})

describe('侧栏成交：换账号时上个账号在途的请求作废（B13）', () => {
  it('A 的请求在 B 登录后才回来，不把「有回合」带给 B', async () => {
    vi.stubGlobal('localStorage', memoryStorage())
    login('A')
    const pend: ((v: TradeRecord[]) => void)[] = []
    const first = vi.spyOn(reviewApi, 'tradesFirstPage').mockImplementation(() => new Promise(r => pend.push(r as (v: TradeRecord[]) => void)) as never)
    vi.spyOn(reviewApi, 'tradesOf').mockImplementation(() => new Promise(r => pend.push(r as (v: TradeRecord[]) => void)) as never)
    installTradesPanel(() => {})
    const el = { innerHTML: '', querySelector: () => null } as unknown as HTMLElement
    renderTradesPanel(el, 'BTCUSDT')
    expect(first).toHaveBeenCalledTimes(1)
    login('B')
    renderTradesPanel(el, 'BTCUSDT')
    // 请求顺序：A 的 tradesOf、firstPage，B 的 tradesOf、firstPage。
    // B 的先回来：B 一条成交都没有 → 应该说「没绑密钥」
    pend[2]([]); pend[3]([])
    await new Promise(r => setTimeout(r, 0))
    // A 的后回来：A 有回合，不能把 B 的说法改成「这只还没有成交」
    pend[0]([]); pend[1]([{ id: 'x' } as TradeRecord])
    await new Promise(r => setTimeout(r, 0))
    renderTradesPanel(el, 'BTCUSDT')
    expect(el.innerHTML).toContain('data-tr-empty="nokey"')
    expect(session.userId).toBe('B')
  })
})
