/* 手机网页版 · 朋友页删朋友（审查 D 线）：删不掉时错抛给朋友页自己说，
 * 不写进收件箱那行「· 重试」（那颗按钮是重拉收件箱，不是再删一次），朋友还在 */
import { beforeEach, describe, expect, it, vi } from 'vitest'

const net = vi.hoisted(() => {
  class ApiError extends Error {
    status: number; code: string
    constructor(status: number, code: string) { super(code); this.status = status; this.code = code }
  }
  return { ApiError, authed: vi.fn() }
})
vi.mock('../src/account/client', () => ({ ApiError: net.ApiError, authed: net.authed, fresh: vi.fn() }))
vi.mock('../src/account/session', () => ({ session: { userId: 'qa_me' }, onSession: () => () => {} }))
vi.mock('../src/m/app/shell', () => ({ hooks: { onForeground: [] } }))
vi.mock('../src/m/app/sync', () => ({ onSyncStatus: () => () => {}, syncStatus: () => ({}) }))
vi.mock('../src/m/app/drawings', () => ({ drawingBook: {} }))
vi.mock('../src/m/pages/chart/share', () => ({ shareErrorText: () => '暂时连不上' }))
vi.mock('../src/m/chart/draw/drawing', () => ({ newDrawingID: () => 'd', tryDecodeDrawing: () => null }))

import { inboxBusy, inboxFriends, inboxNotice, pullInbox, removeFriend } from '../src/m/pages/inboxStore'

describe('删朋友', () => {
  beforeEach(async () => {
    net.authed.mockReset()
    net.authed.mockImplementation(async (method: string, path: string) => {
      if (path.startsWith('/v1/shares/inbox')) return { items: [], cursor: 'c', more: false }
      if (path === '/v1/friends') return [{ username: 'qa_a' }, { username: 'qa_b' }]
      throw new Error('unexpected ' + method + ' ' + path)
    })
    pullInbox()
    await vi.waitFor(() => expect(inboxBusy()).toBe(false))
    expect(inboxFriends()).toEqual(['qa_a', 'qa_b'])
  })

  it('删不掉：抛给朋友页，收件箱那行不出「· 重试」，朋友还在', async () => {
    net.authed.mockImplementation(async () => { throw new net.ApiError(503, 'down') })
    await expect(removeFriend('qa_a')).rejects.toBeInstanceOf(net.ApiError)
    expect(inboxNotice()).toBeNull()
    expect(inboxFriends()).toEqual(['qa_a', 'qa_b'])
  })

  it('删掉了：名单里少这一位', async () => {
    net.authed.mockImplementation(async () => ({ ok: true }))
    await removeFriend('qa_a')
    expect(net.authed).toHaveBeenLastCalledWith('DELETE', '/v1/friends/qa_a')
    expect(inboxFriends()).toEqual(['qa_b'])
  })
})
