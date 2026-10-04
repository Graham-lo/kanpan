/* 手机网页版深度审查 E 线（壳）：
 *   C1 换号 / 退登 / 被顶下线后，来路与扫图名单还是上一个人的（iOS A-2：ChartTrail 跟着档案主人走）
 *   C7 已经站在行情页上从提醒「查看」/ 通知 / 复盘本换品种：go 不换页就不收盖板，开着的记一笔 / 分享还对着上一只 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import chartSource from '../src/m/pages/chart.ts?raw'

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

async function loadShell() {
  const mem = new Map<string, string>()
  vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
  const pageEl = { classList: { contains: () => true, toggle: () => {} }, scrollTop: 0 }
  vi.stubGlobal('document', { getElementById: () => pageEl, addEventListener: () => {}, removeEventListener: () => {} })
  const loc = { hash: '#favorites' }
  vi.stubGlobal('location', loc)
  vi.stubGlobal('history', { replaceState: (_s: unknown, _t: string, url: string) => { loc.hash = url } })
  vi.resetModules()
  const shell = await import('../src/m/app/shell')
  const { st } = await import('../src/m/app/store')
  const account = await import('../src/account/session')
  return { shell, st, account }
}

const user = (userId: string, sessionId: string) => ({ username: userId, userId, sessionId, accessToken: 't' })

describe('C1 来路与扫图名单跟着档案主人走', () => {
  it('复现：A 从自选打开图后换成 B 登录，扫图名单与返回来路一起作废', async () => {
    const { shell, st, account } = await loadShell()
    account.setSession(user('A', 's1'))
    st.page = 'favorites'
    shell.openSymbol('BTCUSDT', ['BTCUSDT', 'ETHUSDT', 'SOLUSDT'])
    expect(shell.nav.scan).toEqual(['BTCUSDT', 'ETHUSDT', 'SOLUSDT'])
    expect(shell.nav.origin).toBe('favorites')
    account.setSession(user('B', 's2'))
    expect(shell.nav.scan).toBeNull()
    expect(shell.nav.origin).toBeNull()
  })

  it('退登、被另一台顶下线同样作废', async () => {
    for (const why of [null, { replaced: 'phone' }] as const) {
      const { shell, st, account } = await loadShell()
      account.setSession(user('A', 's1'))
      st.page = 'favorites'
      shell.openSymbol('ETHUSDT', ['ETHUSDT', 'BTCUSDT'])
      account.endSession(why)
      expect(shell.nav.scan).toBeNull()
      expect(shell.nav.origin).toBeNull()
      vi.unstubAllGlobals()
    }
  })

  it('同一个人只是换了会话（令牌续期 / 重登）不动来路与名单；没登录时打开的图登录后作废', async () => {
    const { shell, st, account } = await loadShell()
    account.setSession(user('A', 's1'))
    st.page = 'favorites'
    shell.openSymbol('BTCUSDT', ['BTCUSDT', 'ETHUSDT'])
    account.setSession(user('A', 's9'))
    expect(shell.nav.scan).toEqual(['BTCUSDT', 'ETHUSDT'])
    expect(shell.nav.origin).toBe('favorites')
    account.endSession(null)
    st.page = 'sectors'
    shell.openSymbol('SOLUSDT', ['SOLUSDT', 'ADAUSDT'])
    account.setSession(user('A', 's10'))
    expect(shell.nav.scan).toBeNull()
  })
})

describe('C7 站在行情页上换品种', () => {
  it('复现：提醒「查看」在行情页上换品种——登记过的盖板被收掉（以前 go 同页早退、盖板还对着上一只）', async () => {
    const { shell, st } = await loadShell()
    st.page = 'chart'
    shell.registerPage('chart', { show: () => {}, hide: () => {} })
    const close = vi.fn()
    shell.registerOverlay(close)
    shell.openSymbol('ETHUSDT')
    expect(st.symbol).toBe('ETHUSDT')
    expect(close).toHaveBeenCalledTimes(1)
  })

  it('换品种先收回放（iOS A-6）：行情页的 onSymbol 第一件事是 endReplay', () => {
    const m = chartSource.match(/hooks\.onSymbol\.push\(s => \{([\s\S]*?)\n {2}\}\)/)
    expect(m).toBeTruthy()
    const body = m![1].replace(/^\s*\/\/.*$/gm, '').trim()
    expect(body.startsWith('if (replay) endReplay()')).toBe(true)
  })
})
