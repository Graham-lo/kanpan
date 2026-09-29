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
