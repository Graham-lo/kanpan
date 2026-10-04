import { beforeEach, describe, expect, it, vi } from 'vitest'

const h = vi.hoisted(() => {
  const st = { notes: [] as any[] }
  const acct = { uid: null as string | null }
  const sent: { id: string; uid: string | null }[] = []
  let gate: (() => void) | null = null
  return { st, acct, sent, setGate: (g: (() => void) | null) => { gate = g }, gate: () => gate }
})

vi.mock('../src/app/store', () => ({ st: h.st, save: () => {} }))
vi.mock('../src/account/client', () => ({ readStored: () => (h.acct.uid ? { userId: h.acct.uid } : null) }))
vi.mock('../src/account/session', () => ({ session: { get userId() { return h.acct.uid } }, onSession: () => () => {} }))
vi.mock('../src/review/api', () => {
  class ReviewError extends Error { status: number; constructor(m: string, s: number) { super(m); this.status = s } }
  return {
    ReviewError,
    errorText: () => '',
    reviewToken: () => (h.acct.uid ? 'tok-' + h.acct.uid : null),
    reviewApi: {
      createRecord: async (d: { id: string }) => {
        h.sent.push({ id: d.id, uid: h.acct.uid })
        const g = h.gate(); if (g) { h.setGate(null); await new Promise<void>(r => { g(); r() }) }
      },
      putShot: async () => {},
    },
  }
})
vi.stubGlobal('localStorage', { getItem: () => null, setItem: () => {}, removeItem: () => {} })

import { flushNotes, noteState } from '../src/notes/sync'

const note = (id: string, owner?: string) => ({ id, symbol: 'BTCUSDT', iv: '1h', t: 0, p: 1, text: '', draft: { id }, sync: 'pending', shot: 'none', owner })

describe('记一笔的上传归属', () => {
  beforeEach(() => { h.st.notes = []; h.sent.length = 0; h.setGate(null) })

  it('A 记下的笔没传上，换 B 登录后不会传到 B 的账号', async () => {
    h.st.notes = [note('a1', 'A')]
    h.acct.uid = 'B'
    expect(await flushNotes()).toBe(0)
    expect(h.sent).toEqual([])
    expect(h.st.notes[0].sync).toBe('pending')
    expect(noteState(h.st.notes[0])?.text).toBe('原账号登录后上传')
    h.acct.uid = 'A'
    expect(await flushNotes()).toBe(1)
    expect(h.sent).toEqual([{ id: 'a1', uid: 'A' }])
  })

  it('没登录时记的笔由第一个登录的账号认领', async () => {
    h.st.notes = [note('n1')]
    h.acct.uid = 'A'
    await flushNotes()
    expect(h.st.notes[0].owner).toBe('A')
    expect(h.sent).toEqual([{ id: 'n1', uid: 'A' }])
  })

  it('传到一半换了账号：剩下 A 的不带 B 的令牌传，B 的那一趟接着跑', async () => {
    h.st.notes = [note('a1', 'A'), note('a2', 'A'), note('b1', 'B')]
    h.acct.uid = 'A'
    h.setGate(() => { h.acct.uid = 'B'; void flushNotes() })
    await flushNotes()
    expect(h.sent).toEqual([{ id: 'a1', uid: 'A' }, { id: 'b1', uid: 'B' }])
    expect(h.st.notes.map(n => n.sync)).toEqual(['synced', 'pending', 'synced'])
  })
})
