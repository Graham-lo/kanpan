/* PC「我的」登录入口（G 线走查）：
 * - 没登录时点头像 / 「去登录」落在账号那一栏（以前落在默认的外观栏，看不到登录框）
 * - 被另一台顶掉后「我的」停在账号那一栏
 * - 登录 / 注册 / 改密码先在本地按 account/rules 查，不合规的不发请求（和手机网页同一份规则） */
import { describe, it, expect, vi } from 'vitest'

const h = vi.hoisted(() => {
  const els = new Map<string, Record<string, unknown>>()
  return {
    els,
    $: (sel: string) => { let e = els.get(sel); if (!e) { e = { innerHTML: '', className: '', dataset: {}, addEventListener: () => {}, classList: { toggle: () => {} } }; els.set(sel, e) } return e },
    st: { page: 'chart', meSection: 'look', skin: 'sage', theme: 'light', updown: 'green-up', route: 'direct' } as Record<string, unknown>,
    login: vi.fn(), changePassword: vi.fn(),
  }
})
vi.mock('../src/app/store', () => ({ st: h.st, save: vi.fn() }))
vi.mock('../src/ui/dom', () => ({ $: h.$, $$: () => [], I: () => '', esc: (s: string) => s, tgt: (e: Event) => e.target }))
vi.mock('../src/ui/overlay', () => ({ toast: vi.fn(), hideTip: vi.fn() }))
vi.mock('../src/market', () => ({ setRoute: vi.fn() }))
vi.mock('../src/account/client', () => ({
  login: h.login, logout: vi.fn(), kick: vi.fn(), changePassword: h.changePassword, deleteAccount: vi.fn(), errorText: () => 'err',
  devices: () => new Promise(() => {}),
}))
vi.mock('./../src/pages/chart', () => ({ openShortcuts: vi.fn(), renderPanel: vi.fn(), refreshStreams: vi.fn() }))
vi.mock('../src/watch/importPanel', () => ({ tvImportHTML: () => '', tvImportClick: () => false, tvImportChange: vi.fn(), onTvImported: vi.fn() }))
vi.mock('../src/review/api', () => ({ reviewApi: { trades: () => new Promise(() => {}) }, errorText: () => 'err' }))
vi.mock('../src/trades/panel', () => ({ NO_KEY_TEXT: 'nokey', venueRows: () => [] }))

describe('PC「我的」登录入口与本地校验', async () => {
  const S = await import('../src/account/session')
  const shell = await import('../src/app/shell')
  const me = await import('../src/pages/me')
  const { PASSWORD_RULE, USERNAME_RULE } = await import('../src/account/rules')
  ;(globalThis as Record<string, unknown>).history = { replaceState: () => {} }
  ;(globalThis as Record<string, unknown>).location = { hash: '#chart' }
  ;(globalThis as Record<string, unknown>).addEventListener ??= () => {}

  it('没登录时点头像：落在账号那一栏；登录了点头像不改用户选的栏', () => {
    shell.installShell()
    const av = h.$('#hdrAvatar') as { onclick: () => void }
    h.st.meSection = 'look'
    av.onclick()
    expect(h.st.page).toBe('me')
    expect(h.st.meSection).toBe('account')
    S.setSession({ username: 'u1', userId: 'u1', sessionId: 's1', accessToken: 't' } as Parameters<typeof S.setSession>[0])
    h.st.meSection = 'look'; h.st.page = 'chart'
    av.onclick()
    expect(h.st.meSection).toBe('look')
  })

  it('被另一台顶掉：「我的」停在账号那一栏', () => {
    me.initMe()
    h.st.page = 'chart'; h.st.meSection = 'look'
    S.endSession({ replaced: 'desktop' } as Parameters<typeof S.endSession>[0])
    expect(h.st.meSection).toBe('account')
  })

  it('登录 / 注册 / 改密码的本地校验', () => {
    expect(me.authProblem('login', '', 'x')).toBe('用户名和密码都要填')
    expect(me.authProblem('login', 'a-b', 'whatever')).toBe(USERNAME_RULE)
    expect(me.authProblem('login', 'ab', 'whatever')).toBe(USERNAME_RULE)
    expect(me.authProblem('login', 'Good_Name', 'x')).toBeNull() // 登录不查密码形状
    expect(me.authProblem('register', 'good_name', 'short1')).toBe(PASSWORD_RULE)
    expect(me.authProblem('register', 'good_name', 'longenough')).toBe(PASSWORD_RULE)
    expect(me.authProblem('register', 'good_name', 'longenough1')).toBeNull()
    expect(me.passwordProblem('old', '')).toBe('两个都要填')
    expect(me.passwordProblem('same1234a', 'same1234a')).toBe('新密码和当前密码一样')
    expect(me.passwordProblem('old', '12345678')).toBe(PASSWORD_RULE)
    expect(me.passwordProblem('old', 'abcd1234')).toBeNull()
  })
})
