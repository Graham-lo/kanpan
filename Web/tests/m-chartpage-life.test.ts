/* 手机网页版 · 行情页宿主的生命周期（src/m/pages/chart/data.ts createPagePort）
 *
 * 审查发现：行情页 hide() 只撤了图表的 K 线 / 行情流，主力订单流的六条簿 / 成交 WS 与 500ms 评估
 * 在自选、板块、我的页上照跑。宿主现在 hide → suspend、show → resume；这里把 OrderFlowSource 换成
 * 记账的假件，核对藏起来期间不订、回来按最后想要的品种重订。
 */
import { beforeEach, describe, expect, it, vi } from 'vitest'

const log: string[] = []
vi.mock('../src/m/chart/orderflow.source', () => ({
  OrderFlowSource: class {
    current: string | null = null
    constructor(private readonly push: (s: unknown) => void) {}
    start(sym: string): void { this.current = sym.toUpperCase(); log.push(`start ${this.current}`) }
    stop(): void { if (!this.current) return; log.push(`stop ${this.current}`); this.current = null; this.push(null) }
    park(): void { this.stop() } // 停订但留着订单流在后台（换回来不从零连）；对宿主而言同样是停
    setRoute(): void {}
    setOverride(): void { log.push('override') }
    setVisible(from: number | null, to: number | null): void { log.push(`visible ${from}-${to}`) }
  },
}))

const { createPagePort } = await import('../src/m/pages/chart/data')
const series = { step: 60_000 } as never
const view = (from: number, to: number) => ({ from, to }) as never

describe('手机网页版 · 行情页订单流口：页面藏起来就停订', () => {
  beforeEach(() => { log.length = 0 })

  it('藏起来时停掉；回来按原品种重订并补上最后看到的范围', () => {
    const port = createPagePort(() => {}, () => null)
    port.setWanted(true, 'btcusdt', '1h' as never)
    port.noteView(view(1000, 2000), series)
    port.suspend()
    expect(log).toEqual(['start BTCUSDT', 'visible 1000-62000', 'stop BTCUSDT'])
    log.length = 0
    port.noteView(view(3000, 4000), series) // 藏着时视野变了：只记下，不订
    port.setOverride(null)
    expect(log).toEqual([])
    port.resume()
    expect(log).toEqual(['start BTCUSDT', 'visible 3000-64000'])
  })

  it('藏着时换了品种：只记下，回来订新品种，不带旧品种的视野', () => {
    const port = createPagePort(() => {}, () => null)
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    port.noteView(view(1000, 2000), series)
    port.suspend()
    log.length = 0
    port.setWanted(true, 'ETHUSDT', '1h' as never)
    expect(log).toEqual([])
    port.resume()
    expect(log).toEqual(['start ETHUSDT'])
  })

  it('一开张就藏着（落地在别的页）：图表 setWanted 不会先订一轮；关掉订单流后 resume 什么也不订', () => {
    const port = createPagePort(() => {}, () => null, true)
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    expect(log).toEqual([])
    port.setWanted(false, 'BTCUSDT', '1h' as never)
    port.resume()
    expect(log).toEqual([])
  })

  it('suspend / resume 重复调用是幂等的', () => {
    const port = createPagePort(() => {}, () => null)
    port.setWanted(true, 'BTCUSDT', '1h' as never)
    port.resume()
    port.suspend(); port.suspend()
    port.resume(); port.resume()
    expect(log).toEqual(['start BTCUSDT', 'stop BTCUSDT', 'start BTCUSDT'])
  })
})

// ───────────────────────────── 记一笔的补传

const calls: string[] = []
let gate: (() => void) | null = null
vi.mock('../src/review/api', () => ({
  reviewApi: {
    createRecord: async (d: { id: string }) => {
      calls.push(`record ${d.id}`)
      if (d.id === 'A') await new Promise<void>(r => { gate = r })
      return { record: {} }
    },
    putShot: async (id: string) => { calls.push(`shot ${id}`) },
  },
  reviewToken: () => 'token',
  ReviewError: class extends Error { status = 0 },
  errorText: () => '',
  uuid: () => 'x',
}))

describe('手机网页版 · 记一笔补传：这一轮还在传时新记下的也跟着传', () => {
  it('A 在传的时候记下 B：await 同一轮 flushNotes 之后 B 已经传上去、队列清空', async () => {
    const mem = new Map<string, string>()
    vi.stubGlobal('localStorage', { getItem: (k: string) => mem.get(k) ?? null, setItem: (k: string, v: string) => { mem.set(k, v) }, removeItem: (k: string) => { mem.delete(k) } })
    vi.stubGlobal('navigator', { onLine: true })
    const { flushNotes, pendingNotes, NOTES_KEY } = await import('../src/m/pages/chart/note')
    const put = (...ids: string[]) => mem.set(NOTES_KEY, JSON.stringify(ids.map(id => ({ draft: { id }, queued: 0 }))))
    put('A')
    const first = flushNotes()
    await vi.waitFor(() => expect(gate).not.toBeNull())
    put('A', 'B') // 记一笔页先入队，再 await flushNotes()——拿到的是正在跑的这一轮
    const second = flushNotes()
    expect(second).toBe(first)
    gate!()
    expect(await second).toBe(2)
    expect(calls).toEqual(['record A', 'record B'])
    expect(pendingNotes()).toEqual([])
    vi.unstubAllGlobals()
  })
})

describe('手机网页版 · 行情页横竖屏判定', async () => {
  const { isLandscape } = await import('../src/m/pages/chart/logic')
  it('视口扁且设备横着才算横屏；安卓竖屏弹键盘（视口扁、设备竖）不算', () => {
    expect(isLandscape(true, 'landscape-primary')).toBe(true)
    expect(isLandscape(true, 'landscape-secondary')).toBe(true)
    expect(isLandscape(true, 'portrait-primary')).toBe(false)
    expect(isLandscape(false, 'landscape-primary')).toBe(false)
    expect(isLandscape(true, undefined)).toBe(true) // 拿不到设备朝向（老浏览器）只看视口
  })
})

describe('手机网页版 · 行情页取不到行情时盖住旧图', async () => {
  const { showsOtherChart } = await import('../src/m/pages/chart/logic')
  const err = { loading: false, error: '行情暂时取不到' }
  it('换到下架 / 不认得的品种取数失败：图上还是上一只 → 盖住', () => {
    expect(showsOtherChart(err, { symbol: 'BTCUSDT', interval: '1h' }, 'FOOBARUSDT', '1h')).toBe(true)
    expect(showsOtherChart(err, { symbol: 'BTCUSDT', interval: '1h' }, 'BTCUSDT', '4h')).toBe(true) // 换周期失败
    expect(showsOtherChart(err, null, 'FOOBARUSDT', '1h')).toBe(true)
  })
  it('图上就是这只这一档（只是补最新失败）、还在取、取到了：不盖', () => {
    expect(showsOtherChart(err, { symbol: 'BTCUSDT', interval: '1h' }, 'btcusdt', '1h')).toBe(false)
    expect(showsOtherChart({ loading: true, error: null }, { symbol: 'BTCUSDT', interval: '1h' }, 'ETHUSDT', '1h')).toBe(false)
    expect(showsOtherChart({ loading: false, error: null }, { symbol: 'ETHUSDT', interval: '1h' }, 'ETHUSDT', '1h')).toBe(false)
  })
})

describe('手机网页版 · 行情页价格轴', async () => {
  const { priceModeFor } = await import('../src/m/pages/chart/logic')
  it('百分比原样交给图，学到的那档只替换线性 / 对数', () => {
    expect(priceModeFor('percent', false, undefined)).toBe('percent')
    expect(priceModeFor('percent', true, 'log')).toBe('percent')
    expect(priceModeFor('linear', true, 'log')).toBe('log')
    expect(priceModeFor('log', false, 'linear')).toBe('log')
    expect(priceModeFor('log', true, 'weird')).toBe('log')
  })
})

describe('手机网页版 · 画线列表左滑删除与样式页颜色', async () => {
  const { deleteDrawingById, safeHexColor } = await import('../src/m/pages/chart/logic')

  /** 记账的假控制器：只有 deleteSelected 这条路能删（真控制器里它进撤销栈、回调 onChanged(items)）。 */
  function fake(ids: string[], selected: string | null) {
    const calls: string[] = []
    let sel = selected
    let list = ids.map(id => ({ id }))
    return {
      calls,
      get drawings() { return list },
      get selected() { return sel },
      set selected(v: string | null) { sel = v; calls.push(`select ${v}`) },
      deleteSelected() { calls.push(`delete ${sel}`); list = list.filter(d => d.id !== sel); sel = null },
      setDrawings() { calls.push('setDrawings') },
    }
  }

  it('走控制器的 deleteSelected（保留撤销），不走整桶替换', () => {
    const c = fake(['a', 'b'], null)
    deleteDrawingById(c, 'a')
    expect(c.calls).toEqual(['select a', 'delete a'])
    expect(c.drawings.map(d => d.id)).toEqual(['b'])
    expect(c.selected).toBeNull()
  })

  it('删的不是选中那条时，原来的选中还给它；删的就是选中那条时不再选中', () => {
    const c = fake(['a', 'b'], 'b')
    deleteDrawingById(c, 'a')
    expect(c.selected).toBe('b')
    const d = fake(['a', 'b'], 'a')
    deleteDrawingById(d, 'a')
    expect(d.selected).toBeNull()
  })

  it('id 已经不在（同步刚删掉）时什么都不做', () => {
    const c = fake(['a'], 'a')
    deleteDrawingById(c, 'zz')
    expect(c.calls).toEqual([])
    expect(c.selected).toBe('a')
  })

  it('颜色只认 #RRGGBB / #RRGGBBAA，拼进 style / value 前把别的东西挡掉', () => {
    expect(safeHexColor('#abcdef', '#D6A64F')).toBe('#ABCDEF')
    expect(safeHexColor('#abcdef80', '#D6A64F')).toBe('#ABCDEF80')
    expect(safeHexColor('red;background:url(x)', '#D6A64F')).toBe('#D6A64F')
    expect(safeHexColor('#fff" onfocus="alert(1)', '#D6A64F')).toBe('#D6A64F')
    expect(safeHexColor(null, '#d6a64f')).toBe('#D6A64F')
    expect(safeHexColor(123, '#D6A64F')).toBe('#D6A64F')
  })
})
