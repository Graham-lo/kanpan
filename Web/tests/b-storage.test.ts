import { describe, expect, it, vi } from 'vitest'
import { NOTE_SHOTS_KEY, SECTOR_HISTORY_KEY, setItemMakingRoom } from '../src/util/storage'

/** 按字符数算配额的假 localStorage（Chrome 的上限也是按字符算） */
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
      if (used() > limit) {
        if (before == null) m.delete(k); else m.set(k, before)
        throw new DOMException('quota', 'QuotaExceededError')
      }
    },
  }
}

describe('主存档写不下时让位', () => {
  it('先清板块 5 日缓存，够了就不动截图', () => {
    const s = fakeStorage(1000)
    s.setItem(SECTOR_HISTORY_KEY, 'h'.repeat(400))
    s.setItem(NOTE_SHOTS_KEY, 's'.repeat(400))
    expect(setItemMakingRoom('hkline-web-v1', 'x'.repeat(300), s)).toBe(true)
    expect(s.getItem(SECTOR_HISTORY_KEY)).toBeNull()
    expect(s.getItem(NOTE_SHOTS_KEY)).not.toBeNull()
    expect(s.getItem('hkline-web-v1')).toHaveLength(300)
  })
  it('缓存清完还不够：截图也让出来', () => {
    const s = fakeStorage(1000)
    s.setItem(SECTOR_HISTORY_KEY, 'h'.repeat(300))
    s.setItem(NOTE_SHOTS_KEY, 's'.repeat(500))
    expect(setItemMakingRoom('hkline-web-v1', 'x'.repeat(600), s)).toBe(true)
    expect(s.getItem(NOTE_SHOTS_KEY)).toBeNull()
  })
  it('全让完还写不下返回 false，旧存档原样留着', () => {
    const s = fakeStorage(500)
    s.setItem('hkline-web-v1', 'old')
    expect(setItemMakingRoom('hkline-web-v1', 'x'.repeat(600), s)).toBe(false)
    expect(s.getItem('hkline-web-v1')).toBe('old')
  })
})

describe('store.save 在存储满时', () => {
  it('清掉缓存把主存档写进去；连缓存都没得清时叫 onStorageFull', async () => {
    vi.resetModules()
    const s = fakeStorage(4000)
    vi.stubGlobal('localStorage', s)
    const { st, save, onStorageFull, KEY } = await import('../src/app/store')
    let full = 0
    onStorageFull(() => { full++ })
    save()
    const size = (s.getItem(KEY) ?? '').length
    expect(size).toBeGreaterThan(0)
    // 缓存把剩下的空间占满：修前这一下 setItem 抛错被吞，主存档还是旧的，也没有任何提示
    let used = 0
    for (let i = 0; i < s.length; i++) { const k = s.key(i)!; used += k.length + s.getItem(k)!.length }
    s.setItem(SECTOR_HISTORY_KEY, 'h'.repeat(4000 - used - SECTOR_HISTORY_KEY.length - 2))
    st.customIvs = ['45m']
    save()
    expect(JSON.parse(s.getItem(KEY)!).customIvs).toEqual(['45m'])
    expect(s.getItem(SECTOR_HISTORY_KEY)).toBeNull()
    expect(full).toBe(0)
    st.customIvs = Array.from({ length: 2000 }, (_, i) => i + 'm')
    save()
    expect(full).toBe(1)
    vi.unstubAllGlobals()
  })
})
