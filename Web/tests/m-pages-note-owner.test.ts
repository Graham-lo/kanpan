// 手机网页版 · 记一笔的上传归属：A 账号没传上的那一笔，换 B 登录后不能传进 B 的复盘、也不能列在 B 的复盘本里
import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => {
  const acct = { uid: null as string | null }
  const sent: { id: string; uid: string | null }[] = []
  let gate: (() => void) | null = null
  return { acct, sent, setGate: (g: (() => void) | null) => { gate = g }, gate: () => gate }
})

vi.mock('../src/account/client', () => ({ readStored: () => (h.acct.uid ? { userId: h.acct.uid } : null) }))
vi.mock('../src/account/session', () => ({ session: { get userId() { return h.acct.uid } }, onSession: () => () => {} }))
vi.mock('../src/review/api', () => ({
  ReviewError: class extends Error { status = 0 },
  errorText: () => '',
  uuid: () => 'x',
  reviewToken: () => (h.acct.uid ? 'tok-' + h.acct.uid : null),
  reviewApi: {
    createRecord: async (d: { id: string }) => {
      h.sent.push({ id: d.id, uid: h.acct.uid })
      const g = h.gate(); if (g) { h.setGate(null); g() }
      return { record: {} }
    },
    putShot: async () => {},
  },
}))

const mem = new Map<string, string>()
vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
vi.stubGlobal('navigator', { onLine: true })

const { flushNotes, pendingNotes, NOTES_KEY } = await import('../src/m/pages/chart/note')
const put = (...qs: { id: string; owner?: string }[]) =>
  mem.set(NOTES_KEY, JSON.stringify(qs.map(q => ({ draft: { id: q.id }, queued: 0, owner: q.owner }))))
const left = (): string[] => (JSON.parse(mem.get(NOTES_KEY) ?? '[]') as { draft: { id: string } }[]).map(q => q.draft.id)

describe('手机网页版 · 记一笔的上传归属', () => {
  beforeEach(() => { mem.clear(); h.sent.length = 0; h.setGate(null); h.acct.uid = null })

  it('A 记下的没传上，换 B 登录：不传进 B、不列在 B 的复盘本；A 回来再传给 A', async () => {
    put({ id: 'a1', owner: 'A' })
    h.acct.uid = 'B'
    expect(await flushNotes()).toBe(0)
    expect(h.sent).toEqual([])
    expect(pendingNotes()).toEqual([])
    expect(left()).toEqual(['a1'])
    h.acct.uid = 'A'
    expect(pendingNotes().map(q => q.draft.id)).toEqual(['a1'])
    expect(await flushNotes()).toBe(1)
    expect(h.sent).toEqual([{ id: 'a1', uid: 'A' }])
  })

  it('没登录时记的由第一个登录上的账号认领', async () => {
    put({ id: 'g1' })
    h.acct.uid = 'B'
    expect(await flushNotes()).toBe(1)
    expect(h.sent).toEqual([{ id: 'g1', uid: 'B' }])
  })

  it('传到一半换账号：剩下 A 的不用 B 的令牌传；换上来的 B 那一趟不被吞掉', async () => {
    put({ id: 'a1', owner: 'A' }, { id: 'a2', owner: 'A' }, { id: 'b1', owner: 'B' })
    h.acct.uid = 'A'
    h.setGate(() => { h.acct.uid = 'B'; void flushNotes() })
    await flushNotes()
    expect(h.sent).toEqual([{ id: 'a1', uid: 'A' }, { id: 'b1', uid: 'B' }])
    expect(left()).toEqual(['a2'])
  })
})
