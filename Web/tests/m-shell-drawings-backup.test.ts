/* 手机网页画线本（m/app/drawings）：本机存档读不全时原文另存，第一次落盘不把没登录的人仅有的那份线盖掉 */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { makeDrawing } from '../src/m/chart/draw/drawing'
import { encodeArchive, DrawArchive } from '../src/m/chart/draw/archive'

function memStorage(seed: Record<string, string> = {}) {
  const mem = new Map(Object.entries(seed))
  const api = {
    getItem: (k: string) => mem.get(k) ?? null,
    setItem: (k: string, v: string) => { mem.set(k, v) },
    removeItem: (k: string) => { mem.delete(k) },
    key: (i: number) => [...mem.keys()][i] ?? null,
    get length() { return mem.size },
  }
  return { mem, api }
}
const KEY = 'hkline-m-drawings-v1'
const backups = (mem: Map<string, string>) => [...mem.keys()].filter(k => k.startsWith(KEY + '.unreadable-'))
const line = (id: string, t = 1_700_000_000_000) => makeDrawing('trend', { t, p: 100 }, { t: t + 60_000, p: 110 }, null, id)
async function boot(seed: Record<string, string>) {
  const s = memStorage(seed)
  vi.stubGlobal('localStorage', s.api)
  vi.resetModules()
  const D = await import('../src/m/app/drawings')
  return { ...s, D }
}

afterEach(() => { vi.unstubAllGlobals(); vi.resetModules() })

describe('画线存档读不全（m/app/drawings load）', () => {
  it('整份解不开：原文另存，之后画一条把主键盖掉，原文还在旁边', async () => {
    const bad = '{"v":3,"d":{"BTCUSDT":[{"id":"a1"'
    const { mem, D } = await boot({ [KEY]: bad })
    expect(D.drawingsSuspect()).toBe(true)
    expect(backups(mem).map(k => mem.get(k))).toEqual([bad])
    D.drawingBook.add([line('n1')], 'BTCUSDT')
    expect(mem.get(KEY)).toContain('n1')
    expect(backups(mem).map(k => mem.get(k))).toEqual([bad])
  })

  it('有线解不开（会被这一版丢掉）：解得开的照用，原文另存，按可疑处理', async () => {
    const good = encodeArchive(new DrawArchive(3, { BTCUSDT: [line('ok1')] })) as { d: Record<string, unknown[]> }
    Object.values(good.d)[0].push({ id: 'future1', kind: 'someNewTool', points: [] })
    const raw = JSON.stringify(good)
    const { mem, D } = await boot({ [KEY]: raw })
    expect(Object.values(D.drawingBook.archive.bySymbol).flat().map(d => d.id)).toEqual(['ok1'])
    expect(D.drawingsSuspect()).toBe(true)
    expect(backups(mem).map(k => mem.get(k))).toEqual([raw])
  })

  it('新版本写的存档：照读，原文另存', async () => {
    const raw = JSON.stringify({ ...encodeArchive(new DrawArchive(3, { BTCUSDT: [line('ok1')] })) as object, v: 99 })
    const { mem, D } = await boot({ [KEY]: raw })
    expect(D.drawingsSuspect()).toBe(true)
    expect(backups(mem)).toHaveLength(1)
  })

  it('完好的存档（含同一条线在别名桶里的旧数据）：不另存、不可疑', async () => {
    const raw = JSON.stringify(encodeArchive(new DrawArchive(3, { BTCUSDT: [line('ok1')], ETHUSDT: [line('ok2')] })))
    const { mem, D } = await boot({ [KEY]: raw })
    expect(D.drawingsSuspect()).toBe(false)
    expect(backups(mem)).toHaveLength(0)
  })

  it('同一份坏原文反复打开只存一份；不同的坏原文最多留 3 份最新的', async () => {
    const seed: Record<string, string> = {}
    for (let i = 0; i < 3; i++) seed[`${KEY}.unreadable-${1000 + i}`] = 'old' + i
    let { mem } = await boot({ ...seed, [KEY]: 'bad-new' })
    expect(backups(mem).map(k => mem.get(k)).sort()).toEqual(['bad-new', 'old1', 'old2'])
    const again = Object.fromEntries(mem)
    ;({ mem } = await boot(again))
    expect(backups(mem)).toHaveLength(3)
  })
})

describe('本机状态存档读不出（m/app/store load）', () => {
  for (const [name, bad] of [['JSON 坏了', '{"symbols":{"favorites":["BTCUSDT"'], ['被写成 null', 'null'], ['被写成数组', '["BTCUSDT"]']] as const) {
    it(`${name}：当空档用，原文另存，第一次 save 盖掉主键后原文还在`, async () => {
      const s = memStorage({ 'hkline-m-v1': bad })
      vi.stubGlobal('localStorage', s.api)
      vi.resetModules()
      const store = await import('../src/m/app/store')
      expect(store.st.symbols.favorites).toEqual([])
      store.st.skin = 'terra'; store.save()
      expect(JSON.parse(s.mem.get('hkline-m-v1')!).skin).toBe('terra')
      expect([...s.mem.keys()].filter(k => k.startsWith('hkline-m-v1.unreadable-')).map(k => s.mem.get(k))).toEqual([bad])
    })
  }
  it('完好的存档、没有存档：不另存', async () => {
    for (const seed of [{ 'hkline-m-v1': JSON.stringify({ skin: 'classic' }) }, {}] as Record<string, string>[]) {
      const s = memStorage(seed)
      vi.stubGlobal('localStorage', s.api)
      vi.resetModules()
      await import('../src/m/app/store')
      expect([...s.mem.keys()].some(k => k.includes('.unreadable-'))).toBe(false)
    }
  })
})
