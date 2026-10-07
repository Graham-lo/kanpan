// 网页版体感优化（2026-10-07）：K 线本机留底、换品种先淡旧图、骨架、左缘「加载更早…」、对比线小转圈、自选行先摆
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Bar } from '../src/chart/calc'
import { TVChart } from '../src/chart/chart'
import { CompareStore } from '../src/chart/compare'
import {
  DISK_BARS, DISK_KEYS_LS, FLUSH_MS, KLINE_LS_KEY, RecentBars, diskBars, flushBars, keepBars, klineDiskLoaded, klineDiskReady, lsBackend, packBars,
  resetKlineDiskForTest, unpackBars, type Backend, type DiskRow,
} from '../src/market/klineStore'

const H = 36e5
const bar = (i: number, p = 100 + i): Bar => ({ t: i * H, o: p, h: p + 1, l: p - 1, c: p + 0.5, v: 10 + i, tb: 5 + i, bv: 7 + i })
const run = (n: number, from = 0): Bar[] => Array.from({ length: n }, (_, k) => bar(from + k))

class MemStorage {
  m = new Map<string, string>()
  getItem(k: string) { return this.m.has(k) ? this.m.get(k)! : null }
  setItem(k: string, v: string) { this.m.set(k, String(v)) }
  removeItem(k: string) { this.m.delete(k) }
  clear() { this.m.clear() }
  key(i: number) { return [...this.m.keys()][i] ?? null }
  get length() { return this.m.size }
}

describe('K 线本机留底：压缩与读回', () => {
  it('只留最后 300 根，读回来字段一样；缺成交额的根读回来没有这个字段', () => {
    const src = run(DISK_BARS + 50)
    const back = unpackBars(packBars(src))
    expect(back).toHaveLength(DISK_BARS)
    expect(back[0]).toEqual(src[50])
    expect(back.at(-1)).toEqual(src.at(-1))
    const thin = unpackBars(packBars([{ t: 1, o: 2, h: 3, l: 1, c: 2, v: 4 }]))
    expect(thin[0]).toEqual({ t: 1, o: 2, h: 3, l: 1, c: 2, v: 4 })
  })
  it('写坏的一段（时间或收盘价不是数）整段不认', () => {
    const a = packBars(run(3)); a[8] = NaN
    expect(unpackBars(a)).toEqual([])
  })
})

describe('K 线本机留底：最近看过的表', () => {
  it('超出段数扔最久没看的；读一次就算看过', () => {
    const r = new RecentBars(3)
    r.put('A|1h', run(5), 1); r.put('B|1h', run(5), 2); r.put('C|1h', run(5), 3)
    expect(r.get('A|1h')).not.toBeNull()       // A 挪到最新
    expect(r.put('D|1h', run(5), 4)).toEqual(['B|1h'])
    expect(r.rows().map(x => x.k)).toEqual(['D|1h', 'A|1h', 'C|1h'])
  })
  it('盘上读回来的按时间排在前面，本会话已经写过的键不让旧的盖掉', () => {
    const r = new RecentBars(3)
    r.put('A|1h', run(2, 100), 50)
    const rows: DiskRow[] = [
      { k: 'A|1h', at: 1, d: Array.from(packBars(run(2))) },
      { k: 'B|1h', at: 3, d: Array.from(packBars(run(2))) },
      { k: 'C|1h', at: 2, d: Array.from(packBars(run(2))) },
      { k: 'D|1h', at: 0, d: Array.from(packBars(run(2))) },
    ]
    expect(r.load(rows)).toEqual(['D|1h'])
    expect(r.get('A|1h')![0].t).toBe(100 * H)
    expect(r.rows().map(x => x.k)).toEqual(['A|1h', 'B|1h', 'C|1h'])
  })
})

describe('K 线本机留底：落盘', () => {
  beforeEach(() => { vi.useFakeTimers() })
  afterEach(() => { resetKlineDiskForTest(null); vi.useRealTimers(); vi.unstubAllGlobals() })

  it('记下之后攒一下再写（同一拍几格只写一次），只写变了的键', async () => {
    const writes: string[][] = []
    const be: Backend = { load: async () => [], write: async (_m, keys) => { writes.push(keys) } }
    resetKlineDiskForTest(be)
    keepBars('BTCUSDT', '1h', run(400))
    keepBars('ETHUSDT', '1h', run(10))
    expect(writes).toHaveLength(0)
    await vi.advanceTimersByTimeAsync(FLUSH_MS + 1)
    expect(writes).toEqual([['BTCUSDT|1h', 'ETHUSDT|1h']])
    expect(diskBars('BTCUSDT', '1h')).toHaveLength(DISK_BARS)
    await flushBars()
    expect(writes).toHaveLength(1)                // 没变就不写
  })
  it('关页时立刻落盘，不等攒的那一下', async () => {
    const writes: string[][] = []
    resetKlineDiskForTest({ load: async () => [], write: async (_m, keys) => { writes.push(keys) } })
    keepBars('SOLUSDT', '15m', run(20))
    await flushBars()
    expect(writes).toEqual([['SOLUSDT|15m']])
  })
  it('没有 IndexedDB 时退到 localStorage：只留最近 8 段，刷新后读得回来', async () => {
    const ls = new MemStorage()
    vi.stubGlobal('localStorage', ls)
    vi.stubGlobal('indexedDB', undefined)
    resetKlineDiskForTest(null)
    await klineDiskReady()
    for (let i = 0; i < DISK_KEYS_LS + 3; i++) keepBars(`S${i}USDT`, '1h', run(30), 1000 + i)
    await flushBars()
    const saved = JSON.parse(ls.getItem(KLINE_LS_KEY)!) as { rows: { k: string }[] }
    expect(saved.rows).toHaveLength(DISK_KEYS_LS)
    expect(saved.rows[0].k).toBe(`S${DISK_KEYS_LS + 2}USDT|1h`)
    // 「刷新」：内存清掉，从盘上读回
    resetKlineDiskForTest(null)
    await klineDiskReady()
    expect(diskBars(`S${DISK_KEYS_LS + 2}USDT`, '1h')).toHaveLength(30)
    expect(diskBars('S0USDT', '1h')).toBeNull()
  })
  it('localStorage 写满了不抛', async () => {
    const ls = new MemStorage(); ls.setItem = () => { throw new Error('QuotaExceeded') }
    await expect(lsBackend(ls as unknown as Storage).write(new RecentBars(), [], [])).resolves.toBeUndefined()
  })
  it('盘慢：最多等 150 毫秒就先开图（不等它），盘读完之前的开图走网络', async () => {
    vi.stubGlobal('indexedDB', { open: () => ({}) })     // 打开了永远不回
    resetKlineDiskForTest(null)
    let done = false
    void klineDiskReady(150).then(() => { done = true })
    await vi.advanceTimersByTimeAsync(149)
    expect(done).toBe(false)
    await vi.advanceTimersByTimeAsync(2)
    expect(done).toBe(true)
    expect(klineDiskLoaded()).toBe(false)
    expect(diskBars('BTCUSDT', '1h')).toBeNull()
  })
})

// ------------------------------------------------------------ 图表：等新数据时的样子
type Fake = TVChart & { host: { classList: { set: Set<string>; toggle(c: string, on?: boolean): void; remove(c: string): void; contains(c: string): boolean }; appendChild(e: unknown): void }; legendEl: { innerHTML: string; style: Record<string, string> } }
function fakeChart(): Fake {
  const set = new Set<string>()
  const me = Object.create(TVChart.prototype) as Fake
  Object.assign(me, {
    host: {
      classList: { set, toggle: (c: string, on?: boolean) => { if (on ?? !set.has(c)) set.add(c); else set.delete(c) }, remove: (c: string) => set.delete(c), contains: (c: string) => set.has(c) },
      children: [] as unknown[], appendChild(e: unknown) { (this as { children: unknown[] }).children.push(e) },
    },
    legendEl: { innerHTML: '', style: {} },
    meta: { symbol: 'BTCUSDT', title: 'BTCUSDT', sub: ' · 1小时', badge: '', dec: 1 },
    bars: [] as Bar[], deg: { compact: false }, cross: null, extCross: null, replay: null,
    selected: null, measure: null, drag: null, draft: null, readOnly: false, pendingMeta: null, dirty: false,
    _loadingMore: false, moreEl: null,
    dropGesture() {}, renderPaneLegends() {}, legendTools: () => '', compareOn: () => false,
  })
  return me
}

describe('换品种：旧图淡下去，图例先换成新品种加「载入中」', () => {
  it('手里有旧图：挂 pending（淡下去、不能点），图例是新品种标题，没有旧图的开高低收', () => {
    const c = fakeChart()
    c.bars = run(50)
    c.setPending({ symbol: 'ETHUSDT', title: 'ETHUSDT', sub: ' · 1小时' } as never)
    expect(c.host.classList.contains('pending')).toBe(true)
    expect(c.legendEl.innerHTML).toContain('ETHUSDT')
    expect(c.legendEl.innerHTML).toContain('载入中')
    expect(c.legendEl.innerHTML).not.toContain('开')
    expect(c.legendEl.innerHTML).not.toContain('BTCUSDT')
    expect(c.editable()).toBe(false)          // 这时画的线会记到新品种上，先不让画
  })
  it('冷启动还没有图：不挂淡出（没什么可淡），图例照样先出标题', () => {
    const c = fakeChart()
    c.setPending({ symbol: 'BTCUSDT', title: 'BTCUSDT', sub: ' · 1小时' } as never)
    expect(c.host.classList.contains('pending')).toBe(false)
    expect(c.legendEl.innerHTML).toContain('载入中')
  })
  it('品种表晚到：等待中的标题跟着补，换了别的品种的不混进来', () => {
    const c = fakeChart()
    c.bars = run(5)
    c.setPending({ symbol: 'ETHUSDT', title: 'ETHUSDT', sub: ' · 1小时' } as never)
    c.setMeta({ symbol: 'ETHUSDT', dec: 2, sub: ' · 1小时 · 币安永续' })
    expect(c.pendingMeta!.dec).toBe(2)
    expect(c.meta.dec).toBe(1)               // 手上的旧图（BTC）不动
    c.setMeta({ symbol: 'SOLUSDT', dec: 4 })
    expect(c.pendingMeta!.dec).toBe(2)
  })
  it('撤掉等待（取失败了）：淡出收起、又能点', () => {
    const c = fakeChart()
    c.bars = run(5)
    c.setPending({ symbol: 'ETHUSDT', title: 'ETHUSDT', sub: '' } as never)
    c.renderLegend = () => {}                 // 收起后图例回到旧图的完整一行，这里不看
    c.setPending(null)
    expect(c.host.classList.contains('pending')).toBe(false)
    expect(c.editable()).toBe(true)
  })
  it('只读的图本来就不能点', () => {
    const c = fakeChart(); (c as unknown as { readOnly: boolean }).readOnly = true
    expect(c.editable()).toBe(false)
  })
})

describe('没有 K 线时画骨架，不留白板', () => {
  it('画网格、两条轴和轴上的占位短条', () => {
    const c = fakeChart()
    const calls: string[] = []
    const ctx = new Proxy({} as Record<string, unknown>, {
      get: (t, p) => (p in t ? t[p as string] : (...a: unknown[]) => { calls.push(String(p)); void a }),
      set: (t, p, v) => { t[p as string] = v; return true },
    })
    Object.assign(c, { ctx, colors: { bg: '#fff', grid: '#eee', scaleLine: '#ccc' }, w: 800, h: 400, axisW: () => 60, plotW: () => 740, aw: 60 })
    c.render()
    expect(calls.filter(x => x === 'lineTo').length).toBeGreaterThan(8)
    expect(calls.filter(x => x === 'fill').length).toBeGreaterThan(8)
  })
})

describe('往前翻历史：左缘「加载更早…」', () => {
  afterEach(() => vi.unstubAllGlobals())
  it('取的时候挂上，取完收起；同一块元素复用', () => {
    const els: { className: string; innerHTML: string; hidden: boolean }[] = []
    vi.stubGlobal('document', { createElement: () => { const e = { className: '', innerHTML: '', hidden: false }; els.push(e); return e } })
    const c = fakeChart()
    c.loadingMore = true
    expect(els).toHaveLength(1)
    expect(els[0].className).toBe('chart-more')
    expect(els[0].innerHTML).toContain('加载更早…')
    expect(els[0].hidden).toBe(false)
    c.loadingMore = false
    expect(els[0].hidden).toBe(true)
    c.loadingMore = true
    expect(els).toHaveLength(1)
    expect(els[0].hidden).toBe(false)
  })
})

describe('对比线：第一次取时挂小转圈，取到就收', () => {
  it('取的时候 loading，取到之后再通知一次、loading 已经是 false', async () => {
    let resolve!: (b: Bar[]) => void
    const seen: boolean[] = []
    const store: CompareStore = new CompareStore(
      () => new Promise(r => { resolve = r }),
      (s, iv) => seen.push(store.get(s, iv)!.loading),
      () => H,
      { set: () => 0, clear: () => {} },
    )
    store.want(0, [{ symbol: 'ETHUSDT', iv: '1h', from: 0 }])
    expect(store.get('ETHUSDT', '1h')!.loading).toBe(true)
    resolve(run(10))
    for (let k = 0; k < 6; k++) await Promise.resolve()
    expect(store.get('ETHUSDT', '1h')!.loading).toBe(false)
    expect(seen.at(-1)).toBe(false)           // 最后一次通知时转圈已收，图例会重画成百分比
  })
})
