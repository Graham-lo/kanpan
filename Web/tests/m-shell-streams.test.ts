/* 手机网页版收尾审查（同步与壳）：离开行情页后 K 线流真的撤掉、连接没人要就关（m/pages/_streams → market/stream） */
import { afterEach, describe, expect, it, vi } from 'vitest'
import { LINGER_MS } from '../src/market/stream'

class FakeWS {
  static OPEN = 1; static CONNECTING = 0; static CLOSED = 3
  static all: FakeWS[] = []
  readyState = 0
  sent: any[] = []
  onopen: (() => void) | null = null
  onmessage: ((e: { data: string }) => void) | null = null
  onclose: (() => void) | null = null
  onerror: (() => void) | null = null
  constructor(public url: string) { FakeWS.all.push(this) }
  send(s: string) { this.sent.push(JSON.parse(s)) }
  close() { this.readyState = 3 }
  open() { this.readyState = 1; this.onopen?.() }
}

afterEach(() => { vi.useRealTimers(); vi.unstubAllGlobals(); vi.resetModules(); FakeWS.all = [] })

async function load() {
  vi.useFakeTimers()
  vi.stubGlobal('WebSocket', FakeWS)
  vi.resetModules()
  const streams = await import('../src/m/pages/_streams')
  const market = await import('../src/market')
  return { ...streams, ...market }
}

const K = 'btcusdt@kline_15m', T = 'btcusdt@ticker'
const frames = (w: FakeWS) => w.sent.map(x => `${x.method} ${x.params.join(',')}`)

/* 审查员看到离开行情页后还有一条 URL 里带 @kline 的连接开着，以为 K 线流没断。实测（Playwright 看帧）：
 * 连接池一条连接上可以挂多页的流，URL 里的 ?streams= 只是开连接那一刻的名单；离开后发的是 UNSUBSCRIBE、
 * 之后一帧 K 线都不再收；没人要任何流时连接直接关。这里把这几条钉住 */
describe('离开行情页后 K 线流（_streams.wantStreams → market/stream 连接池）', () => {
  it('只有行情页在订：离开后 K 线立刻退订、连接空着留 LINGER_MS 再关', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    FakeWS.all[0].open()
    expect(m.streamDebug().subscribed).toEqual([K, T])
    m.wantStreams('chart', [])
    vi.advanceTimersByTime(200)
    expect(frames(FakeWS.all[0])).toEqual([`UNSUBSCRIBE ${K},${T}`])
    expect(m.streamDebug().subscribed).toEqual([])
    expect(m.streamDebug().state).toBe('idle')
    vi.advanceTimersByTime(LINGER_MS)
    expect(m.streamDebug().conns).toEqual([])
    expect(FakeWS.all[0].readyState).toBe(3)
  })

  it('F6：我的 ↔ 行情来回点（LINGER_MS 内回来）：同一条连接上补订，不再握手', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    const ws = FakeWS.all[0]
    ws.open()
    for (let i = 0; i < 50; i++) {
      m.wantStreams('chart', []); vi.advanceTimersByTime(1000)
      m.wantStreams('chart', [K, T]); vi.advanceTimersByTime(1000)
      ws.onmessage?.({ data: JSON.stringify({ stream: K, data: { e: 'kline', s: 'BTCUSDT', k: { t: 0, o: '1', h: '1', l: '1', c: '1', q: '1', Q: '1', v: '1', i: '15m' } } }) })
    }
    expect(FakeWS.all).toHaveLength(1)
    expect(ws.readyState).toBe(1)
    expect(m.streamDebug().subscribed.sort()).toEqual([K, T].sort())
  })

  it('F6：没人要流时切后台，空连接立刻收掉，不在后台留', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    FakeWS.all[0].open()
    m.wantStreams('chart', [])
    vi.advanceTimersByTime(200)
    expect(FakeWS.all[0].readyState).toBe(1)
    vi.stubGlobal('document', { visibilityState: 'hidden' })
    m.wantStreams('chart', [])
    vi.advanceTimersByTime(200)
    expect(FakeWS.all[0].readyState).toBe(3)
    expect(m.streamDebug().conns).toEqual([])
  })

  it('自选页还订着行情：连接留着给它用，但 K 线退订；回来在同一条连接上补订，不新开', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    const ws = FakeWS.all[0]
    ws.open()
    m.wantStreams('chart', [])
    m.wantStreams('favorites', ['ethusdt@ticker'])
    vi.advanceTimersByTime(200)
    expect(m.streamDebug().subscribed).toEqual(['ethusdt@ticker'])
    expect(frames(ws)).toEqual([`UNSUBSCRIBE ${K},${T}`, 'SUBSCRIBE ethusdt@ticker'])
    expect(ws.url).toContain(K)                       // URL 还是开连接时那份名单——这就是被误读的那条
    m.wantStreams('favorites', [])
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    expect(FakeWS.all).toHaveLength(1)
    expect(m.streamDebug().subscribed.sort()).toEqual([K, T].sort())
  })

  it('还没连上就离开：连接直接收掉，不会连上以后再把 K 线订回来', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    m.wantStreams('chart', [])
    vi.advanceTimersByTime(200)
    expect(FakeWS.all[0].readyState).toBe(3)
    expect(m.streamDebug().conns).toEqual([])
  })

  it('150ms 防抖里先撤后订（换页时 hide 与 show 同一拍）：只按最后的名单对账一次', async () => {
    const m = await load()
    m.wantStreams('chart', [K, T])
    vi.advanceTimersByTime(200)
    const ws = FakeWS.all[0]
    ws.open()
    m.wantStreams('chart', [])
    m.wantStreams('sectors', ['ethusdt@ticker'])
    m.wantStreams('sectors', [])
    vi.advanceTimersByTime(200)
    expect(frames(ws)).toEqual([`UNSUBSCRIBE ${K},${T}`])
    vi.advanceTimersByTime(LINGER_MS)
    expect(ws.readyState).toBe(3)
  })
})

// 构建：_streams.ts 是各页共用的模块，不是页。main.ts 的页面 glob 把它扫进去当懒加载，
// 而各页又静态引它，rolldown 报 INEFFECTIVE_DYNAMIC_IMPORT、分包不生效。
describe('页面 glob 不扫下划线开头的共用模块', () => {
  it('main.ts 排除 ./pages/_*.ts', async () => {
    const src = (await import('../src/m/main.ts?raw')).default
    const m = src.match(/import\.meta\.glob<PageModule>\((\[[^\]]*\])\)/)
    expect(m, '页面 glob 应是带排除项的数组').not.toBeNull()
    expect(m![1]).toContain("'./pages/*.ts'")
    expect(m![1]).toContain("'!./pages/_*.ts'")
  })
})
