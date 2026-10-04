import { describe, it, expect, vi } from 'vitest'

const h = vi.hoisted(() => {
  const els = new Map<string, { innerHTML: string; addEventListener: () => void }>()
  return {
    els, devCalls: [] as ((v: unknown) => void)[], venCalls: [] as ((v: unknown) => void)[],
    $: (sel: string) => { let e = els.get(sel); if (!e) { e = { innerHTML: '', addEventListener: () => {} }; els.set(sel, e) } return e },
    st: { page: 'me', meSection: 'devices', skin: 'sage', theme: 'light', updown: 'green-up', route: 'direct' },
  }
})
vi.mock('../src/app/store', () => ({ st: h.st, save: vi.fn() }))
vi.mock('../src/app/shell', () => ({ hooks: { pageShown: {}, onTheme: [] }, applyTheme: vi.fn(), renderHeader: vi.fn() }))
vi.mock('../src/ui/dom', () => ({ $: h.$, I: () => '', esc: (s: string) => s, tgt: (e: Event) => e.target }))
vi.mock('../src/ui/overlay', () => ({ toast: vi.fn() }))
vi.mock('../src/market', () => ({ setRoute: vi.fn() }))
vi.mock('../src/account/client', () => ({
  login: vi.fn(), logout: vi.fn(), kick: vi.fn(), changePassword: vi.fn(), deleteAccount: vi.fn(), errorText: () => 'err',
  devices: () => new Promise(r => h.devCalls.push(r)),
}))
vi.mock('./../src/pages/chart', () => ({ openShortcuts: vi.fn(), renderPanel: vi.fn(), refreshStreams: vi.fn() }))
vi.mock('../src/watch/importPanel', () => ({ tvImportHTML: () => '', tvImportClick: () => false, tvImportChange: vi.fn(), onTvImported: vi.fn() }))
vi.mock('../src/review/api', () => ({ reviewApi: { trades: () => new Promise(r => h.venCalls.push(r)) }, errorText: () => 'err' }))
vi.mock('../src/trades/panel', () => ({ NO_KEY_TEXT: 'nokey', venueRows: (rows: { id: string }[]) => rows.map(r => ({ title: r.id, accountTag: '', rounds: 1, lastUpload: 0, lastFill: 0 })) }))

const tick = (): Promise<void> => new Promise(r => setTimeout(r, 0))

describe('「我的」设备 / 交易所：在途请求不重发、换账号作废（B11）', async () => {
  const { session, setSession } = await import('../src/account/session')
  const { initMe } = await import('../src/pages/me')
  const login = (id: string): void => setSession({ username: id, userId: id, sessionId: 's' + id, accessToken: 't' } as Parameters<typeof setSession>[0])
  initMe()

  it('A 的设备列表在 B 登录后才回来：不写到 B 的页面上，也不挡住 B 自己的那次', async () => {
    login('A')
    expect(h.devCalls.length).toBe(1)
    login('B')
    expect(h.devCalls.length).toBe(2)
    h.devCalls[1]([{ id: 'b1', name: 'B 的电脑', kind: 'desktop', current: true, lastSeen: 0 }])
    await tick()
    h.devCalls[0]([{ id: 'a1', name: 'A 的手机', kind: 'phone', current: false, lastSeen: 0 }])
    await tick()
    const body = h.$('#meBody').innerHTML
    expect(body).toContain('B 的电脑')
    expect(body).not.toContain('A 的手机')
    expect(session.user).toBe('B')
  })

  it('取的途中页面重画不再多发请求', async () => {
    h.devCalls.length = 0
    login('C')
    const n = h.devCalls.length
    // 主题切换等引起的重画：页面还在「正在读取…」
    for (const fn of (await import('../src/app/shell')).hooks.onTheme as (() => void)[]) fn()
    for (const fn of (await import('../src/app/shell')).hooks.onTheme as (() => void)[]) fn()
    expect(h.devCalls.length).toBe(n)
    h.devCalls[n - 1]([])
    await tick()
  })

  it('交易所：A 的回合在 B 登录后才回来，不写到 B 的页面上', async () => {
    h.st.meSection = 'exchange'
    login('A2')
    expect(h.venCalls.length).toBe(1)
    login('B2')
    expect(h.venCalls.length).toBe(2)
    h.venCalls[1]([{ id: 'B2 的币安' }])
    await tick()
    h.venCalls[0]([{ id: 'A2 的币安' }])
    await tick()
    const body = h.$('#meBody').innerHTML
    expect(body).toContain('B2 的币安')
    expect(body).not.toContain('A2 的币安')
  })
})
