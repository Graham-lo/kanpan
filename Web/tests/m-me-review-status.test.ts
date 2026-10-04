/* 手机网页「我的」复盘本那两行与角标：换账号时在途那一拉不能把新账号的那一拉挡掉 */
import { afterEach, describe, expect, it, vi } from 'vitest'

type Deferred<T> = { promise: Promise<T>; resolve: (v: T) => void }
function deferred<T>(): Deferred<T> { let resolve!: (v: T) => void; const promise = new Promise<T>(r => { resolve = r }); return { promise, resolve } }

const calls: { views: Deferred<unknown[]>; trades: Deferred<unknown[]> }[] = []
vi.mock('../src/review/api', () => ({
  reviewApi: {
    views: () => { const d = deferred<unknown[]>(); calls.push({ views: d, trades: deferred() }); return d.promise },
    trades: () => calls[calls.length - 1].trades.promise,
    statistics: () => new Promise(() => {}),
  },
  reviewBookApi: {},
  ReviewError: class extends Error {},
  errorText: (e: unknown) => String(e),
  uuid: () => 'u',
}))

function stubBrowser() {
  const mem = new Map<string, string>()
  vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
  vi.stubGlobal('window', { addEventListener() {}, removeEventListener() {}, setTimeout, clearTimeout, matchMedia: () => ({ matches: false, addEventListener() {} }) })
  vi.stubGlobal('navigator', { onLine: true })
  const el = (): unknown => ({ style: {}, classList: { add() {}, remove() {}, toggle() {}, contains: () => false }, dataset: {}, setAttribute() {}, appendChild() {}, append() {}, addEventListener() {}, querySelector: () => null, querySelectorAll: () => [] })
  vi.stubGlobal('document', { addEventListener() {}, removeEventListener() {}, createElement: el, body: el(), documentElement: el(), querySelector: () => null, getElementById: () => null, visibilityState: 'visible' })
}
const flush = () => new Promise(r => setTimeout(r, 0))
const user = (name: string) => ({ username: name, userId: name + '-id', sessionId: name + '-s', accessToken: 't' })

afterEach(() => { calls.length = 0; vi.unstubAllGlobals(); vi.resetModules() })

describe('refreshReviewStatus（m/pages/reviewBook）', () => {
  it('A 的那一拉还在路上时换成 B：B 那一拉照发，回来后两行字按 B 的记录算', async () => {
    stubBrowser()
    vi.resetModules()
    const S = await import('../src/account/session')
    const R = await import('../src/m/pages/reviewBook')
    S.setSession(user('alice'))
    R.onReviewStatus(() => {})
    R.refreshReviewStatus(true)
    expect(calls.length).toBe(1)
    S.setSession(user('bob'))
    expect(calls.length).toBe(2) // 换人那一下必须给 B 发一拉
    calls[0].views.resolve([]); calls[0].trades.resolve([])
    await flush()
    expect(R.reviewRootStatus().line1).toBe('') // A 的数丢掉，B 的还没回来
    calls[1].views.resolve([]); calls[1].trades.resolve([])
    await flush()
    expect(R.reviewRootStatus().line1).not.toBe('')
  })

  it('同一个人在途时又被强制重拉（刚改过记录）：回来后再拉一遍，不吞掉', async () => {
    stubBrowser()
    vi.resetModules()
    const S = await import('../src/account/session')
    const R = await import('../src/m/pages/reviewBook')
    S.setSession(user('carol'))
    R.refreshReviewStatus(true)
    R.refreshReviewStatus(true)
    R.refreshReviewStatus()
    expect(calls.length).toBe(1)
    calls[0].views.resolve([]); calls[0].trades.resolve([])
    await flush()
    expect(calls.length).toBe(2)
    calls[1].views.resolve([]); calls[1].trades.resolve([])
    await flush()
    expect(calls.length).toBe(2)
  })
})
