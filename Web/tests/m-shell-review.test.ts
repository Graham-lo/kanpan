/* 手机网页版收尾审查（同步与壳）：两个标签页、本机存储相关的回归用例 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { makeDrawing } from '../src/m/chart/draw/drawing'

function memStorage(seed: Record<string, string> = {}) {
  const mem = new Map(Object.entries(seed))
  return { mem, api: { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } } }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('两个标签页共用 hkline-m-v1 / hkline-m-drawings-v1（m/app/tabGuard）', () => {
  it('另一页比我更近被人动过：我变旧，之后 save() 与画线落盘都不再写（不把它刚改的整份盖回去）', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const { drawingBook, DRAWINGS_KEY } = await import('../src/m/app/drawings')
    tabGuard.touch(1000)
    store.st.skin = 'terra'; store.save()
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('terra')
    expect(drawingBook.add([makeDrawing('trend', { t: 1_700_000_000_000, p: 100 }, { t: 1_700_000_060_000, p: 110 }, null, 'dA')], 'BTCUSDT')).toBe(true)
    expect(mem.get(DRAWINGS_KEY)).toContain('dA')
    // 另一页（2000 时被人动过）写了皮肤 classic
    mem.set(store.KEY, JSON.stringify({ ...JSON.parse(mem.get(store.KEY)!), skin: 'classic' }))
    mem.set('hkline-m-v1-writer', JSON.stringify({ at: 2000 }))
    expect(tabGuard.onForeignWrite(2000)).toBe('stale')
    // 本页后台自动存一次（同步拉到东西、滚动位置……）：不写
    store.st.scroll = { chart: 10 }; store.save(); store.persistQuiet()
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('classic')
    const before = mem.get(DRAWINGS_KEY)
    expect(drawingBook.add([makeDrawing('trend', { t: 1_700_000_100_000, p: 100 }, { t: 1_700_000_160_000, p: 110 }, null, 'dX')], 'BTCUSDT')).toBe(true)
    expect(mem.get(DRAWINGS_KEY)).toBe(before)
  })

  it('另一页是后台拿旧内存自动存的（它被人动得比我早）：我立刻把两份都写回去', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const { DRAWINGS_KEY } = await import('../src/m/app/drawings')
    tabGuard.touch(5000)
    store.st.skin = 'terra'; store.save()
    mem.set(store.KEY, JSON.stringify({ skin: 'classic' }))
    mem.delete(DRAWINGS_KEY)
    expect(tabGuard.onForeignWrite(1000)).toBe('repair')
    expect(JSON.parse(mem.get(store.KEY)!).skin).toBe('terra')
    expect(mem.has(DRAWINGS_KEY)).toBe(true)
    expect(tabGuard.stale).toBe(false)
  })

  it('旧了之后把别的页写的那份收进内存并照常通知（领头页据此把非领头页的改动推上云端），但仍不写盘；解不开的不收', async () => {
    const { mem, api } = memStorage()
    vi.stubGlobal('localStorage', api)
    vi.resetModules()
    const { tabGuard } = await import('../src/m/app/tabGuard')
    const store = await import('../src/m/app/store')
    const D = await import('../src/m/app/drawings')
    const { DrawArchive, encodeArchive } = await import('../src/m/chart/draw/archive')
    tabGuard.touch(1000)
    store.st.skin = 'terra'; store.st.page = 'me'; store.save()
    const seen: string[] = []
    store.subscribe(s => seen.push(s.skin))
    const kinds: string[] = []
    D.onDrawingsChanged(c => kinds.push(c.kind))
    // 另一页（更近被人动过）改了皮肤、换了页、画了一条线
    mem.set(store.KEY, JSON.stringify({ ...JSON.parse(mem.get(store.KEY)!), skin: 'classic', page: 'chart' }))
    const a = new DrawArchive(); a.set('binance/usd_m/BTCUSDT', [makeDrawing('trend', { t: 1_700_000_000_000, p: 100 }, { t: 1_700_000_060_000, p: 110 }, null, 'dB')])
    mem.set(D.DRAWINGS_KEY, JSON.stringify(encodeArchive(a)))
    const written = { st: mem.get(store.KEY), dr: mem.get(D.DRAWINGS_KEY) }
    tabGuard.onForeignWrite(2000, store.KEY)
    tabGuard.onForeignWrite(2000, D.DRAWINGS_KEY)
    tabGuard.flush()
    expect(store.st.skin).toBe('classic')
    expect(store.st.page).toBe('me') // 现场留本页的
    expect(seen).toContain('classic')
    expect(D.drawingBook.items('BTCUSDT').map(d => d.id)).toEqual(['dB'])
    expect(kinds).toContain('replaced')
    expect(mem.get(store.KEY)).toBe(written.st)
    expect(mem.get(D.DRAWINGS_KEY)).toBe(written.dr)
    // 读坏的画线存档：不收（不然同步会把空的当成本机删光了）
    mem.set(D.DRAWINGS_KEY, '{broken')
    tabGuard.onForeignWrite(3000, D.DRAWINGS_KEY); tabGuard.flush()
    expect(D.drawingBook.items('BTCUSDT').map(d => d.id)).toEqual(['dB'])
  })
})
