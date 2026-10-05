// 深度审查 Web F 线 F10：手机网页版本机存储满了（/web/ 与 /web/m/ 共用约 5M）时，
// 主状态 hkline-m-v1 与画线本 hkline-m-drawings-v1 以前直接 setItem、写不进去只在控制台留一句——
// 人改的自选、皮肤、画线关页面就全没了也不知道。现在与 PC 同一套：先清掉能让位的缓存再写，还不行就通知（弹「本机存储已满」）。
// 现场复现：scripts/f-perf.mjs storage m（把存储塞到只剩不到 1 KB，再连换 50 只品种）。
import { afterEach, describe, expect, it, vi } from 'vitest'
import { SECTOR_HISTORY_KEY } from '../src/util/storage'

function fakeStorage(limit: number): Storage {
  const m = new Map<string, string>()
  const used = (): number => [...m].reduce((n, [k, v]) => n + k.length + v.length, 0)
  return {
    get length() { return m.size },
    key: i => [...m.keys()][i] ?? null,
    getItem: k => m.get(k) ?? null,
    removeItem: k => { m.delete(k) },
    clear: () => m.clear(),
    setItem: (k, v) => {
      const before = m.get(k)
      m.set(k, v)
      if (used() > limit) { if (before == null) m.delete(k); else m.set(k, before); throw new DOMException('quota', 'QuotaExceededError') }
    },
  }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules(); vi.restoreAllMocks() })

async function load(store: Storage) {
  vi.stubGlobal('localStorage', store)
  vi.resetModules()
  const { tabGuard } = await import('../src/m/app/tabGuard')
  tabGuard.reset()
  return tabGuard
}

describe('手机网页版：本机存储满了', () => {
  it('板块 5 日缓存让位，主状态照样写进去，不打扰人', async () => {
    const s = fakeStorage(2000)
    s.setItem(SECTOR_HISTORY_KEY, 'h'.repeat(1200))
    s.setItem('filler', 'f'.repeat(600))
    const g = await load(s)
    const full = vi.fn()
    g.onFull(full)
    g.register('hkline-m-v1', () => JSON.stringify({ skin: 'terra', pad: 'x'.repeat(500) }))
    expect(g.write('hkline-m-v1')).toBe(true)
    expect(s.getItem(SECTOR_HISTORY_KEY)).toBeNull()
    expect(JSON.parse(s.getItem('hkline-m-v1')!).skin).toBe('terra')
    expect(full).not.toHaveBeenCalled()
  })

  it('清完还写不下：通知 onFull（弹提示），不再只是控制台一句', async () => {
    const s = fakeStorage(1000)
    s.setItem('filler', 'f'.repeat(900))
    const g = await load(s)
    const full = vi.fn()
    g.onFull(full)
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    g.register('hkline-m-drawings-v1', () => 'd'.repeat(500))
    expect(g.write('hkline-m-drawings-v1')).toBe(false)
    expect(full).toHaveBeenCalledTimes(1)
  })
})
