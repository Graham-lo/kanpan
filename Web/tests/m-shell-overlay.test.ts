/* 手机网页版收尾审查（同步与壳）：壳换页时把所有盖板收干净（m/app/shell go → closeOverlays） */
import { afterEach, describe, expect, it, vi } from 'vitest'
import searchSource from '../src/m/pages/search.ts?raw'
import shellSource from '../src/m/app/shell.ts?raw'

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

/** 没有 DOM：只给 go() 用得到的那几样（页根按 page-fixed 处理，不碰滚动） */
async function loadShell() {
  const mem = new Map<string, string>()
  vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
  const pageEl = { classList: { contains: () => true, toggle: () => {} }, scrollTop: 0 }
  vi.stubGlobal('document', { getElementById: () => pageEl, addEventListener: () => {}, removeEventListener: () => {} })
  const loc = { hash: '#chart' }
  vi.stubGlobal('location', loc)
  const replaceState = vi.fn((_s: unknown, _t: string, url: string) => { loc.hash = url })
  vi.stubGlobal('history', { replaceState })
  vi.resetModules()
  const shell = await import('../src/m/app/shell')
  const { st } = await import('../src/m/app/store')
  st.page = 'chart'
  return { shell, st, replaceState }
}

describe('壳换页统一收盖板（registerOverlay）', () => {
  it('复现：换页走 replaceState 不发 hashchange，盖板自己的 hashchange 监听收不到；登记过的盖板由 go() 关掉，且只关一次', async () => {
    const { shell, st, replaceState } = await loadShell()
    const close = vi.fn()
    const off = shell.registerOverlay(() => { close(); off() })
    shell.go('me', { fromTab: true })
    expect(st.page).toBe('me')
    expect(replaceState).toHaveBeenCalledWith(null, '', '#me')   // 这条路不会触发 hashchange
    expect(close).toHaveBeenCalledTimes(1)
    shell.go('favorites')
    expect(close).toHaveBeenCalledTimes(1)                       // 已经关了、注销了，不再被调
  })

  it('自己先关掉（注销）的盖板，换页时不会再被调；一个盖板抛错不挡别的', async () => {
    const { shell } = await loadShell()
    const a = vi.fn(), b = vi.fn()
    const offA = shell.registerOverlay(a)
    shell.registerOverlay(() => { throw new Error('boom') })
    shell.registerOverlay(b)
    offA()
    const err = vi.spyOn(console, 'error').mockImplementation(() => {})
    shell.go('sectors')
    expect(a).not.toHaveBeenCalled()
    expect(b).toHaveBeenCalledTimes(1)
    expect(err).toHaveBeenCalled()
    err.mockRestore()
  })

  it('停在同一页没换页（shown 已是这一页）：不动盖板', async () => {
    const { shell } = await loadShell()
    shell.registerPage('chart', { show: () => {}, hide: () => {} })
    const c = vi.fn()
    shell.registerOverlay(c)
    shell.go('chart')
    expect(c).not.toHaveBeenCalled()
    shell.go('me')
    expect(c).toHaveBeenCalledTimes(1)
  })

  it('搜索页开的时候登记、随生命周期注销（壳不硬引用搜索页）', () => {
    expect(searchSource).toMatch(/L\.add\(registerOverlay\(close\)\)/)
    expect(shellSource).not.toMatch(/pages\/search/)
  })
})
